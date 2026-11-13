# Markdown export (user, 2026-11-13): pages of a vault or notebook as Markdown with [[wikilinks]].
# The one way content leaves OneNote, and only as a download the person asks for: the files are
# built in memory (a zip in a MemoryStream) and handed to the browser; nothing is written to disk
# here and nothing is kept. The log gets counts and timings only.
#   - one .md per page: YAML front matter (id, type, title, topics, aliases, url, summary, status,
#     links as [[wikilinks]], the onenote: link), then the page's outlines as Markdown. ObsidiNote's
#     generated outlines (properties, "Linked from") are left out: front matter and a Markdown
#     editor's own backlinks show the same.
#   - a link to another page of the same model becomes [[File name|text]]; file names are unique
#     per model (the title, else " (id)" added), so wikilinks resolve in a Markdown editor.
#   - folders follow the page's first topic path; no topic = Unfiled.
#   - images, ink and attached files are not exported; a line says so where they were.
# PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')

$script:SkipRoles = @('props', 'backlinks', 'index', 'state')
$script:LeftOut = '_(An image, drawing or attached file is left out of the export.)_'

# --- names --------------------------------------------------------------------------------------

function ConvertTo-SafeName {
    <# A file or folder name for Windows and Markdown editors: no \/:*?"<>|#^[] or control characters,
       spaces collapsed, no trailing dot or space, at most $Max characters, never empty. #>
    param([string]$Name, [int]$Max = 100)
    $s = ($Name -replace '[\\/:*?"<>|#^\[\]\x00-\x1f]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.').Trim()
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max).TrimEnd().TrimEnd('.') }
    if (-not $s -or $s -match '^(?i)(con|prn|aux|nul|com\d|lpt\d)$') { $s = "_$s" }
    $s
}

function Get-ExportNames {
    <# File base name per model key (unique, case-insensitive), from the title; a clash gets the id. #>
    param([Parameter(Mandatory)]$Model)
    $names = @{}
    $used = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $keys = @($Model.pages.Keys | Sort-Object)
    foreach ($k in $keys) {
        $p = $Model.pages[$k]
        $base = ConvertTo-SafeName $(if ($p.title) { [string]$p.title } else { 'Untitled page' })
        $n = $base
        if (-not $used.Add($n)) {
            # A clash: the page's id (an obsn id like p12, or the start of a OneNote id), then a counter.
            $short = ($k -replace '^n:', '' -replace '[^A-Za-z0-9]', '')
            if ($short.Length -gt 8) { $short = $short.Substring(0, 8) }
            $n = "$base ($short)"
            $i = 2
            while (-not $used.Add($n)) { $n = "$base ($short $i)"; $i++ }
        }
        $names[$k] = $n
    }
    $names
}

function Get-ExportFolder {
    <# The folder of a page: its first topic path, each part a safe name; no topic = Unfiled. #>
    param($Page)
    $t = @(@($Page.topics) | Where-Object { $_ }) | Select-Object -First 1
    if (-not $t) { return 'Unfiled' }
    (@(([string]$t).Split('/') | Where-Object { $_ } | ForEach-Object { ConvertTo-SafeName $_ 60 }) -join '/')
}

function Get-LinkTargets {
    <# href -> file name, for the links in page text: the page's onenote: link as written, and its
       OneNote page id (page-id={...} in a link, or the id itself). #>
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][hashtable]$Names)
    $map = @{}
    foreach ($k in $Model.pages.Keys) {
        $p = $Model.pages[$k]
        if ($p.link) { $map[[string]$p.link] = $Names[$k] }
        $g = Get-PageGuid ([string]$p.link)
        if (-not $g) { $g = Get-PageGuid ([string]$p.oneNoteId) }
        if ($g) { $map["guid:$g"] = $Names[$k] }
        if ($p.id) { $map["onenote:#$($p.id)"] = $Names[$k] }
    }
    $map
}

function Get-PageGuid([string]$Text) {
    $m = [regex]::Match($Text, '(?i)page-id=\{([0-9a-f-]{36})\}')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    $m = [regex]::Match($Text, '^\{([0-9A-Fa-f-]{36})\}')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    ''
}

# --- inline: the HTML of one one:T -----------------------------------------------------------------

function ConvertTo-MdText([string]$Text, [bool]$Code) {
    if ($Code) { return $Text }
    $Text -replace '([\\`*_\[\]])', '\$1'
}

function ConvertFrom-OneHtml {
    <# The HTML of a one:T (spans with styles, links, br) as Markdown inline text. Bold, italic,
       strikethrough and Consolas (code) spans become **, *, ~~ and backticks; a link to a page in
       $Targets becomes [[name|text]], other http(s)/mailto links [text](url); other tags are
       dropped, their text kept. #>
    param([string]$Html, [hashtable]$Targets = @{})
    $sb = New-Object Text.StringBuilder
    $open = New-Object System.Collections.Generic.List[object]   # @{ tag; close; at; href }
    $code = 0
    foreach ($m in [regex]::Matches($Html, '<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)/?>|([^<]+)')) {
        if ($m.Groups[4].Success) { [void]$sb.Append((ConvertTo-MdText ([Net.WebUtility]::HtmlDecode($m.Groups[4].Value)) ($code -gt 0))); continue }
        $tag = $m.Groups[2].Value.ToLowerInvariant()
        $attrs = $m.Groups[3].Value
        if ($tag -eq 'br') { [void]$sb.Append(' '); continue }
        if ($m.Groups[1].Value -ne '/') {
            if ($tag -eq 'a') {
                $h = [regex]::Match($attrs, '(?i)href\s*=\s*(?:"([^"]*)"|''([^'']*)'')')
                $href = if ($h.Success) { [Net.WebUtility]::HtmlDecode($h.Groups[1].Value + $h.Groups[2].Value) } else { '' }
                $open.Add(@{ tag = 'a'; close = ''; at = $sb.Length; href = $href }); continue
            }
            if ($tag -ne 'span') { $open.Add(@{ tag = $tag; close = ''; at = $sb.Length; href = '' }); continue }
            $mark = ''
            if ($attrs -match '(?i)font-family:\s*[''"]?Consolas') { $mark = '`'; $code++ }
            else {
                if ($attrs -match '(?i)font-weight:\s*bold') { $mark += '**' }
                if ($attrs -match '(?i)font-style:\s*italic') { $mark += '*' }
                if ($attrs -match '(?i)line-through') { $mark += '~~' }
            }
            [void]$sb.Append($mark)
            $open.Add(@{ tag = 'span'; close = $mark; at = $sb.Length; href = '' })
            continue
        }
        # A closing tag: the innermost open one of that name.
        $i = $open.Count - 1
        while ($i -ge 0 -and $open[$i].tag -ne $tag) { $i-- }
        if ($i -lt 0) { continue }
        $o = $open[$i]; $open.RemoveAt($i)
        if ($tag -eq 'a') { Complete-MdLink $sb $o $Targets; continue }
        if ($o.close -eq '`') { $code-- }
        if (-not $o.close) { continue }
        if ($sb.Length -eq $o.at) { [void]$sb.Remove($o.at - $o.close.Length, $o.close.Length); continue }
        $rev = -join @($o.close.ToCharArray()[($o.close.Length - 1)..0])
        [void]$sb.Append($rev)
    }
    ($sb.ToString() -replace '\s+$', '')
}

function Complete-MdLink($Sb, $Open, [hashtable]$Targets) {
    $text = $Sb.ToString($Open.at, $Sb.Length - $Open.at)
    $href = [string]$Open.href
    $name = ''
    if ($href) {
        if ($Targets.ContainsKey($href)) { $name = $Targets[$href] }
        else { $g = Get-PageGuid $href; if ($g -and $Targets.ContainsKey("guid:$g")) { $name = $Targets["guid:$g"] } }
    }
    if ($name) {
        $plain = $text -replace '\\([\\`*_\[\]])', '$1'
        $link = if ($plain -eq $name -or -not $plain.Trim()) { "[[$name]]" } else { "[[$name|$($plain -replace '[\[\]|]', ' ')]]" }
    } elseif ($href -match '^(?i)(https?:|mailto:)') {
        $link = if ($text.Trim()) { "[$text](<$href>)" } else { "<$href>" }
    } else { return }
    [void]$Sb.Remove($Open.at, $Sb.Length - $Open.at)
    [void]$Sb.Append($link)
}

# --- blocks: outlines, OEs, lists, tables -------------------------------------------------------------

function Get-OneNs($Doc) {
    $ns = New-Object Xml.XmlNamespaceManager $Doc.NameTable
    $ns.AddNamespace('one', $Doc.DocumentElement.NamespaceURI)
    , $ns
}

function Get-HeadingStyles($Doc, $Ns) {
    <# quickStyleIndex -> heading level (h1..h6) from the page's QuickStyleDefs. #>
    $h = @{}
    foreach ($q in @($Doc.DocumentElement.SelectNodes('one:QuickStyleDef', $Ns))) {
        if ($q.GetAttribute('name') -match '^h([1-6])$') { $h[$q.GetAttribute('index')] = [int]$Matches[1] }
    }
    $h
}

function ConvertFrom-OneOE {
    <# One one:OE (and its children) as blocks @{ kind = list|para|table; text }. $Indent: the
       indentation of a list item nested under another list item. #>
    param($OE, $Ns, [hashtable]$Ctx, [string]$Indent, [ref]$Number)
    $out = New-Object System.Collections.Generic.List[object]
    $list = $OE.SelectSingleNode('one:List', $Ns)
    $t = $OE.SelectSingleNode('one:T', $Ns)
    $table = $OE.SelectSingleNode('one:Table', $Ns)
    $isList = $false
    if ($table) {
        $out.Add(@{ kind = 'table'; text = (ConvertFrom-OneTable $table $Ns $Ctx) })
    } elseif ($t) {
        $html = $t.InnerText
        $text = ConvertFrom-OneHtml -Html $html -Targets $Ctx.targets
        $style = $OE.GetAttribute('quickStyleIndex')
        # ObsidiNote's own headings (lib/VaultStore.psm1): a bold line in 16/14/12 pt. It writes a size
        # span; OneNote stores the size on the line's style instead (seen live, 2026-11-13). A line
        # only counts when it is bold as a whole, so ordinary 12 pt text stays a paragraph.
        $size = [regex]::Match($html, "^(?:<span style=['""]font-weight:\s*bold;?['""]>)?<span style=['""][^'""]*font-size:\s*(16|14|12)(?:\.0)?pt")
        if (-not $size.Success) { $size = [regex]::Match(($OE.GetAttribute('style') + ';' + $t.GetAttribute('style')), 'font-size:\s*(16|14|12)(?:\.0)?pt') }
        $whole = $text.Length -gt 4 -and $text.StartsWith('**') -and $text.EndsWith('**') -and $text.IndexOf('**', 2) -eq ($text.Length - 2)
        if (-not $list -and $size.Success -and $whole) {
            $level = @{ '16' = 1; '14' = 2; '12' = 3 }[[string]$size.Groups[1].Value]
            $out.Add(@{ kind = 'para'; text = ('#' * $level) + ' ' + $text.Substring(2, $text.Length - 4) }); $text = ''
        }
        if ($list -and $list.SelectSingleNode('one:Number', $Ns)) { $Number.Value++; $out.Add(@{ kind = 'list'; text = "$Indent$($Number.Value). $text" }); $isList = $true }
        elseif ($list) {
            $box = if ($text -match "^[$([char]0x2610)]\s*") { '[ ] ' } elseif ($text -match "^[$([char]0x2611)$([char]0x2612)]\s*") { '[x] ' } else { '' }
            if ($box) { $text = $text -replace "^[$([char]0x2610)$([char]0x2611)$([char]0x2612)]\s*", '' }
            $out.Add(@{ kind = 'list'; text = "$Indent- $box$text" }); $isList = $true
        }
        elseif ($Ctx.headings.ContainsKey($style) -and $text) { $out.Add(@{ kind = 'para'; text = ('#' * $Ctx.headings[$style]) + ' ' + $text }) }
        elseif ($text) { $out.Add(@{ kind = 'para'; text = $text }) }
    } elseif ($OE.SelectSingleNode('one:Image|one:InkDrawing|one:InsertedFile|one:MediaFile', $Ns)) {
        $out.Add(@{ kind = 'para'; text = $script:LeftOut })
    }
    $kids = $OE.SelectSingleNode('one:OEChildren', $Ns)
    if ($kids) {
        $sub = if ($isList) { $Indent + '    ' } else { $Indent }
        foreach ($b in @(ConvertFrom-OneChildren $kids $Ns $Ctx $sub)) { $out.Add($b) }
    }
    $out.ToArray()
}

function ConvertFrom-OneChildren($Node, $Ns, [hashtable]$Ctx, [string]$Indent) {
    $n = 0
    $blocks = New-Object System.Collections.Generic.List[object]
    foreach ($oe in @($Node.SelectNodes('one:OE', $Ns))) {
        if (-not $oe.SelectSingleNode('one:List/one:Number', $Ns)) { $n = 0 }
        foreach ($b in @(ConvertFrom-OneOE $oe $Ns $Ctx $Indent ([ref]$n))) { $blocks.Add($b) }
    }
    $blocks.ToArray()
}

function ConvertFrom-OneTable($Table, $Ns, [hashtable]$Ctx) {
    $headerDone = $false
    $rows =@(foreach ($row in @($Table.SelectNodes('one:Row', $Ns))) {
        $cells = @(foreach ($c in @($row.SelectNodes('one:Cell', $Ns))) {
            $parts = @(foreach ($t in @($c.SelectNodes('.//one:T', $Ns))) { ConvertFrom-OneHtml -Html $t.InnerText -Targets $Ctx.targets })
            $cell = (($parts | Where-Object { $_ }) -join ' ') -replace '\|', '\|'
            # The header row is bold in OneNote; a Markdown header row is bold already.
            if (-not $headerDone -and $cell -match '^\*\*(.+)\*\*$') { $cell = $Matches[1] }
            $cell
        })
        $headerDone = $true
        , $cells
    })
    if (-not $rows.Count) { return '' }
    $w = ($rows | ForEach-Object { @($_).Count } | Measure-Object -Maximum).Maximum
    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $cells = @($rows[$i]) + @(1..$w | Select-Object -Skip @($rows[$i]).Count | ForEach-Object { '' })
        $lines.Add('| ' + (($cells | Select-Object -First $w) -join ' | ') + ' |')
        if ($i -eq 0) { $lines.Add('|' + ((@(1..$w) | ForEach-Object { ' --- ' }) -join '|') + '|') }
    }
    $lines -join "`n"
}

function Join-MdBlocks([object[]]$Blocks) {
    <# Blocks joined: list items line after line, anything else with a blank line between. #>
    $sb = New-Object Text.StringBuilder
    $prev = ''
    foreach ($b in @($Blocks)) {
        if (-not $b -or -not $b.text) { continue }
        if ($sb.Length) { [void]$sb.Append($(if ($prev -eq 'list' -and $b.kind -eq 'list') { "`n" } else { "`n`n" })) }
        [void]$sb.Append($b.text)
        $prev = $b.kind
    }
    $sb.ToString()
}

function ConvertFrom-OnePageXml {
    <# The Markdown body of one page (GetPageContent XML): every outline in page order, except the
       generated ones (obsn.role props, backlinks, index, state). $Targets: Get-LinkTargets. #>
    param([Parameter(Mandatory)][string]$Xml, [hashtable]$Targets = @{})
    [xml]$doc = $Xml
    $ns = Get-OneNs $doc
    $ctx = @{ targets = $Targets; headings = (Get-HeadingStyles $doc $ns) }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($o in @($doc.DocumentElement.SelectNodes('one:Outline', $ns))) {
        $role = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $ns)
        if ($role -and $script:SkipRoles -contains $role.GetAttribute('content')) { continue }
        $kids = $o.SelectSingleNode('one:OEChildren', $ns)
        if (-not $kids) { continue }
        $md = Join-MdBlocks (ConvertFrom-OneChildren $kids $ns $ctx '')
        if ($md) { $parts.Add($md) }
    }
    foreach ($x in @($doc.DocumentElement.SelectNodes('one:Image|one:InkDrawing|one:InsertedFile|one:MediaFile', $ns))) { $parts.Add($script:LeftOut); break }
    ($parts.ToArray() -join "`n`n")
}

# --- front matter and files ---------------------------------------------------------------------------

function ConvertTo-YamlString([string]$Text) {
    '"' + (($Text -replace '\s+', ' ').Trim() -replace '\\', '\\' -replace '"', '\"') + '"'
}

function New-FrontMatter {
    <# YAML front matter of a page: its index record, links as wikilinks to their file names. #>
    param($Page, [hashtable]$Names)
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add('---')
    $id = if ($Page.id) { [string]$Page.id } else { '' }
    if ($id) { $l.Add("id: $(ConvertTo-YamlString $id)") }
    if ($Page.type) { $l.Add("type: $(ConvertTo-YamlString ([string]$Page.type))") }
    $l.Add("title: $(ConvertTo-YamlString $(if ($Page.title) { [string]$Page.title } else { 'Untitled page' }))")
    foreach ($f in @(@{ k = 'topics'; v = @($Page.topics) }, @{ k = 'aliases'; v = @($Page.aliases) })) {
        $vals = @($f.v | Where-Object { $_ })
        if ($vals.Count) { $l.Add("$($f.k):"); foreach ($v in $vals) { $l.Add("  - $(ConvertTo-YamlString ([string]$v))") } }
    }
    if ($Page.url) { $l.Add("url: $(ConvertTo-YamlString ([string]$Page.url))") }
    if ($Page.summary) { $l.Add("summary: $(ConvertTo-YamlString ([string]$Page.summary))") }
    if ($Page.status) { $l.Add("status: $(ConvertTo-YamlString ([string]$Page.status))") }
    $links = @(foreach ($x in @($Page.links)) {
        if (-not $x) { continue }
        $t = [string](Get-JsonProp $x 'target' (Get-JsonProp $x 't' ''))
        if ($t -and $Names.ContainsKey($t)) { $Names[$t] }
    }) | Select-Object -Unique
    if (@($links).Count) { $l.Add('links:'); foreach ($n in $links) { $l.Add("  - $(ConvertTo-YamlString "[[$n]]")") } }
    if ([string]$Page.link -match '^(?i)onenote:') { $l.Add("onenote: $(ConvertTo-YamlString ([string]$Page.link))") }
    if ($Page.updated) { $l.Add("updated: $(ConvertTo-YamlString ([string]$Page.updated))") }
    $l.Add('---')
    $l.ToArray() -join "`n"
}

function Select-ExportPages {
    <# The model keys a scope covers: page (one key), topic (its pages and its subtopics' pages), all. #>
    param([Parameter(Mandatory)]$Model, [ValidateSet('page', 'topic', 'all')][string]$Scope, [string]$Key = '', [string]$Topic = '')
    switch ($Scope) {
        'page' { return @(@($Key) | Where-Object { $Model.pages.Contains($_) }) }
        'topic' {
            $pre = $Topic + '/'
            return @($Model.pages.Keys | Where-Object { @(@($Model.pages[$_].topics) | Where-Object { $_ -and ($_ -eq $Topic -or ([string]$_).StartsWith($pre)) }).Count } | Sort-Object)
        }
    }
    @($Model.pages.Keys | Sort-Object)
}

function New-MarkdownExport {
    <# The download for one export: @{ name; type; bytes; pages; leftOut } or @{ error }.
       $ReadPage { param($OneNoteId) } returns the page XML (GetPageContent). One page = one .md;
       a topic or everything = a zip with one folder named after the source, then topic folders. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][scriptblock]$ReadPage, [Parameter(Mandatory)][string]$SourceName,
        [ValidateSet('page', 'topic', 'all')][string]$Scope = 'all', [string]$Key = '', [string]$Topic = '')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $keys = @(Select-ExportPages -Model $Model -Scope $Scope -Key $Key -Topic $Topic)
    if (-not $keys.Count) { return @{ error = $(switch ($Scope) { 'page' { 'That page is not in this vault.' } 'topic' { 'That topic has no pages.' } default { 'There are no pages to export.' } }) } }
    $names = Get-ExportNames -Model $Model
    $targets = Get-LinkTargets -Model $Model -Names $names
    $files = New-Object System.Collections.Generic.List[object]
    $failed = 0
    foreach ($k in $keys) {
        $p = $Model.pages[$k]
        $body = ''
        try { if ($p.oneNoteId) { $body = ConvertFrom-OnePageXml -Xml ([string](& $ReadPage ([string]$p.oneNoteId))) -Targets $targets } }
        catch { $failed++; $body = '_(This page could not be read from OneNote for the export.)_' }
        $text = (New-FrontMatter -Page $p -Names $names) + "`n`n" + $body + "`n"
        $files.Add(@{ path = ((Get-ExportFolder $p) + '/' + $names[$k] + '.md'); name = $names[$k] + '.md'; text = $text })
    }
    $utf8 = New-Object Text.UTF8Encoding $false
    $src = ConvertTo-SafeName $SourceName 60
    if ($Scope -eq 'page') {
        $r = @{ name = $files[0].name; type = 'text/markdown; charset=utf-8'; bytes = $utf8.GetBytes($files[0].text); pages = 1; failed = $failed }
    } else {
        $label = if ($Scope -eq 'topic') { "$src - $(ConvertTo-SafeName (@($Topic.Split('/'))[-1]) 60)" } else { $src }
        $r = @{ name = "$label - Markdown.zip"; type = 'application/zip'; bytes = (New-ZipBytes -Files $files.ToArray() -Root $src); pages = $files.Count; failed = $failed }
    }
    Write-AppLog info export 'Markdown export' @{ scope = $Scope; pages = $r.pages; failed = $failed; bytes = $r.bytes.Length; ms = [int]$sw.ElapsedMilliseconds }
    $r
}

function New-ZipBytes {
    <# A zip in memory (entries "<root>/<path>", '/' separators); nothing touches the disk. #>
    param([object[]]$Files, [string]$Root)
    Add-Type -AssemblyName System.IO.Compression
    $utf8 = New-Object Text.UTF8Encoding $false
    $ms = New-Object IO.MemoryStream
    $zip = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($f in $Files) {
            $e = $zip.CreateEntry("$Root/$($f.path)", [IO.Compression.CompressionLevel]::Optimal)
            $s = $e.Open()
            try { $b = $utf8.GetBytes([string]$f.text); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
        }
    } finally { $zip.Dispose() }
    $out = $ms.ToArray()
    $ms.Dispose()
    , $out
}

Export-ModuleMember -Function ConvertTo-SafeName, Get-ExportNames, ConvertFrom-OneHtml, ConvertFrom-OnePageXml, New-FrontMatter, Select-ExportPages, New-MarkdownExport
