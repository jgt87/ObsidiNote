# Pester 3.4. Markdown -> outline line model (lib/MarkdownLines.psm1), pure. Synthetic text only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'lib\MarkdownLines.psm1') -Force

function Get-Plain($Line) { (@($Line['parts']) | ForEach-Object { $_['text'] }) -join '' }

Describe 'Test-MarkdownText' {
    It 'finds Markdown structure' {
        Test-MarkdownText "# Title`nText" | Should Be $true
        Test-MarkdownText "- one`n- two" | Should Be $true
        Test-MarkdownText 'See [the plan](https://example.invalid/plan) now' | Should Be $true
        Test-MarkdownText 'This is **important**' | Should Be $true
        Test-MarkdownText "| a | b |`n|---|---|`n| 1 | 2 |" | Should Be $true
    }
    It 'leaves plain text alone' {
        Test-MarkdownText 'A plain note about the partner portal, nothing special.' | Should Be $false
        Test-MarkdownText '' | Should Be $false
        Test-MarkdownText '2 * 3 = 6 and a_b_c' | Should Be $false
    }
}

Describe 'ConvertFrom-MarkdownText: blocks' {
    It 'turns headings into bold lines with their level' {
        $l = @(ConvertFrom-MarkdownText "## Zero trust ##`nBody")
        $l[0]['heading'] | Should Be 2
        $l[0]['bold'] | Should Be $true
        Get-Plain $l[0] | Should Be 'Zero trust'
        Get-Plain $l[1] | Should Be 'Body'
    }
    It 'nests lists by indent, bullet or numbered' {
        $l = @(ConvertFrom-MarkdownText "- one`n  - one a`n  - one b`n- two`n1. first`n2. second")
        $l.Count | Should Be 4
        $l[0]['list'] | Should Be 'bullet'
        @($l[0]['children']).Count | Should Be 2
        Get-Plain (@($l[0]['children'])[1]) | Should Be 'one b'
        $l[2]['list'] | Should Be 'number'
        Get-Plain $l[3] | Should Be 'second'
    }
    It 'continues a list item on an indented line, and puts a box in front of a task' {
        $l = @(ConvertFrom-MarkdownText "- [ ] call Sam`n- [x] done`n- item`n  more text")
        Get-Plain $l[0] | Should Be ([string][char]0x2610 + ' call Sam')
        Get-Plain $l[1] | Should Be ([string][char]0x2611 + ' done')
        Get-Plain $l[2] | Should Be 'item more text'
    }
    It 'keeps fenced code as written, every line monospace' {
        $l = @(ConvertFrom-MarkdownText ("Before`n``````ps`n  Get-Item **x**`n``````" + "`nAfter"))
        $l.Count | Should Be 3
        $l[1]['code'] | Should Be $true
        Get-Plain $l[1] | Should Be '  Get-Item **x**'
        @($l[1]['parts'])[0]['code'] | Should Be $true
    }
    It 'reads a table with its header and rows' {
        $l = @(ConvertFrom-MarkdownText "| Name | Role |`n|:---|---:|`n| Sam | **lead** |`n| Alex | owner |`nAfter")
        $t = $l[0]['table']
        @($t.header).Count | Should Be 2
        (@(@($t.header)[1]) | ForEach-Object { $_['text'] }) -join '' | Should Be 'Role'
        @($t.rows).Count | Should Be 2
        $cell = @(@(@($t.rows)[0])[1])[0]
        $cell['text'] | Should Be 'lead'
        $cell['bold'] | Should Be $true
        Get-Plain $l[1] | Should Be 'After'
    }
    It 'marks quotes, drops rules, keeps empty lines and drops trailing ones' {
        $l = @(ConvertFrom-MarkdownText "> quoted`n---`n`nlast`n`n")
        $l[0]['quote'] | Should Be $true
        Get-Plain $l[0] | Should Be 'quoted'
        $l.Count | Should Be 3
        Get-Plain $l[1] | Should Be ''
        Get-Plain $l[2] | Should Be 'last'
    }
}

Describe 'ConvertFrom-MdInline' {
    It 'splits emphasis, code and links into parts' {
        $p = @(ConvertFrom-MdInline 'Use **bold** and *it* with `code` and [the plan](https://example.invalid/p) ~~old~~')
        ($p | Where-Object { $_['bold'] } | ForEach-Object { $_['text'] }) -join '' | Should Be 'bold'
        ($p | Where-Object { $_['italic'] } | ForEach-Object { $_['text'] }) -join '' | Should Be 'it'
        ($p | Where-Object { $_['code'] } | ForEach-Object { $_['text'] }) -join '' | Should Be 'code'
        ($p | Where-Object { $_['strike'] } | ForEach-Object { $_['text'] }) -join '' | Should Be 'old'
        $link = @($p | Where-Object { $_['href'] })[0]
        $link['text'] | Should Be 'the plan'
        $link['href'] | Should Be 'https://example.invalid/p'
    }
    It 'keeps links with other schemes as literal text' {
        $p = @(ConvertFrom-MdInline 'Do not [click](javascript:alert(1)) or [this](file:///c/x)')
        @($p | Where-Object { $_['href'] }).Count | Should Be 0
        ($p | ForEach-Object { $_['text'] }) -join '' | Should Match '\[click\]'
    }
    It 'honours backslash escapes and leaves lone stars and underscores alone' {
        $p = @(ConvertFrom-MdInline 'Not \*bold\* and 2 * 3 and snake_case_name')
        @($p | Where-Object { $_['bold'] -or $_['italic'] }).Count | Should Be 0
        ($p | ForEach-Object { $_['text'] }) -join '' | Should Be 'Not *bold* and 2 * 3 and snake_case_name'
    }
    It 'makes autolinks real links' {
        $p = @(ConvertFrom-MdInline 'See <https://example.invalid/x>.')
        @($p | Where-Object { $_['href'] })[0]['href'] | Should Be 'https://example.invalid/x'
    }
}

Describe 'ConvertTo-MdPartHtml' {
    It 'writes span styles and encodes text and href' {
        ConvertTo-MdPartHtml @{ text = 'a<b'; href = ''; bold = $true; italic = $true; code = $false; strike = $false } |
            Should Be "<span style='font-weight:bold;font-style:italic'>a&lt;b</span>"
        ConvertTo-MdPartHtml @{ text = 'x'; href = 'https://example.invalid/?a=1&b="2"'; bold = $false; italic = $false; code = $true; strike = $false } |
            Should Be "<a href=""https://example.invalid/?a=1&amp;b=&quot;2&quot;""><span style='font-family:Consolas'>x</span></a>"
        ConvertTo-MdPartHtml @{ text = 'plain'; href = ''; bold = $false; italic = $false; code = $false; strike = $false } | Should Be 'plain'
    }
}
