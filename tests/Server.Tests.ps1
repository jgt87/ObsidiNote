# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The interface's local server (lib/Server.psm1): origin and host checks, the static allow-list,
# the API, and a live server on a test port (never the real 8767) with fake OneNote/Copilot data.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

$script:TestPort = 18767

function New-TestUi {
    $d = Join-Path $env:TEMP ('obsn-ui-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'assets'), (Join-Path $d '.hidden'), (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'index.html'), '<!doctype html><title>ObsidiNote</title>')
    [IO.File]::WriteAllText((Join-Path $d 'assets\app-1.js'), 'console.log(1)')
    [IO.File]::WriteAllText((Join-Path $d 'favicon.svg'), '<svg xmlns="http://www.w3.org/2000/svg"/>')
    [IO.File]::WriteAllText((Join-Path $d 'evil.ps1'), 'Write-Host x')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $d '.hidden\x.js'), 'x')
    $d
}

function Send-RawRequest {
    <# Sends one HTTP/1.1 request exactly as written (path, Host and Origin untouched by .NET) and
       returns @{ status; body }. #>
    param([int]$Port, [string]$Method = 'GET', [string]$Path = '/', [string]$HostHeader = '', [hashtable]$Headers = @{}, [string]$Body = '')
    if (-not $HostHeader) { $HostHeader = "127.0.0.1:$Port" }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $lines = @("$Method $Path HTTP/1.1", "Host: $HostHeader", 'Connection: close')
    foreach ($k in $Headers.Keys) { $lines += "${k}: $($Headers[$k])" }
    if ($Method -eq 'POST') { $lines += 'Content-Type: application/json'; $lines += "Content-Length: $($bytes.Length)" }
    $head = [Text.Encoding]::ASCII.GetBytes((($lines -join "`r`n") + "`r`n`r`n"))
    $c = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $s = $c.GetStream()
        $s.Write($head, 0, $head.Length)
        if ($bytes.Length) { $s.Write($bytes, 0, $bytes.Length) }
        $r = New-Object IO.StreamReader($s, [Text.Encoding]::UTF8)
        $text = $r.ReadToEnd()
    } finally { $c.Close() }
    $status = [int]([regex]::Match($text, '^HTTP/1\.\d (\d{3})').Groups[1].Value)
    $split = $text.IndexOf("`r`n`r`n")
    @{ status = $status; head = $text.Substring(0, $split); body = $text.Substring($split + 4) }
}

Describe 'Test-AllowedOrigin' {
    It 'accepts exactly the three loopback origins with this port' {
        foreach ($o in 'http://127.0.0.1:8767', 'http://localhost:8767', 'http://[::1]:8767') { Test-AllowedOrigin $o 8767 | Should Be $true }
    }
    It 'refuses look-alike origins (never a prefix match)' {
        foreach ($o in 'http://localhost.evil.example', 'http://127.0.0.1.evil.example', 'http://localhost@evil.example', 'http://localhost:8767@evil.example',
            'http://localhost:8767.evil.example', 'https://localhost:8767', 'http://localhost', 'http://localhost:8768', 'null', '', 'http://127.0.0.1:8767/') {
            Test-AllowedOrigin $o 8767 | Should Be $false
        }
    }
}

Describe 'Test-AllowedHost' {
    It 'accepts loopback hosts with this port, nothing else' {
        Test-AllowedHost '127.0.0.1:8767' 8767 | Should Be $true
        Test-AllowedHost 'localhost:8767' 8767 | Should Be $true
        foreach ($h in 'evil.example:8767', 'localhost', '127.0.0.1:80', 'localhost.evil.example:8767', '') { Test-AllowedHost $h 8767 | Should Be $false }
    }
}

Describe 'Get-RequestVerdict' {
    $ok = @{ Method = 'GET'; Path = '/'; HostHeader = '127.0.0.1:8767'; Origin = ''; AppHeader = ''; Loopback = $true; Port = 8767 }
    It 'serves the page without Origin or custom header' {
        Get-RequestVerdict @ok | Should BeNullOrEmpty
    }
    It 'refuses a client that is not this computer, and an unknown Host' {
        $a = $ok.Clone(); $a.Loopback = $false; (Get-RequestVerdict @a).status | Should Be 403
        $b = $ok.Clone(); $b.HostHeader = 'evil.example:8767'; (Get-RequestVerdict @b).status | Should Be 403
    }
    It 'needs X-ObsidiNote: 1 on every API call, and an allowed Origin when one is sent' {
        $a = $ok.Clone(); $a.Method = 'POST'; $a.Path = '/api/intent'
        (Get-RequestVerdict @a).status | Should Be 403
        $a.AppHeader = '1'; Get-RequestVerdict @a | Should BeNullOrEmpty
        $a.Origin = 'http://localhost.evil.example:8767'; (Get-RequestVerdict @a).status | Should Be 403
        $a.Origin = 'http://localhost:8767'; Get-RequestVerdict @a | Should BeNullOrEmpty
        $g = $ok.Clone(); $g.Path = '/api/status'; (Get-RequestVerdict @g).status | Should Be 403
    }
    It 'allows POST only on the API' {
        $a = $ok.Clone(); $a.Method = 'POST'; (Get-RequestVerdict @a).status | Should Be 405
        $b = $ok.Clone(); $b.Method = 'DELETE'; $b.Path = '/api/intent'; $b.AppHeader = '1'; (Get-RequestVerdict @b).status | Should Be 405
    }
}

Describe 'Get-UiAllowList' {
    $ui = New-TestUi
    $list = Get-UiAllowList $ui
    It 'lists the web files of ui\ and / for index.html' {
        $list.ContainsKey('/') | Should Be $true
        $list.ContainsKey('/assets/app-1.js') | Should Be $true
        $list.ContainsKey('/ASSETS/APP-1.JS') | Should Be $true
        $list.ContainsKey('/favicon.svg') | Should Be $true
    }
    It 'leaves out scripts, config files and dot-folders' {
        $list.ContainsKey('/evil.ps1') | Should Be $false
        $list.ContainsKey('/config/obsidinote.json') | Should Be $false
        $list.ContainsKey('/.hidden/x.js') | Should Be $false
    }
    Remove-Item $ui -Recurse -Force
}

Describe 'Get-CopilotTabState' {
    It 'is connected when a page is on a Copilot host' {
        $pages = @([pscustomobject]@{ type = 'page'; url = 'http://127.0.0.1:8767/' }, [pscustomobject]@{ type = 'page'; url = 'https://m365.cloud.microsoft/chat' })
        Get-CopilotTabState -Pages $pages -Hosts @('microsoft365.com', 'm365.cloud.microsoft') | Should Be 'connected'
    }
    It 'is no-tab on a sign-in page or a look-alike host' {
        $pages = @([pscustomobject]@{ type = 'page'; url = 'https://login.example.com/x' }, [pscustomobject]@{ type = 'page'; url = 'https://m365.cloud.microsoft.evil.example/' })
        Get-CopilotTabState -Pages $pages -Hosts @('m365.cloud.microsoft') | Should Be 'no-tab'
    }
}

$script:Hier = [IO.File]::ReadAllText((Join-Path $here 'fixtures\hierarchy.xml'))
$script:Team = '{22222222-2222-2222-2222-222222222222}{1}{B0}'
$script:Reading = '{33333333-3333-3333-3333-333333333333}{1}{B0}'

function New-TempAppRoot {
    # Its own config folder, so the active-vault record never touches the repo's config.
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    $d
}

Describe 'Invoke-ApiRoute' {
    $state = New-ServerState -AppRoot $root -Port 8767 -FakeStatus ([pscustomobject]@{ app = 'ObsidiNote' }) -FakeHierarchyXml $script:Hier
    It 'answers status and notebook' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.app | Should Be 'ObsidiNote'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -State $state).status | Should Be 200
    }
    It 'lists the open notebooks, vaults first, with the active one marked' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $state
        $r.status | Should Be 200
        ($r.body.notebooks | ForEach-Object { "$($_.name):$($_.vault):$($_.active)" }) -join ',' | Should Be 'ObsidiNote:True:True,Team wiki:True:False,Reading notes:False:False'
    }
    It 'reads a chosen notebook with ?id=, the active vault without it' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query "id=$([Uri]::EscapeDataString($script:Reading))" -State $state).body.notebook.name | Should Be 'Reading notes'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -State $state).body.notebook.name | Should Be 'ObsidiNote'
    }
    It 'is 404 for an id that is not an open notebook, 400 for one that is not an id' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query 'id=%7B99999999-9999-9999-9999-999999999999%7D%7B1%7D%7BB0%7D' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query 'id=..%2F..%2Fx' -State $state).status | Should Be 400
    }
    It 'makes a vault active by keeping its record, and refuses a read-only notebook' {
        $app = New-TempAppRoot
        $s2 = New-ServerState -AppRoot $app -Port 8767 -FakeHierarchyXml $script:Hier
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body "{`"id`":`"$($script:Team)`"}" -State $s2
        $r.status | Should Be 200
        $r.body.name | Should Be 'Team wiki'
        ([IO.File]::ReadAllText((Join-Path $app 'config\obsidinote.local.json')) | ConvertFrom-Json).notebook | Should Be 'onenote:https://example.sharepoint.com/sites/Team/Shared Documents/Team wiki/'
        @((Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $s2).body.notebooks | Where-Object { $_.active })[0].name | Should Be 'Team wiki'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body "{`"id`":`"$($script:Reading)`"}" -State $s2).status | Should Be 409
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body '{"id":"x"}' -State $s2).status | Should Be 400
        Remove-Item $app -Recurse -Force
    }
    It 'tells the intent' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/intent' -Body '{"text":"What did we decide?","mode":"auto"}' -State $state
        $r.status | Should Be 200
        $r.body.intent | Should Be 'ask'
    }
    It 'refuses a bad intent request' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intent' -Body 'not json' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intent' -Body '{"text":"x","mode":"delete"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intent' -Body '{"text":5}' -State $state).status | Should Be 400
    }
    It 'answers submit with 501 and what comes next' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"x","mode":"add"}' -State $state
        $r.status | Should Be 501
        $r.body.message | Should Be 'Adding comes in the next step'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"x","mode":"ask"}' -State $state).body.message | Should Be 'Asking comes in the next step'
    }
    It 'is 404 for an unknown route' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/nothing' -State $state).status | Should Be 404
    }
}

Describe 'The live server (test port)' {
    $ui = New-TestUi
    $status = [pscustomobject]@{ app = 'ObsidiNote'; version = 'v0.0.0'; uiPort = $script:TestPort }
    $state = New-ServerState -AppRoot $root -Port $script:TestPort -FakeStatus $status -FakeHierarchyXml $script:Hier
    $server = Start-UiServer -Port $script:TestPort -UiDir $ui -State $state
    $api = @{ 'X-ObsidiNote' = '1'; Origin = "http://127.0.0.1:$($script:TestPort)" }
    try {
        It 'serves the page with a content security policy' {
            $r = Send-RawRequest -Port $script:TestPort -Path '/'
            $r.status | Should Be 200
            $r.body | Should Match '<title>ObsidiNote</title>'
            $r.head | Should Match "Content-Security-Policy: default-src 'self'"
            (Send-RawRequest -Port $script:TestPort -Path '/assets/app-1.js').status | Should Be 200
        }
        It 'answers 404 for scripts, config files, dot-folders and paths not on the allow-list' {
            foreach ($p in '/evil.ps1', '/config/obsidinote.json', '/lib/Server.psm1', '/obsidinote.ps1', '/.hidden/x.js', '/assets/../evil.ps1', '/nothing.html', '/assets/') {
                $r = Send-RawRequest -Port $script:TestPort -Path $p
                $r.status | Should Be 404
                $r.body | Should Not Match 'Write-Host'
            }
        }
        It 'never serves ../ or encoded ../ paths (Windows'' HTTP service refuses most of them itself with 403)' {
            foreach ($p in '/../obsidinote.ps1', '/..%2Fobsidinote.ps1', '/%2e%2e/obsidinote.ps1', '/..%5Cobsidinote.ps1', '/..%2Fevil.ps1', '/assets/..%2F..%2Fevil.ps1') {
                $r = Send-RawRequest -Port $script:TestPort -Path $p
                @(403, 404) -contains $r.status | Should Be $true
                $r.body | Should Not Match 'Write-Host'
            }
        }
        It 'answers the API with the header and an allowed Origin' {
            $r = Send-RawRequest -Port $script:TestPort -Path '/api/status' -Headers $api
            $r.status | Should Be 200
            ($r.body | ConvertFrom-Json).app | Should Be 'ObsidiNote'
            $i = Send-RawRequest -Port $script:TestPort -Method 'POST' -Path '/api/intent' -Headers $api -Body '{"text":"https://example.com/a","mode":"auto"}'
            ($i.body | ConvertFrom-Json).intent | Should Be 'add'
            (Send-RawRequest -Port $script:TestPort -Method 'POST' -Path '/api/submit' -Headers $api -Body '{"text":"Why?","mode":"auto"}').status | Should Be 501
        }
        It 'answers the notebook list and a notebook by ?id= over HTTP' {
            $l = Send-RawRequest -Port $script:TestPort -Path '/api/notebooks' -Headers $api
            @(($l.body | ConvertFrom-Json).notebooks).Count | Should Be 3
            $n = Send-RawRequest -Port $script:TestPort -Path "/api/notebook?id=$([Uri]::EscapeDataString($script:Team))" -Headers $api
            $n.status | Should Be 200
            ($n.body | ConvertFrom-Json).notebook.name | Should Be 'Team wiki'
        }
        It 'refuses look-alike origins, a missing header and a foreign Host' {
            foreach ($o in 'http://localhost.evil.example', "http://127.0.0.1.evil.example:$($script:TestPort)", 'http://localhost@evil.example', "https://localhost:$($script:TestPort)", 'null') {
                (Send-RawRequest -Port $script:TestPort -Method 'POST' -Path '/api/intent' -Headers @{ 'X-ObsidiNote' = '1'; Origin = $o } -Body '{"text":"x"}').status | Should Be 403
            }
            (Send-RawRequest -Port $script:TestPort -Method 'POST' -Path '/api/intent' -Body '{"text":"x"}').status | Should Be 403
            (Send-RawRequest -Port $script:TestPort -Path '/api/status' -Headers $api -HostHeader "evil.example:$($script:TestPort)").status | Should Not Be 200
        }
        It 'finds itself as a running ObsidiNote' {
            Test-UiServerRunning -Port $script:TestPort | Should Be $true
        }
    } finally {
        Stop-UiServer $server
        Remove-Item $ui -Recurse -Force
    }
    It 'stops: the port is free again' {
        Test-UiServerRunning -Port $script:TestPort | Should Be $false
    }
}
