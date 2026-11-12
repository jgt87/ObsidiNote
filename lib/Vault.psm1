# ObsidiNote vaults (FEASIBILITY.md, Several ObsidiNote vaults; Connected notebooks).
# A vault = a structure root (a whole notebook, or a top-level section group of a notebook) that
# holds the section `00 Index` with the `ObsidiNote` state page; the state page's Meta carries
# obsn.indexKey = state, obsn.schema and a unique obsn.vaultId. Vaults are found by that structure,
# never by the notebook's name. Exactly one vault is active: the guarded adapter's write root.
# PS 5.1, ASCII only. Writes nothing to disk.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')

$script:Schema = 1
$script:IndexSection = '00 Index'
$script:StateTitle = 'ObsidiNote'

function Get-ObsnSchemaVersion { $script:Schema }

function Get-ChildElements { param($Node, [string]$LocalName) @($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq $LocalName -and $_.GetAttribute('isRecycleBin') -ne 'true' -and $_.GetAttribute('isInRecycleBin') -ne 'true' }) }

function Find-StatePage {
    <# The state page in a parsed section (ConvertFrom-ObsnHierarchy section, or GetHierarchy XML of
       the 00 Index section at page scope): @{ id; meta } or $null. #>
    param([Parameter(Mandatory)][string]$SectionXml)
    [xml]$doc = $SectionXml
    foreach ($p in @($doc.SelectNodes("//*[local-name()='Page']"))) {
        if ($p.GetAttribute('isInRecycleBin') -eq 'true') { continue }
        $meta = @{}
        foreach ($m in @($p.ChildNodes)) { if ($m.NodeType -eq 'Element' -and $m.LocalName -eq 'Meta') { $meta[$m.GetAttribute('name')] = $m.GetAttribute('content') } }
        if ($meta['obsn.indexKey'] -eq 'state' -and $meta['obsn.vaultId']) { return @{ id = $p.GetAttribute('ID'); title = $p.GetAttribute('name'); meta = $meta } }
    }
    $null
}

function Find-VaultCandidates {
    <# Structure roots that hold a `00 Index` section: open notebooks and their top-level section
       groups. Pure, from GetHierarchy('', 3) XML. @(@{ rootId; rootKind; name; notebookId;
       notebookName; location; indexSectionId }). #>
    param([Parameter(Mandatory)][string]$Xml)
    [xml]$doc = $Xml
    $out = New-Object System.Collections.ArrayList
    foreach ($nb in @(Get-ChildElements $doc.DocumentElement 'Notebook')) {
        $nbName = $nb.GetAttribute('name')
        $ix = @(Get-ChildElements $nb 'Section' | Where-Object { $_.GetAttribute('name') -eq $script:IndexSection })
        if ($ix.Count) { $null = $out.Add(@{ rootId = $nb.GetAttribute('ID'); rootKind = 'notebook'; name = $nbName; notebookId = $nb.GetAttribute('ID'); notebookName = $nbName; location = $nb.GetAttribute('path'); indexSectionId = $ix[0].GetAttribute('ID') }) }
        foreach ($g in @(Get-ChildElements $nb 'SectionGroup')) {
            $gix = @(Get-ChildElements $g 'Section' | Where-Object { $_.GetAttribute('name') -eq $script:IndexSection })
            if ($gix.Count) { $null = $out.Add(@{ rootId = $g.GetAttribute('ID'); rootKind = 'sectiongroup'; name = $g.GetAttribute('name'); notebookId = $nb.GetAttribute('ID'); notebookName = $nbName; location = $g.GetAttribute('path'); indexSectionId = $gix[0].GetAttribute('ID') }) }
        }
    }
    @($out)
}

function Get-VaultList {
    <# Every ObsidiNote vault in the open notebooks (read only). One hierarchy read for the structure,
       plus one page-scope read per `00 Index` section found. Returns @(@{ vaultId; name; rootId;
       rootKind (notebook|sectiongroup); notebookId; notebookName; location; schema; statePageId;
       indexSectionId; pages; topics }). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter)
    $res = @(foreach ($c in @(Find-VaultCandidates ($Adapter.GetHierarchy('', 3)))) {
        $st = Find-StatePage ($Adapter.GetHierarchy($c.indexSectionId, 4))
        if (-not $st) { continue }
        $pages = 0; $topics = 0; $schema = 0
        [void][int]::TryParse([string]$st.meta['obsn.pageCount'], [ref]$pages)
        [void][int]::TryParse([string]$st.meta['obsn.topicCount'], [ref]$topics)
        [void][int]::TryParse([string]$st.meta['obsn.schema'], [ref]$schema)
        [pscustomobject]@{
            vaultId = $st.meta['obsn.vaultId']; name = $c.name; rootId = $c.rootId; rootKind = $c.rootKind
            notebookId = $c.notebookId; notebookName = $c.notebookName; location = $c.location
            schema = $schema; statePageId = $st.id; indexSectionId = $c.indexSectionId; pages = $pages; topics = $topics
        }
    })
    @($res)
}

function Get-NotebookList {
    <# Every notebook open in OneNote (read only): @(@{ name; id; location; cloud; structured
       (the notebook itself is a vault root); vaultIds (vaults inside it, root or section group) }). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [object[]]$Vaults = $null)
    if ($null -eq $Vaults) { $Vaults = @(Get-VaultList -Adapter $Adapter) }
    [xml]$doc = $Adapter.GetHierarchy('', 2)
    $res = @(foreach ($nb in @(Get-ChildElements $doc.DocumentElement 'Notebook')) {
        $id = $nb.GetAttribute('ID')
        $mine = @($Vaults | Where-Object { $_.notebookId -eq $id })
        [pscustomobject]@{
            name = $nb.GetAttribute('name'); id = $id; location = $nb.GetAttribute('path')
            cloud = ($nb.GetAttribute('path') -match '^(?i)https?://')
            structured = [bool](@($mine | Where-Object { $_.rootKind -eq 'notebook' }).Count)
            vaultIds = @($mine | ForEach-Object { $_.vaultId })
        }
    })
    @($res)
}

function New-VaultId { [guid]::NewGuid().ToString() }

function Get-VaultState {
    <# The state page's data: @{ statePageId; vaultId; schema; idCounter; lease; deleted; meta }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId)
    $st = Find-StatePage ($Adapter.GetHierarchy($IndexSectionId, 4))
    if (-not $st) { return $null }
    $c = [int64]1; [void][int64]::TryParse([string]$st.meta['obsn.idCounter'], [ref]$c)
    $s = 0; [void][int]::TryParse([string]$st.meta['obsn.schema'], [ref]$s)
    @{ statePageId = $st.id; vaultId = $st.meta['obsn.vaultId']; schema = $s; idCounter = $c; lease = [string]$st.meta['obsn.lease']; deleted = @(ConvertFrom-JsonList ([string]$st.meta['obsn.deleted'])); meta = $st.meta }
}

function Initialize-ObsidiVault {
    <# Makes sure the vault root $RootId (the guarded adapter's active root) has the fixed structure
       and a state page. Idempotent. A root without a state page gets one with a new obsn.vaultId
       (that is how a vault is born); an existing vault continues from its state page. Returns
       @{ rootId; vaultId; vaultCreated; statePageId; created; present; userSections; sectionIds }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$RootId, [int]$Year = (Get-Date).Year)
    if ($Adapter.PSObject.Properties['RootId'] -and $Adapter.RootId -ne $RootId) { throw 'Initialize-ObsidiVault: the root is not the active vault (Set-OneNoteWriteRoot first).' }
    $r = Install-ObsnStructure -Adapter $Adapter -RootId $RootId -Year $Year
    $ix = $r.sectionIds[$script:IndexSection]
    $state = Get-VaultState -Adapter $Adapter -IndexSectionId $ix
    $made = $false
    if (-not $state) {
        $spid = $Adapter.CreateNewPage($ix)
        $meta = [ordered]@{ 'obsn.indexKey' = 'state'; 'obsn.schema' = [string]$script:Schema; 'obsn.vaultId' = (New-VaultId); 'obsn.idCounter' = '1'; 'obsn.lease' = ''; 'obsn.deleted' = '[]'; 'obsn.pageCount' = '0'; 'obsn.topicCount' = '0' }
        $lines = @('ObsidiNote keeps its state on this page (vault id, id counter, who is writing). It is rewritten by the app; please do not edit it.')
        Write-ObsnPage -Adapter $Adapter -PageId $spid -Meta $meta -Title $script:StateTitle -Outlines @(@{ role = 'state'; lines = $lines }) -NewPage
        $r.created = @($r.created) + 'page 00 Index/ObsidiNote'
        $state = Get-VaultState -Adapter $Adapter -IndexSectionId $ix
        $made = $true
    }
    [pscustomobject]@{
        rootId = $RootId; vaultId = $state.vaultId; vaultCreated = $made; statePageId = $state.statePageId
        indexSectionId = $ix; created = @($r.created); present = @($r.present); userSections = @($r.userSections); sectionIds = $r.sectionIds
    }
}

function New-ObsidiVault {
    <# A new vault. Default: a new notebook $Name next to the first open cloud notebook (or in
       -Location). -InSectionGroupOf <notebook id>: a new top-level section group $Name inside that
       notebook becomes the root; the caller asks the user first (it writes into a notebook
       ObsidiNote does not own yet). Makes the new root the active write root. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$Name, [string]$Location = '', [string]$InSectionGroupOf = '', [int]$Year = (Get-Date).Year)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]*$') { throw "Vault name '$Name' has characters that cannot be used in a file name." }
    if ($InSectionGroupOf) { $rootId = $Adapter.CreateSectionGroupIn($InSectionGroupOf, $Name); $kind = 'sectiongroup' }
    else {
        $base = Get-NotebookBasePath -NotebooksXml ($Adapter.GetHierarchy('', 2)) -Location $Location
        try { $rootId = $Adapter.CreateNotebook($base + $Name) }
        catch {
            if ("$($_.Exception)" -match '0x80042006') { throw "OneNote could not create the notebook in that folder (file does not exist, 0x80042006). Create it in OneNote yourself, or pass -Location with a folder OneNote can create notebooks in." }
            throw
        }
        $kind = 'notebook'
    }
    Set-OneNoteWriteRoot -Adapter $Adapter -RootId $rootId
    $r = Initialize-ObsidiVault -Adapter $Adapter -RootId $rootId -Year $Year
    $r | Add-Member NoteProperty rootKind $kind
    $r
}

function Open-ObsidiVault {
    <# Makes a found vault the active one (write root) and brings its structure up to date (e.g. this
       year's Journal section). Continues from its state page. -VaultId or -RootId. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [string]$VaultId = '', [string]$RootId = '', [int]$Year = (Get-Date).Year, [object[]]$Vaults = $null)
    if ($null -eq $Vaults) { $Vaults = @(Get-VaultList -Adapter $Adapter) }
    $v = @($Vaults | Where-Object { ($VaultId -and $_.vaultId -eq $VaultId) -or ($RootId -and $_.rootId -eq $RootId) }) | Select-Object -First 1
    if (-not $v) { throw "Vault not found among the open notebooks ($(if ($VaultId) { $VaultId } else { $RootId }))." }
    Set-OneNoteWriteRoot -Adapter $Adapter -RootId $v.rootId
    $r = Initialize-ObsidiVault -Adapter $Adapter -RootId $v.rootId -Year $Year
    $r | Add-Member NoteProperty rootKind $v.rootKind
    $r | Add-Member NoteProperty name $v.name
    $r
}

function Initialize-ObsidiNotebook {
    <# Convenience for a start and for dev runs: continue in the vault whose root is the notebook
       $Name, or create that notebook as a new vault when no notebook of that name is open. A notebook
       of that name without a vault is not taken over (it throws; use New-ObsidiVault -InSectionGroupOf
       after asking the user). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [string]$Name = 'ObsidiNote', [string]$Location = '', [int]$Year = (Get-Date).Year)
    $vaults = @(Get-VaultList -Adapter $Adapter)
    $v = @($vaults | Where-Object { $_.rootKind -eq 'notebook' -and $_.notebookName -eq $Name }) | Select-Object -First 1
    if ($v) { return (Open-ObsidiVault -Adapter $Adapter -RootId $v.rootId -Year $Year -Vaults $vaults) }
    $open = @(Get-NotebookList -Adapter $Adapter -Vaults $vaults | Where-Object { $_.name -eq $Name })
    if ($open.Count) { throw "Notebook '$Name' is open but holds no ObsidiNote vault; it is not taken over." }
    New-ObsidiVault -Adapter $Adapter -Name $Name -Location $Location -Year $Year
}

Export-ModuleMember -Function Get-ObsnSchemaVersion, Find-StatePage, Find-VaultCandidates, Get-VaultList, Get-NotebookList, New-VaultId, Get-VaultState, Initialize-ObsidiVault, New-ObsidiVault, Open-ObsidiVault, Initialize-ObsidiNotebook
