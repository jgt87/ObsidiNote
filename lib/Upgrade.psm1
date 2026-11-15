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
# Done once: Intake requests leave the index by the scan rule itself (lib/Index.psm1); nothing to move.
# The log holds counts and ids only. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ingest.psm1')
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')

$script:LinkBuckets = @('Internal links', 'Web links')

function Get-UpgradePlan {
    <# The pages that do not match the current rules. Pure. Returns @(@{ step; id; from; to; type }). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Model, [string[]]$InternalHosts = @(), [string[]]$CompanyNames = @())
    foreach ($p in @($Model.pages.Values)) {
        if ($p.owner -ne 'obsn' -or $p.status -eq 'archived') { continue }
        if (Test-WeakLinkIt -Links @($p.links)) { @{ step = 'link-strength'; id = [string]$p.id; from = ''; to = ''; type = '' } }
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
    $r = [ordered]@{ status = 'none'; planned = 0; changed = 0; moved = 0; raised = 0; failed = 0; reason = '' }
    # Made before the try: when a later step stops the upgrade, the pages already changed and the
    # failures already collected are still reported (code review 2026-11-15).
    $failedIds = @{}; $changedIds = @{}
    try {
        $model = & $Store.Model
        $rules = & $Store.LinkRules
        $plan = @(Get-UpgradePlan -Model $model -InternalHosts @($rules.InternalHosts) -CompanyNames @($rules.CompanyNames))
        $r.planned = @($plan | ForEach-Object { $_.id } | Select-Object -Unique).Count
        if (-not $plan.Count) { return $r }
        try { & $Store.AssertWritable | Out-Null } catch { $r.status = 'skipped'; $r.reason = $_.Exception.Message; return $r }
        $targets = New-Object System.Collections.Generic.List[string]
        foreach ($s in $plan) {
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
