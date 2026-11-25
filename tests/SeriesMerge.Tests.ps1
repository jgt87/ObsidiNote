# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# "Merge duplicates" of a meeting series (D-075): lib/Ingest.psm1 Get-SeriesMergePlan / Invoke-SeriesMerge and the route
# POST /api/series/merge. Two copies of one meeting, made by versions before the occurrence check of
# 2026-11-18, become one page; the other copy goes to the Archive. In-memory OneNote; invented data.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP ('obsidinote-test-data' + $(if ($env:OBSIDINOTE_TEST_TAG) { '-' + $env:OBSIDINOTE_TEST_TAG } else { '' }))
Import-Module (Join-Path $root 'lib\Server.psm1') -Force
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Ingest', 'Meetings') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function New-TempAppRoot {
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    $d
}

$script:Teams = 'Garden sync | Tidal & Brook | Beds and pumps'
$script:Dot = [char]0x00B7

function Add-SeriesMeeting($W, [string]$Day, [string]$At, [string]$Title, [hashtable]$Notes, [object[]]$Links = @()) {
    $text = ConvertTo-MeetingNoteText -Title $script:Teams -Day $Day -Time '09:00' -Notes $Notes
    $id = & $W.store.NewId
    $data = ConvertTo-MeetingDataValue (Get-MeetingDataFromText $text)
    $page = @{ id = $id; type = 'meeting'; bucket = (& $W.store.BucketForType 'meeting'); title = $Title; summary = 'Garden notes.'; topics = @('Garden'); aliases = @(); links = $Links; status = ''; origin = 'meeting'
        series = $script:Teams; meetingAt = $At; meeting = $data; meetingData = '1'; outlines = @(@{ role = 'body'; lines = (ConvertTo-BodyLines $text) }) }
    $cp = & $W.store.CreatePage $page
    $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']
    & $W.store.IndexAddPage $page | Out-Null
    $page
}

function New-MergeVault {
    $w = New-SyntheticVault -SessionId 'server'
    $n1 = @{ found = $true; date = ''; attendees = @(@{ name = 'Ada Example'; email = 'ada@example.com' }); summary = 'The beds move north.'; decisions = @('Move the beds.'); actions = @(@{ text = 'Order a pump'; owner = 'Ada Example'; due = '' }); basedOn = 'transcript' }
    $n2 = @{ found = $true; date = ''; attendees = @(@{ name = 'Ada Example'; email = 'ADA@example.com' }, @{ name = 'Bo Sample'; email = 'bo@example.com' }); summary = 'Beds north, pumps next.'; decisions = @('Move the beds.', 'Buy two pumps.'); actions = @(@{ text = 'Order a pump'; owner = ''; due = '' }, @{ text = 'Call the supplier'; owner = 'Bo Sample'; due = '' }); basedOn = 'recap' }
    # 17 Nov twice: a copy with the start time (kept) and one without (an older version's import).
    $a = Add-SeriesMeeting $w '2026-11-17' '2026-11-17T09:00' "$($script:Teams) $($script:Dot) 2026-11-17 09:00" $n1 @(@{ target = 'p1'; strength = 2; why = 'about it' })
    $b = Add-SeriesMeeting $w '2026-11-17' '2026-11-17' "$($script:Teams) $($script:Dot) 2026-11-17" $n2 @(@{ target = 'p3'; strength = 2; why = 'about it' })
    # 18 Nov links its previous meeting: the copy without the time.
    $c = Add-SeriesMeeting $w '2026-11-18' '2026-11-18T09:00' "$($script:Teams) $($script:Dot) 2026-11-18" $n1 @(@{ target = $b.id; strength = 1; why = 'The previous meeting of this series.' })
    $res = @{ warnings = @(); timings = @{ copilotMs = 0 } }
    Update-SeriesPage -Store $w.store -Ask $null -Info @{ key = (Get-MeetingSeriesKey $script:Teams); series = $script:Teams } -Result $res
    @{ w = $w; a = $a; b = $b; c = $c }
}

Describe 'Merge duplicates: the plan' {
    $v = New-MergeVault
    $plan = Get-SeriesMergePlan -Index (& $v.w.store.GetIndex) -Key (Get-MeetingSeriesKey $script:Teams)
    It 'groups the two copies of 17 Nov and keeps the one with the start time' {
        @($plan.groups).Count | Should Be 1
        $plan.groups[0].keep.id | Should Be $v.a.id
        (@($plan.groups[0].extra | ForEach-Object { $_.id }) -join ',') | Should Be $v.b.id
        $plan.series | Should Be $script:Teams
    }
    It 'leaves the series page and other days out' {
        $ids = @($plan.groups | ForEach-Object { $_.keep.id; @($_.extra | ForEach-Object { $_.id }) })
        $ids -contains $v.c.id | Should Be $false
        @($v.w.open.model.pages.Values | Where-Object { $_.kind -eq 'series' -and $ids -contains $_.id }).Count | Should Be 0
    }
    It 'joins the notes: every person, decision and action once, the kept summary' {
        $d = Join-MeetingData (ConvertFrom-MeetingDataValue $v.a.meeting) (ConvertFrom-MeetingDataValue $v.b.meeting)
        (@($d.people | ForEach-Object { $_.name }) -join ',') | Should Be 'Ada Example,Bo Sample'
        ($d.decisions -join '|') | Should Be 'Move the beds.|Buy two pumps.'
        (@($d.actions | ForEach-Object { $_.text }) -join '|') | Should Be 'Order a pump|Call the supplier'
        $d.summary | Should Be 'The beds move north.'
    }
}

Describe 'Merge duplicates through the route (POST /api/series/merge)' {
    $v = New-MergeVault
    $w = $v.w
    $state = New-ServerState -AppRoot (New-TempAppRoot) -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $body = { param([bool]$Confirm) ConvertTo-Json -Compress -InputObject ([ordered]@{ series = $script:Teams; confirm = $Confirm; vault = $w.v.vaultId }) }
    It 'refuses bad input with 400 and writes nothing' {
        $before = $w.f.Writes.Count
        foreach ($b in 'not json', '{}', '{"series":""}', '{"series":5}', '{"series":"|  |"}') {
            (Invoke-ApiRoute -Method 'POST' -Path '/api/series/merge' -Body $b -State $state).status | Should Be 400
        }
        $w.f.Writes.Count | Should Be $before
    }
    It 'asks first: 409 with the plan, nothing written' {
        $before = $w.f.Writes.Count
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/series/merge' -Body (& $body $false) -State $state
        $r.status | Should Be 409
        $r.body.needsConfirm | Should Be $true
        @($r.body.plan.groups)[0].keep.id | Should Be $v.a.id
        @(@($r.body.plan.groups)[0].extra)[0].id | Should Be $v.b.id
        $w.f.Writes.Count | Should Be $before
    }
    It 'answers 409 with the other-vault sentence for another vault' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/series/merge' -Body ('{"series":"x","confirm":true,"vault":"cccccccc-0000-4000-8000-000000000003"}') -State $state
        $r.status | Should Be 409
        $r.body.error | Should Be 'This item belongs to another vault; open that vault to change it.'
    }
    $r = Invoke-ApiRoute -Method 'POST' -Path '/api/series/merge' -Body (& $body $true) -State $state
    $pages = $w.open.model.pages
    It 'merges with confirm and says so' {
        $r.status | Should Be 200
        $r.body.status | Should Be 'merged'
        $r.body.merged | Should Be 1
        $r.body.message | Should Match 'in the Archive'
    }
    It 'archives the other copy (restorable)' {
        $pages[$v.b.id].status | Should Be 'archived'
        $pages[$v.a.id].status | Should Not Be 'archived'
    }
    It 'keeps the notes of both on the kept page, in its data and its text' {
        $d = ConvertFrom-MeetingDataValue (ConvertFrom-ObsnMeta -Meta $w.f.Nodes[$v.a.pageId].meta).meeting
        (@($d.people | ForEach-Object { $_.name }) -join ',') | Should Be 'Ada Example,Bo Sample'
        (@($d.actions | ForEach-Object { $_.text }) -join '|') | Should Be 'Order a pump|Call the supplier'
        $md = & $w.store.BodyMarkdown $v.a.pageId
        $md | Should Match 'Call the supplier'
        $md | Should Match 'Buy two pumps\.'
    }
    It 'adds the other copy''s links to the kept page' {
        (@($pages[$v.a.id].links | ForEach-Object { $_.target } | Sort-Object) -join ',') | Should Be 'p1,p3'
    }
    It 'points the next meeting''s link at the kept page' {
        (@($pages[$v.c.id].links | ForEach-Object { $_.target }) -join ',') | Should Be $v.a.id
    }
    It 'writes the series page again with the live meetings only' {
        $sp = @($pages.Values | Where-Object { $_.kind -eq 'series' })[0]
        (@($sp.links | ForEach-Object { $_.target } | Sort-Object) -join ',') | Should Be ((@($v.a.id, $v.c.id) | Sort-Object) -join ',')
    }
    It 'finds nothing to merge the second time' {
        $r2 = Invoke-ApiRoute -Method 'POST' -Path '/api/series/merge' -Body (& $body $true) -State $state
        $r2.status | Should Be 200
        $r2.body.status | Should Be 'nothing'
    }
}
