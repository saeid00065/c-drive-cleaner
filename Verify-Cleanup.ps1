$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('cleanup-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$old=Join-Path $fixture 'old.tmp';$recent=Join-Path $fixture 'recent.tmp';$locked=Join-Path $fixture 'locked.tmp'
foreach($path in @($old,$recent,$locked)){[IO.File]::WriteAllBytes($path,(New-Object byte[] 2048))}
foreach($path in @($old,$locked)){[IO.File]::SetCreationTime($path,(Get-Date).AddDays(-10));[IO.File]::SetLastWriteTime($path,(Get-Date).AddDays(-10))}
$code=(Get-Content (Join-Path $PSScriptRoot 'Worker.ps1') -Raw).Replace('foreach($target in Get-Targets)','foreach($target in $FixtureTargets)')
function Invoke-Fixture($mode,$selected){
 $engine=[powershell]::Create()
 $engine.Runspace.SessionStateProxy.SetVariable('FixtureTargets',@(@{Id='fixture';Name='Disposable test';Path=$fixture;Days=7}))
 [void]$engine.AddScript($code).AddParameter('Mode',$mode).AddParameter('Selected',[string[]]$selected)
 try{$result=@($engine.Invoke());if($engine.Streams.Error.Count){throw ($engine.Streams.Error|Out-String)};return $result}finally{$engine.Dispose()}
}
$handle=[IO.File]::Open($locked,'Open','ReadWrite','None')
try {
 $scan=Invoke-Fixture 'Scan' @()
 if($scan.Bytes -ne 4096){throw 'Age filter failed'}
 $none=Invoke-Fixture 'Clean' @('not-selected')
 if($none.Count -ne 0 -or -not (Test-Path $old)){throw 'Selection filter failed'}
 $clean=Invoke-Fixture 'Clean' @('fixture')
 if((Test-Path $old) -or -not (Test-Path $recent) -or -not (Test-Path $locked)){throw 'Deletion safety failed'}
 if($clean.Deleted -ne 1 -or $clean.Removed -ne 2048 -or $clean.Skipped -ne 1){throw 'Result accounting failed'}
 Write-Output 'PASS: old selected file removed; recent, unselected and locked files preserved; counts and skipped reason correct.'
} finally {
 $handle.Dispose()
 foreach($path in @($old,$recent,$locked)){if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
 [IO.Directory]::Delete($fixture)
}
