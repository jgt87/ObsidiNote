#requires -Version 5.1
# ObsidiNote validation kit: runs the checks of this computer, OneNote, Copilot, the window, the
# grounding probes and (from the release with vaults, Add and Ask) the vault checks, one status line
# per check, and writes one log that is safe to send back:
#   <Desktop>\ObsidiNote-validation-<yyyyMMdd-HHmm>.txt  (and a .json summary next to it)
# The log holds status lines, counts and timings only (see validation/lib/ValidationCore.psm1).
# Steps for people: docs/runbooks/RB-03-run-validation.md.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File validation\Run-Validation.ps1 [-Stage V1,V2,...]
#     [-WriteTest] [-NoCopilot] [-NoPrompt] [-TestPort <n>] [-ProbeBasePath <OneDrive Documents URL>]
#     [-PublicUrl <url>] [-SharePointUrl <url>] [-OneDriveUrl <url>] [-OutDir <folder>]
[CmdletBinding()]
param(
    [string[]]$Stage = @(),       # V1..V6, e.g. -Stage V1,V3; all stages when left out
    [switch]$WriteTest,           # also the write tests, ONLY in the notebooks ObsidiNote-Probe and ObsidiNote-Validation
    [switch]$NoCopilot,           # no Copilot: V3, V5 and the Copilot parts of V6 are skipped (no Edge window opens)
    [switch]$NoPrompt,            # ask nothing (P1c manual move, P4, P7 are skipped)
    [int]$TestPort = 0,           # V4's test port (default 18768 and up; never ObsidiNote's own port)
    [string]$ProbeBasePath = '',  # where ObsidiNote-Probe is created (default: next to the first OneDrive notebook)
    [string]$PublicUrl = '',      # P8's public address (default: a public documentation page)
    [string]$SharePointUrl = '',  # P7 without the question (not logged)
    [string]$OneDriveUrl = '',    # P7 without the question (not logged)
    [string]$OutDir = ''          # where the log goes (default: the Desktop)
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell's own module paths: started from PowerShell 7, 5.1 would load 7's modules.
$env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')) | Where-Object { $_ }) -join ';'
$appRoot = Split-Path -Parent $PSScriptRoot
$kitLib = Join-Path $PSScriptRoot 'lib'
foreach ($m in 'ValidationCore', 'StageComputer', 'StageOneNote', 'StageWindow', 'StageCopilot', 'StageGrounding', 'StageVault') {
    Import-Module (Join-Path $kitLib "$m.psm1") -Force
}

try { $stages = Get-ValidationStages -Requested $Stage }
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }

if (-not $OutDir) { $OutDir = [Environment]::GetFolderPath('Desktop') }
if (-not $OutDir -or -not (Test-Path -LiteralPath $OutDir)) { $OutDir = $env:TEMP }
$stamp = (Get-Date).ToString('yyyyMMdd-HHmm')
$logPath = Join-Path $OutDir "ObsidiNote-validation-$stamp.txt"
$jsonPath = [IO.Path]::ChangeExtension($logPath, '.json')
if (Test-Path -LiteralPath $logPath) { [IO.File]::Delete($logPath) }

$flags = @{
    WriteTest = [bool]$WriteTest; NoCopilot = [bool]$NoCopilot; NoPrompt = [bool]$NoPrompt
    TestPort = $TestPort; ProbeBasePath = $ProbeBasePath; PublicUrl = $PublicUrl; SharePointUrl = $SharePointUrl; OneDriveUrl = $OneDriveUrl
}
$ctx = New-ValidationContext -AppRoot $appRoot -LogPath $logPath -Stages $stages -Flags $flags
$appVersion = Get-AppVersionFromRoot $appRoot
foreach ($l in (Get-ValidationHeader -Ctx $ctx -AppVersion $appVersion)) { Write-ValidationLine $ctx $l }
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-ValidationLine $ctx 'Note: run this kit with Windows PowerShell 5.1 (Run Validation.cmd does that); OneNote COM does not work from PowerShell 7.' 'Yellow'
}

$runners = @{
    V1 = { Invoke-StageComputer -Ctx $ctx }; V2 = { Invoke-StageOneNote -Ctx $ctx }; V3 = { Invoke-StageCopilot -Ctx $ctx }
    V4 = { Invoke-StageWindow -Ctx $ctx }; V5 = { Invoke-StageGrounding -Ctx $ctx }; V6 = { Invoke-StageVault -Ctx $ctx }
}
try {
    foreach ($s in $stages) {
        Write-ValidationLine $ctx ''
        Write-ValidationLine $ctx "$s $(Get-StageTitle $s)" 'White'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { & $runners[$s] }
        catch { Add-ValidationResult $ctx $s 'FAIL' 'Stage' "stopped: $($_.Exception.Message)" }
        Write-ValidationLine $ctx "  ($s took $([Math]::Round($sw.Elapsed.TotalSeconds, 1)) s)" 'DarkGray'
    }
} finally {
    Close-KitCopilot -Ctx $ctx
    foreach ($l in (Get-ValidationFooter -Ctx $ctx)) { Write-ValidationLine $ctx $l }
    try { [IO.File]::WriteAllText($jsonPath, (ConvertTo-ValidationJson -Ctx $ctx -AppVersion $appVersion), (New-Object Text.UTF8Encoding($false))) } catch { }
    Write-Host ''
    Write-Host "Log:     $logPath"
    Write-Host "Summary: $jsonPath"
    Write-Host 'Both files hold status lines, counts and timings only. Send both back.'
}
$summary = Get-ValidationSummary $ctx
if ($summary.result -eq 'FAIL') { exit 1 }
exit 0
