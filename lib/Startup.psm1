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

Export-ModuleMember -Function Format-AppVersion, Get-UpdateStatus, Get-RelaunchArguments, Get-OneNoteStatus, Get-CopilotFailureHint
