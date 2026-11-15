# Invented OneNote pages (GetPageContent XML) for the page window's text, one per case of
# tests/fixtures/page-body.json: tests/PageBody.Tests.ps1 runs the real converter on each and
# compares with the fixture's "markdown", which the interface's renderer test reads too.
# Fictional names and example.com / team.example addresses only. ASCII only.

$script:BodyNs = 'http://schemas.microsoft.com/office/onenote/2013/onenote'
# The onenote: links of two other pages of the model: p2 (an obsn page) and a page ObsidiNote did not make.
$script:BodyLinkP2 = 'onenote:https://team.example/Notes.one#Partner%20portal&section-id={11111111-1111-1111-1111-111111111111}&page-id={22222222-2222-2222-2222-222222222222}&end'
$script:BodyOtherId = '{44444444-4444-4444-4444-444444444444}{1}{E1}'

function New-BodyOe([string]$Html, [string]$Inner = '', [string]$Attr = '') { "<one:OE$Attr>$Inner<one:T><![CDATA[$Html]]></one:T></one:OE>" }

function New-BodyOutline([string]$Role, [string]$Oes) {
    $meta = if ($Role) { '<one:Meta name="obsn.role" content="' + $Role + '" />' } else { '' }
    "<one:Outline>$meta<one:OEChildren>$Oes</one:OEChildren></one:Outline>"
}

function New-BodyPageXml([string]$Outlines, [string]$Defs = '') {
    "<?xml version=""1.0""?><one:Page xmlns:one=""$($script:BodyNs)"" ID=""{P1}"" name=""Identity-aware proxies"">$Defs<one:Title><one:OE><one:T><![CDATA[Identity-aware proxies]]></one:T></one:OE></one:Title>$Outlines</one:Page>"
}

function New-BodyCell([string]$Html) { '<one:Cell><one:OEChildren>' + (New-BodyOe $Html) + '</one:OEChildren></one:Cell>' }

function Get-PageBodyModel {
    <# The index model the cases are read against: p1 is the page itself. #>
    $pages = [ordered]@{}
    $pages['p1'] = @{ key = 'p1'; id = 'p1'; title = 'Identity-aware proxies'; link = 'onenote:#p1'; oneNoteId = '{P1}' }
    $pages['p2'] = @{ key = 'p2'; id = 'p2'; title = 'Partner portal'; link = $script:BodyLinkP2; oneNoteId = '{22222222-2222-2222-2222-222222222222}{1}{E1}' }
    $other = 'n:' + $script:BodyOtherId
    $pages[$other] = @{ key = $other; id = ''; title = 'Shopping list'; link = ''; oneNoteId = $script:BodyOtherId }
    @{ pages = $pages; topics = @{} }
}

function Get-PageBodyCases {
    <# name -> page XML, in the order of the fixture. #>
    $bold = "<span style='font-weight:bold'>"
    $bullet = '<one:List><one:Bullet bullet="2" /></one:List>'
    $num = '<one:List><one:Number numberSequence="0" numberFormat="##." text="1." /></one:List>'
    $amp = { param([string]$Href) $Href.Replace('&', '&amp;') }
    $c = [ordered]@{}

    $c['headings and styled text'] = New-BodyPageXml (New-BodyOutline 'body' (
            (New-BodyOe "$bold<span style='font-size:16pt'>Overview</span></span>") +
            (New-BodyOe "${bold}How it works</span>" '' ' style="font-family:Calibri;font-size:14.0pt"') +
            (New-BodyOe "${bold}Details</span>" '' ' style="font-size:12.0pt"') +
            (New-BodyOe "A proxy checks ${bold}who</span> asks and <span style='font-style:italic'>from where</span>, not <span style='text-decoration:line-through'>where from</span>.") +
            (New-BodyOe 'Plain text keeps its signs: 2 * 3, snake_case, [brackets] &amp; a &lt;tag&gt;.') +
            (New-BodyOe 'Own heading' '' ' quickStyleIndex="1"'))) '<one:QuickStyleDef index="1" name="h2" fontSize="14.0" />'

    $nested = "<one:OE>$bullet<one:T><![CDATA[Check the user]]></one:T><one:OEChildren>" + (New-BodyOe 'with a second factor' $bullet) + (New-BodyOe 'on every request' $bullet) + '</one:OEChildren></one:OE>'
    $c['bulleted, numbered and task lists'] = New-BodyPageXml (New-BodyOutline 'body' (
            (New-BodyOe 'Before the lists.') + $nested + (New-BodyOe 'Check the device' $bullet) +
            (New-BodyOe 'Steps:') + (New-BodyOe 'Plan' $num) + (New-BodyOe "Roll ${bold}out</span>" $num) + (New-BodyOe 'Review' $num) +
            (New-BodyOe 'To do:') + (New-BodyOe ([string][char]0x2610 + ' ask the network team') $bullet) + (New-BodyOe ([string][char]0x2611 + ' read the guide') $bullet)))

    $table = '<one:OE><one:Table bordersVisible="true"><one:Columns><one:Column index="0" width="120" /><one:Column index="1" width="120" /></one:Columns>' +
        '<one:Row>' + (New-BodyCell "${bold}Name</span>") + (New-BodyCell "${bold}Use</span>") + '</one:Row>' +
        '<one:Row>' + (New-BodyCell 'Proxy') + (New-BodyCell 'checks a|b') + '</one:Row>' +
        '<one:Row>' + (New-BodyCell "<span style='font-family:Consolas'>vpn</span>") + (New-BodyCell '') + '</one:Row></one:Table></one:OE>'
    $c['a table'] = New-BodyPageXml (New-BodyOutline 'body' ((New-BodyOe 'The parts:') + $table + (New-BodyOe 'After the table.')))

    $c['code'] = New-BodyPageXml (New-BodyOutline 'body' (
            (New-BodyOe "Run <span style='font-family:Consolas'>proxy --check a_b*c</span> first.") +
            (New-BodyOe "<span style='font-family:Consolas'>if (`$ok) { start }</span>") +
            (New-BodyOe "<span style='font-family:Consolas'>else { stop &lt;now&gt; }</span>")))

    $c['links'] = New-BodyPageXml (New-BodyOutline 'body' (
            (New-BodyOe ('See <a href="' + (& $amp $script:BodyLinkP2) + '">the portal</a> and <a href="onenote:#p2">Partner portal</a>.')) +
            (New-BodyOe ('A page from another section: <a href="onenote:https://team.example/Other.one#List&amp;page-id={44444444-4444-4444-4444-444444444444}&amp;end">the list</a>.')) +
            (New-BodyOe 'Read <a href="https://example.com/guide?a=1&amp;b=2">the guide</a>, <a href="http://example.com/a (b)/c">an old page</a> or <a href="https://example.com/bare"></a>.') +
            (New-BodyOe 'Mail <a href="mailto:someone@example.com">the owner</a>.') +
            (New-BodyOe 'In OneNote: <a href="onenote:https://team.example/Elsewhere.one#Other%20page&amp;page-id={99999999-9999-9999-9999-999999999999}&amp;end">a page outside the map</a>.') +
            (New-BodyOe 'Never a script: <a href="javascript:alert(1)">click me</a>, <a href="file:///C:/x.txt">a file</a> or <a href="data:text/html,x">data</a>.')))

    $c['outlines: summary, properties and Linked from left out, Your notes kept'] = New-BodyPageXml (
        (New-BodyOutline 'props' ((New-BodyOe 'Type: concept') + (New-BodyOe 'Topics: Security / Networking'))) +
        (New-BodyOutline 'summary' (New-BodyOe 'SUMMARY: a proxy that checks the user and the device.')) +
        (New-BodyOutline 'body' ((New-BodyOe 'The body stays.') + '<one:OE><one:Image><one:Size width="1" height="1" /></one:Image></one:OE>')) +
        (New-BodyOutline 'backlinks' ((New-BodyOe 'Linked from') + (New-BodyOe '<a href="onenote:#p2">Partner portal</a>'))) +
        (New-BodyOutline 'notes' ((New-BodyOe "${bold}<span style='font-size:14pt'>Your notes</span></span>") + (New-BodyOe 'My own words stay.'))) +
        (New-BodyOutline '' (New-BodyOe 'An outline the person made stays too.')))

    $c['an empty page'] = New-BodyPageXml (New-BodyOutline 'props' (New-BodyOe 'Type: note'))
    $c
}
