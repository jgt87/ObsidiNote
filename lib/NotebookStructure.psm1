# ObsidiNote's notebook structure: the fixed sections, the type -> bucket rule, the 500-page
# rollover, the link bucket rule with URL normalization, hierarchy parsing, and creating the fixed
# structure under a vault root (lib/Vault.psm1 decides which root).
# FEASIBILITY.md section 5 (Notebook structure; Links). PS 5.1, ASCII only. Writes nothing to disk.
# COM goes through an adapter (lib/OneNote.psm1 New-OneNoteComAdapter, or a test stand-in).
Set-StrictMode -Version 2.0

# Fixed layout. Order = order of creation in a new notebook.
# '01 Intake' was '01 Inbox' until 2026-11-13 (user: "Inbox" reads like ObsidiNote pulls mail);
# Install-ObsnStructure renames an existing vault's own '01 Inbox' once (Get-LegacyIntakeSection).
$script:IntakeSection = '01 Intake'
$script:LegacyIntakeSection = '01 Inbox'
$script:FixedSections = @('00 Index', '01 Intake', 'Notes', 'Internal links', 'Web links', 'Sources', 'People', 'Projects', 'Meetings', 'Decisions', 'Files')
$script:FixedGroups = @('Journal', 'Archive')
$script:Buckets = @('Notes', 'Internal links', 'Web links', 'Sources', 'People', 'Projects', 'Meetings', 'Decisions', 'Journal', 'Files')
$script:TypeBucket = [ordered]@{
    'concept' = 'Notes'; 'note' = 'Notes'; 'howto' = 'Notes'
    'link-internal' = 'Internal links'; 'link-web' = 'Web links'
    'source' = 'Sources'; 'person' = 'People'
    'project' = 'Projects'; 'project-part' = 'Projects'
    'meeting' = 'Meetings'; 'decision' = 'Decisions'
    'log' = 'Journal'; 'file' = 'Files'
}
$script:MaxPagesPerSection = 500

# Microsoft 365 hosts that make a link "internal". '*.x' matches x and any subdomain of x.
$script:InternalHostRules = @('*.sharepoint.com', 'teams.microsoft.com', 'teams.cloud.microsoft', '*.loop.cloud.microsoft', 'loop.microsoft.com', '*.office.com', 'm365.cloud.microsoft')
# Company data in a SaaS tenant is internal too (user, 2026-11-13: "Workday where a timesheet can be
# hosted, or internal vacancies are published"). These hosts are a company's own tenant whenever
# there is a subdomain (wd3.myworkday.com/<company>/..., <company>.service-now.com); the vendor's
# public pages (www., docs., community. ...) are not.
$script:TenantSaasRules = @(
    '*.myworkday.com', '*.service-now.com', '*.servicenowservices.com', '*.atlassian.net', '*.okta.com', '*.oktapreview.com',
    '*.okta-emea.com', '*.my.salesforce.com', '*.lightning.force.com', '*.successfactors.com', '*.successfactors.eu',
    '*.sapsf.com', '*.sapsf.eu', '*.slack.com', '*.zendesk.com', '*.webex.com', '*.zoom.us', '*.workplace.com',
    '*.ultipro.com', '*.coupahost.com', '*.concursolutions.com', '*.freshservice.com')
$script:PublicLabels = @('www', 'docs', 'doc', 'help', 'support', 'developer', 'developers', 'community', 'status', 'api', 'blog', 'trust', 'learn', 'events', 'investor', 'investors', 'careers', 'jobs')
# Public by nature, even with the company's name in the host: job boards and public site hosting.
$script:PublicHostRules = @('*.myworkdayjobs.com', '*.github.io', '*.blogspot.com', '*.wordpress.com', '*.medium.com', '*.substack.com',
    '*.tumblr.com', '*.wixsite.com', '*.netlify.app', '*.vercel.app', '*.pages.dev', '*.greenhouse.io', '*.lever.co', '*.smartrecruiters.com')
# Query parameters dropped before comparing URLs (tracking only; never a sharing token).
$script:TrackingParams = '^(utm_.*|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|twclid|li_fat_id|mc_cid|mc_eid|igshid|_hsenc|_hsmi|mkt_tok|vero_id|vero_conv|oly_anon_id|oly_enc_id|_ga|_gl|wt\.mc_id|ocid|ref_src|spm)$'

function Get-ObsnFixedSections { , @($script:FixedSections) }
function Get-ObsnIntakeSection { $script:IntakeSection }
function Get-ObsnBuckets { , @($script:Buckets) }
function Get-ObsnTypes { , @($script:TypeBucket.Keys) }

function Get-BucketForType {
    <# The bucket (section) for a page type from the fixed list. 'log' -> 'Journal/<year>'.
       Any other type throws: a new bucket is a design change, not something Copilot invents. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Type, [int]$Year = (Get-Date).Year)
    $t = $Type.Trim().ToLowerInvariant()
    if (-not $script:TypeBucket.Contains($t)) { throw "Unknown page type '$Type'. Allowed: $(@($script:TypeBucket.Keys) -join ', ')" }
    $b = $script:TypeBucket[$t]
    if ($b -eq 'Journal') { return "Journal/$Year" }
    return $b
}

function Get-TargetSection {
    <# Where a new page of $Bucket goes: the bucket section, or its rollover '<Bucket> 2', '<Bucket> 3'...
       when it holds $Max pages. $Counts: section full name ('Notes', 'Journal/2026') -> page count.
       Returns @{ name (full); group; leaf; exists }. Pure. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Bucket, [hashtable]$Counts = @{}, [int]$Max = $script:MaxPagesPerSection)
    $group = ''; $leaf = $Bucket
    $slash = $Bucket.LastIndexOf('/')
    if ($slash -ge 0) { $group = $Bucket.Substring(0, $slash); $leaf = $Bucket.Substring($slash + 1) }
    for ($n = 1; $n -lt 10000; $n++) {
        $l = if ($n -eq 1) { $leaf } else { "$leaf $n" }
        $full = if ($group) { "$group/$l" } else { $l }
        $exists = $Counts.ContainsKey($full)
        $c = if ($exists) { [int]$Counts[$full] } else { 0 }
        if ($c -lt $Max) { return @{ name = $full; group = $group; leaf = $l; exists = $exists } }
    }
    throw "No room in bucket $Bucket"
}

function Get-ArchiveSectionName {
    <# 'Archive/<bucket>' for a page that is archived from $Bucket ('Journal/2026' -> 'Archive/Journal';
       a rollover section 'Notes 2' -> 'Archive/Notes'). #>
    param([Parameter(Mandatory)][string]$Bucket)
    "Archive/" + (Get-BucketOfSection $Bucket)
}

function Get-BucketOfSection {
    <# The bucket a section belongs to: 'Notes 2' -> 'Notes', 'Journal/2026' -> 'Journal',
       'Archive/Web links' -> 'Archive', '00 Index' -> '00 Index'; '' for a section the user made. #>
    param([Parameter(Mandatory)][string]$Section)
    $parts = $Section.Split('/')
    if ($parts.Count -eq 1) {
        if ($script:FixedSections -contains $Section) { return $Section }
        foreach ($b in $script:Buckets) { if ($Section -match ('^' + [regex]::Escape($b) + ' [2-9][0-9]*$')) { return $b } }
        return ''
    }
    if ($parts.Count -eq 2 -and $parts[0] -eq 'Journal' -and $parts[1] -match '^[0-9]{4}( [2-9][0-9]*)?$') { return 'Journal' }
    if ($parts.Count -eq 2 -and $parts[0] -eq 'Archive') {
        $inner = $parts[1] -replace ' [2-9][0-9]*$', ''
        if ($script:Buckets -contains $inner) { return 'Archive' }
    }
    return ''
}

function Test-ObsnOwnedSection { param([string]$Section) [bool](Get-BucketOfSection $Section) }

function Get-UrlParts {
    param([string]$Url)
    $m = [regex]::Match($Url.Trim(), '^(?i)(https?)://([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$')
    if (-not $m.Success) { return $null }
    $hostPort = $m.Groups[2].Value
    $at = $hostPort.LastIndexOf('@')
    if ($at -ge 0) { $hostPort = $hostPort.Substring($at + 1) }
    @{ scheme = $m.Groups[1].Value.ToLowerInvariant(); hostPort = $hostPort.ToLowerInvariant(); path = $m.Groups[3].Value; query = $m.Groups[4].Value }
}

function Get-UrlHost {
    <# The host of an http(s) URL, lower case, without port; '' when it is not one. #>
    param([string]$Url)
    $p = Get-UrlParts $Url
    if (-not $p) { return '' }
    ($p.hostPort -replace ':[0-9]+$', '').TrimEnd('.')
}

function ConvertTo-NormalizedUrl {
    <# The URL used to find "the same link": lower-case scheme and host, default port dropped, the
       fragment dropped, tracking parameters (utm_* and the like) dropped, other parameters kept in
       their order. A string that is not an http(s) URL comes back trimmed. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url)
    $p = Get-UrlParts $Url
    if (-not $p) { return $Url.Trim() }
    $hp = $p.hostPort.TrimEnd('.')
    if ($p.scheme -eq 'https') { $hp = $hp -replace ':443$', '' } else { $hp = $hp -replace ':80$', '' }
    $path = if ($p.path) { $p.path } else { '/' }
    $keep = @()
    if ($p.query.Length -gt 1) {
        foreach ($kv in $p.query.Substring(1).Split('&')) {
            if (-not $kv) { continue }
            $k = ($kv.Split('=')[0])
            try { $k = [Uri]::UnescapeDataString($k) } catch { }
            if ($k.ToLowerInvariant() -match $script:TrackingParams) { continue }
            $keep += $kv
        }
    }
    $q = if ($keep.Count) { '?' + ($keep -join '&') } else { '' }
    "$($p.scheme)://$hp$path$q"
}

function Test-HostRule {
    param([string]$HostName, [string]$Rule)
    $r = $Rule.Trim().ToLowerInvariant()
    if (-not $r) { return $false }
    if ($r.StartsWith('*.')) { $base = $r.Substring(2); return ($HostName -eq $base -or $HostName.EndsWith('.' + $base)) }
    if ($r.StartsWith('.')) { $base = $r.Substring(1); return ($HostName -eq $base -or $HostName.EndsWith('.' + $base)) }
    return $HostName -eq $r
}

function Get-CompanyNames {
    <# The company's tenant names, from Microsoft 365 addresses it owns (the vault's notebook location,
       a OneDrive or SharePoint URL: 'contoso-my.sharepoint.com' -> 'contoso'). Lower case, at least 3
       characters, unique. Nothing is stored: the names come from the open vault at run time. #>
    param([string[]]$Locations = @())
    $names = @(foreach ($l in @($Locations | Where-Object { $_ })) {
        $u = ([string]$l) -replace '^(?i)onenote:', ''
        $h = Get-UrlHost $u
        if ($h -match '^([a-z0-9][a-z0-9-]*?)(-my|-admin|-files)?\.sharepoint\.com$') { $Matches[1] }
    })
    # Plain pipeline output: callers wrap the call in @() (a ', @()' return would nest there).
    $names | Where-Object { $_.Length -ge 3 } | Select-Object -Unique
}

function Test-TenantHost {
    <# A SaaS host that is a company tenant: a TenantSaasRules host with a subdomain that is not one of
       the vendor's public pages. #>
    param([string]$HostName)
    foreach ($r in $script:TenantSaasRules) {
        $base = $r.Substring(2)
        if (-not $HostName.EndsWith('.' + $base)) { continue }
        $sub = $HostName.Substring(0, $HostName.Length - $base.Length - 1)
        if ($script:PublicLabels -notcontains $sub.Split('.')[0]) { return $true }
    }
    $false
}

function Test-CompanyHost {
    <# The company's name in a subdomain of someone else's host (contoso.zoom.us, contosoitsm.example-saas.com,
       hr-contoso.example.net): a service run for the company. The company's own domain (contoso.com,
       www.contoso.com) is its public web site and does not count. #>
    param([string]$HostName, [string[]]$CompanyNames = @())
    $labels = $HostName.Split('.')
    if ($labels.Count -lt 3) { return $false }
    $domain = $labels[$labels.Count - 2]
    foreach ($n in @($CompanyNames | Where-Object { $_ })) {
        if ($domain -eq $n) { continue }
        for ($i = 0; $i -lt $labels.Count - 2; $i++) {
            $l = $labels[$i]
            if ($l -eq $n -or $l.StartsWith($n) -or $l -match ('(^|-)' + [regex]::Escape($n) + '(-|$)')) { return $true }
        }
    }
    $false
}

function Get-LinkBucket {
    <# 'Internal links' for company data, 'Web links' for public pages. Fixed rules, no model, in order:
       1. Microsoft 365 hosts (SharePoint incl. OneDrive -my, Teams, Loop, office.com, m365.cloud.microsoft)
          and the hosts in $InternalHosts (exact host, '*.domain' or '.domain'): internal.
       2. Public by nature (job boards, public site hosting): web.
       3. A SaaS host that is a company tenant (Workday, ServiceNow, Atlassian, Okta, ...): internal.
       4. The company's name (from $CompanyNames, see Get-CompanyNames) in a subdomain of another
          company's host: internal.
       5. Everything else, including the company's own public domain: web. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url, [string[]]$InternalHosts = @(), [string[]]$CompanyNames = @())
    $h = Get-UrlHost $Url
    if (-not $h) { return 'Web links' }
    foreach ($r in @($script:InternalHostRules + @($InternalHosts | Where-Object { $_ }))) {
        if (Test-HostRule -HostName $h -Rule $r) { return 'Internal links' }
    }
    foreach ($r in $script:PublicHostRules) { if (Test-HostRule -HostName $h -Rule $r) { return 'Web links' } }
    if (Test-TenantHost $h) { return 'Internal links' }
    if (Test-CompanyHost -HostName $h -CompanyNames @($CompanyNames | ForEach-Object { "$_".ToLowerInvariant() })) { return 'Internal links' }
    return 'Web links'
}

function ConvertFrom-ObsnHierarchy {
    <# Parses GetHierarchy XML (from the notebook, or from the notebooks root with -Name) into
       @{ notebook = @{ id; name; path }; groups = @(@{ id; name; full });
          sections = @(@{ id; name; full; group; pages = @(@{ id; title; level; updated; section; meta }) });
          nestedVaults = @(@{ id; name; full }) }. Section groups that hold a `00 Index` section are other
       vaults' roots and are listed in nestedVaults, not parsed.
       The recycle bin and its pages are left out. meta = page-level one:Meta name -> content. Pure. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Xml, [string]$Name = '', [string]$RootId = '')
    [xml]$doc = $Xml
    $root = $doc.DocumentElement
    $nb = $null
    if ($RootId) {
        # A vault root (notebook or section group) anywhere in the XML; paths are relative to it.
        foreach ($n in @($doc.SelectNodes('//*[@ID]'))) { if ($n.GetAttribute('ID') -eq $RootId) { $nb = $n; break } }
    }
    elseif ($root.LocalName -eq 'Notebook' -or $root.LocalName -eq 'SectionGroup') { $nb = $root }
    else {
        foreach ($n in @($root.ChildNodes)) {
            if ($n.LocalName -eq 'Notebook' -and (-not $Name -or $n.GetAttribute('name') -eq $Name -or $n.GetAttribute('nickname') -eq $Name)) { $nb = $n; break }
        }
    }
    if (-not $nb) { return $null }
    $res = @{ notebook = @{ id = $nb.GetAttribute('ID'); name = $nb.GetAttribute('name'); path = $nb.GetAttribute('path'); kind = $(if ($nb.LocalName -eq 'SectionGroup') { 'sectiongroup' } else { 'notebook' }) }; groups = New-Object System.Collections.ArrayList; sections = New-Object System.Collections.ArrayList; nestedVaults = New-Object System.Collections.ArrayList }
    Add-HierarchyChildren -Node $nb -Prefix '' -Result $res
    return $res
}

function Add-HierarchyChildren {
    param($Node, [string]$Prefix, [hashtable]$Result)
    foreach ($c in @($Node.ChildNodes)) {
        if ($c.NodeType -ne 'Element') { continue }
        if ($c.GetAttribute('isRecycleBin') -eq 'true' -or $c.GetAttribute('isInRecycleBin') -eq 'true') { continue }
        $full = if ($Prefix) { "$Prefix/$($c.GetAttribute('name'))" } else { $c.GetAttribute('name') }
        if ($c.LocalName -eq 'SectionGroup') {
            # A section group holding `00 Index` is another vault's root: not part of this tree.
            $nested = @($c.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Section' -and $_.GetAttribute('name') -eq '00 Index' }).Count
            if ($nested) { $null = $Result.nestedVaults.Add(@{ id = $c.GetAttribute('ID'); name = $c.GetAttribute('name'); full = $full }); continue }
            $null = $Result.groups.Add(@{ id = $c.GetAttribute('ID'); name = $c.GetAttribute('name'); full = $full })
            Add-HierarchyChildren -Node $c -Prefix $full -Result $Result
        } elseif ($c.LocalName -eq 'Section') {
            $pages = New-Object System.Collections.ArrayList
            foreach ($p in @($c.ChildNodes)) {
                if ($p.NodeType -ne 'Element' -or $p.LocalName -ne 'Page') { continue }
                if ($p.GetAttribute('isInRecycleBin') -eq 'true') { continue }
                $meta = @{}
                foreach ($m in @($p.ChildNodes)) { if ($m.NodeType -eq 'Element' -and $m.LocalName -eq 'Meta') { $meta[$m.GetAttribute('name')] = $m.GetAttribute('content') } }
                $lvl = 1; [void][int]::TryParse($p.GetAttribute('pageLevel'), [ref]$lvl)
                $null = $pages.Add(@{ id = $p.GetAttribute('ID'); title = $p.GetAttribute('name'); level = $lvl; updated = $p.GetAttribute('lastModifiedTime'); section = $full; meta = $meta })
            }
            $grp = if ($Prefix) { $Prefix } else { '' }
            $null = $Result.sections.Add(@{ id = $c.GetAttribute('ID'); name = $c.GetAttribute('name'); full = $full; group = $grp; locked = ($c.GetAttribute('locked') -eq 'true'); pages = $pages })
        }
    }
}

function Get-StructurePlan {
    <# What Initialize-ObsidiNotebook has to create, from a parsed hierarchy. Pure.
       Returns @{ missingGroups = @(names); missingSections = @(full names); present = @(full names);
       userSections = @(full names) }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Tree, [int]$Year = (Get-Date).Year)
    $want = @($script:FixedSections) + @("Journal/$Year")
    $haveSections = @($Tree.sections | ForEach-Object { $_.full })
    $haveGroups = @($Tree.groups | ForEach-Object { $_.full })
    $missingGroups = @($script:FixedGroups | Where-Object { $haveGroups -notcontains $_ })
    $missingSections = @($want | Where-Object { $haveSections -notcontains $_ })
    $present = @(@($want | Where-Object { $haveSections -contains $_ }) + @($script:FixedGroups | Where-Object { $haveGroups -contains $_ }))
    $user = @($haveSections | Where-Object { -not (Test-ObsnOwnedSection $_) })
    @{ missingGroups = $missingGroups; missingSections = $missingSections; present = $present; userSections = $user }
}

function Get-NotebookBasePath {
    <# The folder for a new notebook: -Location, else the folder of the first open cloud notebook. #>
    param([string]$NotebooksXml, [string]$Location = '')
    if ($Location) { return ($Location.TrimEnd('/', '\') + $(if ($Location -match '^(?i)https?://') { '/' } else { '\' })) }
    [xml]$doc = $NotebooksXml
    foreach ($n in @($doc.DocumentElement.ChildNodes)) {
        if ($n.NodeType -ne 'Element' -or $n.LocalName -ne 'Notebook') { continue }
        $p = $n.GetAttribute('path')
        if ($p -match '^(?i)https://') { $t = $p.TrimEnd('/'); return $t.Substring(0, $t.LastIndexOf('/') + 1) }
    }
    throw 'No cloud notebook is open to put the new notebook next to. Open one in OneNote, or pass -Location.'
}


function Get-LegacyIntakeSection {
    <# The id of an existing vault's own '01 Inbox' section that is to become '01 Intake', or ''.
       Only a section directly in the vault root, only in a root that already has '00 Index' (an
       existing vault, never a notebook being set up), and only while no '01 Intake' exists: when both
       exist, '01 Inbox' stays as it is and counts as a section the user made. Pure. #>
    param([Parameter(Mandatory)][hashtable]$Tree)
    $root = @($Tree.sections | Where-Object { -not $_.group })
    $names = @($root | ForEach-Object { $_.name })
    if ($names -notcontains '00 Index' -or $names -contains $script:IntakeSection) { return '' }
    $old = @($root | Where-Object { $_.name -eq $script:LegacyIntakeSection }) | Select-Object -First 1
    if ($old) { return [string]$old.id }
    ''
}

function Install-ObsnStructure {
    <# Creates what Get-StructurePlan says is missing under the vault root $RootId (a notebook or a
       section group): groups Journal and Archive, the fixed sections, Journal/<year>. The one rename:
       an existing vault's own '01 Inbox' becomes '01 Intake' (Get-LegacyIntakeSection; its pages keep
       their ids and links). Never renames, moves or opens anything else. Writes go through the
       guarded adapter. Returns @{ created; present; userSections; sectionIds (full name -> id) }. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$RootId, [int]$Year = (Get-Date).Year)
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 3)) -RootId $RootId
    if (-not $tree) { throw "Vault root $RootId not found." }
    $created = New-Object System.Collections.ArrayList
    $legacy = Get-LegacyIntakeSection -Tree $tree
    if ($legacy) {
        $Adapter.RenameSection($legacy, $script:IntakeSection)
        $null = $created.Add("renamed section $($script:LegacyIntakeSection) to $($script:IntakeSection)")
        $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 3)) -RootId $RootId
    }
    $plan = Get-StructurePlan -Tree $tree -Year $Year
    $groupIds = @{}
    foreach ($g in $tree.groups) { $groupIds[$g.full] = $g.id }
    foreach ($g in $plan.missingGroups) {
        $groupIds[$g] = $Adapter.OpenHierarchy($g, $RootId, 2)
        $null = $created.Add("group $g")
    }
    foreach ($s in $plan.missingSections) {
        $parts = $s.Split('/')
        if ($parts.Count -eq 2) { $null = $Adapter.OpenHierarchy("$($parts[1]).one", $groupIds[$parts[0]], 3) }
        else { $null = $Adapter.OpenHierarchy("$s.one", $RootId, 3) }
        $null = $created.Add("section $s")
    }
    $final = if ($created.Count) { ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 3)) -RootId $RootId } else { $tree }
    $ids = @{}
    foreach ($s in $final.sections) { $ids[$s.full] = $s.id }
    foreach ($g in $final.groups) { $ids[$g.full] = $g.id }
    @{ created = @($created); present = @($plan.present); userSections = @($plan.userSections); sectionIds = $ids }
}

function Resolve-ObsnSection {
    <# The id of section $Full ('Notes 2', 'Journal/2027', 'Archive/Web links') under the vault root,
       creating it (and its group) when missing. Only for ObsidiNote's own sections. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)][string]$RootId, [Parameter(Mandatory)][string]$Full)
    if (-not (Test-ObsnOwnedSection $Full)) { throw "'$Full' is not one of ObsidiNote's sections." }
    $tree = ConvertFrom-ObsnHierarchy -Xml ($Adapter.GetHierarchy($RootId, 3)) -RootId $RootId
    foreach ($s in $tree.sections) { if ($s.full -eq $Full) { return $s.id } }
    $parts = $Full.Split('/')
    if ($parts.Count -eq 1) { return $Adapter.OpenHierarchy("$Full.one", $RootId, 3) }
    $gid = $null
    foreach ($g in $tree.groups) { if ($g.full -eq $parts[0]) { $gid = $g.id } }
    if (-not $gid) { $gid = $Adapter.OpenHierarchy($parts[0], $RootId, 2) }
    $Adapter.OpenHierarchy("$($parts[1]).one", $gid, 3)
}

Export-ModuleMember -Function Get-ObsnFixedSections, Get-ObsnIntakeSection, Get-LegacyIntakeSection,Get-ObsnBuckets, Get-ObsnTypes, Get-BucketForType, Get-TargetSection, Get-ArchiveSectionName, Get-BucketOfSection, Test-ObsnOwnedSection, Get-UrlHost, ConvertTo-NormalizedUrl, Get-LinkBucket, Get-CompanyNames, ConvertFrom-ObsnHierarchy, Get-StructurePlan, Get-NotebookBasePath, Install-ObsnStructure, Resolve-ObsnSection