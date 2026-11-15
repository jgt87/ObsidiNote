# Single writer per vault: a lease Meta tag (obsn.lease) on the vault's `ObsidiNote` state page.
# Value: {"s":"<session id>","e":"<expiry, UTC ISO>","a":"<acquired, UTC ISO>","m":"<machine mark>"}
# (m: 12 hex of a hash of the computer name, Get-MachineMark; never the name). A start takes the
# lease when it is empty, invalid or expired, renews its own, and runs read-only when another
# session holds a valid one. No lock file. PS 5.1, ASCII only. Writes nothing to disk.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'Vault.psm1')

$script:DefaultTtlSec = 120

function New-WriterSessionId { [guid]::NewGuid().ToString('N') }

function Format-LeaseTime { param([datetime]$Time) $Time.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }

function Get-MachineMark {
    <# A short mark of this computer for the lease: the first 12 hex characters of the SHA-256 of its
       name (upper case). Never the name itself: the lease is stored in the notebook, which may be
       shared. Tells "an earlier ObsidiNote on this PC" from "another PC". Pure for a given name. #>
    param([string]$Name = [Environment]::MachineName)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(([string]$Name).ToUpperInvariant())) } finally { $sha.Dispose() }
    (-join @($h | ForEach-Object { $_.ToString('x2') })).Substring(0, 12)
}

function ConvertTo-LeaseValue {
    param([Parameter(Mandatory)][string]$SessionId, [Parameter(Mandatory)][datetime]$Now, [int]$TtlSec = $script:DefaultTtlSec, [datetime]$Acquired = [datetime]::MinValue, [string]$Machine = (Get-MachineMark))
    $a = if ($Acquired -eq [datetime]::MinValue) { $Now } else { $Acquired }
    ConvertTo-CompactJson -Value ([ordered]@{ s = $SessionId; e = (Format-LeaseTime $Now.AddSeconds($TtlSec)); a = (Format-LeaseTime $a); m = $Machine })
}

function ConvertFrom-LeaseValue {
    <# @{ session; expires (UTC DateTime); acquired; machine ('' for a lease written before the mark
       existed) } or $null for '' or an invalid value. Pure. #>
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if (-not $Value) { return $null }
    try { $o = ConvertFrom-Json -InputObject $Value } catch { return $null }
    $s = [string](Get-JsonProp $o 's' '')
    $e = [string](Get-JsonProp $o 'e' '')
    if (-not $s -or -not $e) { return $null }
    $sty = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    $exp = [datetime]::MinValue
    if (-not [datetime]::TryParse($e, [Globalization.CultureInfo]::InvariantCulture, $sty, [ref]$exp)) { return $null }
    $acq = $exp
    [void][datetime]::TryParse([string](Get-JsonProp $o 'a' ''), [Globalization.CultureInfo]::InvariantCulture, $sty, [ref]$acq)
    @{ session = $s; expires = $exp; acquired = $acq; machine = [string](Get-JsonProp $o 'm' '') }
}

function Get-LeaseDecision {
    <# 'acquire' (no valid lease), 'renew' (ours) or 'readonly' (another session's lease is valid). Pure.
       -NoOtherHere: the caller knows no other ObsidiNote runs on this computer (the start, after it
       replaced the one that was running). Then a valid lease of another session whose machine mark
       is this computer's ($Machine) is left over from a run that ended without giving it back, and is
       taken ('acquire'). A lease with another mark, or an old one without a mark, is never taken
       before it expires: the lease stays the single-writer mechanism between computers. #>
    param([AllowEmptyString()][AllowNull()][string]$Current, [Parameter(Mandatory)][string]$SessionId, [Parameter(Mandatory)][datetime]$Now, [switch]$NoOtherHere, [string]$Machine = (Get-MachineMark))
    $l = ConvertFrom-LeaseValue $Current
    if (-not $l) { return 'acquire' }
    if ($l.session -eq $SessionId) { return 'renew' }
    if ($l.expires -le $Now.ToUniversalTime()) { return 'acquire' }
    if ($NoOtherHere -and $Machine -and $l.machine -eq $Machine) { return 'acquire' }
    'readonly'
}

function Request-WriterLease {
    <# Takes or renews the vault's writer lease. Reads the state page, decides, writes obsn.lease, then
       reads it back: if another session's value is there (it wrote at the same time), this one is
       read-only. -NoOtherHere: see Get-LeaseDecision (only the start passes it). Returns @{ mode
       (writer|readonly); sessionId; holder; expires; acquired (UTC, when the holder took it);
       holderHere (the lease is held by another session of this computer); statePageId }. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId,
        [Parameter(Mandatory)][string]$SessionId, [int]$TtlSec = $script:DefaultTtlSec, [datetime]$Now = [datetime]::UtcNow,
        [switch]$NoOtherHere, [string]$Machine = (Get-MachineMark)
    )
    $st = Get-VaultState -Adapter $Adapter -IndexSectionId $IndexSectionId
    if (-not $st) { throw 'No state page in this vault.' }
    $d = Get-LeaseDecision -Current $st.lease -SessionId $SessionId -Now $Now -NoOtherHere:$NoOtherHere -Machine $Machine
    if ($d -ne 'readonly') {
        $old = ConvertFrom-LeaseValue $st.lease
        $acq = if ($d -eq 'renew' -and $old) { $old.acquired } else { $Now }
        Write-ObsnPage -Adapter $Adapter -PageId $st.statePageId -Meta ([ordered]@{ 'obsn.lease' = (ConvertTo-LeaseValue -SessionId $SessionId -Now $Now -TtlSec $TtlSec -Acquired $acq -Machine $Machine) })
        $st = Get-VaultState -Adapter $Adapter -IndexSectionId $IndexSectionId
    }
    $l = ConvertFrom-LeaseValue $st.lease
    $mine = [bool]($l -and $l.session -eq $SessionId)
    [pscustomobject]@{
        mode = $(if ($mine) { 'writer' } else { 'readonly' }); sessionId = $SessionId
        holder = $(if ($l) { $l.session } else { '' }); expires = $(if ($l) { $l.expires } else { [datetime]::MinValue })
        acquired = $(if ($l) { $l.acquired } else { [datetime]::MinValue })
        holderHere = [bool]($l -and -not $mine -and $Machine -and $l.machine -eq $Machine)
        statePageId = $st.statePageId; indexSectionId = $IndexSectionId
    }
}

function Test-WriterLease {
    <# True when $Lease (from Request-WriterLease) is a writer lease that has not expired. #>
    param($Lease, [datetime]$Now = [datetime]::UtcNow)
    [bool]($Lease -and $Lease.mode -eq 'writer' -and ([datetime]$Lease.expires).ToUniversalTime() -gt $Now.ToUniversalTime())
}

function Clear-WriterLease {
    <# Gives the lease back on exit (only when it is still ours). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)]$Lease)
    $st = Get-VaultState -Adapter $Adapter -IndexSectionId $Lease.indexSectionId
    $l = ConvertFrom-LeaseValue $st.lease
    if ($l -and $l.session -eq $Lease.sessionId) {
        Write-ObsnPage -Adapter $Adapter -PageId $st.statePageId -Meta ([ordered]@{ 'obsn.lease' = '' })
        return $true
    }
    $false
}

Export-ModuleMember -Function New-WriterSessionId, Get-MachineMark, ConvertTo-LeaseValue, ConvertFrom-LeaseValue, Get-LeaseDecision, Request-WriterLease, Test-WriterLease, Clear-WriterLease
