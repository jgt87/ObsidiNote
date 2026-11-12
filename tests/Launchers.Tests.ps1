# Every .cmd in the app root is one ( ) block with exit /b inside. cmd.exe reads a batch file from
# disk as it runs; when the updater replaces the file mid-run (v0.2.3 -> v0.2.4, 2026-11-12), cmd read
# on at its old position in the new file ("'uter' is not recognized") and started the app twice.
# A parenthesised block is read whole before it runs, and exit /b ends it before cmd reads further.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$cmds = @(Get-ChildItem -LiteralPath $root -Filter *.cmd -File)

Describe 'Launchers (.cmd) survive being replaced while they run' {
    It 'finds the launchers' {
        $cmds.Count | Should BeGreaterThan 0
    }
    foreach ($f in $cmds) {
        It "$($f.Name): the commands are one ( ) block that ends with exit /b" {
            $lines = @([IO.File]::ReadAllLines($f.FullName) | Where-Object { $_.Trim() })
            $code = @($lines | Where-Object { $_.Trim() -notmatch '^(@echo off|rem\b)' })
            $code[0].Trim() | Should Be '('
            $code[-1].Trim() | Should Be ')'
            $code[-2].Trim() | Should Be 'exit /b'
        }
        It "$($f.Name): uses CRLF line endings" {
            $t = [IO.File]::ReadAllText($f.FullName)
            ($t -match "[^`r]`n") | Should Be $false
        }
    }
}
