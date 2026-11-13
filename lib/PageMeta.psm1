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
$script:MetaKeys = @('id', 'type', 'topics', 'aliases', 'summary', 'links', 'status', 'url', 'host', 'kind', 'summarizedAt', 'archivedFrom', 'linkSummary', 'summaryHash', 'history', 'seenAt', 'checkStatus')
$script:ListKeys = @('topics', 'aliases')
# Values that can grow past one Meta tag: always written with their obsn.X.n part count.
$script:SplitKeys = @('linkSummary', 'history')
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
        elseif ($k -eq 'links') { $v = ConvertTo-ObsnLinksValue -Links @($v) }
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
        else { $r[$k] = if ($null -eq $v) { '' } else { [string]$v } }
    }
    $r
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

function New-OneLink {
    <# HTML fragment of a link. The href never contains a literal '>' so the CDATA stays closed. #>
    param([string]$Href, [string]$Label)
    if (-not $Href) { return (ConvertTo-OneHtml $Label) }
    '<a href="' + $Href.Replace('&', '&amp;').Replace('"', '&quot;').Replace('<', '&lt;').Replace('>', '&gt;') + '">' + (ConvertTo-OneHtml $Label) + '</a>'
}

function New-OneLine {
    <# A line for New-ObsnOutlineXml: @{ html; children; collapsed }. -Text is encoded, -Html is used
       as is (build it with ConvertTo-OneHtml / New-OneLink). -Bold wraps it in bold. #>
    param([string]$Text = '', [string]$Html = '', [object[]]$Children = @(), [switch]$Bold, [switch]$Collapsed)
    $h = if ($Html) { $Html } else { ConvertTo-OneHtml $Text }
    if ($Bold) { $h = "<span style='font-weight:bold'>$h</span>" }
    @{ html = $h; children = @($Children); collapsed = [bool]$Collapsed }
}

function ConvertTo-OEXml {
    param([object[]]$Lines)
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in @($Lines)) {
        if ($null -eq $l) { continue }
        if ($l -is [string]) { $l = @{ html = (ConvertTo-OneHtml $l); children = @(); collapsed = $false } }
        $kids = @($l['children'] | Where-Object { $null -ne $_ })
        $col = if ($l['collapsed'] -and $kids.Count) { ' collapsed="true"' } else { '' }
        $html = ([string]$l['html']).Replace(']]>', ']]&gt;')
        [void]$sb.Append("<one:OE$col><one:T><![CDATA[$html]]></one:T>")
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

Export-ModuleMember -Function Get-ObsnRoles, Get-ObsnMetaKeys, ConvertTo-Base36, ConvertFrom-Base36, New-ObsnId, Test-ObsnId, Get-ObsnIdNumber, ConvertTo-TopicPath, Format-TopicPath, ConvertTo-CompactJson, Get-JsonProp, ConvertFrom-JsonList, ConvertTo-ObsnLinksValue, ConvertFrom-ObsnLinksValue, ConvertTo-ObsnMeta, ConvertFrom-ObsnMeta, Split-ObsnMetaValue, Join-ObsnMetaValue, ConvertTo-OneHtml, New-OneLink, New-OneLine, New-ObsnOutlineXml, New-ObsnPageXml, ConvertFrom-ObsnPageXml, ConvertFrom-ObsnPageText, Get-PropertiesLines, Get-LinkedFromLines, Read-ObsnPage, Write-ObsnPage
