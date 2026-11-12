# Runs Pester and the ASCII-only rule. Exit code 0 = all good.
# -Path runs one test file (or folder) with the same module-path reset; never call bare
# Invoke-Pester from a pwsh 7 shell (it would load 7's modules).
param([string]$Path = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# When pwsh 7 starts Windows PowerShell 5.1, the child inherits 7's module path
# and loses Utility cmdlets. Reset it to the machine value.
if ($PSVersionTable.PSVersion.Major -le 5) {
    $userModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    $env:PSModulePath = $userModules + ';' + [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
}

$bad = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1 -File |
    Where-Object { $_.FullName -notlike '*\release\*' -and $_.FullName -notlike '*\node_modules\*' } |
    Where-Object { [IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1 }
if ($bad) {
    $bad | ForEach-Object { Write-Error "non-ASCII bytes in $($_.FullName)" -ErrorAction Continue }
    exit 1
}

$target = if ($Path) { $Path } else { Join-Path $root 'tests' }
$result = Invoke-Pester -Path $target -PassThru
if ($result.FailedCount -gt 0) { exit 1 }
exit 0
