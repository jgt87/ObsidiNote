# V6 Vaults, index, knowledge graph, Add and Ask (build steps 2-5). Every check first looks for the
# modules it needs in lib\ and prints [SKIP] "not in this version yet" when one is missing, so the
# same kit runs on every version. Read only on the person's notebooks (vault list, index
# completeness, graph model counts). With -WriteTest it writes ONLY into the dev vault notebook
# ObsidiNote-Validation, through the app's own write guard (Set-OneNoteWriteRoot): it creates or
# continues that vault, writes its index, and runs an Add of a synthetic text with Undo, "Link it"
# between two synthetic pages (then both undone), and an Ask with a synthetic question. Counts and
# timings only. Keep this file ASCII.
Set-StrictMode -Version 2.0
$script:AppLib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib'
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
Import-Module (Join-Path $script:AppLib 'OneNoteHost.psm1')
Import-Module (Join-Path $PSScriptRoot 'StageCopilot.psm1')
# The bridge itself too: StageCopilot's import of it is nested and not visible here, so the Add steps'
# Get-Command Send-CopilotPrompt failed (V6 "Dev vault" FAIL on the target machine, 2026-11-14).
Import-Module (Join-Path $script:AppLib 'CopilotBridge.psm1')
# Get-KitOneNote: the kit's own OneNote object; Test-ProbeLinkOpens follows a link with it (the
# Archive write check).
Import-Module (Join-Path $PSScriptRoot 'StageOneNote.psm1')
Import-Module (Join-Path $PSScriptRoot 'WriteProbes.psm1')

$script:Needs = @{
    vault = @('OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index')
    add   = @('Linker', 'LinkCapture', 'Ingest', 'VaultStore')
    ask   = @('Ask', 'AskSources')
    # Loaded where they are used, and only when this version has them (tests/ModuleImports.Tests.ps1
    # reads every list here).
    later = @('GraphModel', 'MarkdownExport', 'Upgrade', 'VaultSettings')
}
# The functions that connect Add and Ask to OneNote (the store and source adapters,
# lib/VaultStore.psm1 and lib/AskSources.psm1). They are called with the arguments they declare.
$script:StoreBuilders = @('New-VaultStore')
$script:SourceBuilders = @('New-AskSource')
$script:GraphMax = 10
$script:AddText = 'Validation note: tidal gardens grow salt-tolerant crops where the sea reaches the land. Synthetic text from the validation kit.'
$script:AskText = 'What do my notes say about tidal gardens?'
$script:LinkText = 'https://example.org/'
$script:WaitText ='Validation note: salt marsh hay keeps garden beds moist and adds slow nutrients. Synthetic text from the validation kit (answer check).'

function Get-MissingAppModules {
    <# The module names (of $Names) that are not in <AppRoot>\lib. #>
    param([Parameter(Mandatory)][string]$AppRoot, [Parameter(Mandatory)][string[]]$Names)
    @($Names | Where-Object { -not (Test-Path -LiteralPath (Join-Path $AppRoot "lib\$_.psm1")) })
}

function Import-AppModules([string]$AppRoot, [string[]]$Names) {
    foreach ($n in $Names) { Import-Module (Join-Path $AppRoot "lib\$n.psm1") -Global }
}

function Get-KitProp($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    $Default
}

function Find-KitCommand([string[]]$Names) {
    foreach ($n in $Names) { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { return $c } }
    $null
}

function Invoke-WithKnownParams {
    <# Calls $Command with the arguments of $Available that it declares. #>
    param([Parameter(Mandatory)]$Command, [hashtable]$Available)
    $args2 = @{}
    foreach ($k in $Available.Keys) { if ($Command.Parameters.ContainsKey($k)) { $args2[$k] = $Available[$k] } }
    & $Command @args2
}

function Add-SkipAll($Ctx, [string]$Why) {
    foreach ($n in 'Vaults', 'Notebook reads', 'Index completeness', 'Upgrade plan', 'Vault settings', 'Knowledge graph', 'Markdown export', 'Dev vault', 'Add and Undo', 'Check for the answer', 'Link it', 'Undo of a linked page', 'Tags', 'Archive, restore and delete', 'Upgrade move', 'Ask') { Add-ValidationResult $Ctx 'V6' 'SKIP' $n $Why }
}

function Add-VaultResults($Ctx, $Adapter) {
    $v = Measure-KitStep { @(Get-VaultList -Adapter $Adapter) }
    if (-not $v.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Vaults' $v.error; return }
    $vaults = @($v.value)
    Add-ValidationResult $Ctx 'V6' 'OK' 'Vaults' "$($vaults.Count) found in $($v.ms) ms"
    $i = 0
    foreach ($x in $vaults) {
        $i++
        $nb = Register-ValidationName $Ctx 'notebook' "$($x.notebookName)"
        $where = if ("$($x.rootKind)" -eq 'sectiongroup') { $null = Register-ValidationName $Ctx 'name' "$($x.name)"; "a section group in $nb" } else { "the notebook $nb" }
        $x | Add-Member -Force NoteProperty kitAlias "Vault $i"
        Add-ValidationResult $Ctx 'V6' 'INFO' "Vault $i" "root: $where; schema $($x.schema); $($x.pages) pages, $($x.topics) topics on its state page"
    }
    # Each vault to the pipeline: the caller collects them with @().
    $vaults
}

function Get-KitSections($Node) {
    <# The Section elements below $Node that are not in the recycle bin. #>
    @($Node.SelectNodes(".//*[local-name()='Section']") | Where-Object { $_.GetAttribute('isInRecycleBin') -ne 'true' -and $_.ParentNode.GetAttribute('isRecycleBin') -ne 'true' })
}

function Get-NotebookReadFacts($Adapter, [string]$NotebookId, [xml]$AllDoc) {
    <# What OneNote answers for one open notebook, as counts (read only: GetHierarchy only, never
       NavigateTo): its sections read by the notebook's id and in the read of all notebooks, its
       `00 Index` sections (the notebook's own and those of its top-level section groups, as the app
       looks for vaults), their pages, how many carry obsn Meta, and whether a state page is found. #>
    [xml]$own = $Adapter.GetHierarchy($NotebookId, 3)
    $inAll = 0; $index = @()
    foreach ($n in @($AllDoc.DocumentElement.ChildNodes)) {
        if ($n.NodeType -ne 'Element' -or $n.GetAttribute('ID') -ne $NotebookId) { continue }
        $inAll = @(Get-KitSections $n).Count
        $roots = @($n) + @($n.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'SectionGroup' -and $_.GetAttribute('isRecycleBin') -ne 'true' })
        foreach ($r in $roots) { $index += @($r.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Section' -and $_.GetAttribute('name') -eq '00 Index' } | ForEach-Object { $_.GetAttribute('ID') }) }
    }
    $pages = 0; $withMeta = 0; $states = 0
    foreach ($id in $index) {
        $x = $Adapter.GetHierarchy($id, 4)
        [xml]$d = $x
        foreach ($p in @($d.SelectNodes("//*[local-name()='Page']"))) {
            $pages++
            if (@($p.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Meta' -and "$($_.GetAttribute('name'))".StartsWith('obsn.') }).Count) { $withMeta++ }
        }
        if (Find-StatePage $x) { $states++ }
    }
    [pscustomobject]@{ sections = @(Get-KitSections $own.DocumentElement).Count; sectionsInAll = $inAll; indexSections = @($index).Count; pages = $pages; withMeta = $withMeta; states = $states }
}

function Add-NotebookReadResults($Ctx, $Adapter, [object[]]$Vaults) {
    <# Read only (operator, 2026-11-15: pages of the vault showed "read only" while another notebook
       was the selected one in OneNote): per open notebook, what OneNote answers and whether it is the
       notebook OneNote shows now. Run it once with another notebook selected and once with the vault's
       notebook selected, and compare the "state page found" of the vault's notebook. Counts and yes/no
       only. It never selects a notebook itself. #>
    $cur = ''
    if ($Adapter.PSObject.Methods['GetCurrentNotebookId']) { try { $cur = [string]$Adapter.GetCurrentNotebookId() } catch { $cur = '' } }
    $all = Measure-KitStep { $x = $Adapter.GetHierarchy('', 3); [xml]$d = $x; $d }
    if (-not $all.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Notebook reads' $all.error; return }
    $nbs = @($all.value.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Notebook' })
    # OneNote's window can list no window at all (target machine, 2026-11-16: "not known" twice); the
    # hierarchy also marks the notebook in view (isCurrentlyViewed). Not yet seen on that machine, so
    # the line says which of the two answered.
    $from = 'the window'
    if (-not $cur) {
        $cur = [string](@($nbs | Where-Object { $_.GetAttribute('isCurrentlyViewed') -eq 'true' } | ForEach-Object { $_.GetAttribute('ID') }) | Select-Object -First 1)
        $from = 'the notebook list'
    }
    $isOpen = [bool](@($nbs | Where-Object { $_.GetAttribute('ID') -eq $cur }).Count)
    $shown = if (-not $cur) { 'not known' } elseif ($isOpen) { "one of them (said by $from)" } else { 'none of them' }
    # Never "OneNote:" in a line: the kit's masking reads that as the start of a onenote: link.
    Add-ValidationResult $Ctx 'V6' 'INFO' 'Notebook reads' "$($nbs.Count) notebooks open; the selected notebook is $shown; read in $($all.ms) ms (read only, nothing is selected)"
    foreach ($nb in @($nbs | Select-Object -First $script:GraphMax)) {
        $id = [string]$nb.GetAttribute('ID')
        $alias = Register-ValidationName $Ctx 'notebook' "$($nb.GetAttribute('name'))"
        $r = Measure-KitStep { Get-NotebookReadFacts $Adapter $id $all.value }
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V6' 'WARN' "Reads of $alias" $r.error; continue }
        $f = $r.value
        $sel = if (-not $cur) { 'not known' } else { Format-YesNo ($cur -eq $id) }
        $listed = @($Vaults | Where-Object { "$(Get-KitProp $_ 'notebookId' '')" -eq $id }).Count
        $detail = "selected: $sel; sections: $($f.sections) read by notebook, $($f.sectionsInAll) read with all notebooks; "
        if ($f.indexSections) {
            $found = Format-YesNo ($f.states -eq $f.indexSections)
            $detail += "00 Index sections: $($f.indexSections); their pages: $($f.pages), with obsn Meta: $($f.withMeta); state page found: $found$(if ($f.indexSections -gt 1) { " ($($f.states) of $($f.indexSections))" })"
        } else { $detail += 'no 00 Index section listed; state page found: no' }
        $detail += "; vaults listed in it: $listed; $($r.ms) ms"
        $odd = ($f.indexSections -and $f.states -ne $f.indexSections) -or ($f.sections -ne $f.sectionsInAll)
        Add-ValidationResult $Ctx 'V6' $(if ($odd) { 'WARN' } else { 'INFO' }) "Reads of $alias" $detail $(if ($odd) { 'Run this stage again with this notebook selected in OneNote and send both logs.' } else { '' })
    }
}

function Invoke-NotebookSelectionProbe($Ctx, $Adapter, [object[]]$Vaults) {
    <# -SelectNotebooks (Run Notebook Selection Probe.cmd; STATUS 29, operator 2026-11-16: "should a
       new probe be created"): does what OneNote answers for a vault depend on which notebook it shows?
       Shows each open notebook in turn (Select-KitNotebook: NavigateTo, writes nothing), then reads
       every vault's notebook as the app does (Get-NotebookReadFacts) and says per vault whether its
       state page and all its sections were found. Puts the page shown before back at the end. One line
       per notebook shown; counts and yes/no only. #>
    if (-not (Get-KitFlag $Ctx 'SelectNotebooks')) { return }
    $name = 'Notebook selection'
    $one = $null
    try { $one = Get-KitOneNote -Ctx $Ctx } catch { $one = $null }
    if (-not $one -or -not $one.PSObject.Methods['NavigateTo']) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'OneNote''s window cannot be asked to show a notebook'; return }
    $all = Measure-KitStep { $x = $Adapter.GetHierarchy('', 3); [xml]$d = $x; $d }
    if (-not $all.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name $all.error; return }
    $nbs = @($all.value.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Notebook' } | Select-Object -First $script:GraphMax)
    # Every notebook with a `00 Index` section or a vault, not only the vaults found at the start: a
    # vault that is not found while another notebook is shown is the very fault this probe looks for.
    $vaultNbs = @($nbs | Where-Object {
        $id = $_.GetAttribute('ID')
        @($Vaults | Where-Object { "$(Get-KitProp $_ 'notebookId' '')" -eq $id }).Count -or @(Get-KitSections $_ | Where-Object { $_.GetAttribute('name') -eq '00 Index' }).Count
    })
    if (-not $vaultNbs.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'no open notebook has a 00 Index section'; return }
    $before = Get-KitView $one
    $wait = [int](Get-KitFlag $Ctx 'NavWaitMs' 2000)
    try {
        foreach ($nb in $nbs) {
            $alias = Register-ValidationName $Ctx 'notebook' "$($nb.GetAttribute('name'))"
            if (-not (Select-KitNotebook -One $one -Id $nb.GetAttribute('ID') -WaitMs $wait)) { Add-ValidationResult $Ctx 'V6' 'WARN' "$name, $alias shown" 'OneNote did not show it'; continue }
            $now = Measure-KitStep { $x = $Adapter.GetHierarchy('', 3); [xml]$d = $x; $d }
            if (-not $now.ok) { Add-ValidationResult $Ctx 'V6' 'WARN' "$name, $alias shown" $now.error; continue }
            $viewed = Format-YesNo ([bool](@($now.value.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.GetAttribute('ID') -eq $nb.GetAttribute('ID') -and $_.GetAttribute('isCurrentlyViewed') -eq 'true' }).Count))
            $parts = @(); $bad = 0
            foreach ($v in $vaultNbs) {
                $valias = Register-ValidationName $Ctx 'notebook' "$($v.GetAttribute('name'))"
                $f = Measure-KitStep { Get-NotebookReadFacts $Adapter $v.GetAttribute('ID') $now.value }
                if (-not $f.ok) { $parts += "${valias}: not read"; $bad++; continue }
                $ok = $f.value.states -eq $f.value.indexSections -and $f.value.indexSections -gt 0 -and $f.value.sections -eq $f.value.sectionsInAll
                if (-not $ok) { $bad++ }
                $parts += "${valias}: state page found $(Format-YesNo ($f.value.states -eq $f.value.indexSections -and $f.value.indexSections -gt 0)), sections $($f.value.sections) of $($f.value.sectionsInAll), Index pages with Meta $($f.value.withMeta) of $($f.value.pages)"
            }
            Add-ValidationResult $Ctx 'V6' $(if ($bad) { 'WARN' } else { 'OK' }) "$name, $alias shown" "marked as in view: $viewed; $($parts -join '; ')" $(if ($bad) { 'A vault read differently while another notebook was shown: send this log back.' } else { '' })
        }
    } finally { Restore-KitView $one $before }
}

function Add-IndexResults($Ctx, $Adapter, [object[]]$Vaults) {
    if (-not $Vaults.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Index completeness' 'no vault open'; return }
    foreach ($x in $Vaults) {
        $nb = if ($x.PSObject.Properties['kitAlias']) { $x.kitAlias } else { Register-ValidationName $Ctx 'notebook' "$($x.notebookName)" }
        $r = Measure-KitStep {
            $m = Read-IndexModel -Adapter $Adapter -IndexSectionId $x.indexSectionId -VaultId "$($x.vaultId)" -RootId $x.rootId
            $t = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($x.rootId, 4)) -RootId $x.rootId
            [pscustomobject]@{ counts = (Get-IndexCounts -Model $m); missing = @(Test-IndexComplete -Model $m -Tree $t).Count }
        }
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' "Index of $nb" $r.error; continue }
        $c = $r.value.counts
        $status = if ($r.value.missing) { 'WARN' } else { 'OK' }
        Add-ValidationResult $Ctx 'V6' $status "Index of $nb" "load and check $($r.ms) ms; $($c.pages) pages, $($c.topics) topics, $($c.edges) links, $($c.unfiled) unfiled; pages missing from the index: $($r.value.missing)" $(if ($r.value.missing) { 'The next start adds missing pages to Unfiled (completeness rule).' } else { '' })
    }
}

function Add-GraphResults($Ctx, $Adapter, [object[]]$Vaults) {
    $list = Measure-KitStep { @(Get-NotebookList -Adapter $Adapter -Vaults $Vaults) }
    if (-not $list.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Knowledge graph' $list.error; return }
    foreach ($nb in @($list.value | Select-Object -First $script:GraphMax)) {
        $alias = Register-ValidationName $Ctx 'notebook' "$(Get-KitProp $nb 'name' '')"
        $g = Measure-KitStep {
            $m = Get-NotebookModel -Adapter $Adapter -NotebookId "$(Get-KitProp $nb 'id' '')" -NoLinks -Vaults $Vaults
            # The graph's own data (lib/GraphModel.psm1, GET /api/graph) when this version has it.
            if (Get-Command ConvertTo-GraphModel -ErrorAction SilentlyContinue) {
                $gm = ConvertTo-GraphModel -Model $m -Source @{ kind = 'notebook'; id = 'validation'; name = 'validation'; readOnly = $true }
                [pscustomobject]@{ pages = @(Get-KitProp $gm 'pages' @()).Count; topics = @(Get-KitProp $gm 'topics' @()).Count; edges = @(Get-KitProp $gm 'edges' @()).Count }
            } else {
                $edges = try { @(Get-IndexEdges -Model $m).Count } catch { '?' }
                [pscustomobject]@{ pages = $m.pages.Count; topics = $m.topics.Count; edges = $edges }
            }
        }
        if ($g.ok) { Add-ValidationResult $Ctx 'V6' 'INFO' "Graph of $alias" "$($g.value.pages) pages, $($g.value.topics) topics, $($g.value.edges) links; model built in $($g.ms) ms (read only)" }
        else { Add-ValidationResult $Ctx 'V6' 'WARN' "Graph of $alias" $g.error }
    }
}

function Test-GuardRefuses($Ctx, $Adapter, [string]$RootId) {
    <# The app's write guard refuses a section of every other open notebook (only its check runs). #>
    [xml]$nx = $Adapter.GetHierarchy('', 3)
    $tried = 0; $refused = 0
    foreach ($n in @($nx.DocumentElement.ChildNodes)) {
        if ($n.NodeType -ne 'Element' -or $n.GetAttribute('ID') -eq $RootId) { continue }
        $sec = @($n.SelectNodes(".//*[local-name()='Section']")) | Select-Object -First 1
        if (-not $sec) { continue }
        $tried++
        try { $Adapter.Assert($sec.GetAttribute('ID'), 'validation') } catch { $refused++ }
    }
    Add-ValidationResult $Ctx 'V6' $(if ($refused -eq $tried) { 'OK' } else { 'FAIL' }) 'Write guard' "refused $refused of $tried writes into other notebooks"
}

function Open-DevVault($Ctx, $Adapter) {
    <# Creates or continues the dev vault ObsidiNote-Validation and writes its index. Returns
       @{ vault; lease } or $null. #>
    $name = Get-DevNotebookName
    if (-not (Test-KitNameAllowed $name)) { throw "Write refused: '$name' is not the kit's dev vault." }
    $v = Measure-KitStep { Initialize-ObsidiNotebook -Adapter $Adapter -Name $name }
    if (-not $v.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Dev vault' $v.error; return $null }
    $vault = $v.value
    if ("$($Adapter.RootId)" -ne "$($vault.rootId)") { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Dev vault' 'the write root is not the dev vault: stopped'; return $null }
    Add-ValidationResult $Ctx 'V6' 'OK' 'Dev vault' "ObsidiNote-Validation $(if (Get-KitProp $vault 'vaultCreated' $false) { 'created' } else { 'continued' }); sections created $(@(Get-KitProp $vault 'created' @()).Count), present $(@(Get-KitProp $vault 'present' @()).Count); $($v.ms) ms"
    $again = Measure-KitStep { Initialize-ObsidiNotebook -Adapter $Adapter -Name $name }
    if ($again.ok) { Add-ValidationResult $Ctx 'V6' $(if (@(Get-KitProp $again.value 'created' @()).Count) { 'WARN' } else { 'OK' }) 'Dev vault again' "second run created $(@(Get-KitProp $again.value 'created' @()).Count) sections; same vault: $(Format-YesNo ("$(Get-KitProp $again.value 'vaultId' '')" -eq "$(Get-KitProp $vault 'vaultId' '')"))" }
    Test-GuardRefuses $Ctx $Adapter $vault.rootId
    $lease = Request-WriterLease -Adapter $Adapter -IndexSectionId $vault.indexSectionId -SessionId (New-WriterSessionId)
    $u = Measure-KitStep { Update-VaultIndex -Adapter $Adapter -RootId $vault.rootId -IndexSectionId $vault.indexSectionId -Lease $lease -VaultId "$($vault.vaultId)" }
    if ($u.ok) { Add-ValidationResult $Ctx 'V6' 'OK' 'Dev vault index' "lease $($lease.mode); $($u.value.model.pages.Count) pages; missing repaired $(@($u.value.missing).Count); $($u.ms) ms" }
    else { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Dev vault index' $u.error }
    $model = if ($u.ok) { $u.value.model } else { $null }
    $record = @{ vaultId = "$(Get-KitProp $vault 'vaultId' '')"; name = $name; rootId = "$($vault.rootId)"; indexSectionId = "$($vault.indexSectionId)" }
    [pscustomobject]@{ vault = $record; lease = $lease; model = $model; getLease = (New-DevLeaseGetter $Adapter "$($vault.indexSectionId)" $lease) }
}

function Get-DevGetLease($Dev) {
    <# The dev vault's lease getter (New-DevLeaseGetter); a dev record without one (the kit's tests
       build it from an in-memory vault) gets one that hands back its lease as it is. #>
    if ($Dev.PSObject.Properties['getLease'] -and $Dev.getLease) { return $Dev.getLease }
    $l = $Dev.lease
    { $l }.GetNewClosure()
}

function New-DevLeaseGetter($Adapter, [string]$IndexSectionId, $Lease) {
    <# The write steps' GetLease: the dev vault's lease, renewed with the same session when less than 60 s
       are left, as the app's start renews its lease every minute. The kit took it once and never
       renewed it: on the target machine (2026-11-17, v0.12.8) "Check for the answer" waited 92 s and
       every write step after it was refused as "Read only" (TTL 120 s). One holder for all steps, so a
       renewal is seen by every store. Made outside any Measure-KitStep block (see Invoke-DevLinkIt). #>
    $holder = @{ lease = $Lease }
    $req = Get-Command Request-WriterLease
    $a = $Adapter; $isid = $IndexSectionId
    {
        $l = $holder.lease
        if ($l -and $l.mode -eq 'writer' -and ([datetime]$l.expires).ToUniversalTime() -lt [datetime]::UtcNow.AddSeconds(60)) {
            try { $holder.lease = & $req -Adapter $a -IndexSectionId $isid -SessionId $l.sessionId } catch { }
        }
        $holder.lease
    }.GetNewClosure()
}

function Get-AddWhy($Step, [string]$Status, [string]$Expected) {
    <# '; <why>' for a result line when an Add did not end as $Expected: the error of a step that threw,
       else the Add result's own message (Add never throws; its status alone said "failed" without a
       reason on the target machine, 2026-11-16). '' when it went as expected. The line is masked. #>
    if (-not $Step.ok) { return "; $($Step.error)" }
    if ($Status -eq $Expected) { return '' }
    $m = "$(Get-KitProp $Step.value 'message' '')".Trim()
    if ($m) { "; $m" } else { '' }
}

function Invoke-DevAdd($Ctx, $Adapter, $Dev, $Bridge) {
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names $script:Needs.add)
    if ($miss.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Add and Undo' "not in this version yet ($($miss -join ', ') missing)"; return }
    Import-AppModules $Ctx.AppRoot $script:Needs.add
    $builder = Find-KitCommand $script:StoreBuilders
    if (-not $builder) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Add and Undo' 'not in this version yet (Add is not connected to OneNote)'; return }
    if (-not $Bridge) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Add and Undo' 'needs Copilot'; return }
    $send = Get-Command Send-CopilotPrompt
    $b = $Bridge
    $ask = { param($Prompt) $r = & $send -Bridge $b -Text $Prompt -TimeoutSec 240; if ("$($r.Result)" -ne 'Success') { throw "Copilot did not answer ($($r.Result))." }; "$($r.Text)" }.GetNewClosure()
    $getLease = Get-DevGetLease $Dev   # renewed while the steps run (New-DevLeaseGetter)
    $lease = & $getLease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = $getLease; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Add and Undo' "the store could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return }
    $store = $s.value
    $add = Measure-KitStep { Invoke-AddRequest -Request @{ text = $script:AddText; mode = 'add' } -Store $store -Ask $ask }
    $r = $add.value
    $st = "$(Get-KitProp $r 'status' 'error')"
    Add-ValidationResult $Ctx 'V6' $(if ($add.ok -and $st -eq 'added') { 'OK' } else { 'FAIL' }) 'Add (synthetic)' "status $st; $(@(Get-KitProp $r 'links' @()).Count) links, $(@(Get-KitProp $r 'chips' @()).Count) topics; $($add.ms) ms$(Get-AddWhy $add $st 'added')"
    $undo = Get-KitProp $r 'undo' $null
    if (-not $undo) { Add-ValidationResult $Ctx 'V6' 'WARN' 'Undo' 'the Add result has no undo record'; return }
    $u = Measure-KitStep { Undo-AddRequest -Store $store -Undo $undo }
    $ust = "$(Get-KitProp $u.value 'status' 'error')"
    Add-ValidationResult $Ctx 'V6' $(if ($u.ok -and $ust -eq 'undone') { 'OK' } else { 'FAIL' }) 'Undo' "status $ust; $($u.ms) ms"
}

function Invoke-DevAnswerCheck($Ctx, $Adapter, $Dev, $Bridge) {
    <# "Check for the answer": an Add of a second synthetic text with a wait so short that Copilot is
       still answering (the bridge leaves it running: Pending, no Stop), so the Intake item waits; then
       the check every 10 s (at most 3 minutes) until the page is filed, then Undo. Statuses and
       timings only. #>
    $name = 'Check for the answer'
    if (-not (Get-Command Receive-AddAnswer -ErrorAction SilentlyContinue) -or -not (Get-Command Read-CopilotChat -ErrorAction SilentlyContinue)) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet'; return }
    $builder = Find-KitCommand $script:StoreBuilders
    if (-not $builder -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet (Add is not connected to OneNote)'; return }
    if (-not $Bridge) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'needs Copilot'; return }
    $send = Get-Command Send-CopilotPrompt
    $read = Get-Command Read-CopilotChat
    $b = $Bridge
    # A 1-second wait forces the Pending path; the later steps (the check, linking) wait normally.
    $askShort = { param($Prompt) & $send -Bridge $b -Text $Prompt -TimeoutSec 1 -MaxTimeoutSec 1 -StallSec 0 -LeaveRunning -BusyWaitSec 120 }.GetNewClosure()
    $askNormal = { param($Prompt) & $send -Bridge $b -Text $Prompt -TimeoutSec 240 -StallSec 120 -LeaveRunning -BusyWaitSec 120 }.GetNewClosure()
    $readChat = { param($ChatUrl) & $read -Bridge $b -ChatUrl $ChatUrl }.GetNewClosure()
    $getLease = Get-DevGetLease $Dev   # renewed while the steps run (New-DevLeaseGetter)
    $lease = & $getLease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = $getLease; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the store could not be made: $($s.error)"; return }
    $store = $s.value
    $add = Measure-KitStep { Invoke-AddRequest -Request @{ text = $script:WaitText; mode = 'add' } -Store $store -Ask $askShort }
    $st = "$(Get-KitProp $add.value 'status' 'error')"
    $inboxId = "$(Get-KitProp $add.value 'inboxId' '')"
    if ($st -ne 'waiting' -or -not $inboxId) {
        $level = if ($st -eq 'added') { 'WARN' } else { 'FAIL' }
        Add-ValidationResult $Ctx 'V6' $level "$name (waiting)" "status $st instead of waiting; $($add.ms) ms$(Get-AddWhy $add $st 'waiting')" $(if ($st -eq 'added') { 'Copilot answered within 1 s, so the waiting path was not reached; run the kit again.' } else { '' })
        $u0 = Get-KitProp $add.value 'undo' $null
        if ($u0) { $null = Measure-KitStep { Undo-AddRequest -Store $store -Undo $u0 } }
        return
    }
    Add-ValidationResult $Ctx 'V6' 'OK' "$name (waiting)" "the item waits in the Intake; request reference given: $(Format-YesNo ([bool]"$(Get-KitProp $add.value 'ref' '')")); $($add.ms) ms"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tries = 0; $last = ''; $r = $null
    while ($sw.Elapsed.TotalSeconds -lt 180) {
        $tries++
        $c = Measure-KitStep { Receive-AddAnswer -Store $store -Ask $askNormal -ReadChat $readChat -InboxId $inboxId }
        $r = $c.value
        $last = if ($c.ok) { "$(Get-KitProp $r 'status' 'error')" } else { 'error' }
        Add-ValidationResult $Ctx 'V6' 'INFO' "$name (check $tries)" "status $last; $($c.ms) ms"
        if ($last -notin 'still-waiting') { break }
        $until = (Get-Date).AddSeconds(10); while ((Get-Date) -lt $until) { Start-Sleep -Milliseconds 250 }
    }
    $okFinal = $last -eq 'added'
    Add-ValidationResult $Ctx 'V6' $(if ($okFinal) { 'OK' } else { 'FAIL' }) $name "final status $last after $tries check(s), $([int]$sw.Elapsed.TotalSeconds) s" $(if (-not $okFinal) { 'Send this log back; the item stays in the Intake of ObsidiNote-Validation.' } else { '' })
    $undo = Get-KitProp $r 'undo' $null
    if ($okFinal -and $undo) {
        $u = Measure-KitStep { Undo-AddRequest -Store $store -Undo $undo }
        Add-ValidationResult $Ctx 'V6' $(if ($u.ok -and "$(Get-KitProp $u.value 'status' '')" -eq 'undone') { 'OK' } else { 'WARN' }) "$name (undo)" "status $(Get-KitProp $u.value 'status' 'error'); $($u.ms) ms"
    }
    Invoke-DevUpdateCheck $Ctx $store $askShort $askNormal $readChat
}

function Invoke-DevUpdateCheck($Ctx, $Store, $AskShort, $AskNormal, $ReadChat) {
    <# A slow link update waits too (user, 2026-11-13): the synthetic public link is added, its Update
       is sent with the 1-second wait (Pending: an Intake item "Update: ..." waits), then "Check for
       the answer" finishes it (Copilot must repeat the reference AND the link as "source"); then
       Undo of the link page. Statuses and timings only. #>
    $name = 'Update waits for the answer'
    $cmd = Get-Command Update-LinkSummary -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Parameters.ContainsKey('Resume')) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet'; return }
    $add = Measure-KitStep { Invoke-AddRequest -Request @{ text = $script:LinkText; mode = 'add' } -Store $Store -Ask $AskNormal }
    $st = "$(Get-KitProp $add.value 'status' 'error')"
    $page = Get-KitProp $add.value 'page' $null
    if ($st -ne 'added' -or -not $page) { Add-ValidationResult $Ctx 'V6' 'FAIL' "$name (link added)" "status $st; $($add.ms) ms$(if (-not $add.ok) { "; $($add.error)" })"; return }
    Add-ValidationResult $Ctx 'V6' 'OK' "$name (link added)" "$($add.ms) ms"
    try {
        $up = Measure-KitStep { Update-LinkSummary -Store $Store -Ask $AskShort -Id "$(Get-KitProp $page 'id' '')" }
        $ust = "$(Get-KitProp $up.value 'status' 'error')"
        $inboxId = "$(Get-KitProp $up.value 'inboxId' '')"
        if ($ust -ne 'waiting' -or -not $inboxId) { Add-ValidationResult $Ctx 'V6' $(if ($ust -in 'updated', 'unchanged') { 'WARN' } else { 'FAIL' }) "$name (waiting)" "status $ust instead of waiting; $($up.ms) ms"; return }
        Add-ValidationResult $Ctx 'V6' 'OK' "$name (waiting)" "the update waits in the Intake; $($up.ms) ms"
        $sw = [Diagnostics.Stopwatch]::StartNew(); $tries = 0; $last = ''
        while ($sw.Elapsed.TotalSeconds -lt 180) {
            $tries++
            $c = Measure-KitStep { Receive-AddAnswer -Store $Store -Ask $AskNormal -ReadChat $ReadChat -InboxId $inboxId }
            $last = if ($c.ok) { "$(Get-KitProp $c.value 'status' 'error')" } else { 'error' }
            Add-ValidationResult $Ctx 'V6' 'INFO' "$name (check $tries)" "status $last; $($c.ms) ms"
            if ($last -ne 'still-waiting') { break }
            $until = (Get-Date).AddSeconds(10); while ((Get-Date) -lt $until) { Start-Sleep -Milliseconds 250 }
        }
        $ok = $last -in 'updated', 'unchanged', 'kept', 'could-not-update'
        Add-ValidationResult $Ctx 'V6' $(if ($ok) { 'OK' } else { 'FAIL' }) $name "final status $last after $tries check(s), $([int]$sw.Elapsed.TotalSeconds) s" $(if ($last -eq 'mismatch') { 'Copilot did not repeat the reference or the link; send this log back.' } else { '' })
    } finally {
        $undo = Get-KitProp $add.value 'undo' $null
        if ($undo) { $u = Measure-KitStep { Undo-AddRequest -Store $Store -Undo $undo }; Add-ValidationResult $Ctx 'V6' $(if ("$(Get-KitProp $u.value 'status' '')" -eq 'undone') { 'OK' } else { 'WARN' }) "$name (undo)" "status $(Get-KitProp $u.value 'status' 'error'); $($u.ms) ms" }
    }
}

function Add-ExportResults($Ctx, $Adapter, [object[]]$Vaults) {
    <# Markdown export of every vault, read only: the files are built in memory and dropped; only the
       page count, unreadable pages, size and time are logged. Nothing is saved. #>
    if (-not (Get-Command New-MarkdownExport -ErrorAction SilentlyContinue)) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Markdown export' 'not in this version yet'; return }
    if (-not $Vaults.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Markdown export' 'no vault open'; return }
    $read = { param($Id) $Adapter.GetPageContent($Id) }.GetNewClosure()
    foreach ($x in $Vaults) {
        $nb = if ($x.PSObject.Properties['kitAlias']) { $x.kitAlias } else { 'a vault' }
        $r = Measure-KitStep {
            $m = Read-IndexModel -Adapter $Adapter -IndexSectionId $x.indexSectionId -VaultId "$($x.vaultId)" -RootId $x.rootId
            $e = New-MarkdownExport -Model $m -ReadPage $read -SourceName 'validation' -Scope all
            if ($e.ContainsKey('error')) { [pscustomobject]@{ pages = 0; failed = 0; kb = 0 } } else { [pscustomobject]@{ pages = $e.pages; failed = $e.failed; kb = [int]($e.bytes.Length / 1024) } }
        }
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' "Markdown export of $nb" $r.error; continue }
        Add-ValidationResult $Ctx 'V6' $(if ($r.value.failed) { 'WARN' } else { 'OK' }) "Markdown export of $nb" "$($r.value.pages) pages, $($r.value.failed) unreadable, $($r.value.kb) KB zip, $($r.ms) ms (in memory, not saved)"
    }
}

function New-DevLinkPage($Store, [string]$Title) {
    <# One synthetic page of the kit in the dev vault (no Copilot): id, page, index entry. #>
    $id = [string](& $Store.NewId)
    $page = @{ id = $id; type = 'note'; bucket = (& $Store.BucketForType -Type 'note'); title = $Title; summary = 'Synthetic page of the validation kit.'; topics = @(); aliases = @(); links = @(); status = ''; outlines = @(@{ role = 'body'; lines = @('Synthetic page of the validation kit.') }) }
    $cp = & $Store.CreatePage -Page $page
    $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']
    $null = & $Store.IndexAddPage -Page $page
    @{ id = $id; pageId = $page.pageId }
}

function Invoke-DevLinkIt($Ctx, $Adapter, $Dev) {
    <# "Link it" (lib/Ingest.psm1 Add-PageLink, POST /api/link/add): two synthetic pages of the kit,
       one linked to the other, the same link again (already linked), then both pages back out
       (Undo: OneNote's Deleted Pages, out of the index). No Copilot. Statuses and timings only. #>
    $name = 'Link it'
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names $script:Needs.add)
    if ($miss.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name "not in this version yet ($($miss -join ', ') missing)"; return }
    Import-AppModules $Ctx.AppRoot $script:Needs.add
    $builder = Find-KitCommand $script:StoreBuilders
    if (-not $builder -or -not (Get-Command Add-PageLink -ErrorAction SilentlyContinue)) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet'; return }
    # The getter is made outside Measure-KitStep's block (New-DevLeaseGetter): a closure made inside it
    # did not see the function's variables, and the store then reported "Read only".
    $getLease = Get-DevGetLease $Dev
    $lease = & $getLease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = $getLease; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the store could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return }
    $store = $s.value
    $a = $null; $b = $null
    try {
        $mk = Measure-KitStep { New-DevLinkPage $store 'Validation link source' }
        if ($mk.ok) { $a = $mk.value; $mk2 = Measure-KitStep { New-DevLinkPage $store 'Validation link target' }; if ($mk2.ok) { $b = $mk2.value } else { $mk = $mk2 } }
        if (-not $a -or -not $b) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the two test pages could not be made: $($mk.error)"; return }
        $l = Measure-KitStep { Add-PageLink -Store $store -From $a.id -To $b.id }
        $st = "$(Get-KitProp $l.value 'status' 'error')"
        Add-ValidationResult $Ctx 'V6' $(if ($l.ok -and $st -eq 'linked') { 'OK' } else { 'FAIL' }) $name "status $st; backlinks $(Get-KitProp $l.value 'backlinks' 0); $($l.ms) ms (two test pages made in $($mk.ms) ms)"
        $again = Measure-KitStep { Add-PageLink -Store $store -From $b.id -To $a.id }
        $st2 = "$(Get-KitProp $again.value 'status' 'error')"
        Add-ValidationResult $Ctx 'V6' $(if ($again.ok -and $st2 -eq 'already-linked') { 'OK' } else { 'FAIL' }) "$name again" "status $st2 (expected already-linked); $($again.ms) ms"
    } finally {
        $done = 0; $tried = 0
        # The source first, so the target's "Linked from" is rewritten without it; then the target.
        $undos = @()
        if ($a) { $undos += , @{ id = $a.id; pageId = $a.pageId; targets = @($(if ($b) { $b.id } else { @() })) } }
        if ($b) { $undos += , @{ id = $b.id; pageId = $b.pageId; targets = @() } }
        foreach ($rec in $undos) {
            $tried++
            $u = Measure-KitStep { Undo-AddRequest -Store $store -Undo $rec }
            if ($u.ok -and "$(Get-KitProp $u.value 'status' '')" -eq 'undone') { $done++ }
        }
        if ($tried) { Add-ValidationResult $Ctx 'V6' $(if ($done -eq $tried) { 'OK' } else { 'WARN' }) "$name (undo)" "$done of $tried test pages back out (OneNote's Deleted Pages)" }
    }
}

function New-DevStore($Ctx, $Adapter, $Dev, [string]$Name, [string]$NeedsCommand) {
    <# The dev vault's store for a write step without Copilot, or $null with the SKIP/FAIL line written. #>
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names $script:Needs.add)
    if ($miss.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' $Name "not in this version yet ($($miss -join ', ') missing)"; return $null }
    Import-AppModules $Ctx.AppRoot $script:Needs.add
    $builder = Find-KitCommand $script:StoreBuilders
    if (-not $builder -or -not (Get-Command $NeedsCommand -ErrorAction SilentlyContinue)) { Add-ValidationResult $Ctx 'V6' 'SKIP' $Name 'not in this version yet'; return $null }
    $getLease = Get-DevGetLease $Dev   # renewed while the steps run (New-DevLeaseGetter)
    $lease = & $getLease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = $getLease; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' $Name "the store could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return $null }
    $s.value
}

function New-DevLinkedPair($Store, $Dev, [string]$TargetTitle, [string]$LinkerTitle) {
    <# Two synthetic pages of the kit: a target, and a linker with a link to it in its Meta and as a
       link in its own text. Returns @{ target = @{ id; pageId }; linker = @{ id; pageId }; link }
       (link: the target's OneNote link as written into the linker's text). #>
    $t = New-DevLinkPage $Store $TargetTitle
    $link = [string]$Dev.model.pages[$t.id].link
    $i = [string](& $Store.NewId)
    $line = @{ parts = @(@{ text = 'Synthetic page of the validation kit, see '; href = '' }, @{ text = 'the target'; href = $link }) }
    $page = @{ id = $i; type = 'note'; bucket = (& $Store.BucketForType -Type 'note'); title = $LinkerTitle; summary = 'Synthetic page of the validation kit.'; topics = @(); aliases = @(); links = @(@{ target = $t.id; strength = 2; why = 'validation kit' }); status = ''; outlines = @(@{ role = 'body'; lines = @($line) }) }
    $cp = & $Store.CreatePage -Page $page
    $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']
    $null = & $Store.IndexAddPage -Page $page
    @{ target = $t; linker = @{ id = $i; pageId = $page.pageId }; link = $link }
}

function Get-KitBodyLink($Adapter, [string]$PageId) {
    <# The address of the first link in a page's own body outline (obsn.role = body), decoded; '' when
       there is none or the page cannot be read. Read only. #>
    try { [xml]$d = $Adapter.GetPageContent($PageId) } catch { return '' }
    foreach ($o in @($d.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'Outline' })) {
        $role = @($o.ChildNodes | Where-Object { $_.LocalName -eq 'Meta' -and $_.GetAttribute('name') -eq 'obsn.role' } | ForEach-Object { $_.GetAttribute('content') }) | Select-Object -First 1
        if ($role -ne 'body') { continue }
        $m = [regex]::Match($o.InnerText, '(?is)<a\b[^>]*?\bhref\s*=\s*"([^"]*)"')
        if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) }
    }
    ''
}

function Invoke-DevRetire($Ctx, $Adapter, $Dev) {
    <# Archive, Restore and Delete (lib/Ingest.psm1 Get-RetirePlan, Invoke-PageRetire; operator
       2026-11-15): a synthetic target page and a page that links to it (Meta and its own text). The
       target is archived (found again under Archive; then the link in the other page's text is
       followed in OneNote: does it still open the moved page? STATUS P1c says a moved page gets a new
       id), restored to its own section, and deleted (out of the index; the other page's link becomes
       "(deleted: ...)"). Then the linking page goes back out. No Copilot. Statuses, counts, yes/no. #>
    $name = 'Archive, restore and delete'
    $store = New-DevStore $Ctx $Adapter $Dev $name 'Invoke-PageRetire'
    if (-not $store) { return }
    $a = $null; $b = $null
    try {
        $mk = Measure-KitStep { New-DevLinkedPair $store $Dev 'Validation archive target' 'Validation archive linker' }
        if (-not $mk.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the two test pages could not be made: $($mk.error)"; return }
        $a = $mk.value.linker; $b = $mk.value.target
        $homeSection = [string]$Dev.model.pages[$b.id].section   # never $home: $HOME is an automatic variable

        $plan = Measure-KitStep { Get-RetirePlan -Store $store -Action 'archive' -Ids @($b.id) }
        $pp = @(Get-KitProp $plan.value 'pages' @())
        $to = if ($pp.Count) { "$($pp[0]['to'])" } else { '' }
        $okPlan = $plan.ok -and $pp.Count -eq 1 -and $to -like 'Archive*' -and [int]$pp[0]['inbound'] -eq 1
        Add-ValidationResult $Ctx 'V6' $(if ($okPlan) { 'OK' } else { 'FAIL' }) 'Archive plan' "pages $($pp.Count); goes to Archive: $(Format-YesNo ($to -like 'Archive*')); links to it counted: $(if ($pp.Count) { $pp[0]['inbound'] } else { 0 }) (expected 1); refused $(@(Get-KitProp $plan.value 'refused' @()).Count); nothing written; $($plan.ms) ms"

        $ar = Measure-KitStep { Invoke-PageRetire -Store $store -Action 'archive' -Ids @($b.id) }
        $rec = $Dev.model.pages[$b.id]
        $found = $false
        if ($rec) {
            $t = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($Dev.vault.rootId, 4)) -RootId $Dev.vault.rootId
            $found = @($t.sections | Where-Object { $_.full -eq $rec.section } | ForEach-Object { $_.pages } | Where-Object { $_.id -eq $rec.oneNoteId -and $_.meta['obsn.id'] -eq $b.id }).Count -eq 1
        }
        $okAr = $ar.ok -and "$(Get-KitProp $ar.value 'status' '')" -eq 'done' -and $rec -and $rec.status -eq 'archived' -and $rec.section -like 'Archive*' -and $found
        Add-ValidationResult $Ctx 'V6' $(if ($okAr) { 'OK' } else { 'FAIL' }) 'Archive' "status $(Get-KitProp $ar.value 'status' 'error'); marked archived: $(Format-YesNo ($rec -and $rec.status -eq 'archived')); found again under Archive: $(Format-YesNo $found); page id changed: $(Format-YesNo ($rec -and $rec.oneNoteId -ne $b.pageId)); $($ar.ms) ms"

        # A link to the page in another page's own text, after the move (STATUS 7d, P1c): the link as it
        # stands in that text now (Archive points it at the new link since 2026-11-16), not the old one.
        if ($rec) {
            # Following the link selects a page in OneNote: that lives in WriteProbes (write tests only),
            # never in this module, whose read-only checks select nothing (RB-05 step 3a).
            $now = Get-KitBodyLink $Adapter $a.pageId
            $opens = if ($now) { Test-ProbeLinkOpens -One (Get-KitOneNote -Ctx $Ctx) -Url $now -PageId $rec.oneNoteId -WaitMs ([int](Get-KitFlag $Ctx 'NavWaitMs' 1500)) } else { 'no link found' }
            $st = if ($opens -eq 'yes') { 'OK' } elseif ($opens -eq 'no') { 'FAIL' } else { 'INFO' }
            # The link OneNote gives the page now, read again (2026-11-17: the text pointed at another
            # link than the index's, which did not open the page): yes/no only, the log holds no links.
            $fresh = try { [string]$Adapter.GetHyperlinkToObject([string]$rec.oneNoteId) } catch { '' }
            $detail = "the link in the linking page's text opens the archived page: $opens; its OneNote link changed: $(Format-YesNo ($rec.link -ne $mk.value.link)); the text points at the new link: $(Format-YesNo ($now -and $now -eq $rec.link)); the text still has the old link: $(Format-YesNo ($now -and $now -eq $mk.value.link)); OneNote's link now is the index's: $(Format-YesNo ($fresh -and $fresh -eq $rec.link)); the text points at OneNote's link now: $(Format-YesNo ($fresh -and $now -eq $fresh)); pages re-pointed: $(Get-KitProp $ar.value 'relinked' 0)"
            Add-ValidationResult $Ctx 'V6' $st 'Archive (link in another page)' $detail $(if ($opens -eq 'no') { 'Send this log back: Archive should point links in other pages at the moved page.' } else { '' })
        }

        $re = Measure-KitStep { Invoke-PageRetire -Store $store -Action 'restore' -Ids @($b.id) }
        $rec = $Dev.model.pages[$b.id]
        $okRe = $re.ok -and "$(Get-KitProp $re.value 'status' '')" -eq 'done' -and $rec -and -not $rec.status -and $rec.section -eq $homeSection
        Add-ValidationResult $Ctx 'V6' $(if ($okRe) { 'OK' } else { 'FAIL' }) 'Restore' "status $(Get-KitProp $re.value 'status' 'error'); back in its own section: $(Format-YesNo ($rec -and $rec.section -eq $homeSection)); still marked archived: $(Format-YesNo ($rec -and $rec.status -eq 'archived')); $($re.ms) ms"

        $de = Measure-KitStep { Invoke-PageRetire -Store $store -Action 'delete' -Ids @($b.id) }
        $gone = -not $Dev.model.pages.Contains($b.id)
        if ($gone) { $b = $null }
        $pg = Measure-KitStep { & $store.ReadPage -PageId $a.pageId }
        $left = -1; $says = $false
        if ($pg.ok) {
            $left = @(@($pg.value.meta['links']) | Where-Object { $_ -and $_['target'] -eq $mk.value.target.id }).Count
            $body = @($pg.value.outlines | Where-Object { $_.role -eq 'body' }) | Select-Object -First 1
            $says = [bool]($body -and "$($body.text)" -match '\(deleted: ')
        }
        $okDe = $de.ok -and "$(Get-KitProp $de.value 'status' '')" -eq 'done' -and $gone -and $left -eq 0 -and $says
        Add-ValidationResult $Ctx 'V6' $(if ($okDe) { 'OK' } else { 'FAIL' }) 'Delete' "status $(Get-KitProp $de.value 'status' 'error'); out of the index: $(Format-YesNo $gone); links left in the linking page: $left; its text says deleted: $(Format-YesNo $says); $($de.ms) ms (to OneNote's Deleted Pages)"
    } finally {
        $done = 0; $tried = 0
        foreach ($rec in @($a, $b | Where-Object { $_ })) {
            $tried++
            $cur = if ($Dev.model.pages.Contains($rec.id)) { [string]$Dev.model.pages[$rec.id].oneNoteId } else { $rec.pageId }
            $x = Measure-KitStep { Undo-AddRequest -Store $store -Undo @{ id = $rec.id; pageId = $cur; targets = @() } }
            if ($x.ok -and "$(Get-KitProp $x.value 'status' '')" -eq 'undone') { $done++ }
        }
        if ($tried) { Add-ValidationResult $Ctx 'V6' $(if ($done -eq $tried) { 'OK' } else { 'WARN' }) "$name (undo)" "$done of $tried test pages back out (OneNote's Deleted Pages)" }
    }
}

function Invoke-DevUndoLinked($Ctx, $Adapter, $Dev) {
    <# Undo of a page that another page links to (lib/Ingest.psm1 Undo-AddRequest): two synthetic
       pages, the first with a link to the second in its Meta and as a link in its own text. After
       Undo of the second, the first has no link to it left (Meta) and its text says "(deleted: ...)"
       in place of the link. Then the first goes back out too. No Copilot. Counts and statuses only. #>
    $name = 'Undo of a linked page'
    $store = New-DevStore $Ctx $Adapter $Dev $name 'Undo-AddRequest'
    if (-not $store) { return }
    if ((Get-IngestStoreContract) -notcontains 'RewriteBodyLinks') { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet'; return }
    $a = $null; $b = $null
    try {
        $mk = Measure-KitStep { New-DevLinkedPair $store $Dev 'Validation undo target' 'Validation undo linker' }
        if (-not $mk.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the two test pages could not be made: $($mk.error)"; return }
        $a = $mk.value.linker; $b = $mk.value.target
        $u = Measure-KitStep { Undo-AddRequest -Store $store -Undo @{ id = $b.id; pageId = $b.pageId; targets = @() } }
        $st = "$(Get-KitProp $u.value 'status' 'error')"
        if ($st -eq 'undone') { $b = $null }
        $pg = Measure-KitStep { & $store.ReadPage -PageId $a.pageId }
        $left = -1; $says = $false
        if ($pg.ok) {
            $left = @(@($pg.value.meta['links']) | Where-Object { $_ -and $_['target'] -eq $mk.value.target.id }).Count
            $body = @($pg.value.outlines | Where-Object { $_.role -eq 'body' }) | Select-Object -First 1
            $says = [bool]($body -and "$($body.text)" -match '\(deleted: ')
        }
        $ok = $u.ok -and $st -eq 'undone' -and $left -eq 0 -and $says
        Add-ValidationResult $Ctx 'V6' $(if ($ok) { 'OK' } else { 'FAIL' }) $name "status $st; unlinked $(Get-KitProp $u.value 'unlinked' 0); text rewritten on $(Get-KitProp $u.value 'rewritten' 0) page(s); links left in the linking page: $left; its text says deleted: $says; $($u.ms) ms"
    } finally {
        $done = 0; $tried = 0
        foreach ($rec in @($a, $b | Where-Object { $_ })) {
            $tried++
            $x = Measure-KitStep { Undo-AddRequest -Store $store -Undo @{ id = $rec.id; pageId = $rec.pageId; targets = @() } }
            if ($x.ok -and "$(Get-KitProp $x.value 'status' '')" -eq 'undone') { $done++ }
        }
        if ($tried) { Add-ValidationResult $Ctx 'V6' $(if ($done -eq $tried) { 'OK' } else { 'WARN' }) "$name (undo)" "$done of $tried test pages back out (OneNote's Deleted Pages)" }
    }
}

function Invoke-DevTags($Ctx, $Adapter, $Dev) {
    <# Tags, set by hand (lib/Ingest.psm1 Set-PageTags, Rename-Tag): a synthetic page gets a tag, the
       page is read back, the tag is renamed, then removed; then the page goes back out. No Copilot.
       The log holds counts and yes/no only, never a tag's text. #>
    $name = 'Tags'
    $store = New-DevStore $Ctx $Adapter $Dev $name 'Set-PageTags'
    if (-not $store) { return }
    $p = $null
    try {
        $mk = Measure-KitStep { New-DevLinkPage $store 'Validation tag page' }
        if (-not $mk.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the test page could not be made: $($mk.error)"; return }
        $p = $mk.value
        $first = 'validation kit tag'; $second = 'validation kit tag 2'
        $read = { @(@((& $store.ReadPage -PageId $p.pageId).meta['tags']) | Where-Object { $_ }) }
        $t1 = Measure-KitStep { Set-PageTags -Store $store -Ids @($p.id) -Add @($first) }
        $on = @(& $read)
        $ok1 = $t1.ok -and "$(Get-KitProp $t1.value 'status' '')" -eq 'tagged' -and $on.Count -eq 1 -and $on[0] -eq $first
        Add-ValidationResult $Ctx 'V6' $(if ($ok1) { 'OK' } else { 'FAIL' }) $name "status $(Get-KitProp $t1.value 'status' 'error'); pages changed $(Get-KitProp $t1.value 'changed' 0); tags read back from the page: $($on.Count); $($t1.ms) ms"
        $t2 = Measure-KitStep { Rename-Tag -Store $store -From $first -To $second }
        $on = @(& $read)
        $ok2 = $t2.ok -and "$(Get-KitProp $t2.value 'status' '')" -eq 'renamed' -and $on.Count -eq 1 -and $on[0] -eq $second
        Add-ValidationResult $Ctx 'V6' $(if ($ok2) { 'OK' } else { 'FAIL' }) "$name (rename)" "status $(Get-KitProp $t2.value 'status' 'error'); pages changed $(Get-KitProp $t2.value 'changed' 0); the page has the new name: $([bool]($on.Count -eq 1 -and $on[0] -eq $second)); $($t2.ms) ms"
        $t3 = Measure-KitStep { Set-PageTags -Store $store -Ids @($p.id) -Remove @($second) }
        $on = @(& $read)
        $ok3 = $t3.ok -and "$(Get-KitProp $t3.value 'status' '')" -eq 'tagged' -and $on.Count -eq 0
        Add-ValidationResult $Ctx 'V6' $(if ($ok3) { 'OK' } else { 'FAIL' }) "$name (remove)" "status $(Get-KitProp $t3.value 'status' 'error'); tags left on the page: $($on.Count); $($t3.ms) ms"
    } finally {
        if ($p) {
            $x = Measure-KitStep { Undo-AddRequest -Store $store -Undo @{ id = $p.id; pageId = $p.pageId; targets = @() } }
            Add-ValidationResult $Ctx 'V6' $(if ($x.ok -and "$(Get-KitProp $x.value 'status' '')" -eq 'undone') { 'OK' } else { 'WARN' }) "$name (undo)" "status $(Get-KitProp $x.value 'status' 'error') (OneNote's Deleted Pages)"
        }
    }
}

function Get-DevBodyLineCount($Adapter, [string]$PageId) {
    <# The top-level lines of a page's body outline (obsn.role = body): one per journal entry. #>
    [xml]$d = $Adapter.GetPageContent($PageId)
    $ns = New-Object Xml.XmlNamespaceManager $d.NameTable
    $ns.AddNamespace('one', $d.DocumentElement.NamespaceURI)
    foreach ($o in @($d.DocumentElement.SelectNodes('one:Outline', $ns))) {
        $r = $o.SelectSingleNode('one:Meta[@name="obsn.role"]', $ns)
        if ($r -and $r.GetAttribute('content') -eq 'body') { return @($o.SelectNodes('one:OEChildren/one:OE', $ns)).Count }
    }
    -1
}

function Invoke-DevJournal($Ctx, $Adapter, $Dev) {
    <# The journal's day page (2026-11-17, one page per day): two Adds typed as journal entries go into
       one page for today, the second is added to that page's text in OneNote, Undo takes out only the
       second, then the first (the day page goes to Deleted Pages). Copilot is not needed here: its two
       replies are fixed synthetic text, so what is checked is OneNote keeping the day page right. Only
       in ObsidiNote-Validation. Counts and statuses only. #>
    $name = 'Journal day page'
    $store = New-DevStore $Ctx $Adapter $Dev $name 'Undo-AddRequest'
    if (-not $store) { return }
    if (-not $store.ContainsKey('JournalEntry')) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name 'not in this version yet'; return }
    $replies = @(
        '{"title": "Validation entry one", "summary": "Synthetic journal entry of the validation kit.", "type": "log", "topics": [{"new": "Validation kit"}], "links": [], "aliases": [], "intent": "add"}',
        '{"title": "Validation entry two", "summary": "Second synthetic journal entry of the validation kit.", "type": "log", "topics": [{"new": "Validation kit"}], "links": [], "aliases": [], "intent": "add"}'
    )
    $q = @{ n = 0 }
    $ask = { param($Prompt) $r = $replies[$q.n]; $q.n++; $r }.GetNewClosure()
    $a = $null; $b = $null
    try {
        $s1 = Measure-KitStep { Invoke-AddRequest -Request @{ text = 'Validation entry one. Synthetic text from the validation kit.'; mode = 'add' } -Store $store -Ask $ask }
        $a = $s1.value
        $s2 = Measure-KitStep { Invoke-AddRequest -Request @{ text = 'Validation entry two. Synthetic text from the validation kit.'; mode = 'add' } -Store $store -Ask $ask }
        $b = $s2.value
        $sameDay = $s1.ok -and $s2.ok -and $a -and $b -and "$(Get-KitProp $a 'status' '')" -eq 'added' -and "$(Get-KitProp $b 'status' '')" -eq 'added' -and $a.page.id -eq $b.page.id
        $lines = if ($sameDay) { Get-DevBodyLineCount $Adapter ([string]$b.undo.pageId) } else { -1 }
        Add-ValidationResult $Ctx 'V6' $(if ($sameDay -and $lines -eq 2) { 'OK' } else { 'FAIL' }) $name "two entries on one day page: $(Format-YesNo $sameDay); entry lines in its text: $lines (expected 2); $($s1.ms + $s2.ms) ms$(if (-not $sameDay) { "; $(Get-KitProp $b 'message' (Get-KitProp $a 'message' ''))" })"
        if (-not $sameDay) { return }
        $u2 = Measure-KitStep { Undo-AddRequest -Store $store -Undo $b.undo }
        $left = Get-DevBodyLineCount $Adapter ([string]$b.undo.pageId)
        $ok2 = $u2.ok -and "$(Get-KitProp $u2.value 'status' '')" -eq 'undone' -and $left -eq 1
        Add-ValidationResult $Ctx 'V6' $(if ($ok2) { 'OK' } else { 'FAIL' }) "$name (undo one entry)" "status $(Get-KitProp $u2.value 'status' 'error'); entry lines left: $left (expected 1); $($u2.ms) ms$(if (-not $ok2) { "; $(Get-KitProp $u2.value 'message' '')" })"
        $b = $null
    } finally {
        foreach ($x in @($b, $a)) {
            if (-not $x -or -not $x.undo) { continue }
            $u = Measure-KitStep { Undo-AddRequest -Store $store -Undo $x.undo }
            Add-ValidationResult $Ctx 'V6' $(if ($u.ok -and "$(Get-KitProp $u.value 'status' '')" -eq 'undone') { 'OK' } else { 'WARN' }) "$name (undo)" "status $(Get-KitProp $u.value 'status' 'error') (the last entry: the day page to OneNote's Deleted Pages)"
        }
    }
}

function Invoke-DevUpgrade($Ctx, $Adapter, $Dev) {
    <# The upgrade's page move (lib/Upgrade.psm1, lib/VaultStore.psm1 MovePage; probes/p9-move.ps1):
       a synthetic link page with a company-tenant address, filed under Web links as an older version
       did, is moved to Internal links by Invoke-VaultUpgrade; then it goes back out (Undo). Only in
       ObsidiNote-Validation. Statuses and timings only. #>
    $name = 'Upgrade move'
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names (@($script:Needs.add) + 'Upgrade'))
    if ($miss.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' $name "not in this version yet ($($miss -join ', ') missing)"; return }
    Import-AppModules $Ctx.AppRoot (@($script:Needs.add) + 'Upgrade')
    $builder = Find-KitCommand $script:StoreBuilders
    $getLease = Get-DevGetLease $Dev   # renewed while the steps run (New-DevLeaseGetter)
    $lease = & $getLease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = $getLease; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the store could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return }
    $store = $s.value
    $id = ''
    try {
        $mk = Measure-KitStep {
            $i = [string](& $store.NewId)
            $url = 'https://validation-kit.service-now.com/kb_view.do?sysparm_article=KB0000001'
            $page = @{ id = $i; type = 'link-web'; bucket = 'Web links'; title = 'Validation upgrade page'; summary = 'Synthetic page of the validation kit.'; topics = @(); aliases = @(); links = @(); status = ''; url = $url; host = 'validation-kit.service-now.com'; outlines = @(@{ role = 'body'; lines = @('Synthetic page of the validation kit.') }) }
            $cp = & $store.CreatePage -Page $page
            $page.pageId = [string]$cp['pageId']; $page.link = [string]$cp['link']; $page.section = [string]$cp['section']
            $null = & $store.IndexAddPage -Page $page
            $i
        }
        if (-not $mk.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the test page could not be made: $($mk.error)"; return }
        $id = $mk.value
        $u = Measure-KitStep { Invoke-VaultUpgrade -Store $store }
        $rec = $Dev.model.pages[$id]
        $ok = $u.ok -and "$(Get-KitProp $u.value 'status' '')" -eq 'done' -and $rec.section -eq 'Internal links' -and $rec.type -eq 'link-internal'
        $found = $false
        if ($ok) { $t = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($Dev.vault.rootId, 4)) -RootId $Dev.vault.rootId; $found = @($t.sections | Where-Object { $_.full -eq 'Internal links' } | ForEach-Object { $_.pages } | Where-Object { $_.id -eq $rec.oneNoteId -and $_.meta['obsn.id'] -eq $id }).Count -eq 1 }
        Add-ValidationResult $Ctx 'V6' $(if ($ok -and $found) { 'OK' } else { 'FAIL' }) $name "status $(Get-KitProp $u.value 'status' 'error'); moved $(Get-KitProp $u.value 'moved' 0) of $(Get-KitProp $u.value 'planned' 0); found again in Internal links: $found; $($u.ms) ms$(if (-not $u.ok) { "; $($u.error)" })"
    } finally {
        if ($id -and $Dev.model.pages.Contains($id)) {
            $rec = $Dev.model.pages[$id]
            $un = Measure-KitStep { Undo-AddRequest -Store $store -Undo @{ id = $id; pageId = $rec.oneNoteId; targets = @() } }
            Add-ValidationResult $Ctx 'V6' $(if ($un.ok -and "$(Get-KitProp $un.value 'status' '')" -eq 'undone') { 'OK' } else { 'WARN' }) "$name (undo)" "status $(Get-KitProp $un.value 'status' 'error') (OneNote's Deleted Pages)"
        }
    }
}

function Add-UpgradePlanResults($Ctx, [object[]]$Vaults, $Adapter) {
    <# Read only: per vault, how many pages the next start's upgrade would move (lib/Upgrade.psm1). #>
    if (@(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names @('Upgrade', 'VaultStore', 'Ingest', 'Linker', 'LinkCapture')).Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Upgrade plan' 'not in this version yet'; return }
    Import-AppModules $Ctx.AppRoot @('Linker', 'LinkCapture', 'Ingest', 'VaultStore', 'Upgrade')
    foreach ($x in $Vaults) {
        $nb = if ($x.PSObject.Properties['kitAlias']) { $x.kitAlias } else { 'a vault' }
        $r = Measure-KitStep {
            $m = Read-IndexModel -Adapter $Adapter -IndexSectionId $x.indexSectionId -VaultId "$($x.vaultId)" -RootId $x.rootId
            # The one place the link rules are put together (lib/NotebookStructure.psm1), as the start does.
            $names = @((Get-LinkRules -Locations @([string](Get-KitProp $x 'location' ''))).CompanyNames)
            , @(Get-UpgradePlan -Model $m -CompanyNames $names)
        }
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V6' 'WARN' "Upgrade plan of $nb" $r.error; continue }
        $all = @($r.value)
        $p = @($all | Where-Object { $_.step -eq 'link-bucket' })
        $weak = @($all | Where-Object { $_.step -eq 'link-strength' }).Count
        $toIn = @($p | Where-Object { $_.to -eq 'Internal links' }).Count
        Add-ValidationResult $Ctx 'V6' 'INFO' "Upgrade plan of $nb" "$($p.Count) link page(s) to move ($toIn to Internal links, $($p.Count - $toIn) to Web links); $weak page(s) with your own links to set to related; the next start of ObsidiNote does it"
    }
}

function Add-SettingsResults($Ctx, [object[]]$Vaults, $Adapter) {
    <# Read only: per vault, which of its settings are in OneNote (lib/VaultSettings.psm1); the next
       start of ObsidiNote adds the missing ones with their defaults. Key names only, no values. #>
    if (@(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names @('VaultSettings')).Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Vault settings' 'not in this version yet'; return }
    Import-AppModules $Ctx.AppRoot @('VaultSettings')
    foreach ($x in $Vaults) {
        $nb = if ($x.PSObject.Properties['kitAlias']) { $x.kitAlias } else { 'a vault' }
        $r = Measure-KitStep {
            $st = Get-VaultState -Adapter $Adapter -IndexSectionId $x.indexSectionId
            Get-VaultSettingsPlan -Stored (ConvertFrom-SettingsValue ([string]$st.meta['obsn.settings']))
        }
        if (-not $r.ok) { Add-ValidationResult $Ctx 'V6' 'WARN' "Settings of $nb" $r.error; continue }
        $all = @((Get-VaultSettingDefaults).Keys).Count
        $miss = @($r.value.added)
        $bad = @($r.value.invalid)
        $detail = "$($all - $miss.Count) of $all in OneNote" + $(if ($miss.Count) { "; missing: $($miss -join ', ') (the next start adds them with their defaults)" } else { '' }) + $(if ($bad.Count) { "; not usable: $($bad -join ', ') (kept, defaults used)" } else { '' })
        Add-ValidationResult $Ctx 'V6' $(if ($bad.Count) { 'WARN' } else { 'INFO' }) "Settings of $nb" $detail
    }
}

function Invoke-DevAsk($Ctx, $Adapter, $Dev, $Bridge) {
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names $script:Needs.ask)
    if ($miss.Count) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Ask' "not in this version yet ($($miss -join ', ') missing)"; return }
    Import-AppModules $Ctx.AppRoot $script:Needs.ask
    $builder = Find-KitCommand $script:SourceBuilders
    if (-not $builder) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Ask' 'not in this version yet (Ask is not connected to OneNote)'; return }
    if (-not $Bridge) { Add-ValidationResult $Ctx 'V6' 'SKIP' 'Ask' 'needs Copilot'; return }
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Id = $Dev.vault.vaultId; Name = $Dev.vault.name; Kind = 'vault'; AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Ask' "the source could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return }
    $source = $s.value
    $a = Measure-KitStep { Invoke-AskRequest -Request @{ question = $script:AskText; action = 'ask' } -Context @{ Sources = @($source); Copilot = (New-AskCopilot -Bridge $Bridge) } }
    $r = $a.value
    $ok = $a.ok -and (Get-KitProp $r 'ok' $false)
    Add-ValidationResult $Ctx 'V6' $(if ($ok) { 'OK' } else { 'FAIL' }) 'Ask (synthetic)' "status $(Get-KitProp $r 'status' 'error'); $(@(Get-KitProp $r 'sources' @()).Count) sources cited; writes $(Get-KitProp $r 'writes' '?'); $($a.ms) ms$(if (-not $a.ok) { "; $($a.error)" })"
}

function Invoke-DevVaultChecks($Ctx, $Adapter) {
    if (-not (Get-KitFlag $Ctx 'WriteTest')) {
        foreach ($n in 'Dev vault', 'Add and Undo', 'Check for the answer', 'Link it', 'Undo of a linked page', 'Tags', 'Journal day page', 'Archive, restore and delete', 'Upgrade move', 'Ask') { Add-ValidationResult $Ctx 'V6' 'SKIP' $n 'write tests not run' 'Add -WriteTest; they write only into the notebook ObsidiNote-Validation.' }
        return
    }
    $dev = $null
    try {
        $dev = Open-DevVault $Ctx $Adapter
        if (-not $dev) { return }
        $bridge = $null
        if (-not (Get-KitFlag $Ctx 'NoCopilot')) { $bridge = Connect-KitCopilot -Ctx $Ctx -Stage 'V6' }
        Invoke-DevAdd $Ctx $Adapter $dev $bridge
        Invoke-DevAnswerCheck $Ctx $Adapter $dev $bridge
        Invoke-DevLinkIt $Ctx $Adapter $dev
        Invoke-DevUndoLinked $Ctx $Adapter $dev
        Invoke-DevTags $Ctx $Adapter $dev
        Invoke-DevJournal $Ctx $Adapter $dev
        Invoke-DevRetire $Ctx $Adapter $dev
        Invoke-DevUpgrade $Ctx $Adapter $dev
        Invoke-DevAsk $Ctx $Adapter $dev $bridge
    } catch { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Dev vault' $_.Exception.Message }
    finally { if ($dev -and $dev.lease) { try { $null = Clear-WriterLease -Adapter $Adapter -Lease $dev.lease } catch { } } }
}

function Invoke-StageVault {
    param([Parameter(Mandatory)]$Ctx)
    $miss = @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names $script:Needs.vault)
    if ($miss.Count) { Add-SkipAll $Ctx "not in this version yet ($($miss -join ', ') missing)"; return }
    if ((Get-OneNoteState) -eq 'none') { Add-SkipAll $Ctx 'OneNote is not running'; return }
    Import-AppModules $Ctx.AppRoot $script:Needs.vault
    if (-not @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names @('GraphModel')).Count) { Import-AppModules $Ctx.AppRoot @('GraphModel') }
    $a = Measure-KitStep { Get-OneNoteAdapter }
    if (-not $a.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'OneNote adapter' $a.error; return }
    $vaults = @(Add-VaultResults $Ctx $a.value)
    Add-NotebookReadResults $Ctx $a.value $vaults
    Invoke-NotebookSelectionProbe $Ctx $a.value $vaults
    Add-IndexResults $Ctx $a.value $vaults
    Add-UpgradePlanResults $Ctx $vaults $a.value
    Add-SettingsResults $Ctx $vaults $a.value
    Add-GraphResults $Ctx $a.value $vaults
    if (-not @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names @('MarkdownExport')).Count) { Import-AppModules $Ctx.AppRoot @('MarkdownExport') }
    Add-ExportResults $Ctx $a.value $vaults
    Invoke-DevVaultChecks $Ctx $a.value
}

Export-ModuleMember -Function Invoke-StageVault, Get-MissingAppModules
