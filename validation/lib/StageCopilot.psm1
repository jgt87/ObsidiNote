# V3 Copilot: the Edge profile's account type and single sign-on (read from Edge's files), then
# Microsoft 365 Copilot in ObsidiNote's own Edge window: connect, one harmless prompt
# ("Reply with exactly: OK-<random>") and a check of the reply, with timings. Never waits for a
# sign-in: when one is needed it says so and stops. Neither the prompt nor the reply is logged.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.
Set-StrictMode -Version 2.0
$script:AppLib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib'
Import-Module (Join-Path $PSScriptRoot 'ValidationCore.psm1')
foreach ($m in 'AppConfig', 'Cdp', 'Sso', 'Startup', 'CopilotBridge') { Import-Module (Join-Path $script:AppLib "$m.psm1") }

function Get-ProfileFacts {
    <# The Edge profile's account type, single sign-on and the device's join state (yes/no fields). #>
    param([Parameter(Mandatory)]$Ctx)
    $cs = Get-CopilotSettings -AppRoot $Ctx.AppRoot
    $join = Get-DeviceJoinStatus
    $account = Get-ProfileAccount -ProfileDir $cs.profileDir
    $sso = Get-ProfileSsoState -ProfileDir $cs.profileDir -Join $join -Account $account
    [pscustomobject]@{ account = $account; sso = $sso; join = $join; forced = [bool](Test-EdgeForcedSignIn); mode = (Get-CopilotSignInMode -AppRoot $Ctx.AppRoot); port = $cs.cdpPort }
}

function Add-ProfileResult($Ctx, $Facts) {
    $j = @(foreach ($k in 'AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'AzureAdPrt') { "$k $($Facts.join[$k])" }) -join ', '
    $status = if ($Facts.forced -and $Facts.account -ne 'work') { 'WARN' } elseif ($Facts.sso -eq 'off') { 'WARN' } else { 'OK' }
    $hint = if ($Facts.forced -and $Facts.account -ne 'work') { 'Start ObsidiNote once and sign in to Edge with your work account (runbook RB-02).' } elseif ($Facts.sso -eq 'off') { 'Run sso-setup.cmd once (runbook RB-02).' } else { '' }
    Add-ValidationResult $Ctx 'V3' $status 'Edge profile' "account: $($Facts.account); SSO $($Facts.sso); sign-in setting: $($Facts.mode); Edge sign-in required: $(Format-YesNo $Facts.forced); device: $j" $hint
}

function Connect-KitCopilot {
    <# Connects once per run (shared by V3, V5 and V6); $null with a result line when it cannot.
       -NoSignInWait: a missing sign-in comes back at once instead of waiting 5 minutes. #>
    param([Parameter(Mandatory)]$Ctx, [string]$Stage = 'V3')
    if ($Ctx.Bridge) { return $Ctx.Bridge }
    if (Get-KitFlag $Ctx 'NoCopilot') { Add-ValidationResult $Ctx $Stage 'SKIP' 'Copilot' 'not run (-NoCopilot)'; return $null }
    $facts = Get-ProfileFacts $Ctx
    if ($facts.forced -and $facts.account -ne 'work') {
        Add-ValidationResult $Ctx $Stage 'WARN' 'Copilot' 'not run: Edge requires a browser sign-in first (BrowserSignin = 2) and the profile is not signed in' 'Start ObsidiNote once and sign in to Edge when asked (runbook RB-02), then run the kit again.'
        return $null
    }
    $c = Measure-KitStep { Connect-Copilot -NoSignInWait -SignInTimeoutSec 60 }
    if (-not $c.ok) {
        Add-ValidationResult $Ctx $Stage 'FAIL' 'Copilot connect' "$($c.error) ($($c.ms) ms)" (Get-CopilotFailureHint -Message $c.error -Sso $facts.sso)
        return $null
    }
    if ($c.value.SignInPending) {
        try { Disconnect-Copilot $c.value } catch { }
        Add-ValidationResult $Ctx $Stage 'WARN' 'Copilot connect' "not signed in to Copilot in ObsidiNote's Edge window ($($c.ms) ms)" 'Sign in to Copilot in that window (choose "Stay signed in"), then run the kit again.'
        return $null
    }
    Add-ValidationResult $Ctx $Stage 'OK' 'Copilot connect' "ObsidiNote's Edge window, port $($facts.port); $($c.ms) ms"
    $Ctx.Bridge = $c.value
    $c.value
}

function Send-KitPrompt {
    <# Sends one prompt in a new chat; @{ ok; result; text; ms; error }. The text stays in memory. #>
    param([Parameter(Mandatory)]$Bridge, [Parameter(Mandatory)][string]$Text, [int]$TimeoutSec = 180, [ValidateSet('', 'on', 'off')][string]$WorkIq = '')
    try { $null = New-CopilotChat -Bridge $Bridge } catch { }
    # A new chat reloads the page, so the Work IQ switch is set after it.
    $wiq = ''
    if ($WorkIq) { try { $wiq = "$(Set-CopilotWorkIq -Bridge $Bridge -On ($WorkIq -eq 'on'))" } catch { $wiq = 'error' } }
    $s = Measure-KitStep { Send-CopilotPrompt -Bridge $Bridge -Text $Text -TimeoutSec $TimeoutSec }
    if (-not $s.ok) { return [pscustomobject]@{ ok = $false; result = 'error'; text = ''; ms = $s.ms; error = $s.error; workIq = $wiq } }
    $r = $s.value
    [pscustomobject]@{ ok = ("$($r.Result)" -eq 'Success'); result = "$($r.Result)"; text = "$($r.Text)"; ms = $s.ms; error = ''; workIq = $wiq }
}

function Test-EchoReply {
    <# 'exact' when the reply is the token (punctuation and spaces around it allowed), 'contains' when
       the token is in a longer reply, else 'wrong'. Pure. #>
    param([AllowEmptyString()][string]$Reply, [Parameter(Mandatory)][string]$Token)
    $t = "$Reply".Trim().Trim('`', '*', '"', "'", '.', ' ')
    if ($t -ceq $Token) { return 'exact' }
    if ("$Reply".Contains($Token)) { return 'contains' }
    'wrong'
}

function Invoke-StageCopilot {
    param([Parameter(Mandatory)]$Ctx)
    $f = Measure-KitStep { Get-ProfileFacts $Ctx }
    if ($f.ok) { Add-ProfileResult $Ctx $f.value } else { Add-ValidationResult $Ctx 'V3' 'WARN' 'Edge profile' "not read: $($f.error)" }
    $b = Connect-KitCopilot -Ctx $Ctx -Stage 'V3'
    if (-not $b) { return }
    $token = 'OK-' + (Get-Random -Minimum 100000 -Maximum 999999)
    $r = Send-KitPrompt -Bridge $b -Text "Reply with exactly: $token" -TimeoutSec 120
    if (-not $r.ok) { Add-ValidationResult $Ctx 'V3' 'FAIL' 'Copilot reply' "no answer ($($r.result)$(if ($r.error) { ": $($r.error)" })); $($r.ms) ms"; return }
    $m = Test-EchoReply -Reply $r.text -Token $token
    $status = switch ($m) { 'exact' { 'OK' } 'contains' { 'WARN' } default { 'FAIL' } }
    $what = switch ($m) { 'exact' { 'the reply is exactly the token' } 'contains' { 'the reply holds the token with other text' } default { 'the reply does not hold the token' } }
    Add-ValidationResult $Ctx 'V3' $status 'Copilot reply' "$what; $($r.text.Length) chars; $($r.ms) ms"
    $w = Measure-KitStep { Set-CopilotWorkIq -Bridge $b -On $true }
    $state = if ($w.ok) { "$($w.value)" } else { 'error' }
    Add-ValidationResult $Ctx 'V3' $(if ($state -eq 'on') { 'OK' } else { 'WARN' }) 'Work IQ switch' "$state after switching on ($($w.ms) ms)" $(if ($state -ne 'on') { 'Grounding probes (V5) need Work IQ; check the switch in Copilot Chat.' } else { '' })
}

function Close-KitCopilot {
    param([Parameter(Mandatory)]$Ctx)
    if ($Ctx.Bridge) { try { Disconnect-Copilot $Ctx.Bridge } catch { }; $Ctx.Bridge = $null }
}

Export-ModuleMember -Function Invoke-StageCopilot, Connect-KitCopilot, Send-KitPrompt, Test-EchoReply, Close-KitCopilot, Get-ProfileFacts
