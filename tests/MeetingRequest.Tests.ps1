# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Meetings of other days from the box (lib/MeetingRequest.psm1; D-078): a short
# command ("meetings yesterday", "Daily Standup meetings this week") becomes the days the Meetings
# panel lists, one Copilot question per day, and an optional series filter. Invented names only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\MeetingRequest.psm1') -Force
Import-Module (Join-Path $root 'lib\Meetings.psm1') -Force
Import-Module (Join-Path $root 'lib\Intent.psm1') -Force
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

# A Friday: "this week" is Monday 2031-04-07 to Friday 2031-04-11.
$script:Today = [datetime]'2031-04-11'
function Get-Req([string]$Text) { Get-MeetingRequest -Text $Text -Today $script:Today }
function Get-Days([string]$Text) { (@((Get-Req $Text).days)) -join ',' }

Describe 'Get-MeetingRequest: the days' {
    It 'reads "meetings" alone as today' {
        Get-Days 'meetings' | Should Be '2031-04-11'
        (Get-Req 'meetings').when | Should Be 'today'
    }
    It 'reads today, yesterday and the day before, in English and Dutch' {
        Get-Days 'meetings yesterday' | Should Be '2031-04-10'
        Get-Days 'vergaderingen gisteren' | Should Be '2031-04-10'
        Get-Days 'meetings eergisteren' | Should Be '2031-04-09'
        Get-Days 'Teams meetings today' | Should Be '2031-04-11'
    }
    It 'reads a date as yyyy-mm-dd or day-month first, with or without a year' {
        Get-Days 'meetings 2031-04-08' | Should Be '2031-04-08'
        Get-Days 'meetings on 8-4' | Should Be '2031-04-08'
        Get-Days 'meetings 8/4/2031' | Should Be '2031-04-08'
        # A day-month still to come this year is last year's.
        Get-Days 'meetings 24-12' | Should Be '2030-12-24'
    }
    It 'reads a weekday as its latest one up to today, "last" before today' {
        Get-Days 'meetings monday' | Should Be '2031-04-07'
        Get-Days 'meetings friday' | Should Be '2031-04-11'
        Get-Days 'meetings last friday' | Should Be '2031-04-04'
        Get-Days 'teams meetings on tuesday' | Should Be '2031-04-08'
    }
    It 'reads a range of two days' {
        Get-Days 'meetings 7-4 to 9-4' | Should Be '2031-04-07,2031-04-08,2031-04-09'
        Get-Days 'meetings from monday to wednesday' | Should Be '2031-04-07,2031-04-08,2031-04-09'
        Get-Days 'vergaderingen van maandag tot woensdag' | Should Be '2031-04-07,2031-04-08,2031-04-09'
    }
    It 'reads this week and last week as Monday to Friday, without days still to come' {
        Get-Days 'meetings this week' | Should Be '2031-04-07,2031-04-08,2031-04-09,2031-04-10,2031-04-11'
        Get-Days 'meetings last week' | Should Be '2031-03-31,2031-04-01,2031-04-02,2031-04-03,2031-04-04'
        Get-Days 'haal vergaderingen van vorige week op' | Should Be '2031-03-31,2031-04-01,2031-04-02,2031-04-03,2031-04-04'
        (@((Get-MeetingRequest -Text 'meetings this week' -Today ([datetime]'2031-04-09')).days)) -join ',' | Should Be '2031-04-07,2031-04-08,2031-04-09'
    }
    It 'reads the last N days and the last N workdays' {
        Get-Days 'meetings last 3 days' | Should Be '2031-04-09,2031-04-10,2031-04-11'
        (@((Get-MeetingRequest -Text 'meetings last 3 workdays' -Today ([datetime]'2031-04-14')).days)) -join ',' | Should Be '2031-04-10,2031-04-11,2031-04-14'
    }
    It 'refuses days still to come, too many days and a date that does not exist, saying why' {
        (Get-Req 'meetings tomorrow').error | Should Match 'still to come'
        (Get-Req 'meetings last 30 days').error | Should Match 'at most 14 days'
        (Get-Req 'meetings 31-02').error | Should Match 'not a date'
        @((Get-Req 'meetings 31-02').days).Count | Should Be 0
    }
}

Describe 'Get-MeetingRequest: the series' {
    It 'takes the words before or after "meetings" as the series' {
        $r = Get-Req 'Daily Standup meetings this week'
        $r.series | Should Be 'Daily Standup'
        @($r.days).Count | Should Be 5
        (Get-Req 'fetch meetings of Daily Standup last week').series | Should Be 'Daily Standup'
        (Get-Req 'fetch Daily Standup meetings').series | Should Be 'Daily Standup'
    }
    It 'takes a quoted series as it is, also with words that otherwise mean a question' {
        $r = Get-Req 'meetings this week "Sync with Ada"'
        $r.series | Should Be 'Sync with Ada'
        @($r.days).Count | Should Be 5
    }
    It 'has no series for a plain request' {
        (Get-Req 'meetings yesterday').series | Should Be ''
        (Get-Req 'get all my meetings yesterday').series | Should Be ''
    }
}

Describe 'Get-MeetingRequest: Fetch, Get or Import with a time, without the word (2026-11-20)' {
    It 'reads a verb and a time as a request, the words between as the series' {
        Get-Days 'Fetch yesterday' | Should Be '2031-04-10'
        Get-Days 'Import last week' | Should Be '2031-03-31,2031-04-01,2031-04-02,2031-04-03,2031-04-04'
        Get-Days 'Import 7-4 to 9-4' | Should Be '2031-04-07,2031-04-08,2031-04-09'
        Get-Days 'haal gisteren op' | Should Be '2031-04-10'
        $r = Get-Req 'Get Daily Standup this week'
        $r.series | Should Be 'Daily Standup'
        @($r.days).Count | Should Be 5
    }
    It 'reads "yesterday''s meetings" and "last week''s meetings"' {
        $r = Get-Req 'fetch yesterday''s meetings'
        (@($r.days)) -join ',' | Should Be '2031-04-10'
        $r.series | Should Be ''
        @((Get-Req ('Get last week' + [char]0x2019 + 's meetings')).days).Count | Should Be 5
    }
    It 'leaves a verb without a time, with only days to come, or with a long sentence alone' {
        foreach ($t in @('Fetch', 'Import the budget file', 'Get milk tomorrow', 'Fetch the report from Ada and the plan for the garden yesterday', 'Get the report about pumps yesterday')) {
            Get-Req $t | Should Be $null
        }
    }
}

Describe 'Get-MeetingRequest: a series named in a sentence (D-078)' {
    It 'takes the words after "with the topic of", "called", "met het onderwerp" as the series' {
        $r = Get-Req 'Fetch the meetings for this week with the topic of Daily Fernbrook & Tidal'
        $r.series | Should Be 'Daily Fernbrook & Tidal'
        @($r.days).Count | Should Be 5
        (Get-Req 'Get meetings called Garden sync last week').series | Should Be 'Garden sync'
        $nl = Get-Req 'haal vergaderingen van deze week op met het onderwerp Tuinoverleg'
        $nl.series | Should Be 'Tuinoverleg'
        @($nl.days).Count | Should Be 5
    }
    It 'gives a time after the series back to the command' {
        $r = Get-Req 'Get the meetings with the title: Garden sync from monday to wednesday'
        $r.series | Should Be 'Garden sync'
        (@($r.days)) -join ',' | Should Be '2031-04-07,2031-04-08,2031-04-09'
    }
    It 'reads a time in the middle, the words after it as the series' {
        $r = Get-Req 'Fetch meetings this week Daily Standup'
        $r.series | Should Be 'Daily Standup'
        @($r.days).Count | Should Be 5
    }
    It 'reads the time before the word after a verb, with a long Teams title as the series (D-079)' {
        $r = Get-Req 'Fetch for this week meetings Daily Sync | Fernbrook & Tidal | Garden Platform & Pump Studio Governance'
        $r.series | Should Be 'Daily Sync | Fernbrook & Tidal | Garden Platform & Pump Studio Governance'
        @($r.days).Count | Should Be 5
        (Get-Req 'Fetch this week Daily Sync | Fernbrook & Tidal').series | Should Be 'Daily Sync | Fernbrook & Tidal'
    }
    It 'keeps notes with a time in them as notes' {
        Get-Req 'Yesterday meetings ran late' | Should Be $null
        Get-Req 'Get the budget done this week and send it' | Should Be $null
    }
    It 'still leaves "with" in a note alone' {
        Get-Req 'meeting with Ada yesterday' | Should Be $null
        Get-Req 'Monday sync notes are in the folder' | Should Be $null
    }
}

Describe 'Get-MeetingRequest: a series fetched on a day it does not meet (D-080)' {
    It 'takes the past 7 days for a series without a time, today for no series' {
        $r = Get-Req 'Fetch Daily Sync | Fernbrook & Tidal meetings'
        (@($r.days)) -join ',' | Should Be '2031-04-07,2031-04-08,2031-04-09,2031-04-10,2031-04-11'
        $r.when | Should Be 'the past 7 days'
        # A Monday: last Tuesday to Friday, and the Monday itself.
        (@((Get-MeetingRequest -Text 'Fetch Daily Standup meetings' -Today ([datetime]'2031-04-14')).days)) -join ',' | Should Be '2031-04-08,2031-04-09,2031-04-10,2031-04-11,2031-04-14'
        Get-Days 'Fetch meetings' | Should Be '2031-04-11'
    }
    It 'reads "this weeks", "this week''s" and "the week" as this week' {
        foreach ($t in @('Fetch this weeks meetings Daily Sync | Fernbrook', 'Fetch meetings for the week Daily Sync | Fernbrook', ('Fetch this week' + [char]0x2019 + 's meetings Daily Sync | Fernbrook'))) {
            $r = Get-Req $t
            $r.series | Should Be 'Daily Sync | Fernbrook'
            @($r.days).Count | Should Be 5
        }
    }
    It 'takes a long series before the time after a verb when it reads as a meeting title' {
        $r = Get-Req 'Fetch Daily Sync | Fernbrook & Tidal | Garden Platform this week'
        $r.series | Should Be 'Daily Sync | Fernbrook & Tidal | Garden Platform'
        @($r.days).Count | Should Be 5
        (Get-Req 'Get Weekly Garden Review Board Sync last week').series | Should Be 'Weekly Garden Review Board Sync'
        Get-Req 'Get the slides ready for the review this week' | Should Be $null
    }
}

Describe 'Get-MeetingRequest: what is not a request' {
    It 'leaves questions, notes and singular "meeting" alone' {
        foreach ($t in @(
                'What did we decide in the meetings last week',
                'Which meetings did I miss yesterday',
                'show me the meetings about budget',
                'Board meetings this week went well',
                'Daily Standup meetings',
                'meeting with Ada yesterday',
                'Gisteren overleg met het team over de verhuizing.',
                "meetings yesterday`nwith notes below",
                'meetings yesterday?')) {
            Get-Req $t | Should Be $null
        }
    }
}

Describe 'Get-Intent: rule 5, a meetings request (auto only)' {
    It 'reads it as meetings, with the days on the result' {
        $r = Get-Intent -Text 'Daily Standup meetings this week' -Today $script:Today
        $r.intent | Should Be 'meetings'
        $r.rule | Should Be 5
        @($r.meetings.days).Count | Should Be 5
        $r.reason | Should Match '2031-04-07 to 2031-04-11 \(5 days'
        $r.reason | Should Match 'series "Daily Standup" only'
    }
    It 'lets an explicit choice win' {
        (Get-Intent -Text 'meetings yesterday' -Mode add).intent | Should Be 'add'
        (Get-Intent -Text 'meetings yesterday' -Mode ask).intent | Should Be 'ask'
        (Get-Intent -Text '+meetings yesterday').intent | Should Be 'add'
    }
    It 'names the problem as the reason when it cannot be fetched' {
        $r = Get-Intent -Text 'meetings last 30 days' -Today $script:Today
        $r.intent | Should Be 'meetings'
        $r.reason | Should Match 'at most 14 days'
    }
}

Describe 'Get-MeetingRequest: the many ways to ask (fixtures/meeting-request-samples.json; D-078)' {
    # Phrasings in English and Dutch: verbs, polite forms, possessives, number and month words,
    # ranges, "since", "ago", short weekdays, series before or after, and notes and questions that
    # must stay what they are. A sample that fails names its text.
    $fx = Get-Content (Join-Path $here 'fixtures\meeting-request-samples.json') -Raw | ConvertFrom-Json
    $day = [datetime]$fx.today
    foreach ($s in @($fx.samples)) {
        It "reads: $($s.text)" {
            $r = Get-MeetingRequest -Text $s.text -Today $day
            if ($s.want -eq 'none') { $r | Should Be $null; return }
            $r | Should Not Be $null
            if ($s.want -eq 'error') { $r.error | Should Match ([regex]::Escape($s.error)); return }
            $r.error | Should Be ''
            $d = @($r.days)
            "$($d[0])..$($d[$d.Count - 1]) ($($d.Count))" | Should Be "$($s.first)..$($s.last) ($($s.count))"
            $r.series | Should Be $s.series
        }
    }
    It 'has a good spread of samples' {
        @($fx.samples).Count | Should BeGreaterThan 150
        @($fx.samples | Where-Object { $_.want -eq 'none' }).Count | Should BeGreaterThan 20
    }
}

Describe 'Code files hold no control characters' {
    # A "\b" once became a backspace in a pattern and silently stopped "Show me ..." being a question.
    It 'finds none in lib, tools, tests and the UI source' {
        $bad = @(Get-ChildItem (Join-Path $root 'lib'), (Join-Path $root 'tools'), $here, (Join-Path $root 'ui-src\src') -Recurse -File -Include *.ps1, *.psm1, *.ts, *.tsx, *.json, *.css |
                Where-Object { [IO.File]::ReadAllText($_.FullName) -match '[\x00-\x08\x0B\x0C\x0E-\x1F]' } | ForEach-Object { $_.Name })
        $bad -join ', ' | Should Be ''
    }
}

Describe 'Test-MeetingInSeries' {
    It 'finds the filter''s words in the meeting''s series, punctuation and case aside' {
        Test-MeetingInSeries -Title 'Daily Standup | Team A' -Filter 'daily standup' | Should Be $true
        Test-MeetingInSeries -Title 'Daily Standup | Team A' -Filter 'Standup' | Should Be $true
        Test-MeetingInSeries -Title 'Daily Standup 2031-04-08' -Filter 'Daily Standup' | Should Be $true
        Test-MeetingInSeries -Title 'Daily Standups review' -Filter 'Standup' | Should Be $false
        Test-MeetingInSeries -Title 'Lunch talk' -Filter 'Daily Standup' | Should Be $false
        Test-MeetingInSeries -Title 'Lunch talk' -Filter '' | Should Be $true
    }
}

Describe 'POST /api/submit and /api/meetings/day with a meetings request' {
    $app = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
    [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), '{"notebook":""}')
    It 'answers the days to list at once, without Copilot or a vault, and writes nothing' {
        $s = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"Daily Standup meetings 7-4 to 9-4","mode":"auto"}' -State $s
        $r.status | Should Be 200
        $r.body.intent | Should Be 'meetings'
        @($r.body.days).Count | Should Be 3
        $r.body.series | Should Be 'Daily Standup'
    }
    It 'refuses a request it cannot fetch with 400 and the reason' {
        $s = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server'
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/submit' -Body '{"text":"meetings last 30 days","mode":"auto"}' -State $s
        $r.status | Should Be 400
        $r.body.error | Should Match 'at most 14 days'
    }
    It 'keeps only the series'' meetings of a day, and says how many the day had' {
        $reply = '{"ref":"REF","meetings":[{"title":"Daily Standup | Tidal beds","start":"2031-04-09 09:00","hasTranscript":true},{"title":"Lunch talk","start":"2031-04-09 12:30"}]}'
        $send = { param([string]$Text) $ref = [regex]::Match($Text, '"ref": "([a-z0-9]+)"').Groups[1].Value; $reply.Replace('"REF"', '"' + $ref + '"') }.GetNewClosure()
        $s = New-ServerState -AppRoot $app -Port 8767 -SessionId 'server' -TestCopilot @{ Send = $send; NewChat = { } }
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{"day":"2031-04-09","series":"Daily Standup"}' -State $s
        $r.status | Should Be 200
        @($r.body.meetings).Count | Should Be 1
        @($r.body.meetings)[0].title | Should Be 'Daily Standup | Tidal beds'
        $r.body.total | Should Be 2
        $all = Invoke-ApiRoute -Method 'POST' -Path '/api/meetings/day' -Body '{"day":"2031-04-09"}' -State $s
        @($all.body.meetings).Count | Should Be 2
    }
}
