-- Disposable enemy visuals. Never mutate a replica, save, AI, or command model.
local Areas=require('game.expedition_areas')
local Wire=require('game.net.roaming')
local P=require('game.net.protocol')
local Presentation={}; local View={}; View.__index=View
function Presentation.frames(data,system,sessionId,serial,paused)
    if not data or data.scene~='expedition' or data.tacticalBattle then return {} end
    local area=Areas.current(data); local state=area and data.expeditions and data.expeditions[area.id]
    if not state or not data.coop or not system or #(area.mobs or {})>Wire.MAX_MOBS then return nil,'invalid_roaming_state' end
    local frames,frame={}
    for _,definition in ipairs(area.mobs or {}) do
        local saved=state.mobs and state.mobs[definition.id]
        if not saved then return nil,'invalid_roaming_entity' end
        if not frame or #frame.mobs==Wire.BATCH then
            frame=P.message('roaming_motion',{sessionId=sessionId,sceneEpoch=data.coop.sceneEpoch,
                sourceRevision=data.coop.revision,serial=serial,areaId=area.id,paused=paused==true,mobs={}})
            frames[#frames+1]=frame
        end
        local transient=system.transient and system.transient[area.id] and system.transient[area.id][definition.id]
        frame.mobs[#frame.mobs+1]=Wire.pack(definition,saved,transient,not definition.requires or state.gates and state.gates[definition.requires]==true)
    end
    for _,value in ipairs(frames) do
        if not Wire.snapshot(value) or not P.encode(value,P.REALTIME) then return nil,'invalid_roaming_frame' end
    end
    return frames
end
function Presentation.new(context)
    assert(context.data and context.clock,'enemy presentation context missing')
    local self=setmetatable({context=context,entries={},knownDead={},deaths={}},View)
    self:observe(); return self
end
-- Called only after a checked reliable projection commits. Baseline deaths
-- are history; only an observed living -> dead change can animate a defeat.
function View:observe()
    local data=self.context.data(); if not data or not data.coop then return end
    local now=self.context.clock()
    for areaId,state in pairs(data.expeditions or {}) do
        for id,mob in pairs(state.mobs or {}) do
            if Areas.mobDefinition(areaId,id) and type(mob.entityId)=='string' then
                local key=mob.entityId
                if mob.dead and self.knownDead[key]==false then self.deaths[key]={epoch=data.coop.sceneEpoch,untilTime=now+1.35}
                elseif not mob.dead then self.deaths[key]=nil end
                self.knownDead[key]=mob.dead==true
            end
        end
    end
end
local function current(self,frame)
    local data=self.context.data()
    return data and data.coop and data.scene=='expedition' and not data.tacticalBattle
        and frame.sceneEpoch==data.coop.sceneEpoch and frame.areaId==data.activeExpeditionArea
        and frame.sourceRevision==data.coop.revision and data
end
local function interpolate(entry,now)
    local alpha=math.max(0,math.min(1,(now-entry.received)/Wire.INTERVAL))
    local value={}; for key,item in pairs(entry.value) do value[key]=item end
    for _,key in ipairs({'x','y','animationDistance'}) do value[key]=entry.start[key]+(value[key]-entry.start[key])*alpha end
    local age=entry.paused and 0 or math.max(0,now-entry.received)
    for _,key in ipairs({'timer','hitTimer','healthTimer'}) do value[key]=math.max(0,value[key]-age) end
    value.deathTimer=value.deathTimer+age
    return value
end
function View:receive(frame)
    if not Wire.snapshot(frame) then return nil,'invalid_roaming_frame' end
    local data=current(self,frame); if not data then return false end
    local mobs=data.expeditions and data.expeditions[frame.areaId] and data.expeditions[frame.areaId].mobs
    -- Validate the complete batch before installing any visual changes.
    for _,value in ipairs(frame.mobs) do
        local saved=mobs and mobs[value.id]
        if not saved or saved.entityId~=value.e or not Areas.mobDefinition(frame.areaId,value.id) then return nil,'unknown_roaming_entity' end
    end
    local now=self.context.clock(); local changed=false
    for _,value in ipairs(frame.mobs) do
        local old=self.entries[value.id]
        if not old or old.frame.sceneEpoch~=frame.sceneEpoch or frame.serial>old.frame.serial then
            local unpacked=Wire.unpack(value); local start=unpacked
            if old and current(self,old.frame) and now-old.received<=Wire.STALE_SECONDS then
                local previous=interpolate(old,now)
                if (previous.x-unpacked.x)^2+(previous.y-unpacked.y)^2<=120^2 then start=previous end
            end
            self.entries[value.id]={frame=frame,entityId=value.e,value=unpacked,start=start,received=now,paused=frame.paused}
            changed=true
        end
    end
    return changed
end
function View:get(id)
    local entry=self.entries[id]; local now=self.context.clock()
    if not entry or not current(self,entry.frame) or now-entry.received>Wire.STALE_SECONDS then return nil end
    local value=interpolate(entry,now)
    local death=self.deaths[entry.entityId]
    value.allowDeath=death~=nil and death.epoch==entry.frame.sceneEpoch and now<death.untilTime
    return value
end
return Presentation
