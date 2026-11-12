# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# OneNote is the only store (AGENTS.md invariant): the Copilot bridge never writes a file, and its
# log holds ids, counts, timings and states only. These tests read the source files.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\Log.psm1') -Force

# Calls that write a file. Export-ModuleMember is not one (it is the module's export list).
$script:FileWrites = '(?i)\b(WriteAllText|WriteAllLines|WriteAllBytes|AppendAllText|AppendAllLines|Set-Content|Add-Content|Out-File|Tee-Object|Start-Transcript|Copy-Item|Move-Item|StreamWriter|FileStream|Export-(?!ModuleMember)\w+)\b'

function Get-CodeLines([string]$File) {
    # Source lines with full-line comments blanked, so a failure still names file:line.
    $i = 0
    foreach ($l in [IO.File]::ReadAllLines($File)) {
        $i++
        $code = if ($l -match '^\s*#') { '' } else { $l }
        [pscustomobject]@{ file = (Split-Path -Leaf $File); line = $i; text = $code }
    }
}

Describe 'The Copilot bridge writes no files' {
    It 'has no file-writing call in lib/CopilotBridge.psm1, lib/Cdp.psm1 or lib/Sso.psm1' {
        $hits = @(foreach ($f in 'CopilotBridge.psm1', 'Cdp.psm1', 'Sso.psm1') {
            Get-CodeLines (Join-Path $root "lib\$f") | Where-Object { $_.text -match $script:FileWrites } | ForEach-Object { "$($_.file):$($_.line)" }
        })
        ($hits -join ', ') | Should Be ''
    }
    It 'allows a file write only in the logger, and only to its own log file' {
        $hits = @(Get-CodeLines (Join-Path $root 'lib\Log.psm1') | Where-Object { $_.text -match $script:FileWrites })
        $hits.Count | Should Be 1
        $hits[0].text | Should Match 'AppendAllText\(\$file,'
    }
    It 'finds a file write when one is added (the rule is not vacuous)' {
        'x | Out-File a.txt' -match $script:FileWrites | Should Be $true
        '[IO.File]::WriteAllLines($f, $x)' -match $script:FileWrites | Should Be $true
        'Export-Clixml -Path a' -match $script:FileWrites | Should Be $true
        'Export-ModuleMember -Function A' -match $script:FileWrites | Should Be $false
    }
}

Describe 'The bridge never logs content' {
    # A log call that passes prompt or reply text, a page title, a banner or a result message.
    $content = '(\$Text|\$ptext|\.Text|\.ServerText|\.SentText|\.title|\.bar|ResultMessage)\b(?!\)?"?\.Length)'
    It 'has no log call that carries text, a title or a banner' {
        $hits = @(foreach ($f in 'CopilotBridge.psm1', 'Cdp.psm1', 'Sso.psm1') {
            foreach ($l in (Get-CodeLines (Join-Path $root "lib\$f"))) {
                $at = $l.text.IndexOf('Write-AppLog')
                if ($at -lt 0) { continue }
                $call = $l.text.Substring($at)
                $end = $call.IndexOf('; ')
                if ($end -gt 0) { $call = $call.Substring(0, $end) }
                if ($call -cmatch $content -or $call -match '(?i)Write-AppLog\s+trace') { "$($l.file):$($l.line)" }
            }
        })
        ($hits -join ', ') | Should Be ''
    }
    It 'has no log level that records text' {
        { Write-AppLog trace bridge 'x' } | Should Throw
    }
}

Describe 'Write-AppLog' {
    It 'writes one masked line to logs\obsidinote.log in the data folder' {
        $file = Get-AppLogFile
        $file | Should Be (Join-Path $env:OBSIDINOTE_DATA_DIR 'logs\obsidinote.log')
        if (Test-Path $file) { Remove-Item $file -Force }
        Write-AppLog info bridge 'Attached to https://m365.cloud.microsoft/chat?auth=1 as a.b@example.org' @{ id = '12345678-1234-1234-1234-1234567890ab'; chars = 12 }
        $line = [IO.File]::ReadAllText($file)
        $line | Should Match 'INFO\s+bridge'
        $line | Should Match '"chars":12'
        $line | Should Not Match 'auth=1'
        $line | Should Not Match 'example\.org'
        $line | Should Not Match '12345678-1234'
    }
    It 'writes nothing when the level is off, and verbose lines only at verbose' {
        $file = Get-AppLogFile
        if (Test-Path $file) { Remove-Item $file -Force }
        $saved = $env:OBSIDINOTE_LOG
        try {
            $env:OBSIDINOTE_LOG = 'off'; Write-AppLog info bridge 'one'
            $env:OBSIDINOTE_LOG = ''; Write-AppLog verbose bridge 'two'
            Test-Path $file | Should Be $false
            $env:OBSIDINOTE_LOG = 'verbose'; Write-AppLog verbose bridge 'three'
            [IO.File]::ReadAllText($file) | Should Match 'three'
        } finally { $env:OBSIDINOTE_LOG = $saved }
    }
}
