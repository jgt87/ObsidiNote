# Pester 3.4 syntax (inbox on Windows): Should Be / Should Throw.
# The Add-vs-Ask rules (FEASIBILITY.md, "Add or Ask from one input"). Invented example texts only.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here '..\lib\Intent.psm1') -Force

Describe 'Get-Intent: rule 1, an explicit choice wins' {
    It 'Add mode adds even a question' {
        $r = Get-Intent -Text 'What did we decide?' -Mode 'add'
        $r.intent | Should Be 'add'
        $r.rule | Should Be 1
        $r.reason | Should Be 'you chose Add'
    }
    It 'Ask mode asks even a link' {
        (Get-Intent -Text 'https://example.com/a' -Mode 'ask').intent | Should Be 'ask'
    }
    It 'a "+" prefix adds, a "?" prefix asks' {
        (Get-Intent -Text '+ Ask Sam about the device check timeline').intent | Should Be 'add'
        (Get-Intent -Text '? zero trust partner devices').intent | Should Be 'ask'
    }
    It 'refuses an unknown mode' {
        { Get-Intent -Text 'x' -Mode 'delete' } | Should Throw
    }
    It 'treats a missing mode as auto, and says when there is nothing yet' {
        (Get-Intent -Text '   ' -Mode '').intent | Should Be 'empty'
    }
}

Describe 'Get-Intent: rule 2, ask' {
    It 'asks a short text that starts with a question word and ends with "?"' {
        $r = Get-Intent -Text 'What did we decide about the partner portal?'
        $r.intent | Should Be 'ask'
        $r.rule | Should Be 2
        $r.reason | Should Be 'it reads as a question (starts with "What", ends with "?")'
    }
    It 'asks a short text that only ends with "?"' {
        (Get-Intent -Text 'partner portal proxies?').intent | Should Be 'ask'
    }
    It 'asks with a Dutch question word, without a question mark' {
        $r = Get-Intent -Text 'Welke afspraken staan er over het partnerportaal'
        $r.intent | Should Be 'ask'
        $r.reason | Should Match '"Welke"'
    }
    It 'does not take a word that only begins like a question word' {
        (Get-Intent -Text 'Whatever happened to the old plan').intent | Should Be 'unclear'
    }
    It 'does not ask when the question has a link in it: Ask reads the wiki only' {
        $r = Get-Intent -Text 'What is on https://example.com/a?'
        $r.intent | Should Be 'unclear'
        $r.reason | Should Match 'asks about a link'
    }
    It 'asks a long question of one sentence (scored since 2026-11-18; it was added before)' {
        $long = 'Why ' + ('word ' * 70) + '?'
        $r = Get-Intent -Text $long
        $r.intent | Should Be 'ask'
        $r.addScore | Should BeGreaterThan 0
    }
    It 'leaves a question followed by notes unclear' {
        (Get-Intent -Text "How do we roll this out?`n`nNotes from the call follow.").intent | Should Be 'unclear'
    }
}

Describe 'Get-Intent: rule 3, add' {
    It 'adds a link on its own' {
        $r = Get-Intent -Text '  https://example.com/beyond-the-perimeter  '
        $r.intent | Should Be 'add'
        $r.reason | Should Be 'it is a link on its own'
    }
    It 'adds a pasted mail (two header lines)' {
        $mail = "From: Sam Example <sam@example.com>`nSubject: Device check`n`nHi, see below."
        (Get-Intent -Text $mail).reason | Should Match 'mail or meeting'
    }
    It 'adds pasted Dutch meeting headers' {
        (Get-Intent -Text "Onderwerp: Overleg`nWanneer: dinsdag 10:00").intent | Should Be 'add'
    }
    It 'adds a statement' {
        $r = Get-Intent -Text 'We decided to move the portal off the VPN'
        $r.intent | Should Be 'add'
        $r.reason | Should Be 'it reads as a statement (starts with "We decided")'
        (Get-Intent -Text 'Note: proxies check device state now').intent | Should Be 'add'
        (Get-Intent -Text 'TODO check the timeline').intent | Should Be 'add'
        (Get-Intent -Text 'Let op: de VPN gaat dicht').intent | Should Be 'add'
    }
    It 'needs the statement word to end there ("Todos" is not "TODO")' {
        (Get-Intent -Text 'Todos for the portal').intent | Should Be 'unclear'
    }
    It 'adds longer text and several paragraphs' {
        (Get-Intent -Text ('word ' * 70)).intent | Should Be 'add'
        (Get-Intent -Text "First part.`r`n`r`nSecond part.").reason | Should Match 'has several paragraphs'
    }
}

Describe 'Get-Intent: rule 4, unclear' {
    It 'leaves a few words unclear' {
        $r = Get-Intent -Text 'zero trust partner devices'
        $r.intent | Should Be 'unclear'
        $r.rule | Should Be 4
    }
    It 'leaves a link with other words unclear' {
        $r = Get-Intent -Text 'portal https://example.com/a'
        $r.intent | Should Be 'unclear'
        $r.reason | Should Match 'has a link'
    }
}

Describe 'Get-Intent: every example of tests/fixtures/intent-samples.json (2026-11-18)' {
    $fx = Get-Content -Raw -Encoding UTF8 (Join-Path $here 'fixtures\intent-samples.json') | ConvertFrom-Json
    It 'has examples of all three outcomes, in English and Dutch' {
        foreach ($w in 'ask', 'add', 'unclear') { @($fx.samples | Where-Object { $_.want -eq $w }).Count | Should BeGreaterThan 5 }
        @($fx.samples).Count | Should BeGreaterThan 90
    }
    It 'gets every example right' {
        $wrong = @(foreach ($s in $fx.samples) {
                $r = Get-Intent -Text $s.text
                if ($r.intent -ne $s.want) { "[$($s.want) but $($r.intent) ($($r.askScore)/$($r.addScore))] $($s.text -replace '\s+', ' ')" }
            })
        ($wrong -join "`n") | Should Be ''
    }
    It 'says why, naming the strongest signals' {
        foreach ($s in $fx.samples) { (Get-Intent -Text $s.text).reason | Should Not BeNullOrEmpty }
    }
}

Describe 'Get-Intent: a company link with your own words (2026-11-18)' {
    It 'names the Add it will be: the link''s page with the words as notes' {
        $r = Get-Intent -Text 'Plan for the beds https://contoso.sharepoint.com/sites/garden/Beds.aspx'
        $r.intent | Should Be 'add'
        $r.reason | Should Match 'company link with your words'
        (Get-Intent -Text 'Plan for the beds https://example.org/beds').intent | Should Not Be 'add'
    }
}

Describe 'Get-SubmitMessage' {
    It 'says which part comes next' {
        Get-SubmitMessage 'add' | Should Be 'Adding comes in the next step'
        Get-SubmitMessage 'ask' | Should Be 'Asking comes in the next step'
        Get-SubmitMessage 'unclear' | Should Be 'Adding and asking come in the next steps'
    }
}
