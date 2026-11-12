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

function Get-OneNoteNotebooksXml {
    <# The open notebooks (GetHierarchy, scope hsNotebooks = 2, or -Scope 3 with their sections) as
       XML text; '' when COM does not answer. #>
    [CmdletBinding()]
    param([ValidateSet(2, 3)][int]$Scope = 2)
    try {
        $on = New-Object -ComObject OneNote.Application
        $xml = ''
        $on.GetHierarchy('', $Scope, [ref]$xml)
        return [string]$xml
    } catch { return '' }
}

function Find-NotebookInHierarchy {
    <# The notebook called $Name in GetHierarchy's XML: @{ name; path } or $null. Pure. #>
    [CmdletBinding()]
    param([string]$Xml, [string]$Name = 'ObsidiNote')
    if (-not $Xml) { return $null }
    try { [xml]$doc = $Xml } catch { return $null }
    foreach ($nb in @($doc.SelectNodes("//*[local-name()='Notebook']"))) {
        if ("$($nb.GetAttribute('name'))" -eq $Name -or "$($nb.GetAttribute('nickname'))" -eq $Name) {
            return [pscustomobject]@{ name = $Name; path = "$($nb.GetAttribute('path'))" }
        }
    }
    return $null
}

function ConvertTo-NotebookRecord {
    <# What a start opens to bring the notebook up: for a notebook in OneDrive or SharePoint
       (path https://...) its onenote: link; for a local one its .onetoc2 file ('Open Notebook.onetoc2'
       or the first .onetoc2 in the folder). '' when there is nothing to open. #>
    [CmdletBinding()]
    param([string]$Path)
    if (-not $Path) { return '' }
    if ($Path -match '^(?i)https?://') { return "onenote:$Path" }
    if ($Path -match '(?i)\.(onetoc2|one)$') { return $Path }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return '' }
    $toc = Join-Path $Path 'Open Notebook.onetoc2'
    if (Test-Path -LiteralPath $toc -PathType Leaf) { return $toc }
    $any = @(Get-ChildItem -LiteralPath $Path -Filter '*.onetoc2' -File -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($any) { return $any.FullName }
    return ''
}

function Test-NotebookRecord {
    <# Whether the record can be opened: an onenote:https:// link, or an existing .onetoc2/.one file. #>
    [CmdletBinding()]
    param([string]$Record)
    if (-not $Record) { return $false }
    if ($Record -match '^(?i)onenote:https?://') { return $true }
    ($Record -match '(?i)\.(onetoc2|one)$') -and (Test-Path -LiteralPath $Record -PathType Leaf)
}

function Wait-OneNoteReady {
    <# Polls until COM answers and (when $WantNotebook) the notebook is open. Returns @{ com; notebook }. #>
    param([scriptblock]$Probe, [scriptblock]$FindNotebook, [string]$Name, [bool]$WantNotebook, [Diagnostics.Stopwatch]$Watch, [int]$TimeoutSec, [int]$PollMs)
    $com = $false; $nb = $null
    do {
        if (-not $com) { $com = [bool](& $Probe) }
        if ($com) {
            $nb = & $FindNotebook $Name
            if ($nb -or -not $WantNotebook) { break }
        }
        Start-Sleep -Milliseconds $PollMs
    } while ($Watch.Elapsed.TotalSeconds -lt $TimeoutSec)
    [pscustomobject]@{ com = $com; notebook = $nb }
}

function Start-OneNoteIfNeeded {
    <# Makes sure desktop OneNote is running with a window, its COM API answers and ObsidiNote's
       notebook is open. When OneNote is not running (or only in the background) it OPENS THE
       NOTEBOOK ON RECORD ($Record: config "notebook"), so OneNote starts through the file-type or
       onenote: link association with that notebook; without a usable record it starts the exe and
       says so (warn). A running OneNote without the notebook gets the record opened too.
       Never throws: returns @{ ok; state; started; how; path; seconds; notebookOpen; foundRecord;
       warn; message }. foundRecord is the record for the notebook found (to save when it differs).
       -GetState, -Start, -OpenRecord, -Probe and -FindNotebook replace the real process list, exe
       start, Start-Process on the record, COM call and notebook lookup (tests). #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSec = 60,
        [int]$PollMs = 1000,
        [string]$Record = '',
        [string]$NotebookName = 'ObsidiNote',
        [scriptblock]$GetState = { Get-OneNoteState },
        [scriptblock]$Start = { param($exe) Start-Process -FilePath $exe -WindowStyle Minimized },
        [scriptblock]$OpenRecord = { param($rec) Start-Process -FilePath $rec },
        [scriptblock]$Probe = { Test-OneNoteComReady },
        [scriptblock]$FindNotebook = { param($name) Find-NotebookInHierarchy -Xml (Get-OneNoteNotebooksXml) -Name $name },
        [string]$ExePath = ''
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = [pscustomobject]@{ ok = $false; state = ''; started = $false; how = ''; path = ''; seconds = 0; notebookOpen = $false; foundRecord = ''; warn = ''; message = '' }
    try {
        $usable = Test-NotebookRecord $Record
        $result.state = [string](& $GetState)
        if ($result.state -ne 'window') {
            if ($usable) {
                $null = & $OpenRecord $Record
                $result.how = 'record'
            } else {
                $exe = if ($ExePath) { $ExePath } else { Get-OneNoteExePath }
                $result.path = $exe
                if (-not $exe) {
                    $result.message = 'Desktop OneNote (Microsoft 365) was not found. Install or repair Office, then start ObsidiNote again.'
                    return $result
                }
                $null = & $Start $exe
                $result.how = 'exe'
                $result.warn = if ($Record) { "the notebook on record cannot be opened (moved or deleted?); started OneNote itself" } else { "no notebook on record yet; started OneNote itself" }
            }
            $result.started = $true
        }
        $wait = Wait-OneNoteReady -Probe $Probe -FindNotebook $FindNotebook -Name $NotebookName -WantNotebook $usable -Watch $sw -TimeoutSec $TimeoutSec -PollMs $PollMs
        if ($wait.com -and -not $wait.notebook -and $usable -and $result.how -ne 'record') {
            # OneNote runs, but without ObsidiNote's notebook: open it from the record.
            $null = & $OpenRecord $Record
            $result.how = 'record'
            $wait = Wait-OneNoteReady -Probe $Probe -FindNotebook $FindNotebook -Name $NotebookName -WantNotebook $true -Watch $sw -TimeoutSec $TimeoutSec -PollMs $PollMs
        }
        $result.seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        if (-not $wait.com) {
            $result.message = "OneNote did not answer within $TimeoutSec s. Open OneNote, check that it shows your notebooks (sign in if it asks), then start ObsidiNote again."
            return $result
        }
        $result.ok = $true
        if ($wait.notebook) {
            $result.notebookOpen = $true
            $result.foundRecord = ConvertTo-NotebookRecord $wait.notebook.path
            $result.message = "running, notebook $(if ("$($wait.notebook.name)") { $wait.notebook.name } else { $NotebookName }) open"
        } else {
            $result.message = "running; notebook $NotebookName is not open$(if ($usable) { ' (opening it from the record did not work in time)' } else { ' (not created yet, or opened under another name)' })"
        }
        return $result
    } catch {
        $result.seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        $result.message = "Starting OneNote failed: $($_.Exception.Message)"
        return $result
    }
}

Export-ModuleMember -Function Get-OneNoteExePath, Get-OneNoteState, Test-OneNoteComReady, Get-OneNoteNotebooksXml, Find-NotebookInHierarchy, ConvertTo-NotebookRecord, Test-NotebookRecord, Start-OneNoteIfNeeded
