# OneNote at startup: state from the process list, start only when needed, wait for COM, never throw.
# No real OneNote: the process list, the start and the COM probe are stand-ins.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'lib\OneNoteHost.psm1') -Force

Describe 'OneNote state from the process list' {
    It 'is none without a OneNote process' {
        Get-OneNoteState -Processes @() | Should Be 'none'
    }
    It 'is background when OneNote runs only without a window (a COM instance)' {
        Get-OneNoteState -Processes @([pscustomobject]@{ MainWindowHandle = 0 }) | Should Be 'background'
    }
    It 'is window when one OneNote process has a window' {
        Get-OneNoteState -Processes @([pscustomobject]@{ MainWindowHandle = 0 }, [pscustomobject]@{ MainWindowHandle = 4242 }) | Should Be 'window'
    }
}

Describe 'Starting OneNote when needed' {
    It 'does not start OneNote when it already runs with a window' {
        $script:starts = 0
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'window' } -Start { $script:starts++ } -Probe { $true } -PollMs 1
        $r.ok | Should Be $true
        $r.started | Should Be $false
        $script:starts | Should Be 0
    }
    It 'starts OneNote when it is not running, then waits until COM answers' {
        $script:starts = 0; $script:probes = 0
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { $script:starts++ } -Probe { $script:probes++; $script:probes -ge 3 } -PollMs 1
        $r.ok | Should Be $true
        $r.started | Should Be $true
        $script:starts | Should Be 1
        $script:probes | Should Be 3
    }
    It 'starts OneNote with a window when only a background instance runs' {
        $script:starts = 0
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'background' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { $script:starts++ } -Probe { $true } -PollMs 1
        $r.started | Should Be $true
        $script:starts | Should Be 1
    }
    It 'gives up after the timeout with a message, without throwing' {
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { } -Probe { $false } -TimeoutSec 1 -PollMs 100
        $r.ok | Should Be $false
        $r.message | Should Match 'did not answer within 1 s'
    }
    It 'reports a missing OneNote instead of throwing' {
        Mock -ModuleName OneNoteHost Get-OneNoteExePath { '' }
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'none' } -Start { throw 'must not start' } -Probe { $false } -PollMs 1
        $r.ok | Should Be $false
        $r.message | Should Match 'was not found'
    }
    It 'says that no notebook is on record when it starts the exe itself' {
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { } -Probe { $true } -PollMs 1
        $r.how | Should Be 'exe'
        $r.warn | Should Match 'no notebook on record yet'
        $r.notebookOpen | Should Be $false
    }
    It 'turns a failing start into a message' {
        $r = Start-OneNoteIfNeeded -FindNotebook { $null } -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { throw 'access denied' } -Probe { $false } -PollMs 1
        $r.ok | Should Be $false
        $r.message | Should Match 'access denied'
    }
}

Describe 'The notebook on record' {
    $nbXml = '<?xml version="1.0"?><one:Notebooks xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"><one:Notebook name="Other" path="https://example.org/Documents/Other" /><one:Notebook name="ObsidiNote" nickname="ObsidiNote" path="https://example.org/Documents/ObsidiNote" /></one:Notebooks>'
    It 'finds ObsidiNote in the hierarchy and makes an onenote: link for a cloud notebook' {
        $nb = Find-NotebookInHierarchy -Xml $nbXml -Name 'ObsidiNote'
        $nb.path | Should Be 'https://example.org/Documents/ObsidiNote'
        ConvertTo-NotebookRecord $nb.path | Should Be 'onenote:https://example.org/Documents/ObsidiNote'
        Find-NotebookInHierarchy -Xml $nbXml -Name 'Missing' | Should BeNullOrEmpty
        Find-NotebookInHierarchy -Xml '' | Should BeNullOrEmpty
    }
    It 'records the .onetoc2 file of a local notebook folder' {
        $dir = Join-Path $env:TEMP ('obsn-nb-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force $dir
        try {
            ConvertTo-NotebookRecord $dir | Should Be ''
            $toc = Join-Path $dir 'Open Notebook.onetoc2'
            [IO.File]::WriteAllText($toc, '')
            ConvertTo-NotebookRecord $dir | Should Be $toc
            Test-NotebookRecord $toc | Should Be $true
            Test-NotebookRecord (Join-Path $dir 'gone.onetoc2') | Should Be $false
            Test-NotebookRecord 'onenote:https://example.org/Documents/ObsidiNote' | Should Be $true
            Test-NotebookRecord 'C:\x\notes.txt' | Should Be $false
            Test-NotebookRecord '' | Should Be $false
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    It 'opens the notebook on record (not the exe) when OneNote is not running, and waits until it is open' {
        $script:opened = @(); $script:exeStarts = 0; $script:looks = 0
        $r = Start-OneNoteIfNeeded -Record 'onenote:https://example.org/Documents/ObsidiNote' -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' `
            -Start { $script:exeStarts++ } -OpenRecord { param($rec) $script:opened += $rec } -Probe { $true } `
            -FindNotebook { param($n) $script:looks++; if ($script:looks -ge 3) { [pscustomobject]@{ name = $n; path = 'https://example.org/Documents/ObsidiNote' } } } -PollMs 1
        $r.ok | Should Be $true
        $r.how | Should Be 'record'
        $r.notebookOpen | Should Be $true
        $r.message | Should Be 'running, notebook ObsidiNote open'
        $r.foundRecord | Should Be 'onenote:https://example.org/Documents/ObsidiNote'
        $script:exeStarts | Should Be 0
        ($script:opened -join ',') | Should Be 'onenote:https://example.org/Documents/ObsidiNote'
        $script:looks | Should Be 3
    }
    It 'opens the record in a running OneNote that does not show the notebook' {
        $script:opened = 0; $script:open = $false
        $r = Start-OneNoteIfNeeded -Record 'onenote:https://example.org/Documents/ObsidiNote' -GetState { 'window' } -Start { throw 'no exe start' } `
            -OpenRecord { $script:opened++; $script:open = $true } -Probe { $true } `
            -FindNotebook { param($n) if ($script:open) { [pscustomobject]@{ name = $n; path = 'https://example.org/Documents/ObsidiNote' } } } -PollMs 1 -TimeoutSec 2
        $r.started | Should Be $false
        $script:opened | Should Be 1
        $r.notebookOpen | Should Be $true
    }
    It 'starts the exe and warns when the record points at a file that is gone' {
        $r = Start-OneNoteIfNeeded -Record 'C:\gone\Open Notebook.onetoc2' -GetState { 'none' } -ExePath 'C:\fake\ONENOTE.EXE' -Start { } `
            -OpenRecord { throw 'must not open' } -Probe { $true } -FindNotebook { $null } -PollMs 1
        $r.how | Should Be 'exe'
        $r.warn | Should Match 'cannot be opened'
    }
    It 'uses the start stand-ins only (the real Start-Process is never called)' {
        Mock -ModuleName OneNoteHost Start-Process { throw 'real Start-Process called' }
        $r = Start-OneNoteIfNeeded -Record 'onenote:https://example.org/x' -GetState { 'none' } -OpenRecord { } -Probe { $true } -FindNotebook { $null } -PollMs 1 -TimeoutSec 1
        $r.ok | Should Be $true
        Assert-MockCalled -ModuleName OneNoteHost Start-Process -Times 0
    }
}
