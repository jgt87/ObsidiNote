# What this computer needs, checked at every start of obsidinote.ps1 (read only, a few seconds):
# Windows PowerShell 5.1 in Full Language mode, desktop OneNote, Microsoft Edge and its policies,
# the debug port of ObsidiNote's Edge, the Edge profile's sign-in and single sign-on, and GitHub
# (for updates; informational). Each check returns @{ status; name; detail; hint }: OK, WARN or
# FAIL; a FAIL stops the start. Nothing is changed here, and no Edge window is opened.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
foreach ($m in 'AppConfig', 'Cdp', 'OneNoteHost', 'Sso') { Import-Module (Join-Path $PSScriptRoot "$m.psm1") }

function New-StartCheck([string]$Status, [string]$Name, [string]$Detail, [string]$Hint = '') {
    [pscustomobject]@{ status = $Status; name = $Name; detail = $Detail; hint = $Hint }
}

function Get-PowerShellCheck {
    param([string]$Edition = "$($PSVersionTable.PSEdition)", [version]$Version = $PSVersionTable.PSVersion)
    if ($Edition -eq 'Desktop' -and $Version.Major -eq 5 -and $Version.Minor -ge 1) { return New-StartCheck 'OK' 'Windows PowerShell' "$Version" }
    New-StartCheck 'FAIL' 'Windows PowerShell' "$Edition $Version" 'Start ObsidiNote with Windows PowerShell 5.1 (Start ObsidiNote.cmd does that).'
}

function Get-LanguageModeCheck {
    param([string]$Mode = "$($ExecutionContext.SessionState.LanguageMode)")
    if ($Mode -eq 'FullLanguage') { return New-StartCheck 'OK' 'Language mode' $Mode }
    New-StartCheck 'FAIL' 'Language mode' $Mode 'Constrained Language mode (AppLocker or WDAC) blocks ObsidiNote. Ask IT whether scripts may run in Full Language mode.'
}

function Get-OneNoteInstallCheck {
    $exe = Get-OneNoteExePath
    if ($exe) { return New-StartCheck 'OK' 'OneNote (desktop)' 'installed' }
    New-StartCheck 'FAIL' 'OneNote (desktop)' 'not found' 'Install or repair Microsoft 365 Office (desktop OneNote); ObsidiNote keeps everything in OneNote.'
}

function Get-EdgeInstallCheck {
    $edge = try { Get-EdgePath } catch { '' }
    if ($edge) { return New-StartCheck 'OK' 'Microsoft Edge' 'installed' }
    New-StartCheck 'FAIL' 'Microsoft Edge' 'msedge.exe not found' 'ObsidiNote opens Microsoft 365 Copilot in Edge; install or repair Edge.'
}

function Get-EdgePolicyCheck {
    <# The Edge policies that decide whether ObsidiNote can drive Copilot: the debug port
       (RemoteDebuggingAllowed, DeveloperToolsAvailability) and forced browser sign-in (BrowserSignin). #>
    $block = Get-EdgeDebugBlock
    if ($block) { return New-StartCheck 'FAIL' 'Edge policies' $block 'ObsidiNote needs the debug port to drive Copilot; ask IT to allow it.' }
    if (Test-EdgeForcedSignIn) { return New-StartCheck 'OK' 'Edge policies' 'debug port allowed; Edge requires signing in to the browser (BrowserSignin = 2)' }
    New-StartCheck 'OK' 'Edge policies' 'debug port allowed'
}

function Get-CdpPortCheck {
    <# The debug port is free, or already ObsidiNote's own Edge. Edge holding ObsidiNote's profile
       without the port is a FAIL: starting Edge again would only open another window. #>
    param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$ProfileDir)
    $name = "Port $Port (Edge)"
    $use = Get-EdgeProfileUse -ProfileDir $ProfileDir -Port $Port
    if ($use.state -eq 'no-debug') {
        return New-StartCheck 'FAIL' $name "ObsidiNote's Edge profile is open in an Edge window without this debug port" 'Close every window of ObsidiNote''s Edge (the one that shows Copilot for ObsidiNote; also check the taskbar), then start ObsidiNote again.'
    }
    if (-not (Test-PortListening $Port)) { return New-StartCheck 'OK' $name 'free' }
    if ($use.state -eq 'debug' -and (Test-CdpEndpoint $Port)) { return New-StartCheck 'OK' $name "ObsidiNote's Edge is already running" }
    if ($use.state -eq 'debug') { return New-StartCheck 'OK' $name "ObsidiNote's Edge is starting" }
    New-StartCheck 'FAIL' $name 'in use by another program' 'Choose another port: { "cdpPort": 9345 } in config\obsidinote.local.json.'
}

function Get-EdgeProfileSummary {
    <# The Edge profile line, pure: account ('work', 'personal', 'none', 'unknown'), single sign-on
       ('on', 'off', 'unavailable'), the signIn setting and forced browser sign-in. #>
    param([string]$Account, [string]$Sso, [string]$SignInMode = 'single-sign-on', [bool]$ForcedSignIn = $false)
    $who = switch ($Account) { 'work' { 'signed in with a work account' } 'personal' { 'signed in with a personal Microsoft account' } 'none' { 'not signed in' } default { 'not signed in (new profile)' } }
    $ssoText = switch ($Sso) { 'on' { 'SSO on' } 'off' { 'SSO off' } default { 'SSO unavailable (no work account token on this PC)' } }
    $detail = "$who; $ssoText"
    if ($SignInMode -eq 'private') { return New-StartCheck 'OK' 'Edge profile' "$detail; sign-in: private session (you sign in each time)" }
    if ($ForcedSignIn -and $Account -ne 'work') {
        return New-StartCheck 'WARN' 'Edge profile' $detail 'Edge on this PC requires signing in to the browser: when ObsidiNote''s Edge window asks, sign in to Edge with your work account.'
    }
    if ($Sso -eq 'off') { return New-StartCheck 'WARN' 'Edge profile' $detail 'Run sso-setup.cmd once so Copilot signs in by itself.' }
    if ($Sso -eq 'unavailable' -and $Account -ne 'work') { return New-StartCheck 'OK' 'Edge profile' $detail 'Sign in to Copilot once in ObsidiNote''s Edge window and choose "Stay signed in".' }
    New-StartCheck 'OK' 'Edge profile' $detail
}

function Get-EdgeProfileCheck {
    param([Parameter(Mandatory)][string]$ProfileDir, [string]$SignInMode = 'single-sign-on')
    $join = Get-DeviceJoinStatus
    $account = Get-ProfileAccount -ProfileDir $ProfileDir
    $sso = Get-ProfileSsoState -ProfileDir $ProfileDir -Join $join -Account $account
    Get-EdgeProfileSummary -Account $account -Sso $sso -SignInMode $SignInMode -ForcedSignIn (Test-EdgeForcedSignIn)
}

function Test-GitHubReachable {
    try { $null = Invoke-WebRequest 'https://api.github.com' -Method Head -UseBasicParsing -TimeoutSec 5 -Headers @{ 'User-Agent' = 'ObsidiNote-check' }; $true } catch { $false }
}

function Get-GitHubCheck {
    if (Test-GitHubReachable) { return New-StartCheck 'OK' 'GitHub' 'reachable (updates)' }
    New-StartCheck 'WARN' 'GitHub' 'not reachable: updates are skipped until it is' ''
}

function Invoke-SafeCheck([string]$Name, [scriptblock]$Check) {
    # A check that throws is reported, never ends the start by itself.
    try { & $Check } catch { New-StartCheck 'WARN' $Name "not checked: $($_.Exception.Message)" }
}

function Get-StartChecks {
    <# All start checks in order. -NoOneNote leaves out OneNote, -NoCopilot the Edge checks. #>
    param([string]$AppRoot, [switch]$NoOneNote, [switch]$NoCopilot, [switch]$NoNetwork)
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add((Get-PowerShellCheck))
    $out.Add((Get-LanguageModeCheck))
    if (-not $NoOneNote) { $out.Add((Invoke-SafeCheck 'OneNote (desktop)' { Get-OneNoteInstallCheck })) }
    if (-not $NoCopilot) {
        $own = Get-CopilotSettings -AppRoot $AppRoot
        $mode = Get-CopilotSignInMode -AppRoot $AppRoot
        $out.Add((Invoke-SafeCheck 'Microsoft Edge' { Get-EdgeInstallCheck }))
        $out.Add((Invoke-SafeCheck 'Edge policies' { Get-EdgePolicyCheck }))
        $out.Add((Invoke-SafeCheck "Port $($own.cdpPort) (Edge)" { Get-CdpPortCheck -Port $own.cdpPort -ProfileDir $own.profileDir }))
        $out.Add((Invoke-SafeCheck 'Edge profile' { Get-EdgeProfileCheck -ProfileDir $own.profileDir -SignInMode $mode }))
    }
    if (-not $NoNetwork) { $out.Add((Invoke-SafeCheck 'GitHub' { Get-GitHubCheck })) }
    , $out.ToArray()
}

Export-ModuleMember -Function New-StartCheck, Get-PowerShellCheck, Get-LanguageModeCheck, Get-OneNoteInstallCheck, Get-EdgeInstallCheck, Get-EdgePolicyCheck, Get-CdpPortCheck, Get-EdgeProfileSummary, Get-EdgeProfileCheck, Test-GitHubReachable, Get-GitHubCheck, Get-StartChecks
