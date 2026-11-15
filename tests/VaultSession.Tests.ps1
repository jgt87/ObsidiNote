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

Describe 'Find-StartVault: the notebook on record is selected in OneNote only when its vault does not show' {
    # The in-memory OneNote answers a notebook in .Hidden without its sections until NavigateTo is
    # called with its id (what desktop OneNote does for a notebook that is not selected has not been
    # seen live). No test waits: -Sleep records the waits.
    $rec = 'onenote:https://example.invalid/docs/Synthetic Vault/'
    $new = {
        $w = New-SyntheticVault -SessionId 'first'
        $w.waits = New-Object System.Collections.ArrayList
        $w.sleep = { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        $w
    }
    It 'selects the notebook once, finds the vault and says so in one OK line' {
        $w = & $new; $waits = $w.waits
        $nb = [string]$w.open.vault.notebookId
        $w.f.Hidden[$nb] = 'sections'
        $writes = $w.f.Writes.Count
        $d = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        (@($w.f.Navigations) -join ',') | Should Be $nb
        $d.navigated | Should Be $true
        $d.tries | Should Be 1
        (@($waits) -join ',') | Should Be '2000'
        "$($d.status)|$($d.detail)" | Should Be 'OK|the notebook was selected in OneNote so its pages could be read'
        $d.pick.vault.vaultId | Should Be $w.v.vaultId
        $d.pick.why | Should Be 'record-id'
        @($d.vaults).Count | Should Be 1
        $w.f.Writes.Count | Should Be $writes
    }
    It 'does the same when the Index pages come without their Meta' {
        $w = & $new; $waits = $w.waits
        $w.f.Hidden[[string]$w.open.vault.notebookId] = 'meta'
        $d = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        $w.f.Navigations.Count | Should Be 1
        "$($d.status)|$($d.pick.why)" | Should Be 'OK|record-id'
    }
    It 'never selects anything when the vault is found at once, and has no status line then' {
        $w = & $new; $waits = $w.waits
        $d = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        $w.f.Navigations.Count | Should Be 0
        $waits.Count | Should Be 0
        "$($d.navigated)|$($d.tries)|[$($d.status)]" | Should Be 'False|0|[]'
        $d.pick.vault.vaultId | Should Be $w.v.vaultId
    }
    It 'stops after the bounded tries with a WARN and no exception when the notebook stays empty' {
        $w = & $new; $waits = $w.waits
        $nb = [string]$w.open.vault.notebookId
        $w.f.Hidden[$nb] = 'sections'
        $w.f.RevealOnNavigate = $false
        # made here, not inside the Should block: a closure only takes the variables of its own scope
        $sl = { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        { $script:d5 = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep $sl } | Should Not Throw
        $d = $script:d5
        (@($w.f.Navigations) -join ',') | Should Be $nb
        "$($d.navigated)|$($d.tries)|$($d.status)" | Should Be 'True|5|WARN'
        (@($waits) -join ',') | Should Be '2000,2000,2000,2000,2000'
        $d.detail | Should Be 'the notebook on record still shows no vault after selecting it in OneNote (5 checks)'
        $d.pick.vault | Should BeNullOrEmpty
        $d.pick.why | Should Be 'none'
        # the line holds no name, id or address
        "$($d.detail) $($d.hint)" | Should Not Match 'Synthetic|example\.invalid|\{'
    }
    It 'warns without an exception when OneNote refuses to select the notebook' {
        $w = & $new; $waits = $w.waits
        $w.f.Hidden[[string]$w.open.vault.notebookId] = 'sections'
        $w.f | Add-Member -Force ScriptMethod NavigateTo { param([string]$Id) $null = $this.Navigations.Add($Id); throw 'fake: 0x80042010' }
        $sl = { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        { $script:d6 = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep $sl } | Should Not Throw
        "$($script:d6.navigated)|$($script:d6.tries)|$($script:d6.status)" | Should Be 'False|0|WARN'
        $script:d6.detail | Should Match 'could not be selected'
        $waits.Count | Should Be 0
    }
    It 'selects nothing without both records, for a notebook that is closed, or one OneNote already shows' {
        $w = & $new; $waits = $w.waits
        $nb = [string]$w.open.vault.notebookId
        $w.f.Hidden[$nb] = 'sections'
        $sl = { param($ms) $null = $waits.Add($ms) }.GetNewClosure()
        $null = Find-StartVault -Adapter $w.a -RecordVaultId '' -Record $rec -Sleep $sl
        $null = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record '' -Sleep $sl
        $null = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record 'onenote:https://example.invalid/docs/Closed/' -Sleep $sl
        $w.f.Current = $nb
        $d = Find-StartVault -Adapter $w.a -RecordVaultId $w.v.vaultId -Record $rec -Sleep $sl
        $w.f.Navigations.Count | Should Be 0
        $waits.Count | Should Be 0
        $d.status | Should Be ''
    }
    It 'Get-NotebookToSelect (pure): only the notebook on record, only without a vault in it' {
        $nbs = @([pscustomobject]@{ id = 'N1'; location = 'https://example.invalid/docs/Alpha/' }, [pscustomobject]@{ id = 'N2'; location = 'https://example.invalid/docs/Team/' })
        $r = 'onenote:https://example.invalid/docs/Team/'
        (Get-NotebookToSelect -Vaults @() -Notebooks $nbs -RecordVaultId 'b2' -Record $r).id | Should Be 'N2'
        $other = [pscustomobject]@{ vaultId = 'a1'; notebookId = 'N1' }
        (Get-NotebookToSelect -Vaults @($other) -Notebooks $nbs -RecordVaultId 'b2' -Record $r).id | Should Be 'N2'
        # another vault lives in that notebook (a section group): OneNote does answer for it
        Get-NotebookToSelect -Vaults @([pscustomobject]@{ vaultId = 'c3'; notebookId = 'N2' }) -Notebooks $nbs -RecordVaultId 'b2' -Record $r | Should BeNullOrEmpty
        Get-NotebookToSelect -Vaults @([pscustomobject]@{ vaultId = 'b2'; notebookId = 'N9' }) -Notebooks $nbs -RecordVaultId 'b2' -Record $r | Should BeNullOrEmpty
        Get-NotebookToSelect -Vaults @() -Notebooks $nbs -RecordVaultId 'b2' -Record $r -CurrentId 'N2' | Should BeNullOrEmpty
    }
}

Describe 'The adapter''s navigation is not a write' {
    It 'passes NavigateTo through the guard without a write root, only for an open notebook' {
        $f = New-FakeOneNote
        $nb = $f.AddNotebook('Household')
        $sec = $f.AddSection($nb, 'Garden')
        $g = New-GuardedOneNote -Inner $f
        $g.NavigateTo($nb)
        (@($f.Navigations) -join ',') | Should Be $nb
        $g.GetCurrentNotebookId() | Should Be $nb
        { $g.NavigateTo($sec) } | Should Throw 'not an open notebook'
        { $g.NavigateTo('') } | Should Throw 'not an open notebook'
        $f.Navigations.Count | Should Be 1
        $f.Writes.Count | Should Be 0
    }
    It 'does nothing on the read-only stand-in' {
        $x = New-GuardedOneNote -Inner (New-XmlOneNoteAdapter -Xml '<one:Notebooks xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"><one:Notebook name="A" ID="{A}" path="https://example.invalid/docs/A/"/></one:Notebooks>')
        { $x.NavigateTo('{A}') } | Should Not Throw
        $x.GetCurrentNotebookId() | Should Be ''
    }
}
