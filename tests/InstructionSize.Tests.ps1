# Pester 3.4 syntax. The files an agent session loads at every start stay small enough to load.
# Seen 2026-11-25: they had grown to 163k characters, past the loader's 150k limit, by adding each
# feature's contract to AGENTS.md and each lesson's bookkeeping to tasks/lessons.md. Over the
# budget? Do not shorten texts: move what matters for one area only, word for word, into a rule
# file with `paths:` (.claude/rules/project-<area>.md, AGENTS.md points there), and records that
# steer nothing into a file that is not loaded (tasks/lessons-upstream.md).
# Raising a budget is the operator's decision.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

$agentDocLines = 200
$agentDocChars = 40000
# The loader's limit is 150,000; the room below it is for the lessons a session adds.
$loadedChars = 140000

# What loads at every start: CLAUDE.md with the files it imports (a line "@path"), .claude/CLAUDE.md,
# and every rule file without a `paths:` block (one with it loads only for matching files).
# Files that are not there (gitignored ones on CI) count as nothing.
function Get-LoadedInstructionFiles {
    param([Parameter(Mandatory)][string]$Root)
    $found = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Generic.Queue[string]
    foreach ($name in 'CLAUDE.md', '.claude\CLAUDE.md') { $queue.Enqueue((Join-Path $Root $name)) }
    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        if ($found -contains $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $found.Add($file)
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line -match '^@(\S+)\s*$') { $queue.Enqueue((Join-Path (Split-Path -Parent $file) $Matches[1])) }
        }
    }
    $rules = Join-Path $Root '.claude\rules'
    if (Test-Path -LiteralPath $rules) {
        foreach ($rule in (Get-ChildItem -LiteralPath $rules -Filter '*.md' -File)) {
            if (-not (Test-PathScopedRule -Path $rule.FullName)) { $found.Add($rule.FullName) }
        }
    }
    return @($found)
}

# True when the file starts with a front matter block that holds a `paths:` key.
function Test-PathScopedRule {
    param([Parameter(Mandatory)][string]$Path)
    $lines = @([IO.File]::ReadAllLines($Path))
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return $false }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { return $false }
        if ($lines[$i] -match '^paths:') { return $true }
    }
    return $false
}

function Get-LoadedInstructionChars {
    param([Parameter(Mandatory)][string]$Root)
    $sum = 0
    foreach ($file in (Get-LoadedInstructionFiles -Root $Root)) { $sum += [IO.File]::ReadAllText($file).Length }
    return $sum
}

Describe 'The instruction files loaded at every session start' {
    It 'finds the agent doc among them (an empty run is not a pass)' {
        $names = @(Get-LoadedInstructionFiles -Root $root | ForEach-Object { Split-Path -Leaf $_ })
        ($names -contains 'CLAUDE.md') | Should Be $true
        ($names -contains 'AGENTS.md') | Should Be $true
    }
    It "AGENTS.md stays under $agentDocLines lines and $agentDocChars characters" {
        $file = Join-Path $root 'AGENTS.md'
        (@([IO.File]::ReadAllLines($file)).Count -lt $agentDocLines) | Should Be $true
        $chars = [IO.File]::ReadAllText($file).Length
        "AGENTS.md under ${agentDocChars}: $($chars -lt $agentDocChars)" | Should Be "AGENTS.md under ${agentDocChars}: True"
    }
    It "together they stay under $loadedChars characters" {
        $chars = Get-LoadedInstructionChars -Root $root
        "loaded files under ${loadedChars}: $($chars -lt $loadedChars)" | Should Be "loaded files under ${loadedChars}: True"
    }
    It 'counts imports and rule files without paths, and leaves path-scoped rule files out' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('obsn-instr-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $dir '.claude\rules') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $dir 'CLAUDE.md'), "@AGENTS.md`n@tasks/absent.md`n")
            [IO.File]::WriteAllText((Join-Path $dir 'AGENTS.md'), ('a' * 100))
            [IO.File]::WriteAllText((Join-Path $dir '.claude\rules\always.md'), ('b' * 1000))
            [IO.File]::WriteAllText((Join-Path $dir '.claude\rules\scoped.md'), "---`npaths:`n  - `"lib/**`"`n---`n" + ('c' * 10000))
            $entry = [IO.File]::ReadAllText((Join-Path $dir 'CLAUDE.md')).Length
            (Get-LoadedInstructionChars -Root $dir) | Should Be ($entry + 100 + 1000)
            # the broken example: the same text without its paths block is loaded, and counted
            [IO.File]::WriteAllText((Join-Path $dir '.claude\rules\scoped.md'), ('c' * 10000))
            (Get-LoadedInstructionChars -Root $dir) | Should Be ($entry + 100 + 1000 + 10000)
        } finally {
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
    }
}
