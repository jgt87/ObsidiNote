# Code-size ratchet for the PowerShell code: a function stays at most 80 lines and at most
# cyclomatic complexity 10. Older code breaks the rule, so a file may not gain over-limit functions
# beyond the committed baseline (tests/fixtures/ps-code-size.json) and a file not in it may have
# none. The interface's JavaScript has its own ESLint-based ratchet; this one mirrors its rules
# (max-lines-per-function with blank and comment lines skipped, complexity) as far as they map.
# Rule audit, 2026-11-24. Checked by tests/CodeSize.Tests.ps1.
#
#   powershell -NoProfile -File tools/code-size.ps1            check (exit 1 names the file and rule)
#   powershell -NoProfile -File tools/code-size.ps1 -Update    write or lower the baseline after a
#                                                              split; it never rises (that is the operator's call)
#
# What is measured, per function (`function X {}`) and per scriptblock literal (`{ ... }`, like an
# arrow function in ESLint), each its own unit:
# - lines: the lines of the unit's extent that hold code. A blank line and a line holding only a
#   comment (also each line inside a <# #> block) are not counted; a line of a here-string is.
#   Nested units are counted in the outer unit's lines too, as ESLint does.
# - complexity: 1, plus each if and elseif, each loop (for, foreach, while, do), each switch clause
#   (not default), each catch and trap, and each -and / -or. What a nested unit holds counts for
#   that unit only.
# Scope: lib/, validation/lib/, tools/ (*.ps1, *.psm1), obsidinote.ps1 and install.ps1; not tests/
# or probes/. Dot-source this file to get the functions without running the check.
param([switch]$Update)

$script:CodeSizeMaxLines = 80
$script:CodeSizeMaxComplexity = 10
$script:CodeSizeRules = @('max-lines-per-function', 'complexity')

function Get-CodeSizeFiles {
    <# Repo-relative paths (forward slashes) of the files the ratchet measures. #>
    param([Parameter(Mandatory)][string]$Root)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($d in 'lib', 'validation\lib', 'tools') {
        $dir = Join-Path $Root $d
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
            $out.Add(($d -replace '\\', '/') + '/' + $f.Name)
        }
    }
    foreach ($f in 'obsidinote.ps1', 'install.ps1') { if (Test-Path -LiteralPath (Join-Path $Root $f)) { $out.Add($f) } }
    @($out | Sort-Object)
}

function Read-CodeSizeAst {
    <# @{ Ast; Tokens } of a file (-Path) or text (-Text); throws "<name>:<line>:<column>: <message>"
       when it does not parse (a file that fails to parse must never count as having no functions). #>
    param([string]$Path = '', [string]$Text = '', [string]$Name = '<text>')
    $tokens = $null; $errors = $null
    if ($Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $Name = $Path
    } else {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    }
    if ($errors -and @($errors).Count) {
        throw ('Parse errors: ' + ((@($errors) | ForEach-Object { '{0}:{1}:{2}: {3}' -f $Name, $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message }) -join '; '))
    }
    @{ Ast = $ast; Tokens = @($tokens) }
}

function Test-CodeSizeUnit($Node) {
    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or $Node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
}

function Get-CodeSizeOwner($Node) {
    <# The nearest function or scriptblock literal that holds $Node. #>
    $p = $Node.Parent
    while ($p -and -not (Test-CodeSizeUnit $p)) { $p = $p.Parent }
    $p
}

function Get-DecisionPoints($Node) {
    <# How much $Node adds to its unit's complexity (see the header). #>
    if ($Node -is [System.Management.Automation.Language.IfStatementAst]) { return @($Node.Clauses).Count }
    if ($Node -is [System.Management.Automation.Language.SwitchStatementAst]) { return @($Node.Clauses).Count }
    if ($Node -is [System.Management.Automation.Language.LoopStatementAst]) { return 1 }
    if ($Node -is [System.Management.Automation.Language.CatchClauseAst] -or $Node -is [System.Management.Automation.Language.TrapStatementAst]) { return 1 }
    if ($Node -is [System.Management.Automation.Language.BinaryExpressionAst] -and ($Node.Operator -eq 'And' -or $Node.Operator -eq 'Or')) { return 1 }
    0
}

function Get-CodeLineSet($Tokens) {
    <# The line numbers that hold something other than a comment (a token that spans lines, such as
       a here-string, marks each of its lines). #>
    $set = New-Object System.Collections.Generic.HashSet[int]
    $skip = @('Comment', 'NewLine', 'LineContinuation', 'EndOfInput')
    foreach ($t in $Tokens) {
        if ($skip -contains [string]$t.Kind) { continue }
        for ($l = $t.Extent.StartLineNumber; $l -le $t.Extent.EndLineNumber; $l++) { $null = $set.Add($l) }
    }
    , $set
}

function Measure-CodeSize {
    <# One record per unit: @{ Name; Line; Lines; Complexity }. -Path or -Text. #>
    param([string]$Path = '', [string]$Text = '')
    $parsed = if ($Path) { Read-CodeSizeAst -Path $Path } else { Read-CodeSizeAst -Text $Text }
    $code = Get-CodeLineSet $parsed.Tokens
    # One pass: each decision point counts for the unit that holds it (Ast objects compare by reference).
    $complexity = New-Object 'System.Collections.Generic.Dictionary[object,int]'
    $units = New-Object System.Collections.Generic.List[object]
    foreach ($a in $parsed.Ast.FindAll({ $true }, $true)) {
        if (Test-CodeSizeUnit $a) { $units.Add($a); if (-not $complexity.ContainsKey($a)) { $complexity[$a] = 1 } }
        $add = Get-DecisionPoints $a
        if (-not $add) { continue }
        $owner = Get-CodeSizeOwner $a
        if ($null -eq $owner) { continue }
        $complexity[$owner] = $(if ($complexity.ContainsKey($owner)) { $complexity[$owner] } else { 1 }) + $add
    }
    foreach ($u in $units) {
        $lines = 0
        for ($l = $u.Extent.StartLineNumber; $l -le $u.Extent.EndLineNumber; $l++) { if ($code.Contains($l)) { $lines++ } }
        $name = if ($u -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $u.Name } else { '{ }' }
        [pscustomobject]@{ Name = $name; Line = $u.Extent.StartLineNumber; Lines = $lines; Complexity = $complexity[$u] }
    }
}

function Get-CodeSizeCounts {
    <# @{ Files = <number measured>; Counts = @{ '<file>' = @{ rule = n } } (only files and rules
       with a function over the limit); Over = lines naming each unit over a limit }. Throws when a
       file does not parse. #>
    param([Parameter(Mandatory)][string]$Root)
    $files = @(Get-CodeSizeFiles -Root $Root)
    $counts = [ordered]@{}
    $over = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $c = [ordered]@{}
        foreach ($u in @(Measure-CodeSize -Path (Join-Path $Root $f))) {
            if ($u.Lines -gt $script:CodeSizeMaxLines) { $c['max-lines-per-function'] = 1 + $(if ($c.Contains('max-lines-per-function')) { $c['max-lines-per-function'] } else { 0 }); $over.Add("${f}:$($u.Line) $($u.Name) $($u.Lines) lines") }
            if ($u.Complexity -gt $script:CodeSizeMaxComplexity) { $c['complexity'] = 1 + $(if ($c.Contains('complexity')) { $c['complexity'] } else { 0 }); $over.Add("${f}:$($u.Line) $($u.Name) complexity $($u.Complexity)") }
        }
        if ($c.Count) { $counts[$f] = $c }
    }
    @{ Files = $files.Count; Counts = $counts; Over = $over.ToArray() }
}

function Get-CodeSizeField($Object, [string]$Key) {
    <# A key of a hashtable or a property of a ConvertFrom-Json object, else $null. #>
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Key)) { return $Object[$Key] } return $null }
    $p = $Object.PSObject.Properties[$Key]
    if ($p) { $p.Value } else { $null }
}

function Get-BaselineCount($Baseline, [string]$File, [string]$Rule) {
    <# What the baseline allows a file for a rule (0 when it does not name it). #>
    $n = Get-CodeSizeField (Get-CodeSizeField $Baseline $File) $Rule
    if ($null -eq $n) { 0 } else { [int]$n }
}

function Get-LoweredBaseline {
    <# The baseline -Update writes: it only ever lowers. A count above the old baseline keeps the old
       number; a file or rule the old baseline did not allow is not added. Without an old baseline
       ($null) the counts themselves. #>
    param($Counts, $Baseline)
    $next = [ordered]@{}
    foreach ($file in @($Counts.Keys | Sort-Object)) {
        $rules = [ordered]@{}
        foreach ($rule in $script:CodeSizeRules) {
            if (-not $Counts[$file].Contains($rule)) { continue }
            $count = [int]$Counts[$file][$rule]
            $old = if ($null -eq $Baseline) { $count } else { Get-BaselineCount $Baseline $file $rule }
            if ($count -le $old) { $rules[$rule] = $count } elseif ($old -gt 0) { $rules[$rule] = $old }
        }
        if ($rules.Count) { $next[$file] = $rules }
    }
    $next
}

function Get-RatchetFailures {
    <# Each file and rule over its baseline count, as "<file>: <rule> <n> (allowed <m>)". #>
    param($Counts, $Baseline)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($file in @($Counts.Keys | Sort-Object)) {
        foreach ($rule in $script:CodeSizeRules) {
            if (-not $Counts[$file].Contains($rule)) { continue }
            $allowed = Get-BaselineCount $Baseline $file $rule
            if ([int]$Counts[$file][$rule] -gt $allowed) { $out.Add("${file}: $rule $($Counts[$file][$rule]) (allowed $allowed)") }
        }
    }
    $out.ToArray()
}

function ConvertTo-BaselineJson($Baseline) {
    <# Two-space JSON with a final newline, files sorted (ConvertTo-Json in 5.1 indents oddly). #>
    $lines = New-Object System.Collections.Generic.List[string]
    $files = @($Baseline.Keys | Sort-Object)
    $lines.Add('{')
    for ($i = 0; $i -lt $files.Count; $i++) {
        $rules = $Baseline[$files[$i]]
        $parts = @($script:CodeSizeRules | Where-Object { $rules.Contains($_) } | ForEach-Object { '    "{0}": {1}' -f $_, $rules[$_] })
        $lines.Add('  "' + $files[$i] + '": {')
        for ($j = 0; $j -lt $parts.Count; $j++) { $lines.Add($parts[$j] + $(if ($j -lt $parts.Count - 1) { ',' } else { '' })) }
        $lines.Add('  }' + $(if ($i -lt $files.Count - 1) { ',' } else { '' }))
    }
    $lines.Add('}')
    ($lines -join "`n") + "`n"
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $root = Split-Path -Parent $PSScriptRoot
    $baselinePath = Join-Path $root 'tests\fixtures\ps-code-size.json'
    $m = Get-CodeSizeCounts -Root $root
    if ($m.Files -eq 0) { [Console]::Error.WriteLine("code size: no file measured under $root"); exit 1 }
    $baseline = if (Test-Path -LiteralPath $baselinePath) { [IO.File]::ReadAllText($baselinePath) | ConvertFrom-Json } else { $null }
    if ($Update) {
        $next = Get-LoweredBaseline -Counts $m.Counts -Baseline $baseline
        [IO.File]::WriteAllText($baselinePath, (ConvertTo-BaselineJson $next), (New-Object System.Text.UTF8Encoding $false))
        Write-Output "code size baseline written: $($next.Count) files ($($m.Files) measured)"
        exit 0
    }
    if ($null -eq $baseline) { [Console]::Error.WriteLine('code size: no baseline yet. Run with -Update once to write it.'); exit 1 }
    $fail = @(Get-RatchetFailures -Counts $m.Counts -Baseline $baseline)
    if ($fail.Count) {
        [Console]::Error.WriteLine("code size: a function grew past $script:CodeSizeMaxLines lines or complexity $script:CodeSizeMaxComplexity; split it.")
        foreach ($l in $fail) { [Console]::Error.WriteLine("  $l") }
        exit 1
    }
    Write-Output "code size: no file grew ($($m.Files) files measured, $($m.Over.Count) older over-limit functions in the baseline)"
    exit 0
}
