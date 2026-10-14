-- ENet admission, reliable campaign state and optional realtime actor motion.
-- Discrete commands use peer-bound authority callbacks and bounded outcomes.
local P=require('game.net.protocol')
local Crypto=require('game.net.crypto')
local Identity=require('game.net.identity')
local Baseline=require('game.net.baseline')
local Transport=require('game.net.transport_enet')
local Movement=require('game.net.movement')
local Roaming=require('game.net.roaming')
local LastStandEffects=require('game.net.last_stand_effects')
local LastStandStage=require('game.net.last_stand_stage')
local Commands=require('game.net.commands')
local CommandRate=require('game.net.command_rate')
local Session={}; local Host={}; Host.__index=Host; local Client={}; Client.__index=Client
local function call(fn,...)
    local ok,value,reason=pcall(fn,...)
    if not ok then return nil,'callback_failed' end
    return value,reason
end
local function shape(message,kind,fields)
    local allowed={type=true,game=true,protocol=true}
    for _,key in ipairs(fields or {}) do allowed[key]=true end
    return P.envelope(message,kind) and P.fields(message,allowed)
end
local function binding(value)
    return P.fields(value,{campaignId=true,companionId=true})
        and Crypto.isHex(value.campaignId,32) and Crypto.isHex(value.companionId,32)
end
local function now(self)
    local value=call(self.context.clock)
    if not P.clock(value) then return nil end
    self.time=math.max(self.time or 0,value); return self.time
end
local function send(self,peer,message,channel,reliable)
    local bytes,reason=P.encode(message,channel or P.CONTROL)
    if not bytes then return nil,reason end
    if self.mode=='client' then return self.transport:sendToServer(bytes,channel or P.CONTROL,reliable~=false) end
    return self.transport:send(peer,bytes,channel or P.CONTROL,reliable~=false)
end
local function receipt(kind,header)
    return P.message(kind,{id=header.id,revision=header.revision,sceneEpoch=header.sceneEpoch,hash=header.hash})
end
local function sameReceipt(message,kind,header)
    return shape(message,kind,{'id','revision','sceneEpoch','hash'}) and message.id==header.id
        and message.revision==header.revision and message.sceneEpoch==header.sceneEpoch and message.hash==header.hash
end
local function base(context,mode)
    if type(context)~='table' or not Crypto.isHex(context.build,64) or not P.integer(context.schema,1,2147483647)
        or type(context.clock)~='function' then return nil,'invalid_session_options' end
    return {context=context,mode=mode,closed=false,time=0}
end
function Session.host(context)
    local self,reason=base(context,'host'); if not self then return nil,reason end
    for _,key in ipairs({'preflight','authenticate','issue','snapshot','revision'}) do
        if type(context[key])~='function' then return nil,'invalid_host_options' end
    end
    if not P.text(context.sessionId,64) or not Crypto.isHex(context.campaignId,32) then return nil,'invalid_session_id' end
    if not P.integer(context.generationBase or 0,0,2147483646) then return nil,'invalid_generation_base' end
    if call(context.preflight)~=true then return nil,'save_not_ready' end
    local transport,errorMessage=context.transport
    if not transport then transport,errorMessage=Transport.createHost({port=context.port,bind=context.bind,peerCapacity=2}) end
    if not transport then return nil,errorMessage end
    self.transport=transport; self.generation=context.generationBase or 0; self.snapshotId=0
    return setmetatable(self,Host)
end
function Session.join(address,context)
    local self,reason=base(context,'client'); if not self then return nil,reason end
    if not P.text(context.name,32) or not P.text(context.character,128) or type(context.validate)~='function'
        or type(context.store)~='function' or (context.credential~=nil and not Identity.credential(context.credential)) then
        return nil,'invalid_client_options'
    end
    local transport,errorMessage=context.transport
    if not transport then transport,errorMessage=Transport.createClient(address,{port=context.port}) end
    if not transport then return nil,errorMessage end
    self.transport=transport; self.status='connecting'; self.deadline=(now(self) or 0)+P.HELLO_SECONDS
    return setmetatable(self,Client)
end
function Host:_drop(reason)
    local link=self.link
    if not link then return end
    send(self,link.peer,P.message('reject',{reason=reason}))
    self.transport:disconnect(link.peer,0,false)
    self.link=nil; self.reason=reason
    if self.context.disconnected then call(self.context.disconnected,link.generation,reason) end
end
function Client:_fail(reason)
    if self.closed then return end
    if self.receiver then self.receiver:abort(reason) end
    self.receiver=nil; self.pendingSnapshot=nil; self.snapshot=nil
    self.status='failed'; self.reason=reason; self.closed=true
    self.transport:close(0,true)
    if self.context.disconnected then call(self.context.disconnected,reason) end
end
function Host:_welcome(value,credential)
    if not binding(value) or value.campaignId~=self.context.campaignId then return self:_drop('invalid_binding') end
    local link=self.link; link.binding=value; link.phase='credentials'; link.deadline=self.time+P.HELLO_SECONDS
    local message=P.message('welcome',{sessionId=self.context.sessionId,campaignId=value.campaignId,companionId=value.companionId})
    if credential then message.credential=credential end
    if not send(self,link.peer,message) then self:_drop('send_failed') end
end
function Host:pending()
    local link=self.link
    if not link or link.phase~='approval' then return nil end
    return {generation=link.generation,name=link.name,character=link.character}
end
function Host:approve(generation)
    local request=self:pending()
    if not request or request.generation~=generation then return nil,'stale_approval' end
    if not now(self) or self.time>=self.link.deadline then self:_drop('approval_timeout'); return nil,'approval_timeout' end
    if call(self.context.preflight)~=true then return nil,'save_not_ready' end
    local credential,reason=call(self.context.issue,request)
    if not Identity.credential(credential) then return nil,reason or 'admission_not_durable' end
    self:_welcome({campaignId=credential.campaignId,companionId=credential.companionId},credential)
    return self.link~=nil
end
function Host:decline(generation)
    local request=self:pending()
    if not request or request.generation~=generation then return nil,'stale_approval' end
    self:_drop('host_declined'); return true
end
function Host:_baseline(update)
    if call(self.context.preflight)~=true then return self:_drop('save_not_ready') end
    local link=self.link; link.transfers=(link.transfers or 0)+1
    if link.transfers>3 or self.snapshotId>=2147483647 then return self:_drop('state_changing') end
    local snapshot=update or call(self.context.snapshot,link.binding)
    if type(snapshot)~='table' then return self:_drop('snapshot_unavailable') end
    self.snapshotId=self.snapshotId+1
    local transfer=Baseline.pack(snapshot,self.snapshotId,self.context.hash)
    if not transfer then return self:_drop('invalid_snapshot') end
    link.transfer=transfer; link.phase='snapshot'; link.deadline=self.time+P.TRANSFER_SECONDS
    if not send(self,link.peer,transfer.header,P.STATE) then self:_drop('send_failed') end
end
function Host:_checkpointBarrier()
    local link=self.link
    if not link or not link.admitted then return end
    local pending=self.context.checkpointPending and call(self.context.checkpointPending)==true
    if pending then link.checkpointPausedAt=link.checkpointPausedAt or self.time
    elseif link.checkpointPausedAt then
        link.deadline=link.deadline+(self.time-link.checkpointPausedAt)
        link.checkpointPausedAt=nil
    end
end
function Host:_acknowledge()
    local link=self.link
    if call(self.context.preflight)~=true then
        if link.admitted and link.checkpointPausedAt then link.ackDeferred=true; return end
        return self:_drop('save_not_ready')
    end
    link.ackDeferred=nil
    local revision,epoch=call(self.context.revision)
    if revision~=link.transfer.header.revision or epoch~=link.transfer.header.sceneEpoch then return self:_baseline() end
    if not link.admitted and self.context.ready and call(self.context.ready,link.generation,link.binding)~=true then return self:_drop('admission_failed') end
    if not send(self,link.peer,receipt('ready',link.transfer.header)) then return self:_drop('send_failed') end
    local initial=not link.admitted
    link.phase='ready'; link.admitted=true; link.transfers=0
    if initial and self.context.command then
        local nextId=call(self.context.commandSequence,link.generation)
        local ready=P.message('commands_ready',{sessionId=self.context.sessionId,nextRequestId=nextId})
        if not Commands.ready(ready) or not send(self,link.peer,ready) then return self:_drop('command_admission_failed') end
    end
    link.lastReceive=self.time; link.nextPing=self.time+5; link.transfer=nil
    link.nextUpdate=self.time+.1
end
function Host:_receive(event)
    local link=self.link; if not link or event.peer~=link.peer then return end
    -- A preceding command in this transport batch may have opened a failed
    -- checkpoint. Recheck before handling an in-flight snapshot acknowledgement.
    self:_checkpointBarrier()
    if link.phase~='ready' and not link.checkpointPausedAt and self.time>=link.deadline then return self:_drop('join_timeout') end
    if event.channel==P.REALTIME and link.admitted and self.context.movement then
        local message=P.decode(event.payload or event.data,event.channel)
        if not Movement.input(message) or message.sessionId~=self.context.sessionId then return self:_drop('invalid_movement') end
        -- Keep only the newest intent at the adapter. Flooding packets cannot
        -- buy simulation time; this bucket also bounds callback work.
        link.moveTokens=math.min(8,(link.moveTokens or 8)+(self.time-(link.moveTokenTime or self.time))*30)
        link.moveTokenTime=self.time
        if link.moveTokens<1 then return end
        link.moveTokens=link.moveTokens-1
        local accepted=call(self.context.movement,link.generation,message)
        if accepted==nil then return self:_drop('movement_failed') end
        return
    end
    if event.channel~=P.CONTROL then return self:_drop('unexpected_channel') end
    local message=P.decode(event.payload or event.data,event.channel)
    if not message then return self:_drop('invalid_packet') end
    if link.admitted and shape(message,'pong') then link.lastReceive=self.time; return end
    if link.admitted and self.context.command and Commands.request(message) then
        if message.sessionId~=self.context.sessionId then return self:_drop('invalid_command_session') end
        local reply
        if not CommandRate.allow(link,message,self.time) then reply={ok=false,reason='rate_limited'}
        else
            reply=call(self.context.command,link.generation,Commands.unpack(message))
        end
        local outcome=Commands.outcome(self.context.sessionId,message.requestId,reply,message.command)
        if not outcome then return self:_drop('command_failed') end
        if not send(self,link.peer,outcome) then self:_drop('send_failed') end
        return
    end
    if link.admitted and self.context.sceneReady and Movement.ready(message) then
        if message.sessionId~=self.context.sessionId then return self:_drop('invalid_scene_ready') end
        if call(self.context.sceneReady,link.generation,message.sceneEpoch,message.motionId)==nil then return self:_drop('scene_ready_failed') end
        return
    end
    if link.phase=='hello' then
        if not shape(message,'hello',{'build','schema','name','character','credential'})
            or not P.text(message.name,32) or not P.text(message.character,128)
            or (message.credential~=nil and not Identity.credential(message.credential)) then return self:_drop('invalid_hello') end
        if message.build~=self.context.build or message.schema~=self.context.schema then return self:_drop('incompatible_build') end
        if call(self.context.preflight)~=true then return self:_drop('save_not_ready') end
        link.name=message.name; link.character=message.character
        local identity=message.credential and call(self.context.authenticate,message.credential)
        if identity then self:_welcome(identity)
        else
            link.phase='approval'; link.deadline=self.time+P.APPROVAL_SECONDS
            if not send(self,link.peer,P.message('pending')) then self:_drop('send_failed') end
        end
    elseif link.phase=='credentials' and shape(message,'welcome_ack',{'sessionId'})
        and message.sessionId==self.context.sessionId then self:_baseline()
    elseif link.phase=='acknowledging' and sameReceipt(message,'baseline_ack',link.transfer.header) then
        self:_acknowledge()
    elseif link.phase=='ready' and shape(message,'pong') then link.lastReceive=self.time
    else self:_drop('unexpected_message') end
end
function Host:service()
    if self.closed then return end
    if not now(self) then return self:close('invalid_clock') end
    self:_checkpointBarrier()
    local events,reason=self.transport:service(64)
    if reason or not events then return self:close('transport_failed') end
    for _,event in ipairs(events) do
        if event.type=='connect' then
            if self.link or self.generation>=2147483647 then
                send(self,event.peer,P.message('reject',{reason='session_full'})); self.transport:disconnect(event.peer,0,false)
            else
                self.generation=self.generation+1
                self.link={peer=event.peer,generation=self.generation,phase='hello',deadline=self.time+P.HELLO_SECONDS}
                if not send(self,event.peer,P.message('greeting',{build=self.context.build,schema=self.context.schema,
                    campaignId=self.context.campaignId})) then self:_drop('send_failed') end
            end
        elseif event.type=='disconnect' and self.link and event.peer==self.link.peer then self:_drop('peer_disconnected')
        elseif event.type=='receive' then self:_receive(event) end
    end
    local link=self.link
    if not link then return end
    if link.phase~='ready' and not link.checkpointPausedAt and self.time>=link.deadline then return self:_drop('join_timeout') end
    if link.admitted and self.time-link.lastReceive>=15 then return self:_drop('peer_timeout') end
end
-- Continuous state is captured after the application has simulated this frame.
-- Admission receipts and command acknowledgements still follow their original
-- reliable ordering in service(). Neither phase services the transport twice.
function Host:publish()
    if self.closed then return end
    if not now(self) then return self:close('invalid_clock') end
    self:_checkpointBarrier()
    local link=self.link
    if not link then return end
    if link.admitted then
        if self.time-link.lastReceive>=15 then return self:_drop('peer_timeout') end
        if self.time>=link.nextPing then
            link.nextPing=self.time+5
            if not send(self,link.peer,P.message('ping')) then return self:_drop('send_failed') end
        end
        if link.ackDeferred and not link.checkpointPausedAt then
            self:_acknowledge(); link=self.link
            if not link then return end
        end
    end
    if link.phase=='snapshot' then
        for _=1,2 do
            local part=link.transfer:next()
            if not part then link.phase='acknowledging'; break end
            if not send(self,link.peer,part,P.STATE) then return self:_drop('send_failed') end
            if link.transfer.index>link.transfer.header.parts then link.phase='acknowledging'; break end
        end
    elseif link.phase=='ready' then
        if self.link and self.context.update and self.time>=link.nextUpdate and call(self.context.preflight)==true then
            link.nextUpdate=self.time+.1
            local update,errorMessage=call(self.context.update,link.binding)
            if errorMessage then return self:_drop('state_update_failed') end
            if update then self:_baseline(update) end
        end
    end
end
function Host:update()
    self:service()
    return self:publish()
end
function Host:sendMotion(message)
    if self.closed or not self.link or not self.link.admitted then return false,'not_admitted' end
    if not Movement.snapshot(message) or message.sessionId~=self.context.sessionId then return nil,'invalid_motion' end
    return send(self,self.link.peer,message,P.REALTIME,false)
end
function Host:sendRoaming(message)
    if self.closed or not self.link or not self.link.admitted then return false,'not_admitted' end
    if not Roaming.snapshot(message) or message.sessionId~=self.context.sessionId then return nil,'invalid_roaming' end
    return send(self,self.link.peer,message,P.REALTIME,false)
end
function Host:sendLastStandEffects(message)
    if self.closed or not self.link or not self.link.admitted then return false,'not_admitted' end
    if not LastStandEffects.snapshot(message) or message.sessionId~=self.context.sessionId then return nil,'invalid_last_stand_effects' end
    return send(self,self.link.peer,message,P.REALTIME,false)
end
function Host:sendLastStandStage(message)
    if self.closed or not self.link or not self.link.admitted then return false,'not_admitted' end
    if not LastStandStage.snapshot(message) or message.sessionId~=self.context.sessionId then return nil,'invalid_last_stand_stage' end
    return send(self,self.link.peer,message,P.REALTIME,false)
end
function Host:close(reason)
    if self.closed then return true end
    self:_drop(reason or 'host_closed'); self.closed=true
    return self.transport:close(0,false)
end
function Client:_receive(event)
    if event.peer~=self.peer then return end
    if not self.snapshot and self.status~='ready' and self.time>=self.deadline then return self:_fail('join_timeout') end
    local message=P.decode(event.payload or event.data,event.channel)
    if not message then return self:_fail('invalid_packet') end
    if event.channel==P.REALTIME and message.type=='last_stand_stage' and self.context.lastStandStage then
        if not LastStandStage.snapshot(message) or message.sessionId~=self.sessionId then return self:_fail('invalid_last_stand_stage') end
        if not self.snapshot then return end
        if call(self.context.lastStandStage,message)==nil then self:_fail('last_stand_stage_apply_failed') end
        return
    end
    if event.channel==P.REALTIME and message.type=='last_stand_effects' and self.context.lastStandEffects then
        if not LastStandEffects.snapshot(message) or message.sessionId~=self.sessionId then return self:_fail('invalid_last_stand_effects') end
        if not self.snapshot then return end
        if call(self.context.lastStandEffects,message)==nil then self:_fail('last_stand_effects_apply_failed') end
        return
    end
    if event.channel==P.REALTIME and message.type=='roaming_motion' and self.context.roaming then
        if not Roaming.snapshot(message) or message.sessionId~=self.sessionId then return self:_fail('invalid_roaming') end
        if not self.snapshot then return end
        if call(self.context.roaming,message)==nil then self:_fail('roaming_apply_failed') end
        return
    end
    if event.channel==P.REALTIME and self.context.motion then
        if not Movement.snapshot(message) or message.sessionId~=self.sessionId then return self:_fail('invalid_motion') end
        -- The unreliable channel may overtake the initial ready receipt. A
        -- later motion frame will replace this one after the baseline commits.
        if not self.snapshot then return end
        if call(self.context.motion,message)==nil then self:_fail('motion_apply_failed') end
        return
    end
    if event.channel==P.CONTROL and shape(message,'reject',{'reason'}) and P.text(message.reason,64) then
        return self:_fail(message.reason)
    end
    -- Control and state channels can overtake each other. A heartbeat sent
    -- before an update header remains valid while that update is assembling.
    if event.channel==P.CONTROL and self.snapshot and shape(message,'ping') then
        self.lastReceive=self.time
        if not send(self,event.peer,P.message('pong')) then self:_fail('send_failed') end
        return
    end
    if event.channel==P.CONTROL and self.snapshot and Commands.ready(message) then
        if message.sessionId~=self.sessionId or self.nextRequestId then return self:_fail('invalid_command_admission') end
        self.nextRequestId=message.nextRequestId; return
    end
    if event.channel==P.CONTROL and self.snapshot and Commands.result(message) then
        if message.sessionId~=self.sessionId then return self:_fail('invalid_command_result') end
        local pending=self.pendingCommand
        if not pending or message.requestId<pending.requestId then return end
        if message.requestId~=pending.requestId then return self:_fail('unexpected_command_result') end
        if message.command~=pending.command then return self:_fail('wrong_command_result') end
        self.lastCommandResult=message
        if not message.savePending and message.reason~='save_pending' and message.reason~='busy' then self.pendingCommand=nil end
        return
    end
    if event.channel==P.CONTROL and self.status=='greeting' then
        if not shape(message,'greeting',{'build','schema','campaignId'}) or not Crypto.isHex(message.campaignId,32) then
            return self:_fail('invalid_greeting')
        end
        if message.build~=self.context.build or message.schema~=self.context.schema then return self:_fail('incompatible_build') end
        local credential=self.context.credential
        if self.context.credentialFor then
            local errorMessage
            credential,errorMessage=call(self.context.credentialFor,message.campaignId)
            if errorMessage then return self:_fail('credential_lookup_failed') end
        end
        if credential and (not Identity.credential(credential) or credential.campaignId~=message.campaignId) then credential=nil end
        self.sentCredential=credential; self.campaignId=message.campaignId; self.status='hello'
        if not send(self,event.peer,P.message('hello',{build=self.context.build,schema=self.context.schema,
            name=self.context.name,character=self.context.character,credential=credential})) then self:_fail('send_failed') end
    elseif event.channel==P.CONTROL and (self.status=='hello' or self.status=='approval') then
        if self.status=='hello' and shape(message,'pending') then
            self.status='approval'; self.deadline=self.time+P.APPROVAL_SECONDS; return
        end
        if not shape(message,'welcome',{'sessionId','campaignId','companionId','credential'})
            or not P.text(message.sessionId,64) or not Crypto.isHex(message.campaignId,32)
            or not Crypto.isHex(message.companionId,32) then return self:_fail('invalid_welcome') end
        if message.campaignId~=self.campaignId then return self:_fail('campaign_changed') end
        local credential=message.credential or self.sentCredential
        if not Identity.credential(credential) or credential.campaignId~=message.campaignId
            or credential.companionId~=message.companionId then return self:_fail('invalid_credential') end
        if message.credential and call(self.context.store,credential)~=true then return self:_fail('credential_not_saved') end
        self.credential=credential; self.sessionId=message.sessionId; self.status='snapshot'; self.deadline=self.time+P.TRANSFER_SECONDS
        if not send(self,event.peer,P.message('welcome_ack',{sessionId=self.sessionId})) then self:_fail('send_failed') end
    elseif event.channel==P.STATE and (self.status=='snapshot' or self.status=='acknowledging' or self.status=='ready') then
        if P.envelope(message,'baseline') then
            if self.receiver and not self.receiver.closed then return self:_fail('overlapping_baseline') end
            if self.header and (not P.integer(message.id,1,2147483647) or message.id<=self.header.id) then return self:_fail('stale_baseline') end
            local receiver=Baseline.receiver(message,self.time,self.context.validate,self.context.hash)
            if not receiver then return self:_fail('invalid_baseline') end
            self.receiver=receiver; self.header=receiver.header; self.status='snapshot'
            self.pendingSnapshot=nil; self.deadline=self.time+P.TRANSFER_SECONDS
        elseif self.receiver and self.status=='snapshot' then
            local snapshot,reason=self.receiver:push(message,self.time)
            if snapshot==nil then return self:_fail(reason or 'invalid_snapshot') end
            if snapshot then
                self.pendingSnapshot=snapshot; self.status='acknowledging'
                if not send(self,event.peer,receipt('baseline_ack',self.header)) then self:_fail('send_failed') end
            end
        else self:_fail('unexpected_part') end
    elseif event.channel==P.CONTROL and self.status=='acknowledging' and sameReceipt(message,'ready',self.header) then
        if self.context.apply and call(self.context.apply,self.pendingSnapshot)~=true then return self:_fail('snapshot_apply_failed') end
        self.snapshot=self.pendingSnapshot; self.pendingSnapshot=nil; self.receiver=nil; self.status='ready'; self.lastReceive=self.time
    else self:_fail('unexpected_message') end
end
function Client:sceneReady(epoch,motionId)
    if self.closed or not self.snapshot then return false,'not_ready' end
    local message=P.message('scene_ready',{sessionId=self.sessionId,sceneEpoch=epoch,motionId=motionId})
    if not Movement.ready(message) then return nil,'invalid_scene_ready' end
    return send(self,self.peer,message,P.CONTROL)
end
function Client:sendMovement(sequence,epoch,x,y,sprint,motionId)
    if self.closed or not self.snapshot then return false,'not_ready' end
    local message=P.message('movement',{sessionId=self.sessionId,sceneEpoch=epoch,sequence=sequence,x=x,y=y,sprint=sprint,motionId=motionId})
    if not Movement.input(message) then return nil,'invalid_movement' end
    return send(self,self.peer,message,P.REALTIME,false)
end
function Client:submitCommand(name,args,epoch,expected)
    if self.closed or not self.snapshot or not self.nextRequestId then return nil,'commands_not_ready' end
    if self.pendingCommand then return nil,'command_pending' end
    local m=P.message('command',{sessionId=self.sessionId,requestId=self.nextRequestId,command=name,args=args,
        sceneEpoch=epoch,expected=expected})
    if not Commands.request(m) then return nil,'invalid_command' end
    -- Retain the exact encoded request across retries, insulated from UI edits.
    local bytes=assert(P.encode(m,P.CONTROL))
    if not self.transport:sendToServer(bytes,P.CONTROL,true) then return nil,'send_failed' end
    self.pendingCommand={requestId=m.requestId,command=name,bytes=bytes,nextRetry=self.time+.75}
    self.nextRequestId=self.nextRequestId+1; self.lastCommandResult=nil
    return m.requestId
end
function Client:update()
    if self.closed then return end
    if not now(self) then return self:_fail('invalid_clock') end
    local events,reason=self.transport:service(64)
    if reason or not events then return self:_fail('transport_failed') end
    for _,event in ipairs(events) do
        if self.closed then break end
        if event.type=='connect' and self.status=='connecting' then
            self.peer=event.peer
            self.status='greeting'; self.deadline=self.time+P.HELLO_SECONDS
        elseif event.type=='receive' then self:_receive(event)
        elseif event.type=='disconnect' then self:_fail('host_disconnected') end
    end
    if self.closed then return end
    if self.pendingCommand and self.time>=self.pendingCommand.nextRetry then
        self.pendingCommand.nextRetry=self.time+.75
        if not self.transport:sendToServer(self.pendingCommand.bytes,P.CONTROL,true) then return self:_fail('send_failed') end
    end
    if self.snapshot then
        if self.time-self.lastReceive>=15 then self:_fail('host_timeout') end
    elseif self.time>=self.deadline then self:_fail('join_timeout') end
end
function Client:close()
    self:_fail('guest_left'); return true
end
return Session
