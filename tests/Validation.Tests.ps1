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
    # -Force: the kit's own navigation (to a page) in place of FakeOneNote's notebook one.
    $f | Add-Member -Force ScriptMethod NavigateTo { param([string]$Id) $this.Shown = $Id }
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
        $t = Protect-ValidationText 'user ada.example@fernbrook.example tenant 12345678-90ab-cdef-1234-567890abcdef page {ABCDEF01-2345-6789-ABCD-EF0123456789}{1}{B0} key 0123456789abcdef0123456789abcdef'
        $t | Should Not Match 'fernbrook|ada\.example|12345678-90ab|ABCDEF01|0123456789abcdef0123'
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
        $t = Protect-ValidationText 'read https://fernbrook.sharepoint.com/sites/Finance/Pay.aspx?id=7&web=1 and https://example.org/a/b?q=1#f and https://example.org'
        $t | Should Be 'read https://<tenant>.sharepoint.com/<path> and https://example.org/<path> and https://example.org'
        Protect-ValidationText 'https://fernbrook-my.sharepoint.com/personal/ada/Documents/x.docx' | Should Be 'https://<tenant>-my.sharepoint.com/<path>'
    }
    It 'drops onenote: links whole (they hold notebook, section and page names)' {
        Protect-ValidationText 'link onenote:https://example.invalid/Docs/Secret%20Book/Notes.one#Plan&section-id={x}&end done' | Should Be 'link onenote:<link> done'
    }
    It 'masks the machine, domain and user name, SIDs and OneDrive organisation folders' {
        $t = Protect-ValidationText "pc $env:COMPUTERNAME user $env:USERNAME sid S-1-5-21-1004336348-1177238915-682003330-512 folder OneDrive - Fernbrook Ltd\Docs"
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
        Write-ValidationLine $c2 'see Team Alpha Notes at https://fernbrook.sharepoint.com/sites/x?y=1 by ada@fernbrook.example'
        Add-ValidationResult $c2 'V2' 'FAIL' 'Something' "in $env:USERPROFILE\x for Team Alpha Notes" 'mail ada@fernbrook.example'
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'Team Alpha|fernbrook|ada@'
        $text | Should Match 'notebook #1'
        $text | Should Match '%USERPROFILE%'
        Remove-Item $d -Recurse -Force
    }
}

Describe 'The log header' {
    It 'names the date, versions, stages and boolean flags, never the address flags' {
        $c = New-TestCtx -Flags @{ WriteTest = $true; NoCopilot = $false; SharePointUrl = 'https://fernbrook.sharepoint.com/sites/x' }
        $h = (Get-ValidationHeader -Ctx $c -AppVersion 'v9.9.9') -join "`n"
        $h | Should Match 'Kit:'
        $h | Should Match 'ObsidiNote: v9.9.9'
        $h | Should Match 'PowerShell:'
        $h | Should Match 'Stages:\s+V1, V2'
        $h | Should Match '-WriteTest'
        $h | Should Not Match 'NoCopilot|fernbrook|SharePointUrl'
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
        Mock Get-NotebookRecord -ModuleName StageOneNote { 'onenote:https://fernbrook.sharepoint.com/sites/Finance/Q3%20Budget%20Secrets' }
        $c = New-TestCtx -LogPath $log
        Invoke-StageOneNote -Ctx $c
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'Budget|Salaries|Fabrikam|Confidential|fernbrook|Finance'
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
        Get-UrlKind 'https://fernbrook.sharepoint.com/sites/x/SitePages/Home.aspx' | Should Be 'sharepoint'
        Get-UrlKind 'https://fernbrook-my.sharepoint.com/personal/a/Documents/b.docx' | Should Be 'onedrive'
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
        $c = New-TestCtx -LogPath $log -Flags @{ NoPrompt = $true; SharePointUrl = 'https://fernbrook.sharepoint.com/sites/Finance/SitePages/Merger.aspx?a=1'; OneDriveUrl = 'https://fernbrook-my.sharepoint.com/personal/ada/Documents/Deal.docx'; PublicUrl = 'https://example.org/secret-article' }
        Invoke-StageGrounding -Ctx $c
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'fernbrook|Finance|Merger|Fabrikam|Secret|Deal|secret-article|example\.org|12M'
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
        # P8 twice, and P10's meeting list once (its reply has no meetings, so no second question)
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 3 -Exactly -Scope It
    }
}

Describe 'V5 P10 meetings (operator, 2026-11-14)' {
    $list = '{"meetings":[{"title":"Fabrikam merger steering","start":"2026-11-13 10:00","attendees":6,"hasTranscript":true,"hasRecap":true,"hasNotes":false,"link":"https://fernbrook.sharepoint.com/recap/1"},{"title":"Coffee with Ada","start":"2026-11-12 09:00","attendees":2,"hasTranscript":false,"hasRecap":false,"hasNotes":false,"link":""}],"searched":["Teams"]}'
    $notes = '{"found":true,"date":"2026-11-13","attendees":[{"name":"Ada Lovelace","email":"ada@fernbrook.example"},{"name":"Grace Hopper","email":""}],"summary":"Secret merger talk.","decisions":["Buy Fabrikam for 12M"],"actions":[{"text":"Draft term sheet","owner":"Ada Lovelace","due":"2026-11-20"},{"text":"Call the bank","owner":"","due":""}],"basedOn":"transcript","source":"https://fernbrook.sharepoint.com/recap/1"}'
    It 'counts meetings and what Copilot can read of them; picks the newest one that has something' {
        $l = Test-MeetingListReply $list
        "$($l.valid)|$($l.count)|$($l.transcript)|$($l.recap)|$($l.notes)|$($l.links)" | Should Be 'True|2|1|1|0|1'
        $l.pick.title | Should Be 'Fabrikam merger steering'
        (Test-MeetingListReply '{"meetings":[],"searched":[]}').pick | Should Be $null
        (Test-MeetingListReply 'I cannot see your meetings.').valid | Should Be $false
    }
    It 'counts the parts of the structured notes' {
        $n = Test-MeetingNotesReply $notes
        "$($n.found)|$($n.attendees)|$($n.addresses)|$($n.decisions)|$($n.actions)|$($n.owners)|$($n.dues)|$($n.basedOn)|$($n.source)" | Should Be 'True|2|1|1|2|1|1|transcript|True'
        # The old shape (plain names, also "Name <address>") still counts.
        (Test-MeetingNotesReply '{"found":true,"attendees":["Ada <ada@fernbrook.example>","Grace"],"decisions":[],"actions":[]}').addresses | Should Be 1
        (Test-MeetingNotesReply '{"found":false,"attendees":[],"decisions":[],"actions":[]}').found | Should Be $false
    }
    # The full day (operator, 2026-11-15): every meeting of 2026-11-13, two of them with something to read.
    $dayList = '{"meetings":[{"title":"Fabrikam merger steering","start":"2026-11-13 10:00","attendees":6,"hasTranscript":true,"hasRecap":true,"hasNotes":false,"link":""},{"title":"Northwind budget review","start":"2026-11-13 14:00","attendees":4,"hasTranscript":false,"hasRecap":true,"hasNotes":true,"link":""},{"title":"Coffee with Ada","start":"2026-11-13 16:00","attendees":2,"hasTranscript":false,"hasRecap":false,"hasNotes":false,"link":""}],"searched":["Teams"]}'
    function Set-P10Replies([string]$Week, [string]$Day, [string]$Notes) {
        # Pester 3.4: a Mock runs in the module's scope and cannot see this Describe's variables.
        $global:ObsnP10List = $Week; $global:ObsnP10Day = $Day; $global:ObsnP10Notes = $Notes
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding {
            $t = if ($Text -like 'List my Teams meetings*') { $global:ObsnP10List } elseif ($Text -like 'List all my Teams meetings on*') { $global:ObsnP10Day } elseif ($Text -like 'From the transcript*') { $global:ObsnP10Notes } else { '{}' }
            [pscustomobject]@{ ok = $true; result = 'Success'; ms = 900; error = ''; workIq = 'on'; text = $t }
        }
    }
    function Clear-P10Replies { Remove-Variable -Name ObsnP10List, ObsnP10Day, ObsnP10Notes -Scope Global -ErrorAction SilentlyContinue }
    It 'lists the busiest day, asks for the notes of two of its meetings one by one, and logs counts only: no title, name, link, date or text' {
        $d = New-TestDir
        $log = Join-Path $d 'p10.txt'
        Set-P10Replies $list $dayList $notes
        $c = New-TestCtx -LogPath $log -Flags @{ NoPrompt = $true; Probes = @('P10') }
        Invoke-StageGrounding -Ctx $c
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like 'List all my Teams meetings on 2026-11-13,*' } -Times 1 -Exactly
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like 'From the transcript*"Fabrikam merger steering"*' } -Times 1 -Exactly
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like 'From the transcript*"Northwind budget review"*' } -Times 1 -Exactly
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like '*Coffee with Ada*' } -Times 0 -Exactly
        $text = [IO.File]::ReadAllText($log)
        $text | Should Not Match 'Fabrikam|Northwind|Ada|Grace|Lovelace|fernbrook|recap/1|term sheet|bank|12M|Secret|2026-11-1[23]'
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'P10 meetings list=OK,P10 day''s meetings=OK,P10 meeting notes 1=OK,P10 meeting notes 2=OK'
        $text | Should Match '2 meetings in the last 7 days; with a transcript 1, a recap 1, notes 0, a link 1'
        $text | Should Match '3 meetings on the busiest day of the last 7 days \(0 of another day\); with a transcript 1, a recap 2, notes 1; the week''s list had 1 of that day'
        $text | Should Match 'date matches the day yes; 2 attendees \(1 with an address\), 1 decisions, 2 actions \(1 with an owner, 1 with a due date\); source link yes'
        $text | Should Not Match 'fernbrook\.example|@'
        Remove-Item $d -Recurse -Force
        Clear-P10Replies
    }
    It 'asks the day given with -MeetingDay, also when the week''s list has nothing, and never logs it' {
        $d = New-TestDir
        $log = Join-Path $d 'p10day.txt'
        Set-P10Replies '{"meetings":[],"searched":[]}' $dayList $notes
        $c = New-TestCtx -LogPath $log -Flags @{ NoPrompt = $true; Probes = @('P10'); MeetingDay = '2026-11-13' }
        Invoke-StageGrounding -Ctx $c
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like 'List all my Teams meetings on 2026-11-13,*' } -Times 1 -Exactly
        $text = [IO.File]::ReadAllText($log)
        $text | Should Match '3 meetings on the day given with -MeetingDay'
        $text | Should Not Match '2026-11-13'
        @($c.Results | Where-Object { $_.name -eq 'P10 meeting notes 2' })[0].status | Should Be 'OK'
        Remove-Item $d -Recurse -Force
        Clear-P10Replies
    }
    It 'fails on a -MeetingDay that is not a date, without asking for that day' {
        Set-P10Replies $list $dayList $notes
        $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @('P10'); MeetingDay = '13-11-2026' }
        Invoke-StageGrounding -Ctx $c
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'P10 meetings list=OK,P10 day''s meetings=FAIL'
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 1 -Exactly -Scope It
        Clear-P10Replies
    }
    It 'reads one meeting and says why there is no second, on a day with only one to read; a wrong date shows' {
        $one = '{"meetings":[{"title":"Fabrikam merger steering","start":"2026-11-13 10:00","hasTranscript":true},{"title":"Coffee with Ada","start":"2026-11-13 16:00"},{"title":"Late call","start":"2026-11-14 09:00","hasRecap":true}],"searched":["Teams"]}'
        Set-P10Replies $list $one ($notes -replace '"date":"2026-11-13"', '"date":"2026-11-06"')
        $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @('P10') }
        Invoke-StageGrounding -Ctx $c
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'P10 meetings list=OK,P10 day''s meetings=WARN,P10 meeting notes 1=OK,P10 meeting notes 2=SKIP'
        $c.Results[1].detail | Should Match '3 meetings on .* \(1 of another day\)'
        ($c.Lines -join "`n") | Should Match 'Copilot listed meetings of other days too'
        $c.Results[2].detail | Should Match 'date matches the day no'
        $c.Results[3].detail | Should Match 'only 1 meeting'
        # the meeting of another day is never asked about
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Scope It -ParameterFilter { $Text -like '*Late call*' } -Times 0 -Exactly
        Clear-P10Replies
    }
    It 'chooses the day with the most meetings to read, the newest on a tie, and none without dates' {
        Select-MeetingDay ([pscustomobject]@{ richDays = @('2026-11-10', '2026-11-12', '2026-11-12', '2026-11-13') }) | Should Be '2026-11-12'
        Select-MeetingDay ([pscustomobject]@{ richDays = @('2026-11-10', '2026-11-13') }) | Should Be '2026-11-13'
        Select-MeetingDay ([pscustomobject]@{ richDays = @() }) | Should Be ''
        (Test-MeetingListReply $list).richDays -join ',' | Should Be '2026-11-13'
    }
    It 'takes only a real date written yyyy-mm-dd as -MeetingDay' {
        Test-MeetingDayValue '2026-11-13' | Should Be $true
        foreach ($bad in '', '2026-02-30', '13-11-2026', '2026-11-13 10:00', '20261113', 'tomorrow') { Test-MeetingDayValue $bad | Should Be $false }
    }
    It 'takes "today" as -MeetingDay and asks for this computer''s date (operator, 2026-11-16)' {
        Test-MeetingDayValue 'today' | Should Be $true
        Resolve-MeetingDay 'today' -Now ([datetime]'2026-11-16 23:30') | Should Be '2026-11-16'
        Resolve-MeetingDay '2026-11-12' | Should Be '2026-11-12'
        New-MeetingDayPrompt (Resolve-MeetingDay 'today' -Now ([datetime]'2026-11-16 08:00')) | Should Match 'meetings on 2026-11-16,'
    }
    It 'counts the meetings of the day and of other days, and picks only that day''s' {
        $l = Test-MeetingListReply '{"meetings":[{"title":"A","start":"2026-11-13 10:00","hasRecap":true},{"title":"B","start":"2026-11-12 10:00","hasRecap":true},{"title":"C","hasNotes":true}]}' -Day '2026-11-13'
        "$($l.onDay)|$($l.offDay)|$((@($l.picks) | ForEach-Object { $_.title }) -join ',')" | Should Be '1|1|A,C'
    }
    It 'runs only P10 with -Probe P10 (Run Meeting Probe.cmd)' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{"meetings":[],"searched":[]}' } }
        $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @('P10') }
        Invoke-StageGrounding -Ctx $c
        (@($c.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'P10 meetings list,P10 day''s meetings'
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 1 -Exactly -Scope It
    }
    It 'picks no meeting without a title, and never throws on a list item without one (code review 2026-11-15)' {
        # the newest meeting with something has no "title" at all; the next one's is empty; the third has one
        $l = Test-MeetingListReply '{"meetings":[{"start":"2026-11-13 10:00","hasTranscript":true},{"title":"  ","hasRecap":true},{"title":"Fabrikam merger steering","hasNotes":true}]}'
        "$($l.valid)|$($l.count)|$($l.rich)|$($l.pick.title)" | Should Be 'True|3|3|Fabrikam merger steering'
        $none = Test-MeetingListReply '{"meetings":[{"start":"2026-11-13 10:00","hasTranscript":true},{"title":"","hasRecap":true}]}'
        "$($none.valid)|$($none.count)|$($none.rich)" | Should Be 'True|2|2'
        $none.pick | Should Be $null
    }
    It 'gives a WARN line, not a stopped stage, when the meeting to ask about has no title' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{"meetings":[{"start":"2026-11-13 10:00","hasTranscript":true}],"searched":["Teams"]}' } }
        $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @('P10') }
        { Invoke-StageGrounding -Ctx $c } | Should Not Throw
        # the same reply for the week and the day: one meeting of 2026-11-13 with something to read, no title
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'P10 meetings list=OK,P10 day''s meetings=OK,P10 meeting notes 1=WARN'
        $c.Results[2].detail | Should Match 'without a title'
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 2 -Exactly -Scope It
    }
}

Describe 'V5 -Probe: a name that is no probe (code review 2026-11-15)' {
    It 'lists the probes of the stage' {
        ((Get-GroundingProbes) -join ',') | Should Be 'P3,P4,P7,P8,P10'
    }
    It 'fails with a line that names the probes, and never opens Copilot for it' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{}' } }
        $d = New-TestDir
        $log = Join-Path $d 'probe.txt'
        $c = New-TestCtx -LogPath $log -Flags @{ NoPrompt = $true; Probes = @('P1O', 'MEETINGS') }
        Invoke-StageGrounding -Ctx $c
        $c.Results.Count | Should Be 1
        $r = $c.Results[0]
        "$($r.stage)|$($r.status)|$($r.name)" | Should Be 'V5|FAIL|Probe'
        $r.detail | Should Match '2 name\(s\) given with -Probe are not a probe; the probes are P3, P4, P7, P8, P10'
        # what was typed is not written to the log
        [IO.File]::ReadAllText($log) | Should Not Match 'P1O|MEETINGS'
        Assert-MockCalled Connect-KitCopilot -ModuleName StageGrounding -Times 0 -Exactly -Scope It
        Assert-MockCalled Send-KitPrompt -ModuleName StageGrounding -Times 0 -Exactly -Scope It
        (Get-ValidationSummary $c).result | Should Be 'FAIL'
        Remove-Item $d -Recurse -Force
    }
    It 'still runs the probes it knows next to the wrong name, in any letter case' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{"meetings":[],"searched":[]}' } }
        $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @('p10', 'P99') }
        Invoke-StageGrounding -Ctx $c
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'Probe=FAIL,P10 meetings list=WARN,P10 day''s meetings=SKIP'
    }
    It 'a V5 run never ends without a result line' {
        Mock Connect-KitCopilot -ModuleName StageGrounding { [pscustomobject]@{ Port = 9334 } }
        Mock Get-KitOneNote -ModuleName StageGrounding { $null }
        Mock Send-KitPrompt -ModuleName StageGrounding { [pscustomobject]@{ ok = $true; result = 'Success'; ms = 1; error = ''; workIq = 'on'; text = '{"meetings":[],"searched":[]}' } }
        foreach ($p in '', 'P3', 'P4', 'P7', 'P8', 'P10', 'nope', 'P3;P4;P7;P8;P10', 'nope;P99') {
            $c = New-TestCtx -Flags @{ NoPrompt = $true; Probes = @($p.Split(';') | Where-Object { $_ }) }
            Invoke-StageGrounding -Ctx $c
            "$p $($c.Results.Count -gt 0)" | Should Be "$p True"
        }
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
        $c.Results.Count | Should Be 16
        @($c.Results | Where-Object { $_.status -eq 'SKIP' -and $_.detail -match '^not in this version yet' }).Count | Should Be 16
        @($c.Results | Where-Object { $_.name -eq 'Archive, restore and delete' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Notebook reads' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Undo of a linked page' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Tags' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Vault settings' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Link it' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Upgrade plan' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Upgrade move' }).Count | Should Be 1
        @($c.Results | Where-Object { $_.name -eq 'Check for the answer' }).Count | Should Be 1
        Remove-Item $d -Recurse -Force
    }
    It 'names only the kit''s dev vault for writing' {
        Get-DevNotebookName | Should Be 'ObsidiNote-Validation'
        Test-KitNameAllowed (Get-DevNotebookName) | Should Be $true
    }
}

Describe 'V6 Add lines say why an Add did not go as expected (target machine, 2026-11-16)' {
    # The kit logged "status failed" for Add without a reason: Add never throws, its message carries it.
    $why = { param($Step, $St, $Exp) & (Get-Module StageVault) { param($s, $t, $e) Get-AddWhy $s $t $e } $Step $St $Exp }
    It 'adds the Add result''s message when the status is not the expected one' {
        & $why @{ ok = $true; value = @{ status = 'failed'; message = 'Copilot did not answer (Busy).' } } 'failed' 'added' | Should Be '; Copilot did not answer (Busy).'
    }
    It 'adds nothing when the status is the expected one, or the result has no message' {
        & $why @{ ok = $true; value = @{ status = 'added'; message = 'Added.' } } 'added' 'added' | Should Be ''
        & $why @{ ok = $true; value = @{ status = 'failed' } } 'failed' 'waiting' | Should Be ''
    }
    It 'adds the error of a step that threw' {
        & $why @{ ok = $false; error = 'boom'; value = $null } 'error' 'added' | Should Be '; boom'
    }
}

Describe 'V6 compares link parts without logging them (target machine, 2026-11-18)' {
    $cmp = { param($a, $b) & (Get-Module StageVault) { param($x, $y) Format-KitLinkCompare $x $y } $a $b }
    $full = 'onenote:https://example.invalid/docs/Archive/Notes.one#Target&section-id={22222222-2222-2222-2222-222222222222}&page-id={CCCCCCCC-0000-4000-8000-00000000000C}&end'
    It 'tells a short in-notebook form with the same ids from another page' {
        $short = 'onenote:#Target&section-id={22222222-2222-2222-2222-222222222222}&page-id={CCCCCCCC-0000-4000-8000-00000000000C}&end&base-path=https://example.invalid/docs/Archive/Notes.one'
        & $cmp $short $full | Should Be 'same page-id yes; same section-id yes; same address no; short form yes; base-path yes'
        & $cmp ($full -replace 'CCCCCCCC', 'DDDDDDDD') $full | Should Be 'same page-id no; same section-id yes; same address yes; short form no; base-path no'
        & $cmp '' $full | Should Be 'no link in the text'
    }
    It 'never puts an address, an id or a title in the line' {
        (& $cmp $full $full) | Should Not Match 'example|2222|cccc|Target'
    }
}

Describe 'V6 closures are made outside Measure-KitStep blocks (target machine, 2026-11-17)' {
    # A closure made inside a block that Measure-KitStep (another module) runs does not see the
    # function's variables: GetLease returned nothing and Add reported "Read only" on the target
    # machine, while every step that made its closure first passed.
    It 'no kit module makes a closure inside a Measure-KitStep { ... } block' {
        $bad = @()
        foreach ($f in Get-ChildItem (Join-Path $root 'validation\lib') -Filter *.psm1) {
            $n = 0
            foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
                $n++
                if ($line -match 'Measure-KitStep\s*\{.*GetNewClosure\(\)') { $bad += "$($f.Name):$n" }
            }
        }
        ($bad -join ', ') | Should Be ''
    }
}

Describe 'V6 write steps keep the dev vault''s lease alive (target machine, 2026-11-17, v0.12.8)' {
    # The kit took its 120 s lease once; "Check for the answer" waited 92 s and every write step after
    # it was refused as "Read only". The getter renews it with the same session when under 60 s are left.
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $isid = [string]$w.open.vault.indexSectionId
    $short = Request-WriterLease -Adapter $w.a -IndexSectionId $isid -SessionId ([string]$w.open.lease.sessionId) -TtlSec 30
    $get = & (Get-Module StageVault) { param($a, $i, $l) New-DevLeaseGetter $a $i $l } $w.a $isid $short
    It 'renews a lease with less than 60 s left, with the same session, and keeps it a writer lease' {
        $short.mode | Should Be 'writer'
        $l = & $get
        $l.mode | Should Be 'writer'
        $l.sessionId | Should Be $short.sessionId
        ([datetime]$l.expires).ToUniversalTime() -gt [datetime]::UtcNow.AddSeconds(60) | Should Be $true
    }
    It 'hands the same renewed lease to every later call' {
        $a1 = & $get; $a2 = & $get
        $a1.expires | Should Be $a2.expires
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

Describe 'V6 "Undo of a linked page" and "Tags" in the dev vault (in-memory OneNote, no Copilot)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $dev = [pscustomobject]@{ vault = $w.open.vault; lease = $w.open.lease; model = $w.open.model }
    $before = @($w.open.model.pages.Keys | Sort-Object) -join ','
    $c = New-TestCtx -Flags @{ WriteTest = $true }
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevUndoLinked $c $a $d } $c $w.a $dev
    It 'undoes a page another page links to: no link left in that page''s Meta, its text says deleted' {
        $bad = @($c.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.status) $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        (@($c.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Undo of a linked page,Undo of a linked page (undo)'
        $c.Results[0].detail | Should Match '^status undone; unlinked 1; text rewritten on 1 page\(s\); links left in the linking page: 0; its text says deleted: True'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
        (Find-FakePage $w.f 'Validation undo linker') | Should BeNullOrEmpty
    }
    $t = New-TestCtx -Flags @{ WriteTest = $true }
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevTags $c $a $d } $t $w.a $dev
    It 'tags a synthetic page, reads it back, renames the tag, removes it, and takes the page back out' {
        $bad = @($t.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.status) $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        (@($t.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Tags,Tags (rename),Tags (remove),Tags (undo)'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
    }
    $j = New-TestCtx -Flags @{ WriteTest = $true }
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevJournal $c $a $d } $j $w.a $dev
    It 'puts two journal entries on one day page, takes out one, then the other (2026-11-17)' {
        (@($j.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'Journal day page=OK,Journal day page (undo one entry)=OK,Journal day page (undo)=OK'
        $j.Results[0].detail | Should Match '^two entries on one day page: yes; entry lines in its text: 2 \(expected 2\)'
        $j.Results[1].detail | Should Match 'entry lines left: 1 \(expected 1\)'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
        @($j.Results | ForEach-Object { $_.detail } | Where-Object { $_ -match 'Validation entry' }).Count | Should Be 0
    }
    It 'logs counts and statuses only: no page title, no tag text' {
        $lines = @(foreach ($x in $c.Results) { "$($x.name) $($x.detail)" }) + @(foreach ($x in $t.Results) { "$($x.name) $($x.detail)" })
        $lines.Count | Should Be 6
        $all = $lines -join ' '
        $all | Should Not Match 'Validation (undo|tag)'
        $all | Should Not Match 'validation kit tag'
        $all | Should Not Match 'p\d'
    }
    It 'lists both in the read-only plan (no -WriteTest)' {
        $r = New-TestCtx
        & (Get-Module StageVault) { param($c, $a) Invoke-DevVaultChecks $c $a } $r $w.a
        (@($r.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Dev vault,Add and Undo,Check for the answer,Link it,Undo of a linked page,Tags,Journal day page,Archive, restore and delete,Upgrade move,Ask'
        @($r.Results | Where-Object { $_.status -ne 'SKIP' }).Count | Should Be 0
    }
    It 'takes the company names for the upgrade plan from Get-LinkRules' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'validation\lib\StageVault.psm1'))
        $src | Should Not Match 'Get-CompanyNames'
        $src | Should Match 'Get-LinkRules -Locations'
    }
}

Describe 'V6 "Archive, restore and delete" in the dev vault (in-memory OneNote, no Copilot; operator 2026-11-15)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    # As on the business tenant (STATUS P1c): a moved page gets a new page-id, so its old link opens nothing.
    $w.f | Add-Member NoteProperty MoveChangesLink $true
    $dev = [pscustomobject]@{ vault = $w.open.vault; lease = $w.open.lease; model = $w.open.model }
    $before = @($w.open.model.pages.Keys | Sort-Object) -join ','
    # The kit's OneNote window, standing in: it records the links followed and shows the page whose
    # link it is now, as desktop OneNote does (a moved page's old link shows nothing).
    $global:ObsnNav = New-Object System.Collections.Generic.List[string]
    $global:ObsnFake = $w.f
    $stub = New-Object psobject
    $stub | Add-Member ScriptMethod NavigateToUrl { param([string]$Url) $global:ObsnNav.Add($Url) }
    $stub | Add-Member ScriptMethod CurrentPageId {
        if (-not $global:ObsnNav.Count) { return '' }
        $u = $global:ObsnNav[$global:ObsnNav.Count - 1]
        foreach ($k in @($global:ObsnFake.Nodes.Keys)) { if ($global:ObsnFake.Nodes[$k].kind -eq 'Page' -and $global:ObsnFake.GetHyperlinkToObject($k) -eq $u) { return $k } }
        ''
    }
    $stub | Add-Member ScriptMethod NavigateTo { param([string]$Id) }
    $c = New-TestCtx -Flags @{ WriteTest = $true; NavWaitMs = 0 }
    $c.Shared.One = $stub
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevRetire $c $a $d } $c $w.a $dev
    It 'plans, archives, restores and deletes a page another page links to, then takes the linking page back out' {
        (@($c.Results | ForEach-Object { "$($_.name)=$($_.status)" }) -join ',') | Should Be 'Archive plan=OK,Archive=OK,Archive (link in another page)=OK,Restore=OK,Delete=OK,Archive, restore and delete (undo)=OK'
        $c.Results[0].detail | Should Match 'goes to Archive: yes; links to it counted: 1 \(expected 1\); refused 0; nothing written'
        $c.Results[1].detail | Should Match 'marked archived: yes; found again under Archive: yes'
        $c.Results[3].detail | Should Match 'back in its own section: yes; still marked archived: no'
        $c.Results[4].detail | Should Match 'out of the index: yes; links left in the linking page: 0; its text says deleted: yes'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
        (Find-FakePage $w.f 'Validation archive linker') | Should BeNullOrEmpty
    }
    It 'follows the link as it stands in the linking page''s text, once: Archive pointed it at the moved page' {
        $global:ObsnNav.Count | Should Be 1
        $global:ObsnNav[0] | Should Match '^onenote:'
        $c.Results[2].detail | Should Match 'opens the archived page: yes; its OneNote link changed: yes; the text points at the new link: yes; the text still has the old link: no; OneNote''s link now is the index''s: yes; the text points at OneNote''s link now: yes; the text''s link against OneNote''s: same page-id yes; same section-id yes; same address yes; short form no; base-path no; pages re-pointed: 1'
    }
    It 'logs statuses, counts and yes/no only: no page title, id or link' {
        $all = @(foreach ($x in $c.Results) { "$($x.name) $($x.detail)" }) -join ' '
        $all | Should Not Match 'Validation archive|onenote:|p\d|\{'
    }
    It 'says "not checked" when OneNote''s window cannot be asked, and is listed in the read-only plan' {
        $w2 = New-SyntheticVault
        $d2 = [pscustomobject]@{ vault = $w2.open.vault; lease = $w2.open.lease; model = $w2.open.model }
        $c2 = New-TestCtx -Flags @{ WriteTest = $true; NavWaitMs = 0 }
        $c2.Shared.One = New-Object psobject   # no NavigateToUrl
        & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevRetire $c $a $d } $c2 $w2.a $d2
        @($c2.Results | Where-Object { $_.name -eq 'Archive (link in another page)' })[0].status | Should Be 'INFO'
        $r = New-TestCtx
        & (Get-Module StageVault) { param($c, $a) Invoke-DevVaultChecks $c $a } $r $w2.a
        @($r.Results | Where-Object { $_.name -eq 'Archive, restore and delete' -and $_.status -eq 'SKIP' }).Count | Should Be 1
    }
    Remove-Variable -Name ObsnNav, ObsnFake -Scope Global -ErrorAction SilentlyContinue
}

Describe 'V6 "Upgrade move" in the dev vault (in-memory OneNote, no Copilot)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'Linker', 'LinkCapture', 'Ingest', 'Upgrade') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $dev = [pscustomobject]@{ vault = $w.open.vault; lease = $w.open.lease; model = $w.open.model }
    $c = New-TestCtx -Flags @{ WriteTest = $true }
    $before = @($w.open.model.pages.Keys | Sort-Object) -join ','
    & (Get-Module StageVault) { param($c, $a, $d) Invoke-DevUpgrade $c $a $d } $c $w.a $dev
    It 'moves a synthetic company-tenant link page to Internal links, then takes it back out' {
        $bad = @($c.Results | Where-Object { $_.status -ne 'OK' } | ForEach-Object { "$($_.name): $($_.status) $($_.detail)" })
        ($bad -join '; ') | Should Be ''
        (@($c.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Upgrade move,Upgrade move (undo)'
        $c.Results[0].detail | Should Match 'found again in Internal links: True'
        (@($w.open.model.pages.Keys | Sort-Object) -join ',') | Should Be $before
    }
    It 'reports the plan of a vault read only' {
        $c2 = New-TestCtx
        $x = [pscustomobject]@{ indexSectionId = $w.v.indexSectionId; vaultId = $w.v.vaultId; rootId = $w.v.rootId; kitAlias = 'Vault 1'; location = '' }
        $writes = $w.f.Writes.Count
        & (Get-Module StageVault) { param($c, $v, $a) Add-UpgradePlanResults $c $v $a } $c2 @($x) $w.a
        $c2.Results[0].detail | Should Match '^0 link page'
        $w.f.Writes.Count | Should Be $writes
    }
}

Describe 'V6 "Notebook reads" (in-memory OneNote; read only)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $nb = [string]$w.open.vault.notebookId
    $writes = $w.f.Writes.Count
    $run = {
        $c = New-TestCtx
        $vaults = @(Get-VaultList -Adapter $w.a)
        & (Get-Module StageVault) { param($c, $a, $v) Add-NotebookReadResults $c $a $v } $c $w.a $vaults
        $c
    }
    It 'shows "state page found: no" while the vault''s notebook is not selected and comes without Meta' {
        $w.f.Current = [string]$w.household
        $w.f.Hidden[$nb] = 'meta'
        $c = & $run
        (@($c.Results | ForEach-Object { $_.name }) -join ',') | Should Be 'Notebook reads,Reads of notebook #1,Reads of notebook #2'
        $c.Results[0].detail | Should Match '^2 notebooks open; the selected notebook is one of them \(said by the window\);'
        $v = @($c.Results | Where-Object { $_.detail -match '00 Index sections: 1' })
        $v.Count | Should Be 1
        $v[0].status | Should Be 'WARN'
        $v[0].detail | Should Match '^selected: no; sections: (\d+) read by notebook, \1 read with all notebooks; 00 Index sections: 1; their pages: \d+, with obsn Meta: 0; state page found: no; vaults listed in it: 0; \d+ ms$'
        $o = @($c.Results | Where-Object { $_.detail -match 'no 00 Index section listed' })[0]
        "$($o.status)|$($o.detail -replace '; \d+ ms$', '')" | Should Be 'INFO|selected: yes; sections: 1 read by notebook, 1 read with all notebooks; no 00 Index section listed; state page found: no; vaults listed in it: 0'
    }
    It 'asks the notebook list when the window says nothing, and says so (target machine, 2026-11-16)' {
        # An adapter whose window lists no window, while the notebook list marks the notebook in view.
        $global:ObsnInner = $w.a
        $global:ObsnViewed = [string]$w.household
        $s = New-Object psobject
        $s | Add-Member ScriptMethod GetCurrentNotebookId { '' }
        $s | Add-Member ScriptMethod GetHierarchy { param($Id, $Scope)
            $x = $global:ObsnInner.GetHierarchy($Id, $Scope)
            if ($Id) { return $x }
            [xml]$d = $x
            foreach ($n in @($d.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'Notebook' -and $_.GetAttribute('ID') -eq $global:ObsnViewed })) { $n.SetAttribute('isCurrentlyViewed', 'true') }
            $d.OuterXml
        }
        $c = New-TestCtx
        & (Get-Module StageVault) { param($c, $a, $v) Add-NotebookReadResults $c $a $v } $c $s @()
        $c.Results[0].detail | Should Match '^2 notebooks open; the selected notebook is one of them \(said by the notebook list\);'
        @($c.Results | Where-Object { $_.detail -match '^selected: yes;' }).Count | Should Be 1
        Remove-Variable -Name ObsnInner, ObsnViewed -Scope Global
    }
    It 'shows the notebook without its sections' {
        $w.f.Hidden[$nb] = 'sections'
        $c = & $run
        @($c.Results | Where-Object { $_.detail -match '^selected: no; sections: 0 read by notebook, 0 read with all notebooks; no 00 Index section listed; state page found: no' }).Count | Should Be 1
    }
    It 'shows "state page found: yes" while it is selected and answered in full' {
        $w.f.Hidden.Remove($nb)
        $w.f.Current = $nb
        $c = & $run
        $v = @($c.Results | Where-Object { $_.detail -match '00 Index sections: 1' })[0]
        $v.status | Should Be 'INFO'
        $v.detail | Should Match '^selected: yes; .*; their pages: (\d+), with obsn Meta: \1; state page found: yes; vaults listed in it: 1; '
    }
    It 'says so when the selected notebook cannot be read, and only reads: no write, nothing selected' {
        $w.f.Current = ''
        $c = & $run
        $c.Results[0].detail | Should Match 'the selected notebook is not known'
        @($c.Results | Where-Object { $_.detail -match '^selected: not known; ' }).Count | Should Be 2
        $w.f.Writes.Count | Should Be $writes
        $w.f.Navigations.Count | Should Be 0
        (Get-Content -LiteralPath (Join-Path $root 'validation\lib\StageVault.psm1') | Where-Object { $_ -match 'NavigateTo\(' }) | Should BeNullOrEmpty
    }
    It 'logs counts and yes/no only: no notebook name, id or address' {
        $c = & $run
        $all = (@($c.Results | ForEach-Object { "$($_.name) $($_.detail) $($_.hint)" }) -join ' ')
        $all | Should Not Match 'Synthetic|Household|example\.invalid|\{[A-Z]{2}-'
    }
}

Describe 'V6 -SelectNotebooks: each open notebook shown in turn, the vaults read each time (in-memory OneNote)' {
    foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore') { Import-Module (Join-Path $root "lib\$m.psm1") -Global }
    . (Join-Path $here 'SyntheticVault.ps1')
    $w = New-SyntheticVault
    $nb = [string]$w.open.vault.notebookId
    # The fault the probe looks for: the vault's pages come without Meta until its notebook is shown
    # (the in-memory OneNote reveals a notebook when it is navigated to).
    $w.f.Current = [string]$w.household
    $w.f.Hidden[$nb] = 'meta'
    $writes = $w.f.Writes.Count
    $vaults = @(Get-VaultList -Adapter $w.a)
    $c = New-TestCtx -Flags @{ SelectNotebooks = $true; NavWaitMs = 0 }
    $c.Shared.One = $w.f
    & (Get-Module StageVault) { param($c, $a, $v) Invoke-NotebookSelectionProbe $c $a $v } $c $w.a $vaults
    $lines = @($c.Results | Where-Object { $_.name -like 'Notebook selection*' })
    It 'shows each open notebook once and reads the vault each time' {
        $lines.Count | Should Be 2
        $w.f.Navigations.Count | Should Be 2
    }
    It 'flags the vault read while another notebook was shown, and passes once its own was shown' {
        (@($lines | ForEach-Object { $_.status }) -join ',') | Should Be 'WARN,OK'
        $lines[0].detail | Should Match 'state page found no'
        $lines[1].detail | Should Match 'state page found yes, sections (\d+) of \1, Index pages with Meta (\d+) of \2$'
    }
    It 'writes nothing and logs no notebook name, id or address' {
        $w.f.Writes.Count | Should Be $writes
        (@($c.Results | ForEach-Object { "$($_.name) $($_.detail)" }) -join ' ') | Should Not Match 'Synthetic|Household|example\.invalid|\{[A-Z]{2}-'
    }
    It 'does nothing without -SelectNotebooks' {
        $c2 = New-TestCtx -Flags @{ SelectNotebooks = $false }
        $nav = $w.f.Navigations.Count
        & (Get-Module StageVault) { param($c, $a) Invoke-NotebookSelectionProbe $c $a @() } $c2 $w.a
        $c2.Results.Count | Should Be 0
        $w.f.Navigations.Count | Should Be $nav
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
    It 'every .cmd of the kit is one ( ) block that ends with exit /b, with CRLF line endings' {
        $cmds = @(Get-ChildItem -LiteralPath $kit -Filter *.cmd -File)
        (@($cmds | ForEach-Object { $_.Name }) -contains 'Run Meeting Probe.cmd') | Should Be $true
        foreach ($c in $cmds) {
            $f = $c.FullName
            $lines = @([IO.File]::ReadAllLines($f) | Where-Object { $_.Trim() })
            $code = @($lines | Where-Object { $_.Trim() -notmatch '^(@echo off|rem\b)' })
            "$($c.Name): $($code[0].Trim()) .. $($code[-2].Trim()) $($code[-1].Trim())" | Should Be "$($c.Name): ( .. exit /b )"
            "$($c.Name): $([IO.File]::ReadAllText($f) -match "[^`r]`n")" | Should Be "$($c.Name): False"
        }
    }
    # The checks still open after the target machine's v0.12.4 run (operator, 2026-11-17: "if there are
    # items still to be confirmed then create a new scoped cmd for them"): Copilot, today's meetings, the
    # notebook selection probe and the write tests, nothing else. It is the one probe launcher that writes,
    # and only through -WriteTest (the test notebooks); V5 stays narrowed to P10, so no P3 marker page.
    It 'Run Open Checks.cmd runs only the open checks, asking nothing' {
        $run = @([IO.File]::ReadAllLines((Join-Path $kit 'Run Open Checks.cmd')) | Where-Object { $_ -match 'Run-Validation\.ps1' })
        $run.Count | Should Be 1
        $run[0].Trim().EndsWith('Run-Validation.ps1" -Stage V3,V5,V6 -Probe P10 -NoPrompt -MeetingDay today -WriteTest -SelectNotebooks %*') | Should Be $true
    }
    It 'Run Meeting Probe.cmd runs only the meetings probe, asking nothing' {
        $t = [IO.File]::ReadAllText((Join-Path $kit 'Run Meeting Probe.cmd'))
        $t | Should Match '-Stage V5 -Probe P10 -NoPrompt'
    }
    # One launcher per probe still to run on the target machine (operator, 2026-11-15: "provide cmd
    # files for them as well"): each runs exactly its own probe or stage, and never writes.
    It 'each probe launcher runs only its own probe or stage, and none of them writes' {
        $want = [ordered]@{
            'Run OneNote Search Probe.cmd' = '-Stage V5 -Probe P3 -NoPrompt %*'
            'Run Link Probes.cmd' = '-Stage V5 -Probe P7,P8 %*'
            'Run Loop Probe.cmd' = '-Stage V5 -Probe P4 %*'
            'Run Vault Check.cmd' = '-Stage V6 -NoCopilot -NoPrompt %*'
            'Run Meeting Probe.cmd' = '-Stage V5 -Probe P10 -NoPrompt -MeetingDay today %*'
            'Run Notebook Selection Probe.cmd' = '-Stage V6 -NoCopilot -NoPrompt -SelectNotebooks %*'
            'Run OneNote API Probe.cmd' = '-Stage V2 -NoCopilot -NoPrompt %*'
        }
        foreach ($name in $want.Keys) {
            $f = Join-Path $kit $name
            "${name}: $(Test-Path -LiteralPath $f)" | Should Be "${name}: True"
            $run = @([IO.File]::ReadAllLines($f) | Where-Object { $_ -match 'Run-Validation\.ps1' })
            "${name}: $($run.Count) $($run[0].Trim().EndsWith('Run-Validation.ps1" ' + $want[$name]))" | Should Be "${name}: 1 True"
            "${name}: $($run[0] -match '-WriteTest')" | Should Be "${name}: False"
        }
        # every name a launcher passes to -Probe is a probe of the kit
        foreach ($p in @($want.Values | ForEach-Object { if ($_ -match '-Probe (\S+)') { $Matches[1].Split(',') } })) { (Get-GroundingProbes) -contains $p | Should Be $true }
    }
    # Docs in step (code review 2026-11-15: -Probe and Run Meeting Probe.cmd shipped without a word
    # in AGENTS.md, the README or RB-03). What the kit offers is read from the kit itself.
    $tokens = $null; $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $kit 'Run-Validation.ps1'), [ref]$tokens, [ref]$errs)
    $params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $cmdNames = @(Get-ChildItem -LiteralPath $kit -Filter *.cmd -File | ForEach-Object { $_.Name })
    $agents = [IO.File]::ReadAllText((Join-Path $root 'AGENTS.md'))
    $people = (@([IO.File]::ReadAllText((Join-Path $root 'README.md'))) + @(Get-ChildItem -LiteralPath (Join-Path $root 'docs\runbooks') -Filter *.md | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })) -join "`n"
    $missingIn = {
        param([string]$Text)
        @(@($params | Where-Object { $Text -notmatch ('(?<![\w-])-' + [regex]::Escape($_) + '\b') } | ForEach-Object { "-$_" }) + @($cmdNames | Where-Object { $Text.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 }))
    }
    It 'finds the kit''s parameters and launchers to check' {
        ($params -contains 'Probe') | Should Be $true
        ($params.Count -ge 11) | Should Be $true
        ($cmdNames -contains 'Run Meeting Probe.cmd') | Should Be $true
    }
    It 'the README or a runbook names every parameter of Run-Validation.ps1 and every .cmd of the kit' {
        ((& $missingIn $people) -join ', ') | Should Be ''
    }
    It 'AGENTS.md names every parameter of Run-Validation.ps1 and every .cmd of the kit' {
        ((& $missingIn $agents) -join ', ') | Should Be ''
    }
    It 'the stage table and the options of RB-03 know P10 and -Probe' {
        $rb = [IO.File]::ReadAllText((Join-Path $root 'docs\runbooks\RB-03-run-validation.md'))
        $rb | Should Match '\| V5 Grounding \| Probes P3, P4, P7, P8 and P10'
        $rb | Should Match '\| `-Probe P10` \|'
        $rb | Should Match 'Run Meeting Probe\.cmd'
    }
    It 'ships in the release (validation is not a development folder)' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'tools\build-release.ps1'))
        $m = [regex]::Match($src, "foreach \(\`$dev in ([^)]+)\)")
        $m.Success | Should Be $true
        $m.Groups[1].Value | Should Not Match "'validation'"
    }
}
