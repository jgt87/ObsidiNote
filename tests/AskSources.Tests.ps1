# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/AskSources.psm1: Ask's source adapters over the index model, against the in-memory OneNote:
# the active vault (top topics, branches, page text read in memory) and a connected notebook (read
# only, short ids), and a whole Ask (lib/Ask.psm1) over them with recorded Copilot replies.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'AskSources', 'Ask') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

Describe 'The active vault as an Ask source' {
    $w = New-SyntheticVault
    $src = New-AskSource -Adapter $w.a -Model $w.open.model -Id $w.open.vault.vaultId -Name 'Synthetic Vault'
    It 'is the writable source with the adapter contract' {
        foreach ($k in 'Id', 'Name', 'Kind', 'ReadOnly', 'GetTopTopics', 'GetBranch', 'ReadPageText') { $src.ContainsKey($k) | Should Be $true }
        $src.ReadOnly | Should Be $false
        $src.Kind | Should Be 'vault'
    }
    It 'lists the top-level topics with page counts (subtopics included) and their subtopics' {
        $tops = @(& $src.GetTopTopics)
        ($tops | ForEach-Object { "$($_.path):$($_.pageCount)" }) -join ',' | Should Be 'Projects:1,Security:2'
        @(@($tops | Where-Object { $_.path -eq 'Security' })[0].subtopics) -join ',' | Should Be 'Networking'
    }
    It 'gives a branch''s pages with their obsn ids and summaries, deeper pages included' {
        $b = & $src.GetBranch 'Security' $false
        (@($b.pages | ForEach-Object { $_.id } | Sort-Object) -join ',') | Should Be 'p1,p3'
        @($b.subtopics)[0].path | Should Be 'Security/Networking'
        @($b.pages | Where-Object { $_.id -eq 'p1' })[0].summary | Should Match 'Never trust the network'
        @($b.pages | Where-Object { $_.id -eq 'p1' })[0].link | Should Match '^onenote:'
    }
    It 'reads a page''s text by id in memory, and nothing for an unknown id' {
        $t = & $src.ReadPageText 'p1'
        $t | Should Match 'Zero-trust networking'
        $t | Should Match 'Every request checks the user and the device'
        & $src.ReadPageText 'p999' | Should BeNullOrEmpty
    }
    It 'writes nothing' {
        $before = $w.f.Writes.Count
        $null = & $src.GetTopTopics; $null = & $src.GetBranch 'Projects' $false; $null = & $src.ReadPageText 'p2'
        $w.f.Writes.Count | Should Be $before
    }
}

Describe 'A connected notebook as an Ask source' {
    $w = New-SyntheticVault
    $m = Get-NotebookModel -Adapter $w.a -NotebookId $w.household -NoLinks
    $src = New-AskSource -Adapter $w.a -Model $m -Id $w.household -Name 'Household' -Kind 'notebook' -ReadOnly
    It 'is read only, with its sections as topics and short page ids' {
        $src.ReadOnly | Should Be $true
        (@(& $src.GetTopTopics) | ForEach-Object { "$($_.path):$($_.pageCount)" }) -join ',' | Should Be 'Garden:2'
        $b = & $src.GetBranch 'Garden' $false
        (@($b.pages | ForEach-Object { $_.id } | Sort-Object) -join ',') | Should Be 'x1,x2'
        @($b.pages | Where-Object { $_.title -eq 'Tomatoes' })[0].type | Should Be 'Garden'
    }
    It 'reads the page text without the HTML' {
        $b = & $src.GetBranch 'Garden' $false
        $id = @($b.pages | Where-Object { $_.title -eq 'Tomatoes' })[0].id
        & $src.ReadPageText $id | Should Match 'Water them every morning\. See the seed list\.'
    }
}

Describe 'Ask over the real sources' {
    $w = New-SyntheticVault
    Reset-AskState
    $active = New-AskSource -Adapter $w.a -Model $w.open.model -Id $w.open.vault.vaultId -Name 'Synthetic Vault'
    $m = Get-NotebookModel -Adapter $w.a -NotebookId $w.household -NoLinks
    $hh = New-AskSource -Adapter $w.a -Model $m -Id $w.household -Name 'Household' -Kind 'notebook' -ReadOnly
    $replies = New-Object System.Collections.Generic.Queue[string]
    foreach ($r in '{"branches":[{"key":"Security","why":"network access"},{"key":"s2.Garden","why":"x"}]}', '{"pages":[{"id":"p1","why":"defines it"}]}', '{"notFound":false,"confidence":"high","paragraphs":[{"sentences":[{"text":"Every request checks the user and the device.","cites":["p1"]}]}]}') { $replies.Enqueue($r) }
    $prompts = New-Object System.Collections.Generic.List[string]
    $copilot = @{ Send = { param([string]$Text) $prompts.Add($Text); $replies.Dequeue() }.GetNewClosure(); NewChat = { } }
    $res = Invoke-AskRequest -Request @{ question = 'How does zero trust check a request?'; sources = @($w.household) } -Context @{ Sources = @($active, $hh); Copilot = $copilot }
    It 'walks the index of both sources and answers with a citation to the vault page' {
        $res.status | Should Be 'answered'
        $prompts[0] | Should Match 's2\.Garden \[Household, read only\]'
        @($res.sources)[0].title | Should Be 'Zero-trust networking'
        @($res.sources)[0].link | Should Match '^onenote:'
        $res.writes | Should Be 0
    }
    It 'sends the page text only in the third prompt' {
        # The body says "network. Every"; the index summary says "network: every".
        $prompts[1] | Should Not Match 'Never trust the network\. Every'
        $prompts[2] | Should Match 'Never trust the network\. Every'
    }
}
