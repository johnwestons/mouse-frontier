local HelpQuest={}

HelpQuest.version=1
HelpQuest.states={offered=true,accepted=true,investigating=true,active=true,resolved=true}
HelpQuest.grades={assisted=true,successful=true,exceptional=true}
HelpQuest.defaultGoodwill={assisted=1,successful=2,exceptional=3}

local function integer(value,default,minimum)
    value=math.floor(tonumber(value) or default or 0)
    return math.max(minimum or 0,value)
end

local function clean(value)
    value=tostring(value or "unknown"):lower():gsub("[^%w%._%-]+","-"):gsub("%-+","-")
    value=value:gsub("^%-",""):gsub("%-$","")
    return value
end

function HelpQuest.id(spec)
    assert(type(spec)=="table","help quest id requires a specification")
    return table.concat({clean(spec.source or spec.kind or "help"),tostring(integer(spec.location,1,1)),clean(spec.npc or "community")},":")
end

local function repairSession(id,session)
    if type(session)~="table" then return nil end
    session.version=HelpQuest.version
    session.id=tostring(session.id or id)
    session.kind=tostring(session.kind or "community")
    session.mode=session.mode=="dialogue" and "dialogue" or "minigame"
    session.source=tostring(session.source or session.kind)
    session.npc=session.npc and tostring(session.npc) or nil
    session.location=integer(session.location,1,1)
    session.state=HelpQuest.states[session.state] and session.state or "offered"
    session.title=tostring(session.title or "HELP A CRITTER")
    session.objective=tostring(session.objective or "Talk to the critter who needs help.")
    session.stage=integer(session.stage,1,1)
    session.stageCount=integer(session.stageCount,3,1)
    session.progress=type(session.progress)=="table" and session.progress or {}
    session.goodwill=type(session.goodwill)=="table" and session.goodwill or {}
    for grade,default in pairs(HelpQuest.defaultGoodwill) do session.goodwill[grade]=integer(session.goodwill[grade],default,0) end
    session.attempts=integer(session.attempts,0,0)
    session.pauses=integer(session.pauses,0,0)
    session.paused=session.paused==true
    session.rewardClaimed=session.rewardClaimed==true
    if session.state=="resolved" then
        session.result=HelpQuest.grades[session.result] and session.result or "successful"
        session.rewardGoodwill=integer(session.rewardGoodwill,session.goodwill[session.result],0)
    else
        session.result=nil; session.rewardGoodwill=nil; session.rewardClaimed=false
    end
    return session
end

function HelpQuest.ensureData(data)
    assert(type(data)=="table","help quests require save data")
    data.helpQuestSessions=type(data.helpQuestSessions)=="table" and data.helpQuestSessions or {}
    for id,session in pairs(data.helpQuestSessions) do
        local repaired=repairSession(id,session)
        if repaired then data.helpQuestSessions[id]=repaired else data.helpQuestSessions[id]=nil end
    end
    if type(data.activeHelpQuestId)~="string" or not data.helpQuestSessions[data.activeHelpQuestId]
        or data.helpQuestSessions[data.activeHelpQuestId].state=="resolved" then data.activeHelpQuestId=nil end
    return data.helpQuestSessions
end

function HelpQuest.ensure(data,spec)
    assert(type(spec)=="table","help quest creation requires a specification")
    local sessions=HelpQuest.ensureData(data)
    local id=spec.id or HelpQuest.id(spec)
    local session=sessions[id]
    if not session then
        session={version=HelpQuest.version,id=id,kind=spec.kind,mode=spec.mode,source=spec.source,npc=spec.npc,
            location=spec.location,state="offered",title=spec.title,objective=spec.objective,stage=1,
            stageCount=spec.stageCount,progress={},goodwill=spec.goodwill,attempts=0,pauses=0}
        sessions[id]=session
    elseif session.state~="resolved" then
        session.title=spec.title or session.title
        session.objective=spec.objective or session.objective
        session.stageCount=spec.stageCount or session.stageCount
        session.goodwill=spec.goodwill or session.goodwill
    end
    return repairSession(id,session)
end

function HelpQuest.get(data,id)
    local sessions=HelpQuest.ensureData(data)
    return id and sessions[id] or nil
end

function HelpQuest.accept(data,id)
    local session=HelpQuest.get(data,id)
    if not session or session.state=="resolved" then return session,false end
    if session.state=="offered" then session.state="accepted" end
    session.paused=false; data.activeHelpQuestId=id
    return session,true
end

function HelpQuest.investigate(data,id,objective)
    local session,ready=HelpQuest.accept(data,id)
    if not ready then return session,false end
    if session.state=="accepted" then session.state="investigating" end
    if objective then session.objective=tostring(objective) end
    return session,true
end

function HelpQuest.activate(data,id,objective)
    local session,ready=HelpQuest.accept(data,id)
    if not ready then return session,false end
    if session.state~="active" then session.state="active"; session.attempts=session.attempts+1 end
    if objective then session.objective=tostring(objective) end
    return session,true
end

function HelpQuest.progress(data,id,stage,objective,values)
    local session=HelpQuest.get(data,id)
    if not session or session.state=="resolved" then return session,false end
    session.stage=math.min(session.stageCount,integer(stage,session.stage,1))
    if objective then session.objective=tostring(objective) end
    for key,value in pairs(values or {}) do
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then session.progress[key]=value end
    end
    return session,true
end

function HelpQuest.pause(data,id,objective)
    local session=HelpQuest.get(data,id)
    if not session or session.state=="resolved" then return session,false end
    session.paused=true; session.pauses=session.pauses+1
    if objective then session.objective=tostring(objective) end
    if data.activeHelpQuestId==id then data.activeHelpQuestId=nil end
    return session,true
end

function HelpQuest.resume(data,id)
    local session=HelpQuest.get(data,id)
    if not session or session.state=="resolved" then return session,false end
    if session.state=="offered" then session.state="accepted" end
    session.paused=false; data.activeHelpQuestId=id
    return session,true
end

function HelpQuest.retry(data,id,objective)
    local session=HelpQuest.get(data,id)
    if not session or session.state=="resolved" then return session,false end
    session.state="accepted"; session.stage=1; session.progress={}; session.paused=true
    if objective then session.objective=tostring(objective) end
    if data.activeHelpQuestId==id then data.activeHelpQuestId=nil end
    return session,true
end

function HelpQuest.resolve(data,id,grade,objective)
    local session=HelpQuest.get(data,id)
    if not session then return nil,false end
    if session.state=="resolved" then return session,false end
    grade=HelpQuest.grades[grade] and grade or "successful"
    session.state="resolved"; session.result=grade; session.paused=false
    session.stage=session.stageCount; session.objective=objective or "Help completed."
    session.rewardGoodwill=integer(session.goodwill[grade],HelpQuest.defaultGoodwill[grade],0)
    session.rewardClaimed=false
    if data.activeHelpQuestId==id then data.activeHelpQuestId=nil end
    return session,true
end

function HelpQuest.importResolved(data,id,grade,objective)
    local session=HelpQuest.get(data,id)
    if not session then return nil,false end
    if session.state~="resolved" then HelpQuest.resolve(data,id,grade,objective) end
    session.rewardClaimed=true
    return session,true
end

function HelpQuest.claim(data,id,award)
    local session=HelpQuest.get(data,id)
    if not session or session.state~="resolved" or session.rewardClaimed then return {claimed=false,gained=0,session=session} end
    assert(type(award)=="function","help quest reward claim requires an award function")
    local gained,total,tier=award(session.rewardGoodwill,session.kind,session.npc,session.location)
    session.rewardClaimed=true
    return {claimed=true,gained=integer(gained,session.rewardGoodwill,0),total=total,tier=tier,session=session}
end

function HelpQuest.open(data)
    local sessions=HelpQuest.ensureData(data); local result={}
    for _,session in pairs(sessions) do
        if session.state~="offered" and session.state~="resolved" then result[#result+1]=session end
    end
    table.sort(result,function(a,b)
        if a.id==data.activeHelpQuestId then return true end
        if b.id==data.activeHelpQuestId then return false end
        if a.location==b.location then return a.id<b.id end
        return a.location<b.location
    end)
    return result
end

function HelpQuest.summary(data)
    local sessions=HelpQuest.open(data); local first=sessions[1]
    return {count=#sessions,first=first and (first.title..": "..first.objective) or nil,session=first,sessions=sessions}
end

function HelpQuest.audit()
    local data={helpQuestSessions={}}
    local session=HelpQuest.ensure(data,{source="first-aid",kind="aid",mode="minigame",npc="medic.png",location=4,
        title="TREAT THE WOUND",objective="Ask what happened.",stageCount=3,goodwill={assisted=1,successful=3,exceptional=4}})
    local offered=session.state=="offered"
    HelpQuest.accept(data,session.id); HelpQuest.investigate(data,session.id,"Find a medical supply.")
    HelpQuest.activate(data,session.id,"Clean the wound."); HelpQuest.progress(data,session.id,2,"Wrap the wound.",{cleaned=true})
    HelpQuest.pause(data,session.id); local persisted=session.stage==2 and session.progress.cleaned==true
    HelpQuest.resume(data,session.id); HelpQuest.resolve(data,session.id,"successful","Treatment complete.")
    local awarded=0
    local function add(points) awarded=awarded+points; return points,awarded,{name="Helping Hand"} end
    local first=HelpQuest.claim(data,session.id,add); local duplicate=HelpQuest.claim(data,session.id,add)
    return {ready=offered and persisted and session.state=="resolved" and session.result=="successful"
            and first.claimed and first.gained==3 and not duplicate.claimed and awarded==3 and HelpQuest.summary(data).count==0,
        states=5,grades=3,persistent=persisted,rewardOnce=awarded==3,curve="help-session-v1"}
end

return HelpQuest
