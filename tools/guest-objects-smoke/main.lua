-- Real ENet, isolated full applications, detached previews and durable objects.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'; local Save=require('game.save'); local Viewport=require('game.viewport')
local Entities=require('game.coop_entities'); local Items=require('game.item_instances'); local TrainView=require('game.train_view')
local app,c,started,finished,stage,capture,restoreWrite,saveRetried,lastAction,request,expectedCommand,verify,afterResult
local captured={}; local connections=0; local generation,hostItem,guestItem,hostX,gearId,objectId,radioId,crateId,epoch,rejoinAt
local function check(v,m) assert(v,m) end
local function point(x,y)
    local ox,oy,sx,sy=Viewport.transform(960,720); x,y=ox+x*sx,oy+y*sy
    if touch then app.touchpressed('object-test',x,y); app.touchreleased('object-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function press(rect,t)
    check(rect,'missing object control'); point(rect.x+rect.w*(t or .5),rect.y+rect.h/2)
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function control(view,name,t) app.draw(); press(view.ui['object_'..name],t) end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true objects=true reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(9112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData
        data.audio.rainEnabled=true
        data.droppedItems={{name='frontier-short-sword',scene='train',carIndex=1,x=720,y=550,scale=1},
            {name='boombox-radio',scene='train',carIndex=1,x=650,y=550,permanent=true},
            {name='travel-chest',scene='train',carIndex=1,x=740,y=575,storage={'water-bottle'}}}
        check(Items.ensure(data) and Entities.ensure(data),'fixture ownership failed')
        objectId=data.droppedItems[1].entityId; radioId=data.droppedItems[2].entityId; crateId=data.droppedItems[3].entityId
        gearId=data.droppedItems[1].itemInstance.id; data.droppedItems[1].itemInstance.durability=23
        hostX=c.runtime.player.x; hostItem=data.players.host.itemSlots.equipment[1].id
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local own=campaign.players.companion
            own.playerX,own.playerY=require('game.train').clampCharacterToFloor(c.car,c.contentRegistry.scenery.trainCarImages['living-car'],650,520,30)
            return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed'); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Object test friend'); click('next'); click('join'); stage='joining'
    end
end
local function waitResult(view,name,nextStage,fn)
    check(view.objects.pending,'missing object command: '..name)
    request=view.objects.pending.id; expectedCommand=name; verify=fn; afterResult=nextStage
end
local function openEditor(view)
    if view.ui.radioOpen then control(view,'close') end
    app.draw(); if touch then press(view.ui.guestEditor) else app.gamepadpressed({},'leftstick') end
    check(view.runtime.editMode,'editor did not open')
end
local function world(view,x,y)
    local fx,fy,fit=view:focusPoint(); x,y=TrainView.toView(fit,x,y)
    return fx+view.camera.panX+(x-fx)*view.camera.zoom,fy+view.camera.panY+(y-fy)*view.camera.zoom
end
local function drag(view,x,y,nx,ny)
    local ox,oy,sx,sy=Viewport.transform(960,720); x,y=world(view,x,y); nx,ny=world(view,nx,ny)
    x,y=ox+x*sx,oy+y*sy; nx,ny=ox+nx*sx,oy+ny*sy
    if touch then app.touchpressed('drag-test',x,y); app.touchmoved('drag-test',nx,ny); app.touchreleased('drag-test',nx,ny)
    else app.mousepressed(x,y,1,false); app.mousemoved(nx,ny); app.mousereleased(nx,ny,1,false) end
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<80,'object fixture deadline exceeded: '..tostring(stage))
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
                    local object=Entities.find(c.runtime.saveData,objectId)
                    if path==Save.path(99) and object and object.x==780 then return false,'injected placement checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave then capture='host-placement-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-placement-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'placement retry failed'); saveRetried=true; stage='hosting'
        end
        if connections==1 and not link then
            local saved=assert(Save.read(99)); check(saveRetried and not Entities.find(saved,objectId),'collection not durable')
            check(saved.audio.station=='vibes' and saved.audio.rainEnabled==false,'radio not durable')
            check(saved.players.host.itemSlots.equipment[1].id==hostItem and c.runtime.player.x==hostX,'host ownership/position changed')
            check(saved.players.companion.itemSlots.inventory[1].id==gearId and saved.players.companion.itemSlots.inventory[1].durability==23,'collected gear changed')
            check(#saved.droppedItems==2 and Entities.find(saved,crateId).storage[1]=='water-bottle','permanent/container collection was allowed')
            check(not next(lp.authority.activityState.resources),'disconnect leaked object lease')
        elseif connections==2 and not link then finish() end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local data=lp.replica.data
            objectId=data.droppedItems[1].entityId; radioId=data.droppedItems[2].entityId; crateId=data.droppedItems[3].entityId
            gearId=data.droppedItems[1].itemInstance.id; guestItem=data.players.companion.itemSlots.equipment[1].id; epoch=data.coop.sceneEpoch
            capture='guest-objects-world.png'; stage='world-ready'
        elseif stage=='rejoin' and now-rejoinAt>.4 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local data=lp.replica.data
            check(data.players.companion.itemSlots.inventory[1].id==gearId and data.players.companion.itemSlots.equipment[1].id==guestItem,'rejoin lost gear')
            check(data.audio.station=='vibes' and data.audio.rainEnabled==false and data.coop.sceneEpoch==epoch,'rejoin lost radio or progressed story')
            click('leave'); print('LAN_OBJECTS_OK role=guest preview=true lease=true radio=true saved=true hostOnlyStory=true'); finish()
        elseif stage~='joining' and lp.clientView then
            local view=lp.clientView; local panel=view.objects
            if request then
                local result=lp.network.lastCommandResult
                if result and result.requestId==request and not panel.pending then
                    check(result.command==expectedCommand,'wrong object result'); if verify then verify(view,result) end
                    check(view.runtime.saveData.coop.sceneEpoch==epoch,'objects progressed party story')
                    request=nil; stage=afterResult; lastAction=now
                end
            elseif capture or lastAction and now-lastAction<.65 then return
            elseif stage=='world-ready' and captured['guest-objects-world.png'] and view:inputAllowed() then
                app.draw(); if touch then press(view.ui.guestRadio) else app.gamepadpressed({},'x') end
                check(view.ui.radioOpen,'radio did not open'); capture='guest-radio-panel.png'; stage='radio8bit'
            elseif stage=='radio8bit' then
                control(view,'8bit'); waitResult(view,'radio.station','radioVibes',function(v,r) check(r.ok and r.durable and v.runtime.saveData.audio.station=='8bit','8bit selection failed') end)
            elseif stage=='radioVibes' then
                control(view,'vibes'); waitResult(view,'radio.station','radioRain',function(v,r) check(r.ok and r.durable and v.runtime.saveData.audio.station=='vibes','vibes selection failed') end)
            elseif stage=='radioRain' then
                control(view,'rain'); waitResult(view,'radio.station','editor',function(v,r) check(r.ok and r.durable and v.runtime.saveData.audio.rainEnabled==false,'rain selection failed') end)
            elseif stage=='editor' then
                local seq=lp.network.nextRequestId; control(view,'mute'); check(lp.network.nextRequestId==seq,'local playback sent a campaign command')
                check(view.context.audio.status().category=='vibes','guest audio did not follow radio')
                openEditor(view); control(view,'next'); waitResult(view,'decoration.acquire','preview',function(v,r) check(r.ok and v.objects.entityId==objectId,'object selection failed') end)
            elseif stage=='preview' then
                control(view,'right'); control(view,'up'); control(view,'larger'); control(view,'rotate'); control(view,'front')
                control(view,'hue',.6); control(view,'saturation',.7)
                local item=panel.draft; drag(view,item.x+31,item.y+31,780,580)
                check(panel.draft.x==780 and panel.draft.y==580 and panel.dirty,'drag did not create a local preview')
                check(Entities.find(view.runtime.saveData,objectId).x==720 and Entities.find(lp.replica.data,objectId).x==720,'preview mutated replica')
                capture='guest-decoration-preview.png'; stage='apply'
            elseif stage=='apply' then
                control(view,'apply'); waitResult(view,'decoration.place','radioSelect',function(v,r)
                    local item=Entities.find(v.runtime.saveData,objectId)
                    check(r.ok and r.durable and item.x==780 and item.y==580 and item.scale==1.1 and item.layer==2,'placement not durable')
                    check(math.abs(item.hue-.6)<.00001 and math.abs(item.saturation-1.4)<.00001 and item.itemInstance.id==gearId,'placement lost color/identity')
                    capture='guest-decoration-saved.png'
                end)
            elseif stage=='radioSelect' then control(view,'next'); stage='radioSelected'; lastAction=now
            elseif stage=='radioSelected' and not panel.pending and panel.entityId==radioId and panel.lease then
                control(view,'collect'); waitResult(view,'decoration.collect','crateSelect',function(_,r) check(not r.ok and r.reason=='permanent','permanent radio collected') end)
            elseif stage=='crateSelect' then control(view,'next'); stage='crateSelected'; lastAction=now
            elseif stage=='crateSelected' and not panel.pending and panel.entityId==crateId and panel.lease then
                control(view,'collect'); waitResult(view,'decoration.collect','swordSelect',function(_,r) check(not r.ok and r.reason=='container_not_empty','occupied container collected') end)
            elseif stage=='swordSelect' then control(view,'next'); stage='swordSelected'; lastAction=now
            elseif stage=='swordSelected' and not panel.pending and panel.entityId==objectId and panel.lease then
                control(view,'collect'); waitResult(view,'decoration.collect','done',function(v,r) check(r.ok and r.durable and v.runtime.saveData.itemSlots.inventory[1].id==gearId,'collected gear not durable') end)
            elseif stage=='done' then control(view,'close'); menu(); click('leave'); rejoinAt=now; stage='rejoin'
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
