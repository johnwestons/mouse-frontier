-- The same read-only collision adapter for authoritative and predicted actors.
local Train=require('game.train')
local Settlements=require('game.settlements')
local Util=require('game.util')
local Areas=require('game.expedition_areas')
local Caravan=require('game.crow_caravan_area')
local Home=require('game.home_stop')
local Collision={}
function Collision.new(context)
    assert(context.car and context.scenery,'co-op collision requires scene assets')
    return function(data,actor,oldX,oldY,x,y)
        local Players=require('game.coop_players')
        local campaign=Players.campaignOf(data)
        local id=actor.id or campaign.players and campaign.players.companion==actor and 'companion'
        if id and Players.get(campaign,id) then data=Players.forActor(campaign,id) end
        if require('game.coop_last_stand_lifecycle').walking(data) then
            return require('game.last_stand_geometry').move(data.lastStand.lifecycle.mode,oldX,oldY,x,y)
        end
        if data.scene=='train' then
            local image=(context.scenery.trainCarImages or {})[data.trainCars[actor.activeCar]]
            return Train.clampCharacterToFloor(context.car,image,x,y,30)
        elseif data.scene=='stop' then
            if Home.isHome(data) then return Home.move(oldX,oldY,x,y,data) end
            -- Corrections can span more than an ordinary movement step. Sweep
            -- them too; endpoint-only checks could jump a thin closed path.
            local dx,dy=x-oldX,y-oldY
            local count=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/5))
            local nextX,nextY=oldX,oldY
            for _=1,count do nextX,nextY=Settlements.move(data.location,nextX,nextY,nextX+dx/count,nextY+dy/count) end
            return nextX,nextY
        elseif data.scene=='house' then return Util.clampHouseFloor(x,y)
        elseif data.scene=='expedition' then return Areas.move(data,data.activeExpeditionArea,oldX,oldY,x,y,true)
        elseif data.scene=='caravan' then return Caravan.move(oldX,oldY,x,y) end
        return oldX,oldY
    end
end
return Collision
