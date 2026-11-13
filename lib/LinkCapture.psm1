# LinkCapture: a pasted link becomes one summary page (FEASIBILITY.md section 5, Links).
# Pure functions only; lib/Ingest.psm1 runs them and writes through its adapter.
# - Get-PastedUrl: is the item just a URL?
# - New-LinkSummaryPrompt / ConvertTo-LinkSummary: the summary call and its fixed JSON contract.
# - New-LinkPageOutlines: the fixed page shape as owned outlines (summary, checked + earlier
#   summaries, Your notes on a new page only).
# - Get-SummaryHash / Test-SummaryEdited: was the summary outline edited by hand?
# - Compare-LinkSummary / Add-SummaryHistory: old vs new, and the last 3 summaries.
# Line model used for outlines (the adapter turns it into OneNote XML):
#   @{ parts = @(@{ text; href }); bold; collapsed; children = @(lines) }
# PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Linker.psm1')

$script:InternalKinds = @('site', 'page', 'document', 'list', 'file', 'channel', 'message', 'loop-page', 'other')
$script:WebKinds = @('article', 'docs', 'tool', 'video', 'other')
$script:Problems = @('no-access', 'not-found', 'other')

function Get-PastedUrl {
    <# The URL when the item is one http(s) URL and nothing else (white space and <> around it are
       allowed); '' otherwise. #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if (-not $Text) { return '' }
    $t = $Text.Trim().Trim('<', '>').Trim()
    if ($t -match '^(?i)https?://[^\s<>"]+$') { return $t }
    ''
}

function New-LinkLine {
    <# A line of the outline line model. #>
    param([string]$Text = '', [string]$Href = '', [object[]]$Parts = @(), [object[]]$Children = @(), [switch]$Bold, [switch]$Collapsed)
    # Assigned, not taken from an if-expression: that would unroll a one-part list into a hashtable.
    $p = @($Parts | Where-Object { $null -ne $_ })
    if (-not $p.Count) { $p = @(@{ text = $Text; href = $Href }) }
    @{ parts = $p; bold = [bool]$Bold; collapsed = [bool]$Collapsed; children = @($Children | Where-Object { $null -ne $_ }) }
}

function Get-LinesPlainText {
    <# Plain text of a line list: the parts of each line joined, lines joined with newlines. #>
    param([object[]]$Lines = @())
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in @($Lines)) {
        if ($null -eq $l) { continue }
        if ($l -is [string]) { $out.Add($l); continue }
        $out.Add((@($l['parts']) | ForEach-Object { [string]$_['text'] }) -join '')
        $kids = @($l['children'] | Where-Object { $null -ne $_ })
        if ($kids.Count) { $out.Add((Get-LinesPlainText -Lines $kids)) }
    }
    $out -join "`n"
}

function Get-SummaryHash {
    <# Hash of an outline's plain text with white space collapsed: the same text gives the same
       hash however OneNote splits it into lines. 16 hex characters. #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $n = if ($Text) { ($Text -replace '\s+', ' ').Trim() } else { '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($n)) } finally { $sha.Dispose() }
    (($b[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-SummaryEdited {
    <# True when the summary outline's text no longer matches the hash stored when the app wrote
       it. No stored hash = the app never recorded one: treated as not edited. #>
    param([AllowEmptyString()][string]$OutlineText, [AllowEmptyString()][string]$StoredHash)
    if (-not $StoredHash) { return $false }
    (Get-SummaryHash $OutlineText) -ne $StoredHash
}

function New-LinkSummaryPrompt {
    <# The summary prompt. Internal links are read with the user's own Microsoft 365 access, web
       links with web grounding. The reply contract is one JSON object:
       { readable, problem, title, where, kind, summary, keyFacts, useFor, sensitivity }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][ValidateSet('Internal links', 'Web links')][string]$Bucket, [datetime]$Today = (Get-Date),
        # The request's reference code: Copilot repeats it as "ref" and the link it read as "source",
        # so an answer read from the chat later is only used for this request and this link.
        [string]$Ref = '')
    $internal = $Bucket -eq 'Internal links'
    $kinds = if ($internal) { $script:InternalKinds } else { $script:WebKinds }
    $sb = New-Object System.Text.StringBuilder
    if ($internal) {
        [void]$sb.AppendLine('Open this Microsoft 365 item with my own access and summarize it for my personal wiki.')
    } else {
        [void]$sb.AppendLine('Read this web page and summarize it for my personal wiki.')
    }
    [void]$sb.AppendLine("Today is $($Today.ToString('yyyy-MM-dd')).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("URL: $Url")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Reply with exactly one JSON object and nothing else: no Markdown, no code fence, no text before or after it.')
    $refPart = if ($Ref) { ', "ref": "' + $Ref + '", "source": "..."' } else { '' }
    [void]$sb.AppendLine('{"readable": true, "problem": "", "title": "...", "where": "...", "kind": "...", "summary": "...", "keyFacts": ["..."], "useFor": "...", "sensitivity": ""' + $refPart + '}')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Rules:')
    if ($Ref) {
        [void]$sb.AppendLine("- ref: always exactly ""$Ref"" (the reference of this request).")
        [void]$sb.AppendLine('- source: the URL you read, exactly as given above.')
    }
    [void]$sb.AppendLine('- readable: false when you cannot open or read it; then problem is "no-access", "not-found" or "other" and the other fields may stay empty.')
    if ($internal) {
        [void]$sb.AppendLine('- title: the site, page or file name.')
        [void]$sb.AppendLine('- where: the site, library and owner, or the team and channel.')
    } else {
        [void]$sb.AppendLine('- title: the page title.')
        [void]$sb.AppendLine('- where: the domain.')
    }
    [void]$sb.AppendLine("- kind: one of $($kinds -join ', ').")
    [void]$sb.AppendLine('- summary: 3 to 5 sentences: what it is and why it matters.')
    [void]$sb.AppendLine('- keyFacts: up to 8 short items: names, dates, numbers, decisions, contacts.')
    [void]$sb.AppendLine('- useFor: one line: when I would come back to this.')
    if ($internal) { [void]$sb.AppendLine('- sensitivity: the sensitivity label of the item as shown to you, or "".') }
    else { [void]$sb.AppendLine('- sensitivity: "".') }
    [void]$sb.AppendLine('- A summary only: never copy the full text.')
    [void]$sb.AppendLine('- Use straight double quotes only.')
    $sb.ToString()
}

function Limit-LcText {
    param([string]$Text, [int]$Max)
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 3).TrimEnd() + '...' }
    $t
}

function ConvertTo-LinkSummary {
    <# Validates a parsed summary reply. Returns @{ ok; readable; problem; error; summary = @{ title;
       where; kind; summary; keyFacts; useFor; sensitivity } }. A reply that says it could not
       read the source is ok = $true, readable = $false. Pure. #>
    [CmdletBinding()]
    param($Reply, [Parameter(Mandatory)][string]$Bucket)
    if ($null -eq $Reply) { return @{ ok = $false; readable = $false; problem = ''; error = 'The answer holds no JSON object.'; summary = $null } }
    $readable = $true
    $rv = Get-LkProp $Reply 'readable' $true
    if ($rv -is [bool]) { $readable = $rv } elseif ("$rv" -match '^(?i)(false|no|0)$') { $readable = $false }
    $problem = (Get-LkString $Reply 'problem').ToLowerInvariant()
    if (-not $readable) {
        if ($script:Problems -notcontains $problem) { $problem = 'other' }
        return @{ ok = $true; readable = $false; problem = $problem; error = ''; summary = $null }
    }
    $kinds = if ($Bucket -eq 'Internal links') { $script:InternalKinds } else { $script:WebKinds }
    $kind = (Get-LkString $Reply 'kind').ToLowerInvariant() -replace '\s+', '-'
    if ($kinds -notcontains $kind) { $kind = 'other' }
    $facts = @(@(Get-LkProp $Reply 'keyFacts' @()) | Where-Object { $_ -is [string] -and $_.Trim() } | ForEach-Object { Limit-LcText $_ 200 } | Select-Object -First 8)
    $s = @{
        title       = Limit-LcText (Get-LkString $Reply 'title') 120
        where       = Limit-LcText (Get-LkString $Reply 'where') 160
        kind        = $kind
        summary     = Limit-LcText (Get-LkString $Reply 'summary') 1200
        keyFacts    = $facts
        useFor      = Limit-LcText (Get-LkString $Reply 'useFor') 200
        sensitivity = $(if ($Bucket -eq 'Internal links') { Limit-LcText (Get-LkString $Reply 'sensitivity') 60 } else { '' })
    }
    if (-not $s.title) { return @{ ok = $false; readable = $true; problem = ''; error = 'The summary has no title.'; summary = $null } }
    if (-not $s.summary) { return @{ ok = $false; readable = $true; problem = ''; error = 'The summary is empty.'; summary = $null } }
    @{ ok = $true; readable = $true; problem = ''; error = ''; summary = $s }
}

function Get-LinkSummaryText {
    <# The text that linking reads for a link page: summary, key facts and use. #>
    param([Parameter(Mandatory)]$Summary)
    $parts = @([string]$Summary['summary']) + @($Summary['keyFacts']) + @([string]$Summary['useFor'])
    (@($parts | Where-Object { $_ }) -join "`n")
}

function Get-ProblemText {
    param([string]$Problem)
    switch ($Problem) {
        'no-access' { 'no access' }
        'not-found' { 'not found' }
        default { 'the source could not be read' }
    }
}

function New-LinkSummaryLines {
    <# The owned "summary" outline of a link page (fixed shape). $Summary $null = could not be read. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url, $Summary, [string]$Problem = '', [datetime]$Today = (Get-Date))
    $lines = @(New-LinkLine -Parts @(@{ text = 'Link: '; href = '' }, @{ text = $Url; href = $Url }))
    if ($null -eq $Summary) {
        $lines += New-LinkLine -Text ("Could not be read on {0}: {1}." -f $Today.ToString('yyyy-MM-dd'), (Get-ProblemText $Problem))
        return , $lines
    }
    if ($Summary['where']) { $lines += New-LinkLine -Text ('Where: ' + $Summary['where']) }
    if ($Summary['kind']) { $lines += New-LinkLine -Text ('Kind: ' + $Summary['kind']) }
    $lines += New-LinkLine -Text ('Summary: ' + $Summary['summary'])
    $facts = @($Summary['keyFacts'] | Where-Object { $_ })
    if ($facts.Count) { $lines += New-LinkLine -Text 'Key facts:' -Children @($facts | ForEach-Object { New-LinkLine -Text $_ }) }
    if ($Summary['useFor']) { $lines += New-LinkLine -Text ('Use it for: ' + $Summary['useFor']) }
    if ($Summary['sensitivity']) { $lines += New-LinkLine -Text ('Sensitivity: ' + $Summary['sensitivity']) }
    , $lines
}

function New-LinkCheckedLines {
    <# The owned "checked" outline: the date it was summarized (or could not be updated) and the
       collapsed "Earlier summaries" (newest first, at most 3). #>
    [CmdletBinding()]
    param([string]$SummarizedAt = '', [string]$CheckStatus = '', [object[]]$History = @(), [string]$SeenAt = '')
    $first = if ($SummarizedAt) { "Checked: $SummarizedAt" } else { 'Checked: not yet' }
    $lines = @(New-LinkLine -Text $first)
    if ($CheckStatus) { $lines += New-LinkLine -Text $CheckStatus }
    if ($SeenAt) { $lines += New-LinkLine -Text "Seen again: $SeenAt" }
    $h = @($History | Where-Object { $null -ne $_ })
    if ($h.Count) {
        $kids = @(foreach ($e in $h) {
            $label = [string](Get-LkProp $e 'at' '')
            if (Get-LkProp $e 'edited' $false) { $label += ' (edited by you)' }
            $sub = @(New-LinkLine -Text ([string](Get-LkProp $e 'summary' '')))
            foreach ($f in @(Get-LkProp $e 'keyFacts' @())) { if ($f) { $sub += New-LinkLine -Text ('- ' + $f) } }
            New-LinkLine -Text $label -Children $sub
        })
        $lines += New-LinkLine -Text 'Earlier summaries' -Bold -Collapsed -Children $kids
    }
    , $lines
}

function New-LinkNotesLines {
    <# The "Your notes" outline, written once when the page is made and never again. #>
    $head = New-LinkLine -Text 'Your notes' -Bold
    $empty = New-LinkLine -Text ''
    , @($head, $empty)
}

function Compare-LinkSummary {
    <# Old vs new: which fields changed, key facts added and removed. Returns @{ changed; title;
       kind; where; summary; useFor; sensitivity (each $true when changed); factsAdded;
       factsRemoved }. Pure. #>
    [CmdletBinding()]
    param($Old, [Parameter(Mandatory)]$New)
    $norm = { param($s) ([string]$s -replace '\s+', ' ').Trim().ToLowerInvariant() }
    $r = @{ changed = $false; factsAdded = @(); factsRemoved = @() }
    foreach ($f in 'title', 'kind', 'where', 'summary', 'useFor', 'sensitivity') {
        $a = & $norm (Get-LkProp $Old $f '')
        $b = & $norm (Get-LkProp $New $f '')
        $r[$f] = ($a -ne $b)
        if ($r[$f]) { $r.changed = $true }
    }
    $oldFacts = @(@(Get-LkProp $Old 'keyFacts' @()) | Where-Object { $_ })
    $newFacts = @(@(Get-LkProp $New 'keyFacts' @()) | Where-Object { $_ })
    $oldN = @($oldFacts | ForEach-Object { & $norm $_ })
    $newN = @($newFacts | ForEach-Object { & $norm $_ })
    $r.factsAdded = @($newFacts | Where-Object { $oldN -notcontains (& $norm $_) })
    $r.factsRemoved = @($oldFacts | Where-Object { $newN -notcontains (& $norm $_) })
    if ($r.factsAdded.Count -or $r.factsRemoved.Count) { $r.changed = $true }
    $r
}

function Add-SummaryHistory {
    <# Puts the previous summary in front of the history and keeps the last $Keep (default 3). #>
    [CmdletBinding()]
    param([object[]]$History = @(), [Parameter(Mandatory)]$Previous, [string]$At = '', [switch]$Edited, [int]$Keep = 3)
    $e = [ordered]@{ at = $At; summary = [string](Get-LkProp $Previous 'summary' ''); keyFacts = @(@(Get-LkProp $Previous 'keyFacts' @()) | Where-Object { $_ }); edited = [bool]$Edited }
    $all = @($e) + @($History | Where-Object { $null -ne $_ })
    , @($all | Select-Object -First $Keep)
}

function ConvertFrom-LkJson {
    <# A JSON string from a Meta value -> object/array; $Default when empty or broken. #>
    param([AllowEmptyString()][AllowNull()][string]$Text, $Default = $null)
    if (-not $Text) { return $Default }
    try { return (ConvertFrom-Json -InputObject $Text -ErrorAction Stop) } catch { return $Default }
}

function ConvertTo-LkJson {
    param($Value)
    ConvertTo-Json -InputObject $Value -Compress -Depth 6
}

function ConvertTo-SummaryRecord {
    <# A summary object (from JSON or a hashtable) as a plain hashtable. #>
    param($Summary)
    if ($null -eq $Summary) { return $null }
    @{
        title = Get-LkString $Summary 'title'; where = Get-LkString $Summary 'where'; kind = Get-LkString $Summary 'kind'
        summary = Get-LkString $Summary 'summary'; keyFacts = @(@(Get-LkProp $Summary 'keyFacts' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        useFor = Get-LkString $Summary 'useFor'; sensitivity = Get-LkString $Summary 'sensitivity'
    }
}

Export-ModuleMember -Function Get-PastedUrl, New-LinkLine, Get-LinesPlainText, Get-SummaryHash, Test-SummaryEdited, New-LinkSummaryPrompt, ConvertTo-LinkSummary, Get-LinkSummaryText, New-LinkSummaryLines, New-LinkCheckedLines, New-LinkNotesLines, Compare-LinkSummary, Add-SummaryHistory, ConvertFrom-LkJson, ConvertTo-LkJson, ConvertTo-SummaryRecord
