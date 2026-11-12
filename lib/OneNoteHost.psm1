# OneNote at startup: is desktop OneNote running, start it when it is not, and wait until its
# COM API answers. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
# The side effects (process list, starting the exe, the COM probe) are parameters, so the tests
# run without OneNote.
Set-StrictMode -Version 2.0

function Get-OneNoteExePath {
    <# Desktop OneNote (Microsoft 365): the App Paths registration first, then the usual Office
       folders. '' when it is not installed (the old Store app has no COM API and does not count). #>
    [CmdletBinding()]
    param([string[]]$Candidates = @())
    $found = @()
    foreach ($hive in 'HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER') {
        $key = "Registry::$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ONENOTE.EXE"
        $p = try { (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'(default)' } catch { $null }
        if ($p) { $found += ([string]$p).Trim('"') }
    }
    if (-not $Candidates.Count) {
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ($pf) { $Candidates += (Join-Path $pf 'Microsoft Office\root\Office16\ONENOTE.EXE') }
        }
    }
    foreach ($p in @($found + $Candidates)) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
    }
    return ''
}

function Get-OneNoteState {
    <# 'window' = OneNote runs with a window the person can see; 'background' = only a COM
       instance without a window (OneNote started by another program); 'none' = not running.
       -Processes: objects with MainWindowHandle (tests pass stand-ins). #>
    [CmdletBinding()]
    param([object[]]$Processes = $null)
    if ($null -eq $Processes) { $Processes = @(Get-Process -Name ONENOTE -ErrorAction SilentlyContinue) }
    $list = @($Processes | Where-Object { $_ })
    if (-not $list.Count) { return 'none' }
    foreach ($p in $list) { if ([int64]$p.MainWindowHandle -ne 0) { return 'window' } }
    return 'background'
}

function Test-OneNoteComReady {
    <# True when OneNote's COM API answers a hierarchy call (the notebooks are loaded). #>
    [CmdletBinding()]
    param()
    try {
        $on = New-Object -ComObject OneNote.Application
        $xml = ''
        $on.GetHierarchy('', 0, [ref]$xml)
        return [bool]$xml
    } catch { return $false }
}

function Start-OneNoteIfNeeded {
    <# Makes sure desktop OneNote is running with a window and its COM API answers. Starts it
       (minimised) when it is not running or runs only in the background. Never throws: returns
       @{ ok; state; started; path; seconds; message } for the caller to report.
       -GetState, -Start and -Probe replace the real process list, start and COM call (tests). #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSec = 60,
        [int]$PollMs = 1000,
        [scriptblock]$GetState = { Get-OneNoteState },
        [scriptblock]$Start = { param($exe) Start-Process -FilePath $exe -WindowStyle Minimized },
        [scriptblock]$Probe = { Test-OneNoteComReady },
        [string]$ExePath = ''
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = [pscustomobject]@{ ok = $false; state = ''; started = $false; path = ''; seconds = 0; message = '' }
    try {
        $state = [string](& $GetState)
        $result.state = $state
        if ($state -ne 'window') {
            $exe = if ($ExePath) { $ExePath } else { Get-OneNoteExePath }
            $result.path = $exe
            if (-not $exe) {
                $result.message = 'Desktop OneNote (Microsoft 365) was not found. Install or repair Office, then start ObsidiNote again.'
                return $result
            }
            $null = & $Start $exe
            $result.started = $true
        }
        do {
            if (& $Probe) {
                $result.ok = $true
                $result.seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
                $result.message = if ($result.started) { "OneNote started and ready ($($result.seconds) s)." } else { 'OneNote is running and ready.' }
                return $result
            }
            Start-Sleep -Milliseconds $PollMs
        } while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec)
        $result.seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        $result.message = "OneNote did not answer within $TimeoutSec s. Open OneNote, check that it shows your notebooks (sign in if it asks), then start ObsidiNote again."
        return $result
    } catch {
        $result.seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        $result.message = "Starting OneNote failed: $($_.Exception.Message)"
        return $result
    }
}

Export-ModuleMember -Function Get-OneNoteExePath, Get-OneNoteState, Test-OneNoteComReady, Start-OneNoteIfNeeded
