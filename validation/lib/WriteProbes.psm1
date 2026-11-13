# The write probes of the validation kit, all inside the throwaway notebook ObsidiNote-Probe (through
# the guard in ProbeNotebook.psm1): P1 (COM round trip, as probes/p1-roundtrip.ps1), P1b (the largest
# obsn.* Meta value OneNote keeps), P1c (does an onenote: link still open a page after it moved to
# another section; what a link to a deleted page does) and the P3 marker pages. Synthetic text only;
# results are counts, yes/no and timings. Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
# Functions that return a list write its items to the pipeline; callers collect them with @().
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProbeNotebook.psm1')

$script:Ns = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$script:P1bSizes = @(1000, 30000, 100000, 262144)
$script:MarkerSection = 'P3 markers'

function Select-OneNodes([string]$Xml, [string]$XPath) {
    $d = Read-KitXml $Xml
    if (-not $d) { return }
    $m = New-Object System.Xml.XmlNamespaceManager($d.NameTable)
    $m.AddNamespace('one', $script:Ns)
    @($d.SelectNodes($XPath, $m))
}

function Get-HResult($ErrorRecord) {
    $h = [regex]::Match("$($ErrorRecord.Exception)", '0x[0-9A-Fa-f]{8}').Value
    if ($h) { $h } else { 'no HRESULT' }
}

function New-P1Pages {
    <# Section Notes with pages A and B (old probe pages removed first): @{ sec; a; b; la; lb; removed }. #>
    param([Parameter(Mandatory)]$Guard)
    $sec = Add-ProbeSection $Guard 'Notes'
    $removed = Clear-ProbeSection $Guard $sec
    $a = New-ProbePage $Guard $sec
    $b = New-ProbePage $Guard $sec
    [pscustomobject]@{ sec = $sec; a = $a; b = $b; la = $Guard.One.GetHyperlinkToObject($a); lb = $Guard.One.GetHyperlinkToObject($b); removed = $removed }
}

function Write-P1Pages {
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)]$P)
    $esc = { param($s) [Security.SecurityElement]::Escape($s) }
    Set-ProbePageXml $Guard (New-ProbePageXml -PageId $P.a -Title 'Zero-trust networking' -Meta @{ 'obsn.id' = 'p0001' } -Outlines @(
            @{ role = 'props'; lines = @('type: concept', 'topics: Security, Networking', 'id: p0001') },
            @{ role = 'body'; lines = @("Zero trust assumes no implicit trust. It relies on <a href=""$(& $esc $P.lb)"">identity-aware proxies</a> for every request.") }))
    Set-ProbePageXml $Guard (New-ProbePageXml -PageId $P.b -Title 'Identity-aware proxies' -Meta @{ 'obsn.id' = 'p0002' } -Outlines @(
            @{ role = 'body'; lines = @('A proxy that checks user and device identity before forwarding a request.') },
            @{ role = 'backlinks'; lines = @('Linked from:', "<a href=""$(& $esc $P.la)"">Zero-trust networking</a>") }))
}

function Test-P1ReadBack {
    <# The read-back checks of P1: names of the checks that failed (empty = all kept). #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)]$P)
    $ra = $Guard.One.GetPageContent($P.a)
    $rb = $Guard.One.GetPageContent($P.b)
    $failed = @()
    if (@(Select-OneNodes $ra '//one:Title//one:T' | Where-Object { $_.InnerText -eq 'Zero-trust networking' }).Count -eq 0) { $failed += 'title' }
    if (@(Select-OneNodes $ra '/one:Page/one:Meta[@name="obsn.id" and @content="p0001"]').Count -eq 0) { $failed += 'page Meta' }
    $roles = (@(Select-OneNodes $ra '//one:Outline/one:Meta[@name="obsn.role"]' | ForEach-Object { $_.GetAttribute('content') }) -join ',')
    if ($roles -ne 'props,body') { $failed += 'outline Meta' }
    if ($ra -notmatch 'href="onenote:') { $failed += 'onenote link' }
    if (@(Select-OneNodes $rb '//one:Outline[one:Meta[@name="obsn.role" and @content="backlinks"]]').Count -eq 0) { $failed += 'backlinks outline' }
    $failed
}

function Test-P1Rewrite {
    <# Rewrites only the owned backlinks outline of page B (by objectID); names of failed checks. #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)]$P)
    $bl = @(Select-OneNodes ($Guard.One.GetPageContent($P.b)) '//one:Outline[one:Meta[@name="obsn.role" and @content="backlinks"]]')
    if (-not $bl.Count) { return 'backlinks outline' }
    $lines = @('Linked from:', "<a href=""$([Security.SecurityElement]::Escape($P.la))"">Zero-trust networking</a>", 'Rewritten by the validation kit.')
    Set-ProbePageXml $Guard (New-ProbePageXml -PageId $P.b -Outlines @(@{ role = 'backlinks'; lines = $lines; objectId = $bl[0].GetAttribute('objectID') }))
    $rb = $Guard.One.GetPageContent($P.b)
    $failed = @()
    if (@(Select-OneNodes $rb '//one:Outline').Count -ne 2) { $failed += 'outline count' }
    if ($rb -notmatch 'checks user and device identity') { $failed += 'body kept' }
    if ($rb -notmatch 'Rewritten by the validation kit') { $failed += 'outline rewritten' }
    $failed
}

function Invoke-ProbeRoundTrip {
    <# P1: COM round trip in ObsidiNote-Probe. Adds result lines to $Stage. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Guard, [string]$Stage = 'V2')
    $made = Measure-KitStep { New-P1Pages $Guard }
    if (-not $made.ok) { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1 create' $made.error; return }
    $p = $made.value
    Add-ValidationResult $Ctx $Stage 'OK' 'P1 create' "notebook ObsidiNote-Probe $(if ($Guard.Created) { 'created' } else { 'reused' }); section and 2 pages in $($made.ms) ms; $($p.removed) old probe page(s) removed"
    $w = Measure-KitStep { Write-P1Pages $Guard $p }
    if (-not $w.ok) { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1 write' "UpdatePageContent: $($w.error)"; return }
    Add-ValidationResult $Ctx $Stage 'OK' 'P1 write' "2 pages with Meta, outlines and a link in $($w.ms) ms"
    $r = Measure-KitStep { Test-P1ReadBack $Guard $p }
    $bad = @(if ($r.ok) { $r.value } else { "read failed: $($r.error)" })
    if ($bad.Count) { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1 read back' "not kept: $($bad -join ', ')" }
    else { Add-ValidationResult $Ctx $Stage 'OK' 'P1 read back' "title, page Meta, outline Meta, onenote link and backlinks outline kept ($($r.ms) ms)" }
    $o = Measure-KitStep { Test-P1Rewrite $Guard $p }
    $bad = @(if ($o.ok) { $o.value } else { "rewrite failed: $($o.error)" })
    if ($bad.Count) { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1 owned outline' "failed: $($bad -join ', ')" }
    else { Add-ValidationResult $Ctx $Stage 'OK' 'P1 owned outline' "rewritten by objectID; the rest of the page kept ($($o.ms) ms)" }
    $s = Measure-KitStep { $Guard.One.SyncHierarchy($Guard.RootId) }
    if ($s.ok) { Add-ValidationResult $Ctx $Stage 'OK' 'P1 sync' "SyncHierarchy in $($s.ms) ms" }
    else { Add-ValidationResult $Ctx $Stage 'WARN' 'P1 sync' $s.error }
}

function Get-MetaSizeValue([int]$Size) {
    $unit = '{"i":"p1","t":"A & B <c> \"q\"","s":"summary text"},'
    ($unit * ([int][Math]::Ceiling($Size / $unit.Length))).Substring(0, $Size)
}

function Test-MetaSize {
    <# One P1b size: 'kept', 'changed' or 'refused 0x...', with timings. #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$SectionId, [int]$Size)
    $val = Get-MetaSizeValue $Size
    $pg = New-ProbePage $Guard $SectionId
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { Set-ProbePageXml $Guard (New-ProbePageXml -PageId $pg -Title "size $Size" -Meta @{ 'obsn.big' = $val }) }
    catch { return [pscustomobject]@{ size = $Size; state = "refused ($(Get-HResult $_))"; writeMs = $sw.ElapsedMilliseconds; readMs = 0 } }
    $w = $sw.ElapsedMilliseconds; $sw.Restart()
    $page = @(Select-OneNodes ($Guard.One.GetPageContent($pg)) '/one:Page/one:Meta[@name="obsn.big"]' | ForEach-Object { $_.GetAttribute('content') })
    $hier = @(Select-OneNodes ($Guard.One.GetHierarchy($SectionId, 4)) "//one:Page[@ID='$pg']/one:Meta[@name='obsn.big']" | ForEach-Object { $_.GetAttribute('content') })
    $state = if ($page.Count -and $page[0] -ceq $val -and $hier.Count -and $hier[0] -ceq $val) { 'kept' } elseif ($page.Count -and $page[0] -ceq $val) { 'page only' } else { 'changed' }
    [pscustomobject]@{ size = $Size; state = $state; writeMs = $w; readMs = $sw.ElapsedMilliseconds }
}

function Invoke-ProbeMetaSize {
    <# P1b part 1: the largest obsn.* Meta value kept in the page and in the hierarchy. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Guard, [string]$Stage = 'V2', [int[]]$Sizes = $script:P1bSizes)
    $sec = Measure-KitStep { $s = Add-ProbeSection $Guard 'P1b size'; $null = Clear-ProbeSection $Guard $s; $s }
    if (-not $sec.ok) { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1b Meta size' $sec.error; return }
    $kept = 0; $stop = $null; $last = $null
    foreach ($n in $Sizes) {
        $t = Measure-KitStep { Test-MetaSize $Guard $sec.value $n }
        if (-not $t.ok) { $stop = [pscustomobject]@{ size = $n; state = "failed: $($t.error)" }; break }
        if ($t.value.state -ne 'kept') { $stop = $t.value; break }
        $kept = $n; $last = $t.value
    }
    $timing = if ($last) { " (largest: write $($last.writeMs) ms, read $($last.readMs) ms)" } else { '' }
    if (-not $stop) { Add-ValidationResult $Ctx $Stage 'OK' 'P1b Meta size' "kept up to $kept chars in page and hierarchy$timing" }
    else { Add-ValidationResult $Ctx $Stage 'WARN' 'P1b Meta size' "kept up to $kept chars$timing; at $($stop.size) chars: $($stop.state)" }
}

function Find-ProbePageByTitle([object[]]$Pages, [string]$Title) { @($Pages | Where-Object { $_ -and $_.title -eq $Title }) | Select-Object -First 1 }

function Wait-ProbeNavigation {
    <# Opens $Url in OneNote and returns the page OneNote shows then ('' when unknown), or 'error 0x...'. #>
    param([Parameter(Mandatory)]$One, [Parameter(Mandatory)][string]$Url, [int]$WaitMs = 1500)
    try { $One.NavigateToUrl($Url) } catch { return "error $(Get-HResult $_)" }
    Start-Sleep -Milliseconds $WaitMs
    $One.CurrentPageId()
}

function Move-P1cPage {
    <# Moves 'P1c move me' to 'P1c moved', by the kit or (when OneNote refuses) by the person. Returns
       @{ how; page } or $null when skipped. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Guard, [string]$PageId, [string]$HomeSection, [string]$Moved)
    try { Move-ProbePage $Guard $PageId $Moved } catch { }
    $p = Find-ProbePageByTitle (Get-ProbeSectionPages $Guard $Moved) 'P1c move me'
    if ($p) { return [pscustomobject]@{ how = 'by the kit'; page = $p } }
    $a = Get-KitPrompt $Ctx "In OneNote, drag the page 'P1c move me' (notebook ObsidiNote-Probe, section 'P1c home') to the section 'P1c moved'. Press Enter when done, or type s and Enter to skip"
    if ($a -eq 's' -or (Get-KitFlag $Ctx 'NoPrompt')) { return $null }
    $p = Find-ProbePageByTitle (Get-ProbeSectionPages $Guard $Moved) 'P1c move me'
    if ($p) { return [pscustomobject]@{ how = 'by hand'; page = $p } }
    $null
}

function New-P1cPage([object]$Guard, [string]$Section, [string]$Title) {
    $id = New-ProbePage $Guard $Section
    Set-ProbePageXml $Guard (New-ProbePageXml -PageId $id -Title $Title -Outlines @(@{ role = 'body'; lines = @('Synthetic page for the link test of the validation kit.') }))
    $id
}

function Invoke-ProbeLinkMove {
    <# P1c: an onenote: link after the page moved to another section, and a link to a deleted page.
       Moves OneNote's view; it goes back to the page shown before at the end. #>
    param([Parameter(Mandatory)]$Ctx, [Parameter(Mandatory)]$Guard, [string]$Stage = 'V2', [int]$WaitMs = 1500)
    $before = $Guard.One.CurrentPageId()
    try {
        $homeSec = Add-ProbeSection $Guard 'P1c home'; $moved = Add-ProbeSection $Guard 'P1c moved'
        $null = Clear-ProbeSection $Guard $homeSec; $null = Clear-ProbeSection $Guard $moved
        $c = New-P1cPage $Guard $homeSec 'P1c move me'
        $d = New-P1cPage $Guard $homeSec 'P1c delete me'
        $lc = $Guard.One.GetHyperlinkToObject($c); $ld = $Guard.One.GetHyperlinkToObject($d)
    } catch { Add-ValidationResult $Ctx $Stage 'FAIL' 'P1c set up' $_.Exception.Message; return }
    $m = Move-P1cPage -Ctx $Ctx -Guard $Guard -PageId $c -HomeSection $homeSec -Moved $moved
    if (-not $m) { Add-ValidationResult $Ctx $Stage 'SKIP' 'P1c link after move' 'OneNote did not move the page for the kit, and it was not moved by hand' 'Run V2 -WriteTest again without -NoPrompt and move the page when asked.' }
    else {
        $now = $m.page.id
        $shown = Wait-ProbeNavigation -One $Guard.One -Url $lc -WaitMs $WaitMs
        $opens = ($shown -eq $now)
        $linkSame = ($Guard.One.GetHyperlinkToObject($now) -eq $lc)
        $detail = "moved $($m.how); old link opens the page: $(Format-YesNo $opens); page id kept: $(Format-YesNo ($now -eq $c)); link unchanged: $(Format-YesNo $linkSame)"
        Add-ValidationResult $Ctx $Stage $(if ($opens) { 'OK' } else { 'WARN' }) 'P1c link after move' $detail $(if (-not $opens) { 'Archiving must then rewrite links to a moved page.' } else { '' })
    }
    try {
        Remove-ProbeObject $Guard $d
        $shown = Wait-ProbeNavigation -One $Guard.One -Url $ld -WaitMs $WaitMs
        $what = if ($shown -like 'error*') { "OneNote reports $shown" } elseif ($shown -eq $d) { 'opens the page in Deleted Pages' } elseif (-not $shown) { 'no page shown' } else { 'opens another page' }
        Add-ValidationResult $Ctx $Stage 'INFO' 'P1c deleted-page link' $what
    } catch { Add-ValidationResult $Ctx $Stage 'WARN' 'P1c deleted-page link' $_.Exception.Message }
    if ($before) { try { $Guard.One.NavigateTo($before) } catch { } }
}

function New-ProbeMarker {
    <# P3: a new marker page in ObsidiNote-Probe, section 'P3 markers'. Returns the marker. #>
    param([Parameter(Mandatory)]$Guard)
    $marker = New-KitMarker 'OBSN-P3'
    $sec = Add-ProbeSection $Guard $script:MarkerSection
    $pg = New-ProbePage $Guard $sec
    Set-ProbePageXml $Guard (New-ProbePageXml -PageId $pg -Title "P3 marker $marker" -Outlines @(@{ role = 'body'; lines = @("Validation marker $marker. Synthetic text for the grounding probe of ObsidiNote.") }))
    $marker
}

function Get-ProbeMarkers {
    <# The P3 marker pages in ObsidiNote-Probe (read only), newest first: @(@{ marker; ageHours }). #>
    param([Parameter(Mandatory)]$One, [datetime]$Now = (Get-Date))
    $nb = Find-KitNotebook -Xml ($One.GetHierarchy('', 2)) -Name (Get-ProbeNotebookName)
    if (-not $nb) { return }
    $pages = @(Select-OneNodes ($One.GetHierarchy($nb.id, 4)) "//one:Section[@name='$script:MarkerSection']/one:Page")
    $out = @(foreach ($p in $pages) {
            $t = $p.GetAttribute('name')
            if ($t -notmatch '^P3 marker (OBSN-P3-[A-Z0-9]{6})$') { continue }
            $when = [datetime]::MinValue
            $created = if ([datetime]::TryParse($p.GetAttribute('dateTime'), [ref]$when)) { $when.ToLocalTime() } else { $Now }
            [pscustomobject]@{ marker = $Matches[1]; ageHours = [Math]::Round(($Now - $created).TotalHours, 1) }
        })
    @($out | Sort-Object ageHours)
}

Export-ModuleMember -Function Invoke-ProbeRoundTrip, Invoke-ProbeMetaSize, Invoke-ProbeLinkMove, New-ProbeMarker, Get-ProbeMarkers, Get-MetaSizeValue, Test-P1ReadBack
