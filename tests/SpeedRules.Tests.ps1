# Pester 3.4 syntax. No test file reads the clock itself, so a speed limit in seconds cannot come back
# (docs/04 section 3): a CI runner or a busy PC can be many times slower on one run. A speed test compares
# scaling with tests/Scaling.ps1 (Measure-Growth), which may read the clock. Comment lines are not
# read, and a deadline for waiting ((Get-Date) -lt $deadline) measures nothing, so it is allowed.
# The PowerShell form of templates/tests/speed-rules.test.mjs, from a PowerShell bridge, 16 Nov 2026.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# Test files allowed to read the clock, each with its reason: a test of how long a time-out waits
# (behaviour, with seconds of margin) is one; a limit on how fast something runs never is.
$allowed = @{
    'tests/SpeedRules.Tests.ps1' = $true
    # The bridge's reply limits: "waits past the limit while Copilot works, up to the cap" and "stops
    # at the limit when it no longer works" measure how long a time-out waits (1 s limit, 4 s cap,
    # asserted against 3.5 s): behaviour with seconds of margin, not a speed limit.
    'tests/CopilotBridge.Tests.ps1' = $true
}
$clock = '\[Diagnostics\.Stopwatch\]|\.Elapsed\b|New-TimeSpan|\(Get-Date\)\s*-\s*\$'

function Find-ClockReads {
    <# Lines of $Text (comment lines left out) that read the clock, as "LINE: text". #>
    param([string]$Text)
    $lines = $Text -split "`n"
    $hits = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $l = $lines[$i].Trim()
        if ($l.StartsWith('#')) { continue }
        if ($l -match $clock) { $hits.Add(('{0}: {1}' -f ($i + 1), $l)) }
    }
    return $hits.ToArray()
}

$testFiles = @(Get-ChildItem -LiteralPath $here -Filter '*.Tests.ps1' -File)

Describe 'Speed tests compare scaling, never the clock' {
    It 'finds test files (an empty run is not a pass)' {
        $testFiles.Count -gt 0 | Should Be $true
    }
    It 'catches a clock read and skips a comment and a deadline (the check itself works)' {
        @(Find-ClockReads "`$w = [Diagnostics.Stopwatch]::StartNew()`n# [Diagnostics.Stopwatch] in a comment").Count | Should Be 1
        @(Find-ClockReads "`$s = ((Get-Date) - `$start).TotalSeconds`nwhile ((Get-Date) -lt `$deadline) { }").Count | Should Be 1
    }
    It 'no test file reads the clock (use tests/Scaling.ps1 for speed)' {
        $bad = @()
        foreach ($f in $testFiles) {
            $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            if ($allowed.ContainsKey($rel)) { continue }
            foreach ($h in @(Find-ClockReads ([IO.File]::ReadAllText($f.FullName)))) { $bad += "${rel}:$h" }
        }
        ($bad -join "`n") | Should Be ''
    }
}
