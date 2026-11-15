# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Archive, Restore and Delete of pages (lib/Ingest.psm1 Get-RetirePlan / Invoke-PageRetire,
# FEASIBILITY.md "Archive and delete"), and moving a page by changing its type or address in Edit,
# through the real store, the write guard and the lease against the in-memory OneNote. A move gives
# the page a new hierarchy id (as desktop OneNote does), so its index record and the "Linked from"
# lists of the pages it links to follow. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function Get-PageNode($W, [string]$Id) {
    $rec = $W.open.model.pages[$Id]
    if (-not $rec) { return $null }
    $W.f.Nodes[$rec.oneNoteId]
}
function Get-SectionName($W, $Node) { $W.f.Nodes[$Node.parent].name }
function Get-ParentName($W, $Node) { $W.f.Nodes[$W.f.Nodes[$Node.parent].parent].name }

Describe 'Get-RetirePlan: what would happen, nothing written' {
    $w = New-SyntheticVault
    It 'names where each page goes and how many pages link to it' {
        $before = $w.f.Writes.Count
        $p = Get-RetirePlan -Store $w.store -Action archive -Ids @('p1', 'p3')
        @($p.pages).Count | Should Be 2
        $p1 = @($p.pages | Where-Object { $_.id -eq 'p1' })[0]
        "$($p1.section)>$($p1.to)|$($p1.inbound)" | Should Be 'Notes>Archive/Notes|1'
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses a page that is not ObsidiNote''s, and restore of a page that is not archived' {
        $p = Get-RetirePlan -Store $w.store -Action archive -Ids @('p99')
        @($p.refused)[0].reason | Should Match 'not one of ObsidiNote'
        (@((Get-RetirePlan -Store $w.store -Action restore -Ids @('p1')).refused)[0].reason) | Should Match 'not archived'
    }
}

Describe 'Archive and Restore' {
    $w = New-SyntheticVault
    $userP1 = @($w.f.Nodes[(Get-PageNode $w 'p1').id].outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml }) -join '|'
    It 'moves the page to Archive/<bucket> and marks it, on the page and in the index' {
        $r = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
        $r.status | Should Be 'done'
        $r.message | Should Match 'Archived: Zero-trust networking'
        $n = Get-PageNode $w 'p1'
        "$(Get-ParentName $w $n)/$(Get-SectionName $w $n)" | Should Be 'Archive/Notes'
        $n.meta['obsn.status'] | Should Be 'archived'
        $n.meta['obsn.archivedFrom'] | Should Be 'Notes'
        $rec = $w.open.model.pages['p1']
        "$($rec.status)|$($rec.section)|$($rec.archivedFrom)" | Should Be 'archived|Archive/Notes|Notes'
    }
    It 'keeps its links, its id and the person''s own text' {
        $n = Get-PageNode $w 'p1'
        $n.meta['obsn.id'] | Should Be 'p1'
        (@($n.outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml }) -join '|') | Should Be $userP1
        $ix = & $w.store.GetIndex
        @($ix.edges | Where-Object { $_.from -eq 'p3' -and $_.to -eq 'p1' }).Count | Should Be 1
    }
    It 'refuses to archive it twice and writes nothing' {
        $before = $w.f.Writes.Count
        $r = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
        $r.status | Should Be 'invalid'
        $r.message | Should Match 'already archived'
        $w.f.Writes.Count | Should Be $before
    }
    It 'Restore puts it back in its section and clears the mark' {
        $r = Invoke-PageRetire -Store $w.store -Action restore -Ids @('p1')
        $r.status | Should Be 'done'
        $n = Get-PageNode $w 'p1'
        Get-SectionName $w $n | Should Be 'Notes'
        $n.meta['obsn.status'] | Should Be ''
        $n.meta['obsn.archivedFrom'] | Should Be ''
        "$($w.open.model.pages['p1'].status)|$($w.open.model.pages['p1'].section)" | Should Be '|Notes'
    }
    It 'writes the "Linked from" list of the pages a moved page links to again' {
        $null = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p3')
        $p1 = Get-PageNode $w 'p1'
        Get-FakeOutlineXml $w.f $p1.id 'backlinks' | Should Match 'VPN retirement plan'
        $w.open.model.pages['p3'].link | Should Be ($w.f.GetHyperlinkToObject((Get-PageNode $w 'p3').id))
    }
    It 'refuses without the writer lease and writes nothing' {
        $before = $w.f.Writes.Count
        $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        (Invoke-PageRetire -Store $w.store -Action restore -Ids @('p3')).status | Should Be 'refused'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Delete' {
    $w = New-SyntheticVault
    It 'sends the page to Deleted Pages, takes it out of the index and the links of other pages' {
        $pageId = $w.open.model.pages['p1'].oneNoteId
        $r = Invoke-PageRetire -Store $w.store -Action delete -Ids @('p1', 'p99')
        $r.status | Should Be 'done'
        $r.message | Should Match '60 days'
        @($r.refused).Count | Should Be 1
        $w.f.Nodes.ContainsKey($pageId) | Should Be $false
        @($w.f.Writes | Where-Object { $_ -eq "DeleteHierarchy $pageId" }).Count | Should Be 1
        $w.open.model.pages.Contains('p1') | Should Be $false
        (Get-PageNode $w 'p3').meta['obsn.links'] | Should Be '[]'
        @($w.open.model.deleted | Where-Object { $_.title -eq 'Zero-trust networking' }).Count | Should Be 1
    }
    It 'deletes several pages, one failing page does not stop the others' {
        $store = @{} + $w.store
        $real = $w.store.DeletePage
        $bad = $w.open.model.pages['p2'].oneNoteId
        $store.DeletePage = { param([string]$PageId) if ($PageId -eq $bad) { throw 'OneNote refused' }; & $real $PageId }.GetNewClosure()
        $r = Invoke-PageRetire -Store $store -Action delete -Ids @('p2', 'p3')
        $r.status | Should Be 'partial'
        (@($r.done | ForEach-Object { $_.id }) -join ',') | Should Be 'p3'
        @($r.failed)[0].error | Should Match 'OneNote refused'
        $w.open.model.pages.Contains('p2') | Should Be $true
    }
}

Describe 'Edit: another type or address moves the page' {
    $w = New-SyntheticVault
    It 'a type of another section moves the page there and keeps its id' {
        $r = Edit-Page -Store $w.store -Id 'p3' -Changes @{ type = 'decision' }
        $r.status | Should Be 'edited'
        $r.moved | Should Be 'Decisions'
        $r.message | Should Match 'moved to Decisions'
        $n = Get-PageNode $w 'p3'
        Get-SectionName $w $n | Should Be 'Decisions'
        "$($n.meta['obsn.id'])|$($n.meta['obsn.type'])" | Should Be 'p3|decision'
        "$($w.open.model.pages['p3'].section)|$($w.open.model.pages['p3'].type)" | Should Be 'Decisions|decision'
        Get-FakeOutlineXml $w.f (Get-PageNode $w 'p1').id 'backlinks' | Should Match 'VPN retirement plan'
    }
    It 'a log goes to this year''s Journal section' {
        $null = Edit-Page -Store $w.store -Id 'p2' -Changes @{ type = 'log' }
        $n = Get-PageNode $w 'p2'
        "$(Get-ParentName $w $n)/$(Get-SectionName $w $n)" | Should Be "Journal/$((Get-Date).Year)"
    }
    It 'an address of the other link section moves a link page and sets its link type' {
        $sid = $w.v.sectionIds['Web links']
        $pid4 = $w.f.AddPage($sid, 'Example handbook', @{ 'obsn.id' = 'p4'; 'obsn.type' = 'link-web'; 'obsn.url' = 'https://www.example.org/handbook'; 'obsn.host' = 'www.example.org'; 'obsn.links' = '[]' }, 1, 'A public handbook.')
        & $w.store.IndexAddPage @{ id = 'p4'; title = 'Example handbook'; type = 'link-web'; url = 'https://www.example.org/handbook'; host = 'www.example.org'; topics = @(); links = @(); pageId = $pid4; section = 'Web links'; link = 'onenote:#p4' } | Out-Null
        $r = Edit-Page -Store $w.store -Id 'p4' -Changes @{ url = 'https://contoso.sharepoint.com/sites/handbook' }
        $r.status | Should Be 'edited'
        $r.moved | Should Be 'Internal links'
        (Get-PageNode $w 'p4').meta['obsn.type'] | Should Be 'link-internal'
    }
    It 'refuses to move an archived page: Restore first' {
        $null = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
        $before = $w.f.Writes.Count
        $x = Edit-Page -Store $w.store -Id 'p1' -Changes @{ type = 'meeting' }
        $x.status | Should Be 'invalid'
        $x.message | Should Match 'Restore it first'
        $w.f.Writes.Count | Should Be $before
    }
}
