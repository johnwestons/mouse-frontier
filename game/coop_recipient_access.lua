-- Read-only recipient/revision facts; live positions come from host simulation.
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Availability=require('game.coop_object_access')
local Access={}
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function near(state,target,passenger)
    if not finite(state.x) or not finite(state.y) or not finite(target.x) or not finite(target.y) then return false end
    local dx,dy=state.x-target.x,state.y-target.y
    return passenger and math.abs(dx)<75 and math.abs(dy)<90 or not passenger and dx*dx+dy*dy<95*95
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
        and data.stopLayouts[tostring(data.location)]==target and data.currentNPC==npc
        and state.npc and state.npc.id==npc and near(state,state.npc,false) then position=state.npc
    else return nil end
    return {targetId=id,npc=npc,kind=passenger and 'passenger' or 'resident',target=target,x=position.x,y=position.y}
end
function Access.nearest(data,state)
    local nearest,distance
    for _,entry in ipairs(Entities.records(data)) do
        local npc=entry.kind=='passenger' and entry.value.npc or entry.kind=='stop' and data.currentNPC
        local found=npc and Access.find(data,entry.value.entityId,npc,state)
        if found then
            local d=(state.x-found.x)^2+(state.y-found.y)^2
            if not distance or d<distance then nearest,distance=found,d end
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
