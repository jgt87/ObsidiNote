# Where a dropped file lives online (operator, 2026-11-14: "If the file is from OneDrive then the link
# to the original file should be stored"). A browser never tells the page a dropped file's path, so
# the window sends its name, size and last-changed time, and this module looks for exactly that file
# in the folders OneDrive syncs on this PC. OneDrive's own records (HKCU\Software\SyncEngines\
# Providers\OneDrive\<id>: MountPoint = the local folder, UrlNamespace = its web address) turn the
# path into the file's address. Reads names, sizes and dates only: never a file's content, never
# writes; cloud-only placeholders are not downloaded (only their directory entries are read). The
# log gets counts and times only. PS 5.1, ASCII only.
Set-StrictMode -Version 2.0

$script:ProvidersKey = 'HKCU:\Software\SyncEngines\Providers\OneDrive'

function Resolve-SyncRootUrl {
    <# A synced folder's web address. Personal OneDrive stores only "https://d.docs.live.net/" as its
       UrlNamespace; its files live under /<cid>/, the account id in OneDrive\Accounts\Personal
       (seen on the dev PC, 2026-11-14). Work and SharePoint libraries carry their full address. Pure. #>
    param([Parameter(Mandatory)][string]$Url, [string]$PersonalCid = '')
    $u = [uri]$Url
    if ($u.Host -like '*.docs.live.net' -and $u.AbsolutePath -eq '/' ) {
        if (-not $PersonalCid) { return '' }
        return "https://$($u.Host)/$([Uri]::EscapeDataString($PersonalCid))/"
    }
    $Url
}

function Get-SyncRoots {
    <# The synced folders: @(@{ path; url }), the longest path first (a library synced inside another
       folder wins). Empty when OneDrive does not sync anything here. #>
    $out = @()
    if (-not (Test-Path -LiteralPath $script:ProvidersKey)) { return , @() }
    $cid = ''
    try { $cid = [string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal' -ErrorAction Stop).cid } catch { }
    foreach ($k in @(Get-ChildItem -LiteralPath $script:ProvidersKey -ErrorAction SilentlyContinue)) {
        try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
        $mount = if ($p.PSObject.Properties['MountPoint']) { [string]$p.MountPoint } else { '' }
        $url = if ($p.PSObject.Properties['UrlNamespace']) { [string]$p.UrlNamespace } else { '' }
        if ($url -match '^(?i)https://') { $url = Resolve-SyncRootUrl -Url $url -PersonalCid $cid }
        if ($mount -and $url -match '^(?i)https://' -and (Test-Path -LiteralPath $mount)) { $out += @{ path = $mount.TrimEnd('\'); url = $url } }
    }
    , @($out | Sort-Object { $_.path.Length } -Descending)
}

function ConvertTo-SyncedUrl {
    <# The web address of $Path under the synced folder $Root (@{ path; url }): the root's address plus
       the relative path, each part escaped. '' when $Path is not under $Root. Pure. #>
    param([Parameter(Mandatory)][hashtable]$Root, [Parameter(Mandatory)][string]$Path)
    $base = $Root.path.TrimEnd('\') + '\'
    if (-not $Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    $rel = $Path.Substring($base.Length)
    $parts = @($rel.Split('\') | Where-Object { $_ } | ForEach-Object { [Uri]::EscapeDataString($_) })
    $u = [string]$Root.url
    if (-not $u.EndsWith('/')) { $u += '/' }
    $u + ($parts -join '/')
}

function Find-SyncedFile {
    <# The synced file with exactly this name, size and last-changed time (within 2 s; OneDrive and
       file systems round differently): @{ status = found | none | many | no-sync; url; ms }. Walks
       the synced folders breadth first, skips folders it may not read, and stops after $TimeoutMs
       (status none). $Roots: from Get-SyncRoots (tests pass their own). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][int64]$Size, [Parameter(Mandatory)][datetime]$ModifiedUtc,
        [object[]]$Roots = $null, [int]$TimeoutMs = 4000, [int]$MaxFolders = 20000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if ($null -eq $Roots) { $Roots = Get-SyncRoots }
    if (-not @($Roots).Count) { return @{ status = 'no-sync'; url = ''; ms = [int]$sw.ElapsedMilliseconds } }
    $hits = New-Object System.Collections.Generic.List[string]
    $want = $ModifiedUtc.ToUniversalTime()
    $folders = 0
    foreach ($root in @($Roots)) {
        $queue = New-Object System.Collections.Generic.Queue[string]
        $queue.Enqueue([string]$root.path)
        while ($queue.Count -and $sw.ElapsedMilliseconds -lt $TimeoutMs -and $folders -lt $MaxFolders) {
            $dir = $queue.Dequeue()
            $folders++
            $di = New-Object System.IO.DirectoryInfo $dir
            try {
                foreach ($f in $di.EnumerateFiles($Name)) {
                    if ($f.Length -eq $Size -and [Math]::Abs(($f.LastWriteTimeUtc - $want).TotalSeconds) -le 2) { $hits.Add($f.FullName) }
                }
                # Online-only OneDrive folders are reparse points too, so they are followed; a
                # junction loop is cut by $TimeoutMs and $MaxFolders.
                foreach ($sub in $di.EnumerateDirectories()) { $queue.Enqueue($sub.FullName) }
            } catch { continue }
        }
        if ($hits.Count) { break }
    }
    $ms = [int]$sw.ElapsedMilliseconds
    if ($hits.Count -gt 1) { return @{ status = 'many'; url = ''; ms = $ms } }
    if (-not $hits.Count) { return @{ status = 'none'; url = ''; ms = $ms } }
    $path = $hits[0]
    foreach ($root in @($Roots)) {
        $u = ConvertTo-SyncedUrl -Root $root -Path $path
        if ($u) { return @{ status = 'found'; url = $u; ms = $ms } }
    }
    @{ status = 'none'; url = ''; ms = $ms }
}

Export-ModuleMember -Function Get-SyncRoots, Resolve-SyncRootUrl, ConvertTo-SyncedUrl, Find-SyncedFile
