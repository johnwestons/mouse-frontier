-- Host-owned flood corrections choose walkable banks for the entire party.
-- Planning every destination first avoids using the first actor's unsafe old
-- position as an obstacle and keeps two players from landing on each other.
local Areas=require('game.expedition_areas')
local Hazards={}
local offsets={{0,0},{30,0},{-30,0},{0,30},{0,-30},{24,24},{-24,24},{24,-24},{-24,-24},{44,0},{-44,0},{0,44},{0,-44}}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<100000 end
local function separated(x,y,occupied)
    for _,p in ipairs(occupied) do if (p.x-x)^2+(p.y-y)^2<24^2 then return false end end
    return true
end
function Hazards.plan(data,areaId,actors)
    local area=Areas.definition(areaId)
    local banks=area and area.environment and area.environment.floodZone and area.environment.floodZone.safeBanks
    if not banks then return {} end
    local occupied,pending,seen={},{},{}
    for _,actor in ipairs(actors) do
        if (actor.id~='host' and actor.id~='companion') or seen[actor.id] or not finite(actor.x) or not finite(actor.y) then return nil,'invalid_actors' end
        seen[actor.id]=true
        if Areas.isInFlood(data,areaId,actor.x,actor.y) then pending[#pending+1]=actor
        else occupied[#occupied+1]={x=actor.x,y=actor.y} end
    end
    local result={}
    for _,actor in ipairs(pending) do
        local ordered={}; for i,bank in ipairs(banks) do ordered[i]={x=bank.x,y=bank.y,index=i} end
        table.sort(ordered,function(a,b)
            local da,db=(a.x-actor.x)^2+(a.y-actor.y)^2,(b.x-actor.x)^2+(b.y-actor.y)^2
            return da==db and a.index<b.index or da<db
        end)
        local point
        for _,bank in ipairs(ordered) do
            for _,offset in ipairs(offsets) do
                local x,y=bank.x+offset[1],bank.y+offset[2]
                if Areas.isWalkable(data,areaId,x,y) and not Areas.isInFlood(data,areaId,x,y) and separated(x,y,occupied) then
                    point={x=x,y=y}; break
                end
            end
            if point then break end
        end
        if not point then return nil,'bank_unavailable' end
        result[actor.id]=point; occupied[#occupied+1]=point
    end
    return result
end
return Hazards
