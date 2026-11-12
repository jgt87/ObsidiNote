# Status lines "  [OK]   Name                  detail", the same for the installer (tools/install-main.ps1,
# its "This computer" block) and the start (obsidinote.ps1). Keep this file ASCII: PS 5.1 reads
# BOM-less files as ANSI.
Set-StrictMode -Version 2.0

function Format-StatusLine {
    <# The plain text of one status line (without colours), for tests and for logs. #>
    param([Parameter(Mandatory)][string]$Status, [Parameter(Mandatory)][string]$Name, [string]$Detail = '')
    '  [' + $Status + ']' + (' ' * [Math]::Max(0, 5 - $Status.Length)) + $Name.PadRight(22) + $Detail
}

function Get-StatusColor([string]$Status) {
    switch ($Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'INFO' { 'Cyan' } default { 'Red' } }
}

function Write-Status {
    <# Writes one status line with the status word in colour and an optional hint below it.
       -ToError writes to stderr (obsidinote.ps1 keeps stdout for its own output); otherwise to the
       host (the installer). #>
    param(
        [Parameter(Mandatory)][ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$Status,
        [Parameter(Mandatory)][string]$Name,
        [string]$Detail = '',
        [string]$Hint = '',
        [switch]$ToError
    )
    $color = Get-StatusColor $Status
    $pad = (' ' * [Math]::Max(0, 5 - $Status.Length)) + $Name.PadRight(22)
    if ($ToError) {
        $err = [Console]::Error
        $old = $null
        try { $old = [Console]::ForegroundColor } catch { }
        $err.Write('  [')
        try { [Console]::ForegroundColor = $color } catch { }
        $err.Write($Status)
        if ($null -ne $old) { try { [Console]::ForegroundColor = $old } catch { } }
        $err.Write(']' + $pad)
        try { [Console]::ForegroundColor = 'DarkGray' } catch { }
        $err.WriteLine($Detail)
        if ($null -ne $old) { try { [Console]::ForegroundColor = $old } catch { } }
        if ($Hint) {
            try { [Console]::ForegroundColor = $color } catch { }
            $err.WriteLine((' ' * 29) + $Hint)
            if ($null -ne $old) { try { [Console]::ForegroundColor = $old } catch { } }
        }
        return
    }
    Write-Host '  [' -NoNewline
    Write-Host $Status -ForegroundColor $color -NoNewline
    Write-Host ']' -NoNewline
    Write-Host $pad -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
    if ($Hint) { Write-Host ((' ' * 29) + $Hint) -ForegroundColor $color }
}

Export-ModuleMember -Function Format-StatusLine, Write-Status
