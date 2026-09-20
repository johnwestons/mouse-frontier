-- State and rewards for the author's conversations; no generated speech.
local Content=require("game.authored_dialogue")
local Conversations={xp=5,content=Content}
local byId={}
for _,entry in ipairs(Content) do byId[entry.id]=entry end
local calibers={"22lr","9mm","45-cal","556","30-carbine","8mm","380-acp","32-acp","12-gauge","762x39"}

function Conversations.ensure(data)
    data.conversations=data.conversations or {}
    local state=data.conversations
    state.assignments=state.assignments or {}
    state.completed=state.completed or {}
    state.seen=state.seen or {}
    return state
end

-- Choose from the actual residents when a stop is generated, independent of
-- which NPC the player talks to first. Save every roll, including spacing.
function Conversations.assign(data,layout,rng)
    rng=rng or love.math.random
    local state=Conversations.ensure(data)
    local stop=math.floor(tonumber(data.location) or 1)
    local key=tostring(stop)
    if state.assignments[key] then return state.assignments[key] end
    if stop<(state.nextStop or 1) then return nil end
    local candidates={}; local used={}
    for _,assignment in pairs(state.assignments) do used[assignment.id]=true end
    for _,entry in ipairs(Content) do
        if not used[entry.id] and not state.completed[entry.id] then candidates[#candidates+1]=entry.id end
    end
    if #candidates==0 then return nil end
    local residents={}
    -- npcInside is provisional until ensureDoor creates a persistent home.
    if layout.npcOutside then residents[1]=layout.npcOutside end
    local seen={}; if residents[1] then seen[residents[1]]=true end
    local homes={}
    for key in pairs(layout.houseDoors or {}) do homes[#homes+1]=key end
    table.sort(homes)
    for _,key in ipairs(homes) do
        local npc=layout.houseDoors[key].npc
        if npc and not seen[npc] then residents[#residents+1]=npc; seen[npc]=true end
    end
    if #residents==0 and layout.npc then residents[1]=layout.npc end
    if #residents==0 then return nil end
    local assignment={id=candidates[rng(1,#candidates)],npc=residents[rng(1,#residents)],location=stop}
    state.assignments[key]=assignment
    state.nextStop=stop+rng(2,4)
    return assignment
end

function Conversations.request(data,npc)
    local state=Conversations.ensure(data)
    local request=state.assignments[tostring(data.location)]
    if request and request.npc==npc and byId[request.id] and not state.completed[request.id] then return request end
end

function Conversations.view(data,request)
    if not request then return nil end
    local state=Conversations.ensure(data)
    local entry=byId[request.id]
    if not entry or state.assignments[tostring(request.location)]~=request or state.completed[request.id] then return nil end
    local choices={}
    for i,choice in ipairs(entry.choices) do
        local enabled=true
        for _,resource in ipairs({"food","water"}) do
            local amount=choice.cost and choice.cost[resource]
            if amount then
                if ((data.resources or {})[resource] or 0)<amount then enabled=false end
            end
        end
        choices[i]={label=choice.label,enabled=enabled}
    end
    return {authored=true,request=request,title="CONVERSATION",text=entry.question,choices=choices}
end

function Conversations.begin(data,npc)
    local request=Conversations.request(data,npc)
    local view=Conversations.view(data,request)
    if view then Conversations.ensure(data).seen[request.id]=true end
    return view
end

function Conversations.choose(data,request,index,services)
    local view=Conversations.view(data,request)
    local choice=view and view.choices[index]
    if not choice or not choice.enabled then return {completed=false,view=view} end
    if data.location~=request.location or data.currentNPC~=request.npc then return {completed=false} end
    local entry=byId[request.id].choices[index]
    services=services or {}
    assert(type(services.gainExperience)=="function","conversation XP service required")
    if entry.item then assert(type(services.storeItem)=="function","conversation item service required") end
    local reward={}
    -- Check storage delivery before charging costs or marking completion.
    if entry.item then
        local delivery=services.storeItem(entry.item)
        if not delivery or delivery=="unclaimed" then return {completed=false,view=view} end
        reward[#reward+1]="+1 "..entry.item:gsub("%-"," ").." ("..delivery..")"
    end
    for resource,amount in pairs(entry.cost or {}) do
        data.resources[resource]=data.resources[resource]-amount
        reward[#reward+1]="-"..amount.." "..resource
    end
    if entry.ammo then
        data.ammo=data.ammo or {}
        local rng=services.random or love.math.random
        local firstCaliber
        for i=1,entry.ammo.amount do
            local pick=entry.ammo.mixed and rng(1,#calibers) or nil
            if i==2 and pick==firstCaliber and pick then pick=pick%#calibers+1 end
            if i==1 then firstCaliber=pick end
            local caliber=entry.ammo.caliber or calibers[pick]
            data.ammo[caliber]=(data.ammo[caliber] or 0)+1
        end
        reward[#reward+1]="+"..entry.ammo.amount.." "..(entry.ammo.mixed and "mixed cartridges" or entry.ammo.caliber)
    end
    local state=Conversations.ensure(data)
    state.completed[request.id]={answer=index,npc=request.npc,location=request.location,xp=Conversations.xp}
    services.gainExperience(Conversations.xp)
    reward[#reward+1]="+"..Conversations.xp.." XP"
    return {completed=true,text=entry.response,notice=table.concat(reward," / ")}
end

function Conversations.audit()
    local data={location=1,currentNPC="npc",resources={food=10,water=10},ammo={}}
    local count,xp=0,0
    for stop=1,50 do
        data.location=stop
        Conversations.assign(data,{npcOutside="npc"},function(a) return a end)
        local view=Conversations.begin(data,"npc")
        if view then
            local service={gainExperience=function(amount) xp=xp+amount end,random=function(a) return a end}
            local result=Conversations.choose(data,view.request,1,service)
            if result.completed then count=count+1 end
            assert(not Conversations.choose(data,view.request,1,service).completed)
        end
    end
    return {ready=count==#Content and xp==#Content*Conversations.xp,definitions=#Content,completed=count,rewardOnce=true}
end

return Conversations
