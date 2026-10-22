-- Presentation of canonical legal routes. Phase follows traveled world distance,
-- never projected screen distance, so orbiting or zooming cannot change a gait.
local Field=require('game.battle_field')
local Motion={PIXELS_PER_UNIT=60}
local cache=setmetatable({},{__mode='k'})
function Motion.routeLength(field,path)
    local length=0
    for i=2,#path do
        local a,b=path[i-1],path[i];local dy=Field.cellHeight(field,b.q,b.r)-Field.cellHeight(field,a.q,a.r)
        length=length+math.sqrt((b.q-a.q)^2+(b.r-a.r)^2+dy*dy)
    end
    return length
end
function Motion.sample(field,unit)
    local move=unit.moveAnim
    if not move then return unit.q,unit.r,unit.intentQ or unit.facing or 1,unit.intentR or 0,unit.routeDistance or 0,false end
    local path=move.path or {{q=move.fromQ,r=move.fromR},{q=move.toQ,r=move.toR}}
    local p=math.min(1,math.max(0,move.t/math.max(.001,move.duration)));p=p*p*(3-2*p)
    local cached=cache[move]
    if not cached then
        local lengths,total={},0
        for i=2,#path do lengths[i]=Motion.routeLength(field,{path[i-1],path[i]});total=total+lengths[i]end
        cached={lengths=lengths,total=total};cache[move]=cached
    end
    local traveled=cached.total*p;local remaining=traveled
    for i=2,#path do
        local segment=cached.lengths[i]
        if remaining<=segment or i==#path then
            local a,b=path[i-1],path[i];local t=math.min(1,remaining/math.max(.0001,segment))
            return a.q+(b.q-a.q)*t,a.r+(b.r-a.r)*t,b.q-a.q,b.r-a.r,(move.fromDistance or 0)+traveled,true
        end
        remaining=remaining-segment
    end
    return unit.q,unit.r,1,0,unit.routeDistance or 0,false
end
return Motion
