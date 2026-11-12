<#
.SYNOPSIS
    Turns on single sign-on with your Windows work account in ObsidiNote's Edge profile, so Copilot
    signs in by itself after a restart (no password stored anywhere).
.DESCRIPTION
    Checks this PC (joined to Microsoft Entra ID with a work account token; dsregcmd /status, only
    its yes/no fields), opens ObsidiNote's Edge (debug port "cdpPort", 9334 by default) when it is
    not running, finds Edge's switch "Allow single sign-on for work or school sites using this
    profile" in ObsidiNote's Edge profile and turns it on after you confirm (-Yes skips the
    question). Writes %LOCALAPPDATA%\ObsidiNote\logs\ObsidiNote-sso-<date>.txt: what was found and
    which of Edge's sign-in settings changed (names and yes/no values only; no account names, ids,
    addresses or tokens). Only ObsidiNote's own profile is touched; your normal Edge and Edge
    policies stay as they are. -Off turns it off.
.EXAMPLE
    sso-setup.cmd
    sso-setup.cmd -Yes
    sso-setup.cmd -Off
#>
param([switch]$Yes, [switch]$Off)

$ErrorActionPreference = 'Stop'
# Windows PowerShell's own module paths: started from PowerShell 7, 5.1 would load 7's modules.
$env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')) | Where-Object { $_ }) -join ';'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
foreach ($m in 'Log', 'AppConfig', 'Cdp', 'CopilotBridge', 'Sso') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
$own = Get-CopilotSettings -AppRoot $root
$sel = Get-CopilotSelectors -AppRoot $root
try { $null = Start-CdpEdge -Port $own.cdpPort -ProfileDir $own.profileDir -Url $sel.chatUrl }
catch { Write-Host "ObsidiNote's Edge could not be opened: $($_.Exception.Message)" -ForegroundColor Yellow }
$word = if ($Off) { 'off' } else { 'on' }
$confirm = if ($Yes) { $null } else { { (Read-Host "Turn single sign-on for work or school sites $word in ObsidiNote's Edge profile? (y/n)") -match '^(y|j)' } }
$r = Invoke-SsoSetup -Port $own.cdpPort -ProfileDir $own.profileDir -On (-not $Off) -Confirm $confirm
foreach ($l in $r.Lines) { Write-Host $l }
# The log holds the lines above only: names and yes/no values, no content.
$logDir = Join-Path (Get-AppDataDir) 'logs'
$null = New-Item -ItemType Directory -Force -Path $logDir
$file = Join-Path $logDir "ObsidiNote-sso-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
[IO.File]::WriteAllLines($file, [string[]]$r.Lines)
Write-Host ''
Write-Host "Result: $($r.Result). Log: $file (send it if something did not work)" -ForegroundColor $(if ($r.Result -in 'turned on', 'already on', 'signed-in-work', 'turned off', 'already off') { 'Green' } else { 'Yellow' })
