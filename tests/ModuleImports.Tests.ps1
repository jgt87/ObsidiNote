# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# Every function a lib module calls must be visible inside that module when it is loaded on its own,
# as the server's runspace loads it. A test process that imports many modules makes their commands
# global and hides a missing Import-Module: on 2026-11-13 lib/Server.psm1 called Get-CompanyNames
# (lib/NotebookStructure.psm1) without importing it, the Server tests passed, and every Add would
# have failed in the real window. Each module is checked in a fresh runspace.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $here 'AstParse.ps1')
$lib = Join-Path $root 'lib'
# The validation kit's modules too: on 2026-11-14 its V6 Add step looked up Send-CopilotPrompt with
# Get-Command, but only StageCopilot.psm1 imported the bridge (a nested import StageVault cannot see).
$script:ModuleDirs = @($lib, (Join-Path $root 'validation\lib'))

function Get-ModuleFiles { foreach ($d in $script:ModuleDirs) { [IO.Directory]::EnumerateFiles($d, '*.psm1') } }

function Get-LibFunctionNames {
    $names = @{}
    foreach ($f in Get-ModuleFiles) {
        $ast = Read-ScriptAst -Path $f
        foreach ($d in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $names[$d.Name] = $true }
    }
    $names
}

function Get-LookedUpName($Command) {
    <# 'X' for `Get-Command X` (a bare name), unless the lookup is optional (-ErrorAction) or its
       function imports a module itself first (lazy -Global imports such as the server's bridge). #>
    if ($Command.GetCommandName() -ne 'Get-Command') { return '' }
    $els = @($Command.CommandElements)
    if ($els.Count -lt 2 -or $els[1] -isnot [Management.Automation.Language.StringConstantExpressionAst]) { return '' }
    # Optional only when a missing command is allowed: `-ErrorAction Stop` is a lookup that must
    # succeed (lib/Ask.psm1 New-AskCopilot failed that way in the kit's V6 Ask on the target machine,
    # 2026-11-16, while this test skipped it as optional).
    for ($i = 1; $i -lt $els.Count; $i++) {
        $e = $els[$i]
        if ($e -isnot [Management.Automation.Language.CommandParameterAst] -or $e.ParameterName -notlike 'ErrorAction*') { continue }
        $v = if ($e.Argument) { $e.Argument } elseif ($i + 1 -lt $els.Count) { $els[$i + 1] } else { $null }
        if (-not ($v -is [Management.Automation.Language.StringConstantExpressionAst] -and $v.Value -eq 'Stop')) { return '' }
    }
    $fn = $Command.Parent
    while ($fn -and $fn -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
    if ($fn -and @($fn.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module' }, $true)).Count) { return '' }
    $els[1].Value
}

function Get-CalledLibFunctions([string]$File, [hashtable]$LibNames) {
    $ast = Read-ScriptAst -Path $File
    $called = @{}
    foreach ($c in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true)) {
        foreach ($n in @($c.GetCommandName(), (Get-LookedUpName $c))) {
            if ($n -and $LibNames.ContainsKey($n)) { $called[$n] = $true }
        }
    }
    @($called.Keys | Sort-Object)
}

function Get-MissingCommands([string]$File, [string[]]$Names) {
    # A fresh runspace with the machine's module path (as tools/run-tests.ps1 sets it).
    $ps = [PowerShell]::Create()
    try {
        $null = $ps.AddScript({
            param($ModuleFile, $Wanted, $AppLib)
            $m = Import-Module $ModuleFile -PassThru -Force -WarningAction SilentlyContinue
            # A kit stage that loads app modules at run time (validation/lib/StageVault.psm1: the names
            # in $script:Needs, imported -Global so the kit runs on every version) gets them loaded the
            # same way first.
            $needs = @(& $m { if (Get-Variable -Name Needs -Scope Script -ErrorAction SilentlyContinue) { foreach ($v in $script:Needs.Values) { $v } } })
            foreach ($n in $needs) { Import-Module (Join-Path $AppLib "$n.psm1") -Global -WarningAction SilentlyContinue }
            & $m { param($w) @($w | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }) } $Wanted
        }).AddArgument($File).AddArgument($Names).AddArgument($lib)
        @($ps.Invoke())
    } finally { $ps.Dispose() }
}

Describe 'Each lib module imports what it calls' {
    $libNames = Get-LibFunctionNames
    foreach ($f in @(Get-ModuleFiles | Sort-Object)) {
        $name = $f.Substring($root.Length + 1)
        $called = @(Get-CalledLibFunctions $f $libNames)
        It "$name sees every lib function it calls when loaded alone" {
            ((Get-MissingCommands $f $called) -join ', ') | Should Be ''
        }
    }

    It 'catches a module that calls a function it does not import' {
        $tmp = Join-Path $env:TEMP ('obsn-imp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force $tmp
        try {
            $bad = Join-Path $tmp 'Bad.psm1'
            [IO.File]::WriteAllText($bad, "function Get-Thing { Get-CompanyNames -Locations @() }`nExport-ModuleMember -Function Get-Thing")
            ((Get-MissingCommands $bad @('Get-CompanyNames')) -join ',') | Should Be 'Get-CompanyNames'
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }
}
