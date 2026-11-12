# Single sign-on with the Windows work account in ObsidiNote's own Edge profile, so Copilot signs in
# by itself after a restart. Nothing is stored by ObsidiNote: Edge uses the work account Windows
# already holds (a device sign-in token, "PRT"). Only ObsidiNote's profile is changed (Edge's switch
# "Allow single sign-on for work or school sites using this profile", on Edge's own settings page),
# and only by sso-setup.cmd after the person confirms; Edge policies and the normal Edge profile
# are never touched.
#
# Provenance: ported from the CCBridge repo (github.com/jgt87/CCBridge), lib/Sso.psm1. Changed:
# ObsidiNote's port and profile (lib/AppConfig.psm1); Get-DeviceJoinStatus moved in from CCBridge's
# lib/Prereq.psm1; no file is written here (Invoke-SsoSetup returns its lines and
# tools/sso-setup.ps1 writes them); the setup log names tab hosts only, never paths; added
# Get-ProfileSsoState for the start's status line (from Edge's files, without opening Edge).
# Read only from Edge's files: the account type (Local State) and named switch values
# (Preferences). Never cookies, tokens, account names or ids.
# Strict mode stays off here: Edge's JSON files are read with optional fields.
# Keep this file ASCII: PS 5.1 reads BOM-less files as ANSI.

$ErrorActionPreference = 'Stop'
foreach ($m in 'Log', 'AppConfig', 'Cdp', 'CopilotBridge') { Import-Module (Join-Path $PSScriptRoot "$m.psm1") }

$script:SettingsUrl = 'edge://settings/profiles/multiProfileSettings'
# The switch's label in the languages seen so far (Edge's own text).
$script:SwitchPattern = '(?i)single sign-on for work|work or school sites|eenmalige aanmelding.*(werk|school)|einmaliges anmelden.*(arbeits|schul)|authentification unique.*(professionnel|scolaire)|\bSSO\b.*(work|werk|school|schul)'
$script:NotThisPattern = '(?i)microsoft account|microsoft-account|persoonlijk|personal|pers.nliche'
$script:FindJs = @'
(() => {
  const all = []; const walk = (r) => { for (const e of r.querySelectorAll('*')) { all.push(e); if (e.shadowRoot) walk(e.shadowRoot); } }; walk(document);
  const up = (n) => n.parentElement || (n.getRootNode && n.getRootNode().host) || null;
  const byId = (e, id) => { const r = e.getRootNode(); return (r.getElementById ? r.getElementById(id) : null) || document.getElementById(id); };
  const labelOf = (e) => {
    let t = e.getAttribute('aria-label') || '';
    const by = e.getAttribute('aria-labelledby');
    if (!t && by) t = by.split(' ').map(id => { const x = byId(e, id); return x ? (x.innerText || x.textContent || '') : ''; }).join(' ');
    if (!t && e.id) { const l = e.getRootNode().querySelector ? e.getRootNode().querySelector('label[for="' + e.id + '"]') : null; if (l) t = l.innerText || l.textContent || ''; }
    if (!t) { let p = up(e); for (let i = 0; i < 8 && p && !t.trim(); i++, p = up(p)) { const x = (p.innerText || p.textContent || '').trim(); if (x.length <= 400) t = x; else break; } }
    return t.replace(/\s+/g, ' ').trim().slice(0, 140);
  };
  const sw = all.filter(e => e.matches('[role=switch], input[type=checkbox]'));
  window.__obsnSwitches = sw;
  return JSON.stringify(sw.map((e, i) => ({ i, label: labelOf(e), on: e.getAttribute('aria-checked') === 'true' || e.checked === true,
    disabled: e.disabled === true || e.getAttribute('aria-disabled') === 'true' })));
})()
'@

function Get-OwnSession {
    # ObsidiNote's own Edge session: @{ cdpPort; profileDir } (lib/AppConfig.psm1).
    Get-CopilotSettings -AppRoot (Split-Path -Parent $PSScriptRoot)
}

function Get-DeviceJoinStatus {
    <# Whether this PC can sign in to work sites with the Windows account: the yes/no fields of
       dsregcmd /status (nothing else is read; no ids or names). $Lines is for tests. #>
    param([string[]]$Lines)
    if (-not $PSBoundParameters.ContainsKey('Lines')) { $Lines = @(cmd /c "dsregcmd /status 2>nul") }
    $out = [ordered]@{}
    foreach ($k in 'AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'EnterpriseJoined', 'AzureAdPrt') {
        $m = @($Lines | Select-String -Pattern "^\s*$k\s*:\s*(YES|NO)\s*$") | Select-Object -First 1
        $out[$k] = if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
    }
    $out
}

function Select-SsoSwitch {
    <# The single sign-on switch among the switches on Edge's profile settings page (labels as Edge
       shows them); $null when it is not there. #>
    param($Switches)
    @($Switches | Where-Object { $_ -and "$($_.label)" -match $script:SwitchPattern -and "$($_.label)" -notmatch $script:NotThisPattern }) | Select-Object -First 1
}

function Get-CopilotSignInState {
    <# Where ObsidiNote's Copilot tab is: 'chat' (signed in), 'sign-in page' (Microsoft's), 'other page'
       (a web page on another site, such as an organisation's own sign-in page: Get-OtherPageHost
       names it), 'no tab' or 'edge not running'. Only the tab addresses are looked at. $Pages is for tests. #>
    param([int]$Port = 0, $Pages)
    if (-not $PSBoundParameters.ContainsKey('Pages')) {
        if (-not $Port) { $Port = (Get-OwnSession).cdpPort }
        if (-not (Test-CdpEndpoint $Port)) { return 'edge not running' }
        $Pages = @((Invoke-RestMethod "http://127.0.0.1:$Port/json/list") | Where-Object { $_.type -eq 'page' })
    }
    $urls = @($Pages | ForEach-Object { "$($_.url)" })
    if (@($urls | Where-Object { $_ -match '^(?i)https://(login\.microsoftonline\.com|login\.live\.com|login\.microsoft\.com|login\.windows\.net)/' }).Count) { return 'sign-in page' }
    $sel = try { Get-CopilotSelectors } catch { $null }
    $onCopilot = @($urls | Where-Object { if ($sel) { Test-CopilotUrl $_ $sel } else { $_ -match '^(?i)https://([a-z0-9-]+\.)*(microsoft365\.com|m365\.cloud\.microsoft|office\.com)/' } })
    if ($onCopilot.Count) { return 'chat' }
    if (Get-OtherPageHost -Pages $Pages) { return 'other page' }
    'no tab'
}

function Get-OtherPageHost {
    <# The site of a web page in ObsidiNote's Edge that is neither Copilot, Microsoft's sign-in nor a
       local page: where Copilot's tab went instead (often the organisation's sign-in page). Host only. #>
    param([int]$Port = 0, $Pages)
    if (-not $PSBoundParameters.ContainsKey('Pages')) {
        if (-not $Port) { $Port = (Get-OwnSession).cdpPort }
        if (-not (Test-CdpEndpoint $Port)) { return $null }
        $Pages = @((Invoke-RestMethod "http://127.0.0.1:$Port/json/list") | Where-Object { $_.type -eq 'page' })
    }
    foreach ($p in @($Pages)) {
        $u = $null; try { $u = [Uri]"$($p.url)" } catch { continue }
        if ($u.Scheme -notin 'http', 'https' -or $u.Host -match '^(localhost|127\.0\.0\.1|\[::1\])$') { continue }
        if ($u.Host -match '(?i)(^|\.)(microsoft365\.com|m365\.cloud\.microsoft|office\.com)$') { continue }
        return $u.Host
    }
    $null
}

function Get-TabHosts([int]$Port) {
    # Which sites ObsidiNote's Edge tabs show: host names only (no path, no query), for the setup log.
    if (-not (Test-CdpEndpoint $Port)) { return @() }
    @(@((Invoke-RestMethod "http://127.0.0.1:$Port/json/list") | Where-Object { $_.type -eq 'page' } | ForEach-Object {
        try { $u = [Uri]"$($_.url)"; if ($u.Scheme -in 'http', 'https') { $u.Host } else { "$($u.Scheme):" } } catch { '?' }
    }) | Select-Object -Unique)
}

function Test-ProfileSsoAuto {
    <# Whether Edge turned single sign-on for work sites on for ObsidiNote's profile:
       Preferences edge.profile_sso_info.aad_sso_algo_state = 2 (1 = off). Read only. #>
    param([string]$ProfileDir = '')
    if (-not $ProfileDir) { $ProfileDir = (Get-OwnSession).profileDir }
    try { $p = [IO.File]::ReadAllText((Join-Path $ProfileDir 'Default\Preferences')) | ConvertFrom-Json } catch { return $false }
    "$($p.edge.profile_sso_info.aad_sso_algo_state)" -eq '2'
}

function Get-ProfileAccount {
    <# Which account ObsidiNote's Edge profile is signed in with: 'work' (work or school account),
       'personal' (Microsoft account), 'none' or 'unknown' (also: the profile does not exist yet).
       Only the account type is read. #>
    param([string]$ProfileDir = '')
    if (-not $ProfileDir) { $ProfileDir = (Get-OwnSession).profileDir }
    Get-EdgeProfileAccount -ProfileDir $ProfileDir   # lib/Cdp.psm1: Connect-Copilot needs it too
}

function Get-ProfileSsoState {
    <# The profile's single sign-on from Edge's files, without opening Edge (for the start):
       'unavailable' (no work account token on this PC, AzureAdPrt not YES), 'on' (Edge turned it on,
       or the profile is signed in with a work account, which signs work sites in by itself) or 'off'
       (not on as far as Edge's files show). -Join and -Account are for tests. #>
    param([string]$ProfileDir = '', $Join, [string]$Account = '')
    if (-not $ProfileDir) { $ProfileDir = (Get-OwnSession).profileDir }
    if ($null -eq $Join) { $Join = Get-DeviceJoinStatus }
    if (-not $Account) { $Account = Get-ProfileAccount $ProfileDir }
    if ($Join['AzureAdPrt'] -ne 'YES') { return 'unavailable' }
    if ($Account -eq 'work' -or (Test-ProfileSsoAuto $ProfileDir)) { return 'on' }
    'off'
}

function Open-BackgroundTab([int]$Port, [string]$Url) {
    # A tab that does not take focus from the tab the person is looking at. When the page never shows
    # up in Edge's debug list (an edge:// page a policy keeps from debugging, a slow start), the tab
    # that was made is closed again before the error goes up: a settings tab must never stay open.
    $ver = Invoke-RestMethod "http://127.0.0.1:$Port/json/version"
    $browser = Connect-Cdp $ver.webSocketDebuggerUrl
    $targetId = $null
    try {
        $t = Invoke-Cdp $browser 'Target.createTarget' @{ url = $Url; background = $true }
        $targetId = $t.targetId
        $page = $null
        for ($i = 0; $i -lt 20 -and -not $page; $i++) {
            $page = @((Invoke-RestMethod "http://127.0.0.1:$Port/json/list") | Where-Object { $_.id -eq $targetId }) | Select-Object -First 1
            if (-not $page) { Start-Sleep -Milliseconds 150 }
        }
        if (-not $page) { throw "Edge did not open $Url" }
        [pscustomobject]@{ Browser = $browser; TargetId = $targetId; Session = (Connect-Cdp $page.webSocketDebuggerUrl) }
    } catch {
        if ($targetId) { try { $null = Invoke-Cdp $browser 'Target.closeTarget' @{ targetId = $targetId } } catch { } }
        Disconnect-Cdp $browser
        throw
    }
}

function Close-BackgroundTab($Tab) {
    # The browser-level close first; when that fails, the page closes itself (Page.close), so the
    # tab is gone either way.
    if (-not $Tab) { return }
    $closed = $false
    try { $null = Invoke-Cdp $Tab.Browser 'Target.closeTarget' @{ targetId = $Tab.TargetId }; $closed = $true } catch { }
    if (-not $closed -and $Tab.Session) { try { $null = Invoke-Cdp $Tab.Session 'Page.close' @{} } catch { } }
    try { Disconnect-Cdp $Tab.Session } catch { }
    try { Disconnect-Cdp $Tab.Browser } catch { }
}

function Get-PageSwitches($Session, [int]$WaitSec = 10) {
    $list = @()
    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        Start-Sleep -Milliseconds 500
        # Assigned first: in 5.1 a JSON list arrives as one object inside a pipeline or @().
        try { $parsed = ConvertFrom-Json "$(Invoke-CdpEval $Session $script:FindJs)"; $list = @(foreach ($x in $parsed) { $x }) } catch { $list = @() }
    } while (-not $list.Count -and (Get-Date) -lt $deadline)
    , $list
}

function Invoke-SsoSwitchClick($Session, $Switch, [bool]$On) {
    # Clicks the switch and reads it back: 'turned on', 'turned off' or 'did not stick'.
    $null = Invoke-CdpEval $Session "(() => { const e = window.__obsnSwitches[$($Switch.i)]; e.scrollIntoView({ block: 'center' }); e.click(); return true })()"
    Start-Sleep -Seconds 2
    $now = Select-SsoSwitch (Get-PageSwitches $Session 4)
    if ($now -and [bool]$now.on -eq $On) { if ($On) { 'turned on' } else { 'turned off' } } else { 'did not stick' }
}

function Get-SsoStatus {
    <# The whole picture: work account on this PC, the profile switch (on, on-auto, signed-in-work,
       off, managed, not-found, unavailable = no work account, edge-not-running) and where the
       Copilot tab is. -NoPage skips opening Edge's settings page (in a hidden tab, closed again). #>
    param([int]$Port = 0, [switch]$NoPage)
    $own = Get-OwnSession
    if (-not $Port) { $Port = $own.cdpPort }
    $join = Get-DeviceJoinStatus
    $work = $join['AzureAdPrt'] -eq 'YES'
    $st = [ordered]@{ workAccount = $work; join = $join; profileSso = 'unknown'; profileAccount = (Get-ProfileAccount $own.profileDir); copilot = (Get-CopilotSignInState $Port); copilotHost = (Get-OtherPageHost $Port); checkedAt = (Get-Date).ToString('s') }
    if (-not $work) { $st.profileSso = 'unavailable'; return $st }
    if (-not (Test-CdpEndpoint $Port)) { $st.profileSso = 'edge-not-running'; return $st }
    if ($NoPage) { return $st }
    $tab = Open-BackgroundTab $Port $script:SettingsUrl
    try {
        $sw = Select-SsoSwitch (Get-PageSwitches $tab.Session)
        # Edge offers the switch only for profiles without a work account; signed in with one, work
        # sites already sign in with it.
        if (-not $sw) { $st.profileSso = $(if (Test-ProfileSsoAuto $own.profileDir) { 'on-auto' } elseif ($st.profileAccount -eq 'work') { 'signed-in-work' } else { 'not-found' }) }
        else { $st.profileSso = if ($sw.disabled) { 'managed' } elseif ($sw.on) { 'on' } else { 'off' } }
    } finally { Close-BackgroundTab $tab }
    $st
}

function Set-ProfileSso {
    <# Turns the profile switch on or off. Returns 'turned on', 'turned off', 'already on',
       'already off', 'managed', 'not-found', 'unavailable', 'edge-not-running' or 'did not stick'. #>
    param([int]$Port = 0, [Parameter(Mandatory)][bool]$On)
    if (-not $Port) { $Port = (Get-OwnSession).cdpPort }
    if ((Get-DeviceJoinStatus)['AzureAdPrt'] -ne 'YES') { return 'unavailable' }
    if (-not (Test-CdpEndpoint $Port)) { return 'edge-not-running' }
    $tab = Open-BackgroundTab $Port $script:SettingsUrl
    try {
        $sw = Select-SsoSwitch (Get-PageSwitches $tab.Session)
        if (-not $sw) { return 'not-found' }
        if ([bool]$sw.on -eq $On) { return $(if ($On) { 'already on' } else { 'already off' }) }
        if ($sw.disabled) { return 'managed' }
        $result = Invoke-SsoSwitchClick $tab.Session $sw $On
        Write-AppLog info sso "Single sign-on in ObsidiNote's Edge profile: $result"
        $result
    } finally { Close-BackgroundTab $tab }
}

function Get-SsoKeys([string]$ProfileDir) {
    # Edge's sign-in related settings in ObsidiNote's profile: names and simple values only.
    $out = [ordered]@{}
    $walk = {
        param($o, $p)
        if ($o -isnot [pscustomobject]) { return }
        foreach ($q in $o.PSObject.Properties) {
            $k = if ($p) { "$p.$($q.Name)" } else { $q.Name }
            if ($q.Value -is [pscustomobject]) { & $walk $q.Value $k }
            elseif ($k -match '(?i)sso|single_sign|aad|implicit_signin|edge_account_type$' -and $k -notmatch '(?i)arbitration_experiences' -and ($q.Value -is [bool] -or $q.Value -is [int] -or $q.Value -is [long] -or "$($q.Value)" -match '^[A-Za-z]{1,20}$')) { $out[$k] = "$($q.Value)" }
        }
    }
    foreach ($f in @(@{ n = 'Local State'; p = (Join-Path $ProfileDir 'Local State') }, @{ n = 'Preferences'; p = (Join-Path $ProfileDir 'Default\Preferences') })) {
        try { $j = [IO.File]::ReadAllText($f.p) | ConvertFrom-Json; & $walk $j $f.n } catch { }
    }
    $out
}

function Get-SsoSwitchResult {
    <# What to do with the switch found on Edge's page (or not found): a result word and an optional
       log line, before anything is clicked. 'change' means: click it (after the question). #>
    param($Switch, [bool]$On, [bool]$AutoOn, [string]$Account, [int]$SwitchCount)
    if (-not $Switch -and $AutoOn) { return @{ result = 'already on'; line = 'Already on: Edge turned single sign-on for work sites on by itself for this profile (edge.profile_sso_info.aad_sso_algo_state = 2), so there is no switch to change. If Copilot still asks to sign in after a restart, sign in once and choose "Stay signed in".' } }
    if (-not $Switch -and $Account -eq 'work') { return @{ result = 'signed-in-work'; line = 'No switch needed: the profile is signed in with a work account, so Edge signs work sites in with it already. If Copilot still asks to sign in after a restart, choose "Stay signed in" once.' } }
    if (-not $Switch) { return @{ result = 'not-found'; line = "The single sign-on switch is not on Edge's profile page ($SwitchCount switch(es) found; Edge shows it only for a profile that is not signed in with a work account)." } }
    if ([bool]$Switch.on -eq $On) { return @{ result = $(if ($On) { 'already on' } else { 'already off' }); line = '' } }
    if ($Switch.disabled) { return @{ result = 'managed'; line = 'The switch is managed by your organisation (policy) and cannot be changed here.' } }
    @{ result = 'change'; line = '' }
}

function Invoke-SsoSetup {
    <# The full setup: this PC, every switch on Edge's profile page, the change, and which of Edge's
       settings changed. Returns @{ Result; Lines } (names and yes/no values only); the caller
       (tools/sso-setup.ps1) writes the lines to the log folder. $Confirm (scriptblock returning
       $true) asks before changing. #>
    param([int]$Port = 0, [bool]$On = $true, [scriptblock]$Confirm, [string]$ProfileDir = '')
    $own = Get-OwnSession
    if (-not $Port) { $Port = $own.cdpPort }
    if (-not $ProfileDir) { $ProfileDir = $own.profileDir }
    $log = New-Object System.Collections.Generic.List[string]
    $log.Add("ObsidiNote single sign-on setup $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Names and yes/no values only.")
    $join = Get-DeviceJoinStatus
    $log.Add('This PC: ' + (($join.Keys | ForEach-Object { "$_=$($join[$_])" }) -join ', '))
    $account = Get-ProfileAccount $ProfileDir
    $log.Add("ObsidiNote's Edge profile is signed in with: $(switch ($account) { 'work' { 'a work or school account' } 'personal' { 'a personal Microsoft account' } 'none' { 'no account' } default { 'unknown' } })")
    $log.Add('Edge tabs (sites): ' + ((@(Get-TabHosts $Port)) -join ', '))
    $result = 'unavailable'
    $before = Get-SsoKeys $ProfileDir
    if ($join['AzureAdPrt'] -ne 'YES') {
        $log.Add('No work account token on this PC (AzureAdPrt is not YES): Edge has nothing to sign in with. Sign in to Copilot once in ObsidiNote''s Edge window and choose "Stay signed in".')
    } elseif (-not (Test-CdpEndpoint $Port)) {
        $result = 'edge-not-running'; $log.Add('ObsidiNote''s Edge is not running; start it first.')
    } else {
        $tab = Open-BackgroundTab $Port $script:SettingsUrl
        try {
            $all = Get-PageSwitches $tab.Session
            $sw = Select-SsoSwitch $all
            # Every switch on Edge's profile page; only the one labelled for single sign-on counts.
            foreach ($w in $all) {
                $what = $(if ($sw -and $w.i -eq $sw.i) { ' (the single sign-on switch)' } else { ' (another setting, not single sign-on)' })
                $log.Add("  switch on the page: [$(if ($w.on) { 'on' } else { 'off' })$(if ($w.disabled) { ', managed or disabled' })] $(if ("$($w.label)".Trim()) { $w.label } else { '(no label)' })$what")
            }
            $pick = Get-SsoSwitchResult -Switch $sw -On $On -AutoOn (Test-ProfileSsoAuto $ProfileDir) -Account $account -SwitchCount @($all).Count
            $result = $pick.result
            if ($pick.line) { $log.Add($pick.line) }
            if ($result -eq 'change') {
                if ($Confirm -and -not (& $Confirm)) { $result = 'declined' }
                else { $result = Invoke-SsoSwitchClick $tab.Session $sw $On }
            }
        } finally { Close-BackgroundTab $tab }
    }
    Start-Sleep -Seconds 3   # Edge writes its settings files shortly after a change
    $after = Get-SsoKeys $ProfileDir
    $log.Add(''); $log.Add("Result: $result")
    $log.Add('Edge sign-in settings (file.key = before -> after):')
    foreach ($k in @(@($before.Keys) + @($after.Keys) | Select-Object -Unique | Sort-Object)) {
        $b = if ($before.Contains($k)) { $before[$k] } else { '-' }; $a = if ($after.Contains($k)) { $after[$k] } else { '-' }
        $log.Add("  $k = $b$(if ($a -ne $b) { " -> $a   CHANGED" })")
    }
    if ($result -in 'turned on', 'already on', 'signed-in-work') { $log.Add(''); $log.Add('Next: close ObsidiNote''s Edge window and start ObsidiNote again. Copilot should then sign in by itself.') }
    Write-AppLog info sso "Single sign-on setup: $result"
    [pscustomobject]@{ Result = $result; Lines = $log.ToArray() }
}

function Open-SsoSettingsPage([int]$Port = 0) {
    # Edge's profile settings, in front, for the person to look at or change by hand.
    if (-not $Port) { $Port = (Get-OwnSession).cdpPort }
    if (-not (Test-CdpEndpoint $Port)) { throw 'ObsidiNote''s Edge is not running.' }
    $t = Invoke-RestMethod -Method Put "http://127.0.0.1:$Port/json/new?$($script:SettingsUrl)"
    try { $null = Invoke-RestMethod "http://127.0.0.1:$Port/json/activate/$($t.id)" } catch { }
    $true
}

Export-ModuleMember -Function Get-DeviceJoinStatus, Select-SsoSwitch, Get-CopilotSignInState, Get-OtherPageHost, Test-ProfileSsoAuto, Get-ProfileAccount, Get-ProfileSsoState, Get-TabHosts, Get-SsoStatus, Set-ProfileSso, Get-SsoSwitchResult, Invoke-SsoSetup, Open-SsoSettingsPage, Open-BackgroundTab, Close-BackgroundTab
