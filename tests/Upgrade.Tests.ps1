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
