# Journal (D-060): one page per day. Every Add that Copilot types as a journal entry
# ('log') goes into that day's page "yyyy-MM-dd" in Journal/<year> as one entry: a bold "HH:mm  title"
# line with the text under it in the page's body outline (lib/PageMeta.psm1 Add-ObsnBodyEntry), and one
# item of the page's obsn.entries Meta. The day page's topics and links are the union of its entries',
# so the map, Ask and the index see the day as one page; the Journal view lists the entries. Undo of one
# entry takes only that entry out (the whole page when it was the only one). Journal pages made before
# 2026-11-17 (one page per entry, a title of their own) stay as they are and are never merged: a page is
# only a day page when its title is a date and it has entries. Pure. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'PageMeta.psm1')   # Get-ObsnEntryHeading, Get-JsonProp

$script:SummaryMax = 400

function Get-JournalDayTitle {
    <# The title of the day page for $Now: 'yyyy-MM-dd' (the local date). #>
    param([Parameter(Mandatory)][datetime]$Now)
    $Now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

function Test-JournalDayTitle([AllowEmptyString()][string]$Title) { $Title -match '^\d{4}-\d{2}-\d{2}$' }

function Find-JournalDay {
    <# The day page of $Title among $Pages (Ingest's page records): type log, that exact title, not
       archived. A page from before 2026-11-17 that happens to be titled with that date is a day page
       too only when it has entries (else a new day page is made beside it). $null when there is none. #>
    param([object[]]$Pages = @(), [Parameter(Mandatory)][string]$Title)
    foreach ($p in @($Pages)) {
        if (-not $p) { continue }
        if ([string](Get-JsonProp $p 'type' '') -ne 'log') { continue }
        if ([string](Get-JsonProp $p 'title' '') -ne $Title) { continue }
        if ([string](Get-JsonProp $p 'status' '') -eq 'archived') { continue }
        if (-not @(Get-JsonProp $p 'entries' @()).Count) { continue }
        return $p
    }
    $null
}

function New-JournalEntry {
    <# One entry from Copilot's checked reply ($Value: title, summary, topics [{path}], links). #>
    param([Parameter(Mandatory)][string]$Ref, [Parameter(Mandatory)][datetime]$Now, [Parameter(Mandatory)]$Value)
    @{
        ref = $Ref
        at = $Now.ToString('yyyy-MM-ddTHH:mm', [Globalization.CultureInfo]::InvariantCulture)
        title = [string](Get-JsonProp $Value 'title' '')
        summary = [string](Get-JsonProp $Value 'summary' '')
        topics = @(@(Get-JsonProp $Value 'topics' @()) | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { $_ } else { [string](Get-JsonProp $_ 'path' '') } } | Where-Object { $_ })
        links = @(@(Get-JsonProp $Value 'links' @()) | Where-Object { $_ } | ForEach-Object { @{ target = [string](Get-JsonProp $_ 'target' ''); strength = [int](Get-JsonProp $_ 'strength' 1); why = [string](Get-JsonProp $_ 'why' '') } })
    }
}

function Get-JournalSummary {
    <# The day page's summary: how many entries and their titles, at most $SummaryMax characters. #>
    param([object[]]$Entries = @())
    $list = @($Entries | Where-Object { $_ })
    if (-not $list.Count) { return '' }
    $head = if ($list.Count -eq 1) { '1 entry: ' } else { "$($list.Count) entries: " }
    $s = $head + (@($list | ForEach-Object { [string](Get-JsonProp $_ 'title' '') } | Where-Object { $_ }) -join '; ')
    if ($s.Length -gt $script:SummaryMax) { $s = $s.Substring(0, $script:SummaryMax - 3).TrimEnd() + '...' }
    $s
}

function Merge-JournalDay {
    <# The day page's fields from its entries: topics (each once, in order), links (one per target, the
       strongest, with the first reason given) and the summary. Returns @{ topics; links; summary }. #>
    param([object[]]$Entries = @())
    $topics = New-Object System.Collections.Generic.List[string]
    $links = [ordered]@{}
    foreach ($e in @($Entries | Where-Object { $_ })) {
        foreach ($t in @(Get-JsonProp $e 'topics' @())) { if ($t -and -not $topics.Contains([string]$t)) { $topics.Add([string]$t) } }
        foreach ($l in @(Get-JsonProp $e 'links' @())) {
            $tg = [string](Get-JsonProp $l 'target' '')
            if (-not $tg) { continue }
            $s = [int](Get-JsonProp $l 'strength' 1)
            if (-not $links.Contains($tg)) { $links[$tg] = @{ target = $tg; strength = $s; why = [string](Get-JsonProp $l 'why' '') } }
            elseif ($s -gt $links[$tg].strength) { $links[$tg].strength = $s }
        }
    }
    @{ topics = @($topics.ToArray()); links = @($links.Values); summary = (Get-JournalSummary -Entries $Entries) }
}

function Get-JournalTargets([object[]]$Links = @()) {
    # On the pipeline, one id at a time: callers wrap the call in @() (a ", @()" return would reach a
    # Where-Object as one nested item).
    @($Links | Where-Object { $_ } | ForEach-Object { [string](Get-JsonProp $_ 'target' '') }) | Where-Object { $_ } | Select-Object -Unique
}

function New-JournalEntryLines {
    <# The entry as outline lines (line model): its "HH:mm  title" line in bold, the text under it. #>
    param([Parameter(Mandatory)]$Entry, [object[]]$Body = @())
    $heading = Get-ObsnEntryHeading -At ([string](Get-JsonProp $Entry 'at' '')) -Title ([string](Get-JsonProp $Entry 'title' ''))
    , @(@{ parts = @(@{ text = $heading }); bold = $true; collapsed = $false; children = @($Body | Where-Object { $null -ne $_ }) })
}

function Get-JournalEntryIndex {
    <# The place of the entry with request reference $Ref among $Entries, or -1. #>
    param([object[]]$Entries = @(), [string]$Ref)
    $list = @($Entries)
    for ($i = 0; $i -lt $list.Count; $i++) { if ($Ref -and [string](Get-JsonProp $list[$i] 'ref' '') -eq $Ref) { return $i } }
    -1
}

Export-ModuleMember -Function Get-JournalDayTitle, Test-JournalDayTitle, Find-JournalDay, New-JournalEntry, Get-JournalSummary, Merge-JournalDay, Get-JournalTargets, New-JournalEntryLines, Get-JournalEntryIndex
