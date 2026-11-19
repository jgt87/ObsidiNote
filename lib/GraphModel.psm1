# The knowledge graph's data (GET /api/graph): an index model (lib/Index.psm1: a vault's central
# index, or the derived model of a connected notebook) mapped to the interface's GraphModel
# (ui-src/src/graph/model.ts): { source; topics; pages; edges }.
#   - topic id = its path ('Security/Networking'); path shown with ' / '; pageCount counts the pages
#     of the topic and all its subtopics; subjects = the first subtopic names.
#   - page id = the model key (obsn id, or n:<OneNote id> for other pages); topicIds = its topic
#     paths, the first is where the dot is drawn; no topics = the Unfiled area.
#   - edges = the pages' own links (strength 1-3, why); links to pages that are not in the model are
#     left out. A page's link count, weight, dot size and hubs are worked out from the edges in the
#     interface (ui-src/src/graph/weights.ts), the one definition; this module sends none of them.
#   - aliases (other names) and site (a link page's host) feed search and mentions in the interface.
#   - sourceId per page and the sources list feed the Sources view (operator, 2026-11-14): where a
#     link page's address lives (Get-LinkSource in lib/NotebookStructure.psm1), web sites with fewer
#     than $script:MinWebPages pages together as "Other web sites" (internal sites likewise as "Other
#     company sites"; internal = the vault's own link rules, $LinkRules), every page without an address in
#     "ObsidiNote notes" (a vault) or "OneNote pages" (a connected notebook).
# Pure: no COM, no disk. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'NotebookStructure.psm1')

$script:MinWebPages = 3   # a web site with fewer pages joins "Other web sites"
# Order of the kinds in the sources list (the map packs the strongest linked first anyway).
$script:SourceKindOrder = @{ m365 = 0; service = 1; 'other-internal' = 2; web = 3; other = 4; notes = 5 }

function Get-LinkTypeSource([string]$Type) {
    <# A link page without an address or host: its type still says web or company. The same rest
       groups as the view's few-page sites ("Other web sites", "Other company sites"); $null for a page
       that is not a link page. Pure. #>
    switch ($Type) {
        'link-web' { return @{ id = 'web'; name = 'Other web sites'; kind = 'other' } }
        'link-internal' { return @{ id = 'internal'; name = 'Other company sites'; kind = 'other-internal' } }
        default { return $null }
    }
}

function Get-GraphSources {
    <# Per page id its source id, plus the sources list @(@{ id; name; kind; pageCount }). #>
    param([object[]]$Pages, [bool]$Notebook, [hashtable]$LinkRules = @{})
    $hosts = @(if ($LinkRules.ContainsKey('InternalHosts')) { $LinkRules.InternalHosts } else { @() })
    $names = @(if ($LinkRules.ContainsKey('CompanyNames')) { $LinkRules.CompanyNames } else { @() })
    $notes = if ($Notebook) { @{ id = 'onenote'; name = 'OneNote pages'; kind = 'notes' } } else { @{ id = 'obsidinote'; name = 'ObsidiNote notes'; kind = 'notes' } }
    $of = @{}
    $byId = @{}
    $count = @{}
    foreach ($p in $Pages) {
        # The address wins (a link page); then its host alone (a link page whose record lost the
        # address); then where it came from (obsn.origin); then its link type; the notes area only
        # when nothing says where it is from (operator, 2026-11-16: "putting items in ObsidiNote notes
        # should be minimized. Web links should be listed as such, and not as notes").
        $s = if ([string]$p.url -match '^(?i)https?://') { Get-LinkSource -Url ([string]$p.url) -InternalHosts $hosts -CompanyNames $names } else { $null }
        if (-not $s -and $p.ContainsKey('host') -and [string]$p.host -match '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { $s = Get-LinkSource -Url "https://$([string]$p.host)/" -InternalHosts $hosts -CompanyNames $names }
        if (-not $s -and $p.ContainsKey('origin') -and $p.origin) { $s = Get-OriginSource ([string]$p.origin) }
        if (-not $s) { $s = Get-LinkTypeSource ([string]$p.type) }
        if (-not $s) { $s = $notes }
        $of[$p.key] = $s
        $byId[$s.id] = $s
        $count[$s.id] = 1 + [int]$count[$s.id]
    }
    $other = @{ id = 'web'; name = 'Other web sites'; kind = 'other' }
    # Its own kind: a rest group of several sites, not one company service (code review 2026-11-15).
    $otherInternal = @{ id = 'internal'; name = 'Other company sites'; kind = 'other-internal' }
    foreach ($k in @($of.Keys)) {
        $s = $of[$k]
        if ($count[$s.id] -ge $script:MinWebPages) { continue }
        if ($s.kind -eq 'web') { $of[$k] = $other }
        elseif ($s.id -like 'internal/*') { $of[$k] = $otherInternal }
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

function ConvertTo-GraphEntries($Page) {
    <# A day page's entries for the window: @{ ref; at; title; summary; topicIds; links [{to; strength; why}] }. #>
    if (-not $Page.ContainsKey('entries')) { return }
    foreach ($e in @($Page['entries'] | Where-Object { $_ })) {
        [ordered]@{
            ref = [string](Get-JsonProp $e 'ref' ''); at = [string](Get-JsonProp $e 'at' '')
            title = [string](Get-JsonProp $e 'title' ''); summary = [string](Get-JsonProp $e 'summary' '')
            topicIds = [string[]]@(@(Get-JsonProp $e 'topics' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
            links = @(@(Get-JsonProp $e 'links' @()) | Where-Object { $_ } | ForEach-Object { [ordered]@{ to = [string](Get-JsonProp $_ 'target' ''); strength = [int](Get-JsonProp $_ 'strength' 1); why = [string](Get-JsonProp $_ 'why' '') } })
        }
    }
}

function ConvertTo-GraphModel {
    <# GraphModel from an index model. $Source: @{ kind (vault|notebook); id; name; readOnly }.
       $LinkRules: @{ InternalHosts; CompanyNames } as the vault store files links (Sources view). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Source, [hashtable]$LinkRules = @{})
    $edges = New-Object System.Collections.Generic.List[object]
    $seen = @{}
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
        }
    }
    $topics = @(foreach ($t in $Model.topics.Values) {
        $pre = $t.path + '/'
        $count = @($Model.pages.Values | Where-Object { @($_.topics | Where-Object { $_ -eq $t.path -or $_.StartsWith($pre) }).Count }).Count
        $subjects = (@($t.children | Sort-Object | Select-Object -First 3 | ForEach-Object { $Model.topics[$_].name }) -join ', ')
        [ordered]@{ id = $t.path; name = $t.name; path = (Format-TopicPath $t.path); parent = $(if ($t.parent) { $t.parent } else { $null }); pageCount = $count; subjects = $subjects }
    })
    $ro = [bool]$Source.readOnly
    $src = Get-GraphSources -Pages @($Model.pages.Values) -Notebook ($Source.kind -eq 'notebook') -LinkRules $LinkRules
    $pages = @(foreach ($p in $Model.pages.Values) {
        [ordered]@{
            id = $p.key; title = $(if ($p.title) { $p.title } else { 'Untitled page' })
            topicIds = @(@($p.topics) | Where-Object { $_ -and $Model.topics.Contains($_) })
            # section: the section path as the index model holds it ('Notes 2', 'Journal/2026',
            # 'Archive/Notes', a user's 'Group/Section'); bucket folds rollover and year away
            # (pinned by tests/fixtures/graph-pages.json, which the interface tests read too).
            section = [string]$p.section
            bucket = $(if ($p.bucket) { $p.bucket } else { $p.section }); kind = $(if ($p.type) { $p.type } else { '' })
            summary = [string]$p.summary; onenoteUrl = $(if ([string]$p.link -match '^(?i)onenote:') { [string]$p.link } else { '' })
            modified = [string]$p.updated; readOnly = $ro; archived = ($p.status -eq 'archived')
            aliases = @(@($p.aliases) | Where-Object { $_ } | ForEach-Object { [string]$_ }); site = [string]$p.host
            url = $(if ([string]$p.url -match '^(?i)https?://') { [string]$p.url } else { '' })
            # summarizedAt: when a link page's source was last read ('' for other pages); the
            # window's "Link summaries older than N days" filter reads it.
            summarizedAt = [string]$p.summarizedAt
            sourceId = [string]$src.of[$p.key]
            origin = [string]$p['origin']
            # tags: set by hand (obsn.tags); always an array, [] when none.
            tags = [string[]]@(@($p['tags']) | Where-Object { $_ } | ForEach-Object { [string]$_ })
            # own: one of ObsidiNote's own pages (it can be edited, archived and deleted); false for a
            # page the person made in OneNote, which is listed and never changed (operator, 2026-11-16:
            # Delete was offered on such a page and failed).
            own = ([string]$p.owner -eq 'obsn')
            # created: OneNote's own page date ('' when the model does not know it); entries: a journal
            # day page's entries (operator, 2026-11-17), [] for every other page. The Journal view reads
            # both; entry links are page keys like the page's own links.
            created = $(if ($p.ContainsKey('created')) { [string]$p['created'] } else { '' })
            entries = @(ConvertTo-GraphEntries $p)
            # series / meetingAt: a meeting page's series and start (yyyy-MM-ddTHH:mm), '' otherwise
            # (operator, 2026-11-18; pinned by tests/fixtures/graph-pages.json).
            series = $(if ($p.ContainsKey('series')) { [string]$p['series'] } else { '' })
            meetingAt = $(if ($p.ContainsKey('meetingAt')) { [string]$p['meetingAt'] } else { '' })
            # seriesPage: the overview page of a meeting series (record kind series, 2026-11-19), not a
            # meeting: the Journal and the series counts leave it out.
            seriesPage = ([string]$p['kind'] -eq 'series')
        }
    })
    # The tags of the shown source with their page counts, sorted by name (ordinal).
    $tagCount = @{}
    foreach ($p in $pages) { foreach ($t in @($p.tags)) { $tagCount[$t] = 1 + [int]$tagCount[$t] } }
    $tagNames = [string[]]@($tagCount.Keys)
    [Array]::Sort($tagNames, [StringComparer]::Ordinal)
    $tags = [object[]]@(foreach ($t in $tagNames) { [ordered]@{ name = $t; count = [int]$tagCount[$t] } })
    # readOnlyReason: why the shown source cannot be changed here: '' (it can), lease (the active
    # vault while this window is not its writer), not-active (another vault), notebook (a connected
    # notebook). The server says which; a read-only source without one is a notebook or another vault.
    $why = if (-not $ro) { '' } elseif ($Source.ContainsKey('readOnlyReason') -and $Source.readOnlyReason) { [string]$Source.readOnlyReason } elseif ($Source.kind -eq 'notebook') { 'notebook' } else { 'not-active' }
    [ordered]@{
        source = [ordered]@{ kind = $(if ($Source.kind -eq 'notebook') { 'notebook' } else { 'vault' }); id = [string]$Source.id; name = [string]$Source.name; readOnly = $ro; readOnlyReason = $why }
        topics = $topics; pages = $pages; edges = @($edges.ToArray()); sources = @($src.list); tags = $tags
    }
}

Export-ModuleMember -Function ConvertTo-GraphModel
