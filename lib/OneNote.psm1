# OneNote COM adapter: the few COM calls ObsidiNote uses, behind one small object, so the
# structure, page and index modules can be tested with an in-memory stand-in
# (tests/FakeOneNote.ps1). Windows PowerShell 5.1 only (in pwsh 7 GetHierarchy throws).
# Page XML uses the 2013 schema. Keep this file ASCII. Writes nothing to disk.
Set-StrictMode -Version 2.0

$script:OneNs = 'http://schemas.microsoft.com/office/onenote/2013/onenote'

function Get-OneNoteSchemaNs { $script:OneNs }

function New-OneNoteNsManager {
    <# Namespace manager with prefix 'one'. Returned with the unary comma (PS 5.1 unrolls it otherwise). #>
    param([Parameter(Mandatory)][xml]$Doc)
    $m = New-Object System.Xml.XmlNamespaceManager($Doc.NameTable)
    $m.AddNamespace('one', $script:OneNs)
    return , $m
}

function ConvertTo-XmlAttr {
    <# Text for an XML attribute value. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    [Security.SecurityElement]::Escape($Text)
}

function ConvertTo-OneText {
    <# Plain text for a one:T element: HTML-encoded, then wrapped in CDATA (OneNote reads T as an
       HTML fragment). Encoding also makes a literal "]]>" impossible inside the CDATA. #>
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $h = $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    "<![CDATA[$h]]>"
}

function ConvertTo-OneLink {
    <# An HTML anchor for a one:T fragment (not wrapped): href attribute-escaped, label HTML-encoded. #>
    param([string]$Href, [string]$Label)
    $l = "$Label".Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    '<a href="' + ("$Href".Replace('&', '&amp;').Replace('"', '&quot;')) + '">' + $l + '</a>'
}

function New-OneNoteComAdapter {
    <# The real adapter: a thin object over OneNote.Application. Methods return strings (XML or ids).
       Scope numbers: 0 self, 1 children, 2 notebooks, 3 sections, 4 pages.
       OpenHierarchy create types: 1 notebook, 2 section group (folder), 3 section. #>
    [CmdletBinding()]
    param()
    $com = New-Object -ComObject OneNote.Application
    $a = [pscustomobject]@{ Kind = 'com'; Com = $com }
    $a | Add-Member ScriptMethod GetHierarchy { param([string]$StartId, [int]$Scope) $x = ''; $this.Com.GetHierarchy($StartId, $Scope, [ref]$x); [string]$x }
    $a | Add-Member ScriptMethod OpenHierarchy { param([string]$Path, [string]$RelativeToId, [int]$CreateType) $id = ''; $this.Com.OpenHierarchy($Path, $RelativeToId, [ref]$id, $CreateType); [string]$id }
    $a | Add-Member ScriptMethod CreateNewPage { param([string]$SectionId) $id = ''; $this.Com.CreateNewPage($SectionId, [ref]$id, 1); [string]$id }
    $a | Add-Member ScriptMethod GetPageContent { param([string]$PageId) $x = ''; $this.Com.GetPageContent($PageId, [ref]$x, 0); [string]$x }
    $a | Add-Member ScriptMethod UpdatePageContent { param([string]$Xml) $this.Com.UpdatePageContent($Xml) }
    $a | Add-Member ScriptMethod GetHyperlinkToObject { param([string]$Id) $l = ''; $this.Com.GetHyperlinkToObject($Id, '', [ref]$l); [string]$l }
    $a | Add-Member ScriptMethod DeleteHierarchy { param([string]$Id) $this.Com.DeleteHierarchy($Id) }
    $a | Add-Member ScriptMethod DeletePageContent { param([string]$PageId, [string]$ObjectId) $this.Com.DeletePageContent($PageId, $ObjectId) }
    # Renaming a section: OneNote takes the section's own hierarchy XML (scope 0, hsSelf) with a new
    # name attribute through UpdateHierarchy. The section keeps its id; its pages keep ids and links.
    $a | Add-Member ScriptMethod RenameSection { param([string]$SectionId, [string]$NewName)
        $x = ''; $this.Com.GetHierarchy($SectionId, 0, [ref]$x)
        [xml]$d = $x
        if ($d.DocumentElement.LocalName -ne 'Section') { throw "RenameSection: $SectionId is not a section." }
        $d.DocumentElement.SetAttribute('name', $NewName)
        $this.Com.UpdateHierarchy($d.OuterXml)
    }
    # Moving a page to another section: the target section's hierarchy (scope 4, pages) with the
    # page's element from its own section added, through UpdateHierarchy (probes/p9-move.ps1, seen on
    # desktop OneNote 2026-11-13). The page keeps its content, Meta and outlines and the page-id in its
    # onenote: link, but gets a NEW hierarchy id: callers find it again by its obsn.id Meta.
    $a | Add-Member ScriptMethod MovePage { param([string]$PageId, [string]$FromSectionId, [string]$ToSectionId)
        $s = ''; $this.Com.GetHierarchy($FromSectionId, 4, [ref]$s); [xml]$src = $s
        $el = $null
        foreach ($n in @($src.SelectNodes('//*[@ID]'))) { if ($n.LocalName -eq 'Page' -and $n.GetAttribute('ID') -eq $PageId) { $el = $n; break } }
        if (-not $el) { throw "MovePage: page $PageId is not in section $FromSectionId." }
        $t = ''; $this.Com.GetHierarchy($ToSectionId, 4, [ref]$t); [xml]$dst = $t
        if ($dst.DocumentElement.LocalName -ne 'Section') { throw "MovePage: $ToSectionId is not a section." }
        $null = $dst.DocumentElement.AppendChild($dst.ImportNode($el, $true))
        $this.Com.UpdateHierarchy($dst.OuterXml)
    }
    # OneNote's own folder for new notebooks (slDefaultNotebookFolder = 2): the fallback when a
    # notebook cannot be made next to the cloud notebooks (0x80042006).
    $a | Add-Member ScriptMethod GetDefaultNotebookFolder { $p = ''; $this.Com.GetSpecialLocation(2, [ref]$p); [string]$p }
    return $a
}

function Get-HierarchyIds {
    <# Every ID attribute in a hierarchy XML string. Pure. #>
    param([string]$Xml)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not $Xml) { return , $set }
    [xml]$doc = $Xml
    foreach ($n in @($doc.SelectNodes('//*[@ID]'))) { [void]$set.Add($n.GetAttribute('ID')) }
    return , $set
}

function Test-NestedVaultNode {
    <# True for a section group that holds a `00 Index` section: the root of another vault. #>
    param($Node)
    if ($Node.LocalName -ne 'SectionGroup') { return $false }
    foreach ($c in @($Node.ChildNodes)) { if ($c.NodeType -eq 'Element' -and $c.LocalName -eq 'Section' -and $c.GetAttribute('name') -eq '00 Index') { return $true } }
    $false
}

function Get-VaultScopeIds {
    <# The ids inside a vault root (hierarchy XML of the root): the root and everything below it,
       except section groups that are other vaults' roots (and their contents). Pure. #>
    param([string]$Xml, [string]$RootId)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not $Xml) { return , $set }
    [xml]$doc = $Xml
    $start = $null
    foreach ($n in @($doc.SelectNodes('//*[@ID]'))) { if ($n.GetAttribute('ID') -eq $RootId) { $start = $n; break } }
    if (-not $start) { return , $set }
    $stack = New-Object System.Collections.Stack
    $stack.Push($start)
    while ($stack.Count) {
        $n = $stack.Pop()
        [void]$set.Add($n.GetAttribute('ID'))
        foreach ($c in @($n.ChildNodes)) {
            if ($c.NodeType -ne 'Element' -or -not $c.GetAttribute('ID')) { continue }
            if (Test-NestedVaultNode $c) { continue }
            $stack.Push($c)
        }
    }
    return , $set
}

function Get-PageXmlId {
    <# The ID of the one:Page element in update XML ('' when there is none). #>
    param([string]$Xml)
    try { [xml]$doc = $Xml } catch { return '' }
    if ($doc.DocumentElement.LocalName -ne 'Page') { return '' }
    $doc.DocumentElement.GetAttribute('ID')
}

function New-GuardedOneNote {
    <# The write guard (FEASIBILITY.md, Several ObsidiNote vaults): wraps an adapter so that every write
       (UpdatePageContent, CreateNewPage, DeleteHierarchy, DeletePageContent, RenameSection,
       OpenHierarchy that creates) must target an object inside the ACTIVE vault's root (a notebook or a section group;
       Set-OneNoteWriteRoot). Anything else throws 'Write refused'. Without an active root every write
       is refused. Reads pass through. Two writes exist outside a root, for making a new vault only:
       CreateNotebook(path) (refused when a notebook with that path or name is open) and
       CreateSectionGroupIn(notebookId, name) (refused when that group exists; the caller asks the user
       first, because it writes into a notebook ObsidiNote does not own yet). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inner)
    $g = [pscustomobject]@{ Kind = 'guarded'; Inner = $Inner; RootId = ''; Allowed = (New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)) }
    $g | Add-Member ScriptMethod GetHierarchy { param([string]$StartId, [int]$Scope) $this.Inner.GetHierarchy($StartId, $Scope) }
    $g | Add-Member ScriptMethod GetPageContent { param([string]$PageId) $this.Inner.GetPageContent($PageId) }
    $g | Add-Member ScriptMethod GetHyperlinkToObject { param([string]$Id) $this.Inner.GetHyperlinkToObject($Id) }
    $g | Add-Member ScriptMethod GetDefaultNotebookFolder { if ($this.Inner.PSObject.Methods['GetDefaultNotebookFolder']) { $this.Inner.GetDefaultNotebookFolder() } else { '' } }
    $g | Add-Member ScriptMethod SetRoot { param([string]$RootId) $this.RootId = $RootId; $this.Refresh() }
    $g | Add-Member ScriptMethod Refresh {
        $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        if ($this.RootId) {
            foreach ($i in (Get-VaultScopeIds -Xml ($this.Inner.GetHierarchy($this.RootId, 4)) -RootId $this.RootId)) { [void]$set.Add($i) }
            [void]$set.Add($this.RootId)
        }
        $this.Allowed = $set
    }
    $g | Add-Member ScriptMethod IsInside { param([string]$Id)
        if (-not $this.RootId -or -not $Id) { return $false }
        if ($this.Allowed.Contains($Id)) { return $true }
        $this.Refresh()
        $this.Allowed.Contains($Id)
    }
    $g | Add-Member ScriptMethod Assert { param([string]$Id, [string]$What)
        if (-not $this.IsInside($Id)) { throw "Write refused ($What): the target is outside the active vault." }
    }
    $g | Add-Member ScriptMethod CreateNewPage { param([string]$SectionId)
        $this.Assert($SectionId, 'CreateNewPage')
        $id = $this.Inner.CreateNewPage($SectionId); [void]$this.Allowed.Add($id); $id
    }
    $g | Add-Member ScriptMethod UpdatePageContent { param([string]$Xml)
        $this.Assert((Get-PageXmlId $Xml), 'UpdatePageContent')
        $this.Inner.UpdatePageContent($Xml)
    }
    $g | Add-Member ScriptMethod DeleteHierarchy { param([string]$Id)
        if ($Id -eq $this.RootId) { throw 'Write refused (DeleteHierarchy): the vault root itself is never deleted.' }
        $this.Assert($Id, 'DeleteHierarchy')
        $this.Inner.DeleteHierarchy($Id)
    }
    $g | Add-Member ScriptMethod DeletePageContent { param([string]$PageId, [string]$ObjectId)
        $this.Assert($PageId, 'DeletePageContent')
        $this.Inner.DeletePageContent($PageId, $ObjectId)
    }
    $g | Add-Member ScriptMethod RenameSection { param([string]$SectionId, [string]$NewName)
        $this.Assert($SectionId, 'RenameSection')
        if ($SectionId -eq $this.RootId) { throw 'Write refused (RenameSection): the vault root itself is never renamed.' }
        if (-not $NewName -or $NewName.Length -gt 50 -or $NewName -match '[\\/:*?"<>|#%]') { throw 'Write refused (RenameSection): not a valid section name.' }
        $this.Inner.RenameSection($SectionId, $NewName)
    }
    $g | Add-Member ScriptMethod MovePage { param([string]$PageId, [string]$FromSectionId, [string]$ToSectionId)
        # The page, where it is, and where it goes must all be inside the active vault.
        foreach ($x in $PageId, $FromSectionId, $ToSectionId) { $this.Assert($x, 'MovePage') }
        $this.Inner.MovePage($PageId, $FromSectionId, $ToSectionId)
        $this.Refresh()   # the moved page has a new id; it is inside the vault like its section
    }
    $g | Add-Member ScriptMethod OpenHierarchy { param([string]$Path, [string]$RelativeToId, [int]$CreateType)
        if ($CreateType -ne 0) { $this.Assert($RelativeToId, 'OpenHierarchy create') }
        elseif ($RelativeToId) { throw 'Write refused (OpenHierarchy): opening below another object is not used; read the hierarchy instead.' }
        $id = $this.Inner.OpenHierarchy($Path, $RelativeToId, $CreateType)
        if ($CreateType -ne 0) { [void]$this.Allowed.Add($id) }
        $id
    }
    $g | Add-Member ScriptMethod CreateNotebook { param([string]$Path)
        $name = ($Path.TrimEnd('/', '\') -split '[/\\]')[-1]
        [xml]$all = $this.Inner.GetHierarchy('', 2)
        foreach ($n in @($all.DocumentElement.ChildNodes)) {
            if ($n.NodeType -ne 'Element') { continue }
            if ($n.GetAttribute('path').TrimEnd('/', '\') -eq $Path.TrimEnd('/', '\') -or $n.GetAttribute('name') -eq $name) { throw "Write refused (CreateNotebook): a notebook '$name' is already open." }
        }
        $this.Inner.OpenHierarchy($Path, '', 1)
    }
    $g | Add-Member ScriptMethod CreateSectionGroupIn { param([string]$NotebookId, [string]$Name)
        [xml]$nb = $this.Inner.GetHierarchy($NotebookId, 1)
        foreach ($n in @($nb.DocumentElement.ChildNodes)) {
            if ($n.NodeType -eq 'Element' -and $n.LocalName -eq 'SectionGroup' -and $n.GetAttribute('name') -eq $Name) { throw "Write refused (CreateSectionGroupIn): section group '$Name' already exists." }
        }
        $this.Inner.OpenHierarchy($Name, $NotebookId, 2)
    }
    return $g
}

function New-XmlOneNoteAdapter {
    <# A read-only stand-in made from one GetHierarchy XML (the server's fake mode, tests): every read
       answers from that XML (a start id gives that object's subtree), page content is the page's
       Meta and title only, links are example links. Every write throws. Holds no scriptblock state
       from outside, so it can be made inside the server's runspace from the XML text. #>
    param([Parameter(Mandatory)][string]$Xml)
    $a = [pscustomobject]@{ Kind = 'xml'; Doc = ([xml]$Xml) }
    $a | Add-Member ScriptMethod Find { param([string]$Id)
        foreach ($n in @($this.Doc.SelectNodes('//*[@ID]'))) { if ($n.GetAttribute('ID') -eq $Id) { return $n } }
        $null
    }
    $a | Add-Member ScriptMethod GetHierarchy { param([string]$StartId, [int]$Scope)
        if (-not $StartId) { return $this.Doc.OuterXml }
        $n = $this.Find($StartId)
        if (-not $n) { throw "No object $StartId (0x80042014)." }
        $d = New-Object System.Xml.XmlDocument
        $null = $d.AppendChild($d.ImportNode($n, $true))
        $d.OuterXml
    }
    $a | Add-Member ScriptMethod GetPageContent { param([string]$PageId)
        $n = $this.Find($PageId)
        if (-not $n) { throw "No page $PageId (0x80042014)." }
        $meta = (@($n.ChildNodes | Where-Object { $_.LocalName -eq 'Meta' } | ForEach-Object { '<one:Meta name="' + (ConvertTo-XmlAttr $_.GetAttribute('name')) + '" content="' + (ConvertTo-XmlAttr $_.GetAttribute('content')) + '"/>' }) -join '')
        '<?xml version="1.0"?><one:Page xmlns:one="' + $script:OneNs + '" ID="' + (ConvertTo-XmlAttr $PageId) + '">' + $meta + '<one:Title><one:OE><one:T>' + (ConvertTo-OneText $n.GetAttribute('name')) + '</one:T></one:OE></one:Title></one:Page>'
    }
    $a | Add-Member ScriptMethod GetHyperlinkToObject { param([string]$Id) $g = ([regex]::Match($Id, '^\{([0-9A-Fa-f-]{36})\}')).Groups[1].Value; "onenote:https://example.invalid/notebook.one#page&page-id={$g}&end" }
    foreach ($w in 'OpenHierarchy', 'CreateNewPage', 'UpdatePageContent', 'DeleteHierarchy', 'DeletePageContent', 'RenameSection', 'MovePage') {
        $a | Add-Member ScriptMethod $w ([scriptblock]::Create("throw 'Read only: this stand-in cannot write ($w).'"))
    }
    $a
}

function Set-OneNoteWriteRoot {
    <# Makes $RootId (notebook or section group of the active vault) the only place writes may go. #>
    param([Parameter(Mandatory)]$Adapter, [AllowEmptyString()][string]$RootId)
    if ($Adapter.PSObject.Properties['Kind'] -and $Adapter.Kind -ne 'guarded') { throw 'The adapter has no write guard.' }
    $Adapter.SetRoot($RootId)
}

function Get-OneNoteAdapter {
    <# The adapter the app uses: real COM behind the write guard. #>
    New-GuardedOneNote -Inner (New-OneNoteComAdapter)
}

Export-ModuleMember -Function Get-OneNoteSchemaNs, New-OneNoteNsManager, ConvertTo-XmlAttr, ConvertTo-OneText, ConvertTo-OneLink, New-OneNoteComAdapter, Get-HierarchyIds, Test-NestedVaultNode, Get-VaultScopeIds, Get-PageXmlId, New-GuardedOneNote, New-XmlOneNoteAdapter, Set-OneNoteWriteRoot, Get-OneNoteAdapter
