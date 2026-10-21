-- Private practice controls. Targets, ammunition and rewards belong to the host.
local Range=require('game.shooting_range')
local Shooting=require('game.first_person_shooting')
local Life=require('game.coop_last_stand_lifecycle')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local ShooterPad=require('game.mobile_shooter_controls')
local AimTargets=require('game.mobile_aim_targets')
local Panel={}; Panel.__index=Panel
local menuRect={x=764,y=100,w=180,h=38}
local pauseRect={x=20,y=104,w=170,h=40}
local retryAcquire={rate_limited=true,stale_revision=true,not_ready=true,scene_not_ready=true,
    range_not_ready=true,lease_expired=true,lease_owner=true}
local function inside(r,x,y) return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
function Panel.new(view,c)
    return setmetatable({view=view,c=c,held={},touches={},aimPad=ShooterPad.new(),pose={aimX=480,aimY=330,aimMode='hip',menuRow=1}},Panel)
end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed or 0 end
function Panel:state()
    local data=self.view.runtime.saveData
    return data and data.rangeSessions and data.rangeSessions.companion
end
function Panel:available() return self.opened==true end
function Panel:busy() return self.opened or self.pending or self.wantRelease end
function Panel:pauseRect() return {x=pauseRect.x,y=pauseRect.y,w=pauseRect.w,h=pauseRect.h} end
function Panel:nearest()
    local v=self.view; local data=v.runtime.saveData
    if not data or data.scene~='stop' or Life.active(data) or data.tacticalBattle or data.roamingEncounter then return nil end
    local layout=data.stopLayouts and data.stopLayouts[tostring(data.location)]
    local spot=layout and layout.shootingRange; local player=v.runtime.player
    return spot and player and Range.near(spot,player.x,player.y) and spot or nil
end
function Panel:desiredPaused()
    return self.paused==true or self.view.focused~=true or self.view.controller.menuOpen==true
end
function Panel:canManage()
    local v=self.view; local frame=v.controller.motionFrame
    return self.opened and v.ready and v.controller.network and not self.pending and not v.controller.network.pendingCommand
        and v.motionId and frame and frame.sceneEpoch==v.epoch and frame.motionId==v.motionId
        and frame.domain==nil and self.epoch==v.epoch and v.runtime.saveData.health>0
end
function Panel:canRequest() return self:canManage() and not self:desiredPaused() end
function Panel:checkedLease()
    local s=self:state(); local v=self.view
    return self.leaseId and s and s.spotId==self.spotId and self.leaseEpoch==v.epoch
        and self.leaseNetwork==v.controller.network and self.leaseMotionId==v.motionId
        and self.expiresAt>self:now()
end
function Panel:canAct() return self:canRequest() and self:checkedLease() and self.serverPaused==false end
function Panel:commandState()
    local s=self:state()
    return self.opened and self:checkedLease() and s and {active=true,spotId=s.spotId,leaseId=self.leaseId,
        roundRevision=s.roundRevision,paused=self:desiredPaused() or self.serverPaused~=false} or nil
end
function Panel:suspend()
    self.aimPad:cancel()
    self.held={}; self.touches={}; self.aimTouch=nil; self.fireTouch=nil; self.controllerReady=false
    self.controllerFire=false; self.controllerADS=false; self.controllerKeys={}
end
function Panel:open()
    if self:busy() or not self.view:inputAllowed() then return false end
    local spot=self:nearest(); if not spot or not spot.entityId then return false end
    self.opened=true; self.epoch=self.view.epoch; self.network=self.view.controller.network
    self.spotId=spot.entityId; self.paused=false; self.notice=nil; self.model=nil; self.modelRevision=nil
    self.serverPaused=nil
    self.acquireFailures=0; self.acquireBlocked=false; self.acquireRetryAt=nil
    self.view.runtime.shootingRange={phase='lobby'}
    self.pose={aimX=480,aimY=330,aimMode='hip',menuRow=1}; self.view:neutralize()
    return self:submit('range.acquire',{spotId=self.spotId})
end
function Panel:submit(name,args,cleanup)
    local v=self.view; local network=v.controller.network
    if self.pending or not network or network.pendingCommand or not cleanup and not self:canRequest() then return false end
    local State=require('game.coop_range_state')
    local expected={}; for _,scope in ipairs(State.scopes(v.runtime.saveData,'companion',self.spotId,name,args)) do
        expected[scope]=v.runtime.saveData.coop.revisions[scope] or 0
    end
    local id,reason=network:submitCommand(name,args,self.epoch,expected)
    if not id then self.notice='Practice is currently unavailable. Try again when ready.'; return false,reason end
    self.pending={id=id,name=name,args=args,network=network,epoch=v.epoch}
    self.notice='Waiting for the host to save this action...'
    return true
end
function Panel:close()
    self:suspend(); self.wantRelease=true
    if self.leaseId and not self.pending then return self:submit('range.release',{leaseId=self.leaseId},true) end
    if not self.pending then self.opened=false; self.wantRelease=nil; self.view.runtime.shootingRange=nil end
    return true
end
function Panel:configure(action,extra)
    local s=self:state(); if not s or not self:canAct() then return false end
    local args={leaseId=self.leaseId,roundRevision=s.roundRevision,action=action}
    for key,value in pairs(extra or {}) do args[key]=value end
    self:suspend(); return self:submit('range.configure',args)
end
function Panel:fire()
    local s=self:state(); if not s or not self:canAct() or s.phase~='play' or s.time<=0
        or (s.cooldown or 0)>0 or (s.reloadTimer or 0)>0 or (s.loaded or 0)<=0 then return false end
    local x,y=Range.canonicalAim(self.model,self.pose.aimX,self.pose.aimY)
    x=math.max(0,math.min(1000000,math.floor(x/960*1000000+.5)))
    y=math.max(0,math.min(1000000,math.floor(y/720*1000000+.5)))
    return self:submit('range.fire',{leaseId=self.leaseId,roundRevision=s.roundRevision,
        weaponId=s.itemId or s.weapon,x=x,y=y})
end
function Panel:aim(x,y,touch)
    if not self.model or self.model.phase~='play' then return false end
    Range.mousemoved(self.model,x,y,touch)
    self.pose.aimX,self.pose.aimY=self.model.aimX,self.model.aimY
    self.pose.touchAim=self.model.touchAim
    return true
end
function Panel:setAim(aiming)
    if not self.model or not Range.setAim(self.model,aiming) then return false end
    self.pose.aimMode=self.model.aimMode
    self.pose.aimX,self.pose.aimY,self.pose.touchAim=self.model.aimX,self.model.aimY,self.model.touchAim
    return true
end
function Panel:intent(intent)
    if not intent then return true end
    local action=intent.action
    if action=='release' then return self:close() end
    if action=='releaseHeld' then self:suspend(); return true end
    if action=='pointer' then return self:aim(intent.x,intent.y,intent.touch) end
    if action=='row' then self.pose.menuRow=((self.pose.menuRow-1+(intent.direction or 1))%6)+1
    elseif action=='aim' then
        self:setAim(intent.value==true or intent.value==nil and self.pose.aimMode~='sights')
    elseif action=='monocular' then
        if self.pose.hasMonocular then self.pose.monocularActive=not self.pose.monocularActive end
    elseif action=='fire' then
        if intent.x then self:aim(intent.x,intent.y,false) end
        return self:fire()
    elseif action=='configure' then
        if intent.row then self.pose.menuRow=intent.row end
        return self:configure('change',{kind=intent.kind,direction=intent.direction})
    elseif action=='start' or action=='setup' or action=='mode' then
        return self:configure(action,action=='mode' and {direction=1} or nil)
    elseif action=='reload' or action=='ammo' then
        local s=self:state(); if not self:canAct() then return false end
        self:suspend(); return self:submit('range.'..action,{leaseId=self.leaseId,roundRevision=s.roundRevision,weaponId=s.itemId or s.weapon})
    end
    if self.model then
        self.model.menuRow=self.pose.menuRow; self.model.aimMode=self.pose.aimMode; self.model.monocularActive=self.pose.monocularActive==true
    end
    return true
end
function Panel:sync()
    local s=self:state(); local v=self.view
    if not s then self.model=nil; return end
    local identity=s.spotId..':'..s.roundRevision..':'..tostring(s.itemId or s.weapon)..':'..s.phase
    if self.identity~=identity then self:suspend(); self.identity=identity; self.modelRevision=nil end
    if self.modelRevision~=v.revision then
        self.pose.hasMonocular=Range.hasMonocular(v.runtime.saveData)
        if not self.pose.hasMonocular then self.pose.monocularActive=false end
        self.model=Range.presentation(s,self.pose); self.modelRevision=v.revision
        self.pose.aimX,self.pose.aimY,self.pose.touchAim=self.model.aimX,self.model.aimY,self.model.touchAim
    end
    v.runtime.shootingRange=self.opened and self.model or nil
end
function Panel:update(dt)
    if not self.opened and not self.pending then return end
    local v=self.view; local network=v.controller.network
    if self.epoch~=v.epoch or self.network~=network or v.runtime.scene~='stop' or Life.active(v.runtime.saveData) then
        self:suspend(); self.opened=false; self.pending=nil; self.leaseId=nil; self.wantRelease=nil; self.model=nil; v.runtime.shootingRange=nil; return
    end
    local p=self.pending; local reply=network and network.lastCommandResult
    if p and reply and reply.requestId==p.id then
        if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then
            self:suspend(); self.notice='Waiting for the host to finish saving...'
        elseif not reply.ok or reply.durable and v.runtime.saveData.coop.revision>=reply.revision then
            self.pending=nil; self.lastOutcome=reply; self.notice=nil
            local result=reply.details or reply.result
            if not reply.ok then
                self:suspend(); self.notice='The practice session changed. Review it and try again.'
                if reply.reason=='lease_expired' or reply.reason=='lease_owner' or reply.reason=='activity_changed' then self.leaseId=nil end
                if p.name=='range.acquire' then
                    self.leaseId=nil; self.serverPaused=nil
                    if retryAcquire[reply.reason] then
                        self.acquireFailures=(self.acquireFailures or 0)+1
                        self.acquireRetryAt=self:now()+math.min(4,.5*2^(self.acquireFailures-1))
                        self.acquireBlocked=self.acquireFailures>=6
                        self.notice=self.acquireBlocked and 'Practice cannot reconnect yet. RETURN to retry or E to leave.'
                            or 'Reconnecting to your practice lane...'
                    else self.opened=false; v.runtime.shootingRange=nil end
                elseif p.name=='range.release' and (reply.reason=='lease_expired' or reply.reason=='lease_owner') then
                    self.opened=false; self.wantRelease=nil; self.model=nil; v.runtime.shootingRange=nil; return
                end
            elseif result and result.actorId=='companion' and result.spotId==self.spotId then
                if p.name=='range.acquire' then
                    self.leaseId=result.leaseId; self.expiresAt=self:now()+(result.expiresIn or 0)
                    self.leaseEpoch=v.epoch; self.leaseNetwork=network; self.leaseMotionId=v.motionId
                    self.serverPaused=result.paused==true
                    self.acquireFailures=0; self.acquireBlocked=false; self.acquireRetryAt=nil
                elseif p.name=='range.release' then
                    self.opened=false; self.leaseId=nil; self.wantRelease=nil; self.model=nil; v.runtime.shootingRange=nil; return
                elseif p.name=='range.fire' and result.fired then
                    Shooting.playReport(result.weapon,self.c.catalog,v.runtime.saveData)
                elseif p.name=='range.configure' and p.args.action=='pause' and type(result.paused)=='boolean' then
                    self.serverPaused=result.paused; self:suspend()
                end
            end
            self.modelRevision=nil
        end
    end
    self:sync()
    if self.wantRelease and not self.pending then self:close(); return end
    if not self.opened then return end
    if self:canManage() and not self.acquireBlocked and (not self:checkedLease() or self.expiresAt-self:now()<8) then
        if self:now()>=(self.acquireRetryAt or 0) then
            self.acquireRetryAt=self:now()+1; self:suspend(); self:submit('range.acquire',{spotId=self.spotId},true); return
        end
    end
    local s=self:state()
    if self:canManage() and self:checkedLease() and self.serverPaused~=self:desiredPaused() then
        self:suspend()
        self:submit('range.configure',{leaseId=self.leaseId,roundRevision=s.roundRevision,action='pause',paused=self:desiredPaused()},true)
        return
    end
    if self:desiredPaused() or self.serverPaused~=false then self:suspend(); return end
    if self.model then Range.updatePresentation(self.model,math.min(.08,dt)) end
    if self.model and self.model.phase=='play' and v.ready and self:checkedLease() then
        local settings=Accessibility.aimSettings(v.runtime.saveData)
        local px,py=self.aimPad:step(dt,self.pose,960,720,{left=30,top=55,right=930,bottom=625},
            settings,settings.aimAssist>0 and self.aimPad.aimTouch and AimTargets.range(self.model,960,720))
        if px then self:aim(px,py,false) end
    end
    if s and self:canAct() and s.phase=='play' and s.time<=0 then self:configure('complete'); return end
    if not self:canAct() then return end
    local bindings=self.c.bindings
    local x,y=bindings:axisValue('aim_x'),bindings:axisValue('aim_y')
    if self.model and (x~=0 or y~=0) then self:aim(self.pose.aimX+x*340*dt,self.pose.aimY+y*340*dt,false) end
    local trigger=bindings:axisValue('fire')>.35
    if not self.controllerReady then if not trigger then self.controllerReady=true end
    elseif trigger and not self.controllerFire then self.held.controller=true; self:fire()
    elseif not trigger then self.held.controller=nil end
    self.controllerFire=trigger
    local ads=bindings:axisValue('ads')>.35
    if ads~=self.controllerADS then self:setAim(ads) end
    self.controllerADS=ads
    if s and s.phase=='play' and s.fireMode=='auto' and next(self.held) then self:fire() end
end
function Panel:keypressed(key)
    if key=='f8' then self.view.controller:open(); self:suspend(); return true end
    if key=='p' then self.paused=not self.paused; self:suspend(); return true end
    if key=='e' or key=='escape' then self:close(); return true end
    if self.acquireBlocked and key=='return' then
        self.acquireFailures=0; self.acquireBlocked=false; self.acquireRetryAt=nil; self.notice=nil; self:suspend(); return true
    end
    if not self.model then if key=='escape' then self:close() end; return true end
    if self.paused then return true end
    local intent=Range.inputIntent(self.model,'keypressed',key)
    if intent and intent.action=='fire' and self:canAct() then self.held.keyboard=true end
    self:intent(intent); return true
end
function Panel:keyreleased(key) if key=='space' then self.held.keyboard=nil end; return true end
function Panel:gamepadpressed(button)
    local key=self.c.bindings:translateButton(button,'shooting_range')
    self.controllerKeys=self.controllerKeys or {}; self.controllerKeys[button]=key
    if key then return self:keypressed(key) end; return true
end
function Panel:gamepadreleased(button)
    local key=self.controllerKeys and self.controllerKeys[button]
    if self.controllerKeys then self.controllerKeys[button]=nil end
    if key then return self:keyreleased(key) end; return true
end
function Panel:pointer(x,y,button)
    if button==1 and inside(menuRect,x,y) then return self:keypressed('f8') end
    if button==1 and inside(pauseRect,x,y) then return self:keypressed('p') end
    if not self.model or self.paused then return true end
    local intent=Range.inputIntent(self.model,'mousepressed',x,y,button)
    if intent and intent.action=='fire' and self:canAct() then self.held.mouse=true end
    self:intent(intent); return true
end
function Panel:mousemoved(x,y) self:aim(x,y,false); return true end
function Panel:mousereleased(button)
    if button==1 then self.held.mouse=nil elseif button==2 then self:intent({action='aim',value=false}) end
    return true
end
function Panel:touchpressed(id,x,y)
    if inside(menuRect,x,y) then return self:keypressed('f8') end
    if inside(pauseRect,x,y) then return self:keypressed('p') end
    if not self.model or self.paused then return true end
    local intent=Range.inputIntent(self.model,'mousepressed',x,y,4)
    if self.model.phase=='play' and ShooterPad.hit(x,y,960,720) then
        if not self.view.ready or self:desiredPaused() or not self:checkedLease() or self.serverPaused~=false then return true end
        local action=self.aimPad:press(id,x,y,960,720)
        if action then
            if action=='aim' then self.aimTouch=id; self.pose.touchAim=nil; self.model.touchAim=nil
            elseif action=='fire' then self.held.pad=true; self:fire() end
            return true
        end
    end
    if intent and intent.action=='pointer' and self.model.phase=='play' then
        if not self.aimTouch then self.aimTouch=id; self.touches[id]='aim'; self:intent(intent)
        elseif id~=self.aimTouch and not self.fireTouch and self:canAct() then self.fireTouch=id; self.touches[id]='fire'; self.held.touch=true; self:fire() end
    elseif intent and intent.action=='fire' then
        if not self.fireTouch and self:canAct() then self.fireTouch=id; self.touches[id]='fire'; self.held.touch=true; self:intent(intent) end
    else self:intent(intent) end
    return true
end
function Panel:touchmoved(id,x,y)
    if self.aimPad:move(id,x,y,960,720) then return true end
    if id==self.aimTouch then self:aim(x,y,true) end; return true
end
function Panel:touchreleased(id)
    local action=self.aimPad:release(id)
    if action then
        if action=='fire' then self.held.pad=nil end
        if self.aimTouch==id then self.aimTouch=nil end
        return true
    end
    if id==self.aimTouch then self.aimTouch=nil; self.pose.touchAim=nil end
    if id==self.fireTouch then self.fireTouch=nil; self.held.touch=nil end
    self.touches[id]=nil; return true
end
function Panel:draw()
    local g=love.graphics
    if self.model then Range.draw(self.model,self.view.runtime.saveData,self.c.rangeAssets and self.c.rangeAssets(),self.view.ui,self.c.catalog,self.view.mobile.enabled)
    else g.setColor(.055,.038,.025,1); g.rectangle('fill',0,0,960,720) end
    if self.model and self.model.phase=='play' and self.view.mobile.enabled and not self:desiredPaused() then self.aimPad:draw(960,720) end
    g.setColor(.055,.038,.025,.96); g.rectangle('fill',menuRect.x,menuRect.y,menuRect.w,menuRect.h,6,6)
    g.setColor(1,.89,.68,1)
    Typography.drawText(g,'LOCAL PLAY  [F8]',menuRect.x+4,menuRect.y+2,menuRect.w-8,menuRect.h-4,{scale=.8,minScale=.6,align='center',valign='center'})
    g.setColor(.18,.12,.075,.98); g.rectangle('fill',pauseRect.x,pauseRect.y,pauseRect.w,pauseRect.h,6,6)
    g.setColor(.88,.70,.43,1); g.rectangle('line',pauseRect.x,pauseRect.y,pauseRect.w,pauseRect.h,6,6)
    g.setColor(1,.93,.76,1)
    local pauseLabel=self.paused and 'RESUME' or 'PAUSE'
    if not self.view.mobile.enabled then pauseLabel=pauseLabel..'  [P]' end
    Typography.drawText(g,pauseLabel,pauseRect.x+4,pauseRect.y+2,pauseRect.w-8,pauseRect.h-4,
        {scale=.8*Accessibility.textScale(self.view.runtime.saveData),minScale=.6,align='center',valign='center'})
    if self.notice or self.paused then
        g.setColor(.055,.038,.025,.96); g.rectangle('fill',190,145,580,46,6,6); g.setColor(1,.89,.68,1)
        Typography.drawText(g,self.paused and 'Your controls are paused. P / START to resume.' or self.notice,
            198,148,564,40,{scale=.8*Accessibility.textScale(self.view.runtime.saveData),minScale=.6,align='center',valign='center'})
    end
end
function Panel:release() self:suspend(); self.opened=false; self.pending=nil; self.model=nil; self.leaseId=nil; self.view.runtime.shootingRange=nil end
return Panel
