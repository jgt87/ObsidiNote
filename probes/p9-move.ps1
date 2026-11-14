# P9: move a page to another section with UpdateHierarchy (needed to re-file existing pages when a
# filing rule changes; operator, 2026-11-13). Writes only inside the ObsidiNote-Probe notebook:
# sections "Move from" and "Move to", invented pages. Checks: the page leaves the old section and
# appears in the new one, keeps its id, Meta and outlines; the other page in the target section is
# untouched; whether the page's onenote: link changes. Then the probe pages go to Deleted Pages.
# Output: statuses and counts only. PS 5.1, ASCII only.
param([string]$BasePath = '')
$ErrorActionPreference = 'Stop'
$on = New-Object -ComObject OneNote.Application
$ONS = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
function Ns([xml]$x) { $m = New-Object System.Xml.XmlNamespaceManager($x.NameTable); $m.AddNamespace('one', $ONS); ,$m }
function Hier([string]$id, [int]$scope) { $s = ''; $on.GetHierarchy($id, $scope, [ref]$s); [xml]$s }
function PageXml([string]$id) { $s = ''; $on.GetPageContent($id, [ref]$s, 0); [xml]$s }
function Check([string]$label, [bool]$ok, [string]$detail = '') { "{0} {1,-46} {2}" -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $label, $detail; if (-not $ok) { $script:fails++ } }
$script:fails = 0

# notebook and sections (probe notebook only)
$hx = Hier '' 1
$first = $hx.SelectSingleNode('//one:Notebook', (Ns $hx))
if ($BasePath) { $base = $BasePath.TrimEnd('/') + '/' }
elseif ($first -and $first.path -match '^https://') { $base = $first.path.Substring(0, $first.path.TrimEnd('/').LastIndexOf('/') + 1) }
elseif ($first) { $base = (Split-Path -Parent $first.path) + '\' }
else { throw 'No notebook open in OneNote.' }
$r = ''; $on.OpenHierarchy($base + 'ObsidiNote-Probe', '', [ref]$r, 1); $nbId = $r
$r = ''; $on.OpenHierarchy('Move from.one', $nbId, [ref]$r, 3); $fromId = $r
$r = ''; $on.OpenHierarchy('Move to.one', $nbId, [ref]$r, 3); $toId = $r
foreach ($s in $fromId, $toId) { $x = Hier $s 4; foreach ($p in @($x.SelectNodes('//one:Page', (Ns $x)))) { $on.DeleteHierarchy($p.ID) } }

# pages: P in "Move from" (Meta + two outlines), Q in "Move to" linking to P
$r = ''; $on.CreateNewPage($fromId, [ref]$r, 1); $pP = $r
$r = ''; $on.CreateNewPage($toId, [ref]$r, 1); $pQ = $r
$linkBefore = ''; $on.GetHyperlinkToObject($pP, '', [ref]$linkBefore)
$on.UpdatePageContent(@"
<?xml version="1.0"?>
<one:Page xmlns:one="$ONS" ID="$pP"><one:Meta name="obsn.id" content="p9move" /><one:Meta name="obsn.type" content="link-web" />
<one:Title><one:OE><one:T><![CDATA[Probe page to move]]></one:T></one:OE></one:Title>
<one:Outline><one:Meta name="obsn.role" content="props" /><one:OEChildren><one:OE><one:T><![CDATA[type: link-web]]></one:T></one:OE></one:OEChildren></one:Outline>
<one:Outline><one:OEChildren><one:OE><one:T><![CDATA[Text the person typed; it must survive the move.]]></one:T></one:OE></one:OEChildren></one:Outline>
</one:Page>
"@)
$on.UpdatePageContent(@"
<?xml version="1.0"?>
<one:Page xmlns:one="$ONS" ID="$pQ"><one:Title><one:OE><one:T><![CDATA[Probe page that stays]]></one:T></one:OE></one:Title>
<one:Outline><one:OEChildren><one:OE><one:T><![CDATA[<a href="$([Security.SecurityElement]::Escape($linkBefore))">link to the moved page</a>]]></one:T></one:OE></one:OEChildren></one:Outline>
</one:Page>
"@)
"Pages made: P in 'Move from', Q in 'Move to'"

# the move: the target section's hierarchy with P's page element added, through UpdateHierarchy
$src = Hier $fromId 4
$pageEl = $src.SelectSingleNode("//one:Page[@ID='$pP']", (Ns $src))
$dst = Hier $toId 4
$sec = $dst.SelectSingleNode('//one:Section', (Ns $dst))
$null = $sec.AppendChild($dst.ImportNode($pageEl, $true))
$sw = [Diagnostics.Stopwatch]::StartNew()
$moveError = ''
try { $on.UpdateHierarchy($dst.OuterXml) } catch { $moveError = $_.Exception.Message }
Check 'UpdateHierarchy accepted' (-not $moveError) "$($sw.ElapsedMilliseconds) ms $moveError"

# checks
$fromAfter = Hier $fromId 4; $toAfter = Hier $toId 4
$inFrom = @($fromAfter.SelectNodes("//one:Page[@ID='$pP']", (Ns $fromAfter))).Count
$inTo = @($toAfter.SelectNodes("//one:Page[@ID='$pP']", (Ns $toAfter))).Count
$qStill = @($toAfter.SelectNodes("//one:Page[@ID='$pQ']", (Ns $toAfter))).Count
Check 'P left the old section' ($inFrom -eq 0) "count $inFrom"
Check 'Q in the target section untouched' ($qStill -eq 1) "count $qStill"
# Seen 2026-11-13: the moved page gets a NEW hierarchy id; find it by its obsn.id Meta (as the
# upgrade step must), never by title.
$movedId = if ($inTo -eq 1) { $pP } else { @($toAfter.SelectNodes("//one:Page[one:Meta[@name='obsn.id' and @content='p9move']]", (Ns $toAfter)) | ForEach-Object { $_.ID }) | Select-Object -First 1 }
Check 'P is in the new section (found by obsn.id)' ([bool]$movedId) "same hierarchy id: $($inTo -eq 1)"
if ($movedId) {
  $px = PageXml $movedId; $pn = Ns $px
  Check 'Meta kept' ($px.SelectSingleNode("//one:Meta[@name='obsn.id']", $pn).content -eq 'p9move')
  Check 'owned outline kept' ($null -ne $px.SelectSingleNode("//one:Outline[one:Meta[@name='obsn.role' and @content='props']]", $pn))
  Check 'the person''s text kept' ($px.OuterXml -match 'must survive the move')
  $linkAfter = ''; $on.GetHyperlinkToObject($movedId, '', [ref]$linkAfter)
  $samePageId = ([regex]::Match($linkBefore, 'page-id=\{[^}]+\}').Value) -eq ([regex]::Match($linkAfter, 'page-id=\{[^}]+\}').Value)
  "INFO link changed: $($linkBefore -ne $linkAfter); same page-id in the link: $samePageId (old links resolve by page-id)"
}

# clean up: the probe pages to Deleted Pages (probe notebook only)
foreach ($p in @($pQ, $movedId, $(if ($inFrom) { $pP })) | Where-Object { $_ } | Select-Object -Unique) { try { $on.DeleteHierarchy($p) } catch { } }
"Cleaned up. Failures: $($script:fails)"
if ($script:fails) { exit 1 }
