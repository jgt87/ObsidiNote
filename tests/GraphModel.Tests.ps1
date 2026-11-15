# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/GraphModel.psm1: the index model -> the knowledge graph's GraphModel (ui-src/src/graph/model.ts).
# Pure; a hand-made model plus one from the in-memory OneNote for a connected notebook.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'GraphModel') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')

function New-TestModel {
    $m = New-IndexModel -Kind 'vault' -VaultId 'v1'
    $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'Zero trust'; type = 'concept'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{A}'; link = 'onenote:#p1'; summary = 'Never trust.'; topics = @('Security/Networking'); links = @(@{ target = 'p2'; strength = 3; why = 'core' }, @{ target = 'p9'; strength = 2; why = 'gone' }); updated = '2026-11-01T00:00:00.000Z' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p2'; title = 'Proxy'; type = 'concept'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{B}'; link = 'https://not-onenote.example.invalid/'; topics = @('Security', 'Projects'); links = @(@{ target = 'p1'; strength = 9; why = 'back' }) }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p3'; title = 'Loose note'; type = 'note'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{C}'; status = 'archived' }
    $m
}

Describe 'ConvertTo-GraphModel' {
    $g = ConvertTo-GraphModel -Model (New-TestModel) -Source @{ kind = 'vault'; id = 'v1'; name = 'Synthetic'; readOnly = $false }
    It 'names the source' {
        $g.source.kind | Should Be 'vault'
        $g.source.name | Should Be 'Synthetic'
        $g.source.readOnly | Should Be $false
    }
    It 'makes one topic per path with its parent, display path and a page count that includes subtopics' {
        ($g.topics | ForEach-Object { "$($_.id)|$($_.parent)|$($_.pageCount)" }) -join ',' | Should Be 'Security||2,Security/Networking|Security|1,Projects||1'
        @($g.topics | Where-Object { $_.id -eq 'Security/Networking' })[0].path | Should Be 'Security / Networking'
        @($g.topics | Where-Object { $_.id -eq 'Security' })[0].subjects | Should Be 'Networking'
    }
    It 'draws a page in its first topic; a page without topics is Unfiled (no topic ids)' {
        (@($g.pages | Where-Object { $_.id -eq 'p2' })[0].topicIds -join ',') | Should Be 'Security,Projects'
        @(@($g.pages | Where-Object { $_.id -eq 'p3' })[0].topicIds).Count | Should Be 0
    }
    It 'keeps only links between pages of the model, strength clamped' {
        # p1 and p2 link each other: both edges stay (the page window lists both).
        ($g.edges | ForEach-Object { "$($_.from)>$($_.to):$($_.strength)" }) -join ',' | Should Be 'p1>p2:3,p2>p1:3'
    }
    It 'sends no link count, unlinked or hub flag: the interface derives them from the edges (weights.ts)' {
        $p1 = @($g.pages | Where-Object { $_.id -eq 'p1' })[0]
        foreach ($k in 'links', 'unlinked', 'isHub') { $p1.Contains($k) | Should Be $false }
    }
    It 'passes only onenote: links on, and marks archived pages' {
        @($g.pages | Where-Object { $_.id -eq 'p1' })[0].onenoteUrl | Should Be 'onenote:#p1'
        @($g.pages | Where-Object { $_.id -eq 'p2' })[0].onenoteUrl | Should Be ''
        @($g.pages | Where-Object { $_.id -eq 'p3' })[0].archived | Should Be $true
    }
    It 'passes aliases and a link page''s site on' {
        $m = New-TestModel
        $null = Add-IndexPage -Model $m -Page @{ id = 'p4'; title = 'Example site'; type = 'link-web'; bucket = 'Web links'; section = 'Web links'; oneNoteId = '{D}'; aliases = @('ES'); host = 'example.org'; url = 'https://example.org/a' }
        $null = Add-IndexPage -Model $m -Page @{ id = 'p5'; title = 'Odd'; type = 'link-web'; bucket = 'Web links'; section = 'Web links'; oneNoteId = '{E}'; url = 'javascript:alert(1)' }
        $g2 = ConvertTo-GraphModel -Model $m -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false }
        $p = @($g2.pages | Where-Object { $_.id -eq 'p4' })[0]
        ($p.aliases -join ',') | Should Be 'ES'
        $p.site | Should Be 'example.org'
        $p.url | Should Be 'https://example.org/a'
        @($g2.pages | Where-Object { $_.id -eq 'p5' })[0].url | Should Be ''
        $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress
        $json | Should Match '"aliases":\[\]'
    }
    It 'serialises lists as lists (one item, none) for the interface' {
        $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress
        $json | Should Match '"topicIds":\[\]'
        $json | Should Match '"topicIds":\["Security/Networking"\]'
    }
}

Describe 'Get-LinkSource: where a link page''s address lives (Sources view)' {
    $cases = @(
        @('https://contoso-my.sharepoint.com/personal/x/Documents/a.docx', 'onedrive', 'OneDrive'),
        @('https://contoso.sharepoint.com/sites/HR%20Team/SitePages/Leave.aspx', 'sharepoint/hr team', 'SharePoint: HR Team'),
        @('https://contoso.sharepoint.com/teams/IT/Shared%20Documents/x.pdf', 'sharepoint/it', 'SharePoint: IT'),
        @('https://contoso.sharepoint.com/SitePages/Home.aspx', 'sharepoint', 'SharePoint'),
        @('https://teams.microsoft.com/l/message/1', 'teams', 'Teams'),
        @('https://contoso.loop.cloud.microsoft/p/x', 'loop', 'Loop'),
        @('https://outlook.office.com/mail/', 'm365', 'Microsoft 365'),
        @('https://contoso.service-now.com/kb?id=1', 'service/servicenow', 'ServiceNow'),
        @('https://wd3.myworkday.com/contoso/d/home.htmld', 'service/workday', 'Workday'),
        @('https://docs.service-now.com/bundle/x', 'web/docs.service-now.com', 'docs.service-now.com'),
        @('https://www.example.org/handbook', 'web/example.org', 'example.org')
    )
    foreach ($c in $cases) {
        It "puts $($c[0]) in $($c[2])" {
            $s = Get-LinkSource -Url $c[0]
            $s.id | Should Be $c[1]
            $s.name | Should Be $c[2]
        }
    }
    It 'calls internal what the link rules file as internal (code review 2026-11-14)' {
        # internalHosts setting, the company's name on another host, a tenant host without a service name
        (Get-LinkSource -Url 'https://intranet.contoso.local/a' -InternalHosts @('intranet.contoso.local')).id | Should Be 'internal/intranet.contoso.local'
        $c = Get-LinkSource -Url 'https://contoso.example-hr.com/vacancies' -CompanyNames @('contoso')
        "$($c.id):$($c.kind)" | Should Be 'internal/contoso.example-hr.com:service'
        (Get-LinkSource -Url 'https://contoso.example-hr.com/vacancies').kind | Should Be 'web'
        foreach ($u in 'https://intranet.contoso.local/a', 'https://contoso.example-hr.com/vacancies') {
            $bucket = Get-LinkBucket -Url $u -InternalHosts @('intranet.contoso.local') -CompanyNames @('contoso')
            $kind = (Get-LinkSource -Url $u -InternalHosts @('intranet.contoso.local') -CompanyNames @('contoso')).kind
            "$bucket=$kind" | Should Be 'Internal links=service'
        }
    }
    It 'gives nothing for an address that is not http(s)' {
        Get-LinkSource -Url 'onenote:#x' | Should Be $null
        Get-LinkSource -Url '' | Should Be $null
    }
}

Describe 'ConvertTo-GraphModel: sources' {
    $m = New-TestModel
    foreach ($i in 1..3) { $null = Add-IndexPage -Model $m -Page @{ id = "w$i"; title = "Example $i"; type = 'link-web'; bucket = 'Web links'; section = 'Web links'; oneNoteId = "{W$i}"; url = "https://www.example.org/p$i" } }
    $null = Add-IndexPage -Model $m -Page @{ id = 'x1'; title = 'Lone site'; type = 'link-web'; bucket = 'Web links'; section = 'Web links'; oneNoteId = '{X1}'; url = 'https://lone.example.net/a' }
    $null = Add-IndexPage -Model $m -Page @{ id = 's1'; title = 'Leave policy'; type = 'link-internal'; bucket = 'Internal links'; section = 'Internal links'; oneNoteId = '{S1}'; url = 'https://contoso.sharepoint.com/sites/HR/Leave.aspx' }
    $g = ConvertTo-GraphModel -Model $m -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false }
    $src = { param($id) @($g.pages | Where-Object { $_.id -eq $id })[0].sourceId }
    It 'gives every page a source: link pages by address, the rest ObsidiNote notes' {
        & $src 's1' | Should Be 'sharepoint/hr'
        & $src 'w2' | Should Be 'web/example.org'
        & $src 'p1' | Should Be 'obsidinote'
    }
    It 'puts a web site with fewer than 3 pages under Other web sites' {
        & $src 'x1' | Should Be 'web'
        @($g.sources | Where-Object { $_.id -eq 'web' })[0].name | Should Be 'Other web sites'
    }
    It 'lists each source once with its page count, Microsoft 365 first, notes last' {
        (@($g.sources | ForEach-Object { "$($_.id):$($_.pageCount)" }) -join ',') | Should Be 'sharepoint/hr:1,web/example.org:3,web:1,obsidinote:3'
    }
    It 'groups internal sites by the vault''s link rules, small ones as Other company sites' {
        $null = Add-IndexPage -Model $m -Page @{ id = 'c1'; title = 'Vacancies'; type = 'link-internal'; bucket = 'Internal links'; section = 'Internal links'; oneNoteId = '{C1}'; url = 'https://contoso.example-hr.com/vacancies' }
        $g2 = ConvertTo-GraphModel -Model $m -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false } -LinkRules @{ CompanyNames = @('contoso') }
        $c1 = @($g2.pages | Where-Object { $_.id -eq 'c1' })[0].sourceId
        $c1 | Should Be 'internal'
        $s = @($g2.sources | Where-Object { $_.id -eq 'internal' })[0]
        # Its own kind (not 'service'): a rest group, listed after the company services.
        "$($s.id):$($s.name):$($s.kind)" | Should Be 'internal:Other company sites:other-internal'
        (@($g2.sources | ForEach-Object { $_.kind }) -join ',') | Should Be 'm365,other-internal,web,other,notes'
    }
}

Describe 'ConvertTo-GraphModel: section, bucket and kind per page (tests/fixtures/graph-pages.json)' {
    # The fixture is what the server really sends: the interface tests read the same file.
    $fx = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $here 'fixtures\graph-pages.json')))
    $want = @($fx.pages)
    function Add-FixtureSection($F, [string]$RootId, [string]$Full) {
        $parts = $Full.Split('/')
        $parent = $RootId
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            $g = @($F.Nodes[$parent].children | Where-Object { $F.Nodes[$_].kind -eq 'SectionGroup' -and $F.Nodes[$_].name -eq $parts[$i] }) | Select-Object -First 1
            $parent = if ($g) { $g } else { $F.AddGroup($parent, $parts[$i]) }
        }
        $F.AddSection($parent, $parts[-1])
    }
    $f = New-FakeOneNote
    $vault = $f.AddNotebook('Fixture vault')
    foreach ($p in @($want | Where-Object { $_.source -eq 'vault' })) {
        $meta = @{ 'obsn.id' = $p.id; 'obsn.type' = $p.kind }
        if (@($p.tags).Count) { $meta['obsn.tags'] = (ConvertTo-Json -InputObject @($p.tags) -Compress) }
        if ($p.PSObject.Properties['summarizedAt']) { $meta['obsn.summarizedAt'] = $p.summarizedAt }
        $null = $f.AddPage((Add-FixtureSection $f $vault $p.section), "Page $($p.id)", $meta, 1, '')
    }
    $other = $f.AddNotebook('Fixture notebook')
    foreach ($p in @($want | Where-Object { $_.source -eq 'notebook' })) { $null = $f.AddPage((Add-FixtureSection $f $other $p.section), "Page $($p.id)", @{}, 1, '') }
    $gv = ConvertTo-GraphModel -Model (Read-VaultScan -Adapter $f -RootId $vault -VaultId 'v1') -Source @{ kind = 'vault'; id = 'v1'; name = 'Fixture vault'; readOnly = $false }
    $gn = ConvertTo-GraphModel -Model (Get-NotebookModel -Adapter $f -NotebookId $other -NoLinks -Vaults @()) -Source @{ kind = 'notebook'; id = $other; name = 'Fixture notebook'; readOnly = $true }
    It 'covers the cases the interface relies on' {
        foreach ($s in 'Notes', 'Notes 2', 'Journal/2026', 'Journal/2025', 'Web links', 'Archive/Notes', 'Group/Section', '00 Admin') { (@($want | ForEach-Object { $_.section }) -contains $s) | Should Be $true }
        @($gv.pages).Count | Should Be @($want | Where-Object { $_.source -eq 'vault' }).Count
        @($gn.pages).Count | Should Be @($want | Where-Object { $_.source -eq 'notebook' }).Count
    }
    foreach ($p in $want) {
        It "sends $($p.source) section '$($p.section)' as bucket '$($p.bucket)', kind '$($p.kind)'" {
            # A vault page is found by its id; a notebook page (its id is OneNote's) by its section.
            $got = if ($p.source -eq 'vault') { @($gv.pages | Where-Object { $_.id -eq $p.id })[0] } else { @($gn.pages | Where-Object { $_.section -eq $p.section })[0] }
            $got | Should Not BeNullOrEmpty
            "$($got.section)|$($got.bucket)|$($got.kind)" | Should Be "$($p.section)|$($p.bucket)|$($p.kind)"
            # tags: as JSON, so a list of one and an empty list are checked as lists.
            (ConvertTo-Json -InputObject $got.tags -Compress) | Should Be (ConvertTo-Json -InputObject @($p.tags) -Compress)
            $sa = if ($p.PSObject.Properties['summarizedAt']) { $p.summarizedAt } else { '' }
            $got.summarizedAt | Should Be $sa
        }
    }
    It 'sends the tags of the shown source with their page counts, sorted by name, as a list' {
        $jv = ConvertTo-Json -InputObject $gv -Depth 12 -Compress
        $jn = ConvertTo-Json -InputObject $gn -Depth 12 -Compress
        (@(($jv | ConvertFrom-Json).tags | ForEach-Object { "$($_.name):$($_.count)" }) -join ';') | Should Be (@($fx.vaultTags | ForEach-Object { "$($_.name):$($_.count)" }) -join ';')
        @($fx.notebookTags).Count | Should Be 0
        $jn | Should Match '"tags":\[\]\}$'
        $jv | Should Match '"tags":\[\{"name":"follow up","count":1\},'
    }
    It 'says why a read-only source cannot be changed (readOnlyReason)' {
        $gv.source.readOnlyReason | Should Be ''
        $gn.source.readOnlyReason | Should Be 'notebook'
        $m0 = New-IndexModel -Kind 'vault' -VaultId 'v1'
        (ConvertTo-GraphModel -Model $m0 -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $true; readOnlyReason = 'lease' }).source.readOnlyReason | Should Be 'lease'
        (ConvertTo-GraphModel -Model $m0 -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $true }).source.readOnlyReason | Should Be 'not-active'
        (ConvertTo-GraphModel -Model $m0 -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false; readOnlyReason = 'lease' }).source.readOnlyReason | Should Be ''
    }
    It 'sends an empty section when the model has none' {
        $m = New-IndexModel -Kind 'vault' -VaultId 'v1'
        $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'No section'; oneNoteId = '{A}' }
        $g0 = ConvertTo-GraphModel -Model $m -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false }
        $g0.pages[0].section | Should Be ''
        (ConvertTo-Json -InputObject $g0 -Depth 12 -Compress) | Should Match '"section":""'
    }
}

Describe 'A connected notebook, read only' {
    $f = New-FakeOneNote
    $nb = $f.AddNotebook('Household')
    $s = $f.AddSection($nb, 'Garden')
    $a = $f.AddPage($s, 'Tomatoes', @{}, 1, '')
    $b = $f.AddPage($s, 'Watering', @{}, 2, '')
    $link = $f.GetHyperlinkToObject($b)
    $f.Nodes[$a].outlines.Add(@{ objectId = '{O}'; role = ''; xml = '<one:Outline objectID="{O}"><one:OEChildren><one:OE><one:T><![CDATA[<a href="' + $link + '">watering</a>]]></one:T></one:OE></one:OEChildren></one:Outline>' }) | Out-Null
    $m = Get-NotebookModel -Adapter $f -NotebookId $nb
    $null = Get-NotebookLinks -Adapter $f -Model $m
    $g = ConvertTo-GraphModel -Model $m -Source @{ kind = 'notebook'; id = $nb; name = 'Household'; readOnly = $true }
    It 'shows its sections as topic areas, its pages read only, and its onenote: links as edges' {
        $g.source.readOnly | Should Be $true
        ($g.topics | ForEach-Object { $_.id }) -join ',' | Should Be 'Garden'
        @($g.pages | Where-Object { -not $_.readOnly }).Count | Should Be 0
        @($g.edges).Count | Should Be 1
    }
}
