# Pester 3.4. Page data as <one:Meta> and owned outlines: ids, encoding, XML round trips, and the
# rule that only outlines tagged obsn.role are rewritten. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'lib\OneNote.psm1') -Force
Import-Module (Join-Path $root 'lib\PageMeta.psm1') -Force
. (Join-Path $here 'FakeOneNote.ps1')

Describe 'Id scheme' {
    It 'is p + base36 of the counter' {
        New-ObsnId 1 | Should Be 'p1'
        New-ObsnId 35 | Should Be 'pz'
        New-ObsnId 36 | Should Be 'p10'
        New-ObsnId 1296 | Should Be 'p100'
        Get-ObsnIdNumber 'p10' | Should Be 36
        ConvertFrom-Base36 (ConvertTo-Base36 123456789) | Should Be 123456789
    }
    It 'recognises only well-formed ids' {
        Test-ObsnId 'p1a' | Should Be $true
        Test-ObsnId 'P1' | Should Be $false
        Test-ObsnId 'p' | Should Be $false
        Test-ObsnId 'p01' | Should Be $false
        Test-ObsnId 'x12' | Should Be $false
        Test-ObsnId 'p0001' | Should Be $false
    }
}

Describe 'Meta values' {
    It 'round-trips a page record through Meta' {
        $page = @{ id = 'p7'; type = 'link-web'; topics = @('Gardening / Tides ', 'Coast'); aliases = @('TG'); summary = 'A note on "tidal" gardens & <salt>.'
            links = @(@{ target = 'p2'; strength = 5; why = 'same coast' }, @{ target = 'p3'; strength = 0; why = '' }); status = 'linked'; url = 'https://example.org/a'; host = 'example.org'; kind = 'article'; summarizedAt = '2026-01-02'; archivedFrom = '' }
        $m = ConvertTo-ObsnMeta $page
        $m['obsn.topics'] | Should Be '["Gardening/Tides","Coast"]'
        $back = ConvertFrom-ObsnMeta -Meta $m
        $back.id | Should Be 'p7'
        $back.topics -join '|' | Should Be 'Gardening/Tides|Coast'
        $back.aliases -join '|' | Should Be 'TG'
        $back.summary | Should Be $page.summary
        $back.links.Count | Should Be 2
        $back.links[0].strength | Should Be 3
        $back.links[1].strength | Should Be 1
        $back.links[0].why | Should Be 'same coast'
    }
    It 'keeps a single topic as a list' {
        (ConvertFrom-ObsnMeta -Meta (ConvertTo-ObsnMeta @{ topics = @('Only') })).topics.Count | Should Be 1
        (ConvertFrom-ObsnMeta -Meta @{}).topics.Count | Should Be 0
        (ConvertFrom-ObsnMeta -Meta @{ 'obsn.links' = 'not json' }).links.Count | Should Be 0
    }
    It 'splits a long value over numbered Meta tags and joins it back' {
        $v = 'abcdefghij' * 7
        $parts = Split-ObsnMetaValue -Name 'obsn.entries' -Value $v -Max 30
        $parts['obsn.entries.n'] | Should Be '3'
        $parts['obsn.entries.1'].Length | Should Be 30
        Join-ObsnMetaValue -Meta ([hashtable]$parts) -Name 'obsn.entries' | Should Be $v
        $short = Split-ObsnMetaValue -Name 'obsn.entries' -Value 'x' -Max 30
        $short['obsn.entries.n'] | Should Be '0'
        Join-ObsnMetaValue -Meta ([hashtable]$short) -Name 'obsn.entries' | Should Be 'x'
    }
    It 'normalizes topic paths' {
        ConvertTo-TopicPath ' Security /  Networking/ Zero   trust ' | Should Be 'Security/Networking/Zero trust'
        Format-TopicPath 'A/B' | Should Be 'A / B'
    }
}

Describe 'Page XML' {
    It 'builds well-formed XML with Meta before Title and encodes text safely' {
        $x = New-ObsnPageXml -PageId '{P-1}' -Meta ([ordered]@{ 'obsn.summary' = 'a "q" & <b> ]]>' }) -Title 'Tom & Jerry <3' -Outlines @(@{ role = 'props'; lines = @('x ]]> y', (New-OneLine -Html (New-OneLink -Href 'https://example.org/?a=1&b="2">' -Label 'L&L'))) })
        [xml]$d = $x
        $d.DocumentElement.ChildNodes[0].LocalName | Should Be 'Meta'
        $d.DocumentElement.ChildNodes[1].LocalName | Should Be 'Title'
        $p = ConvertFrom-ObsnPageXml $x
        $p.meta['obsn.summary'] | Should Be 'a "q" & <b> ]]>'
        $p.title | Should Be 'Tom & Jerry <3'
        $p.outlines[0].role | Should Be 'props'
        $x | Should Match 'href="https://example.org/\?a=1&amp;b=&quot;2&quot;&gt;"'
    }
    It 'nests and collapses lines' {
        $x = New-ObsnOutlineXml -Role 'index' -Lines @(New-OneLine -Text 'Archived (1)' -Collapsed -Children @('child'))
        $x | Should Match '<one:OE collapsed="true"><one:T><!\[CDATA\[Archived \(1\)\]\]></one:T><one:OEChildren>'
    }
    It 'writes readable properties and Linked from lines' {
        $l = Get-PropertiesLines @{ id = 'p3'; type = 'note'; topics = @('A/B'); aliases = @(); url = ''; status = '' }
        $l -join '|' | Should Be 'type: note|topics: A / B|id: p3'
        $b = Get-LinkedFromLines @(@{ title = 'Zeta'; link = 'onenote:z' }, @{ title = 'Alpha'; link = 'onenote:a' })
        $b.Count | Should Be 3
        $b[1].html | Should Match 'Alpha'
    }
}

Describe 'Writing a page through the adapter' {
    $f = New-FakeOneNote
    $nb = $f.AddNotebook('Synthetic'); $sec = $f.AddSection($nb, 'Notes')
    $pg = $f.AddPage($sec, 'Seed', @{}, 1, 'The user typed this.')
    It 'adds Meta and owned outlines and leaves the user''s outline alone' {
        Write-ObsnPage -Adapter $f -PageId $pg -Meta (ConvertTo-ObsnMeta @{ id = 'p1'; type = 'note' }) -Title 'Seed' -Outlines @(@{ role = 'props'; lines = @('type: note') }, @{ role = 'backlinks'; lines = @('Linked from:') })
        $p = Read-ObsnPage -Adapter $f -PageId $pg
        $p.meta['obsn.id'] | Should Be 'p1'
        @($p.outlines | ForEach-Object { $_.role }) -join ',' | Should Be ',props,backlinks'
    }
    It 'rewrites an owned outline in place (same objectID, no second copy)' {
        $before = Read-ObsnPage -Adapter $f -PageId $pg
        $bid = @($before.outlines | Where-Object { $_.role -eq 'backlinks' })[0].objectId
        Write-ObsnPage -Adapter $f -PageId $pg -Outlines @(@{ role = 'backlinks'; lines = @('Linked from:', 'Other page') })
        $after = Read-ObsnPage -Adapter $f -PageId $pg
        $after.outlines.Count | Should Be 3
        @($after.outlines | Where-Object { $_.role -eq 'backlinks' })[0].objectId | Should Be $bid
        $f.GetPageContent($pg) | Should Match 'The user typed this.'
        $f.GetPageContent($pg) | Should Match 'Other page'
        $after.meta['obsn.id'] | Should Be 'p1'
    }
}
