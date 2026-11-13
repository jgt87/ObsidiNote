# The knowledge graph's data (GET /api/graph): an index model (lib/Index.psm1: a vault's central
# index, or the derived model of a connected notebook) mapped to the interface's GraphModel
# (ui-src/src/graph/model.ts): { source; topics; pages; edges }.
#   - topic id = its path ('Security/Networking'); path shown with ' / '; pageCount counts the pages
#     of the topic and all its subtopics; subjects = the first subtopic names.
#   - page id = the model key (obsn id, or n:<OneNote id> for other pages); topicIds = its topic
#     paths, the first is where the dot is drawn; no topics = the Unfiled area.
#   - edges = the pages' own links (strength 1-3, why); links to pages that are not in the model are
#     left out. links = in + out per page; hubs = pages with many links.
#   - aliases (other names) and site (a link page's host) feed search and mentions in the interface.
# Pure: no COM, no disk. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')

$script:HubLinks = 5   # a page with at least this many links (in + out) is drawn as a hub

function ConvertTo-GraphModel {
    <# GraphModel from an index model. $Source: @{ kind (vault|notebook); id; name; readOnly }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Source)
    $degree = @{}
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
    $pages = @(foreach ($p in $Model.pages.Values) {
        $d = if ($degree.ContainsKey($p.key)) { [int]$degree[$p.key] } else { 0 }
        [ordered]@{
            id = $p.key; title = $(if ($p.title) { $p.title } else { 'Untitled page' })
            topicIds = @(@($p.topics) | Where-Object { $_ -and $Model.topics.Contains($_) })
            bucket = $(if ($p.bucket) { $p.bucket } else { $p.section }); kind = $(if ($p.type) { $p.type } else { '' })
            links = $d; isHub = ($d -ge $script:HubLinks); unlinked = ($d -eq 0)
            summary = [string]$p.summary; onenoteUrl = $(if ([string]$p.link -match '^(?i)onenote:') { [string]$p.link } else { '' })
            modified = [string]$p.updated; readOnly = $ro; archived = ($p.status -eq 'archived')
            aliases = @(@($p.aliases) | Where-Object { $_ } | ForEach-Object { [string]$_ }); site = [string]$p.host
        }
    })
    [ordered]@{
        source = [ordered]@{ kind = $(if ($Source.kind -eq 'notebook') { 'notebook' } else { 'vault' }); id = [string]$Source.id; name = [string]$Source.name; readOnly = $ro }
        topics = $topics; pages = $pages; edges = @($edges.ToArray())
    }
}

Export-ModuleMember -Function ConvertTo-GraphModel
