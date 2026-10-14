-- Application-owned LAN lifecycle. Guest state stays in a non-save replica;
-- client presentation/input will consume that explicit model, not a new save.
local Session=require('game.net.session')
local GameState=require('game.net.game_state')
local Compatibility=require('game.net.compatibility')
local Credentials=require('game.net.credential_store')
local Admission=require('game.coop_admission')
local Address=require('game.net.address')
local P=require('game.net.protocol')
local Movement=require('game.coop_movement')
local MovementWire=require('game.net.movement')
local RoamingPresentation=require('game.coop_roaming_presentation')
local RoamingWire=require('game.net.roaming')
local LastStandEffects=require('game.coop_last_stand_effects')
local LastStandEffectsWire=require('game.net.last_stand_effects')
local LastStandStage=require('game.coop_last_stand_stage')
local LastStandStageWire=require('game.net.last_stand_stage')
local Discovery=require('game.net.lan_discovery')
local Reconnect=require('game.net.lan_reconnect')
local LocalPlay={}; LocalPlay.__index=LocalPlay
local function protected(fn,...)
    local ok,result,reason=pcall(fn,...)
    if not ok then return nil,'operation_failed' end
    return result,reason
end
function LocalPlay.new(context)
    assert(context.runtime and context.session and context.commands and context.filesystem and context.clock,'local play context missing')
    local preferences=context.localPlayPreferences or {}
    local mode=preferences.connectionMode
    if mode~='wifi' and mode~='usb' then mode='auto' end
    return setmetatable({context=context,address='',name='Friend',port='22124',characterIndex=1,menuOpen=false,
        phase='idle',previewOnly=true,nextAudit=0,connectionMode=mode,autoJoin=preferences.autoJoin==true,
        discovery=context.discovery or Discovery.new({socket=context.discoverySocket,clock=context.clock,
            port=context.discoveryPort,addressDetector=context.addressDetector,queryTargets=context.discoveryTargets}),
        reconnect=Reconnect.new(),interfaces={},discoveryMessage='Discovery is idle.'},LocalPlay)
end
local function matches(interface,mode)
    return mode=='auto' or mode=='usb' and interface.isUsb==true or mode=='wifi' and not interface.isUsb
end
local function sameSubnet(interface,address)
    if not Address.isIPv4(interface.address) or not Address.isIPv4(address) then return false end
    local prefix=tonumber(interface.prefixLength) or 24
    if prefix~=math.floor(prefix) or prefix<1 or prefix>32 then prefix=24 end
    local left,right={},{}
    for octet in interface.address:gmatch('%d+') do left[#left+1]=tonumber(octet) end
    for octet in address:gmatch('%d+') do right[#right+1]=tonumber(octet) end
    for index=1,4 do
        local bits=math.min(8,prefix); local block=2^(8-bits)
        if math.floor(left[index]/block)~=math.floor(right[index]/block) then return false end
        prefix=prefix-bits
    end
    return true
end
function LocalPlay:_resetAutoJoin()
    self.autoJoinCandidate=nil; self.autoJoinSince=nil; self.autoJoinFired=nil; self.autoJoinBlocked=nil
end
function LocalPlay:_savePreferences()
    if self.context.saveLocalPlayPreferences then
        local ok=protected(self.context.saveLocalPlayPreferences,{connectionMode=self.connectionMode,autoJoin=self.autoJoin})
        if ok~=true then self.preferenceError='Connection preferences could not be saved on this device.'; return false end
    end
    self.preferenceError=nil; return true
end
function LocalPlay:setConnectionMode(mode)
    if mode~='auto' and mode~='wifi' and mode~='usb' then return false end
    self.connectionMode=mode; self.manualEntry=false; self:_resetAutoJoin(); self:_savePreferences()
    if self.phase=='idle' and self.menuOpen then self:refreshDiscovery() end
    return true
end
function LocalPlay:setAutoJoin(enabled)
    self.autoJoin=enabled==true; self:_resetAutoJoin(); self:_savePreferences(); return true
end
function LocalPlay:_detectInterfaces()
    local result=protected(self.context.addressDetector or Address.detectLanInterfaces,
        self.context.addressOptions or (self.context.discoverySocket~=nil and {socket=self.context.discoverySocket,native=false} or {}))
    self.interfaces=type(result)=='table' and result or {}; return self.interfaces
end
function LocalPlay:localInterfaces()
    local result={}
    for _,entry in ipairs(self.interfaces) do
        result[#result+1]={address=entry.address,prefixLength=entry.prefixLength,broadcast=entry.broadcast,
            interfaceName=entry.interfaceName,isUsb=entry.isUsb==true}
    end
    return result
end
function LocalPlay:refreshDiscovery()
    if self.network then return false end
    self:_resetAutoJoin(); self:_detectInterfaces()
    local selected={}
    for _,entry in ipairs(self.interfaces) do if matches(entry,self.connectionMode) then selected[#selected+1]=entry end end
    local ok,reason=protected(self.discovery.startSearch,self.discovery,{localInterfaces=selected,
        detectInterfaces=false,connectionMode=self.connectionMode})
    self.discoveryMessage=ok and select(2,self.discovery:status()) or reason or 'Discovery is unavailable; enter the host address manually.'
    return ok==true,reason
end
function LocalPlay:discoveryStatus()
    return self.preferenceError or self.discoveryMessage
end
function LocalPlay:discoveredHosts()
    local result={}
    for _,host in ipairs(self.discovery:results()) do
        local allowed=self.connectionMode=='auto'
        for _,entry in ipairs(self.interfaces) do
            if matches(entry,self.connectionMode) and sameSubnet(entry,host.address) then allowed=true end
        end
        if allowed then result[#result+1]={address=host.address,port=host.port,name=host.name} end
    end
    return result
end
function LocalPlay:joinDiscovered(index)
    local hosts=self:discoveredHosts(); local host
    if type(index)=='table' then
        for _,candidate in ipairs(hosts) do
            if candidate.address==index.address and candidate.port==index.port then host=candidate; break end
        end
    else host=hosts[index] end
    if not host then return self:_error('discovered_host_expired') end
    self.address=host.address..':'..tostring(host.port); return self:join()
end
function LocalPlay:reconnectStatus() return self.reconnect:snapshot() end
function LocalPlay:cancelReconnect()
    self:stop('connection_cancelled'); if self.menuOpen then self:refreshDiscovery() end
    self.autoJoinBlocked=true; return true
end
function LocalPlay:_updateConvenience(dt)
    local now=self.context.clock()
    local elapsed=self.convenienceLast and math.max(0,now-self.convenienceLast) or 0
    self.convenienceLast=now
    protected(self.discovery.update,self.discovery,dt or 0)
    local mode,message=self.discovery:status()
    if mode~='idle' then self.discoveryMessage=message end
    if self.phase=='idle' and self.menuOpen and self.reconnect:isActive() then
        local attempt=self.reconnect:update(elapsed)
        if attempt then
            self.address=attempt.address; self.name=attempt.playerName
            local ok,reason=self:join(true)
            if not ok then self.reconnect:failed(reason); self:refreshDiscovery(); self.autoJoinBlocked=true end
        end
        return
    end
    if self.network or self.hostingIntent or not self.menuOpen or self.phase~='idle' or self.context.runtime.state~='slots'
        or not self.autoJoin or self.manualEntry or self.autoJoinBlocked or self.reconnect:isActive()
        or not P.text(self.name,32) or not self:character() then
        self.autoJoinCandidate=nil; self.autoJoinSince=nil; return
    end
    local hosts=self:discoveredHosts()
    if #hosts~=1 then self.autoJoinCandidate=nil; self.autoJoinSince=nil; return end
    local signature=hosts[1].address..':'..hosts[1].port
    if self.autoJoinCandidate~=signature then
        self.autoJoinCandidate=signature; self.autoJoinSince=self.context.clock(); self.autoJoinFired=nil; return
    end
    if self.autoJoinFired~=signature and self.context.clock()-self.autoJoinSince>=1.5 then
        self.autoJoinFired=signature; self:joinDiscovered(1)
    end
end
function LocalPlay:characters() return self.context.characters() end
function LocalPlay:character()
    local characters=self:characters()
    self.characterIndex=math.max(1,math.min(self.characterIndex,#characters))
    return characters[self.characterIndex]
end
function LocalPlay:cycleCharacter(direction)
    local count=#self:characters(); if count>0 then self.characterIndex=(self.characterIndex-1+direction)%count+1 end
end
function LocalPlay:_error(reason) self.error=reason or 'operation_failed'; return nil,self.error end
function LocalPlay:_build()
    if not self.compatibility then
        local result,reason=protected(self.context.compatibility or Compatibility.compute,self.context.filesystem)
        if not result then return self:_error(reason) end
        self.compatibility=result
    end
    return self.compatibility
end
function LocalPlay:open()
    self.menuOpen=true; self.error=nil
    if not self.network then self:refreshDiscovery() end
    if self.clientView then
        if self.clientView.inventory then self.clientView.inventory:cancelDrag() end
        if self.clientView.objects then self.clientView.objects:suspend() end
        if self.clientView.people then self.clientView.people:close() end
        if self.clientView.activities then self.clientView.activities:suspend() end
        if self.clientView.lastStand and self.clientView.lastStand.aid then self.clientView.lastStand.aid:suspend() end
        self.clientView:neutralize()
    end
    if self.context.neutralize then self.context.neutralize() end
end
function LocalPlay:closeMenu()
    if self.hostingIntent then return self:cancelHostingEntry() end
    if self:isClient() and not (self.clientView and self.clientView.ready) then return false end
    self.menuOpen=false
    if not self.network then self.reconnect:cancel(false); self.discovery:stop() end
    return true
end
function LocalPlay:canHost()
    local c=self.context; local runtime=c.runtime
    if not runtime.saveData or not runtime.selectedSlot or not c.session:canWriteCampaign() then return false end
    if runtime.saveData.tacticalBattle then
        local ok,battle=pcall(require('game.tactical_battle_state').pending,runtime.saveData)
        return ok and battle~=nil and runtime.state=='battle' and runtime.battle==battle
    end
    return runtime.state=='game' and not runtime.battle
end
function LocalPlay:canHostSavedJourney()
    return not self.network and self.hostingIntent~='failed' and self.context.runtime.state=='slots'
        and self.context.session:canWriteCampaign()
end
function LocalPlay:hostSavedJourney()
    if not self:canHostSavedJourney() then return self:_error('hosting_entry_unavailable') end
    if not P.integer(tonumber(self.port),1,65535) then return self:_error('invalid_port') end
    self.hostingIntent='selecting'; self.error=nil; self.menuOpen=false
    self.reconnect:cancel(false); self.discovery:stop(); self:_resetAutoJoin()
    if self.context.neutralize then self.context.neutralize() end
    return true
end
function LocalPlay:finishHostingEntry()
    if self.hostingIntent~='selecting' then return false,'hosting_not_requested' end
    local runtime=self.context.runtime
    if not P.integer(runtime.selectedSlot,1,99) or not self:canHost() then
        self.hostingIntent='failed'; self.menuOpen=true; return self:_error('load_journey_to_host')
    end
    local ok,reason=protected(self.host,self)
    if not ok then self.hostingIntent='failed'; self.menuOpen=true; return self:_error(reason) end
    self.hostingIntent=nil; return true
end
function LocalPlay:retryHostingEntry()
    if self.hostingIntent~='failed' then return false,'hosting_not_requested' end
    self.hostingIntent='selecting'; return self:finishHostingEntry()
end
function LocalPlay:cancelHostingEntry()
    self.hostingIntent=nil; self.error=nil; self.menuOpen=false
    if not self.network then self.reconnect:cancel(false); self.discovery:stop() end
    return true
end
function LocalPlay:host()
    if self.network then return self:_error('session_already_open') end
    local c=self.context; local runtime=c.runtime
    if not self:canHost() then return self:_error('load_journey_to_host') end
    local port=tonumber(self.port)
    if not P.integer(port,1,65535) then return self:_error('invalid_port') end
    local build=self:_build(); if not build then return nil,self.error end
    local authority,reason=c.commands.authority()
    if not authority then return self:_error(reason) end
    if authority.campaign~=runtime.saveData then return self:_error('campaign_changed') end
    local audited,auditError=GameState.audit(authority.campaign)
    if not audited then return self:_error(auditError) end
    if not authority:checkpointNow() then return self:_error('save_not_ready') end
    local allowed={}; for _,character in ipairs(self:characters()) do allowed[character]=true end
    local admission,admissionError=Admission.new(authority,{catalog=c.catalog,allowedCharacters=allowed,
        placeCompanion=c.placeCompanion,token=c.token,hash=c.hash})
    if not admission then return self:_error(admissionError) end
    local producer=GameState.producer(); local campaign=authority.campaign; local hostedSlot=runtime.selectedSlot
    local motion=c.movement and Movement.host({campaign=campaign,clock=c.clock,move=c.movement.move,
        domain=c.movement.domain,position=c.movement.position,store=c.movement.store,presentation=c.movement.presentation,
        hostActor=c.movement.hostActor,allowed=function(generation)
            return authority.bindings.companion==generation and not authority.pendingSave and c.movement.allowed()
        end})
    local function synchronize()
        if runtime.saveData~=campaign or runtime.selectedSlot~=hostedSlot then return nil,'campaign_changed' end
        local service,errorMessage=c.commands.authority()
        if service~=authority then return nil,errorMessage or 'authority_changed' end
        if authority.pendingSave then return nil,'save_not_ready' end
        return true
    end
    local function snapshot()
        local ready,errorMessage=synchronize()
        if not ready then self.error=errorMessage; return nil,errorMessage end
        local message,projectionError=producer:capture(campaign,true)
        if not message then self.error=projectionError end
        return message,projectionError
    end
    self:_detectInterfaces()
    local selected={}
    for _,entry in ipairs(self.interfaces) do if matches(entry,self.connectionMode) then selected[#selected+1]=entry end end
    self.localAddress=Address.chooseLanAddress(selected)
    -- Picture Shop's mode selects the displayed adapter and search results.
    -- Keep ENet reachable on every local adapter advertised by UDP discovery.
    local bind=c.bind
    local network,networkError=(c.network or Session).host({port=port,bind=bind,build=build.build,schema=build.schema,
        clock=c.clock,hash=c.hash,sessionId=authority.sessionId,campaignId=campaign.coop.network.campaignId,
        generationBase=authority.lastGeneration or 0,
        preflight=function() return runtime.saveData==campaign and runtime.selectedSlot==hostedSlot and admission:preflight() end,
        checkpointPending=function() return authority.pendingSave~=nil end,
        authenticate=function(value) return admission:authenticate(value) end,
        issue=function(request) return admission:issue(request) end,
        movement=motion and function(generation,message) return motion:receive(generation,message) end,
        sceneReady=motion and function(generation,epoch,motionId) return motion:ready(generation,epoch,motionId) end,
        command=c.commands.remote and function(generation,request)
            if runtime.saveData~=campaign or runtime.selectedSlot~=hostedSlot then return nil,'campaign_changed' end
            return c.commands.remote(generation,request)
        end,
        commandSequence=c.commands.remote and function()
            return (authority.requests.companion and authority.requests.companion.high or 0)+1
        end,
        snapshot=snapshot,revision=function() return producer.revision,campaign.coop.sceneEpoch end,
        update=function()
            local now=c.clock()
            local changed=not producer.current or producer.current.view.coop.revision~=campaign.coop.revision
                or producer.current.sceneEpoch~=campaign.coop.sceneEpoch
            if not changed and now<self.nextAudit then return nil end
            local ambush=campaign.trainAmbush
            local stand=campaign.lastStand
            self.nextAudit=now+((ambush and ambush.active or stand and stand.state=='shootout') and .05 or 1)
            local ready,errorMessage=synchronize(); if not ready then return nil,errorMessage end
            local message,projectionError=producer:capture(campaign)
            if projectionError then self.error=projectionError end
            return message,projectionError
        end,
        ready=function(generation)
            if c.prepareCompanion and c.prepareCompanion(campaign.players.companion)~=true then return false end
            authority:admit('companion',generation); self.generation=generation; admission:forgetPending(generation)
            if motion then motion:admit(generation) end
            return true
        end,
        disconnected=function(generation)
            local treating=false
            for _,lease in pairs(authority.activityState.resources) do
                if lease.actorId=='companion' and lease.payload and lease.payload.kind=='lastStandAid' then treating=true end
            end
            authority:disconnect('companion',generation); admission:forgetPending(generation)
            if treating and not authority.pendingSave then authority:checkpointNow() end
            if motion then motion:disconnect(generation) end
        end})
    if not network then return self:_error(networkError) end
    self.network=network; self.authority=authority; self.campaign=campaign; self.hostedSlot=hostedSlot
    self.admission=admission; self.producer=producer
    self.motion=motion; self.nextMotion=0; self.nextRoaming=0; self.roamingSerial=0
    self.nextLastStandEffects=0; self.lastStandEffectsSerial=0
    self.nextLastStandStage=0; self.lastStandStageSerial=0
    self.phase='hosting'; self.error=nil; self.menuOpen=false; self.lastApproval=nil; self.hostingIntent=nil
    c.session:setNetworkMode('host'); self.reconnect:cancel(true); self.reconnectArmed=nil
    local advertised,advertiseError=protected(self.discovery.startHost,self.discovery,
        {gamePort=port,name='Journey - Slot '..tostring(runtime.selectedSlot)})
    self.discoveryMessage=advertised and select(2,self.discovery:status()) or advertiseError
        or 'Automatic discovery is unavailable; friends can enter the host address manually.'
    return true
end
function LocalPlay:join(reconnecting)
    if self.network then return self:_error('session_already_open') end
    if self.hostingIntent then return self:_error('hosting_entry_pending') end
    local c=self.context; local runtime=c.runtime
    if runtime.state~='slots' or not c.session:canWriteCampaign() then return self:_error('join_from_title') end
    if not P.text(self.name,32) or not self:character() then return self:_error('invalid_guest_profile') end
    local address,addressError=Address.parse(self.address)
    if not address then return self:_error(addressError) end
    local build=self:_build(); if not build then return nil,self.error end
    if c.beforeJoin and c.beforeJoin()~=true then return self:_error('save_not_ready') end
    if reconnecting~=true then self.reconnect:cancel(false); self.reconnect:remember(address.endpoint,self.name); self.reconnectArmed=nil end
    local replica=GameState.replica()
    local roamingPresentation=RoamingPresentation.new({data=function() return replica.data end,clock=c.clock})
    local lastStandEffects=LastStandEffects.new({data=function() return replica.data end,clock=c.clock})
    local lastStandStage=LastStandStage.new({data=function() return replica.data end,clock=c.clock})
    local network,reason=protected((c.network or Session).join,address.endpoint,{build=build.build,schema=build.schema,
        clock=c.clock,hash=c.hash,name=self.name,character=self:character(),
        credentialFor=function(id)
            local data,errorMessage=Credentials.load(c.filesystem)
            return data and Credentials.find(data,id),errorMessage
        end,
        store=function(value) return Credentials.save(value,c.filesystem) end,
        validate=function(message) return replica:validate(message) end,
        motion=function(message)
            if not replica.data or message.sceneEpoch~=replica.data.coop.sceneEpoch
                or message.domain~=require('game.coop_last_stand_lifecycle').key(replica.data)
                or self.motionFrame and message.serial<=self.motionFrame.serial then return false end
            self.motionFrame=message; return true
        end,
        roaming=function(message) return roamingPresentation:receive(message) end,
        lastStandEffects=function(message) return lastStandEffects:receive(message) end,
        lastStandStage=function(message) return lastStandStage:receive(message) end,
        apply=function(message)
            local ok,errorMessage=replica:apply(message)
            if ok then
                roamingPresentation:observe()
                lastStandEffects:observe()
                lastStandStage:observe()
                c.session.replicaData=replica.data
                if self.motionFrame and (self.motionFrame.sceneEpoch~=replica.data.coop.sceneEpoch
                    or self.motionFrame.domain~=require('game.coop_last_stand_lifecycle').key(replica.data)) then self.motionFrame=nil end
            else self.error=errorMessage end
            return ok==true
        end})
    if not network then return self:_error(reason) end
    self.discovery:stop()
    self.roamingPresentation=roamingPresentation
    self.lastStandEffects=lastStandEffects
    self.lastStandStage=lastStandStage
    self.origin={data=runtime.saveData,player=runtime.player,slot=runtime.selectedSlot,scene=runtime.scene}
    self.network=network; self.replica=replica; self.phase='joining'; self.error=nil; self.menuOpen=true
    c.session:setNetworkMode('client')
    if c.neutralize then c.neutralize() end
    return true
end
function LocalPlay:pending() return self.phase=='hosting' and self.network and self.network:pending() or nil end
function LocalPlay:approve()
    local pending=self:pending(); if not pending then return self:_error('stale_approval') end
    local ok,reason=self.network:approve(pending.generation)
    if not ok then return self:_error(reason) end
    self.error=nil; self.menuOpen=false; return true
end
function LocalPlay:decline()
    local pending=self:pending(); if not pending then return false end
    self.network:decline(pending.generation); self.menuOpen=false; return true
end
function LocalPlay:stop(reason,keepReconnect)
    local c=self.context
    self.discovery:stop()
    if not keepReconnect then self.reconnect:cancel(false); self.reconnectArmed=nil end
    if self.authority then
        local treating=false
        for resource,lease in pairs(self.authority.activityState.resources) do
            if lease.payload and lease.payload.kind=='range' then
                self.authority.activityState.resources[resource]=nil
            end
            if lease.payload and lease.payload.kind=='lastStandAid' then
                self.authority.activityState.resources[resource]=nil; treating=true
            end
        end
        if treating and not self.authority.pendingSave then self.authority:checkpointNow() end
    end
    if self.clientView then protected(self.clientView.release,self.clientView); self.clientView=nil end
    if self.network then protected(self.network.close,self.network,reason); self.network=nil end
    if self.authority and self.generation then self.authority:disconnect('companion',self.generation) end
    if self.origin then
        -- Restore local ownership before any ordinary title/quit save path can
        -- run. A remote view is never assigned to the host's selected slot.
        c.runtime.saveData=self.origin.data; c.runtime.player=self.origin.player
        c.runtime.selectedSlot=self.origin.slot; c.runtime.scene=self.origin.scene; c.runtime.state='slots'
    end
    c.session.replicaData=nil; c.session:setNetworkMode('offline')
    if c.onStop then protected(c.onStop,reason) end
    self.origin=nil; self.replica=nil; self.authority=nil; self.campaign=nil; self.hostedSlot=nil; self.admission=nil; self.producer=nil
    self.generation=nil
    self.motion=nil; self.motionFrame=nil; self.roamingPresentation=nil
    self.lastStandEffects=nil
    self.lastStandStage=nil
    self.phase='idle'; self.lastApproval=nil; self.previewOnly=true; self.hostingIntent=nil
    return true
end
local transient={host_disconnected=true,host_timeout=true,transport_failed=true,send_failed=true,join_timeout=true}
function LocalPlay:_connectionFailed(reason)
    local reconnecting=self.context.autoReconnect~=false and self:isClient() and transient[reason]
        and (self.reconnectArmed or self.reconnect:isActive())
    self:stop(reason,reconnecting); self:_error(reason); self.menuOpen=true
    if reconnecting then
        if self.reconnect:isActive() then self.reconnect:failed(reason) else self.reconnect:begin(reason) end
    end
    self:refreshDiscovery(); self.autoJoinBlocked=true
end
function LocalPlay:beginFrame(dt)
    self:_updateConvenience(dt)
    local network=self.network; if not network then return end
    if self.phase=='hosting' then
        local runtime=self.context.runtime
        if runtime.saveData~=self.campaign or runtime.selectedSlot~=self.hostedSlot
            or runtime.state=='slots' or runtime.state=='characters' or runtime.state=='intro' then
            self:stop('host_left_journey'); return
        end
    end
    local service=self.phase=='hosting' and network.service or network.update
    local ok=pcall(service,network)
    if not ok then self:stop('session_error'); self:_error('session_error'); self.menuOpen=true; return end
    if network.closed then
        local reason=self.error or network.reason or 'connection_closed'
        self:_connectionFailed(reason); return
    end
    if self.motion then
        local updated,reason=protected(self.motion.update,self.motion)
        if not updated then self:stop('motion_failed'); self:_error(reason or 'motion_failed'); self.menuOpen=true; return end
    end
    if self:isClient() then
        if network.status=='ready' then self.reconnectArmed=true; self.reconnect:succeeded() end
        self.phase=self.replica and self.replica.data and 'connected' or 'joining'
        if self.phase=='connected' and self.context.createGuestView then
            local view,reason=self.clientView
            if not view then view,reason=protected(self.context.createGuestView,self); self.clientView=view end
            local updated
            if view then updated,reason=protected(view.update,view,dt or 0) end
            if not updated then
                self:stop('guest_view_failed'); self:_error(reason or 'guest_view_failed'); self.menuOpen=true; return
            end
            self.previewOnly=not view.ready
        end
    end
    local pending=self:pending()
    if pending and pending.generation~=self.lastApproval then
        self.lastApproval=pending.generation; self:open()
    end
end
function LocalPlay:finishFrame()
    local network=self.network
    if not network or self.phase~='hosting' then return end
    local runtime=self.context.runtime
    if runtime.saveData~=self.campaign or runtime.selectedSlot~=self.hostedSlot
        or runtime.state=='slots' or runtime.state=='characters' or runtime.state=='intro' then
        self:stop('host_left_journey'); return
    end
    if network.publish then
        local ok=pcall(network.publish,network)
        if not ok then self:stop('session_error'); self:_error('session_error'); self.menuOpen=true; return end
        if network.closed then
            local reason=self.error or network.reason or 'connection_closed'
            self:stop(reason); self:_error(reason); self.menuOpen=true; return
        end
    end
    local now=self.context.clock()
    if self.context.lastStandStage and network.link and network.link.admitted and not self.authority.pendingSave
        and now>=self.nextLastStandStage then
        self.nextLastStandStage=now+LastStandStageWire.INTERVAL
        if self.lastStandStageSerial>=2147483647 then
            self:stop('last_stand_stage_serial_exhausted'); self:_error('last_stand_stage_serial_exhausted'); self.menuOpen=true; return
        end
        self.lastStandStageSerial=self.lastStandStageSerial+1
        local frame,reason=LastStandStage.frame(self.campaign,self.context.lastStandStage(),self.authority.sessionId,self.lastStandStageSerial)
        if frame==nil then self:stop(reason); self:_error(reason); self.menuOpen=true; return end
        if frame and not network:sendLastStandStage(frame) then
            self:stop('last_stand_stage_send_failed'); self:_error('last_stand_stage_send_failed'); self.menuOpen=true; return
        end
    end
    if self.context.lastStandEffects and network.link and network.link.admitted and not self.authority.pendingSave
        and now>=self.nextLastStandEffects then
        self.nextLastStandEffects=now+LastStandEffectsWire.INTERVAL
        if self.lastStandEffectsSerial>=2147483647 then
            self:stop('last_stand_effects_serial_exhausted'); self:_error('last_stand_effects_serial_exhausted'); self.menuOpen=true; return
        end
        self.lastStandEffectsSerial=self.lastStandEffectsSerial+1
        local source=self.context.lastStandEffects()
        local frames,reason=LastStandEffects.frames(self.campaign,source,self.authority.sessionId,self.lastStandEffectsSerial)
        if not frames then self:stop(reason); self:_error(reason); self.menuOpen=true; return end
        for _,frame in ipairs(frames) do
            if not network:sendLastStandEffects(frame) then
                self:stop('last_stand_effects_send_failed'); self:_error('last_stand_effects_send_failed'); self.menuOpen=true; return
            end
        end
    end
    if self.motion and now>=self.nextMotion then
        self.nextMotion=now+MovementWire.SNAPSHOT_INTERVAL
        local frame,errorMessage=self.motion:snapshot(self.authority.sessionId)
        if errorMessage then self:stop(errorMessage); self:_error(errorMessage); self.menuOpen=true; return end
        if frame and not network:sendMotion(frame) then
            self:stop('motion_send_failed'); self:_error('motion_send_failed'); self.menuOpen=true; return
        end
    end
    if self.context.roaming and network.link and network.link.admitted and not self.authority.pendingSave
        and now>=self.nextRoaming then
        self.nextRoaming=now+RoamingWire.INTERVAL
        if self.roamingSerial>=2147483647 then self:stop('roaming_serial_exhausted'); self:_error('roaming_serial_exhausted'); self.menuOpen=true; return end
        self.roamingSerial=self.roamingSerial+1
        local system,paused=self.context.roaming()
        local frames,reason=RoamingPresentation.frames(self.campaign,system,self.authority.sessionId,self.roamingSerial,paused)
        if not frames then self:stop(reason); self:_error(reason); self.menuOpen=true; return end
        for _,frame in ipairs(frames) do
            if not network:sendRoaming(frame) then self:stop('roaming_send_failed'); self:_error('roaming_send_failed'); self.menuOpen=true; return end
        end
    end
end
-- Standalone fixtures and callers can retain the complete lifecycle update.
function LocalPlay:update(dt)
    self:beginFrame(dt)
    return self:finishFrame()
end
function LocalPlay:isClient() return self.context.session.networkMode=='client' end
function LocalPlay:captures() return self.hostingIntent=='failed' or self.menuOpen or self:isClient() and not (self.clientView and self.clientView.ready) end
return LocalPlay
