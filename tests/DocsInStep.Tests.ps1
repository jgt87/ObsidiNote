# Pester 3.4 syntax. Docs in step with the scripts a person runs: every parameter of an entry
# script and every launcher (.cmd) is named in the README or the agent doc.
# Seen 15 Nov 2026 in a PowerShell tool: a validation kit gained a switch, a probe and a launcher,
# and three docs still described the old stage. The rule "update the README and the agent doc in
# the same turn" existed; nothing checked it.
# Add a folder to $scriptDirs when the project gains scripts people run by hand there (a PowerShell
# bridge checks tools/, mcp/ and test-tools/ too, and keeps their options in docs/architecture.md:
# 36 parameters and a launcher no doc named on the first run, 16 Nov 2026).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# The app and its launchers (root) and the tools people run by hand (update, sso-setup, release,
# tests). The validation kit has its own, stricter check: tests/Validation.Tests.ps1 "The kit on disk".
$scriptDirs = @($root, (Join-Path $root 'tools'))
$entryScripts = @(foreach ($d in $scriptDirs) { if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } } })
$launchers = @(foreach ($d in $scriptDirs) { if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -Filter '*.cmd' -File } })
$docs = ''
# docs/architecture.md: where a project with many scripts keeps their options, so AGENTS.md stays short.
foreach ($name in 'README.md', 'AGENTS.md', 'CLAUDE.md', 'docs\architecture.md') {
    $p = Join-Path $root $name
    if (Test-Path $p) { $docs += "`n" + [IO.File]::ReadAllText($p) }
}

function Get-ScriptParameterNames {
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (-not $ast.ParamBlock) { return @() }
    return @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
}

Describe 'Docs in step with the scripts people run' {
    It 'finds something to check (an empty run is not a pass)' {
        ($entryScripts.Count + $launchers.Count) -gt 0 | Should Be $true
        $docs.Length -gt 0 | Should Be $true
    }
    foreach ($script in $entryScripts) {
        foreach ($name in (Get-ScriptParameterNames -Path $script.FullName)) {
            It "names -$name of $($script.Name) in the README or the agent doc" {
                ($docs -match ('(?i)-' + [regex]::Escape($name) + '\b')) | Should Be $true
            }
        }
    }
    foreach ($cmd in $launchers) {
        It "names the launcher '$($cmd.Name)' in the README or the agent doc" {
            $docs.Contains($cmd.Name) | Should Be $true
        }
    }
    It 'reads parameter names from a script (the check itself works)' {
        $tmp = Join-Path $env:TEMP ('docs-in-step-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [IO.File]::WriteAllText($tmp, 'param([string]$Name, [switch]$DryRun)')
            (Get-ScriptParameterNames -Path $tmp) -join ',' | Should Be 'Name,DryRun'
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}
