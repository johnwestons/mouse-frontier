-- AUTHOR-SUPPLIED TEXT ONLY. Source: docs/dialogue-review/user-conversations.txt.
-- Preserve spelling, punctuation and capitalization; do not invent dialogue.
return {
    {id="travel-time", question="How long you been traveling?", choices={
        {label="Im just getting started", response="Well good luck to ya then"},
        {label="Many moons friend, we've came a long way", response="Well stay safe then, I'm sure you'll get there soon"},
        {label="Too long...", response="I know how you feel"},
    }},
    {id="wastes", question="What's it like out in the wastes?", choices={
        {label="It's not as bad as they say", response="Well they say it's extremly dangerous so..."},
        {label="Beautiful but I wouldn't go out there if I were you", response="I believe that for sure"},
        {label="I've seen many a'good critter die out there", response="Geez but ok..."},
    }},
    {id="going-west", question="Mind if i ask why you're going west?", choices={
        {label="Looking for my family", response="I hope you find them"},
        {label="Trying to make the wastes a better place", response="I believe we can one good deed at a time"},
        {label="I have my reasons", response="Fine then keep your secrets"},
    }},
    {id="worries", question="What's your biggest worry out there?", choices={
        {label="The mean critters that try and get you", response="Oh gosh yes, my advice don't let them get you"},
        {label="Running out of reasources out there", response="Definently, gotta stock up"},
        {label="Giving up hope...", response="Well the world was supposed to end but we are still here..."},
    }},
    {id="weapons", question="What weapon do you like the most?", choices={
        {label="Melee weapons are my thing", response="Yeah i bet you mash em good"},
        {label="Bows and guns are my specialty", response="Out of reach of danger i hope"},
        {label="I keep a mixed bag of tricks", response="Ready for anything i like it"},
    }},
    {id="food", question="Got any food i can get?", choices={
        {label="Yeah here you go friend", response="Oh nice that looks yummy", cost={food=2}},
        {label="Yea, you hungry? I can get you somethin to drink too", response="You bet I am, and yes please that would be delightful", cost={food=2,water=1}},
        {label="I can't spare anything right now", response="I understand...I'm sorry"},
    }},
    {id="great-flash", question="How did the world get like this?", choices={
        {label="Greed and war i'd guess...", response="Look how far that got them"},
        {label="Well the Great Flash was bombs real big ones", response="Oh my, that explains the mean critters"},
        {label="There were many than didn't stand up to the few....", response="What's that even mean?"},
    }},
    {id="ammunition", question="Hey i've got some spare ammo, what kind you using?", choices={
        {label="I use alot of .22 long rifle", response="Yeah that's a popular cartridge round these parts", ammo={caliber="22lr",amount=20}},
        {label="I need 9mm pretty badly", response="Classic yea i think ive got some here", ammo={caliber="9mm",amount=10}},
        {label="I'll take whatever you get honestly", response="Here take this bucket then, it's mixed but all still good", ammo={mixed=true,amount=15}},
    }},
    {id="wounds", question="Are you hurt?", choices={
        {label="I'm fine actually thank you tho", response="Good i hope you stay that way"},
        {label="Only small wounds I should be fine...", response="Here this should help", item="field-bandage-roll"},
        {label="I'm wounded pretty bad yeah...", response="Oh my goodness, bless your heart", item="frontier-medkit"},
    }},
    {id="mutations", question="How come some critters don't talk and walk?", choices={
        {label="The great flash left only critters, but not all of them changed.", response="I wonder why we made it...."},
        {label="Mutations from radiation varied by proximity to where the bombs hit", response="Im glad we're some of the nice ones"},
        {label="That's how critters used to be, all of us...", response="They seem to be more at peace than us..."},
    }},
    {id="mean-critters", question="Do you think it's wrong to hurt those mean critters?", choices={
        {label="Yes it's always wrong to hurt others...", response="Yeah i guess you're right..."},
        {label="Although it's wrong, I'm not usually given a choice", response="That's a tough position to be in..."},
        {label="No....I've seen them do things you couldn't imagine", response="I was afraid you'd say something like that..."},
    }},
    {id="sludges", question="Where do you think those sludges came from?", choices={
        {label="The great flash left the cities deep in sludge...", response="How long has it been since then..."},
        {label="Nuclear waste pretty much, severely mutated some critters", response="I feel so sorry for them..."},
        {label="All that matters is that we end thier suffering", response="That's kinda dark but i understand..."},
    }},
    {id="westward", question="Why go west in the first place?", choices={
        {label="All the critters are heading that way...", response="Yeah i know but that doesn't answer my question..."},
        {label="Most of the fallout is in the east so critters have been moving west for ages now", response="Is that why they call it the sickness of the east..."},
        {label="I hear critters are rebuilding out there, making it safe", response="Wow really? that'd really be somethin wouldn't it..."},
    }},
}
