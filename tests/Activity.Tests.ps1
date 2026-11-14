# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/Activity.psm1 and GET /api/activity, POST /api/intake/remove: what ObsidiNote did, read from the
# vault's own Intake (operator, 2026-11-14). Synthetic data in the in-memory OneNote only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest', 'Activity', 'Server') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function New-TempAppRoot {
    $d = Join-Path $env:TEMP ('obsn-act-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"uiPort":8767,"cdpPort":9334}')
    $d
}

Describe 'Get-ActivityList (pure)' {
    $page = { param($id, $upd, $meta) @{ id = $id; title = "Item $id"; updated = $upd; meta = $meta } }
    $pages = @(
        (& $page 'i1' '2026-11-14T08:00:00Z' @{ 'obsn.status' = 'linked'; 'obsn.filedAs' = 'p1'; 'obsn.requestKind' = 'classify'; 'obsn.inboxKind' = 'text' }),
        (& $page 'i2' '2026-11-14T09:00:00Z' @{ 'obsn.status' = 'waiting'; 'obsn.waitingSince' = '2026-11-14T08:59:00Z'; 'obsn.requestKind' = 'classify' }),
        (& $page 'i3' '2026-11-14T10:00:00Z' @{ 'obsn.status' = 'linked'; 'obsn.filedAs' = 'p9'; 'obsn.requestKind' = 'classify' }),
        (& $page 'i4' '2026-11-14T11:00:00Z' @{ 'obsn.status' = 'linked'; 'obsn.filedAs' = 'p2'; 'obsn.requestKind' = 'linkUpdate'; 'obsn.inboxKind' = 'link' }),
        (& $page 'i5' '2026-11-14T12:00:00Z' @{ 'obsn.status' = 'failed'; 'obsn.statusReason' = 'Copilot gave no answer' }),
        (& $page 'i6' '2026-11-14T13:00:00Z' @{ 'obsn.status' = 'new' })
    )
    $index = @{ p1 = @{ title = 'Zero trust'; type = 'concept' }; p2 = @{ title = 'Handbook'; type = 'link-web' } }
    $list = Get-ActivityList -Pages $pages -Index $index
    It 'lists newest first with one state per item' {
        (@($list | ForEach-Object { "$($_.inboxId):$($_.state)" }) -join ',') | Should Be 'i6:working,i5:failed,i4:updated,i3:gone,i2:waiting,i1:added'
    }
    It 'names the page an item became, and offers only the actions that fit' {
        $a = @($list | Where-Object { $_.inboxId -eq 'i1' })[0]
        "$($a.filedTitle)|$($a.canUndo)|$($a.canRemove)|$($a.canCheck)" | Should Be 'Zero trust|True|False|False'
        $w = @($list | Where-Object { $_.inboxId -eq 'i2' })[0]
        "$($w.canCheck)|$($w.canRemove)|$($w.canUndo)|$($w.since)" | Should Be 'True|True|False|2026-11-14T08:59:00Z'
        # an Update changed a page that existed before: no Undo of the page
        @($list | Where-Object { $_.inboxId -eq 'i4' })[0].canUndo | Should Be $false
        @($list | Where-Object { $_.inboxId -eq 'i5' })[0].reason | Should Be 'Copilot gave no answer'
    }
    It 'gives an empty list for an empty Intake' {
        $e = Get-ActivityList -Pages @() -Index @{}   # returns , @(...): assign as is (AGENTS.md)
        $e.Count | Should Be 0
    }
}

Describe 'GET /api/activity and POST /api/intake/remove (in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'start'
    # Two Intake items as Add leaves them: one filed as p1, one still waiting for Copilot.
    $filed = & $w.store.CreateInboxItem 'Note about zero trust' 'Never trust the network.' 'text' 'rAAAA0001' 'classify'
    $null = & $w.store.SetInboxStatus $filed.pageId 'linked' '' 'p1'
    $wait = & $w.store.CreateInboxItem 'Slow link' 'https://example.invalid/slow' 'link' 'rAAAA0002' 'linkSummary'
    $null = & $w.store.SetInboxWaiting $wait.pageId 'rAAAA0002' 'linkSummary' 'https://example.invalid/chat' '2026-11-14T08:00:00Z'
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'start' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    It 'lists the Intake items with their state and the page they became' {
        $r = Invoke-ApiRoute -Method 'GET' -Path '/api/activity' -State $state
        $r.status | Should Be 200
        $r.body.canChange | Should Be $true
        $byId = @{}; foreach ($i in @($r.body.items)) { $byId[$i.inboxId] = $i }
        $byId[$filed.pageId].state | Should Be 'added'
        $byId[$filed.pageId].filedTitle | Should Be 'Zero-trust networking'
        $byId[$wait.pageId].state | Should Be 'waiting'
    }
    It 'refuses to remove an item that became a page, and a page outside the Intake' {
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intake/remove' -Body ('{"inboxId":"' + $filed.pageId + '"}') -State $state).status | Should Be 409
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intake/remove' -Body ('{"inboxId":"' + $w.tomato + '"}') -State $state).status | Should Be 404
        $w.f.Nodes.ContainsKey($w.tomato) | Should Be $true
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intake/remove' -Body '{"inboxId":"x"}' -State $state).status | Should Be 400
    }
    It 'removes a waiting item to Deleted Pages' {
        $r = Invoke-ApiRoute -Method 'POST' -Path '/api/intake/remove' -Body ('{"inboxId":"' + $wait.pageId + '"}') -State $state
        $r.status | Should Be 200
        @($w.f.Writes | Where-Object { $_ -eq "DeleteHierarchy $($wait.pageId)" }).Count | Should Be 1
        @((Invoke-ApiRoute -Method 'GET' -Path '/api/activity' -State $state).body.items | Where-Object { $_.inboxId -eq $wait.pageId }).Count | Should Be 0
    }
    It 'refuses removal in a read-only window' {
        $item = & $w.store.CreateInboxItem 'Another' 'text' 'text' 'rAAAA0003' 'classify'
        $state.Lease.mode = 'readonly'
        (Invoke-ApiRoute -Method 'POST' -Path '/api/intake/remove' -Body ('{"inboxId":"' + $item.pageId + '"}') -State $state).status | Should Be 409
        $state.Lease.mode = 'writer'
    }
    Remove-Item $app -Recurse -Force
}

Describe 'Undo from History: only the page id' {
    $w = New-SyntheticVault
    It 'finds the pages it links to in the index and rewrites their "Linked from"' {
        # p3 links to p1 (SyntheticVault); undo p3 with its id alone
        $r = Undo-AddRequest -Store $w.store -Undo @{ id = 'p3' }
        $r.status | Should Be 'undone'
        $r.backlinks | Should Be 1
    }
}
