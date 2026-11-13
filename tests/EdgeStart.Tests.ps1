# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Starting ObsidiNote's Edge and connecting to Copilot (lib/Cdp.psm1 Start-CdpEdge, lib/CopilotBridge.psm1
# Connect-Copilot): never a second Edge window for the same profile, a clear stop when Edge holds
# the profile without the debug port or policy forces a browser sign-in, and a sign-in redirect
# (the tab's connection closes) leads to another attempt. No Edge, no network: every process,
# CDP and HTTP call is a stand-in.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Cdp.psm1') -Force
Import-Module (Join-Path $root 'lib\CopilotBridge.psm1') -Force

Describe 'Is Edge already running with ObsidiNote''s profile (Get-EdgeProfileUse)' {
    $dir = 'D:\AppData\ObsidiNote\edge-profile'
    $p = { param($cl) [pscustomobject]@{ ProcessId = 7; CommandLine = $cl } }
    It 'is none without an Edge for this profile (the normal Edge does not count)' {
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @()).state | Should Be 'none'
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p '"msedge.exe" --profile-directory=Default'))).state | Should Be 'none'
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --remote-debugging-port=9333 --user-data-dir=`"D:\AppData\OtherTool\edge-profile`""))).state | Should Be 'none'
    }
    It 'is debug when its browser process has --remote-debugging-port=9334 (quoted or not)' {
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --remote-debugging-port=9334 --user-data-dir=`"$dir`" --no-first-run"))).state | Should Be 'debug'
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --user-data-dir=$dir --remote-debugging-port=9334"))).state | Should Be 'debug'
    }
    It 'is no-debug when Edge holds the profile without that port (or with another one)' {
        $u = Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --user-data-dir=`"$dir`" https://m365.cloud.microsoft/chat"))
        $u.state | Should Be 'no-debug'
        @($u.pids).Count | Should Be 1
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --remote-debugging-port=9400 --user-data-dir=`"$dir`""))).state | Should Be 'no-debug'
    }
    It 'looks only at the browser process, not its helpers (renderer, gpu)' {
        $procs = @((& $p "msedge.exe --type=renderer --user-data-dir=`"$dir`""), (& $p "msedge.exe --type=gpu-process --user-data-dir=`"$dir`""))
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes $procs).state | Should Be 'none'
        $procs += (& $p "msedge.exe --remote-debugging-port=9334 --user-data-dir=`"$dir`"")
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes $procs).state | Should Be 'debug'
    }
    It 'does not take a profile whose folder only starts the same way' {
        (Get-EdgeProfileUse -ProfileDir $dir -Port 9334 -Processes @((& $p "msedge.exe --user-data-dir=`"$dir-old`""))).state | Should Be 'none'
    }
}

Describe 'Start-CdpEdge never opens a second Edge window for the profile' {
    # Mocks cannot see Describe variables in Pester 3.4: the profile folder is global.
    $global:obsnProf = Join-Path $env:TEMP ('obsn-edge-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); $prof = $global:obsnProf
    Mock -ModuleName Cdp Get-EdgePath { 'C:\fake\msedge.exe' }
    Mock -ModuleName Cdp Start-Sleep { }
    Mock -ModuleName Cdp Get-EdgeDebugBlock { '' }

    It 'stops with a no-retry error, without starting Edge, when Edge holds the profile without the debug port' {
        Mock -ModuleName Cdp Test-CdpEndpoint { $false }
        Mock -ModuleName Cdp Start-Process { [pscustomobject]@{ Id = 1 } }
        Mock -ModuleName Cdp Get-EdgeBrowserProcesses { @([pscustomobject]@{ ProcessId = 5; CommandLine = "msedge.exe --user-data-dir=`"$global:obsnProf`"" }) }
        $err = $null
        try { Start-CdpEdge -Port 9334 -ProfileDir $prof } catch { $err = $_ }
        "$($err.Exception.Message)" | Should Match 'without its debug port'
        "$($err.Exception.Message)" | Should Match 'Close every window'
        Test-NoRetryError $err | Should Be $true
        Assert-MockCalled -ModuleName Cdp Start-Process -Times 0 -Exactly -Scope It
    }
    It 'waits for an Edge that is still starting with the port, instead of starting another' {
        $global:obsnEndpointLooks = 0
        Mock -ModuleName Cdp Test-CdpEndpoint { $global:obsnEndpointLooks++; $global:obsnEndpointLooks -ge 4 }
        Mock -ModuleName Cdp Start-Process { throw 'must not start Edge again' }
        Mock -ModuleName Cdp Get-EdgeBrowserProcesses { @([pscustomobject]@{ ProcessId = 5; CommandLine = "msedge.exe --remote-debugging-port=9334 --user-data-dir=`"$global:obsnProf`"" }) }
        Start-CdpEdge -Port 9334 -ProfileDir $prof | Should BeNullOrEmpty
        Assert-MockCalled -ModuleName Cdp Start-Process -Times 0 -Exactly -Scope It
    }
    It 'starts Edge once when none runs for the profile, and returns the process it started' {
        $global:obsnEndpointLooks = 0
        Mock -ModuleName Cdp Test-CdpEndpoint { $global:obsnEndpointLooks++; $global:obsnEndpointLooks -ge 3 }
        Mock -ModuleName Cdp Start-Process { [pscustomobject]@{ Id = 42 } }
        Mock -ModuleName Cdp Get-EdgeBrowserProcesses { @() }
        (Start-CdpEdge -Port 9334 -ProfileDir $prof).Id | Should Be 42
        Assert-MockCalled -ModuleName Cdp Start-Process -Times 1 -Exactly -Scope It
    }
    It 'with -NoLaunch never starts Edge (the window was closed twice already)' {
        Mock -ModuleName Cdp Test-CdpEndpoint { $false }
        Mock -ModuleName Cdp Start-Process { throw 'must not start' }
        Mock -ModuleName Cdp Get-EdgeBrowserProcesses { @() }
        { Start-CdpEdge -Port 9334 -ProfileDir $prof -NoLaunch } | Should Throw 'closed (twice)'
    }
    It 'stops at once when policy blocks the debug port' {
        Mock -ModuleName Cdp Test-CdpEndpoint { $false }
        Mock -ModuleName Cdp Get-EdgeDebugBlock { 'Edge policy RemoteDebuggingAllowed = 0 blocks the debug port' }
        Mock -ModuleName Cdp Start-Process { throw 'must not start' }
        { Start-CdpEdge -Port 9334 -ProfileDir $prof } | Should Throw 'RemoteDebuggingAllowed = 0'
    }
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
}

Describe 'Connect-Copilot and a tab that changes during the sign-in' {
    $tab = [pscustomobject]@{ url = 'https://m365.cloud.microsoft/chat'; webSocketDebuggerUrl = 'ws://127.0.0.1:9334/devtools/page/X' }
    Mock -ModuleName CopilotBridge Start-CdpEdge { $null }
    Mock -ModuleName CopilotBridge Close-PrivateCopilotSessions { 0 }
    Mock -ModuleName CopilotBridge Connect-Cdp { [pscustomobject]@{ Lost = $false } }
    Mock -ModuleName CopilotBridge Disconnect-Cdp { }
    Mock -ModuleName CopilotBridge Set-CopilotTabActive { }
    Mock -ModuleName CopilotBridge Start-Sleep { }
    Mock -ModuleName CopilotBridge Get-CopilotPacing { @{} }

    It 'attaches again after the tab closed its connection once (a sign-in redirect), and connects' {
        $global:obsnCdpCalls = 0
        Mock -ModuleName CopilotBridge Get-CopilotTarget { [pscustomobject]@{ url = 'https://m365.cloud.microsoft/chat'; webSocketDebuggerUrl = 'ws://x' } }
        Mock -ModuleName CopilotBridge Invoke-Cdp { $global:obsnCdpCalls++; if ($global:obsnCdpCalls -eq 1) { throw 'Lost the connection to the Copilot tab in Edge (The remote party closed the WebSocket connection without completing the close handshake.)' } }
        Mock -ModuleName CopilotBridge Wait-CopilotEditor { $true }
        Mock -ModuleName CopilotBridge Test-EdgeForcedSignIn { $false }
        $b = Connect-Copilot -Port 9334 -ProfileDir 'C:\fake\edge-profile' -SignIn 'single-sign-on' -SignInTimeoutSec 5
        $b.Port | Should Be 9334
        Assert-MockCalled -ModuleName CopilotBridge Get-CopilotTarget -Times 2 -Exactly -Scope It
    }
    It 'keeps attaching while a sign-in goes on (more than the old 15 attempts) and does not navigate the sign-in page back' {
        $global:obsnTargets = 0; $global:obsnNav = 0
        Mock -ModuleName CopilotBridge Get-CopilotTarget { $global:obsnTargets++; [pscustomobject]@{ url = 'https://login.microsoftonline.com/common/oauth2/authorize'; webSocketDebuggerUrl = 'ws://x' } }
        Mock -ModuleName CopilotBridge Invoke-Cdp { param($Session, $Method) if ($Method -eq 'Page.navigate') { $global:obsnNav++ }; if ($global:obsnTargets -lt 20) { throw 'Lost the connection to the Copilot tab in Edge (closed)' } }
        Mock -ModuleName CopilotBridge Wait-CopilotEditor { $true }
        Mock -ModuleName CopilotBridge Test-EdgeForcedSignIn { $false }
        $null = Connect-Copilot -Port 9334 -ProfileDir 'C:\fake\edge-profile' -SignIn 'single-sign-on' -SignInTimeoutSec 60 2>$null
        $global:obsnTargets | Should Be 20
        $global:obsnNav | Should Be 0
    }
    It 'stops with the Edge sign-in message when policy forces a browser sign-in and the window vanished' {
        Mock -ModuleName CopilotBridge Get-CopilotTarget { [pscustomobject]@{ url = 'https://m365.cloud.microsoft/chat'; webSocketDebuggerUrl = 'ws://x' } }
        Mock -ModuleName CopilotBridge Invoke-Cdp { throw 'Lost the connection to the Copilot tab in Edge (closed)' }
        Mock -ModuleName CopilotBridge Test-EdgeForcedSignIn { $true }
        Mock -ModuleName CopilotBridge Get-EdgeProfileAccount { 'none' }
        Mock -ModuleName CopilotBridge Get-WebPageCount { 0 }
        $err = $null
        try { $null = Connect-Copilot -Port 9334 -ProfileDir 'C:\fake\edge-profile' -SignIn 'single-sign-on' -SignInTimeoutSec 60 } catch { $err = $_ }
        "$($err.Exception.Message)" | Should Match 'BrowserSignin = 2'
        "$($err.Exception.Message)" | Should Match 'sign in to Edge itself with your work account'
        Assert-MockCalled -ModuleName CopilotBridge Get-CopilotTarget -Times 1 -Exactly -Scope It
    }
    It 'retries as usual under that policy once the profile is signed in with a work account' {
        Mock -ModuleName CopilotBridge Test-EdgeForcedSignIn { $true }
        Mock -ModuleName CopilotBridge Get-EdgeProfileAccount { 'work' }
        Mock -ModuleName CopilotBridge Get-WebPageCount { 0 }
        & (Get-Module CopilotBridge) { Test-ForcedSignInBlock -Port 9334 -ProfileDir 'C:\fake' } | Should Be $false
    }
    It 'does not retry an error that would only open more Edge windows' {
        Mock -ModuleName CopilotBridge Start-CdpEdge { throw (New-NoRetryError 'held without its debug port') }
        Mock -ModuleName CopilotBridge Get-CopilotTarget { throw 'must not get here' }
        { Connect-Copilot -Port 9334 -ProfileDir 'C:\fake\edge-profile' -SignIn 'single-sign-on' -SignInTimeoutSec 60 } | Should Throw 'without its debug port'
        Assert-MockCalled -ModuleName CopilotBridge Start-CdpEdge -Times 1 -Exactly -Scope It
    }
    It 'starts Edge at most twice per connect, then only waits (-NoLaunch)' {
        $global:obsnNoLaunch = @()
        Mock -ModuleName CopilotBridge Start-CdpEdge { $global:obsnNoLaunch += [bool]$NoLaunch; if ($NoLaunch) { throw (New-NoRetryError 'closed (twice)') }; [pscustomobject]@{ Id = 1 } }
        Mock -ModuleName CopilotBridge Get-CopilotTarget { throw 'no page targets on port 9334' }
        Mock -ModuleName CopilotBridge Test-EdgeForcedSignIn { $false }
        { Connect-Copilot -Port 9334 -ProfileDir 'C:\fake\edge-profile' -SignIn 'single-sign-on' -SignInTimeoutSec 60 2>$null } | Should Throw 'closed (twice)'
        ($global:obsnNoLaunch -join ',') | Should Be 'False,False,True'
    }
}

Describe 'Which tab is sent to Copilot (Test-NavigateToCopilot)' {
    $sel = [pscustomobject]@{ chatUrl = 'https://m365.cloud.microsoft/chat'; chatHosts = @('m365.cloud.microsoft', 'www.microsoft365.com') }
    It 'sends an empty tab, never Copilot itself or Microsoft''s sign-in page' {
        Test-NavigateToCopilot 'about:blank' $sel | Should Be $true
        Test-NavigateToCopilot 'edge://newtab/' $sel | Should Be $true
        Test-NavigateToCopilot 'https://m365.cloud.microsoft/chat' $sel -FirstAttempt | Should Be $false
        Test-NavigateToCopilot 'https://login.microsoftonline.com/common/oauth2' $sel -FirstAttempt | Should Be $false
    }
    It 'leaves another web page alone after the first attempt (an organisation''s sign-in on its way)' {
        Test-NavigateToCopilot 'https://sso.example.org/adfs/ls' $sel -FirstAttempt | Should Be $true
        Test-NavigateToCopilot 'https://sso.example.org/adfs/ls' $sel | Should Be $false
    }
}

Describe 'Connect-Copilot follows the signIn setting' {
    It 'uses "signIn" from config when -SignIn is not given' {
        Mock -ModuleName CopilotBridge Get-CopilotSignInMode { 'private' }
        Mock -ModuleName CopilotBridge Start-CdpEdge { $null }
        Mock -ModuleName CopilotBridge Get-PrivateCopilotTarget { throw 'Copilot message box never appeared; not signed in?' }
        Mock -ModuleName CopilotBridge Get-CopilotTarget { throw 'must not use the profile tab' }
        { Connect-Copilot -Port 9334 -ProfileDir 'C:\fake' -SignInTimeoutSec 1 } | Should Throw 'never appeared'
        Assert-MockCalled -ModuleName CopilotBridge Get-PrivateCopilotTarget -Times 1 -Scope It
    }
}

Remove-Variable -Name obsnCdpCalls, obsnTargets, obsnNav, obsnNoLaunch, obsnEndpointLooks, obsnProf -Scope Global -ErrorAction SilentlyContinue
