Set-StrictMode -Version 2.0
# Markdown text -> ObsidiNote's outline line model (pure; no OneNote access, nothing on disk).
# OneNote has no Markdown format (user question, 2026-11-13): pasted Markdown is turned into real
# OneNote formatting when a page is added. Anything not recognised stays plain text, so the original
# stays readable. Text without Markdown keeps the plain one-line-per-line behaviour.
#
# Line model (also read by lib/Ingest.psm1 Add-AnchorLinks and lib/VaultStore.psm1):
#   @{ parts = @(part); bold; collapsed; children = @(line); list = ''|'bullet'|'number';
#      heading = 0..6; quote = bool; code = bool; table = $null | @{ header = @(cell); rows = @(@(cell)) } }
#   part = @{ text; href; bold; italic; code; strike }   cell = @(part)
# Links keep only http(s), mailto and onenote addresses; any other target stays literal text.

$script:LinkSchemes = '^(?i)(https?://|mailto:|onenote:)'
$script:EscapeBase = 0xE000   # private-use characters stand in for \-escaped punctuation while parsing

function Test-MarkdownText {
    <# True when the text holds Markdown structure worth converting (headings, lists, fences, tables,
       links, emphasis or inline code). #>
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return $false }
    $block = '(?m)^\s{0,3}(#{1,6}\s+\S|```|~~~|>\s|([-*+]|\d+[.)])\s+\S|\|.*\|\s*$)'
    $inline = '\*\*[^*\s][^*]*\*\*|__[^_\s][^_]*__|`[^`\r\n]+`|\[[^\]\r\n]+\]\([^)\s]+\)|~~[^~\s][^~]*~~'
    [bool](([regex]::IsMatch($Text, $block)) -or ([regex]::IsMatch($Text, $inline)))
}

function New-MdPart([string]$Text, [string]$Href = '', [bool]$Bold = $false, [bool]$Italic = $false, [bool]$Code = $false, [bool]$Strike = $false) {
    @{ text = $Text; href = $Href; bold = $Bold; italic = $Italic; code = $Code; strike = $Strike }
}

function New-MdLine {
    param([object[]]$Parts = @(), [string]$List = '', [int]$Heading = 0, [bool]$Quote = $false, [bool]$Code = $false, $Table = $null)
    @{ parts = @($Parts); bold = ($Heading -gt 0); collapsed = $false; children = @(); list = $List; heading = $Heading; quote = $Quote; code = $Code; table = $Table }
}

function Protect-MdEscapes([string]$Text) {
    # \* \_ \` \[ ... -> private-use stand-ins, so the inline patterns do not see them.
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '\' -and $i + 1 -lt $Text.Length -and ('\`*_{}[]()#+-.!|~<>').Contains([string]$Text[$i + 1])) {
            [void]$sb.Append([char]($script:EscapeBase + [int]$Text[$i + 1])); $i++
        } else { [void]$sb.Append($c) }
    }
    $sb.ToString()
}

function Restore-MdEscapes([string]$Text) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Text.ToCharArray()) {
        $n = [int]$c
        if ($n -ge $script:EscapeBase -and $n -lt $script:EscapeBase + 128) { [void]$sb.Append([char]($n - $script:EscapeBase)) } else { [void]$sb.Append($c) }
    }
    $sb.ToString()
}

function ConvertFrom-MdInline {
    <# One line of text -> parts. Recursive for emphasis and link labels; inline code is literal. #>
    param([AllowEmptyString()][string]$Text, [string]$Href = '', [bool]$Bold = $false, [bool]$Italic = $false, [bool]$Strike = $false)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Text) { return }
    # Idempotent: text from ConvertFrom-MarkdownText is protected already; a direct call is not.
    $Text = Protect-MdEscapes $Text
    $pattern = '(?<code>`(?<ct>[^`]+)`)' +
        '|(?<link>\[(?<lt>[^\]]+)\]\((?<lu>[^)\s]+)(?:\s+"[^"]*")?\))' +
        '|(?<auto><(?<au>(?:https?://|mailto:)[^>\s]+)>)' +
        '|(?<bold>\*\*(?<bt>[^*\s](?:.*?[^*\s])?)\*\*|__(?<bt2>[^_\s](?:.*?[^_\s])?)__)' +
        '|(?<strike>~~(?<st>[^~\s](?:.*?[^~\s])?)~~)' +
        '|(?<ital>(?<![\w*])\*(?<it>[^*\s](?:[^*]*?[^*\s])?)\*(?![\w*])|(?<![\w_])_(?<it2>[^_\s](?:[^_]*?[^_\s])?)_(?![\w_]))'
    $pos = 0
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        if ($m.Index -gt $pos) { $out.Add((New-MdPart (Restore-MdEscapes $Text.Substring($pos, $m.Index - $pos)) $Href $Bold $Italic $false $Strike)) }
        $g = $m.Groups
        if ($g['code'].Success) { $out.Add((New-MdPart (Restore-MdEscapes $g['ct'].Value) $Href $Bold $Italic $true $Strike)) }
        elseif ($g['link'].Success) {
            $url = Restore-MdEscapes $g['lu'].Value
            if (-not $Href -and $url -match $script:LinkSchemes) { foreach ($p in @(ConvertFrom-MdInline $g['lt'].Value $url $Bold $Italic $Strike)) { $out.Add($p) } }
            else { $out.Add((New-MdPart (Restore-MdEscapes $m.Value) $Href $Bold $Italic $false $Strike)) }
        }
        elseif ($g['auto'].Success) {
            $url = Restore-MdEscapes $g['au'].Value
            $out.Add((New-MdPart $url $(if ($Href) { $Href } else { $url }) $Bold $Italic $false $Strike))
        }
        elseif ($g['bold'].Success) {
            $inner = if ($g['bt'].Success) { $g['bt'].Value } else { $g['bt2'].Value }
            foreach ($p in @(ConvertFrom-MdInline $inner $Href $true $Italic $Strike)) { $out.Add($p) }
        }
        elseif ($g['strike'].Success) { foreach ($p in @(ConvertFrom-MdInline $g['st'].Value $Href $Bold $Italic $true)) { $out.Add($p) } }
        else {
            $inner = if ($g['it'].Success) { $g['it'].Value } else { $g['it2'].Value }
            foreach ($p in @(ConvertFrom-MdInline $inner $Href $Bold $true $Strike)) { $out.Add($p) }
        }
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Text.Length) { $out.Add((New-MdPart (Restore-MdEscapes $Text.Substring($pos)) $Href $Bold $Italic $false $Strike)) }
    # Plain pipeline output: callers wrap the call in @() (a ', @()' return would nest, AGENTS.md).
    $out.ToArray()
}

function Get-MdIndent([string]$Line) {
    $n = 0
    foreach ($c in $Line.ToCharArray()) { if ($c -eq ' ') { $n++ } elseif ($c -eq "`t") { $n += 4 } else { break } }
    $n
}

function Split-MdTableRow([string]$Line) {
    $t = $Line.Trim()
    if ($t.StartsWith('|')) { $t = $t.Substring(1) }
    if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    $t -split '\|' | ForEach-Object { $_.Trim() }
}

function Test-MdTableSeparator([string]$Line) {
    $Line -match '^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$' -and $Line.Contains('-')
}

function ConvertFrom-MarkdownText {
    <# Markdown text -> line model (see the header). Nested lists become children of the item above
       them. Trailing empty lines are dropped; other empty lines stay (as in plain text). #>
    param([AllowEmptyString()][string]$Text)
    $raw = @((Protect-MdEscapes $Text) -split '\r?\n')
    $end = $raw.Count - 1
    while ($end -ge 0 -and -not $raw[$end].Trim()) { $end-- }
    if ($end -lt 0) { return }
    $top = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]   # open list items: @{ indent; line }
    $i = 0
    while ($i -le $end) {
        $line = $raw[$i]
        # fenced code: every line monospace, kept as written
        if ($line -match '^\s{0,3}(```|~~~)') {
            $fence = $Matches[1]; $i++
            while ($i -le $end -and $raw[$i] -notmatch ('^\s{0,3}' + [regex]::Escape($fence))) {
                $top.Add((New-MdLine -Parts @(New-MdPart (Restore-MdEscapes $raw[$i]) '' $false $false $true) -Code $true)); $i++
            }
            $i++; $stack.Clear(); continue
        }
        # table: a row, then a separator row, then rows while lines hold a '|'
        if ($line.Contains('|') -and $i + 1 -le $end -and (Test-MdTableSeparator $raw[$i + 1])) {
            $header = @(foreach ($c in @(Split-MdTableRow $line)) { , @(ConvertFrom-MdInline $c) })
            $rows = New-Object System.Collections.Generic.List[object]
            $i += 2
            while ($i -le $end -and $raw[$i].Contains('|') -and $raw[$i].Trim()) {
                $rows.Add(@(foreach ($c in @(Split-MdTableRow $raw[$i])) { , @(ConvertFrom-MdInline $c) })); $i++
            }
            $top.Add((New-MdLine -Table @{ header = $header; rows = @($rows.ToArray()) })); $stack.Clear(); continue
        }
        if ($line -match '^\s{0,3}#{1,6}\s+') {
            $null = $line -match '^\s{0,3}(?<h>#{1,6})\s+(?<t>.*?)\s*#*\s*$'
            # The line is bold (New-MdLine); its parts are not, so the bold is applied once.
            $top.Add((New-MdLine -Parts @(ConvertFrom-MdInline $Matches['t']) -Heading $Matches['h'].Length)); $i++; $stack.Clear(); continue
        }
        if ($line -match '^\s{0,3}([-*_])(\s*\1){2,}\s*$') { $i++; $stack.Clear(); continue }   # rule: nothing to show
        if ($line -match '^\s{0,3}>\s?(?<q>.*)$') {
            $top.Add((New-MdLine -Parts @(ConvertFrom-MdInline $Matches['q'] '' $false $true) -Quote $true)); $i++; $stack.Clear(); continue
        }
        if ($line -match '^(?<ind>\s*)(?<m>[-*+]|\d+[.)])\s+(?<t>.*)$') {
            # Read every group before the next -match: it replaces $Matches.
            $marker = $Matches['m']; $t = $Matches['t']
            $indent = Get-MdIndent $line
            $kind = if ($marker -match '^\d') { 'number' } else { 'bullet' }
            if ($t -match '^\[(?<x>[ xX])\]\s+(?<r>.*)$') {
                # task list: a box character in front (OneNote's own to-do tag is not set here)
                $box = if ($Matches['x'] -eq ' ') { [char]0x2610 } else { [char]0x2611 }
                $t = "$box $($Matches['r'])"
            }
            $item = New-MdLine -Parts @(ConvertFrom-MdInline $t) -List $kind
            while ($stack.Count -and $stack[$stack.Count - 1].indent -ge $indent) { $stack.RemoveAt($stack.Count - 1) }
            if ($stack.Count) { $parent = $stack[$stack.Count - 1].line; $parent['children'] = @($parent['children']) + @($item) }
            else { $top.Add($item) }
            $stack.Add(@{ indent = $indent; line = $item }); $i++; continue
        }
        # an indented line right under a list item continues that item
        if ($stack.Count -and $line.Trim() -and (Get-MdIndent $line) -gt $stack[$stack.Count - 1].indent) {
            $cont = $stack[$stack.Count - 1].line
            $cont['parts'] = @($cont['parts']) + @(New-MdPart ' ') + @(ConvertFrom-MdInline $line.Trim())
            $i++; continue
        }
        $stack.Clear()
        $top.Add((New-MdLine -Parts @(ConvertFrom-MdInline $line.TrimEnd()))); $i++
    }
    $top.ToArray()
}

function ConvertTo-MdPartHtml {
    <# One part -> the HTML OneNote keeps in a text run: bold, italic, strikethrough and monospace as
       span styles, links as <a>. Text is encoded; the href never closes the CDATA. #>
    param([Parameter(Mandatory)]$Part)
    $t = ([string]$Part['text']).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $styles = @()
    if ($Part['code']) { $styles += 'font-family:Consolas' }
    if ($Part['bold']) { $styles += 'font-weight:bold' }
    if ($Part['italic']) { $styles += 'font-style:italic' }
    if ($Part['strike']) { $styles += 'text-decoration:line-through' }
    if ($styles.Count) { $t = "<span style='" + ($styles -join ';') + "'>" + $t + '</span>' }
    $h = [string]$Part['href']
    if ($h) { $t = '<a href="' + $h.Replace('&', '&amp;').Replace('"', '&quot;').Replace('<', '&lt;').Replace('>', '&gt;') + '">' + $t + '</a>' }
    $t
}

Export-ModuleMember -Function Test-MarkdownText, ConvertFrom-MarkdownText, ConvertFrom-MdInline, ConvertTo-MdPartHtml
