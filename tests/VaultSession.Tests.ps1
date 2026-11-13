# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/VaultSession.psm1: which vault a start continues in, opening it (write root, lease, structure,
# index completeness), a second session running read only, lease renewal and giving it back.
# In-memory OneNote stand-in; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

Describe 'Select-StartVault' {
    $a = [pscustomobject]@{ vaultId = 'a1'; rootKind = 'notebook'; location = 'https://example.invalid/docs/Alpha/'; notebookId = '{N1}' }
    $b = [pscustomobject]@{ vaultId = 'b2'; rootKind = 'sectiongroup'; location = 'https://example.invalid/docs/Team/Wiki/'; notebookId = '{N2}' }
    $nbs = @([pscustomobject]@{ id = '{N1}'; location = 'https://example.invalid/docs/Alpha/' }, [pscustomobject]@{ id = '{N2}'; location = 'https://example.invalid/docs/Team/' })
    It 'takes the vault id on record first, then the notebook on record' {
        (Select-StartVault -Vaults @($a, $b) -RecordVaultId 'b2' -Record 'onenote:https://example.invalid/docs/Alpha/' -Notebooks $nbs).vault.vaultId | Should Be 'b2'
        $r = Select-StartVault -Vaults @($a, $b) -Record 'onenote:https://example.invalid/docs/Team/' -Notebooks $nbs
        $r.vault.vaultId | Should Be 'b2'
        $r.why | Should Be 'record-notebook'
    }
    It 'takes the only vault when the record names none of them, else none' {
        (Select-StartVault -Vaults @($a) -RecordVaultId 'gone').why | Should Be 'only'
        $r = Select-StartVault -Vaults @($a, $b) -RecordVaultId 'gone'
        $r.vault | Should BeNullOrEmpty
        $r.why | Should Be 'several'
        (Select-StartVault -Vaults @()).why | Should Be 'none'
    }
    It 'says in a status line what happened' {
        (Format-VaultStatus -Open $null -Why 'none').detail | Should Be 'no ObsidiNote vault is open'
        (Format-VaultStatus -Open $null -Why 'several' -VaultCount 2).status | Should Be 'WARN'
        (Format-VaultStatus -Open $null -Problem 'boom').detail | Should Match 'could not be opened: boom'
    }
}

Describe 'Opening a vault' {
    $w = New-SyntheticVault -SessionId 'first'
    It 'is the writer, with the guard set to the vault root and the index complete' {
        $w.open.mode | Should Be 'writer'
        $w.a.RootId | Should Be $w.v.rootId
        # The three synthetic pages were put in by hand, outside the app: missing once, then listed.
        $w.open.missing | Should Be 3
        $again = Open-VaultSession -Adapter $w.a -Vault $w.vaults[0] -SessionId 'first' -Vaults $w.vaults
        $again.missing | Should Be 0
        (Format-VaultStatus -Open $again).detail | Should Match 'Synthetic Vault \(3 pages, 4 topics\); index complete; this ObsidiNote is the writer'
    }
    It 'reports and repairs pages missing from the index' {
        $null = $w.f.AddPage($w.v.sectionIds['Notes'], 'Typed in OneNote', @{}, 1, 'by hand')
        $vaults = @(Get-VaultList -Adapter $w.a)
        $o = Open-VaultSession -Adapter $w.a -Vault $vaults[0] -SessionId 'first' -Vaults $vaults
        $o.missing | Should Be 1
        (Format-VaultStatus -Open $o).detail | Should Match '1 page was missing from the index and is now in the index \(on Unfiled'
        $unf = @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.meta.Contains('obsn.indexKey') -and $_.meta['obsn.indexKey'] -eq 'unfiled' })[0]
        $unf.meta['obsn.entries'] | Should Match 'Typed in OneNote'
    }
    It 'runs a second session read only, writing nothing but reading the index' {
        $a2 = New-GuardedOneNote -Inner $w.f
        $vaults = @(Get-VaultList -Adapter $a2)
        $before = $w.f.Writes.Count
        $o2 = Open-VaultSession -Adapter $a2 -Vault $vaults[0] -SessionId 'second' -Vaults $vaults
        $o2.mode | Should Be 'readonly'
        @($o2.model.pages.Keys).Count | Should Be 4
        $w.f.Writes.Count | Should Be $before
        (Format-VaultStatus -Open $o2).status | Should Be 'WARN'
    }
    It 'renews the lease, and gives it back on exit' {
        $l = Update-SessionLease -Adapter $w.a -Vault $w.open.vault -SessionId 'first' -Lease $w.open.lease
        $l.mode | Should Be 'writer'
        $l -is [hashtable] | Should Be $true
        Close-VaultSession -Adapter $w.a -Vault $w.open.vault -Lease $l | Should Be $true
        (Get-VaultState -Adapter $w.a -IndexSectionId $w.open.vault.indexSectionId).lease | Should Be ''
    }
    It 'keeps the record of a vault: its notebook''s onenote: link' {
        Get-VaultRecordFor -Vault $w.vaults[0] -ToRecord { param($p) "onenote:$p" } | Should Match '^onenote:https://example\.invalid/docs/Synthetic Vault/$'
    }
}
