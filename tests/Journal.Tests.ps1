# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Journal day pages (D-060): lib/Journal.psm1 (pure), the body-entry
# helpers of lib/PageMeta.psm1, and Add / Undo of journal entries end to end through the real store, the
# write guard and the in-memory OneNote. Recorded Copilot replies; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Journal', 'Ingest', 'Activity', 'GraphModel') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'FakeVault.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function Get-LogReply([string]$Title, [string]$Topic, [string]$Target = '', [string]$Anchor = '') {
    $links = if ($Target) { '[{"target": "' + $Target + '", "anchor": "' + $Anchor + '", "strength": 2, "why": "same subject"}]' } else { '[]' }
    '{"title": "' + $Title + '", "summary": "' + $Title + ' (summary).", "type": "log", "topics": [{"new": "' + $Topic + '"}], "links": ' + $links + ', "aliases": [], "intent": "add"}'
}

function Get-DayPages($W) { @($W.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta['obsn.type'] -eq 'log' }) }

function Get-TopLines([string]$OutlineXml) {
    [xml]$d = $OutlineXml
    $ns = New-Object Xml.XmlNamespaceManager $d.NameTable
    $ns.AddNamespace('one', 'http://schemas.microsoft.com/office/onenote/2013/onenote')
    @($d.SelectNodes('/one:Outline/one:OEChildren/one:OE/one:T', $ns) | ForEach-Object { ($_.InnerText -replace '<[^>]+>', '') })
}

Describe 'Journal rules (pure)' {
    It 'titles the day page with the local date' {
        Get-JournalDayTitle -Now ([datetime]'2026-11-17T23:59:00') | Should Be '2026-11-17'
        Test-JournalDayTitle '2026-11-17' | Should Be $true
        Test-JournalDayTitle 'Standup notes' | Should Be $false
    }
    It 'merges the entries: each topic once, one link per target at its strongest, a summary of titles' {
        $e1 = @{ ref = 'ra'; title = 'Supplier call'; topics = @('Projects/Portal'); links = @(@{ target = 'p1'; strength = 1; why = 'first' }) }
        $e2 = @{ ref = 'rb'; title = 'Budget agreed'; topics = @('Projects/Portal', 'Finance'); links = @(@{ target = 'p1'; strength = 3; why = 'second' }, @{ target = 'p2'; strength = 2; why = '' }) }
        $m = Merge-JournalDay -Entries @($e1, $e2)
        ($m.topics -join ',') | Should Be 'Projects/Portal,Finance'
        @($m.links).Count | Should Be 2
        (@($m.links | Where-Object { $_.target -eq 'p1' })[0]).strength | Should Be 3
        (@($m.links | Where-Object { $_.target -eq 'p1' })[0]).why | Should Be 'first'
        $m.summary | Should Be '2 entries: Supplier call; Budget agreed'
        (Merge-JournalDay -Entries @($e1)).summary | Should Be '1 entry: Supplier call'
    }
    It 'shortens a long summary' {
        $many = @(1..80 | ForEach-Object { @{ title = "Entry number $_ with a longer name" } })
        $s = Get-JournalSummary -Entries $many
        $s.Length | Should Be 400
        $s.EndsWith('...') | Should Be $true
    }
    It 'finds only a day page: a log page with that date as title and entries, not archived' {
        $old = @{ id = 'p7'; type = 'log'; title = '2026-11-17'; status = ''; entries = @() }
        $day = @{ id = 'p8'; type = 'log'; title = '2026-11-17'; status = ''; entries = @(@{ ref = 'ra' }) }
        $arch = @{ id = 'p9'; type = 'log'; title = '2026-11-17'; status = 'archived'; entries = @(@{ ref = 'rb' }) }
        (Find-JournalDay -Pages @($old, $arch) -Title '2026-11-17') | Should BeNullOrEmpty
        (Find-JournalDay -Pages @($old, $arch, $day) -Title '2026-11-17').id | Should Be 'p8'
        (Find-JournalDay -Pages @($day) -Title '2026-11-18') | Should BeNullOrEmpty
    }
    It 'keeps the entries through the page Meta (obsn.entries)' {
        $e = @{ ref = 'ra'; at = '2026-11-17T09:30'; title = 'Supplier call'; summary = 'S'; topics = @('Projects/Portal'); links = @(@{ target = 'p1'; strength = 2; why = 'w' }) }
        $meta = @{}
        foreach ($kv in (ConvertTo-ObsnMeta -Page @{ entries = @($e) }).GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
        $meta['obsn.entries.n'] | Should Be '0'
        $back = @((ConvertFrom-ObsnMeta -Meta $meta).entries)
        $back.Count | Should Be 1
        "$($back[0].ref)|$($back[0].at)|$($back[0].title)|$($back[0].topics -join ',')|$($back[0].links[0].target)" | Should Be 'ra|2026-11-17T09:30|Supplier call|Projects/Portal|p1'
        @((ConvertFrom-ObsnMeta -Meta @{}).entries).Count | Should Be 0
    }
}

Describe 'Body entries on a day page (PageMeta, pure)' {
    $ns = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
    $xml = '<?xml version="1.0"?><one:Page xmlns:one="' + $ns + '" ID="{P}"><one:Outline objectID="{O1}"><one:Meta name="obsn.role" content="body" /><one:OEChildren><one:OE objectID="{E1}"><one:T><![CDATA[<span style=''font-weight:bold''>09:30  Supplier call</span>]]></one:T></one:OE></one:OEChildren></one:Outline><one:Outline objectID="{O2}"><one:OEChildren><one:OE><one:T><![CDATA[My own line]]></one:T></one:OE></one:OEChildren></one:Outline></one:Page>'
    It 'appends an entry to the body outline only, keeping the earlier entry by its objectID' {
        $r = Add-ObsnBodyEntry -Xml $xml -Lines @(New-OneLine -Text '11:00  Budget agreed' -Bold -Children @(New-OneLine -Text 'We agreed the budget.'))
        $r.ok | Should Be $true
        $r.xml | Should Match 'objectID="\{O1\}"'
        $r.xml | Should Match 'objectID="\{E1\}"'
        $r.xml | Should Match '11:00  Budget agreed'
        $r.xml | Should Not Match 'My own line'
        $r.xml | Should Not Match '\{O2\}'
    }
    It 'takes out an entry only when its line is still where it was written' {
        $two = (Add-ObsnBodyEntry -Xml $xml -Lines @(New-OneLine -Text '11:00  Budget agreed' -Bold)).xml
        # The update XML holds the body outline whole; read it back as a page for the removal.
        $bad = Remove-ObsnBodyEntry -Xml $two -Index 0 -Heading '11:00  Budget agreed'
        $bad.ok | Should Be $false
        $bad.reason | Should Match 'changed in OneNote'
        $ok = Remove-ObsnBodyEntry -Xml $two -Index 1 -Heading '11:00  Budget agreed'
        $ok.ok | Should Be $true
        $ok.xml | Should Not Match 'Budget agreed'
        $ok.xml | Should Match 'Supplier call'
        (Remove-ObsnBodyEntry -Xml $two -Index 5 -Heading 'x').ok | Should Be $false
    }
    It 'refuses a page without ObsidiNote''s body outline' {
        $none = '<?xml version="1.0"?><one:Page xmlns:one="' + $ns + '" ID="{P}"><one:Outline objectID="{O2}"><one:OEChildren><one:OE><one:T><![CDATA[x]]></one:T></one:OE></one:OEChildren></one:Outline></one:Page>'
        (Add-ObsnBodyEntry -Xml $none -Lines @('x')).ok | Should Be $false
    }
}

Describe 'Journal entries through the real store (one page per day)' {
    $w = New-SyntheticVault
    $now1 = [datetime]'2026-11-17T09:30:00'; $now2 = [datetime]'2026-11-17T11:05:00'; $now3 = [datetime]'2026-11-18T08:00:00'
    $c = New-FakeCopilot @((Get-LogReply 'Supplier call' 'Projects/Partner portal' 'p2' 'partner portal'), (Get-LogReply 'Budget agreed' 'Finance' 'p1' 'zero trust'), (Get-LogReply 'Next morning' 'Finance'))
    $r1 = Invoke-AddRequest -Request @{ text = 'Called the supplier about the partner portal.'; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $now1 }
    $r2 = Invoke-AddRequest -Request @{ text = "Budget agreed for zero trust.`nNext step: order."; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $now2 }
    $days = @(Get-DayPages $w)

    It 'puts two entries of one day on one page titled with the date, in Journal/<year>' {
        "$($r1.status)|$($r2.status)" | Should Be 'added|added'
        $days.Count | Should Be 1
        $days[0].title | Should Be '2026-11-17'
        $w.f.Nodes[$days[0].parent].name | Should Be '2026'
        $r2.page.id | Should Be $r1.page.id
        $r2.message | Should Be 'Added to the journal of 2026-11-17: Budget agreed'
        $r1.journal.newDay | Should Be $true
        $r2.journal.newDay | Should Be $false
        $r2.journal.entries | Should Be 2
    }
    It 'writes each entry as one line with its time and title, the text under it, links in the text' {
        $body = Get-FakeOutlineXml $w.f $days[0].id 'body'
        (Get-TopLines $body) -join '|' | Should Be '09:30  Supplier call|11:05  Budget agreed'
        $body | Should Match 'Next step: order.'
        $body | Should Match '<a href="onenote:[^"]*">partner portal</a>'
    }
    It 'keeps the union of topics and links and the entries in the page Meta and the index' {
        $m = Get-FakeMeta $w.f $days[0].id
        $m['obsn.topics'] | Should Be '["Projects/Partner portal","Finance"]'
        $m['obsn.summary'] | Should Be '2 entries: Supplier call; Budget agreed'
        @(ConvertFrom-ObsnEntriesValue $m['obsn.entries']).Count | Should Be 2
        $rec = $w.open.model.pages[$r1.page.id]
        @($rec.entries).Count | Should Be 2
        (@($rec.links | ForEach-Object { $_.target } | Sort-Object) -join ',') | Should Be 'p1,p2'
        $rec.created | Should Not BeNullOrEmpty
    }
    It 'files both Intake items with the day page and names the entry in each undo record' {
        $r1.undo.entry | Should Not BeNullOrEmpty
        $r1.undo.entry | Should Not Be $r2.undo.entry
        @($r2.undo.targets) -join ',' | Should Be 'p1'
        $intake = @(Read-ObsnIntakePages -Adapter $w.a -RootId $w.v.rootId)
        $index = @{}; foreach ($p in $w.open.model.pages.Values) { $index[[string]$p.key] = $p }
        $items = Get-ActivityList -Pages $intake -Index $index
        @($items | Where-Object { $_.state -eq 'added' -and $_.entry }).Count | Should Be 2
    }
    It 'sends the entries and the page date to the window (graph model)' {
        $g = ConvertTo-GraphModel -Model $w.open.model -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false }
        $gp = @($g.pages | Where-Object { $_.id -eq $r1.page.id })[0]
        @($gp.entries).Count | Should Be 2
        $gp.entries[1].title | Should Be 'Budget agreed'
        $gp.entries[1].links[0].to | Should Be 'p1'
        @($gp.entries[1].topicIds) -join ',' | Should Be 'Finance'
        $gp.created | Should Not BeNullOrEmpty
        @((@($g.pages | Where-Object { $_.id -eq 'p1' })[0]).entries).Count | Should Be 0
    }
    It 'Undo of the second entry takes out only that entry, its topic and its link' {
        $u = Undo-AddRequest -Store $w.store -Undo $r2.undo
        $u.status | Should Be 'undone'
        $u.message | Should Match 'taken out of the journal of 2026-11-17'
        @(Get-DayPages $w).Count | Should Be 1
        (Get-TopLines (Get-FakeOutlineXml $w.f $days[0].id 'body')) -join '|' | Should Be '09:30  Supplier call'
        (Get-FakeMeta $w.f $days[0].id)['obsn.topics'] | Should Be '["Projects/Partner portal"]'
        (@($w.open.model.pages[$r1.page.id].links | ForEach-Object { $_.target }) -join ',') | Should Be 'p2'
        (Get-FakeOutlineXml $w.f (Find-FakePage $w.f 'Zero-trust networking').id 'backlinks') | Should Not Match '2026-11-17'
    }
    It 'Undo of the last entry removes the day page (to Deleted Pages)' {
        $u = Undo-AddRequest -Store $w.store -Undo $r1.undo
        $u.status | Should Be 'undone'
        @(Get-DayPages $w).Count | Should Be 0
        $w.open.model.pages.Contains($r1.page.id) | Should Be $false
    }
    It 'a new day gets a new page' {
        $r3 = Invoke-AddRequest -Request @{ text = 'Next morning.'; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $now3 }
        $r3.status | Should Be 'added'
        (@(Get-DayPages $w) | ForEach-Object { $_.title }) -join ',' | Should Be '2026-11-18'
    }
    It 'writes only inside the vault' {
        # The first day page was deleted by the last Undo, so it is no longer in the hierarchy read here.
        $scope = Get-VaultScopeIds -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        $gone = $days[0].id
        @($w.f.Writes | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $_ -match '^\{' -and $_ -ne $gone -and -not $scope.Contains($_) }).Count | Should Be 0
    }
}

Describe 'What the window gets for the Journal (tests/fixtures/journal-pages.json)' {
    # The fixture is what the server really sends: the interface's journal tests read the same file.
    $fx = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $here 'fixtures\journal-pages.json')))
    $f = New-FakeOneNote
    $nb = $f.AddNotebook('Fixture vault')
    $sections = @{}
    foreach ($p in @($fx.pages)) {
        $parts = $p.section.Split('/')
        $parent = $nb
        foreach ($g in @($parts | Select-Object -First ($parts.Count - 1))) { $parent = $f.AddGroup($parent, $g) }
        $key = $p.section
        if (-not $sections.ContainsKey($key)) { $sections[$key] = $f.AddSection($parent, $parts[-1]) }
        $meta = @{ 'obsn.id' = $p.id; 'obsn.type' = $p.kind; 'obsn.topics' = (ConvertTo-Json -InputObject @($p.topicIds) -Compress)
            'obsn.links' = (ConvertTo-ObsnLinksValue -Links @(@($p.links) | ForEach-Object { @{ target = $_.to; strength = $_.strength; why = $_.why } })) }
        if (@($p.entries).Count) {
            $e = @(@($p.entries) | ForEach-Object { @{ ref = $_.ref; at = $_.at; title = $_.title; summary = $_.summary; topics = @($_.topicIds); links = @(@($_.links) | ForEach-Object { @{ target = $_.to; strength = $_.strength; why = $_.why } }) } })
            $meta['obsn.entries'] = ConvertTo-ObsnEntriesValue -Entries $e
        }
        $id = $f.AddPage($sections[$key], $p.title, $meta, 1, '')
        $f.Nodes[$id].created = $p.created
    }
    $g = ConvertTo-GraphModel -Model (Read-VaultScan -Adapter $f -RootId $nb -VaultId 'v1') -Source @{ kind = 'vault'; id = 'v1'; name = 'Fixture vault'; readOnly = $false }
    $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress | ConvertFrom-Json
    foreach ($p in @($fx.pages)) {
        It "sends $($p.id) ($($p.kind)) with its date and entries" {
            $got = @($json.pages | Where-Object { $_.id -eq $p.id })[0]
            $got | Should Not BeNullOrEmpty
            "$($got.title)|$($got.kind)|$($got.created)|$(@($got.topicIds) -join ',')" | Should Be "$($p.title)|$($p.kind)|$($p.created)|$(@($p.topicIds) -join ',')"
            (ConvertTo-Json -InputObject @($got.entries) -Depth 6 -Compress) | Should Be (ConvertTo-Json -InputObject @($p.entries) -Depth 6 -Compress)
        }
    }
    It 'sends the topics the fixture names' {
        (@($json.topics | ForEach-Object { $_.id } | Sort-Object) -join ',') | Should Be (@($fx.topics | Sort-Object) -join ',')
    }
}

Describe 'Undo of an entry after the day page was changed in OneNote' {
    $w = New-SyntheticVault
    $now = [datetime]'2026-11-17T09:30:00'
    $c = New-FakeCopilot @((Get-LogReply 'First' 'Finance'), (Get-LogReply 'Second' 'Finance'))
    $a = Invoke-AddRequest -Request @{ text = 'One.'; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $now }
    $b = Invoke-AddRequest -Request @{ text = 'Two.'; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = $now.AddMinutes(5) }
    $day = @(Get-DayPages $w)[0]
    # The person typed a line above the entries inside ObsidiNote's own outline.
    $o = @($w.f.Nodes[$day.id].outlines | Where-Object { $_.xml -match 'content="body"' })[0]
    $o.xml = $o.xml -replace '<one:OEChildren>', '<one:OEChildren><one:OE><one:T><![CDATA[typed by hand]]></one:T></one:OE>'
    It 'refuses and changes nothing' {
        $u = Undo-AddRequest -Store $w.store -Undo $b.undo
        $u.status | Should Be 'failed'
        $u.message | Should Match 'changed in OneNote'
        @($w.open.model.pages[$a.page.id].entries).Count | Should Be 2
        (Get-FakeOutlineXml $w.f $day.id 'body') | Should Match 'Second'
    }
}
