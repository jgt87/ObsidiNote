# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# ObsidiNote's own Edge session settings (lib/AppConfig.psm1): debug port and profile.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
Import-Module (Join-Path $root 'lib\AppConfig.psm1') -Force

function New-TempApp([string]$Shipped, [string]$Local) {
    $app = Join-Path $env:TEMP ('obsn-cfg-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $app 'config')
    if ($Shipped) { [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.json'), $Shipped) }
    if ($Local) { [IO.File]::WriteAllText((Join-Path $app 'config\obsidinote.local.json'), $Local) }
    $app
}

Describe 'The signIn and notebook settings' {
    It 'ships signIn single-sign-on and an empty notebook record' {
        $shipped = [IO.File]::ReadAllText((Join-Path $root 'config\obsidinote.json')) | ConvertFrom-Json
        $shipped.signIn | Should Be 'single-sign-on'
        $shipped.notebook | Should Be ''
        Get-CopilotSignInMode -AppRoot $root | Should Be 'single-sign-on'
    }
    It 'takes private from the local file, and treats anything else as single-sign-on' {
        $app = New-TempApp '{"signIn":"single-sign-on"}' '{"signIn":"private"}'
        Get-CopilotSignInMode -AppRoot $app | Should Be 'private'
        Remove-Item $app -Recurse -Force
        $app = New-TempApp '{"signIn":"whatever"}' ''
        Get-CopilotSignInMode -AppRoot $app | Should Be 'single-sign-on'
        Remove-Item $app -Recurse -Force
    }
    It 'reads the notebook on record from the local file' {
        $app = New-TempApp '{"notebook":""}' '{"notebook":"onenote:https://example.org/Documents/ObsidiNote"}'
        Get-NotebookRecord -AppRoot $app | Should Be 'onenote:https://example.org/Documents/ObsidiNote'
        Remove-Item $app -Recurse -Force
        $app = New-TempApp '{"notebook":""}' ''
        Get-NotebookRecord -AppRoot $app | Should Be ''
        Remove-Item $app -Recurse -Force
    }
}

Describe 'The debug port' {
    It 'is 9334 by default, and 9334 is not on the Fetch standard''s bad-port list' {
        Test-FetchBadPort 9334 | Should Be $false
        Get-CdpPortProblem 9334 | Should Be ''
        $app = New-TempApp '{"autoUpdate":true}' ''
        (Get-CopilotSettings -AppRoot $app).cdpPort | Should Be 9334
        Remove-Item $app -Recurse -Force
    }
    It 'is 9334 in the shipped config\obsidinote.json' {
        (Get-CopilotSettings -AppRoot (Join-Path $env:TEMP 'obsn-no-such-app')).cdpPort | Should Be 9334
        $shipped = [IO.File]::ReadAllText((Join-Path $root 'config\obsidinote.json')) | ConvertFrom-Json
        $shipped.cdpPort | Should Be 9334
    }
    It 'refuses the other helper''s 9333, 8765 and 8766, the reserved 3000 and 3100, blocked and invalid ports' {
        foreach ($p in 9333, 8765, 8766, 3000, 3100) { Get-CdpPortProblem $p | Should Match 'reserved for another program' }
        foreach ($p in 6000, 4190, 10080, 1) { Get-CdpPortProblem $p | Should Match 'browsers block' }
        Get-CdpPortProblem 70000 | Should Match 'not a valid port'
        Get-CdpPortProblem 0 | Should Match 'not a valid port'
    }
    It 'takes cdpPort from obsidinote.local.json over obsidinote.json' {
        $app = New-TempApp '{"cdpPort":9334}' '{"cdpPort":9345}'
        (Get-CopilotSettings -AppRoot $app).cdpPort | Should Be 9345
        Remove-Item $app -Recurse -Force
    }
    It 'stops with a clear message on a port it must not use' {
        $app = New-TempApp '{"cdpPort":9334}' '{"cdpPort":9333}'
        { Get-CopilotSettings -AppRoot $app } | Should Throw 'reserved for another program'
        Remove-Item $app -Recurse -Force
        $app = New-TempApp '{"cdpPort":"abc"}' ''
        { Get-CopilotSettings -AppRoot $app } | Should Throw 'is not a number'
        Remove-Item $app -Recurse -Force
    }
}

Describe 'The interface port (uiPort)' {
    It 'is 8767 in the shipped config\obsidinote.json and by default, and browsers allow it' {
        ([IO.File]::ReadAllText((Join-Path $root 'config\obsidinote.json')) | ConvertFrom-Json).uiPort | Should Be 8767
        $app = New-TempApp '{}' ''
        Get-UiPort -AppRoot $app | Should Be 8767
        Remove-Item $app -Recurse -Force
        Test-FetchBadPort 8767 | Should Be $false
    }
    It 'takes uiPort from obsidinote.local.json' {
        $app = New-TempApp '{"uiPort":8767}' '{"uiPort":8790}'
        Get-UiPort -AppRoot $app | Should Be 8790
        Remove-Item $app -Recurse -Force
    }
    It 'refuses a reserved, blocked, invalid port or the debug port' {
        foreach ($bad in '3000', '8765', '8766', '4190', '"x"', '9334') {
            $app = New-TempApp "{`"cdpPort`":9334,`"uiPort`":$bad}" ''
            { Get-UiPort -AppRoot $app } | Should Throw
            Remove-Item $app -Recurse -Force
        }
    }
}

Describe 'The Edge profile' {
    It 'lives in the data folder, which OBSIDINOTE_DATA_DIR moves' {
        $app = New-TempApp '{}' ''
        (Get-CopilotSettings -AppRoot $app).profileDir | Should Be (Join-Path $env:OBSIDINOTE_DATA_DIR 'edge-profile')
        $saved = $env:OBSIDINOTE_DATA_DIR
        try {
            $env:OBSIDINOTE_DATA_DIR = ''
            (Get-CopilotSettings -AppRoot $app).profileDir | Should Be (Join-Path $env:LOCALAPPDATA 'ObsidiNote\edge-profile')
        } finally { $env:OBSIDINOTE_DATA_DIR = $saved }
        Remove-Item $app -Recurse -Force
    }
}
