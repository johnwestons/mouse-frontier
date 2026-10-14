-- Private defender controls. The host owns enemy simulation and story progress.
local Schema=require('game.save_schema')
local Players=require('game.coop_players')
local Sessions=require('game.coop_shooter_sessions')
local Shooting=require('game.first_person_shooting')
local Actions=require('game.first_person_weapon_actions')
local Guns=require('game.coop_guns')
local Positions=require('game.coop_last_stand_positions')
local Selection=require('game.coop_last_stand_position_state')
local Life=require('game.coop_last_stand_lifecycle')
local Shootout=require('game.last_stand_shootout')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local Panel={}; Panel.__index=Panel
local controls={{key='space',label='FIRE\nLMB / SPACE'},{key='aim',label='AIM\nRMB'},
    {key='r',label='RELOAD\nR'},{key='c',label='COVER\nC'},{key='tab',label='WEAPON\nTAB'},
    {key='v',label='MODE\nV'},{key='l',label='SUPPLIES\nL'},{key='p',label='PAUSE\nP'},
    {key='menu',label='LOCAL PLAY\nF8'}}
local function inside(r,x,y) return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
function Panel.new(view,c,parent) return setmetatable({view=view,c=c,parent=parent,held={},touches={}},Panel) end
function Panel:state()
    local data=self.view.runtime.saveData; local life=Life.active(data)
    return life and life.mode=='shootout' and data.lastStand and data.lastStand.combat and data.lastStand or nil
end
function Panel:available() return self:state()~=nil end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed or 0 end
function Panel:identity()
    local q=self:state(); if not q then return nil end
    return Life.key(self.view.runtime.saveData)..':'..q.combat.entityId..':'..q.combat.phaseRevision
end
function Panel:readyToRequest()
    local v=self.view; local q=self:state(); local frame=v.controller.motionFrame
    return q and not q.combat.result and v.ready and v.focused and not v.controller.menuOpen
        and not self.parent.paused and not self.pending and not self.parent.pending
        and v.controller.network and not v.controller.network.pendingCommand
        and v.motionId and frame and frame.sceneEpoch==v.epoch and frame.motionId==v.motionId
        and frame.domain==Life.key(v.runtime.saveData) and v.runtime.saveData.health>1
end
function Panel:checkedPosition()
    local p=self.position; local q=self:state(); local v=self.view
    return p and q and p.identity==self:identity() and p.epoch==v.epoch and p.motionId==v.motionId
        and p.network==v.controller.network and p.expiresAt>self:now()
        and Selection.selected(v.runtime.saveData,'companion')==p.windowId
        and q.combat.defenders.companion and q.combat.defenders.companion.windowId==p.windowId
end
function Panel:canAct() return self:readyToRequest() and self:checkedPosition() and not self.choosing end
function Panel:suspend()
    self.held={}; self.touches={}; self.aimTouch=nil; self.fireTouch=nil; self.controllerReady=false
    self.controllerFire=false; self.controllerADS=false
    if self.gun then Shooting.setADS(self.gun,false) end
end
function Panel:options()
    local q=self:state(); local options={}
    for _,entry in ipairs(Shooting.weaponOptions(self.view.runtime.saveData,self.c.catalog)) do
        if not entry.borrowed or q and q.shooterSessions and q.shooterSessions.companion
            and q.shooterSessions.companion.loanActive then options[#options+1]=entry end
    end
    return options
end
function Panel:sync()
    local q=self:state(); local v=self.view; local identity=self:identity()
    if self.identityKey~=identity or self.epoch~=v.epoch or self.network~=v.controller.network or self.motionId~=v.motionId then
        self:suspend(); self.gun=nil; self.pending=nil; self.position=nil; self.notice=nil; self.choosing=false; self.drawCampaign=nil; self.drawActor=nil
        self.seenDamage=nil; self.hitFeedback=0; self.damageNotice=nil; self.damageNoticeTime=0
        self.effectBaseline=nil; self.seenEffectSerial=0; self.effectSeen={}; self.effectSeenOrder={}; self.effectClock=0; self.effectPaused=false
        self.visualEvents={}; self.visualImpacts={}; self.visualWindow=nil
        self.identityKey=identity; self.epoch=v.epoch; self.network=v.controller.network; self.motionId=v.motionId; self.seenRevision=nil
    end
    if not q then return end
    local owner=q.combat.defenders.companion; local window=owner and owner.windowId
    if self.visualWindow~=window then self.visualWindow=window; self.visualEvents={}; self.visualImpacts={} end
    if self.seenRevision~=v.revision then
        local owner=q.combat.defenders.companion; local damage=owner and owner.playerDamage
        if damage~=nil then
            if self.seenDamage~=nil and damage>self.seenDamage and v.focused and not v.controller.menuOpen and not self.parent.paused then
                self.hitFeedback=.45; self.damageNotice='HEALTH LOST: '..tostring(damage-self.seenDamage)..'. COVER / C protects your traveler.'
                self.damageNoticeTime=1.7
            end
            self.seenDamage=damage
        else self.seenDamage=nil end
        self.drawCampaign=assert(Schema.copy(Players.campaignOf(v.runtime.saveData)))
        self.drawActor=Players.forActor(self.drawCampaign,'companion')
        local scope=q.shooterSessions and q.shooterSessions.companion
        local saved=scope and scope.weaponSession
        if saved then
            local old=self.gun; self.gun=Sessions.view(assert(Schema.copy(saved)),960,720)
            if old then Shooting.setAim(self.gun,old.aimX,old.aimY); Shooting.setADS(self.gun,old.ads); self.gun.touchAim=old.touchAim end
        else self.gun=nil end
        self.seenRevision=v.revision
    end
end
function Panel:observeEffects(dt)
    local presentation=self.view.controller.lastStandEffects
    local frame=presentation and presentation:get()
    if not frame then
        if not self.effectPaused then self.effectClock=self.effectClock+math.max(0,dt or 0) end
        return
    end
    self.effectPaused=frame.paused==true
    if not frame.paused then self.effectClock=self.effectClock+math.max(0,dt or 0) end
    local q=self:state(); local owner=q and q.combat.defenders.companion
    local visible=self.view.focused and not self.view.controller.menuOpen and not self.parent.paused
    local initial=not self.effectBaseline; self.effectBaseline=true
    local now=self.effectClock; local audible=false
    for _,event in ipairs(frame.events) do
        if not self.effectSeen[event.serial] then
            self.effectSeen[event.serial]=true; self.effectSeenOrder[#self.effectSeenOrder+1]=event.serial
            if #self.effectSeenOrder>64 then self.effectSeen[table.remove(self.effectSeenOrder,1)]=nil end
            self.seenEffectSerial=math.max(self.seenEffectSerial or 0,event.serial)
            if not initial and visible and owner and event.actorId=='companion' and event.windowId==owner.windowId and event.elapsed<.665 then
                local copy={}; for key,value in pairs(event) do copy[key]=value end
                copy.receivedAt=now; copy.receivedElapsed=event.elapsed
                self.visualEvents[#self.visualEvents+1]=copy
                if #self.visualEvents>8 then table.remove(self.visualEvents,1) end
                if event.elapsed<=.35 then audible=true end
            end
        end
    end
    if audible then Shooting.playReport('frontier-22-lever-rifle',self.c.catalog,self.view.runtime.saveData,true) end
    if not visible then self.visualEvents={}; self.hitFeedback=0; self.damageNotice=nil; self.damageNoticeTime=0 end
end
function Panel:visualEffects()
    local result={incomingShots={},flashes={},impactBursts={},impacts={},targetEffects={},hitFeedback=self.hitFeedback or 0}
    local now=self.effectClock
    for index=#self.visualEvents,1,-1 do
        local event=self.visualEvents[index]; local age=event.receivedElapsed+math.max(0,now-event.receivedAt)
        if age>=.305 and event.decal and not event.decalPresented then
            event.decalPresented=true; self.visualImpacts[#self.visualImpacts+1]={point=event.point,frame=event.decalFrame,born=now-(age-.305)}
            if #self.visualImpacts>8 then table.remove(self.visualImpacts,1) end
        end
        if age>=.045+.26+.36 then table.remove(self.visualEvents,index)
        else
            if age<.16 then result.flashes[#result.flashes+1]={slot=event.slot,ttl=.16-age,maxTtl=.16} end
            if age<.045+.26 then
                result.incomingShots[#result.incomingShots+1]={slot=event.slot,point=event.point,actorId=event.actorId,
                    elapsed=age,hit=event.hit,decal=event.decal,impactFrame=event.impactFrame,decalFrame=event.decalFrame}
            else
                local ttl=.045+.26+.36-age
                result.impactBursts[#result.impactBursts+1]={point=event.point,frame=event.impactFrame,ttl=ttl,maxTtl=.36}
            end
        end
    end
    for _,impact in ipairs(self.visualImpacts) do
        result.impacts[#result.impacts+1]={point=impact.point,frame=impact.frame,age=math.max(0,now-impact.born),rotation=0}
    end
    return result
end
function Panel:requestPosition(action,window)
    if not self:readyToRequest() then return false end
    local v=self.view; local q=self:state(); local life=q.lifecycle
    local args={questId=life.entityId,revision=life.revision,action=action,phaseRevision=q.combat.phaseRevision}
    if action=='ready' then args.window=window end
    local expected={}; for _,scope in ipairs(Positions.scopes(v.runtime.saveData,'companion')) do expected[scope]=v.runtime.saveData.coop.revisions[scope] or 0 end
    local id,reason=v.controller.network:submitCommand('lastStand.position',args,v.epoch,expected)
    if not id then self.notice='The position is unavailable. Wait for the host update.'; return false,reason end
    self:suspend(); self.pending={id=id,identity=self:identity(),epoch=v.epoch,name='lastStand.position',action=action,window=window}
    self.notice='Waiting for the host to save your position...'; return true
end
function Panel:submit(name,extra)
    if not self:canAct() then return false end
    local v=self.view; local q=self:state(); local combat=q.combat
    local args={mode='lastStand',encounterId=combat.entityId,phaseRevision=combat.phaseRevision}
    if name~='gun.cover' and name~='lastStand.supply' then args.weaponId=self.gun and (self.gun.borrowed and 'loan:companion' or self.gun.itemId) end
    for key,value in pairs(extra or {}) do args[key]=value end
    local expected={}; for _,scope in ipairs(Guns.scopes(v.runtime.saveData,'companion','lastStand')) do expected[scope]=v.runtime.saveData.coop.revisions[scope] or 0 end
    local id,reason=v.controller.network:submitCommand(name,args,v.epoch,expected)
    if not id then self.notice='Action unavailable. Wait for the host update.'; return false,reason end
    self.pending={id=id,identity=self:identity(),epoch=v.epoch,name=name,x=self.gun and self.gun.aimX,y=self.gun and self.gun.aimY}
    self.notice='Waiting for the host to save this action...'; return true
end
function Panel:aim(x,y,touch)
    if not self.gun or self.parent.paused then return end
    x,y=math.max(0,math.min(960,x)),math.max(0,math.min(720,y))
    if touch then Shooting.setTouchAim(self.gun,x,y,960,720) else Shooting.setAim(self.gun,x,y) end
end
function Panel:fire()
    local gun=self.gun; local q=self:state(); local owner=q and q.combat.defenders.companion
    if not self:canAct() or not gun or not gun.weapon or gun.fireMode=='safe' or not owner
        or owner.ducking or owner.coverProgress>0 or gun.cooldown>0 or gun.reloadTimer>0 then return false end
    if gun.magazine<=0 then return self:submit('gun.reload') end
    return self:submit('gun.fire',{x=math.floor(gun.aimX/960*Guns.POINT+.5),y=math.floor(gun.aimY/720*Guns.POINT+.5)})
end
function Panel:fireHeld(source,down)
    local previous=self.held[source]; self.held[source]=down or nil
    if down and not previous then return self:fire() end
end
function Panel:action(key)
    if key=='menu' or key=='f8' or key=='escape' or key=='acback' then self:suspend(); self.view.controller:open(); return true end
    if key=='p' then self.parent.paused=not self.parent.paused; self:suspend(); return true end
    if self.parent.paused then if key=='return' or key=='space' then self.parent.paused=false; self:suspend() end; return true end
    if key=='1' or key=='2' then return self:requestPosition('ready',key=='1' and 'wide' or 'tall') end
    if key=='backspace' then return self:requestPosition('release') end
    if key=='position' then self:suspend(); self.choosing=not self.choosing; return true end
    if not self:canAct() then return true end
    local owner=self:state().combat.defenders.companion
    if key=='space' then self:fireHeld('keyboard',true)
    elseif key=='r' then self:submit('gun.reload')
    elseif key=='c' then self:suspend(); self:submit('gun.cover',{cover=not owner.ducking})
    elseif key=='v' then self:suspend(); self:submit('gun.mode')
    elseif key=='l' then self:suspend(); self:submit('lastStand.supply')
    elseif key=='aim' and self.gun and not owner.ducking then Shooting.setADS(self.gun,not self.gun.ads)
    elseif key=='tab' then
        local options=self:options(); if #options==0 then return true end
        local selected=0; for index,entry in ipairs(options) do
            if self.gun and (entry.borrowed and self.gun.borrowed or entry.itemId==self.gun.itemId and not self.gun.borrowed) then selected=index end
        end
        local nextWeapon=options[selected%#options+1]
        self:suspend(); self:submit('gun.select',{weaponId=nextWeapon.borrowed and 'loan:companion' or nextWeapon.itemId})
    end
    return true
end
function Panel:update(dt)
    self:sync(); local q=self:state(); if not q then return end
    self:observeEffects(dt)
    local v=self.view; local p=self.pending; local reply=v.controller.network and v.controller.network.lastCommandResult
    if p and reply and reply.requestId==p.id then
        if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then self.notice='Waiting for the host to finish saving...'
        elseif not reply.ok or reply.durable and v.runtime.saveData.coop.revision>=reply.revision then
            self.pending=nil; self.lastOutcome=reply; self.notice=nil
            local facts=reply.details or reply.result
            if not reply.ok then
                self:suspend()
                if reply.reason=='position_unavailable' or reply.reason=='position_expired' or reply.reason=='shooter_unavailable' or reply.reason=='lease_expired' or reply.reason=='stale_phase' then self.position=nil end
                self.notice=reply.reason=='position_occupied' and 'This window is occupied. Choose the other position.'
                    or reply.reason=='position_distance' and 'Move closer to the window.'
                    or reply.reason=='stale_revision' and 'The defense changed. Try the action again.'
                    or 'This action is currently unavailable.'
            elseif facts and facts.actorId=='companion' then
                if p.name=='lastStand.position' and facts.questId==q.lifecycle.entityId and facts.revision==q.lifecycle.revision
                    and facts.phaseRevision==q.combat.phaseRevision and facts.action==p.action then
                    if p.action=='ready' and facts.windowId==p.window and facts.leaseId and facts.expiresIn then
                        self.position={identity=self:identity(),epoch=v.epoch,motionId=v.motionId,network=v.controller.network,
                            windowId=facts.windowId,leaseId=facts.leaseId,expiresAt=self:now()+facts.expiresIn}
                        self.choosing=false
                    elseif p.action=='release' then self.position=nil; self.choosing=true end
                elseif facts.encounterId==q.combat.entityId and facts.phaseRevision==q.combat.phaseRevision and facts.fired then
                    Shooting.playReport(facts.weapon,self.c.catalog,v.runtime.saveData)
                    if facts.hit then self.impact={x=p.x,y=p.y,time=.22} end
                end
            end
        end
    end
    if not v.focused or v.controller.menuOpen or self.parent.paused or q.combat.result or not self:checkedPosition() then self:suspend() end
    if self.gun then Actions.update(self.gun,math.min(.1,dt)) end -- Private authored-frame clock only.
    local cueDt=self.effectPaused and 0 or dt
    if self.impact then self.impact.time=self.impact.time-cueDt; if self.impact.time<=0 then self.impact=nil end end
    self.hitFeedback=math.max(0,(self.hitFeedback or 0)-cueDt)
    self.damageNoticeTime=math.max(0,(self.damageNoticeTime or 0)-cueDt)
    if self.damageNoticeTime==0 then self.damageNotice=nil end
    if self:readyToRequest() and not self.choosing then
        local selected=Selection.selected(v.runtime.saveData,'companion')
        if not self:checkedPosition() and selected and self:now()>=(self.retryReadyAt or 0) then
            self.retryReadyAt=self:now()+1; self:requestPosition('ready',selected); return
        elseif self:checkedPosition() and self.position.expiresAt-self:now()<8 then
            self:requestPosition('ready',self.position.windowId); return
        end
    end
    if self:canAct() and self.gun then
        local bindings=self.c.bindings
        local x,y=bindings:axisValue('aim_x'),bindings:axisValue('aim_y')
        if x~=0 or y~=0 then self:aim(self.gun.aimX+x*340*dt,self.gun.aimY+y*340*dt) end
        local firing,ads=bindings:axisValue('fire')>.4,bindings:axisValue('ads')>.4
        if not firing and not ads then self.controllerReady=true end
        if self.controllerReady then
            if firing~=self.controllerFire then self:fireHeld('controller',firing) end
            if ads~=self.controllerADS then Shooting.setADS(self.gun,ads) end
            self.controllerFire,self.controllerADS=firing,ads
        end
        if self.gun.fireMode=='auto' and next(self.held) then self:fire() end
    end
end
function Panel:rect(index) local width=920/#controls; return {x=20+(index-1)*width,y=644,w=width-5,h=56} end
function Panel:positionRect(window) return {x=window=='wide' and 140 or 510,y=405,w=310,h=58} end
function Panel:pointerAction(x,y)
    if inside({x=350,y=16,w=260,h=45},x,y) then self:action('position'); return true end
    if not self:checkedPosition() or self.choosing then
        for _,window in ipairs({'wide','tall'}) do if inside(self:positionRect(window),x,y) then self:requestPosition('ready',window); return true end end
        if inside({x=350,y=480,w=260,h=52},x,y) then self:requestPosition('release'); return true end
    end
    return false
end
function Panel:pointer(x,y,button)
    if button==1 then
        if self:pointerAction(x,y) then return true end
        for index,control in ipairs(controls) do if inside(self:rect(index),x,y) then
            if control.key=='space' then self:fireHeld('mouse',true) else self:action(control.key) end; return true
        end end
        if self:canAct() then self:aim(x,y); self:fireHeld('mouse',true) end
    elseif button==2 and self:canAct() and self.gun then self:aim(x,y); Shooting.setADS(self.gun,true) end
    return true
end
function Panel:mousemoved(x,y) if y<620 and self:canAct() then self:aim(x,y) end; return true end
function Panel:mousereleased(button)
    if button==1 then self:fireHeld('mouse',false) elseif button==2 and self.gun then Shooting.setADS(self.gun,false) end; return true
end
function Panel:keypressed(key) return self:action(key) end
function Panel:keyreleased(key) if key=='space' then self:fireHeld('keyboard',false) end; return true end
function Panel:gamepadpressed(button)
    if button=='start' then return self:action('p') elseif button=='back' then return self:action('menu') end
    if not self:checkedPosition() or self.choosing then
        if button=='dpleft' then self.windowChoice='wide' elseif button=='dpright' then self.windowChoice='tall'
        elseif button=='a' or button=='x' then self:requestPosition('ready',self.windowChoice or Selection.selected(self.view.runtime.saveData,'companion') or 'wide')
        elseif button=='b' then self:requestPosition('release') end
        return true
    end
    local key=self.c.bindings:translateButton(button,'last_stand_shootout'); if key then self:action(key) end; return true
end
function Panel:gamepadreleased(button)
    local key=self.c.bindings:translateButton(button,'last_stand_shootout'); if key=='space' then self:fireHeld('keyboard',false) end; return true
end
function Panel:touchpressed(id,x,y)
    if self:pointerAction(x,y) then return true end
    for index,control in ipairs(controls) do if inside(self:rect(index),x,y) then
        if control.key=='space' then
            if not self.fireTouch then self.fireTouch=id; self.touches[id]='space'; self:fireHeld('touch',true) end
        else self:action(control.key) end
        return true
    end end
    if self:canAct() and not self.aimTouch then self.aimTouch=id; self.touches[id]='aim'; self:aim(x,y,true) end
    return true
end
function Panel:touchmoved(id,x,y) if self.aimTouch==id then self:aim(x,y,true) end; return true end
function Panel:touchreleased(id)
    if self.fireTouch==id then self.fireTouch=nil; self:fireHeld('touch',false) end
    if self.aimTouch==id then self.aimTouch=nil end; self.touches[id]=nil; return true
end
function Panel:draw()
    local q=self:state(); if not q then return end
    local v=self.view; local data=v.runtime.saveData; local g=love.graphics
    if self.gun and q.combat.defenders.companion then
        local pose=Shootout.guestView(self.drawCampaign.lastStand,self.drawActor,self.gun,960,720,self:visualEffects())
        if pose then Shootout.drawGuest(pose,data,960,720) end
    else g.setColor(.055,.038,.025,1); g.rectangle('fill',0,0,960,720) end
    if self.impact then
        g.setColor(1,.78,.34,1); local x,y=self.impact.x,self.impact.y
        g.line(x-12,y-12,x-5,y-5); g.line(x+5,y+5,x+12,y+12)
        g.line(x-12,y+12,x-5,y+5); g.line(x+5,y-5,x+12,y-12)
    end
    local function text(value,x,y,w,h,scale)
        g.setColor(1,.89,.68,1)
        Typography.drawText(g,value,x,y,w,h,{scale=(scale or .8)*Accessibility.textScale(data),minScale=.6,align='center',valign='center'})
    end
    g.setColor(.055,.038,.025,.95); g.rectangle('fill',350,16,260,45,6,6)
    text('POSITION: '..(Selection.selected(data,'companion') or 'CHOOSE'):upper()..'  [1 / 2]',354,20,252,37,.7)
    if not self:checkedPosition() or self.choosing then
        g.setColor(.035,.025,.02,.85); g.rectangle('fill',100,275,760,280,8,8)
        text('Choose your firing position',125,290,710,46)
        text('The host starts each defense. Choose a free window to assist.',125,345,710,40,.72)
        for _,window in ipairs({'wide','tall'}) do
            local r=self:positionRect(window); local owner=Selection.owner(data,window)
            g.setColor(.18,.12,.075,.96); g.rectangle('fill',r.x,r.y,r.w,r.h,6,6)
            text(window:upper()..' WINDOW  ['..(window=='wide' and '1' or '2')..']'
                ..(owner=='host' and ' — HOST' or owner=='companion' and ' — YOURS' or ' — FREE'),r.x+4,r.y+4,r.w-8,r.h-8,.7)
        end
        g.setColor(.18,.12,.075,.96); g.rectangle('fill',350,480,260,52,6,6)
        text('Release your position [BACKSPACE]',355,484,250,44,.65)
    end
    g.setColor(.035,.025,.02,.95); g.rectangle('fill',0,580,960,140)
    text(self.notice or self.parent.paused and 'Your controls are paused. P / START to resume.'
        or q.combat.result and 'The host controls the next phase, retry and return.'
        or data.health<=1 and 'You are wounded. The host controls how the journey continues.'
        or self.damageNotice
        or self:checkedPosition() and self.gun and Shooting.needsSupply(self.gun,self.drawActor,self.drawCampaign.lastStand) and 'Loan rifle and ammunition are available. Press SUPPLIES / L.'
        or q.combat.defenders.companion and q.combat.defenders.companion.ducking and 'IN COVER — protected. Press COVER / C to return to the window.'
        or 'Help defend the farmhouse. Story decisions stay with the host.',25,590,910,42,.7)
    for index,control in ipairs(controls) do
        local r=self:rect(index); g.setColor(.12,.075,.035,.96); g.rectangle('fill',r.x,r.y,r.w,r.h,5,5)
        text(control.label,r.x+2,r.y+2,r.w-4,r.h-4,.65)
    end
end
function Panel:release() self:suspend(); self.gun=nil; self.pending=nil; self.position=nil end
return Panel
