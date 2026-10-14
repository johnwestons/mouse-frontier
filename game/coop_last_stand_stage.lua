local Wire=require('game.net.last_stand_stage')
local P=require('game.net.protocol')
local Life=require('game.coop_last_stand_lifecycle')
local Stage={}; local View={}; View.__index=View
function Stage.frame(data,source,sessionId,serial)
    if not source then return false end
    local life=Life.active(data)
    if not life or source.questId~=life.entityId or source.lifeRevision~=life.revision or source.mode~=life.mode then
        return nil,'invalid_last_stand_stage_state'
    end
    local values=Wire.pack(source); values.sessionId=sessionId; values.sceneEpoch=data.coop.sceneEpoch; values.serial=serial
    local frame=P.message('last_stand_stage',values)
    if not Wire.snapshot(frame) or not P.encode(frame,P.REALTIME) then return nil,'invalid_last_stand_stage_frame' end
    return frame
end
function Stage.new(context)
    assert(context.data and context.clock,'Last Stand stage context missing')
    return setmetatable({context=context},View)
end
local function current(self,frame)
    local data=self.context.data(); local life=Life.active(data)
    return life and data.coop and data.coop.sceneEpoch==frame.sceneEpoch and life.entityId==frame.questId
        and life.revision==frame.lifeRevision and life.mode==frame.mode
end
function View:observe() if self.frame and not current(self,self.frame) then self.frame=nil end end
function View:receive(frame)
    if not Wire.snapshot(frame) then return nil,'invalid_last_stand_stage_frame' end
    self:observe()
    if not current(self,frame) or self.frame and (frame.serial<=self.frame.serial or frame.clock<self.frame.clock) then return false end
    self.frame=frame; self.received=self.context.clock(); return true
end
function View:get()
    self:observe(); if not self.frame then return nil end
    local age=math.max(0,self.context.clock()-self.received)
    if age>Wire.STALE_SECONDS then return nil end
    local result=Wire.unpack(self.frame)
    if not result.paused then result.clock=result.clock+math.min(.1,age) end
    return result
end
return Stage
