# P1: COM round trip. Creates notebook ObsidiNote-Probe (next to the first cloud notebook),
# section Notes, pages A and B, links A->B, owned "Linked from" outline on B, rewrites it,
# reads back, searches. Writes only inside ObsidiNote-Probe. PS 5.1, ASCII only.
param(
  # Folder URL for the probe notebook, e.g. https://<tenant>-my.sharepoint.com/personal/<user>/Documents/
  # Default: the folder of the first open cloud notebook.
  [string]$BasePath = ''
)
$ErrorActionPreference = 'Stop'
$on = New-Object -ComObject OneNote.Application
$ONS = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$marker = 'OBSN-PROBE-7Q4K'
function T([string]$label, [scriptblock]$b) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { $r = & $b; "OK   {0,-34} {1,6} ms" -f $label, $sw.ElapsedMilliseconds; return $r }
  catch { "FAIL {0,-34} {1}" -f $label, $_.Exception.Message; throw }
}
function Ns([xml]$x) { $m = New-Object System.Xml.XmlNamespaceManager($x.NameTable); $m.AddNamespace('one', $ONS); ,$m }
function PageXml([string]$id) { $s = ''; $on.GetPageContent($id, [ref]$s, 0); [xml]$s }
function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }

# 1. notebook
$h = ''; $on.GetHierarchy('', 1, [ref]$h); [xml]$hx = $h
$first = $hx.SelectSingleNode('//one:Notebook', (Ns $hx))
if ($BasePath) { $base = $BasePath.TrimEnd('/') + '/' }
elseif ($first -and $first.path -match '^https://') { $base = $first.path.Substring(0, $first.path.TrimEnd('/').LastIndexOf('/') + 1) }
else { throw 'No cloud notebook open. Open one in OneNote first, or pass -BasePath with your OneDrive Documents URL.' }
$nbPath = $base + 'ObsidiNote-Probe'
"Notebook path: $nbPath"
$nbId = ''
T 'OpenHierarchy notebook (create)' { $script:r = ''; $on.OpenHierarchy($nbPath, '', [ref]$script:r, 1); $script:r } | Out-Host
$nbId = $script:r
# 2. section
T 'OpenHierarchy section Notes' { $script:r = ''; $on.OpenHierarchy('Notes.one', $nbId, [ref]$script:r, 3) } | Out-Host
$secId = $script:r
# 3. pages (first remove pages left by earlier probe runs; probe notebook only)
$sx = ''; $on.GetHierarchy($secId, 4, [ref]$sx); [xml]$sxx = $sx
foreach ($old in $sxx.SelectNodes('//one:Page', (Ns $sxx))) { $on.DeleteHierarchy($old.ID) }
"old probe pages removed: " + $sxx.SelectNodes('//one:Page', (Ns $sxx)).Count
T 'CreateNewPage A' { $script:r = ''; $on.CreateNewPage($secId, [ref]$script:r, 1) } | Out-Host
$pA = $script:r
T 'CreateNewPage B' { $script:r = ''; $on.CreateNewPage($secId, [ref]$script:r, 1) } | Out-Host
$pB = $script:r
T 'GetHyperlinkToObject B' { $script:r = ''; $on.GetHyperlinkToObject($pB, '', [ref]$script:r) } | Out-Host
$linkB = $script:r
T 'GetHyperlinkToObject A' { $script:r = ''; $on.GetHyperlinkToObject($pA, '', [ref]$script:r) } | Out-Host
$linkA = $script:r
"Link B: " + ($linkB -replace '(page-id=)\{[^}]+\}', '$1{...}').Substring(0, [Math]::Min(90, $linkB.Length)) + '...'

function OE([string]$html) { "<one:OE><one:T><![CDATA[$html]]></one:T></one:OE>" }
function Outline([string]$role, [string[]]$lines, [string]$objId) {
  $idAttr = if ($objId) { " objectID=""$objId""" } else { '' }
  "<one:Outline$idAttr><one:Meta name=""obsn.role"" content=""$role"" /><one:OEChildren>" + (($lines | ForEach-Object { OE $_ }) -join '') + "</one:OEChildren></one:Outline>"
}
# 4. page A: properties + body linking to B
$xa = @"
<?xml version="1.0"?>
<one:Page xmlns:one="$ONS" ID="$pA">
<one:Meta name="obsn.id" content="p0001" />
<one:Title><one:OE><one:T><![CDATA[Zero-trust networking]]></one:T></one:OE></one:Title>
$(Outline 'props' @('type: concept', 'topics: Security, Networking', "id: p0001 | $marker"))
$(Outline 'body' @("Zero trust assumes no implicit trust. It relies on <a href=""$(Esc $linkB)"">identity-aware proxies</a> for every request."))
</one:Page>
"@
T 'UpdatePageContent A' { $on.UpdatePageContent($xa) } | Out-Host
# 5. page B: body + owned Linked-from outline
$xb = @"
<?xml version="1.0"?>
<one:Page xmlns:one="$ONS" ID="$pB">
<one:Meta name="obsn.id" content="p0002" />
<one:Title><one:OE><one:T><![CDATA[Identity-aware proxies]]></one:T></one:OE></one:Title>
$(Outline 'body' @('A proxy that checks user and device identity before forwarding a request.'))
$(Outline 'backlinks' @('Linked from:', "<a href=""$(Esc $linkA)"">Zero-trust networking</a>"))
</one:Page>
"@
T 'UpdatePageContent B' { $on.UpdatePageContent($xb) } | Out-Host

# 6. read back
$ra = PageXml $pA; $na = Ns $ra
"A title: " + $ra.SelectSingleNode('//one:Title//one:T', $na).InnerText
"A page Meta obsn.id: " + $ra.SelectSingleNode('/one:Page/one:Meta[@name="obsn.id"]', $na).content
"A outline Meta roles: " + (($ra.SelectNodes('//one:Outline/one:Meta[@name="obsn.role"]', $na) | ForEach-Object { $_.content }) -join ',')
"A body has onenote link: " + [bool]($ra.InnerXml -match 'href="onenote:')
$rb = PageXml $pB; $nb2 = Ns $rb
$bl = $rb.SelectSingleNode('//one:Outline[one:Meta[@name="obsn.role" and @content="backlinks"]]', $nb2)
"B backlinks outline found by Meta: " + [bool]$bl

# 7. rewrite only the owned outline (by objectID)
$blId = $bl.objectID
$xb2 = @"
<?xml version="1.0"?>
<one:Page xmlns:one="$ONS" ID="$pB">
$(Outline 'backlinks' @('Linked from:', "<a href=""$(Esc $linkA)"">Zero-trust networking</a>", 'Rewritten by probe (2 sources would be listed here).') $blId)
</one:Page>
"@
T 'UpdatePageContent B (rewrite outline)' { $on.UpdatePageContent($xb2) } | Out-Host
$rb = PageXml $pB; $nb2 = Ns $rb
"B outlines after rewrite: " + $rb.SelectNodes('//one:Outline', $nb2).Count + " (expect 2)"
"B body untouched: " + [bool]($rb.InnerXml -match 'checks user and device identity')
"B backlinks rewritten: " + [bool]($rb.InnerXml -match 'Rewritten by probe')

# 8. search
$f = ''
T 'FindPages marker (notebook)' { $on.FindPages($nbId, $marker, [ref]$script:f, $false, $false) } | Out-Host
[xml]$fx = $script:f
"FindPages hits now: " + $fx.SelectNodes('//one:Page', (Ns $fx)).Count + " (index may lag)"
T 'SyncHierarchy notebook' { $on.SyncHierarchy($nbId) } | Out-Host
"IDS nb=$nbId sec=$secId A=$pA B=$pB" | Set-Content -Path (Join-Path $PSScriptRoot 'p1-ids.txt') -Encoding ASCII
"DONE"
