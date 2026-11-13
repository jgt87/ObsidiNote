# Linker: the classify + link step of Add (FEASIBILITY.md section 4, Copilot's role; section 5,
# Central index). Pure functions only:
# - Get-LinkShortlist: candidate pages and topics from the in-memory index model, by keyword,
#   alias and topic overlap, sized to a prompt budget.
# - New-LinkPrompt: the Copilot prompt with the fixed JSON contract.
# - Get-ReplyJson: finds the JSON object in a reply (tolerates code fences and text around it).
# - Test-LinkReply: the validator (type in the fixed list, every target exists, anchors occur in
#   the text, topic path exists or its parent does, no duplicate page).
# Nothing here writes anywhere or calls Copilot; lib/Ingest.psm1 does that through its adapter.
#
# Index model (from the adapter's GetIndex; hashtables or objects):
#   pages  = @( @{ id; title; type; section; link; summary; aliases; topics; url } )
#   topics = @( 'Security', 'Security/Networking', ... )  or @( @{ path } )
#   edges  = @( @{ from; to; strength; why } )
# Topics are identified by their path ('Security/Networking/Zero trust'); in the prompt they get
# short ids t1..tN that only live in that one prompt (Shortlist.topicIds maps them back).
# PS 5.1, ASCII only.
Set-StrictMode -Version 2.0

$script:Stopwords = @(
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'are', 'was', 'were', 'has', 'have', 'had',
    'not', 'but', 'you', 'your', 'our', 'their', 'its', 'they', 'them', 'his', 'her', 'she', 'him',
    'who', 'what', 'when', 'where', 'which', 'why', 'how', 'all', 'any', 'can', 'will', 'would',
    'should', 'could', 'may', 'might', 'into', 'onto', 'than', 'then', 'there', 'here', 'about',
    'also', 'just', 'only', 'more', 'most', 'some', 'such', 'very', 'use', 'used', 'using', 'one',
    'two', 'out', 'over', 'under', 'per', 'via', 'off', 'yet', 'too', 'did', 'does', 'done', 'each',
    'other', 'these', 'those', 'being', 'been', 'because', 'before', 'after', 'while', 'instead',
    'http', 'https', 'www', 'com'
)

# What each fixed type means, for the prompt. Types outside this table still pass when the
# adapter's TypeList has them; they are then listed without a hint.
$script:TypeHints = [ordered]@{
    'concept'       = 'an idea or term explained'
    'note'          = 'a plain note or thought'
    'howto'         = 'steps to do something'
    'link-internal' = 'a Microsoft 365 or intranet link'
    'link-web'      = 'a link to a public web page'
    'source'        = 'a book, talk, paper or pasted text without a link'
    'person'        = 'one person; title "Name (role)"'
    'project'       = 'a project; title is the project name'
    'project-part'  = 'a part of a project (plan, risks)'
    'meeting'       = 'meeting notes; title "yyyy-mm-dd subject"'
    'decision'      = 'a decision record; title "Decision: subject"'
    'log'           = 'a journal entry for one day; title "yyyy-mm-dd"'
    'file'          = 'a file; title is the file name without extension'
}

function Get-LkProp {
    <# A property of a hashtable or object, or $Default (StrictMode-safe). Lists: wrap in @(). #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    $Default
}

function Get-LkString {
    param($Object, [string]$Name)
    $v = Get-LkProp $Object $Name ''
    if ($null -eq $v) { return '' }
    if ($v -is [string]) { return $v.Trim() }
    if ($v -is [ValueType]) { return ([string]$v).Trim() }
    ''
}

function Format-LkTopicPath {
    <# 'Security / Networking ' -> 'Security/Networking': segments trimmed, inner spaces collapsed. #>
    param([AllowEmptyString()][AllowNull()][string]$Path)
    if (-not $Path) { return '' }
    $segs = @($Path.Split('/') | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    $segs -join '/'
}

function Get-LkTopicPaths {
    <# The topic paths of the index model as normalized strings. #>
    param($Index)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in @(Get-LkProp $Index 'topics' @())) {
        if ($null -eq $t) { continue }
        $p = if ($t -is [string]) { $t } else { [string](Get-LkProp $t 'path' '') }
        $p = Format-LkTopicPath $p
        if ($p -and -not $out.Contains($p)) { $out.Add($p) }
    }
    # Topics that only appear on pages count as existing too (the page wins over the index).
    foreach ($pg in @(Get-LkProp $Index 'pages' @())) {
        foreach ($t in @(Get-LkProp $pg 'topics' @())) {
            $p = Format-LkTopicPath ([string]$t)
            if ($p -and -not $out.Contains($p)) { $out.Add($p) }
        }
    }
    , $out.ToArray()
}

function Get-TextTerms {
    <# Lower-case words of 3+ letters/digits without stop words, unique, in order. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $list = New-Object System.Collections.Generic.List[string]
    if (-not $Text) { return , $list.ToArray() }
    foreach ($m in [regex]::Matches($Text.ToLowerInvariant(), '[\p{L}\p{N}][\p{L}\p{N}_-]{2,}')) {
        $w = $m.Value.Trim('-', '_')
        if ($w.Length -lt 3 -or $script:Stopwords -contains $w) { continue }
        if ($set.Add($w)) { $list.Add($w) }
    }
    , $list.ToArray()
}

function Test-PhraseInText {
    <# True when $Phrase occurs in $Text as whole words, ignoring case and runs of white space. #>
    param([string]$Text, [string]$Phrase)
    $p = ($Phrase -replace '\s+', ' ').Trim()
    if (-not $p -or -not $Text) { return $false }
    $pat = '(?<![\p{L}\p{N}])' + ([regex]::Escape($p) -replace '\\ ', '\s+') + '(?![\p{L}\p{N}])'
    [regex]::IsMatch($Text, $pat, 'IgnoreCase')
}

function Get-PageScore {
    param($Page, $TermSet, [string]$Text)
    $score = 0
    foreach ($w in (Get-TextTerms ([string](Get-LkProp $Page 'title' '')))) { if ($TermSet.Contains($w)) { $score += 3 } }
    foreach ($a in @(Get-LkProp $Page 'aliases' @())) {
        $as = [string]$a
        if (-not $as) { continue }
        if (Test-PhraseInText -Text $Text -Phrase $as) { $score += 5 }
        else { foreach ($w in (Get-TextTerms $as)) { if ($TermSet.Contains($w)) { $score += 2 } } }
    }
    foreach ($t in @(Get-LkProp $Page 'topics' @())) {
        foreach ($w in (Get-TextTerms ([string]$t).Replace('/', ' '))) { if ($TermSet.Contains($w)) { $score += 2 } }
    }
    foreach ($w in (Get-TextTerms ([string](Get-LkProp $Page 'summary' '')))) { if ($TermSet.Contains($w)) { $score += 1 } }
    $score
}

function Format-ShortlistLine {
    param($Page)
    $sum = [string](Get-LkProp $Page 'summary' '')
    $sum = ($sum -replace '\s+', ' ').Trim()
    if ($sum.Length -gt 160) { $sum = $sum.Substring(0, 157) + '...' }
    $al = (@(Get-LkProp $Page 'aliases' @()) | Where-Object { $_ }) -join ', '
    $tp = (@(Get-LkProp $Page 'topics' @()) | Where-Object { $_ } | ForEach-Object { Format-LkTopicPath ([string]$_) }) -join '; '
    $title = ([string](Get-LkProp $Page 'title' '') -replace '\s+', ' ').Trim()
    '{0} | {1} | {2} | {3} | {4}' -f (Get-LkProp $Page 'id' ''), $title, $al, $tp, $sum
}

function Get-LinkShortlist {
    <# Candidate pages and topics for one new item, sized to a prompt budget.
       Pages: scored by title (+3 per shared word), alias (+5 when the alias occurs in the text,
       else +2 per shared word), topic path (+2 per shared word) and summary (+1 per shared word);
       pages scoring 0 are left out; at most $MaxPages and $MaxChars of prompt lines.
       Topics: all paths when they fit in $TopicChars, else the roots, the candidates' paths with
       their ancestors, and paths with a word from the text. Each gets a prompt id t1..tN.
       Returns @{ pages = @(@{ id; title; score; line; page }); topics = @(@{ id; path });
       topicIds = @{ t1 = path }; chars }. Pure. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Index,
        [AllowEmptyString()][string]$Text = '',
        [int]$MaxPages = 60,
        [int]$MaxChars = 12000,
        [int]$TopicChars = 4000,
        [string[]]$ExcludeIds = @()
    )
    $terms = Get-TextTerms $Text
    $termSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($w in $terms) { [void]$termSet.Add($w) }

    $scored = @(foreach ($p in @(Get-LkProp $Index 'pages' @())) {
        if ($null -eq $p) { continue }
        $id = [string](Get-LkProp $p 'id' '')
        if (-not $id -or $ExcludeIds -contains $id) { continue }
        if ([string](Get-LkProp $p 'status' '') -eq 'archived') { continue }
        $s = Get-PageScore -Page $p -TermSet $termSet -Text $Text
        if ($s -gt 0) { [pscustomobject]@{ id = $id; title = [string](Get-LkProp $p 'title' ''); score = $s; page = $p } }
    })
    $scored = @($scored | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'title'; Descending = $false })

    $pages = New-Object System.Collections.Generic.List[object]
    $chars = 0
    foreach ($c in $scored) {
        if ($pages.Count -ge $MaxPages) { break }
        $line = Format-ShortlistLine $c.page
        if ($chars + $line.Length + 1 -gt $MaxChars) { break }
        $chars += $line.Length + 1
        $pages.Add(@{ id = $c.id; title = $c.title; score = $c.score; line = $line; page = $c.page })
    }

    $all = Get-LkTopicPaths $Index
    $total = 0
    foreach ($t in $all) { $total += $t.Length + 6 }
    $chosen = New-Object System.Collections.Generic.List[string]
    if ($total -le $TopicChars) { foreach ($t in $all) { $chosen.Add($t) } }
    else {
        $want = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $all) { if ($t.IndexOf('/') -lt 0) { [void]$want.Add($t) } }
        foreach ($c in $pages) {
            foreach ($t in @(Get-LkProp $c.page 'topics' @())) {
                $segs = (Format-LkTopicPath ([string]$t)).Split('/')
                for ($i = 1; $i -le $segs.Count; $i++) { [void]$want.Add(($segs[0..($i - 1)] -join '/')) }
            }
        }
        foreach ($t in $all) {
            foreach ($w in (Get-TextTerms $t.Replace('/', ' '))) { if ($termSet.Contains($w)) { [void]$want.Add($t); break } }
        }
        $used = 0
        foreach ($t in $all) {
            if (-not $want.Contains($t)) { continue }
            if ($used + $t.Length + 6 -gt $TopicChars) { break }
            $used += $t.Length + 6
            $chosen.Add($t)
        }
    }
    $sorted = @($chosen | Sort-Object)
    $topics = @(); $ids = @{}
    $n = 0
    foreach ($t in $sorted) { $n++; $topics += @{ id = "t$n"; path = $t }; $ids["t$n"] = $t; $chars += $t.Length + 6 }

    @{ pages = $pages.ToArray(); topics = $topics; topicIds = $ids; chars = $chars }
}

function New-LinkPrompt {
    <# The classify + link prompt. $Kind 'text' (a captured item) or 'link' (the summary of a pasted
       link; then -FixedType names its type). The reply contract is one JSON object:
       { title, summary, type, topics: [{id}|{new}], links: [{target, anchor, strength, why}],
         aliases, intent }. JSON, never Markdown links: Copilot's filter removes "[x]:" text. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)]$Shortlist,
        [Parameter(Mandatory)][string[]]$Types,
        [string]$FixedType = '',
        [datetime]$Today = (Get-Date),
        [int]$MaxTextChars = 20000,
        # The request's reference code (lib/Ingest.psm1 New-RequestRef): Copilot repeats it as "ref",
        # so an answer read from the chat later is only used for the request that asked for it.
        [string]$Ref = ''
    )
    $item = $Text.Trim()
    if ($item.Length -gt $MaxTextChars) { $item = $item.Substring(0, $MaxTextChars) + "`n(cut here)" }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('You file items into a personal wiki. Reply with exactly one JSON object and nothing else: no Markdown, no code fence, no text before or after it.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Today is $($Today.ToString('yyyy-MM-dd')).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('The new item, between the lines:')
    [void]$sb.AppendLine('-----')
    [void]$sb.AppendLine($item)
    [void]$sb.AppendLine('-----')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Existing topics (id: path; a path is parent/child):')
    $topics = @(Get-LkProp $Shortlist 'topics' @())
    if ($topics.Count) { foreach ($t in $topics) { [void]$sb.AppendLine("$($t['id']): $($t['path'])") } }
    else { [void]$sb.AppendLine('(none yet)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Existing pages that may be related (id | title | aliases | topics | summary):')
    $pages = @(Get-LkProp $Shortlist 'pages' @())
    if ($pages.Count) { foreach ($p in $pages) { [void]$sb.AppendLine($p['line']) } }
    else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('The JSON object:')
    $refPart = if ($Ref) { ', "ref": "' + $Ref + '"' } else { '' }
    [void]$sb.AppendLine('{"title": "...", "summary": "...", "type": "...", "topics": [{"id": "t1"}, {"new": "Parent/New topic"}], "links": [{"target": "p12", "anchor": "...", "strength": 2, "why": "..."}], "aliases": ["..."], "intent": "add"' + $refPart + '}')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Rules:')
    if ($Ref) { [void]$sb.AppendLine("- ref: always exactly ""$Ref"" (the reference of this request).") }
    if ($FixedType) {
        [void]$sb.AppendLine("- type: always ""$FixedType"".")
    } else {
        [void]$sb.AppendLine('- type: exactly one of these:')
        foreach ($t in $Types) {
            $h = if ($script:TypeHints.Contains($t)) { ' (' + $script:TypeHints[$t] + ')' } else { '' }
            [void]$sb.AppendLine("  $t$h")
        }
    }
    [void]$sb.AppendLine('- title: short, in plain words, following the title rule of the type.')
    [void]$sb.AppendLine('- summary: one sentence of at most 200 characters: what this is.')
    [void]$sb.AppendLine('- topics: 1 to 3. Use the id of an existing topic when one fits. Otherwise give a new path in "new": an existing topic path plus one new part, or one new top-level part.')
    [void]$sb.AppendLine('- links: only to page ids from the list above, at most 8; none when nothing fits. anchor: 2 to 6 words copied exactly from the new item. strength: 3 core, 2 related, 1 loose. why: at most 8 words.')
    [void]$sb.AppendLine('- aliases: other names or abbreviations of the subject, at most 5; [] when there are none.')
    [void]$sb.AppendLine('- intent: "add" when the item is something to keep, "ask" when it is a question to the wiki.')
    [void]$sb.AppendLine('- Use straight double quotes only.')
    $sb.ToString()
}

function Get-JsonObjectSpan {
    <# The end index of the JSON object that starts at $Start ('{'), or -1. Respects strings. #>
    param([string]$Text, [int]$Start)
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($ch -eq '\') { $esc = $true }
            elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true }
        elseif ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $i } }
    }
    -1
}

function Get-ReplyJson {
    <# Finds the first JSON object in a Copilot reply: code fences and text around it are ignored,
       trailing commas are forgiven. Returns @{ ok; value; error }. Never throws. #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Reply)
    if (-not $Reply -or -not $Reply.Trim()) { return @{ ok = $false; value = $null; error = 'Copilot gave an empty answer.' } }
    $t = [regex]::Replace($Reply, '```[A-Za-z]*', '')
    $t = $t.Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"')
    $from = 0; $tries = 0
    while ($tries -lt 25) {
        $start = $t.IndexOf('{', $from)
        if ($start -lt 0) { break }
        $tries++
        $end = Get-JsonObjectSpan -Text $t -Start $start
        if ($end -lt 0) { break }
        $cand = $t.Substring($start, $end - $start + 1)
        foreach ($c in @($cand, ([regex]::Replace($cand, ',\s*([}\]])', '$1')))) {
            try {
                $v = ConvertFrom-Json -InputObject $c -ErrorAction Stop
                if ($v -is [System.Management.Automation.PSCustomObject]) { return @{ ok = $true; value = $v; error = '' } }
            } catch { }
        }
        $from = $start + 1
    }
    if ($t.IndexOf('{') -lt 0) { return @{ ok = $false; value = $null; error = 'The answer holds no JSON object.' } }
    @{ ok = $false; value = $null; error = 'The JSON in the answer could not be read.' }
}

function Get-ReplyJsonObjects {
    <# Every JSON object in a text (several replies of one chat read together), in order; nested
       objects are not listed on their own. Never throws. #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if (-not $Text) { return , @() }
    $t = [regex]::Replace($Text, '```[A-Za-z]*', '')
    $t = $t.Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"')
    $out = New-Object System.Collections.Generic.List[object]
    $from = 0
    while ($out.Count -lt 200) {
        $start = $t.IndexOf('{', $from)
        if ($start -lt 0) { break }
        $end = Get-JsonObjectSpan -Text $t -Start $start
        if ($end -lt 0) { break }
        $cand = $t.Substring($start, $end - $start + 1)
        $v = $null
        foreach ($c in @($cand, ([regex]::Replace($cand, ',\s*([}\]])', '$1')))) {
            try { $v = ConvertFrom-Json -InputObject $c -ErrorAction Stop; break } catch { $v = $null }
        }
        if ($v -is [System.Management.Automation.PSCustomObject]) { $out.Add($v); $from = $end + 1 }
        else { $from = $start + 1 }
    }
    , $out.ToArray()
}

function Test-ReplyRef {
    <# The request reference in a parsed reply. Another reference is always refused (it is the answer
       to another request). A reply without one is accepted live (it is this turn's reply) and
       refused with -Required (an answer read from the chat later). Returns @{ ok; error }. #>
    param($Reply, [string]$Ref, [switch]$Required)
    if (-not $Ref) { return @{ ok = $true; error = '' } }
    $got = (Get-LkString $Reply 'ref').Trim()
    if ($got -eq $Ref) { return @{ ok = $true; error = '' } }
    if (-not $got) {
        if ($Required) { return @{ ok = $false; error = "The answer does not carry this item's reference ($Ref)." } }
        return @{ ok = $true; error = '' }
    }
    $shown = if ($got -match '^[A-Za-z0-9]{1,16}$') { $got } else { 'another one' }
    @{ ok = $false; error = "The answer belongs to another request (reference $shown, expected $Ref)." }
}

function Limit-LkText {
    param([string]$Text, [int]$Max)
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 3).TrimEnd() + '...' }
    $t
}

function Test-LinkReply {
    <# Validates a parsed reply against the index. Fatal (ok = $false, errors): no object, no
       title, a type outside $Types, a duplicate page (same title and type as an existing page).
       Dropped, with a reason (the rest is kept): unknown topic ids, new topic paths whose parent
       does not exist, links to ids not in the index or to the page itself, anchors not found in
       $Text (the link stays without an anchor), bad strengths (clamped to 1-3), extra aliases.
       Returns @{ ok; errors; dropped = @(@{ what; value; reason }); duplicateOf;
       value = @{ title; summary; type; topics = @(@{ path; isNew }); links = @(@{ target; title;
       link; anchor; strength; why }); aliases; intent } }. Pure. #>
    [CmdletBinding()]
    param(
        $Reply,
        [Parameter(Mandatory)]$Index,
        [Parameter(Mandatory)]$Shortlist,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Types,
        [string]$FixedType = '',
        [string]$SelfId = '',
        [switch]$SkipDuplicateTitle,
        [int]$MaxLinks = 12,
        [int]$MaxTopics = 5
    )
    $errors = @(); $dropped = @(); $dup = ''
    if ($null -eq $Reply) {
        return @{ ok = $false; errors = @('The answer holds no JSON object.'); dropped = @(); duplicateOf = ''; value = $null }
    }

    $title = Limit-LkText (Get-LkString $Reply 'title') 120
    if (-not $title) { $errors += 'The answer has no title.' }
    $summary = Limit-LkText (Get-LkString $Reply 'summary') 300

    $type = (Get-LkString $Reply 'type').ToLowerInvariant()
    if ($FixedType) {
        if ($type -and $type -ne $FixedType) { $dropped += @{ what = 'type'; value = $type; reason = "a link page is always $FixedType" } }
        $type = $FixedType
    }
    if (-not $type) { $errors += 'The answer has no type.' }
    elseif ($Types -notcontains $type) { $errors += "The type '$type' is not one of the fixed types." }

    # Pages of the index, by id.
    $byId = @{}
    foreach ($p in @(Get-LkProp $Index 'pages' @())) {
        $id = [string](Get-LkProp $p 'id' '')
        if ($id) { $byId[$id] = $p }
    }

    # Duplicate page: same title (ignoring case and spaces) and same type.
    if ($title -and $type -and -not $SkipDuplicateTitle) {
        $norm = ($title -replace '\s+', ' ').Trim().ToLowerInvariant()
        foreach ($p in $byId.Values) {
            $pid2 = [string](Get-LkProp $p 'id' '')
            if ($pid2 -eq $SelfId) { continue }
            $pt = ([string](Get-LkProp $p 'title' '') -replace '\s+', ' ').Trim().ToLowerInvariant()
            if ($pt -eq $norm -and ([string](Get-LkProp $p 'type' '')).ToLowerInvariant() -eq $type) {
                $dup = $pid2
                $errors += "A $type page with this title exists already ($pid2)."
                break
            }
        }
    }

    # Topics.
    $paths = Get-LkTopicPaths $Index
    $pathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $paths) { [void]$pathSet.Add($p) }
    $tids = Get-LkProp $Shortlist 'topicIds' @{}
    $topics = @(); $seenTopic = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @(Get-LkProp $Reply 'topics' @())) {
        if ($null -eq $t) { continue }
        $path = ''; $isNew = $false
        if ($t -is [string]) { $raw = Format-LkTopicPath $t; $tid = '' }
        else { $tid = Get-LkString $t 'id'; $raw = Format-LkTopicPath (Get-LkString $t 'new') }
        if ($tid) {
            if ($tids.Contains($tid)) { $path = [string]$tids[$tid] }
            elseif ($pathSet.Contains((Format-LkTopicPath $tid))) { $path = Format-LkTopicPath $tid }
            else { $dropped += @{ what = 'topic'; value = $tid; reason = 'unknown topic id' }; continue }
        } elseif ($raw) {
            if ($pathSet.Contains($raw)) {
                $path = @($paths | Where-Object { $_ -eq $raw })[0]
            } else {
                $cut = $raw.LastIndexOf('/')
                $parent = if ($cut -lt 0) { '' } else { $raw.Substring(0, $cut) }
                if ($parent -and -not $pathSet.Contains($parent)) { $dropped += @{ what = 'topic'; value = $raw; reason = 'its parent topic does not exist' }; continue }
                if ($parent) { $raw = (@($paths | Where-Object { $_ -eq $parent })[0]) + $raw.Substring($cut) }
                $path = $raw; $isNew = $true
            }
        } else { continue }
        if ($topics.Count -ge $MaxTopics) { $dropped += @{ what = 'topic'; value = $path; reason = 'too many topics' }; continue }
        if ($seenTopic.Add($path)) { $topics += @{ path = $path; isNew = $isNew } }
    }

    # Links.
    $links = @(); $byTarget = @{}
    foreach ($l in @(Get-LkProp $Reply 'links' @())) {
        if ($null -eq $l) { continue }
        $target = Get-LkString $l 'target'
        if (-not $target) { continue }
        if ($target -eq $SelfId) { $dropped += @{ what = 'link'; value = $target; reason = 'a link to the page itself' }; continue }
        if (-not $byId.ContainsKey($target)) { $dropped += @{ what = 'link'; value = $target; reason = 'no such page in the index' }; continue }
        $s = 0
        $sv = Get-LkProp $l 'strength' 1
        if (-not [int]::TryParse(([string]$sv), [ref]$s)) { $s = 1 }
        if ($s -lt 1 -or $s -gt 3) {
            $dropped += @{ what = 'strength'; value = $target; reason = "strength $sv set to the range 1-3" }
            if ($s -lt 1) { $s = 1 } else { $s = 3 }
        }
        $anchor = Limit-LkText (Get-LkString $l 'anchor') 120
        if ($anchor -and -not (Test-PhraseInText -Text $Text -Phrase $anchor)) {
            $dropped += @{ what = 'anchor'; value = $target; reason = 'the anchor is not in the text' }
            $anchor = ''
        }
        $why = Limit-LkText (Get-LkString $l 'why') 120
        $page = $byId[$target]
        $rec = @{ target = $target; title = [string](Get-LkProp $page 'title' ''); link = [string](Get-LkProp $page 'link' ''); anchor = $anchor; strength = $s; why = $why }
        if ($byTarget.ContainsKey($target)) {
            $old = $byTarget[$target]
            if ($s -gt $old.strength) { $old.strength = $s }
            if (-not $old.anchor -and $anchor) { $old.anchor = $anchor }
            continue
        }
        if ($links.Count -ge $MaxLinks) { $dropped += @{ what = 'link'; value = $target; reason = 'too many links' }; continue }
        $byTarget[$target] = $rec
        $links += $rec
    }
    $links = @($links | Sort-Object @{ Expression = { $_.strength }; Descending = $true })

    # Aliases.
    $aliases = @(); $seenAlias = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in @(Get-LkProp $Reply 'aliases' @())) {
        if (-not ($a -is [string])) { continue }
        $as = Limit-LkText $a 60
        if (-not $as -or $as -eq $title) { continue }
        if ($aliases.Count -ge 5) { $dropped += @{ what = 'alias'; value = $as; reason = 'too many aliases' }; continue }
        if ($seenAlias.Add($as)) { $aliases += $as }
    }

    $intent = (Get-LkString $Reply 'intent').ToLowerInvariant()
    if ($intent -ne 'ask') { $intent = 'add' }

    $value = @{ title = $title; summary = $summary; type = $type; topics = $topics; links = $links; aliases = $aliases; intent = $intent }
    @{ ok = ($errors.Count -eq 0); errors = $errors; dropped = $dropped; duplicateOf = $dup; value = $value }
}

Export-ModuleMember -Function Get-LkProp, Get-LkString, Format-LkTopicPath, Get-LkTopicPaths, Get-TextTerms, Test-PhraseInText, Get-LinkShortlist, New-LinkPrompt, Get-ReplyJson, Get-ReplyJsonObjects, Test-ReplyRef, Test-LinkReply
