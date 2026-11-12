# No in-memory download-and-run forms that antivirus flags as malware: WebClient DownloadString
# feeding a script, or encoded commands. Defender blocked "iex ((New-Object Net.WebClient).
# DownloadString(...))" as Trojan:PowerShell/Sacepos.C on 2026-11-12. The README's install line
# stays the same as CCBridge/StreamHub ("irm <url> | iex"), by the operator's decision.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Built from pieces, so this file does not match itself.
$patterns = @(
    ('Download' + 'String'),
    ('Download' + 'Data'),
    ('Encoded' + 'Command'),
    ('\s-e' + 'nc\s'),
    ('FromBase64' + 'String\(.*\)\s*\|\s*i' + 'ex')
)

function Get-FlaggedHits {
    param([Parameter(Mandatory)][string]$Root)
    # Skip folders by their path inside the repo (a system temp folder above the repo must not
    # count); enumerated with .NET so the root keeps the form it was given (8.3 short names).
    $r = $Root.TrimEnd('\')
    $skip = '^(\.git|release|temp|tasks|node_modules|\.claude)\\'
    foreach ($full in [IO.Directory]::EnumerateFiles($r, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = $full.Substring($r.Length + 1)
        if ($rel -match $skip -or $rel -notmatch '\.(ps1|psm1|cmd|md|json)$' -or $rel -match 'NoDownloadExecute\.Tests\.ps1$') { continue }
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($full)) {
            $n++
            foreach ($p in $patterns) {
                if ($line -match $p) { '{0}:{1}' -f $rel, $n; break }
            }
        }
    }
}

Describe 'No download-and-run forms that antivirus flags' {
    It 'finds no DownloadString, DownloadData or encoded commands in scripts and docs' {
        (@(Get-FlaggedHits -Root $root) -join ', ') | Should Be ''
    }

    It 'catches the flagged form when it is there' {
        $tmp = Join-Path $env:TEMP ('obsn-dlx-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force $tmp
        try {
            [IO.File]::WriteAllText((Join-Path $tmp 'bad.md'), ('(New-Object Net.WebClient).Download' + 'String(''https://example.com/x.ps1'')'))
            @(Get-FlaggedHits -Root $tmp).Count | Should Be 1
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }
}
