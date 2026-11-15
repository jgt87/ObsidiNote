# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Undo and links in other pages' text (AGENTS.md, Archive and delete): a link to the undone page in
# another page's ObsidiNote-owned body outline (obsn.role = body) becomes the plain text
# "(deleted: <title>)". Never "Your notes" (role notes), never an outline without a role.
# Pure (lib/PageMeta.psm1 Convert-ObsnBodyLinks), the in-memory test store, and the real store
# against the in-memory OneNote. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'FakeVault.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:Ns = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$script:Target = 'onenote:https://example.invalid/docs/Notes.one#Target&section-id={11111111-1111-1111-1111-111111111111}&page-id={AAAAAAAA-0000-4000-8000-00000000000A}&end'
$script:Other = 'onenote:https://example.invalid/docs/Notes.one#Other&section-id={11111111-1111-1111-1111-111111111111}&page-id={BBBBBBBB-0000-4000-8000-00000000000B}&end'

function New-TestPageXml([string]$BodyHtml, [string]$NotesHtml, [string]$FreeHtml) {
    $o = { param($id, $role, $html)
        $meta = if ($role) { '<one:Meta name="obsn.role" content="' + $role + '" />' } else { '' }
        "<one:Outline objectID=""$id"">$meta<one:OEChildren><one:OE objectID=""$id-1""><one:T lang=""en-GB""><![CDATA[$html]]></one:T></one:OE><one:OE><one:T><![CDATA[second line]]></one:T></one:OE></one:OEChildren></one:Outline>" }
    "<?xml version=""1.0""?><one:Page xmlns:one=""$script:Ns"" ID=""{PAGE}{1}{B0}""><one:Meta name=""obsn.id"" content=""p9"" /><one:Title><one:OE><one:T><![CDATA[Linker]]></one:T></one:OE></one:Title>" +
        (& $o '{O1}' 'body' $BodyHtml) + (& $o '{O2}' 'notes' $NotesHtml) + (& $o '{O3}' '' $FreeHtml) + '</one:Page>'
}

function ConvertTo-HrefHtml([string]$Link) { $Link.Replace('&', '&amp;') }

Describe 'Convert-ObsnBodyLinks (pure)' {
    $a = "<a href=""$(ConvertTo-HrefHtml $script:Target)"">the target</a>"
    $b = "<a href=""$(ConvertTo-HrefHtml $script:Other)"">another page</a>"
    $xml = New-TestPageXml "See $a and $b, and $a again." "My note about $a." "Typed by hand: $a."
    $r = Convert-ObsnBodyLinks -Xml $xml -TargetLink $script:Target -Text '(deleted: Target <page> & co)'

    It 'replaces every link to the page in the body outline with the plain text' {
        $r.count | Should Be 2
        [xml]$d = $r.xml
        $t = @($d.DocumentElement.GetElementsByTagName('one:T'))[0]
        $t.InnerText | Should Be "See (deleted: Target &lt;page&gt; &amp; co) and $b, and (deleted: Target &lt;page&gt; &amp; co) again."
        $t.GetAttribute('lang') | Should Be 'en-GB'
    }
    It 'sends only the body outline, whole and by its object id' {
        [xml]$d = $r.xml
        $d.DocumentElement.GetAttribute('ID') | Should Be '{PAGE}{1}{B0}'
        $outs = @($d.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
        $outs.Count | Should Be 1
        $outs[0].LocalName | Should Be 'Outline'
        $outs[0].GetAttribute('objectID') | Should Be '{O1}'
        $r.xml | Should Match 'second line'
        $r.xml | Should Not Match 'My note about'
        $r.xml | Should Not Match 'Typed by hand'
        $r.xml | Should Not Match '<one:Title'
    }
    It 'never reads "Your notes" or an outline without a role for it' {
        $only = New-TestPageXml 'No link here.' "My note about $a." "Typed by hand: $a."
        $x = Convert-ObsnBodyLinks -Xml $only -TargetLink $script:Target -Text '(deleted: T)'
        $x.count | Should Be 0
        $x.xml | Should Be ''
    }
    It 'leaves links to other pages and web links alone' {
        $x = Convert-ObsnBodyLinks -Xml (New-TestPageXml "See $b and <a href=""https://example.invalid/a?b=1&amp;c=2"">a site</a>." '' '') -TargetLink $script:Target -Text '(deleted: T)'
        $x.count | Should Be 0
    }
    It 'matches by the page id in the link, however OneNote wrote the rest of it' {
        $moved = 'onenote:Other%20notebook.one#Renamed%20title&amp;section-id={99999999-9999-9999-9999-999999999999}&amp;page-id={aaaaaaaa-0000-4000-8000-00000000000a}&amp;end'
        $x = Convert-ObsnBodyLinks -Xml (New-TestPageXml "See <a`nhref=""$moved"">the <span style='font-weight:bold'>target</span></a>." '' '') -TargetLink $script:Target -Text '(deleted: T)'
        $x.count | Should Be 1
        $x.xml | Should Match 'See \(deleted: T\)\.'
    }
}

Describe 'Undo-AddRequest asks the store to rewrite the linking pages (in-memory test store)' {
    $v = New-FakeVault
    $v.st.bodyLinkPages = @('{P3}')
    $r = Undo-AddRequest -Store $v.store -Undo @{ id = 'p1' }
    It 'reports the pages whose text changed as rewritten, next to unlinked' {
        $r.status | Should Be 'undone'
        $r.unlinked | Should Be 1
        $r.rewritten | Should Be 1
    }
    It 'passes the removed page''s link and the text "(deleted: <title>)" for each linking page' {
        $v.st.rewrites.Count | Should Be 1
        $v.st.rewrites[0].pageId | Should Be '{P3}'
        $v.st.rewrites[0].targetLink | Should Be 'onenote:#p1'
        $v.st.rewrites[0].text | Should Be '(deleted: Zero-trust networking)'
    }
    It 'turns a failed rewrite into a warning, not a failed Undo' {
        $v2 = New-FakeVault
        $v2.st.fail['RewriteBodyLinks'] = 'the page is locked'
        $r2 = Undo-AddRequest -Store $v2.store -Undo @{ id = 'p1' }
        $r2.status | Should Be 'undone'
        $r2.rewritten | Should Be 0
        (@($r2.warnings) -join ' ') | Should Match 'still shows a link to the removed page'
    }
    It 'has RewriteBodyLinks in the store contract' {
        (Get-IngestStoreContract) -contains 'RewriteBodyLinks' | Should Be $true
    }
}

Describe 'Undo of a page that another page links to in its text (real store, in-memory OneNote)' {
    $w = New-SyntheticVault
    $p1 = Find-FakePage $w.f 'Zero-trust networking'
    $link = [string]$w.open.model.pages['p1'].link
    # A page as Add writes it: a link to p1 in its Meta, in its own body, and in "Your notes".
    $id = [string](& $w.store.NewId)
    $line = @{ parts = @(@{ text = 'We follow '; href = '' }, @{ text = 'zero trust'; href = $link }, @{ text = ' here.'; href = '' }) }
    $page = @{ id = $id; type = 'note'; bucket = 'Notes'; title = 'Linker'; summary = 'Links to p1.'; topics = @(); aliases = @(); links = @(@{ target = 'p1'; strength = 3; why = 'core' }); status = ''
        outlines = @(@{ role = 'body'; lines = @($line) }, @{ role = 'notes'; lines = @(@{ parts = @(@{ text = 'my own '; href = '' }, @{ text = 'link'; href = $link }) }) }) }
    $cp = & $w.store.CreatePage -Page $page
    $page.pageId = [string]$cp.pageId; $page.link = [string]$cp.link; $page.section = [string]$cp.section
    $null = & $w.store.IndexAddPage -Page $page
    $node = $w.f.Nodes[$page.pageId]
    # Something the person typed on the page themselves (no role), with the same link.
    $free = "<one:Outline objectID=""{FREE}""><one:OEChildren><one:OE><one:T><![CDATA[typed: <a href=""$($link.Replace('&', '&amp;'))"">p1</a>]]></one:T></one:OE></one:OEChildren></one:Outline>"
    $null = $node.outlines.Add(@{ objectId = '{FREE}'; role = ''; xml = $free })
    $notesBefore = Get-FakeOutlineXml $w.f $page.pageId 'notes'
    $propsBefore = Get-FakeOutlineXml $w.f $page.pageId 'props'

    It 'starts with the link in the body' {
        (Get-FakeOutlineXml $w.f $page.pageId 'body') | Should Match '<a href="onenote:[^"]*">zero trust</a>'
    }
    $r = Undo-AddRequest -Store $w.store -Undo @{ id = 'p1' }

    It 'undoes the page and reports the rewritten page' {
        $r.status | Should Be 'undone'
        $r.rewritten | Should Be 1          # p3 links to p1 in its Meta only: its text has no link
        $r.unlinked | Should Be 2
        @($r.warnings).Count | Should Be 0
        $w.f.Nodes.ContainsKey($p1.id) | Should Be $false
    }
    It 'turns the link in the body into "(deleted: <title>)"' {
        $body = Get-FakeOutlineXml $w.f $page.pageId 'body'
        $body | Should Match 'We follow \(deleted: Zero-trust networking\) here\.'
        $body | Should Not Match '<a '
    }
    It 'takes the link out of the linking page''s Meta and index record' {
        $node.meta['obsn.links'] | Should Be '[]'
        @($w.open.model.pages[$id].links).Count | Should Be 0
    }
    It 'never touches "Your notes", the person''s own outline or the properties' {
        (Get-FakeOutlineXml $w.f $page.pageId 'notes') | Should Be $notesBefore
        (Get-FakeOutlineXml $w.f $page.pageId 'notes') | Should Match '<a href="onenote:'
        @($node.outlines | Where-Object { $_.objectId -eq '{FREE}' })[0].xml | Should Be $free
        (Get-FakeOutlineXml $w.f $page.pageId 'props') | Should Be $propsBefore
        $node.outlines.Count | Should Be 4
    }
    It 'keeps every write inside the vault' {
        $scope = Get-VaultScopeIds -Xml ($w.f.GetHierarchy($w.v.rootId, 4)) -RootId $w.v.rootId
        @($w.f.Writes | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $_ -match '^\{' -and $_ -ne $p1.id -and -not $scope.Contains($_) }).Count | Should Be 0
    }
    It 'refuses the rewrite without the writer lease' {
        $w.box.lease = @{ mode = 'readonly'; expires = [datetime]::UtcNow.AddMinutes(5) }
        { & $w.store.RewriteBodyLinks -PageId $page.pageId -TargetLink $link -Text 'x' } | Should Throw
    }
}
