-- A private shooter canvas. Only validated host commands change gameplay.
local Schema=require('game.save_schema')
local Sessions=require('game.coop_shooter_sessions')
local Shooting=require('game.first_person_shooting')
local Actions=require('game.first_person_weapon_actions')
local Commands=require('game.coop_guns')
local State=require('game.coop_ambush_state')
local Scene=require('game.train_ambush_scene')
local Rules=require('game.train_ambush_rules')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local ShooterPad=require('game.mobile_shooter_controls')
local Panel={}; Panel.__index=Panel
local controls={{key='space',label='FIRE\nLMB / SPACE'},{key='aim',label='AIM\nRMB'},
    {key='r',label='RELOAD\nR'},{key='c',label='COVER\nC'},{key='tab',label='WEAPON\nTAB'},
    {key='v',label='MODE\nV'},{key='p',label='PAUSE\nP'},{key='menu',label='LOCAL PLAY\nF8'}}
local AUDIO_FRESH_SECONDS=.35
local function clockValue(value) return type(value)=='number' and value==value and value>=0 and value<=1e12 end
local function protectionValue(value) return clockValue(value) and value<=1024 and value==math.floor(value) end
local function inside(r,x,y) return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
function Panel.new(view,c) return setmetatable({view=view,c=c,held={},touches={},controllerReady=false,aimPad=ShooterPad.new()},Panel) end
function Panel:state()
    local data=self.view.runtime.saveData
    local state=data and data.trainAmbush
    return data and data.scene=='train' and state and state.active and state or nil
end
function Panel:available() return self:state()~=nil end
function Panel:canAct()
    local v=self.view; local s=self:state(); local network=v.controller.network
    local frame=v.controller.motionFrame
    return s and (s.phase=='approach' or s.phase=='combat') and not s.outcome and v.ready and v.focused
        and not v.controller.menuOpen and not self.paused and not self.pending and network and not network.pendingCommand
        and v.motionId and frame and frame.sceneEpoch==v.epoch and frame.motionId==v.motionId and frame.ready
        and v.runtime.saveData.health>1 and not v.runtime.inventoryOpen and not v.runtime.tradeOpen
        and not v.runtime.guestActivityOpen
end
function Panel:suspend()
    self.aimPad:cancel()
    self.held={}; self.touches={}; self.controllerReady=false; self.controllerFire=false; self.controllerADS=false
    if self.gun then Shooting.setADS(self.gun,false) end
end
function Panel:options()
    local options={}
    for _,entry in ipairs(Shooting.weaponOptions(self.view.runtime.saveData,self.c.catalog)) do
        if not entry.borrowed then options[#options+1]=entry end
    end
    return options
end
function Panel:sync()
    local s=self:state(); local v=self.view
    if not s then
        if self.encounterId then self:suspend(); self.gun=nil; self.encounterId=nil; self.pending=nil; self.notice=nil; self.impact=nil end
        self.enemyAudio=nil
        return
    end
    if self.encounterId~=s.entityId or self.epoch~=v.epoch then
        self:suspend(); self.gun=nil; self.pending=nil; self.notice=nil; self.impact=nil; self.paused=false; self.enemyAudio=nil
        self.encounterId=s.entityId; self.epoch=v.epoch; self.seenRevision=nil
        for _,key in ipairs({'inventoryOpen','tradeOpen','trainUpgradeOpen','peopleOpen','guestActivityOpen'}) do v.runtime[key]=false end
        if v.inventory then v.inventory:cancelDrag() end
        if v.objects then v.objects:suspend() end
        if v.people then v.people:close() end
        if v.activities then v.activities:suspend() end
    end
    if self.seenRevision~=v.revision then
        local owner=s.shooterSessions and s.shooterSessions.companion; local saved=owner and owner.weaponSession
        if saved then
            local old=self.gun; local gun=Sessions.view(assert(Schema.copy(saved)),960,720)
            if old then
                Shooting.setAim(gun,old.aimX,old.aimY); Shooting.setADS(gun,old.ads); gun.touchAim=old.touchAim
            end
            self.gun=gun
        else self.gun=nil end
        self.seenRevision=v.revision
    end
end
-- Only real enemy fire lowers global carriage protection, exactly two points
-- per shot. Observe reliable facts even while muted; never queue old audio.
-- One distant report represents a fresh batch, not a reconstructed shot log.
function Panel:observeEnemyFire(s)
    local v=self.view; local network=v.controller.network
    if not clockValue(s.clock) or not protectionValue(s.protection) or not protectionValue(s.maxProtection)
        or s.protection>s.maxProtection or type(v.revision)~='number' then self.enemyAudio=nil; return end
    local now=self.c.clock and self.c.clock() or love.timer and love.timer.getTime and love.timer.getTime() or v.elapsed or 0
    if not clockValue(now) then self.enemyAudio=nil; return end
    local old=self.enemyAudio
    local function baseline()
        self.enemyAudio={network=network,sessionId=network and network.sessionId,epoch=v.epoch,encounterId=s.entityId,
            motionId=v.motionId,revision=v.revision,clock=s.clock,protection=s.protection,maximum=s.maxProtection,received=now}
    end
    if not old or old.network~=network or old.sessionId~=(network and network.sessionId) or old.epoch~=v.epoch
        or old.encounterId~=s.entityId or old.motionId~=v.motionId or old.maximum~=s.maxProtection then baseline(); return end
    if v.revision<=old.revision then return end
    -- Ignore a reordered clock/refill instead of letting it turn the next
    -- duplicate protection value into another apparent enemy shot.
    if s.clock<old.clock or s.protection>old.protection then old.revision=v.revision; return end
    local dropped=old.protection-s.protection; local elapsed=now-old.received
    local fresh=elapsed>=0 and elapsed<=AUDIO_FRESH_SECONDS and s.clock-old.clock<=AUDIO_FRESH_SECONDS
    baseline()
    local frame=v.controller.motionFrame; local p=self.pending
    local reply=network and network.lastCommandResult
    local saving=p and reply and reply.requestId==p.id
        and (reply.savePending or reply.reason=='save_pending' or reply.reason=='busy')
    if dropped<=0 or dropped%2~=0 or not fresh or s.phase~='combat' or s.outcome
        or not v.ready or not v.focused or self.paused or v.controller.menuOpen or saving
        or not network or network.status~='ready' or not frame or not frame.ready
        or frame.sceneEpoch~=v.epoch or frame.motionId~=v.motionId then return end
    Shooting.playReport('frontier-22-lever-rifle',self.c.catalog,v.runtime.saveData,true)
end
function Panel:statusHint(s,pose)
    local data=self.view.runtime.saveData
    if self.pending and self.notice then return self.notice end
    if s.phase=='result' then return 'Encounter ended. The host will continue when ready.' end
    if s.phase=='depart' or s.outcome then return 'The convoy is falling behind. The host will continue when ready.' end
    if self.paused then return 'Your controls are paused. The encounter continues. P / START to resume.' end
    if data.health<=1 then return 'You are wounded. The host controls how the journey continues.' end
    return self.notice or s.phase=='approach' and 'The convoy is pulling alongside.'
        or pose.cover and 'IN COVER - the carriage is still taking fire.'
        or 'Help stop the bandits. The host controls withdrawal and the journey.'
end
function Panel:submit(name,extra)
    if not self:canAct() then return false end
    local v=self.view; local s=self:state()
    local args={mode='ambush',encounterId=s.entityId}
    if name~='gun.cover' then args.weaponId=self.gun and self.gun.itemId end
    for key,value in pairs(extra or {}) do args[key]=value end
    local expected={}; for _,scope in ipairs(Commands.scopes(v.runtime.saveData,'companion')) do
        expected[scope]=v.runtime.saveData.coop.revisions[scope] or 0
    end
    local id,reason=v.controller.network:submitCommand(name,args,v.epoch,expected)
    if not id then self.notice='Action unavailable. Wait for the host update.'; return false,reason end
    self.pending={id=id,epoch=v.epoch,encounterId=s.entityId,name=name,
        x=self.gun and self.gun.aimX,y=self.gun and self.gun.aimY}
    self.notice='Waiting for the host to save this action...'; return true
end
function Panel:aim(x,y,touch)
    if not self.gun or self.paused then return end
    x,y=math.max(0,math.min(960,x)),math.max(0,math.min(720,y))
    if touch then Shooting.setTouchAim(self.gun,x,y,960,720) else Shooting.setAim(self.gun,x,y) end
end
function Panel:fire()
    local s=self:state(); local gun=self.gun
    if not self:canAct() or not gun or not gun.weapon or gun.fireMode=='safe' or s.phase~='combat' then return false end
    local owner=State.owner(s,'companion')
    if owner and (owner.cover or owner.coverProgress>0) or (gun.cooldown or 0)>0 or (gun.reloadTimer or 0)>0 then return false end
    if gun.magazine<=0 then return self:submit('gun.reload') end
    return self:submit('gun.fire',{x=math.floor(gun.aimX/960*Commands.POINT+.5),y=math.floor(gun.aimY/720*Commands.POINT+.5)})
end
function Panel:fireHeld(source,down)
    local previous=self.held[source]; self.held[source]=down or nil
    if down and not previous then return self:fire() end
end
function Panel:action(key)
    if key=='menu' or key=='f8' or key=='escape' or key=='acback' then self:suspend(); self.view.controller:open(); return true end
    if key=='p' then self.paused=not self.paused; self:suspend(); return true end
    if self.paused then if key=='return' or key=='space' then self.paused=false; self:suspend() end; return true end
    if not self:canAct() then return true end
    local s=self:state(); local owner=State.owner(s,'companion')
    if key=='space' then self:fireHeld('keyboard',true)
    elseif key=='r' then self:submit('gun.reload')
    elseif key=='c' then self:suspend(); self:submit('gun.cover',{cover=not (owner and owner.cover)})
    elseif key=='v' then self:suspend(); self:submit('gun.mode')
    elseif key=='aim' and self.gun and not (owner and owner.cover) then Shooting.setADS(self.gun,not self.gun.ads)
    elseif key=='tab' then
        local options=self:options(); if #options==0 then return true end
        local selected=0; for i,entry in ipairs(options) do if self.gun and entry.itemId==self.gun.itemId then selected=i end end
        self:suspend(); self:submit('gun.select',{weaponId=options[selected%#options+1].itemId})
    end
    return true
end
function Panel:update(dt)
    self:sync(); local s=self:state(); if not s then return end
    local v=self.view; local p=self.pending; local reply=v.controller.network and v.controller.network.lastCommandResult
    if p and (p.epoch~=v.epoch or p.encounterId~=s.entityId) then self.pending=nil; p=nil end
    if p and reply and reply.requestId==p.id then
        if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then self.notice='Waiting for the host to finish saving...'
        elseif not reply.ok or reply.durable and v.runtime.saveData.coop.revision>=reply.revision then
            self.pending=nil; self.lastOutcome=reply; self.notice=nil
            if not reply.ok then
                self.notice=reply.reason=='stale_revision' and 'The encounter changed. Try this action again.'
                    or reply.reason=='reload' and 'Reload your weapon.' or 'This action is currently unavailable.'
            else
                local facts=reply.details or reply.result
                if facts and facts.actorId=='companion' and facts.encounterId==s.entityId and facts.fired then
                    Shooting.playReport(facts.weapon,self.c.catalog,v.runtime.saveData)
                    if facts.hit then self.impact={x=p.x,y=p.y,time=.22} end
                end
            end
        end
    end
    self:observeEnemyFire(s)
    if (s.outcome or s.phase=='depart' or s.phase=='result') and not self.pending then self.notice=nil end
    if not v.focused or v.controller.menuOpen or self.paused or s.phase=='result' then self:suspend() end
    if self.gun then Actions.update(self.gun,math.min(.1,dt)) end -- Private authored-frame clock only.
    if self.impact then self.impact.time=self.impact.time-dt; if self.impact.time<=0 then self.impact=nil end end
    if self.gun and v.ready and v.focused and not v.controller.menuOpen and not self.paused and not s.outcome then
        local px,py=self.aimPad:step(dt,self.gun,960,720)
        if px then self:aim(px,py) end
    end
    if self:canAct() then
        if not self.gun or not self.gun.weapon then
            local options=self:options(); if options[1] then self:submit('gun.select',{weaponId=options[1].itemId}) end
        else
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
end
function Panel:rect(index) local width=920/#controls; return {x=20+(index-1)*width,y=644,w=width-5,h=56} end
function Panel:pointer(x,y,button)
    if button==1 then
        for i,control in ipairs(controls) do if inside(self:rect(i),x,y) then
            if control.key=='space' then self:fireHeld('mouse',true) else self:action(control.key) end; return true
        end end
        self:aim(x,y); self:fireHeld('mouse',true)
    elseif button==2 and self.gun then self:aim(x,y); Shooting.setADS(self.gun,true) end
    return true
end
function Panel:mousemoved(x,y) if y<620 then self:aim(x,y) end; return true end
function Panel:mousereleased(button)
    if button==1 then self:fireHeld('mouse',false) elseif button==2 and self.gun then Shooting.setADS(self.gun,false) end; return true
end
function Panel:keypressed(key) return self:action(key) end
function Panel:keyreleased(key) if key=='space' then self:fireHeld('keyboard',false) end; return true end
function Panel:gamepadpressed(button)
    if button=='start' then return self:action('p') elseif button=='back' then return self:action('menu') end
    local key=self.c.bindings:translateButton(button,'last_stand_shootout'); if key then self:action(key) end; return true
end
function Panel:gamepadreleased(button)
    local key=self.c.bindings:translateButton(button,'last_stand_shootout'); if key=='space' then self:fireHeld('keyboard',false) end; return true
end
function Panel:touchpressed(id,x,y)
    if ShooterPad.hit(x,y,960,720) then
        local s=self:state(); local v=self.view
        if not self.gun or not s or s.outcome or self.paused or not v.ready or not v.focused or v.controller.menuOpen then return true end
        local action=self.aimPad:press(id,x,y,960,720)
        if action then
            if action=='aim' then self.gun.touchAim=nil elseif action=='fire' then self:fireHeld('pad',true) end
            return true
        end
    end
    for i,control in ipairs(controls) do if inside(self:rect(i),x,y) then
        self.touches[id]=control.key
        if control.key=='space' then self:fireHeld('touch:'..tostring(id),true) else self:action(control.key) end; return true
    end end
    self.touches[id]='aim'; self:aim(x,y,true); return true
end
function Panel:touchmoved(id,x,y)
    if self.aimPad:move(id,x,y,960,720) then return true end
    if self.touches[id]=='aim' then self:aim(x,y,true) end; return true
end
function Panel:touchreleased(id)
    local action=self.aimPad:release(id)
    if action then if action=='fire' then self:fireHeld('pad',false) end; return true end
    if self.touches[id]=='space' then self:fireHeld('touch:'..tostring(id),false) end
    self.touches[id]=nil; return true
end
function Panel:draw()
    local v=self.view; local s=self:state(); if not s then return end
    local data=v.runtime.saveData; local pose=State.view(s,'companion'); local g=love.graphics
    g.setFont(Typography.font(g)); Scene.draw(pose,960,720,Accessibility.ensure(data),self.impact)
    if self.gun and pose.coverProgress==0 and s.phase~='result' then
        Shooting.draw(self.gun,960,720); local x,y=self.gun.aimX,self.gun.aimY
        if not self.gun.ads then
            g.setColor(1,.94,.75,1); g.line(x-9,y,x-3,y); g.line(x+3,y,x+9,y); g.line(x,y-9,x,y-3); g.line(x,y+3,x,y+9)
        end
    end
    local function text(value,x,y,width,height,scale)
        Typography.drawText(g,value,x,y,width,height,{scale=(scale or .8)*Accessibility.textScale(data),minScale=.6,align='center',valign='center'})
    end
    g.setColor(.035,.025,.02,.95); g.rectangle('fill',16,12,928,54,6,6); g.setColor(1,.89,.68,1)
    local hull,maxHull=Rules.hullTotal(s)
    text('YOUR HEALTH '..math.ceil(data.health)..' / '..data.maxHealth,22,17,250,42)
    text('CARRIAGE '..s.protection..' / '..s.maxProtection,276,17,220,42)
    text('CONVOY '..math.ceil(hull)..' / '..maxHull,500,17,235,42); text('BANDITS '..Rules.crewTotal(s),738,17,190,42)
    g.setColor(.035,.025,.02,.95); g.rectangle('fill',0,577,960,143); g.setColor(1,.89,.68,1)
    local scope=s.shooterSessions and s.shooterSessions.companion; local gun=scope and scope.weaponSession
    local name=(gun and gun.weapon or 'No firearm'):gsub('%-',' '):upper()
    text(name..'   '..(gun and gun.magazine or 0)..' / '..(gun and data.ammo[gun.ammoType] or 0)..' ROUNDS   '
        ..(gun and ((gun.reloadTimer or 0)>0 and 'RELOADING' or (gun.fireMode or ''):upper()) or ''),25,578,910,29,.77)
    if v.mobile and v.mobile.enabled and not self.paused and s.phase~='result' then self.aimPad:draw(960,720) end
    local hint=self:statusHint(s,pose)
    text(hint,30,609,900,30,.72)
    for i,control in ipairs(controls) do
        local r=self:rect(i); g.setColor(.12,.075,.035,.96); g.rectangle('fill',r.x,r.y,r.w,r.h,5,5)
        g.setColor(.73,.49,.22,1); g.rectangle('line',r.x,r.y,r.w,r.h,5,5); g.setColor(1,.89,.68,1)
        text(control.label,r.x+2,r.y+2,r.w-4,r.h-4,.69)
    end
end
function Panel:release() self:suspend(); self.gun=nil; self.enemyAudio=nil; Scene.release(); Shooting.release() end
return Panel
