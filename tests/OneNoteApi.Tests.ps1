# OneNote's API, every method (FEASIBILITY.md section 2, validation/lib/ApiProbe.psm1): the catalogue
# covers every OneNote method the code calls, says truthfully which ones ObsidiNote uses, matches the
# table in FEASIBILITY.md, and the kit's probe calls read methods only and logs no names or ids.
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'validation\lib\ValidationCore.psm1') -Force
Import-Module (Join-Path $root 'validation\lib\ApiProbe.psm1') -Force

$cat = @(Get-OneNoteApiCatalogue)
$names = @($cat | ForEach-Object { $_.name })

# Methods called on a raw OneNote COM object ($this.Com.X(, $Com.X(, $on.X(), and its Windows
# property, in the files of a folder.
function Get-ComMembers([string]$Folder, [string]$Filter = '*.psm1') {
    $out = @{}
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $root $Folder) -Filter $Filter) {
        foreach ($l in [IO.File]::ReadAllLines($f.FullName)) {
            if ($l -match '^\s*#') { continue }
            foreach ($m in [regex]::Matches($l, '(?:\.Com|\$com|\$on)\.([A-Za-z]+)\s*\(', 'IgnoreCase')) { $out[$m.Groups[1].Value] = $true }
            if ($l -match '(?i)(?:\.Com|\$com|\$on)\.Windows\b') { $out['Windows'] = $true }
        }
    }
    @($out.Keys)
}

$app = Get-ComMembers 'lib'
$kit = Get-ComMembers 'validation\lib'
$probes = Get-ComMembers 'probes' '*.ps1'

Describe 'OneNote API catalogue' {
    It 'names each method once, with a known kind; the probe tries read methods only' {
        @($names | Select-Object -Unique).Count | Should Be $names.Count
        @($cat | Where-Object { @('read', 'write', 'file', 'window') -notcontains $_.kind }).Count | Should Be 0
        @($cat | Where-Object { $_.probe -and $_.kind -ne 'read' } | ForEach-Object { $_.name }) -join ', ' | Should Be ''
        @($cat | Where-Object { -not $_.probe -and $_.kind -eq 'read' } | ForEach-Object { $_.name }) -join ', ' | Should Be ''
    }
    It 'finds the COM calls it checks (the scan is not empty)' {
        ($app -contains 'GetHierarchy') | Should Be $true
        ($app -contains 'UpdatePageContent') | Should Be $true
        ($app -contains 'Windows') | Should Be $true
        ($kit -contains 'SyncHierarchy') | Should Be $true
        ($probes -contains 'FindPages') | Should Be $true
    }
    It 'lists every OneNote member the app, the kit or the feasibility probes call' {
        @(@($app) + @($kit) + @($probes) | Select-Object -Unique | Where-Object { $names -notcontains $_ }) -join ', ' | Should Be ''
    }
    It 'says "used" for exactly the methods the app calls; "validation kit only" and "feasibility probes only" are true' {
        foreach ($e in $cat) {
            $kitOnly = $e.used -like 'validation kit only*'
            $probeOnly = $e.used -like 'feasibility probes only*'
            $inApp = $app -contains $e.name
            "$($e.name): app $inApp, entry says used $([bool]($e.used -and -not $kitOnly -and -not $probeOnly))" | Should Be "$($e.name): app $inApp, entry says used $inApp"
            if ($kitOnly) { "$($e.name): kit calls it $($kit -contains $e.name)" | Should Be "$($e.name): kit calls it True" }
            if ($probeOnly) { "$($e.name): probes call it $($probes -contains $e.name)" | Should Be "$($e.name): probes call it True" }
        }
    }
    It 'FEASIBILITY.md has one row per method, with the same kind and probe column' {
        $doc = [IO.File]::ReadAllText((Join-Path $root 'FEASIBILITY.md'))
        $rows = @([regex]::Matches($doc, '(?m)^\| `(\w+)` \| (\w+) \|.*\| (tried|not tried) \|\s*$') | ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value) $($_.Groups[3].Value)" })
        $want = @($cat | ForEach-Object { "$($_.name) $($_.kind) $(if ($_.probe) { 'tried' } else { 'not tried' })" })
        ($rows -join '; ') | Should Be ($want -join '; ')
    }
}

# A stand-in for OneNote.Application: answers the read methods from one invented hierarchy, records
# every method called, and fails a method on request with OneNote's error 0x80042014.
function New-ComFake([string[]]$Fail = @(), [bool]$NoPages = $false, [bool]$OnePage = $false) {
    $nb = '{11111111-2222-3333-4444-555555555555}{1}{B0}'
    $sec = '{22222222-2222-3333-4444-555555555555}{1}{B0}'
    $p1 = '{33333333-2222-3333-4444-555555555555}{1}{E1}'
    $p2 = '{44444444-2222-3333-4444-555555555555}{1}{E1}'
    $pages = if ($NoPages) { '' }
    elseif ($OnePage) { "<one:Page ID=""$p1"" name=""Confidential salaries""/>" }
    else { "<one:Page ID=""$p1"" name=""Confidential salaries""/><one:Page ID=""$p2"" name=""Budget plan""/><one:Page ID=""{9}"" name=""Old"" isInRecycleBin=""true""/>" }
    $xml = "<one:Notebooks xmlns:one=""http://schemas.microsoft.com/office/onenote/2013/onenote""><one:Notebook ID=""$nb"" name=""Fabrikam Finance"" path=""https://fernbrook.sharepoint.com/sites/Finance/Notebook""><one:Section ID=""$sec"" name=""Salaries"">$pages</one:Section></one:Notebook></one:Notebooks>"
    $f = [pscustomobject]@{ Calls = (New-Object System.Collections.Generic.List[string]); Fail = $Fail; Xml = $xml; Ids = @{ nb = $nb; sec = $sec; p1 = $p1; p2 = $p2 } }
    $f | Add-Member NoteProperty Windows ([pscustomobject]@{ Count = 1; CurrentWindow = [pscustomobject]@{ CurrentNotebookId = $nb } })
    $f | Add-Member ScriptMethod Call { param([string]$Name) $this.Calls.Add($Name); if ($this.Fail -contains $Name) { throw (New-Object Runtime.InteropServices.COMException('failed', -2147213292)) } }
    $f | Add-Member ScriptMethod GetHierarchy { param($s, $scope, [ref]$x) $this.Call('GetHierarchy'); $x.Value = $this.Xml }
    $f | Add-Member ScriptMethod GetHierarchyParent { param($id, [ref]$x) $this.Call('GetHierarchyParent'); $x.Value = $this.Ids.sec }
    $f | Add-Member ScriptMethod GetPageContent { param($id, [ref]$x, $info)
        $this.Call('GetPageContent')
        $img = if ($id -eq $this.Ids.p2) { '<one:Image><one:CallbackID callbackID="{CB-1}"/></one:Image>' } else { '' }
        $x.Value = "<one:Page xmlns:one=""http://schemas.microsoft.com/office/onenote/2013/onenote"" name=""Confidential salaries""><one:T>Secret text</one:T>$img</one:Page>"
    }
    $f | Add-Member ScriptMethod GetBinaryPageContent { param($id, $cb, [ref]$x) $this.Call('GetBinaryPageContent'); $x.Value = 'QUJD' * 600 }
    $f | Add-Member ScriptMethod GetHyperlinkToObject { param($id, $obj, [ref]$x) $this.Call('GetHyperlinkToObject'); $x.Value = "onenote:https://fernbrook.sharepoint.com/sites/Finance/Notebook/Salaries.one#Confidential&page-id=$id" }
    $f | Add-Member ScriptMethod GetWebHyperlinkToObject { param($id, $obj, [ref]$x) $this.Call('GetWebHyperlinkToObject'); $x.Value = 'https://fernbrook.sharepoint.com/sites/Finance/_layouts/OneNote.aspx?id=Confidential' }
    $f | Add-Member ScriptMethod FindPages { param($s, $q, [ref]$x, $u, $d) $this.Call('FindPages'); $x.Value = $this.Xml.Replace('name="Budget plan"', 'name="Budget plan" isIndexed="false"') }
    $f | Add-Member ScriptMethod FindMeta { param($s, $n, [ref]$x, $u) $this.Call('FindMeta'); $x.Value = $this.Xml.Replace('name="Budget plan"/>', 'name="Budget plan"><one:Meta name="obsn.id" content="p7"/></one:Page>') }
    $f | Add-Member ScriptMethod GetSpecialLocation { param($l, [ref]$x) $this.Call('GetSpecialLocation'); $x.Value = 'D:\Secret Folder\OneNote Notebooks' }
    # Every other method exists too and is recorded, so a call to a write method shows up in Calls
    # (a missing method would only throw, and the probe would log that as a failed read).
    foreach ($e in @(Get-OneNoteApiCatalogue | Where-Object { $_.kind -ne 'read' })) {
        $f | Add-Member ScriptMethod $e.name ([scriptblock]::Create("`$this.Calls.Add('$($e.name)')"))
    }
    $f
}

function New-ApiCtx { New-ValidationContext -AppRoot $root -Stages @('V2') -Quiet -Prompt { param($q) '' } }

Describe 'OneNote API probe (stage V2, read only)' {
    It 'tries every read method, calls nothing else, and reports each one' {
        $f = New-ComFake
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $f -HierarchyXml $f.Xml
        $read = @($cat | Where-Object { $_.kind -eq 'read' -and $_.name -ne 'Windows' } | ForEach-Object { $_.name })
        (@($f.Calls | Select-Object -Unique | Where-Object { $read -notcontains $_ }) -join ', ') | Should Be ''
        (@($read | Where-Object { @($f.Calls) -notcontains $_ }) -join ', ') | Should Be ''
        $lines = @($c.Results | ForEach-Object { "$($_.status) $($_.name)" })
        foreach ($m in 'GetHierarchy', 'GetHierarchyParent', 'GetPageContent', 'GetBinaryPageContent', 'GetHyperlinkToObject', 'GetWebHyperlinkToObject', 'FindPages', 'FindMeta', 'GetSpecialLocation', 'Windows') {
            ($lines -contains "OK API $m") | Should Be $true
        }
        $last = $c.Results[$c.Results.Count - 1]
        $last.name | Should Be 'API not tried'
        $last.detail | Should Match 'UpdatePageContent'
    }
    It 'reads what it found, never the names, ids, paths or addresses' {
        $f = New-ComFake
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $f -HierarchyXml $f.Xml
        $text = @($c.Results | ForEach-Object { "$($_.name) $($_.detail)" }) -join "`n"
        $text | Should Not Match 'Confidential|salaries|Salaries|Budget|Fabrikam|Finance|fernbrook|Secret|someone|CB-1|11111111|22222222|33333333|44444444|onenote:https'
        $text | Should Match "a page's parent is its section: yes"
        # The fake answers both searches, indexed only or not, with the whole hierarchy, recycle bin
        # included (as OneNote's search does for pages not yet indexed): three pages each time.
        $text | Should Match '3 page\(s\) for a common word; with pages not yet indexed: 3 returned'
        # Only the pages whose answer holds the Meta count as carrying it (the fake's page 2 does).
        $text | Should Match '1 of 3 page\(s\) returned carry the Meta obsn.id; with pages not yet indexed: 1 of 3'
        @($f.Calls | Where-Object { $_ -eq 'FindPages' }).Count | Should Be 2
        @($f.Calls | Where-Object { $_ -eq 'FindMeta' }).Count | Should Be 2
        $text | Should Match 'one object read, 2.3 KB as base64'
        $text | Should Match "a page link in OneNote's own scheme: yes"
        $text | Should Match 'the current one shows a notebook: yes'
    }
    It 'names OneNote''s error code when a method fails; a missing web address is expected, not a fault' {
        $f = New-ComFake -Fail @('FindMeta', 'GetWebHyperlinkToObject')
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $f -HierarchyXml $f.Xml
        $meta = @($c.Results | Where-Object { $_.name -eq 'API FindMeta' })[0]
        $meta.status | Should Be 'FAIL'
        $meta.detail | Should Match 'error 0x80042014'
        @($c.Results | Where-Object { $_.name -eq 'API GetWebHyperlinkToObject' })[0].status | Should Be 'INFO'
    }
    It 'without a page: skips the page methods, still reads the folders and the window' {
        $f = New-ComFake -NoPages $true
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $f -HierarchyXml $f.Xml
        (@($c.Results | ForEach-Object { "$($_.status) $($_.name)" }) -join '; ') | Should Be 'SKIP OneNote API; OK API GetSpecialLocation; OK API Windows; INFO API not tried'
    }
    # Seen live 2026-11-16: OneNote's search found one page, an if-assignment handed over the page
    # instead of a list of one, and .Count stopped the whole stage under strict mode.
    It 'runs to the end when the notebooks hold one page (search answers with one page)' {
        $f = New-ComFake -OnePage $true
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $f -HierarchyXml $f.Xml
        @($c.Results | Where-Object { $_.status -eq 'FAIL' }).Count | Should Be 0
        @($c.Results | Where-Object { $_.name -eq 'API FindPages' })[0].detail | Should Match '^1 page\(s\) for a common word'
        $c.Results[$c.Results.Count - 1].name | Should Be 'API not tried'
    }
    It 'with no COM object it says so and calls nothing' {
        $c = New-ApiCtx
        Invoke-ApiProbe -Ctx $c -Com $null
        (@($c.Results | ForEach-Object { "$($_.status) $($_.name)" }) -join '; ') | Should Be 'SKIP OneNote API'
    }
    It 'picks a live page: never one in the recycle bin' {
        $f = New-ComFake
        $t = Get-ApiTargets $f.Xml
        $t.page | Should Be $f.Ids.p1
        $t.section | Should Be $f.Ids.sec
        $t.notebook | Should Be $f.Ids.nb
        @($t.pages).Count | Should Be 2
    }
}
