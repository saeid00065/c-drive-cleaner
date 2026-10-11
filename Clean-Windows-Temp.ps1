param([guid]$RunId=[guid]::Empty)
$ErrorActionPreference='Stop'
$report=Join-Path $PSScriptRoot 'windows-temp-result.json'
if($RunId -ne [guid]::Empty){$report=Join-Path $PSScriptRoot ('windows-temp-'+$RunId.ToString('N')+'.json')}
try {
 $before=(Get-PSDrive C).Free
 $results=@(& (Join-Path $PSScriptRoot 'Worker.ps1') -Mode Clean -Selected 'windows-temp')
 [pscustomobject]@{Success=$true;Results=$results;FreeGB=[math]::Round((Get-PSDrive C).Free/1GB,2);FreeIncreaseMB=[math]::Round(((Get-PSDrive C).Free-$before)/1MB,1)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $report
}catch{[pscustomobject]@{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $report;exit 1}
