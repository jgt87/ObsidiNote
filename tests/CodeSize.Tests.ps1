# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Code-size ratchet for the PowerShell code (rule audit, 2026-11-24): a function stays at most 80
# lines and at most complexity 10. Long, branchy functions were where the gotchas of AGENTS.md hid,
# and nothing stopped one from growing. Older code breaks the rule, so tests/fixtures/ps-code-size.json
# holds per file how many functions may be over each limit; a file may not gain one, and a file not
# in it may have none. What is counted is in the header of tools/code-size.ps1, which also lowers the
# baseline after a split (-Update; it never raises a number: that is the operator's decision).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root 'tools\code-size.ps1')
$baselinePath = Join-Path $here 'fixtures\ps-code-size.json'

Describe 'PowerShell functions do not grow past 80 lines or complexity 10 (ratchet)' {
    $measured = $null; $problem = ''
    try { $measured = Get-CodeSizeCounts -Root $root } catch { $problem = "$_" }
    $baseline = [IO.File]::ReadAllText($baselinePath) | ConvertFrom-Json

    It 'measures every file and each one parses (an empty run is not a pass)' {
        $problem | Should Be ''
        ($measured.Files -gt 0) | Should Be $true
    }
    It 'finds no file with more over-limit functions than the baseline allows' {
        (@(Get-RatchetFailures -Counts $measured.Counts -Baseline $baseline) -join '; ') | Should Be ''
    }
    It 'has a baseline of measured files and the two rule names only' {
        $files = @(Get-CodeSizeFiles -Root $root)
        $bad = @()
        foreach ($p in $baseline.PSObject.Properties) {
            if ($files -notcontains $p.Name) { $bad += "$($p.Name) is not a measured file" }
            foreach ($r in $p.Value.PSObject.Properties) { if ($r.Name -notin 'max-lines-per-function', 'complexity') { $bad += "$($p.Name): $($r.Name)" } }
        }
        ($bad -join '; ') | Should Be ''
    }
}

Describe 'The code-size check works' {
    It 'counts code lines only: blank lines, comment lines and a comment block are left out' {
        $body = @(1..79 | ForEach-Object { "    `$x$_ = $_" }) -join "`n"
        $text = "function Short {`n    # a comment`n`n    <#`n    block`n    #>`n$body`n}"
        $u = @(Measure-CodeSize -Text $text)
        "$($u[0].Name) $($u[0].Lines)" | Should Be 'Short 81'
        @(Measure-CodeSize -Text $text.Replace('$x1 = 1', "`$x1 = 1`n    `$x0 = 0"))[0].Lines | Should Be 82
    }
    It 'counts a line of a here-string as code' {
        $text = "function H {`n    `$s = @'`n# not a comment`n`n'@`n}"
        @(Measure-CodeSize -Text $text)[0].Lines | Should Be 6
    }
    It 'adds if/elseif, loops, switch clauses, catch, trap and -and/-or; a nested scriptblock is its own unit' {
        $text = @'
function Branchy($a, $b) {
    if ($a -and $b) { 1 } elseif ($a -or $b) { 2 } else { 3 }
    foreach ($x in 1..2) { }
    for ($i = 0; $i -lt 1; $i++) { }
    while ($false) { }
    do { } while ($false)
    do { } until ($true)
    switch ($a) { 1 { } 2 { } default { } }
    try { } catch { }
    trap { continue }
    @(1, 2) | Where-Object { $_ -and $a -and $b }
}
'@
        $u = @(Measure-CodeSize -Text $text)
        $f = @($u | Where-Object { $_.Name -eq 'Branchy' })[0]
        $sb = @($u | Where-Object { $_.Name -eq '{ }' -and $_.Line -eq 11 })[0]
        # 1 + if/elseif 2 + -and/-or 2 + five loops + two switch clauses + catch + trap
        $f.Complexity | Should Be 14
        $sb.Complexity | Should Be 3
    }
    It 'throws with file, line and message for a file that does not parse' {
        { Read-CodeSizeAst -Text "function Broken {`n    if (" } | Should Throw '<text>:2:'
    }
    It 'fails a file over its baseline and a new file with any; lowering never raises a number' {
        $counts = [ordered]@{ 'lib/A.psm1' = [ordered]@{ complexity = 3 }; 'lib/New.psm1' = [ordered]@{ 'max-lines-per-function' = 1 } }
        $old = '{ "lib/A.psm1": { "complexity": 2, "max-lines-per-function": 1 } }' | ConvertFrom-Json
        (@(Get-RatchetFailures -Counts $counts -Baseline $old) -join '; ') | Should Be 'lib/A.psm1: complexity 3 (allowed 2); lib/New.psm1: max-lines-per-function 1 (allowed 0)'
        $next = Get-LoweredBaseline -Counts $counts -Baseline $old
        "$($next['lib/A.psm1']['complexity']) $($next.Contains('lib/New.psm1'))" | Should Be '2 False'
        $down = Get-LoweredBaseline -Counts ([ordered]@{ 'lib/A.psm1' = [ordered]@{ complexity = 1 } }) -Baseline $old
        (ConvertTo-BaselineJson $down) | Should Be "{`n  `"lib/A.psm1`": {`n    `"complexity`": 1`n  }`n}`n"
        $first = Get-LoweredBaseline -Counts $counts -Baseline $null
        @($first.Keys).Count | Should Be 2
    }
}
