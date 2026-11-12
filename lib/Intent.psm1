# Add or Ask from one input (FEASIBILITY.md, "Add or Ask from one input"): fixed, tested rules, no
# model. Pure functions only: the server (lib/Server.psm1) calls them, nothing here reads or writes
# anything. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
# The rules, in order:
#   1. An explicit choice wins: the Add or Ask button (mode), or a "+" / "?" prefix.
#   2. Ask: ends with "?" or starts with a question word (EN + NL), AND is short: one paragraph,
#      under 300 characters, no link.
#   3. Add: a link on its own, longer text (over 300 characters or several paragraphs), pasted
#      mail or meeting headers, or a statement prefix ("We decided", "Note:", "TODO").
#   4. Otherwise unclear (Copilot decides inside the same call, later).
Set-StrictMode -Version 2.0

$script:ShortLimit = 300

# Question words that start a question, English then Dutch (the mock-up's list).
$script:QuestionWords = @(
    'what', 'how', 'why', 'when', 'who', 'whom', 'whose', 'where', 'which', 'find', 'show', 'list',
    'wat', 'hoe', 'waarom', 'wanneer', 'wie', 'waar', 'welke', 'welk', 'zoek', 'toon'
)

# Statement prefixes that mean "keep this" (case-insensitive, at the start of the text).
$script:StatementPrefixes = @(
    'we decided', 'decided:', 'decision:', 'note:', 'todo', 'to do:', 'fyi', 'remember:',
    'we hebben besloten', 'besloten:', 'besluit:', 'notitie:', 'let op:', 'onthoud:'
)

# Header lines of a pasted mail or meeting (EN + NL, as Outlook writes them).
$script:HeaderPattern = '(?im)^\s*(from|to|cc|sent|subject|date|when|where|attendees|required|organizer|van|aan|verzonden|onderwerp|datum|wanneer|locatie|deelnemers|organisator)\s*:\s*\S'

$script:LinkPattern = '(?i)(https?://|www\.)\S+'

function Get-IntentModes { , @('auto', 'add', 'ask') }

function Test-SeveralParagraphs([string]$Text) {
    <# True when the text has an empty line between two parts that hold text. #>
    $Text -match '\S\s*\r?\n\s*\r?\n\s*\S'
}

function Get-QuestionWord([string]$Text) {
    <# The question word the text starts with (as typed), or ''. #>
    $m = [regex]::Match($Text, '^\s*([\p{L}]+)')
    if (-not $m.Success) { return '' }
    $w = $m.Groups[1].Value
    if ($script:QuestionWords -contains $w.ToLowerInvariant()) { return $w }
    ''
}

function Get-StatementPrefix([string]$Text) {
    <# The statement prefix the text starts with (as typed), or ''. #>
    $t = $Text.TrimStart()
    foreach ($p in $script:StatementPrefixes) {
        if ($t.Length -ge $p.Length -and $t.Substring(0, $p.Length).ToLowerInvariant() -eq $p) {
            # A word prefix must end there ("TODO" yes, "Todos" no).
            $next = if ($t.Length -gt $p.Length) { $t[$p.Length] } else { ' ' }
            if ($p.EndsWith(':') -or -not [char]::IsLetterOrDigit($next)) { return $t.Substring(0, $p.Length) }
        }
    }
    ''
}

function New-IntentResult([string]$Intent, [string]$Reason, [int]$Rule) {
    [pscustomobject]@{ intent = $Intent; reason = $Reason; rule = $Rule }
}

function Get-Intent {
    <# Whether the input is an Add or an Ask: @{ intent = add|ask|unclear|empty; reason; rule }.
       $Mode: auto (default), add or ask; an explicit add/ask always wins. reason is a short phrase
       for "Will ask your wiki: <reason>". #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text = '', [string]$Mode = 'auto')
    $m = "$Mode".Trim().ToLowerInvariant()
    if (-not $m) { $m = 'auto' }
    if ((Get-IntentModes) -notcontains $m) { throw "Unknown mode '$Mode' (auto, add or ask)." }
    $t = "$Text".Trim()

    # 1. Explicit choice.
    if ($m -eq 'add') { return New-IntentResult 'add' 'you chose Add' 1 }
    if ($m -eq 'ask') { return New-IntentResult 'ask' 'you chose Ask' 1 }
    if (-not $t) { return New-IntentResult 'empty' 'type, paste or drop something' 0 }
    if ($t.StartsWith('+')) { return New-IntentResult 'add' 'it starts with "+"' 1 }
    if ($t.StartsWith('?')) { return New-IntentResult 'ask' 'it starts with "?"' 1 }

    $long = $t.Length -gt $script:ShortLimit
    $paragraphs = Test-SeveralParagraphs $t
    $hasLink = $t -match $script:LinkPattern
    $short = -not $long -and -not $paragraphs -and -not $hasLink

    # 2. Ask: reads as a question and is short.
    $qWord = Get-QuestionWord $t
    $qMark = $t.EndsWith('?')
    if ($short -and ($qWord -or $qMark)) {
        $why = @()
        if ($qWord) { $why += "starts with `"$qWord`"" }
        if ($qMark) { $why += 'ends with "?"' }
        return New-IntentResult 'ask' "it reads as a question ($($why -join ', '))" 2
    }

    # 3. Add.
    if ($t -match '^(?i)(https?://|www\.)\S+$') { return New-IntentResult 'add' 'it is a link on its own' 3 }
    if ([regex]::Matches($t, $script:HeaderPattern).Count -ge 2) { return New-IntentResult 'add' 'it looks like a pasted mail or meeting (headers such as From: or Subject:)' 3 }
    $prefix = Get-StatementPrefix $t
    if ($prefix) { return New-IntentResult 'add' "it reads as a statement (starts with `"$prefix`")" 3 }
    if ($long) { return New-IntentResult 'add' "it is longer text (over $($script:ShortLimit) characters)" 3 }
    if ($paragraphs) { return New-IntentResult 'add' 'it has several paragraphs' 3 }

    # 4. Unclear.
    if ($hasLink) { return New-IntentResult 'unclear' 'it has a link and other text' 4 }
    New-IntentResult 'unclear' 'it is short, without a question mark, a question word or a statement' 4
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

Export-ModuleMember -Function Get-Intent, Get-IntentModes, Get-SubmitMessage
