-- Disposable client movement. A sequence is a held input sample, never a tick.
-- The host echoes its age at the last simulated step. sample.sentAt + ackAge
-- anchors that authoritative state on the client's input timeline without
-- accepting a client clock or elapsed-time claim on the server.
local Wire=require('game.net.movement')
local Step=require('game.coop_motion_step')
local P=require('game.net.protocol')
local Prediction={MAX_REPLAY=.25,MAX_SAMPLES=64,MAX_HISTORY=120,TELEPORT=140,CORRECTION_RATE=12,REMOTE_RATE=14}
local Client={}; Client.__index=Client
local ZERO={x=0,y=0,sprint=false}
local function copy(value) local result={}; for key,item in pairs(value) do result[key]=item end; return result end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function same(a,b) return a and a.x==b.x and a.y==b.y and a.sprint==b.sprint end
function Prediction.new(context)
    assert(context.clock and context.data and context.move,'prediction context required')
    return setmetatable({context=context,lastSent=0,samples={},sampleOrder={},history={},lastTime=context.clock(),
        lastUpdate=context.clock(),lastSerial=0,lastAck=0,lastTick=0,accumulator=0,offsetX=0,offsetY=0},Client)
end
function Client:reset(epoch,actor,remote,motionId)
    self.epoch=epoch; self.motionId=motionId; self.actor=copy(actor); self.display=copy(actor); self.authoritative=copy(actor)
    self.remote=copy(remote); self.remoteTarget=copy(remote)
    self.samples={}; self.sampleOrder={}; self.history={}; self.current=ZERO
    self.lastSerial=0; self.lastAck=0; self.lastTick=0; self.lastFrame=nil
    self.accumulator=0; self.offsetX=0; self.offsetY=0; self.lastTime=self.context.clock(); self.lastUpdate=self.lastTime
end
function Client:stale()
    return not self.lastFrame or self.context.clock()-self.lastFrame>=Wire.STALE_SECONDS
end
function Client:sent(sequence,input)
    if not P.integer(sequence,self.lastSent+1,2147483647) then return nil,'invalid_prediction_sequence' end
    self.lastSent=sequence
    self.samples[sequence]={at=self.context.clock(),input=copy(input)}
    self.sampleOrder[#self.sampleOrder+1]=sequence
    while #self.sampleOrder>Prediction.MAX_SAMPLES do self.samples[table.remove(self.sampleOrder,1)]=nil end
    return true
end
function Client:neutralize()
    self.samples={}; self.sampleOrder={}; self.history={}; self.current=ZERO
    self.accumulator=0; self.offsetX=0; self.offsetY=0
    Step.stop(self.actor); Step.stop(self.display)
end
function Client:_move(actor,record,input,dt)
    return Step.advance(actor,record,input,dt,function(ox,oy,x,y)
        return self.context.move(self.context.data(),record,ox,oy,x,y)
    end)
end
function Client:receive(frame,enabled)
    if not Wire.snapshot(frame) then return nil,'invalid_motion_state' end
    if frame.sceneEpoch~=self.epoch or frame.serial<=self.lastSerial
        or self.motionId and frame.motionId~=self.motionId then return false,'stale_motion' end
    self.motionId=frame.motionId
    if frame.ack>self.lastSent or frame.tick<self.lastTick or frame.ack<self.lastAck then return nil,'invalid_motion_ack' end
    local now=self.context.clock(); if not P.clock(now) or now<self.lastTime then return nil,'invalid_clock' end
    local old=self.display; local wasStale=self:stale()
    self.authoritative=Wire.unpackActor(frame.companion)
    local record=self.context.data().players.companion
    self.authoritative.character=record.character
    local nextActor=copy(self.authoritative); local sample=self.samples[frame.ack]
    local identityChanged=old.activeCar~=nextActor.activeCar or old.character~=nextActor.character
    if identityChanged then self:neutralize(); sample=nil end
    local base=sample and sample.at+frame.ackAge/1000
    local canReplay=enabled and frame.ready and not frame.paused and frame.inputActive and base
        and now-base>=-.001 and now-base<=Prediction.MAX_REPLAY
    self.accumulator=0
    if canReplay then
        base=math.min(now,base)
        local input=sample.input; local cursor=1
        -- Changes not yet acknowledged (including a just-pressed local key)
        -- become effective on their local timeline, not one step per packet.
        while self.history[cursor] and self.history[cursor].at<=base do
            if self.history[cursor].at>=sample.at then input=self.history[cursor].input end
            cursor=cursor+1
        end
        while base+Wire.STEP<=now+1e-9 do
            base=base+Wire.STEP
            while self.history[cursor] and self.history[cursor].at<=base+1e-9 do
                input=self.history[cursor].input; cursor=cursor+1
            end
            self:_move(nextActor,record,input,Wire.STEP)
        end
        self.accumulator=math.max(0,now-base)
    end
    local hard=not enabled or frame.paused or not frame.ready or wasStale
        or old.activeCar~=nextActor.activeCar or old.character~=nextActor.character
        or distance(old,nextActor)>Prediction.TELEPORT
    self.actor=nextActor
    self.offsetX=hard and 0 or old.x-nextActor.x; self.offsetY=hard and 0 or old.y-nextActor.y
    self.remoteTarget=Wire.unpackActor(frame.host)
    self.remoteTarget.character=self.context.data().players.host.character
    if wasStale or self.remote.activeCar~=self.remoteTarget.activeCar or self.remote.character~=self.remoteTarget.character
        or distance(self.remote,self.remoteTarget)>Prediction.TELEPORT then self.remote=copy(self.remoteTarget) end
    self.lastFrame=now; self.lastTime=now; self.lastSerial=frame.serial; self.lastAck=frame.ack; self.lastTick=frame.tick
    self.paused=frame.paused or not frame.ready
    -- Keep the acknowledged sample while it is held across later snapshots.
    while self.sampleOrder[1] and self.sampleOrder[1]<frame.ack do self.samples[table.remove(self.sampleOrder,1)]=nil end
    return true
end
function Client:update(input,enabled)
    local now=self.context.clock(); if not P.clock(now) or now<self.lastTime then return nil,'invalid_clock' end
    local simulationDelta=math.min(.25,now-self.lastTime); self.lastTime=now
    local dt=math.min(.25,now-self.lastUpdate); self.lastUpdate=now
    if not self.actor then return true end
    local data=self.context.data(); local record=data.players.companion
    local active=enabled and not self.paused and not self:stale()
    input=active and input or ZERO
    if not same(input,self.current) then
        self.current=copy(input); self.history[#self.history+1]={at=now,input=self.current}
    end
    while #self.history>Prediction.MAX_HISTORY or #self.history>1 and self.history[2].at<now-1 do table.remove(self.history,1) end
    if self:stale() then
        self.actor=copy(self.authoritative); self:neutralize(); self.current=ZERO
    elseif active then
        self.accumulator=math.min(Wire.STEP*Wire.MAX_CATCHUP,self.accumulator+simulationDelta)
        while self.accumulator+1e-9>=Wire.STEP do
            self.accumulator=math.max(0,self.accumulator-Wire.STEP)
            self:_move(self.actor,record,input,Wire.STEP)
        end
    else Step.stop(self.actor); self.accumulator=0 end
    local decay=math.exp(-Prediction.CORRECTION_RATE*dt)
    self.offsetX=self.offsetX*decay; self.offsetY=self.offsetY*decay
    if math.abs(self.offsetX)<.01 then self.offsetX=0 end
    if math.abs(self.offsetY)<.01 then self.offsetY=0 end
    self.display=copy(self.actor)
    -- Smooth visible sub-frame travel with the same collision/motion rules.
    if active and self.accumulator>1e-6 then self:_move(self.display,record,input,self.accumulator) end
    self.display.x,self.display.y=self.context.move(data,record,self.display.x,self.display.y,
        self.display.x+self.offsetX,self.display.y+self.offsetY)
    local target=self.remoteTarget; local remote=self.remote; local alpha=1-math.exp(-Prediction.REMOTE_RATE*dt)
    local x,y=remote.x+(target.x-remote.x)*alpha,remote.y+(target.y-remote.y)*alpha
    local animationDistance=(remote.animationDistance or 0)+((target.animationDistance or 0)-(remote.animationDistance or 0))*alpha
    local phase=(remote.posePhase or 0)+((target.posePhase or 0)-(remote.posePhase or 0))*alpha
    local remaining=math.sqrt((x-target.x)^2+(y-target.y)^2)
    self.remote=copy(target)
    if remaining>.01 then
        self.remote.x,self.remote.y=x,y; self.remote.animationDistance=animationDistance; self.remote.posePhase=phase
    end
    if self:stale() then Step.stop(self.remote) end
    return true
end
return Prediction
