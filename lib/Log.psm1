# Diagnostic log for the Copilot bridge. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
# Same approach as the updater's log (tools/update.ps1): one line per event in
# <data dir>\logs\obsidinote.log, restarted when it passes 256 KB, never throws. The data dir is
# %LOCALAPPDATA%\ObsidiNote, or OBSIDINOTE_DATA_DIR when set (the tests point it at %TEMP%).
# OneNote is the only store: a log line holds ids, counts, timings and states only, never prompt or
# reply text, page titles or URLs with query strings. As a second line of defence every line is
# masked (GUIDs, email addresses, query strings, the user profile path).
# Levels: off < info (default) < verbose; OBSIDINOTE_LOG chooses one. There is no level that
# records text.
Set-StrictMode -Version 2.0

$script:Levels = @{ off = 0; info = 1; verbose = 2 }

function Get-AppLogLevel {
    $l = if ($env:OBSIDINOTE_LOG) { "$env:OBSIDINOTE_LOG".ToLowerInvariant() } else { 'info' }
    if (-not $script:Levels.ContainsKey($l)) { $l = 'info' }
    $script:Levels[$l]
}

function Test-AppLog([string]$Level) {
    <# True when a line at $Level would be written. #>
    $want = if ($script:Levels.ContainsKey("$Level")) { $script:Levels["$Level"] } else { 99 }
    $cur = Get-AppLogLevel
    $cur -gt 0 -and $cur -ge $want
}

function Get-AppLogFile {
    $dataDir = if ($env:OBSIDINOTE_DATA_DIR) { $env:OBSIDINOTE_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'ObsidiNote' }
    Join-Path (Join-Path $dataDir 'logs') 'obsidinote.log'
}

function Protect-AppLogText([string]$Text) {
    <# Masks what could identify a person or a conversation. #>
    if (-not $Text) { return $Text }
    foreach ($p in @($env:USERPROFILE, $env:USERNAME, $env:COMPUTERNAME)) {
        if ($p -and $p.Length -ge 3) { $Text = [regex]::Replace($Text, [regex]::Escape($p), '<user>', 'IgnoreCase') }
    }
    $Text = [regex]::Replace($Text, '[\w.+-]+@[\w-]+(\.[\w-]+)+', '<email>')
    $Text = [regex]::Replace($Text, '(https?://[^\s"?]+)\?[^\s"]*', '$1?<query>')
    [regex]::Replace($Text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '<id>')
}

function Write-AppLog {
    <# Write-AppLog verbose bridge 'Sent prompt' @{ chars = 123 } #>
    param(
        [Parameter(Mandatory)][ValidateSet('info', 'verbose')][string]$Level,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Message,
        $Data
    )
    if (-not (Test-AppLog $Level)) { return }
    try {
        $line = '{0} [{1,5}] {2,-7} {3,-8} {4}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $PID, $Level.ToUpperInvariant(), $Component, $Message
        if ($null -ne $Data) { $line += ' ' + (ConvertTo-Json -InputObject $Data -Depth 6 -Compress) }
        $line = Protect-AppLogText $line
        $file = Get-AppLogFile
        $dir = Split-Path -Parent $file
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 256KB) { [IO.File]::Delete($file) }
        [IO.File]::AppendAllText($file, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
    } catch { }   # logging must never break ObsidiNote
}

Export-ModuleMember -Function Write-AppLog, Test-AppLog, Protect-AppLogText, Get-AppLogFile
