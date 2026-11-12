# P1 search check: does FindPages see the probe pages yet? Read-only. PS 5.1.
param([string[]]$Terms = @('OBSN-PROBE-7Q4K', 'identity', 'Zero-trust'))
$on = New-Object -ComObject OneNote.Application
$ids = (Get-Content (Join-Path $PSScriptRoot 'p1-ids.txt')) -split ' '
$nbId = ($ids | Where-Object { $_ -like 'nb=*' }) -replace '^nb=', ''
foreach ($t in $Terms) {
  $f = ''; $on.FindPages($nbId, $t, [ref]$f, $true, $false)
  [xml]$fx = $f; $m = New-Object System.Xml.XmlNamespaceManager($fx.NameTable); $m.AddNamespace('one', $fx.DocumentElement.NamespaceURI)
  "{0,-18} hits={1} {2}" -f $t, $fx.SelectNodes('//one:Page', $m).Count, (($fx.SelectNodes('//one:Page', $m) | ForEach-Object { $_.name }) -join ' | ')
}
