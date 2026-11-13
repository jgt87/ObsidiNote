# V2 OneNote: the open notebooks read through COM (counts only: notebooks, section groups, sections,
# pages; where each notebook lives; which are ObsidiNote vaults), the COM latency, and the notebook
# on record. With -WriteTest also the write probes P1, P1b and P1c, only in ObsidiNote-Probe.
# Every notebook, section and page name read here is registered for masking; the log shows
# "notebook #1" and counts only. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
$script:AppLib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib'
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProbeNotebook.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriteProbes.psm1')
foreach ($m in 'AppConfig', 'OneNoteHost', 'NotebookView') { Import-Module (Join-Path $script:AppLib "$m.psm1") }

$script:ListMax = 25

function Test-KitInRecycle($Node) {
    for ($n = $Node; $n -and $n.NodeType -eq 'Element'; $n = $n.ParentNode) {
        foreach ($a in 'isRecycleBin', 'isInRecycleBin', 'isDeletedPages') { if ($n.GetAttribute($a) -eq 'true') { return $true } }
        if ($n.LocalName -eq 'Notebook') { break }
    }
    $false
}

function Get-NotebookCounts($Node) {
    $sections = @($Node.SelectNodes(".//*[local-name()='Section']") | Where-Object { -not (Test-KitInRecycle $_) })
    $groups = @($Node.SelectNodes(".//*[local-name()='SectionGroup']") | Where-Object { -not (Test-KitInRecycle $_) })
    $pages = @($Node.SelectNodes(".//*[local-name()='Page']") | Where-Object { -not (Test-KitInRecycle $_) })
    $locked = @($sections | Where-Object { $_.GetAttribute('locked') -eq 'true' -or $_.GetAttribute('encrypted') -eq 'true' })
    $vault = @($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Section' -and $_.GetAttribute('name') -eq '00 Index' -and -not (Test-KitInRecycle $_) }).Count -gt 0
    $nick = $Node.GetAttribute('nickname')
    [pscustomobject]@{
        name = $(if ($nick) { $nick } else { $Node.GetAttribute('name') }); path = $Node.GetAttribute('path')
        location = (Get-NotebookLocationLabel $Node.GetAttribute('path')); vault = $vault
        sections = $sections.Count; groups = $groups.Count; pages = $pages.Count; locked = $locked.Count
        names = @(@($sections + $groups) | ForEach-Object { $_.GetAttribute('name') }) + @($pages | ForEach-Object { $_.GetAttribute('name') })
    }
}

function Get-HierarchyCounts {
    <# Counts from GetHierarchy XML at page scope (recycle bins left out). Pure. Returns
       @{ notebooks = @(per notebook: name; path; location; vault; sections; groups; pages; locked; names) }. #>
    param([string]$Xml)
    $d = Read-KitXml $Xml
    if (-not $d) { return [pscustomobject]@{ notebooks = @() } }
    [pscustomobject]@{ notebooks = @($d.SelectNodes("//*[local-name()='Notebook']") | ForEach-Object { Get-NotebookCounts $_ }) }
}

function Register-HierarchyNames($Ctx, $Counts) {
    <# Every notebook, section and page name becomes a masked name in this run. #>
    foreach ($nb in @($Counts.notebooks)) {
        $alias = Register-ValidationName $Ctx 'notebook' $nb.name
        $nb | Add-Member -Force NoteProperty alias $alias
        foreach ($n in @($nb.names)) { if ("$n".Trim().Length -ge 3 -and "$n" -match '\p{L}') { $null = Register-ValidationName $Ctx 'name' $n } }
    }
}

function Add-NotebookResults($Ctx, $Counts) {
    $nbs = @($Counts.notebooks)
    $by = @{}; foreach ($n in $nbs) { $k = if ($n.location) { $n.location } else { 'unknown' }; $by[$k] = 1 + $(if ($by.ContainsKey($k)) { $by[$k] } else { 0 }) }
    $where = @($by.Keys | Sort-Object | ForEach-Object { "$($by[$_]) $_" }) -join ', '
    $vaults = @($nbs | Where-Object { $_.vault }).Count
    Add-ValidationResult $Ctx 'V2' $(if ($nbs.Count) { 'OK' } else { 'WARN' }) 'Notebooks' "$($nbs.Count) open$(if ($where) { " ($where)" }); $vaults ObsidiNote vault(s)" $(if (-not $nbs.Count) { 'Open your notebooks in OneNote, then run V2 again.' } else { '' })
    foreach ($n in @($nbs | Select-Object -First $script:ListMax)) {
        $kind = if ($n.vault) { 'vault' } else { 'read only' }
        Add-ValidationResult $Ctx 'V2' 'INFO' $n.alias "$($n.location); $($n.sections) sections, $($n.groups) groups, $($n.pages) pages; $kind$(if ($n.locked) { "; $($n.locked) password-protected" })"
    }
    if ($nbs.Count -gt $script:ListMax) { Add-ValidationResult $Ctx 'V2' 'INFO' 'More notebooks' "$($nbs.Count - $script:ListMax) not listed" }
    $t = @{ s = 0; g = 0; p = 0; l = 0 }
    foreach ($n in $nbs) { $t.s += $n.sections; $t.g += $n.groups; $t.p += $n.pages; $t.l += $n.locked }
    Add-ValidationResult $Ctx 'V2' $(if ($t.l) { 'WARN' } else { 'OK' }) 'Totals' "$($t.s) sections, $($t.g) section groups, $($t.p) pages$(if ($t.l) { "; $($t.l) password-protected sections (COM cannot read them)" })"
}

function Add-RecordResult($Ctx, $Counts) {
    $rec = Get-NotebookRecord -AppRoot $Ctx.AppRoot
    if (-not $rec) { Add-ValidationResult $Ctx 'V2' 'INFO' 'Notebook on record' 'not set yet (the first start with a vault open records it)'; return }
    $kind = if ($rec -match '^(?i)onenote:') { 'a OneDrive or SharePoint notebook' } else { 'a notebook on this PC' }
    $open = @($Counts.notebooks | Where-Object { Test-RecordMatchesPath $rec $_.path }).Count -gt 0
    Add-ValidationResult $Ctx 'V2' 'INFO' 'Notebook on record' "$kind; usable: $(Format-YesNo (Test-NotebookRecord $rec)); open now: $(Format-YesNo $open)"
}

function Invoke-WriteTests($Ctx, $One) {
    if (-not (Get-KitFlag $Ctx 'WriteTest')) {
        Add-ValidationResult $Ctx 'V2' 'SKIP' 'P1, P1b, P1c' 'write tests not run' 'Add -WriteTest to run them; they write only into the notebook ObsidiNote-Probe.'
        return
    }
    $g = Measure-KitStep { Open-ProbeNotebook -One $One -Name (Get-ProbeNotebookName) -BasePath "$(Get-KitFlag $Ctx 'ProbeBasePath' '')" }
    if (-not $g.ok) { Add-ValidationResult $Ctx 'V2' 'FAIL' 'ObsidiNote-Probe' "could not open or create: $($g.error)" 'Open a OneDrive notebook in OneNote, or pass -ProbeBasePath with your OneDrive Documents address.'; return }
    Add-ValidationResult $Ctx 'V2' 'OK' 'ObsidiNote-Probe' "$(if ($g.value.Created) { 'created' } else { 'opened' }) in $($g.ms) ms"
    $Ctx.Shared.ProbeGuard = $g.value
    Invoke-ProbeRoundTrip -Ctx $Ctx -Guard $g.value -Stage 'V2'
    Invoke-ProbeMetaSize -Ctx $Ctx -Guard $g.value -Stage 'V2'
    Invoke-ProbeLinkMove -Ctx $Ctx -Guard $g.value -Stage 'V2' -WaitMs ([int](Get-KitFlag $Ctx 'NavigateWaitMs' 1500))
}

function Get-KitOneNote {
    <# The COM adapter for this run (shared by V2, V5 and V6): $null when OneNote is not running. #>
    param([Parameter(Mandatory)]$Ctx)
    if ($Ctx.Shared.ContainsKey('One') -and $Ctx.Shared.One) { return $Ctx.Shared.One }
    if ((Get-OneNoteState) -eq 'none') { return $null }
    $Ctx.Shared.One = New-KitOneNote
    $Ctx.Shared.One
}

function Invoke-StageOneNote {
    param([Parameter(Mandatory)]$Ctx)
    $one = $null
    try { $one = Get-KitOneNote $Ctx } catch { Add-ValidationResult $Ctx 'V2' 'FAIL' 'OneNote COM' $_.Exception.Message 'Repair Office (desktop OneNote), then run V2 again.'; return }
    if (-not $one) {
        Add-ValidationResult $Ctx 'V2' 'WARN' 'OneNote' 'not running: nothing read' 'Open OneNote with your notebooks, then run V2 again.'
        return
    }
    $t2 = Measure-KitStep { $one.GetHierarchy('', 2) }
    if (-not $t2.ok) { Add-ValidationResult $Ctx 'V2' 'FAIL' 'OneNote COM' $t2.error 'Open OneNote, wait until it shows your notebooks, then run V2 again.'; return }
    $t4 = Measure-KitStep { $one.GetHierarchy('', 4) }
    if (-not $t4.ok) { Add-ValidationResult $Ctx 'V2' 'FAIL' 'OneNote COM' "full hierarchy: $($t4.error)"; return }
    $counts = Get-HierarchyCounts $t4.value
    Register-HierarchyNames $Ctx $counts
    $slow = $t4.ms -gt 15000
    Add-ValidationResult $Ctx 'V2' $(if ($slow) { 'WARN' } else { 'OK' }) 'COM latency' "notebook list $($t2.ms) ms; all sections and pages $($t4.ms) ms"
    Add-NotebookResults $Ctx $counts
    Add-RecordResult $Ctx $counts
    Invoke-WriteTests $Ctx $one
}

Export-ModuleMember -Function Invoke-StageOneNote, Get-HierarchyCounts, Get-KitOneNote
