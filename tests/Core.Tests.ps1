# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\Core.psm1') -Force

Describe 'Get-Greeting' {
    It 'trims the name' {
        (Get-Greeting -Name '  Ada ').Text | Should Be 'Hello, Ada'
    }
    It 'rejects an empty name' {
        { Get-Greeting -Name '   ' } | Should Throw
    }
    It 'serialises to a non-empty JSON object' {
        (Get-Greeting -Name 'Ada' | ConvertTo-Json -Compress) | Should Be '{"Text":"Hello, Ada"}'
    }
}
