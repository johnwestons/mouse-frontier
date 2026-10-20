-- Read-only recipient/revision facts; live positions come from host simulation.
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Availability=require('game.coop_object_access')
local SceneNPCs=require('game.scene_npcs')
local Home=require('game.home_stop')
local HomeFox=require('game.home_stop_fox')
local Access={}
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function near(state,target,passenger)
    if not finite(state.x) or not finite(state.y) or not finite(target.x) or not finite(target.y) then return false end
    local dx,dy=state.x-target.x,state.y-target.y
    return passenger and math.abs(dx)<75 and math.abs(dy)<90 or not passenger and dx*dx+dy*dy<95*95
end
function Access.resident(data,npc,state)
    if not state or (state.scene~='stop' and state.scene~='house') then return nil end
    if Home.isHome(data) then
        if state.scene=='stop' and not Home.isOffice(data) and npc==Home.FOX then return HomeFox.actor(data) end
        -- The office conductor's introduction uses its own story command.
        return nil
    end
    local door=data.activeHouseDoor or 1
    if state.scene=='house' and state.houseDoor and state.houseDoor~=door then return nil end
    if SceneNPCs.hasResidents(data) then return SceneNPCs.find(data,npc,state.scene,door) end
    -- Legacy single-resident scenes expose their trusted simulation position
    -- through actorState. A prepared resident roster never uses this fallback.
    local position=state.npc
    return data.currentNPC==npc and position and position.id==npc and position or nil
end
function Access.residents(data,state)
    if not state or (state.scene~='stop' and state.scene~='house') then return {} end
    if Home.isHome(data) then
        local fox=Access.resident(data,Home.FOX,state)
        return fox and {fox} or {}
    end
    if state.scene=='house' and state.houseDoor and state.houseDoor~=(data.activeHouseDoor or 1) then return {} end
    if SceneNPCs.hasResidents(data) then return SceneNPCs.list(data,state.scene,data.activeHouseDoor or 1) end
    local position=Access.resident(data,data.currentNPC,state)
    return position and {position} or {}
end
function Access.find(data,id,npc,state,conversation)
    if not Availability.available(data,data,state) or type(npc)~='string' then return nil end
    local target,entry=Entities.find(data,id); if not target then return nil end
    local story=data.conversations and data.conversations.active
    if not conversation and story and story.phase=='prompt' and story.sceneEpoch==data.coop.sceneEpoch
        and story.targetId==id and story.npc==npc then return nil end
    local passenger=entry.kind=='passenger'; local position
    if passenger then
        if data.scene~='train' or (target.carIndex or 1)~=data.activeCar or target.npc~=npc or not near(state,target,true) then return nil end
        position=target
    elseif entry.kind=='stop' and (data.scene=='stop' or data.scene=='house')
        and data.stopLayouts[tostring(data.location)]==target then
        position=Access.resident(data,npc,state)
        if not position or not near(state,position,false) then return nil end
    else return nil end
    return {targetId=id,npc=npc,kind=passenger and 'passenger' or 'resident',target=target,x=position.x,y=position.y}
end
function Access.nearest(data,state)
    local nearest,distance
    local function consider(entry,npc)
        local found=npc and Access.find(data,entry.value.entityId,npc,state)
        if found then
            local d=(state.x-found.x)^2+(state.y-found.y)^2
            if not distance or d<distance then nearest,distance=found,d end
        end
    end
    for _,entry in ipairs(Entities.records(data)) do
        if entry.kind=='passenger' then consider(entry,entry.value.npc)
        elseif entry.kind=='stop' and entry.value==data.stopLayouts[tostring(data.location)] then
            for _,resident in ipairs(Access.residents(data,state)) do consider(entry,resident.file or resident.id) end
        end
    end
    return nearest
end
function Access.expected(data,actorId,command,args)
    local campaign=Players.campaignOf(data); local scopes={'entity:'..args.targetId,'relationships'}
    if command=='npc.gift' or command=='passenger.equip' then
        scopes[#scopes+1]='player:'..actorId
        if args.containerId then scopes[#scopes+1]='entity:'..args.containerId end
    end
    local result={}; for _,scope in ipairs(scopes) do result[scope]=campaign.coop.revisions[scope] or 0 end; return result
end
return Access
