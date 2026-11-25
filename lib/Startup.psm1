# The start sequence's decisions, as pure functions (obsidinote.ps1 does the I/O): the update's
# status line, the arguments to start the new version with after an update, the OneNote line,
# and what to tell the person when Copilot cannot be reached.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0

function Format-AppVersion([string]$Version) {
    if (-not $Version) { return 'unknown version' }
    if ($Version -match '^\d') { "v$Version" } else { $Version }
}

function Get-UpdateStatus {
    <# The update's status line from tools\update.ps1 -PassThru: @{ status; detail; relaunch }.
       relaunch = a new version was installed and has to be started instead of this one. #>
    param($Result)
    if (-not $Result) { return [pscustomobject]@{ status = 'WARN'; detail = 'not checked: the updater gave no result'; relaunch = $false } }
    $v = Format-AppVersion "$($Result.version)"
    $d = "$($Result.detail)"
    switch ("$($Result.outcome)") {
        'up-to-date' { return [pscustomobject]@{ status = 'OK'; detail = "up to date ($v)"; relaunch = $false } }
        'updated' { return [pscustomobject]@{ status = 'OK'; detail = "updated $d; starting the new version"; relaunch = $true } }
        'repaired' { return [pscustomobject]@{ status = 'OK'; detail = "repaired ($d); starting it again"; relaunch = $true } }
        'off' { return [pscustomobject]@{ status = 'OK'; detail = "automatic updates are off ($v)"; relaunch = $false } }
        'skipped' { return [pscustomobject]@{ status = 'OK'; detail = "staying on $v ($d)"; relaunch = $false } }
        'not-updated' { return [pscustomobject]@{ status = 'WARN'; detail = "not updated: $d ($v)"; relaunch = $false } }
        'failed' { return [pscustomobject]@{ status = 'WARN'; detail = "not checked: $d ($v)"; relaunch = $false } }
        default { return [pscustomobject]@{ status = 'WARN'; detail = "unknown result '$($Result.outcome)' ($v)"; relaunch = $false } }
    }
}

function Get-RelaunchArguments {
    <# powershell.exe arguments that start $Script again with the same parameters ($Bound =
       $PSBoundParameters): switches as -Name, values as -Name value. #>
    param([Parameter(Mandatory)][string]$Script, [hashtable]$Bound = @{})
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script)
    foreach ($k in @($Bound.Keys | Sort-Object)) {
        $v = $Bound[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $a += "-$k" } }
        elseif ($v -is [bool]) { if ($v) { $a += "-$k" } }
        else { $a += "-$k"; $a += "$v" }
    }
    , $a
}

function Get-OneNoteStatus {
    <# The OneNote line from Start-OneNoteIfNeeded: @{ status; detail; hint }. #>
    param($Result)
    if (-not $Result.ok) { return [pscustomobject]@{ status = 'FAIL'; detail = "$($Result.message)"; hint = '' } }
    $how = if ($Result.started -and $Result.how -eq 'record') { ' (opened the notebook on record)' } elseif ($Result.started) { ' (started OneNote)' } else { '' }
    if (-not $Result.notebookOpen) {
        $hint = if ($Result.warn) { "$($Result.warn). " } else { '' }
        return [pscustomobject]@{ status = 'WARN'; detail = "$($Result.message)$how"; hint = $hint + 'Open the ObsidiNote notebook in OneNote once; the next start records where it is and opens it by itself.' }
    }
    if ($Result.warn) { return [pscustomobject]@{ status = 'WARN'; detail = "$($Result.message)$how"; hint = "$($Result.warn)" } }
    [pscustomobject]@{ status = 'OK'; detail = "$($Result.message)$how"; hint = '' }
}

function Get-CopilotFailureHint {
    <# What to do when Connect-Copilot failed, from its message and the Edge profile's state. #>
    param([string]$Message, [string]$Sso = '', [string]$Account = '')
    if ($Message -match 'without its debug port') { return 'Close every window of ObsidiNote''s Edge, then start ObsidiNote again.' }
    if ($Message -match 'BrowserSignin') { return 'Sign in to Edge itself with your work account in the window ObsidiNote opened, then start ObsidiNote again.' }
    if ($Message -match 'policy') { return 'Ask IT to allow Edge''s remote debugging (RemoteDebuggingAllowed) for ObsidiNote, then start it again.' }
    if ($Message -match 'never appeared') {
        if ($Sso -eq 'off') { return 'Run sso-setup.cmd once so Copilot signs in by itself, then start ObsidiNote again. Or sign in to Copilot in ObsidiNote''s Edge window within 10 minutes and choose "Stay signed in".' }
        return 'Sign in to Microsoft 365 Copilot in ObsidiNote''s Edge window within 10 minutes (choose "Stay signed in"), then start ObsidiNote again. Without Copilot: start with -NoCopilot.'
    }
    'Start ObsidiNote again. If it fails again, send the last 30 lines of %LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log (they hold no content). Without Copilot: start with -NoCopilot.'
}

function Get-LeftoverStarts {
    <# The other ObsidiNote starts on this computer (pure): powershell.exe processes whose command
       line holds THIS script's full path, never by a bare word or number, and never this process or
       one of its parents (after an update the old version waits as the parent of the new one).
       $Processes: @(@{ ProcessId; ParentProcessId; Name; CommandLine }) of every process. #>
    param([object[]]$Processes = @(), [Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][int]$SelfId)
    # The matches go out on the pipeline: wrap the call in @().
    if ($ScriptPath.Length -lt 8 -or -not [IO.Path]::IsPathRooted($ScriptPath)) { return }
    $byId = @{}
    foreach ($p in @($Processes | Where-Object { $_ })) { $byId[[int]$p.ProcessId] = $p }
    $mine = @{ $SelfId = $true }
    $at = $SelfId
    for ($i = 0; $i -lt 64 -and $byId.ContainsKey($at); $i++) {
        $at = [int]$byId[$at].ParentProcessId
        if ($at -le 0 -or $mine.ContainsKey($at)) { break }
        $mine[$at] = $true
    }
    $Processes | Where-Object {
        $_ -and "$($_.Name)" -eq 'powershell.exe' -and -not $mine.ContainsKey([int]$_.ProcessId) -and
        "$($_.CommandLine)".IndexOf($ScriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }
}

function Invoke-ReplaceRunning {
    <# A new start replaces the ObsidiNote that is running on this computer (D-032).
       When one answers on the port: ask it to stop (POST /api/shutdown; it gives its writer lease
       back and disconnects, as on Ctrl+C) and wait until the port is silent. When it does not stop
       (an older version has no such route, or it hangs): stop the leftover starts of this script
       (Get-LeftoverStarts; the process only, so ObsidiNote's Edge stays for the new start to use).
       Everything outside is injected, so this is tested without processes or sockets:
         $TestRunning { } -> $true while an ObsidiNote answers GET /api/status on the port
         $RequestStop { }  -> posts /api/shutdown (may throw)
         $GetProcesses { } -> every process as @{ ProcessId; ParentProcessId; Name; CommandLine }
         $StopProcess { param($ProcessId) }
         $Wait { param($Milliseconds) }
       Returns @{ found (one answered); replaced; stopped (processes stopped); noOtherHere (no other
       start of this script is left on this computer: the lease take-over may be used); status
       ('' = no line | OK | WARN); detail; hint }. Never throws. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][int]$SelfId,
        [Parameter(Mandatory)][scriptblock]$TestRunning, [Parameter(Mandatory)][scriptblock]$RequestStop,
        [Parameter(Mandatory)][scriptblock]$GetProcesses, [Parameter(Mandatory)][scriptblock]$StopProcess,
        [scriptblock]$Wait = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }, [int]$WaitSec = 10, [int]$StepMs = 250
    )
    $r = @{ found = $false; replaced = $false; stopped = 0; noOtherHere = $false; status = ''; detail = ''; hint = '' }
    $answers = { try { [bool](& $TestRunning) } catch { $false } }
    $silent = { param([int]$Sec) for ($i = 0; $i -lt [Math]::Ceiling($Sec * 1000 / $StepMs); $i++) { if (-not (& $answers)) { return $true }; & $Wait $StepMs }; -not (& $answers) }
    # @{ ok; list }: ok false when the process list could not be read (then nothing is assumed).
    $left = { try { @{ ok = $true; list = @(Get-LeftoverStarts -Processes @(& $GetProcesses) -ScriptPath $ScriptPath -SelfId $SelfId) } } catch { @{ ok = $false; list = @() } } }
    $why = ''
    $r.found = [bool](& $answers)
    if ($r.found) {
        try { $null = & $RequestStop } catch { $why = 'it did not take the request to stop' }
        if (& $silent $WaitSec) { $r.replaced = $true }
        else {
            if (-not $why) { $why = "it still answers after $WaitSec seconds" }
            $l = & $left
            foreach ($p in @($l.list)) { try { & $StopProcess ([int]$p.ProcessId); $r.stopped++ } catch { } }
            if ($r.stopped -and (& $silent 3)) { $r.replaced = $true }
        }
    }
    $l = & $left
    $r.noOtherHere = [bool]($l.ok -and -not @($l.list).Count -and -not ($r.found -and -not $r.replaced))
    if ($r.replaced) {
        $r.status = 'OK'
        $r.detail = 'replaced the ObsidiNote that was running' + $(if ($r.stopped) { ' (it did not stop by itself, so its process was ended)' } else { '' })
    } elseif ($r.found) {
        $r.status = 'WARN'
        $r.detail = "an earlier ObsidiNote did not stop: $why" + $(if (-not $r.stopped) { ', and its process was not found' } else { '' })
        $r.hint = 'Close the other ObsidiNote console window, then start ObsidiNote again.'
    } elseif (-not $l.ok) {
        $r.status = 'WARN'
        $r.detail = 'could not check whether another ObsidiNote runs on this PC (the process list could not be read)'
        $r.hint = 'A vault that an earlier run on this PC left open stays read only for up to 2 minutes.'
    } elseif (-not $r.noOtherHere) {
        $r.status = 'WARN'
        $r.detail = 'an earlier ObsidiNote start is still running on this PC (it does not answer yet)'
        $r.hint = 'It keeps the vault until it ends; this start is read only until then. Close the other ObsidiNote console window to take over.'
    }
    $r
}

Export-ModuleMember -Function Get-LeftoverStarts, Invoke-ReplaceRunning, Format-AppVersion, Get-UpdateStatus, Get-RelaunchArguments, Get-OneNoteStatus, Get-CopilotFailureHint
