-- Production accepted-task controls, all cargo kinds, ENet and isolated saves.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Help=require('game.stop_help_progression'); local Quests=require('game.help_quest_session')
local Entities=require('game.coop_entities'); local Catalog=require('game.catalog')
local app,c,started,finished,stage,capture,restoreWrite,retried,lastAction,rejoinAt,helpId,hostGear,hostX,epoch,location,requestId,expectedCommand
local captured={}; local connections=0; local generation; local npc='crow-merchant.png'
local kinds={'medicine','food','water','repair','ammunition','recovery'}; local kindIndex=1; local mailId; local completedKinds={}
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing task control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('task-test',x,y); app.touchreleased('task-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function control(view,name) app.draw(); press(view.ui['quests_'..name]) end
local function choose(view,predicate)
    app.draw(); local panel=view.people.quests; local found
    for i,offer in ipairs(panel.drawn) do if predicate(offer) then found=i; break end end
    check(found,'accepted task missing: '..tostring(stage)); check(panel.drawn[found].available,'cargo unavailable: '..tostring(stage))
    local page=math.floor((found-1)/4)
    while panel.page<page do control(view,'next') end
    while panel.page>page do control(view,'prev') end
    control(view,'task'..((found-1)%4+1)); check(panel.quote,'task confirmation missing')
    expectedCommand=panel.quote.command; capture='guest-task-confirm-'..stage..'.png'
end
local function confirm(view)
    app.draw(); if touch then control(view,'confirm') else app.gamepadpressed({},'a') end
    check(view.people.pending and view.people.pending.quest,'task command missing'); requestId=view.people.pending.id
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true quests=true reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=20; data.scene='stop'; c.runtime.scene='stop'
        local layout=c.ensureStopLayout(); layout.npcOutside=npc; layout.npc=npc; c.setupNPC()
        c.runtime.npcActor.x=600; c.runtime.npcActor.y=430
        c.runtime.player.x=550; c.runtime.player.y=430; data.playerX=550; data.playerY=430
        -- All tasks are already accepted by the host, including a resolved
        -- recovery encounter. The guest performs no acceptance/story command.
        layout.helpRequests={}; local request=Help.ensureRequest(layout,npc,'item',20,data)
        request.item='field-bandage-roll'; request.accepted=true; Quests.accept(data,request.sessionId); helpId=request.sessionId
        data.mailQuests={{origin=18,destination=20,recipient=npc,complete=false}}; data.supplyQuests={}
        for _,kind in ipairs(kinds) do data.supplyQuests[#data.supplyQuests+1]={origin=18,destination=20,cargoKind=kind,complete=false} end
        data.encounters['20']={hasMob=false,resolved=true}
        data.resources.food=30; data.resources.water=30; data.resources.coal=30
        Items.write(Players.forActor(data,'host'),nil,{kind='inventory',index=1},'field-bandage-roll')
        check(Items.ensure(data) and Entities.ensure(data),'quest fixture invalid'); mailId=data.mailQuests[1].entityId
        hostGear=data.players.host.itemSlots.equipment[1].id; hostX=c.runtime.player.x
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local actor=Players.forActor(campaign,'companion')
            for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil) end
            for i,name in ipairs({'field-bandage-roll','healing-salve','field-bandage-roll','food-ration','water-bottle','coal-chunk'}) do
                Items.write(actor,nil,{kind='inventory',index=i},name)
            end
            actor.ammo.rocks=8; actor.playerX=550; actor.playerY=430; return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Delivery test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<100,'task fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            generation=link.generation; connections=connections+1
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(99) and c.runtime.saveData.mailQuests[1].complete then return false,'injected delivery checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave and not captured['host-task-save-retry.png'] then capture='host-task-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-task-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'delivery save retry failed'); retried=true; stage='hosting'
            local reply=lp.authority:submitLocal('quest.deliver',{targetId=c.runtime.saveData.stopLayouts['20'].entityId,npc=npc,questId=mailId})
            check(reply.reason=='quest_unavailable','host duplicated completed guest delivery')
        end
        if connections==1 and not link then
            local saved=assert(Save.read(99)); check(retried and saved.helpQuestSessions[helpId].rewardClaimed and saved.mailQuests[1].complete,'tasks not saved')
            for _,q in ipairs(saved.supplyQuests) do check(q.complete and q.rewardRecipients.host and q.rewardRecipients.companion,'cargo or party XP missing') end
            check(saved.goodwill==9 and #saved.helpHistory==8,'task rewards repeated or missing')
            check(saved.players.host.inventory[1]=='field-bandage-roll' and saved.players.host.itemSlots.equipment[1].id==hostGear and c.runtime.player.x==hostX,'host ownership changed')
        elseif connections==2 and not link then finish() end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local data=lp.replica.data; location=data.location; epoch=data.coop.sceneEpoch
            helpId=data.stopLayouts[tostring(location)].helpRequests[npc].sessionId; mailId=data.mailQuests[1].entityId
            capture='guest-task-world.png'; stage='open'
        elseif stage=='rejoin' and now-rejoinAt>.4 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
            local data=lp.replica.data; check(data.goodwill==9 and data.helpQuestSessions[helpId].rewardClaimed,'rejoin lost task rewards')
            for _,q in ipairs(data.supplyQuests) do check(q.complete and q.rewardRecipients.companion,'rejoin lost delivery') end
            check(data.scene=='stop' and data.location==location and data.coop.sceneEpoch==epoch,'task controls advanced story')
            click('leave'); print('LAN_QUESTS_OK role=guest selectedItem=true allCargoKinds=true sharedXP=true checkpointRetry=true reconnect=true hostOnlyStory=true'); finish()
        elseif lp.clientView and stage~='joining' then
            local view=lp.clientView; local panel=view.people.quests
            if requestId then
                local r=panel.lastOutcome
                if r and r.requestId==requestId and not view.people.pending then
                    check(r.ok and r.durable and r.command==expectedCommand and r.details.completed,'task action failed: '..tostring(r.reason))
                    check(view.runtime.saveData.coop.sceneEpoch==epoch,'task action progressed story')
                    if stage=='item-wait' then
                        check(view.runtime.saveData.inventory[1]=='field-bandage-roll' and not view.runtime.saveData.inventory[3],'wrong selected item consumed'); stage='mail'
                    elseif stage=='mail-wait' then check(r.details.recipients.host==r.details.xp and r.details.recipients.companion==r.details.xp,'party XP missing'); stage='cargo'
                    else completedKinds[kinds[kindIndex]]=true; kindIndex=kindIndex+1; stage=kindIndex>#kinds and 'done' or 'cargo' end
                    requestId=nil; lastAction=now; capture='guest-task-receipt.png'
                end
            elseif capture or lastAction and now-lastAction<.6 then return
            elseif stage=='open' and view:inputAllowed() then
                app.draw(); if touch then press(view.ui.guestPeople) else app.gamepadpressed({},'dpup') end
                app.draw(); press(view.ui.people_quests); check(panel.opened,'quest help did not open'); capture='guest-task-list.png'; stage='item'
            elseif stage=='item' then choose(view,function(q) return q.command=='quest.help' and q.slot==3 end); stage='item-confirm'
            elseif stage=='item-confirm' then confirm(view); stage='item-wait'
            elseif stage=='mail' then choose(view,function(q) return q.kind=='mail' end); stage='mail-confirm'
            elseif stage=='mail-confirm' then confirm(view); stage='mail-wait'
            elseif stage=='cargo' then choose(view,function(q) return q.kind==kinds[kindIndex] end); stage='cargo-confirm'
            elseif stage=='cargo-confirm' then confirm(view); stage='cargo-wait'
            elseif stage=='done' then
                for _,kind in ipairs(kinds) do check(completedKinds[kind],'cargo kind omitted') end
                control(view,'close'); app.draw(); press(view.ui.people_close); menu(); click('leave'); stage='rejoin'; rejoinAt=now
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
