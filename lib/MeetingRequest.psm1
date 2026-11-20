# Meetings of other days from the box (operator, 2026-11-20: "through the input field, fetch
# meetings from other days ... or from multiple days, for example for a daily meeting all
# occurrences for that series within a given week"). Reads a short command such as
#   meetings yesterday | meetings 2026-11-17 | meetings 17-11 to 19-11 | meetings last 3 days
#   Daily Standup meetings this week | fetch meetings of "Daily Standup" last week | vergaderingen gisteren
#   fetch yesterday | get Daily Standup this week | import last week | fetch yesterday's meetings
# into the days to list (one Copilot question per day: kit P10 found that a list of several days
# comes back empty) and an optional series filter. Nothing is read or written here. Pure; keep this
# file ASCII (PS 5.1 reads BOM-less files as ANSI).
Set-StrictMode -Version 2.0

$script:MaxDays = 14
$script:MaxLength = 250   # Teams titles can be long: "Daily Sync | A & B | Platform Governance"
$script:Inv = [Globalization.CultureInfo]::InvariantCulture

# The word that makes it a meetings command (plural only: "meeting with Ada yesterday" is a note).
$script:MeetWord = '(?:teams[\s-]+)?(?:meetings|vergaderingen)'
# A verb in front: "fetch meetings ...", "haal vergaderingen van gisteren op".
$script:Verb = '^(?:please\s+)?(?:fetch|get|import|load|pull|grab|list|show|haal|ophalen|toon|importeer)\b\s*'
# Words around the series that are not part of it.
$script:Filler = @('all', 'my', 'the', 'of', 'from', 'for', 'on', 'in', 'occurrences', 'series', 'alle', 'mijn', 'de', 'het', 'van', 'voor', 'op', 'uit', 'reeks', 'and', 'en')
# Words that introduce the series ("with the topic of Daily Standup", "called Daily Standup", "met
# het onderwerp ..."; operator, 2026-11-20): everything after them, up to a time, is the series.
$script:SeriesMarker = '(?i)(?:^|\s)(?:(?:(?:with|having|for|on|of|met|van|voor)\s+)?(?:the\s+|a\s+|het\s+|de\s+)?(?:topic|title|subject|name|series|onderwerp|titel|naam|reeks)(?:\s+(?:of|is|van))?\s*:?|called|named|titled|genaamd|getiteld)(?=\s)'
# Openings of a question about meetings ("which meetings last week", "what meetings ..."): Ask's.
$script:QuestionStart = '^(?:(?:show|tell|give|toon|geef)\s+(?:me|us|mij)|what|which|how|who|whom|why|when|where|did|do|does|were|was|are|is|can|could|wat|welke|welk|hoe|wie|waarom|wanneer|waar|hadden|had|zijn|waren|kan|heb|hebben)\b'

$script:Weekdays = @{
    monday = 1; tuesday = 2; wednesday = 3; thursday = 4; friday = 5; saturday = 6; sunday = 0
    maandag = 1; dinsdag = 2; woensdag = 3; donderdag = 4; vrijdag = 5; zaterdag = 6; zondag = 0
}
$script:WeekdayWord = '(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)'
$script:DateWord = '(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[-/.]\d{1,2}(?:[-/.]\d{2,4})?)'
$script:DayWord = "(?:$script:DateWord|$script:WeekdayWord|today|yesterday|tomorrow|vandaag|gisteren|eergisteren|morgen)"
$script:RangeSep = '(?:to|until|till|through|thru|tot\s+en\s+met|tot|t/m|tm|-)'

function ConvertTo-IsoDay([datetime]$Date) { $Date.ToString('yyyy-MM-dd', $script:Inv) }

function Get-MondayOf([datetime]$Date) {
    <# The Monday of $Date's week (weeks start on Monday). #>
    $back = ([int]$Date.DayOfWeek + 6) % 7
    $Date.Date.AddDays(-$back)
}

function Resolve-RequestDay {
    <# One day word as a date: a date (yyyy-mm-dd, or day-month first: 17-11, 17/11/2026), a weekday
       (its latest one up to today, or before today with "last"), today, yesterday. $null when it is
       no date. A day-month without a year is the latest such day up to today. #>
    param([Parameter(Mandatory)][string]$Word, [Parameter(Mandatory)][datetime]$Today, [switch]$Before)
    $w = $Word.Trim().ToLowerInvariant()
    $t = $Today.Date
    switch -Regex ($w) {
        '^(today|vandaag)$' { return $t }
        '^(yesterday|gisteren)$' { return $t.AddDays(-1) }
        '^eergisteren$' { return $t.AddDays(-2) }
        '^(tomorrow|morgen)$' { return $t.AddDays(1) }
    }
    if ($script:Weekdays.ContainsKey($w)) {
        $back = ([int]$t.DayOfWeek - $script:Weekdays[$w] + 7) % 7
        if ($Before -and $back -eq 0) { $back = 7 }
        return $t.AddDays(-$back)
    }
    $y = 0; $m = 0; $d = 0
    if ($w -match '^(\d{4})-(\d{1,2})-(\d{1,2})$') { $y = [int]$Matches[1]; $m = [int]$Matches[2]; $d = [int]$Matches[3] }
    elseif ($w -match '^(\d{1,2})[-/.](\d{1,2})(?:[-/.](\d{2,4}))?$') {
        $d = [int]$Matches[1]; $m = [int]$Matches[2]
        $y = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        if ($y -gt 0 -and $y -lt 100) { $y += 2000 }
    } else { return $null }
    if ($m -lt 1 -or $m -gt 12 -or $d -lt 1) { return $null }
    $year = if ($y) { $y } else { $t.Year }
    if ($year -lt 1 -or $year -gt 9999 -or $d -gt [datetime]::DaysInMonth($year, $m)) { return $null }
    $r = New-Object datetime $year, $m, $d
    if (-not $y -and $r -gt $t) {
        # No year given and still to come this year: the same day last year.
        if ($d -gt [datetime]::DaysInMonth($year - 1, $m)) { return $null }
        $r = New-Object datetime ($year - 1), $m, $d
    }
    $r
}

function Get-WorkDays([datetime]$From, [datetime]$To) {
    <# Monday to Friday from $From to $To (both included). #>
    $out = New-Object System.Collections.Generic.List[datetime]
    for ($x = $From.Date; $x -le $To.Date; $x = $x.AddDays(1)) { if ($x.DayOfWeek -ne 'Saturday' -and $x.DayOfWeek -ne 'Sunday') { $out.Add($x) } }
    , $out.ToArray()
}

function Get-AllDays([datetime]$From, [datetime]$To) {
    $out = New-Object System.Collections.Generic.List[datetime]
    for ($x = $From.Date; $x -le $To.Date; $x = $x.AddDays(1)) { $out.Add($x) }
    , $out.ToArray()
}

function Find-WhenPhrase {
    <# The when-phrase at the end of $Text: @{ index; length; dates (datetime[]); error } or $null. #>
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][datetime]$Today, [switch]$Anywhere)
    $t = $Today.Date
    $lead = '(?:^|\s)(?:(?:on|op|of|from|for|in|van|voor|uit|during|tijdens)\s+)?'
    $rules = @(
        # A range of two days: "17-11 to 19-11", "from monday to wednesday", "van maandag tot woensdag".
        @{ re = "$lead(?:from\s+|van(?:af)?\s+)?($script:DayWord)\s*$script:RangeSep\s*($script:DayWord)\s*$"; get = {
                param($m)
                $a = Resolve-RequestDay $m.Groups[1].Value $t
                $b = Resolve-RequestDay $m.Groups[2].Value $t
                if ($null -eq $a -or $null -eq $b) { return $null }
                # "monday to wednesday" read as weekdays of one week: the end may not come before the start.
                if ($b -lt $a -and $m.Groups[2].Value -match "^$script:WeekdayWord$") { $b = $b.AddDays(7) }
                if ($b -lt $a) { $x = $a; $a = $b; $b = $x }
                Get-AllDays $a $b
            }
        }
        @{ re = "$lead(this|deze|current|huidige)\s+(work\s*)?week\s*$"; get = { param($m) $mo = Get-MondayOf $t; Get-WorkDays $mo $mo.AddDays(4) } }
        @{ re = "$lead(last|previous|past|vorige|afgelopen)\s+(work\s*)?week\s*$"; get = { param($m) $mo = (Get-MondayOf $t).AddDays(-7); Get-WorkDays $mo $mo.AddDays(4) } }
        @{ re = "$lead(?:the\s+)?(?:last|past|previous|afgelopen|laatste|vorige)\s+(\d{1,2})\s+(work\s*days|workdays|werkdagen|days|dagen)\s*$"; get = {
                param($m)
                $n = [int]$m.Groups[1].Value
                if ($n -lt 1) { return $null }
                if ($m.Groups[2].Value -match '^(work|werk)') {
                    $out = New-Object System.Collections.Generic.List[datetime]
                    for ($x = $t; $out.Count -lt $n -and $x -gt $t.AddDays(-100); $x = $x.AddDays(-1)) { if ($x.DayOfWeek -ne 'Saturday' -and $x.DayOfWeek -ne 'Sunday') { $out.Insert(0, $x) } }
                    return , $out.ToArray()
                }
                Get-AllDays $t.AddDays(1 - $n) $t
            }
        }
        @{ re = "$lead(?:(last|vorige)\s+)?($script:DayWord)\s*$"; get = {
                param($m)
                $d = Resolve-RequestDay $m.Groups[2].Value $t -Before:([bool]$m.Groups[1].Value)
                if ($null -eq $d) { return $null }
                , @($d)
            }
        }
    )
    foreach ($r in $rules) {
        # -Anywhere: the phrase may stand in the middle ("this week Daily Standup"), up to a space.
        # Every rule above ends in the 4 characters \s*$, which this swaps for a look-ahead.
        $re = if ($Anywhere) { $r.re.Substring(0, $r.re.Length - 4) + '(?=\s|$)' } else { $r.re }
        $m = [regex]::Match($Text, $re, 'IgnoreCase')
        if (-not $m.Success) { continue }
        $dates = & $r.get $m
        if ($null -eq $dates) { return @{ index = $m.Index; length = $m.Length; dates = @(); error = 'That is not a date ObsidiNote can read: write it as yyyy-mm-dd or day-month, such as 17-11.' } }
        return @{ index = $m.Index; length = $m.Length; dates = @($dates); error = '' }
    }
    $null
}

function Get-MeetingRequest {
    <# A request for the Teams meetings of other days, read from the box: @{ days = @(yyyy-mm-dd,
       oldest first); series (the series filter as typed, or ''); when (the time phrase as typed, or
       'today'); error ('' or why it cannot be fetched) }, or $null when the text is not such a
       request. Days after $Today are left out (no notes yet); at most 14 days. Pure. #>
    param([AllowEmptyString()][string]$Text = '', [datetime]$Today = (Get-Date).Date)
    $t = ([regex]::Replace("$Text", '\s+', ' ')).Trim().TrimEnd('.', '!')
    if (-not $t -or $t.Length -gt $script:MaxLength -or "$Text".Trim() -match '\r|\n' -or $t.Contains('?')) { return $null }
    if ($t -match $script:QuestionStart) { return $null }
    # A quoted series: "Daily Standup" or 'Daily Standup' (straight or typographic quotes).
    $quoted = ''
    $qm = [regex]::Match($t, ('["' + [char]0x201C + [char]0x201D + ']([^"' + [char]0x201C + [char]0x201D + ']{1,100})["' + [char]0x201C + [char]0x201D + ']'))
    if (-not $qm.Success) { $qm = [regex]::Match($t, "(?:^|\s)'([^']{1,100})'(?:\s|$)") }
    if ($qm.Success) { $quoted = $qm.Groups[1].Value.Trim(); $t = ($t.Remove($qm.Index, $qm.Length).Insert($qm.Index, ' ')).Trim() -replace '\s+', ' ' }
    # A series named after a marker word, as typed: "... this week with the topic of Daily Standup".
    if (-not $quoted) {
        $sm = [regex]::Match($t, $script:SeriesMarker)
        $tail = if ($sm.Success) { $t.Substring($sm.Index + $sm.Length).Trim() } else { '' }
        if ($tail) {
            $head = $t.Substring(0, $sm.Index).Trim()
            # A time after the series goes back to the command: "called Daily Standup this week".
            $w = Find-WhenPhrase -Text $tail -Today $Today
            if ($w -and $w.index -gt 0) { $head = "$head $($tail.Substring($w.index).Trim())"; $tail = $tail.Substring(0, $w.index).Trim() }
            $quoted = $tail.Trim(' ', ':', '"', "'")
            $t = $head.Trim()
        }
    }
    # About a subject or with someone: a question for Ask or a note, not a list of days. A quoted
    # series name may hold these words; it is out of $t by now.
    if ($t -match '(?i)\b(about|regarding|with|over|met|waarin|where)\b') { return $null }
    # "yesterday's meetings", "last week's meetings": the time goes after the word.
    $t = [regex]::Replace($t, ("(?i)\b(today|yesterday|this week|last week)['" + [char]0x2019 + "]s\s+($script:MeetWord)\b"), '$2 $1')
    $verb = [regex]::Match($t, $script:Verb, 'IgnoreCase')
    $rest = if ($verb.Success) { $t.Substring($verb.Length) } else { $t }
    $rest = [regex]::Replace($rest, '\s+op$', '', 'IgnoreCase')   # "haal ... op"
    if (-not $rest.Trim()) { return $null }   # "Fetch" alone
    $mw = [regex]::Match($rest, "(?:^|\s)$script:MeetWord(?=\s|$)", 'IgnoreCase')
    $when = Find-WhenPhrase -Text $rest -Today $Today
    # A time in the middle or first ("meetings this week Daily Standup", "Fetch for this week meetings
    # Daily Standup", operator 2026-11-20): only after Fetch/Get/Import, so "Board meetings this
    # week went well" stays a note.
    if (-not $when -and $verb.Success) { $when = Find-WhenPhrase -Text $rest -Today $Today -Anywhere }
    if (-not $mw.Success) {
        # A verb and a time without the word (operator, 2026-11-20: "also on Fetch, Get or Import"):
        # "Fetch yesterday", "Get Daily Standup this week", "Import last week". Without a time it is
        # not a request ("Import the budget file"); the words before the time are the series.
        # Only a time that names past days: "Get milk tomorrow" stays a note.
        if (-not $verb.Success -or -not $when -or $when.error -or -not @($when.dates | Where-Object { $_ -le $Today.Date }).Count) { return $null }
        # A time right after the verb takes a series of any length ("Fetch this week Daily Sync | A & B");
        # else at most 5 words, so "Get the budget done this week and send it" stays a note.
        if ($rest.Substring(0, $when.index).Trim() -and @(($rest.Remove($when.index, $when.length)).Trim() -split '\s+' | Where-Object { $_ }).Count -gt 5) { return $null }
        $mw = [regex]::Match($rest, '^')   # empty, at the start: everything before the time is "before"
    }
    # Without a verb the time comes after the word ("meetings yesterday"); after a verb it may also
    # come first ("Fetch for this week meetings Daily Sync").
    if ($when -and -not $verb.Success -and $when.index -lt $mw.Index + $mw.Length) { $when = $null }
    $before = $rest.Substring(0, $mw.Index).Trim()
    # "Daily Standup meetings" with neither a verb nor a time is a few words, not a command.
    if ($before -and -not $verb.Success -and -not $when -and -not $quoted) { return $null }
    # The series: what is left without the word and the time, in the order typed.
    $left = $rest
    $spans = @(@{ i = $mw.Index; l = $mw.Length })
    if ($when) { $spans += @{ i = $when.index; l = $when.length } }
    foreach ($sp in @($spans | Sort-Object { $_.i } -Descending)) { $left = $left.Remove($sp.i, $sp.l).Insert($sp.i, ' ') }
    $words = @($left -split '\s+' | Where-Object { $_ })
    while ($words.Count -and $script:Filler -contains $words[0].ToLowerInvariant()) { $words = @($words | Select-Object -Skip 1) }
    while ($words.Count -and $script:Filler -contains $words[$words.Count - 1].ToLowerInvariant()) { $words = @($words | Select-Object -First ($words.Count - 1)) }
    $series = if ($quoted) { $quoted } else { ($words -join ' ').Trim() }
    # A sentence, not a series name: more than 8 words without a verb, 20 with one (Teams titles are long).
    if (-not $quoted -and $words.Count -gt $(if ($verb.Success) { 20 } else { 8 })) { return $null }
    $r = [ordered]@{ days = @(); series = $series; when = 'today'; error = '' }
    if (-not $when) { $r.days = @(ConvertTo-IsoDay $Today.Date); return $r }
    $r.when = $rest.Substring($when.index, $when.length).Trim()
    if ($when.error) { $r.error = $when.error; return $r }
    $past = @($when.dates | Where-Object { $_ -le $Today.Date } | Sort-Object -Unique)
    if (-not $past.Count) { $r.error = 'Those days are still to come: there are no meeting notes yet.'; return $r }
    if ($past.Count -gt $script:MaxDays) { $r.error = "That is $($past.Count) days; ObsidiNote asks Copilot one day at a time, so at most $($script:MaxDays) days at once."; return $r }
    $r.days = @($past | ForEach-Object { ConvertTo-IsoDay $_ })
    $r
}

function Format-MeetingRequestReason {
    <# The intent line's words for a request: "Copilot lists your Teams meetings of 2026-11-17 to
       2026-11-19 (3 days), of the series "Daily Standup" only". #>
    param([Parameter(Mandatory)][Collections.IDictionary]$Request)
    if ($Request.error) { return $Request.error }
    $d = @($Request.days)
    $span = if ($d.Count -eq 1) { $d[0] } else { "$($d[0]) to $($d[$d.Count - 1]) ($($d.Count) days, one question each)" }
    $s = if ($Request.series) { ", of the series ""$($Request.series)"" only" } else { '' }
    "Copilot lists your Teams meetings of $span$s; you pick the ones to add"
}

Export-ModuleMember -Function Get-MeetingRequest, Format-MeetingRequestReason, Resolve-RequestDay
