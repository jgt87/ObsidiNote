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

function ConvertTo-LeaseRecord {
    <# The plain record of a lease (Request-WriterLease result); $null stays $null. #>
    param($Lease)
    if (-not $Lease) { return $null }
    @{ mode = [string]$Lease.mode; sessionId = [string]$Lease.sessionId; holder = [string]$Lease.holder; expires = [datetime]$Lease.expires
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
       index is read and checked, nothing is written. Returns @{ vault (record); lease (record);
       model; missing (count); mode; written }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)]$Vault, [Parameter(Mandatory)][string]$SessionId, [object[]]$Vaults = $null, [int]$TtlSec = $script:LeaseTtlSec)
    Set-OneNoteWriteRoot -Adapter $Adapter -RootId $Vault.rootId
    $lease = Request-WriterLease -Adapter $Adapter -IndexSectionId $Vault.indexSectionId -SessionId $SessionId -TtlSec $TtlSec
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
    @{ vault = (ConvertTo-VaultRecord $Vault); lease = (ConvertTo-LeaseRecord $lease); model = $ix.model; missing = $missing; mode = $lease.mode; written = [bool]$ix.write }
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
        return @{ status = 'WARN'; detail = "$($Open.vault.name): read only, another ObsidiNote is writing in this vault (until $until at the latest); $pages pages, $topics topics; $done"; hint = 'Close the other ObsidiNote to add here; this one takes over when its lease ends.' }
    }
    @{ status = 'OK'; detail = "$($Open.vault.name) ($pages pages, $topics topics); $done; this ObsidiNote is the writer"; hint = '' }
}

Export-ModuleMember -Function Get-LeaseTimings, Select-StartVault, ConvertTo-VaultRecord, ConvertTo-LeaseRecord, Get-VaultRecordFor, Open-VaultSession, Update-SessionLease, Close-VaultSession, Format-VaultStatus
