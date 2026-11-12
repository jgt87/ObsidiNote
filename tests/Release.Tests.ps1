# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The release ships the prebuilt interface (ui\) and not its source (ui-src\), and the install
# check (manifest.json) covers ui\. Reads tools/build-release.ps1; builds nothing.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'lib\Update.psm1') -Force

function Get-DevFolders {
    $src = [IO.File]::ReadAllText((Join-Path $root 'tools\build-release.ps1'))
    $m = [regex]::Match($src, "foreach \(\`$dev in ([^)]+)\)")
    @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

Describe 'The release package' {
    It 'drops ui-src (and the tokens source) but keeps ui' {
        $dev = Get-DevFolders
        $dev.Count | Should BeGreaterThan 5
        ($dev -contains 'ui-src') | Should Be $true
        ($dev -contains 'src') | Should Be $true
        ($dev -contains 'ui') | Should Be $false
        ($dev -contains 'config') | Should Be $false
    }
    It 'stops when ui\index.html is missing' {
        [IO.File]::ReadAllText((Join-Path $root 'tools\build-release.ps1')) | Should Match "ui\\index\.html'\)\)\) \{ throw"
    }
    It 'has the built interface in the repo (ui\index.html and its assets)' {
        Test-Path (Join-Path $root 'ui\index.html') | Should Be $true
        @(Get-ChildItem (Join-Path $root 'ui\assets') -Filter *.js).Count | Should BeGreaterThan 0
    }
    It 'lists ui\ files in manifest.json, so the install check covers them' {
        $app = Join-Path $env:TEMP ('obsn-rel-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'ui\assets')
        [IO.File]::WriteAllText((Join-Path $app 'ui\index.html'), 'x')
        [IO.File]::WriteAllText((Join-Path $app 'ui\assets\a.js'), 'y')
        $null = New-InstallManifest -AppFolder $app -Version 'v0.0.0'
        $m = [IO.File]::ReadAllText((Join-Path $app 'manifest.json')) | ConvertFrom-Json
        ($m.files.PSObject.Properties.Name -contains 'ui/index.html') | Should Be $true
        ($m.files.PSObject.Properties.Name -contains 'ui/assets/a.js') | Should Be $true
        Remove-Item $app -Recurse -Force
    }
}
