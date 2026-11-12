#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Name = 'World',
    [switch]$DryRun,
    [switch]$NoUpdate   # skip the update check (also: environment variable OBSIDINOTE_NO_UPDATE=1)
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell's own module paths: started from PowerShell 7, 5.1 would load 7's modules.
$env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')) | Where-Object { $_ }) -join ';'
if ($env:OBSIDINOTE_NO_UPDATE -eq '1') { $NoUpdate = $true }

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

Import-Module (Join-Path $PSScriptRoot 'lib\Core.psm1') -Force

# App data lives in %LOCALAPPDATA%\ObsidiNote, never next to the script.
$dataDir = Join-Path $env:LOCALAPPDATA 'ObsidiNote'
if ($DryRun) {
    Write-Host "[dry-run] would write to $dataDir"
}

(Get-Greeting -Name $Name) | ConvertTo-Json -Compress
