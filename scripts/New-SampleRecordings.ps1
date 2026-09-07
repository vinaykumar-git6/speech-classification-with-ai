<#
.SYNOPSIS
    Generates synthetic call-centre recordings for end-to-end pipeline testing.

.DESCRIPTION
    Builds two-speaker conversations from category-specific dialogue banks and renders
    them with the local Windows SAPI voices at 16 kHz / 16-bit / mono PCM, which is the
    format Azure AI Speech fast transcription expects.

    The files contain genuine recognisable speech. Silence or tones would fail the
    pipeline, because SpeechClient.transcribe raises SpeechError when a response returns
    no recognised text.

    A manifest.json records the ground-truth category for every file so classification
    accuracy can be scored after a pipeline run.

.EXAMPLE
    .\scripts\New-SampleRecordings.ps1
    Generates 50 five-minute recordings into samples/recordings.

.EXAMPLE
    .\scripts\New-SampleRecordings.ps1 -Count 6 -TargetSeconds 60 -Force
    Generates a small, fast batch for a smoke test.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\samples\recordings'),

    [ValidateRange(1, 500)]
    [int]$Count = 50,

    [ValidateRange(20, 1800)]
    [int]$TargetSeconds = 300,

    [int]$Seed = 20260827,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

# Azure AI Speech batch transcription input format.
$SampleRate = 16000
$Categories = @('complaint', 'cancellation', 'sales', 'service_request', 'fraud', 'other')

# ---------------------------------------------------------------- dialogue banks

$Shared = @{
    Greeting = @(
        'Thank you for calling the customer care line, my name is Dana. May I start with your first and last name please.',
        'Good afternoon, you have reached account services, this is Marcus speaking. Who do I have the pleasure of speaking with today.',
        'Thanks for holding, my name is Priya and I will be helping you today. Could I get your name to begin with.',
        'Welcome to the support centre, this is Ellen. Before we get started, may I confirm who I am speaking with.',
        'Hello, you are through to the billing and accounts team, my name is Tobias. Can I take your name please.'
    )
    CustomerName = @(
        'Yes of course, my name is Jordan Whitfield, and I have been a customer with you for about four years now.',
        'Sure thing, it is Alex Ramirez, spelled R A M I R E Z, and the account should be under that same name.',
        'My name is Samantha Okafor. I believe my husband is also listed as an authorised user on the account.',
        'It is Daniel Boyd. I have the account number in front of me if that would be quicker for you.',
        'This is Priyanka Nair speaking. I opened the account last spring when I moved into the new apartment.'
    )
    Verify = @(
        'Thank you for that. For security purposes, could you please confirm the billing postcode and the last four digits on the account.',
        'Appreciate it. I just need to verify two details before I can discuss the account. What is the date of birth we have on file.',
        'Perfect, thank you. Can you confirm the email address that receives your statements, and the first line of the billing address.',
        'Great, I have located a record matching that name. To protect your account, please confirm the security phrase you set up.'
    )
    VerifyReply = @(
        'The postcode is nine four one zero seven, and the last four digits are three three eight two.',
        'My date of birth is the fourteenth of March, nineteen eighty six. The email is the one ending in mail dot com.',
        'The address is forty two Wilson Avenue, apartment six B, and the email should be the personal one, not the work one.',
        'The security phrase is blue harbour. I set that up when I first opened the account over the phone.'
    )
    Verified = @(
        'Thank you, that all matches what I have on my side. The account is now fully verified so we can go ahead.',
        'That is verified, thank you for bearing with me. I can see the full account history now.',
        'Wonderful, everything checks out. I have your profile open in front of me now.'
    )
    Hold = @(
        'I am going to place you on a brief hold while I pull up the detailed transaction history. It should take about a minute, is that alright.',
        'Bear with me one moment, I need to check this against our internal system and that page can be a little slow to load.',
        'Can I put you on hold for two minutes. I want to speak with my supervisor so I can give you an accurate answer rather than a guess.',
        'Let me just review the notes that my colleague left on the account from your previous call, one moment please.'
    )
    HoldReply = @(
        'That is fine, I can wait. I would rather you check properly than give me the wrong information again.',
        'Yes go ahead, I have got time. I have already set aside my lunch break for this call.',
        'No problem at all, take whatever time you need to look into it thoroughly.'
    )
    Back = @(
        'Thank you very much for waiting, I appreciate your patience. I have now got the full picture in front of me.',
        'Thanks for holding. I have confirmed the details with my supervisor and I can explain exactly what has happened.',
        'I am back with you, and I have some clear information to share about what I found.'
    )
    Closing = @(
        'Is there anything else at all I can help you with before we finish up the call today.',
        'Before I let you go, was there any other matter on the account you wanted to raise with me.',
        'That covers everything we discussed. Do you have any further questions for me while I still have the file open.'
    )
    ClosingReply = @(
        'No that is everything, thank you for actually taking the time to sort this out properly.',
        'That is all for now. I appreciate you explaining the situation clearly instead of reading from a script.',
        'Nothing further, thank you. I will keep an eye out for that confirmation email you mentioned.'
    )
    Farewell = @(
        'Thank you for calling, and I hope the rest of your day goes smoothly. Goodbye now.',
        'It was a pleasure helping you today. You have a good afternoon and take care.',
        'Thanks again for your patience with this one. Have a lovely rest of your week, goodbye.'
    )
}

$Banks = @{
    complaint = @{
        Open = @(
            'I am calling because I have been charged twice for the same monthly subscription and nobody has been able to explain why.',
            'I want to raise a formal complaint. This is the fourth time I have called about the same problem and it is still not fixed.',
            'I am extremely frustrated. The engineer was booked for Tuesday morning, never turned up, and no one bothered to call me.',
            'The product I received last week arrived damaged, and the replacement you sent arrived in exactly the same condition.'
        )
        Detail = @(
            'The first charge went out on the second of the month, which is normal, but then a second identical charge appeared on the ninth.',
            'I have the bank statement open in front of me right now, and both transactions show the same merchant reference and the same amount.',
            'Every time I call I have to explain the whole story again from the beginning because nobody writes anything down on the account.',
            'The last agent promised me a callback within twenty four hours and that was eleven days ago now.',
            'What frustrates me most is not the money itself, it is that I have spent hours of my own time chasing this.',
            'I took a full day off work to wait for that engineer visit, and I did not even receive a text message to cancel.',
            'The packaging was intact from the outside, so this is clearly a problem that happened before it was ever shipped.',
            'I have been a loyal customer for years and this is genuinely the worst experience I have had with any company.',
            'I was told the credit would appear within five working days, and it has now been three full weeks with nothing.',
            'When I checked the online portal it still shows the account as being in good standing, which contradicts what I was told.',
            'Honestly at this point I am seriously considering taking my business elsewhere, and I would rather not have to do that.',
            'I want this escalated to somebody who actually has the authority to make a decision, not another apology.'
        )
        Probe = @(
            'I am very sorry to hear that, and I completely understand the frustration. Can you tell me the exact date the second charge appeared.',
            'That is genuinely not the standard we aim for and I apologise. Do you happen to have a reference number from any of your previous calls.',
            'I do apologise for the inconvenience this has caused you. Could you describe exactly what condition the item arrived in.',
            'Thank you for explaining that so clearly. Can you tell me the name of the agent you last spoke with, if you have it.'
        )
        Resolve = @(
            'Here is what I am going to do. I am raising a formal complaint reference, refunding the duplicate charge in full, and applying a goodwill credit to the account.',
            'I have escalated this to our resolutions team with a priority flag, and you will receive a direct callback from a named case handler within one working day.',
            'I am processing the refund now, and I am also arranging a replacement to be sent by tracked next day delivery at no cost to you.'
        )
    }
    cancellation = @{
        Open = @(
            'I would like to cancel my subscription please. I have thought about it carefully and I have made up my mind.',
            'I am calling to close my account entirely. I no longer need the service and I do not want to be billed again.',
            'I want to cancel the contract before the next renewal date. Can you tell me what the process is.',
            'Please can you stop my membership. I am moving abroad next month so I will not be able to use it any more.'
        )
        Detail = @(
            'I have been paying for this for almost two years now and honestly I only use it once or twice a month at most.',
            'My circumstances have changed quite a bit recently and I need to cut back on all my monthly outgoings.',
            'I am relocating to another country in six weeks, and as I understand it the service does not operate in that region.',
            'I did look at the cheaper tier but even that is more than I want to spend given how little I actually use it.',
            'I want to be very clear that this is not about the quality of the service, it has been perfectly fine.',
            'What I need to know is whether I will be charged again before the cancellation actually takes effect.',
            'There is a family plan through my employer that covers this now, so I would be paying twice for the same thing.',
            'I would like written confirmation by email, because last time I cancelled something the billing carried on regardless.',
            'Can you also confirm that all my payment details will be removed from your system once this is processed.',
            'I appreciate the offer but a discount for three months does not really solve the underlying issue for me.',
            'If my situation changes in future I would happily come back, but for now I really do need to close it.',
            'I would also like to know what happens to the data I have stored on the account after cancellation.'
        )
        Probe = @(
            'I am sorry to hear you want to leave us. Before I process that, may I ask what has prompted the decision.',
            'Of course, I can certainly help with that. Would you mind if I asked whether it is a cost issue or a usage issue.',
            'I can absolutely arrange that for you. Just so I record the reason correctly, is this related to the service itself.',
            'Understood, and thank you for being straightforward with me. Have you considered pausing rather than cancelling outright.'
        )
        Resolve = @(
            'I have processed the cancellation with effect from the end of your current billing period, so there will be no further charges.',
            'The account is now scheduled for closure on the renewal date, and I am sending the written confirmation to your email as we speak.',
            'That is all done. Your payment details have been removed, and I have noted the reason on the account for our records.'
        )
    }
    sales = @{
        Open = @(
            'I am interested in upgrading to the larger plan. Could you walk me through what is actually included.',
            'I saw an advertisement for the new bundle and I wanted to find out what the pricing would be for my situation.',
            'I would like to add two more lines to my existing account. What would that do to my monthly bill.',
            'I am comparing a few providers at the moment and I wanted to understand what you could offer me.'
        )
        Detail = @(
            'There are four of us in the household now and the current allowance simply is not stretching far enough any more.',
            'I am mainly interested in whether the higher tier removes the usage cap, because that is the thing that keeps catching me out.',
            'Price does matter to me, but reliability matters more. I would rather pay a bit extra for something that just works.',
            'A competitor quoted me a lower headline figure, but I could not tell whether that included the installation fee.',
            'I would want the change to take effect at the start of next month so it lines up neatly with my billing cycle.',
            'Is there any kind of loyalty discount available given how long I have been with you at this point.',
            'I work from home three days a week now, so upload speed has become far more important than it used to be.',
            'What I really want to avoid is being locked into a long contract that I cannot get out of if it does not suit.',
            'Could you break down exactly what the total would be in the first year including any one off charges.',
            'If I commit to the twenty four month term, what is the best you can actually do on the monthly rate.',
            'I would also like to know whether the equipment is included or whether that is an additional purchase.',
            'That does sound reasonable. Can you send me the full terms in writing so I can review before I commit.'
        )
        Probe = @(
            'Absolutely, I would be glad to help with that. Can I ask roughly how many people would be using the service.',
            'Great question, and there are a few options. What matters most to you, the monthly cost or the overall allowance.',
            'I can certainly look at that for you. Are you currently finding that you run out of your allowance each month.',
            'Happy to go through it. Would you prefer a rolling monthly arrangement or a fixed term with a lower rate.'
        )
        Resolve = @(
            'Based on everything you have told me, the mid tier bundle with the loyalty discount applied works out best, and I can hold that price for seven days.',
            'I have prepared a written quotation covering both options with the full first year cost broken down, and that is on its way to your email now.',
            'I have provisionally added the two additional lines to the account, and nothing will be charged until you confirm you are happy to proceed.'
        )
    }
    service_request = @{
        Open = @(
            'My internet connection keeps dropping out every evening and I need someone to look into it please.',
            'I need help setting up the new device I received. I have followed the instructions but it will not connect.',
            'I need to reset my password. The reset link you keep sending expires before I can actually use it.',
            'I would like to book an engineer appointment. Something is clearly wrong with the line coming into the property.'
        )
        Detail = @(
            'It typically starts happening around seven in the evening and carries on until roughly eleven at night.',
            'I have already tried restarting the router, and I have also tried a completely different cable, with no improvement.',
            'The indicator light on the front goes amber rather than green, which the manual says means no signal is being received.',
            'It affects every device in the house, so I do not think this is a problem with any one particular computer.',
            'I ran the speed test you linked to and it came back at about two megabits, when I am supposed to be getting sixty.',
            'When I click the link in the email it tells me the token has already expired, even within a minute of receiving it.',
            'I have checked the junk folder and the messages are arriving there, but the timing problem is the same.',
            'The best time for an engineer would be a weekday morning, ideally before eleven if that is at all possible.',
            'There is a junction box on the outside wall that looks as though it has taken some water damage over the winter.',
            'I do need this resolved fairly urgently because I rely on the connection for work during the day.',
            'I am reasonably comfortable with technology, so I am happy to try further diagnostic steps over the phone.',
            'Please could you also make a note on the account, so I do not have to explain all of this again next time.'
        )
        Probe = @(
            'I am sorry you are having trouble with that. Can you tell me what time of day the problem is most noticeable.',
            'Let me help you get that sorted. Have you already tried restarting the equipment at the wall socket.',
            'I can look into that for you. What colour is the status light showing on the front of the unit right now.',
            'Understood. Is the issue affecting every device in the property, or just one in particular.'
        )
        Resolve = @(
            'I have run a line test from my side and it is showing a fault on the external segment, so I have booked an engineer for Thursday morning between eight and twelve.',
            'I have reset the password manually and extended the token validity to twenty four hours, so the new link will not expire on you this time.',
            'I have reprovisioned the connection at the exchange and applied a stability profile to the line, which should stop the evening dropouts within about two hours.'
        )
    }
    fraud = @{
        Open = @(
            'I need to report some transactions on my account that I definitely did not make myself.',
            'I think my card details have been stolen. There are several payments here that I do not recognise at all.',
            'I received an alert about a login from a country I have never visited, and now money is missing from the account.',
            'I believe I have been the victim of fraud. Someone appears to have opened a service in my name without my knowledge.'
        )
        Detail = @(
            'There are three separate transactions, all made on the same day, to a merchant I have genuinely never heard of.',
            'The amounts are one hundred and forty, two hundred and ten, and then a much larger one for six hundred pounds.',
            'My physical card has been in my wallet the entire time, so this must have been done using the details alone.',
            'I did receive a text message last week claiming to be from you, asking me to confirm my details via a link.',
            'I am fairly certain I did not click on that link, but I want to be completely honest that I cannot rule it out.',
            'The login alert showed an address in a country I have never travelled to, and it was at three in the morning.',
            'I have already contacted my bank and they have advised me to report it directly to you as well.',
            'I need the card blocked immediately, and I want to be sure no further payments can be taken from this account.',
            'There is also a change of address request on the account that I absolutely did not authorise.',
            'I am genuinely worried about this because the email address on the profile appears to have been changed too.',
            'Can you confirm whether any other accounts linked to my details have been affected by this.',
            'I want to make sure this is formally recorded as fraud, not just written off as a billing dispute.'
        )
        Probe = @(
            'I understand, and I want to reassure you we take this extremely seriously. Can you tell me the dates of the transactions you do not recognise.',
            'Thank you for reporting this promptly. Do you still have physical possession of the card itself.',
            'I am going to help you secure the account right away. Have you received any unexpected messages or emails recently.',
            'Let me stop anything further happening first. Can you confirm whether the contact details on the account still look correct to you.'
        )
        Resolve = @(
            'I have blocked the card immediately, frozen all outbound activity on the account, and raised a formal fraud case with our investigations team.',
            'The unauthorised address change has been reversed, the account is locked to new activity, and a specialist will contact you within four hours.',
            'I have secured the profile, reset every credential, and submitted the disputed transactions for full recovery under our fraud protection policy.'
        )
    }
    other = @{
        Open = @(
            'I just wanted to check what your opening hours are over the bank holiday weekend coming up.',
            'I need to update the address on my account because I am moving house at the end of the month.',
            'I wanted to pass on some positive feedback about one of your team members who helped me last week.',
            'I had a general question about how the referral scheme works. I could not find it explained on the website.'
        )
        Detail = @(
            'I am moving on the twenty eighth, so ideally the change would take effect from the first of the following month.',
            'The new address is fifteen Kingsway Court, and the postcode is different from my current one, it changes county.',
            'I mainly wanted to know whether the branch on the high street keeps the same hours as the main call centre.',
            'The agent I spoke to was called Nadia, and she genuinely went out of her way to sort out a difficult problem.',
            'I think it is important to say when someone does a good job, because people usually only call in to complain.',
            'For the referral scheme, I wanted to know whether the credit applies to me, to the person I refer, or to both.',
            'I have a friend who is thinking of signing up, so I wanted to get the details right before I mention it.',
            'Is there anything I need to do about the equipment when I move, or does it simply come with me.',
            'I would also like to check that my paperless billing preference carries across to the new address.',
            'There is no urgency to any of this, I just wanted to get it sorted well ahead of time.',
            'It would be helpful if you could send me a summary by email so I have it all in one place.',
            'That is really clear, thank you. That answers everything I was uncertain about.'
        )
        Probe = @(
            'Of course, I can help with that. Can I ask which particular location you were planning to visit.',
            'Absolutely, I can update that for you now. What is the new address including the postcode.',
            'That is really kind of you, and I will make sure it is passed on. Do you recall roughly when you called.',
            'Happy to explain how that works. Are you asking as the person referring, or as the person being referred.'
        )
        Resolve = @(
            'I have updated the address with effect from the first of next month, and your billing preferences have carried across unchanged.',
            'I have logged your feedback formally against that agent record, and it will go to their team leader for recognition.',
            'I have emailed you a written summary covering the opening hours and the full referral terms so you have it for reference.'
        )
    }
}

# ---------------------------------------------------------------- helpers

function Get-WavDurationSeconds {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $null = $reader.ReadBytes(12)
        $bytesPerSecond = $SampleRate * 2
        while ($stream.Position -lt ($stream.Length - 8)) {
            $id = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $size = $reader.ReadUInt32()
            if ($id -eq 'fmt ') {
                $fmt = $reader.ReadBytes([int]$size)
                $bytesPerSecond = [BitConverter]::ToUInt32($fmt, 8)
            }
            elseif ($id -eq 'data') {
                return [double]$size / $bytesPerSecond
            }
            else {
                $null = $reader.ReadBytes([int]$size)
            }
            if ($size % 2 -eq 1) { $null = $reader.ReadBytes(1) }
        }
    }
    finally { $stream.Dispose() }
    return 0.0
}

# Draws without repetition, reshuffling only once the pool is exhausted.
function New-Dealer {
    param([Parameter(Mandatory)][string[]]$Items, [Parameter(Mandatory)][System.Random]$Rng)

    $dealer = [pscustomobject]@{
        Items = $Items
        Rng   = $Rng
        Queue = [System.Collections.Generic.Queue[string]]::new()
    }
    $dealer | Add-Member -MemberType ScriptMethod -Name Draw -Value {
        if ($this.Queue.Count -eq 0) {
            # Bind to a local so the Sort-Object block does not depend on $this.
            $random = $this.Rng
            foreach ($item in ($this.Items | Sort-Object { $random.Next() })) { $this.Queue.Enqueue($item) }
        }
        return $this.Queue.Dequeue()
    }
    return $dealer
}

function Get-WordCount {
    param([Parameter(Mandatory)][string]$Text)
    return ($Text -split '\s+' | Where-Object { $_ }).Count
}

# Appends a turn and returns its word count, so the caller keeps the running total.
function Add-Turn {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[psobject]]$Turns,

        [Parameter(Mandatory)][string]$Speaker,
        [Parameter(Mandatory)][string]$Text
    )
    $Turns.Add([pscustomobject]@{ Speaker = $Speaker; Text = $Text })
    return (Get-WordCount -Text $Text)
}

function New-Conversation {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][int]$TargetWords,
        [Parameter(Mandatory)][System.Random]$Rng
    )

    $bank = $Banks[$Category]
    $turns = [System.Collections.Generic.List[psobject]]::new()
    $words = 0

    $dealers = @{
        Greeting     = New-Dealer -Items $Shared.Greeting     -Rng $Rng
        CustomerName = New-Dealer -Items $Shared.CustomerName -Rng $Rng
        Verify       = New-Dealer -Items $Shared.Verify       -Rng $Rng
        VerifyReply  = New-Dealer -Items $Shared.VerifyReply  -Rng $Rng
        Verified     = New-Dealer -Items $Shared.Verified     -Rng $Rng
        Hold         = New-Dealer -Items $Shared.Hold         -Rng $Rng
        HoldReply    = New-Dealer -Items $Shared.HoldReply    -Rng $Rng
        Back         = New-Dealer -Items $Shared.Back         -Rng $Rng
        Closing      = New-Dealer -Items $Shared.Closing      -Rng $Rng
        ClosingReply = New-Dealer -Items $Shared.ClosingReply -Rng $Rng
        Farewell     = New-Dealer -Items $Shared.Farewell     -Rng $Rng
        Open         = New-Dealer -Items $bank.Open           -Rng $Rng
        Detail       = New-Dealer -Items $bank.Detail         -Rng $Rng
        Probe        = New-Dealer -Items $bank.Probe          -Rng $Rng
        Resolve      = New-Dealer -Items $bank.Resolve        -Rng $Rng
    }

    $words += Add-Turn $turns 'agent'    $dealers.Greeting.Draw()
    $words += Add-Turn $turns 'customer' $dealers.CustomerName.Draw()
    $words += Add-Turn $turns 'agent'    $dealers.Verify.Draw()
    $words += Add-Turn $turns 'customer' $dealers.VerifyReply.Draw()
    $words += Add-Turn $turns 'agent'    $dealers.Verified.Draw()
    $words += Add-Turn $turns 'customer' $dealers.Open.Draw()

    # Reserve room for the hold segment, resolution and sign-off.
    $reserve = 90
    $body = $TargetWords - $reserve
    $holdInserted = $false

    while ($words -lt $body) {
        if (-not $holdInserted -and $words -gt ($body * 0.55)) {
            $words += Add-Turn $turns 'agent'    $dealers.Hold.Draw()
            $words += Add-Turn $turns 'customer' $dealers.HoldReply.Draw()
            $words += Add-Turn $turns 'agent'    $dealers.Back.Draw()
            $holdInserted = $true
            continue
        }
        $words += Add-Turn $turns 'agent'    $dealers.Probe.Draw()
        $words += Add-Turn $turns 'customer' $dealers.Detail.Draw()
        $words += Add-Turn $turns 'customer' $dealers.Detail.Draw()
    }

    $words += Add-Turn $turns 'agent'    $dealers.Resolve.Draw()
    $words += Add-Turn $turns 'customer' $dealers.ClosingReply.Draw()
    $words += Add-Turn $turns 'agent'    $dealers.Closing.Draw()
    $words += Add-Turn $turns 'customer' $dealers.ClosingReply.Draw()
    $words += Add-Turn $turns 'agent'    $dealers.Farewell.Draw()

    return [pscustomobject]@{ Turns = $turns; Words = $words }
}

function Write-Recording {
    param(
        [Parameter(Mandatory)][System.Speech.Synthesis.SpeechSynthesizer]$Synth,
        [Parameter(Mandatory)][psobject]$Conversation,
        [Parameter(Mandatory)][string]$AgentVoice,
        [Parameter(Mandatory)][string]$CustomerVoice,
        [Parameter(Mandatory)][string]$Path
    )

    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
        $SampleRate,
        [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
        [System.Speech.AudioFormat.AudioChannel]::Mono)

    $Synth.SetOutputToWaveFile($Path, $format)
    try {
        $current = ''
        foreach ($turn in $Conversation.Turns) {
            $voice = if ($turn.Speaker -eq 'agent') { $AgentVoice } else { $CustomerVoice }
            if ($voice -ne $current) { $Synth.SelectVoice($voice); $current = $voice }
            $Synth.Speak($turn.Text)
        }
    }
    finally {
        $Synth.SetOutputToNull()
    }
}

# ---------------------------------------------------------------- voice selection

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $enUs = @($synth.GetInstalledVoices() |
        Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'en-US' } |
        ForEach-Object { [pscustomobject]@{ Name = $_.VoiceInfo.Name; Gender = $_.VoiceInfo.Gender.ToString() } })

    if ($enUs.Count -lt 2) {
        throw "Need at least two en-US SAPI voices to build a two-speaker call. Found $($enUs.Count)."
    }

    $female = @($enUs | Where-Object { $_.Gender -eq 'Female' } | ForEach-Object { $_.Name })
    $male = @($enUs | Where-Object { $_.Gender -eq 'Male' } | ForEach-Object { $_.Name })
    if ($female.Count -eq 0 -or $male.Count -eq 0) {
        # Fall back to any two distinct voices when the installed set is single-gender.
        $female = @($enUs[0].Name)
        $male = @($enUs[1].Name)
    }

    # ------------------------------------------------------------ generation

    if (Test-Path -LiteralPath $OutputDirectory) {
        $existing = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.wav' -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0 -and -not $Force) {
            throw "$OutputDirectory already contains $($existing.Count) wav file(s). Re-run with -Force to replace them."
        }
        if ($existing.Count -gt 0) { $existing | Remove-Item -Force }
    }
    else {
        $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    }

    $resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $estimatedMb = [math]::Round(($Count * $TargetSeconds * $SampleRate * 2) / 1MB, 0)

    Write-Host ""
    Write-Host "Generating $Count recordings of ~$TargetSeconds s at $SampleRate Hz mono" -ForegroundColor Cyan
    Write-Host "  Output    : $resolvedOutput"
    Write-Host "  Voices    : agent=[$($female -join ', ')]  customer=[$($male -join ', ')]"
    Write-Host "  Disk usage: ~$estimatedMb MB"
    Write-Host ""

    # Self-correcting speech-rate estimate, seeded from the measured SAPI baseline.
    $wordsPerSecond = 2.70
    $manifest = [System.Collections.Generic.List[psobject]]::new()
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    for ($i = 0; $i -lt $Count; $i++) {
        $index = $i + 1
        $category = $Categories[$i % $Categories.Count]
        $rng = New-Object System.Random($Seed + $i)

        $agentVoice = $female[$rng.Next($female.Count)]
        $customerVoice = $male[$rng.Next($male.Count)]
        $name = 'call-{0:d4}-{1}.wav' -f $index, $category
        $path = Join-Path $resolvedOutput $name

        Write-Progress -Activity 'Generating sample recordings' `
            -Status "$index of $Count  ($category)" `
            -PercentComplete (($i / $Count) * 100)

        $targetWords = [int]($TargetSeconds * $wordsPerSecond)
        $duration = 0.0
        $conversation = $null

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $conversation = New-Conversation -Category $category -TargetWords $targetWords -Rng $rng
            Write-Recording -Synth $synth -Conversation $conversation `
                -AgentVoice $agentVoice -CustomerVoice $customerVoice -Path $path
            $duration = Get-WavDurationSeconds -Path $path

            if ($duration -ge ($TargetSeconds * 0.95) -and $duration -le ($TargetSeconds * 1.08)) { break }
            if ($attempt -lt 3) {
                $targetWords = [int]($targetWords * ($TargetSeconds / [math]::Max($duration, 1)))
            }
        }

        # Blend the observed rate so later files converge on the target length.
        if ($duration -gt 0) {
            $observed = $conversation.Words / $duration
            $wordsPerSecond = ($wordsPerSecond * 0.6) + ($observed * 0.4)
        }

        $manifest.Add([pscustomobject]@{
                blobName         = $name
                expectedCategory = $category
                durationSeconds  = [math]::Round($duration, 2)
                words            = $conversation.Words
                turns            = $conversation.Turns.Count
                agentVoice       = $agentVoice
                customerVoice    = $customerVoice
                sizeBytes        = (Get-Item -LiteralPath $path).Length
            })

        Write-Host ("  [{0,3}/{1}] {2,-28} {3,6:n1}s  {4,5} words" -f `
                $index, $Count, $name, $duration, $conversation.Words)
    }

    Write-Progress -Activity 'Generating sample recordings' -Completed
    $stopwatch.Stop()

    # Written OUTSIDE the recording directory on purpose: upload-recordings.ps1 does an
    # upload-batch of the whole folder, and a stray .json blob would start an
    # orchestration that fails (Speech cannot transcribe JSON).
    $manifestPath = Join-Path (Split-Path -Parent $resolvedOutput) 'recordings-manifest.json'
    [pscustomobject]@{
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        count         = $manifest.Count
        targetSeconds = $TargetSeconds
        seed          = $Seed
        sampleRate    = $SampleRate
        format        = 'PCM 16-bit mono WAV'
        recordings    = $manifest
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $totalMb = [math]::Round((($manifest | Measure-Object -Property sizeBytes -Sum).Sum) / 1MB, 1)
    $avg = [math]::Round((($manifest | Measure-Object -Property durationSeconds -Average).Average), 1)

    Write-Host ""
    Write-Host "Done in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor Green
    Write-Host "  Files    : $($manifest.Count)"
    Write-Host "  Avg len  : $avg s"
    Write-Host "  Total    : $totalMb MB"
    Write-Host "  Manifest : $manifestPath"
    Write-Host ""
    $manifest | Group-Object expectedCategory |
        ForEach-Object { Write-Host ("  {0,-16} {1}" -f $_.Name, $_.Count) }
    Write-Host ""
}
finally {
    $synth.Dispose()
}
