-- Independent guest presentation and controls. This module has no campaign
-- writer or world-update callback; all movement is an intent sent to the host.
local Schema=require('game.save_schema')
local Players=require('game.coop_players')
local Presence=require('game.coop_presence')
local Ownership=require('game.replica_ownership')
local Wire=require('game.net.movement')
local Prediction=require('game.coop_prediction')
local Viewport=require('game.viewport')
local Camera=require('game.camera')
local TrainView=require('game.train_view')
local Train=require('game.train')
local SceneFit=require('game.scene_fit')
local Mobile=require('game.mobile_controls')
local Util=require('game.util')
local GuestInventory=require('game.coop_guest_inventory')
local GuestTrade=require('game.coop_guest_trade')
local GuestTrain=require('game.coop_guest_train')
local GuestObjects=require('game.coop_guest_objects')
local GuestPeople=require('game.coop_guest_people')
local GuestActivities=require('game.coop_guest_activities')
local GuestBattles=require('game.coop_guest_battles')
local GuestRoaming=require('game.coop_guest_roaming')
local GuestExpedition=require('game.coop_guest_expedition')
local GuestAmbush=require('game.coop_guest_ambush')
local Life=require('game.coop_last_stand_lifecycle')
local GuestLastStand=require('game.coop_guest_last_stand')
local GuestRange=require('game.coop_guest_range')
local AssetRetention=require('game.coop_guest_asset_retention')
local GuestSettings=require('game.coop_guest_settings')
local Conversations=require('game.npc_conversations')
local Home=require('game.home_stop')
local SceneNPCs=require('game.scene_npcs')
local NPCPresentation=require('game.npc_presentation')
local SavedEvents=require('game.coop_events')
local Events=require('game.events')
local EventUI=require('game.event_ui')
local Style=require('game.ui_layout')
local Finale=require('game.coop_finale')
local FinaleUI=require('game.finale_ui')
local Typography=require('game.typography')
local Focus=require('game.ui_focus')
local View={}; View.__index=View
local function noop() end
local function actor(record)
    return {character=record.character,x=record.playerX,y=record.playerY,facing=record.playerFacing or 1,
        activeCar=record.activeCar,moving=false,velocityX=0,velocityY=0,idleClock=0}
end
function View.new(c,controller)
    local self=setmetatable({context=c,controller=controller,focused=controller.focused~=false,ready=false,
        sequence=0,inputElapsed=Wire.INPUT_INTERVAL,lastSerial=0,paused=true,elapsed=0},View)
    self.runtime={state='game',scene='train',animationClock=0,landscapeOffset=0,sceneryOffset=0,actionTimer=0}
    self.prediction=Prediction.new({clock=c.clock or function() return self.elapsed end,
        data=function() return self.runtime.saveData end,move=assert(c.move,'guest collision adapter required')})
    self.ui={propImages=c.ui.propImages,atlasItems=c.ui.atlasItems,objectTintShader=c.ui.objectTintShader,
        assetStreamer=c.ui.assetStreamer,playSfx=noop,itemOrderRevision=0}
    self.ui.coopCompanion=function()
        if self.runtime.saveData and not Presence.same(Players.campaignOf(self.runtime.saveData),'host','companion') then return end
        local pose=self.poses and self.poses:presentation('host') or {}
        local cue=self.field and self.field:presentation('host') or {}
        if (cue.actionTimer or 0)>0 then for key,value in pairs(cue) do pose[key]=value end end
        return self.remote,self.runtime.saveData and self.runtime.saveData.players.host,pose
    end
    self.ui.drawItem=function(name,rect)
        return require('game.inventory_ui').drawItem({ui=self.ui,Catalog=c.catalog,colors=c.colors,title=Util.titleFromFile},name,rect)
    end
    self.camera=setmetatable({zoom=1,panX=0,panY=0,panning=false,scope='guest',scopes={}},{__index=Camera})
    self.scene=(c.sceneFactory or require('game.coop_scene_view')).new({runtime=self.runtime,ui=self.ui,content=c.content,catalog=c.catalog,
        roamingPresentation=controller.roamingPresentation})
    self.renderer=c.createWorldRenderer(self.runtime,self.ui,self.scene)
    self.assetRetention=AssetRetention.new(c.content)
    self.mobile=(c.mobileFactory or Mobile).new({width=960,height=720,enabled=c.mobileEnabled(),
        toGame=function(x,y) return Viewport.toGame(x,y,960,720) end,
        pressKey=function(key) self:keypressed(key) end,releaseKey=noop,
        pressPointer=function(x,y) if self.runtime.battle and not self.runtime.inventoryOpen then
            return self.battles:pointer(Viewport.toGame(x,y,960,720)) end end,
        movePointer=noop,releasePointer=noop,
        gameplayActive=function() return self:inputAllowed() and (self:interactionAvailable() or self.field and self.field:available()) end,
        primaryAction=function()
            if self:interactionAvailable() then return 'e',self:actionLabel() end
            if self.field and self.field:available() then return 'space','ATTACK' end
            return 'e',self:actionLabel()
        end,
        secondaryAction=function()
            if self:interactionAvailable() and self.field and self.field:available() then return 'space','ATTACK' end
        end,
        movementActive=function() return self:inputAllowed() end,
        cameraGesturesActive=function() return self.ready and not self:travelOpen() and not (self.range and self.range:available()) and not (self.lastStand and self.lastStand:available()) and not (self.ambush and self.ambush:available()) and not controller.menuOpen and not self.runtime.inventoryOpen and not self.runtime.tradeOpen and not self.runtime.trainUpgradeOpen and not self:objectsOpen() and not self.runtime.peopleOpen and not self.runtime.guestActivityOpen end,
        backpackVisible=function() return not self.ui.actionMenuVisible and self.ready and not self:travelOpen() and not (self.range and self.range:available()) and not (self.lastStand and self.lastStand:available()) and not self.runtime.battle and not controller.menuOpen and not self.runtime.inventoryOpen and not self.runtime.tradeOpen and not self.runtime.trainUpgradeOpen and not self:objectsOpen() and not self.runtime.peopleOpen and not self.runtime.guestActivityOpen end,
        backpackAction=function() self.inventory:toggle() end,
        menuVisible=function() return not self.ui.actionMenuVisible and self.ready and not self.runtime.inventoryOpen end,menuLabel=function() return 'LOCAL PLAY' end,
        menuAction=function() controller:open() end,
        getZoom=function() return self.camera.zoom end,
        setZoom=function(zoom,x,y)
            local gx,gy=Viewport.toGame(x,y,960,720); local fx,fy=self:focusPoint()
            return self.camera:setZoomAt(zoom,gx,gy,fx,fy)
        end,
        beginCameraPan=function(x,y) self.camera:beginPan(x,y) end,
        moveCameraPan=function(x,y) local _,_,scale=Viewport.transform(960,720); self.camera:movePan(x,y,scale) end,
        endCameraPan=function() self.camera:endPan() end,
        accessibilityData=function() return self.runtime.saveData or {} end})
    self.inventory=GuestInventory.new(self,c)
    self.inspection=require('game.coop_guest_inspection').new(self)
    self.trade=GuestTrade.new(self,c)
    self.train=GuestTrain.new(self,c)
    self.objects=GuestObjects.new(self,c)
    self.people=GuestPeople.new(self,c)
    self.activities=GuestActivities.new(self,c)
    self.battles=GuestBattles.new(self,c)
    self.field=GuestRoaming.new(self,c)
    self.expedition=GuestExpedition.new(self)
    self.visits=require('game.coop_guest_visits').new(self,c)
    self.ambush=GuestAmbush.new(self,c)
    self.lastStand=GuestLastStand.new(self,c)
    self.range=GuestRange.new(self,c)
    self.poses=require('game.coop_guest_pose').new(self)
    self.journey=require('game.coop_guest_journey').new(self,c)
    self.travel=require('game.coop_guest_travel').new(self,c)
    if c.preferences and c.bindings and (c.filesystem or love and love.filesystem) then
        self.settings=GuestSettings.new(self,c)
    end
    self.ui.decorationPreview=function(item) return self.objects:preview(item) end
    return self
end
function View:travelOpen()return self.travel and self.travel.opened==true or false end
function View:activityBusy() return self.range and self.range:busy() or self.expedition and self.expedition.pending or self.field and self.field.pending or self.runtime.guestActivityOpen or self.activities and (self.activities.pending or self.activities.lease or self.activities.wantRelease or self.activities.sewing:busy() or self.activities.firstAid:busy()) end
function View:objectsOpen() return self.ui.radioOpen or self.runtime.editMode end
function View:actionsAllowed()
    local traveler=self.controller.traveler
    if traveler and (traveler.leaving or traveler.savedReturn or traveler.error) then return false end
    return self.ready and self.focused and not self.paused and not self.carRequest and not self.carTransition
        and not (self.runtime.saveData and self.runtime.saveData.roamingEncounter)
        and not self.controller.menuOpen and not self.prediction:stale()
end
function View:inputAllowed()
    if self.inspection and self.inspection.opened then return false end
    if self.ui.mobileMenuOpen or self.ui.playerToolsOpen then return false end
    if self.controllerFocus or self.poses and self.poses.opened or self.journey and self.journey.opened or self.travel and self.travel.opened then return false end
    if self.lastStand and self.lastStand:available() then return self:actionsAllowed() and self.lastStand:inputAllowed() end
    return self:actionsAllowed() and not (self.ambush and self.ambush:available()) and not self.runtime.inventoryOpen and not self.runtime.tradeOpen and not self.runtime.trainUpgradeOpen
        and not self:activityBusy() and not self:objectsOpen() and not self.runtime.peopleOpen and not (self.objects and self.objects.pending) and not (self.people and self.people.pending)
        and not (self.inventory and self.inventory.pending) and not (self.trade and self.trade.pending) and not (self.train and self.train.pending)
        and not (self.expedition and self.expedition.pending)
        and not (self.visits and self.visits.pending)
end
function View:interactionAvailable() if self.lastStand:available() then return false end; return self.range:nearest()~=nil or self.expedition:nearest()~=nil or self.visits:nearest()~=nil or self.inventory:nearest()~=nil or self.inspection:nearest()~=nil or self.trade:nearest()~=nil or self.people:nearest()~=nil or self.train:nearFire() end
function View:actionLabel() local spot=self.expedition:nearest(); local visit=self.visits:nearest(); return spot and spot.label or self.range:nearest() and 'TARGET RANGE' or visit and visit.label or self.inventory:nearest() and self.inventory:actionLabel() or self.inspection:nearest() and 'INSPECT' or self.trade:nearest() and 'TRADE' or self.people:nearest() and (Home.isHome(self.runtime.saveData) and 'TALK' or 'TALK / GIFT') or self.train:nearFire() and 'ADD FUEL' or 'PICK UP' end
function View:interact()
    if not self:inputAllowed() then return false end
    if self.expedition:nearest() then return self.expedition:interact() end
    if self.range:nearest() then return self.range:open() end
    if self.visits:nearest() then return self.visits:interact() end
    if self.inventory:nearest() then return self.inventory:pickup() end
    if self.inspection:nearest() then return self.inspection:open() end
    local merchant=self.trade:nearest()
    if merchant then return self.trade:open(merchant) end
    local person=self.people:nearest(); if person then return self.people:open(person) end
    if self.train:nearFire() then return self.train:fuel() end
    return self.inventory:pickup()
end
function View:_send(x,y,sprint)
    if not self.ready or not self.controller.network then return false end
    if not self.motionId then return true end
    self.sequence=self.sequence+1
    local sent,reason=self.controller.network:sendMovement(self.sequence,self.epoch,x,y,sprint,self.motionId)
    if not sent then return nil,reason or 'movement_send_failed' end
    local recorded,errorMessage=self.prediction:sent(self.sequence,{x=x/1000,y=y/1000,sprint=sprint})
    if not recorded then return nil,errorMessage end
    self.lastX,self.lastY=x,y; return true
end
function View:neutralize()
    self.controllerPressed={}
    if self.settings then self.settings.pressedKeys={}; self.settings.pressedButtons={} end
    if self.range then self.range:suspend() end
    if self.ambush then self.ambush:suspend() end
    if self.lastStand then self.lastStand:suspend() end
    if self.mobile then self.mobile:cancelAll() end
    self.camera:endPan()
    self.prediction:neutralize()
    if self.ready then return self:_send(0,0,false) end
    return true
end
function View:update(dt)
    dt=tonumber(dt) or 0
    if dt~=dt or dt<0 or dt==math.huge then return nil,'invalid_frame_time' end
    self.elapsed=self.elapsed+dt
    if self.settings then self.settings:update() end
    local replica=self.controller.replica
    if not replica or not replica.data then return true end
    local runtime=self.runtime
    if self.revision~=replica.revision then
        local copy=Ownership.mark(Schema.copy(replica.data))
        local data=Players.forActor(copy,'companion')
        if self.context.preferences then self.context.preferences:bind(copy,function() return 'client' end) end
        runtime.saveData=data; runtime.scene=data.scene
        runtime.battle=data.tacticalBattle and data.tacticalBattle.battle
        runtime.state=runtime.battle and 'battle' or 'game'
        local sceneRevision=Presence.revision(copy,'companion')
        local changed=self.epoch~=data.coop.sceneEpoch or self.modalDomain~=Life.key(data) or self.sceneRevision~=sceneRevision
        self.sceneRevision=sceneRevision
        self.modalDomain=Life.key(data)
        if changed then
            self:neutralize(); self.ready=false; self.paused=true; self.lastSerial=0; self.wasAllowed=false
            self.epoch=data.coop.sceneEpoch
            self.motionId=nil; self.carTransition=nil; self.carRequest=nil
            runtime.player=actor(data.players.companion); self.remote=actor(data.players.host)
            local own,other=Life.pose(data,'companion'),Life.pose(data,'host')
            if own then runtime.player.x,runtime.player.y,runtime.player.facing=own.x,own.y,own.facing end
            if other then self.remote.x,self.remote.y,self.remote.facing=other.x,other.y,other.facing end
            self.prediction:reset(self.epoch,runtime.player,self.remote)
            self.camera:resetAll()
        end
        runtime.player.character=data.character; self.remote.character=data.players.host.character
        local key=Util.sceneKey(runtime.scene,data.location)..(runtime.scene=='house' and (':'..tostring(data.activeHouseDoor or 1)) or '')
        if runtime.scene=='stop' and Home.isHome(data) then key=Home.isOffice(data) and 'homeStop:conductor' or nil end
        local selected=runtime.npcActor and runtime.npcActor.file
        runtime.npcActor=key and data.npcStates and data.npcStates[key] or nil
        runtime.npcActors=runtime.npcActor and {runtime.npcActor} or {}
        if SceneNPCs.hasResidents(data) and not Home.isHome(data) then
            if SceneNPCs.locked(runtime) and selected then data.currentNPC=selected end
            NPCPresentation.update(runtime,0)
        end
        self.ui.itemOrderCache={}; self.ui.itemOrderRevision=replica.revision
        self.assetRetention:update(self)
        if self.scene.prepareAssetRetention then self.scene.prepareAssetRetention({range=self.range and self.range:available()}) end
        if self.ui.assetStreamer then
            self.ui.assetStreamer:update(runtime.battle and 'battle' or Finale.available(data) and 'ending' or 'game',Life.active(data) and 'lastStand' or runtime.scene,data,runtime.battle,runtime.npcActor,nil,data.players.host.character)
        end
        if self.context.prepareCharacters then self.context.prepareCharacters(data.players) end
        if not Life.active(data) then local ok,reason=self.scene.prepare(); if not ok then return nil,reason end end
        if changed then self.ready=true end
        self.revision=replica.revision
    end
    local frame=self.controller.motionFrame
    if frame and frame.sceneEpoch==self.epoch and frame.domain==self.modalDomain
        and (frame.companion.sceneRevision or 0)==self.sceneRevision and frame.serial>self.lastSerial then
        if not Wire.snapshot(frame) then return nil,'invalid_motion_state' end
        if self.motionId and frame.motionId<self.motionId then return nil,'invalid_motion_generation' end
        if frame.companion.car>#runtime.saveData.trainCars then return true end -- Wait for the matching consist projection.
        local oldCar=runtime.player.activeCar or runtime.saveData.activeCar
        local oldX,oldY=runtime.player.x,runtime.player.y
        -- Personal car selection is a host output too; no local party change.
        runtime.saveData.players.companion.activeCar=frame.companion.car
        runtime.saveData.players.host.activeCar=frame.host.car
        if self.motionId~=frame.motionId then
            self:neutralize(); self.motionId=frame.motionId; self.paused=true
            local own,remote=Wire.unpackActor(frame.companion),Wire.unpackActor(frame.host)
            own.character=runtime.saveData.character; remote.character=runtime.saveData.players.host.character
            self.prediction:reset(self.epoch,own,remote,self.motionId)
            runtime.player=own; self.remote=remote
            if not Life.active(runtime.saveData) then local ok,reason=self.scene.prepare(); if not ok then return nil,reason end end
            local sent,errorMessage=self.controller.network:sceneReady(self.epoch,self.motionId)
            if not sent then return nil,errorMessage or 'scene_ready_failed' end
            if oldCar~=frame.companion.car and runtime.scene=='train' then
                self.carTransition={from=oldCar,to=frame.companion.car,fromX=oldX,fromY=oldY,t=0,duration=.78}
                self.camera:resetAll()
            end
        end
        if self.carRequest and self.carRequest.car==frame.companion.car and self.carRequest.motionId~=frame.motionId then self.carRequest=nil end
        local applied,reason=self.prediction:receive(frame,self.focused and not self.controller.menuOpen)
        if applied==nil then return nil,reason end
        self.lastSerial=frame.serial; self.paused=frame.paused or not frame.ready
    end
    -- A campaign projection may lag the independent motion channel. Retain the
    -- newest presented personal car instead of blinking back to an older car.
    if frame and frame.sceneEpoch==self.epoch and frame.domain==self.modalDomain
        and (frame.companion.sceneRevision or 0)==self.sceneRevision and frame.serial==self.lastSerial then
        runtime.saveData.players.companion.activeCar=frame.companion.car
        runtime.saveData.players.host.activeCar=frame.host.car
    end
    local result=self.controller.network.lastCommandResult
    if self.carRequest and result and result.requestId==self.carRequest.id and not result.ok
        and result.reason~='save_pending' and result.reason~='busy' then
        self.actionError=result.reason; self.carRequest=nil
    end
    if not Home.isHome(runtime.saveData) then NPCPresentation.update(runtime,dt) end
    self.inventory:update()
    self.inspection:update()
    self.expedition:update()
    self.visits:update()
    self.trade:update()
    self.train:update()
    self.objects:update()
    self.people:update()
    self.activities:update(dt)
    self.battles:update(dt)
    self.ambush:update(math.min(.1,dt))
    self.lastStand:update(math.min(.1,dt))
    self.range:update(math.min(.1,dt))
    self.assetRetention:update(self)
    if self.scene.prepareAssetRetention then self.scene.prepareAssetRetention({range=self.range and self.range:available()}) end
    if self.scene.updatePresentation and not Life.active(runtime.saveData) then self.scene.updatePresentation(math.min(.25,dt)) end
    self.field:update()
    self.journey:update()
    self.travel:update()
    dt=math.max(0,math.min(.25,tonumber(dt) or 0))
    runtime.animationClock=runtime.animationClock+dt
    if self.carTransition then
        self.carTransition.t=self.carTransition.t+dt
        if self.carTransition.t>=self.carTransition.duration then self.carTransition=nil end
    end
    self.inputElapsed=self.inputElapsed+dt
    local controllerIdentity=self:controllerIdentity()
    if self.lastControllerIdentity and self.lastControllerIdentity~=controllerIdentity then
        self.controllerFocus=nil; self.controllerPressed={}
        -- Actor motion already has its scene-ready/neutralization ordering.
        -- Only discard private held controls here; do not insert extra input
        -- messages between the ready acknowledgment and the current intent.
        if self.range and self.range:available() then self.range:suspend() end
        if self.ambush:available() then self.ambush:suspend() end
        if self.lastStand and self.lastStand:available() then self.lastStand:suspend() end
    end
    self.lastControllerIdentity=controllerIdentity
    if self.controllerFocus and (self.controller.menuOpen or not self.focused
        or self.controllerFocusIdentity~=self:controllerIdentity() or self:controllerScope()~='hud') then
        self.controllerFocus=nil; self:neutralize()
    end
    local allowed=self:inputAllowed()
    if not allowed and self.wasAllowed then self:neutralize() end
    self.wasAllowed=allowed
    local x,y,sprint=0,0,false
    if allowed then
        local down=self.context.keyDown or love.keyboard.isDown
        x=(down('d','right') and 1 or 0)-(down('a','left') and 1 or 0)
        y=(down('s','down') and 1 or 0)-(down('w','up') and 1 or 0)
        local px,py=self.context.bindings:movement(); local tx,ty=self.mobile:movement()
        x,y=x+px+tx,y+py+ty
        if self.lastStand and self.lastStand:available() then x,y=self.lastStand:movement(x,y) end
        local length=math.max(1,math.sqrt(x*x+y*y)); x,y=x/length,y/length
        sprint=down('lshift','rshift') or self.context.bindings:actionDown('sprint') or self.mobile:isSprinting()
    end
    local ix,iy=math.floor(x*1000+.5),math.floor(y*1000+.5)
    if self.inputElapsed+1e-9>=Wire.INPUT_INTERVAL then
        -- Keep fractional time at 30/60/120 FPS, but never catch up in a burst.
        self.inputElapsed=math.max(0,self.inputElapsed-Wire.INPUT_INTERVAL)%Wire.INPUT_INTERVAL
        local sent,reason=self:_send(ix,iy,sprint==true); if not sent then return sent,reason end
    end
    local updated,reason=self.prediction:update({x=ix/1000,y=iy/1000,sprint=sprint==true},allowed)
    if not updated then return nil,reason end
    runtime.player=self.prediction.display; self.remote=self.prediction.remote
    self.poses:update()
    local pose=self.field:presentation('companion')
    local manual=self.poses:presentation('companion')
    runtime.playerPose=manual.playerPose or 'idle'
    if (pose.actionTimer or 0)<=0 then pose=manual end
    runtime.actionTimer=pose.actionTimer or 0; runtime.actionDuration=pose.actionDuration; runtime.actionKind=pose.actionKind; runtime.actionHeldItem=pose.actionHeldItem
    if runtime.actionTimer>0 and pose.facing~=nil then runtime.player.facing=pose.facing end
    self.waiting=self.paused or self.prediction:stale()
    return true
end
function View:focusPoint()
    local runtime=self.runtime; local x,y=runtime.player.x,runtime.player.y
    if runtime.battle then return 480,250 end
    local width,height=love.graphics.getDimensions()
    if runtime.scene=='train' then
        local fit=TrainView.layout(self.context.car,960,720,width,height,{mobile=self.mobile.enabled,carCount=#runtime.saveData.trainCars})
        x,y=TrainView.toView(fit,x,y); return x,y,fit
    elseif runtime.scene=='house' then
        local fit=SceneFit.house(960,720,width,height); x,y=SceneFit.toView(fit,x,y); return x,y,fit
    elseif runtime.scene=='expedition' then
        local ox,oy=require('game.expedition_areas').cameraOffset(runtime.saveData,runtime.player,960,720)
        return x-ox,y-oy
    end
    return x,y
end
function View:draw()
    if not self.ready then return end
    local g=love.graphics; local runtime=self.runtime; local renderer=self.renderer
    g.push('all'); g.origin(); g.clear(.055,.045,.035,1)
    local ox,oy,sx,sy=Viewport.transform(960,720); g.translate(ox,oy); g.scale(sx,sy)
    if self.ambush:available() then self.ambush:draw(); g.pop(); return end
    if self.lastStand and self.lastStand:available() then
        self.lastStand:draw(); g.pop(); if not self.lastStand.aid.opened and not self.lastStand.shooter:available() then self.mobile:draw(ox,oy,sx,sy) end; return
    end
    if self.range and self.range:available() then self.range:draw(); g.pop(); return end
    if runtime.battle then
        self.font=self.font or g.newFont(18); g.setFont(self.font)
        if runtime.inventoryOpen then self.inventory:draw() else self.battles:draw() end
        g.pop(); self.mobile:draw(ox,oy,sx,sy); return
    end
    g.push(); local fx,fy,fit=self:focusPoint(); self.camera:apply(fx,fy)
    if runtime.scene=='train' then
        renderer.drawLandscape(); g.push(); TrainView.apply(fit); renderer.drawTracks(fit)
        local car=runtime.saveData.activeCar
        local transition=self.carTransition
        if transition then
            local p=math.min(1,transition.t/transition.duration); local eased=p*p*(3-2*p)
            local slide=fit.transitionDistance*(transition.to>transition.from and -1 or 1)
            renderer.drawTrainView(transition.from,slide*eased,transition.from,transition.fromX,transition.fromY)
            renderer.drawTrainView(transition.to,slide*(eased-1),nil)
        else renderer.drawTrainView(car,0,car) end
        g.pop()
    elseif runtime.scene=='house' then SceneFit.apply(fit); renderer.drawHouse()
    elseif runtime.scene=='stop' then renderer.drawStop()
    elseif runtime.scene=='expedition' then renderer.drawExpedition()
    elseif runtime.scene=='caravan' then renderer.drawCaravan() end
    g.pop()
    self.font=self.font or g.newFont(18); g.setFont(self.font)
    if self.inspection.opened then self.inspection:draw(); g.pop(); return end
    if runtime.guestActivityOpen then self.activities:draw(); g.pop(); return end
    if runtime.peopleOpen then self.people:draw(); g.pop(); return end
    if self:objectsOpen() then self.objects:draw(); g.pop(); return end
    if runtime.inventoryOpen then self.inventory:draw(); g.pop(); return end
    if runtime.tradeOpen then self.trade:draw(); g.pop(); return end
    if runtime.trainUpgradeOpen then self.train:draw(); g.pop(); return end
    if self.poses and self.poses.opened then self.poses:draw(); g.pop(); return end
    if self.journey and self.journey.opened then self.journey:draw(); g.pop(); return end
    if self.travel and self.travel.opened then self.travel:draw(); g.pop(); return end
    self.finaleReadAlong=Finale.readAlong(runtime.saveData)
    if self.finaleReadAlong then
        FinaleUI.draw(runtime.saveData,self.finaleReadAlong,{colors=self.context.colors,
            characterImages=self.context.content.characterImages,npcImages=self.context.content.npcImages,
            animationClock=runtime.animationClock,textBox=function(value,x,y,w,h,scale,align)
                Typography.drawText(g,value,x,y,w,h,{scale=scale or 1,minScale=.65,align=align or 'left',valign='center'})
            end},false)
        g.pop(); self.mobile:draw(ox,oy,sx,sy); return
    end
    self.eventReadAlong=SavedEvents.readAlong(runtime.saveData)
    if self.eventReadAlong then
        local read=self.eventReadAlong
        Style.scope('event',{x=60,y=42,w=840,h=640},function()
            EventUI.drawReadAlong(Events.findById(read.id),read,self.context.content.scenery.eventArt,
                function(...) self.inventory:frame(...) end,noop,self.context.colors,false)
        end)
        g.pop(); self.mobile:draw(ox,oy,sx,sy); return
    end
    g.setColor(.045,.035,.025,.9); g.rectangle('fill',16,14,928,52,8,8)
    g.setColor(.96,.88,.69,1)
    g.printf('COMPANION  /  Stop '..runtime.saveData.location..'  /  '..runtime.scene,30,24,470,'left')
    g.printf('Health '..runtime.saveData.health..' / '..runtime.saveData.maxHealth,self.mobile.enabled and 500 or 580,24,225,'right')
    g.setColor(.045,.035,.025,.9); g.rectangle('fill',220,660,520,45,8,8)
    g.setColor(.96,.88,.69,1)
    local bindings=self.context.bindings
    local controllerHint=bindings.buttons and bindings.buttons.guest_actions and love and love.joystick
        and bindings:hasGamepad() and require('game.accessibility').enabled(runtime.saveData,'controlHints')
        and (bindings:display('button','guest_actions')..': choose companion actions.')
    g.printf((self.carRequest or self.carTransition) and 'Changing cars...' or self.actionError and 'Car change unavailable. Try again when ready.'
        or self.expedition.pending and self.expedition.notice or self.inventory.pending and self.inventory.notice or self.trade.pending and self.runtime.tradeMessage or self.train.pending and self.train.notice or self.waiting and 'Waiting for the host to continue.'
        or self.visits.notice or self.expedition.notice and self.expedition.noticeUntil>self.elapsed and self.expedition.notice
        or self.activities.notice or self.people.notice or self.objects.notice or self.train.notice or self.trade.notice or self.inventory.notice
        or controllerHint or (self.mobile.enabled and 'Move with the left stick. Tap nearby actions to interact.'
            or 'WASD: move   E: interact   I: backpack'),230,667,500,'center')
    self.ui.trainCarTabs=nil
    if runtime.scene=='train' and #runtime.saveData.trainCars>1 then
        self.ui.trainCarTabs=Train.consistLayout(960,#runtime.saveData.trainCars,{mobile=self.mobile.enabled})
        for index,tab in ipairs(self.ui.trainCarTabs) do
            if self.mobile.enabled then tab.y=214 end
            g.setColor(.17,.135,.09,.94); g.rectangle('fill',tab.x,tab.y,tab.w,tab.h,7,7)
            g.setColor(index==runtime.saveData.activeCar and 1 or .7,.8,.5,1)
            g.rectangle('line',tab.x,tab.y,tab.w,tab.h,7,7)
            g.printf(tostring(index),tab.x,tab.y+(tab.h-18)/2,tab.w,'center')
        end
        g.setColor(.96,.88,.69,1)
        g.printf('CAR '..runtime.saveData.activeCar..' / '..#runtime.saveData.trainCars..(self.mobile.enabled and '' or '   [ / ]'),10,self.mobile.enabled and 284 or 248,400,'center')
    end
    self.ui.guestBackpack=nil
    if not self.mobile.enabled and not self.ui.actionMenuVisible then
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',764,78,180,46,8,8)
        g.setColor(.96,.88,.69,1); g.printf('LOCAL PLAY [F8]',774,92,160,'center')
        self.ui.guestBackpack={x=764,y=134,w=180,h=46}
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',764,134,180,46,8,8)
        g.setColor(.96,.88,.69,1); g.printf('BACKPACK [I]',774,148,160,'center')
        self.ui.guestPickup=self:interactionAvailable() and {x=550,y=78,w=200,h=46} or nil
        if self.ui.guestPickup then
            g.setColor(.17,.135,.09,.94); g.rectangle('fill',550,78,200,46,8,8)
            g.setColor(.96,.88,.69,1); g.printf(self:actionLabel()..' [E]',560,92,180,'center')
        end
    end
    -- Preserve access to nearby loot/storage even when a merchant occupies the
    -- same spot. The companion can explicitly choose either interaction.
    self.ui.guestTrade=self.trade:nearest() and self.inventory:nearest()
        and {x=self.mobile.enabled and 370 or 550,y=self.mobile.enabled and 78 or 134,w=200,h=46} or nil
    if self.ui.guestTrade then
        local r=self.ui.guestTrade
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf(self.mobile.enabled and 'TRADE' or 'TRADE [T / X]',r.x+10,r.y+14,r.w-20,'center')
    end
    self.ui.guestWorkshop=not self.ui.actionMenuVisible and runtime.scene=='train' and {x=self.mobile.enabled and 794 or 764,y=self.mobile.enabled and 145 or 190,w=self.mobile.enabled and 144 or 180,h=self.mobile.enabled and 56 or 46} or nil
    local workshop=self.ui.guestWorkshop
    if workshop then
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',workshop.x,workshop.y,workshop.w,workshop.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf('WORKSHOP',workshop.x+8,workshop.y+14,workshop.w-16,'center')
    end
    self.ui.guestFuel=self.train:nearFire() and {x=550,y=self.mobile.enabled and 145 or 134,w=200,h=46} or nil
    if self.ui.guestFuel then
        local f=self.ui.guestFuel
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',f.x,f.y,f.w,f.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf('ADD FUEL',f.x+8,f.y+14,f.w-16,'center')
    end
    self.ui.guestRadio=self.objects:nearestRadio() and {x=550,y=202,w=200,h=46} or nil
    if self.ui.guestRadio then
        local r=self.ui.guestRadio; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf('RADIO',r.x+8,r.y+14,r.w-16,'center')
    end
    self.ui.guestEditor=not self.ui.actionMenuVisible and runtime.scene=='train' and {x=self.mobile.enabled and 794 or 764,y=self.mobile.enabled and 268 or 248,w=self.mobile.enabled and 144 or 180,h=self.mobile.enabled and 56 or 46} or nil
    if self.ui.guestEditor then
        local r=self.ui.guestEditor; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf(self.mobile.enabled and 'DECORATE' or 'DECORATE [O]',r.x+6,r.y+14,r.w-12,'center')
    end
    self.ui.guestPose=not self.ui.actionMenuVisible and self.poses and {x=self.mobile.enabled and 794 or 764,y=self.mobile.enabled and 330 or 310,
        w=self.mobile.enabled and 144 or 180,h=self.mobile.enabled and 56 or 46} or nil
    if self.ui.guestPose then
        local r=self.ui.guestPose; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf('POSES',r.x+8,r.y+18,r.w-16,'center')
    end
    self.ui.guestPeople=self.people:nearest() and {x=20,y=78,w=240,h=56} or nil
    self.ui.guestMap=nil;self.ui.guestJournal=nil
    for index,entry in ipairs(self.ui.actionMenuVisible and {} or {{'guestMap','MAP'},{'guestJournal','JOURNAL'}}) do
        local rect={x=self.mobile.enabled and 794 or 764,y=(self.mobile.enabled and 392 or 364)+(index-1)*62,
            w=self.mobile.enabled and 144 or 180,h=self.mobile.enabled and 56 or 46}
        self.ui[entry[1]]=rect
        g.setColor(.17,.135,.09,.94); g.rectangle('fill',rect.x,rect.y,rect.w,rect.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf(entry[2],rect.x+8,rect.y+18,rect.w-16,'center')
    end
    self.ui.guestTravel=not self.ui.actionMenuVisible and runtime.scene=='train' and runtime.saveData.location<50 and not runtime.saveData.coop.journey
        and {x=self.mobile.enabled and 794 or 764,y=self.mobile.enabled and 516 or 488,w=self.mobile.enabled and 144 or 180,h=self.mobile.enabled and 56 or 46} or nil
    if self.ui.guestTravel then
        local r=self.ui.guestTravel;g.setColor(.17,.135,.09,.94);g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1);g.printf('NEXT LEG',r.x+8,r.y+18,r.w-16,'center')
    end
    if self.ui.guestPeople then
        local r=self.ui.guestPeople; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        local label=Home.isHome(self.runtime.saveData) and (self.mobile.enabled and 'TALK' or 'TALK [E]') or (self.mobile.enabled and 'TALK / GIFT' or 'TALK / GIFT [G]')
        g.setColor(.96,.88,.69,1); g.printf(label,r.x+6,r.y+18,r.w-12,'center')
    end
    self.ui.guestMaintenance=nil; self.ui.guestRepair=nil; self.ui.guestSewing=nil
    self.ui.guestFirstAid=self.activities.firstAid:nearest() and {x=20,y=146,w=240,h=56} or nil
    if self.ui.guestFirstAid then
        local r=self.ui.guestFirstAid; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf(self.mobile.enabled and 'FIRST AID' or 'FIRST AID [H]',r.x+6,r.y+18,r.w-12,'center')
    end
    if self.activities:eligible() then
        for i,entry in ipairs({{'guestMaintenance','SERVICE','MAINTENANCE'},{'guestRepair','REPAIR','WEAPON BENCH'},{'guestSewing','SEWING','SEWING BENCH'}}) do
            local r={x=20+(i-1)*178,y=146,w=168,h=56}; self.ui[entry[1]]=r
            g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
            g.setColor(.96,.88,.69,1); g.printf(self.mobile.enabled and entry[3] or entry[2],r.x+6,r.y+18,r.w-12,'center')
        end
    end
    self.ui.guestRange=self.range:nearest() and {x=20,y=214,w=240,h=56} or nil
    if self.ui.guestRange then
        local r=self.ui.guestRange; g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(.96,.88,.69,1); g.printf(self.mobile.enabled and 'TARGET RANGE' or 'TARGET RANGE [E]',r.x+6,r.y+18,r.w-12,'center')
    end
    local nearby=self.people:nearest()
    local reference=nearby and (nearby.kind=='passenger' and nearby.target or nearby.npc)
    self.ui.npcIdentityCard=not Home.isHome(runtime.saveData) and require('game.npc_identity_ui').draw({
        data=runtime.saveData,reference=reference,images=self.context.content.npcImages,characterImages=self.context.content.characterImages,key=self.mobile.enabled and 'TAP' or 'E'}) or nil
    self.field:draw()
    local read=Conversations.readAlong(runtime.saveData)
    if read then
        local height=self.mobile.enabled and 226 or 292
        g.setColor(.045,.035,.025,.94); g.rectangle('fill',16,222,520,height,8,8)
        g.setColor(.96,.88,.69,1); g.printf(require('game.npc_identity').title(runtime.saveData,read.npc),30,234,492,'left')
        local body=read.answer and (read.answer..'\n\n'..read.text) or read.text
        local _,lines=self.font:getWrap(body,492)
        local scale=math.min(1,(height-90)/math.max(1,#lines*self.font:getHeight()*self.font:getLineHeight()))
        g.printf(body,30,266,492/scale,'left',0,scale,scale)
        g.printf(read.waiting and 'The host is choosing a response.' or 'The host will continue when ready.',30,222+height-34,492,'left')
    end
    if self.controllerFocus then
        g.setColor(.045,.035,.025,.94); g.rectangle('fill',220,612,520,40,7,7)
        g.setColor(.96,.88,.69,1); g.printf('Choose an action. Confirm to use; cancel to return.',230,621,500,'center')
        Focus.draw(Focus.current(self.ui,self:controllerTargets(),'guest-controller-actions'))
    end
    g.pop(); self.mobile:draw(ox,oy,sx,sy)
end
function View:objectPoint(x,y)
    local fx,fy,fit=self:focusPoint(); x,y=self.camera:toWorld(x,y,fx,fy)
    return TrainView.toWorld(fit,x,y)
end
function View:requestCar(index)
    if not self:inputAllowed() or self.runtime.scene~='train' or index==self.runtime.saveData.activeCar
        or index<1 or index>#self.runtime.saveData.trainCars then return false end
    local network=self.controller.network
    local source=self.controller.replica.data
    local id,reason=network:submitCommand('player.car',{car=index},self.epoch,{['player:companion']=source.coop.revisions['player:companion'] or 0})
    if not id then self.actionError=reason; return false end
    self:neutralize(); self.actionError=nil; self.carRequest={id=id,car=index,motionId=self.motionId}
    return true
end
function View:carPointer(x,y)
    for index,tab in ipairs(self.ui.trainCarTabs or {}) do
        if Util.pointIn(x,y,tab) then self:requestCar(index); return true end
    end
    return false
end
function View:keypressed(key,scancode,isrepeat)
    if isrepeat then return true end
    if key=='f8' then self.controller:open(); return true end
    if self.inspection.opened then return self.inspection:keypressed(key) end
    if self.travel and self.travel.opened then return self.travel:keypressed(key)end
    if self.journey and self.journey.opened then return self.journey:keypressed(key) end
    if self.poses and self.poses.opened then return self.poses:keypressed(key) end
    if self.controllerFocus then return self:controllerActionFocus(key) end
    if self.lastStand and self.lastStand:available() then return self.lastStand:keypressed(key) end
    if self.ambush:available() then return self.ambush:keypressed(key) end
    if self.range and self.range:available() then return self.range:keypressed(key) end
    if self.runtime.battle and not self.runtime.inventoryOpen then return self.battles:keypressed(key) end
    if self.runtime.guestActivityOpen then return self.activities:keypressed(key) end
    if self.runtime.peopleOpen then return self.people:keypressed(key) end
    if self:objectsOpen() then return self.objects:keypressed(key) end
    if self.runtime.trainUpgradeOpen then return self.train:keypressed(key) end
    if self.runtime.tradeOpen then return self.trade:keypressed(key) end
    if self.runtime.inventoryOpen then return self.inventory:keypressed(key) end
    if key=='i' then self.inventory:toggle(); return true end
    if key=='e' then self:interact(); return true end
    if key=='space' and self.field:available() then self.field:attack(); return true end
    if key=='t' then self.trade:open(); return true end
    if key=='u' then self.train:open(); return true end
    if key=='f' then if self.field:available() then self.field:attack() else self.train:fuel() end; return true end
    if key=='p' then self.objects:openRadio(); return true end
    if key=='o' then self.objects:openEditor(); return true end
    if key=='g' then self.people:open(); return true end
    if key=='m' then self.journey:open('map'); return true end
    if key=='j' then self.journey:open('journal'); return true end
    if key=='v' then self.travel:open();return true end
    if key=='r' then self.activities:open('weaponRepair'); return true end
    if key=='c' then self.activities:open('sewing'); return true end
    if key=='h' then self.activities:open('firstAid'); return true end
    if key=='escape' or key=='acback' or key=='f8' then self.controller:open() end
    if key=='[' or key==']' then self:requestCar(self.runtime.saveData.activeCar+(key==']' and 1 or -1)) end
    return true
end
function View:controllerIdentity()
    local data=self.runtime.saveData or {}; local range=data.rangeSessions and data.rangeSessions.companion
    local ambush=data.trainAmbush; local life=data.lastStand
    return table.concat({tostring(self.controller.network),tostring(self.epoch),tostring(self.motionId),tostring(self.modalDomain),
        tostring(self.runtime.scene),tostring(data.tacticalBattle and data.tacticalBattle.encounterId),
        tostring(range and range.roundRevision),tostring(range and range.phase),
        tostring(ambush and ambush.encounterId),tostring(ambush and ambush.phase),
        tostring(life and life.mode),tostring(life and life.combat and life.combat.phaseRevision)},':')
end
function View:controllerScope()
    if self.inspection.opened then return 'menu',self.inspection end
    if self.travel and self.travel.opened then return 'menu',self.travel end
    if self.lastStand and self.lastStand:available() then
        local panel=self.lastStand
        if panel.aid.opened then return 'last_stand_treatment',panel.aid end
        if panel.shooter:available() then
            return (not panel.shooter:checkedPosition() or panel.shooter.choosing) and 'last_stand_position' or 'last_stand_shootout',panel.shooter
        end
        return 'last_stand_world',panel
    end
    if self.ambush:available() then return 'last_stand_shootout',self.ambush end
    if self.range and self.range:available() then return 'shooting_range',self.range end
    if self.poses and self.poses.opened then return 'menu',self.poses end
    if self.journey and self.journey.opened then return 'menu',self.journey end
    if self.runtime.inventoryOpen then return 'menu',self.inventory end
    if self.runtime.guestActivityOpen then return 'menu',self.activities end
    if self.runtime.peopleOpen then return 'menu',self.people end
    if self:objectsOpen() then return 'menu',self.objects end
    if self.runtime.trainUpgradeOpen then return 'menu',self.train end
    if self.runtime.tradeOpen then return 'menu',self.trade end
    if self.runtime.battle then return 'battle',self.battles end
    if self.controllerFocus then return 'hud',self end
    return 'game',self
end
function View:controllerTargets()
    local targets={}; local function add(id,rect,action)
        if rect then targets[#targets+1]={id=id,rect=rect,action=action,enabled=rect.enabled~=false} end
    end
    local function mobileRect(control)
        if not control then return nil end
        local rect=control.radius and {x=control.x-control.radius,y=control.y-control.radius,w=control.radius*2,h=control.radius*2} or control
        return self.mobile.uiBounds and Style.transformRectFor('mobileControls',self.mobile:uiBounds(),rect) or rect
    end
    add('backpack',self.ui.guestBackpack or mobileRect(self.mobile.backpack),function() self.inventory:toggle() end)
    add('interact',self.ui.guestPickup or self.mobile.primary and self:interactionAvailable() and mobileRect(self.mobile.primary),function() self:interact() end)
    add('workshop',self.runtime.scene=='train' and self.ui.guestWorkshop,function() self.train:open() end)
    add('fuel',self.ui.guestFuel,function() self.train:fuel() end)
    add('radio',self.ui.guestRadio,function() self.objects:openRadio() end)
    add('decorate',self.ui.guestEditor,function() self.objects:openEditor() end)
    add('people',self.ui.guestPeople,function() self.people:open() end)
    add('trade',self.ui.guestTrade,function() self.trade:open() end)
    add('maintenance',self.ui.guestMaintenance,function() self.activities:open('maintenance') end)
    add('repair',self.ui.guestRepair,function() self.activities:open('weaponRepair') end)
    add('sewing',self.ui.guestSewing,function() self.activities:open('sewing') end)
    add('firstAid',self.ui.guestFirstAid,function() self.activities:open('firstAid') end)
    add('range',self.ui.guestRange,function() self.range:open() end)
    add('poses',self.ui.guestPose,function() self.poses:open() end)
    add('map',self.ui.guestMap,function() self.journey:open('map') end)
    add('journal',self.ui.guestJournal,function() self.journey:open('journal') end)
    add('travel',self.ui.guestTravel,function()self.travel:open()end)
    for index,rect in ipairs(self.ui.trainCarTabs or {}) do local car=index
        add('car'..index,rect,function() self:requestCar(car) end)
    end
    return targets
end
function View:controllerActionFocus(key)
    if key=='guest-actions' then
        if self.controllerFocus then self.controllerFocus=nil; self:neutralize()
        elseif self:actionsAllowed() then self:neutralize(); self.controllerFocus=true; self.controllerFocusIdentity=self:controllerIdentity() end
    elseif key=='escape' then self.controllerFocus=nil; self:neutralize()
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        Focus.move(self.ui,self:controllerTargets(),'guest-controller-actions',key,
            love and love.keyboard and love.keyboard.isDown('lshift','rshift') or false)
    elseif key=='return' or key=='space' then
        local target=Focus.current(self.ui,self:controllerTargets(),'guest-controller-actions')
        self.controllerFocus=nil; self:neutralize()
        if target and target.enabled~=false and self:actionsAllowed() then target.action() end
    end
    return true
end
function View:controllerActionPointer(x,y)
    if not self.controllerFocus then return false end
    if self.controllerFocusIdentity~=self:controllerIdentity() or not self:actionsAllowed() then return true end
    for _,target in ipairs(self:controllerTargets()) do
        if Util.pointIn(x,y,target.rect) then
            self.ui.keyboardFocusScreen='guest-controller-actions'; self.ui.keyboardFocusId=target.id
            return self:controllerActionFocus('return')
        end
    end
    return true
end
function View:controllerWorld(key,id)
    if id=='guest_service' then self.activities:open('maintenance'); return true end
    if id=='guest_fuel' then self.train:fuel(); return true end
    if id=='attack' then if self.field:available() then self.field:attack() end; return true end
    if key=='guest-actions' then return self:controllerActionFocus(key) end
    if key=='pose' then if self.poses then self.poses:open() end; return true end
    -- Source map/journal bindings never alias the guest's maintenance shortcut.
    if id=='map' or id=='journey' then self.journey:open(id=='map' and 'map' or 'journal'); return true end
    return self:keypressed(key)
end
function View:gamepadpressed(_,button)
    if not self.ready or not self.focused or self.controller.menuOpen then return true end
    self.controllerPressed=self.controllerPressed or {}
    if self.controllerPressed[button] then return true end
    local scope,target=self:controllerScope(); local bindings=self.context.bindings; local key,id
    if scope=='game' then
        key,id=bindings:translateButton(button,'guest_world')
        if not key then key,id=bindings:translateButton(button,'game') end
    elseif scope=='hud' then
        key,id=bindings:translateButton(button,'guest_world')
        if key~='guest-actions' then key,id=bindings:translateButton(button,'menu') end
    else
        key,id=bindings:translateButton(button,scope)
        if not key and scope=='battle' then
            local fallback,fallbackId=bindings:translateButton(button,'menu')
            if fallbackId=='menu_pause' then key,id=fallback,fallbackId end
        end
    end
    if not key then return true end
    self.controllerPressed[button]={key=key,target=target,identity=self:controllerIdentity()}
    if scope=='game' then return self:controllerWorld(key,id) end
    if scope=='hud' then return self:controllerActionFocus(key) end
    if scope=='last_stand_position' then
        if key=='left' then target.windowChoice='wide' elseif key=='right' then target.windowChoice='tall'
        elseif key=='return' then
            local saved=require('game.coop_last_stand_position_state').selected(self.runtime.saveData,'companion')
            target:action((target.windowChoice or saved)=='tall' and '2' or '1')
        else target:keypressed(key) end; return true
    end
    if scope=='last_stand_world' and key=='escape' and target:state().mode=='interior' then return target:position('release') end
    return target:keypressed(key) -- A canonical key, never a second button translation.
end
function View:mousepressed(x,y,button,istouch)
    if istouch then return true end
    local gx,gy=Viewport.toGame(x,y,960,720)
    if self.inspection.opened then if button==1 then self.inspection:pointer(gx,gy) end;return true end
    if self.travel and self.travel.opened then if button==1 then self.travel:pointer(gx,gy)end;return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestTravel)then self.travel:open();return true end
    if self.journey and self.journey.opened then if button==1 then self.journey:pointer(gx,gy) end; return true end
    if self.controllerFocus then if button==1 then self:controllerActionPointer(gx,gy) end; return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestMap) then self.journey:open('map'); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestJournal) then self.journey:open('journal'); return true end
    if self.poses and self.poses.opened then if button==1 then self.poses:pointer(gx,gy) end; return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestPose) then self.poses:open(); return true end
    if self.lastStand and self.lastStand:available() then self.lastStand:pointer(gx,gy,button); return true end
    if self.ambush:available() then return self.ambush:pointer(gx,gy,button) end
    if self.range and self.range:available() then return self.range:pointer(gx,gy,button) end
    if self.runtime.battle and not self.runtime.inventoryOpen then return self.battles:pointer(gx,gy,button~=1) end
    if self.runtime.guestActivityOpen then if button==1 then self.activities:press(gx,gy) end; return true end
    if self.runtime.peopleOpen then if button==1 then self.people:press(gx,gy) end; return true end
    if self:objectsOpen() then if button==1 then self.objects:press(gx,gy) end; return true end
    if self.runtime.trainUpgradeOpen then if button==1 then self.train:press(gx,gy) end; return true end
    if self.runtime.tradeOpen then if button==1 then self.trade:press(gx,gy) end; return true end
    if self.runtime.inventoryOpen then if button==1 then self.inventory:press(gx,gy) end; return true end
    if button==1 and self.field:pointer(gx,gy) then return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestRange) then self.range:open(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestMaintenance) then self.activities:open('maintenance'); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestRepair) then self.activities:open('weaponRepair'); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestSewing) then self.activities:open('sewing'); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestFirstAid) then self.activities:open('firstAid'); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestWorkshop) then self.train:open(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestPeople) then self.people:open(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestRadio) then self.objects:openRadio(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestEditor) then self.objects:openEditor(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestFuel) then self.train:fuel(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestTrade) then self.trade:open(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestBackpack) then self.inventory:toggle(); return true end
    if button==1 and Util.pointIn(gx,gy,self.ui.guestPickup) then self:interact(); return true end
    if button==1 and self:carPointer(gx,gy) then return true end
    if button==1 and gx>=764 and gx<=944 and gy>=78 and gy<=124 then self.controller:open()
    elseif button==1 and self.field:available() then
        local fx,fy=self:focusPoint(); local wx,wy=self.camera:toWorld(gx,gy,fx,fy)
        local ox,oy=0,0
        if self.runtime.scene=='expedition' then ox,oy=require('game.expedition_areas').cameraOffset(self.runtime.saveData,self.runtime.player,960,720) end
        self.field:attack(wx+ox,wy+oy)
    elseif button==2 or button==3 then self.camera:beginPan(x,y) end
    return true
end
function View:mousemoved(x,y)
    if self.inspection.opened then return true end
    if self.travel and self.travel.opened then return true end
    if self.journey and self.journey.opened or self.controllerFocus or self.poses and self.poses.opened then return true end
    if self.lastStand and self.lastStand:available() then
        if self.lastStand.shooter:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.lastStand.shooter:mousemoved(gx,gy) end
        if self.lastStand.aid.opened then local gx,gy=Viewport.toGame(x,y,960,720); self.lastStand.aid:move(gx,gy) end
        return true
    end
    if self.ambush:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.ambush:mousemoved(gx,gy) end
    if self.range and self.range:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.range:mousemoved(gx,gy) end
    if self.runtime.guestActivityOpen then local gx,gy=Viewport.toGame(x,y,960,720); return self.activities:move(gx,gy) end
    if self.runtime.peopleOpen then return true end
    if self:objectsOpen() then local gx,gy=Viewport.toGame(x,y,960,720); return self.objects:move(gx,gy) end
    if self.runtime.trainUpgradeOpen then return true end
    if self.runtime.tradeOpen then return true end
    if self.runtime.inventoryOpen then self.inventory.pointerX,self.inventory.pointerY=Viewport.toGame(x,y,960,720); return true end
    local _,_,scale=Viewport.transform(960,720); self.camera:movePan(x,y,scale); return true
end
function View:mousereleased(x,y,button)
    if self.lastStand and self.lastStand:available() then
        if self.lastStand.shooter:available() then return self.lastStand.shooter:mousereleased(button) end
        if button==1 and self.lastStand.aid.opened then local gx,gy=Viewport.toGame(x,y,960,720); self.lastStand.aid:releasePointer(gx,gy) end
        return true
    end
    if self.ambush:available() then return self.ambush:mousereleased(button) end
    if self.range and self.range:available() then return self.range:mousereleased(button) end
    if self.runtime.guestActivityOpen then if button==1 then local gx,gy=Viewport.toGame(x,y,960,720); return self.activities:releasePointer(gx,gy) end; return true end
    if self.runtime.peopleOpen then return true end
    if self:objectsOpen() then if button==1 then local gx,gy=Viewport.toGame(x,y,960,720); self.objects:releasePointer(gx,gy) end; return true end
    if self.runtime.trainUpgradeOpen then return true end
    if self.runtime.tradeOpen then return true end
    if self.runtime.inventoryOpen then
        if button==1 then local gx,gy=Viewport.toGame(x,y,960,720); self.inventory:release(gx,gy) end
        return true
    end
    self.camera:endPan(); return true
end
function View:wheelmoved(_,dy)
    if self.inspection.opened then return true end
    if self.travel and self.travel.opened then return true end
    if self.journey and self.journey.opened then return self.journey:wheelmoved(0,dy) end
    if self.controllerFocus or self.poses and self.poses.opened then return true end
    if self.range and self.range:available() then return true end
    if self.lastStand and self.lastStand:available() then return true end
    if self.ambush:available() then return true end
    if self.runtime.guestActivityOpen then return self.activities:wheel(dy) end
    if self.runtime.inventoryOpen or self.runtime.tradeOpen or self.runtime.trainUpgradeOpen or self:objectsOpen() or self.runtime.peopleOpen or self.runtime.guestActivityOpen then return true end
    local x,y=love.mouse.getPosition(); x,y=Viewport.toGame(x,y,960,720)
    local fx,fy=self:focusPoint(); self.camera:wheel(dy,x,y,fx,fy); return true
end
function View:touchpressed(id,x,y,...)
    local gx,gy=Viewport.toGame(x,y,960,720)
    if self.inspection.opened then self.inspection:pointer(gx,gy);return true end
    if self.travel and self.travel.opened then self.travel:pointer(gx,gy);return true end
    if Util.pointIn(gx,gy,self.ui.guestTravel)then self.travel:open();return true end
    if self.journey and self.journey.opened then self.journey:pointer(gx,gy); return true end
    if self.controllerFocus then self:controllerActionPointer(gx,gy); return true end
    if Util.pointIn(gx,gy,self.ui.guestMap) then self.journey:open('map'); return true end
    if Util.pointIn(gx,gy,self.ui.guestJournal) then self.journey:open('journal'); return true end
    if self.poses and self.poses.opened then self.poses:pointer(gx,gy); return true end
    if Util.pointIn(gx,gy,self.ui.guestPose) then self.poses:open(); return true end
    if self.lastStand and self.lastStand:available() then
        if self.lastStand.shooter:available() then return self.lastStand.shooter:touchpressed(id,gx,gy) end
        local aid=self.lastStand.aid
        if aid.opened then if not aid.touch then aid.touch=id; aid:press(gx,gy) end; return true end
        if not self.lastStand:pointer(gx,gy,1,true) then self.mobile:touchpressed(id,x,y,...) end; return true
    end
    if self.ambush:available() then return self.ambush:touchpressed(id,gx,gy) end
    if self.range and self.range:available() then return self.range:touchpressed(id,gx,gy) end
    if self.runtime.battle and not self.runtime.inventoryOpen then self.mobile:touchpressed(id,x,y,...); return true end
    if self.runtime.guestActivityOpen then
        if not self.activities.touch then self.activities.touch=id; self.activities:press(gx,gy) end; return true
    end
    if self.runtime.peopleOpen then self.people:press(gx,gy); return true end
    if self:objectsOpen() then
        if not self.objects.touch then self.objects.touch=id; self.objects:press(gx,gy) end
        return true
    end
    if self.runtime.trainUpgradeOpen then self.train:press(gx,gy); return true end
    if self.runtime.tradeOpen then self.trade:press(gx,gy); return true end
    if self.runtime.inventoryOpen then
        if not self.inventory.touch then self.inventory.touch=id; self.inventory:press(gx,gy) end
        return true
    end
    if self.field:pointer(gx,gy) then return true end
    if Util.pointIn(gx,gy,self.ui.guestRange) then self.range:open(); return true end
    if Util.pointIn(gx,gy,self.ui.guestMaintenance) then self.activities:open('maintenance'); return true end
    if Util.pointIn(gx,gy,self.ui.guestRepair) then self.activities:open('weaponRepair'); return true end
    if Util.pointIn(gx,gy,self.ui.guestSewing) then self.activities:open('sewing'); return true end
    if Util.pointIn(gx,gy,self.ui.guestFirstAid) then self.activities:open('firstAid'); return true end
    if Util.pointIn(gx,gy,self.ui.guestWorkshop) then self.train:open(); return true end
    if Util.pointIn(gx,gy,self.ui.guestPeople) then self.people:open(); return true end
    if Util.pointIn(gx,gy,self.ui.guestRadio) then self.objects:openRadio(); return true end
    if Util.pointIn(gx,gy,self.ui.guestEditor) then self.objects:openEditor(); return true end
    if Util.pointIn(gx,gy,self.ui.guestFuel) then self.train:fuel(); return true end
    if Util.pointIn(gx,gy,self.ui.guestTrade) then self.trade:open(); return true end
    if self:carPointer(gx,gy) then return true end
    self.mobile:touchpressed(id,x,y,...); return true
end
function View:touchmoved(id,x,y,...)
    if self.inspection.opened then return true end
    if self.travel and self.travel.opened then return true end
    if self.journey and self.journey.opened or self.controllerFocus or self.poses and self.poses.opened then return true end
    if self.range and self.range:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.range:touchmoved(id,gx,gy) end
    if self.lastStand and self.lastStand.shooter:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.lastStand.shooter:touchmoved(id,gx,gy) end
    if self.lastStand and self.lastStand:available() and self.lastStand.aid.opened then
        local aid=self.lastStand.aid; if aid.touch==id then local gx,gy=Viewport.toGame(x,y,960,720); aid:move(gx,gy) end
        return true
    end
    if self.ambush:available() then local gx,gy=Viewport.toGame(x,y,960,720); return self.ambush:touchmoved(id,gx,gy) end
    if self.runtime.guestActivityOpen then if self.activities.touch==id then local gx,gy=Viewport.toGame(x,y,960,720); self.activities:move(gx,gy) end; return true end
    if self.runtime.peopleOpen then return true end
    if self:objectsOpen() then if self.objects.touch==id then local gx,gy=Viewport.toGame(x,y,960,720); self.objects:move(gx,gy) end; return true end
    if self.runtime.trainUpgradeOpen then return true end
    if self.runtime.tradeOpen then return true end
    if self.runtime.inventoryOpen then
        if self.inventory.touch==id then self.inventory.pointerX,self.inventory.pointerY=Viewport.toGame(x,y,960,720) end
        return true
    end
    self.mobile:touchmoved(id,x,y,...); return true
end
function View:touchreleased(id,x,y,...)
    if self.range and self.range:available() then return self.range:touchreleased(id) end
    if self.lastStand and self.lastStand.shooter:available() then return self.lastStand.shooter:touchreleased(id) end
    if self.lastStand and self.lastStand:available() and self.lastStand.aid.opened then
        local aid=self.lastStand.aid; if aid.touch==id then aid.touch=nil; local gx,gy=Viewport.toGame(x,y,960,720); aid:releasePointer(gx,gy) end
        return true
    end
    if self.ambush:available() then return self.ambush:touchreleased(id) end
    if self.mobile.touches and self.mobile.touches[id] then self.mobile:touchreleased(id,x,y,...); return true end
    if self.activities.touch==id then
        self.activities.touch=nil
        if self.runtime.guestActivityOpen then local gx,gy=Viewport.toGame(x,y,960,720); self.activities:releasePointer(gx,gy) end
        return true
    end
    if self.runtime.guestActivityOpen then return true end
    if self.runtime.peopleOpen then return true end
    if self:objectsOpen() then
        if self.objects.touch==id then self.objects.touch=nil; local gx,gy=Viewport.toGame(x,y,960,720); self.objects:releasePointer(gx,gy) end
        return true
    end
    if self.runtime.trainUpgradeOpen then return true end
    if self.runtime.tradeOpen then return true end
    if self.runtime.inventoryOpen then
        if self.inventory.touch==id then self.inventory.touch=nil; local gx,gy=Viewport.toGame(x,y,960,720); self.inventory:release(gx,gy) end
        return true
    end
    self.mobile:touchreleased(id,x,y,...); return true
end
function View:keyreleased(key)
    if self.range and self.range:available() then return self.range:keyreleased(key) end
    if self.lastStand and self.lastStand.shooter:available() then return self.lastStand.shooter:keyreleased(key) end
    if self.ambush:available() then return self.ambush:keyreleased(key) end
    if self.runtime.guestActivityOpen then return self.activities:keyreleased(key) end; return true
end
function View:gamepadreleased(_,button)
    local pressed=self.controllerPressed and self.controllerPressed[button]
    if self.controllerPressed then self.controllerPressed[button]=nil end
    if pressed and pressed.identity==self:controllerIdentity() and pressed.target.keyreleased then
        pressed.target:keyreleased(pressed.key)
    end
    return true
end
function View:focus(focused)
    if self.travel then self.travel:focus(focused)end
    if self.journey then self.journey:focus(focused) end
    if self.settings then self.settings:focus(focused) end
    self.focused=focused; if not focused then self.controllerFocus=nil; self.inventory:cancelDrag(); self.objects:suspend(); self.people:close(); self.activities:suspend(); self:neutralize() end
    if self.context.audio then self.context.audio.focus(focused,self.runtime) end; return true
end
function View:release()
    self.inspection:close()
    if self.travel then self.travel:release()end
    if self.journey then self.journey:release() end
    if self.settings then self.settings:release() end
    self.range:release()
    self.lastStand:release()
    self.ambush:release()
    self.objects:suspend()
    self.people:close()
    self.activities:release()
    self:neutralize(); self.ready=false; self.scene.release()
    if self.renderer.release then self.renderer.release() end
    if self.font then self.font:release(); self.font=nil end
end
return View
