# The store adapter that lib/Ingest.psm1 (Add, Undo, link Update) writes through, on top of the
# step-2 modules: every function of Get-IngestStoreContract, bound to one active vault.
#   - Writes go only through the guarded OneNote adapter (lib/OneNote.psm1) whose write root is the
#     active vault, and only while this session holds the vault's writer lease (AssertWritable).
#   - The in-memory index model (lib/Index.psm1) is updated in place; after each index change the
#     affected Index pages are regenerated (root, lists, state, the page's topic hubs and their
#     parents) and the hierarchy is checked against the index (completeness rule).
#   - Ids come from the state page's counter (obsn.idCounter), under the lease.
# Line model from lib/LinkCapture.psm1 (@{ parts = @(@{ text; href }); bold; collapsed; children })
# is turned into owned outlines here. Nothing is written to disk; page text stays in memory.
# PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')
Import-Module (Join-Path $PSScriptRoot 'Vault.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriterLease.psm1')
Import-Module (Join-Path $PSScriptRoot 'Index.psm1')
Import-Module (Join-Path $PSScriptRoot 'MarkdownLines.psm1')

$script:FixedIndexKeys = @('root', 'bytype', 'az', 'unfiled', 'links', 'archive', 'other', 'state')
$script:DeletedKeepDays = 60

# ---------------------------------------------------------------- pure helpers

function ConvertTo-PartsHtml([object[]]$Parts) {
    # Parts may carry Markdown styles (bold, italic, code, strike; lib/MarkdownLines.psm1).
    (@(@($Parts) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-MdPartHtml $_ }) -join '')
}

function ConvertTo-OutlineLines {
    <# Line model -> New-OneLine lines (PageMeta). Strings stay plain text. Markdown lines keep their
       list kind (numbered items count per level), heading size and table. #>
    param([object[]]$Lines = @())
    $num = 0
    , @(foreach ($l in @($Lines)) {
        if ($null -eq $l) { continue }
        if ($l -is [string]) { New-OneLine -Text $l; $num = 0; continue }
        $html = ConvertTo-PartsHtml @($l['parts'])
        $level = [int]$l['heading']
        if ($level -ge 1 -and $level -le 3) { $html = "<span style='font-size:" + @('16', '14', '12')[$level - 1] + "pt'>$html</span>" }
        $list = [string]$l['list']
        if ($list -eq 'number') { $num++ } else { $num = 0 }
        $table = $null
        if ($l['table']) {
            $t = $l['table']
            $table = @{
                header = @(foreach ($c in @($t['header'])) { ConvertTo-PartsHtml @($c) })
                rows = @(foreach ($r in @($t['rows'])) { , @(foreach ($c in @($r)) { ConvertTo-PartsHtml @($c) }) })
            }
        }
        $kids = ConvertTo-OutlineLines -Lines @($l['children'])
        New-OneLine -Html $html -Children $kids -Bold:([bool]$l['bold']) -Collapsed:([bool]$l['collapsed']) -List $list -Number $num -Table $table
    })
}

function ConvertTo-IngestPage {
    <# A page record of the index model in the shape lib/Ingest.psm1 and lib/Linker.psm1 read. #>
    param([Parameter(Mandatory)][hashtable]$Page)
    @{
        id = $Page.id; title = $Page.title; type = $Page.type; section = $Page.section; bucket = $Page.bucket; pageId = $Page.oneNoteId
        link = $Page.link; summary = $Page.summary; aliases = @($Page.aliases); topics = @($Page.topics); status = $Page.status
        links = @(@($Page.links) | ForEach-Object { @{ target = [string]$_.target; strength = [int]$_.strength; why = [string]$_.why } })
        url = $Page.url
    }
}

function Get-IngestIndex {
    <# The index as Ingest reads it: ObsidiNote's own pages (with an obsn id), all topic paths, edges. #>
    param([Parameter(Mandatory)][hashtable]$Model)
    $pages = @($Model.pages.Values | Where-Object { Test-ObsnId $_.id } | ForEach-Object { ConvertTo-IngestPage $_ })
    @{ pages = $pages; topics = @($Model.topics.Keys); edges = @(Get-IndexEdges -Model $Model) }
}

function Get-SectionCounts {
    <# Section full name -> number of pages in it (for the 500-page rollover). #>
    param([Parameter(Mandatory)][hashtable]$Model)
    $c = @{}
    foreach ($p in $Model.pages.Values) { if ($p.section) { if ($c.ContainsKey($p.section)) { $c[$p.section]++ } else { $c[$p.section] = 1 } } }
    $c
}

function Get-AffectedIndexKeys {
    <# The Index pages a change touches: the fixed lists and the hubs of $Topics and their parents. #>
    param([string[]]$Topics = @())
    $set = New-Object System.Collections.Generic.List[string]
    foreach ($k in $script:FixedIndexKeys) { $set.Add($k) }
    foreach ($t in @($Topics | Where-Object { $_ })) {
        $p = ConvertTo-TopicPath $t
        while ($p) {
            if (-not $set.Contains("topic:$p")) { $set.Add("topic:$p") }
            $i = $p.LastIndexOf('/')
            $p = if ($i -gt 0) { $p.Substring(0, $i) } else { '' }
        }
    }
    , $set.ToArray()
}

function Get-RecentlyDeleted {
    <# The state page's Recently deleted list with $Entry added, entries older than 60 days dropped. #>
    param([object[]]$Deleted = @(), $Entry = $null, [datetime]$Now = (Get-Date))
    $cut = $Now.AddDays(-$script:DeletedKeepDays).ToString('yyyy-MM-dd')
    $keep = @(@($Deleted) | Where-Object { $_ -and [string](Get-JsonProp $_ 'date' '') -ge $cut })
    if ($Entry) { $keep = @($Entry) + $keep }
    , $keep
}

# ---------------------------------------------------------------- index pages

function Write-AffectedIndexPages {
    <# Regenerates only the Index pages in $Keys (and their continuation pages) from the model; makes
       the ones that do not exist yet. Needs a valid writer lease. Returns the number written. #>
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][string]$IndexSectionId, $Lease, [string[]]$Keys)
    if (-not (Test-WriterLease $Lease)) { throw 'Read only: this session does not hold the writer lease.' }
    $existing = @{}
    [xml]$sx = $Adapter.GetHierarchy($IndexSectionId, 4)
    foreach ($p in @($sx.SelectNodes("//*[local-name()='Page']"))) {
        if ($p.GetAttribute('isInRecycleBin') -eq 'true') { continue }
        foreach ($m in @($p.ChildNodes)) { if ($m.NodeType -eq 'Element' -and $m.LocalName -eq 'Meta' -and $m.GetAttribute('name') -eq 'obsn.indexKey') { $existing[$m.GetAttribute('content')] = $p.GetAttribute('ID') } }
    }
    foreach ($p in $Model.pages.Values) { if (-not $p.link -and $p.oneNoteId) { try { $p.link = $Adapter.GetHyperlinkToObject($p.oneNoteId) } catch { } } }
    $all = @(Get-IndexPageSpecs -Model $Model | ForEach-Object { $_.key })
    $want = @($all | Where-Object { $Keys -contains (($_ -split '#')[0]) })
    $new = @{}
    foreach ($k in $want) { if (-not $existing.ContainsKey($k)) { $existing[$k] = $Adapter.CreateNewPage($IndexSectionId); $new[$k] = $true } }
    $links = @{}
    foreach ($k in $all) {
        if (-not $existing.ContainsKey($k)) { continue }
        if ($Model.indexLinks.ContainsKey($k) -and $Model.indexPages.ContainsKey($k) -and $Model.indexPages[$k] -eq $existing[$k]) { $links[$k] = $Model.indexLinks[$k] }
        else { $links[$k] = $Adapter.GetHyperlinkToObject($existing[$k]) }
    }
    $n = 0
    foreach ($s in @(Get-IndexPageSpecs -Model $Model -Links $links)) {
        if ($want -notcontains $s.key) { continue }
        $meta = [ordered]@{ 'obsn.indexKey' = $s.key }
        foreach ($kv in $s.meta.GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
        $role = if ($s.ContainsKey('role')) { $s.role } else { 'index' }
        Write-ObsnPage -Adapter $Adapter -PageId $existing[$s.key] -Meta $meta -Title $s.title -Outlines @(@{ role = $role; lines = $s.lines }) -NewPage:([bool]$new[$s.key])
        $n++
    }
    $Model.indexPages = $existing; $Model.indexLinks = $links
    $n
}

# ---------------------------------------------------------------- the store functions

function Assert-VsWritable {
    param([hashtable]$Ctx)
    $lease = & $Ctx.GetLease
    if (-not (Test-WriterLease $lease)) { throw 'Read only: another ObsidiNote is writing in this vault, or this one could not renew its writer lease.' }
    if (-not $Ctx.Adapter.PSObject.Properties['RootId'] -or $Ctx.Adapter.RootId -ne $Ctx.Vault.rootId) { throw 'The write guard is not set to the active vault.' }
}

function Update-VsIndex {
    <# After an index change: completeness check against the hierarchy, then the affected Index pages. #>
    param([hashtable]$Ctx, [string[]]$Topics)
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Ctx.Adapter.GetHierarchy($Ctx.Vault.rootId, 4)) -RootId $Ctx.Vault.rootId
    $missing = @(Repair-IndexCompleteness -Model $Ctx.Model -Tree $tree)
    $t = @($Topics)
    foreach ($m in $missing) { $k = $Ctx.Model.byOneNoteId[$m.oneNoteId]; if ($k) { $t += @($Ctx.Model.pages[$k].topics) } }
    $null = Write-AffectedIndexPages -Adapter $Ctx.Adapter -Model $Ctx.Model -IndexSectionId $Ctx.Vault.indexSectionId -Lease (& $Ctx.GetLease) -Keys (Get-AffectedIndexKeys -Topics $t)
    $missing.Count
}

function Get-VsPageRecord {
    <# The obsn.* fields of an Ingest page hashtable. #>
    param([hashtable]$Page)
    $r = @{}
    foreach ($k in (Get-ObsnMetaKeys)) { if ($Page.ContainsKey($k)) { $r[$k] = $Page[$k] } }
    $r
}

function Invoke-VsNewId {
    param([hashtable]$Ctx)
    Assert-VsWritable $Ctx
    $st = Get-VaultState -Adapter $Ctx.Adapter -IndexSectionId $Ctx.Vault.indexSectionId
    if (-not $st) { throw 'The vault has no state page.' }
    $c = [int64][Math]::Max([int64]$st.idCounter, [int64]$Ctx.Model.idCounter)
    while ($Ctx.Model.pages.Contains((New-ObsnId $c))) { $c++ }
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $st.statePageId -Meta ([ordered]@{ 'obsn.idCounter' = [string]($c + 1) })
    $Ctx.Model.idCounter = $c + 1
    New-ObsnId $c
}

function Invoke-VsCreateInboxItem {
    <# A new Intake item (section '01 Intake'): the text as added, status new, and the request
       reference of its first Copilot step (obsn.requestRef, obsn.requestKind classify|linkSummary). #>
    param([hashtable]$Ctx, [string]$Title, [string]$Text, [string]$Kind, [string]$Ref = '', [string]$RequestKind = '')
    Assert-VsWritable $Ctx
    $sid = Resolve-ObsnSection -Adapter $Ctx.Adapter -RootId $Ctx.Vault.rootId -Full (Get-ObsnIntakeSection)
    $pageId = $Ctx.Adapter.CreateNewPage($sid)
    $lines = @($Text -split '\r?\n' | ForEach-Object { New-OneLine -Text $_.TrimEnd() })
    $meta = [ordered]@{ 'obsn.status' = 'new'; 'obsn.inboxKind' = $Kind; 'obsn.requestRef' = $Ref; 'obsn.requestKind' = $RequestKind }
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $pageId -Meta $meta -Title $Title -Outlines @(@{ role = 'props'; lines = @('status: new') }, @{ role = 'body'; lines = $lines }) -NewPage
    @{ pageId = $pageId; link = $Ctx.Adapter.GetHyperlinkToObject($pageId) }
}

function Invoke-VsSetInboxStatus {
    param([hashtable]$Ctx, [string]$PageId, [string]$Status, [string]$Reason, [string]$Id)
    Assert-VsWritable $Ctx
    $line = "status: $Status" + $(if ($Reason) { " - $Reason" } else { '' }) + $(if ($Id) { " (filed as $Id)" } else { '' })
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $PageId -Meta ([ordered]@{ 'obsn.status' = $Status; 'obsn.statusReason' = $Reason; 'obsn.filedAs' = $Id }) -Outlines @(@{ role = 'props'; lines = @($line) })
}

function Invoke-VsSetInboxWaiting {
    <# Copilot is still answering: status waiting, the request reference and kind, when the wait began,
       and the Copilot chat's address (an id-like URL without query; no prompt text). #>
    param([hashtable]$Ctx, [string]$PageId, [string]$Ref, [string]$RequestKind, [string]$ChatUrl, [string]$Since)
    Assert-VsWritable $Ctx
    $line = "status: waiting - Copilot is still answering (reference $Ref)"
    $meta = [ordered]@{ 'obsn.status' = 'waiting'; 'obsn.statusReason' = ''; 'obsn.requestRef' = $Ref; 'obsn.requestKind' = $RequestKind; 'obsn.waitingSince' = $Since; 'obsn.chatUrl' = $ChatUrl }
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $PageId -Meta $meta -Outlines @(@{ role = 'props'; lines = @($line) })
}

function Invoke-VsReadInboxItem {
    <# An Intake item of the active vault: only a page of the '01 Intake' section directly in the vault
       root (never another section, notebook or the recycle bin). Returns @{ pageId; title; status;
       kind; text; ref; requestKind; waitingSince; chatUrl }; throws for anything else. #>
    param([hashtable]$Ctx, [string]$PageId)
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Ctx.Adapter.GetHierarchy($Ctx.Vault.rootId, 4)) -RootId $Ctx.Vault.rootId
    $intake = Get-ObsnIntakeSection
    $sec = @($tree.sections | Where-Object { $_.full -eq $intake }) | Select-Object -First 1
    if (-not $sec -or -not @($sec.pages | Where-Object { $_.id -eq $PageId }).Count) { throw 'not an Intake item' }
    $xml = $Ctx.Adapter.GetPageContent($PageId)
    $meta = (ConvertFrom-ObsnPageXml -Xml $xml).meta
    $t = ConvertFrom-ObsnPageText -Xml $xml
    $body = @($t.outlines | Where-Object { $_.role -eq 'body' }) | Select-Object -First 1
    $m = { param($k) if ($meta.ContainsKey($k)) { [string]$meta[$k] } else { '' } }
    @{
        pageId = $PageId; title = $t.title; status = (& $m 'obsn.status'); kind = (& $m 'obsn.inboxKind')
        text = $(if ($body) { [string]$body.text } else { '' }); ref = (& $m 'obsn.requestRef'); requestKind = (& $m 'obsn.requestKind')
        waitingSince = (& $m 'obsn.waitingSince'); chatUrl = (& $m 'obsn.chatUrl')
    }
}

function Invoke-VsCreatePage {
    param([hashtable]$Ctx, [hashtable]$Page)
    Assert-VsWritable $Ctx
    $bucket = [string]$Page['bucket']
    if (-not $bucket) { $bucket = Get-BucketForType -Type ([string]$Page['type']) }
    $target = Get-TargetSection -Bucket $bucket -Counts (Get-SectionCounts $Ctx.Model)
    $sid = Resolve-ObsnSection -Adapter $Ctx.Adapter -RootId $Ctx.Vault.rootId -Full $target.name
    $pageId = $Ctx.Adapter.CreateNewPage($sid)
    $rec = Get-VsPageRecord $Page
    $outs = @(@{ role = 'props'; lines = (Get-PropertiesLines $rec) })
    foreach ($o in @($Page['outlines'])) { if ($o) { $outs += @{ role = [string]$o['role']; lines = (ConvertTo-OutlineLines -Lines @($o['lines'])) } } }
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $pageId -Meta (ConvertTo-ObsnMeta -Page $rec) -Title ([string]$Page['title']) -Outlines $outs -NewPage
    @{ pageId = $pageId; link = $Ctx.Adapter.GetHyperlinkToObject($pageId); section = $target.name }
}

function Invoke-VsReadPage {
    param([hashtable]$Ctx, [string]$PageId)
    $xml = $Ctx.Adapter.GetPageContent($PageId)
    $p = ConvertFrom-ObsnPageXml -Xml $xml
    $t = ConvertFrom-ObsnPageText -Xml $xml
    @{ pageId = $PageId; title = $t.title; meta = (ConvertFrom-ObsnMeta -Meta $p.meta); outlines = $t.outlines }
}

function Invoke-VsUpdatePage {
    param([hashtable]$Ctx, [string]$PageId, [hashtable]$Meta, [object[]]$Outlines, [string]$Title)
    Assert-VsWritable $Ctx
    $m = if ($Meta) { $Meta } else { @{} }
    $rec = Get-VsPageRecord $m
    $outs = @(foreach ($o in @($Outlines)) { if ($o) { @{ role = [string]$o['role']; lines = (ConvertTo-OutlineLines -Lines @($o['lines'])) } } })
    if (@('topics', 'aliases', 'url', 'status', 'type' | Where-Object { $rec.ContainsKey($_) }).Count) {
        $cur = Invoke-VsReadPage -Ctx $Ctx -PageId $PageId
        $merged = $cur.meta
        foreach ($k in $rec.Keys) { $merged[$k] = $rec[$k] }
        $outs = @(@{ role = 'props'; lines = (Get-PropertiesLines $merged) }) + $outs
    }
    $a = @{ Adapter = $Ctx.Adapter; PageId = $PageId; Meta = $(if ($rec.Count) { ConvertTo-ObsnMeta -Page $rec } else { [ordered]@{} }); Outlines = $outs }
    if ($Title) { $a.Title = $Title }
    Write-ObsnPage @a
}

function Invoke-VsSetLinkedFrom {
    param([hashtable]$Ctx, [string]$Id, [object[]]$Sources)
    Assert-VsWritable $Ctx
    if (-not $Ctx.Model.pages.Contains($Id)) { throw "page $Id is not in the index" }
    $p = $Ctx.Model.pages[$Id]
    if ($p.owner -ne 'obsn') { throw "page $Id is not one of ObsidiNote's pages" }
    Write-ObsnPage -Adapter $Ctx.Adapter -PageId $p.oneNoteId -Outlines @(@{ role = 'backlinks'; lines = (Get-LinkedFromLines -Sources @($Sources | Where-Object { $_ })) })
}

function Invoke-VsDeletePage {
    <# To OneNote's Deleted Pages (DeleteHierarchy without "permanently"), through the guard. #>
    param([hashtable]$Ctx, [string]$PageId)
    Assert-VsWritable $Ctx
    $Ctx.Adapter.DeleteHierarchy($PageId)
    if ($Ctx.Model.byOneNoteId.ContainsKey($PageId)) {
        $k = $Ctx.Model.byOneNoteId[$PageId]
        if ($Ctx.Model.pages.Contains($k) -and -not (Test-ObsnId $Ctx.Model.pages[$k].id)) { $Ctx.Model.pages.Remove($k) }
        $Ctx.Model.byOneNoteId.Remove($PageId)
    }
}

function Invoke-VsIndexAddPage {
    param([hashtable]$Ctx, [hashtable]$Page, [switch]$Replace)
    Assert-VsWritable $Ctx
    $id = [string]$Page['id']
    $old = if ($Ctx.Model.pages.Contains($id)) { $Ctx.Model.pages[$id] } else { $null }
    $rec = @{}
    if ($old) { foreach ($k in @($old.Keys)) { $rec[$k] = $old[$k] } }
    foreach ($k in 'id', 'title', 'type', 'summary', 'topics', 'aliases', 'links', 'status', 'url', 'host', 'kind', 'summarizedAt', 'link', 'section') { if ($Page.ContainsKey($k)) { $rec[$k] = $Page[$k] } }
    if ($Page.ContainsKey('pageId') -and $Page['pageId']) { $rec.oneNoteId = [string]$Page['pageId'] }
    $rec.key = $id
    if ($rec.ContainsKey('section') -and $rec.section) { $b = Get-BucketOfSection ([string]$rec.section); $rec.bucket = $(if ($b) { $b } else { [string]$Page['bucket'] }) } elseif ($Page.ContainsKey('bucket')) { $rec.bucket = $Page['bucket'] }
    $rec.owner = 'obsn'
    $rec.updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')
    $rec.links = @(@($rec.links) | Where-Object { $_ } | ForEach-Object { @{ target = [string](Get-JsonProp $_ 'target' ''); strength = [int](Get-JsonProp $_ 'strength' 1); why = [string](Get-JsonProp $_ 'why' '') } })
    $null = Add-IndexPage -Model $Ctx.Model -Page $rec
    $topics = @($rec.topics) + $(if ($old) { @($old.topics) } else { @() })
    $null = Update-VsIndex -Ctx $Ctx -Topics $topics
}

function Invoke-VsIndexRemovePage {
    param([hashtable]$Ctx, [string]$Id)
    Assert-VsWritable $Ctx
    if (-not $Ctx.Model.pages.Contains($Id)) { return }
    $p = $Ctx.Model.pages[$Id]
    $Ctx.Model.pages.Remove($Id)
    if ($p.oneNoteId -and $Ctx.Model.byOneNoteId.ContainsKey($p.oneNoteId)) { $Ctx.Model.byOneNoteId.Remove($p.oneNoteId) }
    $Ctx.Model.deleted = Get-RecentlyDeleted -Deleted @($Ctx.Model.deleted) -Entry ([ordered]@{ title = $p.title; bucket = $p.bucket; date = (Get-Date).ToString('yyyy-MM-dd') })
    $null = Update-VsIndex -Ctx $Ctx -Topics @($p.topics)
}

function Invoke-VsMovePage {
    <# Re-files one of ObsidiNote's pages into $Bucket when a filing rule changed (an upgrade step,
       lib/Upgrade.psm1): moves it in OneNote through the guarded adapter (it keeps its content, Meta,
       outlines and the page-id in its link, but gets a NEW hierarchy id, found again by its obsn.id;
       probes/p9-move.ps1), sets $Type when given (Meta + properties outline), and updates the index
       record (id, section, link, type), which regenerates the affected Index pages. Returns
       @{ moved; pageId; from; to; link }. Throws when the page is not ObsidiNote's or cannot be found. #>
    param([hashtable]$Ctx, [string]$Id, [string]$Bucket, [string]$Type = '')
    Assert-VsWritable $Ctx
    if (-not $Ctx.Model.pages.Contains($Id)) { throw "page $Id is not in the index" }
    $p = $Ctx.Model.pages[$Id]
    if ($p.owner -ne 'obsn') { throw "page $Id is not one of ObsidiNote's pages" }
    $root = $Ctx.Vault.rootId
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Ctx.Adapter.GetHierarchy($root, 4)) -RootId $root
    $from = @($tree.sections | Where-Object { @($_.pages | Where-Object { $_.id -eq $p.oneNoteId }).Count }) | Select-Object -First 1
    if (-not $from) { throw "page $Id was not found in the vault" }
    $target = Get-TargetSection -Bucket $Bucket -Counts (Get-SectionCounts $Ctx.Model)
    if ($from.full -eq $target.name -or (Get-BucketOfSection $from.full) -eq $Bucket) { return @{ moved = $false; pageId = $p.oneNoteId; from = $from.full; to = $from.full; link = $p.link } }
    $sid = Resolve-ObsnSection -Adapter $Ctx.Adapter -RootId $root -Full $target.name
    $Ctx.Adapter.MovePage($p.oneNoteId, $from.id, $sid)
    $after = ConvertFrom-ObsnHierarchy -Xml ($Ctx.Adapter.GetHierarchy($root, 4)) -RootId $root
    $sec = @($after.sections | Where-Object { $_.full -eq $target.name }) | Select-Object -First 1
    $newId = if ($sec) { [string](@($sec.pages | Where-Object { $_.meta['obsn.id'] -eq $Id } | ForEach-Object { $_.id }) | Select-Object -First 1) } else { '' }
    if (-not $newId) { throw "page $Id was moved to $($target.name) but could not be found there again" }
    if ($Type) { Invoke-VsUpdatePage -Ctx $Ctx -PageId $newId -Meta @{ type = $Type } -Outlines @() }
    $old = [string]$p.oneNoteId
    if ($old -and $Ctx.Model.byOneNoteId.ContainsKey($old)) { $Ctx.Model.byOneNoteId.Remove($old) }
    $link = $Ctx.Adapter.GetHyperlinkToObject($newId)
    $rec = @{ id = $Id; pageId = $newId; section = $target.name; link = $link }
    if ($Type) { $rec.type = $Type }
    Invoke-VsIndexAddPage -Ctx $Ctx -Page $rec
    @{ moved = $true; pageId = $newId; from = $from.full; to = $target.name; link = $link }
}

function Invoke-VsFindPageByUrl {
    param([hashtable]$Ctx, [string]$Url)
    $n = ConvertTo-NormalizedUrl -Url $Url
    foreach ($p in $Ctx.Model.pages.Values) {
        if ($p.url -and (Test-ObsnId $p.id) -and (ConvertTo-NormalizedUrl -Url ([string]$p.url)) -eq $n) { return (ConvertTo-IngestPage $p) }
    }
    $null
}

function Invoke-VaultStoreCall {
    <# The one entry the store's scriptblocks call (closures made in a module cannot see the module's
       functions, so each one holds this command and its context). #>
    param([Parameter(Mandatory)][hashtable]$Ctx, [Parameter(Mandatory)][string]$Name, [hashtable]$Arguments = @{})
    switch ($Name) {
        'AssertWritable' { Assert-VsWritable $Ctx; return }
        'GetIndex' { return (Get-IngestIndex $Ctx.Model) }
        'TypeList' { return (Get-ObsnTypes) }
        'BucketForType' { return (Get-BucketForType -Type $Arguments.Type) }
        'LinkBucket' { return (Get-LinkBucket -Url $Arguments.Url -InternalHosts $Ctx.InternalHosts -CompanyNames $Ctx.CompanyNames) }
        'NormalizeUrl' { return (ConvertTo-NormalizedUrl -Url $Arguments.Url) }
        'FindPageByUrl' { return (Invoke-VsFindPageByUrl -Ctx $Ctx -Url $Arguments.Url) }
        'NewId' { return (Invoke-VsNewId $Ctx) }
        'CreateInboxItem' { return (Invoke-VsCreateInboxItem -Ctx $Ctx @Arguments) }
        'SetInboxStatus' { return (Invoke-VsSetInboxStatus -Ctx $Ctx @Arguments) }
        'SetInboxWaiting' { return (Invoke-VsSetInboxWaiting -Ctx $Ctx @Arguments) }
        'ReadInboxItem' { return (Invoke-VsReadInboxItem -Ctx $Ctx @Arguments) }
        'CreatePage' { return (Invoke-VsCreatePage -Ctx $Ctx @Arguments) }
        'ReadPage' { return (Invoke-VsReadPage -Ctx $Ctx @Arguments) }
        'UpdatePage' { return (Invoke-VsUpdatePage -Ctx $Ctx @Arguments) }
        'SetLinkedFrom' { return (Invoke-VsSetLinkedFrom -Ctx $Ctx @Arguments) }
        'DeletePage' { return (Invoke-VsDeletePage -Ctx $Ctx @Arguments) }
        'IndexAddPage' { return (Invoke-VsIndexAddPage -Ctx $Ctx @Arguments) }
        'IndexUpdatePage' { return (Invoke-VsIndexAddPage -Ctx $Ctx @Arguments) }
        'IndexRemovePage' { return (Invoke-VsIndexRemovePage -Ctx $Ctx @Arguments) }
        'MovePage' { return (Invoke-VsMovePage -Ctx $Ctx @Arguments) }
        'Model' { return $Ctx.Model }
    }
    throw "The store has no '$Name'."
}

function New-VaultStore {
    <# The store adapter for lib/Ingest.psm1 over the active vault. $Adapter: the guarded adapter (its
       write root must be the vault's root); $Vault: @{ vaultId; name; rootId; indexSectionId };
       $Model: the vault's in-memory index model (updated in place); $GetLease: returns the current
       lease record (renewed elsewhere). Returns a hashtable with one scriptblock per contract name. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Vault, [Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][scriptblock]$GetLease, [string[]]$InternalHosts = @(), [string[]]$CompanyNames = @())
    # CompanyNames: the company's tenant names (Get-CompanyNames), so its SaaS links file as internal.
    $ctx = @{ Adapter = $Adapter; Vault = $Vault; Model = $Model; GetLease = $GetLease; InternalHosts = @($InternalHosts); CompanyNames = @($CompanyNames) }
    $call = Get-Command Invoke-VaultStoreCall
    $name = [string]$Vault.name
    @{
        AssertWritable  = { & $call $ctx 'AssertWritable' }.GetNewClosure()
        VaultName       = { $name }.GetNewClosure()
        GetIndex        = { & $call $ctx 'GetIndex' }.GetNewClosure()
        TypeList        = { & $call $ctx 'TypeList' }.GetNewClosure()
        BucketForType   = { param([string]$Type) & $call $ctx 'BucketForType' @{ Type = $Type } }.GetNewClosure()
        LinkBucket      = { param([string]$Url) & $call $ctx 'LinkBucket' @{ Url = $Url } }.GetNewClosure()
        NormalizeUrl    = { param([string]$Url) & $call $ctx 'NormalizeUrl' @{ Url = $Url } }.GetNewClosure()
        FindPageByUrl   = { param([string]$Url) & $call $ctx 'FindPageByUrl' @{ Url = $Url } }.GetNewClosure()
        NewId           = { & $call $ctx 'NewId' }.GetNewClosure()
        CreateInboxItem = { param([string]$Title, [string]$Text, [string]$Kind, [string]$Ref, [string]$RequestKind) & $call $ctx 'CreateInboxItem' @{ Title = $Title; Text = $Text; Kind = $Kind; Ref = $Ref; RequestKind = $RequestKind } }.GetNewClosure()
        SetInboxStatus  = { param([string]$PageId, [string]$Status, [string]$Reason, [string]$Id) & $call $ctx 'SetInboxStatus' @{ PageId = $PageId; Status = $Status; Reason = $Reason; Id = $Id } }.GetNewClosure()
        SetInboxWaiting = { param([string]$PageId, [string]$Ref, [string]$RequestKind, [string]$ChatUrl, [string]$Since) & $call $ctx 'SetInboxWaiting' @{ PageId = $PageId; Ref = $Ref; RequestKind = $RequestKind; ChatUrl = $ChatUrl; Since = $Since } }.GetNewClosure()
        ReadInboxItem   = { param([string]$PageId) & $call $ctx 'ReadInboxItem' @{ PageId = $PageId } }.GetNewClosure()
        CreatePage      = { param([hashtable]$Page) & $call $ctx 'CreatePage' @{ Page = $Page } }.GetNewClosure()
        ReadPage        = { param([string]$PageId) & $call $ctx 'ReadPage' @{ PageId = $PageId } }.GetNewClosure()
        UpdatePage      = { param([string]$PageId, [hashtable]$Meta, [object[]]$Outlines, [string]$Title) & $call $ctx 'UpdatePage' @{ PageId = $PageId; Meta = $Meta; Outlines = $Outlines; Title = $Title } }.GetNewClosure()
        SetLinkedFrom   = { param([string]$Id, [object[]]$Sources) & $call $ctx 'SetLinkedFrom' @{ Id = $Id; Sources = $Sources } }.GetNewClosure()
        DeletePage      = { param([string]$PageId) & $call $ctx 'DeletePage' @{ PageId = $PageId } }.GetNewClosure()
        IndexAddPage    = { param([hashtable]$Page) & $call $ctx 'IndexAddPage' @{ Page = $Page } }.GetNewClosure()
        IndexUpdatePage = { param([hashtable]$Page) & $call $ctx 'IndexUpdatePage' @{ Page = $Page } }.GetNewClosure()
        IndexRemovePage = { param([string]$Id) & $call $ctx 'IndexRemovePage' @{ Id = $Id } }.GetNewClosure()
        # Upgrade steps (lib/Upgrade.psm1), not part of Ingest's contract.
        MovePage        = { param([string]$Id, [string]$Bucket, [string]$Type) & $call $ctx 'MovePage' @{ Id = $Id; Bucket = $Bucket; Type = $Type } }.GetNewClosure()
        Model           = { & $call $ctx 'Model' }.GetNewClosure()
        LinkRules       = { @{ InternalHosts = $ctx.InternalHosts; CompanyNames = $ctx.CompanyNames } }.GetNewClosure()
    }
}

Export-ModuleMember -Function New-VaultStore, ConvertTo-OutlineLines, ConvertTo-IngestPage, Get-IngestIndex, Get-AffectedIndexKeys, Get-RecentlyDeleted, Write-AffectedIndexPages
