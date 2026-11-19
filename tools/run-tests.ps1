# Runs Pester and the ASCII-only rule. Exit code 0 = all good.
#   powershell -NoProfile -File tools/run-tests.ps1                                  all tests
#   powershell -NoProfile -File tools/run-tests.ps1 -Path C:\full\path\tests\Core.Tests.ps1   one file
# Run one file through here, never bare Invoke-Pester from pwsh 7: that loads 7's modules (the
# module-path reset below) and reports failures 5.1 does not have. Give -Path absolute: a relative
# path that does not exist makes `powershell -File` print its banner and exit 0; this script now
# also fails on a path that does not exist and on a run where no test ran.
param([string]$Path = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# When pwsh 7 starts Windows PowerShell 5.1, the child inherits 7's module path
# and loses Utility cmdlets. Reset it to the machine value.
if ($PSVersionTable.PSVersion.Major -le 5) {
    $userModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    $env:PSModulePath = $userModules + ';' + [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
}
# The tests are Pester 3.4 syntax (`Should Be`). A newer Pester beside it (GitHub's Windows runners
# have one) loads first in a process of its own; a pin in CI reaches only the process it runs in, not
# this script started with -File (CommonShared ps51 starter, 16 Nov 2026).
try { Import-Module Pester -RequiredVersion 3.4.0 -ErrorAction Stop } catch { Write-Warning 'Pester 3.4.0 is not installed: the tests run with the newest Pester found.' }

$bad = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1 -File |
    Where-Object { $_.FullName -notlike '*\release\*' -and $_.FullName -notlike '*\node_modules\*' } |
    Where-Object { [IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1 }
if ($bad) {
    $bad | ForEach-Object { Write-Error "non-ASCII bytes in $($_.FullName)" -ErrorAction Continue }
    exit 1
}

$target = if ($Path) { $Path } else { Join-Path $root 'tests' }
if (-not (Test-Path -LiteralPath $target)) { Write-Error "No such test path: $target" -ErrorAction Continue; exit 1 }
$result = Invoke-Pester -Path $target -PassThru
if ($result.TotalCount -eq 0) { Write-Error "No tests ran under $target" -ErrorAction Continue; exit 1 }
if ($result.FailedCount -gt 0) { exit 1 }
exit 0
