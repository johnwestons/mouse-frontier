-- Production recipient controls in two isolated applications over real ENet.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local scene=os.getenv('MOUSE_FRONTIER_PEOPLE_SCENE') or 'train'; local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Entities=require('game.coop_entities')
local Items=require('game.item_instances'); local Catalog=require('game.catalog')
local app,c,started,finished,stage,capture,restoreWrite,saveRetried,request,command,verify,nextStage,lastAction,firstLine
local captured={}; local connections=0; local generation,hostItem,hostX,guestItem,gearId,chestId,recipientId,npc,epoch,location,rejoinAt
local function check(v,m) assert(v,m) end
local function press(rect)
    check(rect,'missing recipient control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('people-test',x,y); app.touchreleased('people-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function control(view,name) app.draw(); press(view.ui['people_'..name]) end
local function recipient(data) return assert(Entities.find(data,recipientId)) end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true people='..scene..' reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(9112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; npc='crow-merchant.png'
        if scene=='train' then
            data.passengers={{npc=npc,x=700,y=550,carIndex=1,weapon='trail-slingshot',destination=data.location+5}}
            check(Items.ensure(data) and Entities.ensure(data),'passenger fixture invalid'); recipientId=data.passengers[1].entityId
        else
            data.location=20; data.scene='stop'; c.runtime.scene='stop'
            local layout=c.ensureStopLayout(); layout.npcOutside=npc; layout.npc=npc; layout.npcWeapon='trail-slingshot'
            c.setupNPC(); c.runtime.npcActor.x=600; c.runtime.npcActor.y=430
            c.runtime.player.x=550; c.runtime.player.y=430; data.playerX=550; data.playerY=430
            check(Items.ensure(data) and Entities.ensure(data),'resident fixture invalid'); recipientId=layout.entityId
        end
        data.droppedItems={{name='mailbox-reward',mailbox=true,mailUnread=true,permanent=true,scene=scene,location=data.location,
            carIndex=1,x=scene=='train' and 665 or 570,y=scene=='train' and 550 or 430,storage={'frontier-short-sword'}}}
        check(Items.ensure(data) and Entities.ensure(data),'gift storage fixture invalid')
        chestId=data.droppedItems[1].entityId; gearId=Items.get(data,data.droppedItems[1],{kind='chest',index=1}).id
        Items.get(data,data.droppedItems[1],{kind='chest',index=1}).durability=31
        hostX=c.runtime.player.x; hostItem=data.players.host.itemSlots.equipment[1].id
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local own=campaign.players.companion; own.inventory={[1]='field-bandage-roll',[2]='food-ration'}
            if scene=='train' then own.playerX,own.playerY=require('game.train').clampCharacterToFloor(c.car,c.contentRegistry.scenery.trainCarImages['living-car'],650,520,30)
            else own.playerX=550; own.playerY=430 end
            return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed'); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Gift test friend'); click('next'); click('join'); stage='joining'
    end
end
local function waiting(view,name,after,fn)
    check(view.people.pending,'missing recipient command: '..name)
    request=view.people.pending.id; command=name; nextStage=after; verify=fn
end
local function choose(view,kind,index)
    app.draw(); local panel=view.people; local found
    for i,offer in ipairs(panel.drawn) do if offer.args.source.kind==kind and offer.args.source.index==index then found=i; break end end
    check(found and found<=9,'gift source not on first page'); control(view,'item'..found)
    check(panel.quote,'gift confirmation missing'); capture='guest-gift-confirm.png'
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<75,'recipient fixture deadline exceeded: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end -- Logical focus for injected hidden-window input.
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            connections=connections+1; generation=link.generation
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    local relationship=c.runtime.saveData.relationships[npc]
                    if path==Save.path(99) and relationship and relationship.gifts>=1 then return false,'injected gift checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave then capture='host-gift-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-gift-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'gift save retry failed'); saveRetried=true; stage='hosting'
        end
        if connections==1 and not link then
            local saved=assert(Save.read(99)); local target=recipient(saved)
            local instance=scene=='train' and target.weaponInstance or target.npcWeaponInstance
            check(saveRetried and instance.id==gearId and instance.durability==31,'gifted gear not durable')
            check(saved.relationships[npc].gifts==3 and saved.relationships[npc].talks==2,'relationship history not durable')
            check(saved.players.host.itemSlots.equipment[1].id==hostItem and c.runtime.player.x==hostX,'host ownership/position changed')
            local chest=assert(Entities.find(saved,chestId)); check(not chest.storage[1] and not chest.mailUnread,'mailbox gift not committed')
        elseif connections==2 and not link then finish() end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local data=lp.replica.data; npc='crow-merchant.png'; location=data.location; epoch=data.coop.sceneEpoch
            recipientId=scene=='train' and data.passengers[1].entityId or data.stopLayouts[tostring(location)].entityId
            chestId=data.droppedItems[1].entityId; gearId=Items.get(data,data.droppedItems[1],{kind='chest',index=1}).id
            guestItem=data.players.companion.itemSlots.equipment[1].id; capture='guest-recipient-world.png'; stage='world-ready'
        elseif stage=='rejoin' and now-rejoinAt>.4 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local data=lp.replica.data; local target=recipient(data); local instance=scene=='train' and target.weaponInstance or target.npcWeaponInstance
            check(instance.id==gearId and data.relationships[npc].gifts==3 and data.relationships[npc].talks==2,'rejoin lost gift/chatter')
            check(data.coop.sceneEpoch==epoch and data.scene==scene and data.location==location,'recipient controls progressed story')
            click('leave'); print('LAN_PEOPLE_OK role=guest scene='..scene..' approvedChatter=true gift=true gear=true saved=true hostOnlyStory=true'); finish()
        elseif lp.clientView and stage~='joining' then
            local view=lp.clientView; local panel=view.people
            if request then
                local result=lp.network.lastCommandResult
                if result and result.requestId==request and not panel.pending then
                    check(result.command==command,'wrong recipient result'); check(result.ok and result.durable,'recipient action failed: '..tostring(result.reason))
                    if verify then verify(view,result) end
                    check(view.runtime.saveData.coop.sceneEpoch==epoch,'recipient action advanced story')
                    request=nil; stage=nextStage; lastAction=now
                end
            elseif capture or lastAction and now-lastAction<.65 then return
            elseif stage=='world-ready' and captured['guest-recipient-world.png'] and view:inputAllowed() then
                app.draw(); if touch then press(view.ui.guestPeople) else app.gamepadpressed({},'dpup') end
                check(view.runtime.peopleOpen,'recipient panel did not open'); capture='guest-recipient-panel.png'; stage='talk1'
            elseif stage=='talk1' then
                control(view,'talk'); waiting(view,scene=='train' and 'passenger.chatter' or 'npc.chatter','talk2',function(v,r)
                    firstLine=r.details.lineIndex; check(v.people.speech.text==Catalog.dialogueLines[firstLine],'chatter text changed'); capture='guest-approved-chatter.png'
                end)
            elseif stage=='talk2' then
                control(view,'speechClose'); control(view,'talk'); waiting(view,scene=='train' and 'passenger.chatter' or 'npc.chatter','gear',function(v,r)
                    check(r.details.lineIndex~=firstLine and v.people.speech.text==Catalog.dialogueLines[r.details.lineIndex],'chatter repeated or changed')
                end)
            elseif stage=='gear' then
                control(view,'speechClose'); if scene=='train' then control(view,'equip') end
                choose(view,'equipment',1); stage='gearConfirm'
            elseif stage=='gearConfirm' then
                if touch then control(view,'confirm') else app.gamepadpressed({},'a') end
                waiting(view,scene=='train' and 'passenger.equip' or 'npc.gift','food',function(v,r)
                    local target=recipient(v.runtime.saveData); local instance=scene=='train' and target.weaponInstance or target.npcWeaponInstance
                    check(r.details.equipped and instance.id==guestItem and not v.runtime.saveData.equipment[1],'personal gear gift failed')
                end)
            elseif stage=='food' then control(view,'gift'); choose(view,'inventory',2); stage='foodConfirm'
            elseif stage=='foodConfirm' then
                control(view,'confirm'); waiting(view,'npc.gift','storage',function(v,r) check(not r.details.equipped and not v.runtime.saveData.inventory[2],'food gift failed') end)
            elseif stage=='storage' then choose(view,'chest',1); stage='storageConfirm'
            elseif stage=='storageConfirm' then
                control(view,'confirm'); waiting(view,'npc.gift','done',function(v,r)
                    local target=recipient(v.runtime.saveData); local instance=scene=='train' and target.weaponInstance or target.npcWeaponInstance
                    check(r.details.equipped and instance.id==gearId and instance.durability==31,'storage gift changed gear identity'); capture='guest-gift-completed.png'
                end)
            elseif stage=='done' then control(view,'close'); menu(); click('leave'); stage='rejoin'; rejoinAt=now
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
