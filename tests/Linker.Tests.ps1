# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/Linker.psm1: shortlist, prompt, JSON extractor and validator. Synthetic replies only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\Linker.psm1') -Force
. (Join-Path $here 'FakeVault.ps1')

$script:Types = @('concept', 'note', 'howto', 'link-internal', 'link-web', 'source', 'person', 'project', 'project-part', 'meeting', 'decision', 'log', 'file')
$script:Text = 'An identity-aware proxy checks who the user is and which device they use before it forwards a request. We use it for the partner portal instead of the old VPN.'

function Get-Reply([string]$Json) { ConvertFrom-Json $Json }

Describe 'Get-TextTerms' {
    It 'lower-cases, drops short words and stop words, keeps order once' {
        $t = Get-TextTerms 'The Partner portal and the PARTNER VPN is ok'
        ($t -join ',') | Should Be 'partner,portal,vpn'
    }
    It 'is empty for empty text' {
        (Get-TextTerms '').Count | Should Be 0
    }
}

Describe 'Get-LinkShortlist' {
    $idx = New-FakeIndex
    It 'ranks by title, topic and summary overlap and leaves out pages with nothing in common' {
        $sl = Get-LinkShortlist -Index $idx -Text $script:Text
        $ids = @($sl.pages | ForEach-Object { $_['id'] })
        $ids[0] | Should Be 'p2'
        $ids -contains 'p3' | Should Be $true
        $ids -contains 'p4' | Should Be $true
        $ids -contains 'p6' | Should Be $false
    }
    It 'scores an alias that occurs in the text high' {
        $sl = Get-LinkShortlist -Index $idx -Text 'We moved the login to SSO last week.'
        $sl.pages[0]['id'] | Should Be 'p5'
    }
    It 'keeps to the page and character budget' {
        @((Get-LinkShortlist -Index $idx -Text $script:Text -MaxPages 1).pages).Count | Should Be 1
        $full = Get-LinkShortlist -Index $idx -Text $script:Text
        @($full.pages).Count | Should BeGreaterThan 2
        $sl = Get-LinkShortlist -Index $idx -Text $script:Text -MaxChars ($full.pages[0]['line'].Length + 5)
        @($sl.pages).Count | Should Be 1
    }
    It 'leaves out excluded ids' {
        $sl = Get-LinkShortlist -Index $idx -Text $script:Text -ExcludeIds @('p2')
        @($sl.pages | ForEach-Object { $_['id'] }) -contains 'p2' | Should Be $false
    }
    It 'gives every topic a prompt id that maps back to its path' {
        $sl = Get-LinkShortlist -Index $idx -Text $script:Text
        @($sl.topics).Count | Should Be 6
        $sl.topicIds['t1'] | Should Be 'Cooking'
        @($sl.topicIds.Values) -contains 'Security/Networking' | Should Be $true
    }
    It 'sends only roots, candidate paths and matching paths when all topics do not fit' {
        $sl = Get-LinkShortlist -Index $idx -Text 'A note about the partner portal' -TopicChars 100
        $paths = @($sl.topics | ForEach-Object { $_['path'] })
        $paths -contains 'Projects/Partner portal' | Should Be $true
        $paths -contains 'Security' | Should Be $true
        $paths -contains 'Security/Networking' | Should Be $false
    }
}

Describe 'New-LinkPrompt' {
    $idx = New-FakeIndex
    $sl = Get-LinkShortlist -Index $idx -Text $script:Text
    $p = New-LinkPrompt -Text $script:Text -Shortlist $sl -Types $script:Types -Today ([datetime]'2026-11-13')
    It 'holds the item, the topics with ids, the candidate lines and the date' {
        $p | Should Match 'identity-aware proxy checks'
        $p | Should Match 't1: Cooking'
        $p | Should Match 'p2 \| Partner portal: access review notes'
        $p | Should Match 'Today is 2026-11-13'
    }
    It 'asks for the fixed JSON contract and lists the fixed types' {
        $p | Should Match '"links": \[\{"target": "p12", "anchor"'
        $p | Should Match '"intent": "add"'
        $p | Should Match '  project-part '
        $p | Should Match 'no code fence'
    }
    It 'names the type when it is fixed' {
        $q = New-LinkPrompt -Text 'x' -Shortlist $sl -Types $script:Types -FixedType 'link-web'
        $q | Should Match 'type: always "link-web"'
        $q | Should Not Match '  project-part '
    }
    It 'contains no Markdown link syntax' {
        $p | Should Not Match '\]\('
        $p | Should Not Match '\[[^\]]*\]:'
    }
}

Describe 'Get-ReplyJson' {
    It 'reads a bare object' {
        $r = Get-ReplyJson '{"title":"A","links":[]}'
        $r.ok | Should Be $true
        $r.value.title | Should Be 'A'
    }
    It 'reads an object inside a code fence with text around it' {
        $reply = "Here is the result:`n``````json`n{ ""title"": ""B"", ""type"": ""note"" }`n```````nHope this helps."
        $r = Get-ReplyJson $reply
        $r.ok | Should Be $true
        $r.value.type | Should Be 'note'
    }
    It 'keeps braces inside strings and forgives a trailing comma' {
        $r = Get-ReplyJson 'x {"title":"a {b} c","aliases":["q",],} y'
        $r.ok | Should Be $true
        $r.value.title | Should Be 'a {b} c'
    }
    It 'skips a broken object and takes the next good one' {
        $r = Get-ReplyJson '{"title": oops} then {"title":"ok"}'
        $r.ok | Should Be $true
        $r.value.title | Should Be 'ok'
    }
    It 'reports broken JSON, no JSON and an empty reply without throwing' {
        (Get-ReplyJson '{"title": "cut off').ok | Should Be $false
        (Get-ReplyJson '{"title": "x", "links": [}').error | Should Match 'could not be read'
        (Get-ReplyJson 'Sorry, I cannot help with that.').error | Should Match 'no JSON'
        (Get-ReplyJson '').error | Should Match 'empty'
        (Get-ReplyJson $null).ok | Should Be $false
    }
    It 'turns curly quotes into straight quotes' {
        $q1 = [string][char]0x201C; $q2 = [string][char]0x201D
        (Get-ReplyJson ('{' + $q1 + 'title' + $q2 + ': ' + $q1 + 'C' + $q2 + '}')).value.title | Should Be 'C'
    }
}

Describe 'Test-LinkReply' {
    $idx = New-FakeIndex
    $sl = Get-LinkShortlist -Index $idx -Text $script:Text
    $tNet = @($sl.topics | Where-Object { $_['path'] -eq 'Security/Networking' })[0]['id']
    $good = '{"title":"Identity-aware proxies","summary":"A proxy that checks user and device.","type":"concept","topics":[{"id":"' + $tNet + '"},{"new":"Security / Networking / Zero trust"}],"links":[{"target":"p1","anchor":"checks who the user is","strength":3,"why":"core concept"},{"target":"p2","anchor":"partner portal","strength":2,"why":"where it is used"},{"target":"p3","anchor":"the old VPN","strength":1,"why":"replaces it"}],"aliases":["IAP"],"intent":"add"}'

    It 'accepts a good reply and keeps everything' {
        $v = Test-LinkReply -Reply (Get-Reply $good) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.ok | Should Be $true
        @($v.dropped).Count | Should Be 0
        $v.value.type | Should Be 'concept'
        @($v.value.topics)[0]['path'] | Should Be 'Security/Networking'
        @($v.value.topics)[1]['path'] | Should Be 'Security/Networking/Zero trust'
        @($v.value.topics)[1]['isNew'] | Should Be $true
        @($v.value.links).Count | Should Be 3
        @($v.value.links)[0]['strength'] | Should Be 3
        @($v.value.links)[0]['title'] | Should Be 'Zero-trust networking'
        @($v.value.links)[0]['link'] | Should Be 'onenote:#p1'
        $v.value.aliases[0] | Should Be 'IAP'
    }
    It 'drops invented targets and links to itself' {
        $j = '{"title":"T","type":"note","links":[{"target":"p999","anchor":"partner portal","strength":2,"why":"x"},{"target":"p4","anchor":"device","strength":2,"why":"y"},{"target":"p50","strength":1}]}'
        $v = Test-LinkReply -Reply (Get-Reply $j) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types -SelfId 'p4'
        $v.ok | Should Be $true
        @($v.value.links).Count | Should Be 0
        @($v.dropped | Where-Object { $_['reason'] -eq 'no such page in the index' }).Count | Should Be 2
        @($v.dropped | Where-Object { $_['reason'] -match 'itself' }).Count | Should Be 1
    }
    It 'keeps a link whose anchor is not in the text, without the anchor' {
        $j = '{"title":"T","type":"note","links":[{"target":"p1","anchor":"zero trust architecture","strength":2,"why":"x"}]}'
        $v = Test-LinkReply -Reply (Get-Reply $j) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        @($v.value.links).Count | Should Be 1
        @($v.value.links)[0]['anchor'] | Should Be ''
        @($v.dropped)[0]['what'] | Should Be 'anchor'
    }
    It 'matches anchors ignoring case and runs of white space, as whole words' {
        $j = '{"title":"T","type":"note","links":[{"target":"p2","anchor":"Partner   Portal","strength":2},{"target":"p3","anchor":"VP","strength":1}]}'
        $v = Test-LinkReply -Reply (Get-Reply $j) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        @($v.value.links | Where-Object { $_['target'] -eq 'p2' })[0]['anchor'] | Should Be 'Partner Portal'
        @($v.value.links | Where-Object { $_['target'] -eq 'p3' })[0]['anchor'] | Should Be ''
    }
    It 'rejects a type outside the fixed list, and a missing title' {
        $v = Test-LinkReply -Reply (Get-Reply '{"title":"T","type":"topic"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.ok | Should Be $false
        $v.errors[0] | Should Match "type 'topic' is not one of the fixed types"
        $v = Test-LinkReply -Reply (Get-Reply '{"type":"note"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.ok | Should Be $false
        $v.errors[0] | Should Match 'no title'
    }
    It 'rejects a reply that is not an object' {
        (Test-LinkReply -Reply $null -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types).ok | Should Be $false
    }
    It 'rejects a duplicate page (same title and type) and names it' {
        $v = Test-LinkReply -Reply (Get-Reply '{"title":"zero-trust  Networking","type":"concept"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.ok | Should Be $false
        $v.duplicateOf | Should Be 'p1'
        $v = Test-LinkReply -Reply (Get-Reply '{"title":"Zero-trust networking","type":"note"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.ok | Should Be $true
    }
    It 'checks topics: unknown ids and new paths without a parent are dropped, new roots allowed' {
        $j = '{"title":"T","type":"note","topics":[{"id":"t99"},{"new":"Finance/Budgets/2027"},{"new":"Gardening"},{"new":"security/identity"}]}'
        $v = Test-LinkReply -Reply (Get-Reply $j) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $paths = @($v.value.topics | ForEach-Object { $_['path'] })
        ($paths -join ';') | Should Be 'Gardening;Security/Identity'
        @($v.value.topics)[1]['isNew'] | Should Be $false
        @($v.dropped | Where-Object { $_['what'] -eq 'topic' }).Count | Should Be 2
    }
    It 'clamps strength to 1-3 and merges two links to one target' {
        $j = '{"title":"T","type":"note","links":[{"target":"p1","strength":7},{"target":"p2","strength":"2"},{"target":"p2","strength":3,"anchor":"partner portal"}]}'
        $v = Test-LinkReply -Reply (Get-Reply $j) -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        @($v.value.links).Count | Should Be 2
        @($v.value.links | Where-Object { $_['target'] -eq 'p1' })[0]['strength'] | Should Be 3
        $p2 = @($v.value.links | Where-Object { $_['target'] -eq 'p2' })[0]
        $p2['strength'] | Should Be 3
        $p2['anchor'] | Should Be 'partner portal'
    }
    It 'forces a fixed type and skips the title check for link pages' {
        $v = Test-LinkReply -Reply (Get-Reply '{"title":"Zero-trust networking","type":"concept"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types -FixedType 'link-web' -SkipDuplicateTitle
        $v.ok | Should Be $true
        $v.value.type | Should Be 'link-web'
    }
    It 'reads intent, defaults to add, and limits aliases to 5' {
        $v = Test-LinkReply -Reply (Get-Reply '{"title":"T","type":"note","intent":"ASK","aliases":["a","b","c","d","e","f","T"]}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types
        $v.value.intent | Should Be 'ask'
        @($v.value.aliases).Count | Should Be 5
        (Test-LinkReply -Reply (Get-Reply '{"title":"T","type":"note","intent":"maybe"}') -Index $idx -Shortlist $sl -Text $script:Text -Types $script:Types).value.intent | Should Be 'add'
    }
}

Describe 'Request reference: every JSON object of a chat, and the ref check' {
    It 'finds every JSON object in text read from several replies, in order' {
        $o = Get-ReplyJsonObjects ("Sure.`n" + '```json' + "`n" + '{"a": 1, "inner": {"b": 2}}' + "`n" + '```' + "`nand " + '{"ref": "r1",}' + ' {broken')
        @($o).Count | Should Be 2
        @($o)[0].a | Should Be 1
        @($o)[1].ref | Should Be 'r1'
        (Get-ReplyJsonObjects '').Count | Should Be 0
    }
    It 'accepts the same ref, refuses another one, and a missing one only when it is required' {
        (Test-ReplyRef -Reply ([pscustomobject]@{ ref = 'rabc' }) -Ref 'rabc').ok | Should Be $true
        (Test-ReplyRef -Reply ([pscustomobject]@{ ref = 'rxyz' }) -Ref 'rabc').ok | Should Be $false
        (Test-ReplyRef -Reply ([pscustomobject]@{ title = 'T' }) -Ref 'rabc').ok | Should Be $true
        (Test-ReplyRef -Reply ([pscustomobject]@{ title = 'T' }) -Ref 'rabc' -Required).ok | Should Be $false
        (Test-ReplyRef -Reply ([pscustomobject]@{ ref = '<b>x y</b>' }) -Ref 'rabc').error | Should Match 'reference another one'
    }
}