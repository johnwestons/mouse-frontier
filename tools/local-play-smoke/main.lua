-- Full applications with production Local Play inputs, separate save roots,
-- real ENet, guest world rendering, ordinary movement controls and reconnect.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touchInput=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local app,c,started,finished,stage,capture,restoreWrite
local captured={}; local connections=0; local lastGeneration; local updated=false
local firstItem,firstCompanion,baselineFood,startedRejoin
local motionStart,motionOrigin,motionHostX,motionStoppedX,movementKey,keyboardQuery,sawPrediction
local hostOriginalX,companionOriginalX,hostMotionChecked
local carEpoch,carMotionId,carChecked
local itemSteps,itemStep,itemRequest,itemSubmittedAt,itemIdentity,packIdentity,itemsChecked
local storageSeeded,storageSteps,storageStep,storageRequest,storageSubmittedAt,storageChecked,sharedGear,mailGear
local Save=require('game.save'); local Viewport=require('game.viewport')
local Inventory=require('game.inventory'); local Style=require('game.ui_layout')
local drag
local function check(value,message) assert(value,message) end
local function press(rect)
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touchInput then app.touchpressed('lan-panel',x,y); app.touchreleased('lan-panel',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function click(name,text)
    app.draw()
    local rect=assert(c.ui.localPlayControls[name],'Local Play control missing: '..name)
    press(rect)
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function bagRect(rect) return Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect) end
local function slot(kind,index)
    if kind=='equipment' then return bagRect(touchInput and Inventory.mobileEquipmentSlotRect(index) or Inventory.equipmentSlotRect(index)) end
    if kind=='chest' then return bagRect(Inventory.chestSlotRect(index)) end
    return bagRect(touchInput and Inventory.mobileInventorySlotRect(index) or Inventory.inventorySlotRect(index))
end
local function interact(view)
    app.draw()
    if touchInput then local p=view.mobile.primary; press({x=p.x-15,y=p.y-15,w=30,h=30}) else app.keypressed('e') end
end
local function storageAction(index,action)
    press(slot('chest',index)); app.draw()
    local panel=c.ui.localPlay.clientView.inventory
    press(bagRect(action=='transfer' and panel.transferButton or c.ui.localPlay.clientView.ui[action]))
end
local function storagePlan(view)
    sharedGear=view.runtime.activeChest.storageInstances[1].id
    return {
        {name='inventory.swap',run=function() drag(slot('chest',1),slot('inventory',3)) end,
            verify=function(actor) check(actor.itemSlots.inventory[3].id==sharedGear,'chest drag changed gear identity') end},
        {name='storage.transfer',run=function()
            press(slot('inventory',3)); app.draw(); press(bagRect(view.inventory.transferButton))
        end,verify=function(actor) check(not actor.inventory[3] and view.runtime.activeChest.storageInstances[1].id==sharedGear,'chest deposit failed') end},
        {name='mailbox.collect',run=function() storageAction(4,'transfer') end,
            verify=function(_,result) check(result.details.amount==require('game.catalog').ammoPickupAmounts.rocks and not view.runtime.activeChest.storage[4],'chest ammunition collection failed') end},
        {name='inventory.consume',run=function() storageAction(2,'consume') end,
            verify=function(_,result) check(result.details.gained.food==3 and view.runtime.saveData.resources.food==baselineFood+9,'shared chest food failed') end},
        {name='storage.transfer',run=function() storageAction(1,'transfer') end,
            verify=function(actor) check(actor.itemSlots.inventory[2].id==sharedGear and not next(view.runtime.activeChest.storage),'chest was not emptied') end},
        {name='loot.pickup',run=function() press(bagRect(assert(view.inventory.takeButton,'empty container control missing'))) end,
            verify=function(actor) check(actor.inventory[3]=='travel-chest' and not view.runtime.chestOpen and not view.runtime.activeChest,'empty container pickup failed') end},
        {openMailbox=true,run=function()
            press(bagRect(view.inventory.closeButton)); app.draw(); interact(view)
            check(view.runtime.chestOpen and view.runtime.activeChest.mailbox,'mailbox control failed')
            mailGear=view.runtime.activeChest.storageInstances[6].id
        end,capture='guest-mailbox.png'},
        {name='mailbox.collect',run=function() storageAction(20,'transfer') end,
            verify=function(_,result)
                check(result.details.amount==require('game.catalog').ammoPickupAmounts.rocks and not view.runtime.activeChest.storage[20],'last mailbox slot could not be collected')
                check(view.runtime.activeChest.mailUnread==false,'guest collection did not clear new mail')
            end},
        {name='storage.transfer',run=function() storageAction(6,'transfer') end,
            verify=function(actor) check(actor.itemSlots.inventory[4].id==mailGear,'mailbox gear reward lost its identity') end},
        {name='inventory.consume',run=function() storageAction(1,'consume') end,
            verify=function(_,result) check(result.details.gained.water==3 and view.runtime.saveData.resources.water==11,'mailbox supply reward failed') end},
        {name='inventory.swap',rejected=true,run=function() drag(slot('inventory',3),slot('chest',20)) end,
            verify=function(actor,result) check(result.reason=='cannot_transfer' and actor.inventory[3]=='travel-chest' and not next(view.runtime.activeChest.storage),'mailbox accepted a guest deposit') end,
            capture='guest-mailbox-collected.png'},
    }
end
function drag(from,to)
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(from.x+from.w/2)*sx,oy+(from.y+from.h/2)*sy
    local tx,ty=ox+(to.x+to.w/2)*sx,oy+(to.y+to.h/2)*sy
    if touchInput then
        app.touchpressed('guest-item',x,y); app.touchmoved('guest-item',tx,ty,tx-x,ty-y); app.touchreleased('guest-item',tx,ty)
    else app.mousepressed(x,y,1,false); app.mousemoved(tx,ty,tx-x,ty-y); app.mousereleased(tx,ty,1,false) end
end
local function selectAction(kind,index,action)
    press(slot(kind,index)); app.draw()
    press(bagRect(assert(c.ui.localPlay.clientView.ui[action],'missing guest item action: '..action)))
end
local function itemPlan(view)
    local first=view.runtime.saveData.itemSlots.equipment[1].id
    itemIdentity=view.runtime.saveData.itemSlots.equipment[2].id
    packIdentity=view.runtime.saveData.itemSlots.inventory[3].id
    return {
        {name='inventory.swap',run=function() drag(slot('equipment',1),slot('inventory',4)) end,
            verify=function(actor) check(not actor.equipment[1] and actor.itemSlots.inventory[4].id==first,'guest drag lost weapon identity') end},
        {name='inventory.swap',run=function()
            if touchInput then drag(slot('inventory',4),slot('equipment',1))
            else
                for _=1,3 do app.keypressed('tab') end; app.gamepadpressed({},'a')
                for _=1,3 do app.keypressed('tab') end; app.gamepadpressed({},'a')
            end
        end,verify=function(actor) check(actor.itemSlots.equipment[1].id==first and not actor.inventory[4],'guest keyboard/controller equip failed') end},
        {name='inventory.swap',run=function() selectAction('inventory',3,'consume') end,
            verify=function(actor) check(actor.itemSlots.wearable.backpack.id==packIdentity and actor.inventoryCapacity==8,'guest wearable equip failed') end,
            capture='guest-equipped.png'},
        {name='inventory.consume',run=function() selectAction('inventory',1,'consume') end,
            verify=function(actor,result) check(actor.health==actor.maxHealth and not actor.inventory[1] and result.details.gained.health==5,'guest heal result failed') end},
        {name='inventory.consume',run=function() selectAction('inventory',2,'consume') end,
            verify=function(actor,result) check(not actor.inventory[2] and result.details.gained.food==3,'guest supply result failed') end},
        {name='loot.drop',run=function() selectAction('equipment',2,'drop') end,
            verify=function(actor,result)
                check(not actor.equipment[2] and result.details.entityId,'guest drop failed')
                local found
                for _,item in ipairs(view.runtime.saveData.droppedItems) do if item.entityId==result.details.entityId then found=item end end
                check(found and found.itemInstance.id==itemIdentity and found.carIndex==2,'guest drop changed gear identity or car')
            end},
        {name='loot.pickup',run=function()
            if touchInput then press(bagRect(view.inventory.closeButton)) else app.keypressed('i') end
            app.draw(); check(view.inventory:nearest(),'guest dropped item not reachable')
            if touchInput then local p=view.mobile.primary; press({x=p.x-15,y=p.y-15,w=30,h=30}) else app.keypressed('e') end
        end,verify=function(actor)
            check(actor.itemSlots.inventory[1].id==itemIdentity and not actor.equipment[2],'guest pickup failed to keep dropped gear')
            check(view.runtime.saveData.resources.food==baselineFood+6,'guest food failed to update train supplies')
        end,capture='guest-collected.png'},
    }
end
local function open()
    if touchInput then
        if c.ui.localPlay:isClient() and c.ui.localPlay.clientView then
            app.draw(); press(c.ui.localPlay.clientView.mobile.menu); app.draw()
            check(c.ui.localPlay.menuOpen,'Guest Local Play menu failed'); return
        end
        if c.runtime.state=='game' and not c.ui.escMenuOpen then app.keypressed('escape'); app.keyreleased('escape') end
        app.draw(); press(assert(c.ui.localPlayLauncher,'Local Play launcher missing')); app.draw()
    else app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
    check(c.ui.localPlay.menuOpen,'Local Play entry control failed')
end
local function finish()
    if finished then return end; finished=true
    check(app.quit()~=true,'application quit was unexpectedly cancelled')
    print('LAN_SMOKE_OK role='..role..' ready='..connections..' application=true guestWorld=true motion=true input='..(touchInput and 'touch' or 'keyboard'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(6112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    keyboardQuery=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for _,key in ipairs({...}) do if movementKey and (key==movementKey or key=='lshift') then return true end end
        return keyboardQuery(...)
    end
    check(c and c.ui.localPlay,'Local Play was not installed in the application')
    c.ui.localPlay.context.bind='127.0.0.1' -- Keep the automated host off physical LAN interfaces.
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.trainCars={'living-car','medical','storage'}; data.resources.food=8; data.resources.water=8
        check(c.enterGame(data),'could not enter isolated host journey')
        local place=c.ui.localPlay.context.placeCompanion
        c.ui.localPlay.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local actor=campaign.players.companion
            actor.health=actor.maxHealth-5; actor.inventory[1]='field-bandage-roll'; actor.inventory[2]='food-ration'
            actor.inventory[3]='patched-canvas-pack'; check(require('game.item_instances').ensure(campaign),'fixture gear invalid')
            return true
        end
        open(); click('port',port)
        local write=love.filesystem.write
        restoreWrite=write
        love.filesystem.write=function(path,bytes)
            if path==Save.path(99) then return false,'injected LAN preflight failure' end
            return write(path,bytes)
        end
        click('host')
        check(c.ui.checkpointStatus().pending and not c.ui.localPlay.network,'host opened a socket before checkpoint success')
        capture='host-save-retry.png'; stage='retry'
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        open(); click('address','127.0.0.1:'..port); click('name','Co-op test friend'); click('next')
        capture='guest-join.png'; stage='join'
    end
end
local function update(dt)
    if finished then return end
    check(love.timer.getTime()-started<70,'application LAN smoke deadline exceeded')
    app.update(math.min(dt,.05))
    local localPlay=c.ui.localPlay
    if role=='host' then
        if stage=='retry' and captured['host-save-retry.png'] then
            check(c.ui.checkpointStatus().pending and c.ui.checkpointBlocked,'save failure did not render the retry barrier')
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touchInput then press({x=190,y=438,w=185,h=58})
            else app.keypressed('r'); app.keyreleased('r') end
            check(not c.ui.checkpointStatus().pending,'save retry failed')
            click('host'); check(localPlay.network and localPlay.phase=='hosting','Start hosting control failed')
            open(); stage='hosting'; print('LAN_SMOKE_LISTENING')
        elseif stage=='hosting' then
            local pending=localPlay:pending()
            if pending then capture='host-approval.png'; stage='approval' end
        elseif stage=='approval' and captured['host-approval.png'] then
            click('approve'); open(); stage='hosting'
        end
        local link=localPlay.network and localPlay.network.link
        if link and link.admitted and companionOriginalX and localPlay.motion.actor
            and math.abs(localPlay.motion.actor.x-companionOriginalX)>30
            and math.abs(localPlay.motion.actor.x-c.runtime.player.x)>100 and not captured['host-two-actors.png'] then
            localPlay.menuOpen=false; c.ui.escMenuOpen=false; app.update(0)
            capture='host-two-actors.png'
        end
        if link and link.admitted and link.generation~=lastGeneration then
            connections=connections+1; lastGeneration=link.generation
            local data=c.runtime.saveData
            local item=data.players.companion.itemSlots.equipment[1].id
            if firstItem then check(firstItem==item,'application rejoin replaced companion equipment') else firstItem=item end
            check(data.coop.network.bindingVersion==1,'rejoin issued a new credential')
            if not updated then
                hostOriginalX=c.runtime.player.x; companionOriginalX=data.players.companion.playerX
                data.resources.food=data.resources.food+3; updated=true
                app.focus(false); app.focus(true)
                check(assert(Save.read(99)).resources.food==data.resources.food,'host change was not saved')
            end
        end
        if link and link.admitted and not storageSeeded and not localPlay.authority.pendingSave then
            local data=c.runtime.saveData; local actor=data.players.companion
            if actor.activeCar==2 and actor.inventory[1]=='trail-slingshot' and actor.inventoryCapacity==8 and data.resources.food==14 then
                local x,y=localPlay.motion.actor.x,localPlay.motion.actor.y
                data.droppedItems[#data.droppedItems+1]={name='travel-chest',scene='train',carIndex=2,x=x+30,y=y,
                    storage={[1]='frontier-short-sword',[2]='food-ration',[4]='rocks'},scale=1,rotation=0}
                data.droppedItems[#data.droppedItems+1]={name='mailbox-reward',mailbox=true,mailUnread=true,permanent=true,scene='train',carIndex=2,x=x+60,y=y,
                    storage={[1]='water-bottle',[6]='trail-slingshot',[20]='rocks'},scale=1,rotation=0}
                check(require('game.coop_entities').ensure(data) and require('game.item_instances').ensure(data),'storage fixture is invalid')
                check(localPlay.authority:checkpointNow(),'storage fixture checkpoint failed'); storageSeeded=true
            end
        end
        if connections==1 and not link and not hostMotionChecked then
            check(c.runtime.player.x==hostOriginalX,'companion input moved the host')
            check(math.abs(c.runtime.saveData.players.companion.playerX-companionOriginalX)>10,'companion never moved')
            check(localPlay.menuOpen and not localPlay.motion.generation and not localPlay.motion.actor.moving,'host modal/disconnect movement ownership failed')
            app.focus(false); app.focus(true)
            check(math.abs(assert(Save.read(99)).players.companion.playerX-localPlay.motion.actor.x)<.00001,'companion position was not saved')
            check(c.runtime.saveData.players.host.activeCar==1 and c.runtime.saveData.players.companion.activeCar==2,'personal car selection moved the host')
            check(assert(Save.read(99)).players.companion.activeCar==2,'personal car selection was not saved')
            local saved=assert(Save.read(99)); local companion=saved.players.companion
            check(companion.health==companion.maxHealth and companion.inventoryCapacity==8 and companion.inventory[1]=='trail-slingshot',
                'guest item actions were not checkpointed')
            check(companion.itemSlots.equipment[1].id==firstItem and saved.resources.food==17 and saved.resources.water==11,'guest items modified the wrong actor or resources')
            check(storageSeeded and companion.inventory[2]=='frontier-short-sword' and companion.inventory[3]=='travel-chest'
                and companion.inventory[4]=='trail-slingshot','guest storage transfers were not saved')
            hostMotionChecked=true
            print('LAN_MOTION_OK role=host modal=true saved=true stopped=true')
            print('LAN_CAR_OK role=host hostCar=1 companionCar=2 saved=true')
            print('LAN_ITEMS_OK role=host durable=true companionOnly=true supplies=true')
            print('LAN_STORAGE_OK role=host saved=true mailbox=true identities=true')
        end
        if connections==2 and not link then
            check(hostMotionChecked,'host movement checks did not finish')
            check(captured['host-two-actors.png'],'two-actor host view was not captured')
            check(not localPlay.authority.bindings.companion,'guest binding survived leave')
            finish()
        end
    else
        if stage=='join' and captured['guest-join.png'] then click('join'); stage='first'
        elseif stage=='first' and localPlay.phase=='connected' then
            local data=localPlay.replica.data
            baselineFood=baselineFood or data.resources.food
            firstCompanion=firstCompanion or data.players.companion.itemSlots.equipment[1].id
            check(c.runtime.session.networkMode=='client' and not c.runtime.saveData,'guest replaced its local save with a replica')
            check(not love.filesystem.getInfo(Save.path(99)) and love.filesystem.getInfo('coop-connections.dat'),'guest save ownership failed')
            if data.resources.food==baselineFood+3 then capture='guest-connected.png'; stage='leave-first'; connections=1 end
        elseif stage=='leave-first' and captured['guest-connected.png'] and localPlay.motionFrame and localPlay.motionFrame.ready then
            local frame=localPlay.motionFrame
            motionOrigin=frame.companion.x; motionHostX=frame.host.x
            check(localPlay.clientView.ready and not localPlay.previewOnly,'guest world was not prepared')
            click('close'); check(not localPlay:captures(),'guest could not enter the world')
            capture='guest-world.png'; stage='start-motion'
        elseif stage=='start-motion' and captured['guest-world.png'] then
            local direction=motionOrigin>480000 and -1 or 1
            if touchInput then
                local stick=localPlay.clientView.mobile.joystick
                local ox,oy,sx,sy=Viewport.transform(960,720)
                app.touchpressed('guest-walk',ox+stick.x*sx,oy+stick.y*sy)
                app.touchmoved('guest-walk',ox+(stick.x+direction*stick.radius*.95)*sx,oy+stick.y*sy,0,0)
            else movementKey=direction==-1 and 'a' or 'd'; app.keypressed(movementKey) end
            motionStart=love.timer.getTime(); stage='moving'
        elseif stage=='moving' then
            local now=love.timer.getTime()
            local frame=localPlay.motionFrame
            if frame and math.abs(localPlay.clientView.runtime.player.x-frame.companion.x/1000)>.5 then sawPrediction=true end
            if now-motionStart>=.65 then
                capture='guest-moved.png'; stage='capture-motion'
            end
        elseif stage=='capture-motion' and captured['guest-moved.png'] then
            check(localPlay.menuOpen,'guest menu input did not open Local Play')
            movementKey=nil; app.touchreleased('guest-walk',0,0)
            stage='stale-motion'; motionStart=love.timer.getTime()
        elseif stage=='stale-motion' and love.timer.getTime()-motionStart>.6 then
            local frame=assert(localPlay.motionFrame)
            -- Allow a cold first world draw to finish before judging the next
            -- frame. The core tests assert the exact host .35-second cutoff.
            if frame.companion.moving or frame.companion.vx~=0 then
                check(love.timer.getTime()-motionStart<3,'stale input kept moving'); return
            end
            check(frame.ready and frame.ack>0 and math.abs(frame.companion.x-motionOrigin)>10000,'host did not simulate companion input')
            check(not frame.companion.moving and frame.companion.vx==0,'stale input kept moving')
            check(frame.host.x==motionHostX,'guest input changed the host position')
            motionStoppedX=frame.companion.x/1000
            check(sawPrediction,'guest never displayed locally predicted motion')
            check(math.abs(localPlay.clientView.runtime.player.x-frame.companion.x/1000)<.05,'guest view did not converge to host position')
            print('LAN_MOTION_OK role=guest ack='..frame.ack..' delta='..(math.abs(frame.companion.x-motionOrigin)/1000)..' stopped=true controls=true prediction=true')
            carEpoch=frame.sceneEpoch; carMotionId=frame.motionId
            click('close'); app.draw()
            if touchInput then press(assert(localPlay.clientView.ui.trainCarTabs[2],'guest car tab missing'))
            else app.keypressed(']'); app.keyreleased(']') end
            check(localPlay.clientView.carRequest,'guest car controls did not submit an action')
            stage='changing-car'
        elseif stage=='changing-car' then
            local frame=localPlay.motionFrame; local view=localPlay.clientView
            local result=localPlay.network.lastCommandResult
            if result and not result.ok then error('car action rejected: '..tostring(result.reason)) end
            if frame and frame.companion.car==2 and frame.ready and not frame.paused and not view.carTransition
                and result and result.durable and localPlay.replica.data.players.companion.activeCar==2 then
                check(frame.sceneEpoch==carEpoch and frame.motionId>carMotionId,'car change did not use a personal motion generation')
                check(frame.host.car==1 and frame.host.x==motionHostX,'car change moved the host')
                check(view.runtime.saveData.activeCar==2 and not view.carRequest,'guest did not display its car')
                motionStoppedX=frame.companion.x/1000; carChecked=true; capture='guest-car.png'; stage='capture-car'
                print('LAN_CAR_OK role=guest hostCar=1 companionCar=2 epoch='..carEpoch..' motionId='..frame.motionId..' durable=true controls=true')
            end
        elseif stage=='capture-car' and captured['guest-car.png'] then
            app.draw()
            if touchInput then press(localPlay.clientView.mobile.backpack) else app.keypressed('i') end
            check(localPlay.clientView.runtime.inventoryOpen,'guest backpack control did not open')
            app.draw(); capture='guest-backpack.png'; itemSteps=itemPlan(localPlay.clientView); itemStep=1; stage='items'
        elseif stage=='items' and captured['guest-backpack.png'] then
            local view=localPlay.clientView; local panel=view.inventory
            local entry=itemSteps[itemStep]; local now=love.timer.getTime()
            if itemRequest then
                local result=localPlay.network.lastCommandResult
                if result and result.requestId==itemRequest then
                    check(result.ok,'guest item action rejected: '..tostring(result.reason))
                    if not panel.pending then
                        check(result.durable and result.command==entry.name,'guest item action missing durable receipt')
                        entry.verify(view.runtime.saveData,result)
                        capture=entry.capture; itemStep=itemStep+1; itemRequest=nil
                    end
                end
            elseif not entry then
                itemsChecked=true; print('LAN_ITEMS_OK role=guest equipment=true wearable=true consume=true dropPickup=true identity=true input='..(touchInput and 'touch' or 'keyboard+mouse+controller'))
                stage='open-storage'
            elseif not capture and (not itemSubmittedAt or now-itemSubmittedAt>.6) and view:actionsAllowed() then
                app.draw(); entry.run(); check(panel.pending,'guest item controls did not submit '..entry.name)
                itemRequest=panel.pending.id; itemSubmittedAt=now
            end
        elseif stage=='open-storage' and captured['guest-collected.png'] then
            local view=localPlay.clientView; local nearest=view.inventory:nearest()
            if nearest and nearest.name=='travel-chest' then
                interact(view); check(view.runtime.chestOpen,'shared chest did not open')
                storageSteps=storagePlan(view); storageStep=1; capture='guest-storage.png'; stage='storage'
            end
        elseif stage=='storage' and captured['guest-storage.png'] then
            local view=localPlay.clientView; local entry=storageSteps[storageStep]; local now=love.timer.getTime()
            if storageRequest then
                local result=localPlay.network.lastCommandResult
                if result and result.requestId==storageRequest then
                    check(result.ok~=(entry.rejected==true),'guest storage result unexpected: '..tostring(result.reason))
                    if not view.inventory.pending then
                        check(result.command==entry.name and (entry.rejected or result.durable),'guest storage receipt not durable')
                        entry.verify(view.runtime.saveData,result); capture=entry.capture; storageRequest=nil; storageStep=storageStep+1
                    end
                end
            elseif not entry then
                storageChecked=true; stage='leave-items'
                print('LAN_STORAGE_OK role=guest roundtrip=true supply=true ammo=true emptyContainer=true mailbox20=true deniedDeposit=true')
            elseif not capture and (not storageSubmittedAt or now-storageSubmittedAt>.6) and view:actionsAllowed() then
                app.draw(); entry.run(); storageSubmittedAt=now
                if entry.openMailbox then capture=entry.capture; storageStep=storageStep+1
                else check(view.inventory.pending,'guest storage controls did not submit '..entry.name); storageRequest=view.inventory.pending.id end
            end
        elseif stage=='leave-items' and captured['guest-mailbox-collected.png'] then
            local view=localPlay.clientView
            if view.runtime.inventoryOpen then press(bagRect(view.inventory.closeButton)) end
            open()
            click('leave'); check(c.runtime.session.networkMode=='offline' and c.runtime.state=='slots','leave did not restore the title')
            stage='rejoin'; startedRejoin=love.timer.getTime()
        elseif stage=='rejoin' and love.timer.getTime()-startedRejoin>.4 then
            open(); click('join'); stage='second'
        elseif stage=='second' and localPlay.phase=='connected' then
            check(localPlay.replica.data.players.companion.itemSlots.equipment[1].id==firstCompanion,'saved companion was not resumed')
            check(localPlay.replica.data.resources.food==baselineFood+9 and localPlay.replica.data.resources.water==11,'rejoin missed shared supply changes')
            local actor=localPlay.replica.data.players.companion
            check(itemsChecked and actor.itemSlots.inventory[1].id==itemIdentity and actor.itemSlots.wearable.backpack.id==packIdentity
                and actor.health==actor.maxHealth and actor.inventoryCapacity==8,'rejoin lost guest item actions')
            check(storageChecked and actor.itemSlots.inventory[2].id==sharedGear and actor.itemSlots.inventory[4].id==mailGear
                and actor.inventory[3]=='travel-chest','rejoin lost shared storage item identity')
            check(math.abs(localPlay.replica.data.players.companion.playerX-motionStoppedX)<.001,'rejoin lost companion movement')
            check(carChecked and localPlay.replica.data.players.companion.activeCar==2,'rejoin lost personal car selection')
            connections=2; click('leave'); finish()
        end
        if localPlay.error then error('Local Play failed: '..localPlay.error) end
    end
end
local function guarded(fn,...)
    local args={...}
    local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..tostring(role)..' '..tostring(reason)); finished=true
        if c and c.ui.localPlay then c.ui.localPlay:stop() end
        love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if not app or finished then return end
    guarded(function()
        app.draw()
        if capture then
            love.graphics.captureScreenshot(capture); captured[capture]=true
            if capture=='host-two-actors.png' then c.ui.localPlay:open() end
            if capture=='guest-moved.png' then
                -- Queue capture of the world frame, then use the normal menu
                -- input without redrawing over that frame. Held movement must
                -- be neutralized before its eventual release on the next tick.
                if touchInput then press(c.ui.localPlay.clientView.mobile.menu)
                else app.keypressed('f8'); app.keyreleased('f8') end
            end
            capture=nil
        end
    end)
end
function love.focus(focused) if app then app.focus(focused) end end
