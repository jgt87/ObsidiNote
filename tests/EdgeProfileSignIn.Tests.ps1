# One-time Edge sign-in (Invoke-EdgeProfileSignIn) for Edge policy BrowserSignin = 2: Edge closes a
# not-signed-in profile's window when started with --no-first-run and a debug port, so ObsidiNote
# starts it plainly, waits for a work account, then closes that Edge. No real Edge: all mocked.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Cdp.psm1') -Force
$profileDir = Join-Path $env:TEMP ('obsn-edgeprof-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

Describe 'One-time Edge sign-in (BrowserSignin = 2)' {
    It 'does nothing when the profile already has a work account' {
        $script:starts = 0
        $r = Invoke-EdgeProfileSignIn -ProfileDir $profileDir -Port 9334 -GetAccount { 'work' } -GetUse { [pscustomobject]@{ state = 'none'; pids = @() } } -StartEdge { $script:starts++ } -StopEdge { }
        $r.ok | Should Be $true
        $r.started | Should Be $false
        $script:starts | Should Be 0
    }
    It 'starts Edge without the debug port, waits for the work account, then closes that Edge' {
        $script:polls = 0; $script:args = $null; $script:stopped = @()
        $r = Invoke-EdgeProfileSignIn -ProfileDir $profileDir -Port 9334 -PollMs 1 `
            -GetAccount { $script:polls++; if ($script:polls -ge 4) { 'work' } else { 'none' } } `
            -GetUse { if ($script:polls -ge 4) { [pscustomobject]@{ state = 'no-debug'; pids = @(4242) } } else { [pscustomobject]@{ state = 'none'; pids = @() } } } `
            -StartEdge { param($d) $script:args = $d } `
            -StopEdge { param($ids) $script:stopped += $ids }
        $r.ok | Should Be $true
        $r.started | Should Be $true
        $script:args | Should Be $profileDir
        @($script:stopped) -join ',' | Should Be '4242'
    }
    It 'closes an Edge that already holds the profile before starting the sign-in' {
        $script:stopped = @(); $script:n = 0
        $r = Invoke-EdgeProfileSignIn -ProfileDir $profileDir -Port 9334 -PollMs 1 `
            -GetAccount { $script:n++; if ($script:n -ge 3) { 'work' } else { 'none' } } `
            -GetUse { if ($script:n -le 1) { [pscustomobject]@{ state = 'debug'; pids = @(77) } } else { [pscustomobject]@{ state = 'none'; pids = @() } } } `
            -StartEdge { } -StopEdge { param($ids) $script:stopped += $ids }
        $r.ok | Should Be $true
        @($script:stopped) -join ',' | Should Be '77'
    }
    It 'gives up after the timeout with what to do, without throwing' {
        $r = Invoke-EdgeProfileSignIn -ProfileDir $profileDir -Port 9334 -TimeoutSec 1 -PollMs 100 `
            -GetAccount { 'none' } -GetUse { [pscustomobject]@{ state = 'none'; pids = @() } } -StartEdge { } -StopEdge { }
        $r.ok | Should Be $false
        $r.detail | Should Match 'was not signed in within 1 s'
    }
    Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
}
