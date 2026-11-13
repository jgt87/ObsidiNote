# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/VaultStore.psm1: Add (lib/Ingest.psm1) end to end against the in-memory OneNote through the real
# store and the write guard: Intake item, content page with Meta and owned outlines, "Linked from",
# the id counter on the state page, the Index pages, completeness, Undo, a link page, and the guard
# refusing every write outside the active vault. Recorded Copilot replies; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'FakeVault.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:Now = [datetime]'2026-11-13T10:00:00'
$script:Text = "An identity-aware proxy checks who the user is and which device they use before it forwards a request.`nWe use it for the partner portal instead of the old VPN."

function Get-AddReply($Store) {
    $sl = Get-LinkShortlist -Index (& $Store.GetIndex) -Text $script:Text
    $t = @($sl.topics | Where-Object { $_['path'] -eq 'Security/Networking' })[0]['id']
    '{"title": "Identity-aware proxies", "summary": "A proxy that checks user and device before it forwards a request.", "type": "concept", "topics": [{"new": "Security/Networking/Zero trust"}, {"id": "' + $t + '"}], "links": [{"target": "p1", "anchor": "checks who the user is", "strength": 3, "why": "core concept"}, {"target": "p2", "anchor": "partner portal", "strength": 2, "why": "where it is used"}, {"target": "p3", "anchor": "the old VPN", "strength": 1, "why": "replaces it"}], "aliases": ["IAP"], "intent": "add"}'
}

function Test-WritesInside($World) {
    # Every recorded write of the fake targets an object inside the vault root (or was refused before).
    $scope = Get-VaultScopeIds -Xml ($World.f.GetHierarchy($World.v.rootId, 4)) -RootId $World.v.rootId
    @($World.f.Writes | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $_ -match '^\{' -and -not $scope.Contains($_) })
}

Describe 'The store adapter' {
    $w = New-SyntheticVault
    It 'implements every function of the Ingest store contract' {
        (Get-MissingStoreFunctions $w.store).Count | Should Be 0
    }
    It 'gives Ingest the index of ObsidiNote''s own pages and the topic paths' {
        $ix = & $w.store.GetIndex
        (@($ix.pages | ForEach-Object { $_.id } | Sort-Object) -join ',') | Should Be 'p1,p2,p3'
        @($ix.topics) -contains 'Security/Networking' | Should Be $true
        @($ix.edges).Count | Should Be 1
        (@($ix.pages | Where-Object { $_.id -eq 'p1' })[0]).pageId | Should Match '^\{PA-'
    }
    It 'finds a link page by its normalized URL only' {
        & $w.store.FindPageByUrl -Url 'https://example.org/a' | Should BeNullOrEmpty
    }
}

Describe 'Add of a text item through the real store' {
    $w = New-SyntheticVault
    $c = New-FakeCopilot @((Get-AddReply $w.store))
    $r = Invoke-AddRequest -Request @{ text = $script:Text; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $script:Now }
    $page = Find-FakePage $w.f 'Identity-aware proxies'

    It 'adds the page with the next id from the state page' {
        $r.status | Should Be 'added'
        $r.page.id | Should Be 'p4'
        $r.page.section | Should Be 'Notes'
        $st = Get-VaultState -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId
        $st.idCounter | Should Be 5
    }
    It 'writes the content page in its bucket with obsn Meta, a properties outline and the body with onenote: links' {
        $page | Should Not BeNullOrEmpty
        $w.f.Nodes[$page.parent].name | Should Be 'Notes'
        $page.meta['obsn.id'] | Should Be 'p4'
        $page.meta['obsn.type'] | Should Be 'concept'
        $page.meta['obsn.topics'] | Should Be '["Security/Networking/Zero trust","Security/Networking"]'
        (Get-FakeOutlineXml $w.f $page.id 'props') | Should Match 'topics: Security / Networking / Zero trust'
        $body = Get-FakeOutlineXml $w.f $page.id 'body'
        $body | Should Match '<a href="onenote:[^"]*">checks who the user is</a>'
        $body | Should Match 'partner portal</a>'
    }
    It 'writes "Linked from" on the target pages' {
        $p1 = Find-FakePage $w.f 'Zero-trust networking'
        (Get-FakeOutlineXml $w.f $p1.id 'backlinks') | Should Match 'Identity-aware proxies'
        $r.backlinks | Should Be 3
    }
    It 'files the Intake item: status linked, filed as the new id' {
        $inbox = @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta.Contains('obsn.inboxKind') })
        $inbox.Count | Should Be 1
        $w.f.Nodes[$inbox[0].parent].name | Should Be '01 Intake'
        $inbox[0].meta['obsn.status'] | Should Be 'linked'
        $inbox[0].meta['obsn.filedAs'] | Should Be 'p4'
    }
    It 'puts the page in the central index and regenerates the affected Index pages' {
        $w.open.model.pages.Contains('p4') | Should Be $true
        $hubs = @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta.Contains('obsn.indexKey') } | ForEach-Object { $_.meta['obsn.indexKey'] })
        $hubs -contains 'topic:Security/Networking/Zero trust' | Should Be $true
        $hub = @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta.Contains('obsn.topic') -and $_.meta['obsn.topic'] -eq 'Security/Networking/Zero trust' })[0]
        $hub.meta['obsn.entries'] | Should Match '"i":"p4"'
    }
    It 'leaves nothing outside the index (completeness)' {
        $tree = ConvertFrom-ObsnHierarchy -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        @(Test-IndexComplete -Model $w.open.model -Tree $tree).Count | Should Be 0
    }
    It 'writes only inside the active vault' {
        (Test-WritesInside $w) -join ',' | Should Be ''
        $w.f.Nodes[$w.tomato].outlines.Count | Should Be 1
    }

    Context 'Undo' {
        $p1 = Find-FakePage $w.f 'Zero-trust networking'
        $u = Undo-AddRequest -Store $w.store -Undo $r.undo
        It 'moves the page to Deleted Pages, takes it out of the index and rewrites the backlinks' {
            $u.status | Should Be 'undone'
            $w.f.Nodes.ContainsKey($page.id) | Should Be $false
            $w.open.model.pages.Contains('p4') | Should Be $false
            (Get-FakeOutlineXml $w.f $p1.id 'backlinks') | Should Not Match 'Identity-aware proxies'
        }
        It 'keeps it on the state page''s Recently deleted list' {
            $st = Get-VaultState -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId
            @($st.deleted | ForEach-Object { $_.title }) -contains 'Identity-aware proxies' | Should Be $true
        }
    }
}

Describe 'Markdown text through the real store (user, 2026-11-13: OneNote has no Markdown)' {
    $w = New-SyntheticVault
    $md = "# Proxy notes`n`nThe proxy **checks who the user is** first.`n`n- step one`n  - step one a`n1. first`n2. second`n`n| Name | Role |`n|---|---|`n| Sam | lead |`n`nRun ``partner portal`` here."
    $reply = '{"title": "Proxy notes", "summary": "Notes on the proxy.", "type": "concept", "topics": [{"new": "Security/Proxies"}], "links": [{"target": "p1", "anchor": "checks who the user is", "strength": 3, "why": "core concept"}, {"target": "p2", "anchor": "partner portal", "strength": 2, "why": "named"}], "aliases": [], "intent": "add"}'
    $c = New-FakeCopilot @($reply)
    $r = Invoke-AddRequest -Request @{ text = $md; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $script:Now }
    $page = Find-FakePage $w.f 'Proxy notes'
    $body = Get-FakeOutlineXml $w.f $page.id 'body'
    It 'adds the page' {
        $r.status | Should Be 'added'
    }
    It 'writes a heading in a larger bold font and keeps bold around the link Copilot proposed' {
        $body | Should Match "<span style='font-weight:bold'><span style='font-size:16pt'>Proxy notes</span></span>"
        $body | Should Match '<a href="onenote:[^"]*"><span style=''font-weight:bold''>checks who the user is</span></a>'
        $body | Should Not Match '\*\*'
    }
    It 'writes real list items, nested, bullets and numbers' {
        ([regex]::Matches($body, '<one:Bullet ')).Count | Should Be 2
        $body | Should Match 'text="1\."'
        $body | Should Match 'text="2\."'
        $body | Should Match '<one:OEChildren><one:OE><one:List><one:Bullet[^>]*/></one:List><one:T><!\[CDATA\[step one a'
    }
    It 'writes a OneNote table with a bold header row' {
        $body | Should Match '<one:Table bordersVisible="true"><one:Columns><one:Column index="0" width="120" ?/><one:Column index="1" width="120" ?/></one:Columns>'
        $body | Should Match "<span style='font-weight:bold'>Role</span>"
        $body | Should Match 'CDATA\[lead\]'
    }
    It 'never puts a link inside inline code' {
        $body | Should Match "font-family:Consolas'>partner portal</span>"
        $body | Should Not Match 'partner portal</span></a>'
    }
    It 'writes well-formed page XML' {
        { [xml]('<x xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote">' + $body + '</x>') } | Should Not Throw
    }
}

Describe 'A link through the real store' {
    $w = New-SyntheticVault
    $summary = '{"readable": true, "problem": "", "title": "Identity-aware proxy explained", "where": "example.org", "kind": "article", "summary": "An identity-aware proxy checks the user and the device before it forwards a request. It replaces a VPN for many apps.", "keyFacts": ["Checks user and device"], "useFor": "When you plan remote access", "sensitivity": ""}'
    $links = '{"title": "x", "summary": "How identity-aware proxies replace a VPN.", "type": "link-web", "topics": [{"new": "Security/Networking"}], "links": [{"target": "p3", "anchor": "replaces a VPN", "strength": 2, "why": "same move away from VPN"}], "aliases": [], "intent": "add"}'
    $c = New-FakeCopilot @($summary, $links)
    $r = Invoke-AddRequest -Request @{ text = 'https://example.org/iap?utm_source=x#top'; mode = 'auto' } -Store $w.store -Ask $c.ask -Options @{ Now = $script:Now }
    $page = Find-FakePage $w.f 'Identity-aware proxy explained'
    It 'makes one summary page in Web links with summary, checked and Your notes outlines' {
        $r.status | Should Be 'added'
        $w.f.Nodes[$page.parent].name | Should Be 'Web links'
        $page.meta['obsn.url'] | Should Be 'https://example.org/iap'
        $page.meta['obsn.linkSummary'] | Should Match 'Identity-aware proxy explained'
        $page.meta['obsn.linkSummary.n'] | Should Be '0'
        $page.meta['obsn.summaryHash'].Length | Should Be 16
        (Get-FakeOutlineXml $w.f $page.id 'notes') | Should Match 'Your notes'
        (Get-FakeOutlineXml $w.f $page.id 'checked') | Should Match 'Checked: 2026-11-13'
    }
    It 'finds it again by its normalized URL, and reads the summary outline back unchanged (not edited)' {
        (& $w.store.FindPageByUrl -Url 'https://EXAMPLE.org/iap#x').id | Should Be $r.page.id
        $p = & $w.store.ReadPage -PageId $page.id
        $sum = @($p.outlines | Where-Object { $_.role -eq 'summary' })[0].text
        Test-SummaryEdited -OutlineText $sum -StoredHash $p.meta.summaryHash | Should Be $false
    }
    It 'never rewrites the Your notes outline' {
        { & $w.store.UpdatePage -PageId $page.id -Meta @{} -Outlines @(@{ role = 'notes'; lines = @('x') }) -Title '' } | Should Throw 'written once'
    }
}

Describe 'The write guard and the lease' {
    $w = New-SyntheticVault
    It 'refuses a write to a page outside the active vault' {
        { & $w.store.UpdatePage -PageId $w.tomato -Meta @{ summary = 'x' } -Outlines @() -Title 'Changed' } | Should Throw 'Write refused'
        { & $w.store.DeletePage -PageId $w.seeds } | Should Throw 'Write refused'
        $w.f.Nodes.ContainsKey($w.seeds) | Should Be $true
        $w.f.Nodes[$w.tomato].title | Should Be 'Tomatoes'
    }
    It 'adds nothing while this session does not hold the writer lease' {
        $before = $w.f.Writes.Count
        $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        $c = New-FakeCopilot @((Get-AddReply $w.store))
        $r = Invoke-AddRequest -Request @{ text = $script:Text; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'failed'
        $r.message | Should Match 'Read only'
        $c.q.prompts.Count | Should Be 0
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Pure helpers' {
    It 'turns the line model into owned outline lines with links, bold and children' {
        $l = @(@{ parts = @(@{ text = 'See '; href = '' }, @{ text = 'a & b'; href = 'onenote:x?a=1&b=2' }); bold = $true; collapsed = $false; children = @(@{ parts = @(@{ text = 'child'; href = '' }); bold = $false; collapsed = $false; children = @() }) })
        $o = ConvertTo-OutlineLines -Lines $l
        $o[0].html | Should Be "<span style='font-weight:bold'>See <a href=""onenote:x?a=1&amp;b=2"">a &amp; b</a></span>"
        @($o[0].children)[0].html | Should Be 'child'
    }
    It 'lists the affected Index pages: the lists, the topic and its parents' {
        (Get-AffectedIndexKeys -Topics @('A/B/C')) -join ',' | Should Be 'root,bytype,az,unfiled,links,archive,other,state,topic:A/B/C,topic:A/B,topic:A'
    }
    It 'keeps 60 days of Recently deleted' {
        $d = Get-RecentlyDeleted -Deleted @(@{ title = 'old'; date = '2026-01-01' }, @{ title = 'new'; date = '2026-11-01' }) -Entry @{ title = 'now'; date = '2026-11-13' } -Now $script:Now
        ($d | ForEach-Object { $_.title }) -join ',' | Should Be 'now,new'
    }
}
