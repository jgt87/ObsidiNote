# An in-memory stand-in for OneNote's COM API with the adapter's method names (lib/OneNote.psm1).
# Dot-source it in a test. Synthetic data only: fictional names, made-up ids, example.invalid links.
# Builders: AddNotebook(name), AddGroup(parentId, name), AddSection(parentId, name),
# AddPage(sectionId, title, meta hashtable, level, bodyHtml). Writes are recorded in .Writes.

function New-FakeOneNote {
    $f = [pscustomobject]@{ Kind = 'fake'; Nodes = @{}; Roots = (New-Object System.Collections.ArrayList); Seq = 0; Writes = (New-Object System.Collections.ArrayList); Calls = @{} }
    $f | Add-Member ScriptMethod NewId { param([string]$Prefix) $this.Seq++; '{' + $Prefix + '-' + $this.Seq.ToString('0000') + '}{1}{B0}' }
    $f | Add-Member ScriptMethod Count { param([string]$Name) if ($this.Calls.ContainsKey($Name)) { $this.Calls[$Name]++ } else { $this.Calls[$Name] = 1 } }
    $f | Add-Member ScriptMethod AddNode { param([string]$Kind, [string]$ParentId, [string]$Name)
        $id = $this.NewId($Kind.Substring(0, 2).ToUpperInvariant())
        $path = if ($ParentId) { $this.Nodes[$ParentId].path + $Name + $(if ($Kind -eq 'Section') { '.one' } else { '/' }) } else { "https://example.invalid/docs/$Name/" }
        $n = @{ kind = $Kind; id = $id; name = $Name; path = $path; parent = $ParentId; children = (New-Object System.Collections.ArrayList); meta = [ordered]@{}; title = $Name; outlines = (New-Object System.Collections.ArrayList); level = 1; recycle = $false; guid = [guid]::NewGuid().ToString(); modified = '2026-01-02T03:04:05.000Z' }
        $this.Nodes[$id] = $n
        if ($ParentId) { $null = $this.Nodes[$ParentId].children.Add($id) } else { $null = $this.Roots.Add($id) }
        $id
    }
    $f | Add-Member ScriptMethod AddNotebook { param([string]$Name) $this.AddNode('Notebook', '', $Name) }
    $f | Add-Member ScriptMethod AddGroup { param([string]$ParentId, [string]$Name) $this.AddNode('SectionGroup', $ParentId, $Name) }
    $f | Add-Member ScriptMethod AddSection { param([string]$ParentId, [string]$Name) $this.AddNode('Section', $ParentId, $Name) }
    $f | Add-Member ScriptMethod AddRecycleBin { param([string]$NotebookId)
        $g = $this.AddNode('SectionGroup', $NotebookId, 'OneNote_RecycleBin'); $this.Nodes[$g].recycle = $true
        $s = $this.AddNode('Section', $g, 'Deleted Pages'); $this.Nodes[$s].recycle = $true
        $s
    }
    $f | Add-Member ScriptMethod AddPage { param([string]$SectionId, [string]$Title, [hashtable]$Meta = @{}, [int]$Level = 1, [string]$BodyHtml = '')
        $id = $this.AddNode('Page', $SectionId, $Title)
        $n = $this.Nodes[$id]; $n.level = $Level; $n.recycle = $this.Nodes[$SectionId].recycle
        foreach ($k in $Meta.Keys) { $n.meta[$k] = [string]$Meta[$k] }
        if ($BodyHtml) { $null = $n.outlines.Add(@{ objectId = "{OBJ-$($this.Seq)}"; role = ''; xml = "<one:Outline objectID=""{OBJ-$($this.Seq)}""><one:OEChildren><one:OE><one:T><![CDATA[$BodyHtml]]></one:T></one:OE></one:OEChildren></one:Outline>" }) }
        $id
    }
    $f | Add-Member ScriptMethod NodeXml { param([string]$Id, [int]$Scope)
        $n = $this.Nodes[$Id]
        $a = ' name="' + [Security.SecurityElement]::Escape($n.name) + '" ID="' + $n.id + '"'
        switch ($n.kind) {
            'Notebook' { $a += ' nickname="' + [Security.SecurityElement]::Escape($n.name) + '" path="' + $n.path + '"' }
            'SectionGroup' { $a += ' path="' + $n.path + '"'; if ($n.recycle) { $a += ' isRecycleBin="true"' } }
            'Section' { $a += ' path="' + $n.path + '"'; if ($n.recycle) { $a += ' isInRecycleBin="true" isDeletedPages="true"' } }
            'Page' { $a = ' ID="' + $n.id + '" name="' + [Security.SecurityElement]::Escape($n.title) + '" lastModifiedTime="' + $n.modified + '" pageLevel="' + $n.level + '"'; if ($n.recycle) { $a += ' isInRecycleBin="true"' } }
        }
        $inner = ''
        if ($n.kind -eq 'Page') { foreach ($k in $n.meta.Keys) { $inner += '<one:Meta name="' + $k + '" content="' + [Security.SecurityElement]::Escape([string]$n.meta[$k]) + '"/>' } }
        $depth = @{ Notebook = 2; SectionGroup = 2; Section = 3; Page = 4 }
        # OneNote lists sections before section groups.
        $ordered = @($n.children | Where-Object { $this.Nodes[$_].kind -ne 'SectionGroup' }) + @($n.children | Where-Object { $this.Nodes[$_].kind -eq 'SectionGroup' })
        foreach ($c in $ordered) {
            $ck = $this.Nodes[$c].kind
            if ($depth[$ck] -le $Scope -or ($ck -ne 'Page' -and $Scope -ge 3)) { $inner += $this.NodeXml($c, $Scope) }
        }
        "<one:$($n.kind)$a>$inner</one:$($n.kind)>"
    }
    $f | Add-Member ScriptMethod GetHierarchy { param([string]$StartId, [int]$Scope)
        $this.Count('GetHierarchy')
        $ns = 'xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote"'
        if (-not $StartId) {
            $s = if ($Scope -eq 2) { 3 } else { $Scope }
            $body = (@($this.Roots | ForEach-Object { if ($Scope -eq 2) { $this.NodeXml($_, 1) } else { $this.NodeXml($_, $s) } }) -join '')
            return "<?xml version=""1.0""?><one:Notebooks $ns>$body</one:Notebooks>"
        }
        if (-not $this.Nodes.ContainsKey($StartId)) { throw "fake: no object $StartId" }
        $x = $this.NodeXml($StartId, $(if ($Scope -lt 3) { 3 } else { $Scope }))
        $x = $x.Insert($x.IndexOf(' '), " $ns")
        "<?xml version=""1.0""?>$x"
    }
    $f | Add-Member ScriptMethod OpenHierarchy { param([string]$Path, [string]$RelativeToId, [int]$CreateType)
        $null = $this.Writes.Add("OpenHierarchy $Path")
        if (-not $RelativeToId) {
            foreach ($r in $this.Roots) { if ($this.Nodes[$r].path.TrimEnd('/') -eq $Path.TrimEnd('/')) { return $r } }
            if ($CreateType -ne 1) { throw 'fake: notebook not found' }
            $id = $this.AddNotebook(($Path.TrimEnd('/') -split '/')[-1]); $this.Nodes[$id].path = $Path.TrimEnd('/') + '/'; return $id
        }
        $name = $Path -replace '\.one$', ''
        $kind = if ($CreateType -eq 2) { 'SectionGroup' } else { 'Section' }
        foreach ($c in $this.Nodes[$RelativeToId].children) { if ($this.Nodes[$c].name -eq $name -and $this.Nodes[$c].kind -eq $kind) { return $c } }
        $this.AddNode($kind, $RelativeToId, $name)
    }
    $f | Add-Member ScriptMethod CreateNewPage { param([string]$SectionId) $null = $this.Writes.Add("CreateNewPage $SectionId"); $this.AddPage($SectionId, '', @{}, 1, '') }
    $f | Add-Member ScriptMethod GetHyperlinkToObject { param([string]$Id) $this.Count('GetHyperlinkToObject'); $n = $this.Nodes[$Id]; "onenote:https://example.invalid/docs/x.one#p&section-id={00000000-0000-0000-0000-000000000000}&page-id={$($n.guid)}&end" }
    $f | Add-Member ScriptMethod GetPageContent { param([string]$PageId)
        $this.Count('GetPageContent')
        $n = $this.Nodes[$PageId]
        $m = (@($n.meta.Keys | ForEach-Object { '<one:Meta name="' + $_ + '" content="' + [Security.SecurityElement]::Escape([string]$n.meta[$_]) + '"/>' }) -join '')
        $o = (@($n.outlines | ForEach-Object { $_.xml }) -join '')
        "<?xml version=""1.0""?><one:Page xmlns:one=""http://schemas.microsoft.com/office/onenote/2013/onenote"" ID=""$PageId"">$m<one:Title><one:OE><one:T><![CDATA[$([Security.SecurityElement]::Escape($n.title))]]></one:T></one:OE></one:Title>$o</one:Page>"
    }
    $f | Add-Member ScriptMethod UpdatePageContent { param([string]$Xml)
        [xml]$d = $Xml
        $id = $d.DocumentElement.GetAttribute('ID')
        $null = $this.Writes.Add("UpdatePageContent $id")
        if (-not $this.Nodes.ContainsKey($id)) { throw 'fake: 0x80042014 page not found' }
        $n = $this.Nodes[$id]
        foreach ($c in @($d.DocumentElement.ChildNodes)) {
            if ($c.NodeType -ne 'Element') { continue }
            if ($c.LocalName -eq 'Meta') { $n.meta[$c.GetAttribute('name')] = $c.GetAttribute('content') }
            elseif ($c.LocalName -eq 'Title') { $n.title = [Net.WebUtility]::HtmlDecode($c.InnerText); $n.name = $n.title }
            elseif ($c.LocalName -eq 'Outline') {
                $oid = $c.GetAttribute('objectID')
                $hit = $null
                foreach ($o in $n.outlines) { if ($oid -and $o.objectId -eq $oid) { $hit = $o } }
                if (-not $hit) { $this.Seq++; $oid = "{OBJ-$($this.Seq)}"; $c.SetAttribute('objectID', $oid); $hit = @{ objectId = $oid }; $null = $n.outlines.Add($hit) }
                $hit.xml = $c.OuterXml
            }
        }
    }
    $f | Add-Member ScriptMethod DeleteHierarchy { param([string]$Id)
        $null = $this.Writes.Add("DeleteHierarchy $Id")
        $n = $this.Nodes[$Id]
        if ($n.parent) { $this.Nodes[$n.parent].children.Remove($Id) } else { $this.Roots.Remove($Id) }
        $this.Nodes.Remove($Id)
    }
    $f | Add-Member ScriptMethod DeletePageContent { param([string]$PageId, [string]$ObjectId)
        $null = $this.Writes.Add("DeletePageContent $PageId")
        $n = $this.Nodes[$PageId]
        foreach ($o in @($n.outlines)) { if ($o.objectId -eq $ObjectId) { $n.outlines.Remove($o) } }
    }
    $f | Add-Member ScriptMethod RenameSection { param([string]$SectionId, [string]$NewName)
        $null = $this.Writes.Add("RenameSection $SectionId")
        $n = $this.Nodes[$SectionId]
        if (-not $n -or $n.kind -ne 'Section') { throw 'fake: 0x80042014 section not found' }
        $n.path = $n.path.Substring(0, $n.path.Length - ($n.name.Length + 4)) + $NewName + '.one'
        $n.name = $NewName
    }
    # Like desktop OneNote (probes/p9-move.ps1, 2026-11-13): the page moves with its content and Meta
    # but gets a NEW hierarchy id; its guid (the page-id in links) stays.
    $f | Add-Member ScriptMethod MovePage { param([string]$PageId, [string]$FromSectionId, [string]$ToSectionId)
        $null = $this.Writes.Add("MovePage $PageId")
        $n = $this.Nodes[$PageId]
        if (-not $n -or $n.kind -ne 'Page' -or $n.parent -ne $FromSectionId) { throw 'fake: MovePage: page not in that section' }
        if ($this.Nodes[$ToSectionId].kind -ne 'Section') { throw 'fake: MovePage: target is not a section' }
        $this.Nodes[$FromSectionId].children.Remove($PageId)
        $this.Nodes.Remove($PageId)
        $new = $this.NewId('PA')
        $n.id = $new; $n.parent = $ToSectionId
        $this.Nodes[$new] = $n
        $null = $this.Nodes[$ToSectionId].children.Add($new)
    }
    $f | Add-Member ScriptMethod FindByName { param([string]$Name) foreach ($v in $this.Nodes.Values) { if ($v.name -eq $Name) { return $v.id } } }
    $f
}
