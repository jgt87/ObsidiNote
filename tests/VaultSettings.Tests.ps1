# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/VaultSettings.psm1: the vault's settings live in OneNote (obsn.settings on the state page).
# At every start missing keys are added with their defaults; an existing value is never set back
# (D-010). Synthetic data in the in-memory OneNote only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest', 'VaultSettings') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

# The defaults of the settings added after the first three, as stored (in the table's order).
$script:Rest = '"relatedCount":3,"linkStaleDays":90,"askIncludeArchived":false,"graphShowArchived":false,"askMaxPages":20'
$script:RestKeys = 'relatedCount,linkStaleDays,askIncludeArchived,graphShowArchived,askMaxPages'

function Get-StoredSettings($W) {
    $st = Get-VaultState -Adapter $W.a -IndexSectionId $W.open.vault.indexSectionId
    [string]$st.meta['obsn.settings']
}
function Set-StoredSettings($W, [string]$Json) {
    $st = Get-VaultState -Adapter $W.a -IndexSectionId $W.open.vault.indexSectionId
    $W.f.Nodes[$st.statePageId].meta['obsn.settings'] = $Json
}

Describe 'Get-VaultSettingsPlan (pure)' {
    It 'adds every key to an empty set with its default' {
        $p = Get-VaultSettingsPlan -Stored ([ordered]@{})
        ($p.added -join ',') | Should Be ('internalHosts,graphView,labelsHubsOnly,' + $script:RestKeys)
        $p.effective.relatedCount | Should Be 3
        $p.effective.linkStaleDays | Should Be 90
        $p.effective.graphView | Should Be 'topics'
        $p.effective.labelsHubsOnly | Should Be $false
    }
    It 'keeps every existing value and adds only what is missing' {
        $p = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue '{"graphView":"sources"}')
        ($p.added -join ',') | Should Be ('internalHosts,labelsHubsOnly,' + $script:RestKeys)
        $p.stored.graphView | Should Be 'sources'
        $p.effective.graphView | Should Be 'sources'
    }
    It 'keeps a key it does not know (from a newer version)' {
        $p = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue '{"futureKey":7}')
        $p.stored.futureKey | Should Be 7
    }
    It 'keeps a wrong value in OneNote and uses the default in memory' {
        $p = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue '{"graphView":"timeline","labelsHubsOnly":"yes","internalHosts":[]}')
        $p.stored.graphView | Should Be 'timeline'
        $p.effective.graphView | Should Be 'topics'
        ($p.invalid -join ',') | Should Be 'graphView,labelsHubsOnly'
        @($p.added | Where-Object { $_ -in 'graphView', 'labelsHubsOnly', 'internalHosts' }).Count | Should Be 0
    }
    It 'fills a missing internalHosts from the local setting once, never over a value in OneNote' {
        (Get-VaultSettingsPlan -Stored ([ordered]@{}) -Local @{ internalHosts = @('intranet.example.invalid') }).stored.internalHosts | Should Be 'intranet.example.invalid'
        $keep = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue '{"internalHosts":["wiki.example.invalid"]}') -Local @{ internalHosts = @('intranet.example.invalid') }
        (@($keep.stored.internalHosts) -join ',') | Should Be 'wiki.example.invalid'
        $empty = Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue '{"internalHosts":[]}') -Local @{ internalHosts = @('intranet.example.invalid') }
        @($empty.stored.internalHosts).Count | Should Be 0
    }
    It 'writes lists as lists, also with one item or none' {
        ConvertTo-SettingsValue ([ordered]@{ internalHosts = @('a.example.invalid') }) | Should Be '{"internalHosts":["a.example.invalid"]}'
        ConvertTo-SettingsValue ([ordered]@{ internalHosts = @() }) | Should Be '{"internalHosts":[]}'
    }
    It 'checks values by kind' {
        Test-VaultSettingValue -Key 'internalHosts' -Value @('*.example.invalid', '.corp.example.invalid') | Should Be $true
        Test-VaultSettingValue -Key 'internalHosts' -Value @('not a host') | Should Be $false
        Test-VaultSettingValue -Key 'graphView' -Value 'sources' | Should Be $true
        Test-VaultSettingValue -Key 'labelsHubsOnly' -Value 1 | Should Be $false
        Test-VaultSettingValue -Key 'nope' -Value 'x' | Should Be $false
        Test-VaultSettingValue -Key 'relatedCount' -Value 5 | Should Be $true
        Test-VaultSettingValue -Key 'relatedCount' -Value 0 | Should Be $false
        Test-VaultSettingValue -Key 'relatedCount' -Value 11 | Should Be $false
        Test-VaultSettingValue -Key 'relatedCount' -Value '5' | Should Be $false
        Test-VaultSettingValue -Key 'linkStaleDays' -Value ([long]30) | Should Be $true
        Test-VaultSettingValue -Key 'linkStaleDays' -Value 3 | Should Be $false
        Test-VaultSettingValue -Key 'graphShowArchived' -Value $true | Should Be $true
        Test-VaultSettingValue -Key 'askMaxPages' -Value 50 | Should Be $true
        Test-VaultSettingValue -Key 'askMaxPages' -Value 51 | Should Be $false
    }
}

Describe 'The start: settings in OneNote' {
    $w = New-SyntheticVault
    It 'adds the defaults to a new vault when it opens, and says so' {
        $w.open.settingsResult.status | Should Be 'added'
        (Format-VaultSettingsStatus $w.open.settingsResult).status | Should Be 'OK'
        Get-StoredSettings $w | Should Be ('{"internalHosts":[],"graphView":"topics","labelsHubsOnly":false,' + $script:Rest + '}')
    }
    It 'writes nothing at the next start when all are there (idempotent)' {
        $o = Open-VaultSession -Adapter $w.a -Vault $w.vaults[0] -SessionId 'session-one' -Vaults $w.vaults
        $o.settingsResult.status | Should Be 'none'
        Format-VaultSettingsStatus $o.settingsResult | Should Be $null
        # The opening also renews the lease on the same page, so count the settings check alone.
        $before = $w.f.Writes.Count
        $r = Sync-VaultSettings -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Writer $true
        $r.status | Should Be 'none'
        $w.f.Writes.Count | Should Be $before
    }
    It 'adds only the missing keys and never resets an existing one' {
        Set-StoredSettings $w '{"graphView":"sources","internalHosts":["wiki.example.invalid"],"futureKey":"x"}'
        $o = Open-VaultSession -Adapter $w.a -Vault $w.vaults[0] -SessionId 'session-one' -Vaults $w.vaults -LocalSettings @{ internalHosts = @('other.example.invalid') }
        ($o.settingsResult.added -join ',') | Should Be ('labelsHubsOnly,' + $script:RestKeys)
        Get-StoredSettings $w | Should Be ('{"graphView":"sources","internalHosts":["wiki.example.invalid"],"futureKey":"x","labelsHubsOnly":false,' + $script:Rest + '}')
        $o.settings.graphView | Should Be 'sources'
    }
    It 'a read-only start uses the defaults and writes nothing' {
        Set-StoredSettings $w ''
        $r = Sync-VaultSettings -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Writer $false
        $r.status | Should Be 'readonly'
        $r.effective.graphView | Should Be 'topics'
        Get-StoredSettings $w | Should Be ''
        (Format-VaultSettingsStatus $r).status | Should Be 'WARN'
    }
}

Describe 'Set-VaultSetting' {
    $w = New-SyntheticVault
    It 'changes one key and keeps the others, also unknown ones' {
        Set-StoredSettings $w '{"internalHosts":[],"graphView":"topics","labelsHubsOnly":false,"futureKey":1}'
        $eff = Set-VaultSetting -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Key 'internalHosts' -Value @(' Intranet.Example.Invalid ', 'intranet.example.invalid')
        (@($eff.internalHosts) -join ',') | Should Be 'intranet.example.invalid'
        Get-StoredSettings $w | Should Be ('{"internalHosts":["intranet.example.invalid"],"graphView":"topics","labelsHubsOnly":false,"futureKey":1,' + $script:Rest + '}')
        $eff2 = Set-VaultSetting -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Key 'relatedCount' -Value 5
        $eff2.relatedCount | Should Be 5
        { Set-VaultSetting -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Key 'linkStaleDays' -Value 1 } | Should Throw 'from 7 to 730'
    }
    It 'refuses an unknown key or a wrong value and writes nothing' {
        $before = Get-StoredSettings $w
        $writes = $w.f.Writes.Count
        { Set-VaultSetting -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Key 'theme' -Value 'dark' } | Should Throw 'Unknown setting'
        { Set-VaultSetting -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId -Key 'graphView' -Value 'timeline' } | Should Throw 'not a valid value'
        Get-StoredSettings $w | Should Be $before
        $w.f.Writes.Count | Should Be $writes
    }
}

Describe 'Stored settings that cannot be read are left alone (code review 2026-11-15)' {
    $w = New-SyntheticVault
    $sid = $w.open.vault.indexSectionId
    $cases = @(
        @{ name = 'cut-off JSON'; value = '{"graphView":"sources","internalHosts":["wiki.example.inv' },
        @{ name = 'a list instead of an object'; value = '["sources"]' },
        @{ name = 'a bare text'; value = '"sources"' },
        @{ name = 'a bare number'; value = '5' }
    )
    It 'tells a readable value from one that is not' {
        Test-SettingsValueReadable '' | Should Be $true
        Test-SettingsValueReadable '  ' | Should Be $true
        Test-SettingsValueReadable '{"graphView":"sources"}' | Should Be $true
        foreach ($c in $cases) { Test-SettingsValueReadable $c.value | Should Be $false }
    }
    foreach ($c in $cases) {
        It "the start writes no defaults over $($c.name), warns, and uses the defaults in memory" {
            Set-StoredSettings $w $c.value
            $writes = $w.f.Writes.Count
            $r = Sync-VaultSettings -Adapter $w.a -IndexSectionId $sid -Writer $true -Local @{ internalHosts = @('other.example.invalid') }
            $r.status | Should Be 'unreadable'
            Get-StoredSettings $w | Should Be $c.value
            $w.f.Writes.Count | Should Be $writes
            $r.effective.graphView | Should Be 'topics'
            @($r.effective.internalHosts).Count | Should Be 0
            $line = Format-VaultSettingsStatus $r
            $line.status | Should Be 'WARN'
            $line.detail | Should Match 'could not be read and were left as they are'
        }
        It "Set-VaultSetting refuses to rewrite $($c.name)" {
            Set-StoredSettings $w $c.value
            $writes = $w.f.Writes.Count
            { Set-VaultSetting -Adapter $w.a -IndexSectionId $sid -Key 'relatedCount' -Value 5 } | Should Throw 'could not be read, so nothing was changed'
            Get-StoredSettings $w | Should Be $c.value
            $w.f.Writes.Count | Should Be $writes
        }
    }
    It 'opening the vault (start or switch) leaves it alone too' {
        Set-StoredSettings $w '{"graphView":'
        $o = Open-VaultSession -Adapter $w.a -Vault $w.vaults[0] -SessionId 'session-one' -Vaults $w.vaults
        $o.settingsResult.status | Should Be 'unreadable'
        Get-StoredSettings $w | Should Be '{"graphView":'
        $o.settings.relatedCount | Should Be 3
    }
    It 'reads another vault''s values without writing (Read-VaultSettings)' {
        Set-StoredSettings $w '{"internalHosts":["wiki.example.invalid"]}'
        $writes = $w.f.Writes.Count
        (@((Read-VaultSettings -Adapter $w.a -IndexSectionId $sid).internalHosts) -join ',') | Should Be 'wiki.example.invalid'
        Set-StoredSettings $w '{"internalHosts":'
        @((Read-VaultSettings -Adapter $w.a -IndexSectionId $sid).internalHosts).Count | Should Be 0
        $w.f.Writes.Count | Should Be $writes
    }
}

Describe 'The interface''s copy of the settings' {
    It 'matches tests/fixtures/vault-settings.json' {
        $want = Get-Content -Raw (Join-Path $here 'fixtures\vault-settings.json') | ConvertFrom-Json
        $d = Get-VaultSettingDefaults
        (@($want.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should Be (@($d.Keys) -join ',')
        foreach ($k in @($d.Keys)) {
            if ($k -eq 'internalHosts') { @($want.internalHosts).Count | Should Be 0 }
            else { "${k}=$($want.$k)" | Should Be "${k}=$($d[$k])" }
        }
    }
}
