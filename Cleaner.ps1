param([switch]$SelfTest,[switch]$SmokeTest)
$ErrorActionPreference='Stop'
trap {
    $detail=($_ | Out-String)+"`r`n"+$_.ScriptStackTrace
    $detail | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'error.log')
    [void][System.Windows.Forms.MessageBox]::Show($detail,'C Drive Cleaner error')
    exit 1
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$worker=Join-Path $PSScriptRoot 'Worker.ps1'
if($SelfTest){
    $errors=$null; $tokens=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors | Out-String)}
    Write-Output 'Worker syntax OK; Windows Forms available.'
    exit
}
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='C Drive Cleaner - Safe Cleanup'; $form.Size=New-Object Drawing.Size(1050,660); $form.MinimumSize=$form.Size; $form.StartPosition='CenterScreen'
$form.ShowInTaskbar=$true;$form.WindowState='Normal'
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(245,247,250)
function Label($text,$x,$y,$width,$height){$l=New-Object Windows.Forms.Label;$l.Text=$text;$l.SetBounds($x,$y,$width,$height);$form.Controls.Add($l);return $l}
$title=Label 'C Drive Cleaner' 24 20 880 40
$title.Font=New-Object Drawing.Font('Segoe UI',22,[Drawing.FontStyle]::Bold)
$disk=Label '' 26 70 880 28
$info=Label 'Scan hidden caches and old temporary files. Personal files and Windows system files are protected.' 26 109 870 46
$list=New-Object Windows.Forms.ListView
$list.SetBounds(26,164,980,270);$list.View='Details';$list.CheckBoxes=$true;$list.FullRowSelect=$true;$list.GridLines=$true
$list.Anchor='Top,Bottom,Left,Right'
foreach($column in @(@('Cleanup category',280),@('Eligible / removed',140),@('Files',70),@('Minimum age',100),@('Skipped',75),@('Result',280))){[void]$list.Columns.Add($column[0],[int]$column[1])}
$form.Controls.Add($list)
$path=Label 'Select a row to see its exact folder. Tick only the categories you want to clean.' 26 444 875 44
$path.Anchor='Bottom,Left,Right'
$status=Label 'Scanning cleanup candidates...' 26 540 975 70
$status.Anchor='Bottom,Left,Right'
function Button($text,$x,$width){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.SetBounds($x,492,$width,36);$b.Anchor='Bottom,Left';$form.Controls.Add($b);return $b}
$scan=Button 'Scan' 26 120
$clean=Button 'Clean selected' 158 170
$admin=Button 'Run as administrator' 340 205
$selectAll=Button 'Select eligible' 557 150
$selectAll.Enabled=$false
. (Join-Path $PSScriptRoot 'TempButton.ps1')
$tempButton=Add-WindowsTempButton $form 719 492 287 {Refresh-Disk}
$tempButton.Anchor='Bottom,Left'
$selectAll.Add_Click({foreach($item in $list.Items){$item.Checked=$item.Tag.Bytes -gt 0}})
$clean.Enabled=$false
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($isAdmin){$admin.Enabled=$false;$admin.Text='Administrator mode'}
function Refresh-Disk {$d=New-Object IO.DriveInfo('C');$disk.Text=('C:   {0:N2} GB free of {1:N1} GB   |   {2:N1}% used' -f ($d.AvailableFreeSpace/1GB),($d.TotalSize/1GB),(100*(1-$d.AvailableFreeSpace/$d.TotalSize)))}
function Begin-Work($mode,$ids){
    $script:mode=$mode;$scan.Enabled=$false;$clean.Enabled=$false;$selectAll.Enabled=$false;$admin.Enabled=$false;$status.Text="$mode in progress... Locked and inaccessible files are skipped."
    $engine=[powershell]::Create()
    [void]$engine.AddCommand($worker).AddParameter('Mode',$mode).AddParameter('Selected',[string[]]$ids)
    $script:job=@{Engine=$engine;Handle=$engine.BeginInvoke()}
    $timer.Start()
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=400
$timer.Add_Tick({
 try {
    if($script:job.Handle.IsCompleted){
        $timer.Stop()
        $results=@($script:job.Engine.EndInvoke($script:job.Handle));$jobErrors=@($script:job.Engine.Streams.Error)
        $failed=$jobErrors.Count -gt 0
        $script:job.Engine.Dispose();$script:job=$null
        if($failed){$status.Text='Operation failed: '+(($jobErrors|ForEach-Object {$_.ToString()}) -join '; ');$status.Text|Set-Content (Join-Path $PSScriptRoot 'cleanup-error.log')}
        elseif($script:mode -eq 'Scan'){
            $list.BeginUpdate();$list.Items.Clear()
            foreach($row in $results){
                $item=New-Object Windows.Forms.ListViewItem($row.Name);$item.Tag=$row
                [void]$item.SubItems.Add(('{0:N1} MB' -f ($row.Bytes/1MB)));[void]$item.SubItems.Add([string]$row.Files);[void]$item.SubItems.Add("$($row.Days) days");[void]$item.SubItems.Add([string]$row.Skipped)
                [void]$item.SubItems.Add($row.Status)
                [void]$list.Items.Add($item)
            }
            $list.EndUpdate()
            $total=($results|Measure-Object Bytes -Sum).Sum
            $status.Text=('Scan complete: {0:N2} GB eligible. Check categories to clean. Skipped counts may indicate access restrictions.' -f ($total/1GB))
            $clean.Enabled=$true
            $selectAll.Enabled=$true
        }else{
            $total=($results|Measure-Object Removed -Sum).Sum;$count=($results|Measure-Object Deleted -Sum).Sum;$skipped=($results|Measure-Object Skipped -Sum).Sum
            $status.Text=('Removed {0:N1} MB in {1} files; skipped {2}. Close affected apps for locked files; administrator mode may help access-denied files. Scan to refresh.' -f ($total/1MB),$count,$skipped)
            $list.BeginUpdate();$list.Items.Clear()
            foreach($row in $results){$item=New-Object Windows.Forms.ListViewItem($row.Name);$item.Tag=$row;[void]$item.SubItems.Add(('{0:N1} MB removed' -f ($row.Removed/1MB)));[void]$item.SubItems.Add([string]$row.Deleted);[void]$item.SubItems.Add('');[void]$item.SubItems.Add([string]$row.Skipped);[void]$item.SubItems.Add($row.Status);[void]$list.Items.Add($item)}
            $list.EndUpdate()
            $results|Export-Clixml -LiteralPath (Join-Path $PSScriptRoot 'last-cleanup.xml')
        }
        $scan.Enabled=$true;$admin.Enabled=-not $isAdmin;Refresh-Disk
        if($SmokeTest){
            [pscustomobject]@{Failed=[bool]$failed;Rows=$list.Items.Count;Status=$status.Text} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'smoke-result.json')
            $form.Close()
        }
    }
 } catch {
  $timer.Stop();$status.Text='Cleanup error: '+$_.Exception.Message
  ($_|Out-String)+$_.ScriptStackTrace|Set-Content (Join-Path $PSScriptRoot 'cleanup-error.log')
  $scan.Enabled=$true;$admin.Enabled=-not $isAdmin
  if($SmokeTest){$form.Close()}
 }
})
$scan.Add_Click({Begin-Work 'Scan' @()})
$list.Add_SelectedIndexChanged({if($list.SelectedItems.Count){$path.Text=$list.SelectedItems[0].Tag.Path}})
$clean.Add_Click({
    $chosen=@($list.CheckedItems|ForEach-Object {$_.Tag})
    if(-not $chosen.Count){[void][Windows.Forms.MessageBox]::Show('Check one or more categories first.','Nothing selected');return}
    $total=($chosen|Measure-Object Bytes -Sum).Sum
    $message=('Permanently delete up to {0:N2} GB from these categories?' -f ($total/1GB))+"`r`n`r`n"+(($chosen|ForEach-Object {$_.Name}) -join "`r`n")+"`r`n`r`nClose browsers and reaConverter first. Cached web content will download again. This cannot be undone."
    if([Windows.Forms.MessageBox]::Show($message,'Confirm cleanup','YesNo','Warning','Button2') -eq 'Yes'){Begin-Work 'Clean' @($chosen|ForEach-Object {$_.Id})}
})
$admin.Add_Click({
    try{Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"'+$PSCommandPath+'"'));$form.Close()}catch{$status.Text='Administrator request cancelled.'}
})
$form.Add_FormClosing({$timer.Stop();if($script:job){[void]$script:job.Engine.BeginStop($null,$null)}})
Refresh-Disk
$form.Add_Shown({$form.TopMost=$true;$form.Activate();$form.BringToFront();$form.TopMost=$false;$scan.PerformClick()})
[void]$form.ShowDialog()
