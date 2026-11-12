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
foreach ($m in 'Log', 'AppConfig', 'Startup', 'Intent', 'OneNoteHost', 'NotebookView', 'Update') {
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
    <# The shared state of one server: plain values only (it crosses into the server's runspace).
       -FakeStatus replaces /api/status; -FakeHierarchyXml replaces OneNote's GetHierarchy answer
       (every scope gets this XML, OneNote counts as running), so the tests run the real parsing. #>
    param([Parameter(Mandatory)][string]$AppRoot, [int]$Port, [int]$CdpPort = 9334, [bool]$CopilotSkipped = $false,
        $FakeStatus = $null, [string]$FakeHierarchyXml = '')
    $h = [hashtable]::Synchronized(@{})
    $h.AppRoot = $AppRoot; $h.Port = $Port; $h.CdpPort = $CdpPort; $h.CopilotSkipped = $CopilotSkipped
    $h.FakeStatus = $FakeStatus; $h.FakeHierarchyXml = $FakeHierarchyXml
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

function Get-CopilotState($State) {
    <# Read-only: lists the pages of ObsidiNote's Edge on its debug port; never attaches to a tab. #>
    if ($State.CopilotSkipped) { return 'skipped' }
    try { $pages = @(Invoke-RestMethod "http://127.0.0.1:$($State.CdpPort)/json/list" -TimeoutSec 2) } catch { return 'not-running' }
    $flat = @(foreach ($p in $pages) { $p })   # PS 5.1 hands a JSON array over as one object
    Get-CopilotTabState -Pages $flat -Hosts (Get-CopilotHostList $State.AppRoot)
}

function Read-NotebookData {
    <# THE one place the server reads notebooks (read only), so the full structure detection
       (Get-NotebookList / Get-NotebookModel) can replace it in one spot.
       'list'   -> @{ notebooks = @( @{ id; name; vault; active; location } ); message }
       'view'   -> one notebook's view (-Id, or the active vault)
       'record' -> @{ ok; record; name; message } for making vault -Id the active one #>
    param($State, [ValidateSet('list', 'view', 'record')][string]$What, [string]$Id = '')
    $record = Get-NotebookRecord -AppRoot $State.AppRoot
    $getState = { Get-OneNoteState }
    $read = @{}
    if ($State.FakeHierarchyXml) {
        $fake = [string]$State.FakeHierarchyXml
        $getState = { 'window' }
        $read = @{ GetXml = { param($startId, $scope) $fake }.GetNewClosure(); GetLink = { param($pageId) "onenote:https://example.com/notebook#page-id=$pageId" } }
    }
    $xmlOnly = @{}
    if ($read.ContainsKey('GetXml')) { $xmlOnly.GetXml = $read.GetXml }
    switch ($What) {
        'list' { return Get-OpenNotebookList -Record $record -GetState $getState @xmlOnly }
        'view' { return Get-NotebookView -Id $Id -Record $record -GetState $getState @read }
        'record' { return Get-VaultRecord -Id $Id -GetState $getState -ToRecord { param($path) ConvertTo-NotebookRecord $path } @xmlOnly }
    }
}

function Get-ServerStatus($State) {
    if ($State.FakeStatus) { return $State.FakeStatus }
    $one = Get-OneNoteState
    $active = $null
    if ($one -ne 'none') { $active = @((Read-NotebookData $State 'list').notebooks | Where-Object { $_.active }) | Select-Object -First 1 }
    [pscustomobject]@{
        app     = 'ObsidiNote'
        version = (Get-AppVersionText $State.AppRoot)
        uiPort  = [int]$State.Port
        oneNote = [pscustomobject]@{ state = $one; running = ($one -ne 'none'); notebookOpen = [bool]$active; notebook = $(if ($active) { $active.name } else { 'ObsidiNote' }) }
        copilot = [pscustomobject]@{ state = (Get-CopilotState $State); port = [int]$State.CdpPort }
    }
}

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

function Set-ActiveVault($State, [string]$Body) {
    <# POST /api/active-vault {id}: makes an open vault the active one by keeping its record in the
       "notebook" setting (the start reopens it). Writes no notebook; refuses read-only notebooks. #>
    $id = ''
    try { $b = $Body | ConvertFrom-Json; if ($b -and $b.PSObject.Properties['id']) { $id = "$($b.id)" } } catch { }
    if (-not (Test-NotebookId $id)) { return @{ status = 400; body = @{ error = 'id must be a OneNote notebook id.' } } }
    $r = Read-NotebookData $State 'record' $id
    if (-not $r.ok) { return @{ status = 409; body = @{ error = $r.message } } }
    if ((Get-NotebookRecord -AppRoot $State.AppRoot) -ne $r.record) { Set-LocalAppValue $State.AppRoot 'notebook' $r.record }
    Write-AppLog info server 'Active vault changed'
    @{ status = 200; body = @{ id = $id; name = $r.name } }
}

function Read-IntentRequest([string]$Body) {
    <# The {text, mode} of an intent or submit request; throws on anything else. #>
    $b = $null
    try { $b = $Body | ConvertFrom-Json } catch { throw 'The request is not JSON.' }
    if (-not $b -or $b -isnot [pscustomobject]) { throw 'The request is not a JSON object.' }
    $text = if ($b.PSObject.Properties['text'] -and $null -ne $b.text) { $b.text } else { '' }
    if ($text -isnot [string]) { throw 'text must be a string.' }
    $mode = if ($b.PSObject.Properties['mode'] -and $b.mode) { "$($b.mode)" } else { 'auto' }
    if ((Get-IntentModes) -notcontains $mode.ToLowerInvariant()) { throw "mode must be auto, add or ask." }
    @{ text = $text; mode = $mode }
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
        'POST /api/active-vault' { return (Set-ActiveVault $State $Body) }
        'POST /api/intent' {
            try { $r = Read-IntentRequest $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
            return @{ status = 200; body = (Get-Intent -Text $r.text -Mode $r.mode) }
        }
        'POST /api/submit' {
            # Step 1: Add and Ask are not built yet; the interface shows this message.
            try { $r = Read-IntentRequest $Body } catch { return @{ status = 400; body = @{ error = $_.Exception.Message } } }
            $i = Get-Intent -Text $r.text -Mode $r.mode
            return @{ status = 501; body = @{ intent = $i.intent; message = (Get-SubmitMessage $i.intent) } }
        }
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
    Get-CopilotTabState, New-ServerState, Invoke-ApiRoute, Invoke-ServerLoop, Start-UiServer, Stop-UiServer, Test-UiServerRunning, Test-ClientGone
