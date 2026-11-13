# The interface's local web server: serves the prebuilt interface from ui\ and a small JSON API.
# Windows PowerShell 5.1, System.Net.HttpListener; the request loop runs in its own runspace, so
# obsidinote.ps1 keeps its console (Ctrl+C, closing the window) and the Copilot bridge.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
#
# Security (the same model as the sister project's server, rewritten for ObsidiNote):
#   - Listens on 127.0.0.1 / localhost only, and answers only loopback clients.
#   - Host header must be 127.0.0.1, localhost or [::1] with this port (stops DNS rebinding).
#   - An Origin header, when sent, must be exactly http://127.0.0.1|localhost|[::1]:<port>; never
#     a prefix match (localhost.evil.example, localhost@evil.example, https://localhost, null fail).
#   - Every /api/ request carries "X-ObsidiNote: 1": a page on another site cannot add that header
#     without a CORS preflight, which this server never answers.
#   - Static files only through an allow-list built from the files in ui\ at start (known web
#     types only), never a directory mount: ..\, .ps1 and config files are 404.
# OneNote is the only store: the server writes nothing to disk (tests/NoContentOnDisk.Tests.ps1);
# notebook titles only go to the local interface, never to the log.
Set-StrictMode -Version 2.0

$script:Here = $PSScriptRoot
# Update.psm1 for Set-LocalAppValue only: the active vault's record ("notebook") is a setting in
# config\obsidinote.local.json, the one file this server changes (no content, FEASIBILITY.md).
# Vaults, index, store and the Add/Ask handlers: lib/VaultSession.psm1, VaultStore, AskSources,
# GraphModel, Ingest, Ask (and the step-2 modules they import). Status for the [WARN] line of a new vault.
foreach ($m in 'Log', 'AppConfig', 'Startup', 'Intent', 'OneNoteHost', 'NotebookView', 'Update', 'Status', 'OneNote', 'PageMeta', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'AskSources', 'GraphModel', 'Ingest', 'Ask') {
    Import-Module (Join-Path $PSScriptRoot "$m.psm1")
}

$script:Mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.woff2' = 'font/woff2'
}

# The page loads nothing from elsewhere and cannot be framed.
$script:PagePolicy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

$script:MaxBodyBytes = 1048576

# --- Checks (pure) ---------------------------------------------------------------------------

function Get-AllowedOrigins([int]$Port) { , @("http://127.0.0.1:$Port", "http://localhost:$Port", "http://[::1]:$Port") }

function Test-AllowedOrigin([string]$Origin, [int]$Port) {
    <# True only for exactly http://127.0.0.1:<port>, http://localhost:<port> or http://[::1]:<port>. #>
    if (-not $Origin) { return $false }
    foreach ($o in (Get-AllowedOrigins $Port)) { if ([string]::Equals($Origin, $o, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}

function Test-AllowedHost([string]$HostHeader, [int]$Port) {
    <# True only for the Host header 127.0.0.1:<port>, localhost:<port> or [::1]:<port>. #>
    if (-not $HostHeader) { return $false }
    foreach ($h in "127.0.0.1:$Port", "localhost:$Port", "[::1]:$Port") { if ([string]::Equals($HostHeader, $h, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}

function Get-RequestVerdict {
    <# Whether a request may be served: $null when yes, else @{ status; error }. Pure. #>
    param([string]$Method, [string]$Path, [string]$HostHeader, [string]$Origin, [string]$AppHeader, [bool]$Loopback, [int]$Port)
    if (-not $Loopback) { return @{ status = 403; error = 'Only this computer may use ObsidiNote.' } }
    if (-not (Test-AllowedHost $HostHeader $Port)) { return @{ status = 403; error = 'Unknown host.' } }
    if ($Origin -and -not (Test-AllowedOrigin $Origin $Port)) { return @{ status = 403; error = 'Only the ObsidiNote page may do this.' } }
    $api = $Path.StartsWith('/api/')
    if ($Method -ne 'GET' -and -not ($api -and $Method -eq 'POST')) { return @{ status = 405; error = 'Method not allowed.' } }
    if ($api -and $AppHeader -ne '1') { return @{ status = 403; error = 'Only the ObsidiNote page may do this.' } }
    $null
}

function Get-UiAllowList {
    <# The files the server may send: @{ '/<path>' = full path } for every file of a known web type
       in $UiDir (no dot-files), plus '/' for index.html. Built once at start; a request for
       anything else is 404. Keys compare case-insensitively. #>
    param([Parameter(Mandatory)][string]$UiDir)
    $map = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $base = [IO.Path]::GetFullPath($UiDir).TrimEnd('\')
    if (-not [IO.Directory]::Exists($base)) { return , $map }
    foreach ($f in [IO.Directory]::EnumerateFiles($base, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($base.Length + 1).Replace('\', '/')
        if (@($rel.Split('/') | Where-Object { $_.StartsWith('.') }).Count) { continue }
        if (-not $script:Mime.ContainsKey([IO.Path]::GetExtension($f).ToLowerInvariant())) { continue }
        $map['/' + $rel] = $f
    }
    if ($map.ContainsKey('/index.html')) { $map['/'] = $map['/index.html'] }
    , $map
}

function Get-CopilotTabState {
    <# From CDP's /json/list pages: 'connected' when a page is on a Copilot host, else 'no-tab'. Pure. #>
    param([object[]]$Pages, [string[]]$Hosts)
    foreach ($p in @($Pages | Where-Object { $_ -and "$($_.type)" -eq 'page' })) {
        $h = try { ([uri]"$($p.url)").Host.ToLowerInvariant() } catch { '' }
        if ($h -and @($Hosts | Where-Object { $_ -and ($h -eq $_ -or $h.EndsWith(".$_")) }).Count) { return 'connected' }
    }
    'no-tab'
}

# --- What the API reports ---------------------------------------------------------------------

function New-ServerState {
    <# The shared state of one server (it crosses into the server's runspace): plain values, plus the
       Copilot bridge object (no scriptblocks). Vault and Lease are the active vault's records
       (lib/VaultSession.psm1), set by the start and by a vault switch; Lock serialises the lease
       writes of the start's renewal and the server's switch.
       -FakeStatus replaces /api/status; -FakeHierarchyXml replaces OneNote with a read-only stand-in
       made from that XML (New-XmlOneNoteAdapter, OneNote counts as running), so the tests run the
       real parsing. -TestAdapter / -TestCopilot: in-process tests of Invoke-ApiRoute only (objects
       with scriptblocks; never with Start-UiServer). #>
    param([Parameter(Mandatory)][string]$AppRoot, [int]$Port, [int]$CdpPort = 9334, [bool]$CopilotSkipped = $false,
        $FakeStatus = $null, [string]$FakeHierarchyXml = '', $Copilot = $null, $Vault = $null, $Lease = $null, [string]$SessionId = '',
        $Model = $null, $TestAdapter = $null, $TestCopilot = $null)
    $h = [hashtable]::Synchronized(@{})
    $h.AppRoot = $AppRoot; $h.Port = $Port; $h.CdpPort = $CdpPort; $h.CopilotSkipped = $CopilotSkipped
    $h.FakeStatus = $FakeStatus; $h.FakeHierarchyXml = $FakeHierarchyXml
    $h.Copilot = $Copilot; $h.Vault = $Vault; $h.Lease = $Lease; $h.Model = $Model
    $h.SessionId = $(if ($SessionId) { $SessionId } else { New-WriterSessionId })
    $h.TestAdapter = $TestAdapter; $h.TestCopilot = $TestCopilot
    $h.Lock = New-Object object
    $h.Id = [guid]::NewGuid().ToString('N')
    $h.Stop = $false
    $h
}

function Get-AppVersionText([string]$AppRoot) {
    $f = Join-Path $AppRoot 'version.txt'
    $v = if (Test-Path -LiteralPath $f) { ([IO.File]::ReadAllText($f)).Trim() } else { '' }
    Format-AppVersion $v
}

function Get-CopilotHostList([string]$AppRoot) {
    $sel = Get-AppConfig -Name 'selectors' -AppRoot $AppRoot
    $hosts = @()
    if ($sel.PSObject.Properties['chatHosts']) { $hosts += @($sel.chatHosts) }
    if ($sel.PSObject.Properties['chatUrl'] -and $sel.chatUrl) { try { $hosts += ([uri]"$($sel.chatUrl)").Host -replace '^www\.', '' } catch { } }
    , @($hosts | Where-Object { $_ } | ForEach-Object { "$_".ToLowerInvariant() } | Select-Object -Unique)
}

function Test-BridgeOpen($Bridge) {
    <# True while the start's Copilot bridge still has an open connection to its Copilot tab. Pure. #>
    if (-not $Bridge -or -not $Bridge.PSObject.Properties['Session'] -or -not $Bridge.Session) { return $false }
    $s = $Bridge.Session
    if ($s.PSObject.Properties['Lost'] -and $s.Lost) { return $false }
    try { return ("$($s.Ws.State)" -eq 'Open') } catch { return $false }
}

function Get-CopilotState($State) {
    <# Read-only; never attaches to a tab. The bridge's own open connection is the answer when there
       is one: the tab's address can be on a host the list below does not know (a tenant redirect),
       which made the window say "Copilot is not open" while it was connected (v0.4.0, 2026-11-13).
       Without a bridge it lists the pages of ObsidiNote's Edge on its debug port. #>
    if ($State.CopilotSkipped) { return 'skipped' }
    if (Test-BridgeOpen $State.Copilot) { return 'connected' }
    try { $pages = @(Invoke-RestMethod "http://127.0.0.1:$($State.CdpPort)/json/list" -TimeoutSec 2) } catch { return 'not-running' }
    $flat = @(foreach ($p in $pages) { $p })   # PS 5.1 hands a JSON array over as one object
    Get-CopilotTabState -Pages $flat -Hosts (Get-CopilotHostList $State.AppRoot)
}

# --- OneNote, vaults and the active vault ---------------------------------------------------------

$script:NotRunning = 'OneNote is not running. Start OneNote, or start ObsidiNote again.'
$script:NoAnswer = 'OneNote did not answer. Check that OneNote is open, then try again.'
$script:NoVault = 'No ObsidiNote vault is active. Make one with "New ObsidiNote vault", or open a notebook that holds one.'
$script:CacheMs = 3000
# Runspace-local state (the server's runspace imports this module itself): the COM adapter, the
# active vault's working copy of the index, Ask's sources per conversation, connected notebooks.
$script:ComAdapter = $null
$script:XmlAdapter = $null
$script:XmlAdapterSource = ''
$script:VaultCache = $null
$script:Model = $null
$script:ModelKey = ''
$script:AskConversations = @{}
$script:ForeignCache = @{}

function Get-ServerAdapter($State) {
    <# The guarded OneNote adapter of this runspace; $null when OneNote is not running (a COM call
       would start it). Fake mode: the read-only stand-in from the XML. #>
    if ($State.TestAdapter) { return $State.TestAdapter }
    if ($State.FakeHierarchyXml) {
        if (-not $script:XmlAdapter -or $script:XmlAdapterSource -ne $State.FakeHierarchyXml) {
            $script:XmlAdapter = New-GuardedOneNote -Inner (New-XmlOneNoteAdapter -Xml $State.FakeHierarchyXml)
            $script:XmlAdapterSource = $State.FakeHierarchyXml
            $script:VaultCache = $null
        }
        return $script:XmlAdapter
    }
    if ((Get-OneNoteState) -eq 'none') { $script:ComAdapter = $null; return $null }
    if (-not $script:ComAdapter) { $script:ComAdapter = Get-OneNoteAdapter }
    $script:ComAdapter
}

function Reset-VaultCache { $script:VaultCache = $null }

function Get-VaultData($State, [switch]$Fresh) {
    <# @{ adapter; vaults (Get-VaultList); notebooks (Get-NotebookList); message }. Cached for a few
       seconds (the window asks for the list and the status often). Read only. #>
    $c = $script:VaultCache
    if (-not $Fresh -and $c -and $c.at.ElapsedMilliseconds -lt $script:CacheMs -and $c.key -eq $State.Id) { return $c.data }
    $data = @{ adapter = $null; vaults = @(); notebooks = @(); message = '' }
    try {
        $ad = Get-ServerAdapter $State
        if (-not $ad) { $data.message = $script:NotRunning; return $data }
        $data.adapter = $ad
        $data.vaults = @(Get-VaultList -Adapter $ad)
        $data.notebooks = @(Get-NotebookList -Adapter $ad -Vaults $data.vaults)
        if (-not $data.notebooks.Count) { $data.message = 'No notebooks are open in OneNote.' }
    } catch {
        $script:ComAdapter = $null
        $data.message = $script:NoAnswer
        return $data
    }
    $script:VaultCache = @{ at = [Diagnostics.Stopwatch]::StartNew(); key = $State.Id; data = $data }
    $data
}

function Get-ActiveVaultItem($State, $Data) {
    <# The active vault among the open ones: the one the start (or a switch) opened; while none is
       open, the one a start would pick (record, else the only vault). Read only. #>
    if ($State.Vault) {
        $v = @($Data.vaults | Where-Object { $_.vaultId -eq $State.Vault.vaultId }) | Select-Object -First 1
        if ($v) { return $v }
    }
    $rid = "$(Get-AppSetting -Key 'vaultId' -Default '' -AppRoot $State.AppRoot)"
    (Select-StartVault -Vaults $Data.vaults -RecordVaultId $rid -Record (Get-NotebookRecord -AppRoot $State.AppRoot) -Notebooks $Data.notebooks).vault
}

function Get-LeaseMode($State) { if ($State.Vault -and $State.Lease -and (Test-WriterLease $State.Lease)) { 'writer' } elseif ($State.Vault) { 'readonly' } else { 'none' } }

function Get-VaultListId($Vault) { if ($Vault.rootKind -eq 'notebook') { [string]$Vault.notebookId } else { [string]$Vault.rootId } }

function ConvertTo-NotebookListing {
    <# The switcher's list (pure): vaults first (one entry per vault: a whole notebook, or a section
       group inside one), then the open notebooks that are not a vault root, read only.
       @( @{ id; name; vault; active; location; vaultId; kind; notebookId } ). #>
    param([object[]]$Vaults = @(), [object[]]$Notebooks = @(), [string]$ActiveVaultId = '')
    $out = @(foreach ($v in @($Vaults)) {
        $nb = @($Notebooks | Where-Object { $_.id -eq $v.notebookId }) | Select-Object -First 1
        $loc = if ($nb) { Get-NotebookLocationLabel $nb.location } else { Get-NotebookLocationLabel $v.location }
        $name = if ($v.rootKind -eq 'sectiongroup') { "$($v.name) (in $($v.notebookName))" } else { [string]$v.name }
        [pscustomobject]@{ id = (Get-VaultListId $v); name = $name; vault = $true; active = ($ActiveVaultId -and $v.vaultId -eq $ActiveVaultId); location = $loc; vaultId = [string]$v.vaultId; kind = [string]$v.rootKind; notebookId = [string]$v.notebookId }
    })
    $out += @(foreach ($n in @($Notebooks | Where-Object { -not $_.structured })) {
        [pscustomobject]@{ id = [string]$n.id; name = [string]$n.name; vault = $false; active = $false; location = (Get-NotebookLocationLabel $n.location); vaultId = ''; kind = 'notebook'; notebookId = [string]$n.id }
    })
    , @($out)
}

function New-EmptyView([string]$Message, [bool]$NotFound = $false) {
    [pscustomobject]@{ available = $false; notFound = $NotFound; message = $Message; notebook = $null; sections = @(); totals = [pscustomobject]@{ sections = 0; pages = 0 }; recent = @() }
}

function Read-NotebookData {
    <# THE one place the server reads notebooks (read only): vaults by their state page
       (Get-VaultList), notebooks (Get-NotebookList).
       'list' -> @{ notebooks = @( listing ); message; activeVaultId; mode }
       'view' -> one notebook's sections and recent pages (-Id, or the active vault's notebook) #>
    param($State, [ValidateSet('list', 'view')][string]$What, [string]$Id = '')
    $d = Get-VaultData $State
    if ($d.message -and -not $d.notebooks.Count) {
        if ($What -eq 'list') { return [pscustomobject]@{ notebooks = @(); message = $d.message; activeVaultId = ''; mode = 'none' } }
        return (New-EmptyView $d.message)
    }
    $active = Get-ActiveVaultItem $State $d
    $activeId = if ($active) { [string]$active.vaultId } else { '' }
    $list = ConvertTo-NotebookListing -Vaults $d.vaults -Notebooks $d.notebooks -ActiveVaultId $activeId
    if ($What -eq 'list') {
        return [pscustomobject]@{ notebooks = $list; message = $(if ($d.vaults.Count) { $d.message } else { $script:NoVault }); activeVaultId = $activeId; mode = (Get-LeaseMode $State) }
    }
    $entry = $null
    if ($Id) { $entry = @($list | Where-Object { $_.id -eq $Id }) | Select-Object -First 1 }
    elseif ($active) { $entry = @($list | Where-Object { $_.vaultId -eq $activeId }) | Select-Object -First 1 }
    if (-not $entry) { if ($Id) { return (New-EmptyView 'That notebook is not open in OneNote.' $true) } else { return (New-EmptyView $script:NoVault) } }
    $ad = $d.adapter
    $getXml = { param($s, $sc) $ad.GetHierarchy($s, $sc) }.GetNewClosure()
    $getLink = { param($pageId) try { $ad.GetHyperlinkToObject($pageId) } catch { '' } }.GetNewClosure()
    try { $v = Get-NotebookView -Id $entry.notebookId -GetState { 'window' } -GetXml $getXml -GetLink $getLink } catch { return (New-EmptyView $script:NoAnswer) }
    if ($v.notebook) { $v.notebook.id = $entry.id; $v.notebook.name = $entry.name; $v.notebook.vault = [bool]$entry.vault; $v.notebook.active = [bool]$entry.active }
    # An empty notebook that is no vault and holds none can be set up as one ("Set up ObsidiNote in
    # this notebook", POST /api/vault/setup; user, 2026-11-13).
    $canSetUp = $false
    if ($v.notebook -and -not $entry.vault) {
        $nb = @($d.notebooks | Where-Object { $_.id -eq $entry.notebookId }) | Select-Object -First 1
        if ($nb -and -not @($nb.vaultIds).Count) { try { $canSetUp = [bool](Test-EmptyNotebook -Adapter $ad -NotebookId $entry.notebookId) } catch { } }
    }
    if ($v.notebook) { $v.notebook | Add-Member -NotePropertyName canSetUp -NotePropertyValue $canSetUp -Force }
    $v
}

function Get-ServerStatus($State) {
    if ($State.FakeStatus) { return $State.FakeStatus }
    $one = Get-OneNoteState
    $name = ''
    if ($State.Vault) { $name = [string]$State.Vault.name }
    elseif ($one -ne 'none') { $a = @((Read-NotebookData $State 'list').notebooks | Where-Object { $_.active }) | Select-Object -First 1; if ($a) { $name = $a.name } }
    [pscustomobject]@{
        app     = 'ObsidiNote'
        version = (Get-AppVersionText $State.AppRoot)
        uiPort  = [int]$State.Port
        oneNote = [pscustomobject]@{ state = $one; running = ($one -ne 'none'); notebookOpen = [bool]$name; notebook = $(if ($name) { $name } else { 'ObsidiNote' }) }
        copilot = [pscustomobject]@{ state = (Get-CopilotState $State); port = [int]$State.CdpPort; ready = (Test-CopilotReady $State) }
        vault   = [pscustomobject]@{ name = $name; vaultId = $(if ($State.Vault) { [string]$State.Vault.vaultId } else { '' }); mode = (Get-LeaseMode $State) }
    }
}

function Get-ServerModel($State, $Adapter) {
    <# The active vault's in-memory index model (the working copy; OneNote stays the store). Built
       once per vault (or taken over from the start), then updated in place by the store. #>
    if (-not $State.Vault) { return $null }
    $key = "$($State.Id)|$($State.Vault.vaultId)"
    if ($script:Model -and $script:ModelKey -eq $key) { return $script:Model }
    if ($State.Model -and $State.Model.vaultId -eq $State.Vault.vaultId) { $script:Model = $State.Model; $State.Model = $null }
    else {
        Set-ServerWriteRoot $State $Adapter
        $script:Model = (Update-VaultIndex -Adapter $Adapter -RootId $State.Vault.rootId -IndexSectionId $State.Vault.indexSectionId -VaultId $State.Vault.vaultId).model
    }
    $script:ModelKey = $key
    $script:Model
}

function Set-ServerWriteRoot($State, $Adapter) {
    if ($State.Vault -and $Adapter.PSObject.Properties['RootId'] -and $Adapter.RootId -ne $State.Vault.rootId) { Set-OneNoteWriteRoot -Adapter $Adapter -RootId $State.Vault.rootId }
}

function Switch-ServerVault($State, $Vault, $Data) {
    <# Makes $Vault (a Get-VaultList item) the active vault: gives the old vault's lease back, opens
       the new one (write root, lease, structure, index), keeps its record for the next start and
       forgets Ask's follow-up state. Returns the open result. #>
    $ad = $Data.adapter
    [Threading.Monitor]::Enter($State.Lock)
    try {
        if ($State.Vault -and $State.Lease) { $null = Close-VaultSession -Adapter $ad -Vault $State.Vault -Lease $State.Lease }
        $o = Open-VaultSession -Adapter $ad -Vault $Vault -SessionId $State.SessionId -Vaults $Data.vaults
        $State.Vault = $o.vault; $State.Lease = $o.lease
        $script:Model = $o.model; $script:ModelKey = "$($State.Id)|$($o.vault.vaultId)"
    } finally { [Threading.Monitor]::Exit($State.Lock) }
    Reset-AskState
    $script:AskConversations = @{}
    $script:ForeignCache = @{}
    Reset-VaultCache
    try {
        # The vault's record ("notebook" + "vaultId" in config\obsidinote.local.json, the one file the
        # server changes; no content): the next start reopens this vault.
        $rec = Get-VaultRecordFor -Vault $Vault -Notebooks $Data.notebooks -ToRecord { param($p) ConvertTo-NotebookRecord $p }
        if ($rec -and (Get-NotebookRecord -AppRoot $State.AppRoot) -ne $rec) { Set-LocalAppValue $State.AppRoot 'notebook' $rec }
        if ("$(Get-AppSetting -Key 'vaultId' -Default '' -AppRoot $State.AppRoot)" -ne $o.vault.vaultId) { Set-LocalAppValue $State.AppRoot 'vaultId' $o.vault.vaultId }
    } catch { Write-AppLog info server 'The active vault could not be recorded' }
    Write-AppLog info server 'Active vault changed' @{ mode = $o.mode; missing = $o.missing }
    $o
}

function Use-ActiveVault($State) {
    <# For a route that writes or reads the active vault: @{ ok; status; error; data; adapter; model }.
       Opens the vault a start would pick when none is open yet. #>
    $d = Get-VaultData $State
    if (-not $d.adapter) { return @{ ok = $false; status = 503; error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } }
    if (-not $State.Vault) {
        $pick = Get-ActiveVaultItem $State $d
        if (-not $pick) { return @{ ok = $false; status = 409; error = $script:NoVault } }
        try { $null = Switch-ServerVault $State $pick $d } catch { return @{ ok = $false; status = 500; error = "The vault could not be opened: $($_.Exception.Message)" } }
    }
    Set-ServerWriteRoot $State $d.adapter
    @{ ok = $true; data = $d; adapter = $d.adapter; model = (Get-ServerModel $State $d.adapter) }
}

function New-ServerStore($State, $Use) {
    $st = $State
    New-VaultStore -Adapter $Use.adapter -Vault $State.Vault -Model $Use.model -GetLease { $st.Lease }.GetNewClosure()
}

# --- Copilot ----------------------------------------------------------------------------------------

function Test-CopilotReady($State) { [bool]($State.TestCopilot -or ($State.Copilot -and -not $State.CopilotSkipped)) }

function Get-CopilotMissing([string]$Intent) {
    @{ status = 503; body = @{ intent = $Intent; error = 'Microsoft 365 Copilot is not connected, so ObsidiNote cannot add or ask right now. Start ObsidiNote with Copilot and sign in. The map, your notebooks and Undo still work.' } }
}

# How long Add and Ask wait for Copilot (user, 2026-11-13: a SharePoint link came back "NoAnswer").
# TimeoutSec: the normal wait. StallSec: no data from Copilot this long counts as hanging; the bridge
# then presses Stop, which also cancels an answer that was still coming, so it is long (reading a
# SharePoint or OneDrive source through Work IQ can be silent for minutes; it was 90 s). MaxTimeoutSec:
# while the page still shows Copilot at work, waiting goes on up to this. Add passes -LeaveRunning, so
# for Add the end of the wait means 'Pending' (the item waits in the Intake), never Stop. BusyWaitSec:
# an earlier answer still running in the chat (left running) is waited for this long before Add types.
$script:CopilotWait = @{ TimeoutSec = 600; StallSec = 300; MaxTimeoutSec = 900; BusyWaitSec = 60 }

function Get-AskCopilotAdapter($State) {
    <# @{ Send; NewChat } for Ask: the test stand-in, or the bridge (lib/Ask.psm1 New-AskCopilot). #>
    if ($State.TestCopilot) { return $State.TestCopilot }
    Import-Module (Join-Path $script:Here 'CopilotBridge.psm1') -Global
    $w = $script:CopilotWait
    New-AskCopilot -Bridge $State.Copilot -TimeoutSec $w.TimeoutSec -StallSec $w.StallSec -MaxTimeoutSec $w.MaxTimeoutSec
}

function Get-AddCopilot($State) {
    <# { param($Prompt) } for Add: one prompt, the bridge's reply object back (lib/Ingest.psm1). Add
       never stops a slow answer (-LeaveRunning: the bridge returns 'Pending' and the Intake item waits
       for "Check for the answer"), and never types over an answer still running (-BusyWaitSec). #>
    if ($State.TestCopilot) { $send = $State.TestCopilot.Send; return { param([string]$Prompt) & $send $Prompt }.GetNewClosure() }
    Import-Module (Join-Path $script:Here 'CopilotBridge.psm1') -Global
    $cmd = Get-Command Send-CopilotPrompt
    $b = $State.Copilot
    $w = $script:CopilotWait
    $t = $w.TimeoutSec; $st = $w.StallSec; $mx = $w.MaxTimeoutSec; $bw = $w.BusyWaitSec
    { param([string]$Prompt) & $cmd -Bridge $b -Text $Prompt -TimeoutSec $t -StallSec $st -MaxTimeoutSec $mx -LeaveRunning -BusyWaitSec $bw }.GetNewClosure()
}

function Get-AddChatReader($State) {
    <# { param($ChatUrl) } for "Check for the answer": the test stand-in (TestCopilot.ReadChat), or the
       bridge's Read-CopilotChat on ObsidiNote's own Copilot tab. #>
    if ($State.TestCopilot) {
        $tc = $State.TestCopilot
        $read = if ($tc -is [hashtable] -and $tc.ContainsKey('ReadChat')) { $tc['ReadChat'] } else { $null }
        if ($read) { return $read }
        return { param([string]$ChatUrl) @{ state = 'unavailable'; text = ''; busy = $false; message = 'no chat reader' } }
    }
    Import-Module (Join-Path $script:Here 'CopilotBridge.psm1') -Global
    $cmd = Get-Command Read-CopilotChat
    $b = $State.Copilot
    { param([string]$ChatUrl) & $cmd -Bridge $b -ChatUrl $ChatUrl }.GetNewClosure()
}

# --- Requests (pure parts) ----------------------------------------------------------------------------

function Get-QueryValue([string]$Query, [string]$Name) {
    <# One value of a query string (?a=1&b=2), URL-decoded; '' when absent. #>
    foreach ($pair in $Query.TrimStart('?').Split('&')) {
        $kv = $pair.Split('=', 2)
        if ($kv.Count -eq 2 -and $kv[0] -eq $Name) { return [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) }
    }
    ''
}

function Test-NotebookId([string]$Id) {
    <# A plausible OneNote object id ({GUID}{n}{Bn}); anything else is never passed to OneNote. #>
    $Id.Length -le 200 -and $Id -match '^\{[0-9A-Fa-f-]{36}\}(\{\d+\}\{[A-Za-z]\d+\})?$'
}

function Test-VaultIdText([string]$Id) { $Id.Length -le 64 -and $Id -match '^[0-9A-Fa-f-]{8,64}$' }

function Read-JsonBody([string]$Body) {
    <# The request body as an object; throws on anything that is not a JSON object. #>
    $b = $null
    try { $b = $Body | ConvertFrom-Json } catch { throw 'The request is not JSON.' }
    if (-not $b -or $b -isnot [pscustomobject]) { throw 'The request is not a JSON object.' }
    $b
}

function Get-BodyValue($Body, [string]$Name, $Default = '') { if ($Body.PSObject.Properties[$Name] -and $null -ne $Body.$Name) { $Body.$Name } else { $Default } }

function Read-IntentRequest([string]$Body) {
    <# The {text, mode} of an intent request; throws on anything else. #>
    $b = Read-JsonBody $Body
    $text = Get-BodyValue $b 'text' ''
    if ($text -isnot [string]) { throw 'text must be a string.' }
    $mode = "$(Get-BodyValue $b 'mode' 'auto')"
    if (-not $mode) { $mode = 'auto' }
    if ((Get-IntentModes) -notcontains $mode.ToLowerInvariant()) { throw "mode must be auto, add or ask." }
    @{ text = $text; mode = $mode.ToLowerInvariant() }
}

function Get-SubmitRoute {
    <# Where a submit goes (pure): @{ intent (add|ask); ingestMode (add|auto) } or @{ error }.
       Explicit mode wins; auto follows the intent rules; unclear goes to Add in auto mode, where
       Copilot's reply says add or ask (FEASIBILITY.md, Add or Ask from one input, rule 4). An Ask
       action (follow-up, save) is always Ask. #>
    param([string]$Text, [string]$Mode, [string]$Action = '')
    if ($Action -and $Action -ne 'ask') { return @{ intent = 'ask'; ingestMode = '' } }
    if ($Mode -eq 'add') { return @{ intent = 'add'; ingestMode = 'add' } }
    if ($Mode -eq 'ask') { return @{ intent = 'ask'; ingestMode = '' } }
    $i = (Get-Intent -Text $Text -Mode 'auto').intent
    switch ($i) {
        'ask' { return @{ intent = 'ask'; ingestMode = '' } }
        'add' { return @{ intent = 'add'; ingestMode = 'add' } }
        'empty' { return @{ error = 'Type or paste something first.' } }
    }
    @{ intent = 'add'; ingestMode = 'auto' }
}

# --- Routes ---------------------------------------------------------------------------------------

function Set-ActiveVault($State, [string]$Body) {
    <# POST /api/active-vault {id}: makes an open vault the active one (id = the switcher entry's id or
       the vault id). Opens it with its writer lease and keeps its record for the next start.
       Refuses read-only notebooks with 409. #>
    $id = ''
    try { $b = Read-JsonBody $Body; $id = "$(Get-BodyValue $b 'id' '')" } catch { }
    if (-not ((Test-NotebookId $id) -or (Test-VaultIdText $id))) { return @{ status = 400; body = @{ error = 'id must be a OneNote notebook id or a vault id.' } } }
    $d = Get-VaultData $State -Fresh
    if (-not $d.adapter) { return @{ status = 503; body = @{ error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } } }
    $v = @($d.vaults | Where-Object { $_.vaultId -eq $id -or (Get-VaultListId $_) -eq $id }) | Select-Object -First 1
    if (-not $v) {
        $msg = if (@($d.notebooks | Where-Object { $_.id -eq $id }).Count) { 'That notebook is not an ObsidiNote vault; it can only be read.' } else { 'That notebook is not open in OneNote.' }
        return @{ status = 409; body = @{ error = $msg } }
    }
    if ($State.Vault -and $State.Vault.vaultId -eq $v.vaultId) { return @{ status = 200; body = @{ id = (Get-VaultListId $v); name = $v.name; vaultId = $v.vaultId; mode = (Get-LeaseMode $State); missing = 0 } } }
    try { $o = Switch-ServerVault $State $v $d } catch { return @{ status = 500; body = @{ error = "The vault could not be opened: $($_.Exception.Message)" } } }
    @{ status = 200; body = @{ id = (Get-VaultListId $v); name = $v.name; vaultId = $v.vaultId; mode = $o.mode; missing = $o.missing } }
}

function New-VaultRoute($State, [string]$Body) {
    <# POST /api/vault/new {name, inNotebook, confirm}: a new vault as its own notebook, or (only with
       confirm) as a section group inside an open notebook, then made active. When OneNote cannot make
       the notebook next to the cloud notebooks (0x80042006) it goes to OneNote's default notebook
       folder, with a warning. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $name = ("$(Get-BodyValue $b 'name' '')").Trim()
    $inNb = "$(Get-BodyValue $b 'inNotebook' '')"
    $confirm = [bool](Get-BodyValue $b 'confirm' $false)
    if (-not $name -or $name.Length -gt 60 -or $name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]*$') { return @{ status = 400; body = @{ error = 'Give the vault a name of letters, digits, spaces, dots, dashes or underscores (at most 60).' } } }
    $d = Get-VaultData $State -Fresh
    if (-not $d.adapter) { return @{ status = 503; body = @{ error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } } }
    if ($inNb) {
        # Only an id that is one of the open notebooks ever reaches OneNote.
        if ($inNb.Length -gt 200) { return @{ status = 400; body = @{ error = 'inNotebook must be a OneNote notebook id.' } } }
        $nb = @($d.notebooks | Where-Object { $_.id -eq $inNb }) | Select-Object -First 1
        if (-not $nb) { return @{ status = 404; body = @{ error = 'That notebook is not open in OneNote.' } } }
        if ($nb.structured) { return @{ status = 409; body = @{ error = 'That notebook is already an ObsidiNote vault.' } } }
        if (-not $confirm) { return @{ status = 409; body = @{ needsConfirm = $true; error = "This writes a section group '$name' into the notebook '$($nb.name)', which ObsidiNote does not own yet. Confirm to go ahead." } } }
    }
    $warning = ''
    [Threading.Monitor]::Enter($State.Lock)
    try {
        try {
            if ($inNb) { $r = New-ObsidiVault -Adapter $d.adapter -Name $name -InSectionGroupOf $inNb }
            else { $r = New-ObsidiVault -Adapter $d.adapter -Name $name }
        } catch {
            if ($inNb -or "$($_.Exception.Message)" -notmatch '0x80042006|No cloud notebook') { throw }
            $folder = $d.adapter.GetDefaultNotebookFolder()
            if (-not $folder) { throw }
            $r = New-ObsidiVault -Adapter $d.adapter -Name $name -Location $folder
            $warning = "OneNote could not make the notebook next to your cloud notebooks, so it is in OneNote's default notebook folder on this PC. Move it to OneDrive in OneNote to share it."
            try { Write-Status -ToError 'WARN' 'New vault' $warning } catch { }
        }
    } catch {
        return @{ status = 500; body = @{ error = "The vault could not be made: $($_.Exception.Message)" } }
    } finally { [Threading.Monitor]::Exit($State.Lock) }
    $d = Get-VaultData $State -Fresh
    $v = @($d.vaults | Where-Object { $_.vaultId -eq $r.vaultId }) | Select-Object -First 1
    if (-not $v) { return @{ status = 500; body = @{ error = 'The vault was made but could not be found again. Restart ObsidiNote.' } } }
    try { $o = Switch-ServerVault $State $v $d } catch { return @{ status = 500; body = @{ error = "The vault was made but could not be opened: $($_.Exception.Message)" } } }
    Write-AppLog info server 'New vault' @{ kind = $v.rootKind; mode = $o.mode }
    @{ status = 200; body = @{ id = (Get-VaultListId $v); vaultId = $v.vaultId; name = $v.name; kind = $v.rootKind; mode = $o.mode; warning = $warning } }
}

function Set-UpVaultRoute($State, [string]$Body) {
    <# POST /api/vault/setup {id, confirm}: sets up an open, EMPTY notebook (no pages, no section groups)
       as a vault in place, then makes it active (user, 2026-11-13). Without confirm it only answers
       409 needsConfirm: it writes into a notebook ObsidiNote does not own yet. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $id = "$(Get-BodyValue $b 'id' '')"
    $confirm = [bool](Get-BodyValue $b 'confirm' $false)
    if (-not $id -or $id.Length -gt 200) { return @{ status = 400; body = @{ error = 'id must be a OneNote notebook id.' } } }
    $d = Get-VaultData $State -Fresh
    if (-not $d.adapter) { return @{ status = 503; body = @{ error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } } }
    # Only an id that is one of the open notebooks ever reaches OneNote (as in /api/vault/new).
    $nb = @($d.notebooks | Where-Object { $_.id -eq $id }) | Select-Object -First 1
    if (-not $nb) { return @{ status = 404; body = @{ error = 'That notebook is not open in OneNote.' } } }
    if ($nb.structured -or @($nb.vaultIds).Count) { return @{ status = 409; body = @{ error = 'That notebook already holds an ObsidiNote vault.' } } }
    if (-not (Test-EmptyNotebook -Adapter $d.adapter -NotebookId $id)) { return @{ status = 409; body = @{ error = 'That notebook is not empty, so ObsidiNote does not set it up. Use "New ObsidiNote vault" instead.' } } }
    if (-not $confirm) { return @{ status = 409; body = @{ needsConfirm = $true; error = "This adds ObsidiNote's sections (00 Index, 01 Intake and the buckets) to the empty notebook '$($nb.name)' and makes it your active vault. Confirm to go ahead." } } }
    [Threading.Monitor]::Enter($State.Lock)
    try { $r = Initialize-EmptyNotebookVault -Adapter $d.adapter -NotebookId $id -Vaults $d.vaults }
    catch { return @{ status = 500; body = @{ error = "The notebook could not be set up: $($_.Exception.Message)" } } }
    finally { [Threading.Monitor]::Exit($State.Lock) }
    $d = Get-VaultData $State -Fresh
    $v = @($d.vaults | Where-Object { $_.vaultId -eq $r.vaultId }) | Select-Object -First 1
    if (-not $v) { return @{ status = 500; body = @{ error = 'The notebook was set up but could not be found again. Restart ObsidiNote.' } } }
    try { $o = Switch-ServerVault $State $v $d } catch { return @{ status = 500; body = @{ error = "The notebook was set up but could not be opened: $($_.Exception.Message)" } } }
    Write-AppLog info server 'Vault set up' @{ kind = 'notebook'; mode = $o.mode }
    @{ status = 200; body = @{ id = (Get-VaultListId $v); vaultId = $v.vaultId; name = $v.name; kind = 'notebook'; mode = $o.mode; warning = '' } }
}

function Get-ForeignGraphModel($State, $Adapter, $Notebook, $Vaults, [int]$BudgetMs = 15000) {
    <# A connected notebook's derived model, kept in memory for a few minutes; its link edges are read
       in batches (Get-NotebookLinks) within $BudgetMs per call, later calls go on where it stopped. #>
    if (-not $script:ForeignCache) { $script:ForeignCache = @{} }
    $c = $script:ForeignCache[$Notebook.id]
    if (-not $c -or $c.at.Elapsed.TotalMinutes -gt 5) {
        $c = @{ at = [Diagnostics.Stopwatch]::StartNew(); model = (Get-NotebookModel -Adapter $Adapter -NotebookId $Notebook.id -NoLinks -Vaults $Vaults); next = 0; done = $false }
        $script:ForeignCache[$Notebook.id] = $c
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $c.done -and $sw.ElapsedMilliseconds -lt $BudgetMs) {
        $b = Get-NotebookLinks -Adapter $Adapter -Model $c.model -Start $c.next -BatchSize 50
        $c.next = $b.next; $c.done = $b.done
    }
    $c
}

function Get-GraphRoute($State, [string]$Query) {
    <# GET /api/graph?vault=<vault id> | ?notebook=<notebook id>; neither = the active vault. #>
    $vid = Get-QueryValue $Query 'vault'
    $nid = Get-QueryValue $Query 'notebook'
    if ($vid -and -not (Test-VaultIdText $vid)) { return @{ status = 400; body = @{ error = 'vault must be a vault id.' } } }
    if ($nid -and -not (Test-NotebookId $nid)) { return @{ status = 400; body = @{ error = 'notebook must be a OneNote notebook id.' } } }
    $d = Get-VaultData $State
    if (-not $d.adapter) { return @{ status = 503; body = @{ error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } } }
    $v = $null
    if ($vid) { $v = @($d.vaults | Where-Object { $_.vaultId -eq $vid }) | Select-Object -First 1; if (-not $v) { return @{ status = 404; body = @{ error = 'That vault is not open in OneNote.' } } } }
    elseif ($nid) { $v = @($d.vaults | Where-Object { (Get-VaultListId $_) -eq $nid }) | Select-Object -First 1 }
    else {
        $u = Use-ActiveVault $State
        if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
        $v = @($d.vaults | Where-Object { $_.vaultId -eq $State.Vault.vaultId }) | Select-Object -First 1
    }
    if ($v) {
        if ($State.Vault -and $v.vaultId -eq $State.Vault.vaultId) {
            $u = Use-ActiveVault $State
            if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
            $m = ConvertTo-GraphModel -Model $u.model -Source @{ kind = 'vault'; id = $v.vaultId; name = $v.name; readOnly = ((Get-LeaseMode $State) -ne 'writer') }
        } else {
            $model = Read-IndexModel -Adapter $d.adapter -IndexSectionId $v.indexSectionId -VaultId $v.vaultId -RootId $v.rootId
            $m = ConvertTo-GraphModel -Model $model -Source @{ kind = 'vault'; id = $v.vaultId; name = $v.name; readOnly = $true }
        }
        $m['edgesComplete'] = $true
        return @{ status = 200; body = $m }
    }
    $nb = @($d.notebooks | Where-Object { $_.id -eq $nid }) | Select-Object -First 1
    if (-not $nb) { return @{ status = 404; body = @{ error = 'That notebook is not open in OneNote.' } } }
    $c = Get-ForeignGraphModel $State $d.adapter $nb $d.vaults
    $m = ConvertTo-GraphModel -Model $c.model -Source @{ kind = 'notebook'; id = $nb.id; name = $nb.name; readOnly = $true }
    $m['edgesComplete'] = [bool]$c.done
    @{ status = 200; body = $m }
}

function Get-AskSourceList($State, $Use, [string[]]$Wanted) {
    <# The source adapters for one Ask: the active vault (ReadOnly false) and the chosen read-only
       vaults and connected notebooks. #>
    $ad = $Use.adapter
    $list = @(New-AskSource -Adapter $ad -Model $Use.model -Id $State.Vault.vaultId -Name $State.Vault.name -Kind 'vault')
    foreach ($w in @($Wanted | Where-Object { $_ } | Select-Object -Unique)) {
        if ($w -eq $State.Vault.vaultId) { continue }
        $v = @($Use.data.vaults | Where-Object { $_.vaultId -eq $w -or (Get-VaultListId $_) -eq $w }) | Select-Object -First 1
        if ($v) {
            if ($v.vaultId -eq $State.Vault.vaultId) { continue }
            $m = Read-IndexModel -Adapter $ad -IndexSectionId $v.indexSectionId -VaultId $v.vaultId -RootId $v.rootId
            $list += New-AskSource -Adapter $ad -Model $m -Id $w -Name $v.name -Kind 'vault' -ReadOnly
            continue
        }
        $nb = @($Use.data.notebooks | Where-Object { $_.id -eq $w }) | Select-Object -First 1
        if (-not $nb) { continue }
        $c = Get-ForeignGraphModel $State $ad $nb $Use.data.vaults -BudgetMs 0
        $list += New-AskSource -Adapter $ad -Model $c.model -Id $w -Name $nb.name -Kind 'notebook' -ReadOnly
    }
    , $list
}

function Invoke-SubmitRoute($State, [string]$Body) {
    <# POST /api/submit: Add (Invoke-AddRequest through the vault store) or Ask (Invoke-AskRequest
       over the index), by mode and intent. 503 without Copilot. The answer carries intent add|ask. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $text = Get-BodyValue $b 'text' (Get-BodyValue $b 'question' '')
    if ($text -isnot [string]) { return @{ status = 400; body = @{ error = 'text must be a string.' } } }
    $mode = ("$(Get-BodyValue $b 'mode' 'auto')").ToLowerInvariant()
    if (-not $mode) { $mode = 'auto' }
    if ((Get-IntentModes) -notcontains $mode) { return @{ status = 400; body = @{ error = 'mode must be auto, add or ask.' } } }
    $action = "$(Get-BodyValue $b 'action' '')"
    $route = Get-SubmitRoute -Text $text -Mode $mode -Action $action
    if ($route.ContainsKey('error')) { return @{ status = 400; body = @{ error = $route.error } } }
    $needsCopilot = -not ($route.intent -eq 'ask' -and $action -in 'save-page', 'save-open-question')
    if ($needsCopilot -and -not (Test-CopilotReady $State)) { return (Get-CopilotMissing $route.intent) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ intent = $route.intent; error = $u.error } } }
    if ($route.intent -eq 'add') {
        $r = Invoke-AddRequest -Request @{ text = $text; mode = $route.ingestMode } -Store (New-ServerStore $State $u) -Ask (Get-AddCopilot $State)
        $r['intent'] = 'add'
        return @{ status = 200; body = $r }
    }
    $req = @{ action = $(if ($action) { $action } else { 'ask' }); question = $text; includeArchived = [bool](Get-BodyValue $b 'includeArchived' $false)
        conversationId = "$(Get-BodyValue $b 'conversationId' '')"; turn = [int](Get-BodyValue $b 'turn' 0) }
    $wanted = @(@(Get-BodyValue $b 'sources' @()) | ForEach-Object { "$_" } | Where-Object { (Test-NotebookId $_) -or (Test-VaultIdText $_) })
    if (-not $script:AskConversations) { $script:AskConversations = @{} }
    if ($req.action -eq 'follow-up' -and $script:AskConversations.ContainsKey($req.conversationId)) { $wanted = @($script:AskConversations[$req.conversationId]) }
    $req.sources = $wanted
    $ctx = @{ Sources = (Get-AskSourceList $State $u $wanted); Copilot = $(if ($needsCopilot) { Get-AskCopilotAdapter $State } else { $null }) }
    $r = Invoke-AskRequest -Request $req -Context $ctx
    $r['intent'] = 'ask'
    if ($r.ContainsKey('conversationId') -and $r.conversationId) { $script:AskConversations[[string]$r.conversationId] = $wanted }
    @{ status = 200; body = $r }
}

function Invoke-UndoRoute($State, [string]$Body) {
    <# POST /api/add/undo {undo}: the Add's page to OneNote's Deleted Pages, its backlinks rewritten. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $undo = Get-BodyValue $b 'undo' $null
    if (-not $undo -or $undo -isnot [pscustomobject]) { return @{ status = 400; body = @{ error = 'undo must be the Add result''s undo record.' } } }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    @{ status = 200; body = (Undo-AddRequest -Store (New-ServerStore $State $u) -Undo $undo) }
}

function Test-PageIdText([string]$Id) {
    <# A plausible OneNote page id ({...}{n}{Bn}); the store then checks that it is an Intake item. #>
    $Id.Length -le 200 -and $Id -match '^\{[0-9A-Za-z-]{1,40}\}(\{\d+\}\{[A-Za-z]\d+\})?$'
}

function Invoke-AddFetchRoute($State, [string]$Body) {
    <# POST /api/add/fetch {inboxId}: "Check for the answer" for an Intake item that waits for Copilot
       (lib/Ingest.psm1 Receive-AddAnswer). 200 with the outcome (the Add result, or still-waiting,
       mismatch, invalid); 409 when the item is not waiting or this session is not the writer. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $id = "$(Get-BodyValue $b 'inboxId' '')"
    if (-not (Test-PageIdText $id)) { return @{ status = 400; body = @{ error = 'inboxId must be the Intake item''s page id.' } } }
    if (-not (Test-CopilotReady $State)) { return (Get-CopilotMissing 'add') }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ intent = 'add'; error = $u.error } } }
    $r = Receive-AddAnswer -Store (New-ServerStore $State $u) -Ask (Get-AddCopilot $State) -ReadChat (Get-AddChatReader $State) -InboxId $id
    $r['intent'] = 'add'
    if ($r.status -eq 'refused') { return @{ status = 409; body = @{ intent = 'add'; error = $r.message } } }
    @{ status = 200; body = $r }
}

function Invoke-LinkUpdateRoute($State, [string]$Body) {
    <# POST /api/link/update {id, decision, proposed}: Update of a link page. Copilot is needed unless
       the person decides on a summary it already proposed. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $id = "$(Get-BodyValue $b 'id' '')"
    $decision = "$(Get-BodyValue $b 'decision' '')"
    $proposed = Get-BodyValue $b 'proposed' $null
    if (-not (Test-ObsnId $id)) { return @{ status = 400; body = @{ error = 'id must be an ObsidiNote page id.' } } }
    if (@('', 'replace', 'keep') -notcontains $decision) { return @{ status = 400; body = @{ error = 'decision must be replace or keep.' } } }
    if ($null -eq $proposed -and -not (Test-CopilotReady $State)) { return (Get-CopilotMissing 'add') }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $ask = if (Test-CopilotReady $State) { Get-AddCopilot $State } else { { throw 'Copilot is not connected.' } }
    $r = Update-LinkSummary -Store (New-ServerStore $State $u) -Ask $ask -Id $id -Decision $decision -Proposed $proposed
    $r['intent'] = 'add'
    @{ status = 200; body = $r }
}

function Invoke-ApiRoute {
    <# The answer to one API call: @{ status; body }. The body is an object for ConvertTo-Json. #>
    param([string]$Method, [string]$Path, [string]$Body, $State, [string]$Query = '')
    $route = "$Method $Path"
    switch -Exact ($route) {
        'GET /api/status' { return @{ status = 200; body = (Get-ServerStatus $State) } }
        'GET /api/notebooks' { return @{ status = 200; body = (Read-NotebookData $State 'list') } }
        'GET /api/notebook' {
            $id = Get-QueryValue $Query 'id'
            if ($id -and -not (Test-NotebookId $id)) { return @{ status = 400; body = @{ error = 'id must be a OneNote notebook id.' } } }
            $v = Read-NotebookData $State 'view' $id
            if ($v.notFound) { return @{ status = 404; body = @{ error = $v.message } } }
            return @{ status = 200; body = $v }
        }
        'GET /api/graph' { return (Get-GraphRoute $State $Query) }
        'POST /api/active-vault' { return (Set-ActiveVault $State $Body) }
        'POST /api/vault/new' { return (New-VaultRoute $State $Body) }
        'POST /api/vault/setup' { return (Set-UpVaultRoute $State $Body) }
        'POST /api/intent' {
            try { $r = Read-IntentRequest $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
            return @{ status = 200; body = (Get-Intent -Text $r.text -Mode $r.mode) }
        }
        'POST /api/submit' { return (Invoke-SubmitRoute $State $Body) }
        'POST /api/add/undo' { return (Invoke-UndoRoute $State $Body) }
        'POST /api/add/fetch' { return (Invoke-AddFetchRoute $State $Body) }
        'POST /api/link/update' { return (Invoke-LinkUpdateRoute $State $Body) }
    }
    @{ status = 404; body = @{ error = 'Not found.' } }
}


# --- Requests ---------------------------------------------------------------------------------

function Send-Bytes($Ctx, [int]$Status, [string]$Type, [byte[]]$Bytes) {
    $res = $Ctx.Response
    $res.StatusCode = $Status
    $res.ContentType = $Type
    $res.Headers['Cache-Control'] = 'no-store'
    $res.Headers['X-Content-Type-Options'] = 'nosniff'
    $res.Headers['Referrer-Policy'] = 'no-referrer'
    $res.ContentLength64 = $Bytes.Length
    $res.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $res.Close()
}

function Send-Json($Ctx, $Object, [int]$Status = 200) {
    $json = ConvertTo-Json -InputObject $Object -Depth 12 -Compress
    Send-Bytes $Ctx $Status 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($json))
}

function Read-Body($Ctx) {
    if ($Ctx.Request.ContentLength64 -gt $script:MaxBodyBytes) { throw 'too-large' }
    $reader = New-Object IO.StreamReader($Ctx.Request.InputStream, [Text.Encoding]::UTF8)
    try {
        $buf = New-Object char[] ($script:MaxBodyBytes + 1)
        $n = $reader.ReadBlock($buf, 0, $buf.Length)
        if ($n -gt $script:MaxBodyBytes) { throw 'too-large' }
        New-Object string ($buf, 0, $n)
    } finally { $reader.Dispose() }
}

function Send-UiFile($Ctx, $AllowList, [string]$Path) {
    $full = $null
    if (-not $AllowList.TryGetValue($Path, [ref]$full)) { return Send-Json $Ctx @{ error = 'Not found.' } 404 }
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    if ($ext -eq '.html') { $Ctx.Response.Headers['Content-Security-Policy'] = $script:PagePolicy }
    $Ctx.Response.Headers['X-Frame-Options'] = 'DENY'
    Send-Bytes $Ctx 200 $script:Mime[$ext] ([IO.File]::ReadAllBytes($full))
}

function Invoke-ServerRequest($Ctx, $State, $AllowList) {
    $req = $Ctx.Request
    # The raw path, so an encoded ..%2F stays as typed and simply is not on the allow-list.
    $raw = "$($req.RawUrl)"
    $parts = $raw -split '\?', 2
    $path = $parts[0]
    $query = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $remote = $req.RemoteEndPoint
    $verdict = Get-RequestVerdict -Method $req.HttpMethod -Path $path -HostHeader "$($req.Headers['Host'])" -Origin "$($req.Headers['Origin'])" `
        -AppHeader "$($req.Headers['X-ObsidiNote'])" -Loopback ([bool]($remote -and [Net.IPAddress]::IsLoopback($remote.Address))) -Port ([int]$State.Port)
    if ($verdict) { return Send-Json $Ctx @{ error = $verdict.error } $verdict.status }
    if (-not $path.StartsWith('/api/')) { return Send-UiFile $Ctx $AllowList $path }
    $body = ''
    if ($req.HttpMethod -eq 'POST') {
        try { $body = Read-Body $Ctx } catch { return Send-Json $Ctx @{ error = 'The request is too large.' } 413 }
    }
    $a = Invoke-ApiRoute -Method $req.HttpMethod -Path $path -Body $body -State $State -Query $query
    Send-Json $Ctx $a.body $a.status
}

function Test-ClientGone($Exception) {
    <# The browser closed the connection before the answer was written. #>
    for ($e = $Exception; $e; $e = $e.InnerException) {
        if ($e -is [Net.HttpListenerException] -and $e.ErrorCode -in 64, 995, 1229, 10053, 10054) { return $true }
    }
    $false
}

function Invoke-ServerLoop {
    <# Serves until the listener stops (Stop-UiServer). Runs in the server's runspace. #>
    param([Parameter(Mandatory)]$Listener, [Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$UiDir)
    $allow = Get-UiAllowList $UiDir
    while ($Listener.IsListening -and -not $State.Stop) {
        try { $ctx = $Listener.GetContext() } catch { break }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $what = "$($ctx.Request.HttpMethod) $(($ctx.Request.Url.AbsolutePath))"
        try { Invoke-ServerRequest $ctx $State $allow }
        catch {
            if (Test-ClientGone $_.Exception) { try { $ctx.Response.Abort() } catch { }; continue }
            Write-AppLog info server "$what failed ($($_.Exception.GetType().Name))"
            try { Send-Json $ctx @{ error = 'Something went wrong on this computer. Try again.' } 500 } catch { }
        }
        if ($what -like '* /api/*') { Write-AppLog verbose server "$what ($($sw.ElapsedMilliseconds) ms)" }
    }
}

function Start-UiServer {
    <# Starts listening on 127.0.0.1:$Port (and localhost) and runs the request loop in its own
       runspace. Throws when the port is taken or ui\index.html is missing. Returns the handle for
       Stop-UiServer: @{ Listener; PowerShell; Runspace; Async; Url; State }. #>
    param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$UiDir, [Parameter(Mandatory)]$State)
    if (-not (Test-Path -LiteralPath (Join-Path $UiDir 'index.html') -PathType Leaf)) { throw "The interface is missing: $UiDir\index.html. Reinstall ObsidiNote (update.cmd -Repair)." }
    $listener = New-Object Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'   # OneNote's COM API
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript({
        param($ModulePath, $Listener, $State, $UiDir)
        $ErrorActionPreference = 'Stop'
        Import-Module $ModulePath
        Invoke-ServerLoop -Listener $Listener -State $State -UiDir $UiDir
    }).AddArgument((Join-Path $script:Here 'Server.psm1')).AddArgument($listener).AddArgument($State).AddArgument($UiDir)
    $async = $ps.BeginInvoke()
    Write-AppLog info server "Interface server started on port $Port"
    [pscustomobject]@{ Listener = $listener; PowerShell = $ps; Runspace = $rs; Async = $async; Url = "http://127.0.0.1:$Port"; State = $State }
}

function Stop-UiServer {
    <# Stops the listener and ends the request loop (waits up to 5 s for a request in progress). #>
    param($Server)
    if (-not $Server) { return }
    $Server.State.Stop = $true
    try { $Server.Listener.Stop(); $Server.Listener.Close() } catch { }
    try { if ($Server.Async.AsyncWaitHandle.WaitOne(5000)) { $null = $Server.PowerShell.EndInvoke($Server.Async) } } catch { }
    try { $Server.PowerShell.Dispose(); $Server.Runspace.Dispose() } catch { }
    Write-AppLog info server 'Interface server stopped'
}

function Test-UiServerRunning {
    <# True when an ObsidiNote server already answers on $Port (a second start opens that one). #>
    param([int]$Port)
    try {
        $s = Invoke-RestMethod "http://127.0.0.1:$Port/api/status" -Headers @{ 'X-ObsidiNote' = '1' } -TimeoutSec 5
        "$($s.app)" -eq 'ObsidiNote'
    } catch { $false }
}

Export-ModuleMember -Function Get-AllowedOrigins, Test-AllowedOrigin, Test-AllowedHost, Get-RequestVerdict, Get-UiAllowList,
    Get-CopilotTabState, New-ServerState, Invoke-ApiRoute, Invoke-ServerLoop, Start-UiServer, Stop-UiServer, Test-UiServerRunning, Test-ClientGone,
    ConvertTo-NotebookListing, Get-SubmitRoute
