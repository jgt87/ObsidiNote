# Pester 3.4. Notebook structure: type -> bucket, rollover, link buckets, URL normalization,
# hierarchy parsing. Synthetic data only (fictional names, made-up ids).
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'lib\NotebookStructure.psm1') -Force

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
        foreach ($u in 'https://contoso.sharepoint.com/sites/Team/Shared%20Documents/a.docx', 'https://contoso-my.sharepoint.com/personal/x/Documents/b.xlsx',
            'https://teams.microsoft.com/l/channel/abc', 'https://contoso.loop.cloud.microsoft/p/xyz', 'https://loop.microsoft.com/p/1',
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
        ConvertTo-NormalizedUrl 'https://contoso.sharepoint.com/:w:/s/T/Eabc?e=Xy12&utm_campaign=q' | Should Be 'https://contoso.sharepoint.com/:w:/s/T/Eabc?e=Xy12'
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
        $p.missingSections -join ',' | Should Be '01 Inbox,Internal links,Web links,Sources,People,Projects,Meetings,Decisions,Files'
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
