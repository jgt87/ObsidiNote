# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Editing a page in the window (lib/Ingest.psm1 Edit-Page, POST /api/page/edit) through the real
# store, the write guard and the lease against the in-memory OneNote: title, type (another section moves the page),
# topics, aliases, summary, a link page's address, links to other pages with their "Linked from"
# lists, the person's own outlines untouched, refusals. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function Get-UserOutlines($F, [string]$PageId) {
    , @($F.Nodes[$PageId].outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml })
}

function Add-LinkPage($W) {
    # A web link page p4 next to the synthetic pages, as an Add would leave it.
    $sid = $W.v.sectionIds['Web links']
    $pid4 = $W.f.AddPage($sid, 'Example handbook', @{ 'obsn.id' = 'p4'; 'obsn.type' = 'link-web'; 'obsn.url' = 'https://www.example.org/handbook'; 'obsn.host' = 'www.example.org'; 'obsn.topics' = '["Security"]'; 'obsn.links' = '[]' }, 1, 'A public handbook.')
    & $W.store.IndexAddPage @{ id = 'p4'; title = 'Example handbook'; type = 'link-web'; url = 'https://www.example.org/handbook'; host = 'www.example.org'; topics = @('Security'); links = @(); pageId = $pid4; section = 'Web links'; link = 'onenote:#p4' } | Out-Null
    $pid4
}

Describe 'Edit-Page: title, details and links of a page' {
    $w = New-SyntheticVault
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    $p3 = Find-FakePage $w.f 'VPN retirement plan'
    $userP3 = (Get-UserOutlines $w.f $p3.id) -join '|'

    It 'changes title, topics, aliases and summary, in the page and in the index' {
        $r = Edit-Page -Store $w.store -Id 'p3' -Changes @{ title = 'VPN switch-off plan'; topics = @('Security/Networking', ' Projects / Partner portal '); aliases = @('VPN plan', 'VPN plan'); summary = 'Steps and dates to switch off the old VPN.' }
        $r.status | Should Be 'edited'
        ($r.changed -join ',') | Should Be 'aliases,summary,title,topics'
        $w.f.Nodes[$p3.id].title | Should Be 'VPN switch-off plan'
        $p3.meta['obsn.topics'] | Should Be '["Security/Networking","Projects/Partner portal"]'
        $p3.meta['obsn.aliases'] | Should Be '["VPN plan"]'
        $p3.meta['obsn.summary'] | Should Be 'Steps and dates to switch off the old VPN.'
        Get-FakeOutlineXml $w.f $p3.id 'props' | Should Match 'aliases: VPN plan'
        $rec = $w.open.model.pages['p3']
        $rec.title | Should Be 'VPN switch-off plan'
        (@($rec.topics) -join ',') | Should Be 'Security/Networking,Projects/Partner portal'
    }
    It 'shows the new title in the "Linked from" list of the page it links to' {
        Get-FakeOutlineXml $w.f $p1.id 'backlinks' | Should Match 'VPN switch-off plan'
    }
    It 'replaces the links: a new one gets "Linked from", a removed one loses it' {
        $r = Edit-Page -Store $w.store -Id 'p3' -Changes @{ links = @(@{ target = 'p2'; strength = 3; why = 'same review' }) }
        $r.status | Should Be 'edited'
        $p3.meta['obsn.links'] | Should Be '[{"t":"p2","s":3,"w":"same review"}]'
        Get-FakeOutlineXml $w.f $p2.id 'backlinks' | Should Match 'VPN switch-off plan'
        Get-FakeOutlineXml $w.f $p1.id 'backlinks' | Should Not Match 'VPN switch-off plan'
        $ix = & $w.store.GetIndex
        @($ix.edges | Where-Object { $_.from -eq 'p3' -and $_.to -eq 'p1' }).Count | Should Be 0
        @($ix.edges | Where-Object { $_.from -eq 'p3' -and $_.to -eq 'p2' }).Count | Should Be 1
    }
    It 'changes the type within its section without moving the page' {
        $before = $p1.parent
        $r = Edit-Page -Store $w.store -Id 'p1' -Changes @{ type = 'howto' }
        $r.status | Should Be 'edited'
        $r.moved | Should Be ''
        $p1.meta['obsn.type'] | Should Be 'howto'
        $p1.parent | Should Be $before
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ type = 'novel' }).status | Should Be 'invalid'
    }
    It 'refuses a link type for a page that is not a link (its address decides that)' {
        $x = Edit-Page -Store $w.store -Id 'p2' -Changes @{ type = 'link-web' }
        $x.status | Should Be 'invalid'
        $x.message | Should Match 'address'
    }
    It 'replaces a link page''s address, within its section and never onto another page''s address' {
        $pid4 = Add-LinkPage $w
        $r = Edit-Page -Store $w.store -Id 'p4' -Changes @{ url = 'https://docs.example.org/handbook/v2' }
        $r.status | Should Be 'edited'
        $w.f.Nodes[$pid4].meta['obsn.url'] | Should Be 'https://docs.example.org/handbook/v2'
        $w.f.Nodes[$pid4].meta['obsn.host'] | Should Be 'docs.example.org'
        Get-FakeOutlineXml $w.f $pid4 'props' | Should Match 'link: https://docs.example.org/handbook/v2'
        (Edit-Page -Store $w.store -Id 'p4' -Changes @{ url = 'javascript:alert(1)' }).status | Should Be 'invalid'
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ url = 'https://example.org/' }).message | Should Match 'Only a link page'
    }
    It 'refuses bad input and writes nothing' {
        $before = $w.f.Writes.Count
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ title = '   ' }).status | Should Be 'invalid'
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ links = @(@{ target = 'p2' }) }).message | Should Match 'itself'
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ links = @(@{ target = 'p99' }) }).message | Should Match 'not in this vault'
        (Edit-Page -Store $w.store -Id 'p99' -Changes @{ title = 'x' }).status | Should Be 'not-found'
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{}).status | Should Be 'invalid'
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ title = 'Partner portal: access review notes' }).status | Should Be 'unchanged'
        $w.f.Writes.Count | Should Be $before
    }
    It 'never touches the person''s own outlines' {
        ((Get-UserOutlines $w.f $p3.id) -join '|') | Should Be $userP3
        $userP3 | Should Match 'Switch off the old VPN'
        Get-FakeOutlineXml $w.f $p3.id 'notes' | Should Be ''
    }
    It 'refuses without the writer lease and writes nothing' {
        $before = $w.f.Writes.Count
        $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        $x = Edit-Page -Store $w.store -Id 'p2' -Changes @{ title = 'Other' }
        $x.status | Should Be 'refused'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Edit-Page: where a page came from (origin), also for pages added before it was recorded' {
    $w = New-SyntheticVault
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    It 'sets it on a page that never had one, in the page and in the index' {
        $r = Edit-Page -Store $w.store -Id 'p2' -Changes @{ origin = 'outlook' }
        $r.status | Should Be 'edited'
        ($r.changed -join ',') | Should Be 'origin'
        $p2.meta['obsn.origin'] | Should Be 'outlook'
        $w.open.model.pages['p2'].origin | Should Be 'outlook'
    }
    It 'clears it back to typed, and refuses an unknown one or one on a link page' {
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ origin = '' }).status | Should Be 'edited'
        $p2.meta['obsn.origin'] | Should Be ''
        (Edit-Page -Store $w.store -Id 'p2' -Changes @{ origin = 'myspace' }).message | Should Be 'Unknown origin.'
        $null = Add-LinkPage $w
        (Edit-Page -Store $w.store -Id 'p4' -Changes @{ origin = 'teams' }).message | Should Match 'address'
    }
    It 'shows the page in that source on the map (GraphModel)' {
        $null = Edit-Page -Store $w.store -Id 'p2' -Changes @{ origin = 'word' }
        Import-Module (Join-Path $root 'lib\GraphModel.psm1') -Force
        $g = ConvertTo-GraphModel -Model $w.open.model -Source @{ kind = 'vault'; id = 'v'; name = 'S'; readOnly = $false }
        $p = @($g.pages | Where-Object { $_.id -eq 'p2' })[0]
        $p.sourceId | Should Be 'word'
        $p.origin | Should Be 'word'
        @($g.sources | Where-Object { $_.id -eq 'word' })[0].name | Should Be 'Word'
    }
}

Describe 'The origin list matches the interface''s (tests/fixtures/origins.json)' {
    It 'has the same ids, labels, source names and kinds in the same order' {
        $want = Get-Content -Raw (Join-Path $here 'fixtures\origins.json') | ConvertFrom-Json
        $have = Get-OriginList   # returns , @(...): assign as is
        $have.Count | Should Be @($want).Count
        for ($i = 0; $i -lt $have.Count; $i++) {
            "$($have[$i].id)|$($have[$i].label)|$($have[$i].source)|$($have[$i].kind)" | Should Be "$($want[$i].id)|$($want[$i].label)|$($want[$i].source)|$($want[$i].kind)"
        }
    }
}
