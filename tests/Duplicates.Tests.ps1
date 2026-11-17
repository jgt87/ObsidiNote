# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Add of a page whose title and type an existing page already has (2026-11-17): refused with
# duplicateOf (the window offers "Open it" and "Add anyway"), and added beside it with allowDuplicate.
# Through the real store and the in-memory OneNote; recorded Copilot replies; synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Journal', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'FakeVault.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

Describe 'Add of a page that is already there (same title and type)' {
    $w = New-SyntheticVault
    $reply = '{"title": "Zero-trust networking", "summary": "Again about zero trust.", "type": "concept", "topics": [{"new": "Security/Networking"}], "links": [], "aliases": [], "intent": "add"}'
    $c = New-FakeCopilot @($reply, $reply)
    $r1 = Invoke-AddRequest -Request @{ text = 'Zero trust again.'; mode = 'add' } -Store $w.store -Ask $c.ask -Options @{ Now = [datetime]'2026-11-17T10:00' }
    It 'is refused and names the page that is there' {
        $r1.status | Should Be 'failed'
        $r1.duplicateOf | Should Be 'p1'
        @($r1.related)[0].id | Should Be 'p1'
        @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.title -eq 'Zero-trust networking' }).Count | Should Be 1
    }
    It 'is added beside it with allowDuplicate ("Add anyway")' {
        $r2 = Invoke-AddRequest -Request @{ text = 'Zero trust again.'; mode = 'add'; allowDuplicate = $true } -Store $w.store -Ask $c.ask -Options @{ Now = [datetime]'2026-11-17T10:05' }
        $r2.status | Should Be 'added'
        $r2.Contains('duplicateOf') | Should Be $false
        @($w.f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.title -eq 'Zero-trust networking' }).Count | Should Be 2
    }
}
