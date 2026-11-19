# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/Upgrade.psm1: existing pages follow rules that changed after they were filed (operator,
# 2026-11-13). Old-shaped data in the in-memory OneNote: company SaaS links filed under Web links
# before the internal-link rule changed. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest', 'Upgrade') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function Add-OldLinkPage($W, [string]$Id, [string]$Title, [string]$Url, [string]$Section = 'Web links', [string]$Status = '', [string]$Links = '[]') {
    # A link page as an older version filed it: type link-web in Web links.
    $sid = if ($W.v.sectionIds.ContainsKey($Section)) { $W.v.sectionIds[$Section] } else { $W.a.OpenHierarchy('Web links.one', $W.v.sectionIds['Archive'], 3) }
    $meta = @{ 'obsn.id' = $Id; 'obsn.type' = 'link-web'; 'obsn.url' = $Url; 'obsn.host' = ([uri]$Url).Host; 'obsn.topics' = '["Security"]'; 'obsn.links' = $Links }
    if ($Status) { $meta['obsn.status'] = $Status }
    $pg = $W.f.AddPage($sid, $Title, $meta, 1, 'Text the person typed on this link page.')
    $sec = if ($Section -eq 'Archive') { 'Archive/Web links' } else { $Section }
    & $W.store.IndexAddPage @{ id = $Id; title = $Title; type = 'link-web'; url = $Url; host = ([uri]$Url).Host; topics = @('Security'); links = @(ConvertFrom-Json $Links | ForEach-Object { @{ target = $_.t; strength = $_.s; why = $_.w } }); pageId = $pg; section = $sec; link = "onenote:#$Id"; status = $Status } | Out-Null
    $pg
}

Describe 'Upgrade: link pages move to the section the current rule asks for' {
    $w = New-SyntheticVault
    $snow = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://fernbrook.service-now.com/kb?id=1' -Links '[{"t":"p1","s":2,"w":"explains"}]'
    $null = Add-OldLinkPage $w 'p8' 'Public handbook' 'https://www.example.org/handbook'
    $null = Add-OldLinkPage $w 'p9' 'Old portal page' 'https://fernbrook.service-now.com/old' -Section 'Archive' -Status 'archived'
    $named = Add-OldLinkPage $w 'p10' 'Internal vacancies' 'https://fernbrook.example-hr.com/vacancies'
    # the store as the start makes it: the company name comes from the vault's own address
    $store = New-VaultStore -Adapter $w.a -Vault $w.open.vault -Model $w.open.model -GetLease { $w.box.lease }.GetNewClosure() -CompanyNames @('fernbrook')

    It 'plans only ObsidiNote''s live link pages in the wrong section' {
        $plan = @(Get-UpgradePlan -Model $w.open.model -CompanyNames @('fernbrook'))
        (@($plan | ForEach-Object { "$($_.id):$($_.to):$($_.type)" } | Sort-Object) -join ',') | Should Be 'p10:Internal links:link-internal,p7:Internal links:link-internal'
    }
    $userText = $w.f.Nodes[$snow].outlines | Where-Object { $_.xml -match 'Text the person typed' } | ForEach-Object { $_.xml }
    $r = Invoke-VaultUpgrade -Store $store
    It 'moves them, and says so' {
        $r.status | Should Be 'done'
        $r.moved | Should Be 2
        (Format-UpgradeStatus $r).detail | Should Match '2 link page'
    }
    It 'files the page under Internal links with type link-internal, its new OneNote id in the index' {
        $rec = $w.open.model.pages['p7']
        $rec.section | Should Be 'Internal links'
        $rec.bucket | Should Be 'Internal links'
        $rec.type | Should Be 'link-internal'
        $rec.oneNoteId | Should Not Be $snow
        $w.f.Nodes.ContainsKey($snow) | Should Be $false
        $n = $w.f.Nodes[$rec.oneNoteId]
        $w.f.Nodes[$n.parent].name | Should Be 'Internal links'
        $n.meta['obsn.type'] | Should Be 'link-internal'
        $w.open.model.byOneNoteId.ContainsKey($snow) | Should Be $false
        $w.open.model.byOneNoteId[$rec.oneNoteId] | Should Be 'p7'
    }
    It 'keeps the person''s text on the moved page' {
        $n = $w.f.Nodes[$w.open.model.pages['p7'].oneNoteId]
        (@($n.outlines | Where-Object { $_.xml -match 'Text the person typed' } | ForEach-Object { $_.xml }) -join '') | Should Be (@($userText) -join '')
    }
    It 'writes the new link into "Linked from" of the page it links to' {
        Get-FakeOutlineXml $w.f (Find-FakePage $w.f 'Zero-trust networking').id 'backlinks' | Should Match 'Service desk article'
    }
    It 'leaves public pages, archived pages and the person''s pages where they are' {
        $w.open.model.pages['p8'].section | Should Be 'Web links'
        $w.open.model.pages['p9'].section | Should Be 'Archive/Web links'
        $w.f.Nodes[$w.tomato].parent | Should Not Be $null
    }
    It 'finds nothing to do at the next start (idempotent)' {
        $before = $w.f.Writes.Count
        $again = Invoke-VaultUpgrade -Store $store
        $again.status | Should Be 'none'
        Format-UpgradeStatus $again | Should Be $null
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Upgrade: "Link it" links written as loose (1) before 2026-11-14 become related (2)' {
    $w = New-SyntheticVault
    # Old shape: p2 got a "Link it" link with strength 1 next to a link Copilot rated loose.
    $why = 'Linked by you (mentioned in the text)'
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    $old = '[{"t":"p1","s":1,"w":"' + $why + '"},{"t":"p3","s":1,"w":"loose match"}]'
    $p2.meta['obsn.links'] = $old
    & $w.store.IndexUpdatePage @{ id = 'p2'; links = @(@{ target = 'p1'; strength = 1; why = $why }, @{ target = 'p3'; strength = 1; why = 'loose match' }) } | Out-Null
    $user = @($p2.outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml }) -join '|'

    It 'plans only the page with a weak "Link it" link' {
        (@(Get-UpgradePlan -Model $w.open.model) | ForEach-Object { "$($_.step):$($_.id)" }) -join ',' | Should Be 'link-strength:p2'
    }
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'raises it in the page''s own Meta and its index record, and says so' {
        $r.status | Should Be 'done'
        $r.raised | Should Be 1
        (Format-UpgradeStatus $r).detail | Should Be 'your own links on 1 page(s) set to related'
        $p2.meta['obsn.links'] | Should Be ('[{"t":"p1","s":2,"w":"' + $why + '"},{"t":"p3","s":1,"w":"loose match"}]')
        (@($w.open.model.pages['p2'].links | ForEach-Object { "$($_.target):$($_.strength)" }) -join ',') | Should Be 'p1:2,p3:1'
    }
    It 'leaves Copilot''s rating and the person''s own text alone' {
        (@($p2.outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml }) -join '|') | Should Be $user
    }
    It 'finds nothing to do at the next start (idempotent)' {
        $before = $w.f.Writes.Count
        $again = Invoke-VaultUpgrade -Store $w.store
        $again.status | Should Be 'none'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Upgrade: meetings imported before series pages get their notes kept and one series page (operator, 2026-11-19)' {
    Import-Module (Join-Path $root 'lib\Meetings.psm1') -Force -Global
    $w = New-SyntheticVault
    # Old shape (v0.12.11-v0.12.14): meeting pages with series and meetingAt, the notes only as text.
    $notes = @{ found = $true; date = ''; attendees = @(@{ name = 'Ada Example'; email = 'ada@example.com' }, @{ name = 'Bo Sample'; email = '' }); summary = 'The beds move north.'; decisions = @('Move the beds.'); actions = @(@{ text = 'Order a pump'; owner = 'Ada Example'; due = '2031-04-12' }); basedOn = 'transcript' }
    $made = @{}
    foreach ($d in '2031-04-08', '2031-04-09') {
        $text = ConvertTo-MeetingNoteText -Title 'Garden sync' -Day $d -Time '10:00' -Notes $notes
        $id = & $w.store.NewId
        $page = @{ id = $id; type = 'meeting'; bucket = (& $w.store.BucketForType 'meeting'); title = "Garden sync $d"; summary = 'The beds move north.'; topics = @('Garden'); aliases = @(); links = @(); status = ''; origin = 'meeting'
            series = 'Garden sync'; meetingAt = "${d}T10:00"; outlines = @(@{ role = 'body'; lines = (ConvertTo-BodyLines $text) }) }
        $cp = & $w.store.CreatePage $page
        $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']
        & $w.store.IndexAddPage $page | Out-Null
        $made[$d] = $page
    }
    It 'plans each page''s notes and one series page' {
        $plan = @(Get-UpgradePlan -Model $w.open.model)
        (@($plan | Where-Object { $_.step -eq 'series-data' } | ForEach-Object { $_.id } | Sort-Object) -join ',') | Should Be (@($made.Values | ForEach-Object { $_.id } | Sort-Object) -join ',')
        (@($plan | Where-Object { $_.step -eq 'series-page' } | ForEach-Object { "$($_.from):$($_.type)" }) -join ',') | Should Be 'garden sync:new'
    }
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'reads the notes back from the page''s own text and keeps them as its data' {
        $r.status | Should Be 'done'
        $r.meetingData | Should Be 2
        $pg = $w.f.Nodes[$made['2031-04-08'].pageId]
        $d = ConvertFrom-MeetingDataValue (ConvertFrom-ObsnMeta -Meta $pg.meta).meeting
        $d.summary | Should Be 'The beds move north.'
        $d.decisions -join '|' | Should Be 'Move the beds.'
        "$($d.actions[0].text)|$($d.actions[0].owner)|$($d.actions[0].due)" | Should Be 'Order a pump|Ada Example|2031-04-12'
        (@($d.people | ForEach-Object { "$($_.name)/$($_.email)" }) -join ',') | Should Be 'Ada Example/ada@example.com,Bo Sample/'
    }
    It 'writes one series page that links both meetings, without asking Copilot, and says so' {
        $r.seriesPages | Should Be 1
        $sp = @($w.open.model.pages.Values | Where-Object { $_.kind -eq 'series' })
        $sp.Count | Should Be 1
        $sp[0].title | Should Be 'Garden sync (series)'
        (@($sp[0].links | ForEach-Object { $_.target } | Sort-Object) -join ',') | Should Be (@($made.Values | ForEach-Object { $_.id } | Sort-Object) -join ',')
        (Format-UpgradeStatus $r).detail | Should Match '1 series page\(s\) written'
        (Format-UpgradeStatus $r).detail | Should Match 'the notes of 2 meeting page\(s\)'
    }
    It 'finds nothing to do at the next start, also after the index was loaded again (idempotent)' {
        @(Get-UpgradePlan -Model $w.open.model | Where-Object { $_.step -like 'series-*' }).Count | Should Be 0
        # The index keeps only the marker, never the notes: a reload must not plan the pages again.
        $entry = ConvertFrom-IndexEntry (ConvertFrom-Json (ConvertTo-CompactJson (ConvertTo-IndexEntry $w.open.model.pages[$made['2031-04-09'].id])))
        $entry['meetingData'] | Should Be '1'
        $entry.ContainsKey('meeting') | Should Be $false
    }
    It 'adds a later meeting to the series page at the next start' {
        $page = $made['2031-04-09'].Clone(); $page.id = & $w.store.NewId; $page.meetingAt = '2031-04-10T10:00'; $page.title = 'Garden sync 2031-04-10'
        $cp = & $w.store.CreatePage $page; $page.pageId = [string]$cp['pageId']
        & $w.store.IndexAddPage $page | Out-Null
        $r2 = Invoke-VaultUpgrade -Store $w.store
        $r2.seriesPages | Should Be 1
        @($w.open.model.pages.Values | Where-Object { $_.kind -eq 'series' }).Count | Should Be 1
        @(@($w.open.model.pages.Values | Where-Object { $_.kind -eq 'series' })[0].links).Count | Should Be 3
    }
}

Describe 'Upgrade: meeting pages from before series get their series (operator, 2026-11-18)' {
    $w = New-SyntheticVault
    # Old shape: a page Today's meetings made on 17 Nov (v0.12.8-v0.12.10), Copilot's title with the date.
    $pg = Find-FakePage $w.f 'Partner portal: access review notes'
    $pg.meta['obsn.type'] = 'meeting'; $pg.meta['obsn.origin'] = 'meeting'
    $rec = $w.open.model.pages['p2']
    $rec.type = 'meeting'; $rec.origin = 'meeting'; $rec.title = '2026-11-17 Garden sync Tidal beds'
    It 'plans the meeting page' {
        (@(Get-UpgradePlan -Model $w.open.model) | Where-Object { $_.step -eq 'meeting-series' } | ForEach-Object { "$($_.id):$($_.to):$($_.type)" }) -join ',' | Should Be 'p2:Garden sync Tidal beds:2026-11-17'
    }
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'writes the series and the day on the page and its index record, and says so' {
        $r.status | Should Be 'done'
        $r.series | Should Be 1
        (Format-UpgradeStatus $r).detail | Should Match '1 meeting page\(s\) given their series'
        $pg.meta['obsn.series'] | Should Be 'Garden sync Tidal beds'
        $pg.meta['obsn.meetingAt'] | Should Be '2026-11-17'
        $w.open.model.pages['p2'].series | Should Be 'Garden sync Tidal beds'
    }
    It 'finds nothing to do at the next start (idempotent)' {
        (@(Get-UpgradePlan -Model $w.open.model) | Where-Object { $_.step -eq 'meeting-series' }).Count | Should Be 0
    }
}

Describe 'Upgrade: the page is already right, its index record is not (code review 2026-11-14)' {
    $w = New-SyntheticVault
    # An earlier run raised the page's Meta, then its index write failed: Meta s=2, index s=1.
    $why = 'Linked by you (mentioned in the text)'
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    $p2.meta['obsn.links'] = '[{"t":"p1","s":2,"w":"' + $why + '"}]'
    & $w.store.IndexUpdatePage @{ id = 'p2'; links = @(@{ target = 'p1'; strength = 1; why = $why }) } | Out-Null
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'mirrors the page into the index and says so' {
        $r.status | Should Be 'done'
        $r.raised | Should Be 1
        (@($w.open.model.pages['p2'].links | ForEach-Object { "$($_.target):$($_.strength)" }) -join ',') | Should Be 'p1:2'
    }
    It 'does not plan it again at the next start' {
        (Invoke-VaultUpgrade -Store $w.store).status | Should Be 'none'
    }
}

Describe 'Upgrade: counts pages, not steps' {
    $w = New-SyntheticVault
    # One link page needs both steps: wrong section and a weak "Link it" link.
    $why = 'Linked by you (mentioned in the text)'
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://fernbrook.service-now.com/kb?id=1' -Links ('[{"t":"p1","s":1,"w":"' + $why + '"}]')
    $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
    It 'plans two steps but reports one page' {
        @(Get-UpgradePlan -Model $w.open.model).Count | Should Be 2
        $r = Invoke-VaultUpgrade -Store $w.store
        $r.planned | Should Be 1
        (Format-UpgradeStatus $r).detail | Should Match '^1 page\(s\) do not follow'
    }
    It 'says "N of M pages" from the pages really changed on a partial run, never planned minus failed' {
        # 3 planned: 1 changed, 1 failed, 1 needed nothing after all (or was not reached).
        (Format-UpgradeStatus @{ status = 'partial'; planned = 3; changed = 1; moved = 1; raised = 1; failed = 1; reason = '' }).detail | Should Be '1 of 3 page(s) brought in line; 1 could not be changed'
        (Format-UpgradeStatus @{ status = 'partial'; planned = 3; changed = 0; moved = 0; raised = 0; failed = 0; reason = 'OneNote did not answer' }).detail | Should Be '0 of 3 page(s) brought in line; the upgrade stopped early (OneNote did not answer)'
    }
}

Describe 'Upgrade: a partial run reports what really happened (code review 2026-11-15)' {
    $w = New-SyntheticVault
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://fernbrook.service-now.com/kb?id=1'
    $null = Add-OldLinkPage $w 'p10' 'Internal vacancies' 'https://fernbrook.service-now.com/vacancies' -Links '[{"t":"p1","s":2,"w":"explains"}]'
    $null = Add-OldLinkPage $w 'p11' 'Change calendar' 'https://fernbrook.service-now.com/changes'
    $real = New-VaultStore -Adapter $w.a -Vault $w.open.vault -Model $w.open.model -GetLease { $w.box.lease }.GetNewClosure()
    # Two pages cannot be moved; then the step after the moves (the "Linked from" lists) stops the run.
    $store = @{} + $real
    $move = $real.MovePage
    $store.MovePage = { param([string]$Id, [string]$Bucket, [string]$Type) if ($Id -ne 'p10') { throw 'OneNote refused the move' }; & $move $Id $Bucket $Type }.GetNewClosure()
    $store.GetIndex = { throw 'OneNote did not answer' }
    $r = Invoke-VaultUpgrade -Store $store
    It 'counts the page that moved and both that failed, although a later step stopped the run' {
        $r.status | Should Be 'partial'
        $r.planned | Should Be 3
        $r.moved | Should Be 1
        $r.changed | Should Be 1
        $r.failed | Should Be 2
        $r.reason | Should Be 'OneNote did not answer'
        $w.open.model.pages['p10'].section | Should Be 'Internal links'
        $w.open.model.pages['p7'].section | Should Be 'Web links'
    }
    It 'says so in the status line' {
        $line = Format-UpgradeStatus $r
        $line.status | Should Be 'WARN'
        $line.detail | Should Be '1 of 3 page(s) brought in line; 2 could not be changed; the upgrade stopped early (OneNote did not answer)'
    }
    It 'brings the others in line at the next start' {
        $again = Invoke-VaultUpgrade -Store $real
        "$($again.status):$($again.planned):$($again.changed):$($again.failed)" | Should Be 'done:2:2:0'
    }
}

Describe 'Upgrade: personal OneDrive links filed under Web links before 2026-11-15 move to Internal links' {
    $w = New-SyntheticVault
    # Old shape: a dropped file's link page (d.docs.live.net) and a shared onedrive.live.com link,
    # both filed as link-web in Web links; a public page next to them stays.
    $one = Add-OldLinkPage $w 'p7' 'Budget review' 'https://d.docs.live.net/0123456789abcdef/Documents/Budget%20review.docx'
    $null = Add-OldLinkPage $w 'p8' 'Holiday list' 'https://onedrive.live.com/edit?id=ABC&cid=0123456789abcdef'
    $null = Add-OldLinkPage $w 'p9' 'Public handbook' 'https://www.example.org/handbook'
    It 'files a new personal OneDrive address as internal, as the Sources view names it' {
        foreach ($u in 'https://d.docs.live.net/0123456789abcdef/a.docx', 'https://onedrive.live.com/edit?id=ABC') {
            Get-LinkBucket -Url $u | Should Be 'Internal links'
            (Get-LinkSource -Url $u).id | Should Be 'onedrive'
        }
        Get-LinkBucket -Url 'https://live.com/' | Should Be 'Web links'
        Get-LinkBucket -Url 'https://docs.live.net.example.org/a' | Should Be 'Web links'
    }
    It 'plans the old pages for a move, and only those' {
        (@(Get-UpgradePlan -Model $w.open.model | ForEach-Object { "$($_.step):$($_.id):$($_.from)>$($_.to):$($_.type)" } | Sort-Object) -join ',') | Should Be 'link-bucket:p7:Web links>Internal links:link-internal,link-bucket:p8:Web links>Internal links:link-internal'
    }
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'moves them at the next start and finds nothing to do after it' {
        "$($r.status):$($r.moved)" | Should Be 'done:2'
        $rec = $w.open.model.pages['p7']
        "$($rec.section):$($rec.type)" | Should Be 'Internal links:link-internal'
        $w.f.Nodes.ContainsKey($one) | Should Be $false
        $w.open.model.pages['p9'].section | Should Be 'Web links'
        (Invoke-VaultUpgrade -Store $w.store).status | Should Be 'none'
    }
}

Describe 'Upgrade: a read-only session only reports' {
    $w = New-SyntheticVault
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://fernbrook.service-now.com/kb?id=1'
    $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
    It 'writes nothing and says why' {
        $before = $w.f.Writes.Count
        $r = Invoke-VaultUpgrade -Store $w.store
        $r.status | Should Be 'skipped'
        $r.planned | Should Be 1
        (Format-UpgradeStatus $r).status | Should Be 'WARN'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'The write guard on moves' {
    It 'refuses a move out of or into another notebook' {
        $w = New-SyntheticVault
        $sid = $w.v.sectionIds['Web links']
        { $w.a.MovePage($w.tomato, $w.f.Nodes[$w.tomato].parent, $sid) } | Should Throw 'Write refused'
    }
}

Describe 'Upgrade body-links: links in the text to a page archived before moves re-pointed them (2026-11-16)' {
    # Old-shaped data: a page links to p1 in its Meta and its body, then p1 was archived by a version
    # that did not re-point the link, so the body still holds p1's old address, which no page has.
    $w = New-SyntheticVault
    $dead = 'onenote:https://example.invalid/docs/Notes.one#Zero-trust%20networking&section-id={11111111-1111-1111-1111-111111111111}&page-id={DEADDEAD-0000-4000-8000-0000000000DE}&end'
    $id = [string](& $w.store.NewId)
    $line = @{ parts = @(@{ text = 'We follow '; href = '' }, @{ text = 'Zero-trust networking'; href = $dead }, @{ text = ' and '; href = '' }, @{ text = 'a retired wiki'; href = $dead }, @{ text = '.'; href = '' }) }
    $page = @{ id = $id; type = 'note'; bucket = 'Notes'; title = 'Linker'; summary = 'Links to p1.'; topics = @(); aliases = @(); links = @(@{ target = 'p1'; strength = 3; why = 'core' }); status = ''
        outlines = @(@{ role = 'body'; lines = @($line) }, @{ role = 'notes'; lines = @(@{ parts = @(@{ text = 'Zero-trust networking'; href = $dead }) }) }) }
    $cp = & $w.store.CreatePage -Page $page
    $page.pageId = [string]$cp.pageId; $page.link = [string]$cp.link; $page.section = [string]$cp.section
    $null = & $w.store.IndexAddPage -Page $page
    $null = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
    $notesBefore = Get-FakeOutlineXml $w.f $page.pageId 'notes'

    It 'plans a check of each page that links to the archived page (p3 links to it in its Meta only)' {
        (@(Get-UpgradePlan -Model $w.open.model | Where-Object { $_.step -eq 'body-links' } | ForEach-Object { "$($_.id)>$($_.to)" } | Sort-Object) -join ',') | Should Be "p3>p1,$id>p1"
    }
    $r = Invoke-VaultUpgrade -Store $w.store
    It 'points the link whose text is the archived page''s title at it, and says so' {
        $r.status | Should Be 'done'
        $r.relinked | Should Be 1
        $body = Get-FakeOutlineXml $w.f $page.pageId 'body'
        $p1link = ([string]$w.open.model.pages['p1'].link).Replace('&', '&amp;')
        $body | Should Match ([regex]::Escape("<a href=""$p1link"">Zero-trust networking</a>"))
        (Format-UpgradeStatus $r).detail | Should Be 'links in the text of 1 page(s) point at the archived pages again'
    }
    It 'leaves a dead link whose text names no page it links to, and "Your notes"' {
        Get-FakeOutlineXml $w.f $page.pageId 'body' | Should Match 'DEADDEAD[^"]*"[^>]*>a retired wiki</a>'
        Get-FakeOutlineXml $w.f $page.pageId 'notes' | Should Be $notesBefore
    }
    It 'changes nothing and says nothing at the next start' {
        $before = $w.f.Writes.Count
        $again = Invoke-VaultUpgrade -Store $w.store
        $again.relinked | Should Be 0
        Format-UpgradeStatus $again | Should Be $null
        $w.f.Writes.Count | Should Be $before
    }
    It 'stays quiet in a read-only session that only had pages to check' {
        $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        Format-UpgradeStatus (Invoke-VaultUpgrade -Store $w.store) | Should Be $null
    }
}
