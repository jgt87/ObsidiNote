# Meetings into ObsidiNote (operator, 2026-11-14 and 2026-11-17: "build as suggested"). Copilot,
# with the person's own Microsoft 365 access, lists the Teams meetings of one day and writes
# structured notes for one meeting from its transcript, recap or notes. Kit probe P10 on the target
# machine (2026-11-17): the day's list works (8 meetings, 3 with a transcript) and the notes of two
# meetings came back read from the transcript, while a list of "the last 7 days" came back empty, so
# the window asks for one day only. The questions are the probe's, plus the request reference.
# Read only: nothing here writes. A meeting becomes a page through the normal Add (POST /api/submit
# with the text built here and origin "meeting"), which checks, files, links and can be undone.
# Pure; keep this file ASCII (PS 5.1 reads BOM-less files as ANSI).
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Linker.psm1')

$script:MaxMeetings = 30
$script:MaxTitle = 200
$script:MaxSummary = 2000
$script:MaxItem = 500
$script:MaxItems = 30

function Test-MeetingDay([AllowEmptyString()][string]$Day) {
    <# A day the window may ask for: yyyy-mm-dd and a real date. #>
    $d = [datetime]::MinValue
    [bool]($Day -match '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($Day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d))
}

function Get-MeetingText([AllowNull()]$Value, [int]$Max) {
    <# One line of text from a reply value: trimmed, line breaks and control characters out, cut. #>
    $t = ([regex]::Replace("$Value", '[\x00-\x1f]+', ' ')).Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max).TrimEnd() }
    $t
}

function Get-MeetingFlag($Object, [string]$Name) {
    [bool]($Object.PSObject.Properties[$Name] -and "$($Object.$Name)" -eq 'True')
}

function Format-PromptTitle([string]$Title) {
    # The title goes into the question between double quotes: its own become single ones.
    (Get-MeetingText $Title $script:MaxTitle).Replace('"', "'")
}

function New-MeetingDayPrompt {
    <# The question for every Teams meeting of $Day (kit P10's day question, with the reference). #>
    param([Parameter(Mandatory)][string]$Day, [Parameter(Mandatory)][string]$Ref)
    "List all my Teams meetings on $Day, in the order they started. For each, say whether a transcript, a Copilot recap (intelligent recap) or meeting notes (for example Facilitator or Loop notes) exist that you can read. " +
    'Answer only with one JSON object and no other text: {"ref": "' + $Ref + '", "meetings": [{"title": "...", "start": "yyyy-mm-dd hh:mm", "attendees": 0, "hasTranscript": true or false, "hasRecap": true or false, "hasNotes": true or false}]}. ' +
    'If you cannot see my meetings of that day, answer {"ref": "' + $Ref + '", "meetings": []}.'
}

function ConvertFrom-MeetingDayReply {
    <# The meetings of a reply to New-MeetingDayPrompt: @{ ok; error; meetings = @(@{ title; start;
       time (hh:mm or ''); attendees; hasTranscript; hasRecap; hasNotes; readable }) }. A meeting
       without a title (the notes question names it) or of another day is left out; at most 30. #>
    param([AllowEmptyString()][AllowNull()][string]$Reply, [Parameter(Mandatory)][string]$Day, [string]$Ref = '')
    $j = Get-ReplyJson $Reply
    if (-not $j.ok) { return @{ ok = $false; error = $j.error; meetings = @() } }
    $rc = Test-ReplyRef -Reply $j.value -Ref $Ref
    if (-not $rc.ok) { return @{ ok = $false; error = $rc.error; meetings = @() } }
    if (-not $j.value.PSObject.Properties['meetings']) { return @{ ok = $false; error = 'The answer holds no list of meetings.'; meetings = @() } }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($m in @($j.value.meetings)) {
        if (-not ($m -is [pscustomobject]) -or $out.Count -ge $script:MaxMeetings) { continue }
        $title = if ($m.PSObject.Properties['title']) { Get-MeetingText $m.title $script:MaxTitle } else { '' }
        if (-not $title) { continue }
        $start = if ($m.PSObject.Properties['start']) { Get-MeetingText $m.start 40 } else { '' }
        if ($start -match '^(\d{4}-\d{2}-\d{2})' -and $Matches[1] -ne $Day) { continue }
        $time = if ($start -match '(\d{1,2}:\d{2})') { $Matches[1] } else { '' }
        $n = 0
        if ($m.PSObject.Properties['attendees']) { [void][int]::TryParse("$($m.attendees)", [ref]$n) }
        $t = Get-MeetingFlag $m 'hasTranscript'; $r = Get-MeetingFlag $m 'hasRecap'; $o = Get-MeetingFlag $m 'hasNotes'
        $out.Add([ordered]@{ title = $title; start = $start; time = $time; attendees = [Math]::Max(0, $n); hasTranscript = $t; hasRecap = $r; hasNotes = $o; readable = ($t -or $r -or $o) })
    }
    @{ ok = $true; error = ''; meetings = @($out.ToArray()) }
}

function New-MeetingNotesPrompt {
    <# The question for one meeting's notes (kit P10's notes question, with the reference). #>
    param([Parameter(Mandatory)][string]$Title, [string]$Start = '', [Parameter(Mandatory)][string]$Ref)
    $s = Get-MeetingText $Start 40
    'From the transcript, the Copilot recap or the meeting notes of my Teams meeting "' + (Format-PromptTitle $Title) + '"' + $(if ($s) { ' (started ' + $s + ')' } else { '' }) + ', write structured meeting notes for my personal wiki. ' +
    'Answer only with one JSON object and no other text: {"ref": "' + $Ref + '", "found": true or false, "date": "yyyy-mm-dd", "attendees": ["names"], "summary": "3 to 5 sentences", "decisions": ["each decision in one sentence"], ' +
    '"actions": [{"text": "the action", "owner": "a name or empty", "due": "yyyy-mm-dd or empty"}], "basedOn": "transcript, recap, notes or empty"}. ' +
    'A summary only: never copy the transcript. If you cannot read it, answer {"ref": "' + $Ref + '", "found": false, "attendees": [], "decisions": [], "actions": []}.'
}

function Get-MeetingList($Object, [string]$Name) {
    if (-not $Object.PSObject.Properties[$Name]) { return , @() }
    , @(@($Object.$Name) | ForEach-Object { Get-MeetingText $_ $script:MaxItem } | Where-Object { $_ } | Select-Object -First $script:MaxItems)
}

function ConvertFrom-MeetingNotesReply {
    <# The notes of a reply to New-MeetingNotesPrompt: @{ ok; error; found; date; attendees;
       summary; decisions; actions = @(@{ text; owner; due }); basedOn }. found is false when Copilot
       says it could not read the meeting, or the notes are empty. A date of another day than $Day
       is refused: Copilot read another meeting with the same title. #>
    param([AllowEmptyString()][AllowNull()][string]$Reply, [string]$Day = '', [string]$Ref = '')
    $none = @{ ok = $false; error = ''; found = $false; date = ''; attendees = @(); summary = ''; decisions = @(); actions = @(); basedOn = '' }
    $j = Get-ReplyJson $Reply
    if (-not $j.ok) { $none.error = $j.error; return $none }
    $rc = Test-ReplyRef -Reply $j.value -Ref $Ref
    if (-not $rc.ok) { $none.error = $rc.error; return $none }
    $v = $j.value
    $r = @{ ok = $true; error = ''; found = (Get-MeetingFlag $v 'found') }
    $r.date = if ($v.PSObject.Properties['date'] -and "$($v.date)" -match '^\d{4}-\d{2}-\d{2}$') { "$($v.date)" } else { '' }
    $r.attendees = Get-MeetingList $v 'attendees'
    $r.summary = if ($v.PSObject.Properties['summary']) { Get-MeetingText $v.summary $script:MaxSummary } else { '' }
    $r.decisions = Get-MeetingList $v 'decisions'
    $acts = New-Object System.Collections.Generic.List[object]
    if ($v.PSObject.Properties['actions']) {
        foreach ($a in @($v.actions)) {
            if ($acts.Count -ge $script:MaxItems) { break }
            if ($a -is [pscustomobject]) {
                $t = if ($a.PSObject.Properties['text']) { Get-MeetingText $a.text $script:MaxItem } else { '' }
                if (-not $t) { continue }
                $acts.Add([ordered]@{
                        text = $t
                        owner = $(if ($a.PSObject.Properties['owner']) { Get-MeetingText $a.owner 120 } else { '' })
                        due = $(if ($a.PSObject.Properties['due'] -and "$($a.due)" -match '^\d{4}-\d{2}-\d{2}$') { "$($a.due)" } else { '' })
                    })
            } elseif ("$a".Trim()) { $acts.Add([ordered]@{ text = (Get-MeetingText $a $script:MaxItem); owner = ''; due = '' }) }
        }
    }
    $r.actions = @($acts.ToArray())
    $r.basedOn = if ($v.PSObject.Properties['basedOn'] -and "$($v.basedOn)" -match '^(?i)(transcript|recap|notes)$') { "$($v.basedOn)".ToLowerInvariant() } else { '' }
    if ($Day -and $r.date -and $r.date -ne $Day) {
        $r.ok = $false; $r.found = $false
        $r.error = "Copilot answered with the notes of a meeting on $($r.date), not $Day. Try again, or add this meeting's notes by hand."
        return $r
    }
    if ($r.found -and -not $r.summary -and -not @($r.decisions).Count -and -not @($r.actions).Count) { $r.found = $false }
    $r
}

function ConvertTo-MeetingNoteText {
    <# The text an Add files as the meeting's page (Markdown, which Add keeps as headings and lists):
       title, when, what the notes came from, attendees, summary, decisions and actions. #>
    param([Parameter(Mandatory)][string]$Title, [string]$Day = '', [string]$Time = '', [Parameter(Mandatory)][hashtable]$Notes)
    $when = @($(if ($Notes.date) { $Notes.date } else { $Day }), $Time) | Where-Object { $_ }
    $from = switch ($Notes.basedOn) { 'transcript' { 'the meeting transcript' } 'recap' { 'the Copilot recap' } 'notes' { 'the meeting notes' } default { 'the meeting' } }
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add("# Meeting: $(Get-MeetingText $Title $script:MaxTitle)")
    $l.Add('')
    $l.Add("Teams meeting$(if ($when) { ' on ' + ($when -join ' at ') }). Notes written by Copilot from $from.")
    if (@($Notes.attendees).Count) { $l.Add(''); $l.Add('## Attendees'); foreach ($a in @($Notes.attendees)) { $l.Add("- $a") } }
    if ($Notes.summary) { $l.Add(''); $l.Add('## Summary'); $l.Add($Notes.summary) }
    if (@($Notes.decisions).Count) { $l.Add(''); $l.Add('## Decisions'); foreach ($d in @($Notes.decisions)) { $l.Add("- $d") } }
    if (@($Notes.actions).Count) {
        $l.Add(''); $l.Add('## Actions')
        foreach ($a in @($Notes.actions)) {
            $who = @($(if ($a.owner) { $a.owner }), $(if ($a.due) { "due $($a.due)" })) | Where-Object { $_ }
            $l.Add("- $($a.text)$(if ($who) { ' (' + ($who -join ', ') + ')' })")
        }
    }
    $l.ToArray() -join "`n"
}

Export-ModuleMember -Function Test-MeetingDay, New-MeetingDayPrompt, ConvertFrom-MeetingDayReply, New-MeetingNotesPrompt, ConvertFrom-MeetingNotesReply, ConvertTo-MeetingNoteText
