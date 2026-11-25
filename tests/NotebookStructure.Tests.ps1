# Pester 3.4. Notebook structure: type -> bucket, rollover, link buckets, URL normalization,
# hierarchy parsing. Synthetic data only (fictional names, made-up ids).
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'lib\NotebookStructure.psm1') -Force
. (Join-Path $root 'tests\AstParse.ps1')

$ns = 'xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"'
$fixture = @"
<?xml version="1.0"?>
<one:Notebook $ns name="Vault Test" nickname="Vault Test" ID="{NB-1}{1}{B0}" path="https://example.invalid/docs/Vault Test/">
 <one:Section name="00 Index" ID="{S-1}{1}{B0}" path="x"><one:Page ID="{S-1}{1}{E1}" name="ObsidiNote" pageLevel="1" lastModifiedTime="2026-01-01T00:00:00.000Z"><one:Meta name="obsn.indexKey" content="state"/></one:Page></one:Section>
 <one:Section name="Notes" ID="{S-2}{1}{B0}" path="x">
  <one:Page ID="{S-2}{1}{E1}" name="Tidal gardens" pageLevel="1" lastModifiedTime="2026-01-01T00:00:00.000Z"><one:Meta name="obsn.id" content="p1"/><one:Meta name="obsn.type" content="note"/></one:Page>
  <one:Page ID="{S-2}{1}{E2}" name="Part of it" pageLevel="2" lastModifiedTime="2026-01-01T00:00:00.000Z"/>
 </one:Section>
 <one:Section name="Recipes I keep" ID="{S-3}{1}{B0}" path="x"/>
 <one:SectionGroup name="Journal" ID="{G-1}{1}{B0}" path="x"><one:Section name="2026" ID="{S-4}{1}{B0}" path="x"/></one:SectionGroup>
 <one:SectionGroup name="OneNote_RecycleBin" ID="{G-9}{1}{B0}" path="x" isRecycleBin="true"><one:Section name="Deleted Pages" ID="{S-9}{1}{B0}" path="x" isInRecycleBin="true"><one:Page ID="{S-9}{1}{E1}" name="Gone" pageLevel="1" isInRecycleBin="true"/></one:Section></one:SectionGroup>
</one:Notebook>
"@

Describe 'Type to bucket' {
    It 'maps every type of the fixed list' {
        Get-BucketForType concept | Should Be 'Notes'
        Get-BucketForType note | Should Be 'Notes'
        Get-BucketForType howto | Should Be 'Notes'
        Get-BucketForType link-internal | Should Be 'Internal links'
        Get-BucketForType link-web | Should Be 'Web links'
        Get-BucketForType source | Should Be 'Sources'
        Get-BucketForType person | Should Be 'People'
        Get-BucketForType project | Should Be 'Projects'
        Get-BucketForType project-part | Should Be 'Projects'
        Get-BucketForType meeting | Should Be 'Meetings'
        Get-BucketForType decision | Should Be 'Decisions'
        Get-BucketForType file | Should Be 'Files'
        Get-BucketForType -Type log -Year 2026 | Should Be 'Journal/2026'
        Get-BucketForType ' Note ' | Should Be 'Notes'
    }
    It 'rejects any other type' {
        { Get-BucketForType recipe } | Should Throw
        { Get-BucketForType '' } | Should Throw
    }
}

Describe 'Rollover at 500 pages' {
    It 'uses the bucket while it has room, even when it does not exist yet' {
        $r = Get-TargetSection -Bucket 'Notes' -Counts @{}
        $r.name | Should Be 'Notes'; $r.exists | Should Be $false
        (Get-TargetSection -Bucket 'Notes' -Counts @{ 'Notes' = 499 }).name | Should Be 'Notes'
    }
    It 'rolls over to <Bucket> 2, 3 when full' {
        (Get-TargetSection -Bucket 'Notes' -Counts @{ 'Notes' = 500 }).name | Should Be 'Notes 2'
        (Get-TargetSection -Bucket 'Web links' -Counts @{ 'Web links' = 500; 'Web links 2' = 500; 'Web links 3' = 7 }).name | Should Be 'Web links 3'
        $j = Get-TargetSection -Bucket 'Journal/2026' -Counts @{ 'Journal/2026' = 500 }
        $j.name | Should Be 'Journal/2026 2'; $j.group | Should Be 'Journal'; $j.leaf | Should Be '2026 2'
        (Get-TargetSection -Bucket 'Notes' -Counts @{ 'Notes' = 3 } -Max 3).name | Should Be 'Notes 2'
    }
    It 'knows which bucket a section belongs to' {
        Get-BucketOfSection 'Notes 2' | Should Be 'Notes'
        Get-BucketOfSection 'Journal/2026 2' | Should Be 'Journal'
        Get-BucketOfSection 'Archive/Web links' | Should Be 'Archive'
        Get-BucketOfSection '00 Index' | Should Be '00 Index'
        Get-BucketOfSection 'Recipes I keep' | Should Be ''
        Get-BucketOfSection 'Notes old' | Should Be ''
        Get-ArchiveSectionName 'Journal/2026' | Should Be 'Archive/Journal'
        Get-ArchiveSectionName 'Notes 2' | Should Be 'Archive/Notes'
    }
}

Describe 'Link bucket by host' {
    It 'files Microsoft 365 hosts as Internal links' {
        foreach ($u in 'https://fernbrook.sharepoint.com/sites/Team/Shared%20Documents/a.docx', 'https://fernbrook-my.sharepoint.com/personal/x/Documents/b.xlsx',
            'https://teams.microsoft.com/l/channel/abc', 'https://fernbrook.loop.cloud.microsoft/p/xyz', 'https://loop.microsoft.com/p/1',
            'https://outlook.office.com/mail/', 'https://www.office.com/', 'https://m365.cloud.microsoft/chat') {
            Get-LinkBucket $u | Should Be 'Internal links'
        }
    }
    It 'files every other host as Web links, including look-alikes' {
        foreach ($u in 'https://example.org/a', 'https://sharepoint.com.evil.example/x', 'https://notsharepoint.com/', 'https://teams.microsoft.com.example.net/', 'not a url') {
            Get-LinkBucket $u | Should Be 'Web links'
        }
    }
    It 'uses the internalHosts setting (exact host or *.domain)' {
        Get-LinkBucket 'https://wiki.corp.example/page' -InternalHosts @('*.corp.example') | Should Be 'Internal links'
        Get-LinkBucket 'https://corp.example/' -InternalHosts @('*.corp.example') | Should Be 'Internal links'
        Get-LinkBucket 'http://intranet:8080/home' -InternalHosts @('intranet') | Should Be 'Internal links'
        Get-LinkBucket 'https://other.example/' -InternalHosts @('*.corp.example') | Should Be 'Web links'
    }
    It 'files a company''s SaaS tenant as Internal links (D-112: timesheets, internal vacancies)' {
        foreach ($u in 'https://wd3.myworkday.com/fernbrook/d/inst/1$2/rel-task/3.htmld', 'https://fernbrookitsmprod.service-now.com/msh?id=kb_article',
            'https://fernbrook.atlassian.net/wiki/spaces/OPS', 'https://fernbrook.okta.com/app/UserHome', 'https://fernbrook.my.salesforce.com/001',
            'https://fernbrook.zoom.us/j/123', 'https://app.slack.com/client/T01') {
            Get-LinkBucket $u | Should Be 'Internal links'
        }
    }
    It 'keeps the vendors'' public pages, job boards and public hosting as Web links' {
        foreach ($u in 'https://www.myworkday.com/', 'https://docs.service-now.com/x', 'https://community.atlassian.net/t/1', 'https://www.okta.com/',
            'https://fernbrook.wd3.myworkdayjobs.com/External', 'https://fernbrook.github.io/tools', 'https://myworkday.com/') {
            Get-LinkBucket $u -CompanyNames @('fernbrook') | Should Be 'Web links'
        }
    }
    It 'files a host with the company''s name in a subdomain as internal, not the company''s own public site' {
        Get-LinkBucket 'https://fernbrook.example-hr.com/vacancies/internal' -CompanyNames @('fernbrook') | Should Be 'Internal links'
        Get-LinkBucket 'https://hr-fernbrook.example.net/' -CompanyNames @('fernbrook') | Should Be 'Internal links'
        Get-LinkBucket 'https://www.fernbrook.com/about' -CompanyNames @('fernbrook') | Should Be 'Web links'
        Get-LinkBucket 'https://fernbrook.com/' -CompanyNames @('fernbrook') | Should Be 'Web links'
        Get-LinkBucket 'https://news.example.org/companies/fernbrook' -CompanyNames @('fernbrook') | Should Be 'Web links'
        Get-LinkBucket 'https://fernbrook.example-hr.com/' | Should Be 'Web links'
    }
    It 'takes the company''s tenant names from its own Microsoft 365 addresses only' {
        $n = @(Get-CompanyNames -Locations @('https://fernbrook-my.sharepoint.com/personal/someone/Documents/ObsidiNote', 'onenote:https://fernbrook.sharepoint.com/sites/Team/x.one', 'C:\Notes\x.onetoc2', '', 'https://fabrikam.sharepoint.com/'))
        $n.Count | Should Be 2
        ($n -join ',') | Should Be 'fernbrook,fabrikam'
        # as the server passes them on: two separate names, not one joined string
        Get-LinkBucket 'https://fabrikam.example-hr.com/' -CompanyNames $n | Should Be 'Internal links'
        @(Get-CompanyNames -Locations @('https://ab.sharepoint.com/', 'https://example.org/')).Count | Should Be 0
    }
}

Describe 'URL normalization for dedup' {
    It 'drops tracking parameters and the fragment, keeps the rest in order' {
        ConvertTo-NormalizedUrl 'https://Example.ORG/Path/A?b=2&utm_source=x&a=1&fbclid=zz&UTM_Medium=y#section' | Should Be 'https://example.org/Path/A?b=2&a=1'
        ConvertTo-NormalizedUrl 'https://learn.example.com/x?WT.mc_id=abc&gclid=1&msclkid=2' | Should Be 'https://learn.example.com/x'
    }
    It 'lower-cases scheme and host, drops default ports, adds the root path' {
        ConvertTo-NormalizedUrl 'HTTPS://Example.org:443' | Should Be 'https://example.org/'
        ConvertTo-NormalizedUrl 'http://example.org:80/a' | Should Be 'http://example.org/a'
        ConvertTo-NormalizedUrl 'http://example.org:8080/a' | Should Be 'http://example.org:8080/a'
    }
    It 'keeps a sharing token and returns non-URLs trimmed' {
        ConvertTo-NormalizedUrl 'https://fernbrook.sharepoint.com/:w:/s/T/Eabc?e=Xy12&utm_campaign=q' | Should Be 'https://fernbrook.sharepoint.com/:w:/s/T/Eabc?e=Xy12'
        ConvertTo-NormalizedUrl '  just text ' | Should Be 'just text'
    }
    It 'makes the same link equal however it was pasted' {
        (ConvertTo-NormalizedUrl 'https://example.org/a?x=1#top') | Should Be (ConvertTo-NormalizedUrl 'https://EXAMPLE.org/a?x=1&utm_source=mail')
    }
}

Describe 'Hierarchy parsing' {
    $t = ConvertFrom-ObsnHierarchy -Xml $fixture
    It 'reads sections with their full path and pages with Meta and level' {
        @($t.sections | ForEach-Object { $_.full }) -join ',' | Should Be '00 Index,Notes,Recipes I keep,Journal/2026'
        $notes = @($t.sections | Where-Object { $_.full -eq 'Notes' })[0]
        $notes.pages.Count | Should Be 2
        $notes.pages[0].meta['obsn.id'] | Should Be 'p1'
        $notes.pages[1].level | Should Be 2
    }
    It 'leaves the recycle bin out' {
        @($t.groups | ForEach-Object { $_.full }) -join ',' | Should Be 'Journal'
    }
    It 'parses relative to a section-group root' {
        $g = ConvertFrom-ObsnHierarchy -Xml $fixture -RootId '{G-1}{1}{B0}'
        $g.notebook.kind | Should Be 'sectiongroup'
        @($g.sections | ForEach-Object { $_.full }) -join ',' | Should Be '2026'
    }
    It 'plans the missing fixed sections and lists the user''s own' {
        $p = Get-StructurePlan -Tree $t -Year 2026
        $p.missingGroups -join ',' | Should Be 'Archive'
        $p.missingSections -join ',' | Should Be '01 Intake,Internal links,Web links,Sources,People,Projects,Meetings,Decisions,Files'
        $p.userSections -join ',' | Should Be 'Recipes I keep'
        ($p.present -contains 'Journal/2026') | Should Be $true
    }
    It 'puts a new notebook next to the first cloud notebook, or in -Location' {
        $all = "<?xml version=""1.0""?><one:Notebooks $ns><one:Notebook name=""L"" ID=""1"" path=""C:\nb\L""/><one:Notebook name=""C"" ID=""2"" path=""https://example.invalid/docs/C/""/></one:Notebooks>"
        Get-NotebookBasePath -NotebooksXml $all | Should Be 'https://example.invalid/docs/'
        Get-NotebookBasePath -NotebooksXml $all -Location 'https://example.invalid/other' | Should Be 'https://example.invalid/other/'
        { Get-NotebookBasePath -NotebooksXml "<?xml version=""1.0""?><one:Notebooks $ns/>" } | Should Throw
    }
}

Describe 'Link rules and origin: one place each (code review 2026-11-15)' {
    It 'Get-LinkRules puts a vault''s rules together from its setting and the addresses it owns' {
        $r = Get-LinkRules -InternalHosts @('wiki.example.invalid', '', $null) -Locations @('https://fernbrook-my.sharepoint.com/personal/x/Documents/V/', '', 'onenote:https://fernbrook.sharepoint.com/sites/a/x.one', 'C:\nb\L')
        (@($r.InternalHosts) -join ',') | Should Be 'wiki.example.invalid'
        (@($r.CompanyNames) -join ',') | Should Be 'fernbrook'
        $none = Get-LinkRules
        "$(@($none.InternalHosts).Count):$(@($none.CompanyNames).Count)" | Should Be '0:0'
    }
    It 'the start and the server both use it and neither works the company names out itself' {
        # The commands a file calls (comments and strings are no commands in the AST).
        $calls = { param($file) @((Read-ScriptAst -Path $file).FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }) }
        foreach ($f in 'obsidinote.ps1', 'lib\Server.psm1') {
            $c = & $calls (Join-Path $root $f)
            "$f $($c -contains 'Get-LinkRules') $($c -contains 'Get-CompanyNames')" | Should Be "$f True False"
        }
    }
    It 'Resolve-OriginId is the one check: nothing is typed, text is trimmed, anything else is refused' {
        foreach ($v in $null, '', '  ') { $o = Resolve-OriginId $v; "$($o.ok):$($o.origin)" | Should Be 'True:' }
        $o = Resolve-OriginId ' Teams '
        "$($o.ok):$($o.origin)" | Should BeExactly 'True:teams'   # stored as the list's own id (tests/fixtures/origins.json)
        (Resolve-OriginId ' teams ').origin | Should Be 'teams'
        (Resolve-OriginId 'slack').error | Should Be 'Unknown origin.'
        foreach ($v in 5, $true, @('teams')) { (Resolve-OriginId $v).error | Should Be 'origin must be text.' }
        foreach ($id in @(Get-OriginList | ForEach-Object { $_.id })) { (Resolve-OriginId $id).ok | Should Be $true }
    }
    It 'no other module checks an origin by itself' {
        $lib = Join-Path $root 'lib'
        $hits = @(Get-ChildItem -LiteralPath $lib -Filter '*.psm1' | Where-Object { $_.Name -ne 'NotebookStructure.psm1' } | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'Test-OriginId' } | ForEach-Object { $_.Name })
        ($hits -join ',') | Should Be ''
    }
    It 'personal OneDrive is filed as internal (the same place the Sources view shows it)' {
        Get-LinkBucket -Url 'https://d.docs.live.net/0123456789abcdef/Documents/a.docx' | Should Be 'Internal links'
        Get-LinkBucket -Url 'https://onedrive.live.com/edit?id=1' | Should Be 'Internal links'
    }
}
