# V5 Grounding probes (FEASIBILITY.md section 7), with Microsoft 365 Copilot in ObsidiNote's Edge:
#   P3  can Copilot (Work IQ on) find a marker on a OneNote page? Marker pages live in
#       ObsidiNote-Probe, section "P3 markers" (a new one only with -WriteTest); every run asks for
#       the newest three, so running V5 again after 1 hour and 24 hours measures the indexing delay.
#   P4  the same for a marker the person put on a Loop page (optional; typed in when asked).
#   P7  the link summary prompt for a SharePoint page and a OneDrive document the person pastes.
#   P8  the same for a public web address, with Work IQ off (web) and on.
# Logged: found yes/no, JSON shape valid yes/no, reply length and timings. Never the marker, the
# address, the prompt or the reply. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProbeNotebook.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriteProbes.psm1')
Import-Module (Join-Path $PSScriptRoot 'StageOneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'StageCopilot.psm1')

$script:LinkKeys = @('title', 'where', 'kind', 'summary', 'keyFacts', 'useItFor', 'sensitivity', 'access')
$script:MarkerKeys = @('found', 'where', 'app')
$script:DefaultPublicUrl = 'https://learn.microsoft.com/en-us/powershell/scripting/overview'
$script:MarkersAsked = 3

function New-MarkerPrompt([string]$Marker) {
    'Search my Microsoft 365 content (OneNote notebooks, OneDrive files, Loop pages) for the exact text "' + $Marker + '". ' +
    'Answer only with one JSON object and no other text: {"found": true or false, "where": "the page or file name, or empty", ' +
    '"app": "OneNote, OneDrive, Loop, other or empty", "searched": ["the sources you were able to search"]}'
}

function Test-MarkerReply {
    <# @{ valid; found; cited } from a reply to New-MarkerPrompt. cited: the page it names is the
       kit's marker page (or a Loop page for P4). Pure. #>
    param([AllowEmptyString()][string]$Text, [string]$Expect = 'P3 marker')
    $j = Get-JsonFromReply $Text
    $valid = Test-JsonShape $j $script:MarkerKeys
    $found = $valid -and ("$($j.found)" -eq 'True')
    $cited = $found -and ("$($j.where) $($j.app)" -match [regex]::Escape($Expect))
    [pscustomobject]@{ valid = $valid; found = $found; cited = $cited }
}

function New-LinkPrompt([string]$Url, [string]$Kinds) {
    'Read the content at this address with my access and summarize it. Answer only with one JSON object and no other text, in this shape: ' +
    '{"title": "the page, file or site name", "where": "site, library or owner, or the domain", "kind": "' + $Kinds + '", ' +
    '"summary": "3 to 5 sentences: what it is and why it matters", "keyFacts": ["up to 8 short facts: names, dates, numbers, decisions"], ' +
    '"useItFor": "one line: when I would come back to this", "sensitivity": "its sensitivity label, or empty", ' +
    '"access": "ok, no-access or not-found"}. Address: ' + $Url
}

function Test-LinkReply {
    <# @{ valid; access; found; facts } from a reply to New-LinkPrompt. Pure. #>
    param([AllowEmptyString()][string]$Text)
    $j = Get-JsonFromReply $Text
    $valid = (Test-JsonShape $j $script:LinkKeys) -and ($j.keyFacts -is [array] -or $j.keyFacts -is [string] -or $null -eq $j.keyFacts)
    $access = if ($valid) { "$($j.access)".ToLowerInvariant() } else { '' }
    $found = $valid -and $access -eq 'ok' -and "$($j.summary)".Trim().Length -gt 0
    [pscustomobject]@{ valid = $valid; access = $access; found = $found; facts = $(if ($valid) { @($j.keyFacts | Where-Object { $_ }).Count } else { 0 }) }
}

function Get-UrlKind {
    <# 'sharepoint', 'onedrive', 'web' for an absolute https address; '' otherwise. Pure. #>
    param([string]$Url)
    $u = $null
    if (-not [Uri]::TryCreate("$Url".Trim(), [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'https') { return '' }
    if ($u.Host -match '(?i)-my\.sharepoint\.com$') { return 'onedrive' }
    if ($u.Host -match '(?i)\.sharepoint\.com$') { return 'sharepoint' }
    'web'
}

function Get-MarkerStatus($Check, [double]$AgeHours) {
    if ($Check.cited) { return 'OK' }
    if ($Check.found) { return 'WARN' }
    if ($AgeHours -lt 1) { return 'INFO' }
    'WARN'
}

function Invoke-P3 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $one = $null
    try { $one = Get-KitOneNote $Ctx } catch { }
    if ($one -and (Get-KitFlag $Ctx 'WriteTest')) {
        $m = Measure-KitStep {
            $g = if ($Ctx.Shared.ContainsKey('ProbeGuard') -and $Ctx.Shared.ProbeGuard) { $Ctx.Shared.ProbeGuard } else { Open-ProbeNotebook -One $one -Name (Get-ProbeNotebookName) -BasePath "$(Get-KitFlag $Ctx 'ProbeBasePath' '')" }
            New-ProbeMarker -Guard $g
        }
        if ($m.ok) { Add-ValidationResult $Ctx 'V5' 'OK' 'P3 marker page' "new marker page in ObsidiNote-Probe ($($m.ms) ms)" }
        else { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P3 marker page' $m.error }
    }
    $markers = @(if ($one) { Get-ProbeMarkers -One $one })
    if (-not $markers.Count) {
        Add-ValidationResult $Ctx 'V5' 'SKIP' 'P3 OneNote grounding' $(if ($one) { 'no marker page in ObsidiNote-Probe yet' } else { 'OneNote is not running' }) 'Run V5 with -WriteTest once; then run V5 again after 1 hour and after 24 hours.'
        return
    }
    foreach ($mk in @($markers | Select-Object -First $script:MarkersAsked)) {
        $r = Send-KitPrompt -Bridge $Bridge -Text (New-MarkerPrompt $mk.marker) -WorkIq 'on'
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P3 OneNote grounding' "marker age $($mk.ageHours) h: no answer ($($r.result)); $($r.ms) ms"; continue }
        $c = Test-MarkerReply $r.text
        Add-ValidationResult $Ctx 'V5' (Get-MarkerStatus $c $mk.ageHours) 'P3 OneNote grounding' "marker age $($mk.ageHours) h: found $(Format-YesNo $c.found); names the marker page $(Format-YesNo $c.cited); JSON valid $(Format-YesNo $c.valid); reply $($r.text.Length) chars; $($r.ms) ms; Work IQ $($r.workIq)"
    }
}

function Invoke-P4 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $mk = (Get-KitPrompt $Ctx 'P4 (optional): type the marker you put on a Loop page (it starts with OBSN-P4-), or press Enter to skip').ToUpperInvariant()
    if ($mk -notmatch '^OBSN-P4-[A-Z0-9]{4,12}$') { Add-ValidationResult $Ctx 'V5' 'SKIP' 'P4 Loop grounding' 'no Loop marker given' 'Optional: see runbook RB-04, step P4.'; return }
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-MarkerPrompt $mk) -WorkIq 'on'
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' 'P4 Loop grounding' "no answer ($($r.result)); $($r.ms) ms"; return }
    $c = Test-MarkerReply $r.text -Expect 'Loop'
    Add-ValidationResult $Ctx 'V5' $(if ($c.found) { 'OK' } else { 'WARN' }) 'P4 Loop grounding' "found $(Format-YesNo $c.found); names Loop $(Format-YesNo $c.cited); JSON valid $(Format-YesNo $c.valid); reply $($r.text.Length) chars; $($r.ms) ms"
}

function Invoke-LinkProbe {
    <# One P7/P8 call: adds one result line. The address is never logged. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge, [string]$Name, [string]$Url, [string]$Kinds, [string]$WorkIq = 'on')
    $r = Send-KitPrompt -Bridge $Bridge -Text (New-LinkPrompt $Url $Kinds) -WorkIq $WorkIq -TimeoutSec 240
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V5' 'FAIL' $Name "no answer ($($r.result)); $($r.ms) ms"; return }
    $c = Test-LinkReply $r.text
    $status = if ($c.found) { 'OK' } elseif ($c.valid) { 'WARN' } else { 'WARN' }
    $hint = if (-not $c.valid) { 'The reply was not in the fixed JSON shape.' } elseif (-not $c.found) { 'Copilot could not read the address (see access).' } else { '' }
    Add-ValidationResult $Ctx 'V5' $status $Name "summary made $(Format-YesNo $c.found); access $(if ($c.access) { $c.access } else { '?' }); JSON valid $(Format-YesNo $c.valid); $($c.facts) key facts; reply $($r.text.Length) chars; $($r.ms) ms; Work IQ $($r.workIq)" $hint
}

function Invoke-P7 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $asks = @(
        @{ flag = 'SharePointUrl'; kind = 'sharepoint'; name = 'P7 SharePoint page'; q = 'P7: paste the address of a SharePoint page you can open, or press Enter to skip (it is not logged)' },
        @{ flag = 'OneDriveUrl'; kind = 'onedrive'; name = 'P7 OneDrive document'; q = 'P7: paste the address of a document in your OneDrive, or press Enter to skip (it is not logged)' }
    )
    foreach ($a in $asks) {
        $url = "$(Get-KitFlag $Ctx $a.flag '')"
        if (-not $url) { $url = Get-KitPrompt $Ctx $a.q }
        if (-not $url) { Add-ValidationResult $Ctx 'V5' 'SKIP' $a.name 'no address given'; continue }
        if ((Get-UrlKind $url) -ne $a.kind) { Add-ValidationResult $Ctx 'V5' 'WARN' $a.name "not a $(if ($a.kind -eq 'onedrive') { 'OneDrive (-my.sharepoint.com)' } else { 'SharePoint (.sharepoint.com)' }) address: skipped"; continue }
        Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name $a.name -Url $url -Kinds 'site, page, document, list, file, channel, message or loop page'
    }
}

function Invoke-P8 {
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Bridge)
    $url = "$(Get-KitFlag $Ctx 'PublicUrl' '')"
    if (-not $url) { $url = $script:DefaultPublicUrl }
    if ((Get-UrlKind $url) -ne 'web') { Add-ValidationResult $Ctx 'V5' 'WARN' 'P8 web link' 'not a public https address: skipped'; return }
    Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name 'P8 web, Work IQ off' -Url $url -Kinds 'article, docs, tool, video or other' -WorkIq 'off'
    Invoke-LinkProbe -Ctx $Ctx -Bridge $Bridge -Name 'P8 web, Work IQ on' -Url $url -Kinds 'article, docs, tool, video or other' -WorkIq 'on'
}

function Invoke-StageGrounding {
    param([Parameter(Mandatory)]$Ctx)
    $b = Connect-KitCopilot -Ctx $Ctx -Stage 'V5'
    if (-not $b) { Add-ValidationResult $Ctx 'V5' 'SKIP' 'P3, P4, P7, P8' 'need Copilot (see the line above)'; return }
    Invoke-P3 $Ctx $b
    Invoke-P4 $Ctx $b
    Invoke-P7 $Ctx $b
    Invoke-P8 $Ctx $b
}

Export-ModuleMember -Function Invoke-StageGrounding, New-MarkerPrompt, Test-MarkerReply, New-LinkPrompt, Test-LinkReply, Get-UrlKind
