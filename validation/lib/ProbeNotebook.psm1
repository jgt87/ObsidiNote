# OneNote for the validation kit: a small COM adapter (no [ref] arguments, so tests can fake it), the
# write guard that keeps every write inside ObsidiNote-Probe or ObsidiNote-Validation, and the
# write probes P1 (round trip), P1b (Meta size), P1c (links after a move or delete) and the P3 marker
# pages. Logic of probes/p1-roundtrip.ps1 (which is not shipped). Synthetic text only.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
# Functions that return a list write its items to the pipeline; callers collect them with @().
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')

$script:Ns = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$script:MarkerChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

function New-KitOneNote {
    <# OneNote's COM API behind plain methods. Throws when COM cannot be created. #>
    $com = New-Object -ComObject OneNote.Application
    $o = [pscustomobject]@{ Com = $com }
    $o | Add-Member ScriptMethod GetHierarchy { param([string]$Start, [int]$Scope) $x = ''; $this.Com.GetHierarchy($Start, $Scope, [ref]$x); $x }
    $o | Add-Member ScriptMethod OpenHierarchy { param([string]$Path, [string]$Rel, [int]$Type) $x = ''; $this.Com.OpenHierarchy($Path, $Rel, [ref]$x, $Type); $x }
    $o | Add-Member ScriptMethod CreateNewPage { param([string]$SectionId) $x = ''; $this.Com.CreateNewPage($SectionId, [ref]$x, 1); $x }
    $o | Add-Member ScriptMethod UpdatePageContent { param([string]$Xml) $this.Com.UpdatePageContent($Xml) }
    $o | Add-Member ScriptMethod UpdateHierarchy { param([string]$Xml) $this.Com.UpdateHierarchy($Xml) }
    $o | Add-Member ScriptMethod GetPageContent { param([string]$Id) $x = ''; $this.Com.GetPageContent($Id, [ref]$x, 0); $x }
    $o | Add-Member ScriptMethod DeleteHierarchy { param([string]$Id) $this.Com.DeleteHierarchy($Id) }
    $o | Add-Member ScriptMethod GetHyperlinkToObject { param([string]$Id) $x = ''; $this.Com.GetHyperlinkToObject($Id, '', [ref]$x); $x }
    $o | Add-Member ScriptMethod SyncHierarchy { param([string]$Id) $this.Com.SyncHierarchy($Id) }
    $o | Add-Member ScriptMethod NavigateToUrl { param([string]$Url) $this.Com.NavigateToUrl($Url, $false) }
    $o | Add-Member ScriptMethod NavigateTo { param([string]$Id) $this.Com.NavigateTo($Id, '', $false) }
    $o | Add-Member ScriptMethod CurrentPageId { try { "$($this.Com.Windows.CurrentWindow.CurrentPageId)" } catch { '' } }
    $o
}

function Read-KitXml([string]$Xml) { if (-not $Xml) { return $null }; try { [xml]$d = $Xml; return $d } catch { return $null } }

function Get-KitHierarchyIds {
    <# Every object id in a hierarchy XML (the root and everything below it). Pure. #>
    param([string]$Xml)
    $d = Read-KitXml $Xml
    if (-not $d) { return }
    @($d.SelectNodes('//*[@ID]') | ForEach-Object { $_.GetAttribute('ID') })
}

function Find-KitNotebook {
    <# The open notebook called $Name (name or nickname): @{ id; path } or $null. Pure. #>
    param([string]$Xml, [string]$Name)
    $d = Read-KitXml $Xml
    if (-not $d) { return $null }
    foreach ($n in @($d.SelectNodes("//*[local-name()='Notebook']"))) {
        if ($n.GetAttribute('name') -ceq $Name -or $n.GetAttribute('nickname') -ceq $Name) { return [pscustomobject]@{ id = $n.GetAttribute('ID'); path = $n.GetAttribute('path') } }
    }
    $null
}

function Get-KitBasePath {
    <# Where a new notebook goes: -BasePath, else the folder of the first open cloud notebook. Pure. #>
    param([string]$Xml, [string]$BasePath = '')
    if ($BasePath) { return $BasePath.TrimEnd('/', '\') + '/' }
    $d = Read-KitXml $Xml
    if ($d) {
        foreach ($n in @($d.SelectNodes("//*[local-name()='Notebook']"))) {
            $p = $n.GetAttribute('path')
            if ($p -match '^(?i)https://') { return $p.Substring(0, $p.TrimEnd('/').LastIndexOf('/') + 1) }
        }
    }
    throw 'No notebook in OneDrive or SharePoint is open. Open one in OneNote first, or pass -ProbeBasePath with your OneDrive Documents address.'
}

function Open-ProbeNotebook {
    <# Opens (or creates) the kit's own notebook and returns its write guard. Only ObsidiNote-Probe
       and ObsidiNote-Validation are accepted. #>
    param([Parameter(Mandatory)]$One, [Parameter(Mandatory)][string]$Name, [string]$BasePath = '')
    if (-not (Test-KitNameAllowed $Name)) { throw "Write refused: the kit writes only into ObsidiNote-Probe or ObsidiNote-Validation, not '$Name'." }
    $xml = $One.GetHierarchy('', 2)
    $nb = Find-KitNotebook -Xml $xml -Name $Name
    $created = $false
    if ($nb) { $id = $nb.id }
    else {
        $id = $One.OpenHierarchy((Get-KitBasePath -Xml $xml -BasePath $BasePath) + $Name, '', 1)
        $created = $true
    }
    New-ProbeGuard -One $One -RootId $id -RootName $Name -Created $created
}

function New-ProbeGuard {
    param([Parameter(Mandatory)]$One, [Parameter(Mandatory)][string]$RootId, [Parameter(Mandatory)][string]$RootName, [bool]$Created = $false)
    if (-not (Test-KitNameAllowed $RootName)) { throw "Write refused: the kit writes only into ObsidiNote-Probe or ObsidiNote-Validation, not '$RootName'." }
    [pscustomobject]@{ One = $One; RootId = $RootId; RootName = $RootName; Created = $Created; Writes = (New-Object System.Collections.Generic.List[string]) }
}

function Assert-ProbeTarget {
    <# Throws unless $Id is the kit notebook or inside it (checked against OneNote's hierarchy). #>
    param([Parameter(Mandatory)]$Guard, [string]$Id)
    if (-not $Id) { throw 'Write refused: no target.' }
    if ($Id -eq $Guard.RootId) { return }
    $ids = @(Get-KitHierarchyIds ($Guard.One.GetHierarchy($Guard.RootId, 4)))
    if ($ids -notcontains $Id) { throw "Write refused: the target is not inside $($Guard.RootName)." }
}

function Get-PageIdFromXml([string]$Xml) {
    $d = Read-KitXml $Xml
    if (-not $d -or $d.DocumentElement.LocalName -ne 'Page') { return '' }
    $d.DocumentElement.GetAttribute('ID')
}

function Add-ProbeSection {
    <# Opens or creates section $Name directly in the kit notebook. #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$Name)
    $Guard.Writes.Add("section:$($Guard.RootId)")
    $Guard.One.OpenHierarchy("$Name.one", $Guard.RootId, 3)
}

function New-ProbePage {
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$SectionId)
    Assert-ProbeTarget $Guard $SectionId
    $Guard.Writes.Add("page:$SectionId")
    $Guard.One.CreateNewPage($SectionId)
}

function Set-ProbePageXml {
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$Xml)
    $id = Get-PageIdFromXml $Xml
    Assert-ProbeTarget $Guard $id
    $Guard.Writes.Add("update:$id")
    $Guard.One.UpdatePageContent($Xml)
}

function Remove-ProbeObject {
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$Id)
    if ($Id -eq $Guard.RootId) { throw 'Write refused: the kit never deletes its notebook itself.' }
    Assert-ProbeTarget $Guard $Id
    $Guard.Writes.Add("delete:$Id")
    $Guard.One.DeleteHierarchy($Id)
}

function Move-ProbePage {
    <# Moves a page into another section of the kit notebook (UpdateHierarchy with the target
       section's page list plus the page). OneNote may refuse; the caller checks the result. #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$PageId, [Parameter(Mandatory)][string]$SectionId)
    Assert-ProbeTarget $Guard $PageId
    Assert-ProbeTarget $Guard $SectionId
    [xml]$d = $Guard.One.GetHierarchy($SectionId, 4)
    $p = $d.CreateElement('one', 'Page', $script:Ns)
    $p.SetAttribute('ID', $PageId)
    $null = $d.DocumentElement.AppendChild($p)
    $Guard.Writes.Add("move:$PageId")
    $Guard.One.UpdateHierarchy($d.OuterXml)
}

function Get-ProbeSectionPages {
    <# The pages of one section of the kit notebook: @(@{ id; title; created }). #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$SectionId)
    $d = Read-KitXml ($Guard.One.GetHierarchy($SectionId, 4))
    if (-not $d) { return }
    @($d.SelectNodes("//*[local-name()='Page']") | Where-Object { $_.GetAttribute('isInRecycleBin') -ne 'true' } | ForEach-Object {
            [pscustomobject]@{ id = $_.GetAttribute('ID'); title = $_.GetAttribute('name'); created = $_.GetAttribute('dateTime') } })
}

function Clear-ProbeSection {
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$SectionId)
    $n = 0
    foreach ($p in @(Get-ProbeSectionPages $Guard $SectionId)) { Remove-ProbeObject $Guard $p.id; $n++ }
    $n
}

function ConvertTo-KitCdata([string]$Text) { '<![CDATA[' + $Text.Replace(']]>', ']] >') + ']]>' }

function New-ProbeOutline([string]$Role, [string[]]$Lines, [string]$ObjectId = '') {
    $idAttr = if ($ObjectId) { " objectID=""$ObjectId""" } else { '' }
    $oes = (@($Lines | ForEach-Object { '<one:OE><one:T>' + (ConvertTo-KitCdata $_) + '</one:T></one:OE>' }) -join '')
    "<one:Outline$idAttr><one:Meta name=""obsn.role"" content=""$Role"" /><one:OEChildren>$oes</one:OEChildren></one:Outline>"
}

function New-ProbePageXml {
    <# Page XML: optional page Meta, a title and outlines (@(@{ role; lines; objectId })). #>
    param([Parameter(Mandatory)][string]$PageId, [string]$Title = '', [hashtable]$Meta = @{}, [object[]]$Outlines = @())
    $metaXml = (@($Meta.Keys | Sort-Object | ForEach-Object { "<one:Meta name=""$_"" content=""$([Security.SecurityElement]::Escape([string]$Meta[$_]))"" />" }) -join '')
    $titleXml = if ($Title) { '<one:Title><one:OE><one:T>' + (ConvertTo-KitCdata $Title) + '</one:T></one:OE></one:Title>' } else { '' }
    $outXml = (@($Outlines | ForEach-Object { New-ProbeOutline $_.role @($_.lines) $(if ($_.ContainsKey('objectId')) { $_.objectId } else { '' }) }) -join '')
    "<?xml version=""1.0""?><one:Page xmlns:one=""$script:Ns"" ID=""$PageId"">$metaXml$titleXml$outXml</one:Page>"
}

function New-KitMarker([string]$Prefix = 'OBSN-P3') {
    $r = New-Object Random
    $Prefix + '-' + (-join (1..6 | ForEach-Object { $script:MarkerChars[$r.Next($script:MarkerChars.Length)] }))
}

Export-ModuleMember -Function New-KitOneNote, Read-KitXml, Get-KitHierarchyIds, Find-KitNotebook, Get-KitBasePath, Open-ProbeNotebook, New-ProbeGuard,
    Assert-ProbeTarget, Get-PageIdFromXml, Add-ProbeSection, New-ProbePage, Set-ProbePageXml, Remove-ProbeObject, Move-ProbePage,
    Get-ProbeSectionPages, Clear-ProbeSection, New-ProbeOutline, New-ProbePageXml, New-KitMarker
