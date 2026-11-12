# Settings for the Copilot bridge: the data folder, config\<name>.json merged with
# config\<name>.local.json, and ObsidiNote's own Edge session (debug port and profile).
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0

# The "bad port" list of the Fetch standard (https://fetch.spec.whatwg.org/#port-blocking, read
# 2026-11-12): browsers refuse these, so ObsidiNote never uses one. 9334 is not on it.
$script:FetchBadPorts = @(0, 1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95,
    101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465,
    512, 513, 514, 515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995,
    1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080)

# Ports other programs on this machine own: 9333 is the other Copilot helper's Edge, 3000 and 3100
# are reserved local servers. Sharing 9333 would make both programs drive the same Edge window.
$script:ReservedPorts = @(9333, 3000, 3100)

$script:DefaultCdpPort = 9334

function Get-AppRoot { Split-Path -Parent $PSScriptRoot }

function Get-AppDataDir {
    <# %LOCALAPPDATA%\ObsidiNote, or OBSIDINOTE_DATA_DIR when set (tests use %TEMP%). #>
    if ($env:OBSIDINOTE_DATA_DIR) { return $env:OBSIDINOTE_DATA_DIR }
    Join-Path $env:LOCALAPPDATA 'ObsidiNote'
}

function Read-AppJsonFile([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    $text = [IO.File]::ReadAllText($File)
    if (-not $text.Trim()) { return $null }
    $text | ConvertFrom-Json
}

function Get-AppConfig {
    <# config\<Name>.json with the top-level keys of config\<Name>.local.json laid over it (the local
       file wins key by key; a nested object is replaced whole). An empty object when neither exists. #>
    param([Parameter(Mandatory)][string]$Name, [string]$AppRoot)
    if (-not $AppRoot) { $AppRoot = Get-AppRoot }
    $dir = Join-Path $AppRoot 'config'
    $cfg = Read-AppJsonFile (Join-Path $dir "$Name.json")
    if (-not $cfg) { $cfg = [pscustomobject]@{} }
    $local = Read-AppJsonFile (Join-Path $dir "$Name.local.json")
    if ($local) {
        foreach ($p in $local.PSObject.Properties) { $cfg | Add-Member -Force -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    $cfg
}

function Test-FetchBadPort([int]$Port) { $script:FetchBadPorts -contains $Port }

function Get-CdpPortProblem([int]$Port) {
    <# Why a debug port cannot be used ('' when it can). #>
    if ($Port -lt 1 -or $Port -gt 65535) { return "port $Port is not a valid port (1-65535)" }
    if ($script:ReservedPorts -contains $Port) { return "port $Port is reserved for another program on this computer" }
    if (Test-FetchBadPort $Port) { return "port $Port is one that browsers block" }
    ''
}

function Get-CopilotSettings {
    <# ObsidiNote's own Edge session: @{ cdpPort; profileDir }. "cdpPort" comes from
       config\obsidinote.json (overridable in config\obsidinote.local.json), 9334 by default; the
       profile is <data dir>\edge-profile. Throws on a port that cannot be used. #>
    param([string]$AppRoot)
    $cfg = Get-AppConfig -Name 'obsidinote' -AppRoot $AppRoot
    $port = $script:DefaultCdpPort
    if ($cfg.PSObject.Properties['cdpPort'] -and $null -ne $cfg.cdpPort) {
        $raw = "$($cfg.cdpPort)"
        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n)) { throw "Setting cdpPort ('$raw') in config\obsidinote.json or config\obsidinote.local.json is not a number." }
        $port = $n
    }
    $problem = Get-CdpPortProblem $port
    if ($problem) { throw "Setting cdpPort: $problem. Choose another port in config\obsidinote.local.json (default $($script:DefaultCdpPort))." }
    @{ cdpPort = $port; profileDir = (Join-Path (Get-AppDataDir) 'edge-profile') }
}

function Get-AppSetting {
    <# One top-level setting from config\obsidinote.json (+ .local.json); $Default when missing or empty. #>
    param([Parameter(Mandatory)][string]$Key, $Default = $null, [string]$AppRoot)
    $cfg = Get-AppConfig -Name 'obsidinote' -AppRoot $AppRoot
    if ($cfg.PSObject.Properties[$Key] -and $null -ne $cfg.$Key -and "$($cfg.$Key)" -ne '') { return $cfg.$Key }
    $Default
}

function Get-CopilotSignInMode {
    <# "signIn": 'single-sign-on' (default: ObsidiNote's own Edge profile, which signs in with the
       Windows work account when single sign-on is on) or 'private' (a private session: you sign in
       yourself, once per Edge start). Anything else counts as the default. #>
    param([string]$AppRoot)
    if ("$(Get-AppSetting -Key 'signIn' -Default '' -AppRoot $AppRoot)" -eq 'private') { 'private' } else { 'single-sign-on' }
}

function Get-NotebookRecord {
    <# "notebook": where ObsidiNote's notebook is, so a start can open it (a local .onetoc2/.one
       path, or onenote:https://... for a notebook in OneDrive or SharePoint). '' when not recorded yet. #>
    param([string]$AppRoot)
    "$(Get-AppSetting -Key 'notebook' -Default '' -AppRoot $AppRoot)"
}

Export-ModuleMember -Function Get-AppRoot, Get-AppDataDir, Get-AppConfig, Test-FetchBadPort, Get-CdpPortProblem, Get-CopilotSettings, Get-AppSetting, Get-CopilotSignInMode, Get-NotebookRecord
