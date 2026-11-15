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
    $snow = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://contoso.service-now.com/kb?id=1' -Links '[{"t":"p1","s":2,"w":"explains"}]'
    $null = Add-OldLinkPage $w 'p8' 'Public handbook' 'https://www.example.org/handbook'
    $null = Add-OldLinkPage $w 'p9' 'Old portal page' 'https://contoso.service-now.com/old' -Section 'Archive' -Status 'archived'
    $named = Add-OldLinkPage $w 'p10' 'Internal vacancies' 'https://contoso.example-hr.com/vacancies'
    # the store as the start makes it: the company name comes from the vault's own address
    $store = New-VaultStore -Adapter $w.a -Vault $w.open.vault -Model $w.open.model -GetLease { $w.box.lease }.GetNewClosure() -CompanyNames @('contoso')

    It 'plans only ObsidiNote''s live link pages in the wrong section' {
        $plan = @(Get-UpgradePlan -Model $w.open.model -CompanyNames @('contoso'))
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
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://contoso.service-now.com/kb?id=1' -Links ('[{"t":"p1","s":1,"w":"' + $why + '"}]')
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
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://contoso.service-now.com/kb?id=1'
    $null = Add-OldLinkPage $w 'p10' 'Internal vacancies' 'https://contoso.service-now.com/vacancies' -Links '[{"t":"p1","s":2,"w":"explains"}]'
    $null = Add-OldLinkPage $w 'p11' 'Change calendar' 'https://contoso.service-now.com/changes'
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
    $null = Add-OldLinkPage $w 'p7' 'Service desk article' 'https://contoso.service-now.com/kb?id=1'
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
