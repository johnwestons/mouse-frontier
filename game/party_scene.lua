-- Major-scene state is committed with both saved actor positions. Network
-- presentation/readiness will consume the same result; it cannot choose it.
local Players=require("game.coop_players")
local Party={MAX=2147483647}
local function integer(n,low,high) return type(n)=="number" and n==math.floor(n) and n>=low and n<=high end
function Party.validate(data)
    local leg=data.coop and data.coop.journey
    if leg==nil then return true end
    if type(leg)~="table" then return false,"invalid journey" end
    local fields={from=true,to=true,phase=true,epoch=true,maintenanceCondition=true}
    for key in pairs(leg) do if not fields[key] then return false,"invalid journey field" end end
    if not integer(leg.from,1,49) or leg.to~=leg.from+1
        or (leg.phase~="departed" and leg.phase~="arrived") or not integer(leg.epoch,1,data.coop.sceneEpoch)
        or type(leg.maintenanceCondition)~="number" or leg.maintenanceCondition~=leg.maintenanceCondition
        or leg.maintenanceCondition<0 or leg.maintenanceCondition>100 or data.scene~="train"
        or data.location~=(leg.phase=="departed" and leg.from or leg.to) then return false,"invalid journey state" end
    return true
end
function Party.place(data,spawn,clamp)
    local placed={}
    for _,id in ipairs({Players.HOST,Players.COMPANION}) do
        local actor=Players.get(data,id)
        if actor then
            local x,y=spawn(id,actor)
            local px,py
            for _,offset in ipairs({{0,0},{36,0},{-36,0},{0,36},{0,-36},{60,36},{-60,-36},{90,0},{-90,0}}) do
                local cx,cy=clamp(x+offset[1],y+offset[2],id,actor)
                local free=type(cx)=="number" and type(cy)=="number" and cx==cx and cy==cy and math.abs(cx)<100000 and math.abs(cy)<100000
                for otherId,point in pairs(placed) do
                    local other=Players.get(data,otherId)
                    if (data.scene~="train" or actor.activeCar==other.activeCar) and (cx-point.x)^2+(cy-point.y)^2<24^2 then free=false end
                end
                if free then px,py=cx,cy; break end
            end
            if not px then return nil,"spawn_unavailable" end
            actor.playerX,actor.playerY=px,py
            placed[id]={x=px,y=py,carIndex=actor.activeCar,facing=actor.playerFacing or 1}
        end
    end
    return placed
end
function Party.commit(data,activities,actors,screen)
    if data.coop.sceneEpoch>=Party.MAX then return nil,"scene_epoch_exhausted" end
    data.coop.sceneEpoch=data.coop.sceneEpoch+1
    if data.conversations then data.conversations.active=nil end
    activities.state.resources={}
    return {ok=true,scene=data.scene,sceneEpoch=data.coop.sceneEpoch,location=data.location,
        actors=actors,screen=screen or "game",partyTransition=true}
end
return Party
