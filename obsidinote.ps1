#requires -Version 5.1
# The start, in this order; each step prints one status line ([OK]/[WARN]/[FAIL], lib/Status.psm1):
#   1. Update: check for a new release; when one was installed, start the new version instead
#      (same arguments) and end this one.
#   2. This computer: PowerShell, OneNote, Edge and its policies, the debug port, the Edge profile's
#      sign-in and single sign-on, GitHub. A FAIL ends the start with what to do (exit 1).
#   3. OneNote: open the notebook on record (or start OneNote) and wait for its COM API (exit 2).
#   4. Microsoft 365 Copilot in ObsidiNote's own Edge profile (exit 3), then the interface (later).
# Status lines and messages go to stderr: stdout carries ObsidiNote's own output.
[CmdletBinding()]
param(
    [string]$Name = 'World',
    [switch]$DryRun,
    [switch]$NoUpdate,  # skip the update check (also: environment variable OBSIDINOTE_NO_UPDATE=1)
    [switch]$NoOneNote,  # skip the OneNote start and check (tests, update-only runs)
    [switch]$NoCopilot   # skip connecting to Microsoft 365 Copilot (also: OBSIDINOTE_NO_COPILOT=1)
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell's own module paths: started from PowerShell 7, 5.1 would load 7's modules.
$env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')) | Where-Object { $_ }) -join ';'
if ($env:OBSIDINOTE_NO_UPDATE -eq '1') { $NoUpdate = $true }
if ($env:OBSIDINOTE_NO_COPILOT -eq '1') { $NoCopilot = $true }
$bound = @{}; foreach ($k in $PSBoundParameters.Keys) { $bound[$k] = $PSBoundParameters[$k] }
Import-Module (Join-Path $PSScriptRoot 'lib\Status.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Startup.psm1') -Force
function Say([string]$Text) { [Console]::Error.WriteLine("[ObsidiNote] $Text") }

# --- 1. Update -------------------------------------------------------------------------------
# Before anything else is loaded (GitHub; skipped offline, for local edits or "autoUpdate": false).
# The updater never fails this script; -PassThru hands back its outcome for the status line.
[Console]::Error.WriteLine('Update')
if ($env:OBSIDINOTE_UPDATED) {
    # Started by the previous version right after it installed this one.
    Write-Status -ToError 'OK' 'Update' "$env:OBSIDINOTE_UPDATED; this is the new version"
    Remove-Item Env:\OBSIDINOTE_UPDATED -ErrorAction SilentlyContinue
} elseif ($NoUpdate) {
    Write-Status -ToError 'OK' 'Update' 'not checked (-NoUpdate or OBSIDINOTE_NO_UPDATE=1)'
} else {
    $updateResult = @(& (Join-Path $PSScriptRoot 'tools\update.ps1') -PassThru) | Where-Object { $_ -and $_.PSObject.Properties['outcome'] } | Select-Object -Last 1
    $u = Get-UpdateStatus $updateResult
    Write-Status -ToError $u.status 'Update' $u.detail
    if ($u.relaunch) {
        # The files on disk are the new version now: run it (same arguments) and end this one.
        $env:OBSIDINOTE_UPDATED = "$(if ($updateResult.outcome -eq 'repaired') { 'repaired' } else { 'updated' }) $($updateResult.detail)"
        $relaunch = Get-RelaunchArguments -Script $PSCommandPath -Bound $bound
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @relaunch } finally { $ErrorActionPreference = $eap }
        exit $LASTEXITCODE
    }
}
# Is the app folder the release as shipped (manifest.json)? An update that stopped halfway leaves
# files missing or of another version: repair it once (the same version again), else say so.
try {
    Import-Module (Join-Path $PSScriptRoot 'lib\Update.psm1') -Force
    $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
    if ($installProblem) {
        Write-Status -ToError 'WARN' 'Install' $installProblem
        if (-not $NoUpdate) {
            & (Join-Path $PSScriptRoot 'tools\update.ps1') -Repair
            $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
            if (-not $installProblem) { Write-Status -ToError 'OK' 'Install' 'repaired' }
        }
    }
} catch { Write-Status -ToError 'WARN' 'Install' "not checked: $($_.Exception.Message)" }

# --- 2. This computer --------------------------------------------------------------------------
[Console]::Error.WriteLine('This computer')
Import-Module (Join-Path $PSScriptRoot 'lib\StartChecks.psm1') -Force
$checks = Get-StartChecks -AppRoot $PSScriptRoot -NoOneNote:$NoOneNote -NoCopilot:$NoCopilot
foreach ($c in $checks) { Write-Status -ToError $c.status $c.name $c.detail -Hint $(if ($c.status -ne 'OK' -or $c.name -eq 'Edge profile') { $c.hint } else { '' }) }
if (@($checks | Where-Object { $_.status -eq 'FAIL' }).Count) {
    Say 'ObsidiNote cannot start until the FAIL items above are fixed.'
    exit 1
}

# --- 3. OneNote --------------------------------------------------------------------------------
# OneNote is the only store. When it is not running, ObsidiNote opens the notebook on record
# ("notebook" in config\obsidinote.local.json), so OneNote starts with that notebook open; the
# record is filled in once the notebook is found.
[Console]::Error.WriteLine('Starting')
if (-not $NoOneNote) {
    Import-Module (Join-Path $PSScriptRoot 'lib\AppConfig.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\OneNoteHost.psm1') -Force
    $record = Get-NotebookRecord -AppRoot $PSScriptRoot
    $oneNote = Start-OneNoteIfNeeded -Record $record
    if ($oneNote.foundRecord -and $oneNote.foundRecord -ne $record) {
        try { Set-LocalAppValue $PSScriptRoot 'notebook' $oneNote.foundRecord; $oneNote.warn = '' } catch { $oneNote.warn = "the notebook's location could not be saved: $($_.Exception.Message)" }
    }
    $on = Get-OneNoteStatus $oneNote
    Write-Status -ToError $on.status 'OneNote' $on.detail -Hint $on.hint
    if ($on.status -eq 'FAIL') { exit 2 }
}

# --- 4. Microsoft 365 Copilot and the interface -----------------------------------------------
# Copilot in ObsidiNote's own Edge window (debug port "cdpPort", 9334 by default; profile
# %LOCALAPPDATA%\ObsidiNote\edge-profile; "signIn" single-sign-on or private). Connect-Copilot waits
# up to 300 s for a sign-in. Without Copilot ObsidiNote cannot classify or link: exit 3.
$copilot = $null
if (-not $NoCopilot) {
    Import-Module (Join-Path $PSScriptRoot 'lib\CopilotBridge.psm1') -Force
    # Edge policy BrowserSignin = 2 and ObsidiNote's Edge profile not signed in yet: Edge closes the
    # Copilot window at once. Let Edge run its own sign-in first (one time), then connect.
    Import-Module (Join-Path $PSScriptRoot 'lib\Cdp.psm1') -Force
    $cs = Get-CopilotSettings
    if ((Test-EdgeForcedSignIn) -and (Get-EdgeProfileAccount -ProfileDir $cs.profileDir) -ne 'work') {
        $signIn = Invoke-EdgeProfileSignIn -ProfileDir $cs.profileDir -Port ([int]$cs.cdpPort) -OnWait {
            Write-Status -ToError 'WARN' 'Edge sign-in' 'one time: sign in to Edge with your work account' -Hint 'Edge on this PC requires it. In the Edge window that just opened, sign in with your work account (waiting up to 5 minutes; ObsidiNote continues by itself).'
        }
        Write-Status -ToError $(if ($signIn.ok) { 'OK' } else { 'FAIL' }) 'Edge sign-in' $signIn.detail
        if (-not $signIn.ok) { exit 3 }
    }
    Say 'Opening Microsoft 365 Copilot in ObsidiNote''s Edge window...'
    try { $copilot = Connect-Copilot }
    catch {
        $why = $_.Exception.Message
        $sso = ''
        try { Import-Module (Join-Path $PSScriptRoot 'lib\Sso.psm1') -Force; $sso = Get-ProfileSsoState } catch { }
        Write-Status -ToError 'FAIL' 'Copilot' $why -Hint (Get-CopilotFailureHint -Message $why -Sso $sso)
        exit 3
    }
    Write-Status -ToError 'OK' 'Copilot' "connected in ObsidiNote's Edge window (port $($copilot.Port))"
}
# The interface: ObsidiNote has no web UI yet. When it exists, open it here, in ObsidiNote's Edge
# window next to Copilot (the model is the sister project's Start-AppWindow: a tab in the Copilot
# window by default, side by side, or the default browser), once its local server listens.
Write-Status -ToError 'OK' 'ObsidiNote' $(if ($copilot) { 'ready; no interface yet (Copilot is open in ObsidiNote''s Edge window)' } else { 'ready; no interface yet' })

try {
    Import-Module (Join-Path $PSScriptRoot 'lib\Core.psm1') -Force

    # App data lives in %LOCALAPPDATA%\ObsidiNote, never next to the script.
    $dataDir = Join-Path $env:LOCALAPPDATA 'ObsidiNote'
    if ($DryRun) {
        Write-Host "[dry-run] would write to $dataDir"
    }

    (Get-Greeting -Name $Name) | ConvertTo-Json -Compress
} finally {
    # The bridge ($copilot) is kept for the steps that will use it; the demo flow ends here.
    if ($copilot) { try { Disconnect-Copilot $copilot } catch { } }
}
