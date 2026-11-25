# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Names that never appear in the repo: code, comments, docs, tests, config, the built interface
# (D-001): the note app ObsidiNote's ideas come from and the author's sister
# projects. Describe things on their own terms ("Markdown with [[wikilinks]]", "the author's
# earlier Copilot bridge"). One spelling stays allowed: Microsoft's Copilot endpoint path
# "/StreamHub" in URL patterns, which the bridge must match. The names are built from pieces, so
# this file does not match itself.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# The code-index tool used while building (D-030).
$script:Names = @(('obsid' + 'ian'), ('ccb' + 'ridge'), ('stream' + 'hub'), ('repo' + 'wise'))
$script:Allowed = '/' + 'stream' + 'hub'   # Microsoft's endpoint path, matched case-insensitively

# Real names of people and companies seen in the operator's own data (D-076): kept in tasks/private-names.txt,
# which is gitignored and stays on that machine, one name per line ('#' starts a comment), matched as a
# whole word in any case. The repo itself never holds them; on CI the file is absent and adds nothing.
function Get-PrivateNames {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(foreach ($l in [IO.File]::ReadAllLines($Path)) { $t = $l.Trim(); if ($t -and -not $t.StartsWith('#')) { '(?<![\p{L}\p{N}])' + [regex]::Escape($t) + '(?![\p{L}\p{N}])' } })
}
$script:Names = @($script:Names) + @(Get-PrivateNames -Path (Join-Path $root 'tasks\private-names.txt'))

function Get-ReferenceNameHits {
    param([Parameter(Mandatory)][string]$Root)
    # Paths inside the repo; .NET enumeration keeps the root as given (8.3 short names on CI).
    $r = $Root.TrimEnd('\')
    # Dot-folders are local tool state (index caches, worktrees, agent files), except .github.
    $skip = '(^|\\)(\.(?!github\\)[^\\]+|release|temp|tasks|node_modules)\\'
    foreach ($full in [IO.Directory]::EnumerateFiles($r, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = $full.Substring($r.Length + 1)
        if ($rel -match $skip -or ($rel -notmatch '\.(ps1|psm1|cmd|md|json|txt|yml|yaml|ts|tsx|js|mjs|css|html|svg|py)$' -and $rel -notmatch '^\.git(ignore|attributes)$')) { continue }
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

    It 'reads a local list of real names as whole words in any case; no list adds nothing' {
        $tmp = Join-Path $env:TEMP ('obsn-priv-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force $tmp
        try {
            $list = Join-Path $tmp 'names.txt'
            [IO.File]::WriteAllText($list, "# invented names for this test`nQuillon Works`nZed`n")
            $pats = @(Get-PrivateNames -Path $list)
            $pats.Count | Should Be 2
            ('Notes from QUILLON works' -match $pats[0]) | Should Be $true
            ('Zed joined' -match $pats[1]) | Should Be $true
            ('Zedonia and zeds' -match $pats[1]) | Should Be $false
            @(Get-PrivateNames -Path (Join-Path $tmp 'absent.txt')).Count | Should Be 0
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }
}
