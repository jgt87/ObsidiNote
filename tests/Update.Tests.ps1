# Release updates (lib/Update.psm1, tools/update.ps1). Pester 3.4 syntax. No network: every updater
# run below stops before it would contact GitHub. State and logs go to %TEMP%.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'lib\Update.psm1') -Force
$updater = Join-Path $root 'tools\update.ps1'
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'

function New-UpdateDirs {
    $b = Join-Path $env:TEMP ('obsn-upd-' + [guid]::NewGuid().ToString('N'))
    foreach ($d in 'new\tools', 'new\lib', 'app\tools', 'app\lib', 'app\node_modules\x', 'app\config') { New-Item -ItemType Directory (Join-Path $b $d) -Force | Out-Null }
    foreach ($f in 'tools\run.cmd', 'lib\A.psm1') { [IO.File]::WriteAllText((Join-Path $b "new\$f"), 'new') }
    [IO.File]::WriteAllText((Join-Path $b 'app\tools\run.cmd'), 'old one')
    [IO.File]::WriteAllText((Join-Path $b 'app\lib\A.psm1'), 'new'); (Get-Item (Join-Path $b 'app\lib\A.psm1')).LastWriteTimeUtc = (Get-Item (Join-Path $b 'new\lib\A.psm1')).LastWriteTimeUtc
    [IO.File]::WriteAllText((Join-Path $b 'app\gone.cmd'), 'removed in the release')
    [IO.File]::WriteAllText((Join-Path $b 'app\node_modules\x\i.js'), '')
    [IO.File]::WriteAllText((Join-Path $b 'app\config\obsidinote.local.json'), '{}')
    $b
}

function Invoke-Updater([string[]]$UpdaterArgs) {
    # The updater reports on stderr: with ErrorActionPreference Stop, 2>&1 would turn that into an error.
    $ErrorActionPreference = 'Continue'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updater @UpdaterArgs 2>&1 | ForEach-Object { "$_" }
    $out -join ' '
}

Describe 'Release versions' {
    It 'reads release versions with or without the v' {
        ConvertTo-ReleaseVersion 'v0.1.150' | Should Be ([version]'0.1.150')
        ConvertTo-ReleaseVersion '0.1.9' | Should Be ([version]'0.1.9')
        ConvertTo-ReleaseVersion 'latest' | Should BeNullOrEmpty
        ConvertTo-ReleaseVersion 'v1.2' | Should BeNullOrEmpty
    }
    It 'treats v0.1.0 and 0.1.0 as the same release, and compares numbers, not text' {
        Test-SameRelease 'v0.1.0' '0.1.0' | Should Be $true
        Test-SameRelease 'v0.1.0' "0.1.0`n" | Should Be $true
        Test-SameRelease 'v0.1.10' 'v0.1.1' | Should Be $false
        Test-SameRelease '' '' | Should Be $true
        Test-SameRelease 'v0.1.0' '' | Should Be $false
    }
}

Describe 'Skipping releases after going back' {
    It 'skips a release up to the newest one gone back from' {
        Test-ReleaseSkipped 'v0.1.150' @('v0.1.150') | Should Be $true
        Test-ReleaseSkipped 'v0.1.149' @('v0.1.150') | Should Be $true    # older than the skip: left alone too
        Test-ReleaseSkipped 'v0.1.151' @('v0.1.150') | Should Be $false   # the fix: installed again
        Test-ReleaseSkipped 'v0.1.151' @('v0.1.150', 'v0.1.152') | Should Be $true
        Test-ReleaseSkipped 'v0.1.151' @() | Should Be $false
        Test-ReleaseSkipped 'v0.1.151' @('junk') | Should Be $false
        Test-ReleaseSkipped 'v0.1.100' @('v0.1.99') | Should Be $false    # numbers, not text
    }
    It 'skips the newest of the installed and the latest release, when it is newer than the target' {
        Get-RollbackSkip 'v0.1.149' 'v0.1.150' 'v0.1.150' | Should Be 'v0.1.150'
        Get-RollbackSkip 'v0.1.148' 'v0.1.149' 'v0.1.150' | Should Be 'v0.1.150'
        Get-RollbackSkip 'v0.1.149' '0.1.150' '' | Should Be 'v0.1.150'            # GitHub not reached
        Get-RollbackSkip 'v0.1.150' 'v0.1.149' 'v0.1.150' | Should Be ''           # forward: nothing to skip
        Get-RollbackSkip 'nope' 'v0.1.150' 'v0.1.150' | Should Be ''
    }
}

Describe 'Update settings' {
    It 'is on by default, and the local file wins over the shipped defaults' {
        $b = New-UpdateDirs
        Remove-Item "$b\app\config\obsidinote.local.json"
        $s = Get-UpdateSettings "$b\app"
        $s.autoUpdate | Should Be $true
        @($s.skipUpdates).Count | Should Be 0
        [IO.File]::WriteAllText("$b\app\config\obsidinote.json", '{ "autoUpdate": true, "skipUpdates": ["v0.1.1"] }')
        [IO.File]::WriteAllText("$b\app\config\obsidinote.local.json", '{ "autoUpdate": false }')
        $s = Get-UpdateSettings "$b\app"
        $s.autoUpdate | Should Be $false
        (@($s.skipUpdates) -join ',') | Should Be 'v0.1.1'
        Remove-Item $b -Recurse -Force
    }
    It 'sets and removes values in obsidinote.local.json, keeping the others' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\app\config\obsidinote.local.json", '{ "port": 8800 }')
        Set-LocalAppValue "$b\app" 'skipUpdates' @('v0.1.150')
        @(Get-LocalAppValue "$b\app" 'skipUpdates') | Should Be 'v0.1.150'
        Get-LocalAppValue "$b\app" 'port' | Should Be 8800
        Set-LocalAppValue "$b\app" 'skipUpdates' $null
        Get-LocalAppValue "$b\app" 'skipUpdates' | Should BeNullOrEmpty
        Get-LocalAppValue "$b\app" 'port' | Should Be 8800
        Remove-Item "$b\app\config" -Recurse
        Get-LocalAppValue "$b\app" 'skipUpdates' | Should BeNullOrEmpty   # no file yet
        Set-LocalAppValue "$b\app" 'autoUpdate' $false                    # creates config\ too
        Get-LocalAppValue "$b\app" 'autoUpdate' | Should Be $false
        Remove-Item $b -Recurse -Force
    }
}

Describe 'Files an update touches' {
    It 'lists changed and removed files, not identical or excluded ones' {
        $b = New-UpdateDirs
        $r = @(Get-UpdateTouchedFiles -Source "$b\new" -Target "$b\app" -ExcludeFiles @('*.local.json') -ExcludeDirs @('node_modules')) | Sort-Object
        ($r -join ',') | Should Be 'gone.cmd,tools\run.cmd'
        Remove-Item $b -Recurse -Force
    }
}

Describe 'Files in use' {
    It 'names a file another program has open, and nothing once it is closed' {
        $b = New-UpdateDirs
        $fs = [IO.File]::Open("$b\app\tools\run.cmd", 'Open', 'Read', 'Read')
        try {
            Test-FileLocked "$b\app\tools\run.cmd" | Should Be $true
            $l = Get-LockedUpdateFiles -Source "$b\new" -Target "$b\app" -ExcludeFiles @('*.local.json') -ExcludeDirs @('node_modules')
            (@($l.blocking) -join ',') | Should Be 'tools\run.cmd'
            $msg = Format-LockedUpdateFiles @($l.blocking) 'v9.9.9'
            $msg | Should Match '^update to v9\.9\.9 waits: in use by another program: tools\\run\.cmd\. Nothing was changed\. Close the command window'
        } finally { $fs.Close() }
        Test-FileLocked "$b\app\tools\run.cmd" | Should Be $false
        Test-FileLocked "$b\app\not-there.txt" | Should Be $false
        @((Get-LockedUpdateFiles -Source "$b\new" -Target "$b\app" -ExcludeDirs @('node_modules')).blocking).Count | Should Be 0
        Remove-Item $b -Recurse -Force
    }
    It 'skips an open file with the same content and an open file the release removes' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\app\tools\run.cmd", 'new')
        (Get-Item "$b\app\tools\run.cmd").LastWriteTimeUtc = (Get-Date).AddDays(-3).ToUniversalTime()
        $f1 = [IO.File]::Open("$b\app\tools\run.cmd", 'Open', 'Read', 'Read')
        $f2 = [IO.File]::Open("$b\app\gone.cmd", 'Open', 'Read', 'Read')
        try {
            $l = Get-LockedUpdateFiles -Source "$b\new" -Target "$b\app" -ExcludeFiles @('*.local.json') -ExcludeDirs @('node_modules')
            @($l.blocking).Count | Should Be 0
            (@($l.same) -join ',') | Should Be 'tools\run.cmd'
            (@($l.removed) -join ',') | Should Be 'gone.cmd'
        } finally { $f1.Close(); $f2.Close() }
        Remove-Item $b -Recurse -Force
    }
    It 'reads the file names from robocopy errors' {
        $lines = @('', '2026/10/07 10:00:01 ERROR 32 (0x00000020) Copying File C:\App\tools\run.cmd', 'The process cannot access the file because it is being used by another process.', '2026/10/07 10:00:02 ERROR 5 (0x00000005) Deleting Extra File C:\App\old.cmd')
        (@(Get-RobocopyFailures $lines) -join ',') | Should Be 'C:\App\tools\run.cmd,C:\App\old.cmd'
    }
}

Describe 'An update that fails halfway' {
    It 'puts the old version back whole: replaced and removed files return, added files go' {
        $b = New-UpdateDirs
        $touched = @(Get-UpdateTouchedFiles -Source "$b\new" -Target "$b\app" -ExcludeFiles @('*.local.json') -ExcludeDirs @('node_modules'))
        [IO.File]::WriteAllText("$b\new\lib\Added.psm1", 'added in the release')
        $added = @(Get-UpdateNewFiles -Source "$b\new" -Target "$b\app" -ExcludeDirs @('node_modules'))
        ($added -join ',') | Should Be 'lib\Added.psm1'
        Save-UpdateBackup -Target "$b\app" -Files $touched -BackupDir "$b\backup"
        # Half a copy: one file replaced, one removed, one added.
        [IO.File]::WriteAllText("$b\app\tools\run.cmd", 'new')
        Remove-Item "$b\app\gone.cmd"
        New-Item -ItemType Directory "$b\app\newdir" | Out-Null; [IO.File]::WriteAllText("$b\app\newdir\x.txt", 'x')
        [IO.File]::WriteAllText("$b\app\lib\Added.psm1", 'added in the release')
        @(Restore-UpdateBackup -Target "$b\app" -BackupDir "$b\backup" -NewFiles @($added + 'newdir\x.txt')).Count | Should Be 0
        [IO.File]::ReadAllText("$b\app\tools\run.cmd") | Should Be 'old one'
        [IO.File]::ReadAllText("$b\app\gone.cmd") | Should Be 'removed in the release'
        Test-Path "$b\app\lib\Added.psm1" | Should Be $false
        Test-Path "$b\app\newdir" | Should Be $false
        Test-Path "$b\app\config\obsidinote.local.json" | Should Be $true
        Remove-Item $b -Recurse -Force
    }
}

Describe 'Release checksums and manifest' {
    It 'writes SHA256SUMS that sha256sum -c reads: lower-case hash, two spaces, file name, LF' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\a.zip", 'abc')
        (New-ReleaseChecksums -Files @("$b\a.zip") -OutFile "$b\SHA256SUMS") | Should Be 1
        [IO.File]::ReadAllText("$b\SHA256SUMS") | Should BeExactly "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  a.zip`n"
        { New-ReleaseChecksums -Files @("$b\missing.zip") -OutFile "$b\SHA256SUMS" } | Should Throw 'Cannot read'
        Remove-Item $b -Recurse -Force
    }
    It 'finds files missing or different from the release, and nothing in a complete folder' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\new\version.txt", 'v9.9.9')
        (New-InstallManifest -AppFolder "$b\new" -Version 'v9.9.9') | Should Be 2
        $m = ConvertFrom-Json ([IO.File]::ReadAllText("$b\new\manifest.json"))
        $m.version | Should Be 'v9.9.9'
        $m.files.'lib/A.psm1' | Should Match '^[0-9A-F]{64}$'
        $ok = Test-InstallIntegrity "$b\new"
        @($ok.missing).Count + @($ok.changed).Count | Should Be 0
        Format-InstallProblem $ok | Should Be ''
        [IO.File]::WriteAllText("$b\new\lib\A.psm1", 'damaged')
        Remove-Item "$b\new\tools\run.cmd"
        [IO.File]::WriteAllText("$b\new\config.local.json", '{}')   # machine files are not part of the release
        $bad = Test-InstallIntegrity "$b\new"
        (@($bad.missing) -join ',') | Should Be 'tools/run.cmd'
        (@($bad.changed) -join ',') | Should Be 'lib/A.psm1'
        Format-InstallProblem $bad | Should Match '^ObsidiNote v9\.9\.9 is not complete: 1 file\(s\) missing and 1 different from the release \(tools/run\.cmd, lib/A\.psm1\)\. An update probably stopped halfway\.'
        Test-InstallIntegrity "$b\app" | Should BeNullOrEmpty   # no manifest: a git clone or development copy
        Remove-Item $b -Recurse -Force
    }
}

Describe 'The updater script (no network)' {
    It 'installs an unpacked release when handed over, keeping local settings' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\app\version.txt", 'v0.0.1')
        $out = Invoke-Updater @('-AppRoot', "$b\app", '-FromFolder', "$b\new", '-Version', 'v9.9.9')
        $out | Should Match '\[ObsidiNote update\] updated v0\.0\.1 -> v9\.9\.9'
        [IO.File]::ReadAllText("$b\app\version.txt") | Should Be 'v9.9.9'
        [IO.File]::ReadAllText("$b\app\tools\run.cmd") | Should Be 'new'
        Test-Path "$b\app\gone.cmd" | Should Be $false
        Test-Path "$b\app\config\obsidinote.local.json" | Should Be $true   # kept although the release has no config\
        Test-Path "$b\app\node_modules\x\i.js" | Should Be $true
        Remove-Item $b -Recurse -Force
    }
    It 'waits for a file in use instead of copying half a release' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\app\version.txt", 'v0.0.1')
        $fs = [IO.File]::Open("$b\app\tools\run.cmd", 'Open', 'Read', 'Read')
        try { $out = Invoke-Updater @('-AppRoot', "$b\app", '-FromFolder', "$b\new", '-Version', 'v9.9.9') } finally { $fs.Close() }
        $out | Should Match 'update to v9\.9\.9 waits: in use by another program: tools\\run\.cmd'
        [IO.File]::ReadAllText("$b\app\version.txt") | Should Be 'v0.0.1'
        Test-Path "$b\app\gone.cmd" | Should Be $true
        Remove-Item $b -Recurse -Force
    }
    It 'does nothing when automatic updates are off' {
        $b = New-UpdateDirs
        [IO.File]::WriteAllText("$b\app\config\obsidinote.local.json", '{ "autoUpdate": false }')
        Invoke-Updater @('-AppRoot', "$b\app") | Should Be ''
        $LASTEXITCODE | Should Be 0
        Remove-Item $b -Recurse -Force
    }
    It 'refuses something that is not a release, and a git clone, before going online' {
        $b = New-UpdateDirs
        Invoke-Updater @('-AppRoot', "$b\app", '-To', 'the-good-one') | Should Match "'the-good-one' is not a release"
        New-Item -ItemType Directory "$b\app\.git" | Out-Null
        Invoke-Updater @('-AppRoot', "$b\app", '-To', '0.1.149') | Should Match 'This is a git clone: go back with git itself \(git checkout v0\.1\.149\)'
        Remove-Item $b -Recurse -Force
    }
}
