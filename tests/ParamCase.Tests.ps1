# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# PowerShell variable names ignore case, so a local named like one of its function's parameters in
# another case ($all for -All) is the parameter: assigning it silently overwrites the input. The rule
# audit of 2026-11-24 found $all/$All in Get-AskSources and $text/$Text in Get-MeetingDataFromText,
# where the loop overwrote the input. This test reads the AST of every function in lib/, validation/lib/,
# tools/, obsidinote.ps1 and install.ps1 and fails on an assignment (or a foreach variable) whose name
# is a parameter's name in a different case. The same name in the same case is a deliberate update of
# the parameter and is allowed.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $here 'AstParse.ps1')

function Get-AssignedNames($Left) {
    <# The plain variable names an assignment's left side sets ($a, [int]$a, $a, $b = ...). #>
    if ($Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $vp = $Left.VariablePath
        if ($vp.IsUnqualified -or $vp.IsLocal) { return $vp.UserPath -replace '^local:', '' }
        return
    }
    if ($Left -is [System.Management.Automation.Language.AttributedExpressionAst]) { return Get-AssignedNames $Left.Child }
    if ($Left -is [System.Management.Automation.Language.ArrayLiteralAst]) { foreach ($e in $Left.Elements) { Get-AssignedNames $e } }
}

function Find-ParamCaseClashes {
    <# "<name>:<line> <function> $<local> overwrites -<Param>" for each clash in a parsed script. #>
    param([Parameter(Mandatory)]$Ast, [string]$Name = '<text>')
    $isFn = { param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }
    foreach ($fn in $Ast.FindAll($isFn, $true)) {
        $params = @(@($fn.Parameters) + @(if ($fn.Body.ParamBlock) { $fn.Body.ParamBlock.Parameters }) | Where-Object { $_ } | ForEach-Object { $_.Name.VariablePath.UserPath })
        if (-not $params.Count) { continue }
        $sets = $fn.Body.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -or $a -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)
        foreach ($s in $sets) {
            # Only this function's own code: a nested function is checked against its own parameters.
            $p = $s.Parent
            while ($p -and -not (& $isFn $p)) { $p = $p.Parent }
            if (-not [object]::ReferenceEquals($p, $fn)) { continue }
            $names = if ($s -is [System.Management.Automation.Language.ForEachStatementAst]) { Get-AssignedNames $s.Variable } else { Get-AssignedNames $s.Left }
            foreach ($n in @($names)) {
                foreach ($q in $params) {
                    if ($n -ieq $q -and $n -cne $q) { '{0}:{1} {2} ${3} overwrites -{4}' -f $Name, $s.Extent.StartLineNumber, $fn.Name, $n, $q }
                }
            }
        }
    }
}

Describe 'No local overwrites a parameter by a name in another case (2026-11-24)' {
    $files = @(@('lib', 'validation\lib', 'tools') | ForEach-Object {
            $d = Join-Path $root $_
            if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -File | Where-Object { $_.Extension -in '.ps1', '.psm1' } | ForEach-Object { $_.FullName } }
        }) + @('obsidinote.ps1', 'install.ps1' | ForEach-Object { Join-Path $root $_ })
    It 'checks the files (an empty run is not a pass)' {
        ($files.Count -gt 10) | Should Be $true
        (@($files | Where-Object { -not (Test-Path -LiteralPath $_) }) -join ', ') | Should Be ''
    }
    It 'finds no local named like a parameter of its function in another case' {
        $bad = @(foreach ($f in $files) { Find-ParamCaseClashes -Ast (Read-ScriptAst -Path $f) -Name $f.Substring($root.Length + 1) })
        ($bad -join '; ') | Should Be ''
    }
    It 'finds the clash in a snippet (the check works)' {
        $text = @'
function Get-Thing {
    param([object[]]$All, [string]$Text)
    $all = @($All | Where-Object { $_ })
    foreach ($text in $all) { }
    [int]$Text = 1
    $Other, $tEXT = 1, 2
    function Inner($x) { $all = 1 }
}
'@
        $bad = @(Find-ParamCaseClashes -Ast (Read-ScriptAst -Text $text))
        ($bad -join '; ') | Should Be '<text>:3 Get-Thing $all overwrites -All; <text>:4 Get-Thing $text overwrites -Text; <text>:6 Get-Thing $tEXT overwrites -Text'
    }
}
