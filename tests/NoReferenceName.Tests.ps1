# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Names that never appear in the repo: code, comments, docs, tests, config, the built interface
# (operator, 2026-11-12/13): the note app ObsidiNote's ideas come from and the author's sister
# projects. Describe things on their own terms ("Markdown with [[wikilinks]]", "the author's
# earlier Copilot bridge"). One spelling stays allowed: Microsoft's Copilot endpoint path
# "/StreamHub" in URL patterns, which the bridge must match. The names are built from pieces, so
# this file does not match itself.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:Names = @(('obsid' + 'ian'), ('ccb' + 'ridge'), ('stream' + 'hub'))
$script:Allowed = '/' + 'stream' + 'hub'   # Microsoft's endpoint path, matched case-insensitively

function Get-ReferenceNameHits {
    param([Parameter(Mandatory)][string]$Root)
    # Paths inside the repo; .NET enumeration keeps the root as given (8.3 short names on CI).
    $r = $Root.TrimEnd('\')
    # Dot-folders are local tool state (index caches, worktrees, agent files), except .github.
    $skip = '(^|\\)(\.(?!github\\)[^\\]+|release|temp|tasks|node_modules)\\'
    foreach ($full in [IO.Directory]::EnumerateFiles($r, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = $full.Substring($r.Length + 1)
        if ($rel -match $skip -or $rel -notmatch '\.(ps1|psm1|cmd|md|json|txt|yml|yaml|ts|tsx|js|mjs|css|html|svg|py)$') { continue }
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($full)) {
            $n++
            $text = $line -replace [regex]::Escape($script:Allowed), ''
            foreach ($w in $script:Names) {
                if ($text -match $w) { '{0}:{1}' -f $rel, $n; break }
            }
        }
    }
}

Describe 'No reference or sister-project names in the repo' {
    It 'finds none of the names in any code, doc, test, config or built file' {
        (@(Get-ReferenceNameHits -Root $root) -join ', ') | Should Be ''
    }

    It 'catches each name in any case, and allows only the endpoint path' {
        $tmp = Join-Path $env:TEMP ('obsn-ref-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force $tmp
        try {
            [IO.File]::WriteAllText((Join-Path $tmp 'a.md'), ('Works with ' + 'Obsid' + 'ian.'))
            [IO.File]::WriteAllText((Join-Path $tmp 'b.ps1'), ('# copied from ' + 'CCB' + 'ridge'))
            [IO.File]::WriteAllText((Join-Path $tmp 'c.md'), ('Same install as ' + 'Stream' + 'Hub.'))
            [IO.File]::WriteAllText((Join-Path $tmp 'ok.json'), ('{ "streamUrlPattern": "/' + 'Stream' + 'Hub/" } ObsidiNote'))
            (@(Get-ReferenceNameHits -Root $tmp) | Sort-Object) -join ',' | Should Be 'a.md:1,b.ps1:1,c.md:1'
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }
}
