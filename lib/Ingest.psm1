# Ingest: Add (capture anything into the active vault). FEASIBILITY.md sections 4 and 5.
# Invoke-AddRequest  text or link -> Intake page (01 Intake, status new, with the request reference)
#                    -> Copilot -> validate -> content page in its bucket (properties + obsn Meta +
#                    body with onenote: links) -> "Linked from" on target pages -> index -> Intake item
#                    filed (or failed + reason). When Copilot is still answering at the end of the wait
#                    (the bridge's 'Pending', it is never stopped) the item becomes 'waiting' with the
#                    reference and the chat's address, and nothing else is written.
# Receive-AddAnswer  "Check for the answer": reads that chat, takes ONLY the answer whose "ref" is the
#                    item's reference (and, for a link, whose "source" is the item's link) and runs the
#                    same pipeline from it (Invoke-AddRequest -Resume); anything else writes nothing.
# Undo-AddRequest    removes the created page (to OneNote's Deleted Pages) and reverts backlinks.
# Code names (CreateInboxItem, inbox fields) keep the section's old name "Inbox"; people see "Intake".
# Update-LinkSummary re-reads a link page's source: old vs new, last 3 summaries, never "Your
#                    notes", asks before replacing a hand-edited summary.
# Every read and write goes through the injected $Store adapter (see Get-IngestStoreContract);
# the adapter's write guard keeps writes inside the active vault. Copilot is the injected $Ask
# scriptblock (prompt -> reply text, or the bridge's reply object). Nothing is written to disk
# here; the log gets ids, counts and timings only. Results are JSON-ready ordered hashtables.
# PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Linker.psm1')
Import-Module (Join-Path $PSScriptRoot 'LinkCapture.psm1')
Import-Module (Join-Path $PSScriptRoot 'MarkdownLines.psm1')
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')

$script:StoreContract = @(
    'AssertWritable', 'VaultName', 'GetIndex', 'TypeList', 'BucketForType', 'LinkBucket', 'NormalizeUrl',
    'FindPageByUrl', 'NewId', 'CreateInboxItem', 'SetInboxStatus', 'SetInboxWaiting', 'ReadInboxItem', 'CreatePage', 'ReadPage', 'UpdatePage',
    'SetLinkedFrom', 'DeletePage', 'IndexAddPage', 'IndexUpdatePage', 'IndexRemovePage'
)

function New-RequestRef {
    <# A short reference code for one Copilot request: 'r' + 8 random base36 characters. It holds no
       content; it ties an answer in the chat to the Intake item that asked for it. #>
    $d = '0123456789abcdefghijklmnopqrstuvwxyz'
    $bytes = New-Object byte[] 8
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    'r' + (-join @($bytes | ForEach-Object { $d[[int]$_ % 36] }))
}

function Get-IngestStoreContract { , @($script:StoreContract) }

function Get-MissingStoreFunctions {
    <# The contract names the adapter lacks (empty = complete). #>
    param([Parameter(Mandatory)]$Store)
    , @($script:StoreContract | Where-Object { -not ((Get-LkProp $Store $_ $null) -is [scriptblock]) })
}

function Invoke-Store {
    param([Parameter(Mandatory)]$Store, [Parameter(Mandatory)][string]$Name, [hashtable]$Arguments = @{})
    $f = Get-LkProp $Store $Name $null
    if (-not ($f -is [scriptblock])) { throw "The store adapter has no '$Name'." }
    & $f @Arguments
}

function Get-IngestNow {
    param([hashtable]$Options)
    if ($Options -and $Options.ContainsKey('Now') -and $Options['Now']) { return [datetime]$Options['Now'] }
    Get-Date
}

function Get-IngestOption {
    param([hashtable]$Options, [string]$Name, $Default)
    if ($Options -and $Options.ContainsKey($Name) -and $null -ne $Options[$Name]) { return $Options[$Name] }
    $Default
}

function Invoke-IngestAsk {
    <# Calls Copilot. Returns @{ ok; text; error; ms }. $Ask may return a string or the bridge's
       reply object (Text + Result); a Result other than Success is a failure. Never throws. #>
    param([Parameter(Mandatory)][scriptblock]$Ask, [Parameter(Mandatory)][string]$Prompt)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $r = & $Ask $Prompt } catch {
        return @{ ok = $false; text = ''; error = "Copilot did not answer: $($_.Exception.Message)"; ms = [int]$sw.ElapsedMilliseconds }
    }
    $ms = [int]$sw.ElapsedMilliseconds
    if ($r -is [array]) { $r = ($r | ForEach-Object { [string]$_ }) -join "`n" }
    if ($null -eq $r) { return @{ ok = $false; text = ''; error = 'Copilot gave no answer.'; ms = $ms } }
    if ($r -is [string]) { return @{ ok = $true; text = $r; error = ''; ms = $ms } }
    $res = [string](Get-LkProp $r 'Result' 'Success')
    # Pending: Copilot was still answering when the wait ended and was left running (never stopped).
    if ($res -eq 'Pending') { return @{ ok = $false; pending = $true; chatUrl = [string](Get-LkProp $r 'ChatUrl' ''); text = ''; error = 'Copilot did not answer in time; it is still working on it.'; ms = $ms } }
    if ($res -eq 'Busy') { return @{ ok = $false; text = ''; error = 'Copilot is still answering an earlier item, so nothing was sent. Try again in a minute.'; ms = $ms } }
    if ($res -and $res -ne 'Success') { return @{ ok = $false; text = ''; error = "Copilot gave no answer ($res)."; ms = $ms } }
    if (Get-LkProp $r 'Cancelled' $false) { return @{ ok = $false; text = ''; error = 'The request was cancelled.'; ms = $ms } }
    @{ ok = $true; text = [string](Get-LkProp $r 'Text' ''); error = ''; ms = $ms }
}

function New-AddResult {
    param([string]$Status, [string]$Kind, [string]$Message = '')
    [ordered]@{
        # added | failed | updated | unchanged | kept | needs-confirmation | could-not-update | ask-instead
        # | waiting (Copilot still answering; the item waits in the Intake) | still-waiting | mismatch
        # | invalid | refused (the outcomes of "Check for the answer", Receive-AddAnswer)
        status    = $Status
        kind      = $Kind          # text | link
        message   = $Message
        inboxId   = ''             # the Intake item's page id (waiting and the check's outcomes)
        ref       = ''             # its request reference
        text      = ''
        page      = $null
        chips     = @()
        links     = @()
        backlinks = 0
        related   = @()
        dropped   = @()
        warnings  = @()
        timings   = [ordered]@{ totalMs = 0; inboxMs = 0; copilotMs = 0; writeMs = 0; indexMs = 0 }
        undo      = $null
        inbox     = $null
        update    = $null
        confirm   = $null
    }
}

function Get-InboxTitle {
    param([string]$Text)
    $first = @($Text -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1)
    $t = if ($first.Count) { ($first[0] -replace '\s+', ' ').Trim() } else { 'Item' }
    if ($t.Length -gt 80) { $t = $t.Substring(0, 77).TrimEnd() + '...' }
    $t
}

function Get-UrlHostName {
    param([string]$Url)
    $m = [regex]::Match($Url, '^(?i)https?://(?:[^/?#@]*@)?([^/?#:]+)')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    ''
}

function Add-AnchorLinks {
    <# Turns the first occurrence of each link's anchor in $Lines (line model, children included)
       into a link part to the target page. Links without an anchor or a target link are skipped.
       Returns the new line list. #>
    param([object[]]$Lines = @(), [object[]]$Links = @())
    $todo = New-Object System.Collections.Generic.List[object]
    foreach ($l in @($Links)) { if ($l -and $l['anchor'] -and $l['link']) { $todo.Add($l) } }
    if (-not $todo.Count) { return , @($Lines) }
    $state = @{ todo = $todo }
    , @(foreach ($line in @($Lines)) { Add-AnchorLinksToLine -Line $line -State $state })
}

function Add-AnchorLinksToLine {
    param($Line, $State)
    if ($null -eq $Line) { return }
    $parts = @($Line['parts'])
    foreach ($l in @($State.todo.ToArray())) {
        $p = ($l['anchor'] -replace '\s+', ' ').Trim()
        $pat = '(?<![\p{L}\p{N}])' + ([regex]::Escape($p) -replace '\\ ', '\s+') + '(?![\p{L}\p{N}])'
        $new = @(); $hit = $false
        foreach ($part in $parts) {
            # Never inside a link or inline code; a code line (fenced block) is left alone too.
            if ($hit -or $part['href'] -or $part['code'] -or $Line['code']) { $new += $part; continue }
            $m = [regex]::Match([string]$part['text'], $pat, 'IgnoreCase')
            if (-not $m.Success) { $new += $part; continue }
            $s = [string]$part['text']
            # The pieces keep the part's bold/italic/strike (Markdown), only the text and href change.
            if ($m.Index -gt 0) { $new += (Copy-PartWith $part $s.Substring(0, $m.Index) '') }
            $new += (Copy-PartWith $part $m.Value ([string]$l['link']))
            $rest = $s.Substring($m.Index + $m.Length)
            if ($rest) { $new += (Copy-PartWith $part $rest '') }
            $hit = $true
        }
        $parts = $new
        if ($hit) { [void]$State.todo.Remove($l) }
    }
    $kids = @(foreach ($c in @($Line['children'])) { Add-AnchorLinksToLine -Line $c -State $State })
    # Every other field of the line (list, heading, quote, code, table) is kept as it was.
    $out = @{}
    foreach ($k in @($Line.Keys)) { $out[$k] = $Line[$k] }
    $out['parts'] = $parts; $out['bold'] = [bool]$Line['bold']; $out['collapsed'] = [bool]$Line['collapsed']; $out['children'] = $kids
    $out
}

function Copy-PartWith($Part, [string]$Text, [string]$Href) {
    $p = @{}
    foreach ($k in @($Part.Keys)) { $p[$k] = $Part[$k] }
    $p['text'] = $Text; $p['href'] = $Href
    $p
}

function ConvertTo-BodyLines {
    <# The item's text as outline lines. Markdown (headings, lists, emphasis, links, code, tables;
       lib/MarkdownLines.psm1) becomes real OneNote formatting (user, 2026-11-13); other text stays one
       plain line per text line. Trailing empty lines are dropped. #>
    param([string]$Text)
    if (Test-MarkdownText $Text) { return , @(ConvertFrom-MarkdownText $Text) }
    $raw = @($Text -split '\r?\n')
    $end = $raw.Count - 1
    while ($end -ge 0 -and -not $raw[$end].Trim()) { $end-- }
    if ($end -lt 0) { return , @() }
    , @(foreach ($t in $raw[0..$end]) { New-LinkLine -Text $t.TrimEnd() })
}

function Get-IndexPageMap {
    param($Index)
    $m = @{}
    foreach ($p in @(Get-LkProp $Index 'pages' @())) {
        $id = [string](Get-LkProp $p 'id' '')
        if ($id) { $m[$id] = $p }
    }
    $m
}

function Get-IncomingSources {
    <# The pages that link to $TargetId: index edges plus the links on the page records (the page
       wins), without $ExcludeId, plus $Add. Returns @(@{ id; title; link }) sorted by title. #>
    param($Index, [string]$TargetId, [string]$ExcludeId = '', $Add = $null)
    $pages = Get-IndexPageMap $Index
    $from = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($e in @(Get-LkProp $Index 'edges' @())) {
        if ([string](Get-LkProp $e 'to' '') -eq $TargetId) { [void]$from.Add([string](Get-LkProp $e 'from' '')) }
    }
    foreach ($p in $pages.Values) {
        foreach ($l in @(Get-LkProp $p 'links' @())) {
            $t = [string](Get-LkProp $l 'target' (Get-LkProp $l 't' ''))
            if ($t -eq $TargetId) { [void]$from.Add([string](Get-LkProp $p 'id' '')) }
        }
    }
    $out = @(foreach ($f in $from) {
        if (-not $f -or $f -eq $ExcludeId -or -not $pages.ContainsKey($f)) { continue }
        @{ id = $f; title = [string](Get-LkProp $pages[$f] 'title' ''); link = [string](Get-LkProp $pages[$f] 'link' '') }
    })
    if ($Add -and -not $from.Contains([string]$Add['id'])) { $out += $Add }
    , @($out | Sort-Object { [string]$_['title'] })
}

function Update-Backlinks {
    <# Rewrites the "Linked from" outline of each target. Returns @{ count; warnings }. #>
    param($Store, $Index, [string[]]$Targets = @(), [string]$ExcludeId = '', $Add = $null)
    $count = 0; $warn = @()
    foreach ($t in @($Targets | Where-Object { $_ } | Select-Object -Unique)) {
        $src = Get-IncomingSources -Index $Index -TargetId $t -ExcludeId $ExcludeId -Add $Add
        try { Invoke-Store $Store 'SetLinkedFrom' @{ Id = $t; Sources = $src } | Out-Null; $count++ }
        catch { $warn += "The ""Linked from"" list of page $t could not be updated: $($_.Exception.Message)" }
    }
    @{ count = $count; warnings = $warn }
}

function Get-PageView {
    <# The "Placed in the central index" data of the Add result. #>
    param([hashtable]$Page, [string]$Vault)
    $paths = @($Page['topics'] | Where-Object { $_ })
    $sec = [string]$Page['section']
    if (-not $sec) { $sec = [string]$Page['bucket'] }
    $one = @($Vault) + @($sec.Split('/') | Where-Object { $_ }) + @([string]$Page['title'])
    [ordered]@{
        id          = $Page['id']
        title       = $Page['title']
        type        = $Page['type']
        bucket      = $Page['bucket']
        section     = $sec
        link        = [string]$Page['link']
        url         = [string]$Page['url']
        topicPath   = $(if ($paths.Count) { [string]$paths[0] } else { '' })
        alsoUnder   = @($paths | Select-Object -Skip 1)
        oneNotePath = @($one | Where-Object { $_ })
        unfiled     = ($paths.Count -eq 0)
    }
}

function Get-Chips {
    param([string]$Type, [object[]]$Aliases = @(), [object[]]$Topics = @())
    $c = @(@{ kind = 'type'; label = $Type })
    foreach ($a in @($Aliases | Where-Object { $_ })) { $c += @{ kind = 'alias'; label = [string]$a } }
    foreach ($t in @($Topics | Where-Object { $_ })) {
        $path = [string]$t['path']
        $c += @{ kind = $(if ($t['isNew']) { 'new-topic' } else { 'topic' }); label = @($path.Split('/'))[-1]; path = $path }
    }
    , $c
}

function Get-RelatedPages {
    param($Shortlist, [object[]]$Links = @(), [int]$Count = 3)
    $linked = @($Links | ForEach-Object { [string]$_['target'] })
    , @(@(Get-LkProp $Shortlist 'pages' @()) | Where-Object { $linked -notcontains $_['id'] } | Select-Object -First $Count | ForEach-Object {
        @{ id = $_['id']; title = $_['title']; link = [string](Get-LkProp $_['page'] 'link' '') }
    })
}

function ConvertTo-LinkResult {
    param([object[]]$Links = @())
    , @(foreach ($l in @($Links)) { [ordered]@{ target = $l['target']; title = $l['title']; link = $l['link']; anchor = $l['anchor']; strength = $l['strength']; why = $l['why'] } })
}

function Set-InboxFailed {
    <# Marks the Intake item failed. Not for an answer checked later (-Resume): a check that does not
       fit writes nothing, so the item keeps waiting. #>
    param($Store, $Inbox, [string]$Reason, $Result)
    if (-not $Inbox -or $Inbox['resumed']) { return }
    try { Invoke-Store $Store 'SetInboxStatus' @{ PageId = $Inbox['pageId']; Status = 'failed'; Reason = $Reason; Id = '' } | Out-Null; $Result.inbox = @{ pageId = $Inbox['pageId']; status = 'failed' } }
    catch { $Result.warnings = @($Result.warnings) + "The Intake item could not be marked as failed: $($_.Exception.Message)" }
}

function Set-InboxWaiting {
    <# Copilot was still answering at the end of the wait: the Intake item becomes 'waiting' with the
       request reference, the kind of step and the chat's address; nothing else is written. #>
    param($Store, $Inbox, [string]$Ref, [string]$RequestKind, $Answer, $Result, [datetime]$Now)
    $r = $Result
    $since = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    try { Invoke-Store $Store 'SetInboxWaiting' @{ PageId = $Inbox['pageId']; Ref = $Ref; RequestKind = $RequestKind; ChatUrl = [string]$Answer['chatUrl']; Since = $since } | Out-Null }
    catch {
        $r.message = "Copilot did not answer in time, and the Intake item could not be marked as waiting: $($_.Exception.Message)"
        Set-InboxFailed $Store $Inbox $r.message $r
        return $r
    }
    $r.status = 'waiting'
    $r.message = 'Copilot is still working on this and did not answer in time. The item waits in your Intake; check for the answer in a few minutes.'
    $r.inbox = @{ pageId = $Inbox['pageId']; status = 'waiting' }
    $r.inboxId = [string]$Inbox['pageId']
    $r.ref = $Ref
    $r
}

function Get-StepAnswer {
    <# The answer to a pipeline step: the reply handed in by "Check for the answer" (-Resume, Copilot
       is not asked again for that step), else Copilot's live answer. #>
    param([scriptblock]$Ask, [string]$Prompt, $Resume)
    if ($Resume) { return @{ ok = $true; pending = $false; text = [string]$Resume['reply']; error = ''; ms = 0 } }
    Invoke-IngestAsk -Ask $Ask -Prompt $Prompt
}

function Get-StepInbox {
    <# The Intake item of this Add: the waiting one (-Resume), or a new one with the request reference.
       Returns the item record, or a string with the reason it could not be written. #>
    param($Store, $Resume, [string]$Title, [string]$Text, [string]$Kind, [string]$Ref, [string]$RequestKind)
    if ($Resume) { return @{ pageId = [string]$Resume['inboxPageId']; resumed = $true } }
    try { Invoke-Store $Store 'CreateInboxItem' @{ Title = $Title; Text = $Text; Kind = $Kind; Ref = $Ref; RequestKind = $RequestKind } }
    catch { "Could not write to the Intake: $($_.Exception.Message)" }
}

function Complete-AddResult {
    param($Result, $Sw)
    $Result.timings.totalMs = [int]$Sw.ElapsedMilliseconds
    $id = if ($Result.page) { [string]$Result.page['id'] } else { '' }
    Write-AppLog info ingest 'Add finished' @{ status = $Result.status; kind = $Result.kind; id = $id; links = @($Result.links).Count; backlinks = $Result.backlinks; dropped = @($Result.dropped).Count; ms = $Result.timings.totalMs; copilotMs = $Result.timings.copilotMs }
    $Result
}

function Invoke-AddRequest {
    <# The Add handler behind POST /api/submit (mode add, or auto when the intent rules say add).
       $Request: @{ text; mode } (mode 'add' or 'auto'). $Store: the adapter (Get-IngestStoreContract).
       $Ask: { param($Prompt) ... } returning Copilot's reply. $Options: Now, MaxPromptChars,
       MaxPages, RelatedCount. -Resume @{ inboxPageId; ref; reply }: continue the Add of a waiting
       Intake item from the answer Receive-AddAnswer found (that step is not asked again; the reply
       must carry the item's ref, and for a link its source; a failure writes nothing).
       Returns the Add result (New-AddResult fields). Never throws. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)]$Store, [Parameter(Mandatory)][scriptblock]$Ask, [hashtable]$Options = @{}, [hashtable]$Resume = $null)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $text = [string](Get-LkProp $Request 'text' '')
    $mode = (Get-LkString $Request 'mode').ToLowerInvariant()
    if (-not $mode -or $Resume) { $mode = 'add' }
    $url = Get-PastedUrl $text
    $r = New-AddResult -Status 'failed' -Kind $(if ($url) { 'link' } else { 'text' })
    if (-not $text.Trim()) { $r.message = 'There is nothing to add.'; return (Complete-AddResult $r $sw) }
    $missing = Get-MissingStoreFunctions $Store
    if ($missing.Count) { $r.message = "The notebook connection is incomplete ($($missing -join ', '))."; return (Complete-AddResult $r $sw) }
    try { Invoke-Store $Store 'AssertWritable' | Out-Null } catch {
        $r.message = "Nothing was added: $($_.Exception.Message)"
        return (Complete-AddResult $r $sw)
    }
    try {
        if ($url) { $r = Invoke-LinkAdd -Url $url -Store $Store -Ask $Ask -Options $Options -Result $r -Resume $Resume }
        else { $r = Invoke-TextAdd -Text $text -Mode $mode -Store $Store -Ask $Ask -Options $Options -Result $r -Resume $Resume }
    } catch {
        $r.status = 'failed'
        $r.message = "Adding stopped: $($_.Exception.Message)"
    }
    Complete-AddResult $r $sw
}

function Invoke-TextAdd {
    param([string]$Text, [string]$Mode, $Store, [scriptblock]$Ask, [hashtable]$Options, $Result, $Resume = $null)
    $r = $Result
    $r.text = $Text
    $now = Get-IngestNow $Options
    $idx = Invoke-Store $Store 'GetIndex'
    $types = @(Invoke-Store $Store 'TypeList')
    $ref = if ($Resume) { [string]$Resume['ref'] } else { New-RequestRef }

    $t0 = [Diagnostics.Stopwatch]::StartNew()
    $inbox = Get-StepInbox -Store $Store -Resume $Resume -Title (Get-InboxTitle $Text) -Text $Text -Kind 'text' -Ref $ref -RequestKind 'classify'
    if ($inbox -is [string]) { $r.message = $inbox; return $r }
    $r.inbox = @{ pageId = $inbox['pageId']; status = $(if ($Resume) { 'waiting' } else { 'new' }) }
    $r.timings.inboxMs = [int]$t0.ElapsedMilliseconds

    $sl = Get-LinkShortlist -Index $idx -Text $Text -MaxChars (Get-IngestOption $Options 'MaxPromptChars' 12000) -MaxPages (Get-IngestOption $Options 'MaxPages' 60)
    $prompt = New-LinkPrompt -Text $Text -Shortlist $sl -Types $types -Today $now -Ref $ref
    $ans = Get-StepAnswer -Ask $Ask -Prompt $prompt -Resume $Resume
    $r.timings.copilotMs += $ans.ms
    if ($ans['pending']) { return (Set-InboxWaiting $Store $inbox $ref 'classify' $ans $r $now) }
    if (-not $ans.ok) { $r.message = $ans.error; Set-InboxFailed $Store $inbox $ans.error $r; return $r }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { $r.message = $json.error; Set-InboxFailed $Store $inbox $json.error $r; return $r }
    $rc = Test-ReplyRef -Reply $json.value -Ref $ref -Required:([bool]$Resume)
    if (-not $rc.ok) { $r.message = $rc.error; if ($Resume) { $r.status = 'mismatch' }; Set-InboxFailed $Store $inbox $rc.error $r; return $r }
    $v = Test-LinkReply -Reply $json.value -Index $idx -Shortlist $sl -Text $Text -Types $types
    $r.dropped = @($v.dropped)
    if (-not $v.ok) {
        $r.message = ($v.errors -join ' ')
        if ($v.duplicateOf) { $r.related = @(@{ id = $v.duplicateOf; title = [string](Get-LkProp (Get-IndexPageMap $idx)[$v.duplicateOf] 'title' ''); link = [string](Get-LkProp (Get-IndexPageMap $idx)[$v.duplicateOf] 'link' '') }) }
        Set-InboxFailed $Store $inbox $r.message $r
        return $r
    }
    $val = $v.value
    if ($val.intent -eq 'ask' -and $Mode -eq 'auto') {
        try { Invoke-Store $Store 'DeletePage' @{ PageId = $inbox['pageId'] } | Out-Null; $r.inbox = @{ pageId = $inbox['pageId']; status = 'removed' } } catch { Set-InboxFailed $Store $inbox 'Looks like a question' $r }
        $r.status = 'ask-instead'
        $r.message = 'This looks like a question. Ask it instead?'
        return $r
    }

    $t1 = [Diagnostics.Stopwatch]::StartNew()
    $id = [string](Invoke-Store $Store 'NewId')
    $bucket = [string](Invoke-Store $Store 'BucketForType' @{ Type = $val.type })
    $body = Add-AnchorLinks -Lines (ConvertTo-BodyLines $Text) -Links $val.links
    $page = @{
        id = $id; type = $val.type; bucket = $bucket; title = $val.title; summary = $val.summary
        topics = @($val.topics | ForEach-Object { $_['path'] }); aliases = @($val.aliases)
        links = @($val.links | ForEach-Object { @{ target = $_['target']; strength = $_['strength']; why = $_['why'] } })
        status = ''
        outlines = @(@{ role = 'body'; lines = $body })
    }
    try { $cp = Invoke-Store $Store 'CreatePage' @{ Page = $page } }
    catch { $r.message = "Could not write the page: $($_.Exception.Message)"; Set-InboxFailed $Store $inbox $r.message $r; return $r }
    $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']

    $targets = @($val.links | ForEach-Object { [string]$_['target'] })
    $bl = Update-Backlinks -Store $Store -Index $idx -Targets $targets -ExcludeId $id -Add @{ id = $id; title = $page.title; link = $page.link }
    $r.backlinks = $bl.count
    $r.warnings = @($r.warnings) + @($bl.warnings)
    $r.timings.writeMs = [int]$t1.ElapsedMilliseconds

    $t2 = [Diagnostics.Stopwatch]::StartNew()
    try { Invoke-Store $Store 'IndexAddPage' @{ Page = $page } | Out-Null }
    catch { $r.warnings = @($r.warnings) + "The index was not updated; the next start adds the page to Unfiled ($($_.Exception.Message))." }
    $r.timings.indexMs = [int]$t2.ElapsedMilliseconds

    try { Invoke-Store $Store 'SetInboxStatus' @{ PageId = $inbox['pageId']; Status = 'linked'; Reason = ''; Id = $id } | Out-Null; $r.inbox = @{ pageId = $inbox['pageId']; status = 'linked' } }
    catch { $r.warnings = @($r.warnings) + "The Intake item was not marked as filed: $($_.Exception.Message)" }

    $r.status = 'added'
    $r.message = "Added: $($page.title)"
    $r.page = Get-PageView -Page $page -Vault ([string](Invoke-Store $Store 'VaultName'))
    $r.chips = Get-Chips -Type $val.type -Aliases $val.aliases -Topics $val.topics
    $r.links = ConvertTo-LinkResult $val.links
    $r.related = Get-RelatedPages -Shortlist $sl -Links $val.links -Count (Get-IngestOption $Options 'RelatedCount' 3)
    $r.undo = @{ id = $id; pageId = $page.pageId; targets = $targets }
    $r
}

function Invoke-Relink {
    <# Linking for a link page's summary text (the second Copilot call). Returns @{ ok; error; v; sl; ms }. #>
    param($Index, [string]$Text, [string]$Type, [string]$SelfId, $Store, [scriptblock]$Ask, [hashtable]$Options, [datetime]$Now)
    $types = @(Invoke-Store $Store 'TypeList')
    $ex = if ($SelfId) { @($SelfId) } else { @() }
    $sl = Get-LinkShortlist -Index $Index -Text $Text -MaxChars (Get-IngestOption $Options 'MaxPromptChars' 12000) -MaxPages (Get-IngestOption $Options 'MaxPages' 60) -ExcludeIds $ex
    $ref = New-RequestRef
    $prompt = New-LinkPrompt -Text $Text -Shortlist $sl -Types $types -FixedType $Type -Today $Now -Ref $ref
    $ans = Invoke-IngestAsk -Ask $Ask -Prompt $prompt
    if (-not $ans.ok) { return @{ ok = $false; error = $ans.error; v = $null; sl = $sl; ms = $ans.ms } }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { return @{ ok = $false; error = $json.error; v = $null; sl = $sl; ms = $ans.ms } }
    $rc = Test-ReplyRef -Reply $json.value -Ref $ref
    if (-not $rc.ok) { return @{ ok = $false; error = $rc.error; v = $null; sl = $sl; ms = $ans.ms } }
    $v = Test-LinkReply -Reply $json.value -Index $Index -Shortlist $sl -Text $Text -Types $types -FixedType $Type -SelfId $SelfId -SkipDuplicateTitle
    if (-not $v.ok) { return @{ ok = $false; error = ($v.errors -join ' '); v = $v; sl = $sl; ms = $ans.ms } }
    @{ ok = $true; error = ''; v = $v; sl = $sl; ms = $ans.ms }
}

function Invoke-LinkAdd {
    param([string]$Url, $Store, [scriptblock]$Ask, [hashtable]$Options, $Result, $Resume = $null)
    $r = $Result
    $r.text = $Url
    $now = Get-IngestNow $Options
    $today = $now.ToString('yyyy-MM-dd')
    $norm = [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $Url })
    $existing = Invoke-Store $Store 'FindPageByUrl' @{ Url = $norm }
    if ($existing -and $Resume) {
        $r.message = "A page for this link exists already ($([string](Get-LkProp $existing 'id' ''))); use Update on it."
        return $r
    }
    if ($existing) {
        # One page per link: pasting it again updates that page.
        return (Update-LinkSummary -Store $Store -Ask $Ask -Id ([string](Get-LkProp $existing 'id' '')) -SeenAgain -Options $Options)
    }
    $bucket = [string](Invoke-Store $Store 'LinkBucket' @{ Url = $norm })
    $type = if ($bucket -eq 'Internal links') { 'link-internal' } else { 'link-web' }
    $idx = Invoke-Store $Store 'GetIndex'
    $ref = if ($Resume) { [string]$Resume['ref'] } else { New-RequestRef }

    $t0 = [Diagnostics.Stopwatch]::StartNew()
    $inbox = Get-StepInbox -Store $Store -Resume $Resume -Title (Get-InboxTitle $norm) -Text $Url -Kind 'link' -Ref $ref -RequestKind 'linkSummary'
    if ($inbox -is [string]) { $r.message = $inbox; return $r }
    $r.inbox = @{ pageId = $inbox['pageId']; status = $(if ($Resume) { 'waiting' } else { 'new' }) }
    $r.timings.inboxMs = [int]$t0.ElapsedMilliseconds

    $ans = Get-StepAnswer -Ask $Ask -Prompt (New-LinkSummaryPrompt -Url $norm -Bucket $bucket -Today $now -Ref $ref) -Resume $Resume
    $r.timings.copilotMs += $ans.ms
    if ($ans['pending']) { return (Set-InboxWaiting $Store $inbox $ref 'linkSummary' $ans $r $now) }
    if (-not $ans.ok) { $r.message = $ans.error; Set-InboxFailed $Store $inbox $ans.error $r; return $r }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { $r.message = $json.error; Set-InboxFailed $Store $inbox $json.error $r; return $r }
    $rc = Test-ReplyRef -Reply $json.value -Ref $ref -Required:([bool]$Resume)
    if ($rc.ok -and $Resume) {
        # An answer read from the chat later must be about this item's link.
        $src = Get-LkString $json.value 'source'
        $srcNorm = if ($src) { [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $src }) } else { '' }
        if ($srcNorm -ne $norm) { $rc = @{ ok = $false; error = "The answer is about another link than this item's link." } }
    }
    if (-not $rc.ok) { $r.message = $rc.error; if ($Resume) { $r.status = 'mismatch' }; Set-InboxFailed $Store $inbox $rc.error $r; return $r }
    $sum = ConvertTo-LinkSummary -Reply $json.value -Bucket $bucket
    if (-not $sum.ok) { $r.message = $sum.error; Set-InboxFailed $Store $inbox $sum.error $r; return $r }

    $val = @{ title = ''; summary = ''; topics = @(); links = @(); aliases = @() }
    $sl = $null
    $checkStatus = ''
    if ($sum.readable) {
        $s = $sum.summary
        $rl = Invoke-Relink -Index $idx -Text (Get-LinkSummaryText $s) -Type $type -SelfId '' -Store $Store -Ask $Ask -Options $Options -Now $now
        $r.timings.copilotMs += $rl.ms
        $sl = $rl.sl
        if ($rl.ok) { $val = $rl.v.value; $r.dropped = @($rl.v.dropped) }
        else { $r.warnings = @($r.warnings) + "The link was summarized but not linked; it stays Unfiled until it is checked again ($($rl.error))." }
        $title = $s.title
        $oneLine = if ($val.summary) { $val.summary } else { Limit-Sentence $s.summary }
    } else {
        $s = $null
        $title = Get-InboxTitle $norm
        $oneLine = ''
        $checkStatus = 'Could not be read on {0}: {1}.' -f $today, $(if ($sum.problem -eq 'no-access') { 'no access' } elseif ($sum.problem -eq 'not-found') { 'not found' } else { 'the source could not be read' })
        $r.warnings = @($r.warnings) + $checkStatus
    }

    $t1 = [Diagnostics.Stopwatch]::StartNew()
    $id = [string](Invoke-Store $Store 'NewId')
    $sumLines = Add-AnchorLinks -Lines (New-LinkSummaryLines -Url $norm -Summary $s -Problem $sum.problem -Today $now) -Links $val.links
    $page = @{
        id = $id; type = $type; bucket = $bucket; title = $title; summary = $oneLine
        topics = @($val.topics | ForEach-Object { $_['path'] }); aliases = @($val.aliases)
        links = @($val.links | ForEach-Object { @{ target = $_['target']; strength = $_['strength']; why = $_['why'] } })
        status = ''; url = $norm; host = (Get-UrlHostName $norm)
        kind = $(if ($s) { $s.kind } else { '' })
        summarizedAt = $(if ($s) { $today } else { '' })
        linkSummary = $(if ($s) { ConvertTo-LkJson $s } else { '' })
        summaryHash = (Get-SummaryHash (Get-LinesPlainText $sumLines))
        history = '[]'; seenAt = ''; checkStatus = $checkStatus
        outlines = @(
            @{ role = 'summary'; lines = $sumLines },
            @{ role = 'checked'; lines = (New-LinkCheckedLines -SummarizedAt $(if ($s) { $today } else { '' }) -CheckStatus $checkStatus) },
            @{ role = 'notes'; lines = (New-LinkNotesLines) }
        )
    }
    try { $cp = Invoke-Store $Store 'CreatePage' @{ Page = $page } }
    catch { $r.message = "Could not write the page: $($_.Exception.Message)"; Set-InboxFailed $Store $inbox $r.message $r; return $r }
    $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']

    $targets = @($val.links | ForEach-Object { [string]$_['target'] })
    $bl = Update-Backlinks -Store $Store -Index $idx -Targets $targets -ExcludeId $id -Add @{ id = $id; title = $page.title; link = $page.link }
    $r.backlinks = $bl.count
    $r.warnings = @($r.warnings) + @($bl.warnings)
    $r.timings.writeMs = [int]$t1.ElapsedMilliseconds

    $t2 = [Diagnostics.Stopwatch]::StartNew()
    try { Invoke-Store $Store 'IndexAddPage' @{ Page = $page } | Out-Null }
    catch { $r.warnings = @($r.warnings) + "The index was not updated; the next start adds the page to Unfiled ($($_.Exception.Message))." }
    $r.timings.indexMs = [int]$t2.ElapsedMilliseconds

    try { Invoke-Store $Store 'SetInboxStatus' @{ PageId = $inbox['pageId']; Status = 'linked'; Reason = ''; Id = $id } | Out-Null; $r.inbox = @{ pageId = $inbox['pageId']; status = 'linked' } }
    catch { $r.warnings = @($r.warnings) + "The Intake item was not marked as filed: $($_.Exception.Message)" }

    $r.status = 'added'
    $r.message = "Added: $title"
    $r.page = Get-PageView -Page $page -Vault ([string](Invoke-Store $Store 'VaultName'))
    $r.chips = Get-Chips -Type $type -Aliases $val.aliases -Topics $val.topics
    $r.links = ConvertTo-LinkResult $val.links
    if ($sl) { $r.related = Get-RelatedPages -Shortlist $sl -Links $val.links -Count (Get-IngestOption $Options 'RelatedCount' 3) }
    $r.update = [ordered]@{ old = $null; new = $s; diff = $null; oldAt = ''; newAt = $page.summarizedAt; review = @() }
    $r.undo = @{ id = $id; pageId = $page.pageId; targets = $targets }
    $r
}

function Limit-Sentence {
    param([string]$Text, [int]$Max = 200)
    $t = ($Text -replace '\s+', ' ').Trim()
    $m = [regex]::Match($t, '^.+?[.!?](?=\s|$)')
    if ($m.Success) { $t = $m.Value }
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 3).TrimEnd() + '...' }
    $t
}

function Get-ChatAnswerFor {
    <# What a read of the Copilot chat holds for request $Ref (pure): @{ status; message; reply }.
       status 'found' with the reply text (the LAST answer whose "ref" is $Ref; answers without it or
       with another reference are never used), else 'still-waiting' or 'mismatch' with the reason.
       $Read: the chat reader's record @{ state = read|busy|unavailable; text; busy; message }. #>
    param($Read, [string]$Ref)
    $state = Get-LkString $Read 'state'
    if ($state -eq 'busy') { return @{ status = 'still-waiting'; message = 'Copilot is busy with another answer right now. Try again in a minute.'; reply = '' } }
    if ($state -ne 'read') {
        $why = Get-LkString $Read 'message'
        return @{ status = 'still-waiting'; message = "The Copilot chat could not be read$(if ($why) { " ($why)" }). Try again later."; reply = '' }
    }
    # Returned as one list (", array"): assigned as is, not wrapped in @() (that nests it).
    $objs = Get-ReplyJsonObjects (Get-LkString $Read 'text')
    $hits = @($objs | Where-Object { (Get-LkString $_ 'ref').Trim() -eq $Ref })
    if ($hits.Count) { return @{ status = 'found'; message = ''; reply = (ConvertTo-Json -InputObject $hits[-1] -Depth 12 -Compress) } }
    if ([bool](Get-LkProp $Read 'busy' $false) -or -not $objs.Count) {
        return @{ status = 'still-waiting'; message = 'Copilot has not answered this item yet. Try again in a few minutes.'; reply = '' }
    }
    @{ status = 'mismatch'; message = "No answer in that chat carries this item's reference ($Ref), so none is used."; reply = '' }
}

function Receive-AddAnswer {
    <# "Check for the answer" (POST /api/add/fetch {inboxId}) for an Intake item that is waiting for
       Copilot. Needs the writer lease and an item of the active vault's Intake with status waiting.
       $ReadChat { param($ChatUrl) } reads that Copilot chat (all replies on the page, the chat opened
       in ObsidiNote's Copilot tab only when it is not already showing) and returns @{ state; text;
       busy; message }. Only the answer that carries the item's ref is used (Get-ChatAnswerFor); it is
       checked exactly like a live answer and the Add continues from it (Invoke-AddRequest -Resume;
       a new link's linking prompt is still sent live). Outcomes: the normal Add result, or status
       still-waiting | mismatch | invalid (nothing written; the item keeps waiting) | refused. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Store, [Parameter(Mandatory)][scriptblock]$Ask, [Parameter(Mandatory)][scriptblock]$ReadChat, [Parameter(Mandatory)][string]$InboxId, [hashtable]$Options = @{})
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = New-AddResult -Status 'refused' -Kind 'text'
    $r.inboxId = $InboxId
    $missing = Get-MissingStoreFunctions $Store
    if ($missing.Count) { $r.message = "The notebook connection is incomplete ($($missing -join ', '))."; return (Complete-AddResult $r $sw) }
    try { Invoke-Store $Store 'AssertWritable' | Out-Null } catch { $r.message = "Nothing was checked: $($_.Exception.Message)"; return (Complete-AddResult $r $sw) }
    try { $item = Invoke-Store $Store 'ReadInboxItem' @{ PageId = $InboxId } }
    catch { $r.message = "That item is not in the Intake of this vault ($($_.Exception.Message))."; return (Complete-AddResult $r $sw) }
    $r.kind = if ((Get-LkString $item 'kind') -eq 'link') { 'link' } else { 'text' }
    $r.text = Get-LkString $item 'text'
    $r.ref = Get-LkString $item 'ref'
    $status = Get-LkString $item 'status'
    $r.inbox = @{ pageId = $InboxId; status = $status }
    if ($status -ne 'waiting') { $r.message = "This item is not waiting for Copilot (its status is $(if ($status) { $status } else { 'unknown' }))."; return (Complete-AddResult $r $sw) }
    if (-not $r.ref) { $r.message = 'This item has no request reference, so no answer can be matched to it. Add it again.'; return (Complete-AddResult $r $sw) }
    try { $read = & $ReadChat (Get-LkString $item 'chatUrl') } catch { $read = @{ state = 'unavailable'; message = $_.Exception.Message } }
    $found = Get-ChatAnswerFor -Read $read -Ref $r.ref
    Write-AppLog info ingest 'Answer check' @{ found = $found.status; state = (Get-LkString $read 'state'); ms = [int]$sw.ElapsedMilliseconds }
    if ($found.status -ne 'found') {
        $r.status = $found.status
        $r.message = $found.message + $(if ($found.status -eq 'mismatch') { ' Nothing was written; the item still waits in your Intake.' } else { '' })
        return (Complete-AddResult $r $sw)
    }
    if ((Get-LkString $item 'requestKind') -in 'linkUpdate', 'linkSeen') {
        $add = Receive-UpdateAnswer -Store $Store -Ask $Ask -Item $item -InboxId $InboxId -Ref $r.ref -Reply $found.reply -Options $Options -Result $r
    } else {
        $add = Invoke-AddRequest -Request @{ text = $r.text; mode = 'add' } -Store $Store -Ask $Ask -Options $Options -Resume @{ inboxPageId = $InboxId; ref = $r.ref; reply = $found.reply }
    }
    if ($add.status -eq 'failed') { $add.status = 'invalid' }
    if ($add.status -in 'invalid', 'mismatch') { $add.message = "$($add.message) Nothing was written; the item still waits in your Intake." }
    $add.inboxId = $InboxId
    $add.ref = $r.ref
    $add
}

function Undo-AddRequest {
    <# Undo of an Add: the created page goes to OneNote's Deleted Pages (never a permanent delete),
       leaves the index, and the "Linked from" lists of its targets are rewritten without it.
       $Undo: the result's undo record @{ id; pageId; targets }. Returns a JSON-ready result. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Store, [Parameter(Mandatory)]$Undo)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $id = Get-LkString $Undo 'id'
    $pageId = Get-LkString $Undo 'pageId'
    $targets = @(@(Get-LkProp $Undo 'targets' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $r = [ordered]@{ status = 'failed'; message = ''; id = $id; backlinks = 0; warnings = @(); ms = 0 }
    try {
        Invoke-Store $Store 'AssertWritable' | Out-Null
        $idx = Invoke-Store $Store 'GetIndex'
        $rec = (Get-IndexPageMap $idx)[$id]
        if (-not $rec) { throw "page $id is not in the index" }
        $recPage = Get-LkString $rec 'pageId'
        if (-not $pageId) { $pageId = $recPage }
        if ($recPage -and $recPage -ne $pageId) { throw "page $id does not match the page that was added" }
        Invoke-Store $Store 'DeletePage' @{ PageId = $pageId } | Out-Null
        try { Invoke-Store $Store 'IndexRemovePage' @{ Id = $id } | Out-Null }
        catch { $r.warnings = @($r.warnings) + "The index still lists the page; the next start removes it ($($_.Exception.Message))." }
        $bl = Update-Backlinks -Store $Store -Index $idx -Targets $targets -ExcludeId $id
        $r.backlinks = $bl.count
        $r.warnings = @($r.warnings) + @($bl.warnings)
        $r.status = 'undone'
        $r.message = "Undone. The page is in OneNote's Deleted Pages for 60 days."
    } catch {
        $r.message = "Undo did not work: $($_.Exception.Message)"
    }
    $r.ms = [int]$sw.ElapsedMilliseconds
    Write-AppLog info ingest 'Undo finished' @{ status = $r.status; id = $id; backlinks = $r.backlinks; ms = $r.ms }
    $r
}

function Get-OutlineText {
    param($Page, [string]$Role)
    foreach ($o in @(Get-LkProp $Page 'outlines' @())) {
        if ([string](Get-LkProp $o 'role' '') -eq $Role) { return [string](Get-LkProp $o 'text' '') }
    }
    ''
}

function Update-LinkSummary {
    <# Update of a link page (button, or the same link pasted again with -SeenAgain).
       Copilot reads the source again; nothing changed -> only the date ('unchanged'); source gone
       -> the old summary stays, marked could not be updated ('could-not-update'); the summary
       outline edited by hand and no -Decision -> 'needs-confirmation' with the proposed summary
       (pass it back as -Proposed with -Decision replace|keep; Copilot is not asked again).
       On replace the previous summary goes to Earlier summaries (last 3), linking runs again on
       the new text (new links added, links it no longer proposes listed for review, never
       removed) and "Your notes" is never written. Returns an Add result (kind 'link'). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][scriptblock]$Ask,
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('', 'replace', 'keep')][string]$Decision = '',
        $Proposed = $null,
        [switch]$SeenAgain,
        [hashtable]$Options = @{},
        # @{ ref; reply }: the answer "Check for the answer" found for a waiting update (not asked again).
        [hashtable]$Resume = $null
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = New-AddResult -Status 'failed' -Kind 'link'
    try { Invoke-Store $Store 'AssertWritable' | Out-Null } catch { $r.message = "Nothing was updated: $($_.Exception.Message)"; return (Complete-AddResult $r $sw) }
    try { $r = Invoke-LinkUpdate -Store $Store -Ask $Ask -Id $Id -Decision $Decision -Proposed $Proposed -SeenAgain:$SeenAgain -Options $Options -Result $r -Resume $Resume }
    catch { $r.status = 'failed'; $r.message = "The update stopped: $($_.Exception.Message)" }
    Complete-AddResult $r $sw
}

function Set-UpdateWaiting {
    <# A link update whose answer did not come in time (Copilot left running): an Intake item
       "Update: <title>" with the link, the request reference and requestKind linkUpdate (button) or
       linkSeen (the link pasted again) becomes 'waiting', so "Check for the answer" can finish the
       update later. The page itself is not touched. #>
    param($Store, $Result, [string]$Url, [string]$Title, [string]$Ref, [switch]$SeenAgain, $Answer, [datetime]$Now)
    $kind = if ($SeenAgain) { 'linkSeen' } else { 'linkUpdate' }
    $t = Get-InboxTitle ('Update: ' + $(if ($Title) { $Title } else { $Url }))
    $inbox = Get-StepInbox -Store $Store -Resume $null -Title $t -Text $Url -Kind 'link' -Ref $Ref -RequestKind $kind
    if ($inbox -is [string]) { $Result.message = "Copilot did not answer in time. $inbox"; return $Result }
    Set-InboxWaiting $Store $inbox $Ref $kind $Answer $Result $Now
}

function Receive-UpdateAnswer {
    <# "Check for the answer" for a waiting link update (requestKind linkUpdate|linkSeen): the update
       runs again from the answer found in the chat (Update-LinkSummary -Resume); when it is used, the
       Intake item is marked filed with the page's id. #>
    param($Store, [scriptblock]$Ask, $Item, [string]$InboxId, [string]$Ref, [string]$Reply, [hashtable]$Options, $Result)
    $r = $Result
    $norm = [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $r.text })
    $existing = Invoke-Store $Store 'FindPageByUrl' @{ Url = $norm }
    $id = [string](Get-LkProp $existing 'id' '')
    if (-not $id) { $r.status = 'invalid'; $r.message = 'The page for this link is no longer in the index, so the answer is not used. Nothing was written; the item still waits in your Intake.'; return $r }
    $up = Update-LinkSummary -Store $Store -Ask $Ask -Id $id -SeenAgain:((Get-LkString $Item 'requestKind') -eq 'linkSeen') -Options $Options -Resume @{ ref = $Ref; reply = $Reply }
    if ($up.status -in 'updated', 'unchanged', 'kept', 'could-not-update', 'needs-confirmation') {
        try { Invoke-Store $Store 'SetInboxStatus' @{ PageId = $InboxId; Status = 'linked'; Reason = ''; Id = $id } | Out-Null; $up.inbox = @{ pageId = $InboxId; status = 'linked' } }
        catch { $up.warnings = @($up.warnings) + "The Intake item was not marked as filed: $($_.Exception.Message)" }
    }
    $up
}

function Invoke-LinkUpdate {
    param($Store, [scriptblock]$Ask, [string]$Id, [string]$Decision, $Proposed, [switch]$SeenAgain, [hashtable]$Options, $Result, $Resume = $null)
    $r = $Result
    $now = Get-IngestNow $Options
    $today = $now.ToString('yyyy-MM-dd')
    $idx = Invoke-Store $Store 'GetIndex'
    $rec = (Get-IndexPageMap $idx)[$Id]
    if (-not $rec) { $r.message = "Page $Id is not in the index."; return $r }
    $pageId = Get-LkString $rec 'pageId'
    $pg = Invoke-Store $Store 'ReadPage' @{ PageId = $pageId }
    $meta = Get-LkProp $pg 'meta' @{}
    $url = Get-LkString $meta 'url'
    if (-not $url) { $url = Get-LkString $rec 'url' }
    if (-not $url) { $r.message = "Page $Id is not a link page."; return $r }
    $type = Get-LkString $meta 'type'
    if (-not $type) { $type = Get-LkString $rec 'type' }
    $bucket = [string](Invoke-Store $Store 'LinkBucket' @{ Url = $url })
    $old = ConvertTo-SummaryRecord (ConvertFrom-LkJson (Get-LkString $meta 'linkSummary'))
    $oldAt = Get-LkString $meta 'summarizedAt'
    $history = @(ConvertFrom-LkJson (Get-LkString $meta 'history') @())
    $seenAt = if ($SeenAgain) { $today } else { Get-LkString $meta 'seenAt' }
    $outlineText = Get-OutlineText $pg 'summary'
    $edited = Test-SummaryEdited -OutlineText $outlineText -StoredHash (Get-LkString $meta 'summaryHash')
    $view = @{ id = $Id; type = $type; bucket = (Get-LkString $rec 'section'); section = (Get-LkString $rec 'section'); title = (Get-LkString $rec 'title'); link = (Get-LkString $rec 'link'); url = $url; topics = @(Get-LkProp $rec 'topics' @()) }
    $vault = [string](Invoke-Store $Store 'VaultName')
    $r.text = $url
    $r.page = Get-PageView -Page $view -Vault $vault
    $r.update = [ordered]@{ old = $old; new = $null; diff = $null; oldAt = $oldAt; newAt = ''; review = @() }

    if ($null -ne $Proposed) {
        $new = ConvertTo-SummaryRecord $Proposed
        if (-not $new -or -not $new.title -or -not $new.summary) { $r.message = 'The proposed summary is incomplete.'; return $r }
    } else {
        $ref = if ($Resume) { [string]$Resume['ref'] } else { New-RequestRef }
        $ans = Get-StepAnswer -Ask $Ask -Prompt (New-LinkSummaryPrompt -Url $url -Bucket $bucket -Today $now -Ref $ref) -Resume $Resume
        $r.timings.copilotMs += $ans.ms
        if ($ans['pending']) { return (Set-UpdateWaiting -Store $Store -Result $r -Url $url -Title $view.title -Ref $ref -SeenAgain:$SeenAgain -Answer $ans -Now $now) }
        if (-not $ans.ok) { $r.message = $ans.error; return $r }
        $json = Get-ReplyJson $ans.text
        if (-not $json.ok) { $r.message = $json.error; return $r }
        $rc = Test-ReplyRef -Reply $json.value -Ref $ref -Required:([bool]$Resume)
        if ($rc.ok -and $Resume) {
            # An answer read from the chat later must be about this page's link.
            $src = Get-LkString $json.value 'source'
            $srcNorm = if ($src) { [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $src }) } else { '' }
            if ($srcNorm -ne [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $url })) { $rc = @{ ok = $false; error = "The answer is about another link than this page's link." } }
        }
        if (-not $rc.ok) { $r.message = $rc.error; if ($Resume) { $r.status = 'mismatch' }; return $r }
        $sum = ConvertTo-LinkSummary -Reply $json.value -Bucket $bucket
        if (-not $sum.ok) { $r.message = $sum.error; return $r }
        if (-not $sum.readable) {
            $why = if ($sum.problem -eq 'no-access') { 'no access' } elseif ($sum.problem -eq 'not-found') { 'not found' } else { 'the source could not be read' }
            $cs = "Could not be updated on ${today}: $why."
            Invoke-Store $Store 'UpdatePage' @{ PageId = $pageId; Meta = @{ checkStatus = $cs; seenAt = $seenAt }; Outlines = @(@{ role = 'checked'; lines = (New-LinkCheckedLines -SummarizedAt $oldAt -CheckStatus $cs -History $history -SeenAt $seenAt) }); Title = $null } | Out-Null
            $r.status = 'could-not-update'
            $r.message = "$cs The earlier summary stays."
            return $r
        }
        $new = $sum.summary
    }
    $diff = if ($old) { Compare-LinkSummary -Old $old -New $new } else { @{ changed = $true; factsAdded = @($new.keyFacts); factsRemoved = @() } }
    $r.update.new = $new
    $r.update.diff = $diff

    if (-not $diff.changed -or $Decision -eq 'keep') {
        $at = if ($Decision -eq 'keep') { $oldAt } else { $today }
        $cs = if ($Decision -eq 'keep') { "Checked on ${today}: your edited summary was kept." } else { '' }
        Invoke-Store $Store 'UpdatePage' @{ PageId = $pageId; Meta = @{ summarizedAt = $at; checkStatus = $cs; seenAt = $seenAt }; Outlines = @(@{ role = 'checked'; lines = (New-LinkCheckedLines -SummarizedAt $at -CheckStatus $cs -History $history -SeenAt $seenAt) }); Title = $null } | Out-Null
        if ($Decision -eq 'keep') { $r.status = 'kept'; $r.message = 'Your edited summary was kept.' }
        else { $r.status = 'unchanged'; $r.message = "No changes since $(if ($oldAt) { $oldAt } else { 'the last check' })." }
        $r.update.newAt = $at
        return $r
    }

    if ($edited -and -not $Decision) {
        $r.status = 'needs-confirmation'
        $r.message = 'You edited the summary on this page. Replace it with the new summary?'
        $r.confirm = [ordered]@{
            id = $Id
            question = 'You edited the summary on this page. Replace it with the new summary?'
            detail = 'Your text moves to Earlier summaries on the page, marked as edited by you. Your notes are not touched.'
            options = @('replace', 'keep')
            editedText = $outlineText
            proposed = $new
        }
        return $r
    }

    # Replace.
    $prev = if ($edited) { @{ summary = ($outlineText -replace '\s+', ' ').Trim(); keyFacts = @() } } elseif ($old) { $old } else { $null }
    if ($prev) { $history = Add-SummaryHistory -History $history -Previous $prev -At $oldAt -Edited:$edited }

    $existingLinks = @(@(Get-LkProp $rec 'links' @()) | ForEach-Object { @{ target = [string](Get-LkProp $_ 'target' (Get-LkProp $_ 't' '')); strength = [int](Get-LkProp $_ 'strength' (Get-LkProp $_ 's' 1)); why = [string](Get-LkProp $_ 'why' (Get-LkProp $_ 'w' '')) } } | Where-Object { $_['target'] })
    $existingTargets = @($existingLinks | ForEach-Object { $_['target'] })
    $newLinks = @(); $review = @(); $topics = @(@(Get-LkProp $rec 'topics' @()) | Where-Object { $_ }); $newTopics = @()
    $rl = Invoke-Relink -Index $idx -Text (Get-LinkSummaryText $new) -Type $type -SelfId $Id -Store $Store -Ask $Ask -Options $Options -Now $now
    $r.timings.copilotMs += $rl.ms
    $proposedLinks = @()
    if ($rl.ok) {
        $proposedLinks = @($rl.v.value.links)
        $r.dropped = @($rl.v.dropped)
        $newLinks = @($proposedLinks | Where-Object { $existingTargets -notcontains $_['target'] })
        $propTargets = @($proposedLinks | ForEach-Object { $_['target'] })
        $pages = Get-IndexPageMap $idx
        $review = @(foreach ($t in $existingTargets) {
            if ($propTargets -contains $t) { continue }
            $p = if ($pages.ContainsKey($t)) { $pages[$t] } else { $null }
            [ordered]@{ target = $t; title = [string](Get-LkProp $p 'title' ''); link = [string](Get-LkProp $p 'link' ''); reason = 'no longer proposed for the new summary' }
        })
        foreach ($t in @($rl.v.value.topics)) { if ($topics -notcontains $t['path']) { $topics += $t['path']; $newTopics += $t } }
        if ($rl.sl) { $r.related = Get-RelatedPages -Shortlist $rl.sl -Links $proposedLinks -Count (Get-IngestOption $Options 'RelatedCount' 3) }
    } else {
        $r.warnings = @($r.warnings) + "Linking was not run again ($($rl.error)); the existing links stay."
    }

    $t1 = [Diagnostics.Stopwatch]::StartNew()
    $lines = Add-AnchorLinks -Lines (New-LinkSummaryLines -Url $url -Summary $new -Today $now) -Links $proposedLinks
    $merged = @($existingLinks) + @($newLinks | ForEach-Object { @{ target = $_['target']; strength = $_['strength']; why = $_['why'] } })
    $oneLine = if ($rl.ok -and $rl.v.value.summary) { $rl.v.value.summary } else { Limit-Sentence $new.summary }
    $meta2 = @{
        title = $new.title; summary = $oneLine; kind = $new.kind; summarizedAt = $today; seenAt = $seenAt; checkStatus = ''
        linkSummary = (ConvertTo-LkJson $new); summaryHash = (Get-SummaryHash (Get-LinesPlainText $lines)); history = (ConvertTo-LkJson @($history))
        links = $merged; topics = $topics
    }
    Invoke-Store $Store 'UpdatePage' @{ PageId = $pageId; Meta = $meta2; Outlines = @(@{ role = 'summary'; lines = $lines }, @{ role = 'checked'; lines = (New-LinkCheckedLines -SummarizedAt $today -History $history -SeenAt $seenAt) }); Title = $new.title } | Out-Null
    $newTargets = @($newLinks | ForEach-Object { [string]$_['target'] })
    $bl = Update-Backlinks -Store $Store -Index $idx -Targets $newTargets -ExcludeId $Id -Add @{ id = $Id; title = $new.title; link = (Get-LkString $rec 'link') }
    $r.backlinks = $bl.count
    $r.warnings = @($r.warnings) + @($bl.warnings)
    $r.timings.writeMs = [int]$t1.ElapsedMilliseconds

    $t2 = [Diagnostics.Stopwatch]::StartNew()
    $full = @{ id = $Id; pageId = $pageId; link = (Get-LkString $rec 'link'); section = (Get-LkString $rec 'section'); type = $type; title = $new.title; summary = $oneLine; topics = $topics; aliases = @(Get-LkProp $rec 'aliases' @()); links = $merged; url = $url; host = (Get-UrlHostName $url); kind = $new.kind; summarizedAt = $today }
    try { Invoke-Store $Store 'IndexUpdatePage' @{ Page = $full } | Out-Null }
    catch { $r.warnings = @($r.warnings) + "The index was not updated; the next start reads the page again ($($_.Exception.Message))." }
    $r.timings.indexMs = [int]$t2.ElapsedMilliseconds

    $view.title = $new.title; $view.topics = $topics
    $r.page = Get-PageView -Page $view -Vault $vault
    $newPaths = @($newTopics | ForEach-Object { $_['path'] })
    $chipTopics = @($topics | ForEach-Object { @{ path = [string]$_; isNew = ($newPaths -contains $_) } })
    $r.chips = Get-Chips -Type $type -Aliases @(Get-LkProp $rec 'aliases' @()) -Topics $chipTopics
    $r.links = ConvertTo-LinkResult $newLinks
    $r.status = 'updated'
    $r.message = "Updated: $($new.title)"
    $r.update.newAt = $today
    $r.update.review = @($review)
    $r
}

Export-ModuleMember -Function Get-IngestStoreContract, Get-MissingStoreFunctions, New-RequestRef, Invoke-AddRequest, Receive-AddAnswer, Get-ChatAnswerFor, Undo-AddRequest, Update-LinkSummary, Add-AnchorLinks, ConvertTo-BodyLines, Get-IncomingSources, Get-InboxTitle
