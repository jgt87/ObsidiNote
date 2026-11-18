# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Meetings (lib/Meetings.psm1; POST /api/meetings/day and /notes in lib/Server.psm1): Copilot lists
# one day's Teams meetings and writes one meeting's notes, read only; the window files the notes
# through the normal Add with origin "meeting". Kit probe P10 on the target machine, 2026-11-17: the
# day's list and two meetings' notes worked. Invented meetings and names only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Meetings.psm1') -Force
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

$script:Day = '2031-04-09'
$script:DayReply = @'
Here you go:
{"ref":"REF","meetings":[
 {"title":"Garden sync | Tidal beds","start":"2031-04-09 10:00","attendees":5,"hasTranscript":true,"hasRecap":false,"hasNotes":false},
 {"title":"Lunch talk","start":"2031-04-09 12:30","attendees":3,"hasTranscript":false,"hasRecap":false,"hasNotes":false},
 {"title":"","start":"2031-04-09 14:00","hasTranscript":true},
 {"title":"Yesterday's review","start":"2031-04-08 16:00","hasTranscript":true},
 {"title":"No start given","hasNotes":true}
]} [1] [2]
'@
$script:NotesReply = @'
{"ref":"REF","found":true,"date":"2031-04-09","attendees":[{"name":"Ada Example","email":"Ada.Example@contoso.example"},{"name":"Bo Sample","email":""}],
 "summary":"The team agreed to move the tidal beds.\nThe pumps stay.",
 "decisions":["Move the tidal beds north.",""],
 "actions":[{"text":"Order new pumps","owner":"Ada Example","due":""},{"text":"Draw the plan","owner":"","due":"2031-04-20"},{"text":""}],
 "basedOn":"transcript","source":""}
'@
function Set-Ref([string]$Text, [string]$Ref) { $Text.Replace('"REF"', '"' + $Ref + '"') }

Describe 'A day''s meetings (pure)' {
    It 'asks for one day and carries the reference' {
        $p = New-MeetingDayPrompt -Day $script:Day -Ref 'rabc12345'
        $p | Should Match 'on 2031-04-09'
        $p | Should Match '"ref": "rabc12345"'
    }
    It 'keeps titled meetings of that day, says which can be read, and leaves out the rest' {
        $x = ConvertFrom-MeetingDayReply -Reply (Set-Ref $script:DayReply 'rabc12345') -Day $script:Day -Ref 'rabc12345'
        $x.ok | Should Be $true
        @($x.meetings).Count | Should Be 3
        $x.meetings[0].title | Should Be 'Garden sync | Tidal beds'
        $x.meetings[0].time | Should Be '10:00'
        $x.meetings[0].readable | Should Be $true
        $x.meetings[1].readable | Should Be $false
        $x.meetings[2].title | Should Be 'No start given'
        $x.meetings[2].time | Should Be ''
    }
    It 'refuses an answer to another request, and an answer without a list' {
        (ConvertFrom-MeetingDayReply -Reply (Set-Ref $script:DayReply 'rzzz') -Day $script:Day -Ref 'rabc12345').ok | Should Be $false
        $n = ConvertFrom-MeetingDayReply -Reply '{"ref":"rabc12345"}' -Day $script:Day -Ref 'rabc12345'
        $n.ok | Should Be $false
        $n.error | Should Match 'no list of meetings'
        (ConvertFrom-MeetingDayReply -Reply 'Sorry, I cannot help.' -Day $script:Day -Ref 'r1').ok | Should Be $false
    }
    It 'takes an empty day as an empty list' {
        $e = ConvertFrom-MeetingDayReply -Reply '{"ref":"r1","meetings":[]}' -Day $script:Day -Ref 'r1'
        $e.ok | Should Be $true
        @($e.meetings).Count | Should Be 0
    }
    It 'checks a day' {
        Test-MeetingDay '2031-04-09' | Should Be $true
        foreach ($bad in '2031-13-01', '9 April', '', '2031-04-09x') { Test-MeetingDay $bad | Should Be $false }
    }
}

Describe 'One meeting''s notes (pure)' {
    It 'names the meeting with its quotes made single, and carries the reference' {
        $p = New-MeetingNotesPrompt -Title 'The "big" sync' -Start '2031-04-09 10:00' -Ref 'r9'
        $p | Should Match 'meeting "The ''big'' sync" \(started 2031-04-09 10:00\)'
        $p | Should Match '"ref": "r9"'
        $p | Should Match 'never copy the transcript'
    }
    It 'reads the notes: empty items out, one line each' {
        $n = ConvertFrom-MeetingNotesReply -Reply (Set-Ref $script:NotesReply 'r9') -Day $script:Day -Ref 'r9'
        $n.ok | Should Be $true
        $n.found | Should Be $true
        @($n.attendees).Count | Should Be 2
        $n.summary | Should Be 'The team agreed to move the tidal beds. The pumps stay.'
        @($n.decisions).Count | Should Be 1
        @($n.actions).Count | Should Be 2
        $n.actions[1].due | Should Be '2031-04-20'
        $n.basedOn | Should Be 'transcript'
    }
    It 'refuses the notes of a meeting on another day (another meeting with the same title)' {
        $n = ConvertFrom-MeetingNotesReply -Reply (Set-Ref $script:NotesReply 'r9') -Day '2031-04-10' -Ref 'r9'
        $n.ok | Should Be $false
        $n.error | Should Match 'on 2031-04-09, not 2031-04-10'
    }
    It 'says not found when Copilot could not read it, or sent nothing to file' {
        (ConvertFrom-MeetingNotesReply -Reply '{"ref":"r9","found":false,"attendees":[],"decisions":[],"actions":[]}' -Ref 'r9').found | Should Be $false
        (ConvertFrom-MeetingNotesReply -Reply '{"ref":"r9","found":true,"attendees":["A"],"decisions":[],"actions":[]}' -Ref 'r9').found | Should Be $false
    }
    It 'reads attendees with their display name and address, old and new shapes (2026-11-18)' {
        $n = ConvertFrom-MeetingNotesReply -Reply (Set-Ref $script:NotesReply 'r9') -Day $script:Day -Ref 'r9'
        (@($n.attendees | ForEach-Object { "$($_.name)|$($_.email)" }) -join ';') | Should Be 'Ada Example|ada.example@contoso.example;Bo Sample|'
        $old = ConvertFrom-MeetingNotesReply -Reply '{"ref":"r9","found":true,"attendees":["Ada Example <ada@contoso.example>","Bo Sample","cy@contoso.example","Ada again (ADA@contoso.example)"],"summary":"x","decisions":[],"actions":[]}' -Ref 'r9'
        (@($old.attendees | ForEach-Object { "$($_.name)|$($_.email)" }) -join ';') | Should Be 'Ada Example|ada@contoso.example;Bo Sample|;cy@contoso.example|cy@contoso.example'
    }
    It 'keeps no address that is not one, and never guesses one' {
        $bad = ConvertFrom-MeetingNotesReply -Reply '{"ref":"r9","found":true,"attendees":[{"name":"Ada Example","email":"Ada Example"},{"name":"","email":"not an address"},{"name":"Bo","email":"bo@contoso"}],"summary":"x","decisions":[],"actions":[]}' -Ref 'r9'
        (@($bad.attendees | ForEach-Object { "$($_.name)|$($_.email)" }) -join ';') | Should Be 'Ada Example|;Bo|'
    }
    It 'asks for the display name and the address, and says never to guess one' {
        $p = New-MeetingNotesPrompt -Title 'Garden sync' -Ref 'r9'
        $p | Should Match '"attendees": \[\{"name": "display name", "email": "address or empty"\}\]'
        $p | Should Match 'never guess one'
    }
    It 'builds the page text with headings and lists' {
        $n = ConvertFrom-MeetingNotesReply -Reply (Set-Ref $script:NotesReply 'r9') -Day $script:Day -Ref 'r9'
        $t = ConvertTo-MeetingNoteText -Title 'Garden sync' -Day $script:Day -Time '10:00' -Notes $n
        $lines = $t -split "`n"
        $lines[0] | Should Be '# Meeting: Garden sync'
        $t | Should Match 'Teams meeting on 2031-04-09 at 10:00\. Notes written by Copilot from the meeting transcript\.'
        $t | Should Match '(?m)^## Decisions\n- Move the tidal beds north\.$'
        $t | Should Match '(?m)^- Order new pumps \(Ada Example\)$'
        $t | Should Match '(?m)^- Draw the plan \(due 2031-04-20\)$'
        $t | Should Match '(?m)^## Attendees\n- Ada Example \(\[ada\.example@contoso\.example\]\(mailto:ada\.example@contoso\.example\)\)\n- Bo Sample$'
    }
}

Describe 'POST /api/meetings/day and /notes (stand-in Copilot; nothing is written)' {
    $app = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
    [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), '{"notebook":""}')
    # The stand-in answers with the reference of the prompt it was sent.
    $replies = @{ day = $script:DayReply; notes = $script:NotesReply }
    $sent = New-Object System.Collections.ArrayList
    $send = { param([string]$Text)
        $null = $sent.Add($Text)
        $ref = [regex]::Match($Text, '"ref": "([a-z0-9]+)"').Groups[1].Value
        $k = if ($Text -match '^List all my Teams meetings') { 'day' } else { 'notes' }
        $replies[$k].Replace('"REF"', '"' + $ref + '"')
    }.GetNewClosure()
    $state = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server' -TestCopilot @{ Send = $send; NewChat = { } }
    It 'lists the meetings of the day asked for' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{"day":"2031-04-09"}' -State $state
        $r.status | Should Be 200
        $r.body.day | Should Be '2031-04-09'
        @($r.body.meetings).Count | Should Be 3
    }
    It 'asks for today when no day is sent, and refuses a day that is no date' {
        $sent.Clear()
        $null = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{}' -State $state
        $sent[0] | Should Match ([regex]::Escape((Get-Date).ToString('yyyy-MM-dd')))
        (Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{"day":"next Monday"}' -State $state).status | Should Be 400
    }
    It 'answers a meeting''s notes as the text to add, with counts' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/notes' -Body '{"title":"Garden sync","start":"2031-04-09 10:00","time":"10:00","day":"2031-04-09"}' -State $state
        $r.status | Should Be 200
        $r.body.found | Should Be $true
        $r.body.text | Should Match '^# Meeting: Garden sync'
        $r.body.decisions | Should Be 1
        $r.body.actions | Should Be 2
    }
    It 'refuses notes without a title' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/notes' -Body '{"title":"  "}' -State $state).status | Should Be 400
    }
    It 'asks each question in a new chat with Work IQ on, before sending it (target machine, 2026-11-17)' {
        $calls = New-Object System.Collections.ArrayList
        $tc = @{
            NewChat = { $null = $calls.Add('new') }.GetNewClosure()
            WorkIq  = { $null = $calls.Add('workiq'); 'on' }.GetNewClosure()
            Send    = { param([string]$Text) $null = $calls.Add('send'); $ref = [regex]::Match($Text, '"ref": "([a-z0-9]+)"').Groups[1].Value; '{"ref":"' + $ref + '","meetings":[]}' }.GetNewClosure()
        }
        $s = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server' -TestCopilot $tc
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{}' -State $s
        $r.status | Should Be 200
        ($calls -join ',') | Should Be 'new,workiq,send'
    }
    It 'answers 503 without Copilot' {
        $none = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server'
        $none.CopilotSkipped = $true
        (Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{}' -State $none).status | Should Be 503
    }
    It 'answers 502 with a reason when Copilot''s answer cannot be used' {
        $bad = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server' -TestCopilot @{ Send = { param([string]$Text) 'I cannot see your calendar.' }; NewChat = { } }
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{}' -State $bad
        $r.status | Should Be 502
        $r.body.error | Should Match 'could not be read'
    }
    Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction SilentlyContinue
}
