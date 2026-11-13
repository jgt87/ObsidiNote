# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/Ingest.psm1: Add of a text item end to end, failures, the write guard, Undo and the log.
# Fake vault and recorded Copilot replies; no OneNote, no Edge, nothing on disk except the log test.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $here '..\lib\Linker.psm1') -Force
Import-Module (Join-Path $here '..\lib\Ingest.psm1') -Force
. (Join-Path $here 'FakeVault.ps1')

$script:Now = [datetime]'2026-11-13T10:00:00'
$script:Text = "An identity-aware proxy checks who the user is and which device they use before it forwards a request.`nWe use it for the partner portal instead of the old VPN."

function Get-GoodReply {
    $sl = Get-LinkShortlist -Index (New-FakeIndex) -Text $script:Text
    $t = @($sl.topics | Where-Object { $_['path'] -eq 'Security/Networking' })[0]['id']
    '{"title": "Identity-aware proxies", "summary": "A proxy that checks user and device before it forwards a request.", "type": "concept", "topics": [{"new": "Security/Networking/Zero trust"}, {"id": "' + $t + '"}], "links": [{"target": "p1", "anchor": "checks who the user is", "strength": 3, "why": "core concept this implements"}, {"target": "p2", "anchor": "partner portal", "strength": 2, "why": "where it is used"}, {"target": "p3", "anchor": "the old VPN", "strength": 1, "why": "replaces it"}, {"target": "p77", "anchor": "request", "strength": 2, "why": "invented"}], "aliases": ["IAP"], "intent": "add"}'
}

function Invoke-Add([string]$Reply, $Vault, [string]$Mode = 'add', [string]$Text = $script:Text) {
    $c = New-FakeCopilot @($Reply)
    $r = Invoke-AddRequest -Request @{ text = $Text; mode = $Mode } -Store $Vault.store -Ask $c.ask -Options @{ Now = $script:Now }
    @{ r = $r; c = $c }
}

Describe 'Store contract' {
    It 'lists the adapter functions Add needs and finds missing ones' {
        (Get-IngestStoreContract).Count | Should Be 19
        $v = New-FakeVault
        (Get-MissingStoreFunctions $v.store).Count | Should Be 0
        $v.store.Remove('SetLinkedFrom')
        (Get-MissingStoreFunctions $v.store) -join ',' | Should Be 'SetLinkedFrom'
    }
    It 'adds nothing with an incomplete adapter' {
        $v = New-FakeVault; $v.store.Remove('IndexAddPage')
        $x = Invoke-Add (Get-GoodReply) $v
        $x.r.status | Should Be 'failed'
        $x.r.message | Should Match 'incomplete \(IndexAddPage\)'
        $x.c.q.prompts.Count | Should Be 0
    }
}

Describe 'Invoke-AddRequest with text' {
    $v = New-FakeVault
    $x = Invoke-Add (Get-GoodReply) $v
    $r = $x.r

    It 'writes the Inbox page before it asks Copilot, then files it' {
        $calls = @($v.st.calls)
        [array]::IndexOf($calls, 'CreateInboxItem') | Should BeLessThan ([array]::IndexOf($calls, 'CreatePage'))
        $v.st.inbox['{IN0}'].kind | Should Be 'text'
        $v.st.inbox['{IN0}'].title.Length | Should Be 80
        $v.st.inbox['{IN0}'].title.EndsWith('...') | Should Be $true
        $v.st.inbox['{IN0}'].status | Should Be 'linked'
        $v.st.inbox['{IN0}'].filedAs | Should Be 'p101'
        $r.inbox.status | Should Be 'linked'
    }
    It 'sends one prompt with the item and the shortlist' {
        $x.c.q.prompts.Count | Should Be 1
        $x.c.q.prompts[0] | Should Match 'p2 \| Partner portal'
        $x.c.q.prompts[0] | Should Match 'Today is 2026-11-13'
    }
    It 'creates the content page in its bucket with Meta data and a body with onenote: links' {
        $page = $v.st.created['{NEW-p101}']
        $page.bucket | Should Be 'Notes'
        $page.type | Should Be 'concept'
        ($page.topics -join ';') | Should Be 'Security/Networking/Zero trust;Security/Networking'
        ($page.aliases -join ',') | Should Be 'IAP'
        @($page.links).Count | Should Be 3
        @($page.links)[0]['target'] | Should Be 'p1'
        @($page.outlines)[0]['role'] | Should Be 'body'
        $body = @($page.outlines)[0]['lines']
        @($body).Count | Should Be 2
        $linked = @($body | ForEach-Object { $_['parts'] } | Where-Object { $_['href'] })
        ($linked | ForEach-Object { "$($_['text'])=$($_['href'])" }) -join '|' | Should Be 'checks who the user is=onenote:#p1|partner portal=onenote:#p2|the old VPN=onenote:#p3'
        (@($body)[0]['parts'] | ForEach-Object { $_['text'] }) -join '' | Should Be 'An identity-aware proxy checks who the user is and which device they use before it forwards a request.'
    }
    It 'writes "Linked from" on every target, keeping the pages that already link there' {
        $r.backlinks | Should Be 3
        (@($v.st.linkedFrom['p1']) | ForEach-Object { $_['id'] }) -join ',' | Should Be 'p101,p3'
        @($v.st.linkedFrom['p2'])[0]['link'] | Should Be 'onenote:#p101'
        $v.st.linkedFrom.ContainsKey('p77') | Should Be $false
    }
    It 'updates the index with the new page' {
        $op = $v.st.indexOps[0]
        $op['op'] | Should Be 'add'
        $op['page']['pageId'] | Should Be '{NEW-p101}'
        $op['page']['section'] | Should Be 'Notes'
    }
    It 'returns what the Add result screen needs' {
        $r.status | Should Be 'added'
        $r.message | Should Be 'Added: Identity-aware proxies'
        $r.page.topicPath | Should Be 'Security/Networking/Zero trust'
        ($r.page.alsoUnder -join ';') | Should Be 'Security/Networking'
        ($r.page.oneNotePath -join ' > ') | Should Be 'ObsidiNote > Notes > Identity-aware proxies'
        (@($r.chips) | ForEach-Object { "$($_['kind']):$($_['label'])" }) -join ',' | Should Be 'type:concept,alias:IAP,new-topic:Zero trust,topic:Networking'
        @($r.links)[0]['strength'] | Should Be 3
        @($r.links)[0]['anchor'] | Should Be 'checks who the user is'
        @($r.links)[0]['why'] | Should Be 'core concept this implements'
        @($r.links)[2]['title'] | Should Be 'VPN retirement plan'
        @($r.dropped)[0]['value'] | Should Be 'p77'
        (@($r.related) | ForEach-Object { $_['id'] }) -contains 'p4' | Should Be $true
        (@($r.related) | ForEach-Object { $_['id'] }) -contains 'p1' | Should Be $false
        $r.undo.id | Should Be 'p101'
        ($r.undo.targets -join ',') | Should Be 'p1,p2,p3'
        $r.timings.totalMs | Should BeGreaterThan -1
    }
    It 'serializes to JSON with lists that stay lists' {
        $j = $r | ConvertTo-Json -Depth 12 -Compress
        $o = ConvertFrom-Json $j
        $o.page.alsoUnder.GetType().IsArray | Should Be $true
        $o.page.oneNotePath.Count | Should Be 3
        $o.links.Count | Should Be 3
        $j | Should Match '"warnings":\[\]'
    }
}

Describe 'Invoke-AddRequest failures' {
    It 'keeps the Inbox item as failed with the reason when the JSON is broken' {
        $v = New-FakeVault
        $x = Invoke-Add '{"title": "Identity-aware proxies", "type": "concept", "links": [' $v
        $x.r.status | Should Be 'failed'
        $x.r.message | Should Match 'could not be read'
        $v.st.inbox['{IN0}'].status | Should Be 'failed'
        $v.st.inbox['{IN0}'].reason | Should Match 'could not be read'
        $v.st.created.Count | Should Be 0
        $v.st.linkedFrom.Count | Should Be 0
    }
    It 'fails on a type outside the fixed list' {
        $v = New-FakeVault
        $x = Invoke-Add '{"title": "T", "type": "topic"}' $v
        $x.r.status | Should Be 'failed'
        $v.st.inbox['{IN0}'].reason | Should Match 'fixed types'
    }
    It 'fails on a duplicate page and points to it' {
        $v = New-FakeVault
        $x = Invoke-Add '{"title": "Zero-trust networking", "type": "concept"}' $v
        $x.r.status | Should Be 'failed'
        @($x.r.related)[0]['id'] | Should Be 'p1'
        $v.st.created.Count | Should Be 0
    }
    It 'fails when Copilot throws, and when the bridge reports no answer' {
        $v = New-FakeVault
        $r = Invoke-AddRequest -Request @{ text = 'note' } -Store $v.store -Ask { throw 'socket closed' }
        $r.status | Should Be 'failed'
        $r.message | Should Match 'Copilot did not answer: socket closed'
        $v.st.inbox['{IN0}'].status | Should Be 'failed'
        $v = New-FakeVault
        $r = Invoke-AddRequest -Request @{ text = 'note' } -Store $v.store -Ask { [pscustomobject]@{ Text = ''; Result = 'NoAnswer' } }
        $r.message | Should Match 'NoAnswer'
    }
    It 'accepts the bridge reply object' {
        $v = New-FakeVault
        $reply = Get-GoodReply
        $r = Invoke-AddRequest -Request @{ text = $script:Text } -Store $v.store -Ask { [pscustomobject]@{ Text = $reply; Result = 'Success' } }.GetNewClosure() -Options @{ Now = $script:Now }
        $r.status | Should Be 'added'
    }
    It 'keeps the Inbox item when the page cannot be written' {
        $v = New-FakeVault; $v.st.fail['CreatePage'] = 'COM error'
        $x = Invoke-Add (Get-GoodReply) $v
        $x.r.status | Should Be 'failed'
        $x.r.message | Should Match 'Could not write the page: COM error'
        $v.st.inbox['{IN0}'].status | Should Be 'failed'
    }
    It 'still adds the page when a backlink or the index cannot be written, with warnings' {
        $v = New-FakeVault; $v.st.fail['SetLinkedFrom'] = 'busy'; $v.st.fail['IndexAddPage'] = 'busy'
        $x = Invoke-Add (Get-GoodReply) $v
        $x.r.status | Should Be 'added'
        $x.r.backlinks | Should Be 0
        @($x.r.warnings | Where-Object { $_ -match 'Linked from' }).Count | Should Be 3
        @($x.r.warnings | Where-Object { $_ -match 'Unfiled' }).Count | Should Be 1
    }
    It 'adds nothing for empty text' {
        $v = New-FakeVault
        (Invoke-Add '{}' $v 'add' '   ').r.message | Should Be 'There is nothing to add.'
        $v.st.calls.Count | Should Be 0
    }
}

Describe 'Write guard: the active vault only' {
    It 'writes nothing and does not ask Copilot when the guard refuses' {
        $v = New-FakeVault; $v.st.writable = $false
        $x = Invoke-Add (Get-GoodReply) $v
        $x.r.status | Should Be 'failed'
        $x.r.message | Should Match 'Write refused'
        $x.c.q.prompts.Count | Should Be 0
        (@($v.st.calls) -join ',') | Should Be 'AssertWritable'
    }
    It 'goes through the adapter for every write' {
        $v = New-FakeVault
        $null = Invoke-Add (Get-GoodReply) $v
        $writes = @($v.st.calls | Where-Object { $_ -notin @('GetIndex', 'ReadPage', 'FindPageByUrl') })
        ($writes | Select-Object -Unique) -join ',' | Should Be 'AssertWritable,CreateInboxItem,CreatePage,SetLinkedFrom,IndexAddPage,SetInboxStatus'
    }
}

Describe 'Intent from Copilot' {
    It 'offers Ask instead in auto mode when Copilot says it is a question, and removes the Inbox item' {
        $v = New-FakeVault
        $x = Invoke-Add '{"title": "Which proxy do we use?", "type": "note", "intent": "ask"}' $v 'auto' 'which proxy do we use for the portal'
        $x.r.status | Should Be 'ask-instead'
        @($v.st.deleted) -contains '{IN0}' | Should Be $true
        $v.st.created.Count | Should Be 0
    }
    It 'adds anyway when the person chose Add' {
        $v = New-FakeVault
        $x = Invoke-Add '{"title": "Which proxy do we use", "type": "note", "intent": "ask"}' $v 'add' 'which proxy do we use for the portal'
        $x.r.status | Should Be 'added'
    }
}

Describe 'Undo-AddRequest' {
    It 'sends the page to Deleted Pages, takes it out of the index and reverts the backlinks' {
        $v = New-FakeVault
        $r = (Invoke-Add (Get-GoodReply) $v).r
        $u = Undo-AddRequest -Store $v.store -Undo $r.undo
        $u.status | Should Be 'undone'
        $u.message | Should Match 'Deleted Pages'
        @($v.st.deleted) -contains '{NEW-p101}' | Should Be $true
        @($v.st.indexOps | Where-Object { $_['op'] -eq 'remove' })[0]['id'] | Should Be 'p101'
        (@($v.st.linkedFrom['p1']) | ForEach-Object { $_['id'] }) -join ',' | Should Be 'p3'
        @($v.st.linkedFrom['p2']).Count | Should Be 0
        $u.backlinks | Should Be 3
    }
    It 'refuses a page that is not in the index, and a page id that does not match' {
        $v = New-FakeVault
        (Undo-AddRequest -Store $v.store -Undo @{ id = 'p999'; pageId = '{X}'; targets = @() }).status | Should Be 'failed'
        $u = Undo-AddRequest -Store $v.store -Undo @{ id = 'p1'; pageId = '{OTHER}'; targets = @() }
        $u.status | Should Be 'failed'
        $v.st.deleted.Count | Should Be 0
    }
    It 'does nothing when the guard refuses' {
        $v = New-FakeVault
        $r = (Invoke-Add (Get-GoodReply) $v).r
        $v.st.writable = $false
        (Undo-AddRequest -Store $v.store -Undo $r.undo).message | Should Match 'Write refused'
        $v.st.deleted.Count | Should Be 0
    }
}

Describe 'Body lines and anchors' {
    It 'links only the first occurrence of each anchor, in nested lines too' {
        $lines = ConvertTo-BodyLines "VPN here`nand VPN there`n`n"
        $lines.Count | Should Be 2
        $out = Add-AnchorLinks -Lines $lines -Links @(@{ anchor = 'vpn'; link = 'onenote:#x' })
        @(@($out)[0]['parts']).Count | Should Be 2
        @(@($out)[1]['parts']).Count | Should Be 1
    }
}

Describe 'Add writes no files' {
    It 'has no file-writing call in lib/Linker.psm1, lib/LinkCapture.psm1 or lib/Ingest.psm1' {
        $writes = '(?i)\b(WriteAllText|WriteAllLines|WriteAllBytes|AppendAllText|AppendAllLines|Set-Content|Add-Content|Out-File|Tee-Object|Start-Transcript|Copy-Item|Move-Item|New-Item|StreamWriter|FileStream|Export-(?!ModuleMember)\w+)\b'
        $hits = @(foreach ($f in 'Linker.psm1', 'LinkCapture.psm1', 'Ingest.psm1') {
            $i = 0
            foreach ($l in [IO.File]::ReadAllLines((Join-Path $here "..\lib\$f"))) {
                $i++
                if ($l -notmatch '^\s*#' -and $l -match $writes) { "${f}:$i" }
            }
        })
        ($hits -join ', ') | Should Be ''
    }
    It 'logs only ids, counts, states and timings' {
        $lines = @(Select-String -Path (Join-Path $here '..\lib\Ingest.psm1') -Pattern 'Write-AppLog' | ForEach-Object { $_.Line })
        $lines.Count | Should Be 2
        foreach ($l in $lines) { $l | Should Not Match '(?i)\$(text|title|message|prompt|reply|url|anchor|summary)\b|\.(text|title|message|url)\b' }
    }
}

Describe 'The log holds ids and counts only' {
    It 'writes no item text, title, anchor or summary' {
        $file = Join-Path $env:OBSIDINOTE_DATA_DIR 'logs\obsidinote.log'
        if (Test-Path $file) { Remove-Item $file -Force }
        $saved = $env:OBSIDINOTE_LOG
        $env:OBSIDINOTE_LOG = 'verbose'
        try {
            $v = New-FakeVault
            $null = Invoke-Add (Get-GoodReply) $v
        } finally { $env:OBSIDINOTE_LOG = $saved }
        $log = [IO.File]::ReadAllText($file)
        $log | Should Match 'Add finished'
        $log | Should Match '"id":"p101"'
        $log | Should Not Match 'identity-aware'
        $log | Should Not Match '(?i)proxies'
        $log | Should Not Match 'partner portal'
    }
}
