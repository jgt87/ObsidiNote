# Pester 3.4. The central index: rebuild scan (page wins), fast load from the Index pages, the
# completeness rule, the generated pages, path-based retrieval, the writer lease, and the read-only
# model of a connected notebook. In-memory OneNote stand-in; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')

function New-TestVault {
    $f = New-FakeOneNote
    $a = New-GuardedOneNote -Inner $f
    $v = New-ObsidiVault -Adapter $a -Name 'Synthetic Vault' -Location 'https://example.invalid/docs' -Year 2026
    $s = $v.sectionIds
    $p = @{}
    $p.zt = $f.AddPage($s['Notes'], 'Zero-trust basics', (ConvertTo-ObsnMeta @{ id = 'p1'; type = 'concept'; topics = @('Security/Networking'); summary = 'No implicit trust.'; links = @(@{ target = 'p2'; strength = 3; why = 'uses' }) }))
    $p.iap = $f.AddPage($s['Notes'], 'Identity-aware proxy', (ConvertTo-ObsnMeta @{ id = 'p2'; type = 'concept'; topics = @('Security/Networking', 'Security/Identity'); summary = 'Checks identity per request.' }))
    $p.web = $f.AddPage($s['Web links'], 'Example article', (ConvertTo-ObsnMeta @{ id = 'pa'; type = 'link-web'; topics = @('Gardening'); url = 'https://www.example.org/a'; host = 'www.example.org' }))
    $p.int = $f.AddPage($s['Internal links'], 'Team site home', (ConvertTo-ObsnMeta @{ id = 'pb'; type = 'link-internal'; url = 'https://contoso.sharepoint.com/sites/Ops/SitePages/Home.aspx'; host = 'contoso.sharepoint.com' }))
    $arch = $a.OpenHierarchy('Notes.one', $s['Archive'], 3)
    $p.old = $f.AddPage($arch, 'Old idea', (ConvertTo-ObsnMeta @{ id = 'p9'; type = 'note'; topics = @('Gardening'); status = 'archived'; archivedFrom = 'Notes' }))
    $p.userInNotes = $f.AddPage($s['Notes'], 'Typed by hand', @{}, 1, 'my text')
    $mine = $f.AddSection($v.rootId, 'My recipes')
    $p.userSection = $f.AddPage($mine, 'Soup', @{}, 1, 'mine')
    $p.userInIndex = $f.AddPage($s['00 Index'], 'My own index notes', @{}, 1, 'keep me')
    @{ f = $f; a = $a; v = $v; p = $p }
}

function Get-Lease($w) { Request-WriterLease -Adapter $w.a -IndexSectionId $w.v.indexSectionId -SessionId 'session-a' }

Describe 'Rebuild scan (content pages are the truth)' {
    $w = New-TestVault
    $m = Read-VaultScan -Adapter $w.a -RootId $w.v.rootId -VaultId $w.v.vaultId
    It 'reads every content page and its Meta' {
        $m.pages.Count | Should Be 7
        $m.pages['p2'].topics -join '|' | Should Be 'Security/Networking|Security/Identity'
        $m.pages['p1'].links[0].target | Should Be 'p2'
        $m.pages['p9'].bucket | Should Be 'Archive'
        $m.pages['p9'].status | Should Be 'archived'
    }
    It 'builds the topic tree with parents and children' {
        @($m.topics.Keys) -contains 'Security' | Should Be $true
        $m.topics['Security/Identity'].parent | Should Be 'Security'
        @($m.topics['Security'].children) -join ',' | Should Be 'Security/Networking,Security/Identity'
    }
    It 'keeps the user''s pages as theirs' {
        $m.pages['n:' + $w.p.userInNotes].owner | Should Be 'user'
        $m.pages['n:' + $w.p.userSection].owner | Should Be 'user-section'
        $m.byOneNoteId.ContainsKey($w.p.userInIndex) | Should Be $false
    }
    It 'sets the id counter past the highest id seen' {
        $m.idCounter | Should Be 12
    }
}

Describe 'Completeness rule (synthetic hierarchy)' {
    $ns = 'xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"'
    $xml = @"
<?xml version="1.0"?>
<one:Notebook $ns name="V" ID="{NB}" path="x">
 <one:Section name="00 Index" ID="{S0}" path="x"><one:Page ID="{I1}" name="Index" pageLevel="1"><one:Meta name="obsn.indexKey" content="root"/></one:Page></one:Section>
 <one:Section name="Notes" ID="{S1}" path="x">
  <one:Page ID="{A}" name="Alpha" pageLevel="1"><one:Meta name="obsn.id" content="p1"/><one:Meta name="obsn.topics" content="[&quot;T&quot;]"/></one:Page>
  <one:Page ID="{B}" name="Beta" pageLevel="1"><one:Meta name="obsn.id" content="p2"/><one:Meta name="obsn.topics" content="[&quot;T/U&quot;]"/></one:Page>
  <one:Page ID="{C}" name="Hand-made" pageLevel="1"/>
 </one:Section>
 <one:Section name="Scrapbook" ID="{S2}" path="x"><one:Page ID="{D}" name="Clip" pageLevel="1"/></one:Section>
 <one:SectionGroup name="OneNote_RecycleBin" ID="{RB}" path="x" isRecycleBin="true"><one:Section name="Deleted Pages" ID="{S9}" path="x" isInRecycleBin="true"><one:Page ID="{Z}" name="Gone" pageLevel="1" isInRecycleBin="true"/></one:Section></one:SectionGroup>
</one:Notebook>
"@
    $tree = ConvertFrom-ObsnHierarchy -Xml $xml
    It 'reports every page id of the hierarchy that the index lacks (not index pages, not the recycle bin)' {
        $m = New-IndexModel
        $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'Alpha'; oneNoteId = '{A}'; topics = @('T') }
        $missing = @(Test-IndexComplete -Model $m -Tree $tree)
        @($missing | ForEach-Object { $_.oneNoteId }) -join ',' | Should Be '{B},{C},{D}'
    }
    It 'repairs by adding the missing pages; pages without a topic land on Unfiled' {
        $m = New-IndexModel
        $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'Alpha'; oneNoteId = '{A}'; topics = @('T') }
        $rep = @(Repair-IndexCompleteness -Model $m -Tree $tree)
        $rep.Count | Should Be 3
        @(Test-IndexComplete -Model $m -Tree $tree).Count | Should Be 0
        $m.pages['p2'].topics -join ',' | Should Be 'T/U'
        $specs = @(Get-IndexPageSpecs -Model $m)
        $unf = @($specs | Where-Object { $_.key -eq 'unfiled' })[0]
        (@($unf.lines | Where-Object { $_.html -match 'Hand-made' })).Count | Should Be 1
        $oth = @($specs | Where-Object { $_.key -eq 'other' })[0]
        (@($oth.lines | Where-Object { $_.html -match 'Clip' })).Count | Should Be 1
    }
    It 'is complete for an empty notebook' {
        @(Test-IndexComplete -Model (New-IndexModel) -Tree (ConvertFrom-ObsnHierarchy -Xml "<?xml version=""1.0""?><one:Notebook $ns name=""E"" ID=""{E}"" path=""x""/>")).Count | Should Be 0
    }
}

Describe 'Writing and loading the Index pages' {
    $w = New-TestVault
    $lease = Get-Lease $w
    $r = Update-VaultIndex -Adapter $w.a -RootId $w.v.rootId -IndexSectionId $w.v.indexSectionId -Lease $lease -VaultId $w.v.vaultId
    $sec = ConvertFrom-ObsnHierarchy -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
    $ix = @($sec.sections | Where-Object { $_.full -eq '00 Index' })[0]
    $keys = @($ix.pages | ForEach-Object { $_.meta['obsn.indexKey'] } | Where-Object { $_ })
    It 'writes root, lists, hubs and state' {
        foreach ($k in 'root', 'bytype', 'az', 'unfiled', 'links', 'archive', 'other', 'state', 'topic:Security', 'topic:Security/Networking', 'topic:Security/Identity', 'topic:Gardening') { $keys -contains $k | Should Be $true }
        $r.write.created | Should Be 11
        @($ix.pages | Where-Object { $_.meta['obsn.indexKey'] -eq 'state' }).Count | Should Be 1
    }
    It 'links the root page to the other Index pages and hubs to their pages' {
        $rootId = @($ix.pages | Where-Object { $_.meta['obsn.indexKey'] -eq 'root' })[0].id
        $x = $w.f.GetPageContent($rootId)
        ([regex]::Matches($x, 'href="onenote:')).Count -ge 9 | Should Be $true
        $hub = @($ix.pages | Where-Object { $_.meta['obsn.indexKey'] -eq 'topic:Security/Networking' })[0]
        $w.f.GetPageContent($hub.id) | Should Match 'Zero-trust basics</a>'
        $hub.title | Should Be 'Topic: Security / Networking'
    }
    It 'never touches the user''s page in 00 Index or any content page' {
        $w.f.Nodes[$w.p.userInIndex].title | Should Be 'My own index notes'
        @($w.f.Writes | Where-Object { $_ -match 'UpdatePageContent' -and $_ -match [regex]::Escape($w.p.userInIndex) }).Count | Should Be 0
        foreach ($k in $w.p.Keys) { @($w.f.Writes | Where-Object { $_ -eq "UpdatePageContent $($w.p[$k])" }).Count | Should Be 0 }
    }
    It 'loads the same model back from the Index pages alone (fast load)' {
        $calls = $w.f.Calls['GetHierarchy']
        $m = Read-IndexModel -Adapter $w.a -IndexSectionId $w.v.indexSectionId
        $w.f.Calls['GetHierarchy'] - $calls | Should Be 1
        (@($m.pages.Keys) | Sort-Object) -join ',' | Should Be ((@($r.model.pages.Keys) | Sort-Object) -join ',')
        $m.topics.Count | Should Be $r.model.topics.Count
        $m.pages['p1'].links[0].target | Should Be 'p2'
        $m.pages['p1'].link | Should Match '^onenote:'
        $m.idCounter | Should Be 12
        $m.vaultId | Should Be $w.v.vaultId
    }
    It 'rewrites in place on the next run and removes hubs that are gone' {
        $w.f.Nodes[$w.p.web].meta['obsn.topics'] = '["Security"]'
        $w.f.Nodes[$w.p.old].meta['obsn.topics'] = '["Security"]'
        $r2 = Update-VaultIndex -Adapter $w.a -RootId $w.v.rootId -IndexSectionId $w.v.indexSectionId -Lease $lease
        $r2.changed -contains 'pa' | Should Be $true
        $r2.write.created | Should Be 0
        $r2.model.pages['pa'].topics -join ',' | Should Be 'Security'
        $m = Read-IndexModel -Adapter $w.a -IndexSectionId $w.v.indexSectionId
        $m.pages['pa'].topics -join ',' | Should Be 'Security'
        # Gardening has no pages now but the index keeps a topic once made (pages win, topics stay)
        $m.topics.Contains('Gardening') | Should Be $true
    }
    It 'refuses to write without the writer lease' {
        $ro = [pscustomobject]@{ mode = 'readonly'; expires = [datetime]::UtcNow.AddMinutes(5) }
        { Write-IndexPages -Adapter $w.a -Model $r.model -IndexSectionId $w.v.indexSectionId -Lease $ro } | Should Throw
        { Write-IndexPages -Adapter $w.a -Model $r.model -IndexSectionId $w.v.indexSectionId -Lease $null } | Should Throw
    }
}

Describe 'Intake requests are not content (each Add showed twice on the map, 2026-11-13)' {
    $w = New-TestVault
    $lease = Get-Lease $w
    $req = $w.f.AddPage($w.v.sectionIds['01 Intake'], 'https://www.example.org/a', @{ 'obsn.status' = 'filed'; 'obsn.filedAs' = 'pa' }, 1, 'https://www.example.org/a')
    $wait = $w.f.AddPage($w.v.sectionIds['01 Intake'], 'Some pasted text', @{ 'obsn.status' = 'waiting' }, 1, 'Some pasted text')
    $r = Update-VaultIndex -Adapter $w.a -RootId $w.v.rootId -IndexSectionId $w.v.indexSectionId -Lease $lease -VaultId $w.v.vaultId
    It 'leaves the Intake pages out of the scan, the completeness check and the Index pages' {
        $r.model.byOneNoteId.ContainsKey($req) | Should Be $false
        $r.model.byOneNoteId.ContainsKey($wait) | Should Be $false
        @($r.missing).Count | Should Be 0
        $tree = ConvertFrom-ObsnHierarchy -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        @(Test-IndexComplete -Model $r.model -Tree $tree).Count | Should Be 0
        (Read-IndexModel -Adapter $w.a -IndexSectionId $w.v.indexSectionId).byOneNoteId.ContainsKey($req) | Should Be $false
    }
    It 'drops Intake entries that older Index pages still list, on load and on the next start' {
        $old = $r.model
        $null = Add-IndexPage -Model $old -Page @{ title = 'https://www.example.org/a'; oneNoteId = $req; section = '01 Intake'; updated = '2026-11-13T00:00:00.000Z' }
        $null = Write-IndexPages -Adapter $w.a -Model $old -IndexSectionId $w.v.indexSectionId -Lease $lease
        (Read-IndexModel -Adapter $w.a -IndexSectionId $w.v.indexSectionId).byOneNoteId.ContainsKey($req) | Should Be $false
        $r2 = Update-VaultIndex -Adapter $w.a -RootId $w.v.rootId -IndexSectionId $w.v.indexSectionId -Lease $lease -VaultId $w.v.vaultId
        $r2.model.byOneNoteId.ContainsKey($req) | Should Be $false
        $r2.model.pages.Contains('pa') | Should Be $true
    }
}

Describe 'Large lists' {
    $m = New-IndexModel
    for ($i = 1; $i -le 30; $i++) { $null = Add-IndexPage -Model $m -Page @{ id = (New-ObsnId $i); title = "Entry $i"; oneNoteId = "{X$i}"; bucket = 'Notes'; topics = @('Big'); summary = ('s' * 40) } }
    It 'continues a long page as <Title> (2), with the data Meta on the first part only' {
        $specs = @(Get-IndexPageSpecs -Model $m -MaxLines 10)
        @($specs | Where-Object { $_.key -like 'az*' }).Count | Should Be 4
        @($specs | Where-Object { $_.key -eq 'az#2' })[0].title | Should Be 'A-Z (2)'
        @($specs | Where-Object { $_.key -eq 'topic:Big#2' })[0].meta.Count | Should Be 0
    }
    It 'splits the entries Meta when it is longer than the limit, and loads it back' {
        $specs = @(Get-IndexPageSpecs -Model $m -MaxMeta 500)
        $hub = @($specs | Where-Object { $_.key -eq 'topic:Big' })[0]
        [int]$hub.meta['obsn.entries.n'] | Should BeGreaterThan 1
        $ns = 'xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"'
        $metaXml = (@($hub.meta.Keys | ForEach-Object { '<one:Meta name="' + $_ + '" content="' + [Security.SecurityElement]::Escape([string]$hub.meta[$_]) + '"/>' }) -join '')
        $xml = "<?xml version=""1.0""?><one:Section $ns name=""00 Index"" ID=""{S}""><one:Page ID=""{H}"" name=""Topic: Big""><one:Meta name=""obsn.indexKey"" content=""topic:Big""/>$metaXml</one:Page></one:Section>"
        $back = ConvertFrom-IndexSectionXml -Xml $xml
        $back.pages.Count | Should Be 30
        $back.pages[(New-ObsnId 30)].title | Should Be 'Entry 30'
    }
}

Describe 'Path-based retrieval' {
    $m = New-IndexModel
    $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'Zero trust'; oneNoteId = '{1}'; topics = @('Security/Networking'); summary = 'No implicit trust.' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p2'; title = 'Proxies'; oneNoteId = '{2}'; topics = @('Security/Networking/Proxies'); summary = 'Per-request checks.' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p3'; title = 'Compost'; oneNoteId = '{3}'; topics = @('Gardening'); summary = 'Brown and green.' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p4'; title = 'Old firewall'; oneNoteId = '{4}'; topics = @('Security'); status = 'archived' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p5'; title = 'Loose'; oneNoteId = '{5}' }
    It 'step 1 gives the top-level topics with counts and subtopic names' {
        $t = Get-IndexTopLevel -Model $m
        @($t.topics | ForEach-Object { $_.path }) -join ',' | Should Be 'Gardening,Security'
        @($t.topics | Where-Object { $_.path -eq 'Security' })[0].pages | Should Be 2
        $t.text | Should Match 'Security \[2 pages\]: Networking'
        $t.text | Should Match '\(Unfiled\) \[1 pages\]'
        $t.truncated | Should Be $false
    }
    It 'step 2 gives a branch breadth first, without archived pages by default' {
        $b = Get-IndexBranch -Model $m -Paths @('Security')
        $b.pages -join ',' | Should Be 'p1,p2'
        $b.text | Should Match 'p1 \| Zero trust \| No implicit trust\.'
        (Get-IndexBranch -Model $m -Paths @('Security') -IncludeArchived).pages -join ',' | Should Be 'p4,p1,p2'
        (Get-IndexBranch -Model $m -Paths @('(Unfiled)')).pages -join ',' | Should Be 'p5'
    }
    It 'stays within the prompt budget' {
        $t = Get-IndexTopLevel -Model $m -MaxChars 30
        $t.truncated | Should Be $true
        $t.text.Length -le 30 | Should Be $true
        $b = Get-IndexBranch -Model $m -Paths @('Security') -MaxChars 80
        $b.truncated | Should Be $true
        $b.text.Length -le 80 | Should Be $true
    }
}

Describe 'Writer lease' {
    $w = New-TestVault
    $ix = $w.v.indexSectionId
    $t0 = [datetime]'2026-03-01T10:00:00Z'
    It 'is taken when free and renewed by its holder' {
        $l = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'one' -Now $t0 -TtlSec 120
        $l.mode | Should Be 'writer'
        $l2 = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'one' -Now $t0.AddSeconds(60) -TtlSec 120
        $l2.mode | Should Be 'writer'
        $l2.expires | Should Be $t0.AddSeconds(180).ToUniversalTime()
    }
    It 'makes a second instance read-only while the lease is valid' {
        $o = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'two' -Now $t0.AddSeconds(90)
        $o.mode | Should Be 'readonly'
        $o.holder | Should Be 'one'
        Test-WriterLease $o -Now $t0 | Should Be $false
    }
    It 'lets another instance take over an expired lease' {
        $o = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'two' -Now $t0.AddSeconds(400)
        $o.mode | Should Be 'writer'
        (Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'one' -Now $t0.AddSeconds(401)).mode | Should Be 'readonly'
    }
    It 'is given back on exit only by its holder' {
        $mine = [pscustomobject]@{ sessionId = 'two'; indexSectionId = $ix }
        Clear-WriterLease -Adapter $w.a -Lease ([pscustomobject]@{ sessionId = 'one'; indexSectionId = $ix }) | Should Be $false
        Clear-WriterLease -Adapter $w.a -Lease $mine | Should Be $true
        (Get-VaultState -Adapter $w.a -IndexSectionId $ix).lease | Should Be ''
    }
    It 'treats an invalid value as free and expires by time' {
        Get-LeaseDecision -Current 'garbage' -SessionId 'x' -Now $t0 | Should Be 'acquire'
        Get-LeaseDecision -Current '' -SessionId 'x' -Now $t0 | Should Be 'acquire'
        $l = [pscustomobject]@{ mode = 'writer'; expires = $t0 }
        Test-WriterLease $l -Now $t0.AddSeconds(-1) | Should Be $true
        Test-WriterLease $l -Now $t0.AddSeconds(1) | Should Be $false
    }
    It 'is per vault: a lease in one vault does not block another' {
        $v2 = New-ObsidiVault -Adapter $w.a -Name 'Second' -Location 'https://example.invalid/docs' -Year 2026
        (Request-WriterLease -Adapter $w.a -IndexSectionId $v2.indexSectionId -SessionId 'three' -Now $t0.AddSeconds(402)).mode | Should Be 'writer'
    }
}

Describe 'Connected (foreign) notebook, read only' {
    $f = New-FakeOneNote
    $a = New-GuardedOneNote -Inner $f
    $nb = $f.AddNotebook('Club notes')
    $top = $f.AddSection($nb, 'General')
    $g = $f.AddGroup($nb, 'Events'); $s1 = $f.AddSection($g, 'Spring'); $s2 = $f.AddSection($g, 'Autumn')
    $pA = $f.AddPage($top, 'Welcome', @{}, 1, '')
    $pB = $f.AddPage($s1, 'Fair', @{}, 1, '')
    $pB1 = $f.AddPage($s1, 'Stalls', @{}, 2, '')
    $pB2 = $f.AddPage($s1, 'Stall rota', @{}, 3, '')
    $pC = $f.AddPage($s2, 'Harvest', @{}, 1, '')
    $f.AddRecycleBin($nb) | Out-Null
    # cross links: Welcome -> Fair and Harvest; Stalls -> Welcome; a link to another notebook is ignored
    $f.Nodes[$pA].outlines.Add(@{ objectId = '{O1}'; xml = '<one:Outline objectID="{O1}"><one:OEChildren><one:OE><one:T><![CDATA[See <a href="' + ($f.GetHyperlinkToObject($pB)).Replace('&', '&amp;') + '">Fair</a> and <a href="' + ($f.GetHyperlinkToObject($pC)).Replace('&', '&amp;') + '">Harvest</a> and <a href="onenote:https://example.invalid/other.one#x&amp;page-id={11111111-2222-3333-4444-555555555555}&amp;end">elsewhere</a>]]></one:T></one:OE></one:OEChildren></one:Outline>' }) | Out-Null
    $f.Nodes[$pB1].outlines.Add(@{ objectId = '{O2}'; xml = '<one:Outline objectID="{O2}"><one:OEChildren><one:OE><one:T><![CDATA[<a href="' + ($f.GetHyperlinkToObject($pA)).Replace('&', '&amp;') + '">back</a>]]></one:T></one:OE></one:OEChildren></one:Outline>' }) | Out-Null
    $writes = $f.Writes.Count
    $m = Get-NotebookModel -Adapter $a -Name 'Club notes'
    It 'derives topics from section groups and sections' {
        $m.kind | Should Be 'foreign'
        $m.readOnly | Should Be $true
        (@($m.topics.Keys) | Sort-Object) -join ',' | Should Be 'Events,Events/Autumn,Events/Spring,General'
        $m.pages.Count | Should Be 5
        $m.pages['n:' + $pB].topics -join ',' | Should Be 'Events/Spring'
        $m.pages['n:' + $pA].link | Should Match '^onenote:'
    }
    It 'makes subpages children of the page above them' {
        $m.pages['n:' + $pB1].parent | Should Be ('n:' + $pB)
        $m.pages['n:' + $pB2].parent | Should Be ('n:' + $pB1)
        @($m.pages['n:' + $pB].children) -join ',' | Should Be ('n:' + $pB1)
        $m.pages['n:' + $pC].parent | Should Be ''
    }
    It 'reads links between its pages in batches into edges' {
        $r1 = Get-NotebookLinks -Adapter $a -Model $m -Start 0 -BatchSize 2
        $r1.done | Should Be $false
        $r1.next | Should Be 2
        $n = $r1.next; $total = $r1.edges
        while ($true) { $r = Get-NotebookLinks -Adapter $a -Model $m -Start $n -BatchSize 2; $total += $r.edges; $n = $r.next; if ($r.done) { break } }
        $total | Should Be 3
        (@($m.pages['n:' + $pA].links | ForEach-Object { $_.target }) | Sort-Object) -join ',' | Should Be ((@(('n:' + $pB), ('n:' + $pC)) | Sort-Object) -join ',')
        $m.pages['n:' + $pB1].links[0].target | Should Be ('n:' + $pA)
        @(Get-IndexEdges -Model $m).Count | Should Be 3
        (Get-NotebookLinks -Adapter $a -Model $m -Start 0 -BatchSize 10).edges | Should Be 0
    }
    It 'never writes to the notebook' {
        $f.Writes.Count | Should Be $writes
    }
    It 'can be walked with the same retrieval helpers' {
        (Get-IndexTopLevel -Model $m).text | Should Match 'Events \[4 pages\]: Autumn, Spring'
        (Get-IndexBranch -Model $m -Paths @('Events')).pages.Count | Should Be 4
    }
    It 'loads a vault notebook from its own index, read only' {
        $v = New-ObsidiVault -Adapter $a -Name 'Vault Two' -Year 2026
        $vm = Get-NotebookModel -Adapter $a -NotebookId $v.rootId
        $vm.kind | Should Be 'vault'
        $vm.readOnly | Should Be $true
        $vm.vaultId | Should Be $v.vaultId
    }
}

Describe 'Links page grouping' {
    It 'groups internal links by site or team and web links by domain' {
        Get-LinkGroup @{ bucket = 'Internal links'; url = 'https://contoso.sharepoint.com/sites/Ops/SitePages/Home.aspx'; host = 'contoso.sharepoint.com'; type = '' } | Should Be 'contoso.sharepoint.com/sites/Ops'
        Get-LinkGroup @{ bucket = 'Internal links'; url = 'https://teams.microsoft.com/l/channel/x'; host = ''; type = '' } | Should Be 'Teams'
        Get-LinkGroup @{ bucket = 'Web links'; url = 'https://www.example.org/a'; host = ''; type = '' } | Should Be 'example.org'
    }
}
