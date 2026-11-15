# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Tags, set by hand only (2026-11-15): the one normal form (lib/PageMeta.psm1 ConvertTo-TagList,
# pinned by tests/fixtures/tags.json, which the interface's tests read too), and tagging through the
# real store against the in-memory OneNote: obsn.tags Meta, the properties outline, the index record
# and its compact entry, the graph model, the Markdown export, rename and remove. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest', 'GraphModel', 'MarkdownExport') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'FakeVault.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:Fixture = [IO.File]::ReadAllText((Join-Path $here 'fixtures\tags.json')) | ConvertFrom-Json

Describe 'ConvertTo-TagList gives exactly tests/fixtures/tags.json' {
    foreach ($c in @($script:Fixture.tags)) {
        $in = [string]$c.'in'
        $want = $c.out
        It "single tag $(ConvertTo-Json $in -Compress) -> $(if ($null -eq $want) { 'refused' } else { $want })" {
            $r = ConvertTo-TagList -Tags @($in)
            if ($null -eq $want) {
                $r.ok | Should Be $false
                $r.error | Should Not BeNullOrEmpty
                @($r.tags).Count | Should Be 0
            } else {
                $r.ok | Should Be $true
                @($r.tags).Count | Should Be 1
                $r.tags[0] | Should BeExactly $want
            }
        }
    }
    $n = 0
    foreach ($c in @($script:Fixture.lists)) {
        $n++
        $in = @($c.'in')
        $refused = $null -eq $c.out
        $want = @($c.out | Where-Object { $null -ne $_ })
        It "list $n ($($in.Count) in) -> $(if ($refused) { 'refused' } else { "$($want.Count) out" })" {
            $r = ConvertTo-TagList -Tags $in
            if ($refused) { $r.ok | Should Be $false; $r.error | Should Not BeNullOrEmpty }
            else { $r.ok | Should Be $true; (@($r.tags) -join '|') | Should BeExactly ($want -join '|') }
        }
    }
    It 'refuses a control character and something that is not text, with a plain sentence' {
        (ConvertTo-TagList -Tags @("a$([char]9)b")).ok | Should Be $false
        (ConvertTo-TagList -Tags @(5)).ok | Should Be $false
        (ConvertTo-TagList -Tags @('a:b')).error | Should Match '^A tag cannot hold'
        (ConvertTo-TagList -Tags @('')).error | Should Match '^A tag is 1 to 40 characters'
    }
}

Describe 'Tags in the page Meta and the index entry (pure)' {
    It 'writes obsn.tags as a JSON list, and as an empty value when the last tag goes' {
        (ConvertTo-ObsnMeta -Page @{ tags = @('a', 'b c') })['obsn.tags'] | Should Be '["a","b c"]'
        (ConvertTo-ObsnMeta -Page @{ tags = @('a') })['obsn.tags'] | Should Be '["a"]'
        (ConvertTo-ObsnMeta -Page @{ tags = @() })['obsn.tags'] | Should Be ''
        (ConvertTo-ObsnMeta -Page @{ title = 'x'; type = 'note' }).Contains('obsn.tags') | Should Be $false
    }
    It 'reads them back, and reads a page without the Meta as no tags' {
        (@((ConvertFrom-ObsnMeta -Meta @{ 'obsn.tags' = '["a","b c"]' }).tags) -join '|') | Should Be 'a|b c'
        @((ConvertFrom-ObsnMeta -Meta @{ 'obsn.tags' = '' }).tags).Count | Should Be 0
        @((ConvertFrom-ObsnMeta -Meta @{}).tags).Count | Should Be 0
    }
    It 'shows a tags line in the properties outline only when there are tags' {
        (Get-PropertiesLines @{ type = 'note'; tags = @('a', 'b c'); id = 'p1' }) -contains 'tags: a, b c' | Should Be $true
        @((Get-PropertiesLines @{ type = 'note'; tags = @(); id = 'p1' }) | Where-Object { $_ -like 'tags:*' }).Count | Should Be 0
    }
}

Describe 'Tagging pages through the real store (in-memory OneNote)' {
    $w = New-SyntheticVault
    $r = Set-PageTags -Store $w.store -Ids @('p1', 'p2') -Add @('Licensing', 'follow   up')
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $p3 = Find-FakePage $w.f 'VPN retirement plan'

    It 'answers the pages with their tags' {
        $r.status | Should Be 'tagged'
        $r.changed | Should Be 2
        (@($r.pages | ForEach-Object { "$($_.id)=$($_.tags -join ',')" }) -join ';') | Should Be 'p1=licensing,follow up;p2=licensing,follow up'
        @($r.warnings).Count | Should Be 0
    }
    It 'writes obsn.tags on the page and a tags line in its properties outline' {
        $p1.meta['obsn.tags'] | Should Be '["licensing","follow up"]'
        (Get-FakeOutlineXml $w.f $p1.id 'props') | Should Match 'tags: licensing, follow up'
    }
    It 'keeps the page''s other content: no outline but the properties is written' {
        @($p1.outlines | Where-Object { $_.xml -match 'obsn\.role' -and $_.xml -notmatch 'content="props"' -and $_.xml -match 'licensing' }).Count | Should Be 0
        @($p1.outlines | Where-Object { $_.xml -match 'Never trust the network' }).Count | Should Be 1
    }
    It 'leaves a page that was never tagged without the Meta and without the line' {
        $p3.meta.Contains('obsn.tags') | Should Be $false
        (Get-FakeOutlineXml $w.f $p3.id 'props') | Should Not Match 'tags:'
    }
    It 'mirrors the tags in the index record and its compact entry, which a fresh load reads' {
        (@($w.open.model.pages['p1'].tags) -join '|') | Should Be 'licensing|follow up'
        $fresh = Read-IndexModel -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -VaultId $w.open.vault.vaultId -RootId $w.open.vault.rootId
        (@($fresh.pages['p1'].tags) -join '|') | Should Be 'licensing|follow up'
        @($fresh.pages['p3'].tags).Count | Should Be 0
    }
    It 'reads them from the page''s own Meta on a rebuild scan' {
        $tree = ConvertFrom-ObsnHierarchy -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        $scan = ConvertFrom-VaultScan -Tree $tree -VaultId $w.open.vault.vaultId
        (@($scan.pages['p2'].tags) -join '|') | Should Be 'licensing|follow up'
    }
    It 'keeps every write inside the vault' {
        $scope = Get-VaultScopeIds -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        @($w.f.Writes | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $_ -match '^\{' -and -not $scope.Contains($_) }).Count | Should Be 0
    }

    It 'gives the graph every page''s tags as a list and the tags with their counts, sorted by name' {
        $null = Set-PageTags -Store $w.store -Ids @('p3') -Add @('archive me')
        $g = ConvertTo-GraphModel -Model $w.open.model -Source @{ kind = 'vault'; id = 'v'; name = 'n'; readOnly = $false }
        $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress
        $back = $json | ConvertFrom-Json
        (@($back.tags | ForEach-Object { "$($_.name):$($_.count)" }) -join ';') | Should Be 'archive me:1;follow up:2;licensing:2'
        (@(@($back.pages | Where-Object { $_.id -eq 'p1' })[0].tags) -join '|') | Should Be 'licensing|follow up'
        $json | Should Match '"tags":\["archive me"\]'            # one tag is still a list
        $null = Set-PageTags -Store $w.store -Ids @('p3') -Remove @('archive me')
        $json2 = ConvertTo-Json -InputObject (ConvertTo-GraphModel -Model $w.open.model -Source @{ kind = 'vault'; id = 'v'; name = 'n'; readOnly = $false }) -Depth 12 -Compress
        $json2 | Should Match '"id":"p3".*?"tags":\[\]'            # none is an empty list, not null
        $p3.meta['obsn.tags'] | Should Be ''
        (Get-FakeOutlineXml $w.f $p3.id 'props') | Should Not Match 'tags:'
    }
    It 'gives an empty tags list for a model without tags' {
        $w2 = New-SyntheticVault
        $j = ConvertTo-Json -InputObject (ConvertTo-GraphModel -Model $w2.open.model -Source @{ kind = 'vault'; id = 'v'; name = 'n'; readOnly = $false }) -Depth 12 -Compress
        $j | Should Match '"tags":\[\]\}$'
    }
    It 'puts the tags in the Markdown export''s front matter' {
        $ad = $w.a
        $x = New-MarkdownExport -Model $w.open.model -ReadPage { param($id) $ad.GetPageContent($id) }.GetNewClosure() -SourceName 'v' -Scope page -Key 'p1'
        $text = [Text.Encoding]::UTF8.GetString([byte[]]$x.bytes)
        $text | Should Match "tags:\n  - ""licensing""\n  - ""follow up"""
        $y = New-MarkdownExport -Model $w.open.model -ReadPage { param($id) $ad.GetPageContent($id) }.GetNewClosure() -SourceName 'v' -Scope page -Key 'p3'
        [Text.Encoding]::UTF8.GetString([byte[]]$y.bytes) | Should Not Match '(?m)^tags:'
    }
}

Describe 'Tagging: what is refused writes nothing' {
    $w = New-SyntheticVault
    It 'refuses an invalid tag, no pages, too many pages and nothing to do' {
        $before = $w.f.Writes.Count
        (Set-PageTags -Store $w.store -Ids @('p1') -Add @('a:b')).status | Should Be 'invalid'
        (Set-PageTags -Store $w.store -Ids @('p1') -Remove @('a,b')).status | Should Be 'invalid'
        (Set-PageTags -Store $w.store -Ids @() -Add @('a')).status | Should Be 'invalid'
        (Set-PageTags -Store $w.store -Ids @(1..201 | ForEach-Object { "p$_" }) -Add @('a')).message | Should Be 'At most 200 pages at a time.'
        (Set-PageTags -Store $w.store -Ids @('p1')).message | Should Be 'Nothing to add or remove.'
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses the whole request when one id is not a page of the vault' {
        $before = $w.f.Writes.Count
        $r = Set-PageTags -Store $w.store -Ids @('p1', 'p99') -Add @('a')
        $r.status | Should Be 'not-found'
        $w.f.Writes.Count | Should Be $before
        (Find-FakePage $w.f 'Zero-trust networking').meta.Contains('obsn.tags') | Should Be $false
    }
    It 'refuses a 13th tag on a page and writes none of the pages' {
        (Set-PageTags -Store $w.store -Ids @('p1') -Add @(1..12 | ForEach-Object { "t$_" })).status | Should Be 'tagged'
        $before = $w.f.Writes.Count
        $r = Set-PageTags -Store $w.store -Ids @('p2', 'p1') -Add @('one more')
        $r.status | Should Be 'invalid'
        $r.message | Should Match 'at most 12 tags'
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses without the writer lease' {
        $before = $w.f.Writes.Count
        $w.box.lease = @{ mode = 'readonly'; expires = [datetime]::UtcNow.AddMinutes(5) }
        (Set-PageTags -Store $w.store -Ids @('p2') -Add @('a')).status | Should Be 'refused'
        (Rename-Tag -Store $w.store -From 't1' -To 't2').status | Should Be 'refused'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'Tagging: the page wins over its index record' {
    $w = New-SyntheticVault
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    It 'adds to the tags on the page when the index record does not know them' {
        $p1.meta['obsn.tags'] = '["by hand"]'      # on the page, not in the index record
        $r = Set-PageTags -Store $w.store -Ids @('p1') -Add @('second')
        $r.status | Should Be 'tagged'
        $p1.meta['obsn.tags'] | Should Be '["by hand","second"]'
        (@($w.open.model.pages['p1'].tags) -join '|') | Should Be 'by hand|second'
    }
    It 'counts nothing and writes no page when the page has the tag already' {
        $n = @($w.f.Writes | Where-Object { $_ -eq "UpdatePageContent $($p1.id)" }).Count
        $r = Set-PageTags -Store $w.store -Ids @('p1') -Add @('SECOND')
        $r.changed | Should Be 0
        @($w.f.Writes | Where-Object { $_ -eq "UpdatePageContent $($p1.id)" }).Count | Should Be $n
    }
}

Describe 'Edit, Update and other writes keep the tags' {
    $w = New-SyntheticVault
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    It 'sets tags through Edit, in normal form' {
        $r = Edit-Page -Store $w.store -Id 'p1' -Changes @{ tags = @(' Key Ref ', 'key ref', 'later') }
        $r.status | Should Be 'edited'
        (@($r.changed) -join ',') | Should Be 'tags'
        $p1.meta['obsn.tags'] | Should Be '["key ref","later"]'
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ tags = @('key ref', 'later') }).status | Should Be 'unchanged'
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ tags = @('no:colon') }).status | Should Be 'invalid'
    }
    It 'keeps them when another field is edited (Meta, properties line and index record)' {
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ aliases = @('ZTN', 'Zero trust'); summary = 'Changed.' }).status | Should Be 'edited'
        $p1.meta['obsn.tags'] | Should Be '["key ref","later"]'
        (Get-FakeOutlineXml $w.f $p1.id 'props') | Should Match 'tags: key ref, later'
        (@($w.open.model.pages['p1'].tags) -join '|') | Should Be 'key ref|later'
    }
    It 'keeps them when a store update carries other Meta only (what Add and link Update send)' {
        $null = & $w.store.UpdatePage -PageId $p1.id -Meta @{ topics = @('Security'); links = @() } -Outlines @() -Title $null
        $null = & $w.store.IndexUpdatePage -Page @{ id = 'p1'; topics = @('Security'); links = @() }
        $p1.meta['obsn.tags'] | Should Be '["key ref","later"]'
        (Get-FakeOutlineXml $w.f $p1.id 'props') | Should Match 'tags: key ref, later'
        (@($w.open.model.pages['p1'].tags) -join '|') | Should Be 'key ref|later'
    }
    It 'clears them through Edit with an empty list' {
        (Edit-Page -Store $w.store -Id 'p1' -Changes @{ tags = @() }).status | Should Be 'edited'
        $p1.meta['obsn.tags'] | Should Be ''
        (Get-FakeOutlineXml $w.f $p1.id 'props') | Should Not Match 'tags:'
        @($w.open.model.pages['p1'].tags).Count | Should Be 0
    }
}

Describe 'Rename-Tag across the vault' {
    $w = New-SyntheticVault
    $null = Set-PageTags -Store $w.store -Ids @('p1') -Add @('alpha', 'beta')
    $null = Set-PageTags -Store $w.store -Ids @('p2') -Add @('beta')
    $null = Set-PageTags -Store $w.store -Ids @('p3') -Add @('alpha', 'gamma')
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $p2 = Find-FakePage $w.f 'Partner portal: access review notes'
    $p3 = Find-FakePage $w.f 'VPN retirement plan'
    It 'gives every page that has the tag the new one, without a duplicate, in the same place' {
        $r = Rename-Tag -Store $w.store -From ' Alpha ' -To 'Beta'
        $r.status | Should Be 'renamed'
        $r.changed | Should Be 2
        $p1.meta['obsn.tags'] | Should Be '["beta"]'
        $p2.meta['obsn.tags'] | Should Be '["beta"]'
        $p3.meta['obsn.tags'] | Should Be '["beta","gamma"]'
        (@($w.open.model.pages['p3'].tags) -join '|') | Should Be 'beta|gamma'
    }
    It 'changes nothing for a tag no page has, or the same name' {
        $before = $w.f.Writes.Count
        (Rename-Tag -Store $w.store -From 'nobody' -To 'x').changed | Should Be 0
        (Rename-Tag -Store $w.store -From 'beta' -To ' BETA ').changed | Should Be 0
        $w.f.Writes.Count | Should Be $before
    }
    It 'refuses an invalid name' {
        (Rename-Tag -Store $w.store -From '' -To 'x').status | Should Be 'invalid'
        (Rename-Tag -Store $w.store -From 'beta' -To 'a,b').status | Should Be 'invalid'
    }
    It 'removes the tag from every page when the new name is empty' {
        $r = Rename-Tag -Store $w.store -From 'beta' -To ''
        $r.changed | Should Be 3
        $p1.meta['obsn.tags'] | Should Be ''
        $p3.meta['obsn.tags'] | Should Be '["gamma"]'
        @($w.open.model.pages['p2'].tags).Count | Should Be 0
    }
}

Describe 'Tags with the in-memory test store (no batch index write)' {
    It 'falls back to one index update per page' {
        $v = New-FakeVault
        $r = Set-PageTags -Store $v.store -Ids @('p1', 'p2') -Add @('x')
        $r.status | Should Be 'tagged'
        @($v.st.updates | Where-Object { $_.meta.ContainsKey('tags') }).Count | Should Be 2
        @($v.st.indexOps | Where-Object { $_.op -eq 'update' -and $_.page.ContainsKey('tags') }).Count | Should Be 2
    }
}
