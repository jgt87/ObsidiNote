# The central index (FEASIBILITY.md section 5, Central index): an in-memory model of a vault (topic
# tree, pages, edges), loaded from the `00 Index` section's obsn.* Meta (fast) or rebuilt from the
# content pages' own Meta (the source of truth; the page wins), the completeness rule, the
# generated Index pages, path-based retrieval, and the same model derived read-only for a connected
# (foreign) notebook. Page Meta comes from GetHierarchy at page scope (it carries page-level Meta),
# so a load is one COM call per section tree. PS 5.1, ASCII only. Writes nothing to disk; logs none.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')
Import-Module (Join-Path $PSScriptRoot 'Vault.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriterLease.psm1')

$script:IndexSection = '00 Index'
# Intake pages are Add requests, not content: a filed one has become its own page, a waiting or
# failed one shows in the window's Intake card. Listing them made every Add show twice on the map
# (the filed page, and its request under Unfiled with the pasted text as title; seen live 2026-11-13).
# '01 Inbox' is the section's old name (before the one-time rename).
$script:RequestSections = @((Get-ObsnIntakeSection), '01 Inbox')
$script:MaxLinesPerPage = 400

function Test-RequestSection([string]$Full) { $script:RequestSections -contains $Full }
$script:MaxMetaChars = 30000

# ---------------------------------------------------------------- model

function New-IndexModel {
    <# An empty model. kind: vault | foreign. #>
    param([string]$Kind = 'vault', [string]$VaultId = '', [string]$RootId = '')
    @{
        schema = (Get-ObsnSchemaVersion); kind = $Kind; vaultId = $VaultId; rootId = $RootId; readOnly = ($Kind -ne 'vault')
        idCounter = [int64]1; topics = [ordered]@{}; pages = [ordered]@{}; byOneNoteId = @{}
        deleted = @(); indexPages = @{}; indexLinks = @{}; source = ''
    }
}

function Add-IndexTopic {
    <# Adds a topic path and its parents. Returns the topic @{ path; name; parent; children }. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][string]$Path)
    $p = ConvertTo-TopicPath $Path
    if (-not $p) { return $null }
    if ($Model.topics.Contains($p)) { return $Model.topics[$p] }
    $segs = $p.Split('/')
    $parent = ''
    if ($segs.Count -gt 1) { $parent = ($segs[0..($segs.Count - 2)] -join '/'); $null = Add-IndexTopic -Model $Model -Path $parent }
    $t = @{ path = $p; name = $segs[-1]; parent = $parent; children = (New-Object System.Collections.ArrayList) }
    $Model.topics[$p] = $t
    if ($parent) { $null = $Model.topics[$parent].children.Add($p) }
    $t
}

function New-PageRecord {
    param([hashtable]$From = @{})
    $r = @{ key = ''; id = ''; title = ''; type = ''; bucket = ''; section = ''; oneNoteId = ''; link = ''; summary = ''; topics = @(); aliases = @(); status = ''; url = ''; host = ''; kind = ''; summarizedAt = ''; archivedFrom = ''; links = @(); updated = ''; owner = 'obsn'; level = 1; parent = '' }
    foreach ($k in @($From.Keys)) { $r[$k] = $From[$k] }
    $r.topics = @(@($r.topics) | Where-Object { $_ } | ForEach-Object { ConvertTo-TopicPath ([string]$_) } | Where-Object { $_ })
    $r.aliases = @(@($r.aliases) | Where-Object { $_ })
    $r.links = @(@($r.links) | Where-Object { $_ })
    if (-not $r.key) { $r.key = if ($r.id) { $r.id } else { 'n:' + $r.oneNoteId } }
    $r
}

function Add-IndexPage {
    <# Adds (or replaces) a page record. Its topics are added to the tree. Returns the record. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Page)
    $r = New-PageRecord $Page
    $Model.pages[$r.key] = $r
    if ($r.oneNoteId) { $Model.byOneNoteId[$r.oneNoteId] = $r.key }
    foreach ($t in $r.topics) { $null = Add-IndexTopic -Model $Model -Path $t }
    $n = Get-ObsnIdNumber $r.id
    if ($n -ge $Model.idCounter) { $Model.idCounter = $n + 1 }
    $r
}

function Get-IndexEdges {
    <# All edges: @(@{ from; to; strength; why }) from the pages' own links. #>
    param([Parameter(Mandatory)][hashtable]$Model)
    $e = @(foreach ($p in $Model.pages.Values) { foreach ($l in @($p.links)) { @{ from = $p.key; to = $l.target; strength = $l.strength; why = $l.why } } })
    $e
}

function Get-TopicPages {
    <# Pages filed directly under $Path (not its subtopics). #>
    param([hashtable]$Model, [string]$Path)
    @($Model.pages.Values | Where-Object { @($_.topics) -contains $Path })
}

function Get-TopicSubtreeCount {
    param([hashtable]$Model, [string]$Path, [switch]$IncludeArchived)
    $pre = $Path + '/'
    @($Model.pages.Values | Where-Object { ($IncludeArchived -or $_.status -ne 'archived') -and @($_.topics | Where-Object { $_ -eq $Path -or $_.StartsWith($pre) }).Count }).Count
}

function Test-PageUnfiled { param([hashtable]$Page) (-not @($Page.topics).Count) -and $Page.owner -ne 'user-section' }

# ---------------------------------------------------------------- compact entries (index Meta)

$script:EntryMap = [ordered]@{ id = 'i'; title = 't'; oneNoteId = 'o'; link = 'k'; bucket = 'b'; section = 'c'; type = 'y'; topics = 'p'; summary = 's'; status = 'st'; url = 'u'; host = 'h'; kind = 'kd'; summarizedAt = 'sa'; archivedFrom = 'af'; aliases = 'a'; links = 'l'; updated = 'm'; owner = 'w' }

function ConvertTo-IndexEntry {
    param([Parameter(Mandatory)][hashtable]$Page)
    $o = [ordered]@{}
    foreach ($k in $script:EntryMap.Keys) {
        $v = $Page[$k]
        if ($k -eq 'links') { $v = @(@($v) | ForEach-Object { [ordered]@{ t = $_.target; s = [int]$_.strength; w = [string]$_.why } }); if (-not $v.Count) { continue } }
        elseif ($k -eq 'topics' -or $k -eq 'aliases') { $v = @($v); if (-not $v.Count) { continue } }
        elseif ($k -eq 'owner') { if ($v -eq 'obsn') { continue } }
        elseif (-not $v) { continue }
        $o[$script:EntryMap[$k]] = $v
    }
    $o
}

function ConvertFrom-IndexEntry {
    param($Entry)
    $h = @{}
    foreach ($k in $script:EntryMap.Keys) {
        $v = Get-JsonProp $Entry $script:EntryMap[$k] $null
        if ($null -eq $v) { continue }
        if ($k -eq 'links') { $h[$k] = @(@($v) | ForEach-Object { @{ target = [string](Get-JsonProp $_ 't' ''); strength = [int](Get-JsonProp $_ 's' 1); why = [string](Get-JsonProp $_ 'w' '') } }) }
        elseif ($k -eq 'topics' -or $k -eq 'aliases') { $h[$k] = @(@($v) | ForEach-Object { [string]$_ }) }
        else { $h[$k] = [string]$v }
    }
    $h
}

function ConvertTo-EntriesValue { param([object[]]$Pages) ConvertTo-CompactJson -Value @(@($Pages) | ForEach-Object { ConvertTo-IndexEntry $_ }) }

# ---------------------------------------------------------------- load: index Meta (fast)

function ConvertFrom-IndexSectionXml {
    <# The model from the `00 Index` section's hierarchy XML at page scope (pure): the state page
       (counter, deleted list), topic hubs (obsn.topic + obsn.entries), Unfiled and Other sections
       (obsn.entries). Index page ids by obsn.indexKey go to indexPages. #>
    param([Parameter(Mandatory)][string]$Xml, [string]$VaultId = '', [string]$RootId = '')
    $m = New-IndexModel -Kind 'vault' -VaultId $VaultId -RootId $RootId
    $m.source = 'index'
    [xml]$doc = $Xml
    foreach ($p in @($doc.SelectNodes("//*[local-name()='Page']"))) {
        if ($p.GetAttribute('isInRecycleBin') -eq 'true') { continue }
        $meta = @{}
        foreach ($x in @($p.ChildNodes)) { if ($x.NodeType -eq 'Element' -and $x.LocalName -eq 'Meta') { $meta[$x.GetAttribute('name')] = $x.GetAttribute('content') } }
        $key = [string]$meta['obsn.indexKey']
        if (-not $key) { continue }
        $m.indexPages[$key] = $p.GetAttribute('ID')
        if ($key -eq 'state') {
            if (-not $m.vaultId) { $m.vaultId = [string]$meta['obsn.vaultId'] }
            $c = [int64]1; [void][int64]::TryParse([string]$meta['obsn.idCounter'], [ref]$c)
            if ($c -gt $m.idCounter) { $m.idCounter = $c }
            $m.deleted = @(ConvertFrom-JsonList ([string]$meta['obsn.deleted']))
            continue
        }
        if ($meta.ContainsKey('obsn.topic') -and $meta['obsn.topic']) { $null = Add-IndexTopic -Model $m -Path $meta['obsn.topic'] }
        $entries = Join-ObsnMetaValue -Meta $meta -Name 'obsn.entries'
        foreach ($e in (ConvertFrom-JsonList $entries)) {
            $h = ConvertFrom-IndexEntry $e
            $k = if ($h['id']) { $h['id'] } else { 'n:' + $h['oneNoteId'] }
            if (-not $m.pages.Contains($k)) { $null = Add-IndexPage -Model $m -Page $h }
        }
    }
    $m
}

function Read-IndexModel {
    <# Fast load of a vault's index: one hierarchy read of its `00 Index` section. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$IndexSectionId, [string]$VaultId = '', [string]$RootId = '')
    $m = ConvertFrom-IndexSectionXml -Xml ($Adapter.GetHierarchy($IndexSectionId, 4)) -VaultId $VaultId -RootId $RootId
    Remove-RequestEntries $m
    $m
}

function Remove-RequestEntries {
    <# Index pages written before 2026-11-13 can still list Intake pages; a vault that is only read
       (never rewritten by this session) would show them. Drops them from a loaded model. #>
    param([Parameter(Mandatory)][hashtable]$Model)
    foreach ($k in @($Model.pages.Keys)) {
        $p = $Model.pages[$k]
        if (-not (Test-RequestSection ([string]$p.section))) { continue }
        $Model.pages.Remove($k)
        if ($p.oneNoteId -and $Model.byOneNoteId.ContainsKey($p.oneNoteId)) { $Model.byOneNoteId.Remove($p.oneNoteId) }
    }
}

# ---------------------------------------------------------------- rebuild: content pages' Meta

function Get-PageRecordFromHierarchy {
    <# A page record from a parsed hierarchy page (ConvertFrom-ObsnHierarchy). Pages with a valid
       obsn.id are ObsidiNote's; others belong to the user (owner user, or user-section when the
       section itself is the user's). #>
    param([Parameter(Mandatory)][hashtable]$HPage)
    $bucket = Get-BucketOfSection $HPage.section
    $base = @{ oneNoteId = $HPage.id; title = $HPage.title; section = $HPage.section; updated = $HPage.updated; level = $HPage.level }
    $id = [string]$HPage.meta['obsn.id']
    if ($bucket -and (Test-ObsnId $id)) {
        $r = ConvertFrom-ObsnMeta -Meta $HPage.meta
        foreach ($k in @($base.Keys)) { $r[$k] = $base[$k] }
        $r.bucket = $bucket
        if ($bucket -eq 'Archive' -and -not $r.status) { $r.status = 'archived' }
        $r.owner = 'obsn'
        return $r
    }
    $base.bucket = $bucket
    $base.owner = if ($bucket) { 'user' } else { 'user-section' }
    $base
}

function ConvertFrom-VaultScan {
    <# Rebuild (pure): the model from the vault root's hierarchy at page scope; every content page's
       own Meta is the truth. Pages in `00 Index` are the index itself and are left out, except the
       state page's counter. #>
    param([Parameter(Mandatory)][hashtable]$Tree, [string]$VaultId = '')
    $m = New-IndexModel -Kind 'vault' -VaultId $VaultId -RootId $Tree.notebook.id
    $m.source = 'scan'
    foreach ($s in $Tree.sections) {
        if ($s.full -eq $script:IndexSection) {
            foreach ($p in $s.pages) {
                if ($p.meta['obsn.indexKey'] -eq 'state') {
                    $c = [int64]1; [void][int64]::TryParse([string]$p.meta['obsn.idCounter'], [ref]$c)
                    if ($c -gt $m.idCounter) { $m.idCounter = $c }
                    if (-not $m.vaultId) { $m.vaultId = [string]$p.meta['obsn.vaultId'] }
                    $m.deleted = @(ConvertFrom-JsonList ([string]$p.meta['obsn.deleted']))
                }
            }
            continue
        }
        if (Test-RequestSection $s.full) { continue }
        foreach ($p in $s.pages) { $null = Add-IndexPage -Model $m -Page (Get-PageRecordFromHierarchy $p) }
    }
    $m
}

function Read-VaultScan {
    <# Rebuild scan through the adapter: one hierarchy read of the vault root at page scope. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$RootId, [string]$VaultId = '')
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 4)) -RootId $RootId
    ConvertFrom-VaultScan -Tree $tree -VaultId $VaultId
}

function Merge-IndexWithScan {
    <# Page wins: the scan's pages replace the index's; the index adds only what pages do not carry
       (their onenote: links, empty topics, index page ids). Returns @{ model; added; removed; changed }
       (keys of pages that differ). #>
    param([Parameter(Mandatory)][hashtable]$Index, [Parameter(Mandatory)][hashtable]$Scan)
    $added = @(); $removed = @(); $changed = @()
    foreach ($k in @($Scan.pages.Keys)) {
        $s = $Scan.pages[$k]
        if (-not $Index.pages.Contains($k)) { $added += $k; continue }
        $i = $Index.pages[$k]
        if (-not $s.link -and $i.link -and $i.oneNoteId -eq $s.oneNoteId) { $s.link = $i.link }
        $a = ConvertTo-CompactJson (ConvertTo-IndexEntry $s); $b = ConvertTo-CompactJson (ConvertTo-IndexEntry $i)
        if ($a -ne $b) { $changed += $k }
    }
    foreach ($k in @($Index.pages.Keys)) { if (-not $Scan.pages.Contains($k)) { $removed += $k } }
    foreach ($t in @($Index.topics.Keys)) { $null = Add-IndexTopic -Model $Scan -Path $t }
    foreach ($k in @($Index.indexPages.Keys)) { $Scan.indexPages[$k] = $Index.indexPages[$k] }
    if ($Index.idCounter -gt $Scan.idCounter) { $Scan.idCounter = $Index.idCounter }
    if (-not $Scan.vaultId) { $Scan.vaultId = $Index.vaultId }
    @{ model = $Scan; added = $added; removed = $removed; changed = $changed }
}

# ---------------------------------------------------------------- completeness

function Get-ContentPageList {
    <# Every page of the vault tree outside `00 Index` and the Intake (the recycle bin is already
       left out). #>
    param([Parameter(Mandatory)][hashtable]$Tree)
    @(foreach ($s in $Tree.sections) { if ($s.full -ne $script:IndexSection -and -not (Test-RequestSection $s.full)) { foreach ($p in $s.pages) { $p } } })
}

function Test-IndexComplete {
    <# Completeness rule: every page id in the hierarchy must be in the index. Returns the missing
       pages @(@{ oneNoteId; title; section }) (empty = complete). Pure. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Tree)
    @(foreach ($p in @(Get-ContentPageList $Tree)) {
        if (-not $Model.byOneNoteId.ContainsKey($p.id)) { @{ oneNoteId = $p.id; title = $p.title; section = $p.section } }
    })
}

function Repair-IndexCompleteness {
    <# Adds every missing page to the model (its own Meta when it has one; without topics it shows on
       Unfiled). Returns the missing list it repaired. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Tree)
    $missing = @(Test-IndexComplete -Model $Model -Tree $Tree)
    if (-not $missing.Count) { return }
    $want = @{}; foreach ($x in $missing) { $want[$x.oneNoteId] = $true }
    foreach ($p in @(Get-ContentPageList $Tree)) { if ($want.ContainsKey($p.id)) { $null = Add-IndexPage -Model $Model -Page (Get-PageRecordFromHierarchy $p) } }
    $missing
}

# ---------------------------------------------------------------- generated Index pages (pure)

function Get-LinkGroup {
    <# Links page grouping: SharePoint/OneDrive by site (host + /sites/x, /teams/x, /personal/x),
       Teams as 'Teams', other internal by host; web links by domain without www. #>
    param([hashtable]$Page)
    $u = [string]$Page.url
    $h = if ($Page.host) { [string]$Page.host } else { Get-UrlHost $u }
    if (-not $h) { return '(no link)' }
    if ($Page.bucket -eq 'Internal links' -or $Page.type -eq 'link-internal') {
        $m = [regex]::Match($u, '^(?i)https?://[^/]+/(sites|teams|personal)/([^/?#]+)')
        if ($m.Success) { return "$h/$($m.Groups[1].Value.ToLowerInvariant())/$($m.Groups[2].Value)" }
        if ($h -like 'teams.*') { return 'Teams' }
        return $h
    }
    $h -replace '^www\.', ''
}

function Get-PageLine {
    param([hashtable]$Page, [switch]$WithBucket, [switch]$WithTopics, [switch]$WithSummary)
    $h = New-OneLink -Href $Page.link -Label $Page.title
    $extra = @()
    if ($WithBucket) { $b = if ($Page.bucket) { $Page.bucket } else { $Page.section }; if ($b) { $extra += $b } }
    if ($WithTopics -and @($Page.topics).Count) { $extra += ((@($Page.topics) | ForEach-Object { Format-TopicPath $_ }) -join '; ') }
    if ($Page.status -eq 'archived') { $extra += 'archived' }
    if ($extra.Count) { $h += ' (' + (ConvertTo-OneHtml ($extra -join ' | ')) + ')' }
    if ($WithSummary -and $Page.summary) { $h += ' - ' + (ConvertTo-OneHtml $Page.summary) }
    New-OneLine -Html $h
}

function Split-SpecLines {
    <# Pages a long list: @(lines) -> @(@(lines)...) of at most $Max lines (a collapsed group counts
       its children). #>
    param([object[]]$Lines, [int]$Max)
    $parts = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList; $n = 0
    foreach ($l in @($Lines)) {
        $size = 1 + @($l['children']).Count
        if ($n -gt 0 -and $n + $size -gt $Max) { $null = $parts.Add(@($cur)); $cur = New-Object System.Collections.ArrayList; $n = 0 }
        $null = $cur.Add($l); $n += $size
    }
    if ($cur.Count -or -not $parts.Count) { $null = $parts.Add(@($cur)) }
    , @($parts)
}

function Add-Spec {
    param([System.Collections.ArrayList]$Specs, [string]$Key, [string]$Title, [System.Collections.IDictionary]$Meta, [object[]]$Head, [object[]]$Lines, [int]$Max)
    $parts = Split-SpecLines -Lines $Lines -Max $Max
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $k = if ($i -eq 0) { $Key } else { "$Key#$($i + 1)" }
        $t = if ($i -eq 0) { $Title } else { "$Title ($($i + 1))" }
        $mm = if ($i -eq 0) { $Meta } else { [ordered]@{} }
        $hd = if ($i -eq 0) { @($Head) } else { @(New-OneLine -Text "Continued from $Title.") }
        $null = $Specs.Add(@{ key = $k; title = $t; meta = $mm; lines = @(@($hd) + @($parts[$i])) })
    }
}

function Get-IndexPageSpecs {
    <# The generated Index pages for a model (pure): @(@{ key; title; meta; lines }). Keys: root,
       bytype, az, unfiled, links, archive, other, topic:<path>, state; a long page continues as
       <key>#2 ('<Title> (2)'), at most $MaxLines lines each. $Links: index key -> onenote: link of
       that index page (for the links between Index pages). Data Meta: hubs carry obsn.topic,
       obsn.parent, obsn.children and obsn.entries (their pages); Unfiled and Other sections carry
       obsn.entries; together they hold every page. #>
    param([Parameter(Mandatory)][hashtable]$Model, [hashtable]$Links = @{}, [int]$MaxLines = $script:MaxLinesPerPage, [int]$MaxMeta = $script:MaxMetaChars)
    $specs = New-Object System.Collections.ArrayList
    $all = @($Model.pages.Values | Sort-Object { $_.title })
    $active = @($all | Where-Object { $_.status -ne 'archived' })
    $lk = { param($k, $label) New-OneLine -Html (New-OneLink -Href $Links[$k] -Label $label) }

    # topic hubs
    foreach ($t in $Model.topics.Values) {
        $pages = @(Get-TopicPages -Model $Model -Path $t.path | Sort-Object { $_.title })
        $live = @($pages | Where-Object { $_.status -ne 'archived' }); $arch = @($pages | Where-Object { $_.status -eq 'archived' })
        $crumb = 'Index'
        $acc = ''
        foreach ($seg in $t.path.Split('/')) { $acc = if ($acc) { "$acc/$seg" } else { $seg }; $crumb += ' > ' + $seg }
        $head = @(New-OneLine -Text "Path: $crumb")
        if ($t.parent) { $head += & $lk "topic:$($t.parent)" ('Up: ' + (Format-TopicPath $t.parent)) } else { $head += & $lk 'root' 'Up: Index' }
        $lines = @()
        if ($t.children.Count) {
            $lines += New-OneLine -Text "Subtopics ($($t.children.Count))" -Bold
            foreach ($c in ($t.children | Sort-Object)) { $lines += & $lk "topic:$c" ("$($Model.topics[$c].name) ($(Get-TopicSubtreeCount -Model $Model -Path $c))") }
        }
        $lines += New-OneLine -Text "Pages ($($live.Count))" -Bold
        foreach ($p in $live) { $lines += Get-PageLine $p -WithBucket -WithSummary }
        if ($arch.Count) { $lines += New-OneLine -Text "Archived ($($arch.Count))" -Collapsed -Children @($arch | ForEach-Object { Get-PageLine $_ -WithBucket }) }
        $meta = [ordered]@{ 'obsn.topic' = $t.path; 'obsn.parent' = $t.parent; 'obsn.children' = (ConvertTo-CompactJson -Value @($t.children)) }
        foreach ($kv in (Split-ObsnMetaValue -Name 'obsn.entries' -Value (ConvertTo-EntriesValue $pages) -Max $MaxMeta).GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
        Add-Spec -Specs $specs -Key "topic:$($t.path)" -Title ('Topic: ' + (Format-TopicPath $t.path)) -Meta $meta -Head $head -Lines $lines -Max $MaxLines
    }

    # Unfiled
    $unf = @($all | Where-Object { Test-PageUnfiled $_ })
    $meta = [ordered]@{}
    foreach ($kv in (Split-ObsnMetaValue -Name 'obsn.entries' -Value (ConvertTo-EntriesValue $unf) -Max $MaxMeta).GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
    Add-Spec -Specs $specs -Key 'unfiled' -Title 'Unfiled' -Meta $meta -Head @(New-OneLine -Text "Pages without a topic ($($unf.Count)), including your own pages in ObsidiNote's sections. They stay here until they are placed.") -Lines @($unf | ForEach-Object { Get-PageLine $_ -WithBucket }) -Max $MaxLines

    # Other sections (the user's own sections, listed only)
    $usr = @($all | Where-Object { $_.owner -eq 'user-section' })
    $meta = [ordered]@{}
    foreach ($kv in (Split-ObsnMetaValue -Name 'obsn.entries' -Value (ConvertTo-EntriesValue $usr) -Max $MaxMeta).GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
    $lines = @()
    foreach ($g in ($usr | Group-Object { $_.section } | Sort-Object Name)) {
        $lines += New-OneLine -Text "$($g.Name) ($($g.Count))" -Bold
        foreach ($p in $g.Group) { $lines += Get-PageLine $p }
    }
    Add-Spec -Specs $specs -Key 'other' -Title 'Other sections' -Meta $meta -Head @(New-OneLine -Text 'Sections you made yourself. ObsidiNote lists them and never edits or moves them.') -Lines $lines -Max $MaxLines

    # By type
    $lines = @()
    foreach ($g in ($active | Where-Object { $_.owner -ne 'user-section' } | Group-Object { if ($_.bucket) { $_.bucket } else { $_.section } } | Sort-Object Name)) {
        $lines += New-OneLine -Text "$($g.Name) ($($g.Count))" -Bold
        foreach ($p in $g.Group) { $lines += Get-PageLine $p -WithTopics }
    }
    Add-Spec -Specs $specs -Key 'bytype' -Title 'By type' -Meta ([ordered]@{}) -Head @(New-OneLine -Text 'Every page, one list per bucket.') -Lines $lines -Max $MaxLines

    # A-Z
    $lines = @()
    foreach ($g in ($all | Group-Object { $c = ([string]$_.title).Trim(); if ($c -and [char]::IsLetter($c[0])) { [string]([char]::ToUpperInvariant($c[0])) } else { '#' } } | Sort-Object Name)) {
        $lines += New-OneLine -Text $g.Name -Bold
        foreach ($p in $g.Group) { $lines += Get-PageLine $p -WithBucket -WithTopics }
    }
    Add-Spec -Specs $specs -Key 'az' -Title 'A-Z' -Meta ([ordered]@{}) -Head @(New-OneLine -Text "Every page title ($($all.Count)), with its bucket and topics.") -Lines $lines -Max $MaxLines

    # Links
    $lines = @()
    foreach ($b in 'Internal links', 'Web links') {
        $lp = @($all | Where-Object { $_.bucket -eq $b -or ($_.status -eq 'archived' -and ($_.type -eq $(if ($b -eq 'Web links') { 'link-web' } else { 'link-internal' }))) })
        $lines += New-OneLine -Text "$b ($($lp.Count))" -Bold
        foreach ($g in ($lp | Group-Object { Get-LinkGroup $_ } | Sort-Object Name)) {
            $lines += New-OneLine -Text "$($g.Name) ($($g.Count))"
            foreach ($p in $g.Group) { $lines += Get-PageLine $p }
        }
    }
    Add-Spec -Specs $specs -Key 'links' -Title 'Links' -Meta ([ordered]@{}) -Head @(New-OneLine -Text 'Internal links by site or team, web links by domain.') -Lines $lines -Max $MaxLines

    # Archive
    $arch = @($all | Where-Object { $_.status -eq 'archived' })
    $lines = @()
    foreach ($g in ($arch | Group-Object { if ($_.archivedFrom) { $_.archivedFrom } else { '(unknown bucket)' } } | Sort-Object Name)) {
        $lines += New-OneLine -Text "$($g.Name) ($($g.Count))" -Bold
        foreach ($p in $g.Group) { $lines += Get-PageLine $p -WithTopics }
    }
    Add-Spec -Specs $specs -Key 'archive' -Title 'Archive' -Meta ([ordered]@{}) -Head @(New-OneLine -Text 'Archived pages by their original bucket. Restore puts a page back.') -Lines $lines -Max $MaxLines

    # root
    $counts = Get-IndexCounts -Model $Model
    $lines = @(New-OneLine -Text 'Lists' -Bold)
    $lines += & $lk 'bytype' "By type ($($counts.pages) pages)"
    $lines += & $lk 'az' 'A-Z'
    $lines += & $lk 'unfiled' "Unfiled ($($counts.unfiled))"
    $lines += & $lk 'links' "Links ($($counts.internalLinks) internal, $($counts.webLinks) web)"
    $lines += & $lk 'archive' "Archive ($($counts.archived))"
    $lines += & $lk 'other' "Other sections ($($counts.userSectionPages) pages)"
    $lines += & $lk 'state' 'ObsidiNote (state)'
    $tops = @($Model.topics.Values | Where-Object { -not $_.parent } | Sort-Object { $_.name })
    $lines += New-OneLine -Text "Topics ($($counts.topics); $($tops.Count) at the top)" -Bold
    foreach ($t in $tops) { $lines += & $lk "topic:$($t.path)" "$($t.name) ($(Get-TopicSubtreeCount -Model $Model -Path $t.path))" }
    $lines += New-OneLine -Text 'Pages per bucket' -Bold
    foreach ($kv in ($counts.buckets.GetEnumerator() | Sort-Object Name)) { $lines += New-OneLine -Text "$($kv.Name): $($kv.Value)" }
    $null = $specs.Insert(0, @{ key = 'root'; title = 'Index'; meta = [ordered]@{ 'obsn.counts' = (ConvertTo-CompactJson -Value $counts) }; lines = @(@(New-OneLine -Text 'The central index of this ObsidiNote vault. Generated by the app; edits here are overwritten.') + $lines) })

    # state (no lease, no vault id: those are written by their own code)
    $sl = @(New-OneLine -Text 'ObsidiNote keeps its state on this page (vault id, id counter, who is writing). It is rewritten by the app; please do not edit it.')
    $sl += New-OneLine -Text "Schema $($Model.schema); next id $(New-ObsnId $Model.idCounter); $($counts.pages) pages; $($counts.topics) topics."
    $del = @($Model.deleted)
    $sl += New-OneLine -Text "Recently deleted ($($del.Count)): in OneNote's Deleted Pages for 60 days." -Bold
    foreach ($d in $del) { $sl += New-OneLine -Text ("{0} ({1}, {2})" -f (Get-JsonProp $d 'title' ''), (Get-JsonProp $d 'bucket' ''), (Get-JsonProp $d 'date' '')) }
    $null = $specs.Add(@{ key = 'state'; title = 'ObsidiNote'; meta = [ordered]@{ 'obsn.schema' = [string]$Model.schema; 'obsn.idCounter' = [string]$Model.idCounter; 'obsn.deleted' = (ConvertTo-CompactJson -Value @($del)); 'obsn.pageCount' = [string]$counts.pages; 'obsn.topicCount' = [string]$counts.topics }; lines = $sl; role = 'state' })
    @($specs)
}

function Get-IndexCounts {
    param([Parameter(Mandatory)][hashtable]$Model)
    $all = @($Model.pages.Values)
    $b = [ordered]@{}
    foreach ($g in ($all | Where-Object { $_.owner -ne 'user-section' } | Group-Object { if ($_.bucket) { $_.bucket } else { $_.section } })) { $b[$g.Name] = $g.Count }
    [ordered]@{
        pages = $all.Count; topics = $Model.topics.Count
        unfiled = @($all | Where-Object { Test-PageUnfiled $_ }).Count
        archived = @($all | Where-Object { $_.status -eq 'archived' }).Count
        internalLinks = @($all | Where-Object { $_.bucket -eq 'Internal links' }).Count
        webLinks = @($all | Where-Object { $_.bucket -eq 'Web links' }).Count
        userSectionPages = @($all | Where-Object { $_.owner -eq 'user-section' }).Count
        edges = @(Get-IndexEdges -Model $Model).Count
        buckets = $b
    }
}

# ---------------------------------------------------------------- write the Index pages (COM)

function Write-IndexPages {
    <# Regenerates the vault's Index pages from the model. Needs a valid writer lease. Index pages
       are found by obsn.indexKey (pages in `00 Index` without one are the user's and are never
       touched), created when missing, rewritten whole (title, Meta, their one 'index' outline), and
       removed (to OneNote's Deleted Pages) when the model no longer has them. Content pages are only
       read (their onenote: links). Returns counts and milliseconds. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][string]$IndexSectionId, $Lease, [int]$MaxLines = $script:MaxLinesPerPage, [int]$MaxMeta = $script:MaxMetaChars)
    if (-not (Test-WriterLease $Lease)) { throw 'Read-only: this session does not hold the writer lease.' }
    if ($Model.kind -ne 'vault') { throw 'Only a vault index is written.' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $existing = @{}
    [xml]$sx = $Adapter.GetHierarchy($IndexSectionId, 4)
    foreach ($p in @($sx.SelectNodes("//*[local-name()='Page']"))) {
        if ($p.GetAttribute('isInRecycleBin') -eq 'true') { continue }
        foreach ($m in @($p.ChildNodes)) { if ($m.NodeType -eq 'Element' -and $m.LocalName -eq 'Meta' -and $m.GetAttribute('name') -eq 'obsn.indexKey') { $existing[$m.GetAttribute('content')] = $p.GetAttribute('ID') } }
    }
    $linksFetched = 0
    foreach ($p in $Model.pages.Values) { if (-not $p.link -and $p.oneNoteId) { $p.link = $Adapter.GetHyperlinkToObject($p.oneNoteId); $linksFetched++ } }
    $keys = @(Get-IndexPageSpecs -Model $Model -MaxLines $MaxLines -MaxMeta $MaxMeta | ForEach-Object { $_.key })
    $new = @{}
    foreach ($k in $keys) { if (-not $existing.ContainsKey($k)) { $existing[$k] = $Adapter.CreateNewPage($IndexSectionId); $new[$k] = $true } }
    $links = @{}
    foreach ($k in $keys) {
        if ($Model.indexLinks.ContainsKey($k) -and $Model.indexPages[$k] -eq $existing[$k]) { $links[$k] = $Model.indexLinks[$k] }
        else { $links[$k] = $Adapter.GetHyperlinkToObject($existing[$k]); $linksFetched++ }
    }
    $specs = @(Get-IndexPageSpecs -Model $Model -Links $links -MaxLines $MaxLines -MaxMeta $MaxMeta)
    foreach ($s in $specs) {
        $meta = [ordered]@{ 'obsn.indexKey' = $s.key }
        foreach ($kv in $s.meta.GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
        $role = if ($s.ContainsKey('role')) { $s.role } else { 'index' }
        Write-ObsnPage -Adapter $Adapter -PageId $existing[$s.key] -Meta $meta -Title $s.title -Outlines @(@{ role = $role; lines = $s.lines }) -NewPage:([bool]$new[$s.key])
    }
    $removed = 0
    foreach ($k in @($existing.Keys)) {
        if ($keys -notcontains $k) { $Adapter.DeleteHierarchy($existing[$k]); $removed++; $existing.Remove($k) }
    }
    $Model.indexPages = $existing; $Model.indexLinks = $links
    [pscustomobject]@{ written = @($specs).Count; created = $new.Count; removed = $removed; linksFetched = $linksFetched; ms = $sw.ElapsedMilliseconds }
}

function Update-VaultIndex {
    <# The start / after-write routine for the active vault: fast load from the Index pages, rebuild
       scan of the content pages (page wins), completeness repair, then (with a writer lease) write the
       Index pages. Returns @{ model; missing; added; removed; changed; write }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$RootId, [Parameter(Mandatory)][string]$IndexSectionId, $Lease = $null, [string]$VaultId = '')
    $ix = Read-IndexModel -Adapter $Adapter -IndexSectionId $IndexSectionId -VaultId $VaultId -RootId $RootId
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 4)) -RootId $RootId
    $scan = ConvertFrom-VaultScan -Tree $tree -VaultId $VaultId
    $mg = Merge-IndexWithScan -Index $ix -Scan $scan
    $missing = @(Repair-IndexCompleteness -Model $mg.model -Tree $tree)
    $w = $null
    if ($Lease -and (Test-WriterLease $Lease)) { $w = Write-IndexPages -Adapter $Adapter -Model $mg.model -IndexSectionId $IndexSectionId -Lease $Lease }
    @{ model = $mg.model; missing = $missing; added = $mg.added; removed = $mg.removed; changed = $mg.changed; write = $w }
}

# ---------------------------------------------------------------- path-based retrieval (pure)

function Get-IndexTopLevel {
    <# Ask step 1: the top-level topics with page counts and their subtopic names, within $MaxChars.
       Returns @{ text; topics = @(@{ path; pages; subtopics }); truncated }. #>
    param([Parameter(Mandatory)][hashtable]$Model, [int]$MaxChars = 4000, [switch]$IncludeArchived)
    $sb = New-Object System.Text.StringBuilder
    $items = @(); $trunc = $false
    foreach ($t in @($Model.topics.Values | Where-Object { -not $_.parent } | Sort-Object { $_.name })) {
        $n = Get-TopicSubtreeCount -Model $Model -Path $t.path -IncludeArchived:$IncludeArchived
        $subs = @($t.children | Sort-Object | ForEach-Object { $Model.topics[$_].name })
        $line = "$($t.path) [$n pages]" + $(if ($subs.Count) { ': ' + ($subs -join ', ') } else { '' })
        if ($sb.Length + $line.Length + 1 -gt $MaxChars) { $trunc = $true; break }
        [void]$sb.AppendLine($line)
        $items += @{ path = $t.path; pages = $n; subtopics = $subs }
    }
    $unf = @($Model.pages.Values | Where-Object { (Test-PageUnfiled $_) -and ($IncludeArchived -or $_.status -ne 'archived') }).Count
    if ($unf -and -not $trunc) { $l = "(Unfiled) [$unf pages]"; if ($sb.Length + $l.Length + 1 -le $MaxChars) { [void]$sb.AppendLine($l) } }
    @{ text = $sb.ToString(); topics = $items; truncated = $trunc }
}

function Get-IndexBranch {
    <# Ask step 2: for the chosen branch paths, their subtopics and the page summaries under them,
       breadth first (the branch's own pages, then one level deeper, ...), within $MaxChars.
       '(Unfiled)' selects the pages without a topic. Returns @{ text; pages (keys); truncated }. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][string[]]$Paths, [int]$MaxChars = 8000, [switch]$IncludeArchived)
    $sb = New-Object System.Text.StringBuilder
    $seen = @{}; $keys = New-Object System.Collections.ArrayList; $trunc = $false
    $queue = New-Object System.Collections.Queue
    foreach ($p in $Paths) { if ($p -eq '(Unfiled)') { $queue.Enqueue($p) } else { $n = ConvertTo-TopicPath $p; if ($Model.topics.Contains($n)) { $queue.Enqueue($n) } } }
    while ($queue.Count -and -not $trunc) {
        $path = [string]$queue.Dequeue()
        if ($path -eq '(Unfiled)') { $pages = @($Model.pages.Values | Where-Object { Test-PageUnfiled $_ }); $kids = @() }
        else { $pages = @(Get-TopicPages -Model $Model -Path $path); $kids = @($Model.topics[$path].children | Sort-Object) }
        $head = "## $path" + $(if ($kids.Count) { ' (subtopics: ' + (($kids | ForEach-Object { $Model.topics[$_].name }) -join ', ') + ')' } else { '' })
        if ($sb.Length + $head.Length + 1 -gt $MaxChars) { $trunc = $true; break }
        [void]$sb.AppendLine($head)
        foreach ($pg in ($pages | Sort-Object { $_.title })) {
            if (-not $IncludeArchived -and $pg.status -eq 'archived') { continue }
            if ($seen.ContainsKey($pg.key)) { continue }
            $line = "- $($pg.key) | $($pg.title)" + $(if ($pg.summary) { " | $($pg.summary)" } else { '' })
            if ($sb.Length + $line.Length + 1 -gt $MaxChars) { $trunc = $true; break }
            [void]$sb.AppendLine($line); $seen[$pg.key] = $true; $null = $keys.Add($pg.key)
        }
        foreach ($k in $kids) { $queue.Enqueue($k) }
    }
    @{ text = $sb.ToString(); pages = @($keys); truncated = $trunc }
}

# ---------------------------------------------------------------- connected (foreign) notebooks

function Get-OneNoteLinkPageGuid {
    <# The page-id GUID in an onenote: link ('' when there is none). #>
    param([string]$Link)
    $m = [regex]::Match([string]$Link, '(?i)page-id=(%7B|\{)([0-9a-f-]{36})(%7D|\})')
    if ($m.Success) { return $m.Groups[2].Value.ToLowerInvariant() }
    ''
}

function ConvertFrom-ForeignTree {
    <# The model for a notebook that is not a vault (pure, read only): topics from section groups
       and sections ('Group/Section'), pages with their section path as topic, subpages (page level
       2/3) as children of the page above them. $SkipGroups: top-level groups that are vaults. #>
    param([Parameter(Mandatory)][hashtable]$Tree, [string[]]$SkipGroups = @())
    $m = New-IndexModel -Kind 'foreign' -RootId $Tree.notebook.id
    $m.source = 'foreign'
    foreach ($s in $Tree.sections) {
        $top = $s.full.Split('/')[0]
        if ($s.group -and $SkipGroups -contains $top) { continue }
        $null = Add-IndexTopic -Model $m -Path $s.full
        $stack = @{}
        foreach ($p in $s.pages) {
            $lvl = [int]$p.level; if ($lvl -lt 1) { $lvl = 1 }
            $parent = ''
            for ($l = $lvl - 1; $l -ge 1; $l--) { if ($stack.ContainsKey($l)) { $parent = $stack[$l]; break } }
            $r = Add-IndexPage -Model $m -Page @{ oneNoteId = $p.id; title = $p.title; section = $s.full; topics = @($s.full); updated = $p.updated; level = $lvl; parent = $parent; owner = 'foreign' }
            $stack[$lvl] = $r.key
            foreach ($k in @($stack.Keys)) { if ($k -gt $lvl) { $stack.Remove($k) } }
        }
    }
    foreach ($p in $m.pages.Values) { $p['children'] = @($m.pages.Values | Where-Object { $_.parent -eq $p.key } | ForEach-Object { $_.key }) }
    $m
}

function Get-NotebookModel {
    <# The in-memory model of any open notebook, read only. A notebook that is a vault (root kind
       notebook) loads from its own index (fast load); any other notebook is derived from its
       hierarchy (sections as topic paths, subpages as children). -NoLinks skips the onenote: link of
       each page (one COM call per page). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [string]$NotebookId = '', [string]$Name = '', [switch]$NoLinks, [object[]]$Vaults = $null)
    if ($null -eq $Vaults) { $Vaults = @(Get-VaultList -Adapter $Adapter) }
    if (-not $NotebookId) {
        $nb = @(Get-NotebookList -Adapter $Adapter -Vaults $Vaults | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
        if (-not $nb) { throw "Notebook '$Name' is not open in OneNote." }
        $NotebookId = $nb.id
    }
    $v = @($Vaults | Where-Object { $_.rootKind -eq 'notebook' -and $_.rootId -eq $NotebookId }) | Select-Object -First 1
    if ($v) {
        $m = Read-IndexModel -Adapter $Adapter -IndexSectionId $v.indexSectionId -VaultId $v.vaultId -RootId $v.rootId
        $m.readOnly = $true
        return $m
    }
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($NotebookId, 4)) -RootId $NotebookId
    $skip = @($Vaults | Where-Object { $_.notebookId -eq $NotebookId -and $_.rootKind -eq 'sectiongroup' } | ForEach-Object { $_.name })
    $m = ConvertFrom-ForeignTree -Tree $tree -SkipGroups $skip
    if (-not $NoLinks) { foreach ($p in $m.pages.Values) { $p.link = $Adapter.GetHyperlinkToObject($p.oneNoteId) } }
    $m
}

function Get-PageLinkTargets {
    <# The page-id GUIDs of the onenote: links in a page's XML (pure; text stays in memory). #>
    param([string]$PageXml)
    $set = @{}
    foreach ($mm in [regex]::Matches([string]$PageXml, '(?i)href="?onenote:[^"\s>]*?page-id=(%7B|\{)([0-9a-f-]{36})(%7D|\})')) { $set[$mm.Groups[2].Value.ToLowerInvariant()] = $true }
    @($set.Keys)
}

function Get-NotebookLinks {
    <# Edges for a connected notebook: reads page content (in memory only) and turns onenote: links
       between pages of the same notebook into edges (strength 1, why 'link'), resolved by the page-id
       in the link. Works in batches: -Start and -BatchSize; call again with the returned next until
       done. Pages without an onenote: link get one first (one COM call each). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Model, [int]$Start = 0, [int]$BatchSize = 50)
    $keys = @($Model.pages.Keys)
    $byGuid = @{}
    foreach ($p in $Model.pages.Values) {
        if (-not $p.link -and $p.oneNoteId) { $p.link = $Adapter.GetHyperlinkToObject($p.oneNoteId) }
        $g = Get-OneNoteLinkPageGuid $p.link
        if ($g) { $byGuid[$g] = $p.key }
    }
    $end = [Math]::Min($keys.Count, $Start + $BatchSize)
    $edges = 0
    for ($i = $Start; $i -lt $end; $i++) {
        $p = $Model.pages[$keys[$i]]
        $xml = try { $Adapter.GetPageContent($p.oneNoteId) } catch { '' }
        $have = @{}; foreach ($l in @($p.links)) { $have[$l.target] = $true }
        $add = @()
        foreach ($g in (Get-PageLinkTargets $xml)) {
            if (-not $byGuid.ContainsKey($g)) { continue }
            $t = $byGuid[$g]
            if ($t -eq $p.key -or $have.ContainsKey($t)) { continue }
            $have[$t] = $true
            $add += @{ target = $t; strength = 1; why = 'link' }
        }
        if ($add.Count) { $p.links = @(@($p.links) + $add); $edges += $add.Count }
        $xml = $null
    }
    @{ processed = $end - $Start; edges = $edges; next = $end; done = ($end -ge $keys.Count) }
}

Export-ModuleMember -Function New-IndexModel, Add-IndexTopic, Add-IndexPage, Get-IndexEdges, Get-TopicPages, Get-IndexCounts, ConvertTo-IndexEntry, ConvertFrom-IndexEntry, ConvertFrom-IndexSectionXml, Read-IndexModel, Get-PageRecordFromHierarchy, ConvertFrom-VaultScan, Read-VaultScan, Merge-IndexWithScan, Get-ContentPageList, Test-IndexComplete, Repair-IndexCompleteness, Get-LinkGroup, Get-IndexPageSpecs, Write-IndexPages, Update-VaultIndex, Get-IndexTopLevel, Get-IndexBranch, Get-OneNoteLinkPageGuid, ConvertFrom-ForeignTree, Get-NotebookModel, Get-PageLinkTargets, Get-NotebookLinks
