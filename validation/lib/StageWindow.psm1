# V4 ObsidiNote window: starts the window's local server on a TEST port (never the port of a running
# ObsidiNote), calls its pages and API, checks that a foreign Origin and a call without the app
# header are refused, and stops it. Logs status codes, counts and timings only. Opens no window.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
$script:AppLib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib'
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
foreach ($m in 'AppConfig', 'Cdp', 'Server') { Import-Module (Join-Path $script:AppLib "$m.psm1") }

$script:DefaultTestPort = 18768

function Invoke-KitHttp {
    <# One HTTP call to the local server without a proxy: @{ status; ms; body; type }. A refused call
       (4xx/5xx) is a result, not an error; a connection failure gives status 0. #>
    param([Parameter(Mandatory)][string]$Url, [string]$Method = 'GET', [string]$Body = '', [hashtable]$Headers = @{}, [int]$TimeoutMs = 20000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $req = [Net.HttpWebRequest][Net.WebRequest]::Create($Url)
    $req.Method = $Method; $req.Proxy = $null; $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = $TimeoutMs
    foreach ($k in $Headers.Keys) { if ($k -eq 'Origin') { $req.Headers.Add('Origin', $Headers[$k]) } else { $req.Headers[$k] = $Headers[$k] } }
    $res = $null
    try {
        if ($Body) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentType = 'application/json'; $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        }
        $res = $req.GetResponse()
    } catch [Net.WebException] {
        $res = $_.Exception.Response
        if (-not $res) { return [pscustomobject]@{ status = 0; ms = $sw.ElapsedMilliseconds; body = ''; type = ''; error = $_.Exception.Message } }
    }
    try {
        $reader = New-Object IO.StreamReader($res.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd(); $reader.Close()
        [pscustomobject]@{ status = [int]$res.StatusCode; ms = $sw.ElapsedMilliseconds; body = $text; type = "$($res.ContentType)"; error = '' }
    } finally { $res.Close() }
}

function Get-KitTestPort {
    <# A free test port: -TestPort, else 18768 and up. Never the window's own port (8767 by default)
       or the Edge debug port. #>
    param([Parameter(Mandatory)]$Ctx)
    $own = 8767; $cdp = 9334
    try { $own = Get-UiPort -AppRoot $Ctx.AppRoot } catch { }
    try { $cdp = (Get-CopilotSettings -AppRoot $Ctx.AppRoot).cdpPort } catch { }
    $start = [int](Get-KitFlag $Ctx 'TestPort' 0)
    if (-not $start) { $start = $script:DefaultTestPort }
    for ($p = $start; $p -lt $start + 20; $p++) {
        if ($p -eq $own -or $p -eq $cdp -or (Get-CdpPortProblem $p)) { continue }
        if (-not (Test-PortListening $p)) { return $p }
    }
    0
}

function Test-ApiCalls {
    <# The calls of stage V4 against $Base; adds one result per call. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][string]$Base)
    $app = @{ 'X-ObsidiNote' = '1' }
    $r = Invoke-KitHttp "$Base/"
    Add-ValidationResult $Ctx 'V4' $(if ($r.status -eq 200 -and $r.type -match 'html') { 'OK' } else { 'FAIL' }) 'GET /' "status $($r.status); $($r.body.Length) bytes; $($r.ms) ms"
    $r = Invoke-KitHttp "$Base/api/status" -Headers $app
    $s = if ($r.status -eq 200) { try { $r.body | ConvertFrom-Json } catch { $null } } else { $null }
    if ($s -and "$($s.app)" -eq 'ObsidiNote') {
        Add-ValidationResult $Ctx 'V4' 'OK' 'GET /api/status' "status 200; version $($s.version); OneNote $($s.oneNote.state); Copilot $($s.copilot.state); $($r.ms) ms"
    } else { Add-ValidationResult $Ctx 'V4' 'FAIL' 'GET /api/status' "status $($r.status); $($r.ms) ms" }
    $r = Invoke-KitHttp "$Base/api/notebooks" -Headers $app
    $n = if ($r.status -eq 200) { try { $r.body | ConvertFrom-Json } catch { $null } } else { $null }
    if ($n) {
        $list = @(@($n.notebooks) | Where-Object { $_ })
        Add-ValidationResult $Ctx 'V4' 'OK' 'GET /api/notebooks' "status 200; $($list.Count) notebooks, $(@($list | Where-Object { $_.vault }).Count) vault(s); $($r.ms) ms"
    } else { Add-ValidationResult $Ctx 'V4' 'FAIL' 'GET /api/notebooks' "status $($r.status); $($r.ms) ms" }
    $body = '{"text":"What did we decide about the garden budget?","mode":"auto"}'
    $r = Invoke-KitHttp "$Base/api/intent" -Method POST -Body $body -Headers $app
    $i = if ($r.status -eq 200) { try { $r.body | ConvertFrom-Json } catch { $null } } else { $null }
    $ok = $i -and "$($i.intent)" -eq 'ask'
    Add-ValidationResult $Ctx 'V4' $(if ($ok) { 'OK' } else { 'FAIL' }) 'POST /api/intent' "status $($r.status); a question is classified as $(if ($i) { $i.intent } else { '?' }); $($r.ms) ms"
    Test-RefusedCalls $Ctx $Base $body
}

function Test-RefusedCalls($Ctx, [string]$Base, [string]$Body) {
    $r = Invoke-KitHttp "$Base/api/intent" -Method POST -Body $Body -Headers @{ 'X-ObsidiNote' = '1'; 'Origin' = 'http://evil.example' }
    Add-ValidationResult $Ctx 'V4' $(if ($r.status -eq 403) { 'OK' } else { 'FAIL' }) 'Bad Origin refused' "status $($r.status) (expected 403)"
    $r = Invoke-KitHttp "$Base/api/status"
    Add-ValidationResult $Ctx 'V4' $(if ($r.status -eq 403) { 'OK' } else { 'FAIL' }) 'No header refused' "status $($r.status) (expected 403)"
    $r = Invoke-KitHttp "$Base/lib/Server.psm1"
    Add-ValidationResult $Ctx 'V4' $(if ($r.status -eq 404) { 'OK' } else { 'FAIL' }) 'Source not served' "status $($r.status) (expected 404)"
}

function Invoke-StageWindow {
    param([Parameter(Mandatory)]$Ctx)
    $port = Get-KitTestPort $Ctx
    if (-not $port) { Add-ValidationResult $Ctx 'V4' 'FAIL' 'Test port' 'no free test port found' 'Pass -TestPort with a free port.'; return }
    $cdp = 9334
    try { $cdp = [int](Get-CopilotSettings -AppRoot $Ctx.AppRoot).cdpPort } catch { }
    $state = New-ServerState -AppRoot $Ctx.AppRoot -Port $port -CdpPort $cdp -CopilotSkipped ([bool](Get-KitFlag $Ctx 'NoCopilot'))
    $start = Measure-KitStep { Start-UiServer -Port $port -UiDir (Join-Path $Ctx.AppRoot 'ui') -State $state }
    if (-not $start.ok) { Add-ValidationResult $Ctx 'V4' 'FAIL' 'Server start' "test port ${port}: $($start.error)"; return }
    Add-ValidationResult $Ctx 'V4' 'OK' 'Server start' "test port $port; $($start.ms) ms"
    try { Test-ApiCalls -Ctx $Ctx -Base "http://127.0.0.1:$port" }
    catch { Add-ValidationResult $Ctx 'V4' 'FAIL' 'Server calls' $_.Exception.Message }
    finally {
        $stop = Measure-KitStep { Stop-UiServer $start.value }
        $free = -not (Test-PortListening $port)
        Add-ValidationResult $Ctx 'V4' $(if ($free) { 'OK' } else { 'WARN' }) 'Server stop' "$($stop.ms) ms; port free again: $(Format-YesNo $free)"
    }
}

Export-ModuleMember -Function Invoke-StageWindow, Invoke-KitHttp, Get-KitTestPort
