# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# "Link it" (lib/Ingest.psm1 Add-PageLink) through the real store, the write guard and the lease
# against the in-memory OneNote: the link in the from page's Meta and index record, the to page's
# "Linked from" outline, the user's own outlines untouched, already linked, refused without the lease.
# Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function Get-UserOutlines($F, [string]$PageId) {
    # The outlines without an obsn.role: the person's own content.
    , @($F.Nodes[$PageId].outlines | Where-Object { $_.xml -notmatch 'obsn\.role' } | ForEach-Object { $_.xml })
}

Describe 'Link it: p2 mentions p1, the person links them' {
    $w = New-SyntheticVault
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    $userP1 = (Get-UserOutlines $w.f $p1.id) -join '|'
    $userP2 = (Get-UserOutlines $w.f $p2.id) -join '|'
    $w0 = $w.f.Writes.Count
    $r = Add-PageLink -Store $w.store -From 'p2' -To 'p1'
    $newWrites = @($w.f.Writes | Select-Object -Skip $w0)

    It 'links them' {
        $r.status | Should Be 'linked'
        $r.backlinks | Should Be 1
        @($r.warnings).Count | Should Be 0
    }
    It 'writes the link into the from page''s own Meta with strength 1 and the why' {
        $p2.meta['obsn.links'] | Should Be '[{"t":"p1","s":1,"w":"Linked by you (mentioned in the text)"}]'
    }
    It 'updates the from page''s index record, so the index edge exists' {
        $rec = $w.open.model.pages['p2']
        @($rec.links | Where-Object { $_.target -eq 'p1' }).Count | Should Be 1
        $ix = & $w.store.GetIndex
        @($ix.edges | Where-Object { $_.from -eq 'p2' -and $_.to -eq 'p1' }).Count | Should Be 1
    }
    It 'rewrites the to page''s "Linked from" outline with both pages that link to it' {
        $bl = Get-FakeOutlineXml $w.f $p1.id 'backlinks'
        $bl | Should Match 'Linked from'
        $bl | Should Match 'Partner portal: access review notes'
        $bl | Should Match 'VPN retirement plan'
    }
    It 'regenerates the Index pages of the from page''s topic' {
        $hub = @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta.Contains('obsn.indexKey') -and $_.meta['obsn.indexKey'] -eq 'topic:Projects/Partner portal' })
        $hub.Count | Should Be 1
        $newWrites -contains ('UpdatePageContent ' + $hub[0].id) | Should Be $true
        @($newWrites | Where-Object { $_ -like 'CreateNewPage*' -or $_ -like 'DeleteHierarchy*' }).Count | Should Be 0
    }
    It 'leaves the person''s own outlines and the pages outside the vault untouched' {
        ((Get-UserOutlines $w.f $p1.id) -join '|') | Should Be $userP1
        ((Get-UserOutlines $w.f $p2.id) -join '|') | Should Be $userP2
        $userP1 | Should Match 'Never trust the network'
        $w.f.Nodes[$w.tomato].outlines.Count | Should Be 1
        Get-FakeOutlineXml $w.f $p2.id 'notes' | Should Be ''
    }
    It 'says already-linked for the same pair, in either direction, and writes nothing' {
        $before = $w.f.Writes.Count
        (Add-PageLink -Store $w.store -From 'p2' -To 'p1').status | Should Be 'already-linked'
        (Add-PageLink -Store $w.store -From 'p1' -To 'p2').status | Should Be 'already-linked'
        (Add-PageLink -Store $w.store -From 'p3' -To 'p1').status | Should Be 'already-linked'
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses unknown ids and the same id, and writes nothing' {
        $before = $w.f.Writes.Count
        (Add-PageLink -Store $w.store -From 'p2' -To 'p99').status | Should Be 'not-found'
        (Add-PageLink -Store $w.store -From 'p2' -To 'p2').status | Should Be 'invalid'
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses without the writer lease and writes nothing' {
        $before = $w.f.Writes.Count
        $w.box.lease = @{ mode = 'readonly'; sessionId = 'other'; holder = 'other'; expires = (Get-Date).AddMinutes(1); statePageId = ''; indexSectionId = '' }
        $x = Add-PageLink -Store $w.store -From 'p3' -To 'p2'
        $x.status | Should Be 'refused'
        $x.message | Should Match 'Read only'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Link it keeps the links a page has' {
    $w = New-SyntheticVault
    $r = Add-PageLink -Store $w.store -From 'p3' -To 'p2'
    It 'adds the new link next to the existing one' {
        $r.status | Should Be 'linked'
        (Find-FakePage $w.f 'VPN retirement plan').meta['obsn.links'] | Should Be '[{"t":"p1","s":2,"w":"replaced by"},{"t":"p2","s":1,"w":"Linked by you (mentioned in the text)"}]'
    }
}
