# Upgrade steps: when a filing, indexing or page rule changes, the knowledge already in the vault is
# brought in line too, not only new items (operator, 2026-11-13). Each step is a conformance check:
# it compares every page with the CURRENT rule and fixes what differs, so it is idempotent and simply
# runs at every start (writer only; a read-only session only reports the plan). Never deletes, never
# touches the person's pages, archived pages, other vaults or connected notebooks.
#
# Steps:
#   link-bucket (2026-11-13): a link page sits in the section its address calls for today
#     (Get-LinkBucket: Microsoft 365, a company SaaS tenant or the company's name -> Internal links;
#     public pages -> Web links). A page in the wrong one is moved (it gets a new OneNote id, found
#     again by its obsn.id; probes/p9-move.ps1), gets the matching type (link-internal | link-web),
#     its index record follows, and the "Linked from" lists of the pages it links to get its new link.
#   link-strength (2026-11-14): a "Link it" link (the person's own) is "related" (2); before v0.8.2
#     it was written as "loose" (1). The page's obsn.links Meta and index record are raised
#     (Update-LinkItStrength in lib/Ingest.psm1); no outline is written. Copilot's links are left as rated.
#   body-links (2026-11-16): a moved page gets a new link (on a business tenant a new page-id too), so
#     before moves re-pointed them (lib/VaultStore.psm1 MovePage), a link to an archived page in the
#     text of a page that links to it stopped opening it. Each page that links to an archived page is
#     checked (store RepairBodyLinks): in its own body outline only, a link that points at no page of
#     the vault any more and whose text is the archived page's title or alias points at it again.
#     Pages archived and restored before stay as they are (no mark says they moved).
#   meeting-series (2026-11-18): a meeting page from Today's meetings (origin meeting) made before
#     series existed gets obsn.series (its title without the date Copilot put in it) and obsn.meetingAt
#     (that date, else the day it was made; no time is known). Meta and index record only; the title stays.
#   series-data (2026-11-19): a meeting page of a series imported before its notes were kept as data
#     gets obsn.meeting, read from its own body outline (attendees, summary, decisions, actions); the
#     index marks it read (meetingData '1', or 'none' when the text held no notes), so it is read once.
#     Nothing is asked: what the page says is kept as it is (attendees imported as invitees stay so
#     until that day is imported again).
#   series-page (2026-11-19): every series with a meeting page has one series page (kind series)
#     that links all its meetings; one is made or written again when a meeting is not on it yet. At
#     start Copilot is not asked: a new series page gets its summary at the next import of the series.
# Done once: Intake requests leave the index by the scan rule itself (lib/Index.psm1); nothing to move.
# The log holds counts and ids only. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ingest.psm1')
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')
Import-Module (Join-Path $PSScriptRoot 'Meetings.psm1')   # meeting-series: the series name of a title

$script:LinkBuckets = @('Internal links', 'Web links')

function Get-UpgradePlan {
    <# The pages that do not match the current rules. Pure. Returns @(@{ step; id; from; to; type }). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Model, [string[]]$InternalHosts = @(), [string[]]$CompanyNames = @())
    # body-links: the pages that link to an archived page (their own links, from their obsn.links Meta).
    $archived = @{}
    foreach ($p in @($Model.pages.Values)) { if ($p.owner -eq 'obsn' -and $p.status -eq 'archived') { $archived[[string]$p.id] = $true } }
    foreach ($p in @($Model.pages.Values)) {
        if ($p.owner -ne 'obsn' -or -not $p.oneNoteId -or -not $archived.Count) { continue }
        foreach ($l in @($p.links)) {
            if (-not $l) { continue }
            $t = [string]$(if ($l -is [Collections.IDictionary]) { if ($l.Contains('target')) { $l['target'] } else { $l['t'] } } else { $l.target })
            if ($t -and $t -ne [string]$p.id -and $archived.ContainsKey($t)) { @{ step = 'body-links'; id = [string]$p.id; from = ''; to = $t; type = '' }; break }
        }
    }
    # series-data and series-page: the live meeting pages of each series, and its series page.
    $series = @{}; $seriesPages = @{}
    foreach ($p in @($Model.pages.Values)) {
        if ($p.owner -ne 'obsn' -or $p.status -eq 'archived' -or $p.type -ne 'meeting' -or -not [string]$p['series']) { continue }
        $key = Get-MeetingSeriesKey ([string]$p['series'])
        if (-not $key) { continue }
        if ([string]$p.kind -eq 'series') { $seriesPages[$key] = $p; continue }
        if (-not $series.ContainsKey($key)) { $series[$key] = New-Object System.Collections.Generic.List[object] }
        $series[$key].Add($p)
        if (-not [string]$p['meetingData'] -and -not [string]$p['meeting'] -and $p.oneNoteId) { @{ step = 'series-data'; id = [string]$p.id; from = ''; to = ''; type = '' } }
    }
    foreach ($key in @($series.Keys | Sort-Object)) {
        $ids = @($series[$key] | ForEach-Object { [string]$_.id })
        $sp = if ($seriesPages.ContainsKey($key)) { $seriesPages[$key] } else { $null }
        $have = @(if ($sp) { foreach ($l in @($sp.links)) { if ($l) { [string]$(if ($l -is [Collections.IDictionary]) { $l['target'] } else { $l.target }) } } })
        if (-not $sp -or @($ids | Where-Object { $have -notcontains $_ }).Count) {
            # id: the newest meeting of the series (its series name is the one written on the page).
            $newest = @($series[$key] | Sort-Object { [string]$_['meetingAt'] } -Descending)[0]
            @{ step = 'series-page'; id = [string]$newest.id; from = $key; to = [string]$newest['series']; type = $(if ($sp) { 'update' } else { 'new' }) }
        }
    }
    foreach ($p in @($Model.pages.Values)) {
        if ($p.owner -ne 'obsn' -or $p.status -eq 'archived') { continue }
        if (Test-WeakLinkIt -Links @($p.links)) { @{ step = 'link-strength'; id = [string]$p.id; from = ''; to = ''; type = '' } }
        if ($p.type -eq 'meeting' -and [string]$p['origin'] -eq 'meeting' -and -not [string]$p['series']) {
            $s = Get-MeetingSeriesName ([string]$p.title)
            if ($s) {
                $day = if ([string]$p.title -match '\b(\d{4}-\d{2}-\d{2})\b') { $Matches[1] } elseif ([string]$p['created'] -match '^(\d{4}-\d{2}-\d{2})') { $Matches[1] } else { '' }
                @{ step = 'meeting-series'; id = [string]$p.id; from = ''; to = $s; type = $day }
            }
        }
        $u = [string]$p.url
        if ($u -notmatch '^(?i)https?://') { continue }
        $have = Get-BucketOfSection ([string]$p.section)
        if ($script:LinkBuckets -notcontains $have) { continue }
        $want = Get-LinkBucket -Url $u -InternalHosts $InternalHosts -CompanyNames $CompanyNames
        if ($want -eq $have) { continue }
        @{ step = 'link-bucket'; id = [string]$p.id; from = $have; to = $want; type = $(if ($want -eq 'Internal links') { 'link-internal' } else { 'link-web' }) }
    }
}

function Invoke-VaultUpgrade {
    <# Runs the plan through the vault store (lib/VaultStore.psm1 New-VaultStore). Returns
       @{ status = done | none | partial | skipped; planned; moved; raised; failed; reason }. Never throws.
       planned and failed count PAGES (a page can need more than one step); moved and raised count
       the steps that changed something. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Store)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = [ordered]@{ status = 'none'; planned = 0; changed = 0; moved = 0; raised = 0; relinked = 0; series = 0; meetingData = 0; seriesPages = 0; failed = 0; reason = '' }
    # Made before the try: when a later step stops the upgrade, the pages already changed and the
    # failures already collected are still reported (code review 2026-11-15).
    $failedIds = @{}; $changedIds = @{}
    try {
        $model = & $Store.Model
        $rules = & $Store.LinkRules
        $plan = @(Get-UpgradePlan -Model $model -InternalHosts @($rules.InternalHosts) -CompanyNames @($rules.CompanyNames))
        # body-links pages are only checked (most need nothing): they count once something changed.
        # series-page steps count as their own item (one series page each), added when they run.
        $r.planned = @($plan | Where-Object { $_.step -ne 'body-links' -and $_.step -ne 'series-page' } | ForEach-Object { $_.id } | Select-Object -Unique).Count
        if (-not $plan.Count) { return $r }
        # Read only: say so only when a page is known to differ (body-links pages are only checks).
        try { & $Store.AssertWritable | Out-Null } catch { if ($r.planned) { $r.status = 'skipped'; $r.reason = $_.Exception.Message }; return $r }
        $targets = New-Object System.Collections.Generic.List[string]
        foreach ($s in $plan) {
            if ($s.step -eq 'body-links') {
                try { if ((& $Store.RepairBodyLinks $s.id).count) { $r.relinked++; $changedIds[$s.id] = $true; $r.planned++ } }
                catch { $failedIds[$s.id] = $true; $r.planned++; Write-AppLog info upgrade 'Body links failed' @{ step = $s.step; id = $s.id; error = $_.Exception.GetType().Name } }
                continue
            }
            if ($s.step -eq 'series-data') {
                try {
                    $p = $model.pages[$s.id]
                    $data = Get-MeetingDataFromText -Text ([string](& $Store.BodyMarkdown ([string]$p.oneNoteId))) -Body
                    $v = ConvertTo-MeetingDataValue $data
                    if ($v) { & $Store.UpdatePage ([string]$p.oneNoteId) @{ meeting = $v } @() $null | Out-Null }
                    & $Store.IndexUpdatePage @{ id = $s.id; meeting = $v; meetingData = $(if ($v) { '1' } else { 'none' }) } | Out-Null
                    $r.meetingData++; $changedIds[$s.id] = $true
                } catch { $failedIds[$s.id] = $true; Write-AppLog info upgrade 'Meeting notes failed' @{ step = $s.step; id = $s.id; error = $_.Exception.GetType().Name } }
                continue
            }
            if ($s.step -eq 'series-page') {
                $res = @{ warnings = @(); timings = @{ copilotMs = 0 } }
                Update-SeriesPage -Store $Store -Ask $null -Info @{ key = $s.from; series = $s.to } -Result $res
                if ($res['series']) { $r.seriesPages++; $changedIds["series:$($s.from)"] = $true; $r.planned++ }
                else { $failedIds["series:$($s.from)"] = $true; $r.planned++; Write-AppLog info upgrade 'Series page failed' @{ step = $s.step; id = $s.id; warnings = @($res.warnings).Count } }
                continue
            }
            if ($s.step -eq 'meeting-series') {
                try {
                    $p = $model.pages[$s.id]
                    & $Store.UpdatePage ([string]$p.oneNoteId) @{ series = $s.to; meetingAt = $s.type } @() $null | Out-Null
                    & $Store.IndexUpdatePage @{ id = $s.id; series = $s.to; meetingAt = $s.type } | Out-Null
                    $r.series++; $changedIds[$s.id] = $true
                } catch { $failedIds[$s.id] = $true; Write-AppLog info upgrade 'Meeting series failed' @{ step = $s.step; id = $s.id; error = $_.Exception.GetType().Name } }
                continue
            }
            if ($s.step -eq 'link-strength') {
                try { if ((Update-LinkItStrength -Store $Store -Id $s.id).changed) { $r.raised++; $changedIds[$s.id] = $true } }
                catch { $failedIds[$s.id] = $true; Write-AppLog info upgrade 'Link strength failed' @{ step = $s.step; id = $s.id; error = $_.Exception.GetType().Name } }
                continue
            }
            try {
                $m = & $Store.MovePage $s.id $s.to $s.type
                if ($m.moved) {
                    $r.moved++; $changedIds[$s.id] = $true
                    foreach ($l in @($model.pages[$s.id].links)) { if ($l -and $l.target -and -not $targets.Contains([string]$l.target)) { $targets.Add([string]$l.target) } }
                }
            } catch {
                $failedIds[$s.id] = $true
                Write-AppLog info upgrade 'Re-file failed' @{ step = $s.step; id = $s.id; error = $_.Exception.GetType().Name }
            }
        }
        # "Linked from" on the pages a moved page links to holds its (old) link: write them again.
        if ($targets.Count) {
            $idx = & $Store.GetIndex
            foreach ($t in $targets) {
                if (-not $model.pages.Contains($t)) { continue }
                try { & $Store.SetLinkedFrom $t (Get-IncomingSources -Index $idx -TargetId $t) | Out-Null } catch { }
            }
        }
        $r.status = if ($failedIds.Count) { 'partial' } else { 'done' }
    } catch {
        # Stopped early: not a page's failure, so it is the reason, not one more failed page.
        $r.status = 'partial'; $r.reason = $_.Exception.Message
    } finally {
        $r.failed = $failedIds.Count; $r.changed = $changedIds.Count
        Write-AppLog info upgrade 'Upgrade finished' @{ status = $r.status; planned = $r.planned; changed = $r.changed; moved = $r.moved; raised = $r.raised; failed = $r.failed; ms = $sw.ElapsedMilliseconds }
    }
    $r
}

function Format-UpgradeStatus {
    <# The start's status line for an upgrade result, or $null when there was nothing to do. #>
    param($Result)
    if (-not $Result -or $Result.status -eq 'none') { return $null }
    $done = @()
    if ($Result.moved) { $done += "$($Result.moved) link page(s) moved to the section the current link rule asks for" }
    if ($Result.raised) { $done += "your own links on $($Result.raised) page(s) set to related" }
    if ($Result -is [Collections.IDictionary] -and $Result['relinked']) { $done += "links in the text of $($Result.relinked) page(s) point at the archived pages again" }
    if ($Result -is [Collections.IDictionary] -and $Result['series']) { $done += "$($Result.series) meeting page(s) given their series" }
    if ($Result -is [Collections.IDictionary] -and $Result['meetingData']) { $done += "the notes of $($Result.meetingData) meeting page(s) kept for their series page" }
    if ($Result -is [Collections.IDictionary] -and $Result['seriesPages']) { $done += "$($Result.seriesPages) series page(s) written (summary at the next import of each series)" }
    if ($Result.status -eq 'done' -and -not $done.Count) { return $null }
    switch ($Result.status) {
        'done' { @{ status = 'OK'; detail = ($done -join '; '); hint = '' } }
        'skipped' { @{ status = 'WARN'; detail = "$($Result.planned) page(s) do not follow the current rules (link section, strength of your own links); not changed, this ObsidiNote is read only"; hint = 'The writer brings them in line at its next start.' } }
        default {
            # The pages really changed, never "planned minus failed": a page that was not reached,
            # or needed nothing after all, is neither.
            $d = "$([int]$Result.changed) of $($Result.planned) page(s) brought in line"
            if ($Result.failed) { $d += "; $($Result.failed) could not be changed" }
            if ($Result.reason) { $d += "; the upgrade stopped early ($($Result.reason))" }
            @{ status = 'WARN'; detail = $d; hint = 'The others stay as they are and are tried again at the next start. The log has the ids.' }
        }
    }
}

Export-ModuleMember -Function Get-UpgradePlan, Invoke-VaultUpgrade, Format-UpgradeStatus
