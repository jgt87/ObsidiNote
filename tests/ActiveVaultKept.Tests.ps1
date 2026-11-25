# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The active vault is never demoted (D-035): a vault that the start or a switch
# opened stays the active, writable vault in every route while its notebook is open in OneNote, also
# when a later detection does not list it (OneNote answering the notebook without its sections, or
# its Index pages without their Meta: here simulated by the in-memory OneNote's .Hidden; what desktop
# OneNote really answers for a notebook that is not the selected one has not been seen live).
# lib/VaultSession.psm1 Join-ActiveVault (pure) and lib/Server.psm1 Get-VaultData. Synthetic data only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP ('obsidinote-test-data' + $(if ($env:OBSIDINOTE_TEST_TAG) { '-' + $env:OBSIDINOTE_TEST_TAG } else { '' }))
Import-Module (Join-Path $root 'lib\Server.psm1') -Force
foreach ($m in 'OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index', 'VaultSession', 'VaultStore', 'VaultSettings') { Import-Module (Join-Path $root "lib\$m.psm1") }
. (Join-Path $here 'FakeOneNote.ps1')
. (Join-Path $here 'SyntheticVault.ps1')

function New-TempAppRoot {
    $d = Join-Path $env:TEMP ('obsn-app-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'config')
    [IO.File]::WriteAllText((Join-Path $d 'config\obsidinote.json'), '{"notebook":""}')
    $d
}

# The server keeps the list for a few seconds; a test that changes OneNote asks for a fresh one.
function Reset-ServerList { & (Get-Module Server) { Reset-VaultCache } }

function Get-Api($State, [string]$Path, [string]$Query = '') { Reset-ServerList; Invoke-ApiRoute -Method 'GET' -Path $Path -Query $Query -State $State }
function Send-Api($State, [string]$Path, [string]$Body) { Reset-ServerList; Invoke-ApiRoute -Method 'POST' -Path $Path -Body $Body -State $State }

Describe 'Join-ActiveVault (pure)' {
    $rec = @{ vaultId = 'aaaaaaaa-0000-4000-8000-000000000001'; name = 'Mine'; rootId = 'N1'; rootKind = 'notebook'; notebookId = 'N1'; notebookName = 'Mine'; location = 'https://example.invalid/docs/Mine/'; indexSectionId = 'S1'; statePageId = 'P1' }
    $nb1 = [pscustomobject]@{ name = 'Mine'; id = 'N1'; location = 'https://example.invalid/docs/Mine/'; cloud = $true; structured = $false; vaultIds = @() }
    $nb2 = [pscustomobject]@{ name = 'Other'; id = 'N2'; location = 'https://example.invalid/docs/Other/'; cloud = $true; structured = $true; vaultIds = @('b2') }
    $other = [pscustomobject]@{ vaultId = 'b2'; name = 'Other'; rootId = 'N2'; rootKind = 'notebook'; notebookId = 'N2'; notebookName = 'Other'; location = ''; schema = 1; statePageId = 'P2'; indexSectionId = 'S2'; pages = 0; topics = 0 }
    It 'adds the active vault from its record when detection misses it and its notebook is open' {
        $j = Join-ActiveVault -Vaults @($other) -Notebooks @($nb1, $nb2) -Record $rec
        $j.kept | Should Be $true
        (@($j.vaults | ForEach-Object { $_.vaultId }) -join ',') | Should Be 'b2,aaaaaaaa-0000-4000-8000-000000000001'
        $v = @($j.vaults)[1]
        "$($v.rootId)|$($v.rootKind)|$($v.notebookId)|$($v.indexSectionId)|$($v.statePageId)|$($v.name)" | Should Be 'N1|notebook|N1|S1|P1|Mine'
        $n = @($j.notebooks | Where-Object { $_.id -eq 'N1' })[0]
        $n.structured | Should Be $true
        (@($n.vaultIds) -join ',') | Should Be 'aaaaaaaa-0000-4000-8000-000000000001'
        @($j.notebooks).Count | Should Be 2
        # the given objects are not changed
        $nb1.structured | Should Be $false
    }
    It 'keeps a section-group vault without calling its notebook a vault root' {
        $g = $rec.Clone(); $g.rootId = 'G1'; $g.rootKind = 'sectiongroup'
        $j = Join-ActiveVault -Vaults @() -Notebooks @($nb1) -Record $g
        $j.kept | Should Be $true
        @($j.notebooks)[0].structured | Should Be $false
        (@(@($j.notebooks)[0].vaultIds) -join ',') | Should Be $g.vaultId
    }
    It 'adds nothing when the vault is listed, its notebook is closed, there is no record, or OneNote shows another vault at that root' {
        $listed = [pscustomobject]@{ vaultId = $rec.vaultId; rootId = 'N1'; rootKind = 'notebook'; notebookId = 'N1' }
        (Join-ActiveVault -Vaults @($listed) -Notebooks @($nb1) -Record $rec).kept | Should Be $false
        @((Join-ActiveVault -Vaults @($listed) -Notebooks @($nb1) -Record $rec).vaults).Count | Should Be 1
        $closed = Join-ActiveVault -Vaults @($other) -Notebooks @($nb2) -Record $rec
        $closed.kept | Should Be $false
        @($closed.vaults).Count | Should Be 1
        (Join-ActiveVault -Vaults @($other) -Notebooks @($nb1, $nb2) -Record $null).kept | Should Be $false
        $replaced = [pscustomobject]@{ vaultId = 'c3'; rootId = 'N1'; rootKind = 'notebook'; notebookId = 'N1' }
        (Join-ActiveVault -Vaults @($replaced) -Notebooks @($nb1) -Record $rec).kept | Should Be $false
    }
}

foreach ($mode in 'sections', 'meta') {
    Describe "The active vault stays the active vault when OneNote answers its notebook without its $(if ($mode -eq 'sections') { 'sections' } else { 'pages'' Meta' })" {
        $w = New-SyntheticVault -SessionId 'server' -GuidIds
        $app = New-TempAppRoot
        $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
        $nbId = [string]$w.open.vault.notebookId
        $vid = [string]$w.v.vaultId
        $before = Get-Api $state '/api/notebooks'
        $pagesBefore = @((Get-Api $state '/api/graph').body.pages).Count
        # From here on OneNote holds the vault's notebook back, AFTER the vault was opened.
        $w.f.Hidden[$nbId] = $mode
        $writes = $w.f.Writes.Count
        It 'is what the test means: detection itself no longer lists the vault' {
            @(Get-VaultList -Adapter $w.a | Where-Object { $_.vaultId -eq $vid }).Count | Should Be 0
            @(Get-NotebookList -Adapter $w.a | Where-Object { $_.id -eq $nbId }).Count | Should Be 1
        }
        It 'GET /api/notebooks: the same entry, still a vault, still active, as the writer' {
            $r = Get-Api $state '/api/notebooks'
            $e = @($r.body.notebooks | Where-Object { $_.id -eq $nbId })
            $e.Count | Should Be 1
            "$($e[0].vault)|$($e[0].active)|$($e[0].vaultId)|$($e[0].kind)" | Should Be "True|True|$vid|notebook"
            $r.body.activeVaultId | Should Be $vid
            $r.body.mode | Should Be 'writer'
            @($r.body.notebooks).Count | Should Be @($before.body.notebooks).Count
            $e[0].name | Should Be @($before.body.notebooks | Where-Object { $_.id -eq $nbId })[0].name
        }
        It 'GET /api/graph by vault id, by the list id and without either: the active vault from the index in memory, writable' {
            foreach ($q in "vault=$vid", "notebook=$([Uri]::EscapeDataString($nbId))", '') {
                $g = Get-Api $state '/api/graph' $q
                # a source that is not read only carries no reason
                "$q -> $($g.status) $($g.body.source.kind) readOnly=$($g.body.source.readOnly) [$($g.body.source.readOnlyReason)] $($g.body.source.id)" | Should Be "$q -> 200 vault readOnly=False [] $vid"
                @($g.body.pages).Count | Should Be $pagesBefore
            }
        }
        It 'read only by the lease only: another writer makes it read only with reason lease' {
            $keep = $state.Lease
            $state.Lease = @{ mode = 'readonly'; sessionId = 'server'; holder = 'other'; expires = [datetime]::UtcNow.AddSeconds(90); acquired = [datetime]::UtcNow; holderHere = $false; statePageId = ''; indexSectionId = '' }
            $g = Get-Api $state '/api/graph' "notebook=$([Uri]::EscapeDataString($nbId))"
            "$($g.body.source.kind)|$($g.body.source.readOnly)|$($g.body.source.readOnlyReason)" | Should Be 'vault|True|lease'
            $state.Lease = $keep
        }
        It 'POST /api/export and GET /api/page/body read the active vault (three ways to name it)' {
            foreach ($b in '{"scope":"all"}', ('{"scope":"all","vault":"' + $vid + '"}'), ('{"scope":"all","notebook":"' + $nbId + '"}')) {
                $x = Send-Api $state '/api/export' $b
                "$($x.status) $($x.file.pages)" | Should Be "200 $pagesBefore"
            }
            foreach ($q in 'page=p1', "page=p1&vault=$vid", "page=p1&notebook=$([Uri]::EscapeDataString($nbId))") {
                $p = Get-Api $state '/api/page/body' $q
                "$q -> $($p.status) $($p.body.id)" | Should Be "$q -> 200 p1"
            }
        }
        It 'GET /api/notebook, /api/activity and /api/status still speak of the active vault' {
            $v = Get-Api $state '/api/notebook'
            "$($v.status)|$($v.body.notebook.vault)|$($v.body.notebook.active)|$($v.body.notebook.canSetUp)" | Should Be '200|True|True|False'
            $a = Get-Api $state '/api/activity'
            "$($a.status)|$($a.body.vaultId)|$($a.body.canChange)" | Should Be "200|$vid|True"
            $s = (Get-Api $state '/api/status').body.vault
            "$($s.vaultId)|$($s.mode)" | Should Be "$vid|writer"
        }
        It 'choosing it again is "already active", and it is never offered or taken for setting up' {
            $r = Send-Api $state '/api/active-vault' ('{"id":"' + $nbId + '"}')
            "$($r.status)|$($r.body.vaultId)|$($r.body.mode)" | Should Be "200|$vid|writer"
            $s = Send-Api $state '/api/vault/setup' ('{"id":"' + $nbId + '","confirm":true}')
            $s.status | Should Be 409
            $s.body.error | Should Match 'already holds'
            (Send-Api $state '/api/vault/new' ('{"name":"Inside","inNotebook":"' + $nbId + '","confirm":true}')).status | Should Be 409
        }
        It 'wrote nothing to OneNote and selected nothing in it' {
            $w.f.Writes.Count | Should Be $writes
            $w.f.Navigations.Count | Should Be 0
        }
        It 'lists the vault once when OneNote answers in full again' {
            $w.f.Hidden.Remove($nbId)
            $r = Get-Api $state '/api/notebooks'
            @($r.body.notebooks | Where-Object { $_.id -eq $nbId }).Count | Should Be 1
            @($r.body.notebooks | Where-Object { $_.vaultId -eq $vid }).Count | Should Be 1
            $w.f.Hidden[$nbId] = $mode
        }
        It 'does not keep a notebook that was closed in OneNote' {
            $null = $w.f.Roots.Remove($nbId)
            $r = Get-Api $state '/api/notebooks'
            @($r.body.notebooks | Where-Object { $_.id -eq $nbId -or $_.vaultId -eq $vid }).Count | Should Be 0
            $r.body.activeVaultId | Should Be ''
            (Get-Api $state '/api/graph' "vault=$vid").status | Should Be 404
            (Get-Api $state '/api/graph' "notebook=$([Uri]::EscapeDataString($nbId))").status | Should Be 404
            (Get-Api $state '/api/graph').status | Should Be 404
        }
        Remove-Item $app -Recurse -Force
    }
}

Describe 'Another vault and a connected notebook stay read only while the active vault is kept' {
    $w = New-SyntheticVault -SessionId 'server' -GuidIds
    $v2 = New-ObsidiVault -Adapter $w.a -Name 'Team Vault' -Location 'https://example.invalid/team' -Year 2026
    Set-OneNoteWriteRoot -Adapter $w.a -RootId $w.open.vault.rootId
    $app = New-TempAppRoot
    $state = New-ServerState -AppRoot $app -Port 8767 -TestAdapter $w.a -SessionId 'server' -Vault $w.open.vault -Lease $w.open.lease -Model $w.open.model
    $w.f.Hidden[[string]$w.open.vault.notebookId] = 'sections'
    It 'answers the other vault as not-active and the connected notebook as a notebook' {
        $g = Get-Api $state '/api/graph' "vault=$($v2.vaultId)"
        "$($g.status)|$($g.body.source.readOnly)|$($g.body.source.readOnlyReason)" | Should Be '200|True|not-active'
        $n = Get-Api $state '/api/graph' "notebook=$([Uri]::EscapeDataString($w.household))"
        "$($n.status)|$($n.body.source.kind)|$($n.body.source.readOnly)|$($n.body.source.readOnlyReason)" | Should Be '200|notebook|True|notebook'
    }
    It 'marks only the active vault as active in the list' {
        $r = Get-Api $state '/api/notebooks'
        (@($r.body.notebooks | Where-Object { $_.active } | ForEach-Object { $_.vaultId }) -join ',') | Should Be $w.v.vaultId
        @($r.body.notebooks | Where-Object { $_.vault }).Count | Should Be 2
    }
    Remove-Item $app -Recurse -Force
}
