# Source adapters for lib/Ask.psm1 (see its header: Id, Name, Kind, ReadOnly, GetTopTopics,
# GetBranch, ReadPageText), made from an index model (lib/Index.psm1): the active vault's working
# copy, another vault's index (read only) or the derived model of a connected notebook (read only).
#   GetTopTopics  the top-level topics with page counts and subtopic names (+ Unfiled when it has pages)
#   GetBranch     a branch's subtopics and the pages under it (Get-IndexBranch, breadth first)
#   ReadPageText  one page's text by its Ask id, read through the adapter (GetPageContent), in memory
# Ask ids: an ObsidiNote page keeps its obsn id (p1a); any other page gets a short id (x1, x2, ...)
# so Copilot never has to copy a OneNote object id. Nothing is written anywhere; page text is
# returned to Ask and never kept. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')
Import-Module (Join-Path $PSScriptRoot 'Index.psm1')

$script:LinkFetchMax = 200   # onenote: links fetched per branch for pages that have none yet

function Get-AskIdMap {
    <# Ask id <-> model key for every page of the model. Pure. #>
    param([Parameter(Mandatory)][hashtable]$Model)
    $toKey = @{}; $toAsk = @{}; $n = 0
    foreach ($k in @($Model.pages.Keys)) {
        $p = $Model.pages[$k]
        if (Test-ObsnId $p.id) { $a = [string]$p.id } else { $n++; $a = "x$n" }
        $toKey[$a] = $k; $toAsk[$k] = $a
    }
    @{ toKey = $toKey; toAsk = $toAsk }
}

function Get-AskTopTopics {
    <# Ask step 1 data: @(@{ path; pageCount; summary; subtopics }). Pure. #>
    param([Parameter(Mandatory)][hashtable]$Model, [switch]$IncludeArchived)
    $top = Get-IndexTopLevel -Model $Model -MaxChars 10000000 -IncludeArchived:$IncludeArchived
    $out = @(foreach ($t in @($top.topics)) { @{ path = $t.path; pageCount = [int]$t.pages; summary = ''; subtopics = @($t.subtopics) } })
    $unf = @($Model.pages.Values | Where-Object { -not @($_.topics).Count -and $_.owner -ne 'user-section' -and ($IncludeArchived -or $_.status -ne 'archived') }).Count
    if ($unf) { $out += @{ path = '(Unfiled)'; pageCount = $unf; summary = 'Pages that have no topic yet'; subtopics = @() } }
    , $out
}

function Get-AskBranchData {
    <# Ask step 2 data for one branch: @{ subtopics = @(@{ path; pageCount }); pages = @(@{ id; title;
       summary; type; topics; link; updated; summarizedAt; url; status }) }. Pure. #>
    param([Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][hashtable]$Ids, [Parameter(Mandatory)][string]$Path, [bool]$IncludeArchived = $false)
    $b = Get-IndexBranch -Model $Model -Paths @($Path) -MaxChars 10000000 -IncludeArchived:$IncludeArchived
    $norm = ConvertTo-TopicPath $Path
    $subs = @()
    if ($Model.topics.Contains($norm)) {
        $subs = @(foreach ($c in @($Model.topics[$norm].children | Sort-Object)) { @{ path = $c; pageCount = @($Model.pages.Values | Where-Object { @($_.topics | Where-Object { $_ -eq $c -or $_.StartsWith("$c/") }).Count }).Count } })
    }
    $pages = @(foreach ($k in @($b.pages)) {
        $p = $Model.pages[$k]
        @{ id = $Ids.toAsk[$k]; title = $p.title; summary = $p.summary; type = $(if ($p.type) { $p.type } else { $p.section }); topics = @($p.topics)
            link = $p.link; updated = $p.updated; summarizedAt = $p.summarizedAt; url = $p.url; status = $p.status }
    })
    @{ subtopics = $subs; pages = $pages }
}

function Read-AskPageText {
    <# The text of one page (title + every outline), read through the adapter. In memory only. #>
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$PageId)
    $t = ConvertFrom-ObsnPageText -Xml ($Adapter.GetPageContent($PageId))
    $parts = @($t.title) + @(@($t.outlines) | Where-Object { $_.role -ne 'props' -and $_.text } | ForEach-Object { $_.text })
    (@($parts | Where-Object { $_ }) -join "`n`n")
}

function Invoke-AskSourceCall {
    <# The one entry the source's scriptblocks call (closures made in a module cannot see its functions). #>
    param([Parameter(Mandatory)][hashtable]$Ctx, [Parameter(Mandatory)][string]$Name, [hashtable]$Arguments = @{})
    switch ($Name) {
        'GetTopTopics' { return (Get-AskTopTopics -Model $Ctx.Model) }
        'GetBranch' {
            $d = Get-AskBranchData -Model $Ctx.Model -Ids $Ctx.Ids -Path $Arguments.Path -IncludeArchived ([bool]$Arguments.IncludeArchived)
            $missing = @($d.pages | Where-Object { -not $_.link })
            if ($missing.Count -and $missing.Count -le $script:LinkFetchMax) {
                foreach ($pg in $missing) {
                    $p = $Ctx.Model.pages[$Ctx.Ids.toKey[$pg.id]]
                    if ($p.oneNoteId) { try { $p.link = $Ctx.Adapter.GetHyperlinkToObject($p.oneNoteId); $pg.link = $p.link } catch { } }
                }
            }
            return $d
        }
        'ReadPageText' {
            $k = $Ctx.Ids.toKey[[string]$Arguments.PageId]
            if (-not $k -or -not $Ctx.Model.pages.Contains($k)) { return $null }
            $p = $Ctx.Model.pages[$k]
            if (-not $p.oneNoteId) { return $null }
            return (Read-AskPageText -Adapter $Ctx.Adapter -PageId $p.oneNoteId)
        }
    }
    throw "The Ask source has no '$Name'."
}

function New-AskSource {
    <# A source adapter for Ask over $Model. -ReadOnly for other vaults and connected notebooks (the
       active vault is the one source with ReadOnly = $false). $Kind: vault | notebook. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][hashtable]$Model, [Parameter(Mandatory)][string]$Id, [string]$Name = '', [string]$Kind = 'vault', [switch]$ReadOnly)
    $ctx = @{ Adapter = $Adapter; Model = $Model; Ids = (Get-AskIdMap -Model $Model) }
    $call = Get-Command Invoke-AskSourceCall
    @{
        Id = $Id; Name = $Name; Kind = $Kind; ReadOnly = [bool]$ReadOnly
        GetTopTopics = { & $call $ctx 'GetTopTopics' }.GetNewClosure()
        GetBranch = { param([string]$Path, [bool]$IncludeArchived) & $call $ctx 'GetBranch' @{ Path = $Path; IncludeArchived = $IncludeArchived } }.GetNewClosure()
        ReadPageText = { param([string]$PageId) & $call $ctx 'ReadPageText' @{ PageId = $PageId } }.GetNewClosure()
    }
}

Export-ModuleMember -Function New-AskSource, Get-AskIdMap, Get-AskTopTopics, Get-AskBranchData, Read-AskPageText
