# OneNote at startup: state from the process list, start only when needed, wait for COM, never throw.
# No real OneNote: the process list, the start and the COM probe are stand-ins.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'lib\OneNoteHost.psm1') -Force

Describe 'OneNote state from the process list' {
    It 'is none without a OneNote process' {
        Get-OneNoteState -Processes @() | Should Be 'none'
    }
    It 'is background when OneNote runs only without a window (a COM instance)' {
        Get-OneNoteState -Processes @([pscustomobject]@{ MainWindowHandle = 0 }) | Should Be 'background'
    }
    It 'is window when one OneNote process has a window' {
        Get-OneNoteState -Processes @([pscustomobject]@{ MainWindowHandle = 0 }, [pscustomobject]@{ MainWindowHandle = 4242 }) | Should Be 'window'
    }
}

Describe 'Starting OneNote when needed' {
    It 'does not start OneNote when it already runs with a window' {
        $script:starts = 0
        $r = Start-OneNoteIfNeeded -GetState { 'window' } -Start { $script:starts++ } -Probe { $true } -PollMs 1
        $r.ok | Should Be $true
        $r.started | Should Be $false
        $script:starts | Should Be 0
    }
    It 'starts OneNote when it is not running, then waits until COM answers' {
        $script:starts = 0; $script:probes = 0
        $r = Start-OneNoteIfNeeded -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { $script:starts++ } -Probe { $script:probes++; $script:probes -ge 3 } -PollMs 1
        $r.ok | Should Be $true
        $r.started | Should Be $true
        $script:starts | Should Be 1
        $script:probes | Should Be 3
    }
    It 'starts OneNote with a window when only a background instance runs' {
        $script:starts = 0
        $r = Start-OneNoteIfNeeded -GetState { 'background' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { $script:starts++ } -Probe { $true } -PollMs 1
        $r.started | Should Be $true
        $script:starts | Should Be 1
    }
    It 'gives up after the timeout with a message, without throwing' {
        $r = Start-OneNoteIfNeeded -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { } -Probe { $false } -TimeoutSec 1 -PollMs 100
        $r.ok | Should Be $false
        $r.message | Should Match 'did not answer within 1 s'
    }
    It 'reports a missing OneNote instead of throwing' {
        Mock -ModuleName OneNoteHost Get-OneNoteExePath { '' }
        $r = Start-OneNoteIfNeeded -GetState { 'none' } -Start { throw 'must not start' } -Probe { $false } -PollMs 1
        $r.ok | Should Be $false
        $r.message | Should Match 'was not found'
    }
    It 'turns a failing start into a message' {
        $r = Start-OneNoteIfNeeded -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { throw 'access denied' } -Probe { $false } -PollMs 1
        $r.ok | Should Be $false
        $r.message | Should Match 'access denied'
    }
}
