# V1 This computer: the start checks of ObsidiNote (lib/StartChecks.psm1), the Edge policy values,
# the ports, OneNote installed and running, the versions, and the install folder against its
# manifest. Read only: opens no window and changes nothing.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
$script:AppLib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib'
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
foreach ($m in 'AppConfig', 'Cdp', 'OneNoteHost', 'StartChecks', 'Update', 'Server') { Import-Module (Join-Path $script:AppLib "$m.psm1") }

$script:Policies = @('BrowserSignin', 'RemoteDebuggingAllowed', 'DeveloperToolsAvailability', 'InPrivateModeAvailability', 'BrowserGuestModeEnabled')

function Get-AppVersionFromRoot([string]$AppRoot) {
    $f = Join-Path $AppRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $v = ([IO.File]::ReadAllText($f)).Trim()
    if ($v -and $v -notlike 'v*') { $v = "v$v" }
    $v
}

function Get-InstallKind([string]$AppRoot) {
    <# Where this copy of ObsidiNote lives, in words (no path). #>
    if (Test-Path -LiteralPath (Join-Path $AppRoot '.git')) { return 'a git clone' }
    $installed = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\ObsidiNote' } else { '' }
    if ($installed -and [string]::Equals($AppRoot.TrimEnd('\'), $installed, [StringComparison]::OrdinalIgnoreCase)) { return 'the installed folder (%LOCALAPPDATA%\Programs\ObsidiNote)' }
    'an unpacked release folder'
}

function Get-FileVersionText([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    try { "$((Get-Item -LiteralPath $Path).VersionInfo.ProductVersion)" } catch { '' }
}

function Add-StartCheckResults($Ctx) {
    $checks = Measure-KitStep { Get-StartChecks -AppRoot $Ctx.AppRoot }
    if (-not $checks.ok) { Add-ValidationResult $Ctx 'V1' 'FAIL' 'Start checks' "could not run: $($checks.error)"; return }
    foreach ($c in @($checks.value)) {
        $hint = if ($c.status -ne 'OK') { $c.hint } else { '' }
        Add-ValidationResult $Ctx 'V1' $c.status $c.name $c.detail $hint
    }
}

function Add-PolicyResult($Ctx) {
    $parts = @(foreach ($p in $script:Policies) {
            $v = Get-EdgePolicyValue $p
            "$p = $(if ($null -eq $v) { 'not set' } else { "$v" })"
        })
    Add-ValidationResult $Ctx 'V1' 'INFO' 'Edge policy values' ($parts -join '; ')
}

function Add-UiPortResult($Ctx) {
    $port = 0
    try { $port = Get-UiPort -AppRoot $Ctx.AppRoot } catch { Add-ValidationResult $Ctx 'V1' 'FAIL' 'Window port' $_.Exception.Message; return }
    $name = "Port $port (window)"
    if (Test-UiServerRunning -Port $port) { Add-ValidationResult $Ctx 'V1' 'INFO' $name 'ObsidiNote is running on it'; return }
    if (Test-PortListening $port) {
        Add-ValidationResult $Ctx 'V1' 'WARN' $name 'in use by another program' 'Choose another port: { "uiPort": 8790 } in config\obsidinote.local.json.'
        return
    }
    Add-ValidationResult $Ctx 'V1' 'OK' $name 'free'
}

function Add-OneNoteRunResult($Ctx) {
    $state = Get-OneNoteState
    $ver = Get-FileVersionText (Get-OneNoteExePath)
    $v = if ($ver) { "; version $ver" } else { '' }
    switch ($state) {
        'window' { Add-ValidationResult $Ctx 'V1' 'OK' 'OneNote running' "with a window$v" }
        'background' { Add-ValidationResult $Ctx 'V1' 'WARN' 'OneNote running' "in the background only (no window)$v" 'Open OneNote yourself so its window shows your notebooks.' }
        default { Add-ValidationResult $Ctx 'V1' 'WARN' 'OneNote running' "not running$v" 'Open OneNote before stage V2 (it reads your notebooks there).' }
    }
}

function Add-InstallResult($Ctx) {
    $ver = Get-AppVersionFromRoot $Ctx.AppRoot
    $edge = try { Get-FileVersionText (Get-EdgePath) } catch { '' }
    Add-ValidationResult $Ctx 'V1' 'INFO' 'ObsidiNote version' "$(if ($ver) { $ver } else { 'unknown' }) in $(Get-InstallKind $Ctx.AppRoot)$(if ($edge) { "; Edge $edge" })"
    $r = Measure-KitStep { Test-InstallIntegrity -AppRoot $Ctx.AppRoot }
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V1' 'WARN' 'Install folder' "not checked: $($r.error)"; return }
    if ($null -eq $r.value) { Add-ValidationResult $Ctx 'V1' 'INFO' 'Install folder' 'no manifest.json (a development copy): not compared'; return }
    $problem = Format-InstallProblem $r.value
    if ($problem) { Add-ValidationResult $Ctx 'V1' 'WARN' 'Install folder' $problem 'Run update.cmd, or tools\update.ps1 -Repair, then run the kit again.'; return }
    $count = 0
    try { $count = @((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $Ctx.AppRoot 'manifest.json')))).files.PSObject.Properties).Count } catch { }
    Add-ValidationResult $Ctx 'V1' 'OK' 'Install folder' "all $count files as released ($($r.value.version)); checked in $($r.ms) ms"
}

function Invoke-StageComputer {
    param([Parameter(Mandatory)]$Ctx)
    Add-StartCheckResults $Ctx
    Add-PolicyResult $Ctx
    Add-UiPortResult $Ctx
    Add-OneNoteRunResult $Ctx
    Add-InstallResult $Ctx
}

Export-ModuleMember -Function Invoke-StageComputer, Get-AppVersionFromRoot, Get-InstallKind
