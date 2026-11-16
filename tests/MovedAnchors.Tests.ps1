# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# A moved page and links to it in other pages' text (AGENTS.md, Archive and delete: archive keeps the
# page's links). OneNote gives a moved page a new link, and on a business tenant a new page-id too, so
# a link to it in another page's text stopped opening it (target machine, 2026-11-16: kit V6 "Archive
# (link in another page)" and probe P1c). The store's MovePage (Archive, Restore, Edit's move, the
# upgrade's link-bucket step) now points such links at the new link, in ObsidiNote's own body outline
# only (obsn.role = body): never "Your notes", never an outline without a role. Pure
# (lib/PageMeta.psm1 Convert-ObsnBodyLinks -NewLink) and the real store against the in-memory OneNote.
# Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

$script:Ns = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
$script:Old = 'onenote:https://example.invalid/docs/Notes.one#Target&section-id={11111111-1111-1111-1111-111111111111}&page-id={AAAAAAAA-0000-4000-8000-00000000000A}&end'
$script:New = 'onenote:https://example.invalid/docs/Archive/Notes.one#Target&section-id={22222222-2222-2222-2222-222222222222}&page-id={CCCCCCCC-0000-4000-8000-00000000000C}&end'
$script:Other = 'onenote:https://example.invalid/docs/Notes.one#Other&section-id={11111111-1111-1111-1111-111111111111}&page-id={BBBBBBBB-0000-4000-8000-00000000000B}&end'

function New-MovePageXml([string]$BodyHtml, [string]$NotesHtml) {
    $o = { param($id, $role, $html)
        "<one:Outline objectID=""$id""><one:Meta name=""obsn.role"" content=""$role"" /><one:OEChildren><one:OE><one:T lang=""en-GB""><![CDATA[$html]]></one:T></one:OE></one:OEChildren></one:Outline>" }
    "<?xml version=""1.0""?><one:Page xmlns:one=""$script:Ns"" ID=""{PAGE}{1}{B0}""><one:Title><one:OE><one:T><![CDATA[Linker]]></one:T></one:OE></one:Title>" + (& $o '{O1}' 'body' $BodyHtml) + (& $o '{O2}' 'notes' $NotesHtml) + '</one:Page>'
}
function ConvertTo-HrefHtml([string]$Link) { $Link.Replace('&', '&amp;') }

Describe 'Convert-ObsnBodyLinks -NewLink (pure)' {
    $a = "<a style=""color:#1f4e79"" href=""$(ConvertTo-HrefHtml $script:Old)"">the <b>target</b></a>"
    $b = "<a href=""$(ConvertTo-HrefHtml $script:Other)"">another page</a>"
    $r = Convert-ObsnBodyLinks -Xml (New-MovePageXml "See $a and $b, and $a again." "My note about $a.") -TargetLink $script:Old -NewLink $script:New
    It 'points every link to the moved page at its new link and keeps the link text and attributes' {
        $r.count | Should Be 2
        [xml]$d = $r.xml
        $t = @($d.DocumentElement.GetElementsByTagName('one:T'))[0].InnerText
        $want = "<a style=""color:#1f4e79"" href=""$(ConvertTo-HrefHtml $script:New)"">the <b>target</b></a>"
        $t | Should Be "See $want and $b, and $want again."
    }
    It 'sends only the body outline: "Your notes" is never read for it' {
        $r.xml | Should Not Match 'My note about'
    }
    It 'finds a link by its page id however OneNote wrote the rest, and leaves a link already moved alone' {
        $loose = 'onenote:Renamed.one#X&amp;section-id={99999999-9999-9999-9999-999999999999}&amp;page-id={aaaaaaaa-0000-4000-8000-00000000000a}&amp;end'
        (Convert-ObsnBodyLinks -Xml (New-MovePageXml "See <a href=""$loose"">it</a>." '') -TargetLink $script:Old -NewLink $script:New).count | Should Be 1
        $done = "<a href=""$(ConvertTo-HrefHtml $script:New)"">it</a>"
        (Convert-ObsnBodyLinks -Xml (New-MovePageXml "See $done." '') -TargetLink $script:Old -NewLink $script:New).count | Should Be 0
    }
    It 'needs either the replacement text or the new link' {
        { Convert-ObsnBodyLinks -Xml (New-MovePageXml 'x' '') -TargetLink $script:Old } | Should Throw
    }
}

function Add-LinkingPage($W, [string]$TargetId) {
    <# A page as Add writes it: a link to $TargetId in its Meta, its own body and "Your notes". #>
    $link = [string]$W.open.model.pages[$TargetId].link
    $id = [string](& $W.store.NewId)
    $line = @{ parts = @(@{ text = 'We follow '; href = '' }, @{ text = 'zero trust'; href = $link }, @{ text = ' here.'; href = '' }) }
    $page = @{ id = $id; type = 'note'; bucket = 'Notes'; title = 'Linker'; summary = 'Links to it.'; topics = @(); aliases = @(); links = @(@{ target = $TargetId; strength = 3; why = 'core' }); status = ''
        outlines = @(@{ role = 'body'; lines = @($line) }, @{ role = 'notes'; lines = @(@{ parts = @(@{ text = 'my own '; href = '' }, @{ text = 'link'; href = $link }) }) }) }
    $cp = & $W.store.CreatePage -Page $page
    $page.pageId = [string]$cp.pageId; $page.link = [string]$cp.link; $page.section = [string]$cp.section
    $null = & $W.store.IndexAddPage -Page $page
    $page
}
function Get-BodyHref($W, $Page) { [regex]::Match((Get-FakeOutlineXml $W.f $Page.pageId 'body'), 'href="([^"]*)"').Groups[1].Value.Replace('&amp;', '&') }

Describe 'Archive and Restore point the links in other pages'' text at the moved page (real store, a tenant that changes the page id)' {
    $w = New-SyntheticVault
    $w.f | Add-Member NoteProperty MoveChangesLink $true
    $linker = Add-LinkingPage $w 'p1'
    $before = [string]$w.open.model.pages['p1'].link
    $notesBefore = Get-FakeOutlineXml $w.f $linker.pageId 'notes'
    $r = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
    It 'archives the page, which gets a new link' {
        $r.status | Should Be 'done'
        $w.open.model.pages['p1'].link | Should Not Be $before
    }
    It 'the link in the linking page''s text opens the archived page again, with its text kept' {
        Get-BodyHref $w $linker | Should Be ([string]$w.open.model.pages['p1'].link)
        (Get-FakeOutlineXml $w.f $linker.pageId 'body') | Should Match '>zero trust</a>'
        $r.relinked | Should Be 1
        @($r.warnings).Count | Should Be 0
    }
    It 'never touches "Your notes"' {
        (Get-FakeOutlineXml $w.f $linker.pageId 'notes') | Should Be $notesBefore
    }
    It 'Restore points it at the page''s place again' {
        $x = Invoke-PageRetire -Store $w.store -Action restore -Ids @('p1')
        $x.status | Should Be 'done'
        Get-BodyHref $w $linker | Should Be ([string]$w.open.model.pages['p1'].link)
    }
    It 'Edit''s move does the same' {
        $x = Edit-Page -Store $w.store -Id 'p1' -Changes @{ type = 'decision' }
        $x.moved | Should Be 'Decisions'
        Get-BodyHref $w $linker | Should Be ([string]$w.open.model.pages['p1'].link)
    }
    It 'turns a failed rewrite into a warning; the move stands' {
        $w2 = New-SyntheticVault
        $w2.f | Add-Member NoteProperty MoveChangesLink $true
        $l2 = Add-LinkingPage $w2 'p1'
        # The linking page cannot be read (as a page OneNote no longer has).
        $w2.open.model.pages[$l2.id].oneNoteId = '{GONE}{1}{B0}'
        $x = Invoke-PageRetire -Store $w2.store -Action archive -Ids @('p1')
        $x.status | Should Be 'done'
        (@($x.warnings) -join ' ') | Should Match 'still shows the old link'
        $w2.open.model.pages['p1'].status | Should Be 'archived'
    }
}

Describe 'A move where OneNote keeps the page link changes nothing in other pages (real store)' {
    $w = New-SyntheticVault
    $linker = Add-LinkingPage $w 'p1'
    $bodyBefore = Get-FakeOutlineXml $w.f $linker.pageId 'body'
    $r = Invoke-PageRetire -Store $w.store -Action archive -Ids @('p1')
    It 'writes nothing to the linking page' {
        $r.status | Should Be 'done'
        $r.relinked | Should Be 0
        (Get-FakeOutlineXml $w.f $linker.pageId 'body') | Should Be $bodyBefore
    }
}
