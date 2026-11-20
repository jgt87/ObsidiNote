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
# MarkdownExport: POST /api/export, the download the person asks for (built in memory).
# WhatsNew: GET /api/whats-new, the running version's CHANGELOG.md lines (read only).
# NotebookStructure: the company names for link buckets and the page types for editing.
# Meetings: POST /api/meetings/day and /notes, Copilot's questions about a day's Teams meetings (read only).
foreach ($m in 'Log', 'AppConfig', 'Startup', 'Intent', 'OneNoteHost', 'NotebookView', 'Update', 'Status', 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'AskSources', 'GraphModel', 'Ingest', 'Ask', 'MarkdownExport', 'WhatsNew', 'VaultSettings', 'Activity', 'SyncedFiles', 'Meetings') {
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
       with scriptblocks; never with Start-UiServer); -TestConnect stands in for Connect-Copilot in
       POST /api/copilot/reconnect (returns a bridge-like object or throws). UpdatedTo: the version this start was updated
       to ('' when it followed no update), for GET /api/whats-new. #>
    param([Parameter(Mandatory)][string]$AppRoot, [int]$Port, [int]$CdpPort = 9334, [bool]$CopilotSkipped = $false,
        $FakeStatus = $null, [string]$FakeHierarchyXml = '', $Copilot = $null, $Vault = $null, $Lease = $null, [string]$SessionId = '',
        $Model = $null, $TestAdapter = $null, $TestCopilot = $null, [string]$UpdatedTo = '', $TestConnect = $null, $VaultSettings = $null,
        # VaultDetail: the start's Vault status line when it opened no vault (GET /api/status says why).
        # SettingsUnreadable: the vault's stored settings could not be read (GET /api/settings says so).
        [string]$VaultDetail = '', [bool]$SettingsUnreadable = $false)
    $h = [hashtable]::Synchronized(@{})
    $h.AppRoot = $AppRoot; $h.Port = $Port; $h.CdpPort = $CdpPort; $h.CopilotSkipped = $CopilotSkipped
    $h.FakeStatus = $FakeStatus; $h.FakeHierarchyXml = $FakeHierarchyXml
    $h.Copilot = $Copilot; $h.Vault = $Vault; $h.Lease = $Lease; $h.Model = $Model
    $h.SessionId = $(if ($SessionId) { $SessionId } else { New-WriterSessionId })
    $h.TestAdapter = $TestAdapter; $h.TestCopilot = $TestCopilot; $h.TestConnect = $TestConnect
    $h.UpdatedTo = $UpdatedTo
    # The active vault's settings from OneNote (lib/VaultSettings.psm1), refreshed on a vault switch
    # and by POST /api/settings; the defaults until a vault is open.
    $h.VaultSettings = $(if ($VaultSettings) { $VaultSettings } else { Get-VaultSettingDefaults })
    $h.Lock = New-Object object
    $h.Id = [guid]::NewGuid().ToString('N')
    $h.Stop = $false
    # 'shutdown' once POST /api/shutdown asked this server to end (a new start on this PC takes over).
    $h.StopReason = ''
    $h.VaultDetail = $VaultDetail
    $h.SettingsUnreadable = $SettingsUnreadable
    # POST /api/open: a list here (tests) records the addresses instead of opening the browser.
    $h.OpenedUrls = $null
    $h
}

function Test-WebAddress([string]$Url) {
    <# An address POST /api/open may hand to the default browser: absolute http(s), no spaces or
       control characters, at most 2000 characters. Never a file, onenote: or script address. #>
    if (-not $Url -or $Url.Length -gt 2000 -or $Url -match '[\s\x00-\x1f"<>]') { return $false }
    $u = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$u)) { return $false }
    ($u.Scheme -eq 'https' -or $u.Scheme -eq 'http') -and [bool]$u.Host
}

function Invoke-OpenUrlRoute($State, [string]$Body) {
    <# POST /api/open {url}: opens a web address in a new tab of the person's default browser
       (operator, 2026-11-17: web links open there, not in ObsidiNote's own Edge window). The window
       cannot pick the browser itself; this asks Windows to open the address. http(s) only; nothing
       is written or kept; the log says only that an address was opened. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $url = "$(Get-BodyValue $b 'url' '')"
    if (-not (Test-WebAddress $url)) { return @{ status = 400; body = @{ error = 'url must be a web address (http or https).' } } }
    if ($null -ne $State.OpenedUrls) { $null = $State.OpenedUrls.Add($url); return @{ status = 200; body = @{ opened = $true } } }
    try { Start-Process -FilePath $url | Out-Null }
    catch { return @{ status = 500; body = @{ error = "The browser could not be opened: $($_.Exception.Message)" } } }
    Write-AppLog info server 'Web address opened in the default browser' @{}
    @{ status = 200; body = @{ opened = $true } }
}

function Get-MeetingDayValue($Body) {
    <# The day of a meetings request: its "day" (yyyy-mm-dd), else today on this PC; $null when the
       value given is not a date. #>
    $d = "$(Get-BodyValue $Body 'day' '')".Trim()
    if (-not $d) { return (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    if (Test-MeetingDay $d) { return $d }
    $null
}

function Send-MeetingQuestion($State, [string]$Prompt) {
    <# One meetings question to Copilot (Ask's adapter: a slow answer is waited for, then stopped;
       nothing waits in the Intake, as nothing is written). @{ ok; text; error }. Each question gets a
       new chat with Work IQ switched on, as kit probe P10 does (Send-KitPrompt): asked in the chat
       that was open and without Work IQ, Copilot answered "no meetings" for a day the probe listed 8
       (target machine, 2026-11-17, v0.12.8). #>
    try {
        $c = Get-AskCopilotAdapter $State
        try { $null = & $c.NewChat } catch { }
        $wiq = Set-MeetingWorkIq $State
        $text = [string](& $c.Send $Prompt)
        Write-AppLog info server 'Meetings question' @{ workIq = $wiq }
        return @{ ok = $true; text = $text; error = '' }
    } catch { return @{ ok = $false; text = ''; error = "Copilot did not answer: $($_.Exception.Message)" } }
}

function Set-MeetingWorkIq($State) {
    <# Work IQ on (Microsoft 365 data: the calendar and the meetings): 'on' | 'off' | 'unavailable' |
       'error' | 'test'. A test stand-in has its own WorkIq when it wants to see the call. #>
    $tc = $State.TestCopilot
    if ($tc) { if ($tc -is [hashtable] -and $tc.ContainsKey('WorkIq')) { return [string](& $tc['WorkIq']) }; return 'test' }
    try { Import-Module (Join-Path $script:Here 'CopilotBridge.psm1') -Global; $cmd = Get-Command Set-CopilotWorkIq; return [string](& $cmd -Bridge $State.Copilot -On $true) }
    catch { return 'error' }
}

function Get-MeetingSeriesCounts($State) {
    <# @{ pages = series key -> the starts (meetingAt) of its meeting pages in the active vault's index
       (archived left out); waiting = @(@{ key; at }) of the meetings whose Add still waits for
       Copilot in the Intake }. Empty when no vault is open or it cannot be read. #>
    $out = @{ pages = @{}; waiting = @() }
    try {
        if (-not $State.Vault) { return $out }   # never opens a vault for a list (Use-ActiveVault may)
        $u = Use-ActiveVault $State
        if (-not $u.ok) { return $out }
        $model = $u.model
        if (-not $model) { return $out }
        foreach ($p in $model.pages.Values) {
            if ($p.type -ne 'meeting' -or $p.status -eq 'archived' -or -not $p['series'] -or [string]$p['kind'] -eq 'series') { continue }
            $k = Get-MeetingSeriesKey ([string]$p['series'])
            if (-not $out.pages.ContainsKey($k)) { $out.pages[$k] = New-Object System.Collections.Generic.List[string] }
            $out.pages[$k].Add([string]$p['meetingAt'])
        }
        $store = New-ServerStore $State $u
        $ws = & $store.WaitingTexts   # returned with ',': assigned first
        $out.waiting = @(foreach ($w in @($ws | Where-Object { $_ })) { $i = Get-MeetingInfoFromText ([string]$w['text']); if ($i) { @{ key = $i.key; at = $i.at } } })
    } catch { }
    $out
}

function Invoke-MeetingsDayRoute($State, [string]$Body) {
    <# POST /api/meetings/day {day?}: the Teams meetings of one day (today when no day is sent), as
       Copilot lists them with the person's own access (lib/Meetings.psm1). Read only: nothing is
       written. 200 {day, meetings:[{title, start, time, attendees, hasTranscript, hasRecap,
       hasNotes, readable}]}; 400 for a day that is no date; 503 without Copilot; 502 when Copilot's
       answer cannot be used. The log gets counts only, never a title. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $day = Get-MeetingDayValue $b
    if (-not $day) { return @{ status = 400; body = @{ error = 'day must be a date written yyyy-mm-dd.' } } }
    if (-not (Test-CopilotReady $State)) { return (Get-CopilotMissing 'meetings') }
    $ref = New-RequestRef
    $a = Send-MeetingQuestion $State (New-MeetingDayPrompt -Day $day -Ref $ref)
    if (-not $a.ok) { return @{ status = 502; body = @{ error = $a.error } } }
    $x = ConvertFrom-MeetingDayReply -Reply $a.text -Day $day -Ref $ref
    if (-not $x.ok) { return @{ status = 502; body = @{ error = "Copilot's list of meetings could not be read: $($x.error) Try again." } } }
    # How Copilot wrote the transcript/recap/notes yes-no fields, as counts (2026-11-18): tells a list
    # that said no from one that said yes as text. Never a title.
    $ff = $x.flagForms
    Write-AppLog info server 'Meetings of a day listed' @{ meetings = @($x.meetings).Count; readable = @($x.meetings | Where-Object { $_.readable }).Count; flagsJsonTrue = $ff.jsonTrue; flagsTextYes = $ff.textYes; flagsNo = $ff.no; flagsMissing = $ff.missing }
    # Each meeting's series and how many of its meetings are in the wiki already (another day), so the
    # window can say "part of a series" (operator, 2026-11-18). 0 when no vault is open.
    # inWiki / waiting (2026-11-18: fetched several times a day): this meeting has its page already, or
    # its Add still waits for Copilot; the window does not tick it and says so.
    $counts = Get-MeetingSeriesCounts $State
    foreach ($m in @($x.meetings)) {
        $m.series = Get-MeetingSeriesName $m.title
        $k = Get-MeetingSeriesKey $m.series
        $at = Format-MeetingAt -Day $day -Time $m.time
        $starts = @(if ($counts.pages.ContainsKey($k)) { $counts.pages[$k] })
        $m.earlier = @($starts | Where-Object { (Get-MeetingDayOf $_) -ne $day }).Count
        $m.inWiki = [bool]@($starts | Where-Object { Test-MeetingSameOccurrence $_ $at }).Count
        $m.waiting = [bool]@($counts.waiting | Where-Object { $_.key -eq $k -and (Test-MeetingSameOccurrence $_.at $at) }).Count
    }
    @{ status = 200; body = @{ day = $day; meetings = @($x.meetings) } }
}

function Invoke-MeetingsNotesRoute($State, [string]$Body) {
    <# POST /api/meetings/notes {title, start?, time?, day?}: one meeting's notes, written by Copilot
       from its transcript, recap or notes, as the text an Add files (lib/Meetings.psm1). Read only:
       the window then sends that text to POST /api/submit with origin "meeting", so the page is made,
       linked and undone like any Add. 200 {found:true, text, attendees, decisions, actions, basedOn}
       (counts) or {found:false, message}; 400; 503 without Copilot; 502 when the answer cannot be
       used. The log gets counts only. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $title = "$(Get-BodyValue $b 'title' '')".Trim()
    if (-not $title -or $title.Length -gt 200) { return @{ status = 400; body = @{ error = 'title must be the meeting''s title (at most 200 characters).' } } }
    $day = Get-MeetingDayValue $b
    if (-not $day) { return @{ status = 400; body = @{ error = 'day must be a date written yyyy-mm-dd.' } } }
    if (-not (Test-CopilotReady $State)) { return (Get-CopilotMissing 'meetings') }
    $start = "$(Get-BodyValue $b 'start' '')".Trim()
    $time = "$(Get-BodyValue $b 'time' '')".Trim()
    if ($time -notmatch '^\d{1,2}:\d{2}$') { $time = '' }
    $ref = New-RequestRef
    $a = Send-MeetingQuestion $State (New-MeetingNotesPrompt -Title $title -Start $start -Ref $ref)
    if (-not $a.ok) { return @{ status = 502; body = @{ error = $a.error } } }
    $n = ConvertFrom-MeetingNotesReply -Reply $a.text -Day $day -Ref $ref
    if (-not $n.ok) { return @{ status = 502; body = @{ error = $(if ($n.error -match 'Copilot answered with') { $n.error } else { "Copilot's notes could not be read: $($n.error) Try again." }) } } }
    # Counts only: never a name or an address in the log.
    $withMail = @(@($n.attendees) | Where-Object { $_ -is [Collections.IDictionary] -and $_['email'] }).Count
    Write-AppLog info server 'Meeting notes read' @{ found = $n.found; attendees = @($n.attendees).Count; withAddress = $withMail; decisions = @($n.decisions).Count; actions = @($n.actions).Count }
    if (-not $n.found) { return @{ status = 200; body = @{ found = $false; message = 'Copilot could not read a transcript, recap or notes of this meeting.' } } }
    @{ status = 200; body = @{ found = $true; text = (ConvertTo-MeetingNoteText -Title $title -Day $day -Time $time -Notes $n); attendees = @($n.attendees).Count; withAddress = $withMail; decisions = @($n.decisions).Count; actions = @($n.actions).Count; basedOn = $n.basedOn } }
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
$script:VaultKept = $false
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
    <# @{ adapter; vaults (Get-VaultList); notebooks (Get-NotebookList); message; kept }. Cached for a
       few seconds (the window asks for the list and the status often). Read only.
       THE one place the server learns which vaults are open: every route takes "is this the active
       vault" from this list. The vault this session opened ($State.Vault) is therefore put back here
       when a detection does not list it while its notebook is still open (Join-ActiveVault,
       lib/VaultSession.psm1; kept = that happened): the active vault is never demoted to a read-only
       notebook by what OneNote answers later (operator, 2026-11-15). #>
    $c = $script:VaultCache
    if (-not $Fresh -and $c -and $c.at.ElapsedMilliseconds -lt $script:CacheMs -and $c.key -eq $State.Id) { return $c.data }
    $data = @{ adapter = $null; vaults = @(); notebooks = @(); message = ''; kept = $false }
    try {
        $ad = Get-ServerAdapter $State
        if (-not $ad) { $data.message = $script:NotRunning; return $data }
        $data.adapter = $ad
        $found = @(Get-VaultList -Adapter $ad)
        $j = Join-ActiveVault -Vaults $found -Notebooks @(Get-NotebookList -Adapter $ad -Vaults $found) -Record $State.Vault
        $data.vaults = @($j.vaults); $data.notebooks = @($j.notebooks); $data.kept = [bool]$j.kept
        # One log line when it starts and one when it ends (counts only), not one per read.
        if ($data.kept -ne $script:VaultKept) {
            $script:VaultKept = $data.kept
            Write-AppLog info server $(if ($data.kept) { 'Active vault not listed by OneNote; kept from its record' } else { 'Active vault listed by OneNote again' }) @{ vaults = $data.vaults.Count; notebooks = $data.notebooks.Count }
        }
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

function Get-VaultModeInfo($State) {
    <# Why the active vault is read only, for GET /api/status (pure, from the same lease record the
       start and the renewal keep): @{ mode; reason; since; detail }.
       reason: '' as the writer; this-pc = the lease is held by another session of this computer;
       other-pc = by another computer, by a lease without a machine mark (an older version), or this
       session's own lease could not be renewed; not-opened = no vault is open (mode none), with the
       start's Vault line as detail. since: when the holder took the lease (ISO, UTC), '' unknown.
       until: when the holder's lease runs out unless it is renewed (ISO, UTC); renewed: when the
       holder last renewed it (until minus the lease time). A holder that renews every minute is
       still running; one that stopped lets this window take over at "until" (operator, 2026-11-15:
       "Check again" did not clear the note, and the note could not say what it was waiting for). #>
    $mode = Get-LeaseMode $State
    $r = [ordered]@{ mode = $mode; reason = ''; since = ''; until = ''; renewed = ''; detail = '' }
    if ($mode -eq 'none') { $r.reason = 'not-opened'; $r.detail = [string]$State.VaultDetail; return $r }
    if ($mode -eq 'writer') { return $r }
    $l = $State.Lease
    # Get-JsonProp reads a hashtable (the record) or an object alike, and gives the default for a
    # record made before these fields existed.
    $here = [bool](Get-JsonProp $l 'holderHere' $false)
    $r.reason = if ($here) { 'this-pc' } else { 'other-pc' }
    $holder = [string](Get-JsonProp $l 'holder' '')
    $acq = Get-JsonProp $l 'acquired' $null
    if ($holder -and $holder -ne [string](Get-JsonProp $l 'sessionId' '') -and $acq -is [datetime] -and $acq -gt [datetime]::MinValue) {
        $r.since = ([datetime]$acq).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    $exp = Get-JsonProp $l 'expires' $null
    if ($holder -and $holder -ne [string](Get-JsonProp $l 'sessionId' '') -and $exp -is [datetime] -and $exp -gt [datetime]::MinValue) {
        $iso = { param($t) ([datetime]$t).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
        $r.until = & $iso $exp
        $r.renewed = & $iso (([datetime]$exp).AddSeconds(-(Get-LeaseTimings).ttlSec))
    }
    $r
}

function Invoke-LeaseCheckRoute($State) {
    <# POST /api/vault/check-lease: "Check again" on the read-only note. Tries to take the writer lease
       now (the same Update-SessionLease the start's renewal runs every minute) instead of waiting
       for the next renewal, then answers what GET /api/status says about the vault. It only takes
       a lease that is free or has run out; one another ObsidiNote still renews is never taken. #>
    if (-not $State.Vault) { return @{ status = 409; body = @{ error = $script:NoVault } } }
    $d = Get-VaultData $State
    if (-not $d.adapter) { return @{ status = 503; body = @{ error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } } }
    [Threading.Monitor]::Enter($State.Lock)
    try {
        $State.Lease = Update-SessionLease -Adapter $d.adapter -Vault $State.Vault -SessionId $State.SessionId -Lease $State.Lease
    } finally { [Threading.Monitor]::Exit($State.Lock) }
    $why = Get-VaultModeInfo $State
    @{ status = 200; body = [pscustomobject]@{ name = [string]$State.Vault.name; vaultId = [string]$State.Vault.vaultId; mode = $why.mode; reason = $why.reason; since = $why.since; until = $why.until; renewed = $why.renewed; detail = $why.detail } }
}

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
    $why = Get-VaultModeInfo $State
    [pscustomobject]@{
        app     = 'ObsidiNote'
        version = (Get-AppVersionText $State.AppRoot)
        uiPort  = [int]$State.Port
        oneNote = [pscustomobject]@{ state = $one; running = ($one -ne 'none'); notebookOpen = [bool]$name; notebook = $(if ($name) { $name } else { 'ObsidiNote' }) }
        copilot = [pscustomobject]@{ state = (Get-CopilotState $State); port = [int]$State.CdpPort; ready = (Test-CopilotReady $State) }
        vault   = [pscustomobject]@{ name = $name; vaultId = $(if ($State.Vault) { [string]$State.Vault.vaultId } else { '' }); mode = $why.mode; reason = $why.reason; since = $why.since; until = $why.until; renewed = $why.renewed; detail = $why.detail }
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
        $o = Open-VaultSession -Adapter $ad -Vault $Vault -SessionId $State.SessionId -Vaults $Data.vaults -LocalSettings (Get-LocalVaultSettings $State)
        $State.Vault = $o.vault; $State.Lease = $o.lease; $State.VaultSettings = $o.settings
        $State.SettingsUnreadable = [bool]($o.settingsResult -and $o.settingsResult.status -eq 'unreadable')
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

function Get-LocalVaultSettings($State) {
    <# Local values that fill a vault setting missing in OneNote, once (internalHosts from before
       2026-11-14, when it was a local setting). Never replaces a value in OneNote. #>
    @{ internalHosts = @(@(Get-AppSetting -Key 'internalHosts' -Default @() -AppRoot $State.AppRoot) | ForEach-Object { "$_" } | Where-Object { $_ }) }
}

function Get-VaultSettingValue($State, [string]$Key) {
    <# One setting of the active vault (in OneNote), else its default. #>
    $set = $State.VaultSettings
    if ($set -and $set.Contains($Key)) { return $set[$Key] }
    (Get-VaultSettingDefaults)[$Key]
}

function Get-AddOptions($State) {
    <# Add's options from the vault's settings: how many related pages a new page links to. #>
    @{ RelatedCount = [int](Get-VaultSettingValue $State 'relatedCount') }
}

function Get-ServerLinkRules($State) {
    <# The link rules: the vault's "internalHosts" setting (in OneNote, lib/VaultSettings.psm1), and
       the company's tenant names from the active vault's location and the notebook record (never
       stored; Get-CompanyNames). The vault store files with them and the graph's Sources view groups
       with them, so both agree on internal vs web. #>
    $loc = if ($State.Vault) { [string]$State.Vault.location } else { '' }
    $set = $State.VaultSettings
    # Get-LinkRules (lib/NotebookStructure.psm1) is the one place the rules are put together; the
    # start's upgrade store in obsidinote.ps1 calls it with the same values.
    Get-LinkRules -InternalHosts @(if ($set -and $set.Contains('internalHosts')) { @($set['internalHosts']) } else { @() }) -Locations @($loc, (Get-NotebookRecord -AppRoot $State.AppRoot))
}

function Get-SourceLinkRules($State, $Adapter, $Vault = $null, $Notebooks = @(), $Notebook = $null) {
    <# The link rules of the source a graph SHOWS when it is not the active vault (code review
       2026-11-15: it was grouped with the active vault's rules). Another vault: its own
       "internalHosts" setting (read only from its state page) and the company names of its own
       location and its notebook's. A connected notebook has no settings: the fixed host rules plus
       the company names of its own location. Nothing of the active vault is mixed in, so a source
       kept on this PC only (no SharePoint or OneDrive address) has no company names. #>
    if ($Vault) {
        $nb = @($Notebooks | Where-Object { $_.id -eq $Vault.notebookId }) | Select-Object -First 1
        $hosts = @((Read-VaultSettings -Adapter $Adapter -IndexSectionId ([string]$Vault.indexSectionId))['internalHosts'])
        return (Get-LinkRules -InternalHosts $hosts -Locations @([string]$Vault.location, $(if ($nb) { [string]$nb.location } else { '' })))
    }
    Get-LinkRules -Locations @($(if ($Notebook) { [string]$Notebook.location } else { '' }))
}

function New-ServerStore($State, $Use) {
    <# The vault store for one request, with the link rules of Get-ServerLinkRules. #>
    $st = $State
    $rules = Get-ServerLinkRules $State
    New-VaultStore -Adapter $Use.adapter -Vault $State.Vault -Model $Use.model -GetLease { $st.Lease }.GetNewClosure() -InternalHosts $rules.InternalHosts -CompanyNames $rules.CompanyNames
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
# Add (new items, link updates, "Check for the answer"'s linking step) is never stopped, so its wait
# only decides how long the window stays busy before the item shows as waiting with "Check for the
# answer" (user, 2026-11-13: about 2 minutes; it could be busy for 15).
$script:AddWait = @{ TimeoutSec = 120; StallSec = 120; MaxTimeoutSec = 0; BusyWaitSec = 60 }

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
    $w = $script:AddWait
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

# How long one reconnect may look for Copilot's message box after a sign-in redirect. The request
# loop is the server's only thread, so this is short; a sign-in that still has to happen is left to
# the person (state 'sign-in'), who presses the button again afterwards.
$script:ReconnectSignInSec = 15

function Invoke-CopilotReconnectRoute($State) {
    <# POST /api/copilot/reconnect: the refresh button next to "Copilot is not connected" in the
       window's side bar (user, 2026-11-14). One attempt to attach to Copilot in ObsidiNote's Edge
       window (Connect-Copilot starts that Edge when it is closed), without the start's 10-minute
       sign-in wait. 200 {state, message}: connected | sign-in | failed. 409 when this start skipped
       Copilot (-NoCopilot). The log gets the outcome only. #>
    if ($State.CopilotSkipped) { return @{ status = 409; body = @{ state = 'skipped'; error = 'Copilot is off for this start. Start ObsidiNote again without -NoCopilot.' } } }
    if ((Get-CopilotState $State) -eq 'connected') { return @{ status = 200; body = @{ state = 'connected'; message = '' } } }
    if ($State.TestConnect) { $connect = $State.TestConnect }
    else {
        Import-Module (Join-Path $script:Here 'CopilotBridge.psm1') -Global
        $cmd = Get-Command Connect-Copilot
        $sec = $script:ReconnectSignInSec
        $connect = { & $cmd -SignInTimeoutSec $sec -NoSignInWait }.GetNewClosure()
    }
    $b = $null
    try { $b = & $connect }
    catch {
        Write-AppLog info server 'Copilot reconnect failed'
        return @{ status = 200; body = @{ state = 'failed'; message = "Copilot could not be reached: $($_.Exception.Message)" } }
    }
    if (-not $b) { return @{ status = 200; body = @{ state = 'failed'; message = 'Copilot could not be reached. Start ObsidiNote again.' } } }
    if ($b.PSObject.Properties['SignInPending'] -and $b.SignInPending) {
        Close-CopilotBridge $b
        Write-AppLog info server 'Copilot reconnect: sign-in needed'
        return @{ status = 200; body = @{ state = 'sign-in'; message = "Sign in to Microsoft 365 Copilot in ObsidiNote's Edge window, then press the refresh button again." } }
    }
    $old = $State.Copilot
    $State.Copilot = $b
    if ($old) { Close-CopilotBridge $old }
    Write-AppLog info server 'Copilot reconnected'
    @{ status = 200; body = @{ state = 'connected'; message = '' } }
}

function Close-CopilotBridge($Bridge) {
    <# Lets go of a bridge's tab connection; never throws (a lost one is already closed). #>
    # Through Get-Command: CopilotBridge.psm1 is imported on use (-Global), not by this module.
    try { $c = Get-Command Disconnect-Copilot -ErrorAction SilentlyContinue; if ($c) { & $c $Bridge } } catch { }
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
    if (-not (Test-JsonObject $b)) { throw 'The request is not a JSON object.' }
    $b
}

function Test-JsonObject($Value) {
    <# True only for a JSON object from ConvertFrom-Json. The full type name on purpose:
       [pscustomobject] is PSObject, which a bare number, text, true or a list is too once it came
       out of a cmdlet, so `-is [pscustomobject]` let them through as objects (code review 2026-11-15). #>
    $null -ne $Value -and $Value -is [System.Management.Automation.PSCustomObject]
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
            $m = ConvertTo-GraphModel -Model $u.model -Source @{ kind = 'vault'; id = $v.vaultId; name = $v.name; readOnly = ((Get-LeaseMode $State) -ne 'writer'); readOnlyReason = 'lease' } -LinkRules (Get-ServerLinkRules $State)
        } else {
            $model = Read-IndexModel -Adapter $d.adapter -IndexSectionId $v.indexSectionId -VaultId $v.vaultId -RootId $v.rootId
            $m = ConvertTo-GraphModel -Model $model -Source @{ kind = 'vault'; id = $v.vaultId; name = $v.name; readOnly = $true; readOnlyReason = 'not-active' } -LinkRules (Get-SourceLinkRules $State $d.adapter $v $d.notebooks)
        }
        $m['edgesComplete'] = $true
        # The page types and their sections, for the page window's Edit (a type stays in its section).
        $typeList = Get-ObsnTypes   # returns ', @(...)': assign as is, never wrap in @() (AGENTS.md)
        $m['types'] = @(foreach ($t in $typeList) { [ordered]@{ type = [string]$t; bucket = (Get-BucketForType -Type ([string]$t)) } })
        return @{ status = 200; body = $m }
    }
    $nb = @($d.notebooks | Where-Object { $_.id -eq $nid }) | Select-Object -First 1
    if (-not $nb) { return @{ status = 404; body = @{ error = 'That notebook is not open in OneNote.' } } }
    $c = Get-ForeignGraphModel $State $d.adapter $nb $d.vaults
    $m = ConvertTo-GraphModel -Model $c.model -Source @{ kind = 'notebook'; id = $nb.id; name = $nb.name; readOnly = $true; readOnlyReason = 'notebook' } -LinkRules (Get-SourceLinkRules $State $d.adapter $null $d.notebooks $nb)
    $m['edgesComplete'] = [bool]$c.done
    @{ status = 200; body = $m }
}

function Get-ExportSource($State, [string]$VaultId, [string]$NotebookId) {
    <# The index model to export from, like GET /api/graph: a vault (the active one when neither is
       given) or a connected notebook. @{ ok; model; name; adapter } or @{ ok = $false; status; error }. #>
    $d = Get-VaultData $State
    if (-not $d.adapter) { return @{ ok = $false; status = 503; error = $(if ($d.message) { $d.message } else { $script:NotRunning }) } }
    $v = $null
    if ($VaultId) { $v = @($d.vaults | Where-Object { $_.vaultId -eq $VaultId }) | Select-Object -First 1; if (-not $v) { return @{ ok = $false; status = 404; error = 'That vault is not open in OneNote.' } } }
    elseif ($NotebookId) { $v = @($d.vaults | Where-Object { (Get-VaultListId $_) -eq $NotebookId }) | Select-Object -First 1 }
    elseif ($State.Vault) { $v = @($d.vaults | Where-Object { $_.vaultId -eq $State.Vault.vaultId }) | Select-Object -First 1 }
    else { return @{ ok = $false; status = 409; error = 'No vault is open.' } }
    if ($v) {
        if ($State.Vault -and $v.vaultId -eq $State.Vault.vaultId) {
            $u = Use-ActiveVault $State
            if (-not $u.ok) { return @{ ok = $false; status = $u.status; error = $u.error } }
            return @{ ok = $true; model = $u.model; name = $v.name; adapter = $d.adapter }
        }
        return @{ ok = $true; model = (Read-IndexModel -Adapter $d.adapter -IndexSectionId $v.indexSectionId -VaultId $v.vaultId -RootId $v.rootId); name = $v.name; adapter = $d.adapter }
    }
    $nb = @($d.notebooks | Where-Object { $_.id -eq $NotebookId }) | Select-Object -First 1
    if (-not $nb) { return @{ ok = $false; status = 404; error = 'That notebook is not open in OneNote.' } }
    $c = Get-ForeignGraphModel $State $d.adapter $nb $d.vaults -BudgetMs 0
    @{ ok = $true; model = $c.model; name = $nb.name; adapter = $d.adapter }
}

function Get-SourceIdError([string]$VaultId, [string]$NotebookId) {
    <# The 400 message for a vault or notebook id that is not one ('' when both are fine or absent);
       the one check of POST /api/export and GET /api/page/body before Get-ExportSource. #>
    if ($VaultId -and -not (Test-VaultIdText $VaultId)) { return 'vault must be a vault id.' }
    if ($NotebookId -and -not (Test-NotebookId $NotebookId)) { return 'notebook must be a OneNote notebook id.' }
    ''
}

function Test-MapPageKey([string]$Key) {
    <# A page id of the map: an obsn id (p1a), or n:<OneNote page id> for a page ObsidiNote did not make. #>
    $Key.Length -le 220 -and ((Test-ObsnId $Key) -or ($Key.StartsWith('n:') -and (Test-PageIdText $Key.Substring(2))))
}

function Get-PageBodyRoute($State, [string]$Query) {
    <# GET /api/page/body?page=<map page id>[&vault=|&notebook=]: the page's text as Markdown for the
       page window, { id, markdown, truncated, length } (lib/MarkdownExport.psm1 Get-PageBody). The
       source is found like POST /api/export with scope page (Get-ExportSource): the active vault
       without either id; another vault or a connected notebook is read too. Read only: one
       GetPageContent, built in memory, nothing kept and nothing on disk. 400 for a bad id, 404 for
       a page, vault or notebook that is not there, 409 without a vault. #>
    $key = Get-QueryValue $Query 'page'
    $vid = Get-QueryValue $Query 'vault'; $nid = Get-QueryValue $Query 'notebook'
    if (-not (Test-MapPageKey $key)) { return @{ status = 400; body = @{ error = 'page must be a page id of the map.' } } }
    $bad = Get-SourceIdError $vid $nid
    if ($bad) { return @{ status = 400; body = @{ error = $bad } } }
    $src = Get-ExportSource $State $vid $nid
    if (-not $src.ok) { return @{ status = $src.status; body = @{ error = $src.error } } }
    $ad = $src.adapter
    $read = { param([string]$OneNoteId) $ad.GetPageContent($OneNoteId) }.GetNewClosure()
    try { $x = Get-PageBody -Model $src.model -Key $key -ReadPage $read }
    catch { return @{ status = 500; body = @{ error = 'The page could not be read from OneNote. Try again.' } } }
    if ($x.ContainsKey('error')) { return @{ status = 404; body = @{ error = "Page $key is not in this vault's index." } } }
    @{ status = 200; body = [ordered]@{ id = [string]$x.id; markdown = [string]$x.markdown; truncated = [bool]$x.truncated; length = [int]$x.length } }
}

function Invoke-ExportRoute($State, [string]$Body) {
    <# POST /api/export {scope page|topic|all, vault?, notebook?, page?, topic?}: Markdown for one page
       (.md), a topic or everything (.zip), as a download the person asked for (user, 2026-11-13, the
       one exception to "content stays in OneNote"). Read only; built in memory, never on disk. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $scope = "$(Get-BodyValue $b 'scope' 'all')"
    $vid = "$(Get-BodyValue $b 'vault' '')"; $nid = "$(Get-BodyValue $b 'notebook' '')"
    $key = "$(Get-BodyValue $b 'page' '')"; $topic = "$(Get-BodyValue $b 'topic' '')"
    if (@('page', 'topic', 'all') -notcontains $scope) { return @{ status = 400; body = @{ error = 'scope must be page, topic or all.' } } }
    $bad = Get-SourceIdError $vid $nid
    if ($bad) { return @{ status = 400; body = @{ error = $bad } } }
    if ($scope -eq 'page' -and -not (Test-MapPageKey $key)) { return @{ status = 400; body = @{ error = 'page must be a page id of the map.' } } }
    if ($scope -eq 'topic' -and (-not $topic.Trim() -or $topic.Length -gt 300 -or $topic -match '[\x00-\x1f]')) { return @{ status = 400; body = @{ error = 'topic must be a topic path.' } } }
    $src = Get-ExportSource $State $vid $nid
    if (-not $src.ok) { return @{ status = $src.status; body = @{ error = $src.error } } }
    $ad = $src.adapter
    $read = { param([string]$OneNoteId) $ad.GetPageContent($OneNoteId) }.GetNewClosure()
    $x = New-MarkdownExport -Model $src.model -ReadPage $read -SourceName $src.name -Scope $scope -Key $key -Topic $topic
    if ($x.ContainsKey('error')) { return @{ status = 404; body = @{ error = $x.error } } }
    @{ status = 200; file = $x; body = @{ name = $x.name; pages = $x.pages; failed = $x.failed } }
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
    # origin: where an added text came from. One check for Add, Ingest and Edit (Resolve-OriginId in
    # lib/NotebookStructure.psm1: null = typed, text must be a known id). An Ask has no origin: it
    # ignores the field and is never refused for it.
    $origin = ''
    if ($route.intent -eq 'add') {
        $o = Resolve-OriginId (Get-BodyValue $b 'origin' $null)
        if (-not $o.ok) { return @{ status = 400; body = @{ error = $o.error } } }
        $origin = $o.origin
    }
    # fileUrl: a dropped file's OneDrive/SharePoint address (POST /api/file/locate); https only.
    $fileUrl = "$(Get-BodyValue $b 'fileUrl' '')"
    if ($fileUrl -and ($fileUrl -notmatch '^(?i)https://[^\s]+$' -or $fileUrl.Length -gt 2000)) { return @{ status = 400; body = @{ error = 'fileUrl must be an https address.' } } }
    $needsCopilot = -not ($route.intent -eq 'ask' -and $action -in 'save-page', 'save-open-question')
    if ($needsCopilot -and -not (Test-CopilotReady $State)) { return (Get-CopilotMissing $route.intent) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ intent = $route.intent; error = $u.error } } }
    if ($route.intent -eq 'add') {
        # allowDuplicate: "Add anyway" after Add found a page with the same title and type (2026-11-17).
        $dupOk = (Get-BodyValue $b 'allowDuplicate' $false) -eq $true
        $r = Invoke-AddRequest -Request @{ text = $text; mode = $route.ingestMode; origin = $origin; fileUrl = $fileUrl; allowDuplicate = $dupOk } -Store (New-ServerStore $State $u) -Ask (Get-AddCopilot $State) -Options (Get-AddOptions $State)
        $r['intent'] = 'add'
        return @{ status = 200; body = $r }
    }
    $req = @{ action = $(if ($action) { $action } else { 'ask' }); question = $text; includeArchived = [bool](Get-BodyValue $b 'includeArchived' $false)
        conversationId = "$(Get-BodyValue $b 'conversationId' '')"; turn = [int](Get-BodyValue $b 'turn' 0) }
    $wanted = @(@(Get-BodyValue $b 'sources' @()) | ForEach-Object { "$_" } | Where-Object { (Test-NotebookId $_) -or (Test-VaultIdText $_) })
    # series: Ask within one meeting series of the active vault, nothing else (2026-11-18). The series
    # key the window got from the map (lib/Meetings.psm1 Get-MeetingSeriesKey); other sources are dropped.
    $series = "$(Get-BodyValue $b 'series' '')".Trim()
    if ($series.Length -gt 200) { return @{ status = 400; body = @{ intent = 'ask'; error = 'series must be a meeting series of at most 200 characters.' } } }
    if ($series) { $req.series = Get-MeetingSeriesKey $series; $wanted = @() }
    if (-not $script:AskConversations) { $script:AskConversations = @{} }
    if ($req.action -eq 'follow-up' -and $script:AskConversations.ContainsKey($req.conversationId)) { $wanted = @($script:AskConversations[$req.conversationId]) }
    $req.sources = $wanted
    $ctx = @{ Sources = (Get-AskSourceList $State $u $wanted); Copilot = $(if ($needsCopilot) { Get-AskCopilotAdapter $State } else { $null }); StaleDays = [int](Get-VaultSettingValue $State 'linkStaleDays'); MaxPages = [int](Get-VaultSettingValue $State 'askMaxPages') }
    $r = Invoke-AskRequest -Request $req -Context $ctx
    $r['intent'] = 'ask'
    if ($r.ContainsKey('conversationId') -and $r.conversationId) { $script:AskConversations[[string]$r.conversationId] = $wanted }
    @{ status = 200; body = $r }
}

function Invoke-UndoRoute($State, [string]$Body) {
    <# POST /api/add/undo {undo[, vault]}: the Add's page to OneNote's Deleted Pages, its backlinks
       rewritten and the links other pages have to it taken out. 409 when vault is another vault's id. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    # The property itself, not Get-BodyValue: a function's output unrolls a list of one, so
    # {"undo":[{...}]} would arrive as the object inside it.
    # (and not `$undo = if ...`, which unrolls it the same way).
    $undo = $null
    if ($b.PSObject.Properties['undo']) { $undo = $b.PSObject.Properties['undo'].Value }
    if ($undo -is [array] -or -not (Test-JsonObject $undo)) { return @{ status = 400; body = @{ error = 'undo must be the Add result''s undo record.' } } }
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    @{ status = 200; body = (Undo-AddRequest -Store (New-ServerStore $State $u) -Undo $undo) }
}

# History and "Waiting for Copilot" can still show another vault's items after a switch (the list
# carries its vault's id, GET /api/activity): Undo, Remove and "Check for the answer" send it back as
# `vault`, and an item of a vault that is not the active one is refused before anything is read or
# written (code review 2026-11-15). Optional, like `vault` on /api/link/add and /api/page/edit.
$script:OtherVaultItem = 'This item belongs to another vault; open that vault to change it.'

function Test-OtherVault($State, $Body) {
    $vault = "$(Get-BodyValue $Body 'vault' '')"
    [bool]($vault -and (-not $State.Vault -or $vault -ne [string]$State.Vault.vaultId))
}

function Get-OtherVaultAnswer { @{ status = 409; body = @{ error = $script:OtherVaultItem } } }

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
    if (Test-OtherVault $State $b) { $a = Get-OtherVaultAnswer; $a.body['intent'] = 'add'; return $a }
    if (-not (Test-CopilotReady $State)) { return (Get-CopilotMissing 'add') }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ intent = 'add'; error = $u.error } } }
    $r = Receive-AddAnswer -Store (New-ServerStore $State $u) -Ask (Get-AddCopilot $State) -ReadChat (Get-AddChatReader $State) -InboxId $id -Options (Get-AddOptions $State)
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
    $r = Update-LinkSummary -Store (New-ServerStore $State $u) -Ask $ask -Id $id -Decision $decision -Proposed $proposed -Options (Get-AddOptions $State)
    $r['intent'] = 'add'
    @{ status = 200; body = $r }
}

function Invoke-LinkAddRoute($State, [string]$Body) {
    <# POST /api/link/add {from, to[, vault]}: "Link it" for a mention in the active vault (lib/Ingest.psm1
       Add-PageLink; no Copilot). 400 bad or equal ids, 409 another source or read only, 404 a page
       that is not in the index, 200 linked or already-linked. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $from = "$(Get-BodyValue $b 'from' '')"; $to = "$(Get-BodyValue $b 'to' '')"
    if (-not (Test-ObsnId $from) -or -not (Test-ObsnId $to)) { return @{ status = 400; body = @{ error = 'from and to must be ObsidiNote page ids.' } } }
    if ($from -eq $to) { return @{ status = 400; body = @{ error = 'A page cannot be linked to itself.' } } }
    $vault = "$(Get-BodyValue $b 'vault' '')"
    if ("$(Get-BodyValue $b 'notebook' '')" -or ($vault -and (-not $State.Vault -or $vault -ne [string]$State.Vault.vaultId))) {
        return @{ status = 409; body = @{ error = 'Only pages of the active vault can be linked; other sources are read only.' } }
    }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $r = Add-PageLink -Store (New-ServerStore $State $u) -From $from -To $to
    $code = switch ($r.status) { 'linked' { 200 } 'already-linked' { 200 } 'refused' { 409 } 'not-found' { 404 } 'invalid' { 400 } default { 500 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = $r }
}

function Invoke-PageEditRoute($State, [string]$Body) {
    <# POST /api/page/edit {id, title?, type?, topics?, aliases?, summary?, url?, links?, origin?[, vault]}: the
       person edits a page of the active vault in the window (lib/Ingest.psm1 Edit-Page; no Copilot).
       Only the fields sent change. 400 bad input, 409 another source or read only, 404 not in the index,
       200 edited or unchanged. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $id = "$(Get-BodyValue $b 'id' '')"
    if (-not (Test-ObsnId $id)) { return @{ status = 400; body = @{ error = 'id must be an ObsidiNote page id.' } } }
    $vault = "$(Get-BodyValue $b 'vault' '')"
    if ("$(Get-BodyValue $b 'notebook' '')" -or ($vault -and (-not $State.Vault -or $vault -ne [string]$State.Vault.vaultId))) {
        return @{ status = 409; body = @{ error = 'Only pages of the active vault can be changed; other sources are read only.' } }
    }
    $ch = @{}
    foreach ($k in 'title', 'type', 'summary', 'url', 'origin') {
        if (-not $b.PSObject.Properties[$k]) { continue }
        $v = $b.$k
        if ($null -ne $v -and $v -isnot [string]) { return @{ status = 400; body = @{ error = "$k must be text." } } }
        $ch[$k] = [string]$v
    }
    foreach ($k in 'topics', 'aliases', 'tags') {
        if (-not $b.PSObject.Properties[$k]) { continue }
        $v = @($b.$k | Where-Object { $null -ne $_ })
        if (@($v | Where-Object { $_ -isnot [string] }).Count) { return @{ status = 400; body = @{ error = "$k must be a list of text." } } }
        $ch[$k] = @($v)
    }
    if ($b.PSObject.Properties['links']) {
        $ls = @($b.links | Where-Object { $null -ne $_ })
        if (@($ls | Where-Object { -not (Test-JsonObject $_) -or -not $_.PSObject.Properties['target'] -or -not (Test-ObsnId "$($_.target)") }).Count) { return @{ status = 400; body = @{ error = 'links must be a list of {target, strength, why} with ObsidiNote page ids.' } } }
        $ch.links = @($ls | ForEach-Object { @{ target = "$($_.target)"; strength = $(if ($_.PSObject.Properties['strength']) { [int]$_.strength } else { 1 }); why = $(if ($_.PSObject.Properties['why']) { "$($_.why)" } else { '' }) } })
    }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $r = Edit-Page -Store (New-ServerStore $State $u) -Id $id -Changes $ch
    $code = switch ($r.status) { 'edited' { 200 } 'unchanged' { 200 } 'refused' { 409 } 'not-found' { 404 } 'invalid' { 400 } default { 500 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = $r }
}

function Read-TextList($Body, [string]$Name) {
    <# A list-of-text field of a request body: @{ ok; list; error }. Absent or null = an empty list;
       a text, a number or a list holding anything but text is refused. #>
    if (-not $Body.PSObject.Properties[$Name] -or $null -eq $Body.$Name) { return @{ ok = $true; list = @(); error = '' } }
    $v = $Body.$Name
    if ($v -isnot [array] -or @($v | Where-Object { $_ -isnot [string] }).Count) { return @{ ok = $false; list = @(); error = "$Name must be a list of text." } }
    @{ ok = $true; list = @($v); error = '' }
}

function Invoke-PagesTagRoute($State, [string]$Body) {
    <# POST /api/pages/tag {ids, add, remove[, vault]}: the person tags pages of the active vault
       (lib/Ingest.psm1 Set-PageTags; no Copilot). 200 {changed, pages: [{id, tags}], warnings};
       400 an invalid tag, no ids, more than 200, nothing to add or remove; 404 an id that is not a
       page of the vault (nothing written); 409 another vault's item or no writer lease. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $lists = @{}
    foreach ($k in 'ids', 'add', 'remove') {
        $l = Read-TextList $b $k
        if (-not $l.ok) { return @{ status = 400; body = @{ error = $l.error } } }
        $lists[$k] = @($l.list)
    }
    if (-not $lists.ids.Count) { return @{ status = 400; body = @{ error = 'Choose at least one page.' } } }
    if ($lists.ids.Count -gt 200) { return @{ status = 400; body = @{ error = 'At most 200 pages at a time.' } } }
    if (@($lists.ids | Where-Object { -not (Test-ObsnId $_) }).Count) { return @{ status = 400; body = @{ error = 'ids must be ObsidiNote page ids.' } } }
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $r = Set-PageTags -Store (New-ServerStore $State $u) -Ids ([string[]]$lists.ids) -Add $lists.add -Remove $lists.remove
    $code = switch ($r.status) { 'tagged' { 200 } 'refused' { 409 } 'not-found' { 404 } 'invalid' { 400 } default { 500 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = [ordered]@{ changed = [int]$r.changed; pages = [object[]]@($r.pages); warnings = [object[]]@($r.warnings) } }
}

function Invoke-PagesRetireRoute($State, [string]$Body, [string]$Action) {
    <# POST /api/pages/archive | /api/pages/delete {ids, confirm[, vault]} and /api/pages/restore
       {ids[, vault]} (lib/Ingest.psm1 Get-RetirePlan / Invoke-PageRetire; no Copilot). Archive and
       delete always ask first (FEASIBILITY.md, Archive and delete): without confirm = true they answer
       409 {needsConfirm, plan: {pages: [{id, title, section, to, inbound}], refused: [{id, title,
       reason}]}} and write nothing; the window shows that plan in its dialog. Restore is the undo of
       an archive and needs no confirm. 200 {status done|partial|failed, message, action, done,
       refused, failed, warnings}; 400 no ids, more than 200, nothing that can be done; 409 another
       vault's items or no writer lease. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $l = Read-TextList $b 'ids'
    if (-not $l.ok) { return @{ status = 400; body = @{ error = $l.error } } }
    $ids = @($l.list | Select-Object -Unique)
    if (-not $ids.Count) { return @{ status = 400; body = @{ error = 'Choose at least one page.' } } }
    if ($ids.Count -gt 200) { return @{ status = 400; body = @{ error = 'At most 200 pages at a time.' } } }
    # A page key of the map: ObsidiNote's own (p...) or a page the person made (n:<OneNote id>). The
    # plan refuses the second kind with words for a person ("A page you made yourself is moved or
    # deleted in OneNote"); before, the whole request failed with "ids must be ObsidiNote page ids"
    # (operator, 2026-11-16, deleting a test page). Anything else is no page of a map.
    if (@($ids | Where-Object { -not (Test-ObsnId $_) -and $_ -notmatch '^n:[{}A-Za-z0-9-]{1,120}$' }).Count) { return @{ status = 400; body = @{ error = 'These are not pages of this map.' } } }
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $store = New-ServerStore $State $u
    $c = Get-BodyValue $b 'confirm' $false
    if ($Action -ne 'restore' -and -not ($c -is [bool] -and $c)) {
        $plan = Get-RetirePlan -Store $store -Action $Action -Ids ([string[]]$ids)
        $verb = if ($Action -eq 'archive') { 'Archive' } else { 'Delete' }
        return @{ status = 409; body = [ordered]@{ needsConfirm = $true; error = "$verb asks first: confirm to go ahead."; plan = [ordered]@{ pages = [object[]]@($plan.pages); refused = [object[]]@($plan.refused) } } }
    }
    $r = Invoke-PageRetire -Store $store -Action $Action -Ids ([string[]]$ids)
    $code = switch ($r.status) { 'refused' { 409 } 'invalid' { 400 } default { 200 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = [ordered]@{ status = $r.status; message = $r.message; action = $Action; done = [object[]]@($r.done); refused = [object[]]@($r.refused); failed = [object[]]@($r.failed); warnings = [object[]]@($r.warnings) } }
}

function Invoke-SeriesMergeRoute($State, [string]$Body) {
    <# POST /api/series/merge {series, confirm[, vault]} (lib/Ingest.psm1 Get-SeriesMergePlan /
       Invoke-SeriesMerge; no Copilot; operator, 2026-11-19): the copies of one meeting of a series
       become one page, the other copies go to the Archive. Like Archive it always asks first: without
       confirm = true it answers 409 {needsConfirm, plan: {series, groups: [{keep: {id, title}, extra:
       [{id, title}]}]}} and writes nothing. 200 {status merged|partial|nothing, message, merged,
       warnings}; 400 no series; 409 another vault's item or no writer lease. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $s = Get-BodyValue $b 'series' ''
    if ($s -isnot [string] -or -not (Get-MeetingSeriesKey $s) -or $s.Length -gt 400) { return @{ status = 400; body = @{ error = 'Which meeting series?' } } }
    $key = Get-MeetingSeriesKey $s
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $store = New-ServerStore $State $u
    $c = Get-BodyValue $b 'confirm' $false
    if (-not ($c -is [bool] -and $c)) {
        $plan = Get-SeriesMergePlan -Index (& $store.GetIndex) -Key $key
        return @{ status = 409; body = [ordered]@{ needsConfirm = $true; error = 'Merging asks first: confirm to go ahead.'; plan = [ordered]@{ series = [string]$plan.series; groups = [object[]]@($plan.groups) } } }
    }
    $r = Invoke-SeriesMerge -Store $store -Key $key
    $code = switch ($r.status) { 'refused' { 409 } 'failed' { 500 } default { 200 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = [ordered]@{ status = $r.status; message = $r.message; merged = [int]$r.merged; warnings = [object[]]@($r.warnings) } }
}

function Invoke-TagRenameRoute($State, [string]$Body) {
    <# POST /api/tags/rename {from, to[, vault]}: every page of the active vault that has the tag
       `from` gets `to` in its place (no duplicate); to = '' removes it (lib/Ingest.psm1 Rename-Tag).
       200 {changed, warnings}; 400 invalid; 409 another vault's item or no writer lease. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $from = Get-BodyValue $b 'from' ''; $to = Get-BodyValue $b 'to' ''
    if ($from -isnot [string] -or $to -isnot [string]) { return @{ status = 400; body = @{ error = 'from and to must be text.' } } }
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $r = Rename-Tag -Store (New-ServerStore $State $u) -From $from -To $to
    $code = switch ($r.status) { 'renamed' { 200 } 'refused' { 409 } 'invalid' { 400 } default { 500 } }
    if ($code -ne 200) { return @{ status = $code; body = @{ error = $r.message; status = $r.status } } }
    @{ status = 200; body = [ordered]@{ changed = [int]$r.changed; warnings = [object[]]@($r.warnings) } }
}

function Get-SettingsRoute($State) {
    <# GET /api/settings: the active vault's settings (from OneNote, checked at the start or the vault
       switch; defaults without a vault) and whether this ObsidiNote may change them. #>
    $set = [ordered]@{}
    foreach ($k in $State.VaultSettings.Keys) { $set[$k] = $State.VaultSettings[$k] }
    if ($set.Contains('internalHosts')) { $set['internalHosts'] = [object[]]@($set['internalHosts'] | Where-Object { $_ }) }
    # Stored settings that cannot be read are never written over (Set-VaultSetting refuses with this
    # same sentence), so the window is told beforehand: canChange false, with the reason.
    $bad = [bool]($State.Vault -and $State.SettingsUnreadable)
    @{ status = 200; body = [ordered]@{ settings = $set; canChange = [bool]($State.Vault -and (Get-LeaseMode $State) -eq 'writer' -and -not $bad); message = $(if ($bad) { Get-UnreadableSettingsMessage } else { '' }) } }
}

function Set-SettingsRoute($State, [string]$Body) {
    <# POST /api/settings {key, value}: changes one vault setting in OneNote (Set-VaultSetting; the
       other keys stay). 400 unknown key or bad value, 409 no vault or read only. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $key = Get-BodyValue $b 'key' ''
    if ($key -isnot [string] -or -not (Get-VaultSettingDefaults).Contains($key)) { return @{ status = 400; body = @{ error = 'Unknown setting.' } } }
    $value = Get-BodyValue $b 'value' $null
    if ($value -is [array]) { $value = @($value) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    if ((Get-LeaseMode $State) -ne 'writer') { return @{ status = 409; body = @{ error = 'This ObsidiNote is read only; the window that holds the vault can change its settings.' } } }
    try { $eff = Set-VaultSetting -Adapter $u.adapter -IndexSectionId ([string]$State.Vault.indexSectionId) -Key $key -Value $value }
    catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $State.VaultSettings = $eff
    Reset-VaultCache
    Get-SettingsRoute $State
}

function Get-ActivityRoute($State) {
    <# GET /api/activity: what Add and link Update did in the active vault, from its Intake
       (lib/Activity.psm1): waiting, added, updated, failed, undone. Read only. #>
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    $v = $State.Vault
    # Only the Intake section is read (its id, then its pages), never the whole vault at page scope.
    $pages = @(Read-ObsnIntakePages -Adapter $u.adapter -RootId ([string]$v.rootId))
    $index = @{}
    foreach ($p in @($u.model.pages.Values)) { $index[[string]$p.key] = @{ title = [string]$p.title; type = [string]$p.type; entries = @(if ($p.ContainsKey('entries')) { @($p.entries) | Where-Object { $_ } | ForEach-Object { @{ ref = [string]$_['ref'] } } }) } }
    $items = Get-ActivityList -Pages $pages -Index $index   # returns , @(...): assign as is
    # vaultId: the vault these items belong to; the window sends it back as `vault` with Undo, Remove
    # and "Check for the answer", so an item listed before a vault switch is never applied to another.
    @{ status = 200; body = [ordered]@{ items = @($items); canChange = ((Get-LeaseMode $State) -eq 'writer'); vaultId = [string]$v.vaultId } }
}

function Invoke-IntakeRemoveRoute($State, [string]$Body) {
    <# POST /api/intake/remove {inboxId}: an Intake item that never became a page (waiting, failed,
       stopped) goes to OneNote's Deleted Pages. 400 bad id, 409 read only or an item that was filed
       (Undo removes its page instead). #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $id = "$(Get-BodyValue $b 'inboxId' '')"
    if (-not (Test-PageIdText $id)) { return @{ status = 400; body = @{ error = 'inboxId must be the Intake item''s page id.' } } }
    if (Test-OtherVault $State $b) { return (Get-OtherVaultAnswer) }
    $u = Use-ActiveVault $State
    if (-not $u.ok) { return @{ status = $u.status; body = @{ error = $u.error } } }
    if ((Get-LeaseMode $State) -ne 'writer') { return @{ status = 409; body = @{ error = 'This ObsidiNote is read only; the window that holds the vault can remove it.' } } }
    $store = New-ServerStore $State $u
    try { $item = & $store.ReadInboxItem $id } catch { return @{ status = 404; body = @{ error = 'That is not an item of this vault''s Intake.' } } }
    if (-not (Test-RemovableInboxStatus ([string]$item.status))) { return @{ status = 409; body = @{ error = 'This item became a page; use Undo to remove that page.' } } }
    try { & $store.DeletePage $id | Out-Null } catch { return @{ status = 500; body = @{ error = "It could not be removed: $($_.Exception.Message)" } } }
    Write-AppLog info server 'Intake item removed' @{ status = [string]$item.status }
    @{ status = 200; body = @{ status = 'removed'; message = "Removed. It is in OneNote's Deleted Pages for 60 days." } }
}

function Invoke-FileLocateRoute($State, [string]$Body) {
    <# POST /api/file/locate {name, size, modified (ms since 1970, UTC)}: the web address of a dropped
       file when it is in a folder OneDrive syncs here (lib/SyncedFiles.psm1). 200 {status, url};
       400 for a bad request. Reads directory entries only; the log gets the status and time. #>
    try { $b = Read-JsonBody $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
    $name = Get-BodyValue $b 'name' ''
    $size = Get-BodyValue $b 'size' $null
    $mod = Get-BodyValue $b 'modified' $null
    if ($name -isnot [string] -or -not $name -or $name.Length -gt 255 -or $name -match '[\\/:*?"<>|\x00-\x1f]') { return @{ status = 400; body = @{ error = 'name must be a file name.' } } }
    if (-not ($size -is [int] -or $size -is [long]) -or $size -lt 0) { return @{ status = 400; body = @{ error = 'size must be a whole number.' } } }
    if (-not ($mod -is [int] -or $mod -is [long] -or $mod -is [double]) -or $mod -le 0) { return @{ status = 400; body = @{ error = 'modified must be a time in milliseconds.' } } }
    $when = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$mod).UtcDateTime
    $r = if ($State.ContainsKey('TestSyncRoots') -and $null -ne $State.TestSyncRoots) { Find-SyncedFile -Name $name -Size ([int64]$size) -ModifiedUtc $when -Roots @($State.TestSyncRoots) } else { Find-SyncedFile -Name $name -Size ([int64]$size) -ModifiedUtc $when }
    $found = [string]$r.status; $took = [int]$r.ms   # the status and time only, never the name or address
    Write-AppLog info server 'File located' @{ status = $found; ms = $took }
    @{ status = 200; body = [ordered]@{ status = $r.status; url = $r.url } }
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
        'GET /api/page/body' { return (Get-PageBodyRoute $State $Query) }
        'GET /api/whats-new' { return @{ status = 200; body = (Get-WhatsNew -AppRoot $State.AppRoot -UpdatedTo "$($State.UpdatedTo)") } }
        'POST /api/active-vault' { return (Set-ActiveVault $State $Body) }
        'POST /api/vault/new' { return (New-VaultRoute $State $Body) }
        'POST /api/vault/setup' { return (Set-UpVaultRoute $State $Body) }
        'POST /api/intent' {
            try { $r = Read-IntentRequest $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
            # The vault's link rules, so "a company link with your words" is named as the Add it will be.
            $lr = try { Get-ServerLinkRules $State } catch { @{ InternalHosts = @(); CompanyNames = @() } }
            return @{ status = 200; body = (Get-Intent -Text $r.text -Mode $r.mode -InternalHosts @($lr.InternalHosts) -CompanyNames @($lr.CompanyNames)) }
        }
        'POST /api/submit' { return (Invoke-SubmitRoute $State $Body) }
        'POST /api/add/undo' { return (Invoke-UndoRoute $State $Body) }
        'POST /api/add/fetch' { return (Invoke-AddFetchRoute $State $Body) }
        'POST /api/link/update' { return (Invoke-LinkUpdateRoute $State $Body) }
        'POST /api/link/add' { return (Invoke-LinkAddRoute $State $Body) }
        'POST /api/page/edit' { return (Invoke-PageEditRoute $State $Body) }
        'POST /api/export' { return (Invoke-ExportRoute $State $Body) }
        'POST /api/copilot/reconnect' { return (Invoke-CopilotReconnectRoute $State) }
        'GET /api/settings' { return (Get-SettingsRoute $State) }
        'GET /api/activity' { return (Get-ActivityRoute $State) }
        'POST /api/intake/remove' { return (Invoke-IntakeRemoveRoute $State $Body) }
        'POST /api/file/locate' { return (Invoke-FileLocateRoute $State $Body) }
        'POST /api/settings' { return (Set-SettingsRoute $State $Body) }
        'POST /api/pages/tag' { return (Invoke-PagesTagRoute $State $Body) }
        'POST /api/tags/rename' { return (Invoke-TagRenameRoute $State $Body) }
        'POST /api/pages/archive' { return (Invoke-PagesRetireRoute $State $Body 'archive') }
        'POST /api/series/merge' { return (Invoke-SeriesMergeRoute $State $Body) }
        'POST /api/pages/restore' { return (Invoke-PagesRetireRoute $State $Body 'restore') }
        'POST /api/pages/delete' { return (Invoke-PagesRetireRoute $State $Body 'delete') }
        # A new start on this PC asks this one to end (lib/Startup.psm1 Invoke-ReplaceRunning). The
        # answer is sent first; `stop` then ends the request loop (Invoke-ServerRequest), and
        # obsidinote.ps1's finally gives the writer lease back and disconnects, as on Ctrl+C.
        'POST /api/open' { return (Invoke-OpenUrlRoute $State $Body) }
        'POST /api/meetings/day' { return (Invoke-MeetingsDayRoute $State $Body) }
        'POST /api/meetings/notes' { return (Invoke-MeetingsNotesRoute $State $Body) }
        'POST /api/shutdown' { return @{ status = 200; body = @{ stopping = $true }; stop = $true } }
        'POST /api/vault/check-lease' { return (Invoke-LeaseCheckRoute $State) }
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
    if ($a.ContainsKey('file') -and $a.file) { return Send-Download $Ctx $a.file }
    # POST /api/shutdown: the flag first, so the loop ends even when the client is gone already.
    if ($a.ContainsKey('stop') -and $a.stop) { $State.StopReason = 'shutdown'; $State.Stop = $true }
    Send-Json $Ctx $a.body $a.status
}

function Get-ContentDisposition([string]$Name) {
    <# attachment with an ASCII fallback name and the full name as RFC 5987 UTF-8. #>
    $ascii = ($Name -replace '[^\x20-\x7e]', '_' -replace '["\\]', '_')
    "attachment; filename=""$ascii""; filename*=UTF-8''$([Uri]::EscapeDataString($Name))"
}

function Send-Download($Ctx, $File) {
    <# An export the person asked for (POST /api/export): the bytes straight from memory. #>
    $Ctx.Response.Headers['Content-Disposition'] = Get-ContentDisposition ([string]$File.name)
    Send-Bytes $Ctx 200 ([string]$File.type) ([byte[]]$File.bytes)
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

function Get-RunningUiVersion {
    <# The version an ObsidiNote server already running on $Port reports ('' when none answers). #>
    param([int]$Port)
    try {
        $s = Invoke-RestMethod "http://127.0.0.1:$Port/api/status" -Headers @{ 'X-ObsidiNote' = '1' } -TimeoutSec 5
        if ("$($s.app)" -eq 'ObsidiNote') { return "$($s.version)" }
    } catch { }
    ''
}

function Get-RunningUiProblem {
    <# Why a start must not just open the window of the ObsidiNote already running ('' when it may).
       Pure. An older server still running after an update serves the new ui\index.html, but its file
       allow-list was built at its own start, so the new hashed scripts answer 404 and the window stays
       white (v0.6.1 -> v0.7.0 on the target machine, 2026-11-14). #>
    param([AllowEmptyString()][string]$Running, [AllowEmptyString()][string]$Mine)
    if ($Running -eq $Mine) { return '' }
    $what = if ($Running) { "ObsidiNote $Running" } else { 'another ObsidiNote' }
    "$what still runs on this port; this is $Mine"
}

Export-ModuleMember -Function Get-AllowedOrigins, Test-AllowedOrigin, Test-AllowedHost, Get-RequestVerdict, Get-UiAllowList, Get-RunningUiVersion, Get-RunningUiProblem, Get-AppVersionText,
    Get-CopilotTabState, New-ServerState, Invoke-ApiRoute, Invoke-ServerLoop, Start-UiServer, Stop-UiServer, Test-UiServerRunning, Test-ClientGone,
    ConvertTo-NotebookListing, Get-SubmitRoute
