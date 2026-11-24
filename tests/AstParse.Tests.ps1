# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# tests/AstParse.ps1 is how the AST rule tests read a script. Before 2026-11-24 they passed
# [ref]$null for the parse errors, so a file that did not parse was checked as if it were empty
# and passed every rule (rule audit). The helper must throw with file, line and message.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'AstParse.ps1')

Describe 'Read-ScriptAst' {
    It 'returns the AST of a script that parses' {
        $ast = Read-ScriptAst -Text "function Get-Fine { 1 }"
        @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count | Should Be 1
    }
    It 'throws with name, line and message on a broken snippet' {
        { Read-ScriptAst -Text "function Get-Broken {`n    if (`n" -Name 'snippet.ps1' } | Should Throw 'snippet.ps1:2:'
    }
    It 'throws with the file path on a broken file' {
        $tmp = Join-Path $env:TEMP ('obsn-ast-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [IO.File]::WriteAllText($tmp, "`$x = @(1, 2`n")
            $msg = ''
            try { $null = Read-ScriptAst -Path $tmp } catch { $msg = "$_" }
            $msg.Contains($tmp + ':') | Should Be $true
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}
