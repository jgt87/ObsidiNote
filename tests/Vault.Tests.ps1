# Pester 3.4. Vaults (found by structure, not by name), the fixed structure, and the write guard:
# writes go only inside the active vault's root. In-memory OneNote stand-in; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')

function New-World {
    # A cloud notebook of the user's (foreign), with a group and a section.
    $f = New-FakeOneNote
    $nb = $f.AddNotebook('Household')
    $g = $f.AddGroup($nb, 'Garden'); $s = $f.AddSection($g, 'Beds')
    $null = $f.AddPage($s, 'Tomatoes', @{}, 1, 'user text')
    $f.AddRecycleBin($nb) | Out-Null
    $f
}

Describe 'A new vault' {
    $f = New-World
    $a = New-GuardedOneNote -Inner $f
    $r = New-ObsidiVault -Adapter $a -Name 'Team Wiki' -Year 2026
    It 'creates a notebook with the fixed sections, Journal/<year> and Archive' {
        $t = ConvertFrom-ObsnHierarchy -Xml ($f.GetHierarchy($r.rootId, 3)) -RootId $r.rootId
        @($t.sections | ForEach-Object { $_.full }) -join ',' | Should Be '00 Index,01 Inbox,Notes,Internal links,Web links,Sources,People,Projects,Meetings,Decisions,Files,Journal/2026'
        @($t.groups | ForEach-Object { $_.full }) -join ',' | Should Be 'Journal,Archive'
        $r.vaultCreated | Should Be $true
        $r.rootKind | Should Be 'notebook'
    }
    It 'writes a state page with schema, a unique vault id and the id counter' {
        $st = Get-VaultState -Adapter $a -IndexSectionId $r.indexSectionId
        $st.vaultId | Should Be $r.vaultId
        $st.vaultId | Should Match '^[0-9a-f-]{36}$'
        $st.schema | Should Be 1
        $st.idCounter | Should Be 1
    }
    It 'is idempotent: a second run creates nothing and keeps the vault id' {
        $before = $f.Writes.Count
        $r2 = Initialize-ObsidiVault -Adapter $a -RootId $r.rootId -Year 2026
        $r2.created.Count | Should Be 0
        $r2.vaultCreated | Should Be $false
        $r2.vaultId | Should Be $r.vaultId
        $f.Writes.Count | Should Be $before
    }
    It 'adds only what is missing and lists the user''s own sections without touching them' {
        $mine = $f.AddSection($r.rootId, 'My recipes')
        $null = $f.AddPage($mine, 'Soup', @{}, 1, 'mine')
        $f.DeleteHierarchy($r.sectionIds['People'])
        $before = $f.Writes.Count
        $r3 = Initialize-ObsidiVault -Adapter $a -RootId $r.rootId -Year 2027
        ($r3.created -join ',') | Should Be 'section People,section Journal/2027'
        ($r3.userSections -join ',') | Should Be 'My recipes'
        @($f.Writes | Select-Object -Skip $before | Where-Object { $_ -match [regex]::Escape($mine) }).Count | Should Be 0
    }
}

Describe 'Finding vaults by structure' {
    $f = New-World
    $a = New-GuardedOneNote -Inner $f
    $v1 = New-ObsidiVault -Adapter $a -Name 'Alpha' -Year 2026
    $hh = $f.FindByName('Household')
    $v2 = New-ObsidiVault -Adapter $a -Name 'Wiki' -InSectionGroupOf $hh -Year 2026
    # a notebook that only looks like one (00 Index without a state page) is not a vault
    $fake = $f.AddNotebook('Lookalike'); $null = $f.AddSection($fake, '00 Index')
    It 'finds a notebook vault and a section-group vault, whatever their names' {
        $list = @(Get-VaultList -Adapter $a)
        $list.Count | Should Be 2
        $n = @($list | Where-Object { $_.rootKind -eq 'notebook' })[0]
        $n.vaultId | Should Be $v1.vaultId; $n.name | Should Be 'Alpha'
        $g = @($list | Where-Object { $_.rootKind -eq 'sectiongroup' })[0]
        $g.vaultId | Should Be $v2.vaultId; $g.notebookName | Should Be 'Household'; $g.name | Should Be 'Wiki'
        $v1.vaultId | Should Not Be $v2.vaultId
    }
    It 'marks which open notebooks hold a vault' {
        $nbs = @(Get-NotebookList -Adapter $a)
        $nbs.Count | Should Be 3
        (@($nbs | Where-Object { $_.name -eq 'Alpha' })[0]).structured | Should Be $true
        $h = @($nbs | Where-Object { $_.name -eq 'Household' })[0]
        $h.structured | Should Be $false
        @($h.vaultIds) -join ',' | Should Be $v2.vaultId
        @((@($nbs | Where-Object { $_.name -eq 'Lookalike' })[0]).vaultIds).Count | Should Be 0
    }
    It 'continues in an existing vault from its state page' {
        $st = Get-VaultState -Adapter $a -IndexSectionId $v1.indexSectionId
        $f.Nodes[$st.statePageId].meta['obsn.idCounter'] = '42'
        $o = Open-ObsidiVault -Adapter $a -VaultId $v1.vaultId -Year 2026
        $o.vaultCreated | Should Be $false
        $a.RootId | Should Be $v1.rootId
        (Get-VaultState -Adapter $a -IndexSectionId $o.indexSectionId).idCounter | Should Be 42
    }
    It 'does not take over an open notebook of the same name that holds no vault' {
        { Initialize-ObsidiNotebook -Adapter $a -Name 'Household' } | Should Throw
        $x = Initialize-ObsidiNotebook -Adapter $a -Name 'Alpha' -Year 2026
        $x.vaultId | Should Be $v1.vaultId
    }
}

Describe 'Write guard' {
    $f = New-World
    $a = New-GuardedOneNote -Inner $f
    $hh = $f.FindByName('Household')
    $garden = $f.FindByName('Garden'); $beds = $f.FindByName('Beds'); $tomato = $f.FindByName('Tomatoes')
    $other = New-ObsidiVault -Adapter $a -Name 'Other' -Year 2026
    $sg = New-ObsidiVault -Adapter $a -Name 'Wiki' -InSectionGroupOf $hh -Year 2026
    $active = New-ObsidiVault -Adapter $a -Name 'Mine' -Year 2026
    It 'refuses every write when no vault is active' {
        $g = New-GuardedOneNote -Inner $f
        { $g.CreateNewPage($active.sectionIds['Notes']) } | Should Throw
    }
    It 'lets a write inside the active root through' {
        $a.RootId | Should Be $active.rootId
        $p = $a.CreateNewPage($active.sectionIds['Notes'])
        { $a.UpdatePageContent((New-ObsnPageXml -PageId $p -Title 'ok')) } | Should Not Throw
        { $a.DeleteHierarchy($p) } | Should Not Throw
        { $null = $a.OpenHierarchy('Notes 2.one', $active.rootId, 3) } | Should Not Throw
    }
    It 'refuses writes into a second vault' {
        { $a.CreateNewPage($other.sectionIds['Notes']) } | Should Throw
        { $a.UpdatePageContent((New-ObsnPageXml -PageId $other.statePageId -Meta @{ 'obsn.lease' = 'x' })) } | Should Throw
        { $a.DeleteHierarchy($other.statePageId) } | Should Throw
        { $a.OpenHierarchy('Extra.one', $other.rootId, 3) } | Should Throw
    }
    It 'refuses writes into a foreign notebook' {
        { $a.CreateNewPage($beds) } | Should Throw
        { $a.UpdatePageContent((New-ObsnPageXml -PageId $tomato -Title 'changed')) } | Should Throw
        { $a.DeletePageContent($tomato, '{OBJ-1}') } | Should Throw
        { $a.DeleteHierarchy($beds) } | Should Throw
        { $a.OpenHierarchy('New.one', $hh, 3) } | Should Throw
        $f.Nodes[$tomato].title | Should Be 'Tomatoes'
    }
    It 'refuses writes into a sibling section group outside a section-group root' {
        Set-OneNoteWriteRoot -Adapter $a -RootId $sg.rootId
        { $a.CreateNewPage($sg.sectionIds['Notes']) } | Should Not Throw
        { $a.CreateNewPage($beds) } | Should Throw
        { $a.OpenHierarchy('X.one', $garden, 3) } | Should Throw
        { $a.OpenHierarchy('X.one', $hh, 3) } | Should Throw
        { $a.DeleteHierarchy($sg.rootId) } | Should Throw
        Set-OneNoteWriteRoot -Adapter $a -RootId $active.rootId
    }
    It 'treats a vault in a section group of the active vault''s notebook as outside the root' {
        $inner = New-ObsidiVault -Adapter $a -Name 'Inner' -InSectionGroupOf $active.rootId -Year 2026
        Set-OneNoteWriteRoot -Adapter $a -RootId $active.rootId
        { $a.CreateNewPage($inner.sectionIds['Notes']) } | Should Throw
        { $a.UpdatePageContent((New-ObsnPageXml -PageId $inner.statePageId -Meta @{ 'obsn.lease' = 'x' })) } | Should Throw
        { $a.CreateNewPage($active.sectionIds['Notes']) } | Should Not Throw
        $t = ConvertFrom-ObsnHierarchy -Xml ($f.GetHierarchy($active.rootId, 4)) -RootId $active.rootId
        @($t.sections | Where-Object { $_.full -like 'Inner*' }).Count | Should Be 0
        @($t.nestedVaults | ForEach-Object { $_.name }) -join ',' | Should Be 'Inner'
        (Get-StructurePlan -Tree $t -Year 2026).userSections.Count | Should Be 0
    }
    It 'refuses a new notebook over an open one and update XML without a page id' {
        { $a.CreateNotebook('https://example.invalid/docs/Household') } | Should Throw
        { $a.UpdatePageContent('<x/>') } | Should Throw
        { $a.CreateSectionGroupIn($hh, 'Wiki') } | Should Throw
    }
}

Describe 'Setting up an empty notebook as a vault (user, 2026-11-13)' {
    $f = New-World
    $a = New-GuardedOneNote -Inner $f
    $empty = $f.AddNotebook('ObsidiNote'); $f.AddRecycleBin($empty) | Out-Null
    $blank = $f.AddNotebook('Blank'); $null = $f.AddSection($blank, 'New Section 1')
    $hh = $f.FindByName('Household')
    It 'counts a notebook without pages or groups as empty, and one with the person''s pages as not' {
        Test-EmptyNotebook -Adapter $a -NotebookId $empty | Should Be $true
        Test-EmptyNotebook -Adapter $a -NotebookId $blank | Should Be $true
        Test-EmptyNotebook -Adapter $a -NotebookId $hh | Should Be $false
    }
    It 'sets up the empty notebook in place: the notebook is the vault root, found by its state page' {
        $r = Initialize-EmptyNotebookVault -Adapter $a -NotebookId $empty -Year 2026
        $r.rootId | Should Be $empty
        $r.rootKind | Should Be 'notebook'
        $r.vaultCreated | Should Be $true
        $a.RootId | Should Be $empty
        $v = @(Get-VaultList -Adapter $a | Where-Object { $_.rootId -eq $empty })
        $v.Count | Should Be 1
        $v[0].vaultId | Should Be $r.vaultId
    }
    It 'refuses a notebook with the person''s pages, and one that already holds a vault, writing nothing' {
        $before = $f.Writes.Count
        { Initialize-EmptyNotebookVault -Adapter $a -NotebookId $hh -Year 2026 } | Should Throw
        { Initialize-EmptyNotebookVault -Adapter $a -NotebookId $empty -Year 2026 } | Should Throw
        $f.Writes.Count | Should Be $before
    }
}
