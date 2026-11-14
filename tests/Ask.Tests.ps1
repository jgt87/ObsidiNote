# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Ask (lib/Ask.psm1) with fake sources and a fake Copilot: no OneNote, no Edge, no network.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'lib\Ask.psm1') -Force

$script:Now = [datetime]'2026-11-13T12:00:00'

function New-FakeCopilot {
    <# Replies in order; each is a string, a hashtable/array (sent as JSON) or a scriptblock. #>
    param([object[]]$Replies)
    $state = @{ prompts = (New-Object System.Collections.Generic.List[string]); queue = (New-Object System.Collections.Queue); newChats = 0 }
    foreach ($r in $Replies) { $state.queue.Enqueue($r) }
    $state.Send = {
        param([string]$Text)
        $state.prompts.Add($Text)
        if (-not $state.queue.Count) { throw 'fake Copilot: no reply left' }
        $r = $state.queue.Dequeue()
        if ($r -is [scriptblock]) { & $r $Text } elseif ($r -is [string]) { $r } else { ConvertTo-Json -InputObject $r -Depth 10 -Compress }
    }.GetNewClosure()
    $state.NewChat = { $state.newChats++ }.GetNewClosure()
    $state
}

function New-FakeSource {
    param([string]$Id, [string]$Name, [bool]$ReadOnly, [object[]]$Tops, [hashtable]$Branches, [hashtable]$Texts)
    $s = @{ Id = $Id; Name = $Name; Kind = $(if ($ReadOnly) { 'notebook' } else { 'vault' }); ReadOnly = $ReadOnly
        reads = (New-Object System.Collections.Generic.List[string]); branchCalls = (New-Object System.Collections.Generic.List[string]) }
    $s.GetTopTopics = { $Tops }.GetNewClosure()
    $s.GetBranch = { param([string]$Path, [bool]$IncludeArchived) $s.branchCalls.Add($Path); $Branches[$Path] }.GetNewClosure()
    $s.ReadPageText = { param([string]$PageId) $s.reads.Add($PageId); $Texts[$PageId] }.GetNewClosure()
    $s
}

function New-Vault {
    $n = $script:Now
    New-FakeSource -Id 'v1' -Name 'Team vault' -ReadOnly $false -Tops @(
        @{ path = 'Security'; pageCount = 3; subtopics = @('Security/Networking') }
        @{ path = 'Projects'; pageCount = 2; subtopics = @('Projects/Partner portal') }
        @{ path = 'Cooking'; pageCount = 1; subtopics = @() }
    ) -Branches @{
        'Security' = @{ path = 'Security'; subtopics = @(@{ path = 'Security/Networking'; pageCount = 3 }); pages = @(
                @{ id = 'p1'; title = 'Identity-aware proxies'; summary = 'Proxies that check identity per request.'; paths = @('Security/Networking/Zero trust'); type = 'concept'; updated = $n.ToString('s'); link = 'onenote:#p1' }
                @{ id = 'p2'; title = 'Zero-trust networking'; summary = 'Never trust the network.'; paths = @('Security/Networking/Zero trust'); type = 'concept'; updated = $n.AddDays(-14).ToString('s'); link = 'onenote:#p2' }
                @{ id = 'p3'; title = 'Old VPN notes'; summary = 'Archived VPN notes.'; paths = @('Security/Networking'); type = 'note'; updated = $n.AddDays(-400).ToString('s'); link = 'onenote:#p3'; archived = $true }
            ) }
        'Projects' = @{ path = 'Projects'; subtopics = @(@{ path = 'Projects/Partner portal'; pageCount = 2 }); pages = @(
                @{ id = 'p4'; title = 'Partner portal: access review notes'; summary = 'Review of partner access.'; paths = @('Projects/Partner portal'); type = 'meeting'; updated = $n.ToString('s'); link = 'onenote:#p4' }
                @{ id = 'p5'; title = 'VPN retirement plan'; summary = 'Web page about the VPN plan.'; paths = @('Projects/Partner portal'); type = 'link-web'; url = 'https://example.org/vpn'; updated = $n.AddDays(-35).ToString('s'); summarizedAt = $n.AddDays(-120).ToString('s'); link = 'onenote:#p5' }
            ) }
        'Cooking'  = @{ path = 'Cooking'; subtopics = @(); pages = @(@{ id = 'p6'; title = 'Bread'; summary = 'Sourdough.'; paths = @('Cooking'); type = 'howto'; updated = $n.ToString('s'); link = 'onenote:#p6' }) }
    } -Texts @{ p1 = 'TEXT-P1 The partner portal moves to an identity-aware proxy.'; p2 = 'TEXT-P2 Zero trust checks every request.'; p3 = 'TEXT-P3 old'
        p4 = 'TEXT-P4 Unmanaged partner devices get read-only access.'; p5 = 'TEXT-P5 The VPN is switched off afterwards.'; p6 = 'TEXT-P6 bread' }
}

function New-Notebook {
    New-FakeSource -Id 'nb2' -Name 'Old team notebook' -ReadOnly $true -Tops @(@{ path = 'Recipes'; pageCount = 1 }) -Branches @{
        'Recipes' = @{ path = 'Recipes'; subtopics = @(); pages = @(@{ id = 'r1'; title = 'Partner lunch'; summary = 'Where partners eat.'; paths = @('Recipes'); updated = $script:Now.AddDays(-3).ToString('s'); link = 'onenote:#r1' }) }
    } -Texts @{ r1 = 'TEXT-R1 Partners eat at the canteen.' }
}

function New-Answer {
    param([object[]]$Sentences, [bool]$NotFound = $false, [string]$Confidence = 'high')
    @{ notFound = $NotFound; confidence = $Confidence; paragraphs = @(@{ sentences = @($Sentences) }) }
}

function Invoke-Ask {
    param($Sources, $Copilot, [hashtable]$Request)
    Invoke-AskRequest -Request $Request -Context @{ Sources = @($Sources); Copilot = $Copilot; Now = $script:Now }
}

Describe 'Ask: path through the central index' {
    BeforeEach { Reset-AskState }

    It 'shows only top-level topics in step 1, opens only the picked branches, and drops invented branches' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 'Security'; why = 'about proxies' }, @{ key = 'Invented/Branch'; why = 'x' }, @{ key = 'Projects'; why = 'portal' }) }
            @{ pages = @(@{ id = 'p1'; why = 'a' }, @{ id = 'p4'; why = 'b' }) }
            (New-Answer @(@{ text = 'It moves to a proxy.'; cites = @('p1') }, @{ text = 'Unmanaged devices get read-only access.'; cites = @('p4') }))
        )
        $r = Invoke-Ask $v $cp @{ question = 'What did we decide about the partner portal?' }
        $r.status | Should Be 'answered'
        $cp.prompts[0] | Should Match 'Security'
        $cp.prompts[0] | Should Not Match 'Identity-aware proxies'
        $cp.prompts[0] | Should Not Match 'TEXT-'
        ($v.branchCalls -join ',') | Should Be 'Security,Projects'
        $cp.prompts[1] | Should Match 'Identity-aware proxies'
        $cp.prompts[1] | Should Not Match 'Bread'
        $cp.prompts[1] | Should Not Match 'TEXT-'
        $r.path.branchesPicked | Should Be 2
        $r.path.branchesTotal | Should Be 3
        $r.path.invalidBranches | Should Be 1
        $r.path.summary | Should Be 'Copilot picked 2 of 3 top-level branches, then 2 of 4 pages. Nothing outside these pages was used.'
        @($r.path.steps).Count | Should Be 3
        $r.path.steps[1].label | Should Be 'Security + Projects'
        $r.path.steps[2].label | Should Be '2 pages read'
        ($v.reads -join ',') | Should Be 'p1,p4'
        $cp.prompts[2] | Should Match 'TEXT-P1'
        $cp.prompts[2] | Should Not Match 'TEXT-P2'
        $cp.newChats | Should Be 1
    }

    It 'numbers the sources in order of first citation with title, index path, OneNote link and age' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 'Security' }) }
            @{ pages = @(@{ id = 'p1' }, @{ id = 'p2' }) }
            (New-Answer @(@{ text = 'Zero trust.'; cites = @('p2') }, @{ text = 'A proxy.'; cites = @('p1', 'p2') }))
        )
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        @($r.sources).Count | Should Be 2
        $r.sources[0].title | Should Be 'Zero-trust networking'
        $r.sources[0].n | Should Be 1
        $r.sources[0].path | Should Be 'Security / Networking / Zero trust'
        $r.sources[0].link | Should Be 'onenote:#p2'
        $r.sources[0].age | Should Be '2 weeks ago'
        $r.sources[1].age | Should Be 'today'
        (@($r.answer.paragraphs[0].sentences[1].cites) -join ',') | Should Be '2,1'
        $r.answer.confidence | Should Be 'high'
        $r.writes | Should Be 0
        $r.note | Should Be 'Asking never changes your notebook.'
    }

    It 'accepts a branch named by its bare path and a reply wrapped in prose or a code block' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            'Sure! Here you go: {"branches":[{"path":"security","why":"x"}]} Hope that helps.'
            ('```json' + "`n" + '{"pages":[{"id":"P1"}]}' + "`n" + '```')
            (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') }))
        )
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r.status | Should Be 'answered'
        $r.sources[0].id | Should Be 'p1'
    }

    It 'asks once more in the same chat when a reply has no JSON' {
        $v = New-Vault
        $cp = New-FakeCopilot @('I cannot format that.', @{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }) }, (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') })))
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r.status | Should Be 'answered'
        $cp.prompts[1] | Should Match 'not the JSON object'
        $cp.newChats | Should Be 1
    }

    It 'reports an error, never an answer, when Copilot keeps replying without JSON' {
        $v = New-Vault
        $cp = New-FakeCopilot @('no', 'still no')
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r.ok | Should Be $false
        $r.status | Should Be 'error'
        $r.error | Should Match 'not JSON'
    }
}

Describe 'Ask: citations are checked' {
    BeforeEach { Reset-AskState }

    It 'drops citations of pages that were not sent and flags the sentence' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 'Security' }) }
            @{ pages = @(@{ id = 'p1' }, @{ id = 'p77' }) }
            (New-Answer @(@{ text = 'A proxy.'; cites = @('p1', 'p99') }, @{ text = 'Made up.'; cites = @('p6') }))
        )
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r.status | Should Be 'answered'
        $r.path.invalidPages | Should Be 1
        (@($r.invalidCitations) | Sort-Object) -join ',' | Should Be 'p6,p99'
        @($r.sources).Count | Should Be 1
        $r.answer.paragraphs[0].sentences[0].unsupported | Should Be $false
        $r.answer.paragraphs[0].sentences[1].unsupported | Should Be $true
        @($r.answer.paragraphs[0].sentences[1].cites).Count | Should Be 0
    }

    It 'shows no answer when none of its citations is a page that was sent' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }) }, (New-Answer @(@{ text = 'Invented.'; cites = @('p42') })))
        $r = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r.status | Should Be 'not-found'
        $r.notFound.reason | Should Be 'no-valid-citations'
        $r.answer | Should BeNullOrEmpty
    }

    It 'reads inline [[id]] markers as citations and removes them from the text' {
        $j = ConvertFrom-Json '{"notFound":false,"confidence":"medium","paragraphs":[{"sentences":[{"text":"A proxy [[p1]].","cites":[]}]}]}'
        $sent = [ordered]@{ p1 = @{ key = 'p1'; id = 'p1' } }
        $a = Read-AskAnswer -Json $j -Sent $sent
        $a.paragraphs[0].sentences[0].text | Should Be 'A proxy.'
        (@($a.paragraphs[0].sentences[0].cites) -join ',') | Should Be '1'
        $a.confidence | Should Be 'medium'
    }
}

Describe 'Ask: nothing found' {
    BeforeEach { Reset-AskState }

    It 'stops after step 1 when no branch fits and offers to save an Open question' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @() })
        $r = Invoke-Ask $v $cp @{ question = 'Who won the 1974 cup?' }
        $r.status | Should Be 'not-found'
        $r.notFound.reason | Should Be 'no-branch'
        $r.notFound.suggestion.action | Should Be 'save-open-question'
        $r.notFound.suggestion.pageSpec.openQuestion | Should Be $true
        $r.notFound.suggestion.pageSpec.title | Should Be 'Who won the 1974 cup?'
        $cp.prompts.Count | Should Be 1
        $v.reads.Count | Should Be 0
    }

    It 'says not found when the pages do not answer it, with the branches it looked in as topics' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Projects' }) }, @{ pages = @(@{ id = 'p4' }) }, (New-Answer @() -NotFound $true))
        $r = Invoke-Ask $v $cp @{ question = 'Budget of the portal?' }
        $r.status | Should Be 'not-found'
        $r.notFound.reason | Should Be 'not-in-pages'
        (@($r.notFound.suggestion.pageSpec.topics) -join ',') | Should Be 'Projects'
        $r.message | Should Be 'Nothing in your wiki answers this yet.'
    }

    It 'never calls Copilot for step 2 when no page was offered' {
        $v = New-FakeSource -Id 'v1' -Name 'Empty' -ReadOnly $false -Tops @(@{ path = 'Empty'; pageCount = 0 }) -Branches @{ 'Empty' = @{ path = 'Empty'; subtopics = @(); pages = @() } } -Texts @{}
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Empty' }) })
        $r = Invoke-Ask $v $cp @{ question = 'Anything?' }
        $r.notFound.reason | Should Be 'no-page'
        $cp.prompts.Count | Should Be 1
    }

    It 'returns the Open question spec on request' {
        $r = Invoke-AskRequest -Request @{ action = 'save-open-question'; question = 'Why is the sky blue?' } -Context @{}
        $r.status | Should Be 'page-spec'
        $r.pageSpec.type | Should Be 'note'
        $r.pageSpec.openQuestion | Should Be $true
        $r.writes | Should Be 0
    }
}

Describe 'Ask: archived pages' {
    BeforeEach { Reset-AskState }

    It 'leaves archived pages out by default' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p3' }) })
        $r = Invoke-Ask $v $cp @{ question = 'VPN notes?' }
        $cp.prompts[1] | Should Not Match 'Old VPN notes'
        $r.path.pagesTotal | Should Be 2
        $r.path.invalidPages | Should Be 1
        $r.status | Should Be 'not-found'
    }

    It 'includes archived pages when asked' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p3' }) }, (New-Answer @(@{ text = 'Old notes.'; cites = @('p3') })))
        $r = Invoke-Ask $v $cp @{ question = 'VPN notes?'; includeArchived = $true }
        $cp.prompts[1] | Should Match 'Old VPN notes'
        $r.status | Should Be 'answered'
        $r.sources[0].archived | Should Be $true
    }
}

Describe 'Ask: read-only sources' {
    BeforeEach { Reset-AskState }

    It 'reads only the active vault unless the request names other sources' {
        $v = New-Vault; $nb = New-Notebook
        $cp = New-FakeCopilot @(@{ branches = @() })
        $null = Invoke-Ask @($v, $nb) $cp @{ question = 'Partner lunch?' }
        $cp.prompts[0] | Should Not Match 'Recipes'
    }

    It 'includes a connected notebook as a read-only source with its own keys' {
        $v = New-Vault; $nb = New-Notebook
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 's2.Recipes' }, @{ key = 'Projects' }) }
            @{ pages = @(@{ id = 's2.r1' }, @{ id = 'p4' }) }
            (New-Answer @(@{ text = 'Partners eat at the canteen.'; cites = @('s2.r1') }, @{ text = 'Read-only access.'; cites = @('p4') }))
        )
        $r = Invoke-Ask @($v, $nb) $cp @{ question = 'Partner lunch?'; sources = @('nb2') }
        $cp.prompts[0] | Should Match 's2\.Recipes \[Old team notebook, read only\]'
        ($nb.reads -join ',') | Should Be 'r1'
        $r.sources[0].readOnly | Should Be $true
        $r.sources[0].sourceName | Should Be 'Old team notebook'
        $r.sources[0].id | Should Be 'r1'
        $r.sources[1].readOnly | Should Be $false
        $spec = (Invoke-AskRequest -Request @{ action = 'save-page'; conversationId = $r.conversationId } -Context @{}).pageSpec
        (@($spec.links | ForEach-Object { $_.target }) -join ',') | Should Be 'p4'
        @($spec.references).Count | Should Be 1
        $spec.references[0].title | Should Be 'Partner lunch'
        (@($spec.topics) -join ',') | Should Be 'Projects/Partner portal'
    }
}

Describe 'Ask: stale link summaries' {
    BeforeEach { Reset-AskState }

    It 'offers Update for a cited link summary older than 90 days' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Projects' }) }, @{ pages = @(@{ id = 'p5' }, @{ id = 'p4' }) }, (New-Answer @(@{ text = 'VPN off.'; cites = @('p5') }, @{ text = 'Review.'; cites = @('p4') })))
        $r = Invoke-Ask $v $cp @{ question = 'VPN?' }
        @($r.staleLinks).Count | Should Be 1
        $r.staleLinks[0].id | Should Be 'p5'
        $r.staleLinks[0].ageDays | Should Be 120
        $r.staleLinks[0].offer | Should Be 'update'
        $r.sources[0].stale | Should Be $true
        $r.sources[1].stale | Should Be $false
        # a link page's own address goes to the interface, which opens it before OneNote (2026-11-13)
        $r.sources[0].url | Should Be 'https://example.org/vpn'
        $r.sources[1].url | Should Be ''
    }
}

Describe 'Ask: prompt budget' {
    BeforeEach { Reset-AskState }

    It 'keeps short texts whole and cuts long ones at a paragraph break with a note' {
        Limit-AskText 'short' 100 | Should Be 'short'
        $t = ('a' * 600) + "`n`n" + ('b' * 600)
        $cut = Limit-AskText $t 1000
        $cut.Length -le 1000 | Should Be $true
        $cut | Should Match "^a{600}`n\(trimmed: first 600 of 1202 characters kept\)$"
    }

    It 'shares the budget evenly and gives what short pages leave to the long ones' {
        (Get-AskTextShares -Lengths @(100, 5000, 5000) -Budget 3100) -join ',' | Should Be '100,1500,1500'
        (Get-AskTextShares -Lengths @(10, 20) -Budget 1000) -join ',' | Should Be '10,20'
    }

    It 'keeps step 3 under the prompt limit and lists the trimmed pages' {
        $max = (Get-AskSettings).promptMax
        $texts = @{}; $pages = @()
        foreach ($i in 1..4) {
            $texts["q$i"] = ('Sentence number ' + $i + '. ') * 3000
            $pages += @{ id = "q$i"; title = "Long $i"; summary = 's'; paths = @('Big'); updated = $script:Now.ToString('s') }
        }
        $pages += @{ id = 'q5'; title = 'Short'; summary = 's'; paths = @('Big'); updated = $script:Now.ToString('s') }
        $texts['q5'] = 'TEXT-Q5 short and whole.'
        $v = New-FakeSource -Id 'v1' -Name 'Big' -ReadOnly $false -Tops @(@{ path = 'Big'; pageCount = 5 }) -Branches @{ 'Big' = @{ path = 'Big'; subtopics = @(); pages = $pages } } -Texts $texts
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Big' }) }, @{ pages = @('q1', 'q2', 'q3', 'q4', 'q5') }, (New-Answer @(@{ text = 'Yes.'; cites = @('q1') })))
        $r = Invoke-Ask $v $cp @{ question = 'Big?' }
        $cp.prompts[2].Length -le $max | Should Be $true
        $cp.prompts[2].Length -gt ($max - 2000) | Should Be $true
        (@($r.budget.trimmedPages) | Sort-Object) -join ',' | Should Be 'q1,q2,q3,q4'
        $cp.prompts[2] | Should Match 'TEXT-Q5 short and whole\.'
        $cp.prompts[2] | Should Match '\(trimmed: first \d+ of 57000 characters kept\)'
    }

    It 'keeps step 2 under the prompt limit by listing fewer pages, round-robin over the branches' {
        $max = (Get-AskSettings).promptMax
        $a = @(foreach ($i in 1..600) { @{ id = "a$i"; title = "Alpha page $i"; summary = ('x' * 400); paths = @('A') } })
        $b = @(foreach ($i in 1..600) { @{ id = "b$i"; title = "Beta page $i"; summary = ('y' * 400); paths = @('B') } })
        $src = @{ tag = ''; id = 'v1'; name = 'V'; readOnly = $false; adapter = @{ GetBranch = { param($p, $x) if ($p -eq 'A') { @{ pages = $a } } else { @{ pages = $b } } }.GetNewClosure() } }
        $p2 = New-AskStep2Prompt -Question 'q' -Branches @(@{ key = 'A'; path = 'A'; source = $src }, @{ key = 'B'; path = 'B'; source = $src }) -IncludeArchived $false
        $p2.text.Length -le $max | Should Be $true
        $p2.total | Should Be 1200
        $p2.listed -lt 1200 | Should Be $true
        $p2.listed -gt 100 | Should Be $true
        $alpha = @($p2.offered.Keys | Where-Object { $_ -like 'a*' }).Count
        $beta = @($p2.offered.Keys | Where-Object { $_ -like 'b*' }).Count
        [Math]::Abs($alpha - $beta) -le 1 | Should Be $true
    }

    It 'keeps step 1 under the prompt limit by leaving out the smallest branches' {
        $max = (Get-AskSettings).promptMax
        $tops = @(foreach ($i in 1..2000) { @{ path = "Topic $i"; pageCount = $i; summary = ('z' * 100) } })
        $src = @{ tag = ''; id = 'v1'; name = 'V'; readOnly = $false; adapter = @{ GetTopTopics = { $tops }.GetNewClosure() } }
        $p1 = New-AskStep1Prompt -Question 'q' -Sources @($src)
        $p1.text.Length -le $max | Should Be $true
        $p1.total | Should Be 2000
        $p1.offered.Contains('Topic 2000') | Should Be $true
        $p1.offered.Contains('Topic 1') | Should Be $false
    }
}

Describe 'Ask: follow-ups and saving' {
    BeforeEach { Reset-AskState }

    It 'asks a follow-up in the same chat from the same pages without sending their text again' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }, @{ id = 'p2' }) }, (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') }))
            (New-Answer @(@{ text = 'Every request is checked.'; cites = @('p2', 'p4') }))
        )
        $r1 = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $r2 = Invoke-Ask $v $cp @{ action = 'follow-up'; conversationId = $r1.conversationId; question = 'How are requests checked?' }
        $cp.newChats | Should Be 1
        $cp.prompts[3] | Should Match 'p1, p2'
        $cp.prompts[3] | Should Not Match 'TEXT-'
        $r2.status | Should Be 'answered'
        $r2.turn | Should Be 2
        $r2.path.followUp | Should Be $true
        (@($r2.invalidCitations) -join ',') | Should Be 'p4'
        $r2.sources[0].id | Should Be 'p2'
        $v.reads.Count | Should Be 2
    }

    It 'sends the pages again in a new chat when another question took the chat' {
        $v = New-Vault
        $cp = New-FakeCopilot @(
            @{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }) }, (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') }))
            @{ branches = @() }
            (New-Answer @(@{ text = 'Still a proxy.'; cites = @('p1') }))
        )
        $r1 = Invoke-Ask $v $cp @{ question = 'proxy?' }
        $null = Invoke-Ask $v $cp @{ question = 'Something else?' }
        $r3 = Invoke-Ask $v $cp @{ action = 'follow-up'; conversationId = $r1.conversationId; question = 'And then?' }
        $cp.newChats | Should Be 3
        $cp.prompts[4] | Should Match 'TEXT-P1'
        $cp.prompts[4] | Should Match 'Earlier questions: "proxy\?"'
        $r3.status | Should Be 'answered'
    }

    It 'returns a note page spec with topics and links from the cited pages' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }, @{ key = 'Projects' }) }, @{ pages = @(@{ id = 'p1' }, @{ id = 'p4' }, @{ id = 'p2' }) },
            (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') }, @{ text = 'Read-only.'; cites = @('p4') })))
        $r = Invoke-Ask $v $cp @{ question = 'What did we decide about the partner portal?' }
        $s = Invoke-AskRequest -Request @{ action = 'save-page'; conversationId = $r.conversationId } -Context @{}
        $s.status | Should Be 'page-spec'
        $s.writes | Should Be 0
        $s.pageSpec.type | Should Be 'note'
        $s.pageSpec.title | Should Be 'What did we decide about the partner portal?'
        (@($s.pageSpec.topics) -join ',') | Should Be 'Security/Networking/Zero trust,Projects/Partner portal'
        (@($s.pageSpec.links | ForEach-Object { $_.target }) -join ',') | Should Be 'p1,p4'
        $s.pageSpec.links[0].why | Should Be 'cited in the answer'
        $s.pageSpec.body.paragraphs[0] | Should Be 'A proxy. [1] Read-only. [2]'
    }

    It 'refuses to save when the conversation is unknown' {
        $s = Invoke-AskRequest -Request @{ action = 'save-page'; conversationId = 'nope' } -Context @{}
        $s.ok | Should Be $false
    }

    It 'turns a result into JSON the window can send' {
        $v = New-Vault
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }) }, (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') })))
        $r = Invoke-Ask $v $cp @{ text = '? proxy'; mode = 'ask' }
        $r.question | Should Be 'proxy'
        $json = ConvertTo-Json -InputObject $r -Depth 10 -Compress
        $back = ConvertFrom-Json $json
        $back.answer.paragraphs[0].sentences[0].cites[0] | Should Be 1
        $back.sources[0].title | Should Be 'Identity-aware proxies'
    }

    It 'reports progress for the three steps' {
        $v = New-Vault
        $seen = New-Object System.Collections.Generic.List[string]
        $cp = New-FakeCopilot @(@{ branches = @(@{ key = 'Security' }) }, @{ pages = @(@{ id = 'p1' }) }, (New-Answer @(@{ text = 'A proxy.'; cites = @('p1') })))
        $null = Invoke-AskRequest -Request @{ question = 'proxy?' } -Context @{ Sources = @($v); Copilot = $cp; Now = $script:Now; OnProgress = { param($n, $label) $seen.Add("$n $label") }.GetNewClosure() }
        ($seen -join '|') | Should Be '1 Finding branches...|2 Choosing pages...|3 Writing the answer...'
    }
}

Describe 'Ask never writes and never logs content' {
    $src = [IO.File]::ReadAllLines((Join-Path $root 'lib\Ask.psm1')) | Where-Object { $_ -notmatch '^\s*#' }
    It 'has no file write and no OneNote write call' {
        $writes = '(?i)\b(WriteAllText|WriteAllLines|WriteAllBytes|AppendAllText|Set-Content|Add-Content|Out-File|Tee-Object|StreamWriter|FileStream|UpdatePageContent|CreateNewPage|DeleteHierarchy|DeletePageContent|OpenHierarchy|NavigateTo)\b'
        (@($src | Where-Object { $_ -match $writes }) -join "`n") | Should Be ''
    }
    It 'logs ids and counts only' {
        $calls = @($src | Where-Object { $_ -match 'Write-AskLog\s+''' })
        $calls.Count -gt 0 | Should Be $true
        (@($calls | Where-Object { $_ -match '\$(Question|Text|text|reply|title)\b(?!\.Length)|\.text\b(?!\.Length)|\.title\b' }) -join "`n") | Should Be ''
    }
}
