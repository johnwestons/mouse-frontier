-- Connected lifecycle acceptance with staged timing/kill thresholds. This is
-- not a natural 180-second defense. All transitions use production host input.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_LAST_STAND_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_LAST_STAND_RESUMED')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema')
local Players=require('game.coop_players'); local Items=require('game.item_instances')
local Life=require('game.coop_last_stand_lifecycle'); local Window=require('game.window_scene')
local Positions=require('game.coop_last_stand_positions'); local Codec=require('game.net.codec')
local Viewport=require('game.viewport'); local Aim=require('game.mobile_weapon_aim')
local app,c,stage,started,finished,capture,oldKeyboard,movementKey,restoreWrite
local captures={}; local lastReport=0; local requestId,phaseId,oldDomain,oldSession,ownGun,hostGun,checkpoint
local targetIndex,targetX,targetY,guestMagazine,phaseClock,baseScrap,baseGoodwill,baseFood,recoveries
local seededRetreat=false; local rewardFailed=false; local returningHeld=false
local lastGuestActionAt=0; local residentAt=0
local restartReconnectRequested=false
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
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(id,text)
    app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); button('return') end
end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function gunAction(panel,key,index)
    if touch then press(panel:rect(index)) else button(key) end
    lastGuestActionAt=love.timer.getTime()
end
local function walk(view,key)
    movementKey=nil
    if touch then
        app.touchreleased('walk',0,0); app.draw(); local stick=view.mobile.joystick
        local x,y=coords(stick.x,stick.y); app.touchpressed('walk',x,y)
        x,y=coords(stick.x+(key=='d' and 1 or 0)*stick.radius*.95,stick.y+(key=='w' and -1 or 0)*stick.radius*.95)
        app.touchmoved('walk',x,y,0,0)
    else movementKey=key end
end
local function stopWalk()
    movementKey=nil; if touch then app.touchreleased('walk',0,0) end
    local view=c.ui.localPlay.clientView; if view then view.lastStand:suspend(); view:neutralize() end
end
local function aimAndFire(panel,x,y)
    if touch then
        local tx,ty=Aim.gripForAim(panel.gun.weapon,panel.gun.ads and 'sights' or 'hip',x,y,960,720)
        local gx,gy=coords(tx,ty); app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0)
        press(panel:rect(1)); app.touchreleased('aim',gx,gy)
    else local gx,gy=coords(x,y); app.mousemoved(gx,gy,0,0,false); app.mousepressed(gx,gy,1,false); app.mousereleased(gx,gy,1,false) end
end
local function point(window)
    for index=1,#Window.slots do local x,y=Window.slotPosition(Window.layout(window,960,720),index)
        if Window.pointOpen(window,960,720,x,y) then return index,x,y end
    end
    error('no actual window aperture for '..window)
end
local function signature(data)
    local q=data.lastStand; local own=q.shooterSessions.companion
    return assert(Codec.encode({campaignId=data.coop.network.campaignId,companionId=data.coop.network.companionId,
        epoch=data.coop.sceneEpoch,location=data.location,lifecycle=q.lifecycle,hold=q.holdElapsed,kills=q.kills,
        integrity=q.positionIntegrity,morale=q.enemyMorale,completedPhase=q.completedPhase,checkpoint=q.phaseCheckpoint,
        combat=q.combat,targets=q.targets,positions=q.firingPositions,hostGun=q.weaponSession,guestGun=own.weaponSession,
        guestCached=own.weaponSessions,hostAmmo=data.players.host.ammo,guestAmmo=data.players.companion.ammo,
        loan=own.loanAmmo,loanActive=own.loanActive,hostHealth=data.health,guestHealth=data.players.companion.health},
        {maxBytes=32768,maxDepth=16,maxEntries=2048,maxStringBytes=256}))
end
local signatureLimits={maxBytes=32768,maxDepth=16,maxEntries=2048,maxStringBytes=256}
local fractionalFields={clock=true,hold=true,integrity=true,morale=true,timer=true,cooldown=true,reloadTimer=true,
    spawnCooldown=true,withdrawTimer=true,withdrawal=true,
    weaponActionElapsed=true,weaponReloadDuration=true,tubeReloadRoundTimer=true,coverProgress=true,hitRecovery=true,
    playerDamage=true,hostHealth=true,guestHealth=true}
local function checkedSignature(data,expected,label,roundTrip)
    local actual=signature(data); if actual==expected then return true end
    local want=assert(Codec.decode(expected,signatureLimits)); local have=assert(Codec.decode(actual,signatureLimits))
    local differences=0; local checked=0
    local function compare(a,b,path)
        checked=checked+1; check(checked<=4096,'signature diagnostic exceeded its bounded tree')
        if type(a)=='table' and type(b)=='table' then
            local seen={}; for key,value in pairs(a) do seen[key]=true; compare(value,b[key],path..'.'..tostring(key)) end
            for key,value in pairs(b) do if not seen[key] then compare(nil,value,path..'.'..tostring(key)) end end
        elseif a~=b then
            local tiny=roundTrip and fractionalFields[path:match('([^%.]+)$')] and type(a)=='number' and type(b)=='number'
                and (a~=math.floor(a) or b~=math.floor(b)) and math.abs(a-b)<=1e-11*math.max(1,math.abs(a),math.abs(b))
            if not tiny then
                differences=differences+1
                if differences<=16 then print('LAN_LIFECYCLE_SIGNATURE_DIFF label='..label..' path='..path
                    ..' expected='..tostring(a)..' actual='..tostring(b)) end
            end
        end
    end
    compare(want,have,'checkpoint')
    check(differences==0,label..' signature changed ('..differences..' fields)')
    return true
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'application quit cancelled')
    print('LAN_SMOKE_OK role='..role..' lastStandLifecycle=true actualSlotUI=true intermission=true retry=true victory=true'
        ..' rewardSaveRetry=true return=true passiveStages=true hostOnlyStory=true diskResume='..tostring(restart)
        ..' scope=staged-phase-thresholds input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function hostSavedEntry()
    local lp=c.ui.localPlay; lp.port=port; c.runtime.state='slots'
    menu(); click('host'); check(lp.hostingIntent=='selecting' and not lp.menuOpen,'title host intent did not select a saved journey')
    app.draw(); press(c.ui.slots[1])
    check(lp.network and c.session.networkMode=='host' and c.runtime.selectedSlot==1,
        'real saved-slot input did not synchronously start hosting: '..tostring(lp.error))
    back()
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(13102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if key==movementKey then return true end; return oldKeyboard(key,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        if not resumed then
            Save.remove(1); c.runtime.selectedSlot=1
            local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.stopped=true; draft.passengers={}
            draft.playerX,draft.playerY=270,490
            draft.lastStand={state='waiting',originStop=12,returnX=270,returnY=490,holdElapsed=43,
                kills=14,enemyMorale=100,positionIntegrity=100,completedPhase=0,phaseCheckpoint=0}
            check(c.enterGame(draft),'initial canonical save seed failed')
            Items.write(c.runtime.saveData,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            c.runtime.saveData.ammo['22lr']=40; check(Save.write(1,c.runtime.saveData),'isolated visible-slot seed failed')
            c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.lastStand=nil
        else
            local saved=assert(Save.read(1)); checkedSignature(saved,file('resume.expected'),'fresh-process disk',false)
            check(saved.lastStand.state=='shootout','saved mode was not shootout before UI resume')
        end
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,why=place(data); if not ok then return ok,why end
            local own=Players.forActor(data,'companion'); Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            own.ammo['22lr']=40; check(Items.ensure(data),'initial companion ownership failed'); return true
        end
        hostSavedEntry()
        if resumed then
            checkedSignature(c.runtime.saveData,file('resume.expected'),'real saved-slot host entry',false)
            check(lp.authority.sessionId~=file('resume.session'),'replacement host reused the previous session identity')
            file('host.resumed.session',lp.authority.sessionId)
            stage='restored'
        else stage='offer' end
        local submit=lp.context.commands.submit
        lp.context.commands.submit=function(name,args)
            if name=='lastStand.advance' and args.action=='reward' and not rewardFailed then
                rewardFailed=true; restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    if path==Save.path(1)..'.tmp' then return false,'reward fixture checkpoint failure' end
                    return restoreWrite(path,...)
                end
            end
            return submit(name,args)
        end
        print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        menu(); click('address','127.0.0.1:'..port); click('name','Lifecycle friend'); click('join')
        check(lp.network,'guest join failed '..tostring(lp.error)); stage='joining'
    end
end
local function hostWindow(state)
    if state.paused then button('p') end
    state.scene.player.x,state.scene.player.y=350,285; button('e')
    check(state.handoff and state.handoff.window=='wide','Source wide handoff not started')
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local q=data.lastStand; local state=c.runtime.lastStand
    if lp:pending() then click('approve'); check(not lp.error,'approval failed '..tostring(lp.error)); back() end
    if stage=='offer' and state and state.mode=='offer' then
        button('q'); button('p'); file('host.offer.wait','true'); capture='held-offer'; stage='offer-wait'
    elseif stage=='offer-wait' and file('guest.offer.seen') then
        button('p'); button('y'); check(q.lifecycle.mode=='escort','actual host acceptance did not start escort'); stage='escort'
    elseif stage=='escort' and state and state.mode=='escort' and state.clock>.25 then
        button('p'); file('host.escort.wait','true'); capture='held-escort'; stage='escort-wait'
    elseif stage=='escort-wait' and file('guest.escort.seen') then
        button('p'); button('space'); check(state.mode=='backyard','host escort skip did not arrive')
        state.scene.player.x,state.scene.player.y=480,360; button('e'); stage='initial-interior'
    elseif stage=='initial-interior' and state and state.mode=='interior' then
        -- Preserve the existing controlled boundary fixture after real host acceptance.
        q.holdElapsed=43; q.kills=14; q.enemyMorale=100; q.positionIntegrity=100
        check(Save.write(1,data),'staged initial defense checkpoint failed'); file('host.initial.interior','true'); stage='interior'
    elseif stage=='interior' and state then
        if not state.paused then button('p') end
        if file('guest.selected') then hostWindow(state); stage='first-start' end
    elseif stage=='first-start' and state.mode=='shootout' then
        targetIndex,targetX,targetY=point('tall')
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=999 end
        local target=q.targets[targetIndex]; target.health=1; target.status='exposed'; target.timer=999; target.hasSpawned=true
        check(lp.authority:checkpointNow(),'first controlled target checkpoint failed')
        button('p'); file('host.first.ready','true'); stage='first-phase'
    elseif stage=='first-phase' and q.combat.result=='intermission' then
        check(state.paused and state.mode=='shootout' and q.kills==15,'guest progressed intermission or final staged kill failed')
        check(data.players.companion.ammo['22lr']==39 and data.ammo['22lr']==40,'first phase changed wrong ammunition')
        file('host.phase.wait','true'); capture='held-intermission'; stage='phase-wait'
    elseif stage=='phase-wait' and file('guest.phase.denied') then
        phaseId=q.combat.phaseRevision; button('p'); stage='intermission'
    elseif stage=='intermission' and state.mode=='interior' then
        check(q.intermission==2 and q.completedPhase==1 and q.combat.phaseRevision>phaseId,'host intermission did not persist phase')
        file('host.intermission','true'); capture='host-intermission'; hostWindow(state); stage='second-start'
    elseif stage=='second-start' and state.mode=='shootout' then
        check(q.holdElapsed>=45 and q.kills==15,'next phase reset earlier progress')
        button('p'); file('host.second.ready','true'); stage='second-phase'
    elseif stage=='second-phase' and file('guest.second.saved') then
        local own=q.shooterSessions.companion.weaponSession
        check(q.combat.defenders.companion.ducking and own.reloadTimer>0 and data.players.companion.ammo['22lr']==39,
            'personal cover/reload checkpoint absent')
        check(lp.authority:checkpointNow(),'restart checkpoint failed')
        local durable=assert(Save.read(1)); checkpoint=signature(durable)
        -- Lua save serialization rounds finite fractional timers. Integer
        -- identities, phase revisions, costs and all table shapes stay exact.
        checkedSignature(data,checkpoint,'RAM to durable round trip',true)
        file('resume.expected',checkpoint); file('resume.session',lp.authority.sessionId)
        file('host.restart.saved','true'); capture='saved-before-restart'
        if restart then stage='exit-restart' else file('host.resumed','true'); stage='retreat-setup' end
    elseif stage=='exit-restart' and captures['saved-before-restart'] then
        finished=true; print('LAN_SMOKE_RESTART role=host lastStandSaved=true ownItems=true ownAmmo=true phase=true'); love.event.quit(42)
    elseif stage=='restored' and state and state.mode=='shootout' then
        check(q.kills==15 and q.holdElapsed>=45 and q.shooterSessions.companion.weaponSession.itemId,
            'Source restore reset checked phase or gun')
        local lease=Positions.occupied(data,lp.authority.activityState,lp.authority.bindings,lp.context.clock(),'host')
        if lease then
            if not state.paused then button('p') end
            file('host.resumed','true'); capture='source-restored'; stage='retreat-setup'
        end
    elseif stage=='retreat-setup' and file('guest.resumed') then
        ownGun=q.shooterSessions.companion.weaponSession.itemId; hostGun=q.weaponSession.itemId
        recoveries=q.recoveries or 0; q.positionIntegrity=.1
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=.05; target.health=target.maxHealth; target.hasSpawned=true end
        q.combat.spawnCooldown=0; file('host.retreat.pressure','true'); stage='retreat'
    elseif stage=='retreat' and q.combat.result=='retreat' then
        check(state.paused and state.mode=='shootout' and q.positionIntegrity<=0,'retreat did not wait for host')
        phaseId=q.combat.phaseRevision; file('host.retreat.wait','true'); capture='held-retreat'; stage='retreat-wait'
    elseif stage=='retreat-wait' and file('guest.retry.denied') then
        -- Unpause and use the actual retry input before any world update can
        -- consume the terminal result through the alternative host path.
        button('p'); button('return')
        check(q.combat.result==nil and q.combat.phaseRevision>phaseId and q.recoveries==recoveries+1
            and q.holdElapsed==45 and q.kills==15,'actual host retry lost earlier progress')
        check(q.shooterSessions.companion.weaponSession.itemId==ownGun and data.players.companion.ammo['22lr']==39,
            'retry changed personal firearm/cost')
        button('p'); file('host.retry.ready','true'); capture='host-retry'; stage='retry-ready'
    elseif stage=='retry-ready' and file('guest.retry.ready') then
        -- Stage the next authored boundary. Enemy/phase execution remains real.
        q.holdElapsed=104.8; q.combat.stage=2
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=999 end
        file('host.second.boundary','true'); stage='second-boundary'
    elseif stage=='second-boundary' and q.combat.result=='intermission' then
        check(state.paused and q.completedPhase==2,'second boundary advanced without host')
        file('host.second.wait','true'); capture='held-second-intermission'; stage='second-wait'
    elseif stage=='second-wait' and file('guest.second.wait') then button('p'); stage='last-interior'
    elseif stage=='last-interior' and state.mode=='interior' then hostWindow(state); stage='last-start'
    elseif stage=='last-start' and state.mode=='shootout' then
        button('p'); file('host.last.ready','true'); stage='last-ready'
    elseif stage=='last-ready' and file('guest.last.ready') then
        q.holdElapsed=179.8; q.completedPhase=3; q.combat.stage=4; q.enemyMorale=0
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=999 end
        stage='victory'
    elseif stage=='victory' and q.combat.result=='victory' then
        check(state.paused and not q.victory and not q.rewardClaimed,'victory progressed while host controls paused')
        file('host.victory.wait','true'); capture='held-victory'; stage='victory-wait'
    elseif stage=='victory-wait' and file('guest.victory.denied') then button('p'); stage='victory-interior'
    elseif stage=='victory-interior' and state.mode=='interior' and q.victory then
        check(not q.rewardClaimed and not q.residentChecked,'victory granted reward or checked resident automatically')
        baseScrap,baseGoodwill,baseFood=data.scrap,data.goodwill,data.resources.food
        state.scene.player.x,state.scene.player.y=710,335; button('e')
        check(q.residentChecked and not q.rewardClaimed,'host resident interaction did not establish reward eligibility')
        residentAt=love.timer.getTime(); stage='resident-confirmed'
    elseif stage=='resident-confirmed' and not state.pendingProgression and love.timer.getTime()-residentAt>.7 then
        state.scene.player.x,state.scene.player.y=300,335; button('e')
        check(rewardFailed and c.session.checkpointPending and state.pendingProgression,'reward failed-save barrier absent')
        check(data.scrap==baseScrap+28 and data.goodwill==baseGoodwill+3 and data.resources.food==baseFood+2,'reward draft has wrong amounts')
        file('host.reward.pending','true'); capture='host-reward-save-retry'; stage='reward-pending'
    elseif stage=='reward-pending' and file('guest.reward.wait') then
        love.filesystem.write=restoreWrite; restoreWrite=nil; button('r')
        check(not c.session.checkpointPending,'Source reward save retry failed'); stage='reward-confirmed'
    elseif stage=='reward-confirmed' and state.mode=='aftermath' then
        local disk=assert(Save.read(1)); check(disk.lastStand.rewardClaimed and disk.scrap==baseScrap+28
            and disk.goodwill==baseGoodwill+3 and disk.resources.food==baseFood+2,'reward was not saved exactly once')
        check(not q.weaponSession and not q.shooterSessions.companion.weaponSession and (q.shooterSessions.companion.loanAmmo or 0)==0,'victory retained loan/session gameplay')
        file('host.reward.saved','true'); capture='confirmed-aftermath'; stage='aftermath-wait'
    elseif stage=='aftermath-wait' and file('guest.aftermath.seen') then button('return'); stage='returning'
    elseif stage=='returning' and state.mode=='returning' then
        if not returningHeld then button('p'); returningHeld=true; file('host.return.wait','true'); capture='held-return' end
        if file('guest.return.denied') then button('p'); button('space'); stage='complete' end
    elseif stage=='complete' and not c.runtime.lastStand and q.completed and file('guest.ordinary') then
        local disk=assert(Save.read(1)); check(disk.lastStand.completed and disk.lastStand.rewardClaimed and disk.scrap==baseScrap+28,
            'completed return lost or repeated reward')
        check(data.playerX==270 and data.playerY==490 and q.lifecycle.mode=='complete','host return coordinates/mode lost')
        file('host.done','true'); capture='ordinary-return'; stage='done'
    elseif stage=='done' and file('guest.done') then finish() end
end
local function deny(name)
    local view=c.ui.localPlay.clientView; local q=view.runtime.saveData.lastStand
    requestId=assert(c.ui.localPlay.network:submitCommand(name,{questId=q.lifecycle.entityId,revision=q.lifecycle.revision,
        action=name=='lastStand.advance' and 'result' or nil},view.epoch,{}))
end
local function denied()
    local reply=c.ui.localPlay.network.lastCommandResult
    if reply and reply.requestId==requestId then check(not reply.ok and reply.reason=='host_only','guest story action was accepted: '..tostring(reply.reason)); return true end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView; local panel=view and view.lastStand.shooter
    if restart and stage=='restart-wait' then
        local expected=file('host.resumed.session')
        if lp.phase=='connected' and view and view.ready and file('host-resumed.ready') and expected
            and lp.network.sessionId==expected and lp.network.sessionId~=oldSession then
            back(); stage='resuming'
        elseif file('host-resumed.ready') and expected and lp.phase=='connected' and lp.network.sessionId==oldSession
            and not restartReconnectRequested then
            print('LAN_LIFECYCLE_RECONNECT old='..tostring(oldSession)..' presented='..tostring(lp.network.sessionId)..' host='..expected)
            -- An old ENet peer can remain locally connected until its timeout.
            -- Use actual Leave Session and Join controls once the new host is
            -- listening; never treat that old view as a resumed connection.
            menu(); click('leave'); menu(); click('join'); restartReconnectRequested=true
        elseif lp.phase=='idle' and file('host-resumed.ready') then
            -- Manual reconnect is a real menu action; credentials stay on this
            -- isolated guest device, and old private held state is discarded.
            menu(); click('join'); restartReconnectRequested=true
        end
        return
    end
    check(lp.phase~='idle' or not lp.error,'guest link failed '..tostring(lp.error))
    if view and view.ready and lp.menuOpen and (stage=='joining' or stage=='resuming') then back() end
    if stage=='joining' and view and view.ready and view.lastStand:available() then stage='offer-wait' end
    local passive=view and view.lastStand:passiveModel()
    if stage=='offer-wait' and file('host.offer.wait') and passive and passive.mode=='offer' and not passive.stale
        and passive.paused and passive.page.page==4 then
        check(not view:inputAllowed() and not view.lastStand:action(),'offer exposed guest progression or movement')
        button('y'); button('q'); button('return'); check(view.runtime.saveData.lastStand.lifecycle.mode=='offer','guest accepted offer')
        file('guest.offer.seen','true'); capture='guest-held-offer'; stage='escort-wait'
    elseif stage=='escort-wait' and file('host.escort.wait') and passive and passive.mode=='escort' and not passive.stale and passive.paused then
        check(passive.clock>.1 and not view.lastStand:action(),'escort presentation lacks checked host clock')
        button('space'); check(view.runtime.saveData.lastStand.lifecycle.mode=='escort','guest skipped escort')
        file('guest.escort.seen','true'); capture='guest-held-escort'; stage='initial-interior'
    elseif stage=='initial-interior' and file('host.initial.interior') and view:inputAllowed() then walk(view,'w'); stage='up'
    elseif stage=='up' and lp.motionFrame.companion.y<300000 then walk(view,'d'); stage='right'
    elseif stage=='right' and lp.motionFrame.companion.x>635000 then stopWalk(); stage='stop'
    elseif stage=='stop' and lp.motionFrame.companion.vx==0 and lp.motionFrame.companion.vy==0 then
        check(view.lastStand:action() and view.lastStand:action().id=='window-tall','guest not at tall window')
        if touch then press({x=580,y=580,w=350,h=45}) else button('e') end; stage='selected'
    elseif stage=='selected' and not view.lastStand.pending and view.runtime.saveData.lastStand.firingPositions.companion=='tall' then
        file('guest.selected','true'); stage='first-ready'
    elseif stage=='first-ready' and panel:canAct() and file('host.first.ready') then
        targetIndex,targetX,targetY=point('tall'); ownGun=panel.gun.itemId; oldDomain=Life.key(view.runtime.saveData)
        aimAndFire(panel,targetX,targetY); check(panel.pending,'first actual shot missing'); stage='first-shot'
    elseif stage=='first-shot' and not panel.pending and panel.lastOutcome and panel.lastOutcome.ok then
        check(panel.lastOutcome.details.hit and view.runtime.saveData.ammo['22lr']==39 and view.runtime.saveData.lastStand.kills==15,'first actual kill/cost failed')
        stage='phase-wait'
    elseif stage=='phase-wait' and file('host.phase.wait') and view.runtime.saveData.lastStand.combat.result=='intermission' then
        check(not panel:canAct() and not next(panel.held),'terminal phase retained held shooting'); deny('lastStand.advance'); capture='guest-held-intermission'; stage='phase-deny'
    elseif stage=='phase-deny' and denied() then file('guest.phase.denied','true'); stage='second-ready'
    elseif stage=='second-ready' and file('host.second.ready') and panel:canAct() then
        check(Life.key(view.runtime.saveData)~=oldDomain and panel.gun.itemId==ownGun and view.runtime.saveData.ammo['22lr']==39,'next phase reset gun or omitted fresh readiness')
        gunAction(panel,'c',4); stage='cover'
    elseif stage=='cover' and not panel.pending and view.runtime.saveData.lastStand.combat.defenders.companion.ducking
        and love.timer.getTime()-lastGuestActionAt>.7 then
        gunAction(panel,'r',3); stage='reload'
    elseif stage=='reload' and not panel.pending and panel.gun.reloadTimer>0 then
        guestMagazine=panel.gun.magazine; oldSession=lp.network.sessionId; phaseId=view.runtime.saveData.lastStand.combat.phaseRevision
        file('guest.second.saved','true'); capture='guest-before-restart'; stage=restart and 'restart-wait' or 'resuming'
    elseif stage=='resuming' and file('host.resumed') and view and panel:canAct() then
        if restart then print('LAN_LIFECYCLE_RESUMED_SESSION old='..tostring(oldSession)..' presented='..tostring(lp.network.sessionId)
            ..' host='..tostring(file('host.resumed.session'))) end
        check(not restart or lp.network.sessionId~=oldSession,'fresh host process reused old network session')
        check(not restart or lp.network.sessionId==file('host.resumed.session'),'guest resumed the wrong host session')
        check(panel.gun.itemId==ownGun and view.runtime.saveData.ammo['22lr']==39 and panel.position and not next(panel.held),
            're-admission lost owned gun/cost or reused held controls')
        check(view.runtime.saveData.lastStand.combat.phaseRevision==phaseId,'UI host resume advanced saved firing phase')
        if view.runtime.saveData.lastStand.combat.defenders.companion.ducking then gunAction(panel,'c',4) end
        file('guest.resumed','true'); capture='guest-restored'; stage='retreat'
    elseif stage=='retreat' and file('host.retreat.wait') and view.runtime.saveData.lastStand.combat.result=='retreat' then
        check(not panel:canAct(),'retreat allowed shooting'); deny('lastStand.retry'); capture='guest-held-retreat'; stage='retry-deny'
    elseif stage=='retry-deny' and denied() then file('guest.retry.denied','true'); stage='retry-ready'
    elseif stage=='retry-ready' and file('host.retry.ready') and panel:canAct() then
        check(view.runtime.saveData.lastStand.kills==15 and view.runtime.saveData.ammo['22lr']==39 and panel.gun.itemId==ownGun,
            'retry reset earlier kills/ammunition/owned weapon')
        file('guest.retry.ready','true'); stage='second-wait'
    elseif stage=='second-wait' and file('host.second.wait') and view.runtime.saveData.lastStand.combat.result=='intermission' then
        check(not panel:canAct(),'second boundary retained shooting'); file('guest.second.wait','true'); stage='last-ready'
    elseif stage=='last-ready' and file('host.last.ready') and panel:canAct() then file('guest.last.ready','true'); stage='victory'
    elseif stage=='victory' and file('host.victory.wait') and view.runtime.saveData.lastStand.combat.result=='victory' then
        check(not view.runtime.saveData.lastStand.rewardClaimed and not panel:canAct(),'victory granted reward early'); deny('lastStand.advance'); capture='guest-held-victory'; stage='victory-deny'
    elseif stage=='victory-deny' and denied() then file('guest.victory.denied','true'); stage='reward-wait'
    elseif stage=='reward-wait' and file('host.reward.pending') then
        check(not view.runtime.saveData.lastStand.rewardClaimed and view.runtime.saveData.lastStand.lifecycle.mode~='aftermath',
            'guest received reward before checkpoint durability')
        check(not passive or not passive.summary,'unconfirmed reward leaked into passive summary')
        file('guest.reward.wait','true'); capture='guest-reward-wait'; stage='aftermath-wait'
    elseif stage=='aftermath-wait' and file('host.reward.saved') and passive and passive.mode=='aftermath' and not passive.stale then
        check(passive.summary and passive.summary.scrap==28 and passive.summary.goodwill==3 and passive.summary.food==2,
            'passive aftermath omitted durable reward')
        check(passive.guest.x==505 and passive.guest.y==590 and not view.lastStand:action(),'aftermath guest anchor/control mismatch')
        file('guest.aftermath.seen','true'); capture='guest-confirmed-aftermath'; stage='return-wait'
    elseif stage=='return-wait' and file('host.return.wait') and passive and passive.mode=='returning' and not passive.stale and passive.paused then
        check(not passive.summary and not view.lastStand:action(),'return exposed guest story controls')
        button('space'); button('return'); check(view.runtime.saveData.lastStand.lifecycle.mode=='returning','guest completed host return')
        file('guest.return.denied','true'); capture='guest-held-return'; stage='ordinary'
    elseif stage=='ordinary' and view and not view.lastStand:available() and view:inputAllowed() then
        check(view.runtime.scene=='stop' and lp.motionFrame.domain==nil and view.runtime.saveData.lastStand.completed,
            'guest ordinary stop/readiness missing after return')
        check(not c.runtime.saveData,'guest acquired writable campaign'); file('guest.ordinary','true'); capture='guest-ordinary-return'; stage='done'
    elseif stage=='done' and file('host.done') then file('guest.done','true'); finish() end
end
local function update(dt)
    if finished or not app then return end
    app.update(math.min(.05,dt)); if role=='host' then hostUpdate() else guestUpdate() end
    if love.timer.getTime()-lastReport>4 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        print('LAN_LAST_STAND_LIFECYCLE_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)..' error='..tostring(lp.error))
    end
    check(love.timer.getTime()-started<110,'fixture timeout at '..tostring(stage))
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
