# The active vault of one ObsidiNote session (FEASIBILITY.md, Several ObsidiNote vaults; Storage
# principle): which vault a start continues in, opening it (guarded write root, writer lease,
# structure, index with the completeness check), renewing the lease while ObsidiNote runs, switching
# to another vault, and giving the lease back on exit. Used by obsidinote.ps1 (the start, the lease
# renewal and the exit) and lib/Server.psm1 (switching vault, a new vault).
# The vault and lease records that cross into the server's runspace are plain hashtables of strings,
# numbers and dates (ConvertTo-VaultRecord, ConvertTo-LeaseRecord), never objects with methods.
# PS 5.1, ASCII only. Writes nothing to disk; every OneNote write goes through the guarded adapter.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'Vault.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriterLease.psm1')
Import-Module (Join-Path $PSScriptRoot 'Index.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookView.psm1')
Import-Module (Join-Path $PSScriptRoot 'VaultSettings.psm1')

$script:LeaseTtlSec = 120
$script:RenewEverySec = 60

function Get-LeaseTimings { @{ ttlSec = $script:LeaseTtlSec; renewEverySec = $script:RenewEverySec } }

function Select-StartVault {
    <# The vault a start continues in (pure): the vault id on record, else the vault whose notebook is
       on record ("notebook"), else the only open vault, else none. Returns @{ vault; why } with why
       one of record-id, record-notebook, only, none, several. A record that names a vault that is not
       open gives the only vault when there is exactly one. #>
    param([object[]]$Vaults = @(), [string]$RecordVaultId = '', [string]$Record = '', [object[]]$Notebooks = @())
    $all = @($Vaults | Where-Object { $_ })
    if ($RecordVaultId) {
        $v = @($all | Where-Object { $_.vaultId -eq $RecordVaultId }) | Select-Object -First 1
        if ($v) { return @{ vault = $v; why = 'record-id' } }
    }
    if ($Record) {
        foreach ($v in $all) {
            $nbPath = [string]$v.location
            if ($v.rootKind -eq 'sectiongroup') { $nb = @($Notebooks | Where-Object { $_.id -eq $v.notebookId }) | Select-Object -First 1; $nbPath = if ($nb) { [string]$nb.location } else { '' } }
            if ($nbPath -and (Test-RecordMatchesPath $Record $nbPath)) { return @{ vault = $v; why = 'record-notebook' } }
        }
    }
    if ($all.Count -eq 1) { return @{ vault = $all[0]; why = 'only' } }
    if ($all.Count -gt 1) { return @{ vault = $null; why = 'several' } }
    @{ vault = $null; why = 'none' }
}

function ConvertTo-VaultRecord {
    <# The plain record of a vault (Get-VaultList item) that the server state keeps. #>
    param([Parameter(Mandatory)]$Vault)
    @{
        vaultId = [string]$Vault.vaultId; name = [string]$Vault.name; rootId = [string]$Vault.rootId; rootKind = [string]$Vault.rootKind
        notebookId = [string]$Vault.notebookId; notebookName = [string]$Vault.notebookName; location = [string]$Vault.location
        indexSectionId = [string]$Vault.indexSectionId; statePageId = [string]$Vault.statePageId
    }
}

function Join-ActiveVault {
    <# The vaults and notebooks as a running ObsidiNote sees them (pure): what detection found
       (Get-VaultList, Get-NotebookList), plus the ACTIVE vault from its record ($Record: the server
       state's Vault, ConvertTo-VaultRecord) when detection does not list it while its notebook is
       still open. Detection reads OneNote again every few seconds; when OneNote answered a notebook
       without its sections, or its Index pages without their Meta, the vault this session had opened
       and was writing in turned into a read-only connected notebook in the window (operator,
       2026-11-15: another notebook was the selected one in OneNote). A vault that was opened stays
       the active vault until the person switches or its notebook is closed.
       Returns @{ vaults; notebooks; kept }: kept = the record was added. Nothing is added without a
       record, when the vault is listed, when its notebook is not open, or when detection found
       another vault at the same root (what OneNote shows wins). Other vaults are never touched. #>
    param([object[]]$Vaults = @(), [object[]]$Notebooks = @(), $Record = $null)
    $vs = @($Vaults | Where-Object { $_ }); $nbs = @($Notebooks | Where-Object { $_ })
    $same = @{ vaults = $vs; notebooks = $nbs; kept = $false }
    if (-not $Record -or -not $Record.vaultId -or -not $Record.notebookId -or -not $Record.rootId) { return $same }
    if (@($vs | Where-Object { $_.vaultId -eq $Record.vaultId -or $_.rootId -eq $Record.rootId }).Count) { return $same }
    if (-not @($nbs | Where-Object { $_.id -eq $Record.notebookId }).Count) { return $same }
    # The same fields as a Get-VaultList item; the page and topic counts of the state page are not
    # known here (nothing in the app reads them from the list).
    $item = [pscustomobject]@{
        vaultId = [string]$Record.vaultId; name = [string]$Record.name; rootId = [string]$Record.rootId; rootKind = [string]$Record.rootKind
        notebookId = [string]$Record.notebookId; notebookName = [string]$Record.notebookName; location = [string]$Record.location
        schema = (Get-ObsnSchemaVersion); statePageId = [string]$Record.statePageId; indexSectionId = [string]$Record.indexSectionId; pages = 0; topics = 0
    }
    $out = @(foreach ($n in $nbs) {
        if ($n.id -ne $Record.notebookId) { $n; continue }
        [pscustomobject]@{
            name = $n.name; id = $n.id; location = $n.location; cloud = $n.cloud
            structured = [bool]($n.structured -or $item.rootKind -eq 'notebook')
            vaultIds = @(@($n.vaultIds) + $item.vaultId | Where-Object { $_ })
        }
    })
    @{ vaults = @($vs + $item); notebooks = $out; kept = $true }
}

function Get-NotebookToSelect {
    <# The notebook the start selects in OneNote before it looks for the vault again, or $null (pure).
       Only when all of this holds: a vault was opened here before ("vaultId" on record) and is not
       among the vaults found; the notebook on record ("notebook") is open; no vault is found in that
       notebook; and it is not the notebook OneNote already shows ($CurrentId, '' = unknown). #>
    param([object[]]$Vaults = @(), [object[]]$Notebooks = @(), [string]$RecordVaultId = '', [string]$Record = '', [string]$CurrentId = '')
    if (-not $RecordVaultId -or -not $Record) { return $null }
    if (@($Vaults | Where-Object { $_ -and $_.vaultId -eq $RecordVaultId }).Count) { return $null }
    $nb = @($Notebooks | Where-Object { $_ -and $_.location -and (Test-RecordMatchesPath $Record ([string]$_.location)) }) | Select-Object -First 1
    if (-not $nb) { return $null }
    if (@($Vaults | Where-Object { $_ -and $_.notebookId -eq $nb.id }).Count) { return $null }
    if ($CurrentId -and $CurrentId -eq $nb.id) { return $null }
    $nb
}

function Find-StartVault {
    <# The start's vault step before opening: the open vaults and notebooks and the vault to continue
       in (Select-StartVault). When the notebook on record is open but no vault is found in it
       (Get-NotebookToSelect), that notebook is selected in OneNote ONCE (NavigateTo: not a write) and
       detection is read again up to $Tries times, $WaitMs apart, until the vault shows; then the
       start goes on as before with whatever was found. Never navigates when the vault was found,
       and only here, at the start. -Sleep replaces the wait (tests).
       Returns @{ vaults; notebooks; pick; navigated; tries; status ('' | OK | WARN); detail; hint }:
       status is set only when the notebook was selected (one status line). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [string]$RecordVaultId = '', [string]$Record = '', [int]$Tries = 5, [int]$WaitMs = 2000,
        [scriptblock]$Sleep = { param($ms) Start-Sleep -Milliseconds $ms })
    $r = @{ vaults = @(); notebooks = @(); pick = $null; navigated = $false; tries = 0; status = ''; detail = ''; hint = '' }
    $r.vaults = @(Get-VaultList -Adapter $Adapter)
    $r.notebooks = @(Get-NotebookList -Adapter $Adapter -Vaults $r.vaults)
    $current = ''
    try { if ($Adapter.PSObject.Methods['GetCurrentNotebookId']) { $current = [string]$Adapter.GetCurrentNotebookId() } } catch { $current = '' }
    $nb = Get-NotebookToSelect -Vaults $r.vaults -Notebooks $r.notebooks -RecordVaultId $RecordVaultId -Record $Record -CurrentId $current
    if ($nb -and $Adapter.PSObject.Methods['NavigateTo']) {
        $found = $false
        try {
            $Adapter.NavigateTo([string]$nb.id)
            $r.navigated = $true
            while (-not $found -and $r.tries -lt $Tries) {
                $r.tries++
                & $Sleep $WaitMs
                $r.vaults = @(Get-VaultList -Adapter $Adapter)
                $r.notebooks = @(Get-NotebookList -Adapter $Adapter -Vaults $r.vaults)
                $found = [bool]@($r.vaults | Where-Object { $_.notebookId -eq $nb.id }).Count
            }
        } catch { $found = $false }
        if ($found) { $r.status = 'OK'; $r.detail = 'the notebook was selected in OneNote so its pages could be read' }
        elseif ($r.navigated) { $r.status = 'WARN'; $r.detail = "the notebook on record still shows no vault after selecting it in OneNote ($($r.tries) checks)"; $r.hint = 'Open that notebook in OneNote, wait until it has synced, then start ObsidiNote again.' }
        else { $r.status = 'WARN'; $r.detail = 'the notebook on record shows no vault and could not be selected in OneNote'; $r.hint = 'Select that notebook in OneNote, then start ObsidiNote again.' }
    }
    $r.pick = Select-StartVault -Vaults $r.vaults -RecordVaultId $RecordVaultId -Record $Record -Notebooks $r.notebooks
    $r
}

function ConvertTo-LeaseRecord {
    <# The plain record of a lease (Request-WriterLease result); $null stays $null. #>
    param($Lease)
    if (-not $Lease) { return $null }
    # acquired: when the holder took the lease (UTC); holderHere: it is held by another session of
    # this computer (the window says "this PC's earlier run" instead of "another PC").
    $g = { param($n, $d) if ($Lease -is [hashtable]) { if ($Lease.ContainsKey($n)) { $Lease[$n] } else { $d } } elseif ($Lease.PSObject.Properties[$n]) { $Lease.$n } else { $d } }
    @{ mode = [string]$Lease.mode; sessionId = [string]$Lease.sessionId; holder = [string]$Lease.holder; expires = [datetime]$Lease.expires
        acquired = [datetime](& $g 'acquired' ([datetime]::MinValue)); holderHere = [bool](& $g 'holderHere' $false)
        statePageId = [string]$Lease.statePageId; indexSectionId = [string]$Lease.indexSectionId }
}

function Get-VaultRecordFor {
    <# The "notebook" record of a vault (what a start opens to bring it up): its notebook's onenote:
       link or .onetoc2 path. -ToRecord turns a notebook path into a record (ConvertTo-NotebookRecord). #>
    param([Parameter(Mandatory)]$Vault, [object[]]$Notebooks = @(), [scriptblock]$ToRecord = { param($p) $p })
    $path = [string]$Vault.location
    if ($Vault.rootKind -eq 'sectiongroup') {
        $nb = @($Notebooks | Where-Object { $_.id -eq $Vault.notebookId }) | Select-Object -First 1
        $path = if ($nb) { [string]$nb.location } else { '' }
    }
    if (-not $path) { return '' }
    [string](& $ToRecord $path)
}

function Open-VaultSession {
    <# Opens $Vault (a Get-VaultList item) as the active vault: the guarded adapter's write root, the
       writer lease (writer or read-only), then, as the writer, the structure (Open-ObsidiVault) and
       the index (Update-VaultIndex: load, scan, completeness, Index pages written). Read-only: the
       index is read and checked, nothing is written. Then the vault's settings in OneNote are checked
       (Sync-VaultSettings: missing keys added with their defaults as the writer, existing values
       never changed; $LocalSettings fills a missing key once). Returns @{ vault (record); lease
       (record); model; missing (count); mode; written; settings (the values to use); settingsResult }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)]$Vault, [Parameter(Mandatory)][string]$SessionId, [object[]]$Vaults = $null, [int]$TtlSec = $script:LeaseTtlSec, [hashtable]$LocalSettings = @{},
        # Only the start passes it, after it replaced the ObsidiNote that was running here: a lease this
        # computer left behind is then taken at once (Get-LeaseDecision), never another computer's.
        [switch]$NoOtherHere)
    Set-OneNoteWriteRoot -Adapter $Adapter -RootId $Vault.rootId
    $lease = Request-WriterLease -Adapter $Adapter -IndexSectionId $Vault.indexSectionId -SessionId $SessionId -TtlSec $TtlSec -NoOtherHere:$NoOtherHere
    if ($lease.mode -eq 'writer') {
        $list = if ($null -ne $Vaults) { $Vaults } else { @($Vault) }
        $null = Open-ObsidiVault -Adapter $Adapter -RootId $Vault.rootId -Vaults $list
        $ix = Update-VaultIndex -Adapter $Adapter -RootId $Vault.rootId -IndexSectionId $Vault.indexSectionId -Lease $lease -VaultId $Vault.vaultId
    } else {
        $ix = Update-VaultIndex -Adapter $Adapter -RootId $Vault.rootId -IndexSectionId $Vault.indexSectionId -VaultId $Vault.vaultId
    }
    # Missing from the index = pages the scan found that the Index pages did not list (added), plus
    # any the completeness check still had to add; as the writer they are now on the Index pages.
    $missing = @($ix.added).Count + @($ix.missing).Count
    $set = Sync-VaultSettings -Adapter $Adapter -IndexSectionId $Vault.indexSectionId -Writer ($lease.mode -eq 'writer') -Local $LocalSettings
    @{ vault = (ConvertTo-VaultRecord $Vault); lease = (ConvertTo-LeaseRecord $lease); model = $ix.model; missing = $missing; mode = $lease.mode; written = [bool]$ix.write; settings = $set.effective; settingsResult = $set }
}

function Update-SessionLease {
    <# Renews the lease of the vault record $Vault (or takes it when it became free). Returns the new
       lease record; on a COM error the old record with mode 'readonly' when it has expired. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Vault, [Parameter(Mandatory)][string]$SessionId, $Lease = $null, [int]$TtlSec = $script:LeaseTtlSec)
    try {
        if (-not $Adapter.RootId -or $Adapter.RootId -ne $Vault.rootId) { Set-OneNoteWriteRoot -Adapter $Adapter -RootId $Vault.rootId }
        ConvertTo-LeaseRecord (Request-WriterLease -Adapter $Adapter -IndexSectionId $Vault.indexSectionId -SessionId $SessionId -TtlSec $TtlSec)
    } catch {
        if ($Lease -and -not (Test-WriterLease $Lease)) { $Lease.mode = 'readonly' }
        $Lease
    }
}

function Close-VaultSession {
    <# Gives the lease back (only when it is still this session's). Never throws. #>
    param([Parameter(Mandatory)]$Adapter, $Vault, $Lease)
    if (-not $Vault -or -not $Lease -or $Lease.mode -ne 'writer') { return $false }
    try {
        if (-not $Adapter.RootId -or $Adapter.RootId -ne $Vault.rootId) { Set-OneNoteWriteRoot -Adapter $Adapter -RootId $Vault.rootId }
        Clear-WriterLease -Adapter $Adapter -Lease $Lease
    } catch { $false }
}

function Format-VaultStatus {
    <# The start's status line for the vault step: @{ status (OK|WARN); detail; hint }. Pure. #>
    param($Open, [string]$Why = '', [int]$VaultCount = 0, [string]$Problem = '')
    # Not $Error: that is an automatic variable (like $pid, never a page id).
    if ($Problem) { return @{ status = 'WARN'; detail = "could not be opened: $Problem"; hint = 'Check that OneNote shows the vault''s notebook, then start ObsidiNote again.' } }
    if (-not $Open) {
        if ($Why -eq 'several') { return @{ status = 'WARN'; detail = "$VaultCount vaults are open and none is on record"; hint = 'Choose the vault to work in with the notebook switcher in the window.' } }
        return @{ status = 'WARN'; detail = 'no ObsidiNote vault is open'; hint = 'Use "New ObsidiNote vault" in the window, or open a notebook that holds one in OneNote.' }
    }
    $m = $Open.model
    $pages = @($m.pages.Keys).Count; $topics = @($m.topics.Keys).Count
    $many = $Open.missing -ne 1
    $done = if ($Open.missing) { "$($Open.missing) page$(if ($many) { 's were' } else { ' was' }) missing from the index$(if ($Open.mode -eq 'writer') { $(if ($many) { ' and are now in the index (on Unfiled when they have no topic)' } else { ' and is now in the index (on Unfiled when it has no topic)' }) } else { '' })" } else { 'index complete' }
    if ($Open.mode -ne 'writer') {
        $until = ([datetime]$Open.lease.expires).ToLocalTime().ToString('HH:mm')
        $who = if ($Open.lease.holderHere) { 'an earlier ObsidiNote on this PC still holds this vault' } else { 'another ObsidiNote is writing in this vault' }
        return @{ status = 'WARN'; detail = "$($Open.vault.name): read only, $who (until $until at the latest); $pages pages, $topics topics; $done"; hint = 'Close the other ObsidiNote to add here; this one takes over when its lease ends.' }
    }
    @{ status = 'OK'; detail = "$($Open.vault.name) ($pages pages, $topics topics); $done; this ObsidiNote is the writer"; hint = '' }
}

Export-ModuleMember -Function Get-LeaseTimings, Select-StartVault, Join-ActiveVault, Get-NotebookToSelect, Find-StartVault,ConvertTo-VaultRecord, ConvertTo-LeaseRecord, Get-VaultRecordFor, Open-VaultSession, Update-SessionLease, Close-VaultSession, Format-VaultStatus
