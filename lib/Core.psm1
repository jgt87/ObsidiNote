# Pure functions only. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0

function Get-Greeting {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)
    $clean = $Name.Trim()
    if (-not $clean) { throw 'Name is required' }
    # Always return an explicit object; an if without else yields AutomationNull,
    # which ConvertTo-Json writes as {}.
    return [pscustomobject]@{ Text = "Hello, $clean" }
}

Export-ModuleMember -Function Get-Greeting
