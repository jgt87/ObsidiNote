# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Where the interface opens (lib/AppWindow.psm1). Mocks CDP and process starts: no Edge opens.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\AppWindow.psm1') -Force

Describe 'Test-LocalAppUrl' {
    It 'knows the interface by its loopback address and port' {
        Test-LocalAppUrl 'http://127.0.0.1:8767/' 8767 | Should Be $true
        Test-LocalAppUrl 'http://localhost:8767/#/graph' 8767 | Should Be $true
        Test-LocalAppUrl 'http://127.0.0.1:8768/' 8767 | Should Be $false
        Test-LocalAppUrl 'http://127.0.0.1.evil.example:8767/' 8767 | Should Be $false
        Test-LocalAppUrl 'https://m365.cloud.microsoft/chat' 8767 | Should Be $false
    }
}

Describe 'Open-AppInEdgeWindow' {
    It 'opens a new window through Target.createTarget with newWindow' {
        Mock -ModuleName AppWindow Invoke-RestMethod {
            if ($Uri -like '*/json/list') { return , @([pscustomobject]@{ type = 'page'; id = 'C1'; url = 'https://m365.cloud.microsoft/chat' }) }
            [pscustomobject]@{ webSocketDebuggerUrl = 'ws://127.0.0.1:9334/devtools/browser/x' }
        }
        Mock -ModuleName AppWindow Connect-Cdp { [pscustomobject]@{ fake = 1 } }
        Mock -ModuleName AppWindow Invoke-Cdp { [pscustomobject]@{ targetId = 'T1' } }
        Mock -ModuleName AppWindow Disconnect-Cdp { }
        Open-AppInEdgeWindow -Url 'http://127.0.0.1:8767/' -AppPort 8767 -CdpPort 9334 | Should Be 'new-window'
        Assert-MockCalled -ModuleName AppWindow Invoke-Cdp -Times 1 -ParameterFilter { $Method -eq 'Target.createTarget' -and $Params.newWindow -eq $true -and $Params.url -eq 'http://127.0.0.1:8767/' }
    }
    It 'brings an open interface tab to the front instead of opening another' {
        Mock -ModuleName AppWindow Invoke-RestMethod {
            if ($Uri -like '*/json/list') { return , @([pscustomobject]@{ type = 'page'; id = 'A1'; url = 'http://127.0.0.1:8767/' }) }
            'Target activated'
        }
        Mock -ModuleName AppWindow Connect-Cdp { throw 'must not connect' }
        Open-AppInEdgeWindow -Url 'http://127.0.0.1:8767/' -AppPort 8767 -CdpPort 9334 | Should Be 'existing'
        Assert-MockCalled -ModuleName AppWindow Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -like '*/json/activate/A1' }
    }
}

Describe 'Start-AppInEdgeProfile' {
    It 'starts ObsidiNote''s Edge profile as an app window when its Edge is not running' {
        Mock -ModuleName AppWindow Test-CdpEndpoint { $false }
        Mock -ModuleName AppWindow Get-EdgePath { 'C:\Edge\msedge.exe' }
        $global:obsnStarted = $null
        $how = Start-AppInEdgeProfile -Url 'http://127.0.0.1:8767/' -AppPort 8767 -CdpPort 9334 -ProfileDir (Join-Path $env:TEMP 'obsn-test-profile') -Start { param($exe, $a) $global:obsnStarted = @{ exe = $exe; args = ($a -join ' ') } } -OpenDefault { throw 'no browser' }
        $how | Should Be 'edge-profile'
        $global:obsnStarted.exe | Should Be 'C:\Edge\msedge.exe'
        $global:obsnStarted.args | Should Match '--app=http://127\.0\.0\.1:8767/'
        $global:obsnStarted.args | Should Match 'obsn-test-profile'
        $global:obsnStarted.args | Should Match '--remote-debugging-port=9334'
        Remove-Variable -Name obsnStarted -Scope Global
    }
    It 'falls back to the default browser when Edge cannot start' {
        Mock -ModuleName AppWindow Test-CdpEndpoint { $false }
        Mock -ModuleName AppWindow Get-EdgePath { throw 'msedge.exe not found' }
        $global:obsnOpened = ''
        Start-AppInEdgeProfile -Url 'http://127.0.0.1:8767/' -AppPort 8767 -CdpPort 9334 -ProfileDir (Join-Path $env:TEMP 'obsn-test-profile') -Start { throw 'x' } -OpenDefault { param($u) $global:obsnOpened = $u } | Should Be 'browser'
        $global:obsnOpened | Should Be 'http://127.0.0.1:8767/'
        Remove-Variable -Name obsnOpened -Scope Global
    }
}

Describe 'Get-AppWindowDetail' {
    It 'says where the window opened' {
        Get-AppWindowDetail 'new-window' | Should Match "ObsidiNote's Edge"
        Get-AppWindowDetail 'browser' | Should Match 'default browser'
    }
}
