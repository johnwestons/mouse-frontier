-- Two full applications: host route validation, party scene replication,
-- guest input after every barrier, durable retry and reconnect.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local route=assert(os.getenv('MOUSE_FRONTIER_PARTY_SCENE'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Areas=require('game.expedition_areas'); local Caravan=require('game.crow_caravan_area')
local Caravans=require('game.crow_caravans'); local Viewport=require('game.viewport')
local Inventory=require('game.inventory'); local Style=require('game.ui_layout')
local app,c,started,finished,stage,steps,index,epoch,stageAt,distance,generation,connections
local guestEpoch,guestIndex,request,walkAt,rejoinAt,movementKey,walking,keyboardQuery,restoreWrite,retryAt,initialReadyAt
local capture,lastDiagnostic,walkDirection; local captured={}
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing production control')
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('party-button',x,y); app.touchreleased('party-button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function bag(rect) return Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect) end
local function stopWalk()
    movementKey=nil
    if walking then app.touchreleased('party-walk',0,0); walking=false end
end
local function walk(view)
    if not walkDirection then
        local own=view.runtime.player; local data=view.runtime.saveData
        for _,direction in ipairs({{1,0,'d'},{0,-1,'w'},{0,1,'s'},{-1,0,'a'}}) do
            local x,y=c.ui.localPlay.context.movement.move(data,data.players.companion,own.x,own.y,own.x+direction[1]*12,own.y+direction[2]*12)
            if (x-own.x)^2+(y-own.y)^2>25 then walkDirection=direction; break end
        end
        check(walkDirection,'authored party spawn has no movement route')
    end
    if touch then
        local stick=view.mobile.joystick; local ox,oy,sx,sy=Viewport.transform(960,720)
        if not walking then app.touchpressed('party-walk',ox+stick.x*sx,oy+stick.y*sy); walking=true end
        app.touchmoved('party-walk',ox+(stick.x+walkDirection[1]*stick.radius*.95)*sx,oy+(stick.y+walkDirection[2]*stick.radius*.95)*sy,0,0)
    else movementKey=walkDirection[3] end
end
local function toggleBag(view)
    app.draw()
    if touch then
        if view.runtime.inventoryOpen then press(bag(view.inventory.closeButton)) else press(view.mobile.backpack) end
    else app.keypressed('i'); app.keyreleased('i') end
end
local function finish()
    if finished then return end; finished=true; stopWalk()
    if keyboardQuery then love.keyboard.isDown=keyboardQuery end
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true party='..route..' transitions='..#steps..' saveRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function expeditionGate(id)
    for _,gate in ipairs(Areas.current(c.runtime.saveData).interactions) do if gate.id==id then return gate end end
    error('missing authored expedition gate '..id)
end
local function routed(action,id)
    local runtime=c.runtime; local data=runtime.saveData; local world=c.worldSessionComposition.worldScene
    local gate
    if action=='caravan' then gate=Caravan.stopEntrance(data.location)
    elseif action=='caravan-return' then gate={x=480,y=660}
    elseif action=='surface' then gate=Areas.entrance(data.location)
    else gate=expeditionGate(id) end
    runtime.player.x,runtime.player.y=gate.x,gate.y
    if action=='caravan' or action=='caravan-return' then
        return world.activateCaravanInteraction(world.currentCaravanInteraction())
    end
    return world.activateExpeditionInteraction(Areas.interaction(data,runtime.scene,runtime.player))
end
local function plan()
    local result={{scene='stop',run=function() return c.ui.transitionParty('scene.leaveTrain',{}).ok end}}
    if route=='caravan' then
        result[#result+1]={scene='caravan',run=function() return routed('caravan') end}
        result[#result+1]={scene='stop',run=function() return routed('caravan-return') end}
        result[#result+1]={scene='caravan',run=function() return routed('caravan') end}
    else
        local badlands=route=='badlands'
        result[#result+1]={scene='expedition',area=badlands and Areas.BADLANDS_SURFACE_ID or Areas.SURFACE_ID,run=function() return routed('surface') end}
        result[#result+1]={scene='expedition',area=badlands and Areas.BADLANDS_BASIN_ID or Areas.DUNGEON_ID,
            run=function() return routed('area',badlands and 'basin-entrance' or 'dungeon-entrance') end}
        result[#result+1]={scene='expedition',area=badlands and Areas.BADLANDS_SURFACE_ID or Areas.SURFACE_ID,
            run=function() return routed('area',badlands and 'return-approach' or 'return-surface') end}
        result[#result+1]={scene='stop',run=function() return routed('return',badlands and 'return-stop-5' or 'return-town') end}
    end
    result[#result+1]={scene='train',run=function() return c.ui.transitionParty('scene.returnTrain',{}).ok end}
    return result
end
local function beginStep()
    index=index+1; local data=c.runtime.saveData; local lp=c.ui.localPlay
    Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'food-ration')
    -- The first route entry fails one real disk checkpoint, then uses the
    -- production retry input; commands may not pass the pending barrier.
    if index==2 then
        restoreWrite=love.filesystem.write
        love.filesystem.write=function(path,bytes)
            if path==Save.path(99) then return false,'injected party checkpoint failure' end
            return restoreWrite(path,bytes)
        end
    end
    c.runtime.dialogue=nil
    check(steps[index].run(),'host route rejected step '..index)
    check(data.scene==steps[index].scene and data.activeExpeditionArea==steps[index].area,'host route destination mismatch')
    epoch=data.coop.sceneEpoch; stageAt=love.timer.getTime(); distance=0
    capture='host-party-'..index..'.png'
    if index==2 then
        check(lp.authority.pendingSave,'party checkpoint injection did not block')
        check(lp.context.commands.submit('scene.returnTrain',{}).reason=='save_pending','pending scene accepted another command')
        retryAt=stageAt+.7
    end
    stage='steps'
end
local function load()
    started=love.timer.getTime(); connections=0; index=0; love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    keyboardQuery=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if key==movementKey then return true end; return keyboardQuery(key,...) end
    steps=plan(); local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=route=='caravan' and 9 or route=='badlands' and 5 or 6
        data.events[tostring(data.location)]={id='resolved'}; data.encounters[tostring(data.location)]={hasMob=false,resolved=true}
        data.trainCars={'living-car','storage'}; data.resources.food=0; data.passengers={}
        data.crowCaravans={scheduledStops={9,24,40},scheduleVersion=1,scheduleMode='journey',camps={}}
        check(c.enterGame(data),'fixture campaign failed')
        local remote=lp.context.commands.remote
        lp.context.commands.remote=function(peerGeneration,command)
            local reply=remote(peerGeneration,command)
            print('LAN_PARTY_COMMAND request='..command.requestId..' epoch='..command.sceneEpoch..' ok='..tostring(reply.ok)
                ..' reason='..tostring(reply.reason)..' durable='..tostring(reply.durable)..' state='..c.runtime.state
                ..' ready='..tostring(lp.motion and lp.motion.readyEpoch)..' motionEpoch='..tostring(lp.motion and lp.motion.epoch)
                ..' currentEpoch='..c.runtime.saveData.coop.sceneEpoch..' battle='..tostring(c.runtime.battle~=nil)
                ..' firstAid='..tostring(c.runtime.firstAid~=nil))
            return reply
        end
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            Items.write(Players.forActor(campaign,'companion'),nil,{kind='inventory',index=1},'food-ration')
            return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'host failed'); menu()
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Party route friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    check(love.timer.getTime()-started<100,'party deadline stage='..tostring(stage)..' step='..tostring(index)..' guest='..tostring(guestIndex))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end
    if not lastDiagnostic or now-lastDiagnostic>5 then
        lastDiagnostic=now
        print('LAN_PARTY_PROGRESS role='..role..' stage='..tostring(stage)..' step='..tostring(index)..' phase='..tostring(lp.phase)
            ..' epoch='..tostring(role=='host' and c.runtime.saveData.coop.sceneEpoch or lp.clientView and lp.clientView.epoch)
            ..' pending='..tostring(lp:pending()~=nil)..' menu='..tostring(lp.menuOpen))
        if role=='host' and lp.motion and lp.motion.actor then
            print('LAN_PARTY_MOTION distance='..tostring(lp.motion.actor.animationDistance)..' ready='..tostring(lp.motion.readyEpoch)
                ..' xy='..lp.motion.actor.x..','..lp.motion.actor.y..' item='..tostring(c.runtime.saveData.players.companion.inventory[1]))
        end
    end
    if role=='host' then
        if lp:pending() then click('approve'); if lp.menuOpen then click('close') end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        if restoreWrite and now>=retryAt then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'production checkpoint retry failed')
        end
        if stage=='hosting' and connections==1 and not c.runtime.saveData.players.companion.inventory[1] then
            initialReadyAt=initialReadyAt or now
            if now-initialReadyAt>.6 and lp.motion.readyEpoch==c.runtime.saveData.coop.sceneEpoch then beginStep() end
        elseif stage=='steps' then
            check(link and link.admitted,'guest disconnected during party scene')
            local data=c.runtime.saveData
            if not restoreWrite and now-stageAt>(index==#steps and .2 or 1.6) and lp.motion.readyEpoch==epoch
                and not data.players.companion.inventory[1] and (lp.motion.actor.animationDistance or 0)-distance>4 then
                check(data.coop.sceneEpoch==epoch,'guest progressed the scene')
                local a,b=data.players.host,data.players.companion
                check((a.playerX-b.playerX)^2+(a.playerY-b.playerY)^2>=24^2,'party members overlap')
                print('LAN_PARTY_STEP_OK role=host step='..index..' scene='..data.scene..' area='..tostring(data.activeExpeditionArea)..' guestInput=true durable=true')
                if index<#steps then beginStep() else stage='done' end
            end
        elseif stage=='done' and connections==2 and not link then
            local saved=assert(Save.read(99))
            check(saved.scene=='train' and not saved.activeExpeditionArea and saved.resources.food==(#steps+1)*3,'party rewards/scene did not persist once')
            if route=='caravan' then check(saved.crowCaravans.meetings==1 and Caravans.lookup(saved,9).visited,'caravan entry repeated first visit') end
            finish()
        end
    else
        if lp.error then error('Local Play: '..lp.error) end
        local view=lp.clientView
        if stage=='joining' and view and view.ready and lp.motionFrame and lp.motionFrame.ready then
            click('close'); guestEpoch=view.epoch; guestIndex=0; toggleBag(view)
            app.draw(); press(bag(touch and Inventory.mobileInventorySlotRect(1) or Inventory.inventorySlotRect(1)))
            app.draw(); press(bag(view.ui.consume)); check(view.inventory.pending,'initial guest ready command missing')
            request=view.inventory.pending.id; stage='initial-receipt'
        end
        if stage=='initial-receipt' then
            local reply=lp.network.lastCommandResult
            if reply and reply.requestId==request and not view.inventory.pending then
                check(reply.ok and reply.durable,'initial ready receipt failed'); stage='steps'
            end
        elseif stage=='steps' and view and view.epoch~=guestEpoch and view:actionsAllowed() then
            guestEpoch=view.epoch; guestIndex=guestIndex+1; index=guestIndex; stopWalk(); walkDirection=nil
            check(steps[index] and view.runtime.scene==steps[index].scene and view.runtime.saveData.activeExpeditionArea==steps[index].area,'guest scene/area mismatch')
            check(not view.runtime.inventoryOpen,'guest backpack survived scene barrier')
            capture='guest-party-'..index..'.png'; walkAt=now; walk(view); stage='walking'
        elseif stage=='receipt' then
            local reply=lp.network.lastCommandResult
            if reply and reply.requestId==request and not view.inventory.pending then
                check(reply.ok and reply.durable and (view.epoch~=guestEpoch or not view.runtime.saveData.inventory[1]),'guest durable scene command failed: '..tostring(reply.reason))
                if index==#steps then menu(); click('leave'); stage='rejoin'; rejoinAt=now else stage='steps' end
            end
        elseif stage=='walking' then
            walk(view)
            if lp.motionFrame and lp.motionFrame.sceneEpoch==guestEpoch and lp.motionFrame.companion.d>6000 then
                stopWalk(); toggleBag(view)
                app.draw(); press(bag(touch and Inventory.mobileInventorySlotRect(1) or Inventory.inventorySlotRect(1)))
                app.draw(); press(bag(view.ui.consume)); check(view.inventory.pending,'guest food command missing')
                request=view.inventory.pending.id; stage='receipt'
            end
        elseif stage=='rejoin' and now-rejoinAt>.6 then menu(); click('join'); stage='second'
        elseif stage=='second' and view and view.ready and lp.motionFrame and lp.motionFrame.ready then
            check(view.runtime.scene=='train' and view.runtime.saveData.resources.food==(#steps+1)*3,'rejoin lost party checkpoint')
            menu(); click('leave'); finish()
        end
    end
end
local function draw()
    if finished or not app then return end; app.draw()
    if capture then local name=capture; capture=nil; love.graphics.captureScreenshot(function(data) data:encode('png',name); captured[name]=true end) end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        io.stderr:write('LAN_PARTY_ERROR '..tostring(reason)..'\n'); io.stderr:flush()
        if keyboardQuery then love.keyboard.isDown=keyboardQuery end
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() guarded(draw) end
