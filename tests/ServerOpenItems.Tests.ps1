# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The server side of the open items of 2026-11-15 (lib/Server.psm1): read only with the reason
# (GET /api/status vault.reason/since/detail, GET /api/graph source.readOnlyReason), tags through
# the routes (POST /api/pages/tag, /api/tags/rename, tags in /api/page/edit, tags in the graph),
# unreadable settings (GET /api/settings), a JSON body that is not an object, and POST /api/shutdown
# on a live server (test port, never the real 8767). In-memory OneNote; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP ('obsidinote-test-data' + $(if ($env:OBSIDINOTE_TEST_TAG) { '-' + $env:OBSIDINOTE_TEST_TAG } else { '' }))
Import-Module (Join-Path $root 'lib\Server.psm1') -Force
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'VaultSettings') { Import-Module (Join-Path $root "lib\$m.psm1") }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:TestPort = if ($env:OBSIDINOTE_TEST_PORT) { [int]$env:OBSIDINOTE_TEST_PORT } else { 18767 }

function New-TempAppRoot([string]$Local = '') {
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    if ($Local) { [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.local.json'), $Local) }
    $d
}

function Send-ApiRequest([int]$Port, [string]$Method, [string]$Path, [hashtable]$Headers = @{}, [string]$Body = '') {
    <# One raw HTTP/1.1 request; @{ status; body }. #>
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $lines = @("$Method $Path HTTP/1.1", "Host: 127.0.0.1:$Port", 'Connection: close')
    foreach ($k in $Headers.Keys) { $lines += "${k}: $($Headers[$k])" }
    if ($Method -eq 'POST') { $lines += 'Content-Type: application/json'; $lines += "Content-Length: $($bytes.Length)" }
    $head = [Text.Encoding]::ASCII.GetBytes((($lines -join "`r`n") + "`r`n`r`n"))
    $c = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $s = $c.GetStream()
        $s.Write($head, 0, $head.Length)
        if ($bytes.Length) { $s.Write($bytes, 0, $bytes.Length) }
        $text = (New-Object IO.StreamReader($s, [Text.Encoding]::UTF8)).ReadToEnd()
    } finally { $c.Close() }
    $split = $text.IndexOf("`r`n`r`n")
    @{ status = [int]([regex]::Match($text, '^HTTP/1\.\d (\d{3})').Groups[1].Value); body = $text.Substring($split + 4) }
}

function Get-Json($Answer) { ConvertTo-Json -InputObject $Answer.body -Depth 12 -Compress }

Describe 'GET /api/status: read only, with the reason' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $acq = [datetime]::SpecifyKind([datetime]'2026-11-15T08:30:00', 'Utc')
    It 'has no reason as the writer' {
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)|$($v.detail)" | Should Be 'writer|||'
        $v.name | Should Be 'Synthetic Vault'
        $v.vaultId | Should Be $w.v.vaultId
        (@($v.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should Be 'name,vaultId,mode,reason,since,until,renewed,detail'
    }
    It 'says this-pc with the time when another session of this PC holds the lease' {
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'earlier'; expires = [datetime]::UtcNow.AddSeconds(90); acquired = $acq; holderHere = $true; statePageId = ''; indexSectionId = '' }
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)|$($v.detail)" | Should Be 'readonly|this-pc|2026-11-15T08:30:00Z|'
    }
    It 'says other-pc for another computer''s lease and for a lease without a machine mark' {
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'elsewhere'; expires = [datetime]::UtcNow.AddSeconds(90); acquired = $acq; holderHere = $false; statePageId = ''; indexSectionId = '' }
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)" | Should Be 'readonly|other-pc|2026-11-15T08:30:00Z'
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'elsewhere'; expires = [datetime]::UtcNow.AddSeconds(90) }   # a record from before these fields
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)" | Should Be 'readonly|other-pc|'
    }
    It 'gives no time when this session''s own lease could not be renewed' {
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'server'; expires = [datetime]::UtcNow.AddSeconds(-5); acquired = $acq; holderHere = $false }
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)" | Should Be 'readonly|other-pc|'
    }
    It 'gives until and renewed for the holder''s lease, and none for this session''s own' {
        $exp = [datetime]::SpecifyKind([datetime]'2026-11-15T09:02:00', 'Utc')
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'earlier'; expires = $exp; acquired = $acq; holderHere = $true; statePageId = ''; indexSectionId = '' }
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.until)|$($v.renewed)" | Should Be '2026-11-15T09:02:00Z|2026-11-15T09:00:00Z'
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'server'; expires = $exp; acquired = $acq; holderHere = $false }
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault
        "$($v.until)|$($v.renewed)" | Should Be '|'
    }
    It 'derives it from the real lease record of a start next to another session of this PC' {
        $w2 = New-SyntheticVault -SessionId 'earlier'
        $item = @($w2.vaults | Where-Object { $_.vaultId -eq $w2.v.vaultId })[0]
        $o = Open-VaultSession -Adapter $w2.a -Vault $item -SessionId 'later' -Vaults $w2.vaults
        $s2 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w2.a -SessionId 'later' -Vault $o.vault -Lease $o.lease -Model $o.model
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $s2).body.vault
        "$($v.mode)|$($v.reason)" | Should Be 'readonly|this-pc'
        $v.since | Should Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
    }
    It 'says not-opened with the start''s Vault line when no vault is open' {
        $f = New-FakeOneNote
        $nb = $f.AddNotebook('Plain notebook')
        $null = $f.AddPage($f.AddSection($nb, 'Notes'), 'A page', @{}, 1, 'x')
        $s3 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter (New-GuardedOneNote -Inner $f) -SessionId 'server' -VaultDetail 'could not be opened: No state page in this vault.'
        $v = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $s3).body.vault
        "$($v.mode)|$($v.reason)|$($v.since)|$($v.detail)" | Should Be 'none|not-opened||could not be opened: No state page in this vault.'
        $s4 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter (New-GuardedOneNote -Inner $f) -SessionId 'server'
        $v4 = (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $s4).body.vault
        "$($v4.mode)|$($v4.reason)|$($v4.detail)" | Should Be 'none|not-opened|'
    }
    It 'keeps mode on /api/notebooks and adds nothing there' {
        $n = (Invoke-ApiRoute -Method 'GET' -Path '/api/notebooks' -State $state).body
        (@($n.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should Be 'notebooks,message,activeVaultId,mode'
    }
    Remove-Item $app -Recurse -Force
}

Describe 'GET /api/graph: source.readOnlyReason and tags' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    It 'is empty for the active vault as the writer, with tags as lists' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        $g.status | Should Be 200
        $g.body.source.readOnly | Should Be $false
        $g.body.source.readOnlyReason | Should Be ''
        $j = Get-Json $g
        $j | Should Match '"tags":\[\],"edgesComplete"'
        $j | Should Match '"origin":"[^"]*","tags":\[\]\}'
    }
    It 'is notebook for a connected notebook' {
        # The read-only hierarchy fixture: its ids have OneNote's shape, which the route checks.
        $xml = [IO.File]::ReadAllText((Join-Path $here 'fixtures\hierarchy.xml'))
        $sx = New-ServerState -AppRoot $app -Port 8767 -FakeHierarchyXml $xml
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query "notebook=$([Uri]::EscapeDataString('{33333333-3333-3333-3333-333333333333}{1}{B0}'))" -State $sx
        $g.status | Should Be 200
        "$($g.body.source.kind)|$($g.body.source.readOnly)|$($g.body.source.readOnlyReason)" | Should Be 'notebook|True|notebook'
    }
    It 'is lease for the active vault while this window is not its writer' {
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'elsewhere'; expires = [datetime]::UtcNow.AddSeconds(90) }
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        "$($g.body.source.readOnly)|$($g.body.source.readOnlyReason)" | Should Be 'True|lease'
    }
    It 'is not-active for a vault that is not the active one' {
        # A second server whose active vault is another one: the first vault is then "not active".
        $f = $w.f
        $second = New-ObsidiVault -Adapter $w.a -Name 'Second Vault' -Location 'https://example.invalid/docs' -Year 2026
        Set-OneNoteWriteRoot -Adapter $w.a -RootId $w.open.vault.rootId
        $s2 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body ('{"id":"' + $second.vaultId + '"}') -State $s2).status | Should Be 200
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -Query "vault=$($w.v.vaultId)" -State $s2
        $g.status | Should Be 200
        "$($g.body.source.readOnly)|$($g.body.source.readOnlyReason)" | Should Be 'True|not-active'
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Tags through the routes (POST /api/pages/tag, /api/tags/rename, /api/page/edit)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    It 'refuses bad input with 400 and writes nothing' {
        $before = $w.f.Writes.Count
        foreach ($b in 'not json', '{}', '{"ids":[],"add":["a"]}', '{"ids":["p1"]}', '{"ids":["p1"],"add":[],"remove":[]}', '{"ids":["p1"],"add":["a:b"]}', '{"ids":["p1"],"add":["a,b"]}',
            '{"ids":["p1"],"add":"a"}', '{"ids":"p1","add":["a"]}', '{"ids":["p1"],"add":[5]}', '{"ids":["../x"],"add":["a"]}', '{"ids":["p1"],"remove":["a\nb"]}') {
            (Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body $b -State $state).status | Should Be 400
        }
        $many = '{"ids":[' + ((1..201 | ForEach-Object { '"p' + $_ + '"' }) -join ',') + '],"add":["a"]}'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body $many -State $state
        $r.status | Should Be 400
        $r.body.error | Should Be 'At most 200 pages at a time.'
        $w.f.Writes.Count | Should Be $before
    }
    It 'answers 404 for an id that is not a page of the vault, and writes nothing' {
        $before = $w.f.Writes.Count
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body '{"ids":["p1","p99"],"add":["a"]}' -State $state
        $r.status | Should Be 404
        $w.f.Writes.Count | Should Be $before
    }
    It 'answers 409 with the other-vault sentence for another vault''s id' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body '{"ids":["p1"],"add":["a"],"vault":"cccccccc-0000-4000-8000-000000000003"}' -State $state
        $r.status | Should Be 409
        $r.body.error | Should Be 'This item belongs to another vault; open that vault to change it.'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"a","to":"b","vault":"cccccccc-0000-4000-8000-000000000003"}' -State $state).status | Should Be 409
    }
    It 'tags the pages and answers {changed, pages, warnings} with lists' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body ('{"ids":["p1","p2"],"add":["Licensing"],"vault":"' + $w.v.vaultId + '"}') -State $state
        $r.status | Should Be 200
        (Get-Json $r) | Should Be '{"changed":2,"pages":[{"id":"p1","tags":["licensing"]},{"id":"p2","tags":["licensing"]}],"warnings":[]}'
        $p1.meta['obsn.tags'] | Should Be '["licensing"]'
        $one = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body '{"ids":["p2"],"remove":["licensing"]}' -State $state
        (Get-Json $one) | Should Be '{"changed":1,"pages":[{"id":"p2","tags":[]}],"warnings":[]}'
    }
    It 'shows them in the graph, per page and for the source' {
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        $j = Get-Json $g
        $j | Should Match '"tags":\[\{"name":"licensing","count":1\}\],"edgesComplete"'
        (@(@($g.body.pages | Where-Object { $_.id -eq 'p1' })[0].tags) -join '|') | Should Be 'licensing'
    }
    It 'accepts tags in /api/page/edit, only when sent' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p1","summary":"Changed."}' -State $state).status | Should Be 200
        $p1.meta['obsn.tags'] | Should Be '["licensing"]'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p1","tags":["Licensing","Key Ref"]}' -State $state
        $r.status | Should Be 200
        $p1.meta['obsn.tags'] | Should Be '["licensing","key ref"]'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p1","tags":["a:b"]}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body '{"id":"p1","tags":[5]}' -State $state).status | Should Be 400
        $p1.meta['obsn.tags'] | Should Be '["licensing","key ref"]'
    }
    It 'renames a tag, and removes it with an empty new name' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"","to":"x"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"key ref","to":"a:b"}' -State $state).status | Should Be 400
        (Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":5,"to":"x"}' -State $state).status | Should Be 400
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"Key Ref","to":"Reference"}' -State $state
        $r.status | Should Be 200
        (Get-Json $r) | Should Be '{"changed":1,"warnings":[]}'
        $p1.meta['obsn.tags'] | Should Be '["licensing","reference"]'
        $d = Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"licensing","to":""}' -State $state
        $d.body.changed | Should Be 1
        $p1.meta['obsn.tags'] | Should Be '["reference"]'
    }
    It 'answers 409 without the writer lease' {
        $before = $w.f.Writes.Count
        $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'elsewhere'; expires = [datetime]::UtcNow.AddSeconds(90) }
        (Invoke-ApiRoute -Method 'POST' -Path '/api/pages/tag' -Body '{"ids":["p1"],"add":["a"]}' -State $state).status | Should Be 409
        (Invoke-ApiRoute -Method 'POST' -Path '/api/tags/rename' -Body '{"from":"reference","to":"x"}' -State $state).status | Should Be 409
        $w.f.Writes.Count | Should Be $before
    }
    Remove-Item $app -Recurse -Force
}

Describe 'GET /api/settings when the stored settings cannot be read' {
    $w = New-SyntheticVault -SessionId 'start'
    $null = Close-VaultSession -Adapter $w.a -Vault $w.open.vault -Lease $w.open.lease
    $app = New-TempAppRoot
    $st = Get-VaultState -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId
    $w.f.Nodes[$st.statePageId].meta['obsn.settings'] = '{"graphView":"sources","internalHosts":["wiki.exa'    # cut off
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server'
    It 'has an empty message and no problem before a vault is open' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/settings' -State $state
        $r.body.canChange | Should Be $false
        $r.body.message | Should Be ''
    }
    It 'says canChange false with the sentence the refusal uses, as the writer' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/active-vault' -Body ('{"id":"' + $w.v.vaultId + '"}') -State $state).status | Should Be 200
        (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $state).body.vault.mode | Should Be 'writer'
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/settings' -State $state
        $r.body.canChange | Should Be $false
        $r.body.message | Should Match '^The settings stored in this vault could not be read, so nothing was changed\.'
        $r.body.settings.graphView | Should Be 'topics'
        $p = Invoke-ApiRoute -Method 'POST' -Path '/api/settings' -Body '{"key":"graphView","value":"sources"}' -State $state
        $p.status | Should Be 400
        $p.body.error | Should Be $r.body.message
        $w.f.Nodes[$st.statePageId].meta['obsn.settings'] | Should Be '{"graphView":"sources","internalHosts":["wiki.exa'
    }
    It 'takes the start''s finding through New-ServerState too' {
        $s2 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $state.Vault -Lease $state.Lease -SettingsUnreadable $true
        (Invoke-ApiRoute -Method 'GET' -Path '/api/settings' -State $s2).body.canChange | Should Be $false
        $s3 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $state.Vault -Lease $state.Lease
        $ok = Invoke-ApiRoute -Method 'GET' -Path '/api/settings' -State $s3
        $ok.body.canChange | Should Be $true
        $ok.body.message | Should Be ''
    }
    Remove-Item $app -Recurse -Force
}

Describe 'A JSON body that is not an object is refused with 400' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $bodies = @('5', '"text"', '[1,2]', '[{"id":"p1"}]', 'null', 'true', '0', '""')
    foreach ($route in '/api/intent', '/api/submit', '/api/active-vault', '/api/vault/new', '/api/vault/setup', '/api/add/undo', '/api/add/fetch', '/api/link/update', '/api/link/add',
        '/api/page/edit', '/api/export', '/api/settings', '/api/intake/remove', '/api/file/locate', '/api/pages/tag', '/api/tags/rename') {
        It "$route" {
            $before = $w.f.Writes.Count
            foreach ($b in $bodies) {
                $r = Invoke-ApiRoute -Method 'POST' -Path $route -Body $b -State $state
                "$b -> $($r.status)" | Should Be "$b -> 400"
            }
            $w.f.Writes.Count | Should Be $before
        }
    }
    It 'refuses a field that must be an object and is not (undo, a link)' {
        foreach ($b in '{"undo":5}', '{"undo":"p1"}', '{"undo":[{"id":"p1"}]}', '{"undo":true}') {
            (Invoke-ApiRoute -Method 'POST' -Path '/api/add/undo' -Body $b -State $state).status | Should Be 400
        }
        foreach ($b in '{"id":"p1","links":[5]}', '{"id":"p1","links":["p2"]}', '{"id":"p1","links":[["p2"]]}') {
            (Invoke-ApiRoute -Method 'POST' -Path '/api/page/edit' -Body $b -State $state).status | Should Be 400
        }
        $w.f.Nodes.ContainsKey((Find-FakePage $w.f 'Zero-trust networking').id) | Should Be $true
    }
    It 'still takes an object' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intent' -Body '{"text":"https://example.com/a","mode":"auto"}' -State $state).status | Should Be 200
    }
    Remove-Item $app -Recurse -Force
}

Describe 'POST /api/vault/check-lease: "Check again" tries to take the vault now' {
    # operator, 2026-11-15: "Check again" only read the status again, so the note stayed until the
    # next renewal of the lease (every minute) even when nothing held the vault any more.
    $app = New-TempAppRoot
    It 'takes the lease at once when the earlier holder gave it back' {
        $w = New-SyntheticVault -SessionId 'earlier'
        $item = @($w.vaults | Where-Object { $_.vaultId -eq $w.v.vaultId })[0]
        $o = Open-VaultSession -Adapter $w.a -Vault $item -SessionId 'later' -Vaults $w.vaults
        $o.lease.mode | Should Be 'readonly'
        $s = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'later' -Vault $o.vault -Lease $o.lease -Model $o.model
        $null = Clear-WriterLease -Adapter $w.a -Lease $w.open.lease
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/check-lease' -State $s
        $r.status | Should Be 200
        "$($r.body.mode)|$($r.body.reason)|$($r.body.until)" | Should Be 'writer||'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/status' -State $s).body.vault.mode | Should Be 'writer'
    }
    It 'never takes a lease the holder still has, and says until when it runs and when it was renewed' {
        $w = New-SyntheticVault -SessionId 'earlier'
        $item = @($w.vaults | Where-Object { $_.vaultId -eq $w.v.vaultId })[0]
        $o = Open-VaultSession -Adapter $w.a -Vault $item -SessionId 'later' -Vaults $w.vaults
        $s = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'later' -Vault $o.vault -Lease $o.lease -Model $o.model
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/vault/check-lease' -State $s
        $r.status | Should Be 200
        "$($r.body.mode)|$($r.body.reason)" | Should Be 'readonly|this-pc'
        $r.body.until | Should Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
        $r.body.renewed | Should Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
        # The holder still has it: nothing about the vault changed hands.
        $st = Get-VaultState -Adapter $w.a -IndexSectionId $o.lease.indexSectionId
        (ConvertFrom-LeaseValue $st.lease).session | Should Be 'earlier'
    }
    It 'answers 409 without an open vault' {
        $f = New-FakeOneNote
        $s3 = New-ServerState -AppRoot $app -Port 8767 -TestAdapter (New-GuardedOneNote -Inner $f) -SessionId 'server'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/vault/check-lease' -State $s3).status | Should Be 409
    }
}

Describe 'Archive, Restore and Delete through the routes (POST /api/pages/archive|restore|delete)' {
    $w = New-SyntheticVault -SessionId 'server'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    It 'refuses bad input with 400 and writes nothing' {
        $before = $w.f.Writes.Count
        foreach ($b in 'not json', '{}', '{"ids":[]}', '{"ids":"p1"}', '{"ids":[5]}', '{"ids":["../x"],"confirm":true}') {
            (Invoke-ApiRoute -Method 'POST' -Path '/api/pages/archive' -Body $b -State $state).status | Should Be 400
        }
        $w.f.Writes.Count | Should Be $before
    }
    It 'archive and delete always ask first: 409 needsConfirm with the plan, nothing written' {
        $before = $w.f.Writes.Count
        foreach ($b in '{"ids":["p1"]}', '{"ids":["p1"],"confirm":"yes"}', '{"ids":["p1"],"confirm":1}') {
            $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/delete' -Body $b -State $state
            $r.status | Should Be 409
            $r.body.needsConfirm | Should Be $true
        }
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/archive' -Body '{"ids":["p1","p99"]}' -State $state
        (Get-Json $r) | Should Match '"plan":\{"pages":\[\{"id":"p1","title":"Zero-trust networking","section":"Notes","to":"Archive/Notes","inbound":1\}\],"refused":\[\{"id":"p99"'
        $w.f.Writes.Count | Should Be $before
    }
    It 'answers 409 with the other-vault sentence for another vault''s ids' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/archive' -Body '{"ids":["p1"],"confirm":true,"vault":"cccccccc-0000-4000-8000-000000000003"}' -State $state
        $r.status | Should Be 409
        $r.body.error | Should Be 'This item belongs to another vault; open that vault to change it.'
    }
    It 'archives with confirm, restores without, and answers lists' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/archive' -Body ('{"ids":["p1"],"confirm":true,"vault":"' + $w.v.vaultId + '"}') -State $state
        $r.status | Should Be 200
        (Get-Json $r) | Should Match '^\{"status":"done","message":"Archived: Zero-trust networking\. Restore brings it back\.","action":"archive","done":\[\{"id":"p1","title":"Zero-trust networking","to":"Archive/Notes"\}\],"refused":\[\],"failed":\[\],"warnings":\[\]\}$'
        $g = Invoke-ApiRoute -Method 'GET' -Path '/api/graph' -State $state
        @($g.body.pages | Where-Object { $_.id -eq 'p1' })[0].archived | Should Be $true
        $r2 = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/restore' -Body '{"ids":["p1"]}' -State $state
        $r2.status | Should Be 200
        $r2.body.status | Should Be 'done'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/pages/restore' -Body '{"ids":["p1"]}' -State $state).status | Should Be 400
    }
    It 'deletes with confirm' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/pages/delete' -Body '{"ids":["p2"],"confirm":true}' -State $state
        $r.status | Should Be 200
        $r.body.message | Should Match '60 days'
        $w.open.model.pages.Contains('p2') | Should Be $false
    }
}

Describe 'POST /api/shutdown on the live server (test port)' {
    $ui = Join-Path $env:TEMP ('obsn-ui-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $ui
    [IO.File]::WriteAllText((Join-Path $ui 'index.html'), '<!doctype html><title>ObsidiNote</title>')
    $app = New-TempAppRoot
    $status = [pscustomobject]@{ app = 'ObsidiNote'; version = 'v0.0.0'; uiPort = $script:TestPort }
    $state = New-ServerState -AppRoot $app -Port $script:TestPort -FakeStatus $status
    $server = Start-UiServer -Port $script:TestPort -UiDir $ui -State $state
    $api = @{ 'X-ObsidiNote' = '1'; Origin = "http://127.0.0.1:$($script:TestPort)" }
    try {
        It 'is guarded like every other POST: no header, a foreign origin, a GET' {
            (Send-ApiRequest $script:TestPort 'POST' '/api/shutdown' @{} '{}').status | Should Be 403
            (Send-ApiRequest $script:TestPort 'POST' '/api/shutdown' @{ 'X-ObsidiNote' = '1'; Origin = 'http://localhost.evil.example' } '{}').status | Should Be 403
            (Send-ApiRequest $script:TestPort 'GET' '/api/shutdown' $api).status | Should Be 404
            $state.Stop | Should Be $false
            $server.Async.IsCompleted | Should Be $false
            (Send-ApiRequest $script:TestPort 'GET' '/api/status' $api).status | Should Be 200
        }
        It 'answers 200 {"stopping":true} and then ends the server loop by itself' {
            $r = Send-ApiRequest $script:TestPort 'POST' '/api/shutdown' $api '{}'
            $r.status | Should Be 200
            $r.body | Should Be '{"stopping":true}'
            $server.Async.AsyncWaitHandle.WaitOne(5000) | Should Be $true     # the loop ended; nobody called Stop-UiServer
            $state.Stop | Should Be $true
            $state.StopReason | Should Be 'shutdown'
        }
    } finally {
        Stop-UiServer $server
        Remove-Item $ui -Recurse -Force
        Remove-Item $app -Recurse -Force
    }
    It 'leaves the port silent after the start''s finally' {
        Test-UiServerRunning -Port $script:TestPort | Should Be $false
    }
}
