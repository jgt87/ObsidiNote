# ObsidiNote installer: downloads the latest release from GitHub into
# %LOCALAPPDATA%\Programs\ObsidiNote (no admin rights) and adds Start menu and desktop shortcuts.
# Run it again any time to update. ObsidiNote also updates itself when it starts.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jgt87/ObsidiNote/main/install.ps1 | iex"
#
# (The same install sequence as CCBridge/StreamHub.) That command fetches the one-line bootstrap
# install.ps1 in the repo root, which downloads this file and runs it with -File.
#
# Optional: set $env:OBSIDINOTE_DIR to install somewhere else, and
# $env:OBSIDINOTE_NO_SHORTCUTS = '1' to skip the shortcuts.

$ErrorActionPreference = 'Stop'
$repo = 'jgt87/ObsidiNote'
$dir = if ($env:OBSIDINOTE_DIR) { $env:OBSIDINOTE_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\ObsidiNote' }

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if ([Net.WebRequest]::DefaultWebProxy) { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials }

# The two things the installer itself needs. This file runs on its own (downloaded by install.ps1),
# so the status lines come after the files are in place, from the app's own lib\Status.psm1 (the
# same helper the start uses); a failure here stops with a plain message.
$psOk = $PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5
$langOk = $ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage'
if (-not $langOk) { throw "Constrained Language mode ($($ExecutionContext.SessionState.LanguageMode)) blocks ObsidiNote (AppLocker or WDAC). Ask IT whether scripts may run in Full Language mode." }
if (-not $psOk) {
    Write-Host "  Windows PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)): run this installer in Windows PowerShell 5.1 (powershell.exe), as shown in the README." -ForegroundColor Red
    return
}

Write-Host "Installing ObsidiNote into $dir" -ForegroundColor Cyan
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'ObsidiNote-installer' }
$asset = @($release.assets | Where-Object { $_.name -like 'ObsidiNote-*.zip' }) | Select-Object -First 1
$sumsAsset = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS' }) | Select-Object -First 1
if (-not $asset) { throw "The latest release ($($release.tag_name)) has no ObsidiNote zip." }

$tmp = Join-Path $env:TEMP ('obsidinote-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmp
try {
    $zip = Join-Path $tmp $asset.name
    Write-Host "Downloading $($release.tag_name)..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    if ($sumsAsset) {
        $sums = Join-Path $tmp 'SHA256SUMS'
        Invoke-WebRequest $sumsAsset.browser_download_url -OutFile $sums -UseBasicParsing
        $line = @(Get-Content -LiteralPath $sums | Where-Object { $_ -match ('\s\*?' + [regex]::Escape($asset.name) + '$') }) | Select-Object -First 1
        if (-not $line) { throw "SHA256SUMS does not list $($asset.name)." }
        $expected = ($line -split '\s+')[0].ToLowerInvariant()
        # .NET instead of Get-FileHash: that cmdlet is missing when 5.1 is started from pwsh 7.
        $sha = [Security.Cryptography.SHA256]::Create()
        $fs = [IO.File]::OpenRead($zip)
        try { $actual = (-join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') })) } finally { $fs.Dispose(); $sha.Dispose() }
        if ($actual -ne $expected) { throw "The download does not match SHA256SUMS ($($asset.name))." }
    }
    # .NET instead of Expand-Archive: when 5.1 is started from pwsh 7 it can load 7's Archive module and fail.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    $src = Join-Path $tmp 'ObsidiNote'
    $null = New-Item -ItemType Directory -Force -Path $dir
    # Mirror the release in; settings in config\*.local.json are kept.
    $null = & robocopy.exe $src $dir /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF '*.local.json' /XD '.git'
    if ($LASTEXITCODE -ge 8) { throw "copying files failed (robocopy code $LASTEXITCODE)" }
} finally {
    # A file still open (a virus scanner reading the zip) must not fail a finished install.
    try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Host "  (the download folder $tmp could not be removed yet; it can be deleted later)" -ForegroundColor DarkGray }
}

$targets = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'ObsidiNote.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ObsidiNote.lnk')
)
if ($env:OBSIDINOTE_NO_SHORTCUTS -eq '1') { $targets = @() }
if ($targets.Count) { $shell = New-Object -ComObject WScript.Shell }
foreach ($lnkPath in $targets) {
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $dir 'Start ObsidiNote.cmd'
    $lnk.WorkingDirectory = $dir
    $icon = Join-Path $dir 'assets\obsidinote.ico'
    if (Test-Path -LiteralPath $icon) { $lnk.IconLocation = $icon }
    $lnk.Description = 'ObsidiNote - a personal wiki that links itself'
    $lnk.Save()
}

Write-Host ''
# What ObsidiNote needs on this computer (it starts OneNote and opens Copilot in Edge at every start).
Write-Host 'This computer'
Import-Module (Join-Path $dir 'lib\Status.psm1') -Force
Write-Status 'OK' 'Windows PowerShell' "$($PSVersionTable.PSVersion)"
Write-Status 'OK' 'Language mode' "$($ExecutionContext.SessionState.LanguageMode)"
try {
    Import-Module (Join-Path $dir 'lib\OneNoteHost.psm1') -Force
    $oneNoteExe = Get-OneNoteExePath
    Write-Status $(if ($oneNoteExe) { 'OK' } else { 'FAIL' }) 'OneNote (desktop)' $(if ($oneNoteExe) { $oneNoteExe } else { 'not found: install or repair Microsoft 365 Office' })
} catch { Write-Status 'WARN' 'OneNote (desktop)' "not checked: $($_.Exception.Message)" }
try {
    Import-Module (Join-Path $dir 'lib\Cdp.psm1') -Force
    $edgeExe = try { Get-EdgePath } catch { '' }
    Write-Status $(if ($edgeExe) { 'OK' } else { 'FAIL' }) 'Microsoft Edge' $(if ($edgeExe) { $edgeExe } else { 'not found: ObsidiNote opens Copilot in Edge' })
} catch { Write-Status 'WARN' 'Microsoft Edge' "not checked: $($_.Exception.Message)" }
Write-Host ''
Write-Host "ObsidiNote $($release.tag_name) is installed." -ForegroundColor Green
Write-Host '  Start it:  ObsidiNote shortcut on the desktop or in the Start menu'
Write-Host '  Updates:   automatic each time ObsidiNote starts, or update.cmd in the ObsidiNote folder'
