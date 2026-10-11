param([switch]$SmokeTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Windows.Forms.DataVisualization
trap {($_|Out-String)|Set-Content (Join-Path $PSScriptRoot 'map-error.log');[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Storage Map');exit 1}
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='C Drive Cleaner - Storage Map';$form.Size=New-Object Drawing.Size(1180,820);$form.MinimumSize=New-Object Drawing.Size(1000,740);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(245,247,251)
$header=New-Object Windows.Forms.Label;$header.SetBounds(22,16,1100,38);$header.Font=New-Object Drawing.Font('Segoe UI',22,[Drawing.FontStyle]::Bold);$header.Text='Where your space goes';$form.Controls.Add($header)
$disk=New-Object Windows.Forms.Label;$disk.SetBounds(24,60,1100,26);$form.Controls.Add($disk)
$meter=New-Object Windows.Forms.ProgressBar;$meter.SetBounds(24,90,1110,14);$meter.Anchor='Top,Left,Right';$form.Controls.Add($meter)
function Update-Disk {$drive=New-Object IO.DriveInfo('C');$disk.Text=('{0:N1} GB used     {1:N1} GB free     {2:N1} GB total' -f (($drive.TotalSize-$drive.AvailableFreeSpace)/1GB),($drive.AvailableFreeSpace/1GB),($drive.TotalSize/1GB));$meter.Value=[int](100*(1-$drive.AvailableFreeSpace/$drive.TotalSize))}
$location=New-Object Windows.Forms.ComboBox;$location.SetBounds(24,122,430,30);$location.Anchor='Top,Left';[void]$location.Items.Add('C:\');[void]$location.Items.Add((Join-Path $env:USERPROFILE 'AppData'));[void]$location.Items.Add($env:LOCALAPPDATA);[void]$location.Items.Add($env:APPDATA);[void]$location.Items.Add($env:USERPROFILE);$location.SelectedIndex=1;$form.Controls.Add($location)
function New-Button($text,$x,$width){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.SetBounds($x,120,$width,34);$form.Controls.Add($b);return $b}
$scan=New-Button 'Analyze' 466 100;$up=New-Button 'Up' 574 60;$cancel=New-Button 'Stop' 642 70;$cleanup=New-Button 'Safe cleanup' 720 145;$admin=New-Button 'Administrator' 873 145;$cancel.Enabled=$false
$chart=New-Object Windows.Forms.DataVisualization.Charting.Chart;$chart.SetBounds(24,170,375,340);$chart.BackColor=[Drawing.Color]::White
[void]$chart.ChartAreas.Add('Area');[void]$chart.Series.Add('Space');$chart.Series[0].ChartType='Doughnut';$chart.Series[0]['DoughnutRadius']='55';$chart.Series[0].IsValueShownAsLabel=$false;[void]$chart.Titles.Add('Share of scanned folder sizes');$form.Controls.Add($chart)
function New-List($x,$y,$w,$h,$columns){$view=New-Object Windows.Forms.ListView;$view.SetBounds($x,$y,$w,$h);$view.View='Details';$view.FullRowSelect=$true;$view.GridLines=$false;foreach($col in $columns){[void]$view.Columns.Add($col[0],[int]$col[1])};$form.Controls.Add($view);return $view}
$folders=New-List 413 170 721 340 @(@('Folder / file',220),@('Size',100),@('Share',75),@('Handling',150),@('Skipped',75));$folders.Anchor='Top,Left,Right'
$subtitle=New-Object Windows.Forms.Label;$subtitle.SetBounds(24,520,1100,25);$subtitle.Text='Largest files in this scan - double-click to reveal in Explorer';$form.Controls.Add($subtitle)
$files=New-List 24 550 1110 135 @(@('Size',110),@('File path',970));$files.Anchor='Top,Bottom,Left,Right'
$status=New-Object Windows.Forms.Label;$status.SetBounds(24,698,1110,52);$status.Anchor='Bottom,Left,Right';$form.Controls.Add($status)
$note=New-Object Windows.Forms.Label;$note.SetBounds(24,752,1110,25);$note.Anchor='Bottom,Left,Right';$note.Text='Double-click folders to explore. Sizes include hidden files; links are skipped. Hard links may count twice; protected storage may be unreadable.';$note.Font=New-Object Drawing.Font('Segoe UI',9);$form.Controls.Add($note)
$script:rows=@();$script:job=$null;$script:root='';$script:scanErrors=@();$script:cache=@{}
$script:cacheFile=Join-Path $PSScriptRoot 'storage-cache.xml'
try{if(Test-Path -LiteralPath $script:cacheFile){$script:cache=Import-Clixml -LiteralPath $script:cacheFile}}catch{$script:cache=@{}}
$script:maxTickGap=0;$script:lastTick=0;$script:clock=[Diagnostics.Stopwatch]::StartNew()
$heartbeat=New-Object Windows.Forms.Timer;$heartbeat.Interval=50
$heartbeat.Add_Tick({$now=$script:clock.ElapsedMilliseconds;if($script:lastTick){$script:maxTickGap=[math]::Max($script:maxTickGap,$now-$script:lastTick)};$script:lastTick=$now});$heartbeat.Start()
function Format-Size($bytes){if($bytes -ge 1GB){return ('{0:N2} GB' -f ($bytes/1GB))};return ('{0:N1} MB' -f ($bytes/1MB))}
function Get-Handling($row){
 if($row.Path -match '^C:\\Windows|^C:\\Program Files|hiberfil\.sys|pagefile\.sys|swapfile\.sys|System Volume Information|\\Recovery$'){return 'System / keep'}
 if($row.Path -match '\\(Temp|Cache|Code Cache|GPUCache|CrashDumps)$'){return 'Review in cleanup'}
 if($row.Path -match 'DriveFS|Dropbox|Google Drive'){return 'Sync data / review'}
 return 'App or personal data'
}
function Render-Rows {
 $sorted=@($script:rows|Sort-Object Bytes -Descending);$total=($sorted|Measure-Object Bytes -Sum).Sum
 $folders.BeginUpdate();$files.BeginUpdate();$chart.Series[0].Points.SuspendUpdates()
 try {
 $folders.Items.Clear();$chart.Series[0].Points.Clear();$files.Items.Clear()
 $colors=@('RoyalBlue','MediumSeaGreen','DarkOrange','MediumPurple','DeepPink','Teal','Goldenrod','SlateBlue','IndianRed','SteelBlue')
 $index=0;$other=0L
 foreach($row in $sorted){
  $item=New-Object Windows.Forms.ListViewItem($row.Name);$item.Tag=$row
  [void]$item.SubItems.Add((Format-Size $row.Bytes));$share=0;if($total -gt 0){$share=100*$row.Bytes/$total}
  [void]$item.SubItems.Add(('{0:N1}%' -f $share));[void]$item.SubItems.Add((Get-Handling $row));[void]$item.SubItems.Add([string]$row.Skipped)
  if($index -lt 10 -and $row.Bytes -gt 0){$color=[Drawing.Color]::FromName($colors[$index]);$item.ForeColor=$color;$point=$chart.Series[0].Points.AddY([double]$row.Bytes);$chart.Series[0].Points[$point].Color=$color;$chart.Series[0].Points[$point].ToolTip=$row.Name+': '+(Format-Size $row.Bytes)}else{$other+=$row.Bytes}
  if($index -lt 500){[void]$folders.Items.Add($item)};$index++
 }
 if($other -gt 0){$p=$chart.Series[0].Points.AddY([double]$other);$chart.Series[0].Points[$p].Color=[Drawing.Color]::LightGray;$chart.Series[0].Points[$p].ToolTip='Other: '+(Format-Size $other)}
 foreach($file in @($sorted|ForEach-Object {$_.Largest}|Where-Object {$_.Path}|Sort-Object Bytes -Descending|Select-Object -First 50)){
  $item=New-Object Windows.Forms.ListViewItem((Format-Size $file.Bytes));[void]$item.SubItems.Add($file.Path);$item.Tag=$file.Path;[void]$files.Items.Add($item)
 }
 } finally {$folders.EndUpdate();$files.EndUpdate();$chart.Series[0].Points.ResumeUpdates()}
}
function Start-Scan([string]$root,[bool]$refresh=$false){
 if($script:job){return}
 try{$full=[IO.Path]::GetFullPath($root);if(-not $full.StartsWith('C:\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Container)){throw 'Choose an existing folder on C:.'}}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message);return}
 $script:root=$full;$location.Text=$full
 if(-not $refresh -and $script:cache.ContainsKey($full)){
  $snapshot=$script:cache[$full];$script:rows=@($snapshot.Rows);Render-Rows
  $status.Text='Saved scan from '+$snapshot.Time+'. Click Analyze to refresh. '+$full;return
 }
 $script:rows=@();$script:scanErrors=@();Render-Rows
 $scan.Enabled=$false;$up.Enabled=$false;$cancel.Enabled=$true;$status.Text='Analyzing '+$full+' ... You can move the window or stop the scan.'
 if('StorageScan' -as [type]){[StorageScan]::Cancelled=$false;[StorageScan]::FilesSeen=0}
 $engine=[powershell]::Create()
 [void]$engine.AddCommand((Join-Path $PSScriptRoot 'StorageScan.ps1')).AddParameter('Root',$full)
 $script:job=@{Engine=$engine;Handle=$engine.BeginInvoke();Started=[Diagnostics.Stopwatch]::StartNew();Cancelled=$false}
 $timer.Start()
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=500
$timer.Add_Tick({
 try {
 if('StorageScan' -as [type]){$status.Text=('Scanning {0:N0} files - {1}' -f [StorageScan]::FilesSeen,[StorageScan]::CurrentPath)}
 if($script:job.Handle.IsCompleted){
  $timer.Stop();$state='Completed';if($script:job.Cancelled){$state='Stopped (partial results)'}
  $script:rows=@($script:job.Engine.EndInvoke($script:job.Handle));$script:scanErrors=@($script:job.Engine.Streams.Error)
  $elapsed=$script:job.Started.Elapsed.TotalSeconds
  $script:job.Engine.Dispose();$script:job=$null;Render-Rows
  $scan.Enabled=$true;$up.Enabled=$true;$cancel.Enabled=$false
  if($state -eq 'Completed' -and -not $script:scanErrors.Count){
   $script:cache[$script:root]=@{Time=(Get-Date).ToString('g');Rows=$script:rows}
   if($script:rows.Count -lt 2000){$script:cache|Export-Clixml -LiteralPath $script:cacheFile -Depth 8}
  }
  $total=($script:rows|Measure-Object Bytes -Sum).Sum;$skipped=($script:rows|Measure-Object Skipped -Sum).Sum
  $status.Text="$state - $(Format-Size $total) measured in $($script:rows.Count) entries in $([math]::Round($elapsed,1)) seconds. Skipped: $skipped. $($script:root)"
  if($script:rows.Count -gt 500){$status.Text+=' Showing the largest 500 entries.'}
  if($script:scanErrors.Count){$status.Text+=' Some folders could not be read. Try Administrator.'}
  Update-Disk
  if($SmokeTest){$cacheWatch=[Diagnostics.Stopwatch]::StartNew();Start-Scan $script:root;$cacheWatch.Stop();[pscustomobject]@{State=$state;Rows=$folders.Items.Count;FileRows=$files.Items.Count;ChartPoints=$chart.Series[0].Points.Count;Bytes=$total;Errors=$script:scanErrors.Count;Seconds=$elapsed;MaxUITickGapMs=$script:maxTickGap;CachedOpenMs=$cacheWatch.ElapsedMilliseconds}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'map-smoke.json');$form.Close()}
 }
 } catch {
  $timer.Stop()
  ($_|Out-String)+$_.ScriptStackTrace | Set-Content (Join-Path $PSScriptRoot 'map-error.log')
  $status.Text='Scan display failed: '+$_.Exception.Message
  $scan.Enabled=$true;$up.Enabled=$true;$cancel.Enabled=$false
  if($script:job -and $script:job.Handle.IsCompleted){$script:job.Engine.Dispose();$script:job=$null}
  if($SmokeTest){$form.Close()}
 }
})
$scan.Add_Click({Start-Scan $location.Text $true})
$up.Add_Click({$parent=Split-Path -Parent $location.Text.TrimEnd('\');if($parent -eq 'C:'){$parent='C:\'};if($parent){Start-Scan $parent}})
$cancel.Add_Click({if($script:job){$script:job.Cancelled=$true;if('StorageScan' -as [type]){[StorageScan]::Cancelled=$true};$status.Text='Stopping scan...'}})
$folders.Add_DoubleClick({if($folders.SelectedItems.Count){$row=$folders.SelectedItems[0].Tag;if($row.Directory){Start-Scan $row.Path}else{Start-Process explorer.exe -ArgumentList ('/select,"'+$row.Path+'"')}}})
$files.Add_DoubleClick({if($files.SelectedItems.Count){Start-Process explorer.exe -ArgumentList ('/select,"'+$files.SelectedItems[0].Tag+'"')}})
$script:cleanupProcess=$null
. (Join-Path $PSScriptRoot 'TempButton.ps1')
$tempButton=Add-WindowsTempButton $form 880 20 254 {
 $script:cache=@{};$script:cache|Export-Clixml -LiteralPath $script:cacheFile
 Update-Disk
 $status.Text='Windows Temp cleaned. Click Analyze to refresh folder sizes.'
}
$tempButton.Anchor='Top,Right'
$cleanup.Add_Click({
 try {
  if($script:cleanupProcess -and -not $script:cleanupProcess.HasExited){$shell=New-Object -ComObject WScript.Shell;[void]$shell.AppActivate($script:cleanupProcess.Id);return}
  $script:cleanupProcess=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "'+(Join-Path $PSScriptRoot 'Cleaner.ps1')+'"')
 }catch{$status.Text='Could not open cleanup: '+$_.Exception.Message}
})
$admin.Add_Click({try{Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "'+$PSCommandPath+'"');$form.Close()}catch{$status.Text='Administrator launch cancelled.'}})
$form.Add_FormClosing({$timer.Stop();$heartbeat.Stop();if($script:job){if('StorageScan' -as [type]){[StorageScan]::Cancelled=$true};[void]$script:job.Engine.BeginStop($null,$null)}})
$form.Add_Shown({Start-Scan $location.Text ([bool]$SmokeTest)})
Update-Disk
[void]$form.ShowDialog()
