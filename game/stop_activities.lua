local Activities={}
local HelpQuest=require("game.help_quest_session")

Activities.version=1
Activities.order={"water-pump","community-garden","wildlife-trough","track-debris","sludge-seep"}
Activities.profiles={
    ["water-pump"]={label="REPAIR WATER PUMP",short="PUMP",description="Tighten the leaking settlement pump.",reward={scrap=2},
        hazard={kind="slick runoff",radius=58,slow=.72,color={.18,.58,.78},warning="The leaking pump's slick runoff slows you down."}},
    ["community-garden"]={label="CLEAR GARDEN THORNS",short="GARDEN",description="Pull the thorn growth away from the community beds.",reward={food=1},
        hazard={kind="thorn patch",radius=52,slow=.68,color={.46,.64,.16},warning="The thorn patch scratches you and slows your steps."}},
    ["wildlife-trough"]={label="FILL WILDLIFE TROUGH",short="TROUGH",description="Leave one food supply for the settlement animals.",cost={food=1},wildlife=true},
    ["track-debris"]={label="CLEAR TRACK DEBRIS",short="DEBRIS",description="Move sharp salvage away from the settlement path.",reward={scrap=3},
        hazard={kind="sharp debris",radius=54,slow=.78,color={.68,.42,.18},warning="Sharp debris catches your boots and slows you down."}},
    ["sludge-seep"]={label="MOP UP SLUDGE SEEP",short="SLUDGE",description="Contain a small seep before it reaches the homes.",reward={scrap=2},
        hazard={kind="sludge seep",radius=60,slow=.62,color={.08,.62,.68},warning="The sludge seep stings and clings to your boots."}},
}

local anchors={{x=315,y=505},{x=470,y=455},{x=625,y=520},{x=770,y=475},{x=545,y=600}}

function Activities.kindFor(location)
    location=math.max(1,math.floor(tonumber(location) or 1))
    -- Step by two through five entries. Every activity appears once before
    -- the sequence repeats, and neither of the previous two stops can match.
    return Activities.order[(((location-1)*2)%#Activities.order)+1]
end

function Activities.ensure(data,layout,location,settlements)
    if not layout then return nil end
    location=math.max(1,math.floor(tonumber(location) or (data and data.location) or 1))
    if layout.worldActivity and layout.worldActivity.version==Activities.version then
        local existingProfile=Activities.profiles[layout.worldActivity.kind]
        layout.worldActivity.label=existingProfile and existingProfile.label or layout.worldActivity.label
        layout.worldActivity.npc=layout.worldActivity.npc or layout.npcOutside or layout.npc or data.currentNPC
        if existingProfile then
            local quest=HelpQuest.ensure(data,{source="community-"..layout.worldActivity.kind,kind="settlement-activity",mode="minigame",
                npc=layout.worldActivity.npc,location=location,title=existingProfile.label,objective=existingProfile.description,stageCount=3,
                goodwill={assisted=1,successful=1,exceptional=2}})
            layout.worldActivity.sessionId=quest.id
            if layout.worldActivity.completed then HelpQuest.importResolved(data,quest.id,"successful",existingProfile.label.." was already completed.") end
        end
        return layout.worldActivity
    end
    local kind=Activities.kindFor(location)
    local anchor=anchors[((location-1)%#anchors)+1]
    local offsetX=((location*37)%61)-30
    local offsetY=((location*23)%35)-17
    local x,y=anchor.x+offsetX,anchor.y+offsetY
    if settlements and settlements.clamp then x,y=settlements.clamp(x,y,location) end
    layout.worldActivity={version=Activities.version,kind=kind,label=Activities.profiles[kind].label,x=x,y=y,completed=false,hazardTriggered=false,
        npc=layout.npcOutside or layout.npc or data.currentNPC}
    local profile=Activities.profiles[kind]
    local quest=HelpQuest.ensure(data,{source="community-"..kind,kind="settlement-activity",mode="minigame",npc=layout.worldActivity.npc,
        location=location,title=profile.label,objective=profile.description,stageCount=3,goodwill={assisted=1,successful=1,exceptional=2}})
    layout.worldActivity.sessionId=quest.id
    return layout.worldActivity
end

function Activities.profile(activity)
    return activity and Activities.profiles[activity.kind] or nil
end

function Activities.near(activity,x,y,radius)
    if not activity or activity.completed then return false end
    local dx,dy=(x or 0)-activity.x,(y or 0)-activity.y
    return dx*dx+dy*dy<=(radius or 76)^2
end

function Activities.complete(data,layout,StopHelp,options)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if not activity or not profile then return {completed=false,message="There is no community task here."} end
    if activity.completed then return {completed=true,already=true,message="This community task is already finished."} end
    local session=activity.sessionId and HelpQuest.get(data,activity.sessionId)
    if session then HelpQuest.accept(data,session.id) end
    data.resources=data.resources or {}
    for resource,amount in pairs(profile.cost or {}) do
        if (data.resources[resource] or 0)<amount then
            if session then HelpQuest.investigate(data,session.id,"Bring "..amount.." "..resource.." supply to this task.") end
            return {completed=false,missing=resource,message="This task needs "..amount.." "..resource.." supply.",session=session}
        end
    end
    local minigameKind=activity.kind=="sludge-seep" and "sludge-containment"
        or (activity.kind=="track-debris" and "track-debris-clearing")
        or (activity.kind=="community-garden" and "garden-rescue")
        or (activity.kind=="wildlife-trough" and "wildlife-trough-care") or nil
    if minigameKind and not (options and options.minigameComplete) then
        local objectives={
            ["sludge-containment"]="Place a downstream barrier around the seep.",
            ["track-debris-clearing"]="Inspect the debris from a safe edge.",
            ["garden-rescue"]="Mark thorn clusters without disturbing healthy vines.",
            ["wildlife-trough-care"]="Read the freshest animal tracks from a distance.",
        }
        local objective=objectives[minigameKind]
        if session then HelpQuest.investigate(data,session.id,objective) end
        return {completed=false,requiresMinigame=minigameKind,message=profile.description,session=session}
    end
    for resource,amount in pairs(profile.cost or {}) do data.resources[resource]=(data.resources[resource] or 0)-amount end
    for resource,amount in pairs(profile.reward or {}) do
        if resource=="scrap" then data.scrap=math.max(0,tonumber(data.scrap) or 0)+amount
        else data.resources[resource]=math.max(0,tonumber(data.resources[resource]) or 0)+amount end
    end
    if session then HelpQuest.activate(data,session.id,"Finish the community task.") end
    activity.completed=true; activity.completedAt=data.location; activity.hazardCleared=true
    local gained,total
    if session then
        HelpQuest.resolve(data,session.id,(options and options.grade) or "successful",profile.label.." completed.")
        local claimed=HelpQuest.claim(data,session.id,function(amount,kind,npc,questLocation)
            return StopHelp.add(data,amount,kind,npc,questLocation)
        end)
        gained,total=claimed.gained,claimed.total
    else gained,total=StopHelp.add(data,1,"settlement-activity",data.currentNPC,data.location) end
    local reward={}
    for resource,amount in pairs(profile.reward or {}) do reward[#reward+1]="+"..amount.." "..resource end
    local suffix=#reward>0 and ("  "..table.concat(reward,", ")) or ""
    return {completed=true,gained=gained,total=total,kind=activity.kind,wildlife=profile.wildlife,session=session,
        message=profile.label.." complete. +"..gained.." goodwill"..suffix.."."}
end

function Activities.update(data,layout,player)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if not activity or activity.completed or not profile or not profile.hazard or not player then return 1,nil end
    if not Activities.near(activity,player.x,player.y,profile.hazard.radius) then return 1,nil end
    local event
    if not activity.hazardTriggered then
        activity.hazardTriggered=true
        local before=math.max(1,tonumber(data.health) or 1)
        data.health=math.max(1,before-1)
        event={damage=before-data.health,message=profile.hazard.warning}
    end
    return profile.hazard.slow,event
end

function Activities.feedPoint(layout)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if activity and activity.completed and profile and profile.wildlife then return {x=activity.x,y=activity.y} end
end

function Activities.draw(layout,clock,message,messageTimer)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if not activity or not profile then return end
    local x,y=activity.x,activity.y
    if profile.hazard and not activity.completed then
        local hazard=profile.hazard; local pulse=.88+math.sin((clock or 0)*2.4)*.08
        love.graphics.setColor(hazard.color[1],hazard.color[2],hazard.color[3],.24)
        love.graphics.ellipse("fill",x,y,hazard.radius*pulse,hazard.radius*.48*pulse)
        love.graphics.setColor(hazard.color[1],hazard.color[2],hazard.color[3],.72)
        love.graphics.setLineWidth(3); love.graphics.ellipse("line",x,y,hazard.radius,hazard.radius*.48)
        for offset=-1,1 do love.graphics.line(x-28,y+offset*10,x+28,y+offset*10+math.sin((clock or 0)*2+offset)*4) end
        love.graphics.setLineWidth(1)
    end
    local activeColor=activity.completed and {.22,.72,.34} or {.96,.66,.22}
    love.graphics.setColor(.045,.032,.025,.90); love.graphics.rectangle("fill",x-80,y-88,160,42,7,7)
    love.graphics.setColor(activeColor); love.graphics.setLineWidth(3); love.graphics.rectangle("line",x-80,y-88,160,42,7,7)
    love.graphics.circle("line",x,y-2,activity.completed and 13 or 17)
    love.graphics.setColor(1,.93,.75,1)
    love.graphics.printf(activity.completed and "COMMUNITY HELPED" or profile.short,x-74,y-76,148,"center",0,.62,.62)
    love.graphics.setLineWidth(1)
    if messageTimer and messageTimer>0 and message then
        love.graphics.setColor(.055,.038,.028,.92); love.graphics.rectangle("fill",270,350,420,42,7,7)
        love.graphics.setColor(1,.90,.68,1); love.graphics.printf(message,282,362,396,"center",0,.68,.68)
    end
end

function Activities.audit(StopHelp)
    local recent={}
    local repeatProtected=true
    for location=1,15 do
        local kind=Activities.kindFor(location)
        if recent[#recent]==kind or recent[#recent-1]==kind then repeatProtected=false end
        recent[#recent+1]=kind
    end
    local settlements={clamp=function(x,y) return x,y end}
    local data={location=1,resources={food=2},scrap=0,health=6,goodwill=0,helpHistory={},currentNPC="settler.png"}
    local layout={}; local activity=Activities.ensure(data,layout,1,settlements)
    local slow,event=Activities.update(data,layout,{x=activity.x,y=activity.y})
    local secondSlow,secondEvent=Activities.update(data,layout,{x=activity.x,y=activity.y})
    local minigame=activity.kind=="sludge-seep" or activity.kind=="track-debris" or activity.kind=="community-garden" or activity.kind=="wildlife-trough"
    local result=Activities.complete(data,layout,StopHelp,minigame and {minigameComplete=true} or nil)
    local persistent=Activities.ensure(data,layout,1,settlements)==activity and activity.completed
    local session=HelpQuest.get(data,activity.sessionId)
    local wildlifeData={location=2,resources={food=0},scrap=0,health=6,goodwill=0,helpHistory={},currentNPC="ranger.png"}
    local wildlifeLayout={}; local wildlife=Activities.ensure(wildlifeData,wildlifeLayout,2,settlements)
    local missing=Activities.complete(wildlifeData,wildlifeLayout,StopHelp)
    wildlifeData.resources.food=1; local offered=Activities.complete(wildlifeData,wildlifeLayout,StopHelp); local foodBeforeCompletion=wildlifeData.resources.food
    local supplied=Activities.complete(wildlifeData,wildlifeLayout,StopHelp,{minigameComplete=true})
    local foodProtected=wildlife.kind=="wildlife-trough" and missing.missing=="food" and not missing.requiresMinigame
        and offered.requiresMinigame=="wildlife-trough-care" and foodBeforeCompletion==1 and wildlifeData.resources.food==0 and supplied.completed
    return {ready=repeatProtected and slow<1 and secondSlow<1 and event and event.damage==1 and not secondEvent
            and data.health==5 and result.completed and result.gained==1 and data.goodwill==1 and persistent
            and session and session.state=="resolved" and session.rewardClaimed and foodProtected,
        repeatProtected=repeatProtected,profileCount=#Activities.order,damage=event and event.damage,
        goodwill=data.goodwill,persistent=persistent,foodProtected=foodProtected,curve="stop-world-variety-v2"}
end

return Activities
