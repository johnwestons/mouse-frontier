-- A normal three-minute defense. Only the initial isolated save/equipment are
-- seeded. The pilot observes replicas and PNG masks and operates real inputs;
-- it never changes combat clocks, target timers, damage, morale, health or RNG.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Life=require('game.coop_last_stand_lifecycle')
local Window=require('game.window_scene'); local Viewport=require('game.viewport')
local Scene=require('game.last_stand_scene')
local Aim=require('game.mobile_weapon_aim'); local Positions=require('game.coop_last_stand_positions')
local Combat=require('game.coop_last_stand_state')
local app,c,started,finished,movementKey,oldKeyboard,stage
local lastReport=0; local lastInput=0; local capture; local captures={}
local ownItem,baseScrap,baseGoodwill,baseFood,denialId
local observedPhase={}; local lastInterior; local actionPending; local supplyStep=0
local reloadCovered=false; local routeStep=1; local retreats=0; local priorKills=0
local previousHold=0; local bothReadySeconds=0; local battleStarted; local defenseWall
local returnClockFirst,returnClockLast
local pressureArm,pressureSerial,pressureHealth,pressureIntegrity,pressureReady=false,nil,nil,nil,false
local directedShots={host=0,companion=0}; local directedSeen={}; local hostIncomingVisual=false
local guestPacketShots={host=0,companion=0}; local guestPacketSeen={}; local guestIncomingVisual=false
local guestCoveredHealth
local metrics={fire=0,hit=0,reload=0,cover=0,supply=0,firstFire=nil,lastFire=nil}
local pendingNames={}
local hostButtons={r={x=142,y=616,w=108,h=62},c={x=390,y=616,w=108,h=62},
    tab={x=638,y=616,w=148,h=62},space={x=812,y=616,w=130,h=62}}
local guestButtons={space=1,r=3,c=4,tab=5,l=7}
local function check(value,message) assert(value,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function button(key) app.keypressed(key); app.keyreleased(key) end
local function press(r)
    check(r,'missing control at '..tostring(stage)); local x,y=coords(r.x+r.w/2,r.y+r.h/2)
    if touch then app.touchpressed('control',x,y); app.touchreleased('control',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function click(id,text)
    app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); button('return') end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function note(name,result)
    if not result then return end
    if name=='gun.fire' and result.fired then
        metrics.fire=metrics.fire+1; metrics.hit=metrics.hit+(result.hit and 1 or 0)
        metrics.firstFire=metrics.firstFire or love.timer.getTime()-started
        metrics.lastFire=love.timer.getTime()-started
    elseif name=='gun.reload' and result.reloading then metrics.reload=metrics.reload+1
    elseif name=='gun.cover' and result.cover then metrics.cover=metrics.cover+1
    elseif name=='lastStand.supply' then metrics.supply=metrics.supply+1 end
end
local function finish()
    if finished then return end; finished=true; movementKey=nil
    check(app.quit()~=true,'application quit cancelled')
    print('LAN_SMOKE_OK role='..role..' lastStandPressure=true normalHoldSeconds=180 originalTargets=true'
        ..' actualInputs=true fire='..metrics.fire..' hits='..metrics.hit..' reloads='..metrics.reload
        ..' covers='..metrics.cover..' supplies='..metrics.supply..' input='..(touch and 'touch-with-host-supply-key' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime()
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if key==movementKey then return true end; return oldKeyboard(key,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        Save.remove(1); c.runtime.selectedSlot=1
        local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
        draft.lastStand={state='interior',originStop=12,returnX=270,returnY=490,
            holdElapsed=0,kills=0,enemyMorale=100,positionIntegrity=100,completedPhase=0,phaseCheckpoint=0}
        check(c.enterGame(draft),'canonical initial save seed failed')
        Items.write(c.runtime.saveData,nil,{kind='equipment',index=2},'frontier-556-carbine')
        c.runtime.saveData.ammo['556']=120
        check(Save.write(1,c.runtime.saveData),'isolated visible-slot seed failed')
        c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.lastStand=nil
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,why=place(data); if not ok then return ok,why end
            local own=Players.forActor(data,'companion')
            Items.write(own,nil,{kind='equipment',index=2},'frontier-556-carbine'); own.ammo['556']=120
            check(Items.ensure(data),'initial companion ownership failed'); return true
        end
        lp.port=port; c.runtime.state='slots'; menu(); click('host')
        check(lp.hostingIntent=='selecting' and not lp.menuOpen,'title hosting intent failed')
        app.draw(); press(c.ui.slots[1])
        check(lp.network and c.session.networkMode=='host' and c.runtime.selectedSlot==1,'slot entry did not host')
        back()
        -- Observe production command receipts without changing the request/result.
        local submit=lp.context.commands.submit
        lp.context.commands.submit=function(name,args)
            local reply=submit(name,args)
            if reply and reply.ok then note(name,reply.result or reply.details) end
            return reply
        end
        stage='interior'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        menu(); click('address','127.0.0.1:'..port); click('name','Pressure friend'); click('join')
        check(lp.network,'guest join failed '..tostring(lp.error)); stage='joining'
    end
end
local function stopWalk()
    movementKey=nil
    if touch and role=='guest' then app.touchreleased('walk',0,0) end
end
local function hostWalk(state,x,y)
    local p=state.scene.player
    if math.abs(p.x-x)<12 and math.abs(p.y-y)<12 then stopWalk(); return true end
    if touch then
        if not state.scene.moveTarget then local gx,gy=coords(x,y); app.touchpressed('walk-to',gx,gy); app.touchreleased('walk-to',gx,gy) end
    else
        movementKey=math.abs(p.y-y)>=12 and (p.y>y and 'w' or 's') or (p.x>x and 'a' or 'd')
    end
    return false
end
local function guestWalk(view,x,y)
    local frame=c.ui.localPlay.motionFrame; local p=frame and frame.companion
    if not p then return false end
    local px,py=p.x/1000,p.y/1000
    if math.abs(px-x)<12 and math.abs(py-y)<12 then stopWalk(); return p.vx==0 and p.vy==0 end
    local key=math.abs(py-y)>=12 and (py>y and 'w' or 's') or (px>x and 'a' or 'd')
    if touch then
        app.touchreleased('walk',0,0); app.draw(); local stick=view.mobile.joystick
        local gx,gy=coords(stick.x,stick.y); app.touchpressed('walk',gx,gy)
        gx,gy=coords(stick.x+(key=='d' and 1 or key=='a' and -1 or 0)*stick.radius*.95,
            stick.y+(key=='w' and -1 or key=='s' and 1 or 0)*stick.radius*.95)
        app.touchmoved('walk',gx,gy,0,0)
    else movementKey=key end
    return false
end
local function interact()
    if touch then
        press(role=='host' and {x=330,y=654,w=300,h=44} or {x=580,y=580,w=350,h=45})
    else button('e') end
    lastInput=love.timer.getTime()
end
-- Every candidate is checked against the same authored aperture pixels and
-- target ellipse used by production fireAt. There is no staged target or aim.
local aimCache={}
local function aperture(window,slot)
    local key=window..':'..slot
    if aimCache[key]~=nil then local p=aimCache[key]; return p and p[1],p and p[2] end
    local layout=Window.layout(window,960,720); local x,y,w,h=Window.slotRect(layout,slot)
    local function checked(px,py)
        -- Test the quantized point that will actually reach authority, too.
        px=math.floor(px/960*1000000+.5)/1000000*960
        py=math.floor(py/720*1000000+.5)/1000000*720
        if Window.targetHit(layout,slot,px,py) and Window.pointOpen(window,960,720,px,py) then
            aimCache[key]={px,py}; return px,py
        end
    end
    local cx,cy=Window.slotPosition(layout,slot); local ax,ay=checked(cx,cy)
    if ax then return ax,ay end
    for row=0,16 do for col=0,16 do
        local px,py=x+w*(.1+.8*col/16),y+h*(.1+.8*row/16)
        ax,ay=checked(px,py); if ax then return ax,ay end
    end end
    aimCache[key]=false
end
local function targetAim(q,window)
    local best,bx,by,priority
    for _,target in ipairs(q.targets or {}) do
        if target.status=='appearing' or target.status=='exposed' or target.status=='firing' then
            local x,y=aperture(window,target.slot)
            if x then
                local score=(target.status=='firing' and 0 or target.status=='exposed' and 1 or 2)+(target.timer or 0)*.01
                if not priority or score<priority then best,bx,by,priority=target,x,y,score end
            end
        end
    end
    return best,bx,by
end
local function action(panel,key)
    if touch and role=='guest' then press(panel:rect(guestButtons[key]))
    elseif touch and hostButtons[key] then press(hostButtons[key])
    else button(key) end
    lastInput=love.timer.getTime()
end
local function fire(panel,gun,x,y)
    if touch then
        local ax,ay=Aim.gripForAim(gun.weapon,gun.ads and 'sights' or 'hip',x,y,960,720)
        local gx,gy=coords(ax,ay); app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0)
        action(panel,'space'); app.touchreleased('aim',gx,gy)
    else
        local gx,gy=coords(x,y); app.mousemoved(gx,gy,0,0,false)
        app.mousepressed(gx,gy,1,false); app.mousereleased(gx,gy,1,false); lastInput=love.timer.getTime()
    end
end
local function pilot(q,gun,owner,panel)
    if not gun or not owner or q.combat.result or love.timer.getTime()-lastInput<.12 then return end
    ownItem=ownItem or gun.itemId
    -- Exercise the real supply control and restore the exact personal firearm.
    -- Owned ammunition remains available; no test-created loan record is used.
    if supplyStep==0 and metrics.fire>=4 and gun.cooldown<=0 and gun.reloadTimer<=0 then
        action(panel,'l'); supplyStep=1; return
    elseif supplyStep==1 then
        if gun.borrowed then supplyStep=2
        elseif gun.cooldown<=0 and gun.reloadTimer<=0 and love.timer.getTime()-lastInput>.6 then action(panel,'l') end
        return
    elseif supplyStep==2 then
        if not gun.borrowed then check(gun.itemId==ownItem,'supplies replaced personal firearm'); supplyStep=3 end
        if gun.borrowed and gun.cooldown<=0 and gun.reloadTimer<=0 and love.timer.getTime()-lastInput>.6 then action(panel,'tab') end
        return
    end
    local own=role=='host' and c.runtime.saveData or c.ui.localPlay.clientView.runtime.saveData
    local scope=gun.borrowed and (role=='host' and q or q.shooterSessions.companion)
    local rounds=gun.borrowed and scope.loanAmmo or own.ammo[gun.ammoType]
    if (rounds or 0)<=0 and gun.cooldown<=0 and gun.reloadTimer<=0 then action(panel,'l'); return end
    if gun.magazine<=0 and gun.reloadTimer<=0 then
        if not owner.ducking then action(panel,'c'); reloadCovered=true
        else action(panel,'r') end
        return
    end
    if gun.reloadTimer>0 then return end
    if owner.ducking then
        -- A phase can end while this defender is reloading in cover. Resume
        -- exposure after that preserved reload rather than waiting for a local
        -- previous-phase flag that was deliberately cleared at the boundary.
        action(panel,'c'); reloadCovered=false
        return
    end
    if owner.coverProgress>0 or gun.cooldown>0 then return end
    local target,x,y=targetAim(q,owner.windowId)
    if target then fire(panel,gun,x,y) end
end
local function hostCoverDrill(data,state,host,guest)
    local q=data.lastStand; local combat=q.combat; local owners=combat.defenders
    local own=owners.host; local peer=owners.companion
    if host and not own.ducking and love.timer.getTime()-lastInput>.12 then action(nil,'c') end
    if not pressureArm and host and guest and peer and own.ducking and peer.ducking
        and own.coverProgress>=1 and peer.coverProgress>=1 then
        pressureArm=combat.clock; pressureSerial=combat.enemyShots
        pressureHealth={host=data.health,companion=data.players.companion.health}
        pressureIntegrity=q.positionIntegrity
        file('host.pressure.armed',pressureSerial)
        print('LAN_PRESSURE_COVER_ARM clock='..pressureArm..' serial='..pressureSerial)
    end
    if not pressureArm then return end
    check(data.health==pressureHealth.host and data.players.companion.health==pressureHealth.companion,
        'actual covered enemy fire changed defender health')
    check(q.positionIntegrity==pressureIntegrity,'actual covered enemy fire damaged position integrity')
    for _,event in ipairs(Combat.effectEvents(state.shootout)) do
        if event.serial>pressureSerial and not directedSeen[event.serial] then
            directedSeen[event.serial]=true
            check(not event.hit,'covered actor received an actual enemy hit')
            directedShots[event.actorId]=directedShots[event.actorId]+1
        end
    end
    for _,shot in ipairs(state.shootout.incomingShots or {}) do
        if shot.actorId=='host' and shot.serial>pressureSerial then hostIncomingVisual=true end
    end
    if combat.clock-pressureArm>=12 and directedShots.host>=1 and directedShots.companion>=1
        and hostIncomingVisual and file('guest.pressure.observed') then
        check(combat.enemyShots>pressureSerial,'normal production enemies did not actually fire')
        pressureReady=true; file('host.pressure.ready','true'); capture='covered-incoming-pressure'
        print('LAN_PRESSURE_COVER_OBSERVED hostDirected='..directedShots.host..' guestDirected='..directedShots.companion
            ..' actualEnemyShots='..combat.enemyShots..' coveredSeconds='..(combat.clock-pressureArm)
            ..' hostHealth='..data.health..' guestHealth='..data.players.companion.health)
    end
end
local function guestCoverDrill(view,panel,q)
    -- Host may start exposing its actor as soon as it publishes completion.
    -- Stop the covered-only assertions at that shared boundary as well.
    if file('host.pressure.ready') then pressureReady=true; return end
    local owner=q.combat.defenders.companion
    if panel:canAct() and owner and not owner.ducking and love.timer.getTime()-lastInput>.12 then action(panel,'c') end
    local serial=tonumber(file('host.pressure.armed')); if not serial or not owner then return end
    if owner.ducking and owner.coverProgress>=1 then
        guestCoveredHealth=guestCoveredHealth or view.runtime.saveData.health
        check(view.runtime.saveData.health==guestCoveredHealth,'covered guest reliable health changed')
        local frame=c.ui.localPlay.lastStandEffects and c.ui.localPlay.lastStandEffects:get()
        for _,event in ipairs(frame and frame.events or {}) do
            if event.serial>serial and not guestPacketSeen[event.serial] then
                guestPacketSeen[event.serial]=true; check(not event.hit,'checked covered effect claimed an enemy hit')
                guestPacketShots[event.actorId]=guestPacketShots[event.actorId]+1
            end
        end
        local visual=panel:visualEffects()
        for _,shot in ipairs(visual.incomingShots or {}) do
            if shot.actorId=='companion' then guestIncomingVisual=true end
        end
        if #(visual.impactBursts or {})>0 then guestIncomingVisual=true end
        if guestPacketShots.host>=1 and guestPacketShots.companion>=1 and guestIncomingVisual then
            file('guest.pressure.observed','hostPacketShots='..guestPacketShots.host..' guestPacketShots='..guestPacketShots.companion
                ..' ownVisual=true coveredHealth='..guestCoveredHealth)
            capture='covered-incoming-pressure'
        end
    end
end
local function hostUpdate(dt)
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local q=data.lastStand; local state=c.runtime.lastStand
    if lp:pending() then menu(); click('approve'); check(not lp.error,'approval failed '..tostring(lp.error)); back() end
    if state and state.mode=='interior' and not q.victory then
        stage='interior'
        if lastInterior~=q.lifecycle.revision then
            lastInterior=q.lifecycle.revision; routeStep=1; reloadCovered=false
            if q.holdElapsed<previousHold then retreats=retreats+1; check(retreats<=2,'natural pressure required more than two retries') end
            check(q.kills>=priorKills,'natural intermission/retry lost kills')
            priorKills=q.kills
        end
        local reached=routeStep==1 and hostWalk(state,480,285) or routeStep==2 and hostWalk(state,360,285)
        if reached then routeStep=routeStep+1 end
        local sceneAction=routeStep>=3 and Scene.action(state.scene,false)
        if routeStep>=3 and (not sceneAction or sceneAction.id~='window-wide') then routeStep=2 end
        if routeStep>=3 and file('guest.selected.'..q.lifecycle.revision)
            and (not q.intermission or q.intermission~=2 or file('guest.story.denied'))
            and not state.handoff and not state.pendingPosition and not state.pendingProgression
            and love.timer.getTime()-lastInput>.7 then
            interact()
        end
    elseif state and state.mode=='shootout' then
        stopWalk(); stage='defense'; battleStarted=battleStarted or love.timer.getTime()
        previousHold=q.holdElapsed; priorKills=q.kills
        observedPhase[q.combat.stage]=true
        local bindings=lp.authority.bindings; local activity=lp.authority.activityState; local now=lp.context.clock()
        local host=Positions.occupied(data,activity,bindings,now,'host')
        local guest=Positions.occupied(data,activity,bindings,now,'companion')
        if host and guest then bothReadySeconds=bothReadySeconds+dt end
        if not c.session.checkpointPending and not state.paused then
            if not pressureReady then hostCoverDrill(data,state,host,guest)
            elseif host then pilot(q,state.shootout.gun,q.combat.defenders.host,nil) end
        end
    elseif state and state.mode=='interior' and q.victory then
        stopWalk(); stage=q.residentChecked and 'fox' or 'resident'
        if not defenseWall then
            defenseWall=love.timer.getTime()-battleStarted
            check(q.holdElapsed>=180 and q.kills>=15 and q.enemyMorale==0,'natural victory bypassed defense requirements')
            check(defenseWall>=180,'normal three-minute simulation completed faster than wall time')
            check(observedPhase[1] and observedPhase[2] and observedPhase[3] and observedPhase[4],'normal phases were skipped')
            check(bothReadySeconds>=30,'two checked defenders did not share sustained live simulation')
            check(pressureReady and directedShots.host>=1 and directedShots.companion>=1 and hostIncomingVisual
                and q.combat.enemyShots>0,'natural victory lacks actual directed incoming pressure for both actors')
            check((data.weaponProficiency.firearms or 0)>=10 and (data.players.companion.weaponProficiency.firearms or 0)>=10,
                'both actors did not actually fire in production')
            baseScrap,baseGoodwill,baseFood=data.scrap,data.goodwill,data.resources.food
            routeStep=1; file('host.victory','true'); capture='natural-victory'
            print('LAN_PRESSURE_VICTORY hold='..q.holdElapsed..' kills='..q.kills..' morale='..q.enemyMorale
                ..' integrity='..q.positionIntegrity..' hostHealth='..data.health..' guestHealth='..data.players.companion.health
                ..' sharedReadySeconds='..bothReadySeconds..' defenseWall='..defenseWall..' naturalRetreats='..retreats
                ..' actualEnemyShots='..q.combat.enemyShots..' hostDirected='..directedShots.host..' guestDirected='..directedShots.companion)
        end
        if not file('guest.combat.checked') then return end
        local x=q.residentChecked and 300 or 710
        if routeStep==1 then if hostWalk(state,state.scene.player.x,295) then routeStep=2 end
        elseif routeStep==2 then if hostWalk(state,x,295) then routeStep=3 end
        elseif routeStep==3 then
            if hostWalk(state,x,330) and not state.pendingProgression and love.timer.getTime()-lastInput>.8 then
                interact(); if q.residentChecked and not q.rewardClaimed and x==710 then routeStep=1 end
            end
        end
    elseif state and state.mode=='aftermath' then
        stopWalk(); stage='reward'
        local disk=assert(Save.read(1)); check(disk.lastStand.rewardClaimed and disk.scrap==baseScrap+28
            and disk.goodwill==baseGoodwill+3 and disk.resources.food==baseFood+2,'normal victory reward was not durably applied once')
        check(disk.lastStand.combat.enemyShots>0,'actual enemy fire was lost from the durable checkpoint')
        check(not q.weaponSession and not q.shooterSessions.companion.weaponSession,'victory retained personal firing sessions')
        file('host.reward','true'); capture='natural-reward'; button('return'); stage='returning'
    elseif not state and q.completed and file('guest.ordinary') then
        local disk=assert(Save.read(1)); check(disk.lastStand.completed and disk.lastStand.rewardClaimed
            and disk.scrap==baseScrap+28 and disk.goodwill==baseGoodwill+3 and disk.resources.food==baseFood+2,'return repeated/lost reward')
        check(data.playerX==270 and data.playerY==490,'normal return lost host location')
        check(metrics.fire>=10 and metrics.hit>=10 and metrics.reload>=1 and metrics.cover>=1 and metrics.supply>=1,
            'host input evidence missing fire/reload/cover/supply')
        file('host.done','true'); stage='done'; capture='ordinary-return'
        if file('guest.done') then finish() end
    end
end
local lastOutcome; local selectedIdentity
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView; local panel=view and view.lastStand.shooter
    if view and view.ready and lp.menuOpen and stage=='joining' then back() end
    if not view or not view.ready then return end
    local q=view.runtime.saveData.lastStand
    check(not c.runtime.saveData,'guest acquired writable host campaign')
    if panel and panel.lastOutcome and panel.lastOutcome~=lastOutcome then
        lastOutcome=panel.lastOutcome
        if lastOutcome.ok then
            local details=lastOutcome.details or lastOutcome.result
            local name=pendingNames[lastOutcome.requestId]
            if details and name then note(name,details) end
        end
        pendingNames[lastOutcome.requestId]=nil
    end
    if q and q.lifecycle.mode=='interior' and not q.victory then
        stage='interior'
        local identity=Life.key(view.runtime.saveData)
        if selectedIdentity~=identity then
            if not view:inputAllowed() or view.lastStand.pending then return end
            if guestWalk(view,640,285) then
                local act=view.lastStand:action()
                if act and act.id=='window-tall' and love.timer.getTime()-lastInput>.7 then interact() end
                if act and act.id=='window-tall' and q.firingPositions.companion=='tall' and not view.lastStand.pending then
                    selectedIdentity=identity; file('guest.selected.'..q.lifecycle.revision,'true'); capture='window-selection'
                end
            end
        end
        if q.intermission==2 and not file('guest.story.denied') and not lp.network.pendingCommand then
            if not denialId then
                denialId=assert(lp.network:submitCommand('lastStand.start',{questId=q.lifecycle.entityId,
                    revision=q.lifecycle.revision,window='tall'},view.epoch,{}))
            else
                local reply=lp.network.lastCommandResult
                if reply and reply.requestId==denialId then
                    check(not reply.ok and reply.reason=='host_only','guest progressed normal intermission')
                    file('guest.story.denied','true'); capture='host-only-intermission'
                end
            end
        end
    elseif q and q.lifecycle.mode=='shootout' then
        stopWalk(); stage='defense'; selectedIdentity=nil
        if panel then
            if not pressureReady then guestCoverDrill(view,panel,q)
            elseif panel:canAct() then pilot(q,panel.gun,q.combat.defenders.companion,panel) end
        end
        if q.holdElapsed>=110 and not captures['natural-pressure'] then capture='natural-pressure' end
    elseif q and q.victory and not q.completed then
        stopWalk(); stage='victory'
        check(metrics.fire>=10 and metrics.hit>=10 and metrics.reload>=1 and metrics.cover>=1 and metrics.supply>=1,
            'guest input evidence missing fire/reload/cover/supply')
        check(file('guest.story.denied'),'normal intermission host-only denial missing')
        check(pressureReady and guestPacketShots.host>=1 and guestPacketShots.companion>=1 and guestIncomingVisual,
            'guest lacks checked directed pressure and its own actual incoming presentation')
        file('guest.combat.checked','fire='..metrics.fire..' hit='..metrics.hit..' reload='..metrics.reload
            ..' cover='..metrics.cover..' supply='..metrics.supply..' first='..tostring(metrics.firstFire)..' last='..tostring(metrics.lastFire))
        if q.lifecycle.mode=='returning' then
            local visual=lp.lastStandStage and lp.lastStandStage:get()
            if visual and visual.mode=='returning' then
                returnClockFirst=returnClockFirst or visual.clock
                check(not returnClockLast or visual.clock>=returnClockLast-.11,'checked host return presentation reversed')
                returnClockLast=visual.clock; capture='host-driven-return'
            end
            button('space'); button('return')
        end
    elseif q and q.completed and not view.lastStand:available() and view:inputAllowed() then
        stopWalk(); stage='done'
        check(view.runtime.scene=='stop' and lp.motionFrame.domain==nil,'guest ordinary return readiness missing')
        check(returnClockFirst and returnClockLast-returnClockFirst>.25,'guest never observed the checked host return animation clock')
        file('guest.ordinary','true'); capture='ordinary-return'
        if file('host.done') then file('guest.done','true'); finish() end
    end
end
local function update(dt)
    if finished or not app then return end
    dt=math.min(.05,dt)
    if role=='guest' then
        local view=c.ui.localPlay.clientView; local panel=view and view.lastStand.shooter
        local pending=panel and panel.pending
        if pending then pendingNames[pending.id]=pending.name end
    end
    app.update(dt)
    if role=='host' then hostUpdate(dt) else guestUpdate() end
    if love.timer.getTime()-lastReport>5 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        local data=role=='host' and c.runtime.saveData or lp.clientView and lp.clientView.runtime.saveData
        local q=data and data.lastStand
        print('LAN_PRESSURE_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)
            ..' hold='..tostring(q and q.holdElapsed)..' kills='..tostring(q and q.kills)..' fired='..metrics.fire..' error='..tostring(lp.error))
    end
    check(love.timer.getTime()-started<330,'normal pressure fixture timeout at '..tostring(stage))
end
local function guard(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guard(load) end
function love.update(dt) guard(update,dt) end
function love.draw()
    if not app or finished then return end
    guard(function()
        app.draw()
        if capture and not captures[capture] then
            local name=role..'-'..capture..'.png'; love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
            end); captures[capture]=true
        end
        capture=nil
    end)
end
