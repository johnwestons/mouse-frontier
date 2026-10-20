-- Same scenario runs headlessly with an injected transport, or with real ENet
-- in main.lua. All host administration goes through original panel controls.
local LocalPlay=require('game.coop_local_play')
local Panel=require('game.local_play_panel')
local Authority=require('game.coop_authority')
local Runtime=require('game.runtime_state')
local GameSession=require('game.game_session')
local Schema=require('game.save_schema')
local Fixtures=require('tools.tests.lua.coop_fixtures')
local Catalog=require('game.catalog')
local Scenario={};Scenario.__index=Scenario
Scenario.images={'01-first-approval.png','02-connected-host.png','03-disconnect-confirmation.png',
    '04-checkpoint-pending.png','05-kicked-client.png','06-traveler-selection.png',
    '07-traveler-confirmation.png','08-rejoined-client.png'}
local function stable(value)
    if type(value)=='string'then return string.format('%q',value)end
    if type(value)~='table'then return type(value)..':'..tostring(value)end
    local keys={};for key in pairs(value)do keys[#keys+1]=key end
    table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
    local out={'{'};for _,key in ipairs(keys)do out[#out+1]=stable(key)..'='..stable(value[key])..';'end
    out[#out+1]='}';return table.concat(out)
end
local function kit(actor)
    local result={}
    for _,key in ipairs({'inventory','inventoryCapacity','equipment','ammo','wearables','weaponDurability',
        'weaponProficiency','nextBattlePotions','stats','itemSlots'})do result[key]=actor[key]end
    return stable(result)
end
local function runtime(state,data,slot)
    local session=GameSession.new()
    local r=Runtime.new({session=session,transition=function(screen)session:setScreen(screen)end})
    r.saveData=data;r.player={x=200,y=250};r.scene='train';r.selectedSlot=slot;r.state=state
    return r,session
end
function Scenario:check(value,message)
    self.checks=self.checks+1;assert(value,message);return value
end
function Scenario:stage(name)
    self.phase=name;self.since=self.options.clock()
    if self.options.log then self.options.log('STAGE '..name)end
end
function Scenario:queue(panel,control,image,nextPhase,after)
    self.action={panel=panel,control=control,image=image,nextPhase=nextPhase,after=after}
end
function Scenario.new(options)
    local self=setmetatable({options=options,checks=0,writes=0,joins=0,failSave=false,captures={}},Scenario)
    local data=Fixtures.campaign(2,{scene='train',stopped=true})
    self.data=data
    self.hostRuntime,self.hostSession=runtime('game',data,98)
    self.guestRuntime,self.guestSession=runtime('slots',Fixtures.campaign(9,{scene='train'}),97)
    self.authority=Authority.new({campaign=data,sessionId='native-companion-management',clock=options.clock,
        checkpoint=function(value)
            self.writes=self.writes+1
            if self.failSave then return false end
            return options.checkpoint(value)
        end})
    local function context(r,s,fs)
        return {runtime=r,session=s,filesystem=fs,clock=options.clock,hash=options.hash,token=options.token,
            compatibility=function()return options.compatibility end,autoReconnect=true,bind='127.0.0.1',
            discoveryPort=options.discoveryPort,discoveryTargets={'127.0.0.1'},
            addressDetector=function()return {{address='127.0.0.1',prefixLength=8,broadcast='127.255.255.255',isUsb=false}}end,
            commands={authority=function()return self.authority end,checkpointStatus=function()return self.authority:checkpointStatus()end},
            characters=function()return {'cook-mouse.png','scout-frog.png'}end,catalog=Catalog,
            placeCompanion=function(c)c.players.companion.playerX=240;c.players.companion.playerY=250;return true end,
            network=options.network,beforeJoin=function()return true end,
            discovery=options.discovery and options.discovery(r==self.hostRuntime and 'host' or 'guest') or nil}
    end
    local hostContext=context(self.hostRuntime,self.hostSession,options.hostFilesystem)
    local guestContext=context(self.guestRuntime,self.guestSession,options.guestFilesystem)
    local network=options.network or require('game.net.session')
    guestContext.network={host=network.host,join=function(address,value)
        self.joins=self.joins+1;return network.join(address,value)
    end}
    self.host=LocalPlay.new(hostContext);self.guest=LocalPlay.new(guestContext)
    self.host.port=tostring(options.port);self.guest.address='127.0.0.1:'..tostring(options.port)
    local function panel(c,r)
        return Panel.new(c,{runtime=r,ui={},screenToGame=options.screenToGame or function(x,y)return x,y end})
    end
    self.hostPanel=panel(self.host,self.hostRuntime);self.guestPanel=panel(self.guest,self.guestRuntime)
    self:check(self.host:host(),'host failed: '..tostring(self.host.error))
    self.network=self.host.network;self.discovery=self.host.discovery
    self:check(self.guest:join(),'initial join failed: '..tostring(self.guest.error))
    self:stage('first-approval')
    return self
end
function Scenario:preserved()
    local actor=self.data.players.companion
    self:check(kit(actor)==self.savedKit,'companion owned kit, progression or item IDs changed')
    self:check(self.data.itemIdentity.nextId==self.itemCounter,'owned item counter changed')
    self:check(stable(self.data.players.host)==self.hostActor,'host actor changed')
    self:check(stable(self.data.resources)==self.resources,'shared resources changed')
    self:check(self.data.coop.sceneEpoch==self.epoch and self.data.location==2 and self.data.scene=='train','story advanced')
    local disk=assert(self.options.readCheckpoint())
    self:check(kit(disk.players.companion)==self.savedKit and disk.players.companion.character==actor.character,'disk companion mismatch')
    self:check(Schema.validate(disk),'disk schema invalid')
end
function Scenario:update(dt)
    if self.finished then return end
    self.host:update(dt);self.guest:update(dt)
    if self.action then return end
    self:check(self.options.clock()-self.since<12,'stage deadline: '..self.phase)
    local phase=self.phase
    if phase=='first-approval' and self.host:pending()then
        self:queue(self.hostPanel,'approve',Scenario.images[1],'first-ready')
    elseif phase=='first-ready' and self.guest.phase=='connected'then
        local actor=self.data.players.companion
        self:check(actor.character=='cook-mouse.png','initial traveler mismatch')
        self.savedKit=kit(actor);self.itemCounter=self.data.itemIdentity.nextId
        self.hostActor=stable(self.data.players.host);self.resources=stable(self.data.resources);self.epoch=self.data.coop.sceneEpoch
        self.health=actor.health;self.originalCharacter=actor.character
        self.firstCredential=assert(Schema.copy(self.guest.network.credential))
        self.firstGeneration=self.host.network.link.generation
        self:queue(self.hostPanel,'disconnectCompanion',Scenario.images[2],'kick-confirm')
    elseif phase=='kick-confirm'then
        self:check(self.host:managementStatus().phase=='confirm','missing explicit disconnect confirmation')
        self.failSave=true
        self:queue(self.hostPanel,'confirmDisconnect',Scenario.images[3],'kick-save-pending')
    elseif phase=='kick-save-pending'then
        self:check(self.authority.pendingSave and self.host.network.link and self.host.network.link.admitted,'unsaved kick closed the peer')
        self:check(self.authority.bindings.companion==self.firstGeneration and self.guest.phase=='connected','unsaved kick revoked the live binding')
        if self.options.clock()-self.since>.2 then
            self:queue(self.hostPanel,nil,Scenario.images[4],'kicked',function()
                self.failSave=false;self:check(self.authority:retryCheckpoint(),'checkpoint retry failed')
            end)
        end
    elseif phase=='kicked' and self.guest.phase=='idle' and not self.network:hasDeparting()then
        self:check(self.guest.error=='host_kicked','guest missed explicit host_kicked reason: '..tostring(self.guest.error))
        self:check(not self.guest.reconnect:isActive() and not self.guest.reconnectArmed and self.joins==1,'kick started automatic reconnect')
        self:check(self.host.phase=='hosting' and self.host.network==self.network and not self.network.closed,'kick stopped hosting')
        self:check(self.host.discovery==self.discovery and self.discovery:status()=='host','kick stopped discovery')
        self:check(not self.authority.bindings.companion and not self.host.admission:authenticate(self.firstCredential),'kick credentials still authorize')
        self:preserved()
        if self.options.clock()-self.since>1.2 then self:queue(self.guestPanel,'join',Scenario.images[5],'second-approval')end
    elseif phase=='second-approval' and self.host:pending()then
        self:check(self.host:pending().generation>self.firstGeneration,'rejoin reused old connection generation')
        self:queue(self.hostPanel,'approve',nil,'second-ready')
    elseif phase=='second-ready' and self.guest.phase=='connected'then
        self.secondCredential=assert(Schema.copy(self.guest.network.credential))
        self:check(self.secondCredential.token~=self.firstCredential.token,'kick did not rotate the reconnect secret')
        self:preserved();self:queue(self.guestPanel,'leave',nil,'left')
    elseif phase=='left' and not self.host.network.link and not self.network:hasDeparting()then
        self:check(not self.authority.bindings.companion and self.guest.phase=='idle','voluntary leave did not clean up')
        self:queue(self.hostPanel,'changeCompanion',nil,'replacement-select')
    elseif phase=='replacement-select'then
        self:queue(self.hostPanel,'nextReplacement',Scenario.images[6],'replacement-confirm')
    elseif phase=='replacement-confirm'then
        self:check(self.host:replacementCharacter()=='scout-frog.png','replacement selection failed')
        self:queue(self.hostPanel,'confirmReplacement',Scenario.images[7],'replaced')
    elseif phase=='replaced' and not self.host:managementStatus()then
        local actor=self.data.players.companion
        self:check(actor.character=='scout-frog.png' and actor.health==math.min(self.health,actor.maxHealth),'replacement healed or lost traveler')
        self:check(not self.host.admission:authenticate(self.secondCredential),'replacement retained old credential')
        self:preserved();self:queue(self.guestPanel,'join',nil,'third-approval')
    elseif phase=='third-approval' and self.host:pending()then
        self:queue(self.hostPanel,'approve',nil,'third-ready')
    elseif phase=='third-ready' and self.guest.phase=='connected'then
        local credential=self.guest.network.credential
        self:check(credential.companionId~=self.secondCredential.companionId and credential.token~=self.secondCredential.token,'replacement credentials not rebound')
        self:check(self.guest.replica.data.players.companion.character=='scout-frog.png','guest profile overrode the host-selected traveler')
        self:check(self.joins==3,'unexpected automatic connection attempt')
        self:preserved();self:queue(self.guestPanel,nil,Scenario.images[8],'complete',function()
            self.finished=true;self.guest:stop();self.host:stop()
        end)
    end
end
function Scenario:draw()
    local action=self.action
    local panel=action and action.panel or self.hostPanel
    panel:draw()
    if not action then return end
    if action.image then self.options.capture(action.image);self.captures[#self.captures+1]=action.image end
    if action.control then
        local rect=assert(panel.context.ui.localPlayControls[action.control],'missing original control '..action.control)
        self:check(rect.enabled~=false,'disabled original control '..action.control)
        local x,y=rect.x+rect.w/2,rect.y+rect.h/2
        if self.options.toScreen then x,y=self.options.toScreen(x,y)end
        panel:click(x,y)
    end
    if action.after then action.after()end
    self.action=nil;self:stage(action.nextPhase)
end
return Scenario
