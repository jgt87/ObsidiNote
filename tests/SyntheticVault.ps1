# A synthetic vault in the in-memory OneNote (tests/FakeOneNote.ps1), opened the way the app opens
# one (lib/VaultSession.psm1: write root, writer lease, structure, index), plus a connected notebook
# of the user's that must never be written. Dot-source after importing the lib modules and
# FakeOneNote.ps1. Fictional names and example.invalid links only.

function New-SyntheticVault {
    param([string]$SessionId = 'session-one')
    $f = New-FakeOneNote
    $hh = $f.AddNotebook('Household')
    $garden = $f.AddSection($hh, 'Garden')
    $tomato = $f.AddPage($garden, 'Tomatoes', @{}, 1, 'Water them every <b>morning</b>. See the seed list.')
    $seeds = $f.AddPage($garden, 'Seed list', @{}, 1, 'Cherry, plum and beefsteak.')
    $null = $f.AddRecycleBin($hh)
    $a = New-GuardedOneNote -Inner $f
    $v = New-ObsidiVault -Adapter $a -Name 'Synthetic Vault' -Location 'https://example.invalid/docs' -Year 2026
    $notes = $v.sectionIds['Notes']; $meet = $v.sectionIds['Meetings']; $proj = $v.sectionIds['Projects']
    $null = $f.AddPage($notes, 'Zero-trust networking', @{ 'obsn.id' = 'p1'; 'obsn.type' = 'concept'; 'obsn.topics' = '["Security/Networking"]'; 'obsn.summary' = 'Never trust the network: every request checks the user and the device.'; 'obsn.aliases' = '["ZTN"]'; 'obsn.links' = '[]' }, 1, 'Never trust the network. Every request checks the user and the device.')
    $null = $f.AddPage($meet, 'Partner portal: access review notes', @{ 'obsn.id' = 'p2'; 'obsn.type' = 'meeting'; 'obsn.topics' = '["Projects/Partner portal"]'; 'obsn.summary' = 'Who may reach the partner portal and how access is reviewed.'; 'obsn.links' = '[]' }, 1, 'Access to the partner portal is reviewed every quarter.')
    $null = $f.AddPage($proj, 'VPN retirement plan', @{ 'obsn.id' = 'p3'; 'obsn.type' = 'project-part'; 'obsn.topics' = '["Security/Networking"]'; 'obsn.summary' = 'Steps to switch off the old VPN.'; 'obsn.links' = '[{"t":"p1","s":2,"w":"replaced by"}]' }, 1, 'Switch off the old VPN after the proxy is live.')
    $vaults = @(Get-VaultList -Adapter $a)
    $item = @($vaults | Where-Object { $_.vaultId -eq $v.vaultId })[0]
    $open = Open-VaultSession -Adapter $a -Vault $item -SessionId $SessionId -Vaults $vaults
    $box = @{ lease = $open.lease }
    $store = New-VaultStore -Adapter $a -Vault $open.vault -Model $open.model -GetLease { $box.lease }.GetNewClosure()
    @{ f = $f; a = $a; v = $v; open = $open; box = $box; store = $store; household = $hh; tomato = $tomato; seeds = $seeds; vaults = $vaults }
}

function Get-FakeMeta($F, [string]$PageId) { $F.Nodes[$PageId].meta }

function Find-FakePage($F, [string]$Title) {
    foreach ($n in $F.Nodes.Values) { if ($n.kind -eq 'Page' -and $n.title -eq $Title) { return $n } }
    $null
}

function Get-FakeOutlineXml($F, [string]$PageId, [string]$Role) {
    foreach ($o in $F.Nodes[$PageId].outlines) { if ($o.xml -match ('obsn\.role" content="' + [regex]::Escape($Role) + '"')) { return $o.xml } }
    ''
}
