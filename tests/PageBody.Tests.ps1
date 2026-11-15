# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The page window's text: lib/MarkdownExport.psm1 Get-PageBody (the export's converter with
# -LinkStyle page, the summary left out, cut at 20,000 characters) and GET /api/page/body
# (lib/Server.psm1), in process on the in-memory OneNote and over HTTP on the test port (never the
# real 8767). tests/fixtures/page-body.json is what the server sends for the invented pages of
# tests/PageBodyPages.ps1; the interface's renderer test reads the same file: change them together.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP ('obsidinote-test-data' + $(if ($env:OBSIDINOTE_TEST_TAG) { '-' + $env:OBSIDINOTE_TEST_TAG } else { '' }))
Import-Module (Join-Path $root 'lib\Server.psm1') -Force
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'VaultSettings', 'MarkdownExport') { Import-Module (Join-Path $root "lib\$m.psm1") }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')
. (Join-Path $here 'PageBodyPages.ps1')

$script:TestPort = if ($env:OBSIDINOTE_TEST_PORT) { [int]$env:OBSIDINOTE_TEST_PORT } else { 18767 }
$script:Reading = '{33333333-3333-3333-3333-333333333333}{1}{B0}'
$script:ReadingPage = 'n:{33333333-3333-3333-3333-333333333335}{1}{E1}'
$script:VaultA = 'aaaaaaaa-0000-4000-8000-000000000001'

function New-TempAppRoot([string]$Local = '') {
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    if ($Local) { [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.local.json'), $Local) }
    $d
}

function Send-ApiRequest([int]$Port, [string]$Path, [hashtable]$Headers = @{}) {
    <# One raw HTTP/1.1 GET; @{ status; body }. #>
    $lines = @("GET $Path HTTP/1.1", "Host: 127.0.0.1:$Port", 'Connection: close')
    foreach ($k in $Headers.Keys) { $lines += "${k}: $($Headers[$k])" }
    $head = [Text.Encoding]::ASCII.GetBytes((($lines -join "`r`n") + "`r`n`r`n"))
    $c = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $s = $c.GetStream()
        $s.Write($head, 0, $head.Length)
        $text = (New-Object IO.StreamReader($s, [Text.Encoding]::UTF8)).ReadToEnd()
    } finally { $c.Close() }
    $split = $text.IndexOf("`r`n`r`n")
    @{ status = [int]([regex]::Match($text, '^HTTP/1\.\d (\d{3})').Groups[1].Value); body = $text.Substring($split + 4) }
}

function Get-CaseBody([string]$Xml) {
    $x = $Xml
    Get-PageBody -Model (Get-PageBodyModel) -Key 'p1' -ReadPage { param($Id) $x }.GetNewClosure()
}

Describe 'The page window''s text matches tests/fixtures/page-body.json (shared with the interface)' {
    $want = Get-Content -Raw -Encoding UTF8 (Join-Path $here 'fixtures\page-body.json') | ConvertFrom-Json
    $cases = Get-PageBodyCases
    It 'has one fixture case per invented page, in the same order' {
        (@($want.cases) | ForEach-Object { $_.name }) -join '|' | Should Be (@($cases.Keys) -join '|')
    }
    foreach ($c in @($want.cases)) {
        It "case: $($c.name)" {
            $r = Get-CaseBody $cases[$c.name]
            $r.markdown | Should BeExactly $c.markdown
            $r.truncated | Should Be $false
            $r.length | Should Be $c.markdown.Length
            $r.id | Should Be 'p1'
        }
    }
}

Describe 'Get-PageBody: what the text holds' {
    $cases = Get-PageBodyCases
    It 'writes headings, a bulleted list, a table and code' {
        $h = (Get-CaseBody $cases['headings and styled text']).markdown
        $h | Should Match '(?m)^# Overview$'
        $h | Should Match '(?m)^## Own heading$'
        (Get-CaseBody $cases['bulleted, numbered and task lists']).markdown | Should Match "(?m)^- Check the user\n    - with a second factor$"
        $t = (Get-CaseBody $cases['a table']).markdown
        $t | Should Match '(?m)^\| Name \| Use \|\n\| --- \| --- \|$'
        (Get-CaseBody $cases['code']).markdown | Should Match '(?m)^`if \(\$ok\) \{ start \}`$'
    }
    It 'writes a link to a page of the map as obsn:<page id>, by link, by obsn id and by OneNote page id' {
        $l = (Get-CaseBody $cases['links']).markdown
        $l.Contains('See [the portal](obsn:p2) and [Partner portal](obsn:p2).') | Should Be $true
        $l.Contains('[the list](obsn:n:{44444444-4444-4444-4444-444444444444}{1}{E1})') | Should Be $true
        $l | Should Not Match '\[\['
    }
    It 'keeps http, https, mailto and onenote links, with nothing in the address that ends it early' {
        $l = (Get-CaseBody $cases['links']).markdown
        $l.Contains('[the guide](https://example.com/guide?a=1&b=2)') | Should Be $true
        $l.Contains('[an old page](http://example.com/a%20%28b%29/c)') | Should Be $true
        $l.Contains('[the owner](mailto:someone@example.com)') | Should Be $true
        $l.Contains('[a page outside the map](onenote:https://team.example/Elsewhere.one#Other%20page&page-id=') | Should Be $true
    }
    It 'writes any other link as plain text (javascript:, file:, data:)' {
        $l = (Get-CaseBody $cases['links']).markdown
        $l.Contains('Never a script: click me, a file or data.') | Should Be $true
        $l | Should Not Match '(?i)javascript:|file:|data:'
    }
    It 'leaves out the summary, the properties and "Linked from"; keeps the body, "Your notes" and the person''s own outline' {
        $o = (Get-CaseBody $cases['outlines: summary, properties and Linked from left out, Your notes kept']).markdown
        $o | Should Not Match 'SUMMARY'
        $o | Should Not Match 'Type: concept'
        $o | Should Not Match 'Linked from'
        $o | Should Match '(?m)^The body stays\.$'
        $o | Should Match '(?m)^## Your notes\n\nMy own words stay\.$'
        $o | Should Match 'An outline the person made stays too\.'
        $o | Should Match 'not shown here'
        $o | Should Not Match 'export'
    }
    It 'has no front matter and no title line' {
        foreach ($k in $cases.Keys) {
            $md = (Get-CaseBody $cases[$k]).markdown
            $md.StartsWith('---') | Should Be $false
            $md | Should Not Match 'Identity-aware proxies'
        }
    }
    It 'gives an empty page as an empty text that is not cut' {
        $r = Get-CaseBody $cases['an empty page']
        $r.markdown | Should BeExactly ''
        $r.truncated | Should Be $false
        $r.length | Should Be 0
    }
    It 'says not-found for a key that is no page of the model, without reading OneNote' {
        $box = @{ reads = 0 }
        $r = Get-PageBody -Model (Get-PageBodyModel) -Key 'p99' -ReadPage { param($Id) $box.reads++; '' }.GetNewClosure()
        $r.error | Should Be 'not-found'
        $box.reads | Should Be 0
    }
    It 'leaves the export as it was: wikilinks, the summary outline kept, its own left-out line' {
        $m = Get-PageBodyModel
        $names = @{ 'onenote:#p2' = 'Partner portal' }
        ConvertFrom-OneHtml '<a href="onenote:#p2">the portal</a>' -Targets $names | Should Be '[[Partner portal|the portal]]'
        ConvertFrom-OneHtml '<a href="https://example.com/a">x</a>' | Should Be '[x](<https://example.com/a>)'
        $e = ConvertFrom-OnePageXml -Xml $cases['outlines: summary, properties and Linked from left out, Your notes kept']
        $e | Should Match 'SUMMARY'
        $e | Should Match 'left out of the export'
        $e | Should Not Match 'Type: concept'
    }
}

Describe 'The cut at 20,000 characters' {
    # 300 paragraphs of 99 characters, joined by a blank line: 300 * 99 + 299 * 2 = 30,298 characters.
    $line = ('word ' * 20).Substring(0, 99)
    $long = New-BodyPageXml (New-BodyOutline 'body' ((1..300 | ForEach-Object { New-BodyOe $line }) -join ''))
    $r = Get-CaseBody $long
    It 'cuts at the last line break before the limit and reports the full length' {
        $r.truncated | Should Be $true
        $r.length | Should Be 30298
        ($r.markdown.Length -le 20000) | Should Be $true
        # 198 whole paragraphs fit (198 * 99 + 197 * 2 = 19,996); the 199th would pass the limit.
        $r.markdown.Length | Should Be 19996
        $r.markdown.EndsWith($line) | Should Be $true
        @($r.markdown -split "`n`n").Count | Should Be 198
    }
    It 'does not cut a text of exactly the limit, and cuts one character more' {
        $a = Limit-BodyText -Markdown (("a" * 9999) + "`n" + ("b" * 10000))
        "$($a.truncated) $($a.length) $($a.markdown.Length)" | Should Be 'False 20000 20000'
        $b = Limit-BodyText -Markdown (("a" * 9999) + "`n" + ("b" * 10001))
        "$($b.truncated) $($b.length) $($b.markdown.Length)" | Should Be 'True 20001 9999'
    }
    It 'cuts a text without a line break at the limit, never inside a surrogate pair' {
        $c = Limit-BodyText -Markdown ('x' * 25000)
        "$($c.truncated) $($c.length) $($c.markdown.Length)" | Should Be 'True 25000 20000'
        $pair = [char]::ConvertFromUtf32(0x1F600)
        $d = Limit-BodyText -Markdown (('x' * 9) + $pair + 'yyyy') -Max 10
        $d.markdown | Should BeExactly ('x' * 9)
        (Limit-BodyText -Markdown "ab`ncd`nef" -Max 7).markdown | Should BeExactly "ab`ncd"
    }
}

Describe 'GET /api/page/body (in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'server'
    # p1 gets the outlines ObsidiNote writes, with a link to p3 by its obsn id.
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $p1.outlines.Clear()
    foreach ($x in @(
            (New-BodyOutline 'props' (New-BodyOe 'Type: concept')),
            (New-BodyOutline 'summary' (New-BodyOe 'SUMMARY text')),
            (New-BodyOutline 'body' ((New-BodyOe 'Never trust the network.') + (New-BodyOe 'It replaces <a href="onenote:#p3">the old VPN</a>; see <a href="https://example.com/zt">the guide</a>.'))),
            (New-BodyOutline 'backlinks' (New-BodyOe 'Linked from')),
            (New-BodyOutline 'notes' (New-BodyOe 'My own words.')))) { $null = $p1.outlines.Add(@{ objectId = '{X}'; role = ''; xml = $x }) }
    # A second vault, never the active one.
    $v2 = New-ObsidiVault -Adapter $w.a -Name 'Team Vault' -Location 'https://example.invalid/team' -Year 2026
    $null = $w.f.AddPage($v2.sectionIds['Notes'], 'Other vault page', @{ 'obsn.id' = 'p7'; 'obsn.type' = 'note'; 'obsn.links' = '[]' }, 1, 'Text of the other vault.')
    $vaults = @(Get-VaultList -Adapter $w.a)
    $o2 = Open-VaultSession -Adapter $w.a -Vault (@($vaults | Where-Object { $_.vaultId -eq $v2.vaultId })[0]) -SessionId 'server' -Vaults $vaults
    $null = Close-VaultSession -Adapter $w.a -Vault $o2.vault -Lease $o2.lease
    Set-OneNoteWriteRoot -Adapter $w.a -RootId $w.open.vault.rootId
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $writesBefore = $w.f.Writes.Count
    $esc = { param([string]$s) [Uri]::EscapeDataString($s) }

    It 'answers the active vault''s page: id, markdown, truncated, length' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1' -State $state
        $r.status | Should Be 200
        (@($r.body.Keys) -join ',') | Should Be 'id,markdown,truncated,length'
        $r.body.id | Should Be 'p1'
        $r.body.markdown | Should BeExactly "Never trust the network.`n`nIt replaces [the old VPN](obsn:p3); see [the guide](https://example.com/zt).`n`nMy own words."
        $r.body.truncated | Should Be $false
        $r.body.length | Should Be $r.body.markdown.Length
        (ConvertTo-Json -InputObject $r.body -Compress) | Should Match '^\{"id":"p1","markdown":"Never trust.*","truncated":false,"length":\d+\}$'
    }
    It 'answers the same page when the active vault is named' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query "page=p1&vault=$($w.v.vaultId)" -State $state
        "$($r.status) $($r.body.id)" | Should Be '200 p1'
    }
    It 'reads a page of a vault that is not the active one' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query "page=p7&vault=$($v2.vaultId)" -State $state
        $r.status | Should Be 200
        $r.body.markdown | Should BeExactly 'Text of the other vault.'
        # p7 is no page of the active vault
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p7' -State $state).status | Should Be 404
    }
    # A connected notebook: the live server below (the in-memory OneNote's ids are no notebook ids).
    It 'is 400 for a missing or malformed page, vault or notebook' {
        foreach ($q in '', 'page=', 'page=..%2Fx', 'page=P1', 'page=n%3Ax', 'page=p1%20', "page=$('p' + ('a' * 230))", 'vault=aaaaaaaa-0000-4000-8000-000000000001') {
            $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query $q -State $state
            "$q -> $($r.status) $($r.body.error)" | Should Be "$q -> 400 page must be a page id of the map."
        }
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1&vault=not%20a%20vault' -State $state).body.error | Should Be 'vault must be a vault id.'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1&notebook=x' -State $state).body.error | Should Be 'notebook must be a OneNote notebook id.'
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1&notebook=x' -State $state).status | Should Be 400
    }
    It 'is 404 for a page that is not in the index, and for a vault or notebook that is not open' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p99' -State $state
        "$($r.status) $($r.body.error)" | Should Be "404 Page p99 is not in this vault's index."
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1&vault=cccccccc-0000-4000-8000-000000000003' -State $state).status | Should Be 404
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1&notebook=%7B99999999-9999-9999-9999-999999999999%7D%7B1%7D%7BB0%7D' -State $state).status | Should Be 404
        # a page of the active vault asked from the other vault
        (Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query "page=p3&vault=$($v2.vaultId)" -State $state).status | Should Be 404
    }
    It 'is 409 without a vault, as the export is' {
        $none = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server'
        $b = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p1' -State $none
        $e = Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"page","page":"p1"}' -State $none
        "$($b.status) $($b.body.error)" | Should Be "$($e.status) $($e.body.error)"
        $b.status | Should Be 409
    }
    It 'only reads: no OneNote write, and it is a GET (a POST is no route)' {
        $w.f.Writes.Count | Should Be $writesBefore
        $w.f.Calls['GetPageContent'] | Should BeGreaterThan 0
        (Invoke-ApiRoute -Method 'POST' -Path '/api/page/body' -Body '{"page":"p1"}' -State $state).status | Should Be 404
    }
    It 'still refuses the same ids in the export (the shared checks)' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"page","page":"../x"}' -State $state).body.error | Should Be 'page must be a page id of the map.'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"all","vault":"not a vault id"}' -State $state).body.error | Should Be 'vault must be a vault id.'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"all","notebook":"x"}' -State $state).body.error | Should Be 'notebook must be a OneNote notebook id.'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/export' -Body '{"scope":"page","page":"p2"}' -State $state).status | Should Be 200
    }
    It 'is 500 without any page text when the page cannot be read' {
        # What OneNote hands over is not XML: the read fails, as a COM error would.
        $null = (Find-FakePage $w.f 'VPN retirement plan').outlines.Add(@{ objectId = '{Y}'; role = ''; xml = '<one:Outline><one:OEChildren>SECRET' })
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/page/body' -Query 'page=p3' -State $state
        $r.status | Should Be 500
        $r.body.error | Should Be 'The page could not be read from OneNote. Try again.'
        (ConvertTo-Json -InputObject $r.body -Compress) | Should Not Match 'SECRET'
    }
    Remove-Item $app -Recurse -Force
}

Describe 'GET /api/page/body on the live server (test port)' {
    $ui = Join-Path $env:TEMP ('obsn-ui-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $ui
    [IO.File]::WriteAllText((Join-Path $ui 'index.html'), '<!doctype html><title>ObsidiNote</title>')
    $app = New-TempAppRoot ('{"vaultId":"' + $script:VaultA + '"}')
    $status = [pscustomobject]@{ app = 'ObsidiNote'; version = 'v0.0.0'; uiPort = $script:TestPort }
    $hier = [IO.File]::ReadAllText((Join-Path $here 'fixtures\hierarchy.xml'))
    $state = New-ServerState -AppRoot $app -Port $script:TestPort -FakeStatus $status -FakeHierarchyXml $hier
    $server = Start-UiServer -Port $script:TestPort -UiDir $ui -State $state
    $api = @{ 'X-ObsidiNote' = '1'; Origin = "http://127.0.0.1:$($script:TestPort)" }
    $q = "/api/page/body?page=$([Uri]::EscapeDataString($script:ReadingPage))&notebook=$([Uri]::EscapeDataString($script:Reading))"
    try {
        It 'is guarded like every API call: the header, and an allowed Origin when one is sent' {
            (Send-ApiRequest $script:TestPort $q).status | Should Be 403
            (Send-ApiRequest $script:TestPort $q @{ 'X-ObsidiNote' = '1'; Origin = 'http://localhost.evil.example' }).status | Should Be 403
        }
        It 'answers a connected notebook''s page as JSON (a page without text: empty, not cut)' {
            $r = Send-ApiRequest $script:TestPort $q $api
            $r.status | Should Be 200
            $r.body | Should BeExactly ('{"id":"' + $script:ReadingPage + '","markdown":"","truncated":false,"length":0}')
        }
        It 'answers 400 and 404 with { error } over HTTP' {
            $bad = Send-ApiRequest $script:TestPort '/api/page/body' $api
            $bad.status | Should Be 400
            ($bad.body | ConvertFrom-Json).error | Should Be 'page must be a page id of the map.'
            $gone = Send-ApiRequest $script:TestPort "/api/page/body?page=p99&notebook=$([Uri]::EscapeDataString($script:Reading))" $api
            $gone.status | Should Be 404
            ($gone.body | ConvertFrom-Json).error | Should Be "Page p99 is not in this vault's index."
            (Send-ApiRequest $script:TestPort '/api/page/body?page=p1&notebook=%7B99999999-9999-9999-9999-999999999999%7D%7B1%7D%7BB0%7D' $api).status | Should Be 404
        }
        It 'reads a vault that is not the active one, and never another source''s page' {
            # The connected notebook's page is no page of the other vault (Team wiki).
            $r = Send-ApiRequest $script:TestPort "/api/page/body?page=$([Uri]::EscapeDataString($script:ReadingPage))&vault=bbbbbbbb-0000-4000-8000-000000000002" $api
            $r.status | Should Be 404
            ($r.body | ConvertFrom-Json).error | Should Match 'is not in this vault''s index\.$'
        }
    } finally {
        Stop-UiServer $server
        Remove-Item $ui -Recurse -Force
        Remove-Item $app -Recurse -Force
    }
}
