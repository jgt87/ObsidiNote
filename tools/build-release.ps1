# Build + tag + publish in one go. Needs a clean, pushed tree and gh signed in.
# The release carries what tools/update.ps1 needs:
#   ObsidiNote-vX.Y.Z.zip  one folder ObsidiNote\ with version.txt (the tag) and manifest.json
#                          (every file with its SHA-256; checked at every start)
#   SHA256SUMS             the zip's checksum ("<hash>  <name>", LF; sha256sum -c reads it)
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$NotesFile
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$utf8NoBom = New-Object Text.UTF8Encoding $false

if (git status --porcelain) { throw 'Working tree is not clean.' }

# CI gate: every CI run of HEAD must be finished and green. A local pass is not enough (CI has an
# 8.3 temp path, a clean module path and the interface build); two releases once went out while
# CI was red. Runs are looked up by the commit, not the branch, so a release from a worktree on its
# own branch (lessons: committed build output) finds the runs of the commit that main pushed.
$head = (git rev-parse HEAD).Trim()
# CI skips a push that changes only Markdown (ci.yml paths-ignore "**.md"), so the release commit
# that only moves the CHANGELOG section has no run (v0.12.17, 2026-11-20). The runs checked are then
# those of the nearest commit before it that changed anything else; the commits in between changed
# only Markdown, which CI does not test.
$ciCommit = $head
for ($i = 0; $i -lt 50; $i++) {
    $files = @(git diff-tree --no-commit-id --name-only -r $ciCommit | Where-Object { $_ })
    if (@($files | Where-Object { $_ -notlike '*.md' }).Count) { break }
    $ciCommit = (git rev-parse "$ciCommit^").Trim()
}
if ($ciCommit -ne $head) { Write-Host "HEAD changes only Markdown (CI skips it): checking the CI of $($ciCommit.Substring(0, 7))." }
$json = (gh run list --commit $ciCommit --json status,conclusion,workflowName) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'gh run list failed: is gh signed in?' }
$parsed = $json | ConvertFrom-Json   # assigned first: PS 5.1 hands a JSON array over as one object
$runs = @($parsed)
if (-not $runs.Count) { throw "No CI run found for $ciCommit. Push and let CI finish first." }
$notGreen = @($runs | Where-Object { $_.status -ne 'completed' -or $_.conclusion -ne 'success' })
if ($notGreen.Count) { throw "CI for HEAD is not green: $(($notGreen | ForEach-Object { "$($_.workflowName) $($_.status)/$($_.conclusion)" }) -join ', '). Fix it before releasing." }

$plain = $Version.TrimStart('v')

# Write without BOM: Set-Content -Encoding utf8 adds one on PS 5.1.
[IO.File]::WriteAllText((Join-Path $root 'version.txt'), "$plain`n", $utf8NoBom)

& powershell -NoProfile -File (Join-Path $PSScriptRoot 'run-tests.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }

# Commit message via file: inline -m with quotes breaks on PS 5.1.
$msg = Join-Path $env:TEMP "release-msg-$plain.txt"
[IO.File]::WriteAllText($msg, "Release $Version`n", $utf8NoBom)
git add version.txt
git commit -F $msg
git tag -a $Version -m $Version

# Stage the tagged tree as ObsidiNote\ (git archive: line endings as .gitattributes says), drop what
# only development needs, then add version.txt and manifest.json. The interface ships prebuilt in
# ui\ (listed in manifest.json like every file); its source ui-src\ and the tokens it imports
# (src\) are development only: the user's PC never runs Node.
$out = Join-Path $root 'release'
New-Item -ItemType Directory -Force $out | Out-Null
$stage = Join-Path $env:TEMP ('obsidinote-release-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$raw = "$stage.zip"
git archive --format=zip --prefix=ObsidiNote/ -o $raw $Version
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($raw, $stage)
[IO.File]::Delete($raw)
$app = Join-Path $stage 'ObsidiNote'
if (-not (Test-Path -LiteralPath (Join-Path $app 'ui\index.html'))) { throw 'The release has no ui\index.html: run npm run build in ui-src and commit ui\ first.' }
foreach ($dev in '.github', '.claude', '.gitattributes', '.gitignore', '.editorconfig', 'probes', 'tests', 'tasks', 'temp', 'ui-src', 'src') {
    $p = Join-Path $app $dev
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
# Never ship machine-specific files.
Get-ChildItem $app -Recurse -File -Force | Where-Object { $_.Name -like '*.local.json' } | ForEach-Object { [IO.File]::Delete($_.FullName) }
[IO.File]::WriteAllText((Join-Path $app 'version.txt'), $Version, $utf8NoBom)
Import-Module (Join-Path $root 'lib\Update.psm1') -Force
$listed = New-InstallManifest -AppFolder $app -Version $Version
Write-Host "manifest.json: $listed files"

# tar.exe from System32 writes forward-slash zip entries (-a picks zip from the .zip name);
# Compress-Archive on 5.1 does not, and GNU tar from Git Bash would come first on PATH.
$zip = Join-Path $out "ObsidiNote-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
& "$env:SystemRoot\System32\tar.exe" -a -c -f $zip -C $stage ObsidiNote
if ($LASTEXITCODE -ne 0) { throw 'tar failed to write the zip.' }
[IO.Directory]::Delete($stage, $true)

# SHA-256 via .NET (New-ReleaseChecksums): Get-FileHash is missing when 5.1 is started from pwsh 7.
$sums = Join-Path $out 'SHA256SUMS'
$null = New-ReleaseChecksums -Files @($zip) -OutFile $sums
Write-Host "Built $zip and $sums"

git push
git push origin $Version
gh release create $Version $zip $sums --title "ObsidiNote $Version" --notes-file $NotesFile
git fetch --tags
