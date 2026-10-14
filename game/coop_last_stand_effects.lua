-- Realtime presentation expires independently of reliable campaign facts.
local P=require('game.net.protocol')
local Wire=require('game.net.last_stand_effects')
local Life=require('game.coop_last_stand_lifecycle')
local Presentation={}; local View={}; View.__index=View
function Presentation.frames(data,source,sessionId,serial)
    if not source then return {} end
    local combat=data and data.lastStand and data.lastStand.combat
    if not combat or not data.coop or source.encounterId~=combat.entityId
        or source.phaseRevision~=combat.phaseRevision or not P.clock(source.clock)
        or type(source.events)~='table' or #source.events>Wire.MAX_EVENTS or not Life.key(data) then
        return nil,'invalid_last_stand_effect_state'
    end
    local frames,frame,seen={},nil,{}
    for index=1,math.max(1,#source.events) do
        if not frame or #frame.events==Wire.BATCH then
            frame=P.message('last_stand_effects',{sessionId=sessionId,sceneEpoch=data.coop.sceneEpoch,
                domain=Life.key(data),encounterId=combat.entityId,phaseRevision=combat.phaseRevision,
                serial=serial,clock=math.floor(source.clock*1000+.5),paused=source.paused==true,events={}})
            frames[#frames+1]=frame
        end
        if source.events[index] then
            local event=Wire.pack(source.events[index])
            if not Wire.event(event) or seen[event.n] then return nil,'invalid_last_stand_effect_event' end
            seen[event.n]=true; frame.events[#frame.events+1]=event
        end
    end
    for _,value in ipairs(frames) do
        if not Wire.snapshot(value) or not P.encode(value,P.REALTIME) then return nil,'invalid_last_stand_effect_frame' end
    end
    return frames
end
function Presentation.new(context)
    assert(context.data and context.clock,'Last Stand effects context missing')
    return setmetatable({context=context,entries={}},View)
end
local function current(self,frame)
    local data=self.context.data(); local combat=data and data.lastStand and data.lastStand.combat
    return data and data.coop and combat and data.lastStand.lifecycle and data.lastStand.lifecycle.mode=='shootout'
        and frame.sceneEpoch==data.coop.sceneEpoch and frame.domain==Life.key(data)
        and frame.encounterId==combat.entityId and frame.phaseRevision==combat.phaseRevision and not combat.result
end
function View:observe()
    if self.frame and not current(self,self.frame) then self.frame=nil; self.entries={}; self.serial=nil end
end
function View:receive(frame)
    if not Wire.snapshot(frame) then return nil,'invalid_last_stand_effect_frame' end
    self:observe()
    if not current(self,frame) or self.serial and frame.serial<self.serial then return false end
    if self.frame and frame.clock<self.frame.clock then return false end
    local now=self.context.clock()
    -- Repeated batches replace visual age, never execute a hit or resource change.
    local changed=self.serial~=frame.serial
    for _,event in ipairs(frame.events) do
        local old=self.entries[event.n]
        if not old or old.serial~=frame.serial then
            self.entries[event.n]={value=Wire.unpack(event),received=now,paused=frame.paused,serial=frame.serial}
            changed=true
        end
    end
    if not changed then return false end
    self.frame=frame; self.received=now; self.serial=frame.serial
    local count=0; local keys={}
    for key in pairs(self.entries) do count=count+1; keys[#keys+1]=key end
    table.sort(keys)
    for index=1,count-Wire.MAX_EVENTS do self.entries[keys[index]]=nil end
    return true
end
function View:get()
    self:observe(); local now=self.context.clock()
    if not self.frame or now-self.received>Wire.STALE_SECONDS then return nil end
    local result={events={},clock=self.frame.clock/1000,paused=self.frame.paused}
    for key,entry in pairs(self.entries) do
        local age=now-entry.received
        if age>Wire.STALE_SECONDS then self.entries[key]=nil
        else
            local event={}; for name,value in pairs(entry.value) do event[name]=value end
            event.elapsed=event.elapsed+(entry.paused and 0 or math.max(0,age))
            if event.elapsed<=3 then result.events[#result.events+1]=event end
        end
    end
    table.sort(result.events,function(a,b) return a.serial<b.serial end)
    return result
end
return Presentation
