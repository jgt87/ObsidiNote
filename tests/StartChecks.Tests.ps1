# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The start sequence (obsidinote.ps1): status lines (lib/Status.psm1), the checks of this computer
# (lib/StartChecks.psm1), the update line and the start of the new version (lib/Startup.psm1 and
# tools/update.ps1 -PassThru). No Edge, no OneNote, no network: every probe is a stand-in.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Status.psm1') -Force
Import-Module (Join-Path $root 'lib\Startup.psm1') -Force
Import-Module (Join-Path $root 'lib\StartChecks.psm1') -Force

Describe 'Status lines (one helper for the installer and the start)' {
    It 'formats "[OK]" lines with the name in a fixed column' {
        Format-StatusLine 'OK' 'Update' 'up to date (v0.2.3)' | Should Be '  [OK]   Update                up to date (v0.2.3)'
        Format-StatusLine 'WARN' 'Edge profile' 'x' | Should Be '  [WARN] Edge profile          x'
        Format-StatusLine 'FAIL' 'OneNote' 'y' | Should Be '  [FAIL] OneNote               y'
    }
    It 'is the helper the installer uses (no second copy in tools/install-main.ps1)' {
        $inst = [IO.File]::ReadAllText((Join-Path $root 'tools\install-main.ps1'))
        $inst | Should Match "lib\\Status\.psm1"
        $inst | Should Not Match 'function Write-Status'
    }
}

Describe 'The Edge profile line before connecting' {
    It 'says signed in or not, and SSO on/off/unavailable' {
        (Get-EdgeProfileSummary -Account 'work' -Sso 'on').detail | Should Be 'signed in with a work account; SSO on'
        (Get-EdgeProfileSummary -Account 'personal' -Sso 'unavailable').detail | Should Be 'signed in with a personal Microsoft account; SSO unavailable (no work account token on this PC)'
        (Get-EdgeProfileSummary -Account 'unknown' -Sso 'unavailable').detail | Should Be 'not signed in (new profile); SSO unavailable (no work account token on this PC)'
    }
    It 'asks for sso-setup.cmd when the PC has a work account token and SSO is off' {
        $c = Get-EdgeProfileSummary -Account 'none' -Sso 'off'
        $c.status | Should Be 'WARN'
        $c.detail | Should Be 'not signed in; SSO off'
        $c.hint | Should Be 'Run sso-setup.cmd once so Copilot signs in by itself.'
        (Get-EdgeProfileSummary -Account 'none' -Sso 'on').status | Should Be 'OK'
    }
    It 'says to sign in to Edge itself when policy forces a browser sign-in and the profile has no work account' {
        $c = Get-EdgeProfileSummary -Account 'none' -Sso 'off' -ForcedSignIn $true
        $c.status | Should Be 'WARN'
        $c.hint | Should Match 'sign in to Edge with your work account'
        (Get-EdgeProfileSummary -Account 'work' -Sso 'on' -ForcedSignIn $true).status | Should Be 'OK'
    }
    It 'reads the PC and the profile through the SSO module (mocked: no dsregcmd, no Edge files)' {
        Mock -ModuleName StartChecks Get-DeviceJoinStatus { [ordered]@{ AzureAdJoined = 'YES'; AzureAdPrt = 'YES' } }
        Mock -ModuleName StartChecks Get-ProfileAccount { 'none' }
        Mock -ModuleName StartChecks Get-ProfileSsoState { 'off' }
        Mock -ModuleName StartChecks Test-EdgeForcedSignIn { $false }
        $c = Get-EdgeProfileCheck -ProfileDir 'C:\fake\edge-profile'
        $c.name | Should Be 'Edge profile'
        $c.hint | Should Be 'Run sso-setup.cmd once so Copilot signs in by itself.'
    }
}

Describe 'The debug port check' {
    Mock -ModuleName StartChecks Test-CdpEndpoint { $false }
    It 'fails, with what to close, when Edge holds the profile without the debug port' {
        Mock -ModuleName StartChecks Get-EdgeProfileUse { [pscustomobject]@{ state = 'no-debug'; pids = @(5) } }
        Mock -ModuleName StartChecks Test-PortListening { $false }
        $c = Get-CdpPortCheck -Port 9334 -ProfileDir 'C:\fake'
        $c.status | Should Be 'FAIL'
        $c.hint | Should Match 'Close every window of ObsidiNote''s Edge'
    }
    It 'is OK when free or when it is ObsidiNote''s own Edge, and fails for another program' {
        Mock -ModuleName StartChecks Get-EdgeProfileUse { [pscustomobject]@{ state = 'none'; pids = @() } }
        Mock -ModuleName StartChecks Test-PortListening { $false }
        (Get-CdpPortCheck -Port 9334 -ProfileDir 'C:\fake').detail | Should Be 'free'
        Mock -ModuleName StartChecks Test-PortListening { $true }
        (Get-CdpPortCheck -Port 9334 -ProfileDir 'C:\fake').status | Should Be 'FAIL'
        Mock -ModuleName StartChecks Get-EdgeProfileUse { [pscustomobject]@{ state = 'debug'; pids = @(5) } }
        Mock -ModuleName StartChecks Test-CdpEndpoint { $true }
        (Get-CdpPortCheck -Port 9334 -ProfileDir 'C:\fake').detail | Should Be 'ObsidiNote''s Edge is already running'
    }
}

Describe 'All checks of this computer' {
    It 'lists the items in order, and GitHub only as a warning' {
        Mock -ModuleName StartChecks Get-OneNoteExePath { 'C:\fake\ONENOTE.EXE' }
        Mock -ModuleName StartChecks Get-EdgePath { 'C:\fake\msedge.exe' }
        Mock -ModuleName StartChecks Get-EdgeDebugBlock { '' }
        Mock -ModuleName StartChecks Test-EdgeForcedSignIn { $true }
        Mock -ModuleName StartChecks Get-CdpPortCheck { New-StartCheck 'OK' 'Port 9334 (Edge)' 'free' }
        Mock -ModuleName StartChecks Get-EdgeProfileCheck { New-StartCheck 'OK' 'Edge profile' 'signed in with a work account; SSO on' }
        Mock -ModuleName StartChecks Test-GitHubReachable { $false }
        $all = Get-StartChecks -AppRoot $root
        ($all | ForEach-Object { $_.name }) -join '|' | Should Be 'Windows PowerShell|Language mode|OneNote (desktop)|Microsoft Edge|Edge policies|Port 9334 (Edge)|Edge profile|GitHub'
        ($all | Where-Object { $_.name -eq 'GitHub' }).status | Should Be 'WARN'
        ($all | Where-Object { $_.name -eq 'Edge policies' }).detail | Should Match 'BrowserSignin = 2'
        @($all | Where-Object { $_.status -eq 'FAIL' }).Count | Should Be 0
    }
    It 'leaves out the Edge checks with -NoCopilot and the OneNote one with -NoOneNote' {
        $all = Get-StartChecks -AppRoot $root -NoCopilot -NoOneNote -NoNetwork
        ($all | ForEach-Object { $_.name }) -join '|' | Should Be 'Windows PowerShell|Language mode'
    }
    It 'fails Edge policies when the debug port is blocked' {
        Mock -ModuleName StartChecks Get-EdgeDebugBlock { 'Edge policy RemoteDebuggingAllowed = 0 blocks the debug port' }
        (Get-EdgePolicyCheck).status | Should Be 'FAIL'
    }
}

Describe 'The update line and the start of the new version' {
    It 'prints "up to date (vX.Y.Z)" and starts nothing new' {
        $u = Get-UpdateStatus ([pscustomobject]@{ outcome = 'up-to-date'; version = '0.2.3'; detail = '' })
        $u.status | Should Be 'OK'
        $u.detail | Should Be 'up to date (v0.2.3)'
        $u.relaunch | Should Be $false
    }
    It 'starts the new version after an update' {
        $u = Get-UpdateStatus ([pscustomobject]@{ outcome = 'updated'; version = 'v0.2.4'; detail = 'v0.2.3 -> v0.2.4' })
        $u.relaunch | Should Be $true
        $u.detail | Should Match 'v0.2.3 -> v0.2.4'
    }
    It 'warns why a git clone with local changes was not updated' {
        $u = Get-UpdateStatus ([pscustomobject]@{ outcome = 'not-updated'; version = '0.2.3'; detail = 'this git clone has local changes' })
        $u.status | Should Be 'WARN'
        $u.detail | Should Be 'not updated: this git clone has local changes (v0.2.3)'
    }
    It 'starts the new version with the same arguments' {
        $a = Get-RelaunchArguments -Script 'C:\app\obsidinote.ps1' -Bound @{ Label = 'T'; NoCopilot = [System.Management.Automation.SwitchParameter]$true; NoWindow = [System.Management.Automation.SwitchParameter]$false }
        ($a -join ' ') | Should Be '-NoProfile -ExecutionPolicy Bypass -File C:\app\obsidinote.ps1 -Label T -NoCopilot'
    }
    It 'obsidinote.ps1 asks the updater for its outcome, starts the new version and ends itself' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'obsidinote.ps1'))
        $src | Should Match "tools\\update\.ps1'\) -PassThru"
        $src | Should Match 'Get-RelaunchArguments'
        $src | Should Match 'exit \$LASTEXITCODE'
        $src | Should Match 'OBSIDINOTE_UPDATED'
    }
}

Describe 'tools/update.ps1 -PassThru (no network: automatic updates off)' {
    $app = Join-Path $env:TEMP ('obsn-upd-pt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    foreach ($d in 'tools', 'lib', 'config') { $null = New-Item -ItemType Directory -Force (Join-Path $app $d) }
    Copy-Item (Join-Path $root 'tools\update.ps1') (Join-Path $app 'tools\update.ps1')
    Copy-Item (Join-Path $root 'lib\Update.psm1') (Join-Path $app 'lib\Update.psm1')
    [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), '{ "autoUpdate": false }')
    [IO.File]::WriteAllText((Join-Path $app 'version.txt'), 'v0.2.3')
    It 'returns the outcome as one object, and without -PassThru prints nothing on stdout' {
        $r = @(& (Join-Path $app 'tools\update.ps1') -PassThru)
        $r.Count | Should Be 1
        $r[0].outcome | Should Be 'off'
        $r[0].version | Should Be 'v0.2.3'
        (Get-UpdateStatus $r[0]).detail | Should Be 'automatic updates are off (v0.2.3)'
        @(& (Join-Path $app 'tools\update.ps1')).Count | Should Be 0
    }
    Remove-Item -LiteralPath $app -Recurse -Force
}

Describe 'What to do when Copilot cannot be reached' {
    It 'names the step for each cause' {
        Get-CopilotFailureHint 'ObsidiNote''s Edge profile is already open in an Edge window that was started without its debug port (port 9334)' | Should Match 'Close every window'
        Get-CopilotFailureHint 'Edge on this PC must be signed in to before it can be used (Edge policy BrowserSignin = 2)' | Should Match 'Sign in to Edge itself'
        Get-CopilotFailureHint 'Copilot message box never appeared; not signed in?' -Sso 'off' | Should Match 'Run sso-setup\.cmd once'
        Get-CopilotFailureHint 'Copilot message box never appeared; not signed in?' -Sso 'on' | Should Match 'within 10 minutes'
        Get-CopilotFailureHint 'Lost the connection to the Copilot tab in Edge (x)' | Should Match 'last 30 lines of %LOCALAPPDATA%\\ObsidiNote\\logs\\obsidinote\.log'
    }
}

Describe 'The OneNote line' {
    It 'is OK with the notebook open, WARN without it, FAIL when OneNote does not answer' {
        (Get-OneNoteStatus ([pscustomobject]@{ ok = $true; started = $true; how = 'record'; notebookOpen = $true; warn = ''; message = 'running, notebook ObsidiNote open' })).detail | Should Be 'running, notebook ObsidiNote open (opened the notebook on record)'
        (Get-OneNoteStatus ([pscustomobject]@{ ok = $true; started = $true; how = 'exe'; notebookOpen = $false; warn = 'no notebook on record yet; started OneNote itself'; message = 'running; notebook ObsidiNote is not open' })).status | Should Be 'WARN'
        (Get-OneNoteStatus ([pscustomobject]@{ ok = $false; started = $false; how = ''; notebookOpen = $false; warn = ''; message = 'OneNote did not answer' })).status | Should Be 'FAIL'
    }
}
