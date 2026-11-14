# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The interface's local server (lib/Server.psm1): origin and host checks, the static allow-list,
# the API, and a live server on a test port (never the real 8767) with fake OneNote/Copilot data.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
# OBSIDINOTE_TEST_PORT / OBSIDINOTE_TEST_TAG let parallel checkouts run this file at the same time.
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP ('obsidinote-test-data' + $(if ($env:OBSIDINOTE_TEST_TAG) { '-' + $env:OBSIDINOTE_TEST_TAG } else { '' }))
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

$script:TestPort = if ($env:OBSIDINOTE_TEST_PORT) { [int]$env:OBSIDINOTE_TEST_PORT } else { 18767 }

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

Describe 'Get-CopilotState with the start''s bridge' {
    # v0.4.0 on a business tenant: the bridge was connected, the window said "Copilot is not open".
    # Port 1 has no Edge, so only the bridge can make these "connected".
    It 'is connected while the bridge''s connection is open, whatever the tab list says' {
        InModuleScope Server {
            $bridge = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $false; Ws = [pscustomobject]@{ State = 'Open' } } }
            $st = @{ CopilotSkipped = $false; Copilot = $bridge; CdpPort = 1; AppRoot = 'C:\nowhere' }
            Get-CopilotState $st | Should Be 'connected'
        }
    }
    It 'does not trust a lost or closed bridge' {
        InModuleScope Server {
            $lost = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $true; Ws = [pscustomobject]@{ State = 'Open' } } }
            $closed = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $false; Ws = [pscustomobject]@{ State = 'Closed' } } }
            Test-BridgeOpen $lost | Should Be $false
            Test-BridgeOpen $closed | Should Be $false
            Test-BridgeOpen $null | Should Be $false
            Get-CopilotState @{ CopilotSkipped = $false; Copilot = $closed; CdpPort = 1; AppRoot = 'C:\nowhere' } | Should Be 'not-running'
        }
    }
}

Describe 'POST /api/copilot/reconnect (the refresh button, user 2026-11-14)' {
    # Port 1 has no Edge: without a bridge Copilot counts as not running. -TestConnect stands in for
    # Connect-Copilot; nothing here opens Edge.
    $open = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $false; Ws = [pscustomobject]@{ State = 'Open' } }; SignInPending = $false }
    It 'attaches a new bridge, and the status says connected after it' {
        $calls = @{ n = 0 }
        $o = $open   # GetNewClosure() captures this scope's variables only
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -TestConnect { $calls.n++; $o }.GetNewClosure()
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st
        $r.status | Should Be 200
        $r.body.state | Should Be 'connected'
        $calls.n | Should Be 1
        [object]::ReferenceEquals($st.Copilot, $open) | Should Be $true
        $global:ObsnReconnectState = $st   # Pester 3.4's InModuleScope takes no parameters
        try { InModuleScope Server { Get-CopilotState $global:ObsnReconnectState | Should Be 'connected' } }
        finally { Remove-Variable -Name ObsnReconnectState -Scope Global }
    }
    It 'replaces a lost bridge' {
        $lost = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $true; Ws = [pscustomobject]@{ State = 'Open' } } }
        $o = $open
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -Copilot $lost -TestConnect { $o }.GetNewClosure()
        (Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st).body.state | Should Be 'connected'
        [object]::ReferenceEquals($st.Copilot, $open) | Should Be $true
    }
    It 'does nothing while the bridge is connected' {
        $calls = @{ n = 0 }
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -Copilot $open -TestConnect { $calls.n++; $open }.GetNewClosure()
        (Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st).body.state | Should Be 'connected'
        $calls.n | Should Be 0
    }
    It 'asks for a sign-in and keeps no half-connected bridge' {
        $pending = [pscustomobject]@{ Session = $null; SignInPending = $true }
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -TestConnect { $pending }.GetNewClosure()
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st
        $r.status | Should Be 200
        $r.body.state | Should Be 'sign-in'
        $r.body.message | Should Match 'Sign in'
        $st.Copilot | Should BeNullOrEmpty
    }
    It 'reports a failure with its reason' {
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -TestConnect { throw 'Edge holds the profile without the debug port' }
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st
        $r.status | Should Be 200
        $r.body.state | Should Be 'failed'
        $r.body.message | Should Match 'debug port'
        $st.Copilot | Should BeNullOrEmpty
    }
    It 'refuses when this start skipped Copilot' {
        $st = New-ServerState -AppRoot 'C:\nowhere' -Port 8767 -CdpPort 1 -CopilotSkipped $true -TestConnect { throw 'must not be called' }
        (Invoke-ApiRoute -Method 'POST' -Path '/api/copilot/reconnect' -Body '' -State $st).status | Should Be 409
    }
}

Describe 'Get-RunningUiProblem (white window after an update, 2026-11-14)' {
    It 'lets a start open the window of the same version' {
        Get-RunningUiProblem -Running 'v0.7.0' -Mine 'v0.7.0' | Should BeNullOrEmpty
    }
    It 'stops a start when another version still runs on the port' {
        Get-RunningUiProblem -Running 'v0.6.1' -Mine 'v0.7.0' | Should Match 'ObsidiNote v0.6.1 still runs on this port; this is v0.7.0'
        Get-RunningUiProblem -Running '' -Mine 'v0.7.0' | Should Match 'another ObsidiNote'
    }
}

$script:Hier = [IO.File]::ReadAllText((Join-Path $here 'fixtures\hierarchy.xml'))
$script:Team = '{22222222-2222-2222-2222-222222222222}{1}{B0}'
$script:Reading = '{33333333-3333-3333-3333-333333333333}{1}{B0}'
$script:VaultA = 'aaaaaaaa-0000-4000-8000-000000000001'

# The fake OneNote world for the routes that write (in process only: its methods are scriptblocks).
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker') { Import-Module (Join-Path $root "lib\$m.psm1") }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function New-TempAppRoot([string]$Local = '') {
    # Its own config folder, so the active-vault record never touches the repo's config.
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    if ($Local) { [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.local.json'), $Local) }
    $d
}

function New-FakeCopilotSend([string[]]$Replies) {
    $q = New-Object System.Collections.Generic.Queue[string]
    foreach ($r in $Replies) { $q.Enqueue($r) }
    @{ Send = { param([string]$Text) if (-not $q.Count) { throw 'no reply left' }; $q.Dequeue() }.GetNewClosure(); NewChat = { } }
}

Describe 'Invoke-ApiRoute: notebooks and vaults (read only)' {
    $app = New-TempAppRoot ('{"vaultId":"' + $script:VaultA + '"}')
    $state = New-ServerState -AppRoot $app -Port 8767 -FakeStatus ([pscustomobject]@{ app = 'ObsidiNote' }) -FakeHierarchyXml $script:Hier
    It 'answers status and notebook' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.app | Should Be 'ObsidiNote'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -State $state).status | Should Be 200
    }
    It 'lists the open notebooks, vaults (found by their state page) first, the one on record active' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $state
        $r.status | Should Be 200
        ($r.body.notebooks | ForEach-Object { "$($_.name):$($_.vault):$($_.active)" }) -join ',' | Should Be 'ObsidiNote:True:True,Team wiki:True:False,Reading notes:False:False'
        $r.body.activeVaultId | Should Be $script:VaultA
        @($r.body.notebooks)[0].vaultId | Should Be $script:VaultA
    }
    It 'reads a chosen notebook with ?id=, the active vault without it' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query "id=$([Uri]::EscapeDataString($script:Reading))" -State $state).body.notebook.name | Should Be 'Reading notes'
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -State $state).body
        $v.notebook.name | Should Be 'ObsidiNote'
        $v.notebook.vault | Should Be $true
    }
    It 'is 404 for an id that is not an open notebook, 400 for one that is not an id' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query 'id=%7B99999999-9999-9999-9999-999999999999%7D%7B1%7D%7BB0%7D' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'GET' -Path '/api/notebook' -Query 'id=..%2F..%2Fx' -State $state).status | Should Be 400
    }
    It 'is not a vault with a 00 Index section alone (no state page)' {
        $xml = $script:Hier -replace '<one:Meta name="obsn.vaultId" content="bbbbbbbb[^>]*/>', ''
        $s2 = New-ServerState -AppRoot $app -Port 8767 -FakeHierarchyXml $xml
        ((Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $s2).body.notebooks | ForEach-Object { "$($_.name):$($_.vault)" }) -join ',' | Should Be 'ObsidiNote:True,Reading notes:False,Team wiki:False'
    }
    It 'marks none active when several vaults are open and none is on record' {
        $app2 = New-TempAppRoot
        $s3 = New-ServerState -AppRoot $app2 -Port 8767 -FakeHierarchyXml $script:Hier
        @((Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $s3).body.notebooks | Where-Object { $_.active }).Count | Should Be 0
        Remove-Item $app2 -Recurse -Force
    }
    It 'refuses a read-only notebook as the active vault, and a bad id' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body "{`"id`":`"$($script:Reading)`"}" -State $state).status | Should Be 409
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body '{"id":"x"}' -State $state).status | Should Be 400
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
    It 'answers Add and Ask with 503 and a clear message without Copilot' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"x","mode":"add"}' -State $state
        $r.status | Should Be 503
        $r.body.intent | Should Be 'add'
        $r.body.error | Should Match 'Copilot is not connected'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"Why?","mode":"auto"}' -State $state).body.intent | Should Be 'ask'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/update' -Body '{"id":"p1"}' -State $state).status | Should Be 503
        (Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"  ","mode":"auto"}' -State $state).status | Should Be 400
    }
    It 'returns the graph of a vault, and 400/404 for bad or unknown ids' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query 'vault=bbbbbbbb-0000-4000-8000-000000000002' -State $state
        $g.status | Should Be 200
        $g.body.source.name | Should Be 'Team wiki'
        $g.body.source.readOnly | Should Be $true
        (Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query 'vault=..%2F' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query 'vault=cccccccc-0000-4000-8000-000000000003' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query 'notebook=%7B99999999-9999-9999-9999-999999999999%7D%7B1%7D%7BB0%7D' -State $state).status | Should Be 404
    }
    It 'returns a connected notebook''s graph read only' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query "notebook=$([Uri]::EscapeDataString($script:Reading))" -State $state
        $g.status | Should Be 200
        $g.body.source.kind | Should Be 'notebook'
        $g.body.source.readOnly | Should Be $true
        (@($g.body.pages) | ForEach-Object { $_.title }) -join ',' | Should Be 'A book about maps'
    }
    It 'is 404 for an unknown route' {
        (Invoke-ApiRoute -Method 'GET' -Path '/api/nothing' -State $state).status | Should Be 404
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: switching vault, a new vault (in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'start'
    $null = Close-VaultSession -Adapter $w.a -Vault $w.open.vault -Lease $w.open.lease
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server'
    It 'lists the vault and the user''s notebook' {
        ((Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $state).body.notebooks | ForEach-Object { "$($_.name):$($_.vault)" }) -join ',' | Should Be 'Synthetic Vault:True,Household:False'
    }
    It 'makes a vault active: lease, record and vault id kept for the next start' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body ('{"id":"' + $w.v.vaultId + '"}') -State $state
        $r.status | Should Be 200
        $r.body.mode | Should Be 'writer'
        $state.Lease.sessionId | Should Be 'server'
        $cfg = [IO.File]::ReadAllText((Join-Path $app 'config\obsidinote.local.json')) | ConvertFrom-Json
        $cfg.vaultId | Should Be $w.v.vaultId
        $cfg.notebook | Should Be 'onenote:https://example.invalid/docs/Synthetic Vault/'
    }
    It 'asks for confirmation before it writes a vault into a notebook it does not own' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/new' -Body ('{"name":"Wiki","inNotebook":"' + $w.household + '"}') -State $state
        $r.status | Should Be 409
        $r.body.needsConfirm | Should Be $true
        @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'SectionGroup' -and $_.name -eq 'Wiki' }).Count | Should Be 0
        (Invoke-ApiRoute -Method 'POST' -Path '/api/vault/new' -Body '{"name":"../x"}' -State $state).status | Should Be 400
    }
    It 'makes a new vault inside that notebook with the confirm flag, and switches to it (the old lease given back)' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/new' -Body ('{"name":"Wiki","inNotebook":"' + $w.household + '","confirm":true}') -State $state
        $r.status | Should Be 200
        $r.body.kind | Should Be 'sectiongroup'
        $state.Vault.vaultId | Should Be $r.body.vaultId
        (Get-VaultState -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId).lease | Should Be ''
        @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.parent -and $w.f.Nodes[$_.parent].name -eq 'Garden' }).Count | Should Be 2
    }
    It 'makes a new vault as its own notebook' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/new' -Body '{"name":"Second Vault"}' -State $state
        $r.status | Should Be 200
        $r.body.kind | Should Be 'notebook'
        $r.body.warning | Should Be ''
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: setting up an empty notebook as a vault (user, 2026-11-13)' {
    $w = New-SyntheticVault -SessionId 'start'
    $null = Close-VaultSession -Adapter $w.a -Vault $w.open.vault -Lease $w.open.lease
    $empty = $w.f.AddNotebook('ObsidiNote')
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server'
    It 'offers set-up only for the empty notebook' {
        # The fake's ids are not GUID-shaped, which /api/notebook?id= refuses; read the view directly.
        # Pester 3.4's InModuleScope takes no parameters: hand the values over in globals.
        $global:ObsnSetUpCase = @{ s = $state; e = $empty; h = $w.household }
        try {
            InModuleScope Server {
                $c = $global:ObsnSetUpCase
                (Read-NotebookData $c.s 'view' -Id $c.e).notebook.canSetUp | Should Be $true
                (Read-NotebookData $c.s 'view' -Id $c.h).notebook.canSetUp | Should Be $false
            }
        } finally { Remove-Variable -Name ObsnSetUpCase -Scope Global -ErrorAction SilentlyContinue }
    }
    It 'asks for confirmation first and writes nothing without it' {
        $before = $w.f.Writes.Count
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/setup' -Body ('{"id":"' + $empty + '"}') -State $state
        $r.status | Should Be 409
        $r.body.needsConfirm | Should Be $true
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses a notebook with the person''s pages, and bad ids' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/setup' -Body ('{"id":"' + $w.household + '","confirm":true}') -State $state
        $r.status | Should Be 409
        $r.body.needsConfirm | Should Be $null
        (Invoke-ApiRoute -Method 'POST' -Path '/api/vault/setup' -Body '{"id":"","confirm":true}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/vault/setup' -Body '{"id":"../x","confirm":true}' -State $state).status | Should Be 404
    }
    It 'sets it up with the confirm flag and makes it the active vault' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/setup' -Body ('{"id":"' + $empty + '","confirm":true}') -State $state
        $r.status | Should Be 200
        $r.body.kind | Should Be 'notebook'
        $r.body.mode | Should Be 'writer'
        $state.Vault.vaultId | Should Be $r.body.vaultId
        ((Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $state).body.notebooks | Where-Object { $_.name -eq 'ObsidiNote' }).vault | Should Be $true
    }
    It 'answers the new, empty vault''s map with no pages (the window then says "No pages yet")' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        $g.status | Should Be 200
        @($g.body.pages).Count | Should Be 0
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: Add, Undo, Ask and the graph through the routes (in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $text = "An identity-aware proxy checks who the user is and which device they use before it forwards a request.`nWe use it for the partner portal instead of the old VPN."
    $sl = Get-LinkShortlist -Index (& $w.store.GetIndex) -Text $text
    $t = @($sl.topics | Where-Object { $_['path'] -eq 'Security/Networking' })[0]['id']
    $reply = '{"title": "Identity-aware proxies", "summary": "A proxy that checks user and device.", "type": "concept", "topics": [{"id": "' + $t + '"}], "links": [{"target": "p1", "anchor": "checks who the user is", "strength": 3, "why": "core concept"}], "aliases": [], "intent": "add"}'
    $ask = @('{"branches":[{"key":"Security","why":"x"}]}', '{"pages":[{"id":"p1","why":"x"}]}', '{"notFound":false,"confidence":"high","paragraphs":[{"sentences":[{"text":"It checks every request.","cites":["p1"]}]}]}')
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model -TestCopilot (New-FakeCopilotSend (@($reply) + $ask))
    $body = ConvertTo-Json -InputObject @{ text = $text; mode = 'add' } -Compress
    $add = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body $body -State $state
    It 'adds through the vault store and answers with intent add' {
        $add.status | Should Be 200
        $add.body.intent | Should Be 'add'
        $add.body.status | Should Be 'added'
        (Find-FakePage $w.f 'Identity-aware proxies') | Should Not BeNullOrEmpty
        { ConvertTo-Json -InputObject $add.body -Depth 12 } | Should Not Throw
    }
    It 'shows the new page in the graph of the active vault' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        $g.status | Should Be 200
        $g.body.source.readOnly | Should Be $false
        @($g.body.pages | ForEach-Object { $_.title }) -contains 'Identity-aware proxies' | Should Be $true
        @($g.body.edges | Where-Object { $_.to -eq 'p1' }).Count | Should Be 2
    }
    It 'answers an Ask with intent ask and sources from the index' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"mode":"ask","action":"ask","question":"How is a request checked?","sources":[],"includeArchived":false}' -State $state
        $r.status | Should Be 200
        $r.body.intent | Should Be 'ask'
        $r.body.status | Should Be 'answered'
        @($r.body.sources)[0].title | Should Be 'Zero-trust networking'
    }
    It 'undoes the Add through /api/add/undo' {
        $undo = ConvertTo-Json -InputObject @{ undo = $add.body.undo } -Depth 6 -Compress
        $u = Invoke-ApiRoute -Method 'POST' -Path '/api/add/undo' -Body $undo -State $state
        $u.status | Should Be 200
        $u.body.status | Should Be 'undone'
        (Find-FakePage $w.f 'Identity-aware proxies') | Should BeNullOrEmpty
        (Invoke-ApiRoute -Method 'POST' -Path '/api/add/undo' -Body '{"undo":5}' -State $state).status | Should Be 400
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: "Check for the answer" (POST /api/add/fetch, in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $text = 'Tidal gardens grow salt-tolerant crops where the sea reaches the land.'
    $box = @{ chat = ''; reads = 0 }
    $copilot = @{
        Send     = { param([string]$Text) [pscustomobject]@{ Text = ''; Result = 'Pending'; ChatUrl = 'https://m365.cloud.microsoft/chat/conversation/c0ffee12' } }
        NewChat  = { }
        ReadChat = { param([string]$ChatUrl) $box.reads++; @{ state = 'read'; text = $box.chat; busy = $false } }.GetNewClosure()
    }
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model -TestCopilot $copilot
    $add = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body (ConvertTo-Json -InputObject @{ text = $text; mode = 'add' } -Compress) -State $state
    $id = [string]$add.body.inboxId
    It 'answers "waiting" with the Intake item and its reference; the item is in 01 Intake with its Meta' {
        $add.status | Should Be 200
        $add.body.status | Should Be 'waiting'
        $add.body.ref | Should Match '^r[0-9a-z]{8}$'
        $n = $w.f.Nodes[$id]
        $w.f.Nodes[$n.parent].name | Should Be '01 Intake'
        $n.meta['obsn.status'] | Should Be 'waiting'
        $n.meta['obsn.requestRef'] | Should Be $add.body.ref
        $n.meta['obsn.requestKind'] | Should Be 'classify'
        $n.meta['obsn.chatUrl'] | Should Be 'https://m365.cloud.microsoft/chat/conversation/c0ffee12'
        (Find-FakePage $w.f 'Tidal gardens') | Should BeNullOrEmpty
    }
    It 'uses no answer without the reference (mismatch) and writes nothing' {
        $box.chat = '{"title": "Tidal gardens", "type": "concept", "topics": [], "links": [], "aliases": [], "intent": "add"}'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/add/fetch' -Body ('{"inboxId":"' + $id + '"}') -State $state
        $r.status | Should Be 200
        $r.body.status | Should Be 'mismatch'
        (Find-FakePage $w.f 'Tidal gardens') | Should BeNullOrEmpty
    }
    It 'files the page from the answer that carries the reference' {
        $box.chat = '{"title": "Tidal gardens", "summary": "Crops that take salt.", "type": "concept", "topics": [{"new": "Gardening"}], "links": [], "aliases": [], "intent": "add", "ref": "' + $add.body.ref + '"}'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/add/fetch' -Body ('{"inboxId":"' + $id + '"}') -State $state
        $r.status | Should Be 200
        $r.body.status | Should Be 'added'
        (Find-FakePage $w.f 'Tidal gardens') | Should Not BeNullOrEmpty
        $w.f.Nodes[$id].meta['obsn.status'] | Should Be 'linked'
        { ConvertTo-Json -InputObject $r.body -Depth 12 } | Should Not Throw
    }
    It 'refuses the item once it is filed, and bad ids' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/add/fetch' -Body ('{"inboxId":"' + $id + '"}') -State $state
        $r.status | Should Be 409
        $r.body.error | Should Match 'not waiting'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/add/fetch' -Body '{"inboxId":"../x"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/add/fetch' -Body ('{"inboxId":"' + $w.tomato + '"}') -State $state).status | Should Be 409
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: Markdown export (POST /api/export, in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $graph = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
    $writesBefore = $w.f.Writes.Count
    It 'exports the whole active vault as a zip with one file per page of the map' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"all"}' -State $state
        $r.status | Should Be 200
        $r.file.type | Should Be 'application/zip'
        $r.file.name | Should Match ' - Markdown\.zip$'
        $r.file.pages | Should Be @($graph.body.pages).Count
        $r.file.failed | Should Be 0
        $r.file.bytes[0] | Should Be 0x50
    }
    It 'exports one page of the map as .md with its title in the front matter' {
        $p = @($graph.body.pages | Where-Object { $_.id -eq 'p1' })[0]
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"page","page":"p1"}' -State $state
        $r.status | Should Be 200
        $r.file.name | Should Match '\.md$'
        (New-Object Text.UTF8Encoding $false).GetString($r.file.bytes) | Should Match ('(?m)^title: "' + [regex]::Escape($p.title) + '"$')
    }
    It 'refuses bad requests and says when a topic has no pages; it writes nothing' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"disk"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"page","page":"../x"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"all","vault":"not a vault id"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"topic","topic":"No such topic"}' -State $state).status | Should Be 404
        $w.f.Writes.Count | Should Be $writesBefore
        $w.f.Calls['GetPageContent'] | Should BeGreaterThan 0
    }
    It 'names the download for every browser (ASCII fallback plus UTF-8)' {
        InModuleScope Server { Get-ContentDisposition ('Caf' + [char]0xE9 + ' "notes".md') } | Should Be ('attachment; filename="Caf_ _notes_.md"; filename*=UTF-8''''Caf%C3%A9%20%22notes%22.md')
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: "Link it" (POST /api/link/add, in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    It 'refuses bad, equal and foreign ids and other sources without writing' {
        $before = $w.f.Writes.Count
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body 'not json' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"../x"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"x1"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"p2"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"p99"}' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"p1","vault":"cccccccc-0000-4000-8000-000000000003"}' -State $state).status | Should Be 409
        (Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p2","to":"p1","notebook":"{X}"}' -State $state).status | Should Be 409
        $w.f.Writes.Count | Should Be $before
    }
    It 'links two pages of the active vault, then says already-linked' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body ('{"from":"p2","to":"p1","vault":"' + $w.v.vaultId + '"}') -State $state
        $r.status | Should Be 200
        $r.body.status | Should Be 'linked'
        { ConvertTo-Json -InputObject $r.body -Depth 6 } | Should Not Throw
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        @($g.body.edges | Where-Object { $_.from -eq 'p2' -and $_.to -eq 'p1' }).Count | Should Be 1
        $again = Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p1","to":"p2"}' -State $state
        $again.status | Should Be 200
        $again.body.status | Should Be 'already-linked'
    }
    It 'refuses with 409 while this session is read only' {
        $state.Lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        $before = $w.f.Writes.Count
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/link/add' -Body '{"from":"p3","to":"p2"}' -State $state
        $r.status | Should Be 409
        $r.body.error | Should Match 'Read only'
        $w.f.Writes.Count | Should Be $before
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Invoke-ApiRoute: edit a page (POST /api/page/edit, in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    It 'refuses bad input and other sources without writing' {
        $before = $w.f.Writes.Count
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body 'not json' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"../x","title":"T"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p2","title":5}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p2","topics":[1]}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p2","links":[{"target":"../x"}]}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p99","title":"T"}' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p2","title":"T","notebook":"{X}"}' -State $state).status | Should Be 409
        $w.f.Writes.Count | Should Be $before
    }
    It 'saves a title and links, and the graph shows them; the graph lists the page types' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p2","title":"Access review","links":[{"target":"p1","strength":2,"why":"checks access"}]}' -State $state
        $r.status | Should Be 200
        $r.body.status | Should Be 'edited'
        { ConvertTo-Json -InputObject $r.body -Depth 6 } | Should Not Throw
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        @($g.body.pages | Where-Object { $_.id -eq 'p2' })[0].title | Should Be 'Access review'
        @($g.body.edges | Where-Object { $_.from -eq 'p2' -and $_.to -eq 'p1' -and $_.strength -eq 2 }).Count | Should Be 1
        @($g.body.types | Where-Object { $_.type -eq 'howto' })[0].bucket | Should Be 'Notes'
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Pure parts of the routes' {
    It 'routes a submit by mode and intent; unclear goes to Add in auto mode' {
        (Get-SubmitRoute -Text 'x' -Mode 'add').intent | Should Be 'add'
        (Get-SubmitRoute -Text 'What is this?' -Mode 'auto').intent | Should Be 'ask'
        (Get-SubmitRoute -Text 'https://example.org/a' -Mode 'auto').ingestMode | Should Be 'add'
        (Get-SubmitRoute -Text 'zero trust' -Mode 'auto').ingestMode | Should Be 'auto'
        (Get-SubmitRoute -Text '' -Mode 'auto').ContainsKey('error') | Should Be $true
        (Get-SubmitRoute -Text '' -Mode 'auto' -Action 'save-page').intent | Should Be 'ask'
    }
    It 'lists a vault in a section group by its group, and the notebook around it as read only' {
        $v = [pscustomobject]@{ vaultId = 'v1'; name = 'Wiki'; rootId = '{G}'; rootKind = 'sectiongroup'; notebookId = '{N}'; notebookName = 'Team'; location = 'https://example.invalid/Team/Wiki/' }
        $n = [pscustomobject]@{ id = '{N}'; name = 'Team'; location = 'https://example.invalid/Team/'; structured = $false }
        $l = ConvertTo-NotebookListing -Vaults @($v) -Notebooks @($n) -ActiveVaultId 'v1'
        ($l | ForEach-Object { "$($_.id)|$($_.name)|$($_.vault)|$($_.active)" }) -join ',' | Should Be '{G}|Wiki (in Team)|True|True,{N}|Team|False|False'
    }
}

Describe 'The live server (test port)' {
    $ui = New-TestUi
    $status = [pscustomobject]@{ app = 'ObsidiNote'; version = 'v0.0.0'; uiPort = $script:TestPort }
    $liveApp = New-TempAppRoot ('{"vaultId":"' + $script:VaultA + '"}')
    $state = New-ServerState -AppRoot $liveApp -Port $script:TestPort -FakeStatus $status -FakeHierarchyXml $script:Hier
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
            (Send-RawRequest -Port $script:TestPort -Method 'POST' -Path '/api/submit' -Headers $api -Body '{"text":"Why?","mode":"auto"}').status | Should Be 503
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
        Remove-Item $liveApp -Recurse -Force
    }
    It 'stops: the port is free again' {
        Test-UiServerRunning -Port $script:TestPort | Should Be $false
    }
}
