# Test stand-ins for lib/Ingest.psm1: an in-memory store adapter (the contract of
# Get-IngestStoreContract) and a Copilot that answers from a queue. Dot-source this file.
# No OneNote, no Edge, no disk: every page lives in the $st hashtable of the fake.

function New-FakeIndex {
    @{
        pages = @(
            @{ id = 'p1'; title = 'Zero-trust networking'; type = 'concept'; section = 'Notes'; pageId = '{P1}'; link = 'onenote:#p1'; summary = 'Never trust the network: every request checks the user and the device.'; aliases = @('ZTN'); topics = @('Security/Networking'); links = @() }
            @{ id = 'p2'; title = 'Partner portal: access review notes'; type = 'meeting'; section = 'Meetings'; pageId = '{P2}'; link = 'onenote:#p2'; summary = 'Who may reach the partner portal and how access is reviewed.'; aliases = @(); topics = @('Projects/Partner portal'); links = @() }
            @{ id = 'p3'; title = 'VPN retirement plan'; type = 'project-part'; section = 'Projects'; pageId = '{P3}'; link = 'onenote:#p3'; summary = 'Steps to switch off the old VPN.'; aliases = @(); topics = @('Security/Networking'); links = @(@{ target = 'p1'; strength = 2; why = 'replaced by' }) }
            @{ id = 'p4'; title = 'Device trust checklist'; type = 'howto'; section = 'Notes'; pageId = '{P4}'; link = 'onenote:#p4'; summary = 'What a device needs before it is trusted.'; aliases = @(); topics = @('Security'); links = @() }
            @{ id = 'p5'; title = 'Single sign-on setup'; type = 'howto'; section = 'Notes'; pageId = '{P5}'; link = 'onenote:#p5'; summary = 'How sign-in works for the portal users.'; aliases = @('SSO'); topics = @('Security/Identity'); links = @() }
            @{ id = 'p6'; title = 'Sourdough bread'; type = 'note'; section = 'Notes'; pageId = '{P6}'; link = 'onenote:#p6'; summary = 'Flour, water, salt and time.'; aliases = @(); topics = @('Cooking'); links = @() }
            @{ id = 'p7'; title = 'Contoso handbook'; type = 'link-internal'; section = 'Internal links'; pageId = '{P7}'; link = 'onenote:#p7'; summary = 'The staff handbook.'; aliases = @(); topics = @('Projects'); links = @(@{ target = 'p4'; strength = 1; why = 'device rules' }); url = 'https://contoso.sharepoint.com/sites/hr/handbook.aspx' }
        )
        topics = @('Security', 'Security/Networking', 'Security/Identity', 'Projects', 'Projects/Partner portal', 'Cooking')
        edges = @(@{ from = 'p3'; to = 'p1'; strength = 2; why = 'replaced by' })
    }
}

function New-FakeVault {
    <# Returns @{ store; st }. $st records every call; set $st.writable = $false to make the
       write guard refuse, or $st.fail['CreatePage'] = 'message' to make one call throw. #>
    $st = @{
        index = (New-FakeIndex)
        writable = $true
        fail = @{}
        calls = (New-Object System.Collections.Generic.List[string])
        counter = 100
        inbox = @{}
        created = @{}
        content = @{}
        updates = (New-Object System.Collections.Generic.List[object])
        linkedFrom = @{}
        deleted = (New-Object System.Collections.Generic.List[string])
        indexOps = (New-Object System.Collections.Generic.List[object])
    }
    $st.content['{P7}'] = @{
        meta = @{ type = 'link-internal'; url = 'https://contoso.sharepoint.com/sites/hr/handbook.aspx'; summarizedAt = '2026-08-01'; summaryHash = ''; history = '[]'; seenAt = ''
            linkSummary = '{"title":"Contoso handbook","where":"HR site","kind":"page","summary":"The staff handbook. Covers leave and devices.","keyFacts":["Leave is 25 days","Devices are managed"],"useFor":"Policy questions","sensitivity":"General"}' }
        outlines = @(@{ role = 'summary'; text = 'Link: https://contoso.sharepoint.com/sites/hr/handbook.aspx' }, @{ role = 'notes'; text = 'Your notes' })
    }
    $guard = {
        param([string]$What)
        $st.calls.Add($What)
        if ($st.fail.ContainsKey($What)) { throw $st.fail[$What] }
        if (-not $st.writable) { throw "Write refused ($What): the target is outside the active vault." }
    }.GetNewClosure()
    $types = @('concept', 'note', 'howto', 'link-internal', 'link-web', 'source', 'person', 'project', 'project-part', 'meeting', 'decision', 'log', 'file')
    $buckets = @{ concept = 'Notes'; note = 'Notes'; howto = 'Notes'; 'link-internal' = 'Internal links'; 'link-web' = 'Web links'; source = 'Sources'; person = 'People'; project = 'Projects'; 'project-part' = 'Projects'; meeting = 'Meetings'; decision = 'Decisions'; log = 'Journal/2026'; file = 'Files' }
    $store = @{
        AssertWritable = { & $guard 'AssertWritable' }.GetNewClosure()
        VaultName = { 'ObsidiNote' }
        GetIndex = { $st.calls.Add('GetIndex'); $st.index }.GetNewClosure()
        TypeList = { $types }.GetNewClosure()
        BucketForType = { param([string]$Type) if (-not $buckets.ContainsKey($Type)) { throw "Unknown page type '$Type'" }; $buckets[$Type] }.GetNewClosure()
        LinkBucket = { param([string]$Url) if ($Url -match '(?i)^https?://[^/]*sharepoint\.com') { 'Internal links' } else { 'Web links' } }
        NormalizeUrl = { param([string]$Url) $u = $Url.Trim() -replace '#.*$', ''; $u = $u -replace '([?&])utm_[a-z]+=[^&]*&?', '$1'; $u.TrimEnd('?', '&') }
        FindPageByUrl = { param([string]$Url) $st.calls.Add('FindPageByUrl'); @($st.index.pages | Where-Object { $_.ContainsKey('url') -and $_['url'] -eq $Url })[0] }.GetNewClosure()
        NewId = { $st.counter++; 'p' + $st.counter }.GetNewClosure()
        CreateInboxItem = { param([string]$Title, [string]$Text, [string]$Kind)
            & $guard 'CreateInboxItem'
            $pid2 = '{IN' + $st.inbox.Count + '}'
            $st.inbox[$pid2] = @{ title = $Title; kind = $Kind; status = 'new'; reason = ''; filedAs = '' }
            @{ pageId = $pid2; link = "onenote:#$pid2" }
        }.GetNewClosure()
        SetInboxStatus = { param([string]$PageId, [string]$Status, [string]$Reason, [string]$Id)
            & $guard 'SetInboxStatus'
            $st.inbox[$PageId].status = $Status; $st.inbox[$PageId].reason = $Reason; $st.inbox[$PageId].filedAs = $Id
        }.GetNewClosure()
        CreatePage = { param([hashtable]$Page)
            & $guard 'CreatePage'
            $pid2 = '{NEW-' + $Page['id'] + '}'
            $st.created[$pid2] = $Page
            @{ pageId = $pid2; link = "onenote:#$($Page['id'])"; section = $Page['bucket'] }
        }.GetNewClosure()
        ReadPage = { param([string]$PageId) $st.calls.Add('ReadPage'); $st.content[$PageId] }.GetNewClosure()
        UpdatePage = { param([string]$PageId, [hashtable]$Meta, [object[]]$Outlines, [string]$Title)
            & $guard 'UpdatePage'
            $st.updates.Add(@{ pageId = $PageId; meta = $Meta; outlines = @($Outlines); title = $Title })
        }.GetNewClosure()
        SetLinkedFrom = { param([string]$Id, [object[]]$Sources)
            & $guard 'SetLinkedFrom'
            $st.linkedFrom[$Id] = @($Sources)
        }.GetNewClosure()
        DeletePage = { param([string]$PageId) & $guard 'DeletePage'; $st.deleted.Add($PageId) }.GetNewClosure()
        IndexAddPage = { param([hashtable]$Page) & $guard 'IndexAddPage'; $st.indexOps.Add(@{ op = 'add'; page = $Page }); $st.index.pages = @($st.index.pages) + $Page }.GetNewClosure()
        IndexUpdatePage = { param([hashtable]$Page) & $guard 'IndexUpdatePage'; $st.indexOps.Add(@{ op = 'update'; page = $Page }) }.GetNewClosure()
        IndexRemovePage = { param([string]$Id) & $guard 'IndexRemovePage'; $st.indexOps.Add(@{ op = 'remove'; id = $Id }); $st.index.pages = @($st.index.pages | Where-Object { $_['id'] -ne $Id }) }.GetNewClosure()
    }
    @{ store = $store; st = $st }
}

function New-FakeCopilot {
    <# A Copilot that answers from a queue of reply strings and records the prompts it got. #>
    param([string[]]$Replies = @())
    $q = @{ replies = (New-Object System.Collections.Generic.Queue[string]); prompts = (New-Object System.Collections.Generic.List[string]) }
    foreach ($r in $Replies) { $q.replies.Enqueue($r) }
    $ask = {
        param([string]$Prompt)
        $q.prompts.Add($Prompt)
        if ($q.replies.Count -eq 0) { throw 'no recorded reply left' }
        $q.replies.Dequeue()
    }.GetNewClosure()
    @{ ask = $ask; q = $q }
}
