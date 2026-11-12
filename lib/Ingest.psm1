# Ingest: Add (capture anything into the active vault). FEASIBILITY.md sections 4 and 5.
# Invoke-AddRequest  text or link -> Inbox page (01 Inbox, status new) -> Copilot -> validate ->
#                    content page in its bucket (properties + obsn Meta + body with onenote: links)
#                    -> "Linked from" on target pages -> index -> Inbox item filed (or failed + reason).
# Undo-AddRequest    removes the created page (to OneNote's Deleted Pages) and reverts backlinks.
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
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')

$script:StoreContract = @(
    'AssertWritable', 'VaultName', 'GetIndex', 'TypeList', 'BucketForType', 'LinkBucket', 'NormalizeUrl',
    'FindPageByUrl', 'NewId', 'CreateInboxItem', 'SetInboxStatus', 'CreatePage', 'ReadPage', 'UpdatePage',
    'SetLinkedFrom', 'DeletePage', 'IndexAddPage', 'IndexUpdatePage', 'IndexRemovePage'
)

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
    if ($res -and $res -ne 'Success') { return @{ ok = $false; text = ''; error = "Copilot gave no answer ($res)."; ms = $ms } }
    if (Get-LkProp $r 'Cancelled' $false) { return @{ ok = $false; text = ''; error = 'The request was cancelled.'; ms = $ms } }
    @{ ok = $true; text = [string](Get-LkProp $r 'Text' ''); error = ''; ms = $ms }
}

function New-AddResult {
    param([string]$Status, [string]$Kind, [string]$Message = '')
    [ordered]@{
        status    = $Status        # added | failed | updated | unchanged | kept | needs-confirmation | could-not-update | ask-instead | undone
        kind      = $Kind          # text | link
        message   = $Message
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
            if ($hit -or $part['href']) { $new += $part; continue }
            $m = [regex]::Match([string]$part['text'], $pat, 'IgnoreCase')
            if (-not $m.Success) { $new += $part; continue }
            $s = [string]$part['text']
            if ($m.Index -gt 0) { $new += @{ text = $s.Substring(0, $m.Index); href = '' } }
            $new += @{ text = $m.Value; href = [string]$l['link'] }
            $rest = $s.Substring($m.Index + $m.Length)
            if ($rest) { $new += @{ text = $rest; href = '' } }
            $hit = $true
        }
        $parts = $new
        if ($hit) { [void]$State.todo.Remove($l) }
    }
    $kids = @(foreach ($c in @($Line['children'])) { Add-AnchorLinksToLine -Line $c -State $State })
    @{ parts = $parts; bold = [bool]$Line['bold']; collapsed = [bool]$Line['collapsed']; children = $kids }
}

function ConvertTo-BodyLines {
    <# The item's text as outline lines (one per text line; trailing empty lines dropped). #>
    param([string]$Text)
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
    param($Store, $Inbox, [string]$Reason, $Result)
    if (-not $Inbox) { return }
    try { Invoke-Store $Store 'SetInboxStatus' @{ PageId = $Inbox['pageId']; Status = 'failed'; Reason = $Reason; Id = '' } | Out-Null; $Result.inbox = @{ pageId = $Inbox['pageId']; status = 'failed' } }
    catch { $Result.warnings = @($Result.warnings) + "The Inbox item could not be marked as failed: $($_.Exception.Message)" }
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
       MaxPages, RelatedCount. Returns the Add result (New-AddResult fields). Never throws. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)]$Store, [Parameter(Mandatory)][scriptblock]$Ask, [hashtable]$Options = @{})
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $text = [string](Get-LkProp $Request 'text' '')
    $mode = (Get-LkString $Request 'mode').ToLowerInvariant()
    if (-not $mode) { $mode = 'add' }
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
        if ($url) { $r = Invoke-LinkAdd -Url $url -Store $Store -Ask $Ask -Options $Options -Result $r }
        else { $r = Invoke-TextAdd -Text $text -Mode $mode -Store $Store -Ask $Ask -Options $Options -Result $r }
    } catch {
        $r.status = 'failed'
        $r.message = "Adding stopped: $($_.Exception.Message)"
    }
    Complete-AddResult $r $sw
}

function Invoke-TextAdd {
    param([string]$Text, [string]$Mode, $Store, [scriptblock]$Ask, [hashtable]$Options, $Result)
    $r = $Result
    $r.text = $Text
    $now = Get-IngestNow $Options
    $idx = Invoke-Store $Store 'GetIndex'
    $types = @(Invoke-Store $Store 'TypeList')

    $t0 = [Diagnostics.Stopwatch]::StartNew()
    try { $inbox = Invoke-Store $Store 'CreateInboxItem' @{ Title = (Get-InboxTitle $Text); Text = $Text; Kind = 'text' } }
    catch { $r.message = "Could not write to the Inbox: $($_.Exception.Message)"; return $r }
    $r.inbox = @{ pageId = $inbox['pageId']; status = 'new' }
    $r.timings.inboxMs = [int]$t0.ElapsedMilliseconds

    $sl = Get-LinkShortlist -Index $idx -Text $Text -MaxChars (Get-IngestOption $Options 'MaxPromptChars' 12000) -MaxPages (Get-IngestOption $Options 'MaxPages' 60)
    $prompt = New-LinkPrompt -Text $Text -Shortlist $sl -Types $types -Today $now
    $ans = Invoke-IngestAsk -Ask $Ask -Prompt $prompt
    $r.timings.copilotMs += $ans.ms
    if (-not $ans.ok) { $r.message = $ans.error; Set-InboxFailed $Store $inbox $ans.error $r; return $r }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { $r.message = $json.error; Set-InboxFailed $Store $inbox $json.error $r; return $r }
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
    catch { $r.warnings = @($r.warnings) + "The Inbox item was not marked as filed: $($_.Exception.Message)" }

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
    $prompt = New-LinkPrompt -Text $Text -Shortlist $sl -Types $types -FixedType $Type -Today $Now
    $ans = Invoke-IngestAsk -Ask $Ask -Prompt $prompt
    if (-not $ans.ok) { return @{ ok = $false; error = $ans.error; v = $null; sl = $sl; ms = $ans.ms } }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { return @{ ok = $false; error = $json.error; v = $null; sl = $sl; ms = $ans.ms } }
    $v = Test-LinkReply -Reply $json.value -Index $Index -Shortlist $sl -Text $Text -Types $types -FixedType $Type -SelfId $SelfId -SkipDuplicateTitle
    if (-not $v.ok) { return @{ ok = $false; error = ($v.errors -join ' '); v = $v; sl = $sl; ms = $ans.ms } }
    @{ ok = $true; error = ''; v = $v; sl = $sl; ms = $ans.ms }
}

function Invoke-LinkAdd {
    param([string]$Url, $Store, [scriptblock]$Ask, [hashtable]$Options, $Result)
    $r = $Result
    $r.text = $Url
    $now = Get-IngestNow $Options
    $today = $now.ToString('yyyy-MM-dd')
    $norm = [string](Invoke-Store $Store 'NormalizeUrl' @{ Url = $Url })
    $existing = Invoke-Store $Store 'FindPageByUrl' @{ Url = $norm }
    if ($existing) {
        # One page per link: pasting it again updates that page.
        return (Update-LinkSummary -Store $Store -Ask $Ask -Id ([string](Get-LkProp $existing 'id' '')) -SeenAgain -Options $Options)
    }
    $bucket = [string](Invoke-Store $Store 'LinkBucket' @{ Url = $norm })
    $type = if ($bucket -eq 'Internal links') { 'link-internal' } else { 'link-web' }
    $idx = Invoke-Store $Store 'GetIndex'

    $t0 = [Diagnostics.Stopwatch]::StartNew()
    try { $inbox = Invoke-Store $Store 'CreateInboxItem' @{ Title = (Get-InboxTitle $norm); Text = $Url; Kind = 'link' } }
    catch { $r.message = "Could not write to the Inbox: $($_.Exception.Message)"; return $r }
    $r.inbox = @{ pageId = $inbox['pageId']; status = 'new' }
    $r.timings.inboxMs = [int]$t0.ElapsedMilliseconds

    $ans = Invoke-IngestAsk -Ask $Ask -Prompt (New-LinkSummaryPrompt -Url $norm -Bucket $bucket -Today $now)
    $r.timings.copilotMs += $ans.ms
    if (-not $ans.ok) { $r.message = $ans.error; Set-InboxFailed $Store $inbox $ans.error $r; return $r }
    $json = Get-ReplyJson $ans.text
    if (-not $json.ok) { $r.message = $json.error; Set-InboxFailed $Store $inbox $json.error $r; return $r }
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
    catch { $r.warnings = @($r.warnings) + "The Inbox item was not marked as filed: $($_.Exception.Message)" }

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
        [hashtable]$Options = @{}
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = New-AddResult -Status 'failed' -Kind 'link'
    try { Invoke-Store $Store 'AssertWritable' | Out-Null } catch { $r.message = "Nothing was updated: $($_.Exception.Message)"; return (Complete-AddResult $r $sw) }
    try { $r = Invoke-LinkUpdate -Store $Store -Ask $Ask -Id $Id -Decision $Decision -Proposed $Proposed -SeenAgain:$SeenAgain -Options $Options -Result $r }
    catch { $r.status = 'failed'; $r.message = "The update stopped: $($_.Exception.Message)" }
    Complete-AddResult $r $sw
}

function Invoke-LinkUpdate {
    param($Store, [scriptblock]$Ask, [string]$Id, [string]$Decision, $Proposed, [switch]$SeenAgain, [hashtable]$Options, $Result)
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
        $ans = Invoke-IngestAsk -Ask $Ask -Prompt (New-LinkSummaryPrompt -Url $url -Bucket $bucket -Today $now)
        $r.timings.copilotMs += $ans.ms
        if (-not $ans.ok) { $r.message = $ans.error; return $r }
        $json = Get-ReplyJson $ans.text
        if (-not $json.ok) { $r.message = $json.error; return $r }
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

Export-ModuleMember -Function Get-IngestStoreContract, Get-MissingStoreFunctions, Invoke-AddRequest, Undo-AddRequest, Update-LinkSummary, Add-AnchorLinks, ConvertTo-BodyLines, Get-IncomingSources, Get-InboxTitle
