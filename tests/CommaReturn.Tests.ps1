# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# A function that returns its list with a leading comma (", $list" or ", @(...)") hands over ONE
# object, the array; wrapping a call to it in @(...) makes an array holding that array, so [0] is the
# whole list (AGENTS.md gotcha ",@() nesting"). Missed three times on 2026-11-18 (Ask's sources, Ask's
# series pages, the intent signals), each found only by a failing run. This test reads the AST of every
# module and fails on @( <call of such a function> ). Assign the call as is instead.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

function Get-CommaReturnFunctions([string[]]$Files) {
    <# Names of functions whose own body has a statement that is a unary comma (", $x"). #>
    $names = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $Files) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
        foreach ($fn in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            # ", $x" parses as an array literal of one element whose text starts with the comma.
            $commas = $fn.Body.FindAll({ param($a)
                    $a -is [System.Management.Automation.Language.ArrayLiteralAst] -and @($a.Elements).Count -eq 1 -and $a.Extent.Text.TrimStart().StartsWith(',') -and
                    $a.Parent -is [System.Management.Automation.Language.CommandExpressionAst]
                }, $true)
            # Only commas the function itself returns with: not those of a nested function or a
            # scriptblock it builds, and not those inside a loop or an @()/$() that collects a list
            # (", @(cell)" per row builds a list of lists; the function returns that list unrolled).
            $stop = @('ScriptBlockExpressionAst', 'FunctionDefinitionAst', 'ForEachStatementAst', 'ForStatementAst', 'WhileStatementAst', 'DoWhileStatementAst', 'DoUntilStatementAst', 'ArrayExpressionAst', 'SubExpressionAst')
            $own = @($commas | Where-Object {
                    $p = $_.Parent
                    while ($p -and $p -ne $fn) { if ($stop -contains $p.GetType().Name) { break }; $p = $p.Parent }
                    $p -eq $fn
                })
            if ($own.Count) { $null = $names.Add($fn.Name) }
        }
    }
    , @($names)
}

Describe 'No @(...) around a call of a function that returns its list with a comma (2026-11-18)' {
    $files = @(Get-ChildItem (Join-Path $root 'lib'), (Join-Path $root 'validation\lib') -Filter *.psm1 | ForEach-Object { $_.FullName })
    $comma = Get-CommaReturnFunctions $files
    It 'finds the functions that return with a comma (the check works)' {
        ($comma -contains 'Get-AskSources') | Should Be $true
        ($comma -contains 'Get-IntentSignals') | Should Be $true
    }
    It 'finds no call of one of them wrapped in @()' {
        $bad = @()
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
            foreach ($a in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.ArrayExpressionAst] }, $true)) {
                $st = @($a.SubExpression.Statements)
                if ($st.Count -ne 1 -or -not ($st[0] -is [System.Management.Automation.Language.PipelineAst])) { continue }
                $els = @($st[0].PipelineElements)
                if ($els.Count -ne 1 -or -not ($els[0] -is [System.Management.Automation.Language.CommandAst])) { continue }
                $name = $els[0].GetCommandName()
                if ($name -and $comma -contains $name) { $bad += "$([IO.Path]::GetFileName($f)):$($a.Extent.StartLineNumber) @($name)" }
            }
        }
        ($bad -join '; ') | Should Be ''
    }
}
