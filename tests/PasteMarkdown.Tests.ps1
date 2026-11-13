# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The Markdown the window makes from pasted HTML (ui-src/src/add/pasteMarkdown.ts) must be what
# lib/MarkdownLines.psm1 reads: every vector's expected Markdown (tests/fixtures/paste-markdown.json,
# the same file the vitest test checks the converter against) goes through ConvertTo-MarkdownLines here.
# A line reads "<kind>:<text>"; kind = h1..h6, bullet, number, quote, code, table or p; a ">" in front
# per list level; styled parts as [b]..[/], [i], [c], [s], [a] (link).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\MarkdownLines.psm1') -Force

function Format-PartsForTest($Parts) {
    $out = ''
    foreach ($p in @($Parts)) {
        if ($null -eq $p) { continue }
        $t = [string]$p['text']
        if ($p['code']) { $t = "[c]$t[/]" }
        if ($p['strike']) { $t = "[s]$t[/]" }
        if ($p['italic']) { $t = "[i]$t[/]" }
        if ($p['bold']) { $t = "[b]$t[/]" }
        if ($p['href']) { $t = "[a]$t[/]" }
        $out += $t
    }
    $out
}

function Format-LinesForTest($Lines, [int]$Depth = 0) {
    foreach ($l in @($Lines)) {
        if ($null -eq $l) { continue }
        $kind = if ($l['table']) { 'table' } elseif ($l['heading']) { "h$($l['heading'])" } elseif ($l['list']) { $l['list'] } elseif ($l['quote']) { 'quote' } elseif ($l['code']) { 'code' } else { 'p' }
        $text = if ($l['table']) {
            $rows = @(, @($l['table'].header)) + @($l['table'].rows)
            (@(foreach ($r in $rows) { (@(foreach ($c in @($r)) { Format-PartsForTest $c }) -join '/') }) -join ';')
        } else { Format-PartsForTest $l['parts'] }
        ('>' * $Depth) + "${kind}:$text"
        if (@($l['children']).Count) { Format-LinesForTest $l['children'] ($Depth + 1) }
    }
}

$fixture = Join-Path $here 'fixtures\paste-markdown.json'
# Assigned first: PS 5.1 hands a JSON array down a pipeline as one object.
$parsed = ConvertFrom-Json ([IO.File]::ReadAllText($fixture, [Text.Encoding]::UTF8))
$script:Vectors = @(foreach ($x in $parsed) { $x })

Describe 'Pasted HTML as Markdown: what MarkdownLines makes of it' {
    It 'has vectors' {
        $script:Vectors.Count -ge 9 | Should Be $true
    }
    foreach ($v in $script:Vectors) {
        It "reads '$($v.name)' as the expected lines" {
            $got = @(Format-LinesForTest @(ConvertFrom-MarkdownText -Text $v.markdown))
            ($got -join "`n") | Should Be (@($v.lines) -join "`n")
        }
    }
    It 'agrees with the window on which text Test-MarkdownText takes as Markdown (markdownText)' {
        # The window pastes plain text when the server would not convert its Markdown
        # (looksLikeMarkdown in pasteMarkdown.ts, checked against the same field by vitest).
        foreach ($v in $script:Vectors) {
            "$($v.name): $(Test-MarkdownText -Text $v.markdown)" | Should Be "$($v.name): $($v.markdownText)"
        }
    }
}
