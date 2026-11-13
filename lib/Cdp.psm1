# Minimal Chrome DevTools Protocol client for Windows PowerShell 5.1.
# Launches Edge with a debug port and talks to a page target over a WebSocket.
#
# Provenance: copied from the CCBridge repo (github.com/jgt87/CCBridge), lib/Cdp.psm1 at commit
# b972eab. Changed: logs through ObsidiNote's lib/Log.psm1 (Write-AppLog) instead of CCBridge's
# Log.psm1; Start-CdpEdge defaults to ObsidiNote's own session (debug port 9334 and the profile
# <data dir>\edge-profile, from lib/AppConfig.psm1) and no longer clears Edge's cache from a flag
# file; comments name ObsidiNote. The protocol code itself is unchanged.
# Added in ObsidiNote: Start-CdpEdge never starts a second Edge for its profile (it waits for one
# that is starting, and stops with a clear message when Edge holds the profile without the debug
# port or policy blocks the port), waits up to 45 s instead of 15 s, and the Edge policy check
# (Get-EdgePolicyValue, ported from CCBridge's lib/Prereq.psm1).
# Strict mode stays off here: CDP messages are JSON whose optional fields (id, error, method,
# exceptionDetails) are read directly, which Set-StrictMode -Version 2.0 turns into errors.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Log.psm1')
Import-Module (Join-Path $PSScriptRoot 'AppConfig.psm1')

function Get-EdgePath {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    )
    $edge = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $edge) { throw 'msedge.exe not found' }
    $edge
}

function Test-CdpEndpoint([int]$Port) {
    try { $null = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 2; $true } catch { $false }
}

function Test-PortListening([int]$Port) {
    <# True when something accepts connections on 127.0.0.1:$Port (also a program that is not Edge). #>
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync('127.0.0.1', $Port).Wait(500) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}

function New-NoRetryError([string]$Message) {
    <# An error that Connect-Copilot must not retry: retrying would only open more Edge windows. #>
    $ex = New-Object System.InvalidOperationException $Message
    $ex.Data['obsnNoRetry'] = $true
    $ex
}

function Test-NoRetryError($ErrorRecord) {
    $ex = if ($ErrorRecord -is [Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } else { $ErrorRecord }
    [bool]($ex -and $ex.Data -and $ex.Data.Contains('obsnNoRetry'))
}

function Get-EdgePolicyValue([string]$Name) {
    <# An Edge policy value (machine first, then user); $null when not set. Read only. #>
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge') {
        try {
            $v = (Get-ItemProperty -LiteralPath $k -Name $Name -ErrorAction Stop).$Name
            if ($null -ne $v) { return $v }
        } catch { }
    }
    $null
}

function Get-EdgeDebugBlock {
    <# Why Edge policy blocks the debug port ObsidiNote drives Copilot through ('' when it does not). #>
    if ("$(Get-EdgePolicyValue 'RemoteDebuggingAllowed')" -eq '0') { return 'Edge policy RemoteDebuggingAllowed = 0 blocks the debug port' }
    if ("$(Get-EdgePolicyValue 'DeveloperToolsAvailability')" -eq '2') { return 'Edge policy DeveloperToolsAvailability = 2 blocks the debug port' }
    ''
}

function Test-EdgeForcedSignIn {
    <# Edge policy BrowserSignin = 2: Edge makes every profile sign in to the browser itself before
       it can be used. A new, not signed-in profile (ObsidiNote's, on its first start) then gets its
       window closed while Edge shows its own sign-in. Read only. #>
    "$(Get-EdgePolicyValue 'BrowserSignin')" -eq '2'
}

function Get-EdgeProfileAccount {
    <# Which account an Edge profile is signed in with: 'work' (work or school account), 'personal'
       (Microsoft account), 'none' or 'unknown' (also: no profile yet). Only the account type is read
       from 'Local State', never names, ids or tokens. #>
    param([Parameter(Mandatory)][string]$ProfileDir)
    $msaTenant = '9188040d-6c67-4c5b-b112-36a304b66dad'   # the tenant of personal Microsoft accounts
    try { $j = [IO.File]::ReadAllText((Join-Path $ProfileDir 'Local State')) | ConvertFrom-Json } catch { return 'unknown' }
    $d = $j.profile.info_cache.Default
    if (-not $d) { return 'unknown' }
    $type = "$($d.edge_account_type)"
    $tenant = "$($d.edge_account_tenant_id)"
    if ($type -eq '2' -or ($tenant -and $tenant -ne $msaTenant -and $type -ne '1' -and $type -ne '0')) { return 'work' }
    if ($type -eq '1') { return 'personal' }
    if ($type -in '', '0') { return 'none' }
    'unknown'
}

function Get-ForcedSignInMessage {
    "Edge on this PC must be signed in to before it can be used (Edge policy BrowserSignin = 2), and ObsidiNote's Edge profile is not signed in yet, so Edge closed the Copilot window to ask for that first. In the Edge window ObsidiNote opened, sign in to Edge itself with your work account (Edge's own sign-in prompt, or the profile picture at the top left), then start ObsidiNote again. Copilot then signs in with that account by itself."
}

function Get-EdgeBrowserProcesses {
    <# msedge.exe processes with their command lines (ProcessId, CommandLine). Mocked in tests. #>
    @(Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; CommandLine = "$($_.CommandLine)" } })
}

function Get-EdgeProfileUse {
    <# Is an Edge browser process running with this profile (--user-data-dir), and with the debug
       port? state: 'none' (no Edge with this profile), 'debug' (with --remote-debugging-port=$Port)
       or 'no-debug' (without it, or with another port: a new Start-Process would only hand its
       window to that Edge, and no debug port would appear). Helper processes (--type=renderer,
       gpu-process...) are left out: only the browser process carries the port. -Processes for tests. #>
    param([Parameter(Mandatory)][string]$ProfileDir, [Parameter(Mandatory)][int]$Port, $Processes)
    if (-not $PSBoundParameters.ContainsKey('Processes')) { $Processes = Get-EdgeBrowserProcesses }
    $dir = [regex]::Escape($ProfileDir.TrimEnd('\'))
    $mine = @(@($Processes) | Where-Object {
        $_ -and "$($_.CommandLine)" -notmatch '\s--type=' -and "$($_.CommandLine)" -match ('(?i)--user-data-dir=("?)' + $dir + '\\?\1(\s|$)')
    })
    $withPort = @($mine | Where-Object { "$($_.CommandLine)" -match ('--remote-debugging-port=' + $Port + '(\s|$)') })
    $state = if (-not $mine.Count) { 'none' } elseif ($withPort.Count) { 'debug' } else { 'no-debug' }
    [pscustomobject]@{ state = $state; pids = @($mine | ForEach-Object { $_.ProcessId }) }
}

function Get-ProfileInUseMessage([int]$Port) {
    "ObsidiNote's Edge profile is already open in an Edge window that was started without its debug port (port $Port), so ObsidiNote cannot reach Copilot in it and starting Edge again would only open another window. Close every window of that Edge (the one that shows Copilot for ObsidiNote; also check the taskbar), then start ObsidiNote again."
}

function Invoke-EdgeProfileSignIn {
    <# One-time Edge sign-in for ObsidiNote's own profile when Edge policy requires signing in to the
       browser (BrowserSignin = 2). Started with --no-first-run and a debug port, Edge closes the window
       of a profile that is not signed in, and nobody gets a chance to sign in. So: start Edge for the
       profile the plain way (only --user-data-dir: Edge runs its own sign-in), wait until the profile
       reports a work account (account type from 'Local State', nothing else), then close that Edge, so
       Connect-Copilot can start it with the debug port. Returns @{ ok; started; detail }.
       -GetAccount, -GetUse, -StartEdge, -StopEdge and -OnWait replace the real calls in tests. #>
    param(
        [Parameter(Mandatory)][string]$ProfileDir,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSec = 600,
        [int]$PollMs = 2000,
        [scriptblock]$GetAccount = { param($d) Get-EdgeProfileAccount -ProfileDir $d },
        [scriptblock]$GetUse = { param($d, $p) Get-EdgeProfileUse -ProfileDir $d -Port $p },
        [scriptblock]$StartEdge = { param($d) Start-Process -FilePath (Get-EdgePath) -ArgumentList @("--user-data-dir=`"$d`"") },
        [scriptblock]$StopEdge = {
            param($ids)
            foreach ($i in @($ids)) { try { [void](Get-Process -Id $i -ErrorAction Stop).CloseMainWindow() } catch { } }
            Start-Sleep -Seconds 3
            foreach ($i in @($ids)) { try { Stop-Process -Id $i -Force -ErrorAction Stop } catch { } }
        },
        [scriptblock]$OnWait = $null
    )
    $result = [pscustomobject]@{ ok = $false; started = $false; detail = '' }
    if ((& $GetAccount $ProfileDir) -eq 'work') { $result.ok = $true; $result.detail = 'Edge profile already signed in with a work account'; return $result }
    # An Edge that already holds this profile (ObsidiNote's own, from an earlier start) would take
    # the new window and skip Edge's sign-in: close it first.
    $use = & $GetUse $ProfileDir $Port
    if ($use -and $use.state -ne 'none') { & $StopEdge $use.pids }
    $null = New-Item -ItemType Directory -Force -Path $ProfileDir
    $null = & $StartEdge $ProfileDir
    $result.started = $true
    Write-AppLog info cdp 'Started Edge without the debug port for its own browser sign-in (BrowserSignin = 2)'
    if ($OnWait) { & $OnWait }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if ((& $GetAccount $ProfileDir) -eq 'work') {
            $use = & $GetUse $ProfileDir $Port
            if ($use -and $use.state -ne 'none') { & $StopEdge $use.pids }
            Write-AppLog info cdp "Edge profile signed in with a work account after $([int]$sw.Elapsed.TotalSeconds) s"
            $result.ok = $true
            $result.detail = 'Edge profile signed in with your work account'
            return $result
        }
        Start-Sleep -Milliseconds $PollMs
    }
    $result.detail = "Edge was not signed in within $TimeoutSec s. In the Edge window ObsidiNote opened, sign in with your work account (Edge's own sign-in, or the profile picture at the top left), then start ObsidiNote again."
    $result
}

function Start-CdpEdge {
    <# Starts Edge with a debug port, or reuses one already listening on that port. Port and
       profile default to ObsidiNote's own session (Get-CopilotSettings).
       Never starts a second Edge for the same profile: when Edge with this profile is already
       starting (debug port on its command line) it waits for it; when Edge holds the profile
       without the debug port, or policy blocks the port, it stops with an error that
       Connect-Copilot does not retry (New-NoRetryError). -NoLaunch: only wait, never start Edge. #>
    param(
        [int]$Port = 0,
        [string]$ProfileDir = '',
        [string]$Url = 'about:blank',
        [switch]$Headless,
        [int]$StartTimeoutSec = 45,
        [switch]$NoLaunch
    )
    if (-not $Port -or -not $ProfileDir) {
        $own = Get-CopilotSettings
        if (-not $Port) { $Port = $own.cdpPort }
        if (-not $ProfileDir) { $ProfileDir = $own.profileDir }
    }
    if (Test-CdpEndpoint $Port) { Write-AppLog verbose cdp "Reusing Edge on debug port $Port"; return $null }
    $block = Get-EdgeDebugBlock
    if ($block) { Write-AppLog info cdp 'Edge policy blocks the debug port'; throw (New-NoRetryError "$block; ObsidiNote needs it to drive Copilot. Ask IT to allow it.") }
    $use = Get-EdgeProfileUse -ProfileDir $ProfileDir -Port $Port
    $proc = $null
    if ($use.state -eq 'no-debug') {
        Write-AppLog info cdp 'Edge profile is in use without the debug port' @{ port = $Port; processes = @($use.pids).Count }
        throw (New-NoRetryError (Get-ProfileInUseMessage $Port))
    } elseif ($use.state -eq 'debug') {
        Write-AppLog info cdp "Edge with ObsidiNote's profile is still starting; waiting for port $Port (no new window)"
    } elseif ($NoLaunch) {
        throw (New-NoRetryError "ObsidiNote's Edge window was closed (twice) before Copilot was ready. Start ObsidiNote again and leave its Edge window open.")
    } else {
        $null = New-Item -ItemType Directory -Force -Path $ProfileDir
        $edgeArgs = @("--remote-debugging-port=$Port", "--user-data-dir=`"$ProfileDir`"",
                      '--no-first-run', '--no-default-browser-check',
                      # Copilot's tab usually sits in the background; throttling it stalls reply streams.
                      '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding')
        if ($Headless) { $edgeArgs += '--headless=new' }
        $edgeArgs += $Url
        $proc = Start-Process -FilePath (Get-EdgePath) -ArgumentList $edgeArgs -PassThru
        Write-AppLog info cdp "Started Edge (pid $($proc.Id)) with debug port $Port" @{ headless = [bool]$Headless }
    }
    # A new profile on a managed PC can take long to start (first run, policies, virus scan).
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $nextLook = 3
    while ($sw.Elapsed.TotalSeconds -lt $StartTimeoutSec) {
        if (Test-CdpEndpoint $Port) { return $(if ($proc) { $proc } else { $null }) }
        Start-Sleep -Milliseconds 250
        if ($sw.Elapsed.TotalSeconds -ge $nextLook) {
            $nextLook += 3
            $now = Get-EdgeProfileUse -ProfileDir $ProfileDir -Port $Port
            if ($now.state -eq 'no-debug') { throw (New-NoRetryError (Get-ProfileInUseMessage $Port)) }
            if ($now.state -eq 'none') { throw (New-NoRetryError "Edge closed right after it started with ObsidiNote's profile (port $Port). Start ObsidiNote again; if this repeats, send the last lines of %LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log.") }
        }
    }
    Write-AppLog info cdp "Edge did not open its debug port within $StartTimeoutSec s"
    # Not a no-retry error: the next attempt finds this Edge still starting and waits again (no new window).
    throw "Edge runs with ObsidiNote's profile, but its debug port $Port did not answer within $StartTimeoutSec s. If this repeats, close ObsidiNote's Edge window and start ObsidiNote again."
}

function Get-CdpPageTarget {
    <# Returns the first page target, preferring one whose URL matches $UrlLike. #>
    param([int]$Port = 9334, [string]$UrlLike = '*')
    # Parentheses matter: PS 5.1 emits a JSON array from Invoke-RestMethod as a single object.
    $pages = @((Invoke-RestMethod "http://127.0.0.1:$Port/json/list") | Where-Object { $_.type -eq 'page' })
    if (-not $pages) { throw "no page targets on port $Port" }
    $match = $pages | Where-Object { $_.url -like $UrlLike } | Select-Object -First 1
    if ($match) { return $match }
    # Never a local page (ObsidiNote's own web app can be a tab in this window).
    $other = @($pages | Where-Object { "$($_.url)" -notmatch '^(?i)https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(/|$)' })
    if ($other.Count) { $other[0] } else { $pages[0] }
}

function Connect-Cdp {
    param([Parameter(Mandatory)][string]$WebSocketUrl)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    try {
        if (-not $ws.ConnectAsync([uri]$WebSocketUrl, [Threading.CancellationToken]::None).Wait(10000)) {
            throw "could not connect to $WebSocketUrl"
        }
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        throw "Could not connect to the Copilot tab in Edge ($($inner.Message))"
    }
    $buffer = New-Object byte[] 65536
    [pscustomobject]@{
        Ws      = $ws
        NextId  = 0
        Buffer  = $buffer
        Segment = New-Object ArraySegment[byte] -ArgumentList @(, $buffer)
        Stream  = New-Object System.IO.MemoryStream
        Pending = $null
        Lost    = $false
        Events  = New-Object System.Collections.Generic.Queue[object]
    }
}

function Receive-CdpMessage {
    <# Returns the next parsed message, or $null on timeout. A receive that times
       out stays pending on the session and is resumed by the next call. #>
    param([Parameter(Mandatory)]$Session, [int]$TimeoutMs = 1000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ($true) {
        if (-not $Session.Pending) {
            $Session.Pending = $Session.Ws.ReceiveAsync($Session.Segment, [Threading.CancellationToken]::None)
        }
        $remaining = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        try {
            if (-not $Session.Pending.Wait($remaining)) { return $null }
            $r = $Session.Pending.Result
        } catch {
            # The tab went away (closed, replaced during sign-in, Edge closed): report the real reason.
            $Session.Pending = $null
            $Session.Lost = $true
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            throw "Lost the connection to the Copilot tab in Edge ($($inner.Message))"
        }
        $Session.Pending = $null
        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { $Session.Lost = $true; throw 'Lost the connection to the Copilot tab in Edge (the tab closed the connection)' }
        $Session.Stream.Write($Session.Buffer, 0, $r.Count)
        if ($r.EndOfMessage) {
            $text = [Text.Encoding]::UTF8.GetString($Session.Stream.ToArray())
            $Session.Stream.SetLength(0)
            return ($text | ConvertFrom-Json)
        }
    }
}

function Receive-CdpEvent {
    <# Next event: queued ones first (set aside by Invoke-Cdp), then the socket. #>
    param([Parameter(Mandatory)]$Session, [int]$TimeoutMs = 1000)
    if ($Session.Events.Count) { return $Session.Events.Dequeue() }
    Receive-CdpMessage -Session $Session -TimeoutMs $TimeoutMs
}

function Invoke-Cdp {
    <# Sends a command and waits for its result. Events received meanwhile are queued. #>
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{},
        [int]$TimeoutMs = 30000
    )
    $Session.NextId++
    $id = $Session.NextId
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $json = @{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object ArraySegment[byte] -ArgumentList @(, $bytes)
    if ($Session.Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        $Session.Lost = $true
        throw "Lost the connection to the Copilot tab in Edge (connection $($Session.Ws.State))"
    }
    try {
        if (-not $Session.Ws.SendAsync($seg, 'Text', $true, [Threading.CancellationToken]::None).Wait(10000)) {
            throw "timed out sending $Method"
        }
    } catch {
        if ("$($_.Exception.Message)" -like 'timed out sending*') { throw }
        # The tab went away (closed, crashed, replaced during sign-in, Edge closed).
        $Session.Lost = $true
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        throw "Lost the connection to the Copilot tab in Edge ($($inner.Message))"
    }
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $msg = Receive-CdpMessage -Session $Session -TimeoutMs $remaining
        if ($null -eq $msg) { break }
        if ($msg.id -eq $id) {
            if ($msg.error) { Write-AppLog info cdp "$Method failed: $($msg.error.message)"; throw "$Method failed: $($msg.error.message)" }
            if ($sw.ElapsedMilliseconds -gt 5000) { Write-AppLog verbose cdp "$Method was slow ($($sw.ElapsedMilliseconds) ms)" }
            return $msg.result
        }
        if ($msg.method) { $Session.Events.Enqueue($msg) }
    }
    Write-AppLog info cdp "Timed out waiting for $Method after $TimeoutMs ms"
    throw "timed out waiting for $Method"
}

function Invoke-CdpEval {
    <# Evaluates a JS expression in the page and returns its value (awaits promises). #>
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Expression, [int]$TimeoutMs = 30000)
    $r = Invoke-Cdp -Session $Session -Method 'Runtime.evaluate' -TimeoutMs $TimeoutMs -Params @{
        expression = $Expression; returnByValue = $true; awaitPromise = $true
    }
    if ($r.exceptionDetails) {
        $desc = if ($r.exceptionDetails.exception) { $r.exceptionDetails.exception.description } else { $r.exceptionDetails.text }
        throw "JS error: $desc"
    }
    $r.result.value
}

function Disconnect-Cdp {
    param([Parameter(Mandatory)]$Session)
    try {
        $Session.Ws.CloseAsync('NormalClosure', 'bye', [Threading.CancellationToken]::None).Wait(2000) | Out-Null
    } catch { }
    $Session.Ws.Dispose()
}

Export-ModuleMember -Function Get-EdgePath, Test-CdpEndpoint, Start-CdpEdge, Get-CdpPageTarget,
    Test-PortListening, New-NoRetryError, Test-NoRetryError, Get-EdgePolicyValue, Get-EdgeDebugBlock,
    Get-EdgeBrowserProcesses, Get-EdgeProfileUse, Test-EdgeForcedSignIn, Get-EdgeProfileAccount, Get-ForcedSignInMessage, Invoke-EdgeProfileSignIn,
    Connect-Cdp, Receive-CdpMessage, Receive-CdpEvent, Invoke-Cdp, Invoke-CdpEval, Disconnect-Cdp
