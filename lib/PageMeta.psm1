# ObsidiNote's data on a OneNote page: page-level <one:Meta name="obsn.*"> tags and the outlines
# ObsidiNote owns (tagged <one:Meta name="obsn.role">). Pure XML builders/parsers plus thin
# wrappers over the adapter (lib/OneNote.psm1). PS 5.1, ASCII only. Writes nothing to disk.
#
# Id scheme: 'p' + base36 of a counter (p1, p2, ... pz, p10, ...). The counter is the next value to
# hand out and lives on the vault's state page (obsn.idCounter). Only the lease holder allocates.
# A rebuild sets it to max(counter, highest id seen + 1), so a lost state page never reuses an id.
# Topics are identified by their path ('Security/Networking/Zero trust'), not by an id.
#
# Meta values: plain strings; topics, aliases and links are compact JSON arrays.
#   obsn.topics  ["Security/Networking"]          obsn.aliases ["ZTNA"]
#   obsn.links   [{"t":"p2","s":3,"w":"why"}]     (t target id, s strength 1-3, w why)
# A long value is split over obsn.X.1 .. obsn.X.N with obsn.X.n = N (Split-/Join-ObsnMetaValue).
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OneNote.psm1')

# linkSummary .. checkStatus: a link page's summary record (JSON), the hash of the summary outline as
# written (hand edits show as a mismatch), the last 3 earlier summaries (JSON), when the same link was
# pasted again, and why the last check could not update it (lib/Ingest.psm1, Update-LinkSummary).
# origin: where a page without an address came from (Outlook mail, Teams, Word, ...: lib/NotebookStructure.psm1
# Get-OriginList; set at Add from the paste or by the person, changeable in Edit; 2026-11-14).
# tags: set by hand only (2026-11-15), never by Copilot; a JSON array of normal-form tags
# (ConvertTo-TagList). A page that never had a tag has no obsn.tags Meta; '' = all were removed.
# entries: a journal day page's entries (operator, 2026-11-17: one page per day), a JSON array of
# { r: request ref, at: yyyy-MM-ddTHH:mm, t: title, s: summary, p: topic paths, l: links } in the order of
# the body outline's top-level lines (Add-ObsnBodyEntry). Only on day pages; '' or absent elsewhere.
# series / meetingAt: a meeting page's series (the Teams title as the meeting list gave it) and when
# the meeting started (yyyy-MM-ddTHH:mm, local), written by ObsidiNote at import, never by Copilot
# (operator, 2026-11-18: a daily meeting is one series of pages). '' or absent on other pages.
# meeting: a meeting page's notes in structured form (JSON: s summary, d decisions, a actions
# {t, o owner, u due}, p people {n, e}), read from its own text at import (2026-11-19), for the
# series page. kind 'series' marks a series page (the overview of a meeting series).
$script:MetaKeys = @('id', 'type', 'topics', 'aliases', 'summary', 'links', 'status', 'url', 'host', 'kind', 'summarizedAt', 'archivedFrom', 'linkSummary', 'summaryHash', 'history', 'seenAt', 'checkStatus', 'origin', 'tags', 'entries', 'series', 'meetingAt', 'meeting')
$script:ListKeys = @('topics', 'aliases', 'tags')
$script:MaxTagLength = 40
$script:MaxTagsPerPage = 12
# Values that can grow past one Meta tag: always written with their obsn.X.n part count.
$script:SplitKeys = @('linkSummary', 'history', 'entries', 'meeting')
# Outlines ObsidiNote owns (obsn.role). body: the item as added; checked: when a link was summarized
# and its earlier summaries; notes: "Your notes" on a link page, written once when the page is made
# and never again (Write-ObsnPage refuses it on an existing page).
$script:Roles = @('props', 'backlinks', 'summary', 'index', 'state', 'body', 'checked', 'notes')
$script:WriteOnceRoles = @('notes')

function Get-ObsnRoles { , @($script:Roles) }
function Get-ObsnMetaKeys { , @($script:MetaKeys) }

function ConvertTo-Base36 {
    param([Parameter(Mandatory)][int64]$Value)
    if ($Value -lt 0) { throw 'negative' }
    $d = '0123456789abcdefghijklmnopqrstuvwxyz'
    if ($Value -eq 0) { return '0' }
    $s = ''
    while ($Value -gt 0) { $s = $d[[int]($Value % 36)] + $s; $Value = [int64][Math]::Floor($Value / 36) }
    $s
}

function ConvertFrom-Base36 {
    param([Parameter(Mandatory)][string]$Text)
    $d = '0123456789abcdefghijklmnopqrstuvwxyz'
    [int64]$v = 0
    foreach ($ch in $Text.ToLowerInvariant().ToCharArray()) {
        $i = $d.IndexOf($ch)
        if ($i -lt 0) { throw "not base36: $Text" }
        $v = $v * 36 + $i
    }
    $v
}

function New-ObsnId { <# 'p' + base36(counter). #> param([Parameter(Mandatory)][int64]$Counter) 'p' + (ConvertTo-Base36 $Counter) }
function Test-ObsnId { param([string]$Id) [bool]($Id -cmatch '^p[0-9a-z]+$' -and $Id -notmatch '^p0.') }
function Get-ObsnIdNumber { param([string]$Id) if (Test-ObsnId $Id) { ConvertFrom-Base36 $Id.Substring(1) } else { [int64]0 } }

function ConvertTo-TopicPath {
    <# 'Security / Networking ' -> 'Security/Networking'. Segments trimmed, inner spaces collapsed. #>
    param([AllowEmptyString()][string]$Path)
    $segs = @($Path.Split('/') | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    $segs -join '/'
}
function Format-TopicPath { param([string]$Path) $Path.Replace('/', ' / ') }

function ConvertTo-TagList {
    <# THE normal form of hand-set tags (pinned by tests/fixtures/tags.json, which the interface's
       tests read too: change all three together). Each tag: trimmed, inner spaces collapsed to one,
       lower case; 1 to 40 characters; no double quote, comma, colon, line break or control
       character. In the list duplicates go (the first stays), order is kept, at most $Max (12 per
       page). An invalid tag refuses the whole list: nothing is dropped silently.
       Returns @{ ok; tags (string[]); error (a plain sentence) }. Pure. #>
    param([object[]]$Tags = @(), [int]$Max = $script:MaxTagsPerPage)
    $out = New-Object System.Collections.Generic.List[string]
    $fail = { param($m) @{ ok = $false; tags = @(); error = $m } }
    foreach ($raw in @($Tags)) {
        if ($null -eq $raw -or $raw -isnot [string]) { return (& $fail 'A tag must be text.') }
        if ($raw -match '[\x00-\x1f\x7f]' -or $raw -match '[",:]') { return (& $fail 'A tag cannot hold a double quote, a comma, a colon or a line break.') }
        $t = ($raw -replace '\s+', ' ').Trim().ToLowerInvariant()
        if (-not $t -or $t.Length -gt $script:MaxTagLength) { return (& $fail "A tag is 1 to $($script:MaxTagLength) characters long.") }
        if (-not $out.Contains($t)) { $out.Add($t) }
    }
    if ($out.Count -gt $Max) { return (& $fail "A page can have at most $Max tags.") }
    @{ ok = $true; tags = [string[]]$out.ToArray(); error = '' }
}

function ConvertTo-CompactJson {
    param($Value)
    ConvertTo-Json -InputObject $Value -Compress -Depth 8
}

function Get-JsonProp {
    <# A property of a ConvertFrom-Json object, or $Default when it is missing (StrictMode-safe). #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [hashtable]) { if ($Object.ContainsKey($Name)) { return $Object[$Name] } else { return $Default } }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    $Default
}

function ConvertFrom-JsonList {
    <# The items of a JSON array value on the pipeline (nothing for ''/invalid); wrap calls in @(). #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if (-not $Text) { return }
    try { $v = ConvertFrom-Json -InputObject $Text } catch { return }
    @($v | Where-Object { $null -ne $_ })
}

function ConvertTo-ObsnLinksValue {
    <# @(@{ target; strength; why }) -> '[{"t":..,"s":..,"w":..}]'. Strength is clamped to 1-3. #>
    param([object[]]$Links = @())
    $out = @(foreach ($l in @($Links)) {
        if ($null -eq $l) { continue }
        $t = [string](Get-JsonProp $l 'target' (Get-JsonProp $l 't' ''))
        if (-not $t) { continue }
        $s = [int](Get-JsonProp $l 'strength' (Get-JsonProp $l 's' 1))
        if ($s -lt 1) { $s = 1 } elseif ($s -gt 3) { $s = 3 }
        [ordered]@{ t = $t; s = $s; w = [string](Get-JsonProp $l 'why' (Get-JsonProp $l 'w' '')) }
    })
    ConvertTo-CompactJson -Value $out
}

function ConvertFrom-ObsnLinksValue {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $res = @(foreach ($o in (ConvertFrom-JsonList $Text)) {
        $t = [string](Get-JsonProp $o 't' '')
        if ($t) { @{ target = $t; strength = [int](Get-JsonProp $o 's' 1); why = [string](Get-JsonProp $o 'w' '') } }
    })
    return , $res
}

function ConvertTo-ObsnMeta {
    <# A page record (hashtable with id, type, topics, aliases, summary, links, status, url, host, kind,
       summarizedAt, archivedFrom) -> ordered 'obsn.<key>' -> string. Empty values are written as ''
       so an update clears an old value. #>
    param([Parameter(Mandatory)][hashtable]$Page)
    $m = [ordered]@{}
    foreach ($k in $script:MetaKeys) {
        if (-not $Page.ContainsKey($k)) { continue }
        $v = $Page[$k]
        if ($k -eq 'topics') { $v = ConvertTo-CompactJson -Value @(@($v) | Where-Object { $_ } | ForEach-Object { ConvertTo-TopicPath ([string]$_) }) }
        elseif ($k -eq 'aliases') { $v = ConvertTo-CompactJson -Value @(@($v) | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
        elseif ($k -eq 'tags') { $tg = @(@($v) | Where-Object { $_ } | ForEach-Object { [string]$_ }); $v = if ($tg.Count) { ConvertTo-CompactJson -Value $tg } else { '' } }
        elseif ($k -eq 'links') { $v = ConvertTo-ObsnLinksValue -Links @($v) }
        elseif ($k -eq 'entries') { $v = ConvertTo-ObsnEntriesValue -Entries @($v) }
        elseif ($null -eq $v) { $v = '' }
        if ($script:SplitKeys -contains $k) {
            # Long values are split (OneNote refuses a Meta value over about 100k characters).
            foreach ($kv in (Split-ObsnMetaValue -Name "obsn.$k" -Value ([string]$v)).GetEnumerator()) { $m[$kv.Key] = $kv.Value }
            continue
        }
        $m["obsn.$k"] = [string]$v
    }
    $m
}

function ConvertFrom-ObsnMeta {
    <# Meta name -> content (from a page or from the hierarchy) -> page record hashtable with
       typed values (topics/aliases arrays, links array of @{target;strength;why}). Pure. #>
    param([hashtable]$Meta = @{})
    $r = @{}
    foreach ($k in $script:MetaKeys) {
        $v = Join-ObsnMetaValue -Meta $Meta -Name "obsn.$k"
        if ($k -in $script:ListKeys) { $r[$k] = @(ConvertFrom-JsonList $v | ForEach-Object { [string]$_ }) }
        elseif ($k -eq 'links') { $r[$k] = ConvertFrom-ObsnLinksValue $v }
        elseif ($k -eq 'entries') { $r[$k] = @(ConvertFrom-ObsnEntriesValue $v) }
        else { $r[$k] = if ($null -eq $v) { '' } else { [string]$v } }
    }
    $r
}

function ConvertTo-ObsnEntriesValue {
    <# @(@{ ref; at; title; summary; topics; links }) -> the obsn.entries JSON ('' when there are none). #>
    param([object[]]$Entries = @())
    $list = @(foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        [ordered]@{
            r = [string](Get-JsonProp $e 'ref' ''); at = [string](Get-JsonProp $e 'at' ''); t = [string](Get-JsonProp $e 'title' ''); s = [string](Get-JsonProp $e 'summary' '')
            p = @(@(Get-JsonProp $e 'topics' @()) | Where-Object { $_ } | ForEach-Object { ConvertTo-TopicPath ([string]$_) } | Where-Object { $_ })
            l = @(@(Get-JsonProp $e 'links' @()) | Where-Object { $_ } | ForEach-Object { [ordered]@{ t = [string](Get-JsonProp $_ 'target' ''); s = [Math]::Min(3, [Math]::Max(1, [int](Get-JsonProp $_ 'strength' 1))); w = [string](Get-JsonProp $_ 'why' '') } })
        }
    })
    if (-not $list.Count) { return '' }
    ConvertTo-CompactJson -Value $list
}

function ConvertFrom-ObsnEntriesValue {
    <# The obsn.entries JSON -> @(@{ ref; at; title; summary; topics; links }); nothing for ''/invalid.
       Wrap calls in @(). Pure. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    foreach ($e in @(ConvertFrom-JsonList $Text)) {
        @{
            ref = [string](Get-JsonProp $e 'r' ''); at = [string](Get-JsonProp $e 'at' ''); title = [string](Get-JsonProp $e 't' ''); summary = [string](Get-JsonProp $e 's' '')
            topics = @(@(Get-JsonProp $e 'p' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
            links = @(@(Get-JsonProp $e 'l' @()) | Where-Object { $_ } | ForEach-Object { @{ target = [string](Get-JsonProp $_ 't' ''); strength = [int](Get-JsonProp $_ 's' 1); why = [string](Get-JsonProp $_ 'w' '') } })
        }
    }
}

function Split-ObsnMetaValue {
    <# One logical value -> Meta tags. Short values: obsn.X = value, obsn.X.n = '0'. Long values:
       obsn.X = '', obsn.X.1..N = parts of at most $Max chars, obsn.X.n = N. #>
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Value, [int]$Max = 30000)
    $m = [ordered]@{}
    if ($Value.Length -le $Max) { $m[$Name] = $Value; $m["$Name.n"] = '0'; return $m }
    $m[$Name] = ''
    $n = 0
    for ($i = 0; $i -lt $Value.Length; $i += $Max) {
        $n++
        $m["$Name.$n"] = $Value.Substring($i, [Math]::Min($Max, $Value.Length - $i))
    }
    $m["$Name.n"] = [string]$n
    $m
}

function Join-ObsnMetaValue {
    param([hashtable]$Meta, [Parameter(Mandatory)][string]$Name)
    $n = 0
    if ($Meta.ContainsKey("$Name.n")) { [void][int]::TryParse([string]$Meta["$Name.n"], [ref]$n) }
    if ($n -le 0) { if ($Meta.ContainsKey($Name)) { return [string]$Meta[$Name] } else { return $null } }
    $sb = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le $n; $i++) { [void]$sb.Append([string]$Meta["$Name.$i"]) }
    $sb.ToString()
}

function ConvertTo-OneHtml {
    <# Plain text -> HTML fragment for an outline line. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function ConvertTo-OneHref([string]$Href) {
    <# A link address as an href attribute value. Never a literal '>' so the CDATA stays closed. #>
    $Href.Replace('&', '&amp;').Replace('"', '&quot;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function New-OneLink {
    <# HTML fragment of a link. #>
    param([string]$Href, [string]$Label)
    if (-not $Href) { return (ConvertTo-OneHtml $Label) }
    '<a href="' + (ConvertTo-OneHref $Href) + '">' + (ConvertTo-OneHtml $Label) + '</a>'
}

function New-OneLine {
    <# A line for New-ObsnOutlineXml: @{ html; children; collapsed; list; number; table }. -Text is
       encoded, -Html is used as is (build it with ConvertTo-OneHtml / New-OneLink). -Bold wraps it in
       bold. -List bullet|number makes it a OneNote list item (-Number = its place, from 1).
       -Table @{ header = @(cell html); rows = @(@(cell html)) } makes the line a OneNote table. #>
    param([string]$Text = '', [string]$Html = '', [object[]]$Children = @(), [switch]$Bold, [switch]$Collapsed,
        [ValidateSet('', 'bullet', 'number')][string]$List = '', [int]$Number = 1, $Table = $null)
    $h = if ($Html) { $Html } else { ConvertTo-OneHtml $Text }
    if ($Bold) { $h = "<span style='font-weight:bold'>$h</span>" }
    @{ html = $h; children = @($Children); collapsed = [bool]$Collapsed; list = $List; number = $Number; table = $Table }
}

function ConvertTo-OneTableXml($Table) {
    <# A OneNote table: header row in bold, then the rows; every row as wide as the widest. #>
    $header = @($Table['header'])
    $rows = @($Table['rows'])
    $cols = $header.Count
    foreach ($r in $rows) { if (@($r).Count -gt $cols) { $cols = @($r).Count } }
    if ($cols -lt 1) { return '' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<one:Table bordersVisible="true"><one:Columns>')
    for ($c = 0; $c -lt $cols; $c++) { [void]$sb.Append('<one:Column index="' + $c + '" width="120"/>') }
    [void]$sb.Append('</one:Columns>')
    $all = @(, @($header | ForEach-Object { "<span style='font-weight:bold'>$_</span>" })) + @($rows)
    foreach ($r in $all) {
        [void]$sb.Append('<one:Row>')
        $cells = @($r)
        for ($c = 0; $c -lt $cols; $c++) {
            $cell = if ($c -lt $cells.Count) { ([string]$cells[$c]).Replace(']]>', ']]&gt;') } else { '' }
            [void]$sb.Append("<one:Cell><one:OEChildren><one:OE><one:T><![CDATA[$cell]]></one:T></one:OE></one:OEChildren></one:Cell>")
        }
        [void]$sb.Append('</one:Row>')
    }
    [void]$sb.Append('</one:Table>')
    $sb.ToString()
}

function ConvertTo-OEXml {
    param([object[]]$Lines)
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in @($Lines)) {
        if ($null -eq $l) { continue }
        if ($l -is [string]) { $l = @{ html = (ConvertTo-OneHtml $l); children = @(); collapsed = $false } }
        $kids = @($l['children'] | Where-Object { $null -ne $_ })
        $col = if ($l['collapsed'] -and $kids.Count) { ' collapsed="true"' } else { '' }
        [void]$sb.Append("<one:OE$col>")
        # OneNote schema order inside an OE: List before the content (T or Table), OEChildren last.
        if ($l['list'] -eq 'bullet') { [void]$sb.Append('<one:List><one:Bullet bullet="2" fontSize="11.0"/></one:List>') }
        elseif ($l['list'] -eq 'number') {
            $n = [Math]::Max(1, [int]$l['number'])
            [void]$sb.Append('<one:List><one:Number numberSequence="0" numberFormat="##." fontSize="11.0" text="' + $n + '."/></one:List>')
        }
        if ($l['table']) { [void]$sb.Append((ConvertTo-OneTableXml $l['table'])) }
        else {
            $html = ([string]$l['html']).Replace(']]>', ']]&gt;')
            [void]$sb.Append("<one:T><![CDATA[$html]]></one:T>")
        }
        if ($kids.Count) { [void]$sb.Append('<one:OEChildren>' + (ConvertTo-OEXml $kids) + '</one:OEChildren>') }
        [void]$sb.Append('</one:OE>')
    }
    $sb.ToString()
}

function New-ObsnOutlineXml {
    <# An outline owned by ObsidiNote: <one:Outline [objectID]><one:Meta obsn.role/>...</one:Outline>.
       $Lines: strings (plain text) or New-OneLine objects. #>
    param([Parameter(Mandatory)][string]$Role, [object[]]$Lines = @(), [string]$ObjectId = '')
    $id = if ($ObjectId) { ' objectID="' + (ConvertTo-XmlAttr $ObjectId) + '"' } else { '' }
    $body = ConvertTo-OEXml @($Lines)
    if (-not $body) { $body = '<one:OE><one:T><![CDATA[]]></one:T></one:OE>' }
    "<one:Outline$id><one:Meta name=""obsn.role"" content=""$(ConvertTo-XmlAttr $Role)"" /><one:OEChildren>$body</one:OEChildren></one:Outline>"
}

function New-ObsnPageXml {
    <# Update XML for UpdatePageContent: Meta tags, optional title, owned outlines. Meta first, then
       Title, then outlines (2013 schema order). Only what is passed changes; other outlines stay.
       $Outlines: @(@{ role; lines; objectId }). #>
    param(
        [Parameter(Mandatory)][string]$PageId,
        [System.Collections.IDictionary]$Meta = @{},
        [string]$Title = $null,
        [object[]]$Outlines = @()
    )
    $ns = Get-OneNoteSchemaNs
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0"?>')
    [void]$sb.Append("<one:Page xmlns:one=""$ns"" ID=""$(ConvertTo-XmlAttr $PageId)"">")
    foreach ($k in @($Meta.Keys)) {
        [void]$sb.Append("<one:Meta name=""$(ConvertTo-XmlAttr ([string]$k))"" content=""$(ConvertTo-XmlAttr ([string]$Meta[$k]))"" />")
    }
    if ($null -ne $Title -and $PSBoundParameters.ContainsKey('Title')) {
        [void]$sb.Append('<one:Title><one:OE><one:T><![CDATA[' + (ConvertTo-OneHtml $Title) + ']]></one:T></one:OE></one:Title>')
    }
    foreach ($o in @($Outlines)) {
        if ($null -eq $o) { continue }
        $oid = if ($o.ContainsKey('objectId')) { [string]$o['objectId'] } else { '' }
        [void]$sb.Append((New-ObsnOutlineXml -Role $o['role'] -Lines @($o['lines']) -ObjectId $oid))
    }
    [void]$sb.Append('</one:Page>')
    $sb.ToString()
}

function ConvertFrom-ObsnPageXml {
    <# GetPageContent XML -> @{ pageId; title; meta (page-level Meta name -> content);
       outlines = @(@{ role; objectId }) } (role '' for outlines ObsidiNote does not own). Pure. #>
    param([Parameter(Mandatory)][string]$Xml)
    [xml]$doc = $Xml
    $ns = New-OneNoteNsManager $doc
    $page = $doc.DocumentElement
    $meta = @{}
    foreach ($m in @($page.SelectNodes('one:Meta', $ns))) { $meta[$m.GetAttribute('name')] = $m.GetAttribute('content') }
    $t = $page.SelectSingleNode('one:Title//one:T', $ns)
    $title = if ($t) { [regex]::Replace($t.InnerText, '<[^>]+>', '') } else { '' }
    $outs = @(foreach ($o in @($page.SelectNodes('one:Outline', $ns))) {
        $r = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $ns)
        @{ role = $(if ($r) { $r.GetAttribute('content') } else { '' }); objectId = $o.GetAttribute('objectID') }
    })
    @{ pageId = $page.GetAttribute('ID'); title = [System.Net.WebUtility]::HtmlDecode($title); meta = $meta; outlines = $outs }
}

function ConvertFrom-OneT {
    <# The plain text of a one:T element: its HTML fragment without tags, entities decoded. #>
    param($Node)
    [System.Net.WebUtility]::HtmlDecode([regex]::Replace([string]$Node.InnerText, '<[^>]+>', ''))
}

function ConvertFrom-ObsnPageText {
    <# GetPageContent XML -> @{ title; outlines = @(@{ role; objectId; text }) } with each outline's
       text, one line per paragraph in page order (children after their parent). Pure; the text
       stays in memory (Ask reads pages with it, the link Update compares the summary outline). #>
    param([Parameter(Mandatory)][string]$Xml)
    [xml]$doc = $Xml
    $ns = New-OneNoteNsManager $doc
    $page = $doc.DocumentElement
    $t = $page.SelectSingleNode('one:Title//one:T', $ns)
    $outs = @(foreach ($o in @($page.SelectNodes('one:Outline', $ns))) {
        $r = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $ns)
        $lines = @(foreach ($n in @($o.SelectNodes('.//one:OE/one:T', $ns))) { ConvertFrom-OneT $n })
        @{ role = $(if ($r) { $r.GetAttribute('content') } else { '' }); objectId = $o.GetAttribute('objectID'); text = ($lines -join "`n") }
    })
    @{ title = $(if ($t) { ConvertFrom-OneT $t } else { '' }); outlines = $outs }
}

function Get-PropertiesLines {
    <# The readable properties outline of a content page. #>
    param([Parameter(Mandatory)][hashtable]$Page)
    $lines = @()
    if ($Page['type']) { $lines += "type: $($Page['type'])" }
    $tp = @(@($Page['topics']) | Where-Object { $_ })
    if ($tp.Count) { $lines += 'topics: ' + (($tp | ForEach-Object { Format-TopicPath $_ }) -join '; ') }
    $al = @(@($Page['aliases']) | Where-Object { $_ })
    if ($al.Count) { $lines += 'aliases: ' + ($al -join ', ') }
    $tg = @(@($Page['tags']) | Where-Object { $_ })
    if ($tg.Count) { $lines += 'tags: ' + ($tg -join ', ') }
    if ($Page['url']) { $lines += "link: $($Page['url'])" }
    if ($Page['status']) { $lines += "status: $($Page['status'])" }
    if ($Page['id']) { $lines += "id: $($Page['id'])" }
    , $lines
}

function Get-LinkedFromLines {
    <# The "Linked from" outline: @(@{ title; link }) sorted by title. #>
    param([object[]]$Sources = @())
    $l = @(New-OneLine -Text 'Linked from:' -Bold)
    foreach ($s in @($Sources | Sort-Object { [string]$_['title'] })) { $l += New-OneLine -Html (New-OneLink -Href $s['link'] -Label $s['title']) }
    , $l
}

function Get-OneLinkPageGuid([string]$Text) {
    <# The page-id GUID of an onenote: link (also URL-encoded braces), lower case; '' without one. #>
    $m = [regex]::Match([string]$Text, '(?i)page-id=(?:%7B|\{)([0-9a-f-]{36})(?:%7D|\})')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    ''
}

function Get-OneLinkText([string]$Inner) {
    <# The plain text of a link's inner HTML: tags left out, entities decoded, spaces folded. #>
    ([System.Net.WebUtility]::HtmlDecode(($Inner -replace '<[^>]*>', '')) -replace '\s+', ' ').Trim()
}

function Repair-ObsnBodyLinks {
    <# Upgrade step body-links (lib/Upgrade.psm1): links in ObsidiNote's own body outline (obsn.role =
       body only, never "Your notes" or an outline without a role) that a page moved away from before
       moves re-pointed them (target machine, 2026-11-16). A link is re-pointed only when BOTH hold:
       its page-id is not one of $LiveGuids (no page has it any more), and its text is a name of
       exactly one of $Targets (@(@{ link; names = @(title, aliases) }), the pages this page links to
       in its own Meta), compared without case. It then points at that target's link and keeps its
       text. Returns @{ count; xml } as Convert-ObsnBodyLinks. Pure. #>
    param([Parameter(Mandatory)][string]$Xml, [object[]]$Targets = @(), $LiveGuids)
    $byName = @{}
    foreach ($t in @($Targets | Where-Object { $_ -and $_['link'] })) {
        foreach ($n in @($t['names'] | Where-Object { $_ })) {
            $k = ([string]$n -replace '\s+', ' ').Trim().ToLowerInvariant()
            if (-not $k) { continue }
            if ($byName.ContainsKey($k) -and $byName[$k] -ne [string]$t['link']) { $byName[$k] = '' } else { $byName[$k] = [string]$t['link'] }
        }
    }
    if (-not $byName.Count) { return @{ count = 0; xml = '' } }
    Edit-ObsnBodyAnchors -Xml $Xml -OnLink {
        param($Href, $Inner)
        $g = Get-OneLinkPageGuid $Href
        if (-not $g -or ($LiveGuids -and $LiveGuids.Contains($g))) { return $null }
        $to = $byName[(Get-OneLinkText $Inner).ToLowerInvariant()]
        if ($to) { @{ href = $to } } else { $null }
    }
}

function Convert-ObsnBodyLinks {
    <# Delete and archive invariants (AGENTS.md, Archive and delete): in the page XML of GetPageContent,
       every link to the page $TargetLink (an onenote: link; matched as written or by its page-id GUID)
       inside an outline ObsidiNote owns with obsn.role = body becomes the plain text $Text (the page
       was deleted), or with -NewLink keeps its text and points at $NewLink (the page moved: OneNote
       gave it a new link; a link already pointing there is left as it is). Outlines with any other
       role ("Your notes" = notes among them) and outlines without a role are never read for it or
       returned. Returns @{ count (links changed); xml (the update for UpdatePageContent: the page with
       only the changed body outlines, each whole and by its objectID; '' when count is 0) }. Pure. #>
    param([Parameter(Mandatory)][string]$Xml, [Parameter(Mandatory)][string]$TargetLink, [string]$Text = '', [string]$NewLink = '')
    if (-not $NewLink -and -not $Text) { throw 'Convert-ObsnBodyLinks needs -Text or -NewLink' }
    $guid = Get-OneLinkPageGuid $TargetLink
    $plain = ConvertTo-OneHtml $Text
    Edit-ObsnBodyAnchors -Xml $Xml -OnLink {
        param($Href, $Inner)
        if ($NewLink -and $Href -eq $NewLink) { return $null }
        $g = Get-OneLinkPageGuid $Href
        if (-not (($guid -and $g -eq $guid) -or $Href -eq $TargetLink)) { return $null }
        if ($NewLink) { @{ href = $NewLink } } else { @{ html = $plain } }
    }
}

function Edit-ObsnBodyAnchors {
    <# The one walk over links in ObsidiNote's own body outline (obsn.role = body; outlines with any
       other role, "Your notes" among them, and outlines without a role are never read or returned),
       for Convert-ObsnBodyLinks and Repair-ObsnBodyLinks. $OnLink gets each link's address (decoded)
       and inner HTML and returns $null (keep it), @{ href = <new address> } (keep the link's text and
       attributes, change only its address) or @{ html = <replacement> } (the whole link). The block
       runs in this module's call chain, so it sees its caller's variables (no GetNewClosure: a closure
       made here could not see this module's functions). Returns @{ count (links changed); xml (the
       update for UpdatePageContent: the page with only the changed body outlines, each whole and by
       its objectID; '' when count is 0) }. Pure. #>
    param([Parameter(Mandatory)][string]$Xml, [Parameter(Mandatory)][scriptblock]$OnLink)
    [xml]$doc = $Xml
    $ns = New-OneNoteNsManager $doc
    $page = $doc.DocumentElement
    $state = @{ n = 0 }
    $eval = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $res = & $OnLink ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) $m.Groups[2].Value
        if (-not $res) { return $m.Value }
        $state.n++
        if (-not $res.ContainsKey('href')) { return [string]$res['html'] }
        $at = $m.Groups[1].Index - $m.Index
        $m.Value.Substring(0, $at) + (ConvertTo-OneHref ([string]$res['href'])) + $m.Value.Substring($at + $m.Groups[1].Length)
    }
    $rx = New-Object System.Text.RegularExpressions.Regex ('<a\b[^>]*?\bhref\s*=\s*"([^"]*)"[^>]*>(.*?)</a>', ([System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Singleline'))
    $changed = @()
    foreach ($o in @($page.SelectNodes('one:Outline', $ns))) {
        $r = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $ns)
        if (-not $r -or $r.GetAttribute('content') -ne 'body') { continue }
        $before = $state.n
        foreach ($t in @($o.SelectNodes('.//one:T', $ns))) {
            $old = [string]$t.InnerText
            if ($old -notmatch '(?i)<a\b') { continue }
            $new = $rx.Replace($old, $eval)
            # Only the text is replaced: the element keeps its attributes (lang, style).
            if ($new -ne $old) { foreach ($c in @($t.ChildNodes)) { $null = $t.RemoveChild($c) }; $null = $t.AppendChild($doc.CreateCDataSection($new.Replace(']]>', ']]&gt;'))) }
        }
        if ($state.n -gt $before) { $changed += $o }
    }
    if (-not $state.n) { return @{ count = 0; xml = '' } }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0"?>')
    [void]$sb.Append("<one:Page xmlns:one=""$(Get-OneNoteSchemaNs)"" ID=""$(ConvertTo-XmlAttr $page.GetAttribute('ID'))"">")
    foreach ($o in $changed) { [void]$sb.Append($o.OuterXml) }
    [void]$sb.Append('</one:Page>')
    @{ count = $state.n; xml = $sb.ToString() }
}

# ---------------------------------------------------------------- journal day pages (operator, 2026-11-17)
# One page per day: each journal Add is one entry = one top-level OE of the page's body outline (a bold
# "HH:mm  title" line with the entry's text under it), and one item of the page's obsn.entries Meta, in
# the same order. Both helpers send the body outline whole by its objectID, with the other entries as
# read (their own objectIDs), the way Edit-ObsnBodyAnchors rewrites links (verified live 2026-11-16).

function Get-ObsnBodyOutline($Doc, $Ns) {
    foreach ($o in @($Doc.DocumentElement.SelectNodes('one:Outline', $Ns))) {
        $r = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $Ns)
        if ($r -and $r.GetAttribute('content') -eq 'body') { return $o }
    }
    $null
}

function New-ObsnBodyUpdateXml($Doc, $Outline, [System.Collections.IDictionary]$Meta) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0"?>')
    [void]$sb.Append("<one:Page xmlns:one=""$(Get-OneNoteSchemaNs)"" ID=""$(ConvertTo-XmlAttr $Doc.DocumentElement.GetAttribute('ID'))"">")
    foreach ($k in @($Meta.Keys)) { [void]$sb.Append("<one:Meta name=""$(ConvertTo-XmlAttr ([string]$k))"" content=""$(ConvertTo-XmlAttr ([string]$Meta[$k]))"" />") }
    [void]$sb.Append($Outline.OuterXml)
    [void]$sb.Append('</one:Page>')
    $sb.ToString()
}

function Get-ObsnEntryHeading {
    <# The first line of a journal entry, as plain text: "HH:mm  title". Pure. #>
    param([string]$At, [string]$Title)
    $hm = if ($At -match 'T(\d\d:\d\d)') { $Matches[1] } else { '' }
    (($hm + '  ' + $Title).Trim())
}

function Add-ObsnBodyEntry {
    <# Appends one entry (New-OneLine objects: the heading line with the entry's lines as its children)
       to the end of the page's body outline. Returns @{ ok; reason; xml (the update for UpdatePageContent:
       $Meta and the body outline whole) }. Pure. #>
    param([Parameter(Mandatory)][string]$Xml, [Parameter(Mandatory)][object[]]$Lines, [System.Collections.IDictionary]$Meta = @{})
    [xml]$doc = $Xml
    $ns = New-OneNoteNsManager $doc
    $o = Get-ObsnBodyOutline $doc $ns
    if (-not $o) { return @{ ok = $false; reason = 'the day page has no text outline of ObsidiNote''s'; xml = '' } }
    $kids = $o.SelectSingleNode('one:OEChildren', $ns)
    if (-not $kids) { $kids = $o.AppendChild($doc.CreateElement('one', 'OEChildren', (Get-OneNoteSchemaNs))) }
    $frag = [xml]("<x xmlns:one=""$(Get-OneNoteSchemaNs)"">" + (ConvertTo-OEXml @($Lines)) + '</x>')
    foreach ($n in @($frag.DocumentElement.ChildNodes)) { $null = $kids.AppendChild($doc.ImportNode($n, $true)) }
    @{ ok = $true; reason = ''; xml = (New-ObsnBodyUpdateXml $doc $o $Meta) }
}

function Remove-ObsnBodyEntry {
    <# Takes entry number $Index (0-based, the order of obsn.entries) out of the body outline, only when
       that top-level line still starts with $Heading; else nothing (the page was changed in OneNote: its
       lines no longer match the entries). Returns @{ ok; reason; xml }. Pure. #>
    param([Parameter(Mandatory)][string]$Xml, [Parameter(Mandatory)][int]$Index, [Parameter(Mandatory)][string]$Heading, [System.Collections.IDictionary]$Meta = @{})
    [xml]$doc = $Xml
    $ns = New-OneNoteNsManager $doc
    $o = Get-ObsnBodyOutline $doc $ns
    $oes = if ($o) { @($o.SelectNodes('one:OEChildren/one:OE', $ns)) } else { @() }
    if ($Index -lt 0 -or $Index -ge $oes.Count) { return @{ ok = $false; reason = 'the entry is not on the day page any more'; xml = '' } }
    $t = $oes[$Index].SelectSingleNode('one:T', $ns)
    $text = if ($t) { [System.Net.WebUtility]::HtmlDecode(($t.InnerText -replace '<[^>]+>', '')).Trim() } else { '' }
    $norm = { param($s) ($s -replace '\s+', ' ').Trim() }
    if (-not (& $norm $text).StartsWith((& $norm $Heading))) { return @{ ok = $false; reason = 'the day page was changed in OneNote, so the entry was not found where it was written'; xml = '' } }
    $null = $oes[$Index].ParentNode.RemoveChild($oes[$Index])
    if (-not @($o.SelectNodes('one:OEChildren/one:OE', $ns)).Count) { $null = $o.SelectSingleNode('one:OEChildren', $ns).AppendChild($doc.ImportNode(([xml]("<x xmlns:one=""$(Get-OneNoteSchemaNs)"">" + (ConvertTo-OEXml @('')) + '</x>')).DocumentElement.FirstChild, $true)) }
    @{ ok = $true; reason = ''; xml = (New-ObsnBodyUpdateXml $doc $o $Meta) }
}

function Read-ObsnPage {
    <# Reads a page through the adapter and parses it (page XML stays in memory). #>
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$PageId)
    ConvertFrom-ObsnPageXml -Xml ($Adapter.GetPageContent($PageId))
}

function Write-ObsnPage {
    <# Writes Meta, the title (when given) and owned outlines to a page. An outline whose role already
       exists on the page is rewritten in place (its objectID); outlines without obsn.role are never
       touched. $Outlines: @(@{ role; lines }). #>
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$PageId, [System.Collections.IDictionary]$Meta = @{}, [string]$Title = $null, [object[]]$Outlines = @(), [switch]$NewPage)
    if (-not $NewPage) {
        foreach ($o in @($Outlines)) { if ($o -and $script:WriteOnceRoles -contains [string]$o['role']) { throw "The '$($o['role'])' outline is written once, when the page is made, and never rewritten." } }
    }
    $existing = @{}
    if (-not $NewPage -and @($Outlines).Count) {
        $p = Read-ObsnPage -Adapter $Adapter -PageId $PageId
        foreach ($o in $p.outlines) { if ($o.role -and -not $existing.ContainsKey($o.role)) { $existing[$o.role] = $o.objectId } }
    }
    $outs = @(foreach ($o in @($Outlines)) {
        if ($null -eq $o) { continue }
        @{ role = $o['role']; lines = @($o['lines']); objectId = $(if ($existing.ContainsKey($o['role'])) { $existing[$o['role']] } else { '' }) }
    })
    $args2 = @{ PageId = $PageId; Meta = $Meta; Outlines = $outs }
    if ($PSBoundParameters.ContainsKey('Title') -and $null -ne $Title) { $args2.Title = $Title }
    $Adapter.UpdatePageContent((New-ObsnPageXml @args2))
}

Export-ModuleMember -Function Get-ObsnRoles, Get-ObsnMetaKeys, ConvertTo-Base36, ConvertFrom-Base36, New-ObsnId, Test-ObsnId, Get-ObsnIdNumber, ConvertTo-TopicPath, Format-TopicPath, ConvertTo-CompactJson, Get-JsonProp, ConvertFrom-JsonList, ConvertTo-ObsnLinksValue, ConvertFrom-ObsnLinksValue, ConvertTo-ObsnMeta, ConvertFrom-ObsnMeta, Split-ObsnMetaValue, Join-ObsnMetaValue, ConvertTo-OneHtml, New-OneLink, New-OneLine, New-ObsnOutlineXml, New-ObsnPageXml, ConvertFrom-ObsnPageXml, ConvertFrom-ObsnPageText, Get-PropertiesLines, Get-LinkedFromLines, Read-ObsnPage, Write-ObsnPage, ConvertTo-TagList, Convert-ObsnBodyLinks, Repair-ObsnBodyLinks, Get-OneLinkPageGuid, ConvertTo-ObsnEntriesValue, ConvertFrom-ObsnEntriesValue, Get-ObsnEntryHeading, Add-ObsnBodyEntry, Remove-ObsnBodyEntry
