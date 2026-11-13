# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The validation kit (validation/): stage selection, status aggregation, the masking of its log,
# [SKIP] when the modules of a later build step are missing, writes only inside ObsidiNote-Probe and
# ObsidiNote-Validation, and a log without content. OneNote and Copilot are fakes or mocks; nothing
# here opens Edge or OneNote. Synthetic names only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$kit = Join-Path $root 'validation'
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'ValidationCore', 'ProbeNotebook', 'WriteProbes', 'StageOneNote', 'StageWindow', 'StageCopilot', 'StageGrounding', 'StageVault') {
    Import-Module (Join-Path $kit "lib\$m.psm1") -Force
}
. (Join-Path $here 'FakeOneNote.ps1')

function New-TestDir {
    $d = Join-Path $env:TEMP ('obsn-val-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force -Path $d
    $d
}

function New-TestCtx([hashtable]$Flags = @{}, [string]$LogPath = '', [string]$AppRoot = $root) {
    New-ValidationContext -AppRoot $AppRoot -LogPath $LogPath -Stages @('V1', 'V2', 'V3', 'V4', 'V5', 'V6') -Flags $Flags -Quiet -Prompt { param($q) '' }
}

function New-KitFake {
    <# FakeOneNote plus what the kit's adapter has on top: UpdateHierarchy (moves a page), sync and
       navigation (the shown page follows the link's page guid). #>
    $f = New-FakeOneNote
    $f | Add-Member NoteProperty Shown ''
    $f | Add-Member NoteProperty MoveWorks $true
    $f | Add-Member ScriptMethod SyncHierarchy { param([string]$Id) $null = $this.Writes.Add("SyncHierarchy $Id") }
    $f | Add-Member ScriptMethod CurrentPageId { $this.Shown }
    $f | Add-Member ScriptMethod NavigateTo { param([string]$Id) $this.Shown = $Id }
    $f | Add-Member ScriptMethod NavigateToUrl { param([string]$Url)
        foreach ($v in $this.Nodes.Values) { if ($v.kind -eq 'Page' -and $Url -like "*$($v.guid)*") { $this.Shown = $v.id; return } }
        throw 'fake: 0x80042014 object does not exist'
    }
    $f | Add-Member ScriptMethod UpdateHierarchy { param([string]$Xml)
        if (-not $this.MoveWorks) { throw 'fake: 0x80042001 invalid XML' }
        [xml]$d = $Xml
        $sec = $d.DocumentElement.GetAttribute('ID')
        foreach ($p in @($d.DocumentElement.ChildNodes)) {
            $id = $p.GetAttribute('ID')
            $n = $this.Nodes[$id]
            if ($n.parent -ne $sec) { $this.Nodes[$n.parent].children.Remove($id); $n.parent = $sec; $null = $this.Nodes[$sec].children.Add($id); $null = $this.Writes.Add("Move $id") }
        }
    }
    $f
}

function New-PrivateFake {
    <# A fake with one private notebook (invented, but treated as private) and the probe notebook. #>
    $f = New-KitFake
    $nb = $f.AddNotebook('Q3 Budget Secrets')
    $s = $f.AddSection($nb, 'Salaries 2027')
    $null = $f.AddPage($s, 'Plan to acquire Fabrikam', @{}, 1, 'Confidential body text')
    $null = $f.AddSection($nb, '00 Index')
    $f | Add-Member NoteProperty PrivateId $nb
    $f
}

Describe 'Stage selection' {
    It 'runs all stages in order when none are named' {
        (Get-ValidationStages) -join ',' | Should Be 'V1,V2,V3,V4,V5,V6'
        (Get-ValidationStages -Requested @('all')) -join ',' | Should Be 'V1,V2,V3,V4,V5,V6'
    }
    It 'keeps the fixed order and accepts lower case and one comma list' {
        (Get-ValidationStages -Requested @('v4', 'V1')) -join ',' | Should Be 'V1,V4'
        (Get-ValidationStages -Requested @('V2,V6')) -join ',' | Should Be 'V2,V6'
    }
    It 'refuses an unknown stage' {
        { Get-ValidationStages -Requested @('V9') } | Should Throw
    }
}

Describe 'Status aggregation' {
    It 'counts per status and per stage, and the worst status wins' {
        $c = New-TestCtx
        Add-ValidationResult $c 'V1' 'OK' 'a' 'x'
        Add-ValidationResult $c 'V1' 'WARN' 'b' 'x'
        Add-ValidationResult $c 'V2' 'SKIP' 'c' 'x'
        Add-ValidationResult $c 'V2' 'INFO' 'd' 'x'
        $s = Get-ValidationSummary $c
        $s.counts.OK | Should Be 1
        $s.counts.WARN | Should Be 1
        $s.counts.SKIP | Should Be 1
        $s.stages.V2.INFO | Should Be 1
        $s.result | Should Be 'WARN'
        Add-ValidationResult $c 'V3' 'FAIL' 'e' 'x'
        (Get-ValidationSummary $c).result | Should Be 'FAIL'
        (Get-ValidationFooter $c) -join ' ' | Should Match '1 OK, 1 WARN, 1 FAIL, 1 SKIP, 1 INFO'
    }
    It 'writes the summary JSON with the same counts' {
        $c = New-TestCtx
        Add-ValidationResult $c 'V1' 'OK' 'a' 'x'
        $j = ConvertTo-ValidationJson -Ctx $c -AppVersion 'v0.0.0' | ConvertFrom-Json
        $j.counts.OK | Should Be 1
        $j.result | Should Be 'OK'
        @($j.results).Count | Should Be 1
    }
    It 'keeps one space between a long name and its detail' {
        $c = New-TestCtx
        Add-ValidationResult $c 'V1' 'OK' 'A name of 22 characters' 'detail'
        $c.Lines[0] | Should Match 'characters detail'
    }
}

Describe 'Masking of the log' {
    $c = New-TestCtx
    $alias = Register-ValidationName $c 'notebook' 'Q3 Budget Secrets'
    It 'replaces a notebook name with notebook #n, and keeps the kit''s own names' {
        $alias | Should Be 'notebook #1'
        Register-ValidationName $c 'notebook' 'ObsidiNote-Probe' | Should Be 'ObsidiNote-Probe'
        Protect-ValidationText 'opened Q3 Budget Secrets and ObsidiNote-Probe' $c | Should Be 'opened notebook #1 and ObsidiNote-Probe'
    }
    It 'masks a page title registered as a name' {
        $null = Register-ValidationName $c 'name' 'Plan to acquire Fabrikam'
        Protect-ValidationText 'failed on Plan to acquire Fabrikam: 0x80042014' $c | Should Be 'failed on <name>: 0x80042014'
    }
    It 'masks e-mail addresses, GUIDs and long ids' {
        $t = Protect-ValidationText 'user ada.example@contoso.example tenant 12345678-90ab-cdef-1234-567890abcdef page {ABCDEF01-2345-6789-ABCD-EF0123456789}{1}{B0} key 0123456789abcdef0123456789abcdef'
        $t | Should Not Match 'contoso|ada\.example|12345678-90ab|ABCDEF01|0123456789abcdef0123'
        $t | Should Match '<email>'
        $t | Should Match '<id>'
    }
    It 'masks user folders as %USERPROFILE% and other users'' folders too' {
        # The other user's folder is built from parts so the repo audit does not read it as a real path.
        $other = 'C:' + '\Users' + '\someone.else'
        $t = Protect-ValidationText "at $env:USERPROFILE\AppData\x and $other\Documents\y"
        $t | Should Be 'at %USERPROFILE%\AppData\x and %USERPROFILE%\Documents\y'
    }
    It 'keeps only the host of a web address and masks the tenant in SharePoint hosts' {
        $t = Protect-ValidationText 'read https://contoso.sharepoint.com/sites/Finance/Pay.aspx?id=7&web=1 and https://example.org/a/b?q=1#f and https://example.org'
        $t | Should Be 'read https://<tenant>.sharepoint.com/<path> and https://example.org/<path> and https://example.org'
        Protect-ValidationText 'https://contoso-my.sharepoint.com/personal/ada/Documents/x.docx' | Should Be 'https://<tenant>-my.sharepoint.com/<path>'
    }
    It 'drops onenote: links whole (they hold notebook, section and page names)' {
        Protect-ValidationText 'link onenote:https://example.invalid/Docs/Secret%20Book/Notes.one#Plan&section-id={x}&end done' | Should Be 'link onenote:<link> done'
    }
    It 'masks the machine, domain and user name, SIDs and OneDrive organisation folders' {
        $t = Protect-ValidationText "pc $env:COMPUTERNAME user $env:USERNAME sid S-1-5-21-1004336348-1177238915-682003330-512 folder OneDrive - Contoso Ltd\Docs"
        if ($env:COMPUTERNAME) { $t | Should Not Match ([regex]::Escape($env:COMPUTERNAME)) }
        if ($env:USERNAME.Length -ge 2) { $t | Should Not Match ('\b' + [regex]::Escape($env:USERNAME) + '\b') }
        $t | Should Match '<sid>'
        $t | Should Match 'OneDrive - <org>\\Docs'
    }
    It 'writes masked lines to the log file' {
        $d = New-TestDir
        $log = Join-Path $d 'log.txt'
        $c2 = New-TestCtx -LogPath $log
        $null = Register-ValidationName $c2 'notebook' 'Team Alpha Notes'
        Write-ValidationLine $c2 'see Team Alpha Notes at https://contoso.sharepoint.com/sites/x?y=1 by ada@contoso.example'
        Add-ValidationResult $c2 'V2' 'FAIL' 'Something' "in $env:USERPROFILE\x for Team Alpha Notes" 'mail ada@contoso.example'
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'Team Alpha|contoso|ada@'
        $text | Should Match 'notebook #1'
        $text | Should Match '%USERPROFILE%'
        Remove-Item $d -Recurse -Force
    }
}

Describe 'The log header' {
    It 'names the date, versions, stages and boolean flags, never the address flags' {
        $c = New-TestCtx -Flags @{ WriteTest = $true; NoCopilot = $false; SharePointUrl = 'https://contoso.sharepoint.com/sites/x' }
        $h = (Get-ValidationHeader -Ctx $c -AppVersion 'v9.9.9') -join "`n"
        $h | Should Match 'Kit:'
        $h | Should Match 'ObsidiNote: v9.9.9'
        $h | Should Match 'PowerShell:'
        $h | Should Match 'Stages:\s+V1, V2'
        $h | Should Match '-WriteTest'
        $h | Should Not Match 'NoCopilot|contoso|SharePointUrl'
    }
}

Describe 'Writes stay inside the kit''s notebooks' {
    It 'accepts only ObsidiNote-Probe and ObsidiNote-Validation' {
        Test-KitNameAllowed 'ObsidiNote-Probe' | Should Be $true
        Test-KitNameAllowed 'ObsidiNote-Validation' | Should Be $true
        Test-KitNameAllowed 'ObsidiNote' | Should Be $false
        Test-KitNameAllowed 'obsidinote-probe' | Should Be $false
        { New-ProbeGuard -One (New-KitFake) -RootId '{x}' -RootName 'Q3 Budget Secrets' } | Should Throw
    }
    It 'refuses to open another notebook for writing' {
        $f = New-PrivateFake
        { Open-ProbeNotebook -One $f -Name 'Q3 Budget Secrets' } | Should Throw
        @($f.Writes).Count | Should Be 0
    }
    It 'refuses a target in another notebook' {
        $f = New-PrivateFake
        $g = Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe'
        $foreign = $f.FindByName('Salaries 2027')
        { New-ProbePage $g $foreign } | Should Throw
        { Remove-ProbeObject $g $foreign } | Should Throw
        { Remove-ProbeObject $g $g.RootId } | Should Throw
    }
    It 'P1, P1b and P1c write only into ObsidiNote-Probe' {
        $f = New-PrivateFake
        $private = @(Get-KitHierarchyIds ($f.GetHierarchy($f.PrivateId, 4)))
        $private.Count | Should Be 4
        $c = New-TestCtx -Flags @{ WriteTest = $true; NoPrompt = $true }
        $g = Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe'
        Invoke-ProbeRoundTrip -Ctx $c -Guard $g
        Invoke-ProbeMetaSize -Ctx $c -Guard $g -Sizes @(1000, 30000)
        Invoke-ProbeLinkMove -Ctx $c -Guard $g -WaitMs 0
        $null = New-ProbeMarker -Guard $g
        @($f.Writes).Count | Should BeGreaterThan 10
        $touched = @($f.Writes | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { $private -contains $_ })
        ($touched -join ', ') | Should Be ''
        @($f.Writes | Where-Object { $_ -match '^OpenHierarchy https?://' -and $_ -notmatch '/ObsidiNote-Probe$' }).Count | Should Be 0
        @($g.Writes | Where-Object { $_ -like 'section:*' -and $_ -ne "section:$($g.RootId)" }).Count | Should Be 0
        @(Get-KitHierarchyIds ($f.GetHierarchy($f.PrivateId, 4))).Count | Should Be 4
        @($f.Nodes.Values | Where-Object { $_.kind -eq 'Page' -and $_.title -eq 'Plan to acquire Fabrikam' }).Count | Should Be 1
    }
}

Describe 'The write probes (fake OneNote)' {
    It 'P1 passes every step' {
        $f = New-PrivateFake
        $c = New-TestCtx -Flags @{ WriteTest = $true }
        $g = Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe'
        $g.Created | Should Be $true
        Invoke-ProbeRoundTrip -Ctx $c -Guard $g
        $bad = @($c.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        @($c.Results | Where-Object { $_.name -like 'P1 *' }).Count | Should Be 5
    }
    It 'P1b reports the largest Meta value kept' {
        $f = New-PrivateFake
        $c = New-TestCtx
        Invoke-ProbeMetaSize -Ctx $c -Guard (Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe') -Sizes @(1000, 30000)
        $c.Results[0].status | Should Be 'OK'
        $c.Results[0].detail | Should Match 'kept up to 30000 chars'
    }
    It 'P1c: a moved page still opens from its old link; a deleted page''s link is reported' {
        $f = New-PrivateFake
        $c = New-TestCtx -Flags @{ NoPrompt = $true }
        Invoke-ProbeLinkMove -Ctx $c -Guard (Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe') -WaitMs 0
        $m = @($c.Results | Where-Object { $_.name -eq 'P1c link after move' })[0]
        $m.status | Should Be 'OK'
        $m.detail | Should Match 'moved by the kit; old link opens the page: yes; page id kept: yes'
        @($c.Results | Where-Object { $_.name -eq 'P1c deleted-page link' })[0].detail | Should Match 'OneNote reports error 0x80042014'
    }
    It 'P1c is skipped (never guessed) when OneNote does not move the page and no one is asked' {
        $f = New-PrivateFake
        $f.MoveWorks = $false
        $c = New-TestCtx -Flags @{ NoPrompt = $true }
        Invoke-ProbeLinkMove -Ctx $c -Guard (Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe') -WaitMs 0
        @($c.Results | Where-Object { $_.name -eq 'P1c link after move' })[0].status | Should Be 'SKIP'
    }
    It 'P3 marker pages are found again, newest first' {
        $f = New-PrivateFake
        $g = Open-ProbeNotebook -One $f -Name 'ObsidiNote-Probe'
        $m1 = New-ProbeMarker -Guard $g
        $m1 | Should Match '^OBSN-P3-[A-Z0-9]{6}$'
        @(Get-ProbeMarkers -One $f)[0].marker | Should Be $m1
    }
}

Describe 'V2 OneNote: the log holds counts, no names or titles' {
    It 'shows notebook #1 and counts only' {
        $d = New-TestDir
        $log = Join-Path $d 'v2.txt'
        $global:ObsnValFake = New-PrivateFake
        Mock Get-KitOneNote -ModuleName StageOneNote { $global:ObsnValFake }
        Mock Get-NotebookRecord -ModuleName StageOneNote { 'onenote:https://contoso.sharepoint.com/sites/Finance/Q3%20Budget%20Secrets' }
        $c = New-TestCtx -LogPath $log
        Invoke-StageOneNote -Ctx $c
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'Budget|Salaries|Fabrikam|Confidential|contoso|Finance'
        $text | Should Match 'notebook #1'
        $text | Should Match '1 pages; vault'
        $text | Should Match 'P1, P1b, P1c'
        @($global:ObsnValFake.Writes).Count | Should Be 0
        Remove-Item $d -Recurse -Force
    }
    It 'warns and reads nothing when OneNote is not running' {
        Mock Get-KitOneNote -ModuleName StageOneNote { $null }
        $c = New-TestCtx
        Invoke-StageOneNote -Ctx $c
        $c.Results[0].status | Should Be 'WARN'
        $c.Results.Count | Should Be 1
    }
    It 'counts sections, groups and pages without the recycle bin' {
        $f = New-KitFake
        $nb = $f.AddNotebook('Book')
        $g = $f.AddGroup($nb, 'Group')
        $s = $f.AddSection($g, 'Inner')
        $null = $f.AddPage($s, 'p1'); $null = $f.AddPage($s, 'p2')
        $bin = $f.AddRecycleBin($nb)
        $null = $f.AddPage($bin, 'gone')
        $n = @((Get-HierarchyCounts ($f.GetHierarchy('', 4))).notebooks)[0]
        $n.sections | Should Be 1
        $n.groups | Should Be 1
        $n.pages | Should Be 2
        $n.vault | Should Be $false
    }
}

Describe 'V3 Copilot' {
    It 'skips Copilot with -NoCopilot and never connects' {
        Mock Get-ProfileFacts -ModuleName StageCopilot { [pscustomobject]@{ account = 'work'; sso = 'on'; join = @{ AzureAdJoined = 'YES'; DomainJoined = 'NO'; WorkplaceJoined = 'NO'; AzureAdPrt = 'YES' }; forced = $true; mode = 'single-sign-on'; port = 9334 } }
        Mock Connect-Copilot -ModuleName StageCopilot { throw 'must not connect' }
        $c = New-TestCtx -Flags @{ NoCopilot = $true }
        Invoke-StageCopilot -Ctx $c
        @($c.Results | Where-Object { $_.name -eq 'Copilot' })[0].status | Should Be 'SKIP'
        Assert-MockCalled Connect-Copilot -ModuleName StageCopilot -Times 0 -Exactly -Scope It
    }
    It 'does not open Edge to wait for a sign-in when Edge requires one (BrowserSignin = 2)' {
        Mock Get-ProfileFacts -ModuleName StageCopilot { [pscustomobject]@{ account = 'none'; sso = 'unavailable'; join = @{ AzureAdJoined = 'YES'; DomainJoined = 'NO'; WorkplaceJoined = 'NO'; AzureAdPrt = 'YES' }; forced = $true; mode = 'single-sign-on'; port = 9334 } }
        Mock Connect-Copilot -ModuleName StageCopilot { throw 'must not connect' }
        $c = New-TestCtx
        Invoke-StageCopilot -Ctx $c
        @($c.Results | Where-Object { $_.name -eq 'Copilot' })[0].status | Should Be 'WARN'
        Assert-MockCalled Connect-Copilot -ModuleName StageCopilot -Times 0 -Exactly -Scope It
    }
    It 'checks the echo reply' {
        Test-EchoReply -Reply 'OK-123456' -Token 'OK-123456' | Should Be 'exact'
        Test-EchoReply -Reply '`OK-123456`.' -Token 'OK-123456' | Should Be 'exact'
        Test-EchoReply -Reply 'Sure! OK-123456' -Token 'OK-123456' | Should Be 'contains'
        Test-EchoReply -Reply 'Hello' -Token 'OK-123456' | Should Be 'wrong'
    }
    It 'logs the reply length, never the reply' {
        Mock Get-ProfileFacts -ModuleName StageCopilot { [pscustomobject]@{ account = 'work'; sso = 'on'; join = @{ AzureAdJoined = 'YES'; DomainJoined = 'NO'; WorkplaceJoined = 'NO'; AzureAdPrt = 'YES' }; forced = $false; mode = 'single-sign-on'; port = 9334 } }
        Mock Connect-Copilot -ModuleName StageCopilot { [pscustomobject]@{ SignInPending = $false; Port = 9334 } }
        Mock New-CopilotChat -ModuleName StageCopilot { }
        Mock Send-CopilotPrompt -ModuleName StageCopilot { [pscustomobject]@{ Result = 'Success'; Text = 'Secret reply about Fabrikam' } }
        Mock Set-CopilotWorkIq -ModuleName StageCopilot { 'on' }
        $c = New-TestCtx
        Invoke-StageCopilot -Ctx $c
        ($c.Lines -join "`n") | Should Not Match 'Fabrikam|Secret'
        @($c.Results | Where-Object { $_.name -eq 'Copilot reply' })[0].status | Should Be 'FAIL'
        @($c.Results | Where-Object { $_.name -eq 'Work IQ switch' })[0].status | Should Be 'OK'
    }
}

Describe 'V5 Grounding probes' {
    It 'parses JSON replies (with fences) and checks their shape' {
        $j = Get-JsonFromReply ("Here:`n" + '```json' + "`n" + '{"found": true, "where": "P3 marker x", "app": "OneNote"}' + "`n" + '```')
        Test-JsonShape $j @('found', 'where') | Should Be $true
        (Test-MarkerReply '{"found": true, "where": "P3 marker OBSN-P3-AAAAAA", "app": "OneNote"}').cited | Should Be $true
        (Test-MarkerReply '{"found": false, "where": "", "app": ""}').found | Should Be $false
        (Test-MarkerReply 'NOT FOUND').valid | Should Be $false
        (Test-LinkReply '{"title":"t","where":"w","kind":"page","summary":"s","keyFacts":["a","b"],"useItFor":"u","sensitivity":"","access":"ok"}').found | Should Be $true
        (Test-LinkReply '{"title":"t","where":"w","kind":"page","summary":"","keyFacts":[],"useItFor":"u","sensitivity":"","access":"no-access"}').found | Should Be $false
    }
    It 'tells SharePoint, OneDrive and web addresses apart' {
        Get-UrlKind 'https://contoso.sharepoint.com/sites/x/SitePages/Home.aspx' | Should Be 'sharepoint'
        Get-UrlKind 'https://contoso-my.sharepoint.com/personal/a/Documents/b.docx' | Should Be 'onedrive'
        Get-UrlKind 'https://example.org/a' | Should Be 'web'
        Get-UrlKind 'http://example.org/a' | Should Be ''
        Get-UrlKind 'not a url' | Should Be ''
    }
    It 'logs found, shape, length and timing only: no address, marker or reply' {
        $d = New-TestDir
        $log = Join-Path $d 'v5.txt'
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding {
            [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1234; error = ''; workIq = 'on'
                text = '{"title":"Merger plan Fabrikam","where":"Finance site","kind":"page","summary":"Secret merger summary.","keyFacts":["Price 12M"],"useItFor":"deal","sensitivity":"Confidential","access":"ok"}' }
        }
        $c = New-TestCtx -LogPath $log -Flags @{ NoPrompt = $true; SharePointUrl = 'https://contoso.sharepoint.com/sites/Finance/SitePages/Merger.aspx?a=1'; OneDriveUrl = 'https://contoso-my.sharepoint.com/personal/ada/Documents/Deal.docx'; PublicUrl = 'https://example.org/secret-article' }
        Invoke-StageGrounding -Ctx $c
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'contoso|Finance|Merger|Fabrikam|Secret|Deal|secret-article|example\.org|12M'
        @($c.Results | Where-Object { $_.name -like 'P7*' -and $_.status -eq 'OK' }).Count | Should Be 2
        @($c.Results | Where-Object { $_.name -like 'P8*' -and $_.status -eq 'OK' }).Count | Should Be 2
        @($c.Results | Where-Object { $_.name -eq 'P3 OneNote grounding' })[0].status | Should Be 'SKIP'
        $text | Should Match 'summary made yes; access ok; JSON valid yes; 1 key facts'
        Remove-Item $d -Recurse -Force
    }
    It 'refuses a P7 address of the wrong kind without sending it' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{}' } }
        $c = New-TestCtx -Flags @{ NoPrompt = $true; SharePointUrl = 'https://example.org/x'; OneDriveUrl = '' }
        Invoke-StageGrounding -Ctx $c
        @($c.Results | Where-Object { $_.name -eq 'P7 SharePoint page' })[0].status | Should Be 'WARN'
        @($c.Results | Where-Object { $_.name -eq 'P7 OneDrive document' })[0].status | Should Be 'SKIP'
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 2 -Exactly -Scope It
    }
}

Describe 'V6 skips what is not in this version yet' {
    It 'lists the modules missing from lib' {
        $d = New-TestDir
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'lib')
        [IO.File]::WriteAllText((Join-Path $d 'lib\Vault.psm1'), '#')
        $miss = Get-MissingAppModules -AppRoot $d -Names @('Vault', 'Index', 'Ask')
        ($miss -join ',') | Should Be 'Index,Ask'
        Remove-Item $d -Recurse -Force
    }
    It 'prints [SKIP] "not in this version yet" for every V6 check when the modules are missing' {
        $d = New-TestDir
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'lib')
        $c = New-TestCtx -AppRoot $d -Flags @{ WriteTest = $true }
        Invoke-StageVault -Ctx $c
        $c.Results.Count | Should Be 9
        @($c.Results | Where-Object { $_.status -eq 'SKIP' -and $_.detail -match '^not in this version yet' }).Count | Should Be 9
        @($c.Results | Where-Object { $_.name -eq 'Link it' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Check for the answer' }).Count | Should Be 1
        Remove-Item $d -Recurse -Force
    }
    It 'names only the kit''s dev vault for writing' {
        Get-DevNotebookName | Should Be 'ObsidiNote-Validation'
        Test-KitNameAllowed (Get-DevNotebookName) | Should Be $true
    }
}

Describe 'V6 "Link it" in the dev vault (in-memory OneNote, no Copilot)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $dev = [pscustomobject]@{ vault = $w.open.vault; lease = $w.open.lease; model = $w.open.model }
    $c = New-TestCtx -Flags @{ WriteTest = $true }
    $before = @($w.open.model.pages.Keys | Sort-Object) -join ','
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevLinkIt $c $a $d } $c $w.a $dev
    It 'links two synthetic pages, finds the link again, and takes both pages back out' {
        $bad = @($c.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.status) $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        (@($c.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Link it,Link it again,Link it (undo)'
        @($c.Results | Where-Object { $_.name -eq 'Link it again' })[0].detail | Should Match '^status already-linked'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
        (Find-FakePage $w.f 'Validation link source') | Should BeNullOrEmpty
    }
    It 'logs statuses and timings only, no page titles' {
        (@($c.Results | ForEach-Object { "$($_.detail)" }) -join ' ') | Should Not Match 'Validation link'
    }
}

Describe 'V4 window (live server on a test port, no window)' {
    It 'answers on the test port, refuses a bad Origin and a missing header, and stops' {
        $c = New-TestCtx -Flags @{ NoCopilot = $true; TestPort = 18779 }
        Invoke-StageWindow -Ctx $c
        $bad = @($c.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        @($c.Results | Where-Object { $_.name -eq 'Bad Origin refused' }).Count | Should Be 1
        $c.Results[0].detail | Should Match 'test port 18779'
    }
}

Describe 'The kit on disk' {
    It 'writes files only in the log writer (no content on disk)' {
        $writes = '(?i)\b(WriteAllText|WriteAllLines|WriteAllBytes|AppendAllText|AppendAllLines|Set-Content|Add-Content|Out-File|Tee-Object|Start-Transcript|StreamWriter|FileStream|Export-(?!ModuleMember)\w+)\b'
        $hits = @(Get-ChildItem (Join-Path $kit 'lib') -Filter *.psm1 | ForEach-Object {
                $f = $_
                $i = 0
                foreach ($l in [IO.File]::ReadAllLines($f.FullName)) { $i++; if ($l -notmatch '^\s*#' -and $l -match $writes) { "$($f.Name):$i" } }
            })
        @($hits | Where-Object { $_ -notlike 'ValidationCore.psm1:*' }).Count | Should Be 0
        @($hits | Where-Object { $_ -like 'ValidationCore.psm1:*' }).Count | Should Be 2
    }
    It 'Run Validation.cmd is one ( ) block that ends with exit /b, with CRLF line endings' {
        $f = Join-Path $kit 'Run Validation.cmd'
        $lines = @([IO.File]::ReadAllLines($f) | Where-Object { $_.Trim() })
        $code = @($lines | Where-Object { $_.Trim() -notmatch '^(@echo off|rem\b)' })
        $code[0].Trim() | Should Be '('
        $code[-1].Trim() | Should Be ')'
        $code[-2].Trim() | Should Be 'exit /b'
        ([IO.File]::ReadAllText($f) -match "[^`r]`n") | Should Be $false
    }
    It 'ships in the release (validation is not a development folder)' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'tools\build-release.ps1'))
        $m = [regex]::Match($src, "foreach \(\`$dev in ([^)]+)\)")
        $m.Success | Should Be $true
        $m.Groups[1].Value | Should Not Match "'validation'"
    }
}
