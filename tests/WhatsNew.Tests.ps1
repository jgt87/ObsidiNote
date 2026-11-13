# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# What's new: the CHANGELOG parser (lib/WhatsNew.psm1), GET /api/whats-new in process, and the start's
# hand-over of the updated version. Invented changelog text only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'lib\WhatsNew.psm1') -Force
Import-Module (Join-Path $root 'lib\Server.psm1') -Force

$script:Log = @(
    '# Changelog', '',
    '## [Unreleased]', '',
    '### Added', '- Not released yet.', '',
    '## [v1.2.0] - 2026-11-13', '',
    '### Added',
    '- **Find.** Look up a page by its title',
    '  or one of its aliases.',
    '- Uses `config\obsidinote.json`.', '',
    '### Changed',
    '* The box is   higher.', '',
    '### Removed',
    '- Left out on purpose.', '',
    '### Fixed',
    '- A crash on start.', '',
    '## [v1.1.0] - 2026-11-12', '',
    '### Fixed',
    '- Older fix.'
) -join "`r`n"

Describe 'Get-ChangelogNotes' {
    It 'reads only the asked version, with its kind, in file order' {
        $n = @(Get-ChangelogNotes -Text $script:Log -Version 'v1.2.0')
        $n.Count | Should Be 4
        ($n | ForEach-Object { $_.kind }) -join ',' | Should Be 'Added,Added,Changed,Fixed'
    }
    It 'keeps the text plain: no bold markers or code ticks, continuation lines joined, spaces collapsed' {
        $n = @(Get-ChangelogNotes -Text $script:Log -Version 'v1.2.0')
        $n[0].text | Should Be 'Find. Look up a page by its title or one of its aliases.'
        $n[1].text | Should Be 'Uses config\obsidinote.json.'
        $n[2].text | Should Be 'The box is higher.'
    }
    It 'accepts the version with or without its v, and finds the last section' {
        $n = @(Get-ChangelogNotes -Text $script:Log -Version '1.1.0')
        $n.Count | Should Be 1
        $n[0].text | Should Be 'Older fix.'
    }
    It 'leaves out headings other than Added, Changed and Fixed' {
        @(Get-ChangelogNotes -Text $script:Log -Version 'v1.2.0' | Where-Object { $_.text -match 'purpose' }).Count | Should Be 0
    }
    It 'gives nothing for an unknown version or an empty text' {
        @(Get-ChangelogNotes -Text $script:Log -Version 'v9.9.9').Count | Should Be 0
        @(Get-ChangelogNotes -Text '' -Version 'v1.2.0').Count | Should Be 0
    }
    It 'does not read [ as a wildcard (a heading like ## [v1x2x0] is another version)' {
        @(Get-ChangelogNotes -Text "## [v1x2x0] - d`n### Added`n- no" -Version 'v1.2.0').Count | Should Be 0
    }
    It 'reads the shipped CHANGELOG.md for its own version heading' {
        $text = [IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'))
        $first = ([regex]::Match($text, '(?m)^## \[(v\d[^\]]*)\]')).Groups[1].Value
        @(Get-ChangelogNotes -Text $text -Version $first).Count -gt 0 | Should Be $true
    }
}

Describe 'GET /api/whats-new (in process)' {
    $app = Join-Path $env:TEMP ('obsn-whatsnew-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force $app
    [IO.File]::WriteAllText((Join-Path $app 'version.txt'), "v1.2.0`n")
    [IO.File]::WriteAllText((Join-Path $app 'CHANGELOG.md'), $script:Log)
    try {
        It 'says updated with the version and its lines after an update' {
            $state = New-ServerState -AppRoot $app -Port 8767 -SessionId 's' -UpdatedTo 'v1.2.0'
            $r = Invoke-ApiRoute -Method 'GET' -Path '/api/whats-new' -State $state
            $r.status | Should Be 200
            $r.body.version | Should Be 'v1.2.0'
            $r.body.updated | Should Be $true
            @($r.body.notes).Count | Should Be 4
            $json = ConvertTo-Json -InputObject $r.body -Depth 5 -Compress
            $json | Should Match '"kind":"Changed"'
        }
        It 'says not updated on an ordinary start' {
            $state = New-ServerState -AppRoot $app -Port 8767 -SessionId 's'
            (Invoke-ApiRoute -Method 'GET' -Path '/api/whats-new' -State $state).body.updated | Should Be $false
        }
        It 'answers with no lines (not an error) without a CHANGELOG.md, and keeps notes a JSON list' {
            Remove-Item -LiteralPath (Join-Path $app 'CHANGELOG.md')
            $state = New-ServerState -AppRoot $app -Port 8767 -SessionId 's' -UpdatedTo 'v1.2.0'
            $r = Invoke-ApiRoute -Method 'GET' -Path '/api/whats-new' -State $state
            $r.status | Should Be 200
            (ConvertTo-Json -InputObject $r.body -Depth 5 -Compress) | Should Match '"notes":\[\]'
        }
        It 'is a GET only' {
            $state = New-ServerState -AppRoot $app -Port 8767 -SessionId 's'
            (Invoke-ApiRoute -Method 'POST' -Path '/api/whats-new' -State $state).status | Should Be 404
        }
    } finally { Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'The start and the release keep what the notice needs' {
    It 'obsidinote.ps1 hands the updated version to the server state' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'obsidinote.ps1'))
        $src | Should Match '-UpdatedTo \$updatedTo'
        $src | Should Match "OBSIDINOTE_UPDATED`"\.StartsWith\('updated'\)"
    }
    It 'tools/build-release.ps1 does not drop CHANGELOG.md from the release' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'tools\build-release.ps1'))
        $line = ([regex]::Match($src, "foreach \(\`$dev in [^)]*\)")).Value
        $line | Should Match 'ui-src'
        $line | Should Not Match 'CHANGELOG'
    }
}
