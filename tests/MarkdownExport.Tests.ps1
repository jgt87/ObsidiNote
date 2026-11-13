# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/MarkdownExport.psm1: OneNote page XML -> Obsidian-compatible Markdown, front matter, file
# names, scopes and the in-memory zip. Invented pages only; no OneNote, nothing on disk.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $here '..\lib\MarkdownExport.psm1') -Force
Add-Type -AssemblyName System.IO.Compression

$script:NsUri = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$script:LinkP2 = 'onenote:https://example.org/Notes.one#Partner%20portal&section-id={11111111-1111-1111-1111-111111111111}&page-id={22222222-2222-2222-2222-222222222222}&end'

function New-PageXml([string]$Outlines, [string]$Defs = '') {
    "<?xml version=""1.0""?><one:Page xmlns:one=""$($script:NsUri)"" ID=""{P1}"" name=""T"">$Defs<one:Title><one:OE><one:T><![CDATA[T]]></one:T></one:OE></one:Title>$Outlines</one:Page>"
}

function New-Oe([string]$Html, [string]$Inner = '', [string]$Attr = '') { "<one:OE$Attr>$Inner<one:T><![CDATA[$Html]]></one:T></one:OE>" }

function New-Model {
    $pages = [ordered]@{}
    $pages['p1'] = @{ key = 'p1'; id = 'p1'; title = 'Identity-aware proxies'; type = 'concept'; topics = @('Security/Networking'); aliases = @('IAP'); summary = 'A proxy "that" checks.'; url = ''; status = ''; link = 'onenote:#p1'; oneNoteId = '{P1}'; links = @(@{ target = 'p2'; strength = 2; why = 'x' }, @{ target = 'p404'; strength = 1 }); updated = '2026-11-13' }
    $pages['p2'] = @{ key = 'p2'; id = 'p2'; title = 'Partner portal'; type = 'project'; topics = @('Projects'); aliases = @(); summary = ''; url = ''; status = ''; link = $script:LinkP2; oneNoteId = '{22222222-2222-2222-2222-222222222222}{1}{E1}'; links = @(); updated = '' }
    $pages['p3'] = @{ key = 'p3'; id = 'p3'; title = 'Partner portal'; type = 'note'; topics = @('Security/Networking/Zero trust'); aliases = @(); summary = ''; url = ''; status = 'archived'; link = ''; oneNoteId = '{P3}'; links = @(); updated = '' }
    $pages['n:{P4}{1}{B0}'] = @{ key = 'n:{P4}{1}{B0}'; id = ''; title = 'Shopping: list?'; type = ''; topics = @(); aliases = @(); summary = ''; url = ''; status = ''; link = ''; oneNoteId = '{P4}{1}{B0}'; links = @(); updated = '' }
    @{ pages = $pages; topics = @{} }
}

Describe 'ConvertFrom-OneHtml' {
    It 'turns styled spans into Markdown and escapes Markdown characters in plain text' {
        ConvertFrom-OneHtml "plain <span style='font-weight:bold'>bold</span> <span style='font-style:italic'>it</span> <span style='text-decoration:line-through'>gone</span>" | Should Be 'plain **bold** *it* ~~gone~~'
        ConvertFrom-OneHtml "<span style='font-family:Consolas'>a_b*c</span> and a_b*c" | Should Be '`a_b*c` and a\_b\*c'
        ConvertFrom-OneHtml 'Tom &amp; Jerry &lt;3' | Should Be 'Tom & Jerry <3'
        ConvertFrom-OneHtml "<span style='font-weight:bold'></span>x" | Should Be 'x'
    }
    It 'makes web links Markdown links and links to exported pages wikilinks' {
        $t = @{ 'onenote:#p1' = 'Identity-aware proxies'; 'guid:22222222-2222-2222-2222-222222222222' = 'Partner portal' }
        ConvertFrom-OneHtml '<a href="https://example.org/a?b=1&amp;c=2">the guide</a>' | Should Be '[the guide](<https://example.org/a?b=1&c=2>)'
        ConvertFrom-OneHtml '<a href="onenote:#p1">Identity-aware proxies</a>' -Targets $t | Should Be '[[Identity-aware proxies]]'
        ConvertFrom-OneHtml ('see <a href="onenote:https://x/y.one#Other&amp;page-id={22222222-2222-2222-2222-222222222222}&amp;end">the portal</a>') -Targets $t | Should Be 'see [[Partner portal|the portal]]'
        ConvertFrom-OneHtml '<a href="javascript:alert(1)">x</a>' | Should Be 'x'
    }
}

Describe 'ConvertFrom-OnePageXml' {
    $props = '<one:Outline><one:Meta name="obsn.role" content="props" /><one:OEChildren>' + (New-Oe 'Type: concept') + '</one:OEChildren></one:Outline>'
    $back = '<one:Outline><one:Meta name="obsn.role" content="backlinks" /><one:OEChildren>' + (New-Oe 'Linked from') + '</one:OEChildren></one:Outline>'
    $bullet = '<one:List><one:Bullet bullet="2" /></one:List>'
    $num = '<one:List><one:Number numberSequence="0" numberFormat="##." text="1." /></one:List>'
    $nested = "<one:OE>$bullet<one:T><![CDATA[outer]]></one:T><one:OEChildren>" + (New-Oe 'inner' $bullet) + '</one:OEChildren></one:OE>'
    $table = '<one:OE><one:Table bordersVisible="true"><one:Columns><one:Column index="0" width="120" /><one:Column index="1" width="120" /></one:Columns>' +
        '<one:Row><one:Cell><one:OEChildren>' + (New-Oe "<span style='font-weight:bold'>Name</span>") + '</one:OEChildren></one:Cell><one:Cell><one:OEChildren>' + (New-Oe "<span style='font-weight:bold'>Use</span>") + '</one:OEChildren></one:Cell></one:Row>' +
        '<one:Row><one:Cell><one:OEChildren>' + (New-Oe 'IAP') + '</one:OEChildren></one:Cell><one:Cell><one:OEChildren>' + (New-Oe 'a|b') + '</one:OEChildren></one:Cell></one:Row></one:Table></one:OE>'
    $body = '<one:Outline><one:Meta name="obsn.role" content="body" /><one:OEChildren>' +
        (New-Oe "<span style='font-weight:bold'><span style='font-size:16pt'>Overview</span></span>") +
        (New-Oe "<span style='font-weight:bold'>Stored size</span>" '' ' style="font-family:Calibri;font-size:14.0pt"') + (New-Oe 'Normal twelve' '' ' style="font-size:12.0pt"') +
        (New-Oe 'First line.') + $nested + (New-Oe 'one' $num) + (New-Oe 'two' $num) +
        (New-Oe ([string][char]0x2611 + ' done') $bullet) + $table + '<one:OE><one:Image><one:Size width="1" height="1" /></one:Image></one:OE>' + '</one:OEChildren></one:Outline>'
    $user = '<one:Outline><one:OEChildren>' + (New-Oe 'Own heading' '' ' quickStyleIndex="1"') + (New-Oe 'My own words.') + '</one:OEChildren></one:Outline>'
    $md = ConvertFrom-OnePageXml -Xml (New-PageXml ($props + $body + $back + $user) '<one:QuickStyleDef index="1" name="h2" fontSize="14.0" />')

    It 'leaves out the generated outlines (properties, Linked from)' {
        $md | Should Not Match 'Type: concept'
        $md | Should Not Match 'Linked from'
    }
    It 'writes headings, paragraphs, nested bullets, numbers and tasks' {
        $md | Should Match '(?m)^# Overview$'
        $md | Should Match '(?m)^## Stored size$'
        $md | Should Match '(?m)^Normal twelve$'
        $md | Should Match "(?m)^First line\.\r?\n\r?\n- outer\n    - inner\n1\. one\n2\. two\n- \[x\] done$"
        $md | Should Match '(?m)^## Own heading$'
        $md | Should Match '(?m)^My own words\.$'
    }
    It 'writes a table with a header row and escaped pipes' {
        $md | Should Match '(?m)^\| Name \| Use \|$'
        $md | Should Match '(?m)^\| --- \| --- \|$'
        $md | Should Match '(?m)^\| IAP \| a\\\|b \|$'
    }
    It 'says where an image was left out' {
        $md | Should Match 'left out of the export'
    }
}

Describe 'Names, front matter and scopes' {
    $m = New-Model
    $names = Get-ExportNames -Model $m
    It 'gives every page a unique, safe file name' {
        $names['p2'] | Should Be 'Partner portal'
        $names['p3'] | Should Be 'Partner portal (p3)'
        $names['n:{P4}{1}{B0}'] | Should Be 'Shopping list'
        ConvertTo-SafeName 'CON' | Should Be '_CON'
        ConvertTo-SafeName '  a/b\c:d*e?. ' | Should Be 'a b c d e'
    }
    It 'writes front matter from the index record, links as wikilinks to file names' {
        $fm = New-FrontMatter -Page $m.pages['p1'] -Names $names
        $fm | Should Match '(?m)^id: "p1"$'
        $fm | Should Match '(?m)^topics:\n  - "Security/Networking"$'
        $fm | Should Match '(?m)^aliases:\n  - "IAP"$'
        $fm | Should Match '(?m)^summary: "A proxy \\"that\\" checks\."$'
        $fm | Should Match '(?m)^links:\n  - "\[\[Partner portal\]\]"$'
        $fm | Should Not Match 'p404'
        $fm.StartsWith("---`n") | Should Be $true
    }
    It 'selects a page, a topic with its subtopics, or everything' {
        (Select-ExportPages -Model $m -Scope page -Key 'p2') -join ',' | Should Be 'p2'
        @(Select-ExportPages -Model $m -Scope page -Key 'p99').Count | Should Be 0
        (Select-ExportPages -Model $m -Scope topic -Topic 'Security/Networking') -join ',' | Should Be 'p1,p3'
        @(Select-ExportPages -Model $m -Scope topic -Topic 'Security/Net').Count | Should Be 0
        @(Select-ExportPages -Model $m -Scope all).Count | Should Be 4
    }
}

Describe 'New-MarkdownExport' {
    $m = New-Model
    $read = { param($Id) New-PageXml ('<one:Outline><one:OEChildren>' + (New-Oe "Read <a href=""$($script:LinkP2 -replace '&', '&amp;')"">the portal</a>.") + '</one:OEChildren></one:Outline>') }
    It 'returns one .md for a page, with front matter and wikilinks' {
        $x = New-MarkdownExport -Model $m -ReadPage $read -SourceName 'Work' -Scope page -Key 'p1'
        $x.name | Should Be 'Identity-aware proxies.md'
        $x.type | Should Match '^text/markdown'
        $t = (New-Object Text.UTF8Encoding $false).GetString($x.bytes)
        $t | Should Match '(?m)^title: "Identity-aware proxies"$'
        $t | Should Match 'Read \[\[Partner portal\|the portal\]\]\.'
        $x.bytes[0] | Should Be ([byte][char]'-')
    }
    It 'returns a zip with a folder per topic path under the source name' {
        $x = New-MarkdownExport -Model $m -ReadPage $read -SourceName 'Work: vault' -Scope all
        $x.name | Should Be 'Work vault - Markdown.zip'
        $x.pages | Should Be 4
        $ms = New-Object IO.MemoryStream (, $x.bytes)
        $zip = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
        try { $entries = @($zip.Entries | ForEach-Object { $_.FullName } | Sort-Object) } finally { $zip.Dispose() }
        $entries -join '|' | Should Be 'Work vault/Projects/Partner portal.md|Work vault/Security/Networking/Identity-aware proxies.md|Work vault/Security/Networking/Zero trust/Partner portal (p3).md|Work vault/Unfiled/Shopping list.md'
    }
    It 'names a topic export after the topic and says when nothing matches' {
        (New-MarkdownExport -Model $m -ReadPage $read -SourceName 'Work' -Scope topic -Topic 'Security/Networking').name | Should Be 'Work - Networking - Markdown.zip'
        (New-MarkdownExport -Model $m -ReadPage $read -SourceName 'Work' -Scope topic -Topic 'Nope').error | Should Match 'no pages'
    }
    It 'keeps going when a page cannot be read, and says so in that file' {
        $bad = { param($Id) if ($Id -eq '{P1}') { throw 'COM error' }; New-PageXml '' }
        $x = New-MarkdownExport -Model $m -ReadPage $bad -SourceName 'Work' -Scope page -Key 'p1'
        $x.failed | Should Be 1
        (New-Object Text.UTF8Encoding $false).GetString($x.bytes) | Should Match 'could not be read'
    }
}
