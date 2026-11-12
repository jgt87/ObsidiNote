# Closes the ObsidiNote-Probe notebook in OneNote (does not delete it from OneDrive). PS 5.1.
$on = New-Object -ComObject OneNote.Application
$h = ''; $on.GetHierarchy('', 1, [ref]$h); [xml]$x = $h
$m = New-Object System.Xml.XmlNamespaceManager($x.NameTable); $m.AddNamespace('one', $x.DocumentElement.NamespaceURI)
foreach ($n in $x.SelectNodes("//one:Notebook[@name='ObsidiNote-Probe']", $m)) { $on.CloseNotebook($n.ID); "closed: $($n.path)" }
"To remove it completely, delete the ObsidiNote-Probe folder in OneDrive (Documents)."
