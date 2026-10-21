-- Presentation-only aim points. These never change shot validation or damage.
local Targets={}
local WorldView=require('game.world_view')

local function append(list,x,y,radius,width,height,canonical)
    if not canonical then
        local edgeX,edgeY=WorldView.toScreen(x+radius,y)
        x,y=WorldView.toScreen(x,y)
        radius=math.sqrt((edgeX-x)^2+(edgeY-y)^2)
    end
    if x>=0 and x<=width and y>=0 and y<=height then
        list[#list+1]={x=x,y=y,radius=radius}
    end
end

function Targets.range(session,width,height)
    local result={}
    if not session or session.phase~='play' then return result end
    local Range=require('game.shooting_range')
    local zoom=Range.magnification(session)
    for _,point in ipairs(Range.assistPoints(session)) do
        local x,y=480+(point.x-480)*zoom,330+(point.y-330)*zoom
        append(result,x,y,point.radius*zoom,width or 960,height or 720,session.canonicalView==true)
    end
    return result
end

function Targets.lastStand(state,width,height,canonical)
    local result={}
    if not state or state.result or state.ducking or (state.coverProgress or 0)>0 then return result end
    local Scene=require('game.window_scene')
    local layout=Scene.layout(state.windowId,width,height)
    for _,target in ipairs(state.targets or {}) do
        if (target.status=='appearing' or target.status=='exposed' or target.status=='firing')
            and (target.health==nil or target.health>0) then
            local x,y=Scene.slotPosition(layout,target.slot)
            local _,_,w,h=Scene.slotRect(layout,target.slot)
            if Scene.pointOpen(state.windowId,width,height,x,y) and Scene.targetHit(layout,target.slot,x,y) then
                append(result,x,y,math.min(w*.46,h*.5),width,height,canonical)
            end
        end
    end
    return result
end

-- Probe the actual alpha-tested shot path, including the carriage frame and
-- nearer vehicles, so assist cannot settle on a hidden crew member or glass.
local probes={{.5,.5},{.5,.3},{.3,.5},{.7,.5},{.5,.7},{.3,.3},{.7,.3},{.3,.7},{.7,.7}}
local function visiblePoint(Scene,state,width,height,entry,rect,kind,index)
    for _,probe in ipairs(probes) do
        local x=entry.x+(rect.x+rect.w*probe[1])*entry.scale
        local y=entry.y+(rect.y+rect.h*probe[2]-entry.sourceY)*entry.scale
        local hit=Scene.target(state,width,height,x,y)
        if hit and hit.kind==kind and hit.vehicle==entry.id and (not index or hit.index==index) then return x,y end
    end
end

function Targets.ambush(state,width,height)
    local result={}
    if not state or state.phase~='combat' or state.outcome or state.cover or (state.coverProgress or 0)>0 then return result end
    local Scene=require('game.train_ambush_scene')
    local Rules=require('game.train_ambush_rules')
    for _,entry in ipairs(Scene.layout(state,width,height).vehicles) do
        local vehicle=Rules.vehicle(state,entry.id)
        if vehicle and vehicle.hull>0 then
            local hasCrew=false
            for index,crew in ipairs(vehicle.crew or {}) do
                local clip=entry.visual.clips[index]
                if clip and Rules.exposed(crew) then
                    local x,y=visiblePoint(Scene,state,width,height,entry,clip,'crew',index)
                    if x then
                        append(result,x,y,math.min(clip.w,clip.h)*entry.scale*.35,width,height,true)
                        hasCrew=true
                    end
                end
            end
            if not hasCrew then
                local rect={x=0,y=entry.sourceY,w=entry.cellW,h=entry.height}
                local x,y=visiblePoint(Scene,state,width,height,entry,rect,'hull')
                if x then append(result,x,y,math.min(entry.cellW,entry.height)*entry.scale*.16,width,height,true) end
            end
        end
    end
    return result
end

return Targets
