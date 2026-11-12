# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The Copilot bridge (lib/CopilotBridge.psm1): its pure parts, ported from the CCBridge tests
# (ReplyMerge, StreamHub, DamagedHtml, CopilotLock, BusyCopilot, CopilotTheme, HumanInTheLoop and
# Agents), plus ObsidiNote's own session and no-content rules. No network and no Edge: Copilot's
# page and connection are mocked. The fixtures are recorded Chathub frames, scrubbed (ids zeroed;
# timestamps, locale, metering, tenant and user fields removed).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\CopilotBridge.psm1') -Force
$fixtures = Join-Path $here 'fixtures'

function Get-Fixture([string]$Name) {
    [IO.File]::ReadAllLines((Join-Path $fixtures $Name), [Text.Encoding]::UTF8)
}

function New-AgentFrames([string]$Origin, [string]$Text, [string]$AgentName) {
    # Frames in the shape recorded from a tenant with Copilot's agents (ids replaced).
    $id = '00000000-0000-0000-0000-000000000000'
    $upd = @{ type = 1; target = 'update'; arguments = @(@{ messages = @(@{ author = 'bot'; text = $Text; contentOrigin = $Origin; messageId = $id; requestId = 'r' }); requestId = 'r' }) }
    $progress = @{ type = 1; target = 'update'; arguments = @(@{ messages = @(@{ author = 'bot'; text = 'Checking sources'; messageType = 'Progress'; contentOrigin = 'ChainOfThoughtSummary'; messageId = '1' }); requestId = 'r' }) }
    $user = @{ author = 'user'; text = 'Compare three generators'; gptIdentifiers = @(@{ id = 'x'; compliantAgentName = $AgentName }) }
    if (-not $AgentName) { $user.Remove('gptIdentifiers') }
    $done = @{ type = 2; invocationId = '0'; item = @{ messages = @($user, @{ author = 'bot'; text = $Text; contentOrigin = $Origin; messageId = $id }); result = @{ value = 'Success' }; conversationId = 'c' } }
    $sep = [string][char]0x1e
    @(($progress | ConvertTo-Json -Depth 8 -Compress) + $sep, ($upd | ConvertTo-Json -Depth 8 -Compress) + $sep, ($done | ConvertTo-Json -Depth 8 -Compress) + $sep)
}

function Rec([string]$Json) { $Json | ConvertFrom-Json }

Describe 'Reply reconstruction from Chathub frames' {
    It 'keeps bracketed code that Copilot''s link filter deletes' {
        $r = Get-ReplyFromFrames (Get-Fixture 'brackets.jsonl')
        $r.Text | Should Match ([regex]::Escape('[math]::Round($x[0], 2); $h = @{a=1}; Write-Host "[1] [^2] [link](http://x)"'))
        $r.ServerText | Should Not Match ([regex]::Escape('[math]::'))
        $r.Text.TrimEnd() | Should Match '```$'
    }
    It 'rebuilds a long code reply exactly, including indentation after a filtered line' {
        $r = Get-ReplyFromFrames (Get-Fixture 'python-inventory.jsonl')
        $r.Text | Should Match ([regex]::Escape("if quantity >= self.items[name]:`n            del self.items[name]"))
        $r.Text | Should Match ([regex]::Escape("if not self.items:`n            print(""Inventory is empty"")"))
        # Apart from the filtered line, the rebuilt text must equal the server's text.
        $r.Text.Replace("[name]:`n            ", '') | Should BeExactly $r.ServerText
    }
}

Describe 'Cited sources (Work IQ / web)' {
    It 'lists sourceAttributions and references once, with title, url and kind' {
        $bot = '{"sourceAttributions":[{"providerDisplayName":"Q3 budget.xlsx","seeMoreUrl":"https://contoso.sharepoint.com/x","sourceType":"File"},{"providerDisplayName":"Q3 budget.xlsx","seeMoreUrl":"https://contoso.sharepoint.com/x","sourceType":"File"}],"references":[{"title":"RE: planning","type":"Email"},{"imageLink":"only-an-image"}]}' | ConvertFrom-Json
        $refs = @(& (Get-Module CopilotBridge) { param($b) Get-ReplyReferences $b } $bot)
        $refs.Count | Should Be 2
        $refs[0].title | Should Be 'Q3 budget.xlsx'
        $refs[0].kind | Should Be 'File'
        $refs[1].title | Should Be 'RE: planning'
        $refs[1].kind | Should Be 'Email'
    }
    It 'returns nothing for a reply without sources' {
        @(& (Get-Module CopilotBridge) { param($b) Get-ReplyReferences $b } ('{"text":"hi"}' | ConvertFrom-Json)).Count | Should Be 0
    }
}

Describe 'A part of the reply that arrives after the end signal (Merge-LateReplyText)' {
    $have = "Here is the plan for the change.`n`n1. Read the settings file first.`n2. Add the new option to the form."
    It 'adds only the new tail when the page holds a longer version of the same reply' {
        $page = $have + "`n3. Save the option and show it in the list of settings.`n4. Test it."
        $r = Merge-LateReplyText $have $page
        $r.how | Should Be 'tail'
        $r.text | Should Be $page
    }
    It 'keeps the reply when the page has nothing more, or shows another reply' {
        Merge-LateReplyText $have $have | Should BeNullOrEmpty
        Merge-LateReplyText $have ($have + ' Done.') | Should BeNullOrEmpty
        Merge-LateReplyText $have ('A completely different answer about something else entirely, ' * 3) | Should BeNullOrEmpty
    }
    It 'uses the page text when the end of the reply cannot be found in it' {
        $page = "Here is the plan for the change.`n`n1. Read the settings file first, then the form.`n2. Add the new option to the form and the list of settings it shows."
        (Merge-LateReplyText "Here is the plan for the change.`n`n1. Read the settings file first." $page).how | Should Be 'page'
    }
}

Describe 'A reply with a damaged tag is replaced by the page copy of the same reply' {
    It 'recognises damaged tag text and leaves correct HTML and code alone' {
        Test-DamagedTagText "ACTION edit index.html`n  ./data/example.jsscript>`n</head>" | Should Be $true
        Test-DamagedTagText '<script src="./data/example.jsd>' | Should Be $true
        Test-DamagedTagText "<script src=`"./data/example.js`"></script>`n<button onClick={() => go(`"a`")}>Go</button>" | Should Be $false
        Test-DamagedTagText 'if (a < b && c > d) { x = 1; }' | Should Be $false
        Test-DamagedTagText "<head>`nstyles/kit/kit.css`n</head>" | Should Be $true
        Test-DamagedTagText "<head>`n<link rel=""stylesheet"" href=""styles/kit/kit.css"">`n</head>" | Should Be $false
    }
    It 'takes the page copy when it starts the same and is intact' {
        $m = @(Get-Module CopilotBridge)[-1]
        $r = & $m {
            function Receive-CdpEvent { $null }
            function Get-PageReplyState { [pscustomobject]@{ stop = $false } }
            function Get-PageReplyText { [pscustomobject]@{ how = 'state'; text = "Fixing it.`n<script src=`"./data/example.js`"></script>" } }
            $bridge = [pscustomobject]@{ Session = $null; Pacing = @{ lateReplySec = 0.1 } }
            Update-LateReply $bridge ([pscustomobject]@{ Text = "Fixing it.`n./data/example.jsscript>"; Uncertain = 0 })
        }
        $r.Text | Should Match '<script src="\./data/example\.js"></script>'
        $r.TagRepaired | Should Be $true
    }
}

Describe 'Add-StreamRecord (replies over the Copilot stream connection)' {
    It 'collects writeAtCursor chunks and ends on a result' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":2,"invocationId":"1","item":{"writeAtCursor":"Hello "}}')
        Add-StreamRecord $s (Rec '{"type":2,"invocationId":"1","item":{"writeAtCursor":"[x]: y"}}')
        $s.Done | Should Be $false
        Add-StreamRecord $s (Rec '{"type":2,"invocationId":"1","item":{"messages":[{"author":"bot","text":"Hello y"}],"result":{"value":"Success"},"throttling":{"numUserMessagesInConversation":1,"maxNumUserMessagesInConversation":30}}}')
        $s.Done | Should Be $true
        $s.Merger.Text | Should BeExactly 'Hello [x]: y'
        $s.Throttling.maxNumUserMessagesInConversation | Should Be 30
    }
    It 'finds the parts when they are nested deeper in the item' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":2,"item":{"event":{"payload":{"writeAtCursor":"abc"}}}}')
        Add-StreamRecord $s (Rec '{"type":2,"item":{"event":{"isFinal":true}}}')
        $s.Done | Should Be $true
        $s.Why | Should Be 'isFinal=true'
        $s.Merger.Text | Should BeExactly 'abc'
        $s.Keys -contains 'event.payload.writeAtCursor' | Should Be $true
    }
    It 'ends on a state field with a final value' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":2,"item":{"status":"Streaming","messages":[{"author":"bot","text":"Hi"}]}}')
        $s.Done | Should Be $false
        Add-StreamRecord $s (Rec '{"type":2,"item":{"status":"Completed"}}')
        $s.Done | Should Be $true
        $s.Merger.Text | Should BeExactly 'Hi'
    }
    It 'ends on an isLastUpdate flag, as some tenants mark the last update' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":2,"item":{"argument":{"isLastUpdate":false,"messages":[{"author":"bot","text":"Hi"}]}}}')
        $s.Done | Should Be $false
        Add-StreamRecord $s (Rec '{"type":2,"item":{"argument":{"isLastUpdate":true,"messages":[{"author":"bot","text":"Hi there"}]}}}')
        $s.Done | Should Be $true
        $s.Why | Should Be 'isLastUpdate=true'
    }
    It 'ends on a completion record after items, and reports a non-success result' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":3,"invocationId":"1"}')
        $s.Done | Should Be $false
        Add-StreamRecord $s (Rec '{"type":2,"item":{"writeAtCursor":"x"}}')
        Add-StreamRecord $s (Rec '{"type":3,"invocationId":"1"}')
        $s.Done | Should Be $true
        $t = New-StreamState
        Add-StreamRecord $t (Rec '{"type":2,"item":{"result":{"value":"OutOfCredits","message":"limit"}}}')
        $t.Done | Should Be $true
        $t.Why | Should Be 'result OutOfCredits'
    }
    It 'does not end on a success result without any text' {
        $s = New-StreamState
        Add-StreamRecord $s (Rec '{"type":2,"item":{"result":{"value":"Success"}}}')
        $s.Done | Should Be $false
    }
}

Describe 'Page texts that are not an answer' {
    $m = Get-Module CopilotBridge
    It 'recognises usage-limit banners' {
        (& $m { $args[0] -match $script:LimitPattern } "You've reached your daily limit. Get more usage now or check back at 2:00 AM.") | Should Be $true
        (& $m { $args[0] -match $script:LimitPattern } 'Here is the recursion explanation.') | Should Be $false
    }
    It 'recognises progress placeholders but not real answers' {
        $ell = [string][char]0x2026
        (& $m { $args[0] -match $script:PlaceholderPattern } ('Working on it' + $ell)) | Should Be $true
        (& $m { $args[0] -match $script:PlaceholderPattern } 'Taking a look...') | Should Be $true
        (& $m { $args[0] -match $script:PlaceholderPattern } 'Recursion is when a function calls itself to solve smaller parts of a problem.') | Should Be $false
        (& $m { $args[0] -match $script:PlaceholderPattern } 'Searching the web gives 42') | Should Be $false
    }
}

Describe 'Copilot tab hosts and selectors' {
    $sel = [pscustomobject]@{ chatUrl = 'https://www.microsoft365.com/chat'; chatHosts = @('microsoft365.com', 'm365.cloud.microsoft') }
    It 'recognises the Copilot tab on both hosts' {
        Test-CopilotUrl 'https://www.microsoft365.com/chat' $sel | Should Be $true
        Test-CopilotUrl 'https://m365.cloud.microsoft/chat/conversation/x' $sel | Should Be $true
        Test-CopilotUrl 'https://login.microsoftonline.com/x' $sel | Should Be $false
        Test-CopilotUrl 'https://evilmicrosoft365.com/chat' $sel | Should Be $false
    }
    It 'falls back to the host of chatUrl when chatHosts is missing' {
        Test-CopilotUrl 'https://m365.cloud.microsoft/chat' ([pscustomobject]@{ chatUrl = 'https://m365.cloud.microsoft/chat' }) | Should Be $true
    }
    It 'reads the shipped selectors.json with every selector the bridge needs' {
        $s = Get-CopilotSelectors
        foreach ($k in 'chatUrl', 'editor', 'sendButton', 'stopButton', 'chatHubUrlPattern', 'streamHubUrlPattern', 'replyContainer', 'copyReplyButton', 'newChatButton') {
            "$($s.$k)" | Should Not BeNullOrEmpty
        }
        Test-CopilotUrl $s.chatUrl $s | Should Be $true
    }
    It 'lays selectors.local.json over selectors.json key by key' {
        $app = Join-Path $env:TEMP ('obsn-sel-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
        [IO.File]::WriteAllText((Join-Path $app 'config\selectors.json'), '{"chatUrl":"https://www.microsoft365.com/chat","editor":"#a"}')
        [IO.File]::WriteAllText((Join-Path $app 'config\selectors.local.json'), '{"editor":"#b"}')
        $s = Get-CopilotSelectors -AppRoot $app
        $s.editor | Should Be '#b'
        $s.chatUrl | Should Be 'https://www.microsoft365.com/chat'
        Remove-Item $app -Recurse -Force
    }
}

Describe 'Pacing (config\obsidinote.json "pacing")' {
    It 'uses the defaults without a pacing block, and the configured values with one' {
        $app = Join-Path $env:TEMP ('obsn-pace-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
        [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), '{"autoUpdate":true}')
        $p = Get-CopilotPacing -AppRoot $app
        $p.betweenPromptsSec | Should Be 5.0
        $p.lateReplySec | Should Be 2.0
        [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.local.json'), '{"pacing":{"betweenPromptsSec":8,"beforeSendSec":0}}')
        $p = Get-CopilotPacing -AppRoot $app
        $p.betweenPromptsSec | Should Be 8
        $p.beforeSendSec | Should Be 0
        $p.newChatSettleSec | Should Be 3.0
        Remove-Item $app -Recurse -Force
    }
    It 'pauses nothing when a pause is 0 or the bridge has no pacing' {
        $m = Get-Module CopilotBridge
        $w = [Diagnostics.Stopwatch]::StartNew()
        & $m { Wait-Pacing ([pscustomobject]@{ Session = $null; Pacing = @{ beforeSendSec = 0 } }) 'beforeSendSec' 'test' }
        & $m { Wait-Pacing ([pscustomobject]@{ Session = $null }) 'beforeSendSec' 'test' }
        $w.ElapsedMilliseconds | Should BeLessThan 500
    }
}

Describe 'Agent replies and progress lines' {
    It 'names the agent that answered, from the completion record' {
        Get-AgentDisplayName 'ResearcherAgent' | Should BeExactly 'Researcher'
        Get-AgentDisplayName 'analyst' | Should BeExactly 'Analyst'
        $r = Get-ReplyFromFrames (New-AgentFrames 'DeepLeo:researcher-research' '# Report' 'ResearcherAgent')
        $r.Agent | Should BeExactly 'Researcher'
        $r.Text | Should Be '# Report'
        $r.IsPlan | Should Be $false
        (Get-ReplyFromFrames (New-AgentFrames 'DeepLeo' 'Hi' '')).Agent | Should Be ''
    }
    It 'recognises Researcher''s research plan, which waits for the person' {
        $r = Get-ReplyFromFrames (New-AgentFrames 'DeepLeo:researcher-planning' 'My plan. Which period?' 'ResearcherAgent')
        $r.IsPlan | Should Be $true
        $r.Origin | Should Be 'DeepLeo:researcher-planning'
    }
    It 'takes the first line of the newest progress message, not the checklist or the answer' {
        $msgs = @(
            [pscustomobject]@{ author = 'bot'; messageType = 'Progress'; contentOrigin = 'ChainOfThoughtSummary'; text = "**Searching for release details**`n`nLooking into three generators." },
            [pscustomobject]@{ author = 'bot'; messageType = 'Progress'; contentOrigin = 'TodoListContentOrigin'; contentType = 'TodoList'; text = 'step 1; step 2' },
            [pscustomobject]@{ author = 'bot'; text = '# Report' })
        Get-ProgressLine $msgs | Should BeExactly 'Searching for release details'
        Get-ProgressLine @([pscustomobject]@{ author = 'bot'; text = 'answer' }) | Should Be ''
        (Get-ProgressLine @([pscustomobject]@{ author = 'bot'; messageType = 'Progress'; text = ('x' * 200) })).Length | Should Be 120
    }
}

Describe 'Microsoft 365 action proposals in replies' {
    $bridge = Get-Module CopilotBridge
    It 'finds confirmation buttons in adaptive cards and action messages' {
        $item = @'
{"messages":[
 {"author":"bot","text":"Here is a draft.","adaptiveCards":[{"type":"AdaptiveCard","body":[{"type":"TextBlock","text":"To: Anna"}],"actions":[{"type":"Action.Submit","title":"Send"},{"type":"Action.OpenUrl","title":"Open in Outlook"}]}]},
 {"author":"bot","messageType":"ActionConfirmation","text":"Cancel the meeting Weekly sync?"},
 {"author":"bot","messageType":"HintInvocation"},
 {"author":"bot","messageType":"Progress","text":"Working"}]}
'@ | ConvertFrom-Json
        $found = @(& $bridge { param($i) Get-ProposedActions $i } $item)
        $found.Count | Should Be 2
        ($found | Where-Object kind -eq 'button').title | Should Be 'Send'
        ($found | Where-Object kind -eq 'ActionConfirmation').title | Should Match 'Weekly sync'
    }
    It 'reports nothing for an ordinary reply' {
        $item = '{"messages":[{"author":"bot","text":"Done.","adaptiveCards":[{"type":"AdaptiveCard","body":[{"type":"TextBlock","text":"Done."}]}]}]}' | ConvertFrom-Json
        @(& $bridge { param($i) Get-ProposedActions $i } $item).Count | Should Be 0
    }
    It 'notices claims of completed Microsoft 365 actions but not code talk' {
        @(& $bridge { param($t) Get-ActionClaims $t } 'I have sent the email to Anna. The meeting has been cancelled.').Count | Should Be 2
        @(& $bridge { param($t) Get-ActionClaims $t } 'I removed the unused function and moved the helper to utils.ps1.').Count | Should Be 0
    }
}

Describe 'The length the message box should show (Get-TypedLength)' {
    It 'leaves out line breaks and the zero-width characters the box measurement leaves out' {
        $zw = [string][char]0x200B
        Get-TypedLength "ab${zw}c`r`nd" | Should Be 4
        Get-TypedLength ("x" * 10 + ([string][char]0x200C) * 3) | Should Be 10
        Get-TypedLength '' | Should Be 0
    }
}

Describe 'Set-CopilotTheme' {
    Mock -ModuleName CopilotBridge Invoke-Cdp { param($Session, $Method, $Params) $global:obsnCdp += , @{ method = $Method; params = $Params } }
    $bridge = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $false } }
    It 'tells the tab which theme the system prefers, and clears it for system' {
        $global:obsnCdp = @()
        Set-CopilotTheme $bridge 'dark'
        Set-CopilotTheme $bridge 'light'
        Set-CopilotTheme $bridge 'system'
        $global:obsnCdp.Count | Should Be 3
        $global:obsnCdp[0].method | Should Be 'Emulation.setEmulatedMedia'
        @($global:obsnCdp[0].params.features)[0].value | Should Be 'dark'
        @($global:obsnCdp[1].params.features)[0].value | Should Be 'light'
        ($global:obsnCdp[2].params | ConvertTo-Json -Compress) | Should Be '{"features":[]}'
        { Set-CopilotTheme $bridge 'blue' } | Should Throw
    }
}

Describe 'Send-CopilotPrompt keeps waiting while Copilot is busy' {
    Mock -ModuleName CopilotBridge Set-PageReplyBaseline { }
    Mock -ModuleName CopilotBridge Set-CopilotInput { }
    Mock -ModuleName CopilotBridge Invoke-CopilotSend { }
    Mock -ModuleName CopilotBridge Wait-Pacing { }
    Mock -ModuleName CopilotBridge Receive-CdpEvent { Start-Sleep -Milliseconds 100; $null }
    Mock -ModuleName CopilotBridge Test-CopilotGaveUp { $false }
    Mock -ModuleName CopilotBridge Stop-CopilotReply { $global:obsnStops++; 'stopped' }
    Mock -ModuleName CopilotBridge Get-PageReplyText { [pscustomobject]@{ how = 'none'; text = ''; parts = 0 } }
    $bridge = [pscustomobject]@{ Session = [pscustomobject]@{ Events = New-Object System.Collections.Queue; Ws = $null; Lost = $false }
        Selectors = [pscustomobject]@{ stopButton = 'button.stop' }; AttachErrors = @(); PageCheckMs = 200; PageStableSec = 1.0; Pacing = @{ lateReplySec = 0 } }

    It 'waits past the reply limit while the Stop button shows, up to the cap, then stops' {
        $global:obsnStops = 0
        Mock -ModuleName CopilotBridge Get-PageReplyState { [pscustomobject]@{ fresh = 0; lastFresh = $false; replies = 1; copies = 0; stop = $true; lastLen = 10; lastHasCopy = $false; bar = ''; agentBusy = $false } }
        $w = [Diagnostics.Stopwatch]::StartNew()
        $err = $null
        try { $null = Send-CopilotPrompt $bridge 'hello' -TimeoutSec 1 -MaxTimeoutSec 4 -StallSec 0 } catch { $err = $_.Exception.Message }
        $err | Should Match 'No complete reply within [3-5] s'
        $w.Elapsed.TotalSeconds | Should BeGreaterThan 3.5
        $global:obsnStops | Should Be 1
    }
    It 'stops at the reply limit when Copilot no longer shows that it is working' {
        Mock -ModuleName CopilotBridge Get-PageReplyState { [pscustomobject]@{ fresh = 0; lastFresh = $false; replies = 1; copies = 0; stop = $false; lastLen = 10; lastHasCopy = $false; bar = ''; agentBusy = $false } }
        $w = [Diagnostics.Stopwatch]::StartNew()
        $err = $null
        try { $null = Send-CopilotPrompt $bridge 'hello' -TimeoutSec 1 -MaxTimeoutSec 4 -StallSec 0 } catch { $err = $_.Exception.Message }
        $err | Should Match 'No complete reply within [12] s'
        $w.Elapsed.TotalSeconds | Should BeLessThan 3.5
    }
    It 'never calls a request lost (and sends it again) while the page shows Copilot at work' {
        Mock -ModuleName CopilotBridge Get-PageReplyState { [pscustomobject]@{ fresh = 0; lastFresh = $false; replies = 1; copies = 0; stop = $true; lastLen = 0; lastHasCopy = $false; bar = ''; agentBusy = $false } }
        $r = $null; $err = $null
        try { $r = & (Get-Module CopilotBridge) { param($b) Send-CopilotPromptUnlocked -Bridge $b -Text 'hello' -TimeoutSec 3 -MaxTimeoutSec 3 -StallSec 0 -LostSec 1 } $bridge } catch { $err = $_.Exception.Message }
        if ($r) { $r.Result | Should Not Be 'Lost' }
        $err | Should Match 'No complete reply'
    }
    It 'still calls a request lost when the page shows nothing at all' {
        Mock -ModuleName CopilotBridge Get-PageReplyState { [pscustomobject]@{ fresh = 0; lastFresh = $false; replies = 1; copies = 0; stop = $false; lastLen = 0; lastHasCopy = $false; bar = ''; agentBusy = $false } }
        $r = & (Get-Module CopilotBridge) { param($b) Send-CopilotPromptUnlocked -Bridge $b -Text 'hello' -TimeoutSec 10 -MaxTimeoutSec 10 -StallSec 0 -LostSec 1 } $bridge
        $r.Result | Should Be 'Lost'
    }
}

Describe 'Waiting for the send lock (Local\ObsidiNoteCopilot)' {
    function Start-LockHolder([int]$Seconds) {
        # Another process holds the lock; it drops a marker file in TEMP once it has it.
        $marker = Join-Path $env:TEMP ('obsn-lock-' + [guid]::NewGuid().ToString('N'))
        $job = Start-Job -ArgumentList $marker, $Seconds -ScriptBlock {
            param($file, $sec)
            $m = New-Object Threading.Mutex($false, 'Local\ObsidiNoteCopilot')
            $null = $m.WaitOne()
            [IO.File]::WriteAllText($file, 'held')
            Start-Sleep -Seconds $sec
            $m.ReleaseMutex()
        }
        $deadline = (Get-Date).AddSeconds(20)
        while (-not (Test-Path $marker) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Remove-Item $marker -Force -ErrorAction SilentlyContinue
        $job
    }
    It 'says that another ObsidiNote program sends, then clears the line and runs' {
        $job = Start-LockHolder 3
        $lines = New-Object System.Collections.Generic.List[object]
        $r = & (Get-Module CopilotBridge) { param($l) Use-CopilotLock -OnWait { param($t) $l.Add($t) }.GetNewClosure() -Body { 'ran' } } $lines
        $r | Should Be 'ran'
        $lines[0] | Should Be 'waiting: another ObsidiNote program is sending to Copilot'
        $lines[$lines.Count - 1] | Should Be $null
        $job | Wait-Job | Remove-Job
    }
    It 'stops waiting when the task is stopped' {
        $job = Start-LockHolder 6
        { & (Get-Module CopilotBridge) { Use-CopilotLock -CancelCheck { $true } -Body { 'ran' } } } | Should Throw 'Stopped while waiting for another ObsidiNote program'
        $job | Wait-Job | Remove-Job
    }
    It 'takes a free lock at once and says nothing' {
        $lines = New-Object System.Collections.Generic.List[object]
        & (Get-Module CopilotBridge) { param($l) Use-CopilotLock -OnWait { param($t) $l.Add($t) }.GetNewClosure() -Body { 'ran' } } $lines | Should Be 'ran'
        $lines.Count | Should Be 0
    }
}

Describe 'ObsidiNote''s own Edge session' {
    It 'connects on port 9334 with the profile in the data folder, never CCBridge''s 9333' {
        $global:obsnEdge = $null
        Mock -ModuleName CopilotBridge Start-CdpEdge { $global:obsnEdge = @{ port = $Port; profile = $ProfileDir }; throw 'Copilot message box never appeared; not signed in?' }
        { Connect-Copilot -SignInTimeoutSec 1 } | Should Throw 'never appeared'
        $global:obsnEdge.port | Should Be 9334
        $global:obsnEdge.profile | Should Be (Join-Path $env:OBSIDINOTE_DATA_DIR 'edge-profile')
    }
}

Describe 'Nothing from the Copilot page reaches the disk or the log' {
    It 'describes a page without the message box by kind and host only: no title, text or screenshot' {
        $global:obsnCdpMethods = @(); $global:obsnEval = ''
        Mock -ModuleName CopilotBridge Invoke-Cdp { param($Session, $Method) $global:obsnCdpMethods += $Method }
        Mock -ModuleName CopilotBridge Invoke-CdpEval { param($Session, $Expression) $global:obsnEval = $Expression; '{"host":"login.microsoftonline.com","path":"/common/oauth2","challenge":false,"editor":false}' }
        $bridge = [pscustomobject]@{ Session = [pscustomobject]@{ Lost = $false }; Selectors = [pscustomobject]@{ editor = '#e'; chatUrl = 'https://www.microsoft365.com/chat' } }
        $snap = & (Get-Module CopilotBridge) { param($b) Get-CopilotPageSnapshot $b } $bridge
        $text = & (Get-Module CopilotBridge) { param($s) Format-PageSnapshot $s } $snap
        $text | Should Be 'the page shows a sign-in page at login.microsoftonline.com/common/oauth2'
        $global:obsnEval | Should Not Match 'document\.title|innerText'
        @($global:obsnCdpMethods) -contains 'Page.captureScreenshot' | Should Be $false
        @($snap.PSObject.Properties.Name) -contains 'screenshot' | Should Be $false
    }
    It 'has no switch or function that saves reply frames' {
        (Get-Command Connect-Copilot).Parameters.ContainsKey('SaveReplyFrames') | Should Be $false
        @(& (Get-Module CopilotBridge) { Get-Command Save-ReplyFrames -ErrorAction SilentlyContinue }).Count | Should Be 0
    }
}
