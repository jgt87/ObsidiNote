# Dev check for step 2 (structure, index, lease, write guard, connected notebooks), live against
# OneNote. Writes ONLY into the dev notebook (default ObsidiNote-Dev; any name not starting with
# ObsidiNote-Dev is refused) and, with -SecondVault, a section-group vault inside it. Other open
# notebooks are only read (-ReadOthers), and only counts and timings are printed, never titles.
# Windows PowerShell 5.1 with OneNote desktop running. ASCII only.
param(
    [string]$Name = 'ObsidiNote-Dev',
    [switch]$SecondVault,
    [switch]$ReadOthers,
    [int]$LinkBatch = 200
)
$ErrorActionPreference = 'Stop'
if ($Name -notlike 'ObsidiNote-Dev*') { throw "Dev check runs only on a notebook named ObsidiNote-Dev*, not '$Name'." }
$lib = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index') { Import-Module (Join-Path $lib "$m.psm1") -Force }

$rows = New-Object System.Collections.ArrayList
function T([string]$Label, [scriptblock]$Body) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = & $Body
    $null = $rows.Add(('{0,-48} {1,8} ms' -f $Label, $sw.ElapsedMilliseconds))
    $r
}
function Say([string]$Text) { $null = $rows.Add($Text) }

$a = Get-OneNoteAdapter
$vaults = T 'Get-VaultList (all open notebooks)' { @(Get-VaultList -Adapter $a) }
Say "vaults found: $($vaults.Count)"
$devNb = ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy('', 2)) -Name $Name
if ($devNb -and -not @($vaults | Where-Object { $_.rootId -eq $devNb.notebook.id }).Count) {
    # The dev notebook exists (e.g. made by hand) but is no vault yet: make it one (dev names only).
    Set-OneNoteWriteRoot -Adapter $a -RootId $devNb.notebook.id
    $null = T "Initialize-ObsidiVault (adopt empty $Name)" { Initialize-ObsidiVault -Adapter $a -RootId $devNb.notebook.id }
}
$v = T "Initialize-ObsidiNotebook ($Name)" { Initialize-ObsidiNotebook -Adapter $a -Name $Name }
Say "vault created: $($v.vaultCreated); created: $(@($v.created).Count); present: $(@($v.present).Count); user sections: $(@($v.userSections).Count)"
$v2 = T "Initialize-ObsidiNotebook again (idempotent)" { Initialize-ObsidiNotebook -Adapter $a -Name $Name }
Say "second run created: $(@($v2.created).Count); same vault id: $($v2.vaultId -eq $v.vaultId)"

# Synthetic content (fictional), once.
$tree = ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy($v.rootId, 4)) -RootId $v.rootId
$notes = @($tree.sections | Where-Object { $_.full -eq 'Notes' })[0]
if ($notes.pages.Count -lt 3) {
    $seed = @(
        @{ s = 'Notes'; t = 'Tidal gardens'; m = @{ type = 'concept'; topics = @('Gardening/Coast'); summary = 'Growing food where the sea reaches.' } },
        @{ s = 'Notes'; t = 'Salt-tolerant crops'; m = @{ type = 'note'; topics = @('Gardening/Coast', 'Plants'); summary = 'Crops that cope with salty soil.' } },
        @{ s = 'Notes'; t = 'Compost basics'; m = @{ type = 'howto'; topics = @('Gardening/Soil'); summary = 'Brown and green layers.' } },
        @{ s = 'Web links'; t = 'Example article on dunes'; m = @{ type = 'link-web'; topics = @('Gardening/Coast'); url = 'https://www.example.org/dunes'; host = 'www.example.org'; kind = 'article'; summary = 'How dunes move.' } },
        @{ s = 'Internal links'; t = 'Team site home'; m = @{ type = 'link-internal'; url = 'https://contoso.sharepoint.com/sites/Ops/SitePages/Home.aspx'; host = 'contoso.sharepoint.com'; kind = 'page'; summary = 'Start page of a made-up team.' } },
        @{ s = 'People'; t = 'Ada Example (gardener)'; m = @{ type = 'person'; topics = @('Gardening'); summary = 'Fictional person.' } }
    )
    $st = Get-VaultState -Adapter $a -IndexSectionId $v.indexSectionId
    $n = $st.idCounter
    $made = @{}
    T 'seed 6 synthetic content pages + 1 hand-made' {
        foreach ($x in $seed) {
            $sid = $v.sectionIds[$x.s]
            $pg = $a.CreateNewPage($sid)
            $rec = $x.m.Clone(); $rec.id = New-ObsnId $n; $n++
            if ($made.Count) { $rec.links = @(@{ target = @($made.Keys)[0]; strength = 2; why = 'same coast' }) }
            Write-ObsnPage -Adapter $a -PageId $pg -Meta (ConvertTo-ObsnMeta $rec) -Title $x.t -Outlines @(@{ role = 'props'; lines = (Get-PropertiesLines $rec) }) -NewPage
            $made[$rec.id] = $pg
        }
        $u = $a.CreateNewPage($v.sectionIds['Notes'])
        $a.UpdatePageContent((New-ObsnPageXml -PageId $u -Title 'Hand-written page' -Outlines @(@{ role = 'user-like'; lines = @('Typed by hand, no ObsidiNote data.') })))
    } | Out-Null
}

$sid = New-WriterSessionId
$lease = T 'Request-WriterLease' { Request-WriterLease -Adapter $a -IndexSectionId $v.indexSectionId -SessionId $sid }
Say "lease mode: $($lease.mode)"
$other = T 'second session asks for the lease' { Request-WriterLease -Adapter $a -IndexSectionId $v.indexSectionId -SessionId (New-WriterSessionId) }
Say "second session mode: $($other.mode)"
$u1 = T 'Update-VaultIndex (load, scan, repair, write)' { Update-VaultIndex -Adapter $a -RootId $v.rootId -IndexSectionId $v.indexSectionId -Lease $lease -VaultId $v.vaultId }
Say "pages: $($u1.model.pages.Count); topics: $($u1.model.topics.Count); missing repaired: $(@($u1.missing).Count); index pages written: $($u1.write.written), created: $($u1.write.created), links fetched: $($u1.write.linksFetched)"
$u2 = T 'Update-VaultIndex again (rewrite in place)' { Update-VaultIndex -Adapter $a -RootId $v.rootId -IndexSectionId $v.indexSectionId -Lease $lease -VaultId $v.vaultId }
Say "second write created: $($u2.write.created); removed: $($u2.write.removed); changed pages: $(@($u2.changed).Count)"
$fresh = T 'Read-IndexModel (fast load, 1 hierarchy call)' { Read-IndexModel -Adapter $a -IndexSectionId $v.indexSectionId }
$tree = T 'hierarchy of the vault at page scope' { ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy($v.rootId, 4)) -RootId $v.rootId }
$miss = @(Test-IndexComplete -Model $fresh -Tree $tree)
Say "fast load pages: $($fresh.pages.Count); topics: $($fresh.topics.Count); Test-IndexComplete missing: $($miss.Count)"
$scan = T 'Read-VaultScan (rebuild from content pages)' { Read-VaultScan -Adapter $a -RootId $v.rootId }
$mg = Merge-IndexWithScan -Index $fresh -Scan $scan
Say "index vs pages: added $(@($mg.added).Count), removed $(@($mg.removed).Count), changed $(@($mg.changed).Count)"

# Guard: a write outside the root is refused.
$refused = 0
$nbXml = $a.GetHierarchy('', 2)
if ($SecondVault) {
    $g = @(Get-VaultList -Adapter $a | Where-Object { $_.rootKind -eq 'sectiongroup' -and $_.notebookId -eq $v.rootId -and $_.name -eq 'Dev group vault' })
    if ($g.Count) { $gv = T 'Open-ObsidiVault (section-group vault)' { Open-ObsidiVault -Adapter $a -RootId $g[0].rootId } }
    else { $gv = T 'New-ObsidiVault -InSectionGroupOf (dev notebook)' { New-ObsidiVault -Adapter $a -Name 'Dev group vault' -InSectionGroupOf $v.rootId } }
    Say "group vault: created $($gv.vaultCreated); sections created: $(@($gv.created).Count); vault id differs: $($gv.vaultId -ne $v.vaultId)"
    $gl = Request-WriterLease -Adapter $a -IndexSectionId $gv.indexSectionId -SessionId $sid
    $gu = T 'Update-VaultIndex (group vault)' { Update-VaultIndex -Adapter $a -RootId $gv.rootId -IndexSectionId $gv.indexSectionId -Lease $gl -VaultId $gv.vaultId }
    Say "group vault index pages: $($gu.write.written); missing: $(@($gu.missing).Count)"
    try { $null = $a.CreateNewPage($v.sectionIds['Notes']); Say 'GUARD FAIL: write into the outer notebook from the group vault passed' } catch { $refused++ }
    $null = Clear-WriterLease -Adapter $a -Lease $gl
    Set-OneNoteWriteRoot -Adapter $a -RootId $v.rootId
    try { $null = $a.CreateNewPage($gv.sectionIds['Notes']); Say 'GUARD FAIL: write into the group vault from the notebook vault passed' } catch { $refused++ }
    $outer = Read-VaultScan -Adapter $a -RootId $v.rootId
    Say "outer vault scan pages: $($outer.pages.Count) (group vault left out)"
}
[xml]$nx = $nbXml
foreach ($n in @($nx.DocumentElement.ChildNodes)) {
    if ($n.NodeType -ne 'Element' -or $n.GetAttribute('ID') -eq $v.rootId) { continue }
    $sec = @(ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy($n.GetAttribute('ID'), 3)) -RootId $n.GetAttribute('ID')).sections | Select-Object -First 1
    # Only the guard's check is called here (never a real write into someone else's notebook).
    if ($sec) { try { $a.Assert($sec.id, 'dev check'); Say 'GUARD FAIL: another notebook counts as inside' } catch { $refused++ } }
}
Say "guard refusals: $refused"
$null = Clear-WriterLease -Adapter $a -Lease $lease

if ($ReadOthers) {
    foreach ($n in @($nx.DocumentElement.ChildNodes)) {
        if ($n.NodeType -ne 'Element' -or $n.GetAttribute('name') -like 'ObsidiNote*') { continue }
        $id = $n.GetAttribute('ID')
        $fm = T 'Get-NotebookModel (other notebook, read only)' { Get-NotebookModel -Adapter $a -NotebookId $id }
        $sub = @($fm.pages.Values | Where-Object { $_.level -gt 1 }).Count
        Say "  kind $($fm.kind); topics $($fm.topics.Count); pages $($fm.pages.Count); subpages $sub"
        $lk = T "Get-NotebookLinks (first $LinkBatch pages)" { Get-NotebookLinks -Adapter $a -Model $fm -Start 0 -BatchSize $LinkBatch }
        Say "  pages read $($lk.processed); link edges $($lk.edges); done $($lk.done)"
        $top = Get-IndexTopLevel -Model $fm -MaxChars 4000
        Say "  top-level topics $(@($top.topics).Count); step-1 prompt chars $($top.text.Length)"
    }
}
$rows
