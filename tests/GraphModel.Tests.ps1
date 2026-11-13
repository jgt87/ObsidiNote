# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/GraphModel.psm1: the index model -> the knowledge graph's GraphModel (ui-src/src/graph/model.ts).
# Pure; a hand-made model plus one from the in-memory OneNote for a connected notebook.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'GraphModel') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')

function New-TestModel {
    $m = New-IndexModel -Kind 'vault' -VaultId 'v1'
    $null = Add-IndexPage -Model $m -Page @{ id = 'p1'; title = 'Zero trust'; type = 'concept'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{A}'; link = 'onenote:#p1'; summary = 'Never trust.'; topics = @('Security/Networking'); links = @(@{ target = 'p2'; strength = 3; why = 'core' }, @{ target = 'p9'; strength = 2; why = 'gone' }); updated = '2026-11-01T00:00:00.000Z' }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p2'; title = 'Proxy'; type = 'concept'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{B}'; link = 'https://not-onenote.example.invalid/'; topics = @('Security', 'Projects'); links = @(@{ target = 'p1'; strength = 9; why = 'back' }) }
    $null = Add-IndexPage -Model $m -Page @{ id = 'p3'; title = 'Loose note'; type = 'note'; bucket = 'Notes'; section = 'Notes'; oneNoteId = '{C}'; status = 'archived' }
    $m
}

Describe 'ConvertTo-GraphModel' {
    $g = ConvertTo-GraphModel -Model (New-TestModel) -Source @{ kind = 'vault'; id = 'v1'; name = 'Synthetic'; readOnly = $false }
    It 'names the source' {
        $g.source.kind | Should Be 'vault'
        $g.source.name | Should Be 'Synthetic'
        $g.source.readOnly | Should Be $false
    }
    It 'makes one topic per path with its parent, display path and a page count that includes subtopics' {
        ($g.topics | ForEach-Object { "$($_.id)|$($_.parent)|$($_.pageCount)" }) -join ',' | Should Be 'Security||2,Security/Networking|Security|1,Projects||1'
        @($g.topics | Where-Object { $_.id -eq 'Security/Networking' })[0].path | Should Be 'Security / Networking'
        @($g.topics | Where-Object { $_.id -eq 'Security' })[0].subjects | Should Be 'Networking'
    }
    It 'draws a page in its first topic; a page without topics is Unfiled (no topic ids)' {
        (@($g.pages | Where-Object { $_.id -eq 'p2' })[0].topicIds -join ',') | Should Be 'Security,Projects'
        @(@($g.pages | Where-Object { $_.id -eq 'p3' })[0].topicIds).Count | Should Be 0
    }
    It 'keeps only links between pages of the model, strength clamped, counted per page' {
        ($g.edges | ForEach-Object { "$($_.from)>$($_.to):$($_.strength)" }) -join ',' | Should Be 'p1>p2:3,p2>p1:3'
        @($g.pages | Where-Object { $_.id -eq 'p1' })[0].links | Should Be 2
        @($g.pages | Where-Object { $_.id -eq 'p3' })[0].unlinked | Should Be $true
    }
    It 'passes only onenote: links on, and marks archived pages' {
        @($g.pages | Where-Object { $_.id -eq 'p1' })[0].onenoteUrl | Should Be 'onenote:#p1'
        @($g.pages | Where-Object { $_.id -eq 'p2' })[0].onenoteUrl | Should Be ''
        @($g.pages | Where-Object { $_.id -eq 'p3' })[0].archived | Should Be $true
    }
    It 'passes aliases and a link page''s site on' {
        $m = New-TestModel
        $null = Add-IndexPage -Model $m -Page @{ id = 'p4'; title = 'Example site'; type = 'link-web'; bucket = 'Web links'; section = 'Web links'; oneNoteId = '{D}'; aliases = @('ES'); host = 'example.org' }
        $p = @((ConvertTo-GraphModel -Model $m -Source @{ kind = 'vault'; id = 'v1'; name = 'S'; readOnly = $false }).pages | Where-Object { $_.id -eq 'p4' })[0]
        ($p.aliases -join ',') | Should Be 'ES'
        $p.site | Should Be 'example.org'
        $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress
        $json | Should Match '"aliases":\[\]'
    }
    It 'serialises lists as lists (one item, none) for the interface' {
        $json = ConvertTo-Json -InputObject $g -Depth 12 -Compress
        $json | Should Match '"topicIds":\[\]'
        $json | Should Match '"topicIds":\["Security/Networking"\]'
    }
}

Describe 'A connected notebook, read only' {
    $f = New-FakeOneNote
    $nb = $f.AddNotebook('Household')
    $s = $f.AddSection($nb, 'Garden')
    $a = $f.AddPage($s, 'Tomatoes', @{}, 1, '')
    $b = $f.AddPage($s, 'Watering', @{}, 2, '')
    $link = $f.GetHyperlinkToObject($b)
    $f.Nodes[$a].outlines.Add(@{ objectId = '{O}'; role = ''; xml = '<one:Outline objectID="{O}"><one:OEChildren><one:OE><one:T><![CDATA[<a href="' + $link + '">watering</a>]]></one:T></one:OE></one:OEChildren></one:Outline>' }) | Out-Null
    $m = Get-NotebookModel -Adapter $f -NotebookId $nb
    $null = Get-NotebookLinks -Adapter $f -Model $m
    $g = ConvertTo-GraphModel -Model $m -Source @{ kind = 'notebook'; id = $nb; name = 'Household'; readOnly = $true }
    It 'shows its sections as topic areas, its pages read only, and its onenote: links as edges' {
        $g.source.readOnly | Should Be $true
        ($g.topics | ForEach-Object { $_.id }) -join ',' | Should Be 'Garden'
        @($g.pages | Where-Object { -not $_.readOnly }).Count | Should Be 0
        @($g.edges).Count | Should Be 1
    }
}
