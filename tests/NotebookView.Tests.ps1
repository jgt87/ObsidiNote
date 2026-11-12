# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The notebook list and view from GetHierarchy XML (tests/fixtures/hierarchy.xml: invented
# notebooks, two vaults and one read-only). No OneNote: the COM reads are replaced.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\NotebookView.psm1') -Force
$script:Hier = [IO.File]::ReadAllText((Join-Path $here 'fixtures\hierarchy.xml'))
$script:Own = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
$script:Team = '{22222222-2222-2222-2222-222222222222}{1}{B0}'
$script:Reading = '{33333333-3333-3333-3333-333333333333}{1}{B0}'
$script:TeamRecord = 'onenote:https://example.sharepoint.com/sites/Team/Shared Documents/Team wiki/'

Describe 'ConvertTo-NotebookList' {
    It 'lists vaults first (by their 00 Index section, not their name), then read-only notebooks' {
        $l = ConvertTo-NotebookList -Xml $script:Hier
        ($l | ForEach-Object { "$($_.name):$($_.vault)" }) -join ',' | Should Be 'ObsidiNote:True,Team wiki:True,Reading notes:False'
        $l[2].location | Should Be 'this PC'
        $l[1].location | Should Be 'SharePoint'
    }
    It 'marks the vault on record as active, else the first vault' {
        (@(ConvertTo-NotebookList -Xml $script:Hier) | Where-Object { $_.active }).id | Should Be $script:Own
        (@(ConvertTo-NotebookList -Xml $script:Hier -Record $script:TeamRecord) | Where-Object { $_.active }).id | Should Be $script:Team
        @(ConvertTo-NotebookList -Xml $script:Hier | Where-Object { $_.active }).Count | Should Be 1
    }
    It 'is empty for no or broken XML' {
        @(ConvertTo-NotebookList -Xml '').Count | Should Be 0
        @(ConvertTo-NotebookList -Xml 'not xml').Count | Should Be 0
    }
}

Describe 'ConvertTo-NotebookView' {
    $links = { param($id) if ($id -eq '{11111111-1111-1111-1111-111111111115}{1}{E1}') { 'onenote:https://example.com/x#Identity' } elseif ($id -like '*119}*') { 'javascript:alert(1)' } else { '' } }
    $v = ConvertTo-NotebookView -Xml $script:Hier -Id $script:Own -GetLink $links

    It 'reads the notebook with that id only' {
        $v.available | Should Be $true
        $v.notebook.name | Should Be 'ObsidiNote'
        $v.notebook.vault | Should Be $true
        @($v.recent | Where-Object { $_.title -eq 'A book about maps' }).Count | Should Be 0
    }
    It 'lists sections and section groups in order, with page counts' {
        (@($v.sections) | ForEach-Object { "$($_.kind):$($_.name):$($_.pages)" }) -join ',' | Should Be 'section:00 Index:1,section:Notes:2,group:Journal:1'
        $v.sections[2].children[0].name | Should Be '2026'
        $v.totals.sections | Should Be 3
        $v.totals.pages | Should Be 4
    }
    It 'leaves out the recycle bin' {
        @($v.sections | Where-Object { $_.name -eq 'OneNote_RecycleBin' }).Count | Should Be 0
        @($v.recent | Where-Object { $_.title -eq 'Gone' }).Count | Should Be 0
    }
    It 'lists the most recently changed pages first, with the section path' {
        ($v.recent | ForEach-Object { $_.title }) -join ',' | Should Be 'Tuesday,Identity-aware proxies,Untitled page,ObsidiNote'
        $v.recent[0].section | Should Be 'Journal / 2026'
    }
    It 'passes on onenote: links only' {
        $v.recent[1].link | Should Match '^onenote:https://'
        $v.recent[0].link | Should Be ''
    }
    It 'reads a read-only notebook the same way' {
        $r = ConvertTo-NotebookView -Xml $script:Hier -Id $script:Reading
        $r.notebook.vault | Should Be $false
        $r.recent[0].title | Should Be 'A book about maps'
    }
    It 'keeps at most -Recent pages, and says when the id is not an open notebook' {
        @((ConvertTo-NotebookView -Xml $script:Hier -Id $script:Own -Recent 2).recent).Count | Should Be 2
        $none = ConvertTo-NotebookView -Xml $script:Hier -Id '{99999999-9999-9999-9999-999999999999}{1}{B0}'
        $none.available | Should Be $false
        $none.notFound | Should Be $true
    }
}

Describe 'Get-NotebookView and Get-OpenNotebookList (COM replaced)' {
    $xml = { param($startId, $scope) $script:Hier }
    It 'never starts OneNote: when it is not running they only say so' {
        (Get-NotebookView -GetState { 'none' } -GetXml { throw 'must not read' } -GetLink { '' }).message | Should Match 'OneNote is not running'
        (Get-OpenNotebookList -GetState { 'none' } -GetXml { throw 'must not read' }).message | Should Match 'OneNote is not running'
    }
    It 'shows the active vault without an id' {
        (Get-NotebookView -GetState { 'window' } -GetXml $xml -GetLink { '' } -Record $script:TeamRecord).notebook.name | Should Be 'Team wiki'
        $v = Get-NotebookView -GetState { 'window' } -GetXml $xml -GetLink { '' }
        $v.notebook.name | Should Be 'ObsidiNote'
        $v.notebook.active | Should Be $true
    }
    It 'reads a chosen notebook by id, and never an id that is not an open notebook' {
        (Get-NotebookView -Id $script:Reading -GetState { 'window' } -GetXml $xml -GetLink { '' }).notebook.name | Should Be 'Reading notes'
        $script:asked = @()
        $nf = Get-NotebookView -Id '{11111111-1111-1111-1111-111111111114}{1}{B0}' -GetState { 'window' } -GetXml { param($s, $sc) $script:asked += "$s"; $script:Hier } -GetLink { '' }
        $nf.notFound | Should Be $true
        ($script:asked | Where-Object { $_ }).Count | Should Be 0
    }
    It 'turns a COM failure into a message' {
        (Get-OpenNotebookList -GetState { 'window' } -GetXml { throw 'RPC' }).message | Should Match 'did not answer'
    }
}

Describe 'Vault records' {
    It 'gives the record of a vault, and refuses a read-only notebook' {
        $r = Get-VaultRecordFromXml -Xml $script:Hier -Id $script:Team -ToRecord { param($p) "onenote:$p" }
        $r.ok | Should Be $true
        $r.record | Should Be $script:TeamRecord
        $n = Get-VaultRecordFromXml -Xml $script:Hier -Id $script:Reading -ToRecord { param($p) "x" }
        $n.ok | Should Be $false
        $n.message | Should Match 'not an ObsidiNote vault'
    }
    It 'matches records to notebook paths' {
        Test-RecordMatchesPath $script:TeamRecord 'https://example.sharepoint.com/sites/Team/Shared Documents/Team wiki/' | Should Be $true
        Test-RecordMatchesPath 'C:\Notes\Reading notes\Open Notebook.onetoc2' 'C:\Notes\Reading notes' | Should Be $true
        Test-RecordMatchesPath 'C:\Notes\Other\Open Notebook.onetoc2' 'C:\Notes\Reading notes' | Should Be $false
        Test-RecordMatchesPath '' 'C:\Notes' | Should Be $false
    }
    It 'Find-VaultInHierarchy: only the vault on record when there is one, else by name or structure' {
        (Find-VaultInHierarchy -Xml $script:Hier -Record $script:TeamRecord).name | Should Be 'Team wiki'
        Find-VaultInHierarchy -Xml $script:Hier -Record 'onenote:https://example.com/elsewhere/' | Should BeNullOrEmpty
        (Find-VaultInHierarchy -Xml $script:Hier).name | Should Be 'ObsidiNote'
        (Find-VaultInHierarchy -Xml $script:Hier -Name 'No such name').name | Should Be 'ObsidiNote'
    }
}

Describe 'Get-NotebookLocationLabel' {
    It 'tells OneDrive, SharePoint and this PC apart' {
        Get-NotebookLocationLabel 'https://example-my.sharepoint.com/personal/a/Documents/X/' | Should Be 'OneDrive'
        Get-NotebookLocationLabel 'https://d.docs.live.net/0123/Documents/X/' | Should Be 'OneDrive'
        Get-NotebookLocationLabel 'https://example.sharepoint.com/sites/Team/Shared Documents/X/' | Should Be 'SharePoint'
        Get-NotebookLocationLabel 'C:\Notes\X' | Should Be 'this PC'
    }
}
