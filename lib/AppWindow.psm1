# Opens the interface as its own window. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
#   With Copilot: in ObsidiNote's own Edge (the debug port "cdpPort", 9334 by default) as a new
#   window, through Edge's own command Target.createTarget with newWindow; an interface tab that is
#   already open there is brought to the front instead.
#   Without Copilot (-NoCopilot): ObsidiNote's Edge profile, started the normal way as an app
#   window; when Edge cannot start, the default browser.
# Modelled on the sister project's lib/AppWindow.psm1 (Start-AppWindow, Open-AppInCopilotWindow).
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Cdp.psm1')

function Test-LocalAppUrl([string]$Url, [int]$Port) {
    <# Whether a tab shows the interface: http://127.0.0.1|localhost|[::1]:$Port/... #>
    $m = [regex]::Match("$Url", '^(?i)http://(localhost|127\.0\.0\.1|\[::1\]):(\d+)(/|$)')
    $m.Success -and [int]$m.Groups[2].Value -eq $Port
}

function Open-AppInEdgeWindow {
    <# Opens $Url in ObsidiNote's Edge on $CdpPort: 'existing' (an interface tab was there and is
       now in front) or 'new-window'. Throws when that Edge does not answer. #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][int]$AppPort, [Parameter(Mandatory)][int]$CdpPort)
    $list = Invoke-RestMethod "http://127.0.0.1:$CdpPort/json/list" -TimeoutSec 3
    $pages = @(foreach ($p in @($list)) { $p }) | Where-Object { "$($_.type)" -eq 'page' }
    $existing = @($pages | Where-Object { Test-LocalAppUrl "$($_.url)" $AppPort } | Select-Object -First 1)
    if ($existing.Count) {
        $null = Invoke-RestMethod "http://127.0.0.1:$CdpPort/json/activate/$($existing[0].id)" -TimeoutSec 3
        return 'existing'
    }
    $browser = (Invoke-RestMethod "http://127.0.0.1:$CdpPort/json/version" -TimeoutSec 3).webSocketDebuggerUrl
    $s = Connect-Cdp $browser
    try { $null = Invoke-Cdp $s 'Target.createTarget' @{ url = $Url; newWindow = $true } } finally { Disconnect-Cdp $s }
    'new-window'
}

function Start-AppInEdgeProfile {
    <# Without Copilot: ObsidiNote's Edge profile as an app window ('edge-profile'), or the default
       browser when Edge cannot start ('browser'). When that Edge already runs with its debug port,
       the window opens there ('existing' or 'new-window'). The debug port is passed too, so a later
       start with Copilot can use this Edge instead of stopping on "profile in use". -Start and
       -OpenDefault replace the process starts (tests). #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][int]$AppPort, [Parameter(Mandatory)][int]$CdpPort,
        [Parameter(Mandatory)][string]$ProfileDir,
        [scriptblock]$Start = { param($exe, $argList) Start-Process -FilePath $exe -ArgumentList $argList },
        [scriptblock]$OpenDefault = { param($u) Start-Process $u })
    if (Test-CdpEndpoint $CdpPort) {
        try { return (Open-AppInEdgeWindow -Url $Url -AppPort $AppPort -CdpPort $CdpPort) } catch { }
    }
    try {
        $exe = Get-EdgePath
        $null = New-Item -ItemType Directory -Force -Path $ProfileDir
        & $Start $exe @("--user-data-dir=`"$ProfileDir`"", "--remote-debugging-port=$CdpPort", '--no-first-run', '--no-default-browser-check', "--app=$Url")
        return 'edge-profile'
    } catch {
        & $OpenDefault $Url
        return 'browser'
    }
}

function Get-AppWindowDetail([string]$How) {
    <# The status line's words for where the interface opened. #>
    switch ($How) {
        'new-window' { "in a new window of ObsidiNote's Edge" }
        'existing' { "in ObsidiNote's Edge (the window that was already open)" }
        'edge-profile' { "in ObsidiNote's Edge profile (without Copilot)" }
        'browser' { 'in your default browser (Edge could not start)' }
        'none' { 'no window opened (-NoWindow)' }
        default { '' }
    }
}

Export-ModuleMember -Function Test-LocalAppUrl, Open-AppInEdgeWindow, Start-AppInEdgeProfile, Get-AppWindowDetail
