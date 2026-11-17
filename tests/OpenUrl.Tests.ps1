# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# POST /api/open (lib/Server.psm1, operator 2026-11-17): a web link from the window opens in a new tab
# of the default browser, not in ObsidiNote's own Edge. Only http(s) addresses; the test state records
# the address instead of starting a browser (State.OpenedUrls). Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

Describe 'POST /api/open' {
    $app = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
    [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), '{"notebook":""}')
    $state = New-ServerState -AppRoot $app -Port 8767 -FakeStatus @{ ok = $true }
    $state.OpenedUrls = New-Object System.Collections.ArrayList
    It 'opens an https address' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/open' -Body '{"url":"https://example.org/a?b=c"}' -State $state
        $r.status | Should Be 200
        @($state.OpenedUrls) -join ',' | Should Be 'https://example.org/a?b=c'
    }
    It 'refuses anything that is not a web address' {
        foreach ($u in 'file:///C:/Windows/notepad.exe', 'onenote:https://example.org/x.one', 'javascript:alert(1)', 'C:\Windows\notepad.exe', 'https://', 'https://example.org/a b', '', ('https://example.org/' + ('a' * 2000))) {
            $body = ConvertTo-Json -InputObject @{ url = $u } -Compress
            "${u}: $((Invoke-ApiRoute -Method 'POST' -Path '/api/open' -Body $body -State $state).status)" | Should Be "${u}: 400"
        }
        @($state.OpenedUrls).Count | Should Be 1
    }
    It 'refuses a body that is not JSON' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/open' -Body 'url=https://example.org' -State $state).status | Should Be 400
    }
    Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction SilentlyContinue
}
