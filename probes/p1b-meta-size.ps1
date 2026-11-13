# P1b: (1) the largest obsn.* Meta value OneNote accepts and keeps (round trip through
# GetPageContent and through GetHierarchy at page scope), (2) the time to write and to load an
# Index section whose Meta holds 100 / 1000 synthetic entries. Writes ONLY into the throwaway
# notebook ObsidiNote-Probe (created next to the first cloud notebook when missing), through the
# write guard with that notebook as root. Synthetic data only. Prints a short table.
# Windows PowerShell 5.1 with OneNote desktop running. ASCII only.
param(
    [int[]]$Sizes = @(1000, 10000, 30000, 65536, 100000, 262144, 524288, 1048576, 4194304),
    [int[]]$Entries = @(100, 1000),
    [int]$TopicSize = 10,
    [string]$BasePath = ''
)
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index') { Import-Module (Join-Path $lib "$m.psm1") -Force }
$Name = 'ObsidiNote-Probe'

$a = Get-OneNoteAdapter
$nb = ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy('', 2)) -Name $Name
if ($nb) { $root = $nb.notebook.id }
else { $root = $a.CreateNotebook((Get-NotebookBasePath -NotebooksXml ($a.GetHierarchy('', 2)) -Location $BasePath) + $Name) }
Set-OneNoteWriteRoot -Adapter $a -RootId $root
# Remove what earlier P1b runs left (probe notebook only).
foreach ($s in (ConvertFrom-ObsnHierarchy -Xml ($a.GetHierarchy($root, 3)) -RootId $root).sections) { if ($s.name -like 'P1b*') { $a.DeleteHierarchy($s.id) } }

$out = New-Object System.Collections.ArrayList
"P1b part 1: Meta value size (round trip)"
$sec = $a.OpenHierarchy('P1b size.one', $root, 3)
$unit = '{"i":"p1","t":"A & B <c> ""q""","s":"summary text"},'
foreach ($n in $Sizes) {
    $val = ($unit * ([int][Math]::Ceiling($n / $unit.Length))).Substring(0, $n)
    $pg = $a.CreateNewPage($sec)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = ''
    try {
        Write-ObsnPage -Adapter $a -PageId $pg -Meta ([ordered]@{ 'obsn.big' = $val }) -Title "size $n" -NewPage
        $w = $sw.ElapsedMilliseconds; $sw.Restart()
        $p = Read-ObsnPage -Adapter $a -PageId $pg
        $back = [string]$p.meta['obsn.big']
        $r = $sw.ElapsedMilliseconds; $sw.Restart()
        [xml]$hx = $a.GetHierarchy($sec, 4)
        $hn = @($hx.SelectNodes("//*[local-name()='Page']") | Where-Object { $_.GetAttribute('ID') -eq $pg })[0]
        $hv = ''
        foreach ($c in @($hn.ChildNodes)) { if ($c.LocalName -eq 'Meta' -and $c.GetAttribute('name') -eq 'obsn.big') { $hv = $c.GetAttribute('content') } }
        $h = $sw.ElapsedMilliseconds
        $status = if ($back -ceq $val -and $hv -ceq $val) { 'kept' } elseif ($back -ceq $val) { "page ok, hierarchy len $($hv.Length)" } else { "changed (len $($back.Length))" }
        $null = $out.Add(('{0,9} chars  {1,-26} write {2,6} ms  read page {3,6} ms  read hierarchy {4,6} ms' -f $n, $status, $w, $r, $h))
    } catch {
        $hr = [regex]::Match("$($_.Exception)", '0x[0-9A-Fa-f]{8}').Value
        $null = $out.Add(('{0,9} chars  refused by UpdatePageContent ({1})' -f $n, $(if ($hr) { $hr } else { 'no HRESULT' })))
        break
    }
}
$out
$out.Clear()

"P1b part 2: Index section with N entries (write, then load from Meta)"
foreach ($n in $Entries) {
    $m = New-IndexModel
    $topics = [Math]::Max(1, [int][Math]::Ceiling($n / $TopicSize))
    for ($i = 1; $i -le $n; $i++) {
        $t = 'Area ' + ([int][Math]::Floor(($i - 1) / ($TopicSize * 5)) + 1) + '/Topic ' + ([int][Math]::Floor(($i - 1) / $TopicSize) + 1)
        $guid = [guid]::NewGuid().ToString().ToUpperInvariant()
        $null = Add-IndexPage -Model $m -Page @{
            id = (New-ObsnId $i); title = "Synthetic page $i"; oneNoteId = "{$guid}{1}{E$i}"; bucket = 'Notes'; type = 'note'; topics = @($t)
            summary = 'A made-up one-line summary of about eighty characters for sizing the index Meta.'
            link = "onenote:https://example.invalid/Documents/ObsidiNote/Notes.one#Synthetic%20page%20$i&section-id={$guid}&page-id={$guid}&end"
            links = @(@{ target = (New-ObsnId ([Math]::Max(1, $i - 1))); strength = 2; why = 'neighbour' })
        }
    }
    $isec = $a.OpenHierarchy("P1b index $n.one", $root, 3)
    $specs = @(Get-IndexPageSpecs -Model $m)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($s in $specs) {
        $pg = $a.CreateNewPage($isec)
        $meta = [ordered]@{ 'obsn.indexKey' = $s.key }
        foreach ($kv in $s.meta.GetEnumerator()) { $meta[$kv.Key] = $kv.Value }
        Write-ObsnPage -Adapter $a -PageId $pg -Meta $meta -Title $s.title -Outlines @(@{ role = 'index'; lines = $s.lines }) -NewPage
    }
    $write = $sw.ElapsedMilliseconds
    $maxMeta = 0
    foreach ($s in $specs) { foreach ($v in $s.meta.Values) { if (([string]$v).Length -gt $maxMeta) { $maxMeta = ([string]$v).Length } } }
    $sw.Restart()
    $xml = $a.GetHierarchy($isec, 4)
    $call = $sw.ElapsedMilliseconds; $sw.Restart()
    $back = ConvertFrom-IndexSectionXml -Xml $xml
    $parse = $sw.ElapsedMilliseconds
    $ok = ($back.pages.Count -eq $n -and $back.topics.Count -eq $m.topics.Count)
    $null = $out.Add(('{0,5} entries  {1,4} index pages  {2,4} topics  write {3,7} ms  load: hierarchy {4,5} ms + parse {5,5} ms ({6,7:N0} chars XML, largest Meta {7,6})  round trip {8}' -f $n, $specs.Count, $m.topics.Count, $write, $call, $parse, $xml.Length, $maxMeta, $(if ($ok) { 'ok' } else { "MISMATCH pages $($back.pages.Count)" })))
}
$out
