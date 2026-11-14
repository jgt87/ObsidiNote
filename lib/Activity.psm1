# What ObsidiNote did (operator, 2026-11-14): the home page's "Waiting for Copilot" list and the
# History view. The source is the vault's own Intake: every Add and every link Update makes one
# Intake item, whose obsn.status says how it ended (new, waiting, linked, failed) and obsn.filedAs
# which page it became. Nothing else is kept: no log file, no cache (OneNote is the only store).
# A filed item whose page is no longer in the index was undone or deleted. Edits and "Link it" make
# no Intake item and are not listed. Pure: the caller reads the hierarchy. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0

$script:UpdateKinds = @('linkUpdate', 'linkSeen')

function Get-ActivityList {
    <# $Pages: the Intake section's pages from ConvertFrom-ObsnHierarchy (id; title; updated; meta).
       $Index: page id -> index record (title, type). Returns @(@{ inboxId; title; state (working |
       waiting | added | updated | failed | gone); kind (text|link); requestKind; updated; since;
       reason; filedAs; filedTitle; filedType; canCheck; canRemove; canUndo }), newest first. #>
    param([object[]]$Pages = @(), [hashtable]$Index = @{}, [int]$Max = 200)
    $m = { param($p, $k) if ($p.meta -and $p.meta.ContainsKey($k)) { [string]$p.meta[$k] } else { '' } }
    $items = foreach ($p in @($Pages)) {
        if (-not $p) { continue }
        $status = & $m $p 'obsn.status'
        $rk = & $m $p 'obsn.requestKind'
        $filed = & $m $p 'obsn.filedAs'
        $rec = if ($filed -and $Index.ContainsKey($filed)) { $Index[$filed] } else { $null }
        $state = switch ($status) {
            'waiting' { 'waiting' }
            'failed' { 'failed' }
            'linked' { if (-not $rec) { 'gone' } elseif ($script:UpdateKinds -contains $rk) { 'updated' } else { 'added' } }
            default { 'working' }
        }
        [ordered]@{
            inboxId = [string]$p.id; title = [string]$p.title; state = $state
            kind = (& $m $p 'obsn.inboxKind'); requestKind = $rk
            updated = [string]$p.updated; since = (& $m $p 'obsn.waitingSince'); reason = (& $m $p 'obsn.statusReason')
            filedAs = $filed
            filedTitle = $(if ($rec) { [string]$rec.title } else { '' })
            filedType = $(if ($rec) { [string]$rec.type } else { '' })
            canCheck = ($state -eq 'waiting')
            # An item that never became a page can be cleared from the Intake (to Deleted Pages).
            canRemove = ($state -in 'waiting', 'failed', 'working')
            # Only an Add's own new page is undone; an Update changed a page that existed before.
            canUndo = ($state -eq 'added')
        }
    }
    , @(@($items) | Sort-Object { $_.updated } -Descending | Select-Object -First $Max)
}

function Test-RemovableInboxStatus {
    <# An Intake item may be removed only while it never became a page. #>
    param([AllowEmptyString()][string]$Status)
    $Status -in 'waiting', 'failed', 'new', ''
}

Export-ModuleMember -Function Get-ActivityList, Test-RemovableInboxStatus
