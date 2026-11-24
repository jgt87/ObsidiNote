# The one way the AST rule tests read a script: parse it and throw on any parse error. A test that
# passed [ref]$null for the errors checked a file that did not parse as if it were empty, so a broken
# module passed every rule (rule audit, 2026-11-24).
# Dot-source it in a test: . (Join-Path $here 'AstParse.ps1')

function Read-ScriptAst {
    <# The AST of a script file (-Path) or of script text (-Text, named -Name in errors). Throws
       "<file>:<line>:<column>: <message>" for each parse error. #>
    param([string]$Path = '', [string]$Text = '', [string]$Name = '<text>')
    $tokens = $null; $errors = $null
    if ($Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $Name = $Path
    } else {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    }
    if ($errors -and @($errors).Count) {
        $lines = @($errors | ForEach-Object { '{0}:{1}:{2}: {3}' -f $Name, $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message })
        throw ("Parse errors:`n" + ($lines -join "`n"))
    }
    return $ast
}
