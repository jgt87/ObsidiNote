# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# lib/SyncedFiles.psm1 and POST /api/file/locate: a dropped file's OneDrive/SharePoint address, found
# by name, size and time in the synced folders (operator, 2026-11-14). A made-up synced folder in
# %TEMP% stands in for OneDrive; no real files, names or tenants.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$env:OBSIDINOTE_DATA_DIR = Join-Path $env:TEMP 'obsidinote-test-data'
foreach ($m in 'SyncedFiles', 'NotebookStructure', 'LinkCapture') { Import-Module (Join-Path $root "lib\$m.psm1") -Force }

function New-SyncedTree {
    $d = Join-Path $env:TEMP ('obsn-sync-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $d 'Projects\Q3 plans')
    $f = Join-Path $d 'Projects\Q3 plans\Budget review.docx'
    [IO.File]::WriteAllBytes($f, [byte[]](1..100))
    $t = [datetime]::new(2026, 11, 10, 9, 30, 0, [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($f, $t)
    $other = Join-Path $d 'Budget review.docx'
    [IO.File]::WriteAllBytes($other, [byte[]](1..50))
    @{ dir = $d; file = $f; time = $t; root = @{ path = $d; url = 'https://contoso-my.sharepoint.com/personal/someone_example_invalid/Documents' } }
}

Describe 'ConvertTo-SyncedUrl (pure)' {
    It 'turns a path under the synced folder into its web address, each part escaped' {
        $r = @{ path = 'C:\Sync\Docs'; url = 'https://contoso-my.sharepoint.com/personal/x/Documents/' }
        ConvertTo-SyncedUrl -Root $r -Path 'C:\Sync\Docs\Q3 plans\Budget review.docx' | Should Be 'https://contoso-my.sharepoint.com/personal/x/Documents/Q3%20plans/Budget%20review.docx'
        ConvertTo-SyncedUrl -Root $r -Path 'C:\Sync\Other\a.docx' | Should Be ''
        ConvertTo-SyncedUrl -Root $r -Path 'C:\Sync\DocsMore\a.docx' | Should Be ''
    }
    It 'escapes the library''s own address too, and never twice (code review 2026-11-15)' {
        $e = [string][char]0xE9   # e with an acute accent; this file stays ASCII
        $want = 'https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Caf%C3%A9%20plans/Q3%20plans/Budget%20review.docx'
        $raw = @{ path = 'C:\Sync\Team'; url = "https://contoso.sharepoint.com/sites/Team/Shared Documents/Caf$e plans/" }
        ConvertTo-SyncedUrl -Root $raw -Path 'C:\Sync\Team\Q3 plans\Budget review.docx' | Should Be $want
        $escaped = @{ path = 'C:\Sync\Team'; url = 'https://contoso.sharepoint.com/sites/Team/Shared%20Documents/Caf%C3%A9%20plans' }
        ConvertTo-SyncedUrl -Root $escaped -Path 'C:\Sync\Team\Q3 plans\Budget review.docx' | Should Be $want
        # A root without a path, and personal OneDrive's root with the account id, stay as they are.
        ConvertTo-SyncedUrl -Root @{ path = 'C:\Sync\P'; url = 'https://d.docs.live.net/0123456789abcdef/' } -Path 'C:\Sync\P\a b.txt' | Should Be 'https://d.docs.live.net/0123456789abcdef/a%20b.txt'
        ConvertTo-SyncedUrl -Root @{ path = 'C:\Sync\P'; url = 'https://contoso.sharepoint.com' } -Path 'C:\Sync\P\a.txt' | Should Be 'https://contoso.sharepoint.com/a.txt'
    }
}

Describe 'Resolve-SyncRootUrl (pure)' {
    It 'adds the account id to personal OneDrive''s bare address (as the dev PC stores it)' {
        Resolve-SyncRootUrl -Url 'https://d.docs.live.net/' -PersonalCid 'a1b2c3d4e5f60718' | Should Be 'https://d.docs.live.net/a1b2c3d4e5f60718/'
        Resolve-SyncRootUrl -Url 'https://d.docs.live.net/' | Should Be ''
    }
    It 'keeps a work or SharePoint library''s full address' {
        Resolve-SyncRootUrl -Url 'https://contoso-my.sharepoint.com/personal/x/Documents' -PersonalCid 'zz' | Should Be 'https://contoso-my.sharepoint.com/personal/x/Documents'
    }
}

Describe 'Find-SyncedFile' {
    $t = New-SyncedTree
    It 'finds the one file with that name, size and time, and gives its address' {
        $r = Find-SyncedFile -Name 'Budget review.docx' -Size 100 -ModifiedUtc $t.time -Roots @($t.root)
        $r.status | Should Be 'found'
        $r.url | Should Be 'https://contoso-my.sharepoint.com/personal/someone_example_invalid/Documents/Projects/Q3%20plans/Budget%20review.docx'
    }
    It 'accepts a time 1 s off (rounding), not a different size or a time far off' {
        (Find-SyncedFile -Name 'Budget review.docx' -Size 100 -ModifiedUtc $t.time.AddSeconds(1) -Roots @($t.root)).status | Should Be 'found'
        (Find-SyncedFile -Name 'Budget review.docx' -Size 101 -ModifiedUtc $t.time -Roots @($t.root)).status | Should Be 'none'
        (Find-SyncedFile -Name 'Budget review.docx' -Size 100 -ModifiedUtc $t.time.AddHours(1) -Roots @($t.root)).status | Should Be 'none'
    }
    It 'gives no address when two files match' {
        $dup = Join-Path $t.dir 'Projects\Budget review.docx'
        [IO.File]::WriteAllBytes($dup, [byte[]](1..100)); [IO.File]::SetLastWriteTimeUtc($dup, $t.time)
        (Find-SyncedFile -Name 'Budget review.docx' -Size 100 -ModifiedUtc $t.time -Roots @($t.root)).status | Should Be 'many'
        Remove-Item -LiteralPath $dup
    }
    It 'finds the file when the synced folder is given by its 8.3 short name (as CI''s TEMP is)' {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $short = $fso.GetFolder($t.dir).ShortPath
        $root = @{ path = $short; url = $t.root.url }
        $r = Find-SyncedFile -Name 'Budget review.docx' -Size 100 -ModifiedUtc $t.time -Roots @($root)
        $r.status | Should Be 'found'
        $r.url | Should Match '/Projects/Q3%20plans/Budget%20review\.docx$'
    }
    It 'says when nothing is synced' {
        (Find-SyncedFile -Name 'a.docx' -Size 1 -ModifiedUtc $t.time -Roots @()).status | Should Be 'no-sync'
    }
    Remove-Item -LiteralPath $t.dir -Recurse -Force
}

Describe 'The summary prompt for a dropped file' {
    It 'gives Copilot the file text and asks it not to open the address' {
        $p = New-LinkSummaryPrompt -Url 'https://contoso-my.sharepoint.com/x.docx' -Bucket 'Internal links' -Ref 'rAAAA0001' -SourceText 'Tidal gardens need salt marsh hay.'
        $p | Should Match 'do not open the URL'
        $p | Should Match 'FILE TEXT START\r?\nTidal gardens need salt marsh hay\.'
        $p | Should Match '"ref": "rAAAA0001"'
        New-LinkSummaryPrompt -Url 'https://contoso-my.sharepoint.com/x.docx' -Bucket 'Internal links' | Should Not Match 'FILE TEXT'
    }
}

Describe 'Sources view: personal OneDrive addresses' {
    It 'puts d.docs.live.net under OneDrive' {
        (Get-LinkSource -Url 'https://d.docs.live.net/abc123/Documents/a.docx').id | Should Be 'onedrive'
    }
}
