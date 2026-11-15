# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# A new start replaces the ObsidiNote that runs on this PC (lib/Startup.psm1 Invoke-ReplaceRunning,
# Get-LeftoverStarts), and takes over a lease this PC left behind (lib/WriterLease.psm1: the machine
# mark `m`, Get-LeaseDecision -NoOtherHere). No real process, socket or OneNote: the process list and
# the HTTP calls are scriptblocks, the vault is the in-memory OneNote. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'Startup', 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:Script = 'C:\Apps\ObsidiNote\obsidinote.ps1'
function New-Proc([int]$Id, [int]$Parent, [string]$Name, [string]$Cmd) { [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; Name = $Name; CommandLine = $Cmd } }
$script:Line = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$($script:Script)"""

Describe 'Get-LeftoverStarts' {
    $procs = @(
        (New-Proc 100 1 'powershell.exe' $script:Line),                                   # an earlier start
        (New-Proc 200 1 'powershell.exe' $script:Line),                                   # the updater's old version: parent of this start
        (New-Proc 210 200 'cmd.exe' 'cmd /c something'),
        (New-Proc 300 210 'powershell.exe' $script:Line),                                 # this start
        (New-Proc 400 1 'powershell.exe' 'powershell.exe -File "C:\Other\ObsidiNote\obsidinote.ps1"'),
        (New-Proc 500 1 'powershell.exe' 'powershell.exe -Command obsidinote 8767'),      # a bare word and a number
        (New-Proc 600 1 'notepad.exe' "notepad.exe ""$($script:Script)"""),
        (New-Proc 700 1 'powershell.exe' "POWERSHELL.EXE -file ""$($script:Script.ToUpperInvariant())"" -NoCopilot"),
        (New-Proc 800 1 'powershell.exe' $null)
    )
    It 'finds powershell.exe with this script''s full path, never itself or its parents' {
        $l = Get-LeftoverStarts -Processes $procs -ScriptPath $script:Script -SelfId 300
        (@($l | ForEach-Object { $_.ProcessId } | Sort-Object) -join ',') | Should Be '100,700'
    }
    It 'never matches by a bare word, a number, another folder or another program' {
        $l = Get-LeftoverStarts -Processes $procs -ScriptPath $script:Script -SelfId 300
        @($l | Where-Object { $_.ProcessId -in 400, 500, 600, 800 }).Count | Should Be 0
    }
    It 'finds nothing for a path that is not a full path' {
        @(Get-LeftoverStarts -Processes $procs -ScriptPath 'obsidinote.ps1' -SelfId 300).Count | Should Be 0
    }
}

function New-ReplaceWorld([bool]$Running, [bool]$StopsOnRequest, [bool]$StopsOnKill = $true, [object[]]$Procs = @(), [bool]$RequestThrows = $false, [bool]$ListThrows = $false) {
    $w = @{ running = $Running; stops = $StopsOnRequest; kill = $StopsOnKill; procs = (New-Object System.Collections.ArrayList); posted = 0; killed = (New-Object System.Collections.ArrayList); waited = 0; throws = $RequestThrows; listThrows = $ListThrows }
    foreach ($p in $Procs) { $null = $w.procs.Add($p) }
    $w.args = @{
        ScriptPath = $script:Script; SelfId = 300
        TestRunning = { $w.running }.GetNewClosure()
        RequestStop = { $w.posted++; if ($w.throws) { throw 'Not found.' }; if ($w.stops) { $w.running = $false; foreach ($p in @($w.procs)) { if ($p.ProcessId -eq 100) { $w.procs.Remove($p) } } } }.GetNewClosure()
        GetProcesses = { if ($w.listThrows) { throw 'access denied' }; @($w.procs) }.GetNewClosure()
        StopProcess = { param($ProcessId) $null = $w.killed.Add([int]$ProcessId); foreach ($p in @($w.procs)) { if ($p.ProcessId -eq $ProcessId) { $w.procs.Remove($p) } }; if ($w.kill) { $w.running = $false } }.GetNewClosure()
        Wait = { param($Milliseconds) $w.waited += $Milliseconds }.GetNewClosure()
    }
    $w
}

Describe 'Invoke-ReplaceRunning' {
    $old = New-Proc 100 1 'powershell.exe' $script:Line
    $me = New-Proc 300 1 'powershell.exe' $script:Line
    It 'does nothing and says nothing when no ObsidiNote runs' {
        $w = New-ReplaceWorld $false $false -Procs @($me)
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $r.found | Should Be $false
        $r.status | Should Be ''
        $r.noOtherHere | Should Be $true
        $w.posted | Should Be 0
        $w.killed.Count | Should Be 0
    }
    It 'asks the running one to stop and waits until the port is silent' {
        $w = New-ReplaceWorld $true $true -Procs @($old, $me)
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $w.posted | Should Be 1
        $w.killed.Count | Should Be 0
        $r.replaced | Should Be $true
        $r.status | Should Be 'OK'
        $r.detail | Should Be 'replaced the ObsidiNote that was running'
        $r.noOtherHere | Should Be $true
    }
    It 'stops the leftover process when it does not stop by itself (an older version without the route)' {
        $w = New-ReplaceWorld $true $false -Procs @($old, $me) -RequestThrows $true
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        ($w.killed -join ',') | Should Be '100'
        $w.waited | Should Be 10000        # it waited the 10 seconds first
        $r.replaced | Should Be $true
        $r.stopped | Should Be 1
        $r.status | Should Be 'OK'
        $r.detail | Should Match '^replaced the ObsidiNote that was running \(it did not stop by itself'
        $r.noOtherHere | Should Be $true
    }
    It 'never stops itself or a process it cannot tie to this script, and warns' {
        $w = New-ReplaceWorld $true $false -Procs @($me, (New-Proc 400 1 'powershell.exe' 'powershell.exe -File "C:\Other\obsidinote.ps1"'))
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $w.killed.Count | Should Be 0
        $r.replaced | Should Be $false
        $r.status | Should Be 'WARN'
        $r.detail | Should Match '^an earlier ObsidiNote did not stop: it still answers after 10 seconds, and its process was not found$'
        $r.noOtherHere | Should Be $false
    }
    It 'warns when the process was stopped but the port still answers' {
        $w = New-ReplaceWorld $true $false -StopsOnKill $false -Procs @($old, $me)
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $r.status | Should Be 'WARN'
        $r.detail | Should Match '^an earlier ObsidiNote did not stop: '
        $r.noOtherHere | Should Be $false
    }
    It 'does not allow the lease take-over while another start of this script is alive without a server' {
        $w = New-ReplaceWorld $false $false -Procs @($old, $me)
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $w.killed.Count | Should Be 0
        $r.noOtherHere | Should Be $false
        $r.status | Should Be 'WARN'
        $r.detail | Should Match 'an earlier ObsidiNote start is still running on this PC'
    }
    It 'does not allow the take-over when the process list cannot be read' {
        $w = New-ReplaceWorld $false $false -ListThrows $true
        $a = $w.args
        $r = Invoke-ReplaceRunning @a
        $r.noOtherHere | Should Be $false
        $r.status | Should Be 'WARN'
    }
}

Describe 'The lease''s machine mark' {
    $t0 = [datetime]::SpecifyKind([datetime]'2026-11-15T09:00:00', 'Utc')
    It 'is 12 hex characters of a hash, the same for the same name in any case, never the name' {
        $m = Get-MachineMark -Name 'Desk-Example'
        $m | Should Match '^[0-9a-f]{12}$'
        (Get-MachineMark -Name 'DESK-EXAMPLE') | Should Be $m
        (Get-MachineMark -Name 'Other-Example') | Should Not Be $m
        (Get-MachineMark) | Should Match '^[0-9a-f]{12}$'
        (ConvertTo-LeaseValue -SessionId 's' -Now $t0) | Should Not Match ([regex]::Escape([Environment]::MachineName))
    }
    It 'is written as m and read back with the acquired time' {
        $v = ConvertTo-LeaseValue -SessionId 's1' -Now $t0 -TtlSec 120 -Machine 'aaaaaaaaaaaa'
        $v | Should Be '{"s":"s1","e":"2026-11-15T09:02:00Z","a":"2026-11-15T09:00:00Z","m":"aaaaaaaaaaaa"}'
        $l = ConvertFrom-LeaseValue $v
        $l.machine | Should Be 'aaaaaaaaaaaa'
        $l.acquired | Should Be $t0
        (ConvertFrom-LeaseValue '{"s":"s1","e":"2026-11-15T09:02:00Z","a":"2026-11-15T09:00:00Z"}').machine | Should Be ''
    }
}

Describe 'Get-LeaseDecision: a lease this PC left behind' {
    $t0 = [datetime]::SpecifyKind([datetime]'2026-11-15T09:00:00', 'Utc')
    $mine = ConvertTo-LeaseValue -SessionId 'old' -Now $t0 -TtlSec 120 -Machine 'aaaaaaaaaaaa'
    $theirs = ConvertTo-LeaseValue -SessionId 'old' -Now $t0 -TtlSec 120 -Machine 'bbbbbbbbbbbb'
    $unmarked = '{"s":"old","e":"2026-11-15T09:02:00Z","a":"2026-11-15T09:00:00Z"}'
    $now = $t0.AddSeconds(30)
    It 'is taken when it is this PC''s, not expired, and no other ObsidiNote runs here' {
        Get-LeaseDecision -Current $mine -SessionId 'new' -Now $now -Machine 'aaaaaaaaaaaa' -NoOtherHere | Should Be 'acquire'
    }
    It 'is not taken without that knowledge' {
        Get-LeaseDecision -Current $mine -SessionId 'new' -Now $now -Machine 'aaaaaaaaaaaa' | Should Be 'readonly'
    }
    It 'is never taken from another PC, or when it has no machine mark (an older version)' {
        Get-LeaseDecision -Current $theirs -SessionId 'new' -Now $now -Machine 'aaaaaaaaaaaa' -NoOtherHere | Should Be 'readonly'
        Get-LeaseDecision -Current $unmarked -SessionId 'new' -Now $now -Machine 'aaaaaaaaaaaa' -NoOtherHere | Should Be 'readonly'
        Get-LeaseDecision -Current $unmarked -SessionId 'new' -Now $now -Machine '' -NoOtherHere | Should Be 'readonly'
    }
    It 'still takes an expired lease and renews its own, as before' {
        Get-LeaseDecision -Current $theirs -SessionId 'new' -Now $t0.AddSeconds(121) -Machine 'aaaaaaaaaaaa' | Should Be 'acquire'
        Get-LeaseDecision -Current $theirs -SessionId 'old' -Now $now -Machine 'aaaaaaaaaaaa' | Should Be 'renew'
    }
}

Describe 'Request-WriterLease: holderHere, acquired and the take-over (in-memory OneNote)' {
    $w = New-SyntheticVault -SessionId 'first'
    $ix = $w.open.vault.indexSectionId
    $t0 = [datetime]::UtcNow
    It 'carries acquired and holderHere on the record that goes to the server' {
        $w.open.lease.mode | Should Be 'writer'
        $w.open.lease.holderHere | Should Be $false
        $w.open.lease.ContainsKey('acquired') | Should Be $true
        ([datetime]$w.open.lease.acquired) -gt [datetime]::MinValue | Should Be $true
    }
    It 'runs read only next to another session of this PC, and says it is this PC' {
        $o = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'second' -Now $t0.AddSeconds(5)
        $o.mode | Should Be 'readonly'
        $o.holder | Should Be 'first'
        $o.holderHere | Should Be $true
        ([datetime]$o.acquired) -gt [datetime]::MinValue | Should Be $true
    }
    It 'says another PC for a lease with another mark, and never takes it' {
        $o = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'second' -Now $t0.AddSeconds(5) -Machine 'bbbbbbbbbbbb' -NoOtherHere
        $o.mode | Should Be 'readonly'
        $o.holderHere | Should Be $false
        (Get-VaultState -Adapter $w.a -IndexSectionId $ix).lease | Should Match '"s":"first"'
    }
    It 'takes this PC''s lease over when the start says no other ObsidiNote runs here' {
        $o = Request-WriterLease -Adapter $w.a -IndexSectionId $ix -SessionId 'second' -Now $t0.AddSeconds(6) -NoOtherHere
        $o.mode | Should Be 'writer'
        $o.holder | Should Be 'second'
        $o.holderHere | Should Be $false
        (Get-VaultState -Adapter $w.a -IndexSectionId $ix).lease | Should Match ('"m":"' + (Get-MachineMark) + '"')
    }
    It 'opens the vault as the writer with -NoOtherHere, read only without it' {
        $w2 = New-SyntheticVault -SessionId 'crashed'
        $item = @($w2.vaults | Where-Object { $_.vaultId -eq $w2.v.vaultId })[0]
        (Open-VaultSession -Adapter $w2.a -Vault $item -SessionId 'later' -Vaults $w2.vaults).mode | Should Be 'readonly'
        $o = Open-VaultSession -Adapter $w2.a -Vault $item -SessionId 'later' -Vaults $w2.vaults -NoOtherHere
        $o.mode | Should Be 'writer'
        $o.lease.holder | Should Be 'later'
    }
    It 'says in the Vault line that it is this PC''s earlier ObsidiNote' {
        $w3 = New-SyntheticVault -SessionId 'crashed'
        $item = @($w3.vaults | Where-Object { $_.vaultId -eq $w3.v.vaultId })[0]
        $o = Open-VaultSession -Adapter $w3.a -Vault $item -SessionId 'later' -Vaults $w3.vaults
        (Format-VaultStatus -Open $o).detail | Should Match 'read only, an earlier ObsidiNote on this PC still holds this vault'
    }
}
