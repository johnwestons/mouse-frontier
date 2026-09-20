# Removed or retired speech and required rewrites

Original wording below was archived with authorship unverified. On September 19, the user confirmed the original regular `Catalog.dialogueLines` in R001 as theirs and requested restoration; that array is now restored verbatim. Other entries remain pending review. Handling blocks below describe the original September 14 changes unless superseded by a dated note. Neutral task/controls text is UI, not replacement character dialogue. Supply your rewrite by entry ID.

## R001 — game/catalog.lua

Original:
```text
Catalog.dialogueLines = {
    "Hello", "Howdy stranger", "Nice train", "Sure is hot out", "Where'd you come from?", "Where you headed?",
    "Be careful out there", "Hi", "Don't get much visitors these days", "How's yer mom and them?",
    "Hope you find what you're looking for", "Got any grapes?", "Can I borrow $3.50?",
    "What happened to the rest of the people?", "I hope my family is ok...", "What are we gonna do come winter...",
    "How far have you traveled so far?", "Some critters got mutated in the great flash.",
    "We need more people like you...", "Wow, what an adventure!",
    "Those darn sludges keep tainting my crops...", "I would go myself but I know there will be bandits...",
    "We need to work together.", "If you see a sludge you gotta mash it!",
    "I hope you guys make it to the next stop safely.", "I've not seen my family in ages it feels like...",
    "Have you ever seen a human?", "Grab whatever you need for the journey.",
    "How are the tracks holding up?", "How many of us are out there?",
    "Wish we could all get along...", "Safe travels friend", "Maybe we will all get our happy endings..."
}

Catalog.mailRequestLines={"Could you take this letter west for me?","If you see my brother, will you give him this letter?","My sister went west. If you see her, will you give her this letter?","My family is out there somewhere. Could you carry this letter?","If my dad is still alive, please show him the picture in this letter."}
Catalog.rideRequestLines={"I have to get to the next town. Could I ride with you?","Could I bother you for a ride down the tracks?","My family went west. Could I ride on your train for a couple stops?","Do you have room on your train for little ol' me?","Can I ride with you for a few? I won't take up much room."}
Catalog.passengerLines={"Thank you so much for your help.","Thank you for sharing some food with me.","I'll see my family again one day thanks to you.","I don't know what I'd do if you hadn't come along.","Wow, this old train is somethin' else, huh.","*Hums softly*","This is the most peaceful I've been in a while.","Those mean critters can't get us in here.","You're a life saver.","I hope we can be friends..."}
Catalog.mailThanksLines={"A letter for me?!","Oh my gosh, thank you so much!","It's from my family! Where did you get this? Thank you!","I can't believe they are okay and still looking for me...","A letter from my family—this brings me so much hope.","I knew they would make it! I'm so happy!"}

```
Current handling:
```text
-- Legacy speech is archived in docs/dialogue-review/legacy-text.md.
Catalog.dialogueLines = {}
Catalog.mailRequestLines={"Delivery: carry a letter west."}
Catalog.rideRequestLines={"Passenger transport: provide a ride for a few stops."}
Catalog.passengerLines={}
Catalog.mailThanksLines={"Letter delivered."}

```

## R002 — game/npc_relationships.lua

Original:
```text
local giftLines={
    weapon="I'll keep this close if trouble finds us. Thank you.",
    medical="This could save somebody's life. I won't waste it.",
    food="A shared meal means more out here than you might think.",
    water="Clean water is a precious gift. Thank you, friend.",
    gear="This will make the road a little kinder. Thank you.",
    fuel="You just helped keep a cold night away.",
    useful="I can put this to good use. I'll remember your kindness.",
}


```
Current handling:
```text
local giftLines={useful="Gift accepted."}


```

## R003 — game/npc_relationships.lua

Original:
```text
local line=status.index>=3 and "You're kind to offer, but someone else will need that more than I do."
        or "I appreciate the thought, but I can't make use of that right now."
```
Current handling:
```text
local line="Item cannot be used by this NPC."
```

## R004 — game/npc_relationships.lua

Original:
```text
function Relationships.npcDialogue(data,npc,fallbackLines)
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    local status=Relationships.status(data,npc); local lines
    if record.goodwillEarned>=5 then
        lines={"I know that when you say you'll help, you mean it.","Folks here still talk about everything you've done for us.","You're family along this stretch of track now."}
    elseif record.helpCount>0 then
        lines={"I remember the help you gave us. It mattered.","Good to see you again, friend.","You left this place better than you found it."}
    elseif record.gifts>0 then
        lines={"I still remember your gift. That was mighty thoughtful.","You didn't have to share what you had, but you did.","It's good to see a generous face again."}
    elseif globalStep(data.goodwill)>=2 then
        lines={"Word about your good deeds reached us before your train did.","People down the line say you're someone we can trust.","Your train has become a welcome sight around here."}
    else lines=fallbackLines end
    lines=type(lines)=="table" and #lines>0 and lines or {"Safe travels, friend."}
    return lines[((record.talks-1)%#lines)+1],status
end

function Relationships.passengerDialogue(data,passenger,fallbackLines)
    local npc=passenger and passenger.npc
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    passenger.relationshipTalks=math.max(0,math.floor(tonumber(passenger.relationshipTalks) or 0))+1
    local status=Relationships.status(data,npc); local job=passenger.job or "scavenger"
    local lines={
        greenhouse="The greenhouse car makes me think we can grow something lasting.",
        fireman="I'll keep listening to the engine. She tells you what she needs.",
        medic="If anyone gets hurt, bring them to me before the wound worsens.",
        scavenger="I'll keep an eye out for useful salvage along the rails.",
    }
    local line
    if record.gifts>0 and passenger.relationshipTalks%3==0 then line="I haven't forgotten the gift you shared with me."
    elseif status.index>=3 then line="Whatever waits at my stop, I'm glad I'm traveling with a trusted friend."
    elseif passenger.destination then line=(lines[job] or lines.scavenger).." We're headed together to stop "..passenger.destination.."."
    else
        local fallback=type(fallbackLines)=="table" and fallbackLines or {}
        line=fallback[((passenger.relationshipTalks-1)%math.max(1,#fallback))+1] or lines[job] or lines.scavenger
    end
    return line,status
end


```
Current handling:
```text
function Relationships.npcDialogue(data,npc,fallbackLines)
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    return nil,Relationships.status(data,npc)
end

function Relationships.passengerDialogue(data,passenger,fallbackLines)
    local record=Relationships.ensure(data,passenger.npc); record.talks=record.talks+1
    return nil,Relationships.status(data,passenger.npc)
end


```

## R005 — game/help_dialogue_quests.lua

Original:
```text
local HelpQuest=require("game.help_quest_session")
local Relationships=require("game.npc_relationships")

local DialogueQuests={}

DialogueQuests.version=1
DialogueQuests.order={"missing-family","crop-dispute","bandit-warning","broken-promise"}
DialogueQuests.definitions={
    ["missing-family"]={
        title="MISSING FAMILY TRAIL",offer="I have not seen my sister in ages. Could you help me work out where she went?",
        opening="The last message came from somewhere along these tracks, but the directions were smudged.",
        nodes={
            opening={stage=1,objective="Learn something distinctive about the missing traveler.",choices={
                {label="Ask what she was carrying",evidence="redScarf",next="investigate",response="She wore a red scarf sewn with little white stars."},
                {label="Ask where she planned to travel",evidence="northRoute",next="investigate",response="She meant to visit the northern switch house before heading west."},
            }},
            investigate={stage=2,objective="Compare the story with a reliable trail clue.",choices={
                {label="Compare the station ledger",evidence="ledger",next="decision",response="The ledger records a traveler heading north, delayed but safe."},
                {label="Ask about a family keepsake",evidence="locket",next="decision",response="She carries a brass locket engraved with two field mice."},
                {label="Follow the freshest wagon marks",evidence="wagonMarks",next="decision",response="The newest marks turn north instead of following the western rail."},
            }},
            decision={stage=3,objective="Give the family a careful, useful next step.",choices={
                {label="Send a detailed message north",resolve=true,grade="successful",exceptionalIf={"northRoute","ledger"},response="That gives us a real trail without sending anyone into danger."},
                {label="Describe her identifying keepsake",resolve=true,grade="successful",exceptionalIf={"redScarf","locket"},response="Other settlements will know exactly who to look for."},
                {label="Organize safe check-ins along both routes",resolve=true,grade="successful",response="We can search together without anyone traveling alone."},
            }},
        },
        followup="Word is already moving between the switch houses. You gave this family hope with a direction.",
    },
    ["crop-dispute"]={
        title="SHARE THE WATER",offer="Our growers are arguing over the last working irrigation line. Will you help us find a fair answer?",
        opening="The upper beds say they receive nothing. The lower beds say closing their gate will ruin the seedlings.",
        nodes={
            opening={stage=1,objective="Hear one side of the irrigation dispute.",choices={
                {label="Listen to the upper-bed growers",evidence="upperDry",next="investigate",response="Their soil is cracked, and the morning flow never reaches them."},
                {label="Listen to the lower-bed growers",evidence="lowerSeedlings",next="investigate",response="Their new seedlings need a small steady flow, not the whole channel."},
            }},
            investigate={stage=2,objective="Inspect the water system before proposing a compromise.",choices={
                {label="Inspect the leaking channel",evidence="leak",next="decision",response="A split board wastes nearly a third of the water before either field."},
                {label="Read the old watering schedule",evidence="schedule",next="decision",response="The original schedule alternated short morning and evening turns."},
                {label="Measure both garden beds",evidence="bedSizes",next="decision",response="The lower seedlings need less water than everyone assumed."},
            }},
            decision={stage=3,objective="Recommend a fair plan the whole settlement can follow.",choices={
                {label="Repair the leak, then alternate turns",resolve=true,grade="successful",exceptionalIf={"upperDry","leak"},response="Fixing the waste gives both gardens enough for a fair schedule."},
                {label="Restore the morning/evening schedule",resolve=true,grade="successful",exceptionalIf={"lowerSeedlings","schedule"},response="Everyone knows when their turn begins, and the seedlings stay safe."},
                {label="Build a shared measuring basin",resolve=true,grade="successful",exceptionalIf={"bedSizes"},response="A measured share makes the agreement visible and easier to trust."},
            }},
        },
        followup="The growers are tending one another's beds now. They remember who helped them listen.",
    },
    ["bandit-warning"]={
        title="A TRUSTWORTHY WARNING",offer="Someone spotted possible bandits, but every witness tells it differently. Can you help us send an honest warning?",
        opening="One traveler heard engines east of town. Another saw dust near the northern ridge.",
        nodes={
            opening={stage=1,objective="Record one witness account without spreading a rumor.",choices={
                {label="Calmly question the frightened traveler",evidence="engineSound",next="investigate",response="They heard one rough engine, then silence—no gunfire and no voices."},
                {label="Ask the ridge lookout for details",evidence="ridgeDust",next="investigate",response="The lookout saw a narrow dust trail moving north, not toward the homes."},
            }},
            investigate={stage=2,objective="Check physical evidence before choosing the warning.",choices={
                {label="Inspect the tire marks",evidence="singleVehicle",next="decision",response="Only one light vehicle passed, heading away from the settlement."},
                {label="Check the abandoned camp",evidence="coldCamp",next="decision",response="The ashes are cold. Whoever camped here left before dawn."},
                {label="Follow the ridge tracks briefly",evidence="northbound",next="decision",response="The tracks continue north and never turn toward the stop."},
            }},
            decision={stage=3,objective="Send a warning that protects travelers without causing panic.",choices={
                {label="Report one unconfirmed vehicle northbound",resolve=true,grade="successful",exceptionalIf={"ridgeDust","singleVehicle"},response="That is precise enough to help travelers without inventing an army."},
                {label="Mark the old camp and advise caution",resolve=true,grade="successful",exceptionalIf={"engineSound","coldCamp"},response="The warning names what we know and admits what we do not."},
                {label="Organize paired watches and safe travel",resolve=true,grade="successful",response="No one has to face the uncertainty alone, and the stop stays calm."},
            }},
        },
        followup="Travelers trust this stop's warnings now because they are careful, specific, and never exaggerated.",
    },
    ["broken-promise"]={
        title="THE UNFINISHED PROMISE",offer="A friend promised to return, but the last train came without them. Could you help me decide what to do?",
        opening="I do not want to abandon them, but waiting without a plan is wearing everyone down.",
        nodes={
            opening={stage=1,objective="Understand what was promised and why it matters.",choices={
                {label="Ask about the promise",evidence="medicinePromise",next="investigate",response="They promised to return with medicine for an elderly neighbor."},
                {label="Read the last letter together",evidence="delayedLetter",next="investigate",response="The letter says the western bridge was damaged and travel might be delayed."},
            }},
            investigate={stage=2,objective="Find a practical way to keep the promise alive.",choices={
                {label="Check the departure ledger",evidence="laterTrain",next="decision",response="A traveler with their name booked passage on a later northbound train."},
                {label="Ask the mail runner about delays",evidence="bridgeDelay",next="decision",response="The mail runner confirms the bridge detour adds several days."},
                {label="Inventory the neighbor's medicine",evidence="medicineLow",next="decision",response="There is enough for a few days, but a backup supply would ease the fear."},
            }},
            decision={stage=3,objective="Choose a compassionate plan that does not leave anyone stranded.",choices={
                {label="Leave messages along the later route",resolve=true,grade="successful",exceptionalIf={"delayedLetter","laterTrain"},response="They will know where we are, and we will know where to listen for news."},
                {label="Arrange medicine while the friend travels",resolve=true,grade="successful",exceptionalIf={"medicinePromise","medicineLow"},response="The neighbor is cared for without treating the promise as broken."},
                {label="Set a safe check-in date before moving on",resolve=true,grade="successful",exceptionalIf={"bridgeDelay"},response="Waiting has an end point now, and nobody has to choose in panic."},
            }},
        },
        followup="The promise feels possible again—not because anyone ignored the delay, but because the community made a plan.",
    },
}

local function hash(text)
    local result=0
    for index=1,#(text or "") do result=(result*33+text:byte(index))%100003 end
    return result
end

local function hasEvidence(progress,required)
    if type(required)=="string" then return progress[required]==true end
    for _,name in ipairs(required or {}) do if progress[name]~=true then return false end end
    return true
end

function DialogueQuests.kindFor(location,npc)
    location=math.max(1,math.floor(tonumber(location) or 1))
    local index=((location-1+hash(npc or "community"))%#DialogueQuests.order)+1
    return DialogueQuests.order[index]
end

function DialogueQuests.ensure(data,layout,npc,location)
    layout.dialogueHelpRequests=layout.dialogueHelpRequests or {}
    local request=layout.dialogueHelpRequests[npc]
    if not request then request={version=DialogueQuests.version,quest=DialogueQuests.kindFor(location,npc),npc=npc,location=location,complete=false}; layout.dialogueHelpRequests[npc]=request end
    local definition=DialogueQuests.definitions[request.quest] or DialogueQuests.definitions[DialogueQuests.order[1]]
    local session=HelpQuest.ensure(data,{source="dialogue-"..request.quest,kind="dialogue-help",mode="dialogue",npc=npc,location=location,
        title=definition.title,objective=definition.nodes.opening.objective,stageCount=3,goodwill={assisted=1,successful=2,exceptional=3}})
    request.sessionId=session.id
    if request.complete then HelpQuest.importResolved(data,session.id,request.result or "successful",request.outcome or definition.followup)
    elseif request.accepted then HelpQuest.resume(data,session.id) end
    return request
end

function DialogueQuests.request(layout,npc)
    return layout and layout.dialogueHelpRequests and layout.dialogueHelpRequests[npc] or nil
end

function DialogueQuests.offer(request)
    local definition=request and DialogueQuests.definitions[request.quest]
    return definition and definition.offer or nil
end

local function availableChoices(node,progress)
    local result={}
    for _,choice in ipairs(node.choices or {}) do if not choice.requires or hasEvidence(progress,choice.requires) then result[#result+1]=choice end end
    return result
end

function DialogueQuests.view(data,request)
    if not request then return nil end
    local definition=DialogueQuests.definitions[request.quest]; local session=HelpQuest.get(data,request.sessionId)
    if not definition or not session or session.state=="resolved" then return nil end
    local nodeName=session.progress.node or "opening"; local node=definition.nodes[nodeName] or definition.nodes.opening
    return {quest=request.quest,title=definition.title,text=(session.progress.response and (session.progress.response.."\n\n") or "")..(node.text or (nodeName=="opening" and definition.opening or node.objective)),
        objective=node.objective,node=nodeName,choices=availableChoices(node,session.progress),session=session,request=request}
end

function DialogueQuests.begin(data,request)
    if not request or request.complete then return nil end
    request.accepted=true
    local session=HelpQuest.accept(data,request.sessionId)
    session.progress.node=session.progress.node or "opening"
    HelpQuest.investigate(data,session.id,DialogueQuests.definitions[request.quest].nodes[session.progress.node].objective)
    return DialogueQuests.view(data,request)
end

function DialogueQuests.pause(data,request)
    if not request then return false end
    HelpQuest.pause(data,request.sessionId,"Return to this critter to continue the conversation.")
    return true
end

function DialogueQuests.choose(data,request,index,award)
    local view=DialogueQuests.view(data,request); local choice=view and view.choices[tonumber(index) or 0]
    if not choice then return {completed=false,invalid=true,view=view} end
    local session=view.session; local definition=DialogueQuests.definitions[request.quest]
    if choice.evidence then session.progress[choice.evidence]=true end
    session.progress.response=choice.response
    if choice.resolve then
        HelpQuest.activate(data,session.id,"Agree on a compassionate solution.")
        local grade=choice.grade or "successful"
        if choice.exceptionalIf and hasEvidence(session.progress,choice.exceptionalIf) then grade="exceptional" end
        HelpQuest.resolve(data,session.id,grade,choice.response)
        local claimed=HelpQuest.claim(data,session.id,award)
        request.complete=true; request.result=grade; request.outcome=choice.response
        local relationship=Relationships.status(data,request.npc)
        return {completed=true,grade=grade,gained=claimed.gained,total=claimed.total,relationship=relationship,
            text=choice.response.."\n\n"..definition.followup,request=request,session=session}
    end
    session.progress.node=choice.next or session.progress.node
    local node=definition.nodes[session.progress.node]
    HelpQuest.activate(data,session.id,node.objective)
    HelpQuest.progress(data,session.id,node.stage,node.objective,{node=session.progress.node})
    return {completed=false,progressed=true,view=DialogueQuests.view(data,request),session=session}
end

function DialogueQuests.followup(data,request)
    if not request or not request.complete then return nil end
    local definition=DialogueQuests.definitions[request.quest]
    local relationship=Relationships.status(data,request.npc)
    local recognition=relationship.index>=2 and " I knew I could trust you to listen." or " I will remember that you listened."
    return (request.outcome or definition.followup)..recognition
end

function DialogueQuests.audit()
    local completed,branches,exceptional,totalGoodwill=0,0,0,0
    for location,questName in ipairs(DialogueQuests.order) do
        local data={goodwill=0,helpHistory={},relationships={},helpQuestSessions={}}
        local npc="quest-"..location..".png"; local layout={dialogueHelpRequests={[npc]={version=1,quest=questName,npc=npc,location=location}}}
        local request=DialogueQuests.ensure(data,layout,npc,location); local view=DialogueQuests.begin(data,request)
        branches=branches+#view.choices
        local first=DialogueQuests.choose(data,request,1,function(points,kind,who,stop)
            data.goodwill=data.goodwill+points; Relationships.recordHelp(data,who,points,kind,stop); return points,data.goodwill,{name="Helping Hand"}
        end)
        local second=DialogueQuests.choose(data,request,1,function(points,kind,who,stop)
            data.goodwill=data.goodwill+points; Relationships.recordHelp(data,who,points,kind,stop); return points,data.goodwill,{name="Helping Hand"}
        end)
        local final=DialogueQuests.choose(data,request,1,function(points,kind,who,stop)
            data.goodwill=data.goodwill+points; Relationships.recordHelp(data,who,points,kind,stop); return points,data.goodwill,{name="Helping Hand"}
        end)
        if first.progressed and second.progressed and final.completed then
            completed=completed+1; totalGoodwill=totalGoodwill+data.goodwill
            if final.grade=="exceptional" then exceptional=exceptional+1 end
        end
        local duplicate=HelpQuest.claim(data,request.sessionId,function() error("duplicate reward") end)
        if duplicate.claimed then return {ready=false,duplicate=true} end
    end
    return {ready=completed==4 and branches>=8 and totalGoodwill>=8,definitions=#DialogueQuests.order,completed=completed,
        branchChoices=branches,exceptional=exceptional,totalGoodwill=totalGoodwill,rewardOnce=true,curve="branching-dialogue-v1"}
end

return DialogueQuests

```
Current handling:
```text
Retired; author-supplied conversations replace this content.
```

## R006 — game/journey_rules.lua

Original:
```text
text=(message or "Thank you!")
```
Current handling:
```text
text=(message or "Task completed.")
```

## R007 — game/journey_rules.lua

Original:
```text
"That is exactly what we needed. Thank you! +"
```
Current handling:
```text
"Item delivered. +"
```

## R008 — game/journey_rules.lua

Original:
```text
"Thank you for offering. Please bring me "
```
Current handling:
```text
"Required item: "
```

## R009 — game/journey_rules.lua

Original:
```text
" when you find one."
```
Current handling:
```text
"."
```

## R010 — game/journey_rules.lua

Original:
```text
"I still need medical help, but you'll need a bandage, salve, tonic, splint, or medkit before we can begin."
```
Current handling:
```text
"Treatment requires a bandage, salve, tonic, splint, or medkit."
```

## R011 — game/journey_rules.lua

Original:
```text
"Thank you. Find "
```
Current handling:
```text
"Deliver the letter to "
```

## R012 — game/journey_rules.lua

Original:
```text
"Thank you! I'll help as your "
```
Current handling:
```text
"Passenger job: "
```

## R013 — game/journey_rules.lua

Original:
```text
"That feels much better. The cut is clean, covered, and wrapped. +"
```
Current handling:
```text
"Treatment complete. +"
```

## R014 — game/journey_rules.lua

Original:
```text
"The medical supply went missing before the treatment was finished. We can try again."
```
Current handling:
```text
"Medical supply unavailable. Treatment can be retried."
```

## R015 — game/journey_rules.lua

Original:
```text
"That did not work, but thank you for trying. We can try again when you're ready."
```
Current handling:
```text
"Treatment failed. Retry available."
```

## R016 — game/journey_rules.lua

Original:
```text
"We can continue the treatment when you're ready."
```
Current handling:
```text
"Treatment paused."
```

## R017 — game/journey_rules.lua

Original:
```text
"I've got supplies to trade. Want to take a look?"
```
Current handling:
```text
"Trade available."
```

## R018 — game/journey_rules.lua

Original:
```text
local kind=(layout.npcOffers and layout.npcOffers[runtime.saveData.currentNPC]) or "none"
```
Current handling:
```text
local kind=(layout.npcOffers and layout.npcOffers[runtime.saveData.currentNPC]) or "none"
      if kind=="dialogue" then kind="none" end
```

## R019 — game/journey_rules.lua

Original:
```text
runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC or "Traveler").." • "..status.name,text=line,timer=6}
```
Current handling:
```text
runtime.dialogue=nil
```

## R020 — game/gameplay_input.lua

Original:
```text
"I understand. Safe travels."
```
Current handling:
```text
"Task declined."
```

## R021 — game/gameplay_input.lua

Original:
```text
runtime.dialogue={speaker=Util.titleFromFile(p.npc).." - "..Util.titleFromFile(p.job).." • "..status.name,text=line,timer=7}
```
Current handling:
```text
runtime.dialogue=nil
```

## R022 — game/gameplay_input.lua

Original:
```text
speaker=Util.titleFromFile(runtime.giftNPC).." • "..result.status.name
```
Current handling:
```text
speaker="GIFT • "..result.status.name
```

## R023 — game/gameplay_input.lua

Original:
```text
speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Task declined."
```
Current handling:
```text
speaker="TASK",text="Task declined."
```

## R024 — game/inventory_actions.lua

Original:
```text
"Bring me coal from your backpack!"
```
Current handling:
```text
"Coal from the backpack is required."
```

## R025 — game/inventory_actions.lua

Original:
```text
"That's the good stuff!  +"
```
Current handling:
```text
"Fuel added: +"
```

## R026 — game/quest_progression.lua

Original:
```text
    food={amount=3,label="3 food portions",objective="FOOD SUPPLIES",request="Settlers farther west are hungry. Could you deliver three food portions?",accepted="Please take three food portions to stop %d. Your backpack food will be used first, then the train pantry.",thanks="Those food supplies will keep us going. Thank you!"},
```
Current handling:
```text
    food={amount=3,label="3 food portions",objective="FOOD SUPPLIES",request="Delivery: 3 food portions.",accepted="Deliver 3 food portions to stop %d. Backpack food is used before train storage.",thanks="Delivery completed."},
```

## R027 — game/quest_progression.lua

Original:
```text
    water={amount=3,label="3 water supplies",objective="WATER SUPPLIES",request="Our neighbors' well ran dry. Could you deliver three water supplies?",accepted="Please take three water supplies to stop %d. Bottled water will be used first, then the train tank.",thanks="Clean water means everything out here. Thank you!"},
```
Current handling:
```text
    water={amount=3,label="3 water supplies",objective="WATER SUPPLIES",request="Delivery: 3 water supplies.",accepted="Deliver 3 water supplies to stop %d. Backpack water is used before train storage.",thanks="Delivery completed."},
```

## R028 — game/quest_progression.lua

Original:
```text
    medicine={amount=2,label="2 medical supplies",objective="MEDICAL SUPPLIES",request="The next settlement is running out of medicine. Could you bring them two medical supplies?",accepted="Please bring two bandages, salves, tonics, splints, or medkits to stop %d.",thanks="This medicine will save lives. Thank you!"},
```
Current handling:
```text
    medicine={amount=2,label="2 medical supplies",objective="MEDICAL SUPPLIES",request="Delivery: 2 medical supplies.",accepted="Deliver 2 bandages, salves, tonics, splints, or medkits to stop %d.",thanks="Delivery completed."},
```

## R029 — game/quest_progression.lua

Original:
```text
    repair={amount=3,label="3 repair materials",objective="REPAIR MATERIALS",request="A settlement farther on needs materials to repair its pump. Can you bring three?",accepted="Please bring three repair materials to stop %d. Coal or oil canisters in your pack count before train coal.",thanks="We can get the pump running again. Thank you!"},
```
Current handling:
```text
    repair={amount=3,label="3 repair materials",objective="REPAIR MATERIALS",request="Delivery: 3 repair materials.",accepted="Deliver 3 repair materials to stop %d. Backpack coal/oil is used before train coal.",thanks="Delivery completed."},
```

## R030 — game/quest_progression.lua

Original:
```text
    ammunition={amount=8,label="8 rounds of ammunition",objective="AMMUNITION",request="Bandits have been circling the next settlement. Could you spare eight rounds of ammunition?",accepted="Please deliver eight rounds from your ammunition reserves to stop %d.",thanks="Now we can defend the settlement. Thank you!"},
```
Current handling:
```text
    ammunition={amount=8,label="8 rounds of ammunition",objective="AMMUNITION",request="Delivery: 8 rounds of ammunition.",accepted="Deliver 8 rounds from ammunition reserves to stop %d.",thanks="Delivery completed."},
```

## R031 — game/quest_progression.lua

Original:
```text
    recovery={amount=1,label="a lost keepsake",objective="RECOVERY",request="A family lost a keepsake near the next settlement. Could you search for it once the area is safe?",accepted="Search the area around stop %d after dealing with any danger there.",thanks="You found it. Our family will treasure this. Thank you!"},
```
Current handling:
```text
    recovery={amount=1,label="a lost keepsake",objective="RECOVERY",request="Recovery: a lost keepsake.",accepted="Search the area around stop %d after resolving any danger.",thanks="Delivery completed."},
```

## R032 — game/stop_help_progression.lua

Original:
```text
    {item="water-bottle",label="a bottle of clean water",text="Our well tastes like rust. Could you spare a bottle of clean water?"},
```
Current handling:
```text
    {item="water-bottle",label="a bottle of clean water",text="Required item: a bottle of clean water."},
```

## R033 — game/stop_help_progression.lua

Original:
```text
    {item="food-ration",label="a food ration",text="We have a hungry youngster here. Could you spare a food ration?"},
```
Current handling:
```text
    {item="food-ration",label="a food ration",text="Required item: a food ration."},
```

## R034 — game/stop_help_progression.lua

Original:
```text
    {item="field-bandage-roll",label="a bandage roll",text="We used our last clean bandage. Could you bring us a bandage roll?"},
```
Current handling:
```text
    {item="field-bandage-roll",label="a bandage roll",text="Required item: a bandage roll."},
```

## R035 — game/stop_help_progression.lua

Original:
```text
    {item="coal-chunk",label="a chunk of coal",text="The night will be cold. Could you spare a chunk of coal for our stove?"},
```
Current handling:
```text
    {item="coal-chunk",label="a chunk of coal",text="Required item: a chunk of coal."},
```

## R036 — game/stop_help_progression.lua

Original:
```text
    {item="small-oil-canister",label="a small oil canister",text="Our water pump is seizing up. Could you spare a small oil canister?"},
```
Current handling:
```text
    {item="small-oil-canister",label="a small oil canister",text="Required item: a small oil canister."},
```

## R037 — game/stop_help_progression.lua

Original:
```text
"I've been hurt. This small cut needs medical help - could you treat it?"
```
Current handling:
```text
"First aid: treat a small cut."
```

## R038 — game/world_scene.lua

Original:
```text
      local greeting=firstVisit and (meeting==1 and "Warm your paws. Three wagons, three trades, and no trouble inside the firelight."
          or (meeting==2 and "The rails cross our road again. The flock saved its better crates for you."
          or "There you are, rail-friend. See what the Rookery gathered beyond the next bend."))
          or "Back for another look? The wagons have not rolled on yet."
      runtime.dialogue={speaker="The Rookery Caravan",text=greeting,timer=5}

```
Current handling:
```text
      runtime.dialogue=nil

```

## R039 — game/last_stand_quest.lua

Original:
```text
"My friends are trapped at a farmhouse beyond the town. A railway gang has them pinned from an old relay depot."
```
Current handling:
```text
"Objective: defend the farmhouse from the railway gang at the relay depot."
```

## R040 — game/last_stand_quest.lua

Original:
```text
"The wounded are in the yard. The others are holding two front windows, but they cannot hold them forever."
```
Current handling:
```text
"Wounded defenders: backyard. Firing positions: two front windows."
```

## R041 — game/last_stand_quest.lua

Original:
```text
"Come with me. Help us keep those windows firing until the gang loses its nerve."
```
Current handling:
```text
"Accept to follow the scout to the farmhouse and begin the defense."
```

## R042 — game/last_stand_quest.lua

Original:
```text
"The relay is about three hundred meters across the fields. We need to hold for three minutes and break their will to fight."
```
Current handling:
```text
"Relay distance: 300 meters. Defense target: three minutes and reduced enemy morale."
```

## R043 — game/last_stand_quest.lua

Original:
```text
"Guard Fox has a spare lever rifle and ammunition. If your own gun runs dry, ask for it. Nobody will leave you without a way to help."
```
Current handling:
```text
"Loan weapon and ammunition available from Guard Fox. Press L to borrow during the shootout."
```

## R044 — game/last_stand_quest.lua

Original:
```text
"I understand. If you change your mind, I will keep looking for help."
```
Current handling:
```text
"Defense declined. The scout remains available."
```

## R045 — game/last_stand_quest.lua

Original:
```text
"Guard Fox: Your window. I will cover the other side."
```
Current handling:
```text
"Wide firing position selected."
```

## R046 — game/last_stand_quest.lua

Original:
```text
"Gecko Ranger: Taking a step back. You have the narrow angle."
```
Current handling:
```text
"Narrow firing position selected."
```

## R047 — game/last_stand_quest.lua

Original:
```text
"Guard Fox: We will mend the house. Take your time, and find the scout when you are ready."
```
Current handling:
```text
"Defense complete. Return with the scout when ready."
```

## R048 — game/last_stand_quest.lua

Original:
```text
"Guard Fox: They have broken for the tracks. Check on the others, then come back to me."
```
Current handling:
```text
"Enemies retreating. Check on a resident, then return to Guard Fox."
```

## R049 — game/last_stand_quest.lua

Original:
```text
"Guard Fox: Use either window. Call for my spare rifle with L if yours runs dry."
```
Current handling:
```text
"Both windows are available. Press L to borrow the spare rifle."
```

## R050 — game/last_stand_quest.lua

Original:
```text
"Gecko Ranger: Not another shot. You gave this family time to get through it."
```
Current handling:
```text
"Resident checked. Defense complete."
```

## R051 — game/last_stand_quest.lua

Original:
```text
"Gecko Ranger: The narrow window gives better cover. Duck when they raise their rifles."
```
Current handling:
```text
"The narrow window provides more cover. Duck to avoid incoming fire."
```

## R052 — game/last_stand_quest.lua

Original:
```text
"Otter Scout: We will bring the wounded into town when they can travel. I can lead you back through the gate."
```
Current handling:
```text
"Resident checked. Return route: backyard gate."
```

## R053 — game/last_stand_quest.lua

Original:
```text
"Otter Scout: The wounded are behind the house. The gate leads safely back to the stop."
```
Current handling:
```text
"Wounded defenders: backyard. Return route: backyard gate."
```

## R054 — game/last_stand_quest.lua

Original:
```text
"I will wait by the trail. Your friends are keeping the position until you return."
```
Current handling:
```text
"Defense paused. Return to the scout to resume."
```

## R055 — game/last_stand_quest.lua

Original:
```text
"They are safe. The relay gang will think twice before coming back."
```
Current handling:
```text
"Defense complete."
```

## R056 — game/last_stand_quest.lua

Original:
```text
"Gecko Ranger: They are leaving the windows. Check on the residents, then speak to Guard Fox."
```
Current handling:
```text
"Enemies retreating. Check on a resident, then return to Guard Fox."
```

## R057 — game/last_stand_quest.lua

Original:
```text
"I'LL HELP  [Y]"
```
Current handling:
```text
"ACCEPT  [Y]"
```

## R058 — game/last_stand_quest.lua

Original:
```text
"HOW BAD IS IT?  [Q]"
```
Current handling:
```text
"DEFENSE OBJECTIVE  [Q]"
```

## R059 — game/last_stand_quest.lua

Original:
```text
"WHAT ABOUT AMMO?  [F]"
```
Current handling:
```text
"WEAPON SUPPLIES  [F]"
```

## R060 — game/last_stand_tuning.lua

Original:
```text
"Guard Fox: That bought us a breath. Check your ammunition and anyone in the yard."
```
Current handling:
```text
"Intermission: check ammunition and wounded defenders in the yard."
```

## R061 — game/last_stand_tuning.lua

Original:
```text
"Gecko Ranger: They are moving shooters through the loading bays. The upper floor is still their best angle."
```
Current handling:
```text
"Intermission: additional shooters are moving to the upper floor."
```

## R062 — game/last_stand_shootout.lua

Original:
```text
"Guard Fox: Take my lever rifle. Forty-eight rounds."
```
Current handling:
```text
"Loan rifle equipped. 48 rounds supplied."
```

## R063 — game/last_stand_shootout.lua

Original:
```text
"Guard Fox: Another pouch. Make every shot count."
```
Current handling:
```text
"Loan ammunition replenished."
```

## R064 — game/last_stand_shootout.lua

Original:
```text
"Guard Fox: Your house rifle is ready with its remaining ammunition."
```
Current handling:
```text
"Loan rifle equipped with remaining ammunition."
```

## R065 — game/last_stand_shootout.lua

Original:
```text
"They are pulling back. Hold your fire and watch the doors."
```
Current handling:
```text
"Enemy withdrawal in progress."
```

## R066 — game/events.lua

Original:
```text
"The letter says: 'Keep coming west. We are leaving signs where we can.'"
```
Current handling:
```text
"Family clue: the trail continues west."
```
## R067 — game/last_stand_scene.lua

Original scout approach bark: `Please, we need your help!`

Current handling: `[E] Farmhouse defense` action label. Requires your scout approach rewrite.

## R068 — game/last_stand_shootout.lua

Original empty-ammunition offer:

- `You are dry again. I found another pouch of .22s.`
- `Use my lever rifle and ammunition. It comes back when this is over.`

Current handling: neutral LOAN SUPPLIES panel and ammunition/loan status. Requires your Guard Fox rewrite.

## Final handling notes

- Gift feedback now includes the item name in a neutral notice: `Gift accepted: <item>.`
- The Rookery arrival now shows a neutral CARAVAN notice: `Three merchant wagons. Trading available at each stall.`
- Unapproved saved dialogue-help sessions are retired on migration. Existing item-help requests are refreshed with neutral requirements.
