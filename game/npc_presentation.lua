-- Guest-only actor copies follow checked host snapshots. Saved actors remain
-- untouched, and their authoritative occupancy decides which bodies exist.
local NPCs=require('game.scene_npcs')
local Routines=require('game.npc_routines')
local Motion=require('game.character_motion')
local Settlements=require('game.settlements')
local Util=require('game.util')
local Presentation={}
local views=setmetatable({},{__mode='k'})
local function stop(actor)
    actor.moving=false; actor.velocityX,actor.velocityY=0,0
end
local function copy(source)
    local actor={}; for key,value in pairs(source) do actor[key]=value end
    stop(actor); return actor
end
function Presentation.update(runtime,dt)
    local data=runtime.saveData
    if not NPCs.hasResidents(data) then views[runtime]=nil; return end
    dt=math.max(0,math.min(.1,tonumber(dt) or 0))
    NPCs.refresh(runtime,NPCs.locked(runtime))
    local selected=runtime.npcActor and runtime.npcActor.file
    local domain=tostring(data.location)..':'..tostring(runtime.scene)..':'..tostring(data.activeHouseDoor or 1)
    local view=views[runtime]
    if not view or view.domain~=domain then view={domain=domain,actors={}}; views[runtime]=view end
    local visible,retained={},{}
    for _,source in ipairs(runtime.npcActors) do
        local record=view.actors[source.file]
        if not record then record={actor=copy(source),x=source.x,y=source.y}; view.actors[source.file]=record end
        local actor=record.actor
        local distance=math.sqrt((source.x-actor.x)^2+(source.y-actor.y)^2)
        if distance>128 then
            -- Scene restoration or a large authoritative correction is not a
            -- route to animate across intervening walls or furniture.
            actor=copy(source); record.actor=actor; record.path=nil
        elseif record.x~=source.x or record.y~=source.y then
            if source.scene=='stop' then record.path=Routines.path(data.location,actor.x,actor.y,source.x,source.y)
            else record.path={{x=source.x,y=source.y}} end
            record.index=1
        end
        record.x,record.y=source.x,source.y
        actor.file,actor.scene,actor.homeDoor=source.file,source.scene,source.homeDoor
        actor.characterId=source.characterId
        actor.weapon,actor.family=source.weapon,source.family
        actor.routinePaused=source.routinePaused
        if record.phase~=source.routinePhase or record.action~=source.routineAction then
            actor.routineClock=source.routineClock or 0
        elseif not source.moving then actor.routineClock=math.max(actor.routineClock or 0,source.routineClock or 0)+dt end
        record.phase,record.action=source.routinePhase,source.routineAction
        actor.routinePhase,actor.routineStep=source.routinePhase,source.routineStep
        local point=record.path and record.path[record.index]
        if point and dt>0 then
            local arrived=Motion.moveToward(actor,point.x,point.y,dt,{profile=Motion.profileFor(source.file) or Motion.defaults,
                speed=math.min(48,math.max(32,distance)),stopDistance=1,
                move=function(ox,oy,x,y)
                    if source.scene=='stop' then return Settlements.move(data.location,ox,oy,x,y) end
                    return Util.clampHouseFloor(x,y)
                end})
            if arrived or (actor.x-point.x)^2+(actor.y-point.y)^2<=1 then
                record.index=record.index+1
                if record.index>#record.path then record.path=nil; stop(actor) end
            end
        else stop(actor) end
        actor.routineAction=source.routineAction
        if actor.moving and source.routineAction~='carry' then actor.routineAction=nil end
        if not actor.moving then
            actor.facing=source.facing; actor.intentX,actor.intentY=source.intentX,source.intentY
        end
        visible[#visible+1]=actor; retained[source.file]=record
    end
    view.actors=retained
    runtime.npcActors=visible; runtime.npcActor=selected and retained[selected] and retained[selected].actor or nil
end
return Presentation
