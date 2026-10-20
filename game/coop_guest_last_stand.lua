local GuiArt=require('game.gui_art')
-- Independent farmhouse presentation. Campaign decisions remain on the host.
local Life=require('game.coop_last_stand_lifecycle')
local Scene=require('game.last_stand_scene')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local Geometry=require('game.last_stand_geometry')
local WorldView=require('game.world_view')
local Provider=require('game.coop_last_stand_provider')
local Aid=require('game.coop_guest_last_stand_aid')
local Shooter=require('game.coop_guest_last_stand_shooter')
local Positions=require('game.coop_last_stand_positions')
local Selection=require('game.coop_last_stand_position_state')
local Quest=require('game.last_stand_quest')
local Panel={}; Panel.__index=Panel
function Panel.new(view,c)
    local self=setmetatable({view=view,c=c},Panel); self.aid=Aid.new(view,c,self); self.shooter=Shooter.new(view,c,self); return self
end
function Panel:state() return Life.active(self.view.runtime.saveData) end
function Panel:available() return self:state()~=nil end
function Panel:inputAllowed() return Life.walking(self.view.runtime.saveData) and not self.paused and not self.pending and not self.aid:busy() end
function Panel:action()
    if not self.scene or not Life.walking(self.view.runtime.saveData) then return nil end
    self.scene.player=self.view.runtime.player
    return Scene.action(self.scene,Provider.needed(self.view.runtime.saveData,'companion',self.c.catalog))
end
function Panel:assist()
    local action=self:action()
    if action and action.id=='help-wounded' then return self.aid:open() end
    if action and (action.id=='window-wide' or action.id=='window-tall') then return self:position('select',action.id=='window-wide' and 'wide' or 'tall') end
    if not action or action.id~='borrow-rifle' then self.notice='The host controls scene progression.'; return false end
    if not self.view:inputAllowed() then return false end
    local data=self.view.runtime.saveData; local life=data.lastStand.lifecycle; local expected={}
    for _,scope in ipairs(Provider.scopes(data,'companion')) do expected[scope]=data.coop.revisions[scope] or 0 end
    local id,reason=self.view.controller.network:submitCommand('lastStand.supply',
        {mode='farmhouse',questId=life.entityId,revision=life.revision},self.view.epoch,expected)
    if not id then self.notice='Supplies are currently unavailable. Try again when ready.'; return false,reason end
    self.pending={id=id,key=Life.key(data)}; self.notice='Waiting for the host to save supplies...'; self.view:neutralize()
    return true
end
function Panel:position(action,window)
    if not self.view:inputAllowed() then return false end
    local data=self.view.runtime.saveData; local life=data.lastStand.lifecycle; local expected={}
    if life.mode~='interior' then return false end
    for _,scope in ipairs(Positions.scopes(data,'companion')) do expected[scope]=data.coop.revisions[scope] or 0 end
    local args={questId=life.entityId,revision=life.revision,action=action}; if action=='select' then args.window=window end
    local id,reason=self.view.controller.network:submitCommand('lastStand.position',args,self.view.epoch,expected)
    if not id then self.notice='The position is unavailable. Try again when ready.'; return false,reason end
    self.pending={id=id,key=Life.key(data),kind='position'}; self.notice='Waiting for the host to save your position...'; self.view:neutralize()
    return true
end
function Panel:suspend() self.destination=nil; self.shooter:suspend() end
function Panel:movement(x,y)
    if x~=0 or y~=0 then self.destination=nil; return x,y end
    local target=self.destination; local player=self.view.runtime.player
    if not target then return x,y end
    local dx,dy=target.x-player.x,target.y-player.y; local distance=math.sqrt(dx*dx+dy*dy)
    if distance<12 then self.destination=nil; return 0,0 end
    return dx/distance,dy/distance
end
function Panel:update(dt)
    self.aid:update(dt)
    local state=self:state()
    if not state then self.shooter:update(dt); self.key=nil; self.scene=nil; self.stageFrame=nil; return end
    local key=Life.key(self.view.runtime.saveData)
    if self.key~=key then
        self.key=key; self.paused=false; self.notice=nil; self.scene=nil; self.destination=nil; self.pending=nil; self.stageFrame=nil
        local runtime=self.view.runtime
        for _,name in ipairs({'inventoryOpen','tradeOpen','trainUpgradeOpen','peopleOpen','guestActivityOpen'}) do runtime[name]=false end
        if self.view.inventory then self.view.inventory:cancelDrag() end
        if self.view.objects then self.view.objects:suspend() end
        if self.view.people then self.view.people:close() end
        if self.view.activities then self.view.activities:suspend() end
        if Life.walking(runtime.saveData) or state.mode=='aftermath' then
            self.scene=Scene.new(state.mode=='aftermath' and 'interior' or state.mode,runtime.saveData.lastStand)
        end
    end
    local stages=self.view.controller.lastStandStage
    local frame=stages and stages:get()
    self.stageStale=not frame or frame.mode~=state.mode
    if frame and frame.mode==state.mode and not self.paused and not self.view.controller.menuOpen then
        local scout,pose=frame.scout,frame.hostPose
        self.stageFrame={mode=frame.mode,clock=frame.clock,paused=frame.paused,offerPage=frame.offerPage,
            scout=scout and {x=scout.x,y=scout.y,walkDistance=scout.walkDistance,arrival=scout.arrival} or nil,
            hostPose=pose and {x=pose.x,y=pose.y,facing=pose.facing} or nil}
    end
    self.shooter:update(dt)
    if self.scene and Life.walking(self.view.runtime.saveData) then
        self.scene.quest=self.view.runtime.saveData.lastStand
        self.scene.player=self.view.runtime.player
        local preferences=Accessibility.ensure(self.view.runtime.saveData)
        self.scene.reducedMotion=preferences.reducedMotion; self.scene.reducedFlashes=preferences.reducedFlashes
        Scene.update(self.scene,dt,{noMovement=true})
    end
    local pending=self.pending; local network=self.view.controller.network; local reply=network and network.lastCommandResult
    if pending and reply and reply.requestId==pending.id then
        if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then
            self.notice=pending.kind=='position' and 'Waiting for the host to save your position...' or 'Waiting for the host to save supplies...'
        elseif not reply.ok or reply.durable and self.view.runtime.saveData.coop.revision>=reply.revision then
            self.pending=nil
            local facts=reply.details or reply.result
            if pending.kind=='position' then
                self.notice=reply.ok and facts and facts.actorId=='companion' and facts.questId==state.entityId
                    and (facts.windowId and ('Your '..facts.windowId..' window is selected. The host starts the defense.') or 'Your position is released.')
                    or reply.reason=='position_occupied' and 'This window is occupied. Choose the other position.'
                    or 'The position is unavailable. Move closer to a free window and try again.'
            else
                self.notice=reply.ok and facts and facts.actorId=='companion' and facts.questId==state.entityId
                    and 'Loan supplies received. '..facts.loanAmmo..' rounds available.'
                    or 'Supplies are currently unavailable. Stay near Guard Fox and try again.'
            end
        end
    end
end
-- A checked visual frame cannot change the reliable quest or any actor pose.
-- Expired frames retain their last picture until a matching host frame arrives.
function Panel:passiveModel()
    local state=self:state()
    if not state or (state.mode~='offer' and state.mode~='escort' and state.mode~='aftermath' and state.mode~='returning') then return nil end
    local frame=self.stageFrame or {}
    local q=self.view.runtime.saveData.lastStand
    local pose=frame.hostPose
    local scout=frame.scout
    return {mode=state.mode,clock=frame.clock or 0,
        paused=frame.paused==true or self.stageStale or self.paused==true or self.view.controller.menuOpen,
        stale=self.stageStale==true,scout=scout and {x=scout.x,y=scout.y,walkDistance=scout.walkDistance,arrival=scout.arrival} or nil,
        page=state.mode=='offer' and Quest.offerPage(frame.offerPage or 1) or nil,
        summary=state.mode=='aftermath' and Quest.aftermathSummary(q) or nil,
        guest={x=505,y=590,facing=1},
        host={x=pose and pose.x or 480,y=pose and pose.y or 590,facing=pose and pose.facing or 1}}
end
function Panel:keypressed(key)
    if self.aid.opened then return self.aid:keypressed(key) end
    if self.shooter:available() then return self.shooter:keypressed(key) end
    if key=='p' then self.paused=not self.paused; self.view:neutralize()
    elseif key=='backspace' then self:position('release')
    elseif key=='e' or key=='return' or key=='space' then self:assist()
    elseif key=='escape' then self.view.controller:open(); self.view:neutralize() end
    return true
end
function Panel:gamepadpressed(button)
    if self.aid.opened then
        if button=='a' or button=='x' then return self.aid:keypressed('return') end
        if button=='b' or button=='start' or button=='back' then return self.aid:keypressed('escape') end
        return true
    end
    if self.shooter:available() then return self.shooter:gamepadpressed(button) end
    if button=='b' and self:state().mode=='interior' then return self:position('release') end
    if button=='start' then return self:keypressed('p') end
    if button=='a' or button=='x' then return self:keypressed('e') end
    if button=='back' then return self:keypressed('escape') end
    return true
end
function Panel:pointer(x,y,button,istouch)
    if self.aid.opened then if button==1 then self.aid:press(x,y) end; return true end
    if self.shooter:available() then return self.shooter:pointer(x,y,button) end
    if button==1 and x>=648 and x<=750 and y>=12 and y<=57 then self:keypressed('p'); return true end
    local action=self:action()
    if button==1 and self:state().mode=='interior' and Selection.selected(self.view.runtime.saveData,'companion')
        and x>=20 and x<=350 and y>=580 and y<=625 then self:position('release'); return true end
    if button==1 and action and (action.id=='borrow-rifle' or action.id=='help-wounded' or action.id=='window-wide' or action.id=='window-tall') and x>=580 and x<=930 and y>=580 and y<=625 then self:assist(); return true end
    if not istouch and button==1 and self.view:inputAllowed() then
        x,y=WorldView.toWorld(x,y)
        if Geometry.walkable(self:state().mode,x,y) then self.destination={x=x,y=y} end
        return true
    end
    return false
end
local messages={offer='The host is reviewing the defense.',escort='Following the scout to the farmhouse.',
    shootout='Defense in progress.',aftermath='Defense complete. The host chooses when to return.',returning='Returning to the stop.'}
function Panel:visual(id)
    local data=self.view.runtime.saveData; local actor=data.players[id]; local content=self.c.content or {}
    return {image=content.characterImages and content.characterImages[actor.character],character=actor.character,
        animations=self.c.characterAnimations and self.c.characterAnimations() or {},
        walkImage=content.characterWalkImages and content.characterWalkImages[actor.character],clock=self.view.runtime.animationClock or 0}
end
function Panel:draw()
    local state=self:state(); if not state then return end
    if self.aid.opened then self.aid:draw(); return end
    if self.shooter:available() then self.shooter:draw(); return end
    local g=love.graphics
    local model=self:passiveModel()
    if model and (state.mode=='escort' or state.mode=='returning') then
        local preferences=Accessibility.ensure(self.view.runtime.saveData)
        Scene.drawGuestTransition({quest=self.view.runtime.saveData.lastStand,clock=model.clock,paused=model.paused,
            reducedMotion=preferences.reducedMotion},960,720,state.mode=='returning',self:visual('host'),self:visual('companion'))
    elseif model and state.mode=='offer' then
        local preferences=Accessibility.ensure(self.view.runtime.saveData)
        Scene.drawGuestOffer({quest=self.view.runtime.saveData.lastStand,clock=model.clock,paused=model.paused,
            reducedMotion=preferences.reducedMotion,scout=model.scout,
            walkDistance=model.scout and model.scout.walkDistance or 0,arrival=model.scout and model.scout.arrival or 1},960,720)
    elseif model and state.mode=='aftermath' then
        local preferences=Accessibility.ensure(self.view.runtime.saveData)
        self.scene.quest=self.view.runtime.saveData.lastStand; self.scene.clock=model.clock
        self.scene.player=model.guest; self.scene.reducedMotion=preferences.reducedMotion; self.scene.reducedFlashes=preferences.reducedFlashes
        Scene.draw(self.scene,960,720,self:visual('companion'),false,false,false,
            {{player=model.host,visual=self:visual('host')}},true)
    elseif self.scene then
        self.scene.player=self.view.runtime.player
        Scene.draw(self.scene,960,720,self:visual('companion'),false,self.c.mobileEnabled and self.c.mobileEnabled(),false,
            {{player=self.view.remote,visual=self:visual('host')}},true)
    else g.setColor(.055,.038,.025,1); g.rectangle('fill',0,0,960,720) end
    local function text(value,x,y,w,h)
        g.setColor(1,.89,.68,1)
        Typography.drawText(g,value,x,y,w,h,{scale=.85*Accessibility.textScale(self.view.runtime.saveData),minScale=.6,align='center',valign='center'})
    end
    local card=model and (model.page or model.summary)
    if card then
        g.setColor(.055,.038,.025,.96); GuiArt.frame(155,225,650,250)
        text(card.title,180,242,600,45); text(card.text,180,295,600,126)
        if card.page then text('Page '..card.page..' / '..card.count,180,425,600,30) end
    end
    g.setColor(.055,.038,.025,.95); GuiArt.frame(16,12,616,45)
    text('FARMHOUSE CO-OP  •  '..state.mode:upper(),20,15,608,39)
    g.setColor(.18,.12,.075,.95); GuiArt.frame(648,12,102,45); text(self.paused and 'RESUME' or 'PAUSE',652,15,94,39)
    g.setColor(.055,.038,.025,.95); GuiArt.frame(160,645,640,55)
    local walkingHint=self.c.mobileEnabled and self.c.mobileEnabled() and 'Joystick to move. The host controls scene progression.'
        or 'WASD / arrows or click to move. The host controls scene progression.'
    text(self.paused and 'Your movement is paused. P / START to resume.' or self.notice
        or messages[state.mode] or walkingHint,174,649,612,47)
    local action=self:action()
    local selection=Selection.selected(self.view.runtime.saveData,'companion')
    if state.mode=='interior' and selection then
        g.setColor(.18,.12,.075,.95); GuiArt.frame(20,580,330,45)
        text('RELEASE '..selection:upper()..' POSITION  [BACKSPACE]',24,583,322,39)
    end
    if action and (action.id=='borrow-rifle' or action.id=='help-wounded' or action.id=='window-wide' or action.id=='window-tall') then
        g.setColor(.18,.12,.075,.95); GuiArt.frame(580,580,350,45)
        local window=action.id=='window-wide' and 'wide' or action.id=='window-tall' and 'tall'
        local owner=window and Selection.owner(self.view.runtime.saveData,window)
        local label=window and (owner=='host' and 'WINDOW OCCUPIED BY HOST' or owner=='companion' and 'YOUR '..window:upper()..' POSITION' or 'SELECT '..window:upper()..' WINDOW')
            or action.id=='help-wounded' and 'TREAT WOUNDED' or 'BORROW RIFLE / AMMO'
        text(self.c.mobileEnabled and self.c.mobileEnabled() and label or label..'  [E]',584,583,342,39)
    end
end
function Panel:release() self.aid:suspend(); self.shooter:release(); self.scene=nil; self.stageFrame=nil; Scene.release() end
return Panel
