# Add or Ask from one input (FEASIBILITY.md, "Add or Ask from one input"): fixed, tested rules, no
# model. Pure functions only: the server (lib/Server.psm1) calls them, nothing here reads or writes
# anything. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
#
# Since 2026-11-18 (operator: "expand the detection to differentiate between add or ask") the text is
# scored, not decided by the first rule that matches:
#   1. An explicit choice wins: the Add or Ask button (mode), or a "+" / "?" prefix. So do a link on
#      its own and a company (SharePoint, OneDrive, Teams) link with your own words (Add: the link's
#      page, the words in "Your notes"; lib/Ingest.psm1 does the same).
#   2. Every other signal adds points to Ask or to Add (the tables below, EN + NL). The side that
#      leads by $Margin or more wins (rule 2 = ask, 3 = add); a smaller lead, or no signal at all,
#      is unclear (rule 4) and the window offers both. The reason names the strongest signals.
# The examples the rules must get right are in tests/fixtures/intent-samples.json (tests/Intent.Tests.ps1).
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'LinkCapture.psm1')        # Get-LinkWithNotes
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')  # Get-LinkBucket, ConvertTo-NormalizedUrl

$script:ShortLimit = 300
$script:LongLimit = 1000
$script:Margin = 2

# Words that start a question, English then Dutch.
$script:QuestionWords = @(
    'what', 'how', 'why', 'when', 'who', 'whom', 'whose', 'where', 'which', 'whats', 'hows', 'whos', 'wheres',
    'wat', 'hoe', 'waarom', 'wanneer', 'wie', 'waar', 'welke', 'welk', 'hoeveel', 'waarover', 'waarmee', 'wiens'
)
# Helper verbs that open a yes/no question ("Is the portal live", "Kan ik ..."). Dutch puts the verb
# first in every question, so the list is longer there.
$script:HelperVerbs = @(
    'can', 'could', 'is', 'are', 'was', 'were', 'do', 'does', 'did', 'should', 'will', 'would', 'has', 'have', 'had', 'may', 'might', 'shall', 'must',
    'kan', 'kun', 'kunnen', 'kunt', 'is', 'zijn', 'was', 'waren', 'heeft', 'hebben', 'heb', 'hadden', 'moet', 'moeten', 'wordt', 'worden', 'mag', 'mogen', 'zal', 'zullen', 'zou', 'zouden', 'gaat', 'gaan', 'staat', 'klopt'
)
# Requests to the wiki ("Summarize ...", "Vat ... samen"): matched at the start, case-insensitive.
$script:RequestOpenings = @(
    'tell me', 'explain', 'summarize', 'summarise', 'compare', 'give me', 'show me', 'show', 'list', 'find', 'search', 'look up',
    'what about', 'any news', 'remind me', 'help me', 'i need to know', 'i want to know', 'do we have', 'did we',
    'vertel', 'leg uit', 'leg me uit', 'vat samen', 'vat', 'geef', 'geef me', 'zoek', 'toon', 'laat zien', 'vergelijk', 'noem', 'weet jij', 'hebben we', 'staat er'
)
# Openings that mean "keep this" (case-insensitive).
$script:StatementPrefixes = @(
    'we decided', 'decided:', 'decision:', 'note:', 'note to self', 'todo', 'to do:', 'fyi', 'remember:', 'idea:', 'add:', 'log:',
    'we hebben besloten', 'besloten:', 'besluit:', 'notitie:', 'let op:', 'onthoud:', 'idee:', 'ter info'
)
# A note's own heading, at the start of the text or of a line.
$script:NoteHeadings = '(?im)^\s*(meeting notes|notes|minutes|agenda|action items|actions|summary|decisions|next steps|takeaways|notulen|aantekeningen|actiepunten|acties|samenvatting|besluiten|vervolgstappen)\s*[:\-]?\s*$|^\s*(meeting notes|minutes|action items|next steps|notulen|actiepunten|vervolgstappen)\s*:'
# Report openings: what happened ("Met Ada today", "Called the supplier", "Vandaag gesproken met").
$script:ReportOpenings = '(?i)^\s*(today|yesterday|this morning|this afternoon|vandaag|gisteren|vanochtend|vanmiddag|met|spoke|talked|called|had a|discussed|agreed|sent|received|reviewed|finished|started|attended|visited|we agreed|we discussed|we met|we had|i met|i spoke|i called|i talked|i had|i sent|i received|i finished|call with|chat with|meeting with|gesprek met|overleg met|gebeld|gesproken|afgesproken|besproken|gemaild|ontvangen|afgerond)\b'
# Mail or meeting header lines (EN + NL, as Outlook writes them).
$script:HeaderPattern = '(?im)^\s*(from|to|cc|sent|subject|date|when|where|attendees|required|organizer|van|aan|verzonden|onderwerp|datum|wanneer|locatie|deelnemers|organisator)\s*:\s*\S'
$script:DateStart = '(?i)^\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[-/.]\d{1,2}([-/.]\d{2,4})?|\d{1,2}:\d{2}|monday|tuesday|wednesday|thursday|friday|saturday|sunday|maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)\b'
$script:LinkPattern = '(?i)(https?://|www\.)\S+'
# A bullet and a typographic apostrophe, made from their codes (this file stays ASCII).
$script:Bullet = [string][char]0x2022
$script:Apostrophes = "'" + [char]0x2019
$script:ListLine = '(?m)^\s*([-*' + $script:Bullet + ']|\d{1,2}[.)])\s+\S'

function Get-IntentModes { , @('auto', 'add', 'ask') }

function Test-SeveralParagraphs([string]$Text) {
    <# True when the text has an empty line between two parts that hold text. #>
    $Text -match '\S\s*\r?\n\s*\r?\n\s*\S'
}

function Get-FirstWord([string]$Text) {
    $m = [regex]::Match($Text, ('^\s*([\p{L}]+)([' + $script:Apostrophes + '][\p{L}]+)?'))
    if ($m.Success) { $m.Groups[1].Value + $(if ($m.Groups[2].Success) { $m.Groups[2].Value -replace ('[' + $script:Apostrophes + ']'), '' } else { '' }) } else { '' }
}

function Get-QuestionWord([string]$Text) {
    <# The question word the text starts with (as typed), or ''. "What's" counts as "whats". #>
    $w = Get-FirstWord $Text
    if ($w -and $script:QuestionWords -contains $w.ToLowerInvariant()) { return $w }
    ''
}

function Get-HelperVerb([string]$Text) {
    <# The helper verb a question starts with ("Is the portal live"), or ''. A verb on its own, or one
       followed by a colon, is not a question. #>
    $m = [regex]::Match($Text, '^\s*([\p{L}]+)\s+[\p{L}\d]')
    if (-not $m.Success) { return '' }
    $w = $m.Groups[1].Value
    if ($script:HelperVerbs -contains $w.ToLowerInvariant()) { return $w }
    ''
}

function Get-Opening([string]$Text, [string[]]$List) {
    <# The entry of $List the text starts with (as typed), whole words only, or ''. #>
    $t = $Text.TrimStart()
    $lower = $t.ToLowerInvariant()
    foreach ($p in ($List | Sort-Object Length -Descending)) {
        if (-not $lower.StartsWith($p)) { continue }
        $next = if ($t.Length -gt $p.Length) { $t[$p.Length] } else { ' ' }
        if ($p.EndsWith(':') -or -not [char]::IsLetterOrDigit($next)) { return $t.Substring(0, $p.Length) }
    }
    ''
}

function Get-StatementPrefix([string]$Text) { Get-Opening $Text $script:StatementPrefixes }

function Get-LastSentence([string]$Text) {
    <# The last sentence of the text: its last non-empty line, from the last ". " or "! " on. #>
    $lines = @($Text -split '\r?\n' | Where-Object { $_.Trim() })
    if (-not $lines.Count) { return '' }
    $last = $lines[$lines.Count - 1].Trim()
    $parts = [regex]::Split($last, '(?<=[.!])\s+')
    $parts[$parts.Count - 1].Trim()
}

function Test-QuestionSentence([string]$Sentence) {
    <# A sentence that asks: it holds "?" (also before a closing word: "Who owns it? thanks"), or
       opens with a question word, helper verb or request. #>
    if (-not $Sentence) { return $false }
    if ($Sentence -match '\?') { return $true }
    [bool]((Get-QuestionWord $Sentence) -or (Get-HelperVerb $Sentence) -or (Get-Opening $Sentence $script:RequestOpenings))
}

function New-IntentResult([string]$Intent, [string]$Reason, [int]$Rule, [int]$Ask = 0, [int]$Add = 0) {
    [pscustomobject]@{ intent = $Intent; reason = $Reason; rule = $Rule; askScore = $Ask; addScore = $Add }
}

function Get-IntentSignals {
    <# The scored signals of a text: @(@{ side = ask|add; points; why }). Pure. #>
    param([string]$Text)
    $t = $Text
    $s = New-Object System.Collections.Generic.List[object]
    $add = { param($side, $points, $why) $s.Add(@{ side = $side; points = $points; why = $why }) }
    $long = $t.Length -gt $script:ShortLimit
    $paragraphs = Test-SeveralParagraphs $t
    $lines = @($t -split '\r?\n' | Where-Object { $_.Trim() })

    # Ask: the opening.
    $qWord = Get-QuestionWord $t
    $helper = if ($qWord) { '' } else { Get-HelperVerb $t }
    $request = Get-Opening $t $script:RequestOpenings
    if ($qWord) { & $add 'ask' 3 "starts with ""$qWord""" }
    elseif ($request) { & $add 'ask' 3 "asks your wiki (""$request"")" }
    elseif ($helper) { & $add 'ask' 2 "starts with ""$helper""" }
    # Ask: a question mark at the end, or in the last sentence ("Who owns it? thanks").
    $last = Get-LastSentence $t
    if ($t.TrimEnd().EndsWith('?')) { & $add 'ask' 3 'ends with "?"' }
    elseif ($last -match '\?') { & $add 'ask' 2 'its last sentence asks something' }
    # A question after longer text: the last sentence asks, the text above is context.
    if (($long -or $paragraphs -or $lines.Count -gt 2) -and $last -ne $t.Trim() -and (Test-QuestionSentence $last)) { & $add 'ask' 3 'a question after the text above it' }
    # Short and one sentence: questions usually are.
    if (-not $long -and -not $paragraphs -and $lines.Count -le 1 -and ($qWord -or $helper -or $request -or $t.Contains('?'))) { & $add 'ask' 1 'one short sentence' }

    # Add: what a note, a mail or a log looks like.
    $prefix = Get-StatementPrefix $t
    if ($prefix) { & $add 'add' 4 "reads as a statement (starts with ""$prefix"")" }
    if ([regex]::Matches($t, $script:HeaderPattern).Count -ge 2) { & $add 'add' 5 'looks like a pasted mail or meeting (headers such as From: or Subject:)' }
    if ($t -match $script:NoteHeadings) { & $add 'add' 3 'has a note heading (such as "Action items" or "Notulen")' }
    if ($t -match '(?m)^\s*#{1,6}\s+\S') { & $add 'add' 3 'has a heading' }
    if ([regex]::Matches($t, $script:ListLine).Count -ge 2) { & $add 'add' 3 'has a list' }
    $report = [regex]::Match($t, $script:ReportOpenings)
    if ($report.Success) { & $add 'add' 2 "reports what happened (starts with ""$($report.Value.Trim())"")" }
    if ($t -match $script:DateStart) { & $add 'add' 2 'starts with a date or time' }
    if ($t.Length -gt $script:LongLimit) { & $add 'add' 5 "is long text (over $($script:LongLimit) characters)" }
    elseif ($long) { & $add 'add' 3 "is longer text (over $($script:ShortLimit) characters)" }
    if ($paragraphs) { & $add 'add' 2 'has several paragraphs' }
    $sentences = @([regex]::Matches($t, '[.!](\s|$)')).Count
    if ($sentences -ge 2 -and -not $t.Contains('?')) { & $add 'add' 2 'is several sentences without a question' }
    if ($t -match $script:LinkPattern) { & $add 'add' 1 'has a link' }
    , $s.ToArray()
}

function Format-IntentWhy([object[]]$Signals, [string]$Side, [int]$Max = 2) {
    <# The strongest signals of one side; equal ones keep the order they were found in. #>
    $i = 0
    $ranked = @(foreach ($x in $Signals) { $i++; if ($x.side -eq $Side) { [pscustomobject]@{ p = [int]$x.points; n = $i; why = $x.why } } })
    (@($ranked | Sort-Object @{ Expression = 'p'; Descending = $true }, @{ Expression = 'n'; Descending = $false } | Select-Object -First $Max | ForEach-Object { $_.why })) -join ', '
}

function Get-Intent {
    <# Whether the input is an Add or an Ask: @{ intent = add|ask|unclear|empty; reason; rule;
       askScore; addScore }. $Mode: auto (default), add or ask; an explicit add/ask always wins. reason
       is a short phrase for "Will ask your wiki: <reason>". $InternalHosts / $CompanyNames: the
       vault's link rules, so a company link with words is named as the Add it will be (optional). #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text = '', [string]$Mode = 'auto', [string[]]$InternalHosts = @(), [string[]]$CompanyNames = @())
    $m = "$Mode".Trim().ToLowerInvariant()
    if (-not $m) { $m = 'auto' }
    if ((Get-IntentModes) -notcontains $m) { throw "Unknown mode '$Mode' (auto, add or ask)." }
    $t = "$Text".Trim()

    # 1. Explicit choice, and what Add always does.
    if ($m -eq 'add') { return New-IntentResult 'add' 'you chose Add' 1 }
    if ($m -eq 'ask') { return New-IntentResult 'ask' 'you chose Ask' 1 }
    if (-not $t) { return New-IntentResult 'empty' 'type, paste or drop something' 0 }
    if ($t.StartsWith('+')) { return New-IntentResult 'add' 'it starts with "+"' 1 }
    if ($t.StartsWith('?')) { return New-IntentResult 'ask' 'it starts with "?"' 1 }
    if ($t -match '^(?i)(https?://|www\.)\S+$') { return New-IntentResult 'add' 'it is a link on its own' 1 }
    $ln = Get-LinkWithNotes $t
    if ($ln -and (Get-LinkBucket -Url (ConvertTo-NormalizedUrl -Url $ln.url) -InternalHosts $InternalHosts -CompanyNames $CompanyNames) -eq 'Internal links') {
        return New-IntentResult 'add' 'a company link with your words: its page is summarized and your words become your notes' 1
    }

    # 2. Scores.
    $sig = Get-IntentSignals $t   # returned with ',': assigned as is (@() around the call would nest it)
    # Summed by hand: Measure-Object -Property does not read hashtable keys in Windows PowerShell 5.1.
    $ask = 0; $add = 0
    foreach ($x in $sig) { if ($x.side -eq 'ask') { $ask += [int]$x.points } else { $add += [int]$x.points } }
    # A question about a web address: Ask reads your wiki only, so it is never asked by itself.
    if ($ask -ge $add + $script:Margin -and $t -match $script:LinkPattern) { return New-IntentResult 'unclear' 'it asks about a link: Ask reads your wiki only, Add reads the link' 4 $ask $add }
    if ($ask -ge $add + $script:Margin) { return New-IntentResult 'ask' "it reads as a question ($(Format-IntentWhy $sig 'ask'))" 2 $ask $add }
    if ($add -ge $ask + $script:Margin) { return New-IntentResult 'add' "it $(Format-IntentWhy $sig 'add')" 3 $ask $add }
    if (-not $ask -and -not $add) { return New-IntentResult 'unclear' 'a few words, neither a question nor a note yet' 4 }
    New-IntentResult 'unclear' "it could be a question ($(Format-IntentWhy $sig 'ask' 1)) or something to keep (it $(Format-IntentWhy $sig 'add' 1))" 4 $ask $add
}

function Get-SubmitMessage {
    <# What the server answers to a submit while Add and Ask are not built yet (step 1). #>
    [CmdletBinding()]
    param([string]$Intent)
    switch ($Intent) {
        'add' { 'Adding comes in the next step' }
        'ask' { 'Asking comes in the next step' }
        default { 'Adding and asking come in the next steps' }
    }
}

Export-ModuleMember -Function Get-Intent, Get-IntentModes, Get-IntentSignals, Get-SubmitMessage
