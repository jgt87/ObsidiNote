# The validation kit's core: which stages run, the results, the masking and the log file.
# The log is meant to be sent back, so every line is masked before it is written or shown: no page
# titles or text, no prompts or replies, no URLs with paths or queries, no notebook names other than
# the kit's own (ObsidiNote-Probe, ObsidiNote-Validation), no user, machine or domain names, e-mail
# addresses, tenant ids, GUIDs or user paths. Pure except Write-ValidationLine (one file, the log).
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib\Log.psm1')
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib\Status.psm1')

$script:KitVersion = '1.0.0'
$script:StageOrder = @('V1', 'V2', 'V3', 'V4', 'V5', 'V6')
$script:StageTitles = @{
    V1 = 'This computer'; V2 = 'OneNote'; V3 = 'Copilot'; V4 = 'ObsidiNote window'
    V5 = 'Grounding probes (P3, P4, P7, P8)'; V6 = 'Vaults, index, Add, Ask, knowledge graph'
}
# The only notebook names that may appear in the log. The kit writes only into the first two.
$script:ProbeNotebook = 'ObsidiNote-Probe'
$script:DevNotebook = 'ObsidiNote-Validation'
$script:FixedNames = @('ObsidiNote', 'ObsidiNote-Probe', 'ObsidiNote-Validation', 'ObsidiNote-Dev',
    # ObsidiNote's fixed sections and the kit's own probe sections: product wording, not private names.
    '00 Index', '01 Inbox', 'Notes', 'Internal links', 'Web links', 'Sources', 'People', 'Projects', 'Meetings', 'Decisions',
    'Journal', 'Files', 'Archive', 'Index', 'Inbox', 'Unfiled', 'Links', 'P3 markers', 'P1b size', 'P1c home', 'P1c moved')
$script:Statuses = @('OK', 'WARN', 'FAIL', 'SKIP', 'INFO')

function Get-KitVersion { $script:KitVersion }
function Get-ProbeNotebookName { $script:ProbeNotebook }
function Get-DevNotebookName { $script:DevNotebook }

function Get-ValidationStages {
    <# The stages to run, in the fixed order V1..V6. -Requested: names like 'V1', 'v3' or one string
       'V1,V3'; empty or 'all' = every stage. Throws on an unknown name. #>
    param([string[]]$Requested = @())
    $want = @(foreach ($r in @($Requested)) { foreach ($p in "$r".Split(',; '.ToCharArray())) { if ($p.Trim()) { $p.Trim().ToUpperInvariant() } } })
    if (-not $want.Count -or $want -contains 'ALL') { return $script:StageOrder }
    foreach ($w in $want) { if ($script:StageOrder -notcontains $w) { throw "Unknown stage '$w'. Stages: $($script:StageOrder -join ', ')." } }
    @($script:StageOrder | Where-Object { $want -contains $_ })
}

function Get-StageTitle([string]$Stage) { $script:StageTitles[$Stage] }

function Test-KitNameAllowed {
    <# True for the notebook names the kit may write into: ObsidiNote-Probe and ObsidiNote-Validation. #>
    param([string]$Name)
    $Name -ceq $script:ProbeNotebook -or $Name -ceq $script:DevNotebook
}

function New-ValidationContext {
    <# The state of one run. -LogPath '' keeps the log in memory only (tests). -Prompt asks the person
       a question (Read-Host by default); -NoPrompt makes every question answer ''. #>
    param(
        [Parameter(Mandatory)][string]$AppRoot,
        [string]$LogPath = '',
        [string[]]$Stages = @(),
        [hashtable]$Flags = @{},
        [scriptblock]$Prompt = { param($q) Read-Host $q },
        [switch]$Quiet
    )
    @{
        AppRoot = $AppRoot; LogPath = $LogPath; Stages = @($Stages); Flags = $Flags; Prompt = $Prompt
        Quiet = [bool]$Quiet; Started = (Get-Date); Watch = [Diagnostics.Stopwatch]::StartNew()
        Results = (New-Object System.Collections.Generic.List[object])
        Lines = (New-Object System.Collections.Generic.List[string])
        Names = (New-Object System.Collections.Generic.List[object]); NameIndex = (New-Object Collections.Hashtable ([StringComparer]::Ordinal)); NamesSorted = $null
        Counters = @{}; Bridge = $null; Shared = @{}
    }
}

function Get-KitFlag($Ctx, [string]$Name, $Default = $false) {
    if ($Ctx.Flags.ContainsKey($Name) -and $null -ne $Ctx.Flags[$Name]) { return $Ctx.Flags[$Name] }
    $Default
}

function Register-ValidationName {
    <# Remembers a private name (notebook, section, page title) so it is masked in every line. Returns
       what the log shows instead: the kit's own names stay, others become '<kind> #n' (notebook #1). #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][string]$Kind, [AllowEmptyString()][string]$Name)
    $n = "$Name".Trim()
    if (-not $n) { return "$Kind #?" }
    if ($script:FixedNames -ccontains $n) { return $n }
    $key = "$Kind|$n"
    if ($Ctx.NameIndex.ContainsKey($key)) { return $Ctx.NameIndex[$key] }
    if (-not $Ctx.Counters.ContainsKey($Kind)) { $Ctx.Counters[$Kind] = 0 }
    $Ctx.Counters[$Kind]++
    # Section names and page titles are only masked, never listed: they all read '<name>'.
    $alias = if ($Kind -eq 'name') { '<name>' } else { "$Kind #$($Ctx.Counters[$Kind])" }
    $Ctx.Names.Add([pscustomobject]@{ kind = $Kind; name = $n; alias = $alias })
    $Ctx.NameIndex[$key] = $alias
    $Ctx.NamesSorted = $null
    $alias
}

function Protect-KnownNames([string]$Text, $Ctx) {
    if (-not $Ctx -or -not $Ctx.Names.Count) { return $Text }
    # Longest first, so "Team notes 2" is not half replaced by "Team notes".
    if ($null -eq $Ctx.NamesSorted) { $Ctx.NamesSorted = @($Ctx.Names | Sort-Object { $_.name.Length } -Descending) }
    foreach ($e in $Ctx.NamesSorted) {
        if ($Text.IndexOf($e.name, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $Text = [regex]::Replace($Text, '(?<![\w-])' + [regex]::Escape($e.name) + '(?![\w-])', $e.alias, 'IgnoreCase')
    }
    $Text
}

function Protect-Addresses([string]$Text) {
    # onenote: links hold notebook, section and page names: drop them whole.
    $Text = [regex]::Replace($Text, '(?i)onenote:[^\s"''<>]*', 'onenote:<link>')
    # A URL keeps its scheme and host only; the path, query and fragment go.
    $Text = [regex]::Replace($Text, '(?i)\b(https?)://([^/\s"''<>?#]+)[^\s"''<>]*', {
            param($m)
            $rest = $m.Value.Substring($m.Groups[1].Length + 3 + $m.Groups[2].Length)
            "$($m.Groups[1].Value)://$($m.Groups[2].Value)" + $(if ($rest -and $rest -ne '/') { '/<path>' } else { '' })
        })
    # A SharePoint or OneDrive host names the organisation.
    $Text = [regex]::Replace($Text, '(?i)\b[a-z0-9-]+?(-my)?\.sharepoint(-df)?\.com\b', '<tenant>$1.sharepoint.com')
    # UNC paths name servers and shares.
    [regex]::Replace($Text, '\\\\[^\\\s"'']+\\[^\s"'']*', '<network path>')
}

function Protect-LocalIdentity([string]$Text) {
    if ($env:USERPROFILE) { $Text = [regex]::Replace($Text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', 'IgnoreCase') }
    $Text = [regex]::Replace($Text, '(?i)\b[a-z]:\\(Users|Documents and Settings)\\[^\\/\s"'']+', '%USERPROFILE%')
    # "OneDrive - Contoso Ltd" folders name the organisation.
    $Text = [regex]::Replace($Text, '(?i)OneDrive - [^\\/"'';,\r\n]+', 'OneDrive - <org>')
    $Text = [regex]::Replace($Text, '\bS-1-\d+(-\d+){1,14}\b', '<sid>')
    foreach ($pair in @(@($env:COMPUTERNAME, '<computer>'), @($env:USERDOMAIN, '<domain>'), @($env:USERNAME, '<user>'))) {
        $v = "$($pair[0])"
        if ($v.Length -ge 2) { $Text = [regex]::Replace($Text, '(?<![\w-])' + [regex]::Escape($v) + '(?![\w-])', $pair[1], 'IgnoreCase') }
    }
    $Text
}

function Protect-ValidationText {
    <# Masks one line for the log and the console. With -Ctx, also the names registered in this run. #>
    param([AllowEmptyString()][string]$Text, $Ctx = $null)
    if (-not $Text) { return $Text }
    $Text = Protect-KnownNames $Text $Ctx
    $Text = Protect-Addresses $Text
    $Text = [regex]::Replace($Text, '[\w.+''-]+@[\w-]+(\.[\w-]+)+', '<email>')
    $Text = [regex]::Replace($Text, '\{?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}?', '<id>')
    $Text = [regex]::Replace($Text, '\b[0-9a-fA-F]{32,}\b', '<id>')
    $Text = Protect-LocalIdentity $Text
    # The app log's own masking as the last pass (GUIDs, e-mail, query strings, profile path).
    Protect-AppLogText $Text
}

function Write-ValidationLine {
    <# One line to the console and the log file, masked. #>
    param([Parameter(Mandatory)]$Ctx, [AllowEmptyString()][string]$Text, [string]$Color = '')
    $safe = Protect-ValidationText $Text $Ctx
    $Ctx.Lines.Add($safe)
    if (-not $Ctx.Quiet) { if ($Color) { Write-Host $safe -ForegroundColor $Color } else { Write-Host $safe } }
    if ($Ctx.LogPath) {
        try { [IO.File]::AppendAllText($Ctx.LogPath, $safe + "`r`n", (New-Object Text.UTF8Encoding($false))) } catch { }
    }
}

function Add-ValidationResult {
    <# One [OK]/[WARN]/[FAIL]/[SKIP]/[INFO] line: kept for the summary, shown and logged (masked). #>
    param(
        [Parameter(Mandatory)]$Ctx,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][ValidateSet('OK', 'WARN', 'FAIL', 'SKIP', 'INFO')][string]$Status,
        [Parameter(Mandatory)][string]$Name,
        [string]$Detail = '',
        [string]$Hint = ''
    )
    $d = Protect-ValidationText $Detail $Ctx
    $h = Protect-ValidationText $Hint $Ctx
    # The name is the kit's own wording or an alias: the run's registered names are not applied to it.
    $n = Protect-ValidationText $Name
    $Ctx.Results.Add([pscustomobject]@{ stage = $Stage; status = $Status; name = $n; detail = $d })
    # A name of 22 characters or more would run into the detail: keep one space between them.
    if ($n.Length -ge 22 -and $d) { $d = ' ' + $d }
    $line = Format-StatusLine -Status $Status -Name $n -Detail $d
    $Ctx.Lines.Add($line)
    if ($h) { $Ctx.Lines.Add((' ' * 29) + $h) }
    if (-not $Ctx.Quiet) {
        if ($Status -eq 'SKIP') {
            Write-Host $line -ForegroundColor DarkGray
            if ($h) { Write-Host ((' ' * 29) + $h) -ForegroundColor DarkGray }
        } else { Write-Status -Status $Status -Name $n -Detail $d -Hint $h }
    }
    if ($Ctx.LogPath) {
        $text = $line + "`r`n" + $(if ($h) { (' ' * 29) + $h + "`r`n" } else { '' })
        try { [IO.File]::AppendAllText($Ctx.LogPath, $text, (New-Object Text.UTF8Encoding($false))) } catch { }
    }
}

function Measure-KitStep {
    <# Runs $Body and returns @{ ok; value; ms; error } (never throws). #>
    param([Parameter(Mandatory)][scriptblock]$Body)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $v = & $Body; return [pscustomobject]@{ ok = $true; value = $v; ms = $sw.ElapsedMilliseconds; error = '' } }
    catch { return [pscustomobject]@{ ok = $false; value = $null; ms = $sw.ElapsedMilliseconds; error = "$($_.Exception.Message)" } }
}

function Get-ValidationSummary {
    <# Counts per status (all and per stage), the overall result and the time taken. #>
    param([Parameter(Mandatory)]$Ctx)
    $counts = [ordered]@{}
    foreach ($s in $script:Statuses) { $counts[$s] = @($Ctx.Results | Where-Object { $_.status -eq $s }).Count }
    $perStage = [ordered]@{}
    foreach ($st in @($Ctx.Stages)) {
        $c = [ordered]@{}
        foreach ($s in $script:Statuses) { $c[$s] = @($Ctx.Results | Where-Object { $_.stage -eq $st -and $_.status -eq $s }).Count }
        $perStage[$st] = $c
    }
    $overall = if ($counts.FAIL) { 'FAIL' } elseif ($counts.WARN) { 'WARN' } else { 'OK' }
    [pscustomobject]@{ counts = $counts; stages = $perStage; result = $overall; seconds = [Math]::Round($Ctx.Watch.Elapsed.TotalSeconds, 1) }
}

function Get-ValidationHeader {
    <# The header lines: date, versions, stages and flags, and what the file holds. #>
    param([Parameter(Mandatory)]$Ctx, [string]$AppVersion = '', [string]$PsVersion = "$($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)")
    $flags = @($Ctx.Flags.Keys | Sort-Object | Where-Object { $Ctx.Flags[$_] -is [bool] -and $Ctx.Flags[$_] } | ForEach-Object { "-$_" })
    $win = try { [Environment]::OSVersion.Version.ToString() } catch { '?' }
    @(
        'ObsidiNote validation log',
        "Created:    $($Ctx.Started.ToString('yyyy-MM-dd HH:mm')) (local time)",
        "Kit:        $script:KitVersion",
        "ObsidiNote: $(if ($AppVersion) { $AppVersion } else { 'unknown' })",
        "PowerShell: $PsVersion; Windows $win",
        "Stages:     $(@($Ctx.Stages) -join ', ')",
        "Flags:      $(if ($flags.Count) { $flags -join ' ' } else { '(none)' })",
        'This file holds status lines, counts and timings only. It holds no page titles or page text,',
        'no prompts or Copilot replies, no web addresses with paths, no names, e-mail addresses, ids,',
        'machine names or user folders. Notebooks are shown as "notebook #1", "notebook #2" (except the',
        "kit's own test notebooks ObsidiNote-Probe and ObsidiNote-Validation).",
        ''
    )
}

function Get-ValidationFooter {
    param([Parameter(Mandatory)]$Ctx)
    $s = Get-ValidationSummary $Ctx
    $parts = @(foreach ($k in $s.counts.Keys) { "$($s.counts[$k]) $k" })
    @('', "Summary: $($parts -join ', ') in $($s.seconds) s", "Result:  $($s.result)")
}

function ConvertTo-ValidationJson {
    <# The summary as JSON (the same masked values as the log). #>
    param([Parameter(Mandatory)]$Ctx, [string]$AppVersion = '')
    $s = Get-ValidationSummary $Ctx
    $o = [ordered]@{
        kit = $script:KitVersion; obsidiNote = $AppVersion
        powerShell = "$($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
        created = $Ctx.Started.ToString('yyyy-MM-dd HH:mm'); seconds = $s.seconds
        stages = @($Ctx.Stages); flags = @($Ctx.Flags.Keys | Sort-Object | Where-Object { $Ctx.Flags[$_] -is [bool] -and $Ctx.Flags[$_] })
        result = $s.result; counts = $s.counts; perStage = $s.stages
        results = @($Ctx.Results | ForEach-Object { [ordered]@{ stage = $_.stage; status = $_.status; name = $_.name; detail = $_.detail } })
    }
    ConvertTo-Json -InputObject $o -Depth 5
}

function Get-JsonFromReply {
    <# The first JSON object in a Copilot reply (fences and text around it are ignored), or $null. #>
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return $null }
    $a = $Text.IndexOf('{'); $b = $Text.LastIndexOf('}')
    if ($a -lt 0 -or $b -le $a) { return $null }
    try { $o = $Text.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch { return $null }
    if ($o -is [pscustomobject]) { return $o }
    $null
}

function Test-JsonShape {
    <# True when $Object has every key in $Keys (a JSON reply in the expected shape). #>
    param($Object, [string[]]$Keys)
    if (-not $Object) { return $false }
    foreach ($k in $Keys) { if (-not $Object.PSObject.Properties[$k]) { return $false } }
    $true
}

function Get-KitPrompt {
    <# Asks the person (unless -NoPrompt); '' when skipped or not answered. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)][string]$Question)
    if (Get-KitFlag $Ctx 'NoPrompt') { return '' }
    try { "$(& $Ctx.Prompt $Question)".Trim() } catch { '' }
}

function Format-YesNo([bool]$Value) { if ($Value) { 'yes' } else { 'no' } }

Export-ModuleMember -Function Get-KitVersion, Get-ProbeNotebookName, Get-DevNotebookName, Get-ValidationStages, Get-StageTitle,
    Test-KitNameAllowed, New-ValidationContext, Get-KitFlag, Register-ValidationName, Protect-ValidationText, Write-ValidationLine,
    Add-ValidationResult, Measure-KitStep, Get-ValidationSummary, Get-ValidationHeader, Get-ValidationFooter, ConvertTo-ValidationJson,
    Get-JsonFromReply, Test-JsonShape, Get-KitPrompt, Format-YesNo
