# P1 step 0: read-only. Lists open notebooks (kind, host, counts). PS 5.1.
$on = New-Object -ComObject OneNote.Application
$xml = ''
$on.GetHierarchy('', 4, [ref]$xml)   # 4 = hsPages
[xml]$x = $xml
$ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
$ns.AddNamespace('one', $x.DocumentElement.NamespaceURI)
"Schema: $($x.DocumentElement.NamespaceURI)"
$nbs = $x.SelectNodes('//one:Notebook', $ns)
"Notebooks: $($nbs.Count)"
foreach ($n in $nbs) {
  $kind = if ($n.path -match '^https://') { 'cloud' } else { 'local' }
  $hostPart = if ($kind -eq 'cloud') { ($n.path -replace '^(https://[^/]+/[^/]+/).*','$1') } else { 'local path' }
  "{0} | {1} | name={2} | sections={3} pages={4} | unfiled={5}" -f $kind, $hostPart, $n.name,
    $n.SelectNodes('.//one:Section', $ns).Count, $n.SelectNodes('.//one:Page', $ns).Count, $n.isUnread
}
$def = ''
$on.GetSpecialLocation(2, [ref]$def)  # 2 = slDefaultNotebookFolder
"Default notebook folder: $def"
