#requires -Version 5.1
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

# Update before anything is loaded (GitHub; skipped offline, for local edits or "autoUpdate": false).
# The updater never fails this script and writes only to stderr.
if (-not $NoUpdate) { & (Join-Path $PSScriptRoot 'tools\update.ps1') }
# Is the app folder the release as shipped (manifest.json)? An update that stopped halfway leaves
# files missing or of another version: repair it once (the same version again), else say so.
try {
    Import-Module (Join-Path $PSScriptRoot 'lib\Update.psm1') -Force
    $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
    if ($installProblem) {
        [Console]::Error.WriteLine($installProblem)
        if (-not $NoUpdate) {
            [Console]::Error.WriteLine('Repairing it: installing the same version again...')
            & (Join-Path $PSScriptRoot 'tools\update.ps1') -Repair
            $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
            if (-not $installProblem) { [Console]::Error.WriteLine('Repaired.') }
        }
    }
} catch { [Console]::Error.WriteLine("The install check did not run: $($_.Exception.Message)") }

# OneNote is the only store: start desktop OneNote when it is not running and wait until its COM
# API answers. Without it ObsidiNote has nothing to read, so a failure ends the start here.
if (-not $NoOneNote) {
    Import-Module (Join-Path $PSScriptRoot 'lib\OneNoteHost.psm1') -Force
    $oneNote = Start-OneNoteIfNeeded
    [Console]::Error.WriteLine("[ObsidiNote] $($oneNote.message)")
    if (-not $oneNote.ok) { exit 2 }
}

# Microsoft 365 Copilot in ObsidiNote's own Edge window (debug port "cdpPort", 9334 by default;
# profile %LOCALAPPDATA%\ObsidiNote\edge-profile). Connect-Copilot waits up to 300 s for the person
# to sign in. Without Copilot ObsidiNote cannot classify or link, so a failure ends the start here.
$copilot = $null
if (-not $NoCopilot) {
    Import-Module (Join-Path $PSScriptRoot 'lib\CopilotBridge.psm1') -Force
    [Console]::Error.WriteLine('[ObsidiNote] Opening Microsoft 365 Copilot...')
    try { $copilot = Connect-Copilot }
    catch {
        [Console]::Error.WriteLine("[ObsidiNote] Could not connect to Microsoft 365 Copilot: $($_.Exception.Message)")
        [Console]::Error.WriteLine('[ObsidiNote] Sign in once in the Edge window ObsidiNote opens, then start ObsidiNote again (or start it with -NoCopilot).')
        exit 3
    }
    [Console]::Error.WriteLine('[ObsidiNote] Copilot is connected.')
}

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
