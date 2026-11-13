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

$script:Needs = @{
    vault = @('OneNote', 'PageMeta', 'NotebookStructure', 'Vault', 'WriterLease', 'Index')
    add   = @('Linker', 'LinkCapture', 'Ingest', 'VaultStore')
    ask   = @('Ask', 'AskSources')
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
    foreach ($n in 'Vaults', 'Index completeness', 'Knowledge graph', 'Markdown export', 'Dev vault', 'Add and Undo', 'Check for the answer', 'Link it', 'Ask') { Add-ValidationResult $Ctx 'V6' 'SKIP' $n $Why }
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
    [pscustomobject]@{ vault = $record; lease = $lease; model = $model }
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
    $lease = $Dev.lease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = { $lease }.GetNewClosure(); AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok -or -not $Dev.model) { Add-ValidationResult $Ctx 'V6' 'FAIL' 'Add and Undo' "the store could not be made: $(if ($s.ok) { 'no index model' } else { $s.error })"; return }
    $store = $s.value
    $add = Measure-KitStep { Invoke-AddRequest -Request @{ text = $script:AddText; mode = 'add' } -Store $store -Ask $ask }
    $r = $add.value
    $st = "$(Get-KitProp $r 'status' 'error')"
    Add-ValidationResult $Ctx 'V6' $(if ($add.ok -and $st -eq 'added') { 'OK' } else { 'FAIL' }) 'Add (synthetic)' "status $st; $(@(Get-KitProp $r 'links' @()).Count) links, $(@(Get-KitProp $r 'chips' @()).Count) topics; $($add.ms) ms$(if (-not $add.ok) { "; $($add.error)" })"
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
    $lease = $Dev.lease
    $s = Measure-KitStep { Invoke-WithKnownParams $builder @{ Adapter = $Adapter; Vault = $Dev.vault; Model = $Dev.model; Lease = $lease; GetLease = { $lease }.GetNewClosure(); AppRoot = $Ctx.AppRoot } }
    if (-not $s.ok) { Add-ValidationResult $Ctx 'V6' 'FAIL' $name "the store could not be made: $($s.error)"; return }
    $store = $s.value
    $add = Measure-KitStep { Invoke-AddRequest -Request @{ text = $script:WaitText; mode = 'add' } -Store $store -Ask $askShort }
    $st = "$(Get-KitProp $add.value 'status' 'error')"
    $inboxId = "$(Get-KitProp $add.value 'inboxId' '')"
    if ($st -ne 'waiting' -or -not $inboxId) {
        $level = if ($st -eq 'added') { 'WARN' } else { 'FAIL' }
        Add-ValidationResult $Ctx 'V6' $level "$name (waiting)" "status $st instead of waiting; $($add.ms) ms$(if (-not $add.ok) { "; $($add.error)" })" $(if ($st -eq 'added') { 'Copilot answered within 1 s, so the waiting path was not reached; run the kit again.' } else { '' })
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
    $lease = $Dev.lease
    # The closure is made here, not inside Measure-KitStep's block: made there, it did not see $lease
    # when the kit ran under Pester (the store then reported "Read only").
    $getLease = { $lease }.GetNewClosure()
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
        foreach ($n in 'Dev vault', 'Add and Undo', 'Check for the answer', 'Link it', 'Ask') { Add-ValidationResult $Ctx 'V6' 'SKIP' $n 'write tests not run' 'Add -WriteTest; they write only into the notebook ObsidiNote-Validation.' }
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
    Add-IndexResults $Ctx $a.value $vaults
    Add-GraphResults $Ctx $a.value $vaults
    if (-not @(Get-MissingAppModules -AppRoot $Ctx.AppRoot -Names @('MarkdownExport')).Count) { Import-AppModules $Ctx.AppRoot @('MarkdownExport') }
    Add-ExportResults $Ctx $a.value $vaults
    Invoke-DevVaultChecks $Ctx $a.value
}

Export-ModuleMember -Function Invoke-StageVault, Get-MissingAppModules
