-- Read-only train object facts shared by host commands and guest affordances.
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Inventory=require('game.coop_inventory')
local Access={}
function Access.available(data,actor,state)
    return state and state.screen=='game' and state.scene==data.scene and actor.health>0
        and not state.traveling and not state.changingCar and not state.encounterActive and not state.activityBlocked
end
function Access.decoration(data,id,state)
    local item,entry=Entities.find(data,id)
    if Access.available(data,data,state) and data.scene=='train' and item and entry.kind=='drop'
        and item.scene=='train' and (item.carIndex or 1)==data.activeCar then return item,entry end
end
function Access.radio(data,id,state)
    local item,entry=Entities.find(data,id)
    if item and item.name=='boombox-radio' and Access.available(data,data,state)
        and Inventory.canAccess(data,data,state,item,entry) then return item end
end
function Access.nearestRadio(data,state)
    local nearest,distance
    for _,entry in ipairs(Entities.records(data)) do
        local item=entry.value
        if Access.radio(data,item.entityId,state) then
            local d=(state.x-item.x)^2+(state.y-item.y)^2
            if not distance or d<distance then nearest,distance=item,d end
        end
    end
    return nearest
end
function Access.expected(data,command,actorId,entityId)
    local campaign=Players.campaignOf(data); local scopes
    if command=='radio.station' then scopes={'radio','entity:'..entityId}
    elseif command=='activity.release' then scopes={'activity:decoration:'..entityId}
    else
        scopes={'activity:decoration:'..entityId,'entity:'..entityId}
        if command=='decoration.collect' then scopes[#scopes+1]='player:'..actorId end
    end
    local result={}
    for _,scope in ipairs(scopes) do result[scope]=campaign.coop.revisions[scope] or 0 end
    return result
end
return Access
