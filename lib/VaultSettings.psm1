# Vault settings kept in OneNote (operator, 2026-11-14): the settings that belong to a vault, not to a
# PC, live in one Meta tag `obsn.settings` (compact JSON) on the vault's `ObsidiNote` state page, next
# to the lease, so they follow the vault to every PC. At every start (and on a vault switch) the
# settings are checked: a missing key is added with its default; an existing value is NEVER set back
# to its default, also when it has the wrong type (then the default is used in memory only, and the
# stored value stays for the person or a newer version); keys this version does not know are kept.
# Writer only: a read-only session uses the values in memory and writes nothing.
#
# Kept local instead (config\obsidinote.local.json, needed before OneNote is open or per PC): uiPort,
# cdpPort, signIn, notebook, vaultId; the theme stays per PC in the browser (operator, 2026-11-14).
# Once: a local "internalHosts" fills the OneNote key when OneNote has none; it never replaces it.
# The interface's copy of the defaults (ui-src/src/model/vaultSettings.ts) is pinned to this table
# by tests/fixtures/vault-settings.json: change all three together. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'Vault.psm1')

$script:SettingsMeta = 'obsn.settings'

# key -> default and kind (hosts = list of host rules; choice = one of; flag = true/false; number =
# a whole number from min to max). Added 2026-11-14 (operator): relatedCount (Add, was fixed at 3),
# linkStaleDays (when Ask offers Update on a cited link page, was fixed at 90), askIncludeArchived,
# graphShowArchived (the defaults of Ask's checkbox and the graph's Filter).
$script:SettingDefs = [ordered]@{
    internalHosts      = @{ kind = 'hosts'; default = @() }
    graphView          = @{ kind = 'choice'; default = 'topics'; choices = @('topics', 'sources') }
    labelsHubsOnly     = @{ kind = 'flag'; default = $false }
    relatedCount       = @{ kind = 'number'; default = 3; min = 1; max = 10 }
    linkStaleDays      = @{ kind = 'number'; default = 90; min = 7; max = 730 }
    askIncludeArchived = @{ kind = 'flag'; default = $false }
    graphShowArchived  = @{ kind = 'flag'; default = $false }
    # Pages Ask may read for one answer (operator, 2026-11-14: default 20, up to 50; was fixed at 8).
    askMaxPages        = @{ kind = 'number'; default = 20; min = 1; max = 50 }
}

function Get-VaultSettingDefaults {
    <# @{ key = default } for every vault setting, in the table's order. #>
    $d = [ordered]@{}
    foreach ($k in $script:SettingDefs.Keys) { $d[$k] = $script:SettingDefs[$k].default }
    $d
}

function Test-VaultSettingValue {
    <# True when $Value is a valid value of setting $Key. Pure. #>
    param([Parameter(Mandatory)][string]$Key, $Value)
    if (-not $script:SettingDefs.Contains($Key)) { return $false }
    $def = $script:SettingDefs[$Key]
    switch ($def.kind) {
        'hosts' {
            if ($null -eq $Value) { return $false }
            foreach ($h in @($Value)) {
                if ($h -isnot [string] -or $h.Length -gt 253 -or $h -notmatch '^(\*\.|\.)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$') { return $false }
            }
            if (@($Value).Count -gt 200) { return $false }
            return $true
        }
        'choice' { return ($Value -is [string] -and $def.choices -contains $Value) }
        'flag' { return ($Value -is [bool]) }
        'number' { return (($Value -is [int] -or $Value -is [long]) -and $Value -ge $def.min -and $Value -le $def.max) }
    }
    $false
}

function ConvertFrom-SettingsValue {
    <# The stored JSON as an ordered table (unknown keys kept); empty for '' or invalid JSON. Pure. #>
    param([AllowEmptyString()][AllowNull()][string]$Value)
    $t = [ordered]@{}
    if (-not $Value) { return $t }
    try { $o = ConvertFrom-Json -InputObject $Value } catch { return $t }
    # The full type name: [pscustomobject] is PSObject, which a bare number, text or list can be too.
    if ($o -isnot [System.Management.Automation.PSCustomObject]) { return $t }
    foreach ($p in $o.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [array]) { $v = @($v) }
        $t[$p.Name] = $v
    }
    $t
}

function Test-SettingsValueReadable {
    <# False when a stored value holds something that is not a JSON object (cut-off JSON, a list, a
       bare text or number): such a value is never treated as "no settings yet" and never written
       over (code review 2026-11-15). True for nothing stored and for an object. Pure. #>
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if (-not "$Value".Trim()) { return $true }
    try { $o = ConvertFrom-Json -InputObject $Value } catch { return $false }
    # The full type name: [pscustomobject] is PSObject, which a bare number or text can be too.
    $o -is [System.Management.Automation.PSCustomObject]
}

$script:Unreadable = 'the settings stored in this vault could not be read'
# The one sentence for a refused change and for GET /api/settings (canChange false, message).
$script:UnreadableRefusal = 'The settings stored in this vault could not be read, so nothing was changed. They are left as they are in OneNote (the ObsidiNote page in 00 Index); the defaults are used until they are repaired.'
function Get-UnreadableSettingsMessage { $script:UnreadableRefusal }

function Read-VaultSettings {
    <# The values to use of any open vault, read only (the graph of a vault that is not the active
       one): a valid stored value, else the default; the defaults when nothing can be read. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId)
    try {
        $st = Get-VaultState -Adapter $Adapter -IndexSectionId $IndexSectionId
        if ($st) { return (Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue ([string]$st.meta[$script:SettingsMeta]))).effective }
    } catch { }
    Get-VaultSettingDefaults
}

function Get-VaultSettingsPlan {
    <# Compares the stored settings with the table. Returns @{ stored (ordered: what to write, the
       stored keys unchanged plus each missing key); added (keys added); effective (the values to use:
       a valid stored value, else the default); invalid (stored keys with a wrong value, kept as is) }.
       $Local: values from config\obsidinote.local.json that fill a MISSING key once (internalHosts).
       Pure. #>
    param([System.Collections.IDictionary]$Stored = @{}, [hashtable]$Local = @{})
    $out = [ordered]@{}
    foreach ($k in $Stored.Keys) { $out[$k] = $Stored[$k] }
    $added = @(); $invalid = @()
    $eff = [ordered]@{}
    foreach ($k in $script:SettingDefs.Keys) {
        $def = $script:SettingDefs[$k].default
        if (-not $out.Contains($k)) {
            $v = $def
            if ($Local.ContainsKey($k) -and (Test-VaultSettingValue -Key $k -Value $Local[$k]) -and @($Local[$k]).Count) { $v = $Local[$k] }
            $out[$k] = $v
            $added += $k
        }
        if (Test-VaultSettingValue -Key $k -Value $out[$k]) { $eff[$k] = $out[$k] }
        else { $eff[$k] = $def; $invalid += $k }
    }
    @{ stored = $out; added = $added; effective = $eff; invalid = $invalid }
}

function ConvertTo-SettingsValue {
    <# The ordered table as compact JSON; a list stays a list (also with one item or none). Pure. #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Settings)
    $o = [ordered]@{}
    foreach ($k in $Settings.Keys) {
        $v = $Settings[$k]
        if ($script:SettingDefs.Contains($k) -and $script:SettingDefs[$k].kind -eq 'hosts') { $o[$k] = [object[]]@($v | Where-Object { $null -ne $_ }) }
        else { $o[$k] = $v }
    }
    ConvertTo-Json -InputObject $o -Compress -Depth 6
}

function Sync-VaultSettings {
    <# The start's check (and a vault switch's): reads obsn.settings from the state page, adds every
       missing key with its default (as the writer), never changes an existing value. Returns
       @{ status (added|none|readonly|unreadable|failed); added; invalid; effective; message }.
       unreadable: something is stored that is not a settings object; it is left exactly as it is
       (nothing is written) and the defaults are used in memory. Never throws. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId, [bool]$Writer, [hashtable]$Local = @{})
    $r = @{ status = 'none'; added = @(); invalid = @(); effective = (Get-VaultSettingDefaults); message = '' }
    try {
        $st = Get-VaultState -Adapter $Adapter -IndexSectionId $IndexSectionId
        if (-not $st) { $r.status = 'failed'; $r.message = 'No state page in this vault.'; return $r }
        if (-not (Test-SettingsValueReadable ([string]$st.meta[$script:SettingsMeta]))) { $r.status = 'unreadable'; $r.message = $script:Unreadable; return $r }
        $plan = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue ([string]$st.meta[$script:SettingsMeta])) -Local $Local
        $r.effective = $plan.effective; $r.invalid = $plan.invalid; $r.added = $plan.added
        if (-not $plan.added.Count) { return $r }
        if (-not $Writer) { $r.status = 'readonly'; return $r }
        Write-ObsnPage -Adapter $Adapter -PageId $st.statePageId -Meta ([ordered]@{ $script:SettingsMeta = (ConvertTo-SettingsValue $plan.stored) })
        $r.status = 'added'
    } catch {
        $r.status = 'failed'; $r.message = $_.Exception.Message
    }
    $r
}

function Set-VaultSetting {
    <# Changes one setting (the person, in the window): validates, then rewrites obsn.settings with
       only that key changed (other and unknown keys kept). The caller checks the writer lease.
       Returns the new effective settings. Throws on an unknown key or a wrong value. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId, [Parameter(Mandatory)][string]$Key, $Value)
    if (-not $script:SettingDefs.Contains($Key)) { throw "Unknown setting '$Key'." }
    if ($script:SettingDefs[$Key].kind -eq 'hosts') {
        $Value = @(@($Value) | Where-Object { $null -ne $_ } | ForEach-Object { if ($_ -is [string]) { $_.Trim().ToLowerInvariant() } else { $_ } } | Where-Object { $_ -ne '' } | Select-Object -Unique)
    }
    if (-not (Test-VaultSettingValue -Key $Key -Value $Value)) {
        $def = $script:SettingDefs[$Key]
        if ($def.kind -eq 'number') { throw "That is not a valid value for '$Key': a whole number from $($def.min) to $($def.max)." }
        throw "That is not a valid value for '$Key'."
    }
    $st = Get-VaultState -Adapter $Adapter -IndexSectionId $IndexSectionId
    if (-not $st) { throw 'No state page in this vault.' }
    # Never rewrite everything over a value that cannot be read: the other settings would be lost.
    if (-not (Test-SettingsValueReadable ([string]$st.meta[$script:SettingsMeta]))) {
        throw $script:UnreadableRefusal
    }
    $plan = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue ([string]$st.meta[$script:SettingsMeta]))
    $plan.stored[$Key] = $Value
    Write-ObsnPage -Adapter $Adapter -PageId $st.statePageId -Meta ([ordered]@{ $script:SettingsMeta = (ConvertTo-SettingsValue $plan.stored) })
    (Get-VaultSettingsPlan -Stored $plan.stored).effective
}

function Format-VaultSettingsStatus {
    <# The start's status line, or $null when there is nothing to say. #>
    param($Result)
    if (-not $Result) { return $null }
    $names = ($Result.added -join ', ')
    switch ($Result.status) {
        'added' { return @{ status = 'OK'; detail = "settings added to the vault in OneNote with their defaults: $names"; hint = '' } }
        'readonly' { return @{ status = 'WARN'; detail = "settings missing in OneNote ($names); defaults used, not saved: this ObsidiNote is read only"; hint = 'The writer adds them at its next start.' } }
        'unreadable' { return @{ status = 'WARN'; detail = "$($script:Unreadable) and were left as they are; the defaults are used for this session"; hint = 'Nothing was changed in OneNote. Settings cannot be saved in the window until the stored value is repaired.' } }
        'failed' { return @{ status = 'WARN'; detail = "settings not checked: $($Result.message)"; hint = 'Defaults are used for this session.' } }
    }
    if (@($Result.invalid).Count) { return @{ status = 'WARN'; detail = "settings with a value ObsidiNote cannot use: $($Result.invalid -join ', ') (kept in OneNote; defaults used)"; hint = '' } }
    $null
}

Export-ModuleMember -Function Get-UnreadableSettingsMessage, Get-VaultSettingDefaults, Test-VaultSettingValue, ConvertFrom-SettingsValue, Test-SettingsValueReadable, Read-VaultSettings, Get-VaultSettingsPlan, ConvertTo-SettingsValue, Sync-VaultSettings, Set-VaultSetting, Format-VaultSettingsStatus
