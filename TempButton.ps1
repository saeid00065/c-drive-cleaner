function Add-WindowsTempButton($Owner,$X,$Y,$Width,$OnDone) {
 $button=New-Object Windows.Forms.Button
 $button.Text='Clean Windows Temp';$button.SetBounds($X,$Y,$Width,36)
 $Owner.Controls.Add($button)
 $tip=New-Object Windows.Forms.ToolTip
 $tip.SetToolTip($button,'Remove Windows temporary files older than 7 days. Administrator permission required; locked files are skipped.')
 $state=@{Process=$null;Report=$null;Owner=$Owner;Button=$button;Folder=$PSScriptRoot;OnDone=$OnDone;Tip=$tip}
 $poll=New-Object Windows.Forms.Timer;$poll.Interval=500;$state.Timer=$poll
 $poll.Add_Tick({
  if(-not $state.Process.HasExited){return}
  $state.Timer.Stop();$state.Button.Enabled=$true;$state.Button.Text='Clean Windows Temp'
  try {
   if(-not (Test-Path -LiteralPath $state.Report)){throw 'No cleanup result was returned. Please try again.'}
   $result=Get-Content -LiteralPath $state.Report -Raw|ConvertFrom-Json
   if(-not $result.Success){throw $result.Error}
   $bytes=($result.Results|Measure-Object Removed -Sum).Sum
   $count=($result.Results|Measure-Object Deleted -Sum).Sum
   $skipped=($result.Results|Measure-Object Skipped -Sum).Sum
   $text=('Freed {0:N2} GB ({1:N0} MB). Deleted {2:N0} old temporary files.' -f ($bytes/1GB),($bytes/1MB),$count)+"`r`n"+('C: now has {0:N2} GB free. Skipped: {1}.' -f $result.FreeGB,$skipped)
   if($count -eq 0){$text+="`r`nNo removable files older than 7 days were found."}
   if($state.OnDone){& $state.OnDone}
   [void][Windows.Forms.MessageBox]::Show($state.Owner,$text,'Windows Temp cleanup complete','OK','Information')
  }catch{[void][Windows.Forms.MessageBox]::Show($state.Owner,$_.Exception.Message,'Windows Temp cleanup','OK','Warning')}
  finally{$state.Process.Dispose();$state.Process=$null}
 }.GetNewClosure())
 $button.Add_Click({
  $state.Button.Enabled=$false;$state.Button.Text='Cleaning Windows Temp...'
  try {
   $id=[guid]::NewGuid();$state.Report=Join-Path $state.Folder ('windows-temp-'+$id.ToString('N')+'.json')
   $helper=Join-Path $state.Folder 'Clean-Windows-Temp.ps1'
   $state.Process=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$helper+'" -RunId '+$id)
   $state.Timer.Start()
  }catch{
   $state.Button.Enabled=$true;$state.Button.Text='Clean Windows Temp'
   [void][Windows.Forms.MessageBox]::Show($state.Owner,'Windows did not grant administrator access. Click again and choose Yes in the Windows permission prompt.','Cleanup not started','OK','Information')
  }
 }.GetNewClosure())
 $Owner.Add_FormClosed({$state.Timer.Stop();$state.Timer.Dispose();$state.Tip.Dispose()}.GetNewClosure())
 return $button
}
