-- Host decision controls and guest help in two complete ENet applications.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Style=require('game.ui_layout')
local Items=require('game.item_instances'); local Players=require('game.coop_players'); local Help=require('game.stop_help_progression')
local Entities=require('game.coop_entities'); local Contract=require('game.coop_item_contract')
local app,c,started,finished,stage,capture,restoreWrite,rejoinAt,epoch,weaponId,lastAction,diagnosticAt
local targets={}; local index=1; local connections=0; local generation; local captured={}
local kinds={'supplies','mail','ride','trade','aid','item','aid','item'}
local declines={[5]=true,[6]=true}; local moving=0; local walking=false
local denialNames={'quest.offer','quest.accept','quest.decline','passenger.recruit'}; local denialIndex=1; local denialId
local function check(value,message) assert(value,message) end
local function press(rect,dialogue)
    check(rect,'missing control: '..tostring(stage))
    if dialogue then rect=Style.transformRectFor('dialogue',{x=80,y=45,w=800,h=630},rect) end
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('quest-decision',x,y); app.touchreleased('quest-decision',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function stopWalk()
    moving=0; if walking then app.touchreleased('quest-walk',0,0); walking=false end
end
local function walk(view)
    if moving==0 or not touch or not view or not view:inputAllowed() then
        if walking then app.touchreleased('quest-walk',0,0); walking=false end
        return
    end
    if not walking then app.draw() end
    local stick=view.mobile.joystick; local ox,oy,sx,sy=Viewport.transform(960,720)
    if not walking then app.touchpressed('quest-walk',ox+stick.x*sx,oy+stick.y*sy); walking=true end
    check(view.mobile.joystickTouch=='quest-walk','touch joystick not captured')
    app.touchmoved('quest-walk',ox+(stick.x+stick.radius*.95*moving)*sx,oy+stick.y*sy,0,0)
end
local function residents(data)
    local result={}
    for _,npc in ipairs(data.npcRoster) do
        if not npc:lower():find('crow%-merchant') then result[#result+1]=npc; if #result==#kinds then break end end
    end
    check(#result==#kinds,'insufficient fixture residents'); return result
end
local function selectResident()
    local data=c.runtime.saveData; local layout=data.stopLayouts['20']; local npc=targets[index]
    layout.npcOutside=npc; layout.npc=npc; data.currentNPC=npc; c.setupNPC()
    c.runtime.npcActor.x=600; c.runtime.npcActor.y=430; c.runtime.npcActor.wait=100; c.runtime.npcActor.targetX=nil
    c.runtime.dialogue=nil; c.runtime.questOffer=nil; c.runtime.tradeOpen=false
    if index==3 then
        layout.npcWeapon='frontier-short-sword'; layout.npcWeaponInstance=nil; check(Items.ensure(data),'weapon fixture invalid')
        layout.npcWeaponInstance.durability=17; weaponId=layout.npcWeaponInstance.id
    end
    print('LAN_QUEST_HOST_INPUT focusBefore='..tostring(c.ui.localPlay.focused)
        ..' pausedBefore='..tostring(require('game.world_pause').isPaused(c.runtime,c.ui,nil,{allowDialogue=true})))
    app.focus(true)
    check(not require('game.world_pause').isPaused(c.runtime,c.ui,nil,{allowDialogue=true}),'host input remains paused')
    c.ui.refreshWorldInteraction()
    app.keypressed('e'); app.keyreleased('e')
    local history=c.ui.localPlay.authority.requests.host
    local last=history and history.cache[history.high]
    check(c.runtime.questOffer and c.runtime.questOffer.kind==kinds[index],'host talk did not offer '..kinds[index]
        ..' interaction='..tostring(c.ui.interaction and c.ui.interaction.kind)..' dialogue='..tostring(c.runtime.dialogue and c.runtime.dialogue.text)
        ..' reason='..tostring(last and last.response.reason))
    capture='host-offer-'..index..'.png'; stage='offered'
end
local function finish()
    if finished then return end; finished=true; stopWalk()
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true questDecisions=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    local keyboard=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for _,key in ipairs({...}) do
            if not touch and role=='guest' and (moving==1 and key=='d' or moving==-1 and key=='a') then return true end
        end
        return keyboard(...)
    end
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=20; data.scene='stop'; c.runtime.scene='stop'; targets=residents(data)
        local layout=c.ensureStopLayout(); layout.npcOffers={}; layout.helpRequests={}; layout.coopOffers=nil
        data.conversations={assignments={},completed={},seen={},nextStop=99}; data.mailQuests={}; data.supplyQuests={}; data.passengers={}
        for i,npc in ipairs(targets) do
            layout.npcOffers[npc]=kinds[i]
            if kinds[i]=='item' or kinds[i]=='aid' then
                local request=Help.ensureRequest(layout,npc,kinds[i],20,data)
                if kinds[i]=='item' then request.item='field-bandage-roll'; request.label='Field Bandage Roll' end
            end
        end
        layout.offerPolicyVersion=Help.policyVersion; layout.npcOutside=targets[1]; layout.npc=targets[1]; c.setupNPC()
        c.runtime.npcActor.x=600; c.runtime.npcActor.y=430; c.runtime.npcActor.wait=100; c.runtime.npcActor.targetX=nil
        c.runtime.player.x=550; c.runtime.player.y=430; data.playerX=550; data.playerY=430
        data.resources.food=30; data.resources.water=30; data.resources.coal=30; data.encounters['20']={hasMob=false,resolved=true}
        for slot=1,data.inventoryCapacity do Items.write(Players.forActor(data,'host'),nil,{kind='inventory',index=slot},nil) end
        check(Entities.ensure(data),'decision fixture invalid')
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local actor=Players.forActor(campaign,'companion')
            for slot=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=slot},nil) end
            Items.write(actor,nil,{kind='inventory',index=1},'field-bandage-roll')
            Items.write(actor,nil,{kind='inventory',index=2},'field-bandage-roll')
            actor.playerX=550; actor.playerY=430; return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error))
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Quest test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<105,'quest decision deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay
    if not diagnosticAt or now-diagnosticAt>10 then
        diagnosticAt=now; local view=lp.clientView
        print('LAN_QUEST_DECISION_STATE role='..role..' stage='..tostring(stage)..' index='..index..' phase='..tostring(lp.phase)
            ..' x='..tostring(view and view.runtime.player.x)..' ready='..tostring(lp.motionFrame and lp.motionFrame.ready)
            ..' paused='..tostring(lp.motionFrame and lp.motionFrame.paused)..' save='..tostring(lp.authority and lp.authority.pendingSave~=nil)
            ..' state='..tostring(c.runtime.state)..' scene='..tostring(c.runtime.scene)..' focus='..tostring(lp.focused))
    end
    if role=='host' then
        if lp:pending() then menu(); click('approve'); print('LAN_SMOKE_ADMITTED') end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        local data=c.runtime.saveData; local guest=data.players.companion
        if stage=='hosting' and guest and guest.playerX>558 then
            if lp.menuOpen then click('close') end
            epoch=data.coop.sceneEpoch; selectResident()
        elseif stage=='offered' and guest.playerX>628 and captured['host-offer-'..index..'.png'] then
            if index==8 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(99) and data.questAsked['20:'..targets[8]] then return false,'injected quest checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
            app.draw()
            if touch then press(declines[index] and c.ui.questDecline or c.ui.questAccept,true)
            else app.keypressed(declines[index] and 'n' or 'y'); app.keyreleased(declines[index] and 'n' or 'y') end
            local offer=data.stopLayouts['20'].coopOffers[targets[index]]
            check(offer.status==(declines[index] and 'declined' or 'accepted') and not c.runtime.questOffer,'host decision did not commit')
            check(data.coop.sceneEpoch==epoch and data.scene=='stop' and data.location==20,'decision progressed scene')
            if index==8 then
                check(lp.authority.pendingSave and not c.runtime.dialogue,'failed item acceptance did not clear choices and block saving')
                capture='host-quest-save-retry.png'; stage='retry'
            else stage='decided' end
        elseif stage=='retry' and captured['host-quest-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'quest save retry failed'); stage='decided'
        elseif stage=='decided' and (guest.playerX<560 or index==#kinds and data.stopLayouts['20'].helpRequests[targets[index]].complete) then
            if index<#kinds then index=index+1; selectResident() else stage='waiting-rejoin' end
        elseif stage=='waiting-rejoin' and connections==2 and not link then
            local saved=assert(Save.read(99)); local layout=saved.stopLayouts['20']
            for i,npc in ipairs(targets) do check(layout.coopOffers[npc].status==(declines[i] and 'declined' or 'accepted'),'saved decision missing') end
            check(#saved.mailQuests==1 and #saved.supplyQuests==1 and #saved.passengers==1,'duplicated or missing work')
            check(saved.passengers[1].weaponInstance.id==weaponId and saved.passengers[1].weaponInstance.durability==17,'recruitment lost weapon')
            check(layout.helpRequests[targets[8]].complete and saved.goodwill==2,'guest item help missing or repeated')
            check(saved.players.host.inventory[1]==nil and saved.players.companion.inventory[1]==nil
                and saved.players.companion.inventory[2]=='field-bandage-roll','incorrect pack consumption')
            local aid=saved.helpQuestSessions[layout.helpRequests[targets[7]].sessionId]
            check(aid.paused and not aid.rewardClaimed,'paused accepted treatment missing')
            print('LAN_QUEST_DECISIONS_OK role=host allOfferKinds=true hostControls=true recruitment=true checkpointRetry=true guestHelp=true')
            finish()
        end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); targets=residents(lp.replica.data); epoch=lp.replica.data.coop.sceneEpoch; moving=1; stage='wait-offer'
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif lp.clientView and stage~='joining' and stage~='rejoin' then
            local view=lp.clientView; local data=lp.replica.data; local npc=targets[index]; local layout=data.stopLayouts['20']
            local offer=layout.coopOffers and layout.coopOffers[npc]
            if stage=='wait-offer' and offer and offer.status=='offered' and data.currentNPC==npc then
                stopWalk(); app.keypressed('y'); app.keyreleased('y'); app.keypressed('n'); app.keyreleased('n')
                check(offer.status=='offered' and not data.questAsked['20:'..npc],'guest keys chose offer')
                capture='guest-host-offer-'..index..'.png'
                if index==1 then stage='denial' else moving=1; stage='wait-decision' end
            elseif stage=='denial' then
                if not denialId then
                    local name=denialNames[denialIndex]
                    denialId=assert(lp.network:submitCommand(name,{targetId=layout.entityId,npc=npc,kind=name~='quest.offer' and kinds[index] or nil},epoch,{}))
                else
                    local outcome=lp.network.lastCommandResult
                    if outcome and outcome.requestId==denialId then
                        check(not outcome.ok and outcome.reason=='host_only','guest decision packet accepted')
                        denialId=nil; denialIndex=denialIndex+1
                        if denialIndex>#denialNames then moving=1; stage='wait-decision' end
                    end
                end
            elseif stage=='wait-decision' and offer and offer.status~='offered' then
                stopWalk(); check(offer.status==(declines[index] and 'declined' or 'accepted'),'replicated decision differs')
                check(data.location==20 and data.scene=='stop' and data.coop.sceneEpoch==epoch,'guest advanced campaign')
                if index==7 then stage='aid-open' elseif index==8 then stage='item-open' else moving=-1; stage='return' end
            elseif stage=='aid-open' and view:inputAllowed() then
                app.draw(); press(view.ui.guestFirstAid); check(view.activities.firstAid.opened,'accepted aid unavailable')
                stage='aid-begin'
            elseif stage=='aid-begin' then
                app.draw(); press(view.activities.firstAid.beginRect); check(view.activities.firstAid.pending,'guest treatment not submitted'); stage='aid-acquired'
            elseif stage=='aid-acquired' and view.activities.firstAid.session and not view.activities.firstAid.pending then
                check(view.activities.firstAid.session.phase==1,'guest treatment failed'); capture='guest-accepted-aid.png'
                app.keypressed('escape'); app.keyreleased('escape'); stage='aid-paused'
            elseif stage=='aid-paused' and not view.activities.firstAid:busy() then moving=-1; stage='return'
            elseif stage=='item-open' and view:inputAllowed() then
                app.draw(); press(view.ui.guestPeople); app.draw(); press(view.ui.people_quests)
                check(view.people.quests.opened,'accepted item help unavailable'); stage='item-select'
            elseif stage=='item-select' then
                app.draw(); local panel=view.people.quests; local found
                for i,task in ipairs(panel.drawn) do if task.command=='quest.help' and task.slot==1 then found=i; break end end
                check(found and found<=4,'selected guest item missing'); press(view.ui['quests_task'..found])
                check(panel.quote,'item confirmation missing'); capture='guest-accepted-item.png'; stage='item-confirm'
            elseif stage=='item-confirm' and captured['guest-accepted-item.png'] then
                app.draw(); press(view.ui.quests_confirm); check(view.people.pending,'guest hand-in missing'); stage='item-done'
            elseif stage=='item-done' and not view.people.pending and layout.helpRequests[npc].complete then
                check(data.players.companion.inventory[1]==nil and data.players.host.inventory[1]==nil,'hand-in used wrong pack')
                app.draw(); press(view.ui.quests_close); check(not view.people.quests.opened,'task panel did not close')
                app.draw(); press(view.ui.people_close); check(not view.runtime.peopleOpen,'recipient panel did not close')
                moving=-1; stage='return'
            elseif stage=='return' and view.runtime.player.x<555 then
                stopWalk()
                if index<#kinds then index=index+1; stage='wait-offer'
                else menu(); click('leave'); stage='rejoin'; rejoinAt=now end
            elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
                check(layout.helpRequests[npc].complete and data.goodwill==2 and #data.passengers==1,'reconnect lost or duplicated decisions')
                click('leave'); print('LAN_QUEST_DECISIONS_OK role=guest hostOnly=true acceptedHelp=true ownPack=true reconnect=true'); finish()
            end
        end
        walk(lp.clientView)
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw()
    if capture then
        local name=capture; capture=nil
        love.graphics.captureScreenshot(function(pixels)
            pixels:encode('png',name); captured[name]=true
        end)
    end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
