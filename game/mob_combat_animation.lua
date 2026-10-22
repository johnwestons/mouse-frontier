-- Authored enemy combat strips share the NPC six-frame action standard.
-- Images remain in the existing lazy/resident asset tables; this module owns
-- only transient playback state and quads, never campaign/save state.
local Profiles=require('game.mob_combat_profiles')
local Animation={profiles=Profiles}
local playback=setmetatable({},{__mode='k'})
local battlePlayback=setmetatable({},{__mode='k'})
local sheets=setmetatable({},{__mode='k'})
local collections={melee='mobAttackImages',ranged='mobRangedImages',hit='mobHitImages',death='mobDeathImages'}

function Animation.register(targets,register)
    for file,profile in pairs(Profiles) do
        for action,path in pairs(profile.paths) do register(targets[collections[action]],file..'@combat',path,'mob combat') end
    end
end

function Animation.action(unit)
    if unit.hp<=0 then return 'death' end
    if (unit.hitTimer or 0)>0 then return 'hit' end
    if (unit.actionTimer or 0)>0 then return unit.action=='ranged' and 'ranged' or 'melee' end
end

function Animation.frame(unit,clock,facing,state)
    local profile=Profiles[unit.file]
    if not profile then return nil end
    if not state then
        state=playback[unit]
        if not state then state={};playback[unit]=state end
    end
    if clock<(state.clock or 0) then for key in pairs(state) do state[key]=nil end end
    local action=Animation.action(unit)
    if action=='death' then
        if not state.downAt then state.downAt=clock;state.downFacing=facing end
        state.clock=clock
        return action,math.min(6,math.floor(math.max(0,clock-state.downAt)/.85*6+.000001)+1),state.downFacing
    end
    state.downAt=nil;state.downFacing=nil;state.clock=clock
    if not action then
        state.action=nil;state.timer=nil
        if profile.neutralFromCombat and not unit.moveAnim then return 'melee',1,facing end
        return nil
    end
    local timer=action=='hit' and unit.hitTimer or unit.actionTimer
    if state.action~=action or timer>(state.timer or 0)+.001 then
        state.duration=timer;state.action=action
    end
    state.timer=timer
    local progress=1-timer/math.max(.001,state.duration)
    return action,math.min(6,math.max(1,math.floor(progress*6+.000001)+1)),facing
end

function Animation.sample(context,unit,width,height,facing,clock)
    local owner=context.ui or context
    local battle=context.battle
    local saved=context.saveData and context.saveData.tacticalBattle
    local identity=saved and saved.encounterId or battle and battle.encounterId or battle
    local scope=battlePlayback[owner]
    if not scope or scope.identity~=identity then scope={identity=identity,units={}};battlePlayback[owner]=scope end
    local id=unit.id or unit
    scope.units[id]=scope.units[id] or {}
    local action,frame,poseFacing=Animation.frame(unit,clock,facing,scope.units[id])
    if not action then return false end
    local profile=Profiles[unit.file]
    local images=context[collections[action]]
    local image=images and images[unit.file..'@combat']
    if not image then return false end
    local cached=sheets[image]
    if not cached then
        local iw,ih=image:getDimensions()
        if iw%6~=0 then return false end
        cached={w=iw/6,h=ih,quads={}}
        for index=1,6 do cached.quads[index]=love.graphics.newQuad((index-1)*cached.w,0,cached.w,ih,iw,ih) end
        sheets[image]=cached
    end
    -- bodyExtent is measured from the neutral pose against the existing mob
    -- art, so attacks and collapsed bodies retain the same world scale.
    local scale=height/(profile.bodyExtent*cached.h/256)
    return {image=image,quad=cached.quads[frame],scale=scale,mirror=(poseFacing or 1)*profile.baseFacing,
        width=cached.w,height=cached.h,originY=cached.h,offsetY=0,action=action,frame=frame}
end
function Animation.draw(context,unit,x,y,width,height,facing,clock)
    local sample=Animation.sample(context,unit,width,height,facing,clock)
    if not sample then return false end
    love.graphics.setColor(1,1,1)
    love.graphics.draw(sample.image,sample.quad,x,y,0,sample.scale*sample.mirror,sample.scale,sample.width/2,sample.originY)
    return true
end

return Animation
