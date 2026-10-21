-- Two ordinary, independent thirty-second courses through actual application
-- controls. Only initial isolated save/equipment/positions are seeded.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema'); local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Range=require('game.shooting_range'); local State=require('game.coop_range_state')
local Codec=require('game.net.codec'); local Receipts=require('game.coop_receipts')
local Viewport=require('game.viewport'); local Aim=require('game.mobile_weapon_aim')
local app,c,started,stage,finished,capture,movementKey,oldKeyboard,restoreWrite
local captures={}; local writtenCaptures={}; local lastReport=0; local configured=false; local configuredGuest=0
local baseAmmo,baseScrap,baseGoodwill,ownItem,ownRound,partial,oldSession,oldMotion,ownClock
local firstShot=false; local reloadSent=false; local lastInput=0
local pausedChecked=false; local pausedTime; local hostPauseTime
local ammoRequestId; local ammoAttempts=0
local priorStage; local stageAt=0
local commandNames={}; local lastOutcome
local function check(v,message) assert(v,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function button(key) app.keypressed(key); app.keyreleased(key); lastInput=love.timer.getTime() end
local function press(r)
    check(r,'missing control '..tostring(stage)); local x,y=coords(r.x+r.w/2,r.y+r.h/2)
    if touch then app.touchpressed('control',x,y); app.touchreleased('control',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
    lastInput=love.timer.getTime()
end
local function rangePress(r)
    if role=='host' then r=require('game.ui_layout').transformRectFor('shootingRange',{x=0,y=0,w=960,h=720},r) end
    return press(r)
end
local function rangeCoords(x,y)
    if role=='host' then
        local r=require('game.ui_layout').transformRectFor('shootingRange',{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0})
        x,y=r.x,r.y
    end
    return coords(x,y)
end
local function pendingCommand()
    local lp=c.ui.localPlay; local p=lp.authority and lp.authority.pendingSave
    if not p then return nil end
    local receipt=p.actorId and Receipts.find(c.runtime.saveData,p.actorId,lp.authority.sessionId,p.requestId)
    local request=receipt and Codec.decode(receipt.fingerprint,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128})
    return p,request and request.command
end
local function proof()
    local lp=c.ui.localPlay
    if role=='guest' and lp.clientView then
        local view=lp.clientView; local panel=view.range; local frame=lp.motionFrame; local data=view.runtime.saveData
        print('LAN_RANGE_PROOF opened='..tostring(panel.opened)..' paused='..tostring(panel.paused)..' serverPaused='..tostring(panel.serverPaused)
            ..' desiredPaused='..tostring(panel:desiredPaused())..' manage='..tostring(panel:canManage())..' act='..tostring(panel:canAct())
            ..' ready='..tostring(view.ready)..' focused='..tostring(view.focused)..' menu='..tostring(lp.menuOpen)
            ..' scene='..tostring(view.runtime.scene)..' panelEpoch='..tostring(panel.epoch)..' viewEpoch='..tostring(view.epoch)
            ..' dataEpoch='..tostring(data and data.coop.sceneEpoch)..' frameEpoch='..tostring(frame and frame.sceneEpoch)
            ..' panelMotion='..tostring(panel.leaseMotionId)..' viewMotion='..tostring(view.motionId)..' frameMotion='..tostring(frame and frame.motionId)
            ..' frameDomain='..tostring(frame and frame.domain)..' lease='..tostring(panel.leaseId)
            ..' remaining='..tostring(panel.expiresAt and panel.expiresAt-panel:now())..' networkSame='..tostring(panel.network==lp.network)
            ..' netPending='..tostring(lp.network.pendingCommand and lp.network.pendingCommand.command))
    elseif role=='host' then
        local model=c.runtime.shootingRange; local saved=State.session(c.runtime.saveData,'host')
        local checked=lp.context.commands.rangeView('host')
        local resource=saved and State.resource(saved.spotId,'host'); local lease=resource and lp.authority.activityState.resources[resource]
        print('LAN_RANGE_HOST_PROOF state='..tostring(c.runtime.state)..' scene='..tostring(c.runtime.scene)
            ..' model='..tostring(model~=nil)..' modelPhase='..tostring(model and model.phase)..' modelRound='..tostring(model and model.roundRevision)
            ..' savedRound='..tostring(saved and saved.roundRevision)..' checkedView='..tostring(checked~=nil)
            ..' lease='..tostring(lease and lease.id)..' leasePaused='..tostring(lease and lease.payload and lease.payload.paused)
            ..' checkpoint='..tostring(c.session.checkpointPending)..' esc='..tostring(c.ui.escMenuOpen)..' options='..tostring(c.ui.optionsOpen)
            ..' focused='..tostring(lp.focused)..' menu='..tostring(lp.menuOpen)..' epoch='..c.runtime.saveData.coop.sceneEpoch
            ..' motionReady='..tostring(lp.motion and lp.motion.readyEpoch)..' motionEpoch='..tostring(lp.motion and lp.motion.epoch))
    end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(id,text) app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); button('return') end end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function input(key,rect) if touch and rect then rangePress(rect) else button(key) end end
local function stopWalk(view)
    movementKey=nil
    if touch and view then app.touchreleased('walk',0,0); view:neutralize() end
end
local function walkGuest(view)
    if touch then
        app.draw(); local stick=view.mobile.joystick; local x,y=coords(stick.x,stick.y)
        app.touchpressed('walk',x,y); x,y=coords(stick.x,stick.y-stick.radius*.95); app.touchmoved('walk',x,y,0,0)
    else movementKey='w' end
end
local function interact(view)
    if touch and view then
        app.draw(); check(view.ui.guestRange,'actual range proximity button missing'); press(view.ui.guestRange)
    else button('e') end
end
local function fire(model,x,y)
    if touch then
        local ax,ay=Aim.gripForAim(model.weapon,model.aimMode=='sights' and 'sights' or 'hip',x,y,960,720)
        local gx,gy=rangeCoords(ax,ay); app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0)
        rangePress({x=410,y=654,w=132,h=42}); app.touchreleased('aim',gx,gy)
    else local gx,gy=rangeCoords(x,y); app.mousemoved(gx,gy,0,0,false); app.mousepressed(gx,gy,1,false); app.mousereleased(gx,gy,1,false) end
    lastInput=love.timer.getTime()
end
local function target(model)
    for _,t in ipairs(model.targets) do
        if not t.hit and t.age>.2 and (t.permanent or t.life>.2) then
            local zoom=Range.magnification(model)
            return 480+(t.x-480)*zoom,330+(t.y-330)*zoom
        end
    end
end
local function finish()
    if finished then return end; finished=true; movementKey=nil
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' range=true independentLanes=true actualThirtySecondCourses=2'
        ..' actualControls=true stopMelee=true ammoSaveRetry=true partialMagazineResume=true reconnect=true sharedRewardOnce=true privatePause=true'
        ..' input='..(touch and 'touch-with-host-world-key-movement' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown; love.keyboard.isDown=function(key,...)
        if key==movementKey then return true end; return oldKeyboard(key,...)
    end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        Save.remove(1); c.runtime.selectedSlot=1
        local draft=c.newSave(c.characters[1]); draft.location=2; draft.scene='stop'; draft.stopped=true; draft.passengers={}
        -- This fixture starts after the home-yard tutorial.
        draft.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        check(c.enterGame(draft),'initial canonical save seed failed')
        local data=c.runtime.saveData
        data.scene='stop'; data.location=2; data.stopped=true; c.runtime.scene='stop'; c.runtime.state='game'
        local layout=c.ensureStopLayout(); local spot=layout and layout.shootingRange
        check(spot,'actual stop range not initialized'); data.playerX,data.playerY=spot.x-20,spot.y
        c.runtime.player.x,c.runtime.player.y=data.playerX,data.playerY
        Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=40
        Items.write(data,nil,{kind='inventory',index=1},'monocular'); data.scrap=10; baseGoodwill=data.goodwill; baseScrap=data.scrap
        check(require('game.coop_entities').ensure(data),'initial range entity indexing failed')
        check(Items.ensure(data),'initial stop gear indexing failed')
        check(Schema.validate(data),'initial range seed violated canonical save invariants')
        file('base.goodwill',baseGoodwill); check(Save.write(1,data),'isolated seed save failed')
        c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.shootingRange=nil
        local place=lp.context.placeCompanion; lp.context.placeCompanion=function(campaign)
            local ok,why=place(campaign); if not ok then return ok,why end
            local own=Players.forActor(campaign,'companion'); local range=campaign.stopLayouts['2'].shootingRange
            own.playerX,own.playerY=range.x+20,range.y
            check(Items.ensure(campaign),'companion ownership seed failed'); return true
        end
        lp.port=port; c.runtime.state='slots'; app.update(0); menu(); click('saveSlot'); click('slot_1'); click('host'); back()
        check(lp.network and c.session.networkMode=='host','actual title saved-host entry failed')
        local remote=lp.network.context.command
        lp.network.context.command=function(generation,request)
            local reply=remote(generation,request)
            if request.command:match('^range%.') then
                print('LAN_RANGE_COMMAND requestId='..request.requestId..' name='..request.command
                    ..' action='..tostring(request.args.action)..' lease='..tostring(request.args.leaseId)
                    ..' ok='..tostring(reply and reply.ok)..' durable='..tostring(reply and reply.durable)
                    ..' savePending='..tostring(reply and reply.savePending)..' reason='..tostring(reply and reply.reason))
            end
            return reply
        end
        stage='first-host-open'; print('LAN_SMOKE_LISTENING')
    else
        Save.remove(1); local own=c.newSave(c.characters[2] or c.characters[1])
        Items.write(own,nil,{kind='inventory',index=1},'monocular')
        Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); own.ammo['22lr']=40
        check(Items.ensure(own) and Save.write(1,own),'guest range save seed failed')
        c.runtime.state='slots'; menu(); click('address','127.0.0.1:'..port); click('name','Range friend')
        click('saveSlot'); click('slot_1'); click('join')
        check(lp.network,'guest join failed '..tostring(lp.error)); stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local model=c.runtime.shootingRange
    local own=State.session(data,'host'); local guest=State.session(data,'companion')
    if lp:pending() then menu(); click('approve'); check(not lp.error,'approval failed '..tostring(lp.error)); back() end
    if stage=='first-host-open' and file('guest.ready') then
        interact(); check(c.runtime.shootingRange,'actual host range interaction did not open'); file('host.lobby','true'); stage='guest-world-move'
    elseif stage=='guest-world-move' and file('guest.moved') then
        check(own and own.phase=='lobby' and not guest,'guest world movement accidentally opened host lane')
        button('e'); stage='guest-open'
    elseif stage=='guest-open' and file('guest.opened') and not c.runtime.shootingRange then
        ownClock=c.runtime.player.y; movementKey='w'; stage='host-world-move'
    elseif stage=='host-world-move' and c.runtime.player.y<ownClock-15 then
        stopWalk(); check(guest and guest.phase=='lobby','guest private range prevented independent host world movement')
        file('host.moved','true'); interact(); check(c.runtime.shootingRange,'host range reopen failed'); stage='config'
    elseif stage=='config' and model and model.phase=='lobby' then
        if not configured then rangePress({x=218,y=434,w=62,h=46}); configured=true; return end
        check(own.stageLength==30,'host duration control did not select thirty seconds')
        file('host.configured','true'); if file('guest.ammo.prepare') then
            restoreWrite=love.filesystem.write; love.filesystem.write=function(path,...)
                local p,name=pendingCommand(); local campaign=c.runtime.saveData
                if path==Save.path(1)..'.tmp' and p and p.actorId=='companion' and name=='range.ammo'
                    and campaign.players.companion.ammo['22lr']==58 and campaign.scrap==7 then
                    print('LAN_RANGE_AMMO_SAVE_FAIL actor='..p.actorId..' requestId='..p.requestId..' name='..name..' ammo=58 scrap=7')
                    return false,'range fixture ammo checkpoint failure'
                end
                return restoreWrite(path,...)
            end
            file('host.ammo.fail.ready','true'); stage='ammo-fail'
        end
    elseif stage=='ammo-fail' and c.session.checkpointPending then
        local p,name=pendingCommand()
        print('LAN_RANGE_PENDING actor='..tostring(p and p.actorId)..' requestId='..tostring(p and p.requestId)
            ..' name='..tostring(name)..' ammo='..tostring(data.players.companion.ammo['22lr'])..' scrap='..tostring(data.scrap))
        check(p and p.actorId=='companion' and name=='range.ammo','failure injection did not isolate the guest ammo command')
        check(data.players.companion.ammo['22lr']==58 and data.scrap==7,'ammo draft did not charge exactly once')
        file('host.ammo.pending','true'); capture='ammo-save-retry'; stage='ammo-retry'
    elseif stage=='ammo-retry' and file('guest.ammo.wait') then
        love.filesystem.write=restoreWrite; restoreWrite=nil; button('r')
        check(not c.session.checkpointPending,'real checkpoint Retry R failed'); file('host.ammo.saved','true'); stage='start'
    elseif stage=='start' and file('guest.configured') then
        if not model then interact()
        elseif model.phase=='lobby' then input('return',{x=500,y=542,w=275,h=54})
        elseif model.phase=='play' then stage='first-round' end
    elseif stage=='first-round' and model and own.phase=='play' then
        check(own.clock<5 or own.hits>0,'host has no actual hit after five seconds of live course time')
        if file('guest.paused') and not file('host.pause.checked') then
            hostPauseTime=hostPauseTime or own.time
            if hostPauseTime-own.time>.6 then file('host.pause.checked','true') end
        end
        if not firstShot and own.cooldown<=0 then local x,y=target(model); if x then fire(model,x,y); firstShot=own.shots>0 end end
        if own.hits>0 then file('host.hit','true') end
        if own.time<15 and not captures['independent-round'] then capture='independent-round' end
    elseif stage=='first-round' and own and own.phase=='results' and file('guest.result.1') then
        check(own.hits==1 and guest.hits==1 and data.goodwill==baseGoodwill+1,'shared first-tier reward was applied more than once')
        check(own.weapon~=nil and guest.weapon~=nil and own.entityId~=guest.entityId,'lanes shared an identity')
        capture='shared-first-result'; stage='first-result-capture'
    elseif stage=='first-result-capture' and writtenCaptures['shared-first-result'] then
        check(model and model.phase=='results' and own.result,'first result changed before its screenshot completed')
        button('return'); file('host.result.1','true'); stage='replay'
    elseif stage=='replay' and file('guest.replay.ready') and model and model.phase=='lobby' then
        input('return',{x=500,y=542,w=275,h=54}); firstShot=false; stage='second-round'
    elseif stage=='second-round' and own.phase=='play' and model then
        if not firstShot and own.cooldown<=0 and own.reloadTimer<=0 then local x,y=target(model); if x then fire(model,x,y); firstShot=own.shots>0 end end
    elseif stage=='second-round' and own.phase=='lobby' and model then input('return',{x=500,y=542,w=275,h=54})
    elseif stage=='second-round' and own.phase=='results' and file('guest.result.2') then
        check(data.goodwill==baseGoodwill+1 and own.result.gained==0 and guest.result.gained==0,'replay repeated shared tier reward')
        check(data.scrap==7 and data.players.companion.ammo['22lr']==53,'guest ammo charge or actual shot count duplicated')
        local disk=assert(Save.read(1)); check(disk.goodwill==data.goodwill and disk.scrap==7 and disk.players.companion.ammo['22lr']==53,'range outcomes not durable')
        capture='repeat-result'; stage='second-result-capture'
    elseif stage=='second-result-capture' and writtenCaptures['repeat-result'] then
        button('e'); check(not c.runtime.shootingRange,'host range did not close')
        check(c.ui.transitionParty('scene.returnTrain').ok,'host could not board independently')
        check(Players.forActor(data,'companion').scene=='stop','host boarding pulled client out of range')
        file('host.away','true'); stage='away'
    elseif stage=='away' and file('guest.alone.hit') then
        check(c.runtime.scene=='train' and guest.hits==1 and guest.clock>=1,'client range stopped while host was aboard')
        file('host.alone.checked','true'); stage='returning'
    elseif stage=='returning' and file('guest.returned') then
        check(data.players.companion.travelIdentity.status=='closed','range traveler return not acknowledged')
        check(data.players.companion.ammo['22lr']==52,'independent range shot did not consume personal ammo')
        file('host.done','true'); stage='done'
    elseif stage=='done' and file('guest.done') then finish() end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView
    if stage=='returning' and lp.phase=='idle' then
        local saved=assert(Save.read(1)); check(not require('game.coop_traveler').isAway(saved) and saved.ammo['22lr']==52,'range progress did not return to local slot')
        file('guest.returned','true'); stage='returned'
    end
    if stage=='returned' and file('host.done') then file('guest.done','true'); finish(); return end
    if not view or not view.ready then return end
    if lp.menuOpen and (stage=='joining' or stage=='rejoin') then back() end
    local panel=view.range; local s=panel:state(); local model=panel.model
    if panel.lastOutcome and panel.lastOutcome~=lastOutcome then
        lastOutcome=panel.lastOutcome
        print('LAN_RANGE_CHECKED_REPLY requestId='..lastOutcome.requestId..' name='..tostring(commandNames[lastOutcome.requestId])
            ..' ok='..tostring(lastOutcome.ok)..' durable='..tostring(lastOutcome.durable)..' reason='..tostring(lastOutcome.reason))
    end
    if ({start=true,['first-round']=true,['pause-request']=true,['pause-held']=true,['pause-resume']=true,
        resumed=true,reload=true,result=true,['second-round']=true,['capture-reopened']=true,['replay-starting']=true})[stage] then
        check(panel:available(),'ordinary practice UI closed unexpectedly at '..stage)
    end
    check(not c.runtime.saveData,'guest acquired writable campaign')
    if stage=='joining' and view:inputAllowed() then
        app.draw()
        local attackRect=view.ui.guestFieldAttack
        if touch then
            local key=view.mobile.secondaryAction()
            local control=key=='space' and view.mobile.secondary or view.mobile.primary
            check(key=='space' or view.mobile.primaryAction()=='space','ordinary-stop touch melee missing')
            attackRect={x=control.x-control.radius,y=control.y-control.radius,w=control.radius*2,h=control.radius*2}
        end
        check(attackRect,'ordinary-stop melee control missing'); input('space',attackRect)
        check(view.field.pending,'stop swing control did not submit an owned attack')
        stage='stop-swing'
    elseif stage=='stop-swing' and not view.field.pending and view.field.lastOutcome then
        check(view.field.lastOutcome.ok and view.field.lastOutcome.durable,'ordinary-stop swing failed')
        check(view.runtime.saveData.roamingCombat.actors.companion.areaId=='stop:2','stop swing saved in wrong scene')
        check(view.field:presentation('companion').actionTimer>0,'stop swing animation missing')
        capture='stop-swing'
        file('guest.ready','true'); stage='host-open'
    end
    if stage=='host-open' and file('host.lobby') then
        ownClock=lp.motionFrame.companion.y; walkGuest(view); stage='guest-world-move'
    elseif stage=='guest-world-move' and lp.motionFrame.companion.y<ownClock-15000 then
        stopWalk(view); file('guest.moved','true'); stage='guest-open'
    elseif stage=='guest-open' and view:inputAllowed() and not panel.pending then interact(view); stage='guest-acquire'
    elseif stage=='guest-acquire' and panel:canAct() then
        check(s.phase=='lobby' and not view:inputAllowed() and view.runtime.shootingRange,'guest independent lobby/readiness missing')
        ownItem=s.itemId; baseAmmo=view.runtime.saveData.ammo['22lr']; baseScrap=view.runtime.saveData.scrap
        file('guest.opened','true'); stage='config'
    elseif stage=='config' and file('host.moved') and panel:canAct() and love.timer.getTime()-lastInput>.15 then
        local rows={{kind='length',field='stageLength',value=30,x=218,y=434},{kind='motion',field='motion',value='moving',x=680,y=234},
            {kind='material',field='material',value='steel',x=680,y=284},{kind='distance',field='distance',value=75,x=680,y=384}}
        local row=rows[configuredGuest+1]
        if row then
            if s[row.field]==row.value then configuredGuest=configuredGuest+1
            else press({x=row.x,y=row.y,w=62,h=46}) end
        else
            check(s.stageLength==30 and s.motion=='moving' and s.material=='steel' and s.distance==75,'guest six-option controls did not configure private course')
            file('guest.ammo.prepare','true'); stage='ammo-prepare'
        end
    elseif stage=='ammo-prepare' and file('host.ammo.fail.ready') and panel:canAct() and love.timer.getTime()-lastInput>.6 then
        input('b',{x=185,y=542,w=290,h=54}); check(panel.pending and panel.pending.name=='range.ammo','actual guest ammo purchase missing')
        ammoRequestId=panel.pending.id; ammoAttempts=ammoAttempts+1; check(ammoAttempts<=8,'bounded ammo request retries exhausted'); stage='ammo-pending'
    elseif stage=='ammo-pending' and file('host.ammo.pending') then
        check(panel.pending and view.runtime.saveData.ammo['22lr']==baseAmmo and view.runtime.saveData.scrap==baseScrap,'guest predicted unsaved ammo/cost')
        file('guest.ammo.wait','true'); capture='unsaved-ammo-wait'; stage='ammo-saved'
    elseif stage=='ammo-pending' and not panel.pending and panel.lastOutcome and panel.lastOutcome.requestId==ammoRequestId then
        local reply=panel.lastOutcome
        print('LAN_RANGE_AMMO_REPLY requestId='..ammoRequestId..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason)
            ..' ammo='..view.runtime.saveData.ammo['22lr']..' scrap='..view.runtime.saveData.scrap)
        check(not reply.ok,'accepted ammo purchase did not reach the injected checkpoint barrier')
        check(reply.reason=='rate_limited' or reply.reason=='stale_revision' or reply.reason=='lease_expired'
            or reply.reason=='lease_owner' or reply.reason=='range_not_ready','unexpected ammo rejection '..tostring(reply.reason))
        check(view.runtime.saveData.ammo['22lr']==baseAmmo and view.runtime.saveData.scrap==baseScrap,'rejected ammo purchase changed supplies')
        stage='ammo-prepare'
    elseif stage=='ammo-saved' and file('host.ammo.saved') and not panel.pending and view.runtime.saveData.ammo['22lr']==58 then
        check(view.runtime.saveData.scrap==7,'saved purchase charged twice'); file('guest.configured','true'); stage='start'
    elseif stage=='start' and panel:canAct() and s.phase=='lobby' then
        input('return',{x=500,y=542,w=275,h=54}); stage='first-round'
    elseif stage=='first-round' and panel:canAct() and s.phase=='lobby' then
        input('return',{x=500,y=542,w=275,h=54})
    elseif stage=='first-round' and panel:canAct() and s.phase=='play' and s.cooldown<=0 and s.reloadTimer<=0 then
        check(s.clock<5 or s.hits>0,'guest has no actual hit after five seconds of live course time')
        if not pausedChecked then input('p',panel:pauseRect()); stage='pause-request'; return end
        if s.shots==0 then
            if not panel.pose.monocularActive then input('o',{x=366,y=50,w=228,h=40}); return end
            local x,y=target(model); if x then fire(model,x,y) end
        elseif s.hits>=1 and s.shots<4 then fire(model,480,110)
        elseif s.shots==4 then
            check(s.hits==1 and view.runtime.saveData.ammo['22lr']==54,'guest actual hit/cost evidence missing')
            partial=s.loaded; ownRound=s.roundRevision; ownClock=s.clock
            input('e',{x=816,y=654,w=126,h=42}); stage='closed'
        end
    elseif stage=='pause-request' and not panel.pending and panel.serverPaused==true then
        pausedTime=s.time; file('guest.paused','true'); capture='private-paused-lane'; stage='pause-held'
    elseif stage=='pause-held' and file('host.pause.checked') then
        check(s.time==pausedTime and s.shots==0 and not panel:canAct(),'guest pause did not freeze checked personal range clock')
        input('p',panel:pauseRect()); stage='pause-resume'
    elseif stage=='pause-resume' and panel:canAct() and panel.serverPaused==false then
        check(not next(panel.held),'unpause retained held firing'); pausedChecked=true; stage='first-round'
    elseif stage=='closed' and not panel:available() and view:inputAllowed() then
        check(s.loaded==partial and s.itemId==ownItem,'manual close refilled/replaced weapon'); interact(view); stage='reopened'
    elseif stage=='reopened' and panel:canAct() then
        check(s.loaded==partial and s.itemId==ownItem and s.roundRevision==ownRound and s.phase=='play','manual reopen reset partial round/gun')
        capture='partial-reopened'; stage='capture-reopened'
    elseif stage=='capture-reopened' and writtenCaptures['partial-reopened'] and panel:canAct() then
        check(model and model.phase=='play' and model.itemId==ownItem and model.loaded==partial
            and s.roundRevision==ownRound,'partial magazine changed before its screenshot completed')
        oldSession=lp.network.sessionId; oldMotion=view.motionId
        menu(); lp:stop('smoke_connection_drop'); menu(); click('join'); stage='rejoin'
    elseif stage=='rejoin' and lp.phase=='connected' and view:inputAllowed() then
        check(lp.network.sessionId==oldSession and view.motionId~=oldMotion,'manual rejoin did not renew actor motion generation')
        s=panel:state(); check(s.itemId==ownItem and s.loaded==partial and s.roundRevision==ownRound and view.runtime.saveData.ammo['22lr']==54,'disconnect/rejoin reset owned gun/pool/phase')
        interact(view); stage='resumed'
    elseif stage=='resumed' and panel:canAct() then
        check(not next(panel.held) and s.loaded==partial,'rejoin retained held fire or filled magazine')
        input('r',{x=18,y=654,w=126,h=42}); stage='reload'
    elseif stage=='reload' and not panel.pending and s.reloadTimer>0 then reloadSent=true; capture='owned-tube-reload'; stage='result'
    elseif stage=='result' and s.phase=='results' then
        check(reloadSent and s.hits==1 and s.shots==4 and s.result and view.runtime.saveData.ammo['22lr']==54,'personal first result/reload mismatch')
        file('guest.result.1','true'); capture='first-result'; stage='replay'
    elseif stage=='replay' and file('host.result.1') and panel:canAct() then
        ownRound=s.roundRevision; rangePress({x=238,y=548,w=150,h=58}); stage='replay-starting'
    elseif stage=='replay-starting' and panel:canAct() and s.phase=='results' and love.timer.getTime()-lastInput>.6 then
        rangePress({x=238,y=548,w=150,h=58})
    elseif stage=='replay-starting' and panel:canAct() and s.phase=='play' then
        check(s.roundRevision>ownRound and s.stageLength==30 and s.motion=='moving' and s.material=='steel'
            and s.distance==75 and s.targetPattern=='stay-up' and s.itemId==ownItem,'actual Replay button changed course setup or exact weapon')
        file('guest.replay.ready','true'); firstShot=false; stage='second-round'
    elseif stage=='second-round' and panel:canAct() and s.phase=='lobby' then input('return',{x=500,y=542,w=275,h=54})
    elseif stage=='second-round' and panel:canAct() and s.phase=='play' and s.cooldown<=0 and s.reloadTimer<=0 and s.shots==0 then
        local x,y=target(model); if x then fire(model,x,y) end
    elseif stage=='second-round' and s.phase=='results' then
        check(s.shots==1 and s.hits==1 and s.result.gained==0 and view.runtime.saveData.goodwill==tonumber(file('base.goodwill'))+1,'replay granted repeated reward')
        file('guest.result.2','true'); capture='repeat-result'; stage='done'
    elseif stage=='done' and file('host.away') and panel:canAct() then
        rangePress({x=238,y=548,w=150,h=58}); stage='alone-start'
    elseif stage=='alone-start' and s.phase=='results' and panel:canAct() and love.timer.getTime()-lastInput>.6 then
        rangePress({x=238,y=548,w=150,h=58})
    elseif stage=='alone-start' and s.phase=='play' and panel:canAct() then stage='alone'
    elseif stage=='alone' and panel:canAct() and s.phase=='play' then
        if s.shots==0 and s.cooldown<=0 and s.reloadTimer<=0 then local x,y=target(model); if x then fire(model,x,y) end end
        if s.hits==1 and s.clock>=1 then file('guest.alone.hit','true') end
        if file('host.alone.checked') then input('e',{x=816,y=654,w=126,h=42}); stage='alone-close' end
    elseif stage=='alone-close' and not panel:available() and view:inputAllowed() then
        check(lp:returnToSave(),'client range return failed'); stage='returning'
    end
end
local function update(dt)
    if not app or finished then return end
    if role=='guest' then
        local view=c.ui.localPlay.clientView; local pending=view and view.range.pending
        if pending then commandNames[pending.id]=pending.name end
    end
    app.update(math.min(.05,dt))
    if role=='host' then hostUpdate() else guestUpdate() end
    if stage~=priorStage then priorStage=stage; stageAt=love.timer.getTime(); proof() end
    if love.timer.getTime()-lastReport>3 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        local data=role=='host' and c.runtime.saveData or lp.clientView and lp.clientView.runtime.saveData
        local s=data and State.session(data,role=='host' and 'host' or 'companion')
        print('LAN_RANGE_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)
            ..' time='..tostring(s and s.time)..' shots='..tostring(s and s.shots)..' error='..tostring(lp.error))
        if role=='guest' and lp.clientView then
            local panel=lp.clientView.range; local p=panel.pending; local result=panel.lastOutcome
            print('LAN_RANGE_REQUEST pending='..tostring(p and p.name)..' requestId='..tostring(p and p.id)
                ..' lastRequest='..tostring(result and result.requestId)..' lastReason='..tostring(result and result.reason))
        end
        proof()
    end
    if stage=='start' and love.timer.getTime()-stageAt>8 then proof(); error('range controls not ready eight seconds after the saved purchase') end
    check(love.timer.getTime()-started<160,'range fixture timeout at '..tostring(stage))
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
            local label=capture; local name=role..'-'..label..'.png'; love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
                writtenCaptures[label]=true
            end); captures[capture]=true
        end
        capture=nil
    end)
end
