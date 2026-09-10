local Activities={}
local HelpQuest=require("game.help_quest_session")

Activities.version=2
Activities.order={"water-pump"}
Activities.profiles={
    ["water-pump"]={label="REPAIR WATER PUMP",short="PUMP",description="Tighten the leaking settlement pump.",reward={scrap=2},
        hazard={kind="slick runoff",radius=58,slow=.72,warning="The leaking pump's slick runoff slows you down."}},
}

local anchor={x=315,y=505}

local function goodwill()
    return {assisted=1,successful=1,exceptional=1}
end

function Activities.kindFor()
    return "water-pump"
end

function Activities.ensure(data,layout,location,settlements)
    if not layout then return nil end
    location=math.max(1,math.floor(tonumber(location) or (data and data.location) or 1))
    if layout.worldActivity and layout.worldActivity.version==Activities.version and layout.worldActivity.kind=="water-pump" then
        local profile=Activities.profiles["water-pump"]
        layout.worldActivity.label=profile.label
        layout.worldActivity.npc=layout.worldActivity.npc or layout.npcOutside or layout.npc or data.currentNPC
        local quest=HelpQuest.ensure(data,{source="community-water-pump",kind="settlement-activity",mode="dialogue",
            npc=layout.worldActivity.npc,location=location,title=profile.label,objective=profile.description,stageCount=1,
            goodwill=goodwill()})
        layout.worldActivity.sessionId=quest.id
        if layout.worldActivity.completed then HelpQuest.importResolved(data,quest.id,"successful",profile.label.." was already completed.") end
        return layout.worldActivity
    end

    local retired=layout.worldActivity
    if retired and retired.sessionId then
        if data.helpQuestSessions then data.helpQuestSessions[retired.sessionId]=nil end
        if data.activeHelpQuestId==retired.sessionId then data.activeHelpQuestId=nil end
    end

    local offsetX=((location*37)%61)-30
    local offsetY=((location*23)%35)-17
    local x,y=anchor.x+offsetX,anchor.y+offsetY
    if settlements and settlements.clamp then x,y=settlements.clamp(x,y,location) end
    local profile=Activities.profiles["water-pump"]
    layout.worldActivity={version=Activities.version,kind="water-pump",label=profile.label,x=x,y=y,completed=false,hazardTriggered=false,
        npc=layout.npcOutside or layout.npc or data.currentNPC}
    local quest=HelpQuest.ensure(data,{source="community-water-pump",kind="settlement-activity",mode="dialogue",npc=layout.worldActivity.npc,
        location=location,title=profile.label,objective=profile.description,stageCount=1,goodwill=goodwill()})
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

function Activities.complete(data,layout,StopHelp)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if not activity or not profile then return {completed=false,message="There is no community task here."} end
    if activity.completed then return {completed=true,already=true,message="This water pump is already repaired."} end
    local session=activity.sessionId and HelpQuest.get(data,activity.sessionId)
    if session then HelpQuest.activate(data,session.id,"Repair the leaking water pump.") end
    data.resources=data.resources or {}
    for resource,amount in pairs(profile.reward or {}) do
        if resource=="scrap" then data.scrap=math.max(0,tonumber(data.scrap) or 0)+amount
        else data.resources[resource]=math.max(0,tonumber(data.resources[resource]) or 0)+amount end
    end
    activity.completed=true; activity.completedAt=data.location; activity.hazardCleared=true
    local gained,total
    if session then
        HelpQuest.resolve(data,session.id,"successful",profile.label.." completed.")
        local claimed=HelpQuest.claim(data,session.id,function(amount,kind,npc,questLocation)
            return StopHelp.add(data,amount,kind,npc,questLocation)
        end)
        gained,total=claimed.gained,claimed.total
    else gained,total=StopHelp.add(data,1,"settlement-activity",data.currentNPC,data.location) end
    return {completed=true,gained=gained,total=total,kind="water-pump",session=session,
        message=profile.label.." complete. +"..gained.." goodwill, +2 scrap."}
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

function Activities.feedPoint()
    return nil
end

function Activities.draw(layout,clock,message,messageTimer)
    local activity=layout and layout.worldActivity
    local profile=Activities.profile(activity)
    if not activity or not profile then return end
    local x,y=activity.x,activity.y
    love.graphics.push("all")
    -- Keep the surviving pump and its runoff visible even before the player
    -- enters interaction range; an invisible hazard cannot be avoided fairly.
    if not activity.completed then
        love.graphics.setColor(.20,.60,.75,.30)
        love.graphics.ellipse("fill",x,y,profile.hazard.radius,profile.hazard.radius*.48)
        love.graphics.setColor(.50,.85,.92,.80)
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line",x,y,profile.hazard.radius,profile.hazard.radius*.48)
        love.graphics.line(x+18,y-27,x+18,y-9)
    end
    love.graphics.setColor(.08,.075,.065,.95)
    love.graphics.rectangle("fill",x-20,y-8,40,12,2,2)
    love.graphics.rectangle("fill",x-12,y-57,24,49,3,3)
    love.graphics.setColor(.29,.39,.36,1)
    love.graphics.rectangle("fill",x-8,y-53,16,43,2,2)
    love.graphics.setColor(.78,.60,.30,1)
    love.graphics.rectangle("fill",x-14,y-58,28,7,2,2)
    love.graphics.rectangle("fill",x+8,y-42,16,7,2,2)
    love.graphics.rectangle("fill",x+18,y-39,6,12,2,2)
    love.graphics.setLineWidth(5)
    love.graphics.line(x,y-58,x-5,y-70,x-31,y-64)
    love.graphics.setColor(.09,.075,.06,.94)
    love.graphics.rectangle("fill",x-88,y-99,176,24,4,4)
    love.graphics.setColor(activity.completed and .66 or 1,activity.completed and .94 or .86,.60,1)
    love.graphics.printf(activity.completed and "PUMP REPAIRED" or "REPAIR WATER PUMP",x-82,y-94,164/.65,"center",0,.65,.65)
    if message and (messageTimer or 0)>0 then
        love.graphics.setColor(.06,.05,.04,.94)
        love.graphics.rectangle("fill",x-180,y+29,360,47,5,5)
        love.graphics.setColor(1,.92,.74,1)
        love.graphics.printf(message,x-170,y+37,340/.65,"center",0,.65,.65)
    end
    love.graphics.pop()
end

function Activities.audit(StopHelp)
    local settlements={clamp=function(x,y) return x,y end}
    local data={location=1,resources={},scrap=0,health=6,goodwill=0,helpHistory={},currentNPC="settler.png",
        helpQuestSessions={retired={id="retired"}},activeHelpQuestId="retired"}
    local layout={worldActivity={version=1,kind="community-garden",x=1,y=1,sessionId="retired"}}
    local activity=Activities.ensure(data,layout,1,settlements)
    local migrated=activity.kind=="water-pump" and activity.version==Activities.version
        and data.helpQuestSessions.retired==nil and data.activeHelpQuestId==nil
    local slow,event=Activities.update(data,layout,{x=activity.x,y=activity.y})
    local secondSlow,secondEvent=Activities.update(data,layout,{x=activity.x,y=activity.y})
    local result=Activities.complete(data,layout,StopHelp)
    local persistent=Activities.ensure(data,layout,1,settlements)==activity and activity.completed
    local session=HelpQuest.get(data,activity.sessionId)
    return {ready=migrated and slow<1 and secondSlow<1 and event and event.damage==1 and not secondEvent
            and data.health==5 and result.completed and result.gained==1 and data.goodwill==1 and data.scrap==2
            and persistent and session and session.state=="resolved" and session.rewardClaimed,
        onlyWaterPump=true,profileCount=#Activities.order,migrated=migrated,damage=event and event.damage,
        goodwill=data.goodwill,scrap=data.scrap,persistent=persistent,curve="water-pump-help-v1"}
end

return Activities
