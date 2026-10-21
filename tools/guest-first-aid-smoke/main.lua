-- Production treatment gestures, real ENet, save failure and isolated saves.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Help=require('game.stop_help_progression'); local Quests=require('game.help_quest_session')
local Entities=require('game.coop_entities'); local Style=require('game.ui_layout')
local app,c,started,finished,stage,capture,restoreWrite,retried,held,lastAction,rejoinAt,questId,npc,hostGear,hostX,epoch,location
local activeFailure,activeAttempted,activeRetried,activeLease,activeRecovered
local captured={}; local connections=0; local generation; local moves={}; local moveIndex=1
local function check(value,message) assert(value,message) end
local function xy(x,y)
    local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy
end
local function pointer(action,x,y,other)
    local rect=Style.transformRectFor('firstAid',{x=105,y=40,w=750,h=635},{x=x,y=y,w=0,h=0}); x,y=xy(rect.x,rect.y)
    if touch then
        local id=other and 'unrelated-finger' or 'aid-test'
        if action=='press' then app.touchpressed(id,x,y); if not other then held=true end
        elseif action=='move' then app.touchmoved(id,x,y,0,0)
        else app.touchreleased(id,x,y); if not other then held=false end end
    elseif action=='press' then app.mousepressed(x,y,1,false); held=true
    elseif action=='move' then app.mousemoved(x,y,0,0,false)
    else app.mousereleased(x,y,1,false); held=false end
end
local function press(rect)
    check(rect,'missing first-aid control'); local x,y=xy(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('aid-test',x,y); app.touchreleased('aid-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true firstAid=true reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'; lp.port=port
    Save.remove(1)
    if role=='host' then
        c.runtime.selectedSlot=1
        local seed=c.newSave(c.characters[1]); seed.location=20; seed.scene='stop'; seed.stopped=true
        seed.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        seed.lastStand={state='complete',completed=true,rewardClaimed=true}
        seed.events['20']={id='resolved'}; seed.encounters['20']={hasMob=false,resolved=true}
        check(c.enterGame(seed),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=20; data.scene='stop'; c.runtime.scene='stop'; npc='crow-merchant.png'
        local layout=c.ensureStopLayout(); layout.npcOutside=npc; layout.npc=npc; c.setupNPC()
        c.runtime.npcActor.x=600; c.runtime.npcActor.y=430
        c.runtime.player.x=550; c.runtime.player.y=430; data.playerX=550; data.playerY=430
        -- The host has already accepted this assistance quest. No guest command accepts it.
        layout.helpRequests={}; local request=Help.ensureRequest(layout,npc,'aid',data.location,data)
        request.accepted=true; Quests.accept(data,request.sessionId); questId=request.sessionId
        Items.write(Players.forActor(data,'host'),nil,{kind='inventory',index=1},'field-bandage-roll')
        check(Items.ensure(data) and Entities.ensure(data),'patient fixture invalid')
        hostGear=data.players.host.itemSlots.equipment[1].id; hostX=c.runtime.player.x
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local actor=Players.forActor(campaign,'companion')
            actor.playerX=550; actor.playerY=430
            return true
        end
        check(Save.write(1,data),'host seed failed'); c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.state='slots'
        app.update(0); menu(); click('saveSlot'); click('slot_1'); click('host')
        hostX=c.runtime.player.x
        check(lp.network,'hosting failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        local seed=c.newSave(c.characters[2] or c.characters[1])
        for i=1,seed.inventoryCapacity do Items.write(seed,nil,{kind='inventory',index=i},nil) end
        Items.write(seed,nil,{kind='inventory',index=1},'field-bandage-roll')
        check(Save.write(1,seed),'guest seed failed')
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; app.update(0); menu(); click('address','127.0.0.1:'..port)
        click('name','Treatment test friend'); click('saveSlot'); click('slot_1'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<100,'treatment fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    local v=lp.clientView; local p=v and v.activities.firstAid
    local diagnostic=table.concat({tostring(stage),tostring(lp.phase),tostring(p and p.notice),
        tostring(p and p.session and p.session.phase),tostring(v and v.runtime.scene)},':')
    if diagnostic~=c.fixtureDiagnostic then print('LAN_AID_STATE '..role..' '..diagnostic); c.fixtureDiagnostic=diagnostic end
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            generation=link.generation; connections=connections+1
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(1) and (activeFailure or c.runtime.saveData.helpQuestSessions[questId].rewardClaimed) then return false,'injected treatment checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        local heldLease=lp.authority and lp.authority.activityState.resources['firstAid:'..questId]
        if heldLease and not captured.hostContention then
            local layout=c.runtime.saveData.stopLayouts[tostring(c.runtime.saveData.location)]
            local reply=lp.authority:submitLocal('firstAid.acquire',{targetId=layout.entityId,npc=npc})
            check(reply.reason=='activity_busy','host acquired guest patient'); captured.hostContention=true
            if lp.menuOpen then click('close') end
            local lease=heldLease.id; local boarded=c.ui.transitionParty('scene.returnTrain')
            check(boarded.ok,'host could not board independently: '..tostring(boarded.reason))
            check(lp.authority.activityState.resources['firstAid:'..questId].id==lease,'host boarding cancelled guest treatment')
            check(Players.forActor(c.runtime.saveData,'companion').scene=='stop','host boarding moved patient visit')
            hostX=c.runtime.player.x
        end
        if connections==2 and heldLease and heldLease.payload.session.phase==4 and not activeAttempted then
            activeAttempted=true; activeFailure=true; activeLease=heldLease.id
            check(not lp.authority:checkpointNow(),'active treatment checkpoint unexpectedly saved')
        end
        if activeRetried and heldLease and heldLease.id~=activeLease then activeRecovered=true end
        if restoreWrite and lp.authority.pendingSave and activeFailure and not captured['host-treatment-active-save-retry.png'] then
            capture='host-treatment-active-save-retry.png'; stage='save-retry-active'
        elseif restoreWrite and lp.authority.pendingSave and not activeFailure and not captured['host-treatment-save-retry.png'] then capture='host-treatment-save-retry.png'; stage='save-retry' end
        if stage=='save-retry-active' and captured['host-treatment-active-save-retry.png'] then
            activeFailure=false
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'active treatment save retry failed'); activeRetried=true; stage='hosting'
        end
        if stage=='save-retry' and captured['host-treatment-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'treatment save retry failed'); retried=true; stage='hosting'
        end
        if connections==1 and not link then
            local saved=assert(Save.read(1)); local q=saved.helpQuestSessions[questId]
            check(q.paused and q.progress.phase==3 and q.progress.rubDistance==90,'partial treatment not durable')
            check(saved.players.companion.inventory[1]=='field-bandage-roll' and saved.goodwill==0,'pause consumed supply or rewarded')
        elseif connections==2 and not link then
            local saved=assert(Save.read(1))
            check(retried and activeRetried and activeRecovered and captured.hostContention and saved.helpQuestSessions[questId].rewardClaimed,'treatment not committed or recovered')
            check(saved.goodwill==3 and #saved.helpHistory==1 and not saved.players.companion.inventory[1],'treatment repeated or omitted')
            check(saved.players.host.inventory[1]=='field-bandage-roll' and saved.players.host.itemSlots.equipment[1].id==hostGear and c.runtime.player.x==hostX,'host ownership changed')
            finish()
        end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local data=lp.replica.data; location=data.location; epoch=data.coop.sceneEpoch; npc=data.currentNPC
            questId=data.stopLayouts[tostring(location)].helpRequests[npc].sessionId
            capture='guest-treatment-world.png'; stage='open'
        elseif stage=='rejoin' and now-rejoinAt>1 then check(lp:join(),'credential reconnect failed'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); check(lp.replica.data.helpQuestSessions[questId].progress.rubDistance==90,'rejoin lost partial treatment'); stage='open-again'
        elseif stage=='returning' and not lp.network then
            local saved=assert(Save.read(1)); check(not saved.inventory[1],'medical supply returned after consumption')
            print('LAN_FIRST_AID_OK role=guest pointer=true hostClock=true partialRejoin=true checkpointRetry=true activeLeaseRecovery=true ownSupply=true independentScenes=true portableReturn=true'); finish()
        elseif lp.clientView and stage~='joining' and stage~='returning' then
            local view=lp.clientView; local panel=view.activities.firstAid
            if capture or lastAction and now-lastAction<.25 then return end
            if panel.pending or #panel.queue>0 then return end
            if stage=='open' or stage=='open-again' then
                if not view:inputAllowed() then return end
                app.draw(); if touch then press(view.ui.guestFirstAid) else app.gamepadpressed({},'dpdown') end
                check(panel.opened,'treatment did not open'); capture='guest-treatment-supply.png'; stage=stage=='open' and 'begin' or 'begin-again'
            elseif stage=='begin' or stage=='begin-again' then
                app.draw(); if touch then press(panel.beginRect) else app.keypressed('return'); app.keyreleased('return') end
                check(panel.pending and panel.pending.command=='firstAid.acquire','treatment did not start')
                stage=stage=='begin' and 'injury' or 'resume-rub'; lastAction=now
            elseif stage=='injury' and panel.session then
                check(panel.session.phase==1,'wrong initial phase'); pointer('press',512,420); pointer('release',512,420); stage='pour'; lastAction=now
            elseif stage=='pour' and panel.session.phase==2 then
                if touch then pointer('press',480,370) else pointer('move',480,370) end
                capture='guest-treatment-pour.png'; stage='wait-pour'; lastAction=now
            elseif stage=='wait-pour' and panel.session.phase==3 then
                if held then pointer('release',480,370) end; stage='partial-press'; lastAction=now
            elseif stage=='partial-press' then
                pointer('press',410,370); if touch then
                    local n=#panel.queue; pointer('move',550,370,true); check(#panel.queue==n,'unowned finger moved treatment')
                end
                stage='partial-move'; lastAction=now
            elseif stage=='partial-move' then pointer('move',500,370); pointer('release',500,370); stage='pause'; lastAction=now
            elseif stage=='pause' then
                check(panel.session.progress.rubDistance==90,'pointer progress missing')
                capture='guest-treatment-partial.png'; stage='pause-confirm'; lastAction=now
            elseif stage=='pause-confirm' then app.keypressed('escape'); app.keyreleased('escape'); stage='paused'; lastAction=now
            elseif stage=='paused' and not panel:busy() then check(lp:stop(),'temporary disconnect failed'); stage='rejoin'; rejoinAt=now
            elseif stage=='resume-rub' and panel.session then
                check(panel.session.phase==3 and panel.session.progress.rubDistance==90,'resumed phase missing')
                pointer('press',410,370); moves={550,410,550,410}; moveIndex=1; stage='rub'; lastAction=now
            elseif stage=='rub' then
                if panel.session.phase==4 then pointer('release',410,370); stage='ointment-press'
                else
                    local previous=moveIndex%2==1 and 410 or 550; local target=moves[moveIndex]
                    for i=1,70 do pointer('move',previous+(target-previous)*i/70,370) end
                    moveIndex=moveIndex+1; check(moveIndex<=5,'rub did not advance')
                end
                lastAction=now
            elseif stage=='ointment-press' then
                pointer('press',410,370); moveIndex=1; stage='ointment'; capture='guest-treatment-ointment.png'; lastAction=now
            elseif stage=='ointment' then
                if panel.session.phase==5 then pointer('release',480,370); stage='gauze'
                elseif not panel.session.dragging then
                    if held then pointer('release',410,370) end; pointer('press',410,370); moveIndex=1
                else
                    local previous=moveIndex%2==0 and 550 or 410; local target=moveIndex%2==0 and 410 or 550
                    for i=1,70 do pointer('move',previous+(target-previous)*i/70,370) end
                    moveIndex=moveIndex+1; check(moveIndex<=15,'ointment did not advance')
                end
                lastAction=now
            elseif stage=='gauze' then pointer('press',480,370); pointer('release',480,370); stage='wrap-press'; lastAction=now
            elseif stage=='wrap-press' then
                check(panel.session.phase==6,'gauze did not advance'); pointer('press',398,370); moves={562,398,562}; moveIndex=1
                stage='wrap'; capture='guest-treatment-wrap.png'; lastAction=now
            elseif stage=='wrap' then
                if panel.completed then stage='completed'; capture='guest-treatment-completed.png'
                elseif not panel.session.ready then pointer('move',moves[moveIndex],370); moveIndex=moveIndex+1; check(moveIndex<=4,'wrap did not complete'); lastAction=now end
            elseif stage=='completed' then
                check(panel.completed.gained==3 and view.runtime.saveData.goodwill==3,'completion receipt missing')
                check(view.runtime.saveData.scene=='stop' and view.runtime.saveData.location==location and view.runtime.saveData.coop.sceneEpoch==epoch,'treatment advanced story')
                app.draw(); press(panel.closeRect); menu(); click('leave')
                stage='returning'
            end
        end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw(); if capture then love.graphics.captureScreenshot(capture); captured[capture]=true; capture=nil end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
