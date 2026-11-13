#requires -Version 5.1
# The start, in this order; each step prints one status line ([OK]/[WARN]/[FAIL], lib/Status.psm1):
#   1. Update: check for a new release; when one was installed, start the new version instead
#      (same arguments) and end this one.
#   2. This computer: PowerShell, OneNote, Edge and its policies, the debug port, the Edge profile's
#      sign-in and single sign-on, GitHub. A FAIL ends the start with what to do (exit 1).
#   3. OneNote: open the notebook on record (or start OneNote) and wait for its COM API (exit 2).
#      Then the vault: continue in the vault on record (else the only one), take its writer lease
#      (or run read only), check the index against the notebook (a WARN, never a stop).
#   4. Microsoft 365 Copilot in ObsidiNote's own Edge profile (exit 3).
#   5. The interface: the local server on 127.0.0.1:<uiPort> (8767 by default) and its window in
#      ObsidiNote's Edge (exit 4 when the server cannot start). Then it keeps running until the
#      console window is closed or Ctrl+C is pressed.
# Status lines and messages go to stderr.
[CmdletBinding()]
param(
    [switch]$NoUpdate,  # skip the update check (also: environment variable OBSIDINOTE_NO_UPDATE=1)
    [switch]$NoOneNote,  # skip the OneNote start and check (tests, update-only runs)
    [switch]$NoCopilot,  # skip connecting to Microsoft 365 Copilot (also: OBSIDINOTE_NO_COPILOT=1)
    [switch]$NoWindow    # start the interface's server without opening a window (also: OBSIDINOTE_NO_WINDOW=1)
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell's own module paths: started from PowerShell 7, 5.1 would load 7's modules.
$env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')) | Where-Object { $_ }) -join ';'
if ($env:OBSIDINOTE_NO_UPDATE -eq '1') { $NoUpdate = $true }
if ($env:OBSIDINOTE_NO_COPILOT -eq '1') { $NoCopilot = $true }
if ($env:OBSIDINOTE_NO_WINDOW -eq '1') { $NoWindow = $true }
$bound = @{}; foreach ($k in $PSBoundParameters.Keys) { $bound[$k] = $PSBoundParameters[$k] }
Import-Module (Join-Path $PSScriptRoot 'lib\Status.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Startup.psm1') -Force
function Say([string]$Text) { [Console]::Error.WriteLine("[ObsidiNote] $Text") }

# --- 1. Update -------------------------------------------------------------------------------
# Before anything else is loaded (GitHub; skipped offline, for local edits or "autoUpdate": false).
# The updater never fails this script; -PassThru hands back its outcome for the status line.
[Console]::Error.WriteLine('Update')
if ($env:OBSIDINOTE_UPDATED) {
    # Started by the previous version right after it installed this one.
    Write-Status -ToError 'OK' 'Update' "$env:OBSIDINOTE_UPDATED; this is the new version"
    Remove-Item Env:\OBSIDINOTE_UPDATED -ErrorAction SilentlyContinue
} elseif ($NoUpdate) {
    Write-Status -ToError 'OK' 'Update' 'not checked (-NoUpdate or OBSIDINOTE_NO_UPDATE=1)'
} else {
    $updateResult = @(& (Join-Path $PSScriptRoot 'tools\update.ps1') -PassThru) | Where-Object { $_ -and $_.PSObject.Properties['outcome'] } | Select-Object -Last 1
    $u = Get-UpdateStatus $updateResult
    Write-Status -ToError $u.status 'Update' $u.detail
    if ($u.relaunch) {
        # The files on disk are the new version now: run it (same arguments) and end this one.
        $env:OBSIDINOTE_UPDATED = "$(if ($updateResult.outcome -eq 'repaired') { 'repaired' } else { 'updated' }) $($updateResult.detail)"
        $relaunch = Get-RelaunchArguments -Script $PSCommandPath -Bound $bound
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @relaunch } finally { $ErrorActionPreference = $eap }
        exit $LASTEXITCODE
    }
}
# Is the app folder the release as shipped (manifest.json)? An update that stopped halfway leaves
# files missing or of another version: repair it once (the same version again), else say so.
try {
    Import-Module (Join-Path $PSScriptRoot 'lib\Update.psm1') -Force
    $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
    if ($installProblem) {
        Write-Status -ToError 'WARN' 'Install' $installProblem
        if (-not $NoUpdate) {
            & (Join-Path $PSScriptRoot 'tools\update.ps1') -Repair
            $installProblem = Format-InstallProblem (Test-InstallIntegrity $PSScriptRoot)
            if (-not $installProblem) { Write-Status -ToError 'OK' 'Install' 'repaired' }
        }
    }
} catch { Write-Status -ToError 'WARN' 'Install' "not checked: $($_.Exception.Message)" }

# --- 2. This computer --------------------------------------------------------------------------
[Console]::Error.WriteLine('This computer')
Import-Module (Join-Path $PSScriptRoot 'lib\StartChecks.psm1') -Force
$checks = Get-StartChecks -AppRoot $PSScriptRoot -NoOneNote:$NoOneNote -NoCopilot:$NoCopilot
foreach ($c in $checks) { Write-Status -ToError $c.status $c.name $c.detail -Hint $(if ($c.status -ne 'OK' -or $c.name -eq 'Edge profile') { $c.hint } else { '' }) }
if (@($checks | Where-Object { $_.status -eq 'FAIL' }).Count) {
    Say 'ObsidiNote cannot start until the FAIL items above are fixed.'
    exit 1
}

# --- 3. OneNote --------------------------------------------------------------------------------
# OneNote is the only store. When it is not running, ObsidiNote opens the notebook on record
# ("notebook" in config\obsidinote.local.json), so OneNote starts with that notebook open; the
# record is filled in once the notebook is found.
[Console]::Error.WriteLine('Starting')
if (-not $NoOneNote) {
    Import-Module (Join-Path $PSScriptRoot 'lib\AppConfig.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\OneNoteHost.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\NotebookView.psm1') -Force
    $record = Get-NotebookRecord -AppRoot $PSScriptRoot
    # The vault to continue in (FEASIBILITY.md, "Several ObsidiNote vaults"): the notebook on record
    # (the last active vault, set by the window's vault switcher), else one named ObsidiNote or with
    # a 00 Index section. Found by structure, so a vault may have any name.
    $vaultRecord = if (Test-NotebookRecord $record) { $record } else { '' }
    # No GetNewClosure: the block runs in this script's session state, where $vaultRecord and the
    # imported commands are visible (a closure would lose the imported commands).
    $findVault = { param($name) Find-VaultInHierarchy -Xml (Get-OneNoteNotebooksXml -Scope 3) -Record $vaultRecord -Name $name }
    $oneNote = Start-OneNoteIfNeeded -Record $record -FindNotebook $findVault
    if ($oneNote.foundRecord -and $oneNote.foundRecord -ne $record) {
        try { Set-LocalAppValue $PSScriptRoot 'notebook' $oneNote.foundRecord; $oneNote.warn = '' } catch { $oneNote.warn = "the notebook's location could not be saved: $($_.Exception.Message)" }
    }
    $on = Get-OneNoteStatus $oneNote
    Write-Status -ToError $on.status 'OneNote' $on.detail -Hint $on.hint
    if ($on.status -eq 'FAIL') { exit 2 }
}

# --- 3b. The vault --------------------------------------------------------------------------------
# The ObsidiNote vault to continue in (FEASIBILITY.md, Several ObsidiNote vaults), found by its state
# page: the vault on record ("vaultId", else the "notebook" record), else the only one open, else none
# (the window then offers "New ObsidiNote vault"). Opening it sets the write guard's root, takes the
# vault's writer lease (or runs read only while another ObsidiNote writes there), brings the fixed
# structure up to date and checks the index against the notebook (missing pages go to Unfiled).
$mainAdapter = $null; $vaultOpen = $null
Import-Module (Join-Path $PSScriptRoot 'lib\WriterLease.psm1') -Force
$sessionId = New-WriterSessionId
if (-not $NoOneNote) {
    Import-Module (Join-Path $PSScriptRoot 'lib\OneNote.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\Vault.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\VaultSession.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\Update.psm1') -Force
    try {
        $mainAdapter = Get-OneNoteAdapter
        $vaults = @(Get-VaultList -Adapter $mainAdapter)
        $notebooks = @(Get-NotebookList -Adapter $mainAdapter -Vaults $vaults)
        $pick = Select-StartVault -Vaults $vaults -RecordVaultId "$(Get-AppSetting -Key 'vaultId' -Default '' -AppRoot $PSScriptRoot)" -Record (Get-NotebookRecord -AppRoot $PSScriptRoot) -Notebooks $notebooks
        if ($pick.vault) {
            $vaultOpen = Open-VaultSession -Adapter $mainAdapter -Vault $pick.vault -SessionId $sessionId -Vaults $vaults
            try {
                if ("$(Get-AppSetting -Key 'vaultId' -Default '' -AppRoot $PSScriptRoot)" -ne $vaultOpen.vault.vaultId) { Set-LocalAppValue $PSScriptRoot 'vaultId' $vaultOpen.vault.vaultId }
            } catch { }
        }
        $vs = Format-VaultStatus -Open $vaultOpen -Why $pick.why -VaultCount $vaults.Count
    } catch { $vs = Format-VaultStatus -Open $null -Problem $_.Exception.Message }
    Write-Status -ToError $vs.status 'Vault' $vs.detail -Hint $vs.hint
}
function Close-ObsidiVaultLease($State) {
    # Gives the writer lease back (only when it is still this session's); never throws.
    if (-not $mainAdapter) { return }
    $v = if ($State) { $State.Vault } elseif ($vaultOpen) { $vaultOpen.vault } else { $null }
    $l = if ($State) { $State.Lease } elseif ($vaultOpen) { $vaultOpen.lease } else { $null }
    try { $null = Close-VaultSession -Adapter $mainAdapter -Vault $v -Lease $l } catch { }
}

# --- 4. Microsoft 365 Copilot and the interface -----------------------------------------------
# Copilot in ObsidiNote's own Edge window (debug port "cdpPort", 9334 by default; profile
# %LOCALAPPDATA%\ObsidiNote\edge-profile; "signIn" single-sign-on or private). Connect-Copilot waits
# up to 300 s for a sign-in. Without Copilot ObsidiNote cannot classify or link: exit 3.
$copilot = $null
if (-not $NoCopilot) {
    Import-Module (Join-Path $PSScriptRoot 'lib\CopilotBridge.psm1') -Force
    # Edge policy BrowserSignin = 2 and ObsidiNote's Edge profile not signed in yet: Edge closes the
    # Copilot window at once. Let Edge run its own sign-in first (one time), then connect.
    Import-Module (Join-Path $PSScriptRoot 'lib\Cdp.psm1') -Force
    $cs = Get-CopilotSettings
    if ((Test-EdgeForcedSignIn) -and (Get-EdgeProfileAccount -ProfileDir $cs.profileDir) -ne 'work') {
        $signIn = Invoke-EdgeProfileSignIn -ProfileDir $cs.profileDir -Port ([int]$cs.cdpPort) -OnWait {
            Write-Status -ToError 'WARN' 'Edge sign-in' 'one time: sign in to Edge with your work account' -Hint 'Edge on this PC requires it. In the Edge window that just opened, sign in with your work account (waiting up to 5 minutes; ObsidiNote continues by itself).'
        }
        Write-Status -ToError $(if ($signIn.ok) { 'OK' } else { 'FAIL' }) 'Edge sign-in' $signIn.detail
        if (-not $signIn.ok) { exit 3 }
    }
    Say 'Opening Microsoft 365 Copilot in ObsidiNote''s Edge window...'
    try { $copilot = Connect-Copilot }
    catch {
        $why = $_.Exception.Message
        $sso = ''
        try { Import-Module (Join-Path $PSScriptRoot 'lib\Sso.psm1') -Force; $sso = Get-ProfileSsoState } catch { }
        Write-Status -ToError 'FAIL' 'Copilot' $why -Hint (Get-CopilotFailureHint -Message $why -Sso $sso)
        exit 3
    }
    Write-Status -ToError 'OK' 'Copilot' "connected in ObsidiNote's Edge window (port $($copilot.Port))"
}

# --- 5. The interface --------------------------------------------------------------------------
# The local server (lib/Server.psm1) on 127.0.0.1:<uiPort> serves ui\ (prebuilt; no Node here) and
# the API; its window opens in ObsidiNote's Edge (lib/AppWindow.psm1). The process then keeps
# running: the Copilot bridge stays connected, and closing this console (or Ctrl+C) stops it all.
Import-Module (Join-Path $PSScriptRoot 'lib\AppConfig.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Server.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\AppWindow.psm1') -Force
try { $uiPort = Get-UiPort -AppRoot $PSScriptRoot; $cs = Get-CopilotSettings -AppRoot $PSScriptRoot }
catch { Write-Status -ToError 'FAIL' 'ObsidiNote' $_.Exception.Message; exit 4 }
$url = "http://127.0.0.1:$uiPort"

function Open-ObsidiNoteWindow {
    if ($NoWindow) { return 'none' }
    if ($copilot) {
        try { return (Open-AppInEdgeWindow -Url "$url/" -AppPort $uiPort -CdpPort ([int]$cs.cdpPort)) } catch { }
    }
    Start-AppInEdgeProfile -Url "$url/" -AppPort $uiPort -CdpPort ([int]$cs.cdpPort) -ProfileDir $cs.profileDir
}

$server = $null
try {
    # The server's runspace gets the active vault's records (plain values), the index working copy
    # built just now, and the Copilot bridge; it opens its own guarded OneNote adapter.
    $vRec = $null; $lRec = $null; $model = $null
    if ($vaultOpen) { $vRec = $vaultOpen.vault; $lRec = $vaultOpen.lease; $model = $vaultOpen.model }
    $state = New-ServerState -AppRoot $PSScriptRoot -Port $uiPort -CdpPort ([int]$cs.cdpPort) -CopilotSkipped ([bool]$NoCopilot) -Copilot $copilot -Vault $vRec -Lease $lRec -SessionId $sessionId -Model $model
    $server = Start-UiServer -Port $uiPort -UiDir (Join-Path $PSScriptRoot 'ui') -State $state
} catch {
    $why = $_.Exception.Message
    Close-ObsidiVaultLease $null
    if (Test-UiServerRunning -Port $uiPort) {
        # Another ObsidiNote already serves this port: show its window and leave that one running.
        $how = Open-ObsidiNoteWindow
        Write-Status -ToError 'OK' 'ObsidiNote' "already running at $url; $(Get-AppWindowDetail $how)"
        if ($copilot) { try { Disconnect-Copilot $copilot } catch { } }
        exit 0
    }
    Write-Status -ToError 'FAIL' 'ObsidiNote' "the interface could not start on port ${uiPort}: $why" -Hint 'Another program may use this port. Choose another one: { "uiPort": 8790 } in config\obsidinote.local.json.'
    if ($copilot) { try { Disconnect-Copilot $copilot } catch { } }
    exit 4
}

try {
    $how = 'none'
    try { $how = Open-ObsidiNoteWindow } catch { Write-Status -ToError 'WARN' 'Window' "could not open: $($_.Exception.Message)" -Hint "Open $url in Edge yourself." }
    Write-Status -ToError 'OK' 'ObsidiNote' "open at $url" -Hint (Get-AppWindowDetail $how)
    Say 'Close this window to stop ObsidiNote (or press Ctrl+C).'
    # Ctrl+C ends this wait and runs the finally block; closing the console ends the process.
    # Meanwhile the writer lease is renewed (every 60 s, valid 120 s) for whichever vault is active
    # now (the window can switch vault); the lock keeps this apart from the server's own lease writes.
    $renewSec = if ($mainAdapter) { (Get-LeaseTimings).renewEverySec } else { 0 }
    $renew = [Diagnostics.Stopwatch]::StartNew()
    while (-not $server.Async.IsCompleted) {
        Start-Sleep -Milliseconds 500
        if (-not $renewSec -or $renew.Elapsed.TotalSeconds -lt $renewSec) { continue }
        $renew.Restart()
        [Threading.Monitor]::Enter($state.Lock)
        try {
            if ($state.Vault) {
                $was = if ($state.Lease) { $state.Lease.mode } else { '' }
                $state.Lease = Update-SessionLease -Adapter $mainAdapter -Vault $state.Vault -SessionId $state.SessionId -Lease $state.Lease
                $now = if ($state.Lease) { $state.Lease.mode } else { 'readonly' }
                if ($was -and $now -ne $was) {
                    if ($now -eq 'writer') { Write-Status -ToError 'OK' 'Vault' "$($state.Vault.name): this ObsidiNote is the writer now" }
                    else { Write-Status -ToError 'WARN' 'Vault' "$($state.Vault.name): read only now; the writer lease could not be renewed" -Hint 'Another ObsidiNote may have taken over. Adding waits until this one is the writer again.' }
                }
            }
        } finally { [Threading.Monitor]::Exit($state.Lock) }
    }
    Write-Status -ToError 'WARN' 'ObsidiNote' 'the interface''s server stopped' -Hint 'Start ObsidiNote again.'
} finally {
    Stop-UiServer $server
    Close-ObsidiVaultLease $state
    if ($copilot) { try { Disconnect-Copilot $copilot } catch { } }
    Say 'ObsidiNote stopped.'
}
