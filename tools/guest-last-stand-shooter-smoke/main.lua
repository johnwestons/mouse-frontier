-- Two complete apps, real ENet and PNG apertures. Early exposure is controlled;
-- the final stage runs production enemy spawning/targeting from a staged setup.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema')
local Life=require('game.coop_last_stand_lifecycle'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Window=require('game.window_scene')
local Viewport=require('game.viewport')
local Aim=require('game.mobile_weapon_aim')
local Positions=require('game.coop_last_stand_positions'); local Combat=require('game.coop_last_stand_state')
local app,c,stage,started,finished,capture,movementKey,oldKeyboard,restoreWrite
local captures={}; local lastReport=0; local readyFailed=false; local fireFailed=false
local retryReady=false; local retryFire=false; local targetIndex,targetX,targetY
local firstGeneration,ownGun,hostGun,phaseRevision,encounterId,initialClock,initialEpoch
local approvals=0; local submittedAt=0; local denyId; local baselineMagazine; local shotId; local cachedMagazine,initialFireMode
local simultaneousIndex,simultaneousHostX,simultaneousHostY,simultaneousGuestX,simultaneousGuestY
local simultaneousKills,pressureHealth,pressureHostHealth,pressureSerial,pressureSeeded=false
local function check(value,message) assert(value,message) end
local function marker(name,value)
    local f=assert(io.open(root..'/'..name,'w')); f:write(tostring(value or true)); f:close()
end
local function read(name)
    local f=io.open(root..'/'..name,'r'); if not f then return nil end; local value=f:read('*a'); f:close(); return value
end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function button(key) app.keypressed(key); app.keyreleased(key) end
local function press(rect)
    check(rect,'missing control at '..tostring(stage)); local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('button',x,y); app.touchreleased('button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); button('return') end
end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function walk(view,key)
    movementKey=nil
    if touch then
        app.touchreleased('walk',0,0); app.draw(); local stick=view.mobile.joystick
        local x,y=coords(stick.x,stick.y); app.touchpressed('walk',x,y)
        x,y=coords(stick.x+(key=='d' and 1 or key=='a' and -1 or 0)*stick.radius*.95,
            stick.y+(key=='s' and 1 or key=='w' and -1 or 0)*stick.radius*.95)
        app.touchmoved('walk',x,y,0,0)
    else movementKey=key end
end
local function stopWalk()
    movementKey=nil; if touch then app.touchreleased('walk',0,0) end
    local view=c.ui.localPlay.clientView; if view then view.lastStand:suspend(); view:neutralize() end
end
local function point(window)
    for index=1,#Window.slots do
        local x,y=Window.slotPosition(Window.layout(window,960,720),index)
        if Window.pointOpen(window,960,720,x,y) then return index,x,y end
    end
    error('No authored aperture has a visible target for '..window)
end
local function commandKey(panel,key)
    if touch then
        local indexes={space=1,aim=2,r=3,c=4,tab=5,v=6,l=7,p=8,menu=9}
        press(panel:rect(assert(indexes[key])))
    else button(key) end
end
local function fire(panel,x,y)
    if touch then
        local tx,ty=Aim.gripForAim(panel.gun.weapon,panel.gun.ads and 'sights' or 'hip',x,y,960,720)
        local gx,gy=coords(tx,ty); app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0)
        press(panel:rect(1)); app.touchreleased('aim',gx,gy)
    else
        local gx,gy=coords(x,y); app.mousemoved(gx,gy,0,0,false)
        app.mousepressed(gx,gy,1,false); app.mousereleased(gx,gy,1,false)
    end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'application quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' lastStandShooter=true twoApplications=true actorWindows=true independentGuns=true'
        ..' failedReadyCheckpoint=true failedGunCheckpoint=true durableProjection=true reconnect=true hostOnlyStory=true'
        ..' ownedLoanSupply=true borrowedShot=true cachedWeaponSwitch=true fireMode=true'
        ..' simultaneousSettlement=true enemyPressure=true personalHitCue=true personalCoverCue=true'
        ..' nativeMasks=true pressure=controlled input='..(touch and 'touch' or 'desktop')..' approvals='..approvals)
    love.event.quit(0)
end
local function injectFailure(label)
    check(not restoreWrite,'overlapping failure injection'); restoreWrite=love.filesystem.write
    love.filesystem.write=function(path,...)
        if path=='saves/slot99.lua.tmp' then return false,label..' fixture failure' end
        return restoreWrite(path,...)
    end
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(15102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if key==movementKey then return true end; return oldKeyboard(key,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
        draft.lastStand={state='interior',originStop=12,returnX=270,returnY=490}
        check(c.enterGame(draft),'host load failed'); app.update(.01)
        local data=c.runtime.saveData
        Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
        check(Items.owned(data,'frontier-22-lever-rifle'),'host firearm seed failed')
        data.ammo['22lr']=40; initialEpoch=data.coop.sceneEpoch
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local success,result,why=xpcall(function()
                local ok,reason=place(campaign)
                print('LAN_SHOOTER_PLACE_ORIGIN ok='..tostring(ok)..' reason='..tostring(reason))
                if not ok then return ok,reason end
                local own=Players.forActor(campaign,'companion')
                Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
                check(Items.owned(own,'frontier-22-lever-rifle'),'guest firearm seed failed')
                own.ammo['22lr']=40
                local ensured,errorMessage=Items.ensure(campaign)
                print('LAN_SHOOTER_PLACE_ITEMS ok='..tostring(ensured~=nil)..' reason='..tostring(errorMessage))
                check(ensured,errorMessage or 'guest gear ownership invalid')
                return true
            end,debug.traceback)
            if not success then print('LAN_SHOOTER_PLACE_ERROR '..tostring(result)); error(result) end
            return result,why
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed '..tostring(lp.error)); back()
        local command=lp.network.context.command
        lp.network.context.command=function(generation,request)
            if request.command=='lastStand.position' and request.args.action=='ready' and not readyFailed then
                readyFailed=true; injectFailure('ready position')
            elseif request.command=='gun.fire' then
                local campaign=c.runtime.saveData; local q=campaign.lastStand; local source=c.runtime.lastStand.shootout
                local lease=Positions.occupied(campaign,lp.authority.activityState,lp.authority.bindings,lp.context.clock(),'companion')
                local motion=lp.motion
                local motionReady=motion and motion.generation==generation and motion.readyEpoch==campaign.coop.sceneEpoch
                    and motion.domain==Life.key(campaign)
                print('LAN_SHOOTER_BEFORE_FIRE sourceBound='..tostring(source and Combat.record(source)==q.combat)
                    ..' campaignBound='..tostring(source and Combat.campaignOf(source)==campaign)
                    ..' phase='..tostring(q.combat.phaseRevision)..' occupancy='..tostring(lease~=nil)
                    ..' motionReady='..tostring(motionReady)..' domain='..tostring(motion and motion.domain)
                    ..' expectedDomain='..tostring(Life.key(campaign))..' checkpointPending='..tostring(c.session.checkpointPending)
                    ..' health='..tostring(campaign.players.companion.health))
                if lease and lease.generation==generation and motionReady and not fireFailed then
                    fireFailed=true; injectFailure('owned shot')
                end
            end
            local reply=command(generation,request)
            print('LAN_LAST_STAND_SHOOTER_COMMAND name='..request.command..' action='..tostring(request.args.action)
                ..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason)..' durable='..tostring(reply.durable))
            return reply
        end
        button('p'); check(c.runtime.lastStand.paused,'host pause failed')
        stage='interior'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        menu(); click('address','127.0.0.1:'..port); click('name','Defense friend'); click('join')
        check(lp.network,'guest join failed '..tostring(lp.error)); stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local q=data.lastStand; local state=c.runtime.lastStand
    if lp:pending() then
        approvals=approvals+1; click('approve')
        check(not lp.error,'guest approval failed '..tostring(lp.error)); back()
    end
    if lp.authority.pendingSave and restoreWrite then
        if readyFailed and not retryReady and read('guest.ready.pending') then
            check(q.firingPositions.companion=='tall' and q.combat.defenders.companion.windowId=='tall','pending ready not actor-owned')
            love.filesystem.write=restoreWrite; restoreWrite=nil; button('r')
            check(not c.session.checkpointPending,'Source R ready retry failed'); retryReady=true; marker('host.ready.retry')
        elseif fireFailed and not retryFire and read('guest.fire.pending') then
            check(data.players.companion.ammo['22lr']==39 and data.ammo['22lr']==40,'pending shot changed wrong ammunition')
            love.filesystem.write=restoreWrite; restoreWrite=nil; button('r')
            check(not c.session.checkpointPending,'Source R gun retry failed'); retryFire=true; marker('host.fire.retry')
        end
    end
    if stage=='interior' and read('guest.selected') then
        firstGeneration=lp.generation
        local pose=Life.pose(data,'companion')
        check(pose and (pose.x-660)^2+(pose.y-280)^2<82^2,'guest selection bypassed movement')
        check(q.state=='interior' and q.firingPositions.companion=='tall' and state.paused,'guest selection progressed story or resumed host')
        check(Life.pose(data,'host').x==480 and Life.pose(data,'host').y==590,'guest moved host')
        button('p'); state.scene.player.x,state.scene.player.y=350,300; button('e')
        check(state.handoff and state.handoff.window=='wide','host did not start wide handoff')
        stage='handoff'
    elseif stage=='handoff' and state.mode=='shootout' then
        check(q.firingPositions.host=='wide' and q.firingPositions.companion=='tall','host displaced companion selection')
        check(q.lifecycle.mode=='shootout' and state.shootout,'host firing phase missing')
        targetIndex,targetX,targetY=point('tall')
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=999 end
        local target=q.targets[targetIndex]; target.status='exposed'; target.timer=999; target.health=target.maxHealth
        check(lp.authority:checkpointNow(),'controlled target checkpoint failed')
        marker('host.target',targetIndex..','..targetX..','..targetY)
        phaseRevision=q.combat.phaseRevision; encounterId=q.combat.entityId; initialClock=q.combat.clock
        hostGun=q.weaponSession.itemId
        button('p'); check(state.paused,'host shooter private pause failed'); marker('host.paused')
        capture='wide-private-pause'; stage='shootout'
    elseif stage=='shootout' and read('guest.shot.saved') then
        check(retryReady and retryFire and state.paused and q.combat.clock>initialClock,'host pause blocked guest simulation')
        check(q.combat.defenders.companion.windowId=='tall' and q.combat.defenders.host.windowId=='wide','actor windows merged')
        check(data.players.companion.ammo['22lr']==39 and data.ammo['22lr']==40 and q.weaponSession.itemId==hostGun,'shot changed host firearm')
        check(q.targets[targetIndex].health<q.targets[targetIndex].maxHealth,'guest missed actual aperture/target')
        ownGun=q.shooterSessions.companion.weaponSession.itemId; check(ownGun~=hostGun,'actors shared a gun identity')
        local disk=assert(Save.read(99)); check(disk.players.companion.ammo['22lr']==39 and disk.lastStand.shooterSessions.companion.weaponSession.itemId==ownGun,'shot disk receipt missing')
        marker('host.shot.disk',ownGun); stage='controls'
    elseif stage=='controls' and read('guest.controls.saved') then
        local own=q.shooterSessions.companion.weaponSession
        check(data.players.companion.ammo['22lr']==39 and data.ammo['22lr']==40,'reload/cover charged rounds')
        check(not q.combat.defenders.companion.ducking and not q.combat.defenders.host.ducking,'personal cover leaked')
        check(own.itemId==ownGun and q.combat.phaseRevision==phaseRevision,'personal controls replaced gun or phase')
        check(q.shooterSessions.companion.loanActive and q.shooterSessions.companion.loanAmmo==47
            and not q.loanActive and (q.loanAmmo or 0)==0,'personal loan supply/shot leaked or refilled')
        check(lp.authority:checkpointNow(),'controls checkpoint failed'); marker('host.controls.disk',own.magazine); stage='rejoin'
    elseif stage=='rejoin' and read('guest.rejoined') then
        local disk=assert(Save.read(99)); local own=disk.lastStand.shooterSessions.companion.weaponSession
        check(approvals>=1 and lp.generation>firstGeneration and own.itemId==ownGun and disk.players.companion.ammo['22lr']==39,'reconnect reset gun, ammunition or connection generation')
        check(disk.lastStand.combat.phaseRevision==phaseRevision and disk.lastStand.combat.entityId==encounterId,'reconnect reset encounter')
        check(disk.lastStand.shooterSessions.companion.loanAmmo==47 and not own.borrowed,'reconnect refilled loan or changed selected firearm')
        check(data.coop.sceneEpoch==initialEpoch and q.state=='shootout' and state.paused,'guest changed host progression')
        button('p'); check(not state.paused,'host did not resume for simultaneous shots')
        local life=q.lifecycle
        local reply=lp.context.commands.submit('lastStand.position',{questId=life.entityId,revision=life.revision,
            action='ready',window='wide',phaseRevision=q.combat.phaseRevision})
        check(reply.ok and reply.durable,'host checked wide readiness failed '..tostring(reply.reason))
        for index=1,#Window.slots do
            local hx,hy=Window.slotPosition(Window.layout('wide',960,720),index)
            local gx,gy=Window.slotPosition(Window.layout('tall',960,720),index)
            if Window.pointOpen('wide',960,720,hx,hy) and Window.pointOpen('tall',960,720,gx,gy) then
                simultaneousIndex,simultaneousHostX,simultaneousHostY,simultaneousGuestX,simultaneousGuestY=index,hx,hy,gx,gy; break
            end
        end
        check(simultaneousIndex,'no shared target visible through both actual windows')
        for _,target in ipairs(q.targets) do target.status='hidden'; target.timer=999 end
        local target=q.targets[simultaneousIndex]; target.status='exposed'; target.timer=999; target.health=1; target.hasSpawned=true
        simultaneousKills=q.kills
        check(lp.authority:checkpointNow(),'shared settlement setup checkpoint failed')
        marker('host.simultaneous',simultaneousIndex); marker('host.simultaneous.revision',data.coop.revision)
        stage='simultaneous'
    elseif stage=='simultaneous' and read('guest.simultaneous.sent') then
        local x,y=coords(simultaneousHostX,simultaneousHostY)
        app.mousemoved(x,y,0,0,false); app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false)
        check(data.ammo['22lr']==39,'actual host shot did not charge its own firearm')
        marker('host.simultaneous.fired'); capture='wide-shared-settlement'; stage='simultaneous-wait'
    elseif stage=='simultaneous-wait' and read('guest.simultaneous.saved') then
        check(q.targets[simultaneousIndex].health==0 and q.kills==simultaneousKills+1,'shared enemy settled more than once')
        check(data.ammo['22lr']==39 and data.players.companion.ammo['22lr']==38
            and q.shooterSessions.companion.loanAmmo==47,'simultaneous shots charged wrong actor or loan pool')
        check(q.weaponSession.itemId==hostGun and q.shooterSessions.companion.weaponSession.itemId==ownGun,
            'simultaneous shots replaced owned guns')
        button('p'); check(state.paused,'host did not restore private pause for pressure')
        pressureHealth=data.players.companion.health; pressureHostHealth=data.health
        for _,target in ipairs(q.targets) do
            target.status='hidden'; target.timer=.05; target.health=target.maxHealth; target.hasSpawned=true; target.targetActorId=nil
        end
        q.combat.spawnCooldown=0
        check(lp.authority:checkpointNow(),'pressure setup checkpoint failed')
        marker('host.pressure'); stage='pressure'
    elseif stage=='pressure' then
        -- Allow the production spawn -> expose -> windup -> shot sequence.
        -- Seed the documented RNG only at an actual committed guest windup;
        -- never write health/damage/hit results to manufacture a hit cue.
        if not pressureSeeded then for _,target in ipairs(q.targets) do
            if target.status=='firing' and not target.fired and target.targetActorId=='companion' then
                data.coop.randomState=1; pressureSeeded=true; break
            end
        end end
        if read('guest.pressure.hit') and not read('host.pressure.hit') then
            check(pressureSeeded and data.players.companion.health<pressureHealth and data.health==pressureHostHealth,
                'enemy pressure damaged wrong actor or guest cue had no host damage')
            check(state.paused and q.combat.defenders.companion.playerDamage>0,'guest pressure stopped under host pause')
            marker('host.pressure.hit')
        end
        if read('guest.pressure.cover') then
            local covered=tonumber(read('guest.pressure.cover.health'))
            check(q.combat.defenders.companion.ducking and data.players.companion.health==covered
                and data.health==pressureHostHealth,'incoming fire damaged a covered traveler or the host')
            check(data.ammo['22lr']==39 and data.players.companion.ammo['22lr']==38
                and q.shooterSessions.companion.loanAmmo==47,'enemy pressure changed ammunition pools')
            check(lp.authority:checkpointNow(),'pressure outcome checkpoint failed')
            local disk=assert(Save.read(99)); check(disk.lastStand.kills==simultaneousKills+1
                and disk.lastStand.combat.defenders.companion.playerDamage>0,'pressure settlement was not saved')
            marker('host.done'); stage='done'
        end
    elseif stage=='done' and read('guest.done') then finish() end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView; local panel=view and view.lastStand.shooter
    check(lp.phase~='idle' or not lp.error,'guest connection failed '..tostring(lp.error))
    if view and view.ready and lp.menuOpen and (stage=='joining' or stage=='reconnecting') then back() end
    if stage=='joining' and view and view:inputAllowed() then
        check(view.lastStand.scene.mode=='interior','guest interior missing')
        walk(view,'w'); stage='walk-up'
    elseif stage=='walk-up' and lp.motionFrame and lp.motionFrame.companion.y<300000 then
        walk(view,'d'); stage='walk-right'
    elseif stage=='walk-right' and lp.motionFrame and lp.motionFrame.companion.x>635000 then
        stopWalk(); stage='stop'
    elseif stage=='stop' and lp.motionFrame and lp.motionFrame.companion.vx==0 and lp.motionFrame.companion.vy==0 then
        local action=view.lastStand:action(); local pose=Life.pose(view.runtime.saveData,'companion')
        if not action or action.id~='window-tall' or not view:inputAllowed() then
            print('LAN_SHOOTER_SELECT_POSITION saved='..tostring(pose and pose.x)..','..tostring(pose and pose.y)
                ..' frame='..lp.motionFrame.companion.x..','..lp.motionFrame.companion.y
                ..' predicted='..view.runtime.player.x..','..view.runtime.player.y
                ..' action='..tostring(action and action.id)..' input='..tostring(view:inputAllowed()))
        end
        check(action and action.id=='window-tall' and view:inputAllowed(),'tall window interaction is not ready')
        if touch then press({x=580,y=580,w=350,h=45}) else button('e') end
        check(view.lastStand.pending and view.lastStand.pending.kind=='position','guest window selection not submitted')
        stage='selected'
    elseif stage=='selected' and not view.lastStand.pending and view.runtime.saveData.lastStand.firingPositions.companion=='tall' then
        check(view.runtime.saveData.lastStand.state=='interior','guest selection progressed scene'); marker('guest.selected'); capture='tall-selection'; stage='ready'
    elseif stage=='ready' and panel and panel:available() then
        local reply=lp.network.lastCommandResult
        if panel.pending and panel.pending.name=='lastStand.position' and reply and reply.requestId==panel.pending.id and reply.savePending then
            check(not panel:canAct() and not panel.position,'pending ready enabled fire'); marker('guest.ready.pending')
        end
        if panel:canAct() and read('host.target') and read('host.ready.retry') and read('host.paused') then
            local q=view.runtime.saveData.lastStand
            check(panel.gun and panel.gun.itemId and not panel.gun.borrowed,'guest firearm missing')
            ownGun=panel.gun.itemId; baselineMagazine=panel.gun.magazine
            check(q.combat.defenders.companion.windowId=='tall' and q.combat.defenders.host.windowId=='wide','private tall window missing')
            targetIndex,targetX,targetY=point('tall'); fire(panel,targetX,targetY)
            check(panel.pending and panel.pending.name=='gun.fire','guest fire was not submitted')
            shotId=panel.pending.id; capture='tall-shooter'; stage='shot'
        end
    elseif stage=='shot' then
        local reply=lp.network.lastCommandResult
        if panel.pending and panel.pending.name=='gun.fire' and reply and reply.requestId==panel.pending.id and reply.savePending then
            check(not panel.lastOutcome or not panel.lastOutcome.details or not panel.lastOutcome.details.fired,'pending shot presented confirmation')
            marker('guest.fire.pending')
        end
        local outcome=panel.lastOutcome
        if outcome and outcome.requestId==shotId and not outcome.ok then
            check(outcome.reason=='shooter_unavailable' or outcome.reason=='position_expired',
                'first shot rejected unexpectedly '..tostring(outcome.reason))
            stage='ready'; return
        end
        if not panel.pending and panel.lastOutcome and panel.lastOutcome.ok and panel.lastOutcome.details and panel.lastOutcome.details.fired then
            check(panel.lastOutcome.durable and panel.lastOutcome.details.hit and read('host.fire.retry'),'shot failed durable native hit')
            check(view.runtime.saveData.ammo['22lr']==39 and panel.gun.magazine==baselineMagazine-1,'shot charged twice or presentation missed cost')
            marker('guest.shot.saved'); capture='durable-shot'; stage='cover'
        end
    elseif stage=='cover' and read('host.shot.disk') and panel:canAct() and not panel.pending and love.timer.getTime()-submittedAt>.7 then
        commandKey(panel,'c'); submittedAt=love.timer.getTime(); stage='cover-wait'
    elseif stage=='cover-wait' and not panel.pending then
        local owner=view.runtime.saveData.lastStand.combat.defenders.companion
        if owner.ducking and owner.coverProgress>.95 then capture='personal-cover'; stage='uncover'
        elseif panel:canAct() and love.timer.getTime()-submittedAt>.7 then commandKey(panel,'c'); submittedAt=love.timer.getTime() end
    elseif stage=='uncover' and panel:canAct() and love.timer.getTime()-submittedAt>.7 then
        commandKey(panel,'c'); submittedAt=love.timer.getTime(); stage='uncover-wait'
    elseif stage=='uncover-wait' and not panel.pending and panel:canAct() and view.runtime.saveData.lastStand.combat.defenders.companion.coverProgress==0 then
        commandKey(panel,'r'); submittedAt=love.timer.getTime(); stage='reload'
    elseif stage=='reload' and not panel.pending and panel.gun.reloadTimer>0 then
        capture='personal-reload'; stage='reload-wait'
    elseif stage=='reload-wait' and panel:canAct() and panel.gun.reloadTimer==0 and love.timer.getTime()-submittedAt>1 then
        check(panel.gun.itemId==ownGun and view.runtime.saveData.ammo['22lr']==39,'reload changed identity or ammo')
        cachedMagazine=panel.gun.magazine; initialFireMode=panel.gun.fireMode
        commandKey(panel,'l'); submittedAt=love.timer.getTime(); stage='loan-supply'
    elseif stage=='loan-supply' and not panel.pending and panel:canAct() then
        local q=view.runtime.saveData.lastStand; local scope=q.shooterSessions.companion
        check(panel.lastOutcome and panel.lastOutcome.ok and panel.lastOutcome.command=='lastStand.supply',
            'guest loan supply command failed '..tostring(panel.lastOutcome and panel.lastOutcome.reason))
        check(panel.gun.borrowed and scope.loanActive and scope.loanAmmo==48 and view.runtime.saveData.ammo['22lr']==39,
            'guest loan supply changed own firearm ammunition or failed to supply 48 rounds')
        check(not q.loanActive and (q.loanAmmo or 0)==0 and view.runtime.saveData.players.host.ammo['22lr']==40,
            'guest loan supply changed host supplies')
        if love.timer.getTime()-submittedAt>.7 then
            targetIndex,targetX,targetY=point('tall'); fire(panel,targetX,targetY)
            check(panel.pending and panel.pending.name=='gun.fire','borrowed fire was not submitted')
            submittedAt=love.timer.getTime(); capture='personal-loan'; stage='borrowed-shot'
        end
    elseif stage=='borrowed-shot' and not panel.pending and panel:canAct() then
        local scope=view.runtime.saveData.lastStand.shooterSessions.companion
        check(panel.lastOutcome and panel.lastOutcome.ok and panel.lastOutcome.command=='gun.fire'
            and panel.lastOutcome.durable and panel.lastOutcome.details.fired,'borrowed shot failed')
        check(scope.loanAmmo==47 and view.runtime.saveData.ammo['22lr']==39 and view.runtime.saveData.players.host.ammo['22lr']==40,
            'borrowed shot consumed wrong pool or cost twice')
        if panel.gun.cooldown==0 and love.timer.getTime()-submittedAt>.7 then
            commandKey(panel,'tab'); submittedAt=love.timer.getTime(); stage='restore-owned'
        end
    elseif stage=='restore-owned' and not panel.pending and panel:canAct() then
        check(panel.lastOutcome and panel.lastOutcome.ok and panel.lastOutcome.command=='gun.select','owned weapon switch failed')
        check(not panel.gun.borrowed and panel.gun.itemId==ownGun and panel.gun.magazine==cachedMagazine
            and view.runtime.saveData.lastStand.shooterSessions.companion.loanAmmo==47,'weapon switch lost exact cached magazine or loan pool')
        if love.timer.getTime()-submittedAt>.7 then commandKey(panel,'v'); submittedAt=love.timer.getTime(); stage='mode-change' end
    elseif stage=='mode-change' and not panel.pending and panel:canAct() then
        check(panel.lastOutcome and panel.lastOutcome.ok and panel.lastOutcome.command=='gun.mode' and panel.gun.fireMode~=initialFireMode,
            'mode control did not change personal fire mode')
        check(panel.gun.itemId==ownGun and panel.gun.magazine==cachedMagazine and view.runtime.saveData.ammo['22lr']==39,
            'mode change altered gun identity or ammunition')
        capture='personal-safe-mode'
        if love.timer.getTime()-submittedAt>.7 then commandKey(panel,'v'); submittedAt=love.timer.getTime(); stage='mode-restore' end
    elseif stage=='mode-restore' and not panel.pending and panel:canAct() and love.timer.getTime()-submittedAt>.7 then
        check(panel.lastOutcome and panel.lastOutcome.ok and panel.gun.fireMode==initialFireMode
            and panel.gun.itemId==ownGun and panel.gun.magazine==cachedMagazine,'mode control did not restore original gun mode')
        local life=view.runtime.saveData.lastStand.lifecycle
        denyId=assert(lp.network:submitCommand('lastStand.withdraw',{questId=life.entityId,revision=life.revision},view.epoch,{}))
        stage='story-deny'
    elseif stage=='story-deny' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==denyId then
        check(not lp.network.lastCommandResult.ok and lp.network.lastCommandResult.reason=='host_only','guest was allowed to withdraw host story')
        marker('guest.controls.saved'); stage='disconnect'
    elseif stage=='disconnect' and read('host.controls.disk') then
        baselineMagazine=tonumber(read('host.controls.disk')); firstGeneration=view.motionId
        lp:stop('fixture_rejoin'); menu(); click('join'); stage='reconnecting'
    elseif stage=='reconnecting' and lp.phase=='connected' and view and panel:canAct() then
        check(view.motionId~=firstGeneration and panel.position and not next(panel.held),'rejoin lacked fresh checked readiness')
        check(panel.gun.itemId==ownGun and panel.gun.magazine==baselineMagazine and view.runtime.saveData.ammo['22lr']==39,'rejoin refilled or replaced owned gun')
        check(view.runtime.saveData.lastStand.shooterSessions.companion.loanAmmo==47 and panel.gun.fireMode==initialFireMode,
            'rejoin refilled loan pool or changed fire mode')
        marker('guest.rejoined'); capture='rejoined-tall'; stage='simultaneous'
    elseif stage=='simultaneous' and read('host.simultaneous') and panel:canAct()
        and view.runtime.saveData.coop.revision>=tonumber(read('host.simultaneous.revision')) then
        simultaneousIndex=tonumber(read('host.simultaneous'))
        local target=view.runtime.saveData.lastStand.targets[simultaneousIndex]
        if target.status=='exposed' and target.health==1 then
            simultaneousGuestX,simultaneousGuestY=Window.slotPosition(Window.layout('tall',960,720),simultaneousIndex)
            fire(panel,simultaneousGuestX,simultaneousGuestY); check(panel.pending,'simultaneous guest shot not submitted')
            shotId=panel.pending.id; marker('guest.simultaneous.sent'); submittedAt=love.timer.getTime(); stage='simultaneous-wait'
        end
    elseif stage=='simultaneous-wait' and not panel.pending and read('host.simultaneous.fired') then
        local result=panel.lastOutcome
        if result and result.requestId==shotId and not result.ok then
            check(result.reason=='stale_revision','simultaneous guest shot rejected '..tostring(result.reason))
            if panel:canAct() and love.timer.getTime()-submittedAt>.7 then
                fire(panel,simultaneousGuestX,simultaneousGuestY); check(panel.pending,'stale simultaneous shot retry not submitted')
                shotId=panel.pending.id; submittedAt=love.timer.getTime()
            end
        elseif result and result.requestId==shotId and result.ok and result.durable
            and view.runtime.saveData.ammo['22lr']==38 and view.runtime.saveData.players.host.ammo['22lr']==39 then
            check(view.runtime.saveData.ammo['22lr']==38 and view.runtime.saveData.players.host.ammo['22lr']==39
                and view.runtime.saveData.lastStand.shooterSessions.companion.loanAmmo==47,'simultaneous costs did not arrive in reliable projection')
            marker('guest.simultaneous.saved'); capture='tall-shared-settlement'; stage='pressure'
        end
    elseif stage=='pressure' and read('host.pressure') then
        local effects=lp.lastStandEffects and lp.lastStandEffects:get()
        if panel.hitFeedback>0 and panel.damageNotice and effects then
            for _,event in ipairs(effects.events) do if event.actorId=='companion' and event.windowId=='tall' and event.hit then
                marker('guest.pressure.hit'); pressureSerial=event.serial; capture='personal-incoming-hit'; stage='pressure-cover'; break
            end end
        end
    elseif stage=='pressure-cover' and read('host.pressure.hit') and panel:canAct() and not panel.pending then
        commandKey(panel,'c'); submittedAt=love.timer.getTime(); stage='pressure-cover-wait'
    elseif stage=='pressure-cover-wait' and not panel.pending then
        local owner=view.runtime.saveData.lastStand.combat.defenders.companion
        if owner.ducking and owner.coverProgress>.95 then
            local effects=lp.lastStandEffects and lp.lastStandEffects:get()
            for _,event in ipairs(effects and effects.events or {}) do pressureSerial=math.max(pressureSerial,event.serial) end
            pressureHealth=view.runtime.saveData.health; stage='pressure-covered'; capture='personal-incoming-cover'
        end
    elseif stage=='pressure-covered' then
        local effects=lp.lastStandEffects and lp.lastStandEffects:get()
        if effects then for _,event in ipairs(effects.events) do
            if event.serial>pressureSerial and event.actorId=='companion' and event.windowId=='tall' and not event.hit then
                check(view.runtime.saveData.health==pressureHealth,'covered enemy shot changed personal health')
                marker('guest.pressure.cover.health',pressureHealth); marker('guest.pressure.cover'); stage='done'; break
            end
        end end
    elseif stage=='done' and read('host.done') then
        check(not c.runtime.saveData,'guest acquired writable campaign'); marker('guest.done'); finish()
    end
end
local function update(dt)
    if finished or not app then return end
    app.update(math.min(.05,dt)); if role=='host' then hostUpdate() else guestUpdate() end
    if love.timer.getTime()-lastReport>4 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        print('LAN_LAST_STAND_SHOOTER_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)..' error='..tostring(lp.error))
    end
    check(love.timer.getTime()-started<110,'fixture timed out at '..tostring(stage))
end
local function guard(fn,...)
    local args={...}
    local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guard(load) end
function love.update(dt) guard(update,dt) end
function love.draw()
    if not app or finished then return end
    guard(function()
        app.draw()
        if capture and not captures[capture] then
            local name=role..'-'..capture..'.png'
            love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
            end)
            captures[capture]=true
        end
        capture=nil
    end)
end
