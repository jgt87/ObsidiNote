# The knowledge graph's data (GET /api/graph): an index model (lib/Index.psm1: a vault's central
# index, or the derived model of a connected notebook) mapped to the interface's GraphModel
# (ui-src/src/graph/model.ts): { source; topics; pages; edges }.
#   - topic id = its path ('Security/Networking'); path shown with ' / '; pageCount counts the pages
#     of the topic and all its subtopics; subjects = the first subtopic names.
#   - page id = the model key (obsn id, or n:<OneNote id> for other pages); topicIds = its topic
#     paths, the first is where the dot is drawn; no topics = the Unfiled area.
#   - edges = the pages' own links (strength 1-3, why); links to pages that are not in the model are
#     left out. links = distinct linked pages (a page that links back counts once). Weight, dot size
#     and hubs are worked out from the edges in the interface (ui-src/src/graph/weights.ts), the one
#     definition; this module sends no hub flag.
#   - aliases (other names) and site (a link page's host) feed search and mentions in the interface.
#   - sourceId per page and the sources list feed the Sources view (operator, 2026-11-14): where a
#     link page's address lives (Get-LinkSource in lib/NotebookStructure.psm1), web sites with fewer
#     than $script:MinWebPages pages together as "Other web sites", every page without an address in
#     "ObsidiNote notes" (a vault) or "OneNote pages" (a connected notebook).
# Pure: no COM, no disk. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')

$script:MinWebPages = 3   # a web site with fewer pages joins "Other web sites"
# Order of the kinds in the sources list (the map packs the strongest linked first anyway).
$script:SourceKindOrder = @{ m365 = 0; service = 1; web = 2; other = 3; notes = 4 }

function Get-GraphSources {
    <# Per page id its source id, plus the sources list @(@{ id; name; kind; pageCount }). #>
    param([object[]]$Pages, [bool]$Notebook)
    $notes = if ($Notebook) { @{ id = 'onenote'; name = 'OneNote pages'; kind = 'notes' } } else { @{ id = 'obsidinote'; name = 'ObsidiNote notes'; kind = 'notes' } }
    $of = @{}
    $byId = @{}
    $count = @{}
    foreach ($p in $Pages) {
        # The address wins (a link page); else where it came from (obsn.origin); else the notes area.
        $s = if ([string]$p.url -match '^(?i)https?://') { Get-LinkSource -Url ([string]$p.url) } else { $null }
        if (-not $s -and $p.ContainsKey('origin') -and $p.origin) { $s = Get-OriginSource ([string]$p.origin) }
        if (-not $s) { $s = $notes }
        $of[$p.key] = $s
        $byId[$s.id] = $s
        $count[$s.id] = 1 + [int]$count[$s.id]
    }
    $other = @{ id = 'web'; name = 'Other web sites'; kind = 'other' }
    foreach ($k in @($of.Keys)) {
        $s = $of[$k]
        if ($s.kind -eq 'web' -and $count[$s.id] -lt $script:MinWebPages) { $of[$k] = $other }
    }
    $final = @{}
    foreach ($s in $of.Values) {
        if ($final.ContainsKey($s.id)) { $final[$s.id].pageCount++ } else { $final[$s.id] = [ordered]@{ id = $s.id; name = $s.name; kind = $s.kind; pageCount = 1 } }
    }
    $list = @($final.Values | Sort-Object @{ Expression = { $script:SourceKindOrder[$_.kind] } }, @{ Expression = { $_.name } })
    $ids = @{}
    foreach ($k in $of.Keys) { $ids[$k] = $of[$k].id }
    @{ of = $ids; list = $list }
}

function ConvertTo-GraphModel {
    <# GraphModel from an index model. $Source: @{ kind (vault|notebook); id; name; readOnly }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Source)
    $degree = @{}
    $edges = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $pairs = @{}   # linked pairs, either direction: a page that links back counts once in links
    foreach ($p in $Model.pages.Values) {
        foreach ($l in @($p.links)) {
            if (-not $l) { continue }
            $to = [string](Get-JsonProp $l 'target' '')
            if (-not $to -or $to -eq $p.key -or -not $Model.pages.Contains($to)) { continue }
            $k = "$($p.key)>$to"
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $s = [int](Get-JsonProp $l 'strength' 1); if ($s -lt 1) { $s = 1 } elseif ($s -gt 3) { $s = 3 }
            $edges.Add([ordered]@{ from = $p.key; to = $to; strength = $s; kind = 'link'; reason = [string](Get-JsonProp $l 'why' '') })
            $pair = if ($p.key -lt $to) { "$($p.key)|$to" } else { "$to|$($p.key)" }
            if ($pairs.ContainsKey($pair)) { continue }
            $pairs[$pair] = $true
            foreach ($x in $p.key, $to) { if ($degree.ContainsKey($x)) { $degree[$x]++ } else { $degree[$x] = 1 } }
        }
    }
    $topics = @(foreach ($t in $Model.topics.Values) {
        $pre = $t.path + '/'
        $count = @($Model.pages.Values | Where-Object { @($_.topics | Where-Object { $_ -eq $t.path -or $_.StartsWith($pre) }).Count }).Count
        $subjects = (@($t.children | Sort-Object | Select-Object -First 3 | ForEach-Object { $Model.topics[$_].name }) -join ', ')
        [ordered]@{ id = $t.path; name = $t.name; path = (Format-TopicPath $t.path); parent = $(if ($t.parent) { $t.parent } else { $null }); pageCount = $count; subjects = $subjects }
    })
    $ro = [bool]$Source.readOnly
    $src = Get-GraphSources -Pages @($Model.pages.Values) -Notebook ($Source.kind -eq 'notebook')
    $pages = @(foreach ($p in $Model.pages.Values) {
        $d = if ($degree.ContainsKey($p.key)) { [int]$degree[$p.key] } else { 0 }
        [ordered]@{
            id = $p.key; title = $(if ($p.title) { $p.title } else { 'Untitled page' })
            topicIds = @(@($p.topics) | Where-Object { $_ -and $Model.topics.Contains($_) })
            bucket = $(if ($p.bucket) { $p.bucket } else { $p.section }); kind = $(if ($p.type) { $p.type } else { '' })
            links = $d; unlinked = ($d -eq 0)
            summary = [string]$p.summary; onenoteUrl = $(if ([string]$p.link -match '^(?i)onenote:') { [string]$p.link } else { '' })
            modified = [string]$p.updated; readOnly = $ro; archived = ($p.status -eq 'archived')
            aliases = @(@($p.aliases) | Where-Object { $_ } | ForEach-Object { [string]$_ }); site = [string]$p.host
            url = $(if ([string]$p.url -match '^(?i)https?://') { [string]$p.url } else { '' })
            sourceId = [string]$src.of[$p.key]
            origin = [string]$p['origin']
        }
    })
    [ordered]@{
        source = [ordered]@{ kind = $(if ($Source.kind -eq 'notebook') { 'notebook' } else { 'vault' }); id = [string]$Source.id; name = [string]$Source.name; readOnly = $ro }
        topics = $topics; pages = $pages; edges = @($edges.ToArray()); sources = @($src.list)
    }
}

Export-ModuleMember -Function ConvertTo-GraphModel
