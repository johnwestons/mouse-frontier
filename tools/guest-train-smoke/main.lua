-- Two isolated full applications, real ENet and production train controls.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'; local Save=require('game.save'); local Viewport=require('game.viewport')
local app,c,started,finished,stage,capture,restoreWrite,saveRetried; local captured={}; local connections=0; local generation
local steps,index,request,confirming,lastAction,rejoinAt,hostItem,guestItem,epoch,hostX
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing train control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('train-test',x,y); app.touchreleased('train-test',x,y)
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
    print('LAN_SMOKE_OK role='..role..' application=true train=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(9112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=50; data.scrap=200; data.resources.coal=20
        data.trainCars={'living-car'}
        hostX=c.runtime.player.x; hostItem=data.players.host.itemSlots.equipment[1].id
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local own=campaign.players.companion
            own.playerX,own.playerY=require('game.train').clampCharacterToFloor(c.car,c.contentRegistry.scenery.trainCarImages['living-car'],594,520,30)
            own.inventory={[1]='coal-bucket',[2]='coal-chunk',[3]='coal-bucket'}; return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed')
        if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Train test friend'); click('next'); click('join'); stage='joining'
    end
end
local function openWorkshop(view)
    if view.runtime.trainUpgradeOpen then return end
    app.draw(); if touch then press(view.ui.guestWorkshop) else app.keypressed('u') end
    check(view.runtime.trainUpgradeOpen,'workshop did not open'); app.draw()
end
local function fuel(view)
    if view.runtime.trainUpgradeOpen then
        if touch then press(view.ui.guestTrainClose) else app.keypressed('escape') end
    end
    app.draw(); if touch then press(view.ui.guestFuel) else app.gamepadpressed({},'b') end
end
local function buy(id,name,verify,captureName)
    return {name=name,confirm=true,capture=captureName,verify=verify,run=function(view)
        openWorkshop(view)
        if not touch and id=='coal-hauler' then app.gamepadpressed({},'dpdown'); app.gamepadpressed({},'a')
        else press(id=='engine' and view.ui.guestEngine or view.ui.guestCars[id]) end
        check(view.train.quote,'upgrade confirmation missing'); app.draw(); capture='guest-upgrade-confirm.png'
    end}
end
local function plan()
    return {
        {name='train.fuel',rejected=true,run=fuel,verify=function(own,result)
            check(result.reason=='storage_full' and own.inventory[1]=='coal-bucket' and own.resources.coal==20,'full coal storage consumed fuel')
        end,capture='guest-coal-full.png'},
        buy('coal-hauler','train.upgrade',function(own,result)
            check(result.details.carId=='coal-hauler' and own.scrap==180 and #own.trainCars==2,'coal hauler purchase failed')
        end,'guest-coal-hauler.png'),
        {name='train.fuel',run=fuel,verify=function(own,result) check(result.details.gained==3 and not own.inventory[1] and own.resources.coal==23,'bucket fueling failed') end},
        {name='train.fuel',run=fuel,verify=function(own,result) check(result.details.gained==1 and not own.inventory[2] and own.resources.coal==24,'chunk fueling failed') end},
        {name='train.fuel',run=fuel,verify=function(own,result) check(result.details.gained==3 and not own.inventory[3] and own.resources.coal==27,'last bucket failed') end,capture='guest-fueled.png'},
        buy('engine','train.engineUpgrade',function(own,result) check(result.details.level==1 and own.engineLevel==1 and own.scrap==165,'engine tier one failed') end),
        buy('engine','train.engineUpgrade',function(own,result) check(result.details.level==2 and own.engineLevel==2 and own.scrap==137,'engine tier two failed') end),
        buy('storage','train.upgrade',function(own,result) check(result.details.carId=='storage' and #own.trainCars==3 and own.scrap==115,'storage purchase failed') end,'guest-train-upgraded.png'),
    }
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<70,'train fixture deadline exceeded')
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end -- Owned hidden windows receive injected input.
    if role=='host' then
        if lp:pending() then
            click('approve'); check(not lp.error,'companion admission failed: '..tostring(lp.error))
            if not lp.menuOpen then menu() end
        end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            connections=connections+1; generation=link.generation
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(99) and #c.runtime.saveData.trainCars>1 then return false,'injected train purchase checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave then capture='host-upgrade-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-upgrade-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'upgrade checkpoint retry failed'); saveRetried=true; stage='hosting'
        end
        if connections==1 and not link then
            local saved=assert(Save.read(99)); local own=saved.players.companion
            check(saveRetried and saved.scrap==115 and saved.resources.coal==27 and #saved.trainCars==3 and saved.engineLevel==2,'train changes not durable')
            check(saved.players.host.itemSlots.equipment[1].id==hostItem and c.runtime.player.x==hostX,'guest changed host ownership/position')
            check(not own.inventory[1] and not own.inventory[2] and not own.inventory[3],'fuel was not consumed from guest')
            check(saved.location==50 and saved.scene=='train' and saved.players.host.activeCar==1 and own.activeCar==1,'train assistance progressed story or moved host')
        elseif connections==2 and not link then finish() end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); guestItem=lp.replica.data.players.companion.itemSlots.equipment[1].id; epoch=lp.replica.data.coop.sceneEpoch
            capture='guest-train-world.png'; stage='world-ready'
        elseif stage=='world-ready' and captured['guest-train-world.png'] and lp.clientView:inputAllowed() then
            check(lp.clientView.train:nearFire(),'guest cannot reach firebox'); steps=plan(); index=1; stage='actions'
        elseif stage=='actions' then
            local view=lp.clientView; local entry=steps[index]
            if request then
                local result=lp.network.lastCommandResult
                if result and result.requestId==request then
                    check(result.ok~=(entry.rejected==true),'unexpected train result: '..tostring(result.reason))
                    if not view.train.pending then
                        check(result.command==entry.name and (entry.rejected or result.durable),'missing durable train receipt')
                        entry.verify(view.runtime.saveData,result); check(view.runtime.saveData.coop.sceneEpoch==epoch,'train assistance changed party epoch')
                        request=nil; lastAction=now; index=index+1; capture=entry.capture
                    end
                end
            elseif confirming then
                if not capture and view:actionsAllowed() then
                    app.draw(); if touch then press(view.ui.trainConfirm) else app.gamepadpressed({},'a') end
                    check(view.train.pending,'confirmation did not submit'); request=view.train.pending.id; confirming=nil
                end
            elseif not entry and not capture then
                view.train:close(); menu(); click('leave'); stage='rejoin'; rejoinAt=now
            elseif entry and not capture and (not lastAction or now-lastAction>.6) and view:actionsAllowed() then
                app.draw(); entry.run(view)
                if entry.confirm then confirming=true else check(view.train.pending,'fuel input did not submit'); request=view.train.pending.id end
            end
        elseif stage=='rejoin' and now-rejoinAt>.4 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local data=lp.replica.data
            check(data.scrap==115 and data.resources.coal==27 and #data.trainCars==3 and data.engineLevel==2,'reconnect lost upgrades or fuel')
            check(data.players.companion.itemSlots.equipment[1].id==guestItem and data.coop.sceneEpoch==epoch,'reconnect replaced actor or advanced story')
            click('leave'); print('LAN_TRAIN_OK role=guest fuel=true fullStorage=true upgrades=true saved=true hostOnlyStory=true'); finish()
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
