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
