Set-StrictMode -Version 2.0
# What's new: one version's lines from CHANGELOG.md, for the window's "Updated to vX.Y.Z" notice after
# an update (GET /api/whats-new). Read only: CHANGELOG.md ships in the release zip
# (tools/build-release.ps1 does not drop it); nothing is written or kept.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.

$script:Kinds = @('Added', 'Changed', 'Fixed')

function ConvertTo-PlainNote([string]$Text) {
    <# A changelog line as plain text: no bold markers or code ticks, single spaces. Pure. #>
    $t = $Text.Replace('**', '').Replace('`', '')
    ($t -replace '\s+', ' ').Trim()
}

function Get-VersionKey([string]$Version) {
    # 'v0.6.1', '0.6.1' and 'V0.6.1' are the same version.
    $v = "$Version".Trim()
    if ($v.StartsWith('v') -or $v.StartsWith('V')) { $v = $v.Substring(1) }
    $v.ToLowerInvariant()
}

function Get-ChangelogNotes {
    <# The lines of one version's section ("## [v0.6.1] - date") as @{ kind; text }, in file order.
       kind = the "### Added|Changed|Fixed" heading above the line; lines under other headings are
       left out. A bullet's indented continuation lines join it. Pure.
       Headings are found with .StartsWith: -like reads '[' as a wildcard. #>
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Version)
    $notes = New-Object System.Collections.Generic.List[object]
    $want = Get-VersionKey $Version
    # Plain pipeline output: callers wrap the call in @() (a ', @()' return would nest, AGENTS.md).
    if (-not $Text -or -not $want) { return }
    $inSection = $false; $kind = ''; $current = $null
    foreach ($raw in ($Text -split '\r?\n')) {
        $line = $raw.TrimEnd()
        if ($line.StartsWith('## ')) {
            if ($inSection) { break }
            if ($line.StartsWith('## [')) {
                $close = $line.IndexOf(']')
                if ($close -gt 4 -and (Get-VersionKey $line.Substring(4, $close - 4)) -eq $want) { $inSection = $true }
            }
            continue
        }
        if (-not $inSection) { continue }
        if ($line.StartsWith('### ')) {
            $h = $line.Substring(4).Trim()
            $kind = ''
            foreach ($k in $script:Kinds) { if ($h -eq $k) { $kind = $k } }
            $current = $null; continue
        }
        if (-not $kind) { continue }
        if ($line -match '^[-*]\s+(?<t>.+)$') {
            $current = @{ kind = $kind; text = $Matches['t'] }
            $notes.Add($current); continue
        }
        if ($current -and $line.Trim() -and $line -match '^\s+\S') { $current.text = $current.text + ' ' + $line.Trim(); continue }
        if (-not $line.Trim()) { $current = $null }
    }
    foreach ($n in $notes) {
        $t = ConvertTo-PlainNote $n.text
        if ($t) { @{ kind = $n.kind; text = $t } }
    }
}

function Get-WhatsNew {
    <# The answer of GET /api/whats-new: @{ version; updated; notes }. UpdatedTo is the version the
       start was updated to (obsidinote.ps1, '' when this start followed no update). The notes are
       always those of the running version (version.txt); without a CHANGELOG.md they are empty. #>
    param([Parameter(Mandatory)][string]$AppRoot, [AllowEmptyString()][string]$UpdatedTo = '')
    $vf = Join-Path $AppRoot 'version.txt'
    $version = if (Test-Path -LiteralPath $vf) { ([IO.File]::ReadAllText($vf)).Trim() } else { '' }
    $shown = if (-not $version) { '' } elseif ($version -match '^\d') { "v$version" } else { $version }
    $notes = @()
    $cf = Join-Path $AppRoot 'CHANGELOG.md'
    if ($version -and (Test-Path -LiteralPath $cf)) {
        try { $notes = @(Get-ChangelogNotes -Text ([IO.File]::ReadAllText($cf)) -Version $version) } catch { $notes = @() }
    }
    @{ version = $shown; updated = [bool]$UpdatedTo; notes = @($notes) }
}

Export-ModuleMember -Function Get-ChangelogNotes, Get-WhatsNew, ConvertTo-PlainNote
