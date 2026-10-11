param([ValidateSet('Scan','Clean')][string]$Mode='Scan', [string[]]$Selected=@())
$ErrorActionPreference='Stop'
function Get-Targets {
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    $items=@(
        @{Id='user-temp'; Name='Old user temporary files'; Path="$local\Temp"; Days=7},
        @{Id='windows-temp'; Name='Old Windows temporary files'; Path="$env:SystemRoot\Temp"; Days=7},
        @{Id='converter-temp'; Name='Old reaConverter temporary files'; Path="$env:ProgramData\reaConverter8\temp"; Days=7},
        @{Id='crash'; Name='Old application crash reports'; Path="$local\CrashDumps"; Days=7}
    )
    foreach($app in @('Notion','Codex','DropboxElectron')) {
        foreach($cache in @('Cache','Code Cache','GPUCache')) {
            $items+=@{Id="$app-$cache";Name="$app`: $cache";Path=(Join-Path $env:APPDATA "$app\$cache");Days=1}
        }
    }
    foreach($browser in @(@{Name='Chrome';Root="$local\Google\Chrome\User Data"},@{Name='Edge';Root="$local\Microsoft\Edge\User Data"},@{Name='Brave';Root="$local\BraveSoftware\Brave-Browser\User Data"})) {
        foreach($profile in @(Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue | Where-Object {($_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$') -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)})) {
            foreach($cache in @('Cache','Code Cache','GPUCache')) {
                $items+=@{Id="$($browser.Name)-$($profile.Name)-$cache";Name="$($browser.Name) $($profile.Name): $cache";Path=(Join-Path $profile.FullName $cache);Days=1}
            }
        }
    }
    $items
}
function Assert-SafeRoot([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if(-not $full.StartsWith('C:\',[StringComparison]::OrdinalIgnoreCase)){throw 'Only C: targets are allowed.'}
    $part=$full
    while($part -and ([IO.Directory]::Exists($part) -or [IO.File]::Exists($part))) {
        if([IO.File]::GetAttributes($part) -band [IO.FileAttributes]::ReparsePoint){throw "Linked path skipped: $part"}
        $parent=[IO.Directory]::GetParent($part)
        if($parent){$part=$parent.FullName}else{$part=$null}
    }
    $full
}
function Get-SafeFiles([string]$Root) {
    $stack=New-Object 'Collections.Generic.Stack[string]'
    $stack.Push($Root)
    while($stack.Count -gt 0) {
        $dir=$stack.Pop()
        try {$children=@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)} catch {$script:Skipped++;continue}
        foreach($child in $children) {
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($child.PSIsContainer){$stack.Push($child.FullName)}else{$child}
        }
    }
}
foreach($target in Get-Targets) {
    if($Mode -eq 'Clean' -and $Selected -notcontains $target.Id){continue}
    $script:Skipped=0; $bytes=0L; $count=0; $removed=0L; $deleted=0; $status='OK';$reasons=New-Object 'Collections.Generic.List[string]'
    try {
        $root=Assert-SafeRoot $target.Path
        if(-not (Test-Path -LiteralPath $root)){continue}
        $cutoff=(Get-Date).AddDays(-$target.Days)
        foreach($file in Get-SafeFiles $root) {
            if($target.Id -eq 'converter-temp' -and $file.Name -notmatch '^rcp\d+\.(dxf|skp|log|cfg)$'){continue}
            if($file.LastWriteTime -ge $cutoff -or $file.CreationTime -ge $cutoff){continue}
            $bytes+=$file.Length; $count++
            if($Mode -eq 'Clean') {
                try {
                    $resolved=Assert-SafeRoot $file.FullName
                    if(-not $resolved.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Outside approved folder'}
                    $fresh=Get-Item -LiteralPath $resolved -Force
                    if($fresh.LastWriteTime -ge $cutoff -or $fresh.CreationTime -ge $cutoff){continue}
                    $length=$fresh.Length
                    Remove-Item -LiteralPath $resolved -Force -ErrorAction Stop
                    $removed+=$length; $deleted++
                }catch{$script:Skipped++;if($reasons.Count -lt 2){$reasons.Add($_.Exception.Message)}}
            }
        }
    }catch{$status=$_.Exception.Message; $script:Skipped++}
    if($reasons.Count){$status=$reasons -join ' | '}elseif($status -eq 'OK' -and $script:Skipped){$status='Some folders are inaccessible or locked.'}elseif($status -eq 'OK' -and $count -eq 0){$status='No files meet the minimum age.'}
    [pscustomobject]@{Id=$target.Id;Name=$target.Name;Path=$target.Path;Days=$target.Days;Bytes=$bytes;Files=$count;Removed=$removed;Deleted=$deleted;Skipped=$script:Skipped;Status=$status}
}
