# OneNote's API, every method: the catalogue (what each does, whether ObsidiNote uses it, what it
# could add) and the read-only probe that tries each read method on this computer (stage V2).
# FEASIBILITY.md "OneNote's API, every method" is the same list in words; tests/OneNoteApi.Tests.ps1
# keeps the two, and the code's own calls, in step.
# The probe never writes, never opens a dialog and never changes OneNote's window: write methods are
# covered by the write tests (-WriteTest) in ObsidiNote-Probe only. Its log lines hold statuses,
# timings, sizes, counts and OneNote's error codes; no names, ids, paths or addresses.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')

function New-ApiEntry([string]$Name, [string]$Kind, [string]$Does, [string]$Used, [string]$Could, [bool]$Probe) {
    [pscustomobject]@{ name = $Name; kind = $Kind; does = $Does; used = $Used; could = $Could; probe = $Probe }
}

# kind: read (no change anywhere), write (changes notebooks), file (writes or reads files on disk),
# window (changes or opens OneNote's window or a dialog).
$script:Catalogue = @(
    New-ApiEntry 'GetHierarchy' 'read' 'Notebooks, section groups, sections and pages as XML, from any node, at a chosen depth (self, children, notebooks, sections, pages); Meta at page scope' 'everywhere: vaults, index load, the side bar, the graph' '' $true
    New-ApiEntry 'GetHierarchyParent' 'read' 'The id of an object''s parent' '' 'find a page''s section without reading the whole hierarchy' $true
    New-ApiEntry 'GetPageContent' 'read' 'A page''s XML; the page-info flag adds binary data, the selection or file types' 'Ask sources, export, page window text, store reads' 'images and ink of a page (piBinaryData) for the export' $true
    New-ApiEntry 'GetBinaryPageContent' 'read' 'One image, ink or file object of a page, base64, by its callback id' '' 'images in the Markdown export and the page window' $true
    New-ApiEntry 'GetHyperlinkToObject' 'read' 'An onenote: link to a notebook, section, page or paragraph' 'every page link, "Linked from", graph and Ask sources' '' $true
    New-ApiEntry 'GetWebHyperlinkToObject' 'read' 'An https link that opens the object in OneNote on the web' '' 'open a page in the browser when desktop OneNote is closed; share a link' $true
    New-ApiEntry 'FindPages' 'read' 'OneNote''s own search (Windows Search) under a node' 'feasibility probes only (probes/p1-find.ps1); never for retrieval: unindexed pages come back whatever the term' '' $true
    New-ApiEntry 'FindMeta' 'read' 'Every object under a node that carries a Meta of a given name' '' 'none: it depends on Windows Search like FindPages (seen 2026-11-16), and GetHierarchy at page scope already returns every page''s Meta in one call' $true
    New-ApiEntry 'GetSpecialLocation' 'read' 'The backup folder, the unfiled-notes section or the default notebook folder' 'the default notebook folder for a new vault' '' $true
    New-ApiEntry 'Windows' 'read' 'OneNote''s windows and what the current one shows (notebook, section, page)' 'the notebook OneNote shows, at start' '' $true
    New-ApiEntry 'OpenHierarchy' 'write' 'Opens a notebook, or creates a notebook, section group or section by path' 'new vault and fixed sections' '' $false
    New-ApiEntry 'CreateNewPage' 'write' 'A new empty page in a section' 'every new page' '' $false
    New-ApiEntry 'UpdatePageContent' 'write' 'Writes page XML: title, Meta, outlines' 'every page write (owned outlines only)' '' $false
    New-ApiEntry 'DeletePageContent' 'write' 'Removes one object (an outline) from a page' 'owned outlines' '' $false
    New-ApiEntry 'UpdateHierarchy' 'write' 'Changes the hierarchy from XML: rename, reorder, move a page' 'section rename, moving a page (Archive, link bucket)' '' $false
    New-ApiEntry 'DeleteHierarchy' 'write' 'Deletes a page, section or group (to Deleted Pages unless permanent)' 'Delete and Undo (never permanent)' '' $false
    New-ApiEntry 'CloseNotebook' 'write' 'Closes a notebook in OneNote' 'feasibility probes only (probes/p1-cleanup.ps1)' '' $false
    New-ApiEntry 'SyncHierarchy' 'write' 'Asks OneNote to sync a notebook or section now' 'validation kit only' 'sync the vault before reading pages another PC wrote' $false
    New-ApiEntry 'MergeSections' 'write' 'Moves every page of one section into another' '' 'join a rolled-over section back' $false
    New-ApiEntry 'SetFilingLocation' 'write' 'Where Send to OneNote, Outlook and the web clipper file new items' '' 'file clippings straight into the vault''s Intake (changes the person''s OneNote settings: ask first)' $false
    New-ApiEntry 'Publish' 'file' 'Exports a page, section or notebook to a file (PDF, Word, MHTML, .one, .onepkg)' '' 'none: content on disk breaks the storage rule' $false
    New-ApiEntry 'OpenPackage' 'file' 'Unpacks a .onepkg notebook package to a folder' '' '' $false
    New-ApiEntry 'MergeFiles' 'file' 'Merges .one section files' '' '' $false
    New-ApiEntry 'NavigateTo' 'window' 'Shows a notebook, section, page or paragraph in OneNote''s window' 'once at start, so OneNote lists a vault it has not selected' '' $false
    New-ApiEntry 'NavigateToUrl' 'window' 'Opens an onenote: link in OneNote''s window' 'validation kit only (P1c)' '' $false
    New-ApiEntry 'QuickFiling' 'window' 'OneNote''s pick-a-location dialog' '' 'let the person pick a notebook for a new vault in OneNote''s own dialog' $false
)

function Get-OneNoteApiCatalogue { <# Every IApplication method and the Windows property, in table order. #> $script:Catalogue }

function Get-ApiErrorCode($Err) {
    <# OneNote's HRESULT of a failed call as 0x8004xxxx, from the innermost exception. #>
    $e = $Err.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    '0x{0:X8}' -f $e.HResult
}

function Invoke-ApiCall([scriptblock]$Body) {
    <# Runs one COM call: @{ ok; value; ms; code } (never throws). #>
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $v = & $Body; [pscustomobject]@{ ok = $true; value = $v; ms = $sw.ElapsedMilliseconds; code = '' } }
    catch { [pscustomobject]@{ ok = $false; value = $null; ms = $sw.ElapsedMilliseconds; code = (Get-ApiErrorCode $_) } }
}

function Read-ApiXml([string]$Xml) { if (-not $Xml) { return $null }; try { [xml]$d = $Xml; return $d } catch { return $null } }

$script:Live = "not(ancestor-or-self::*[@isRecycleBin='true' or @isInRecycleBin='true' or @isDeletedPages='true'])"

function Get-ApiTargets {
    <# What the probe reads: the first notebook that holds a page, its first section with a page, that
       page, and the first 25 pages of all open notebooks (where it looks for a picture). Pure. Ids
       only; @{} when there is no page. Recycle bins are left out. #>
    param([string]$Xml)
    $d = Read-ApiXml $Xml
    if (-not $d) { return @{} }
    $page = $d.SelectSingleNode("//*[local-name()='Page' and $($script:Live)]")
    if (-not $page) { return @{} }
    $section = $page.ParentNode
    $notebook = $section
    while ($notebook -and $notebook.LocalName -ne 'Notebook') { $notebook = $notebook.ParentNode }
    $pages = @($d.SelectNodes("//*[local-name()='Page' and $($script:Live)]") | Select-Object -First 25 | ForEach-Object { $_.GetAttribute('ID') })
    @{ notebook = $(if ($notebook) { $notebook.GetAttribute('ID') } else { '' }); section = $section.GetAttribute('ID'); page = $page.GetAttribute('ID'); pages = $pages }
}

function Format-Kb([string]$Text) { "$([Math]::Round(([double]$Text.Length) / 1024, 1)) KB" }

function Add-ApiResult($Ctx, [string]$Name, $Call, [string]$OkText) {
    if ($Call.ok) { Add-ValidationResult $Ctx 'V2' 'OK' "API $Name" "$OkText ($($Call.ms) ms)" }
    else { Add-ValidationResult $Ctx 'V2' 'FAIL' "API $Name" "OneNote reports error $($Call.code) ($($Call.ms) ms)" }
}

function Test-ApiHierarchy($Ctx, $Com, $T) {
    $bad = @()
    $ms = 0
    foreach ($scope in 1, 2, 3, 4) {
        $c = Invoke-ApiCall { $x = ''; $Com.GetHierarchy('', $scope, [ref]$x); $x }
        $ms += $c.ms
        if (-not $c.ok) { $bad += "scope $scope $($c.code)" }
    }
    $self = Invoke-ApiCall { $x = ''; $Com.GetHierarchy($T.notebook, 0, [ref]$x); $x }
    if (-not $self.ok) { $bad += "scope 0 $($self.code)" }
    $status = if ($bad.Count) { 'FAIL' } else { 'OK' }
    Add-ValidationResult $Ctx 'V2' $status 'API GetHierarchy' $(if ($bad.Count) { "failed: $($bad -join ', ')" } else { "all five scopes read ($($ms + $self.ms) ms)" })
}

function Test-ApiParent($Ctx, $Com, $T) {
    $c = Invoke-ApiCall { $x = ''; $Com.GetHierarchyParent($T.page, [ref]$x); $x }
    Add-ApiResult $Ctx 'GetHierarchyParent' $c "a page's parent is its section: $(Format-YesNo ($c.value -eq $T.section))"
}

function Test-ApiPageContent($Ctx, $Com, $T) {
    $basic = Invoke-ApiCall { $x = ''; $Com.GetPageContent($T.page, [ref]$x, 0); $x }
    $all = Invoke-ApiCall { $x = ''; $Com.GetPageContent($T.page, [ref]$x, 7); $x }
    if ($basic.ok -and $all.ok) { Add-ValidationResult $Ctx 'V2' 'OK' 'API GetPageContent' "basic $(Format-Kb $basic.value), with binary data $(Format-Kb $all.value) ($($basic.ms + $all.ms) ms)"; return }
    Add-ValidationResult $Ctx 'V2' 'FAIL' 'API GetPageContent' "basic $(if ($basic.ok) { 'read' } else { $basic.code }); with binary data $(if ($all.ok) { 'read' } else { $all.code })"
}

function Find-ApiCallback($Com, $T) {
    <# The first image, ink or file object's callback id on the candidate pages; $null if none. #>
    foreach ($p in @($T.pages)) {
        $c = Invoke-ApiCall { $x = ''; $Com.GetPageContent($p, [ref]$x, 0); $x }
        $d = if ($c.ok) { Read-ApiXml $c.value } else { $null }
        if (-not $d) { continue }
        $cb = $d.SelectSingleNode("//*[local-name()='CallbackID']/@callbackID")
        if ($cb) { return @{ page = $p; id = $cb.Value } }
    }
    $null
}

function Test-ApiBinary($Ctx, $Com, $T) {
    $cb = Find-ApiCallback $Com $T
    if (-not $cb) { Add-ValidationResult $Ctx 'V2' 'SKIP' 'API GetBinaryPageContent' "no image, ink or file on the first $(@($T.pages).Count) page(s) of the open notebooks"; return }
    $c = Invoke-ApiCall { $x = ''; $Com.GetBinaryPageContent($cb.page, $cb.id, [ref]$x); $x }
    Add-ApiResult $Ctx 'GetBinaryPageContent' $c "one object read, $(if ($c.ok) { Format-Kb $c.value } else { '' }) as base64"
}

function Test-ApiLinks($Ctx, $Com, $T) {
    $one = Invoke-ApiCall { $x = ''; $Com.GetHyperlinkToObject($T.page, '', [ref]$x); $x }
    Add-ApiResult $Ctx 'GetHyperlinkToObject' $one "a page link in OneNote's own scheme: $(Format-YesNo ("$($one.value)" -match '^(?i)onenote:'))"
    $web = Invoke-ApiCall { $x = ''; $Com.GetWebHyperlinkToObject($T.page, '', [ref]$x); $x }
    if ($web.ok) { Add-ValidationResult $Ctx 'V2' 'OK' 'API GetWebHyperlinkToObject' "a web address (https): $(Format-YesNo ("$($web.value)" -match '^(?i)https://')) ($($web.ms) ms)"; return }
    # A notebook on this PC has no web address: a failure there is expected, not a fault.
    Add-ValidationResult $Ctx 'V2' 'INFO' 'API GetWebHyperlinkToObject' "no web address: error $($web.code) (expected for a notebook on this PC)"
}

function Get-ApiPages($Call) {
    <# The Page elements of a search answer; none when the call failed. #>
    $d = if ($Call.ok) { Read-ApiXml $Call.value } else { $null }
    # @(if ...): an if that yields one page would hand over the page, not a list of one.
    @(if ($d) { $d.SelectNodes("//*[local-name()='Page']") })
}

function Get-ApiMetaPages($Call) {
    <# The pages of a FindMeta answer that really carry the Meta obsn.id. #>
    @(Get-ApiPages $Call | Where-Object { $_.SelectSingleNode("*[local-name()='Meta' and @name='obsn.id']") })
}

function Join-ApiCalls($First, $Second) {
    <# Two calls as one result: the first failure, else the second; the time of both. #>
    $call = if (-not $First.ok) { $First } else { $Second }
    [pscustomobject]@{ ok = $call.ok; value = $call.value; code = $call.code; ms = $First.ms + $Second.ms }
}

# Both searches run twice from all open notebooks: indexed pages only, then with the pages Windows
# Search has not indexed yet. Seen 2026-11-16 (desktop OneNote, consumer account): with unindexed
# pages included both return EVERY page, recycle bins too, whatever the term or Meta name.
function Test-ApiSearch($Ctx, $Com) {
    $find = Invoke-ApiCall { $x = ''; $Com.FindPages('', 'the', [ref]$x, $false, $false); $x }
    $findAll = Invoke-ApiCall { $x = ''; $Com.FindPages('', 'the', [ref]$x, $true, $false); $x }
    Add-ApiResult $Ctx 'FindPages' (Join-ApiCalls $find $findAll) "$(@(Get-ApiPages $find).Count) page(s) for a common word; with pages not yet indexed: $(@(Get-ApiPages $findAll).Count) returned"
    $meta = Invoke-ApiCall { $x = ''; $Com.FindMeta('', 'obsn.id', [ref]$x, $false); $x }
    $metaAll = Invoke-ApiCall { $x = ''; $Com.FindMeta('', 'obsn.id', [ref]$x, $true); $x }
    $text = "$(@(Get-ApiMetaPages $meta).Count) of $(@(Get-ApiPages $meta).Count) page(s) returned carry the Meta obsn.id; with pages not yet indexed: $(@(Get-ApiMetaPages $metaAll).Count) of $(@(Get-ApiPages $metaAll).Count)"
    Add-ApiResult $Ctx 'FindMeta' (Join-ApiCalls $meta $metaAll) $text
}

function Test-ApiLocations($Ctx, $Com) {
    $parts = @()
    $bad = @()
    $ms = 0
    foreach ($l in @(@(0, 'backup folder'), @(1, 'unfiled notes section'), @(2, 'default notebook folder'))) {
        $c = Invoke-ApiCall { $x = ''; $Com.GetSpecialLocation($l[0], [ref]$x); $x }
        $ms += $c.ms
        if ($c.ok) { $parts += "$($l[1]): $(Format-YesNo ([bool]"$($c.value)"))" } else { $bad += "$($l[1]) $($c.code)" }
    }
    Add-ValidationResult $Ctx 'V2' $(if ($bad.Count) { 'FAIL' } else { 'OK' }) 'API GetSpecialLocation' "$(($parts + $bad) -join '; ') ($ms ms)"
}

function Test-ApiWindows($Ctx, $Com) {
    $c = Invoke-ApiCall {
        $w = $Com.Windows
        $cw = $w.CurrentWindow
        @{ count = [int]$w.Count; shows = [bool]($cw -and "$($cw.CurrentNotebookId)") }
    }
    if (-not $c.ok) { Add-ValidationResult $Ctx 'V2' 'FAIL' 'API Windows' "could not be read: error $($c.code)"; return }
    Add-ValidationResult $Ctx 'V2' 'OK' 'API Windows' "$($c.value.count) window(s); the current one shows a notebook: $(Format-YesNo $c.value.shows) ($($c.ms) ms)"
}

function Invoke-ApiProbe {
    <# Tries every read method of OneNote's API once, on the first page OneNote lists (stage V2). One
       line per method; the methods that write or change the window are listed as not tried. #>
    param([Parameter(Mandatory)]$Ctx, $Com, [string]$HierarchyXml = '')
    if (-not $Com) { Add-ValidationResult $Ctx 'V2' 'SKIP' 'OneNote API' 'no COM object to try the methods on'; return }
    $t = Get-ApiTargets $HierarchyXml
    if (-not $t.Count) {
        Add-ValidationResult $Ctx 'V2' 'SKIP' 'OneNote API' 'no page in any open notebook: open a notebook with at least one page, then run V2 again'
    } else {
        Test-ApiHierarchy $Ctx $Com $t
        Test-ApiParent $Ctx $Com $t
        Test-ApiPageContent $Ctx $Com $t
        Test-ApiBinary $Ctx $Com $t
        Test-ApiLinks $Ctx $Com $t
        Test-ApiSearch $Ctx $Com
    }
    Test-ApiLocations $Ctx $Com
    Test-ApiWindows $Ctx $Com
    $skipped = @($script:Catalogue | Where-Object { -not $_.probe } | ForEach-Object { $_.name })
    Add-ValidationResult $Ctx 'V2' 'INFO' 'API not tried' "$($skipped -join ', ') (they write, use files or change OneNote's window; -WriteTest covers the ones ObsidiNote uses)"
}

Export-ModuleMember -Function Get-OneNoteApiCatalogue, Get-ApiTargets, Invoke-ApiProbe
