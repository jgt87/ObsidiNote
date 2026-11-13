# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/LinkCapture.psm1 and the link flows of lib/Ingest.psm1 (new link, same link again = update,
# hand-edited summary, could not be read). Fake vault and recorded replies; no OneNote, no Copilot.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $here '..\lib\LinkCapture.psm1') -Force
Import-Module (Join-Path $here '..\lib\Ingest.psm1') -Force
. (Join-Path $here 'FakeVault.ps1')

$script:Now = [datetime]'2026-11-13T10:00:00'
$script:WebSummary = '{"readable": true, "problem": "", "title": "Identity-aware proxy explained", "where": "example.org", "kind": "article", "summary": "An identity-aware proxy checks the user and the device before it forwards a request. It replaces a VPN for many apps.", "keyFacts": ["Checks user and device", "Works per request"], "useFor": "When you plan remote access", "sensitivity": ""}'
$script:WebLinks = '{"title": "x", "summary": "How identity-aware proxies replace a VPN.", "type": "link-web", "topics": [{"new": "Security/Networking"}], "links": [{"target": "p3", "anchor": "replaces a VPN", "strength": 2, "why": "same move away from VPN"}], "aliases": ["IAP"], "intent": "add"}'
$script:HandbookNew = '{"readable": true, "title": "Contoso handbook", "where": "HR site", "kind": "page", "summary": "The staff handbook. Covers leave, devices and travel.", "keyFacts": ["Leave is 26 days", "Devices are managed", "Travel needs approval"], "useFor": "Policy questions", "sensitivity": "General"}'
$script:HandbookSame = '{"readable": true, "title": "Contoso handbook", "where": "HR site", "kind": "page", "summary": "The staff handbook.  Covers leave and devices.", "keyFacts": ["Leave is 25 days", "Devices are managed"], "useFor": "Policy questions", "sensitivity": "General"}'
$script:HandbookLinks = '{"title": "Contoso handbook", "summary": "The staff handbook.", "type": "link-internal", "topics": [{"new": "Projects"}], "links": [{"target": "p1", "anchor": "devices", "strength": 1, "why": "device rules"}], "aliases": [], "intent": "add"}'
$script:HandbookUrl = 'https://contoso.sharepoint.com/sites/hr/handbook.aspx'

function Get-Roles($Update) { @($Update.outlines | ForEach-Object { $_['role'] }) }

Describe 'Get-PastedUrl' {
    It 'returns the URL when the item is only a URL' {
        Get-PastedUrl '  https://example.org/a?b=1  ' | Should Be 'https://example.org/a?b=1'
        Get-PastedUrl '<https://example.org/x>' | Should Be 'https://example.org/x'
    }
    It 'is empty for text with a URL in it, or no URL' {
        Get-PastedUrl 'see https://example.org' | Should Be ''
        Get-PastedUrl 'ftp://example.org/f' | Should Be ''
        Get-PastedUrl '' | Should Be ''
    }
}

Describe 'New-LinkSummaryPrompt' {
    It 'asks Copilot to open an internal link with the user''s own access' {
        $p = New-LinkSummaryPrompt -Url $script:HandbookUrl -Bucket 'Internal links' -Today $script:Now
        $p | Should Match 'Microsoft 365 item with my own access'
        $p | Should Match ([regex]::Escape($script:HandbookUrl))
        $p | Should Match 'loop-page'
        $p | Should Match 'sensitivity label'
        $p | Should Match '"keyFacts": \["\.\.\."\]'
    }
    It 'asks for a web page summary with the web kinds' {
        $p = New-LinkSummaryPrompt -Url 'https://example.org/a' -Bucket 'Web links'
        $p | Should Match 'Read this web page'
        $p | Should Match 'article, docs, tool, video, other'
        $p | Should Match 'never copy the full text'
    }
}

Describe 'ConvertTo-LinkSummary' {
    It 'reads a good summary and limits key facts to 8' {
        $j = ConvertFrom-Json ('{"title":"T","where":"w","kind":"Loop Page","summary":"S.","keyFacts":["1","2","3","4","5","6","7","8","9"],"useFor":"u","sensitivity":"Confidential"}')
        $s = ConvertTo-LinkSummary -Reply $j -Bucket 'Internal links'
        $s.ok | Should Be $true
        $s.summary.kind | Should Be 'loop-page'
        @($s.summary.keyFacts).Count | Should Be 8
        $s.summary.sensitivity | Should Be 'Confidential'
    }
    It 'drops sensitivity for web links and maps unknown kinds to other' {
        $s = ConvertTo-LinkSummary -Reply (ConvertFrom-Json '{"title":"T","kind":"podcast","summary":"S.","sensitivity":"x"}') -Bucket 'Web links'
        $s.summary.kind | Should Be 'other'
        $s.summary.sensitivity | Should Be ''
    }
    It 'reports could-not-read with its problem' {
        $s = ConvertTo-LinkSummary -Reply (ConvertFrom-Json '{"readable":false,"problem":"no-access"}') -Bucket 'Internal links'
        $s.ok | Should Be $true
        $s.readable | Should Be $false
        $s.problem | Should Be 'no-access'
        (ConvertTo-LinkSummary -Reply (ConvertFrom-Json '{"readable":"false","problem":"gone"}') -Bucket 'Web links').problem | Should Be 'other'
    }
    It 'rejects a summary without title or text' {
        (ConvertTo-LinkSummary -Reply (ConvertFrom-Json '{"summary":"S."}') -Bucket 'Web links').ok | Should Be $false
        (ConvertTo-LinkSummary -Reply (ConvertFrom-Json '{"title":"T"}') -Bucket 'Web links').ok | Should Be $false
        (ConvertTo-LinkSummary -Reply $null -Bucket 'Web links').ok | Should Be $false
    }
}

Describe 'Summary hash and history' {
    It 'gives the same hash however the text is split into lines' {
        Get-SummaryHash "Link: a`nSummary:  b" | Should Be (Get-SummaryHash 'Link: a Summary: b')
        (Get-SummaryHash 'a').Length | Should Be 16
        Get-SummaryHash 'a' | Should Not Be (Get-SummaryHash 'b')
    }
    It 'sees a hand edit only when a stored hash no longer matches' {
        $h = Get-SummaryHash 'Summary: x'
        Test-SummaryEdited -OutlineText 'Summary:   x' -StoredHash $h | Should Be $false
        Test-SummaryEdited -OutlineText 'Summary: x, and my words' -StoredHash $h | Should Be $true
        Test-SummaryEdited -OutlineText 'anything' -StoredHash '' | Should Be $false
    }
    It 'keeps the last 3 summaries, newest first' {
        $h = @()
        foreach ($i in 1..5) { $h = Add-SummaryHistory -History $h -Previous @{ summary = "s$i"; keyFacts = @() } -At "2026-0$i-01" }
        @($h).Count | Should Be 3
        ((@($h) | ForEach-Object { $_['summary'] }) -join ',') | Should Be 's5,s4,s3'
    }
    It 'compares old and new: changed fields, facts added and removed' {
        $d = Compare-LinkSummary -Old @{ title = 'A'; kind = 'page'; summary = 'S'; keyFacts = @('x', 'y') } -New @{ title = 'A'; kind = 'site'; summary = ' s '; keyFacts = @('y', 'z') }
        $d.changed | Should Be $true
        $d.kind | Should Be $true
        $d.summary | Should Be $false
        ($d.factsAdded -join ',') | Should Be 'z'
        ($d.factsRemoved -join ',') | Should Be 'x'
        (Compare-LinkSummary -Old @{ title = 'A'; keyFacts = @('x') } -New @{ title = 'a '; keyFacts = @('X') }).changed | Should Be $false
    }
}

Describe 'Link page outlines' {
    It 'writes the fixed shape: link, where, kind, summary, key facts, use, sensitivity' {
        $s = @{ title = 'T'; where = 'HR site'; kind = 'page'; summary = 'S.'; keyFacts = @('a', 'b'); useFor = 'U'; sensitivity = 'General' }
        $lines = New-LinkSummaryLines -Url 'https://x.sharepoint.com/p' -Summary $s
        $text = Get-LinesPlainText $lines
        $text | Should Match '^Link: https://x\.sharepoint\.com/p'
        $text | Should Match 'Where: HR site'
        $text | Should Match "Key facts:`na`nb"
        $text | Should Match 'Sensitivity: General'
        @($lines)[0]['parts'][1]['href'] | Should Be 'https://x.sharepoint.com/p'
    }
    It 'says when a link could not be read' {
        (Get-LinesPlainText (New-LinkSummaryLines -Url 'https://x' -Summary $null -Problem 'not-found' -Today $script:Now)) | Should Match 'Could not be read on 2026-11-13: not found\.'
    }
    It 'keeps earlier summaries collapsed under the checked line' {
        $lines = New-LinkCheckedLines -SummarizedAt '2026-11-13' -History @(@{ at = '2026-08-01'; summary = 'old'; keyFacts = @('f'); edited = $true })
        @($lines)[0]['parts'][0]['text'] | Should Be 'Checked: 2026-11-13'
        $earlier = @($lines)[1]
        $earlier['collapsed'] | Should Be $true
        $earlier['children'][0]['parts'][0]['text'] | Should Be '2026-08-01 (edited by you)'
    }
}

Describe 'A new link' {
    It 'files a web link: summary call, then linking on the summary, one page in Web links' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:WebSummary, $script:WebLinks)
        $r = Invoke-AddRequest -Request @{ text = 'https://example.org/iap?utm_source=x#top'; mode = 'auto' } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'added'
        $r.kind | Should Be 'link'
        $c.q.prompts.Count | Should Be 2
        $c.q.prompts[0] | Should Match 'Read this web page'
        $c.q.prompts[0] | Should Match 'URL: https://example.org/iap\r?\n'
        $c.q.prompts[1] | Should Match 'type: always "link-web"'
        $page = $v.st.created['{NEW-p101}']
        $page.bucket | Should Be 'Web links'
        $page.type | Should Be 'link-web'
        $page.title | Should Be 'Identity-aware proxy explained'
        $page.url | Should Be 'https://example.org/iap'
        $page.host | Should Be 'example.org'
        $page.summarizedAt | Should Be '2026-11-13'
        ((@($page.outlines) | ForEach-Object { $_['role'] }) -join ',') | Should Be 'summary,checked,notes'
        $sum = @($page.outlines)[0]['lines']
        $page.summaryHash | Should Be (Get-SummaryHash (Get-LinesPlainText $sum))
        (ConvertFrom-Json $page.linkSummary).keyFacts.Count | Should Be 2
        $hrefs = @($sum | ForEach-Object { $_['parts'] } | Where-Object { $_['href'] -like 'onenote:*' })
        $hrefs[0]['text'] | Should Be 'replaces a VPN'
        $v.st.linkedFrom['p3'].Count | Should Be 1
        $v.st.inbox['{IN0}'].status | Should Be 'linked'
        $r.page.url | Should Be 'https://example.org/iap'
        $r.update.new.title | Should Be 'Identity-aware proxy explained'
    }
    It 'sends a SharePoint link to Internal links with the Microsoft 365 prompt' {
        $v = New-FakeVault; $c = New-FakeCopilot @(($script:HandbookNew -replace 'Contoso handbook', 'Travel policy'), $script:HandbookLinks)
        $r = Invoke-AddRequest -Request @{ text = 'https://contoso.sharepoint.com/sites/hr/travel.aspx'; mode = 'add' } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'added'
        $c.q.prompts[0] | Should Match 'Microsoft 365 item'
        $v.st.created['{NEW-p101}'].bucket | Should Be 'Internal links'
        $v.st.created['{NEW-p101}'].type | Should Be 'link-internal'
    }
    It 'keeps the link with "could not be read" and leaves it Unfiled, without a linking call' {
        $v = New-FakeVault; $c = New-FakeCopilot @('{"readable": false, "problem": "no-access"}')
        $r = Invoke-AddRequest -Request @{ text = 'https://contoso.sharepoint.com/sites/secret/x.aspx' } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'added'
        $c.q.prompts.Count | Should Be 1
        $r.page.unfiled | Should Be $true
        $r.warnings[0] | Should Match 'Could not be read on 2026-11-13: no access'
        $page = $v.st.created['{NEW-p101}']
        $page.checkStatus | Should Match 'no access'
        $page.summarizedAt | Should Be ''
        (Get-LinesPlainText @($page.outlines)[0]['lines']) | Should Match 'Could not be read'
    }
    It 'still files the summary when linking fails, Unfiled with a warning' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:WebSummary, 'no json today')
        $r = Invoke-AddRequest -Request @{ text = 'https://example.org/iap' } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'added'
        $r.page.unfiled | Should Be $true
        $r.warnings[0] | Should Match 'not linked'
    }
    It 'fails and keeps the Intake item when the summary answer is broken' {
        $v = New-FakeVault; $c = New-FakeCopilot @('{"title": "x", "summary": ')
        $r = Invoke-AddRequest -Request @{ text = 'https://example.org/iap' } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'failed'
        $v.st.inbox['{IN0}'].status | Should Be 'failed'
        $v.st.created.Count | Should Be 0
    }
}

Describe 'The same link again: update instead of a new page' {
    It 'finds the page by normalized URL and updates it: old vs new, history, relinking, never Your notes' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:HandbookNew, $script:HandbookLinks)
        $r = Invoke-AddRequest -Request @{ text = "$($script:HandbookUrl)?utm_campaign=mail#leave" } -Store $v.store -Ask $c.ask -Options @{ Now = $script:Now }
        $r.status | Should Be 'updated'
        $v.st.calls -contains 'CreateInboxItem' | Should Be $false
        $v.st.created.Count | Should Be 0
        $v.st.updates.Count | Should Be 1
        $u = $v.st.updates[0]
        $u.pageId | Should Be '{P7}'
        ((Get-Roles $u) -join ',') | Should Be 'summary,checked'
        $u.meta.summarizedAt | Should Be '2026-11-13'
        $u.meta.seenAt | Should Be '2026-11-13'
        $hist = ConvertFrom-Json $u.meta.history
        @($hist).Count | Should Be 1
        $hist[0].at | Should Be '2026-08-01'
        $hist[0].summary | Should Match 'Covers leave and devices'
        $r.update.diff.factsAdded -contains 'Travel needs approval' | Should Be $true
        $r.update.diff.factsRemoved -contains 'Leave is 25 days' | Should Be $true
        $r.update.oldAt | Should Be '2026-08-01'
        @($r.links)[0]['target'] | Should Be 'p1'
        @($r.update.review)[0]['target'] | Should Be 'p4'
        @($u.meta.links | ForEach-Object { $_['target'] }) -contains 'p4' | Should Be $true
        $v.st.linkedFrom.ContainsKey('p1') | Should Be $true
        $v.st.linkedFrom.ContainsKey('p4') | Should Be $false
        @($v.st.indexOps | Where-Object { $_['op'] -eq 'update' }).Count | Should Be 1
    }
    It 'says "No changes since" and only moves the date when nothing changed' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:HandbookSame)
        $r = Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p7' -Options @{ Now = $script:Now }
        $r.status | Should Be 'unchanged'
        $r.message | Should Be 'No changes since 2026-08-01.'
        $c.q.prompts.Count | Should Be 1
        ((Get-Roles $v.st.updates[0]) -join ',') | Should Be 'checked'
        $v.st.updates[0].meta.summarizedAt | Should Be '2026-11-13'
    }
    It 'asks before replacing a hand-edited summary and writes nothing until then' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:HandbookNew)
        $v.st.content['{P7}'].meta.summaryHash = 'deadbeefdeadbeef'
        $r = Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p7' -Options @{ Now = $script:Now }
        $r.status | Should Be 'needs-confirmation'
        $v.st.updates.Count | Should Be 0
        ($r.confirm.options -join ',') | Should Be 'replace,keep'
        $r.confirm.proposed.title | Should Be 'Contoso handbook'
        $r.confirm.editedText | Should Match 'Link:'
        $r.update.diff.changed | Should Be $true
        { $r | ConvertTo-Json -Depth 10 } | Should Not Throw
    }
    It 'replaces after the confirmation without asking for the summary again, keeping the edit in history' {
        $v = New-FakeVault; $c = New-FakeCopilot @($script:HandbookLinks)
        $v.st.content['{P7}'].meta.summaryHash = 'deadbeefdeadbeef'
        $proposed = ConvertFrom-Json $script:HandbookNew
        $r = Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p7' -Decision 'replace' -Proposed $proposed -Options @{ Now = $script:Now }
        $r.status | Should Be 'updated'
        $c.q.prompts.Count | Should Be 1
        $c.q.prompts[0] | Should Match 'type: always "link-internal"'
        $hist = ConvertFrom-Json $v.st.updates[0].meta.history
        $hist[0].edited | Should Be $true
        ((Get-Roles $v.st.updates[0]) -join ',') | Should Be 'summary,checked'
    }
    It 'keeps the edited summary when the person says keep' {
        $v = New-FakeVault; $c = New-FakeCopilot @()
        $v.st.content['{P7}'].meta.summaryHash = 'deadbeefdeadbeef'
        $r = Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p7' -Decision 'keep' -Proposed (ConvertFrom-Json $script:HandbookNew) -Options @{ Now = $script:Now }
        $r.status | Should Be 'kept'
        ((Get-Roles $v.st.updates[0]) -join ',') | Should Be 'checked'
    }
    It 'keeps the old summary when the source is gone' {
        $v = New-FakeVault; $c = New-FakeCopilot @('{"readable": false, "problem": "not-found"}')
        $r = Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p7' -Options @{ Now = $script:Now }
        $r.status | Should Be 'could-not-update'
        $r.message | Should Match 'Could not be updated on 2026-11-13: not found'
        ((Get-Roles $v.st.updates[0]) -join ',') | Should Be 'checked'
        $v.st.updates[0].meta.ContainsKey('linkSummary') | Should Be $false
    }
    It 'refuses a page that is not a link page or not in the index' {
        $v = New-FakeVault; $c = New-FakeCopilot @()
        (Update-LinkSummary -Store $v.store -Ask $c.ask -Id 'p404').message | Should Match 'not in the index'
    }
}
