-- Host-owned companion motion, independent of the host's local menu/input.
-- Only direction and sprint arrive from the peer. No remote delta time, speed,
-- coordinates, actor ID, save pointer or scene choice enters this simulation.
local Motion=require('game.character_motion')
local Step=require('game.coop_motion_step')
local Wire=require('game.net.movement')
local P=require('game.net.protocol')
local Movement={}; local Host={}; Host.__index=Host
local stop=Step.stop
function Movement.host(context)
    assert(context.campaign and context.clock and context.move and context.allowed and context.hostActor,'movement context required')
    return setmetatable({context=context,tick=0,serial=0,sequence=0,ack=0,motionId=0,accumulator=0,last=context.clock()},Host)
end
function Host:_synchronize()
    local data=self.context.campaign; local record=data.players.companion
    local domain=self.context.domain and self.context.domain()
    local pose=self.context.position and self.context.position('companion') or record
    local epoch=data.coop.sceneEpoch
    local sceneRevision=require('game.coop_presence').revision(data,'companion')
    if not record then self.actor=nil; self.readyEpoch=nil; self.input=nil; return end
    if not self.actor or self.epoch~=epoch or self.domain~=domain or self.sceneRevision~=sceneRevision or self.character~=record.character or self.actor.activeCar~=record.activeCar then
        assert(self.motionId<2147483647,'motion generation exhausted')
        self.motionId=self.motionId+1; self.accumulator=0
        self.epoch=epoch; self.character=record.character; self.readyEpoch=nil; self.input=nil; self.simInput=nil
        self.inputQueue={}; self.heldInput=nil
        self.domain=domain; self.sceneRevision=sceneRevision
        self.actor={x=pose.playerX,y=pose.playerY,facing=pose.playerFacing or 1,activeCar=record.activeCar,speed=185,character=record.character}
        Motion.resetActor(self.actor); self.actor.facing=pose.playerFacing or 1
    end
end
function Host:admit(generation)
    assert(P.integer(generation,1,2147483647),'invalid movement generation')
    self:disconnect(); self.actor=nil; self.generation=generation; self.sequence=0; self.ack=0
    self.last=self.context.clock(); self.accumulator=0; self:_synchronize()
end
function Host:disconnect(generation)
    if generation and self.generation~=generation then return false end
    stop(self.actor); self.generation=nil; self.input=nil; self.readyEpoch=nil; self.simInput=nil
    self.inputQueue={}; self.heldInput=nil; return true
end
-- Called by the host's world simulation, never by a movement message. A fresh
-- motion generation discards old predicted inputs while retaining actor/save
-- ownership and the scene epoch. The guest acknowledges its corrected spawn.
function Host:relocate(x,y)
    self:_synchronize()
    if self.domain then return false,'modal_scene' end
    if not self.generation or not self.actor then return false,'unbound_peer' end
    if type(x)~='number' or type(y)~='number' or x~=x or y~=y or math.abs(x)>100000 or math.abs(y)>100000 then return false,'invalid_position' end
    if not Wire.actor(Wire.packActor({x=x,y=y},self.context.campaign.players.companion)) then return false,'invalid_position' end
    if self.motionId>=2147483647 then return false,'motion_generation_exhausted' end
    local record=self.context.campaign.players.companion
    record.playerX,record.playerY=x,y
    stop(self.actor); self.actor=nil; self:_synchronize()
    return true
end
function Host:ready(generation,epoch,motionId)
    self:_synchronize()
    if not self.generation or generation~=self.generation or not self.actor or epoch~=self.epoch
        or motionId~=self.motionId then return false,'stale_scene' end
    self.readyEpoch=epoch; return true
end
function Host:receive(generation,message)
    if not Wire.input(message) then return nil,'invalid_movement' end
    self:_synchronize()
    if not self.generation or generation~=self.generation or not self.actor then return false,'unbound_peer' end
    if message.sceneEpoch~=self.epoch or message.motionId~=self.motionId or self.readyEpoch~=self.epoch then return false,'scene_not_ready' end
    if message.sequence<=self.sequence then return false,'stale_input' end
    self.sequence=message.sequence
    self.input={x=message.x/1000,y=message.y/1000,sprint=message.sprint,sequence=message.sequence,received=self.context.clock()}
    -- Input is sampled in host time. Preserve the previous held sample for
    -- catch-up steps before this packet arrived; using nil there repeatedly
    -- stopped the gait on hosts whose frames did not align with 30 Hz ticks.
    local queue=self.inputQueue
    if queue[#queue] and queue[#queue].received==self.input.received then queue[#queue]=self.input
    else queue[#queue+1]=self.input end
    while #queue>64 do table.remove(queue,1) end
    return true
end
function Host:allowed()
    local record=self.context.campaign.players.companion
    return self.generation~=nil and record~=nil and record.health>0 and self.readyEpoch==self.epoch
        and self.context.allowed(self.generation)==true
end
function Host:update()
    local now=self.context.clock()
    if not P.clock(now) or now<self.last then return nil,'invalid_clock' end
    self:_synchronize()
    self.accumulator=math.min(Wire.STEP*Wire.MAX_CATCHUP,self.accumulator+now-self.last); self.last=now
    if not self.actor or not self:allowed() then
        stop(self.actor); self.input=nil; self.simInput=nil; self.accumulator=0
        self.inputQueue={}; self.heldInput=nil; return true
    end
    if self.input and now-self.input.received>=Wire.STALE_SECONDS then
        self.input=nil; self.simInput=nil; self.inputQueue={}; self.heldInput=nil; stop(self.actor)
    end
    local record=self.context.campaign.players.companion
    while self.accumulator+1e-9>=Wire.STEP do
        local stepTime=now-self.accumulator+Wire.STEP; self.accumulator=math.max(0,self.accumulator-Wire.STEP)
        if self.tick>=2147483647 then return nil,'motion_tick_exhausted' end
        self.tick=self.tick+1
        while self.inputQueue[1] and self.inputQueue[1].received<=stepTime+1e-9 do
            self.heldInput=table.remove(self.inputQueue,1)
        end
        local input=self.heldInput
        if input and stepTime-input.received>=Wire.STALE_SECONDS then input=nil; self.heldInput=nil end
        local mover=function(ox,oy,nx,ny) return self.context.move(self.context.campaign,record,ox,oy,nx,ny) end
        Step.advance(self.actor,record,input,Wire.STEP,mover)
        self.simInput=input; self.stateTime=stepTime
        if input then self.ack=input.sequence end
        if self.context.store then self.context.store(self.actor)
        else record.playerX,record.playerY,record.playerFacing=self.actor.x,self.actor.y,self.actor.facing end
    end
    return true
end
function Host:snapshot(sessionId)
    self:_synchronize()
    local data=self.context.campaign; local host=self.context.hostActor()
    if not self.actor or not self.generation or not host then return nil end
    self.serial=self.serial+1
    local message=P.message('motion',{sessionId=sessionId,sceneEpoch=self.epoch,motionId=self.motionId,serial=self.serial,tick=self.tick,ack=self.ack,domain=self.domain,
        paused=not self:allowed(),ready=self.readyEpoch==self.epoch,
        inputActive=self.simInput~=nil,
        ackAge=self.simInput and math.max(0,math.min(350,math.floor((self.stateTime-self.simInput.received)*1000+.5))) or 0,
        host=Wire.packActor(host,data.players.host,self.context.presentation and self.context.presentation('host')),
        companion=Wire.packActor(self.actor,data.players.companion,self.context.presentation and self.context.presentation('companion'))})
    if not Wire.snapshot(message) then return nil,'invalid_motion_state' end
    return message
end
return Movement
