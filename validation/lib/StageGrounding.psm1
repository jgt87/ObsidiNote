# V5 Grounding probes (FEASIBILITY.md section 7), with Microsoft 365 Copilot in ObsidiNote's Edge:
#   P3  can Copilot (Work IQ on) find a marker on a OneNote page? Marker pages live in
#       ObsidiNote-Probe, section "P3 markers" (a new one only with -WriteTest); every run asks for
#       the newest three, so running V5 again after 1 hour and 24 hours measures the indexing delay.
#   P4  the same for a marker the person put on a Loop page (optional; typed in when asked).
#   P7  the link summary prompt for a SharePoint page and a OneDrive document the person pastes.
#   P8  the same for a public web address, with Work IQ off (web) and on.
# Logged: found yes/no, JSON shape valid yes/no, reply length and timings. Never the marker, the
# address, the prompt or the reply. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProbeNotebook.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriteProbes.psm1')
Import-Module (Join-Path $PSScriptRoot 'StageOneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'StageCopilot.psm1')

$script:LinkKeys = @('title', 'where', 'kind', 'summary', 'keyFacts', 'useItFor', 'sensitivity', 'access')
$script:MarkerKeys = @('found', 'where', 'app')
$script:DefaultPublicUrl = 'https://learn.microsoft.com/en-us/powershell/scripting/overview'
$script:MarkersAsked = 3

function New-MarkerPrompt([string]$Marker) {
    'Search my Microsoft 365 content (OneNote notebooks, OneDrive files, Loop pages) for the exact text "' + $Marker + '". ' +
    'Answer only with one JSON object and no other text: {"found": true or false, "where": "the page or file name, or empty", ' +
    '"app": "OneNote, OneDrive, Loop, other or empty", "searched": ["the sources you were able to search"]}'
}

function Test-MarkerReply {
    <# @{ valid; found; cited } from a reply to New-MarkerPrompt. cited: the page it names is the
       kit's marker page (or a Loop page for P4). Pure. #>
    param([AllowEmptyString()][string]$Text, [string]$Expect = 'P3 marker')
    $j = Get-JsonFromReply $Text
    $valid = Test-JsonShape $j $script:MarkerKeys
    $found = $valid -and ("$($j.found)" -eq 'True')
    $cited = $found -and ("$($j.where) $($j.app)" -match [regex]::Escape($Expect))
    [pscustomobject]@{ valid = $valid; found = $found; cited = $cited }
}

function New-LinkPrompt([string]$Url, [string]$Kinds) {
    'Read the content at this address with my access and summarize it. Answer only with one JSON object and no other text, in this shape: ' +
    '{"title": "the page, file or site name", "where": "site, library or owner, or the domain", "kind": "' + $Kinds + '", ' +
    '"summary": "3 to 5 sentences: what it is and why it matters", "keyFacts": ["up to 8 short facts: names, dates, numbers, decisions"], ' +
    '"useItFor": "one line: when I would come back to this", "sensitivity": "its sensitivity label, or empty", ' +
    '"access": "ok, no-access or not-found"}. Address: ' + $Url
}

function Test-LinkReply {
    <# @{ valid; access; found; facts } from a reply to New-LinkPrompt. Pure. #>
    param([AllowEmptyString()][string]$Text)
    $j = Get-JsonFromReply $Text
    $valid = (Test-JsonShape $j $script:LinkKeys) -and ($j.keyFacts -is [array] -or $j.keyFacts -is [string] -or $null -eq $j.keyFacts)
    $access = if ($valid) { "$($j.access)".ToLowerInvariant() } else { '' }
    $found = $valid -and $access -eq 'ok' -and "$($j.summary)".Trim().Length -gt 0
    [pscustomobject]@{ valid = $valid; access = $access; found = $found; facts = $(if ($valid) { @($j.keyFacts | Where-Object { $_ }).Count } else { 0 }) }
}

function Get-UrlKind {
    <# 'sharepoint', 'onedrive', 'web' for an absolute https address; '' otherwise. Pure. #>
    param([string]$Url)
    $u = $null
    if (-not [Uri]::TryCreate("$Url".Trim(), [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'https') { return '' }
    if ($u.Host -match '(?i)-my\.sharepoint\.com$') { return 'onedrive' }
    if ($u.Host -match '(?i)\.sharepoint\.com$') { return 'sharepoint' }
    'web'
}

function Get-MarkerStatus($Check, [double]$AgeHours) {
    if ($Check.cited) { return 'OK' }
    if ($Check.found) { return 'WARN' }
    if ($AgeHours -lt 1) { return 'INFO' }
    'WARN'
}

function Invoke-P3 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $one = $null
    try { $one = Get-KitOneNote $Ctx } catch { }
    if ($one -and (Get-KitFlag $Ctx 'WriteTest')) {
        $m = Measure-KitStep {
            $g = if ($Ctx.Shared.ContainsKey('ProbeGuard') -and $Ctx.Shared.ProbeGuard) { $Ctx.Shared.ProbeGuard } else { Open-ProbeNotebook -One $one -Name (Get-ProbeNotebookName) -BasePath "$(Get-KitFlag $Ctx 'ProbeBasePath' '')" }
            New-ProbeMarker -Guard $g
        }
        if ($m.ok) { Add-ValidationResult $Ctx 'V5' 'OK' 'P3 marker page' "new marker page in ObsidiNote-Probe ($($m.ms) ms)" }
        else { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P3 marker page' $m.error }
    }
    $markers = @(if ($one) { Get-ProbeMarkers -One $one })
    if (-not $markers.Count) {
        Add-ValidationResult $Ctx 'V5' 'SKIP' 'P3 OneNote grounding' $(if ($one) { 'no marker page in ObsidiNote-Probe yet' } else { 'OneNote is not running' }) 'Run V5 with -WriteTest once; then run V5 again after 1 hour and after 24 hours.'
        return
    }
    foreach ($mk in @($markers | Select-Object -First $script:MarkersAsked)) {
        $r = Send-KitPrompt -Bridge $Bridge -Text (New-MarkerPrompt $mk.marker) -WorkIq 'on'
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P3 OneNote grounding' "marker age $($mk.ageHours) h: no answer ($($r.result)); $($r.ms) ms"; continue }
        $c = Test-MarkerReply $r.text
        Add-ValidationResult $Ctx 'V5' (Get-MarkerStatus $c $mk.ageHours) 'P3 OneNote grounding' "marker age $($mk.ageHours) h: found $(Format-YesNo $c.found); names the marker page $(Format-YesNo $c.cited); JSON valid $(Format-YesNo $c.valid); reply $($r.text.Length) chars; $($r.ms) ms; Work IQ $($r.workIq)"
    }
}

function Invoke-P4 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $mk = (Get-KitPrompt $Ctx 'P4 (optional): type the marker you put on a Loop page (it starts with OBSN-P4-), or press Enter to skip').ToUpperInvariant()
    if ($mk -notmatch '^OBSN-P4-[A-Z0-9]{4,12}$') { Add-ValidationResult $Ctx 'V5' 'SKIP' 'P4 Loop grounding' 'no Loop marker given' 'Optional: see runbook RB-04, step P4.'; return }
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-MarkerPrompt $mk) -WorkIq 'on'
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P4 Loop grounding' "no answer ($($r.result)); $($r.ms) ms"; return }
    $c = Test-MarkerReply $r.text -Expect 'Loop'
    Add-ValidationResult $Ctx 'V5' $(if ($c.found) { 'OK' } else { 'WARN' }) 'P4 Loop grounding' "found $(Format-YesNo $c.found); names Loop $(Format-YesNo $c.cited); JSON valid $(Format-YesNo $c.valid); reply $($r.text.Length) chars; $($r.ms) ms"
}

function Invoke-LinkProbe {
    <# One P7/P8 call: adds one result line. The address is never logged. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge, [string]$Name, [string]$Url, [string]$Kinds, [string]$WorkIq = 'on')
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-LinkPrompt $Url $Kinds) -WorkIq $WorkIq -TimeoutSec 240
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' $Name "no answer ($($r.result)); $($r.ms) ms"; return }
    $c = Test-LinkReply $r.text
    $status = if ($c.found) { 'OK' } elseif ($c.valid) { 'WARN' } else { 'WARN' }
    $hint = if (-not $c.valid) { 'The reply was not in the fixed JSON shape.' } elseif (-not $c.found) { 'Copilot could not read the address (see access).' } else { '' }
    Add-ValidationResult $Ctx 'V5' $status $Name "summary made $(Format-YesNo $c.found); access $(if ($c.access) { $c.access } else { '?' }); JSON valid $(Format-YesNo $c.valid); $($c.facts) key facts; reply $($r.text.Length) chars; $($r.ms) ms; Work IQ $($r.workIq)" $hint
}

function Invoke-P7 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $asks = @(
        @{ flag = 'SharePointUrl'; kind = 'sharepoint'; name = 'P7 SharePoint page'; q = 'P7: paste the address of a SharePoint page you can open, or press Enter to skip (it is not logged)' },
        @{ flag = 'OneDriveUrl'; kind = 'onedrive'; name = 'P7 OneDrive document'; q = 'P7: paste the address of a document in your OneDrive, or press Enter to skip (it is not logged)' }
    )
    foreach ($a in $asks) {
        $url = "$(Get-KitFlag $Ctx $a.flag '')"
        if (-not $url) { $url = Get-KitPrompt $Ctx $a.q }
        if (-not $url) { Add-ValidationResult $Ctx 'V5' 'SKIP' $a.name 'no address given'; continue }
        if ((Get-UrlKind $url) -ne $a.kind) { Add-ValidationResult $Ctx 'V5' 'WARN' $a.name "not a $(if ($a.kind -eq 'onedrive') { 'OneDrive (-my.sharepoint.com)' } else { 'SharePoint (.sharepoint.com)' }) address: skipped"; continue }
        Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name $a.name -Url $url -Kinds 'site, page, document, list, file, channel, message or loop page'
    }
}

function Invoke-P8 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $url = "$(Get-KitFlag $Ctx 'PublicUrl' '')"
    if (-not $url) { $url = $script:DefaultPublicUrl }
    if ((Get-UrlKind $url) -ne 'web') { Add-ValidationResult $Ctx 'V5' 'WARN' 'P8 web link' 'not a public https address: skipped'; return }
    Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name 'P8 web, Work IQ off' -Url $url -Kinds 'article, docs, tool, video or other' -WorkIq 'off'
    Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name 'P8 web, Work IQ on' -Url $url -Kinds 'article, docs, tool, video or other' -WorkIq 'on'
}

# P10 Meetings (operator, 2026-11-14: "In many meetings, Copilot is used to transcribe or use
# facilitator to create action lists and meeting notes"): can Copilot, with the person's own access,
# list recent meetings with a transcript, recap or notes, and turn them into structured notes? This
# decides whether ObsidiNote gets an "Add a meeting" step. Read only. Logged: counts and yes/no only,
# never a meeting title, a name, a link, a date or any text.
# A full day (operator, 2026-11-15: "fetch all meeting notes from a full day ... from multiple
# meetings"): after the list of the last 7 days, the probe asks for every meeting of one day (the
# day given with -MeetingDay, else the busiest day of that list) and then for the notes of up to
# $MeetingNotesAsked of them, one question per meeting, as an "Add a day's meetings" step would.
$script:MeetingListKeys = @('meetings')
$script:MeetingNotesKeys = @('found', 'attendees', 'decisions', 'actions')
$script:MeetingDays = 7
$script:MeetingNotesAsked = 2

function Test-MeetingDayValue([AllowEmptyString()][string]$Day) {
    <# A -MeetingDay value: a real date written yyyy-mm-dd, or "today". Pure. #>
    if ($Day.Trim() -eq 'today') { return $true }
    $d = [datetime]::MinValue
    $Day -match '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($Day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)
}

function Resolve-MeetingDay([string]$Day, [datetime]$Now = (Get-Date)) {
    <# A valid -MeetingDay value as the date to ask for: "today" is this computer's local date
       (operator, 2026-11-16: a Microsoft 365 outage left the busiest day of the week without
       meetings, so the probe asks for the current day). Pure but for the default $Now. #>
    if ($Day.Trim() -eq 'today') { return $Now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    $Day.Trim()
}

function New-MeetingDayPrompt([string]$Day) {
    "List all my Teams meetings on $Day, in the order they started. For each, say whether a transcript, a Copilot recap (intelligent recap) or meeting notes (for example Facilitator or Loop notes) exist that you can read. " +
    'Answer only with one JSON object and no other text: {"meetings": [{"title": "...", "start": "yyyy-mm-dd hh:mm", "attendees": 0, "hasTranscript": true or false, "hasRecap": true or false, "hasNotes": true or false, "link": "the address of the recap or notes, or empty"}], "searched": ["the sources you were able to use"]}. ' +
    'If you cannot see my meetings of that day, answer {"meetings": [], "searched": []}.'
}

function Select-MeetingDay($List) {
    <# The day of a Test-MeetingListReply result with the most meetings Copilot can read something of
       (a transcript, recap or notes); the newest on a tie; '' when there is none. Pure. #>
    $days = @($List.richDays)
    if (-not $days.Count) { return '' }
    $best = $days | Group-Object | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $true } | Select-Object -First 1
    "$($best.Name)"
}

function New-MeetingListPrompt([int]$Days = $script:MeetingDays) {
    "List my Teams meetings of the last $Days days, newest first, at most 10. For each, say whether a transcript, a Copilot recap (intelligent recap) or meeting notes (for example Facilitator or Loop notes) exist that you can read. " +
    'Answer only with one JSON object and no other text: {"meetings": [{"title": "...", "start": "yyyy-mm-dd hh:mm", "attendees": 0, "hasTranscript": true or false, "hasRecap": true or false, "hasNotes": true or false, "link": "the address of the recap or notes, or empty"}], "searched": ["the sources you were able to use"]}. ' +
    'If you cannot see my meetings, answer {"meetings": [], "searched": []}.'
}

function Test-MeetingListReply {
    <# @{ valid; count; transcript; recap; notes; links; pick; picks; richDays; onDay; offDay } from a
       reply to New-MeetingListPrompt or New-MeetingDayPrompt. picks: the meetings with a transcript,
       recap or notes that have a title (@{ title; start }), in the reply's order, for the notes
       questions; pick: the first of them, or $null. richDays: the yyyy-mm-dd of each meeting with
       something to read (for Select-MeetingDay). With -Day: onDay / offDay count the meetings that
       started on that day or on another one (a meeting without a start counts as neither), and picks
       leaves out meetings of another day. Only counts are logged. Pure. #>
    param([AllowEmptyString()][string]$Text, [string]$Day = '')
    $j = Get-JsonFromReply $Text
    $valid = Test-JsonShape $j $script:MeetingListKeys
    $list = @(if ($valid) { @($j.meetings) | Where-Object { $_ -is [pscustomobject] } })
    # "yes", "true", 1 count as yes too, as in the app (lib/Meetings.psm1 Get-MeetingFlag, 2026-11-18).
    $has = { param($m, $k) $m.PSObject.Properties[$k] -and ("$($m.$k)".Trim().ToLowerInvariant() -in 'true', 'yes', 'y', '1', 'available', 'ja', 'present') }
    $dayOf = { param($m) if ($m.PSObject.Properties['start'] -and "$($m.start)" -match '^(\d{4}-\d{2}-\d{2})') { $Matches[1] } else { '' } }
    $rich = @($list | Where-Object { (& $has $_ 'hasTranscript') -or (& $has $_ 'hasRecap') -or (& $has $_ 'hasNotes') })
    # The notes question names the meeting by its title: only a meeting that came back with one can
    # be picked (a reply may leave "title" out or empty; reading it unguarded threw under StrictMode
    # and stopped the stage, code review 2026-11-15).
    $titled = @($rich | Where-Object { $_.PSObject.Properties['title'] -and "$($_.title)".Trim() } | Where-Object { -not $Day -or @('', $Day) -contains (& $dayOf $_) })
    $picks = @($titled | ForEach-Object { @{ title = "$($_.title)".Trim(); start = $(if ($_.PSObject.Properties['start']) { "$($_.start)" } else { '' }) } })
    $days = @($list | ForEach-Object { & $dayOf $_ })
    [pscustomobject]@{
        valid = $valid; count = $list.Count; rich = $rich.Count
        transcript = @($list | Where-Object { & $has $_ 'hasTranscript' }).Count
        recap = @($list | Where-Object { & $has $_ 'hasRecap' }).Count
        notes = @($list | Where-Object { & $has $_ 'hasNotes' }).Count
        links = @($list | Where-Object { $_.PSObject.Properties['link'] -and "$($_.link)" -match '^(?i)https://' }).Count
        pick = $(if ($picks.Count) { $picks[0] } else { $null })
        picks = $picks
        richDays = @($rich | ForEach-Object { & $dayOf $_ } | Where-Object { $_ })
        onDay = $(if ($Day) { @($days | Where-Object { $_ -eq $Day }).Count } else { 0 })
        offDay = $(if ($Day) { @($days | Where-Object { $_ -and $_ -ne $Day }).Count } else { 0 })
    }
}

function New-MeetingNotesPrompt([string]$Title, [string]$Start) {
    'From the transcript, the Copilot recap or the meeting notes of my Teams meeting "' + $Title + '"' + $(if ($Start) { ' (started ' + $Start + ')' } else { '' }) + ', write structured meeting notes for my personal wiki. ' +
    # The app's own question asks the same attendee shape (lib/Meetings.psm1, 2026-11-18).
    'For each attendee give the display name and the e-mail address exactly as in the meeting invitation; leave the address empty when you do not see it, never guess one. ' +
    'Answer only with one JSON object and no other text: {"found": true or false, "date": "yyyy-mm-dd", "attendees": [{"name": "display name", "email": "address or empty"}], "summary": "3 to 5 sentences", "decisions": ["each decision in one sentence"], ' +
    '"actions": [{"text": "the action", "owner": "a name or empty", "due": "yyyy-mm-dd or empty"}], "basedOn": "transcript, recap, notes or empty", "source": "the address of the recap or notes, or empty"}. ' +
    'A summary only: never copy the transcript. If you cannot read it, answer {"found": false, "attendees": [], "decisions": [], "actions": []}.'
}

function Test-MeetingNotesReply {
    <# @{ valid; found; attendees; addresses; decisions; actions; owners; dues; basedOn; source; dateMatch }
       (counts and yes/no) from a reply to New-MeetingNotesPrompt. dateMatch: the notes' "date" is
       -Day (a sign Copilot read the meeting of that day, not another one with the same title). Pure. #>
    param([AllowEmptyString()][string]$Text, [string]$Day = '')
    $j = Get-JsonFromReply $Text
    $valid = Test-JsonShape $j $script:MeetingNotesKeys
    $acts = @(if ($valid) { @($j.actions) | Where-Object { $_ -is [pscustomobject] } })
    [pscustomobject]@{
        valid = $valid; found = $valid -and "$($j.found)" -eq 'True'
        dateMatch = [bool]($valid -and $Day -and $j.PSObject.Properties['date'] -and "$($j.date)" -eq $Day)
        attendees = $(if ($valid) { @(@($j.attendees) | Where-Object { $_ }).Count } else { 0 })
        # How many came with an address (2026-11-18): counted only, never logged.
        addresses = $(if ($valid) { @(@($j.attendees) | Where-Object { ($_ -is [pscustomobject] -and $_.PSObject.Properties['email'] -and "$($_.email)" -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') -or "$_" -match '<[^@\s<>]+@[^@\s<>]+>' }).Count } else { 0 })
        decisions = $(if ($valid) { @(@($j.decisions) | Where-Object { $_ }).Count } else { 0 })
        actions = $acts.Count
        owners = @($acts | Where-Object { $_.PSObject.Properties['owner'] -and "$($_.owner)".Trim() }).Count
        dues = @($acts | Where-Object { $_.PSObject.Properties['due'] -and "$($_.due)" -match '^\d{4}-\d{2}-\d{2}$' }).Count
        basedOn = $(if ($valid -and $j.PSObject.Properties['basedOn'] -and "$($j.basedOn)" -match '^(?i)(transcript|recap|notes)$') { "$($j.basedOn)".ToLowerInvariant() } else { '' })
        source = [bool]($valid -and $j.PSObject.Properties['source'] -and "$($j.source)" -match '^(?i)https://')
    }
}

function Invoke-P10 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-MeetingListPrompt) -WorkIq 'on' -TimeoutSec 240
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P10 meetings list' "no answer ($($r.result)); $($r.ms) ms"; return }
    $l = Test-MeetingListReply $r.text
    $status = if ($l.valid -and $l.count) { 'OK' } else { 'WARN' }
    $hint = if (-not $l.valid) { 'The reply was not in the fixed JSON shape.' } elseif (-not $l.count) { "No meetings came back: none in the last $script:MeetingDays days, or Copilot cannot see your meetings on this tenant." } else { '' }
    Add-ValidationResult $Ctx 'V5' $status 'P10 meetings list' "$($l.count) meetings in the last $script:MeetingDays days; with a transcript $($l.transcript), a recap $($l.recap), notes $($l.notes), a link $($l.links); JSON valid $(Format-YesNo $l.valid); reply $($r.text.Length) chars; $($r.ms) ms; Work IQ $($r.workIq)" $hint
    Invoke-P10Day -Ctx $Ctx -Bridge $Bridge -Week $l
}

function Invoke-P10Day {
    <# One full day: every meeting of the day, then the notes of up to $MeetingNotesAsked of them, one
       question each. The day itself is never logged, only how it was chosen. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge, [Parameter(Mandatory)]$Week)
    $given = "$(Get-KitFlag $Ctx 'MeetingDay' '')".Trim()
    if ($given -and -not (Test-MeetingDayValue $given)) {
        Add-ValidationResult $Ctx 'V5' 'FAIL' 'P10 day''s meetings' 'the -MeetingDay value is not a date written yyyy-mm-dd, nor today' 'Run it again with a date like -MeetingDay 2026-11-12, or -MeetingDay today.'
        return
    }
    $day = if ($given) { Resolve-MeetingDay $given } else { Select-MeetingDay $Week }
    $how = if ($given -eq 'today') { 'today' } elseif ($given) { 'the day given with -MeetingDay' } else { "the busiest day of the last $script:MeetingDays days" }
    if (-not $day) { Add-ValidationResult $Ctx 'V5' 'SKIP' 'P10 day''s meetings' "no meeting of the last $script:MeetingDays days has a transcript, recap or notes with a date, and no -MeetingDay was given" 'Run it again with -MeetingDay set to a day you had meetings with transcription, a recap or notes.'; return }
    # How many of that day the week's list had: the list stops at 10, so a busy day may show more here.
    $inWeek = @($Week.richDays | Where-Object { $_ -eq $day }).Count
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-MeetingDayPrompt $day) -WorkIq 'on' -TimeoutSec 240
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P10 day''s meetings' "no answer ($($r.result)); $($r.ms) ms"; return }
    $d = Test-MeetingListReply $r.text -Day $day
    $hint = if (-not $d.valid) { 'The reply was not in the fixed JSON shape.' } elseif (-not $d.count) { 'No meetings came back for that day.' } elseif ($d.offDay) { 'Copilot listed meetings of other days too.' } else { '' }
    Add-ValidationResult $Ctx 'V5' $(if ($d.valid -and $d.onDay -and -not $d.offDay) { 'OK' } else { 'WARN' }) 'P10 day''s meetings' "$($d.count) meetings on $how ($($d.offDay) of another day); with a transcript $($d.transcript), a recap $($d.recap), notes $($d.notes); the week's list had $inWeek of that day with something to read; JSON valid $(Format-YesNo $d.valid); reply $($r.text.Length) chars; $($r.ms) ms" $hint
    $picks = @($d.picks | Select-Object -First $script:MeetingNotesAsked)
    if (-not $picks.Count) {
        $why = if ($d.rich) { "$($d.rich) meeting(s) of that day with a transcript, recap or notes came back without a title, so none could be asked about" } else { 'no meeting of that day has a transcript, recap or notes' }
        Add-ValidationResult $Ctx 'V5' $(if ($d.rich) { 'WARN' } else { 'SKIP' }) 'P10 meeting notes 1' $why
        return
    }
    for ($i = 0; $i -lt $script:MeetingNotesAsked; $i++) {
        $name = "P10 meeting notes $($i + 1)"
        if ($i -ge $picks.Count) { Add-ValidationResult $Ctx 'V5' 'SKIP' $name "only $($picks.Count) meeting(s) of that day with a transcript, recap or notes and a title"; continue }
        $n = Send-KitPrompt -Bridge $Bridge -Text (New-MeetingNotesPrompt $picks[$i].title $picks[$i].start) -WorkIq 'on' -TimeoutSec 300
        if (-not $n.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' $name "no answer ($($n.result)); $($n.ms) ms"; continue }
        $c = Test-MeetingNotesReply $n.text -Day $day
        $ok = $c.found -and ($c.decisions -or $c.actions)
        $hint2 = if (-not $c.valid) { 'The reply was not in the fixed JSON shape.' } elseif (-not $c.found) { 'Copilot listed the meeting but could not read its transcript, recap or notes.' } else { '' }
        Add-ValidationResult $Ctx 'V5' $(if ($ok) { 'OK' } else { 'WARN' }) $name "read $(Format-YesNo $c.found) (based on $(if ($c.basedOn) { $c.basedOn } else { '?' })); date matches the day $(Format-YesNo $c.dateMatch); $($c.attendees) attendees ($($c.addresses) with an address), $($c.decisions) decisions, $($c.actions) actions ($($c.owners) with an owner, $($c.dues) with a due date); source link $(Format-YesNo $c.source); JSON valid $(Format-YesNo $c.valid); reply $($n.text.Length) chars; $($n.ms) ms" $hint2
    }
}

# The probes of this stage, in the order they run (-Probe names some of them).
$script:Probes = @('P3', 'P4', 'P7', 'P8', 'P10')

function Get-GroundingProbes { , @($script:Probes) }

function Invoke-StageGrounding {
    param([Parameter(Mandatory)]$Ctx)
    # -Probe P10 (Run Meeting Probe.cmd): only the named probes; all when none are named. A name
    # that is no probe is a FAIL line that lists the probes, before Copilot is opened: a typing
    # mistake must never end as a V5 without a result line (code review 2026-11-15).
    $only = @(@(Get-KitFlag $Ctx 'Probes' @()) | ForEach-Object { "$_".Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $unknown = @($only | Where-Object { $script:Probes -notcontains $_ })
    # Only its count goes into the log: what was typed is not the kit's text.
    if ($unknown.Count) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'Probe' "$($unknown.Count) name(s) given with -Probe are not a probe; the probes are $($script:Probes -join ', ')" 'Run it again with one of these names, for example -Probe P10.' }
    $run = @($script:Probes | Where-Object { -not $only.Count -or $only -contains $_ })
    if (-not $run.Count) { return }
    $b = Connect-KitCopilot -Ctx $Ctx -Stage 'V5'
    if (-not $b) { Add-ValidationResult $Ctx 'V5' 'SKIP' ($run -join ', ') 'need Copilot (see the line above)'; return }
    $before = $Ctx.Results.Count   # a generic list: never @() around it (PS 5.1 "Argument types do not match")
    foreach ($p in $run) {
        switch ($p) {
            'P3' { Invoke-P3 $Ctx $b }
            'P4' { Invoke-P4 $Ctx $b }
            'P7' { Invoke-P7 $Ctx $b }
            'P8' { Invoke-P8 $Ctx $b }
            'P10' { Invoke-P10 $Ctx $b }
        }
    }
    if ($Ctx.Results.Count -eq $before) { Add-ValidationResult $Ctx 'V5' 'FAIL' ($run -join ', ') 'no probe gave a result' }
}

Export-ModuleMember -Function Invoke-StageGrounding, Get-GroundingProbes, New-MarkerPrompt, Test-MarkerReply, New-LinkPrompt, Test-LinkReply, Get-UrlKind, New-MeetingListPrompt, Test-MeetingListReply, New-MeetingNotesPrompt, Test-MeetingNotesReply, New-MeetingDayPrompt, Select-MeetingDay, Test-MeetingDayValue, Resolve-MeetingDay
