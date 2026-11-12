# What the interface shows of the notebooks open in OneNote (FEASIBILITY.md, "Connected notebooks"
# and "Several ObsidiNote vaults"): the list for the switcher, ObsidiNote vaults first, and for one
# notebook its sections and section groups with page counts and the most recently changed pages
# with their onenote: links. READ ONLY: GetHierarchy and GetHyperlinkToObject only; nothing is
# written to any notebook or to disk, and titles only go to the local interface, never to a log.
# Thin on purpose (interface step 1): a vault is "a notebook with a section named 00 Index"; the
# real detection (state page, obsn.vaultId, vaults in section groups) replaces this, and
# lib/Server.psm1 reads notebooks through one function (Read-NotebookData) so it can be swapped.
# The parsing is pure (ConvertTo-* take the XML), and the COM reads are parameters (-GetXml,
# -GetLink, -GetState), so the tests run without OneNote. Keep this file ASCII: PS 5.1 reads
# BOM-less files as ANSI.
Set-StrictMode -Version 2.0

$script:IndexSection = '00 Index'

function Get-NotebookLocationLabel {
    <# Where a notebook lives, for display: OneDrive, SharePoint or this PC. The path itself is
       never sent to the interface. #>
    [CmdletBinding()]
    param([string]$Path)
    if ($Path -match '^(?i)https?://[^/]*sharepoint\.[^/]+/sites/') { return 'SharePoint' }
    if ($Path -match '^(?i)https?://') { return 'OneDrive' }
    if ($Path) { return 'this PC' }
    ''
}

function Test-RecordMatchesPath {
    <# Whether the notebook record ("notebook" setting: onenote:https://... or a .onetoc2/.one path)
       points at the notebook whose GetHierarchy path is $Path. Pure. #>
    [CmdletBinding()]
    param([string]$Record, [string]$Path)
    if (-not $Record -or -not $Path) { return $false }
    $p = $Path.TrimEnd('/', '\')
    if ($Record -match '^(?i)onenote:(https?://.*)$') { return [string]::Equals($Matches[1].TrimEnd('/', '\'), $p, [StringComparison]::OrdinalIgnoreCase) }
    $r = $Record.TrimEnd('/', '\')
    if ($r -match '(?i)\.(onetoc2|one)$') { $r = $r.Substring(0, [Math]::Max(0, $r.LastIndexOfAny([char[]]@('\', '/')))) }
    [string]::Equals($r, $p, [StringComparison]::OrdinalIgnoreCase)
}

function Test-InRecycleBin($Node) {
    <# True for OneNote's recycle bin (section group isRecycleBin, section isDeletedPages, or any
       node flagged isInRecycleBin). #>
    foreach ($a in 'isRecycleBin', 'isInRecycleBin', 'isDeletedPages') {
        if ("$($Node.GetAttribute($a))" -eq 'true') { return $true }
    }
    $false
}

function Get-SectionPages($Section) {
    , @($Section.ChildNodes | Where-Object { $_.LocalName -eq 'Page' -and -not (Test-InRecycleBin $_) })
}

function ConvertTo-SectionTree($Parent, [string]$Prefix, [Collections.Generic.List[object]]$AllPages) {
    <# The sections and section groups under $Parent in OneNote's order; collects every page with
       its section path in $AllPages. #>
    $out = New-Object Collections.Generic.List[object]
    foreach ($n in @($Parent.ChildNodes)) {
        if ($n.NodeType -ne 'Element' -or (Test-InRecycleBin $n)) { continue }
        $name = "$($n.GetAttribute('name'))"
        $path = if ($Prefix) { "$Prefix / $name" } else { $name }
        if ($n.LocalName -eq 'Section') {
            $pages = Get-SectionPages $n
            foreach ($p in $pages) { $AllPages.Add([pscustomobject]@{ node = $p; section = $path }) }
            $out.Add([pscustomobject]@{ name = $name; kind = 'section'; pages = $pages.Count; children = @() })
        } elseif ($n.LocalName -eq 'SectionGroup') {
            $kids = ConvertTo-SectionTree $n $path $AllPages   # one array (the function returns it whole)
            $count = 0
            foreach ($k in $kids) { $count += [int]$k.pages }
            $out.Add([pscustomobject]@{ name = $name; kind = 'group'; pages = $count; children = $kids })
        }
    }
    , $out.ToArray()
}

function Read-HierarchyXml([string]$Xml) {
    if (-not $Xml) { return $null }
    try { [xml]$doc = $Xml; return $doc } catch { return $null }
}

function Get-NotebookNodes($Doc) { , @($Doc.SelectNodes("//*[local-name()='Notebook']")) }

function Test-VaultNode($Node) {
    <# Step-1 vault check: a section named 00 Index directly in the notebook. #>
    foreach ($c in @($Node.ChildNodes)) {
        if ($c.NodeType -eq 'Element' -and $c.LocalName -eq 'Section' -and "$($c.GetAttribute('name'))" -eq $script:IndexSection -and -not (Test-InRecycleBin $c)) { return $true }
    }
    $false
}

function ConvertTo-NotebookSummary($Node) {
    $nick = "$($Node.GetAttribute('nickname'))".Trim()
    [pscustomobject]@{
        id       = "$($Node.GetAttribute('ID'))"
        name     = $(if ($nick) { $nick } else { "$($Node.GetAttribute('name'))" })
        vault    = [bool](Test-VaultNode $Node)
        active   = $false
        location = (Get-NotebookLocationLabel "$($Node.GetAttribute('path'))")
    }
}

function ConvertTo-NotebookList {
    <# The notebooks open in OneNote, from GetHierarchy XML with sections (scope hsSections or
       deeper): @( @{ id; name; vault; active; location } ). Vaults first, then the other
       (read-only) notebooks, each in OneNote's order. active marks the vault on $Record, else the
       first vault. Writes the items to the pipeline: callers wrap the call in @(). Pure. #>
    [CmdletBinding()]
    param([string]$Xml, [string]$Record = '')
    $doc = Read-HierarchyXml $Xml
    if (-not $doc) { return }
    $vaults = @(); $others = @(); $activeId = ''
    foreach ($n in (Get-NotebookNodes $doc)) {
        $s = ConvertTo-NotebookSummary $n
        if ($s.vault) {
            $vaults += $s
            if (-not $activeId -and (Test-RecordMatchesPath $Record "$($n.GetAttribute('path'))")) { $activeId = $s.id }
        } else { $others += $s }
    }
    if (-not $activeId -and $vaults.Count) { $activeId = $vaults[0].id }
    foreach ($v in $vaults) { $v.active = ($v.id -eq $activeId) }
    @($vaults + $others)
}

function New-EmptyNotebookView([string]$Message, [bool]$NotFound = $false) {
    [pscustomobject]@{ available = $false; notFound = $NotFound; message = $Message; notebook = $null; sections = @(); totals = [pscustomobject]@{ sections = 0; pages = 0 }; recent = @() }
}

function ConvertTo-NotebookView {
    <# The view of the notebook with ID $Id from GetHierarchy XML (scope hsPages): @{ available;
       notFound; message; notebook = @{ id; name; vault; active; location }; sections;
       totals = @{ sections; pages }; recent = @( @{ title; section; modified; link } ) }.
       -GetLink { param($pageId) } returns the page's onenote: link ('' when none); only onenote:
       links are passed on. Pure. #>
    [CmdletBinding()]
    param([string]$Xml, [Parameter(Mandatory)][string]$Id, [int]$Recent = 10, [scriptblock]$GetLink = { param($id) '' })
    $doc = Read-HierarchyXml $Xml
    $nb = $null
    if ($doc) { foreach ($n in (Get-NotebookNodes $doc)) { if ("$($n.GetAttribute('ID'))" -eq $Id) { $nb = $n; break } } }
    if (-not $nb) { return New-EmptyNotebookView 'That notebook is not open in OneNote.' $true }

    $all = New-Object Collections.Generic.List[object]
    $tree = ConvertTo-SectionTree $nb '' $all
    $sectionCount = @($nb.SelectNodes(".//*[local-name()='Section']") | Where-Object { -not (Test-InRecycleBin $_) -and -not (Test-InRecycleBin $_.ParentNode) }).Count
    $latest = @($all | Sort-Object -Property @{ Expression = { "$($_.node.GetAttribute('lastModifiedTime'))" } } -Descending | Select-Object -First $Recent)
    $recentList = @(foreach ($p in $latest) {
        $link = "$(& $GetLink "$($p.node.GetAttribute('ID'))")"
        if ($link -notmatch '^(?i)onenote:') { $link = '' }
        $title = "$($p.node.GetAttribute('name'))".Trim()
        [pscustomobject]@{ title = $(if ($title) { $title } else { 'Untitled page' }); section = $p.section; modified = "$($p.node.GetAttribute('lastModifiedTime'))"; link = $link }
    })
    [pscustomobject]@{
        available = $true
        notFound  = $false
        message   = ''
        notebook  = (ConvertTo-NotebookSummary $nb)
        sections  = $tree
        totals    = [pscustomobject]@{ sections = $sectionCount; pages = $all.Count }
        recent    = $recentList
    }
}

function Get-VaultRecordFromXml {
    <# The record to keep for the vault with ID $Id ("notebook" setting): @{ ok; record; name;
       message }. Refuses a notebook that is not a vault. Pure except ConvertTo-NotebookRecord's
       look at a local folder. #>
    [CmdletBinding()]
    param([string]$Xml, [Parameter(Mandatory)][string]$Id, [scriptblock]$ToRecord)
    $doc = Read-HierarchyXml $Xml
    $nb = $null
    if ($doc) { foreach ($n in (Get-NotebookNodes $doc)) { if ("$($n.GetAttribute('ID'))" -eq $Id) { $nb = $n; break } } }
    if (-not $nb) { return [pscustomobject]@{ ok = $false; record = ''; name = ''; message = 'That notebook is not open in OneNote.' } }
    $name = (ConvertTo-NotebookSummary $nb).name
    if (-not (Test-VaultNode $nb)) { return [pscustomobject]@{ ok = $false; record = ''; name = $name; message = 'That notebook is not an ObsidiNote vault; it can only be read.' } }
    $rec = "$(& $ToRecord "$($nb.GetAttribute('path'))")"
    if (-not $rec) { return [pscustomobject]@{ ok = $false; record = ''; name = $name; message = 'Where this notebook is could not be worked out.' } }
    [pscustomobject]@{ ok = $true; record = $rec; name = $name; message = '' }
}

function Find-VaultInHierarchy {
    <# For the start (obsidinote.ps1, Start-OneNoteIfNeeded -FindNotebook): the vault to continue in,
       as @{ name; path } or $null. With a record: only the notebook on that record (the last active
       vault), so a start never switches vault by itself while the record's notebook opens. Without
       one: a notebook named ObsidiNote, else the first notebook with a 00 Index section. Pure. #>
    [CmdletBinding()]
    param([string]$Xml, [string]$Record = '', [string]$Name = 'ObsidiNote')
    $doc = Read-HierarchyXml $Xml
    if (-not $doc) { return $null }
    $nodes = Get-NotebookNodes $doc
    $pick = $null
    if ($Record) { $pick = @($nodes | Where-Object { Test-RecordMatchesPath $Record "$($_.GetAttribute('path'))" }) | Select-Object -First 1 }
    else {
        $pick = @($nodes | Where-Object { "$($_.GetAttribute('name'))" -eq $Name -or "$($_.GetAttribute('nickname'))" -eq $Name }) | Select-Object -First 1
        if (-not $pick) { $pick = @($nodes | Where-Object { Test-VaultNode $_ }) | Select-Object -First 1 }
    }
    if (-not $pick) { return $null }
    [pscustomobject]@{ name = (ConvertTo-NotebookSummary $pick).name; path = "$($pick.GetAttribute('path'))" }
}

# --- Live reads (OneNote COM, Windows PowerShell 5.1) -----------------------------------------

function New-OneNoteReader {
    <# The two COM reads, as scriptblocks over one OneNote.Application: @{ GetXml = { param($startId,
       $scope) }; GetLink = { param($pageId) } }. Read only: no other COM method is called. #>
    $on = New-Object -ComObject OneNote.Application
    @{
        GetXml  = { param($startId, [int]$scope) $x = ''; $on.GetHierarchy($startId, $scope, [ref]$x); $x }.GetNewClosure()
        GetLink = { param($id) $l = ''; try { $on.GetHyperlinkToObject($id, '', [ref]$l) } catch { $l = '' }; $l }.GetNewClosure()
    }
}

$script:NotRunning = 'OneNote is not running. Start OneNote, or start ObsidiNote again.'
$script:NoAnswer = 'OneNote did not answer. Check that OneNote is open, then try again.'

function Get-OpenNotebookList {
    <# The notebooks open in OneNote: @{ notebooks; message }. Never starts OneNote (-GetState
       'none' = not running: no COM call, as COM activation would start it). -GetXml replaces the
       COM read (tests). #>
    [CmdletBinding()]
    param([string]$Record = '', [scriptblock]$GetState, [scriptblock]$GetXml)
    $state = if ($GetState) { & $GetState } else { 'none' }
    if ($state -eq 'none') { return [pscustomobject]@{ notebooks = @(); message = $script:NotRunning } }
    try {
        if (-not $GetXml) { $GetXml = (New-OneNoteReader).GetXml }
        $xml = & $GetXml '' 3   # 3 = hsSections: enough to see 00 Index
    } catch { return [pscustomobject]@{ notebooks = @(); message = $script:NoAnswer } }
    $list = @(ConvertTo-NotebookList -Xml $xml -Record $Record)
    [pscustomobject]@{ notebooks = $list; message = $(if ($list.Count) { '' } else { 'No notebooks are open in OneNote.' }) }
}

function Get-NotebookView {
    <# The live view of one open notebook: -Id (an open notebook's id), or without it the active
       vault (the one on $Record, else the first). An id that is not an open notebook is never
       read (notFound). Never starts OneNote. -GetXml and -GetLink replace the COM reads (tests). #>
    [CmdletBinding()]
    param([string]$Id = '', [string]$Record = '', [scriptblock]$GetState, [scriptblock]$GetXml, [scriptblock]$GetLink)
    $state = if ($GetState) { & $GetState } else { 'none' }
    if ($state -eq 'none') { return New-EmptyNotebookView $script:NotRunning }
    try {
        if (-not $GetXml -or -not $GetLink) {
            $reader = New-OneNoteReader
            if (-not $GetXml) { $GetXml = $reader.GetXml }
            if (-not $GetLink) { $GetLink = $reader.GetLink }
        }
        $list = @(ConvertTo-NotebookList -Xml (& $GetXml '' 3) -Record $Record)
        $target = @(if ($Id) { $list | Where-Object { $_.id -eq $Id } } else { $list | Where-Object { $_.active } })
        if (-not $target.Count) {
            if ($Id) { return New-EmptyNotebookView 'That notebook is not open in OneNote.' $true }
            return New-EmptyNotebookView 'No ObsidiNote vault is open in OneNote.'
        }
        $xml = & $GetXml $target[0].id 4   # 4 = hsPages, this notebook only
    } catch { return New-EmptyNotebookView $script:NoAnswer }
    $view = ConvertTo-NotebookView -Xml $xml -Id $target[0].id -GetLink $GetLink
    if ($view.notebook) { $view.notebook.active = [bool]$target[0].active }
    $view
}

function Get-VaultRecord {
    <# The record of the open vault $Id (see Get-VaultRecordFromXml); live COM read unless -GetXml. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [scriptblock]$GetState, [scriptblock]$GetXml, [scriptblock]$ToRecord)
    $state = if ($GetState) { & $GetState } else { 'none' }
    if ($state -eq 'none') { return [pscustomobject]@{ ok = $false; record = ''; name = ''; message = $script:NotRunning } }
    try {
        if (-not $GetXml) { $GetXml = (New-OneNoteReader).GetXml }
        $xml = & $GetXml '' 3
    } catch { return [pscustomobject]@{ ok = $false; record = ''; name = ''; message = $script:NoAnswer } }
    Get-VaultRecordFromXml -Xml $xml -Id $Id -ToRecord $ToRecord
}

Export-ModuleMember -Function Get-NotebookLocationLabel, Test-RecordMatchesPath, ConvertTo-NotebookList, ConvertTo-NotebookView,
    Get-VaultRecordFromXml, Find-VaultInHierarchy, Get-OpenNotebookList, Get-NotebookView, Get-VaultRecord
