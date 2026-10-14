-- Full-app proof that outer host modals retain shared simulation and commands.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Viewport=require('game.viewport'); local Inventory=require('game.inventory'); local Style=require('game.ui_layout')
local app,c,started,finished,stage,mode,modeAt,modeDistance,hostX,hostY,generation,connections
local guestMode,guestRequest,guestDistance,walking,movementKey,keyboardQuery,capture
local captured={}; local modes={'lan','escape','options','backpack','map','maintenance','sewing','controls'}
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing production control')
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('world-button',x,y); app.touchreleased('world-button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function bag(rect) return Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect) end
local function clearHostMode()
    local lp=c.ui.localPlay; lp.menuOpen=false
    if c.ui.playerToolsOpen then app.keypressed('f2'); app.keyreleased('f2') end
    c.ui.suspendOutfitWorkbench(); c.maintenance.close(c.maintenanceSession)
    c.ui.escMenuOpen=false; c.ui.optionsOpen=false; c.ui.radioOpen=false
    c.runtime.inventoryOpen=false; c.runtime.mapOpen=false; c.runtime.trainUpgradeOpen=false
end
local function beginMode(index)
    clearHostMode(); mode=index; modeAt=love.timer.getTime()
    local lp=c.ui.localPlay; local data=c.runtime.saveData
    local passenger=data.passengers[1]
    passenger.x=700; passenger.y=550; passenger.targetX=650; passenger.targetY=550; passenger.wait=100
    Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'food-ration')
    data.resources.water=8+index
    data.coop.revision=data.coop.revision+1
    for _,scope in ipairs({'player:companion','resources'}) do data.coop.revisions[scope]=(data.coop.revisions[scope] or 0)+1 end
    check(lp.context.commands.authority():checkpointNow(),'mode checkpoint failed'); lp.nextAudit=0
    modeDistance=lp.motion.actor.animationDistance or 0
    if index==1 then menu()
    elseif index==2 then app.keypressed('escape'); app.keyreleased('escape'); check(c.ui.escMenuOpen,'escape menu missing')
    elseif index==3 then c.ui.optionsOpen=true
    elseif index==4 then app.keypressed('i'); app.keyreleased('i'); check(c.runtime.inventoryOpen,'host backpack missing')
    elseif index==5 then app.keypressed('m'); app.keyreleased('m'); check(c.runtime.mapOpen,'host map missing')
    elseif index==6 then check(c.maintenance.open(c.maintenanceSession,data),'maintenance lease failed')
    elseif index==7 then check(c.ui.openOutfitWorkbench(),'host sewing lease failed')
    elseif index==8 then check(c.ui.openTouchControls() and c.ui.playerToolsOpen,'controls editor missing') end
    capture='host-modal-'..modes[index]..'.png'
end
local function walk(view)
    local direction=math.floor((love.timer.getTime()-started)*2)%2==0 and 1 or -1
    if touch then
        local stick=view.mobile.joystick; local ox,oy,sx,sy=Viewport.transform(960,720)
        if not walking then app.touchpressed('world-walk',ox+stick.x*sx,oy+stick.y*sy); walking=true end
        app.touchmoved('world-walk',ox+(stick.x+direction*stick.radius*.95)*sx,oy+stick.y*sy,0,0)
    else movementKey=direction==1 and 'd' or 'a' end
end
local function stopWalk()
    movementKey=nil
    if walking then app.touchreleased('world-walk',0,0); walking=false end
end
local function finish()
    if finished then return end; finished=true; stopWalk()
    if keyboardQuery then love.keyboard.isDown=keyboardQuery end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true world=true hostModals=8 reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); connections=0; love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    keyboardQuery=love.keyboard.isDown
    love.keyboard.isDown=function(key,...)
        if role=='host' then return key=='d' end
        if key==movementKey then return true end
        return keyboardQuery(key,...)
    end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        check(c.enterGame(c.newSave(c.characters[1])),'fixture journey failed')
        local data=c.runtime.saveData; data.trainCars={'living-car','storage'}; data.resources.food=0; data.resources.water=8
        data.passengers={{npc='crow-merchant.png',x=700,y=550,carIndex=1,weapon='trail-slingshot',destination=6,wait=100}}
        check(Items.ensure(data) and require('game.coop_entities').ensure(data),'fixture actors invalid')
        hostX=c.runtime.player.x; hostY=c.runtime.player.y
        menu(); click('port',port); click('host'); check(lp.network,'host failed'); menu()
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Shared world friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<100,'world fixture deadline: '..tostring(stage)..' mode='..tostring(mode))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); menu() end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        if stage=='hosting' and connections==1 and lp.motion.readyEpoch==c.runtime.saveData.coop.sceneEpoch then beginMode(1); stage='modes' end
        if stage=='modes' then
            check(link and link.admitted,'guest disconnected during host modal checks')
            check(c.runtime.player.x==hostX and c.runtime.player.y==hostY,'host modal leaked held movement')
            local data=c.runtime.saveData; local actor=lp.motion.actor
            if now-modeAt>=1 and not data.players.companion.inventory[1] and actor.moving and (actor.animationDistance or 0)-modeDistance>5 then
                check(data.passengers[1].x<699 and data.passengers[1].wait<100,'host '..modes[mode]..' paused shared passengers')
                print('LAN_WORLD_MODE_OK role=host mode='..modes[mode]..' sharedNPC=true guestMovement=true guestCommand=true hostStationary=true')
                if mode<#modes then beginMode(mode+1)
                else data.resources.water=17; check(lp.context.commands.authority():checkpointNow(),'final checkpoint failed'); lp.nextAudit=0; stage='done' end
            end
        elseif stage=='done' and connections==2 and not link then
            local saved=assert(Save.read(99))
            check(saved.resources.food==24 and saved.resources.water==17 and not saved.players.companion.inventory[1],'commands did not persist once')
            check(saved.location==1 and saved.scene=='train' and not lp.authority.bindings.companion,'story or admission changed')
            finish()
        end
    else
        if lp.error then error('Local Play: '..lp.error) end
        local view=lp.clientView
        if stage=='joining' and view and view.ready and lp.motionFrame and lp.motionFrame.ready then click('close'); stage='modes' end
        if stage=='modes' then
            local index=view.runtime.saveData.resources.water-8
            if index>=1 and index<=#modes and index~=guestMode then
                check(index==(guestMode or 0)+1,'missed a host modal')
                if guestMode then check(guestRequest==nil and lp.motionFrame.companion.d>guestDistance,'guest movement/receipt missing') end
                stopWalk(); guestMode=index; guestDistance=lp.motionFrame.companion.d
                app.draw(); if touch then press(view.mobile.backpack) else app.keypressed('i') end
                app.draw(); press(bag(touch and Inventory.mobileInventorySlotRect(1) or Inventory.inventorySlotRect(1)))
                app.draw(); press(bag(view.ui.consume)); check(view.inventory.pending,'guest food command missing'); guestRequest=view.inventory.pending.id
                stage='receipt'
            elseif index==9 then
                check(guestMode==8 and guestRequest==nil and view.runtime.saveData.resources.food==24,'final guest receipts missing')
                check(lp.motionFrame.companion.d>guestDistance,'final controls modal stopped guest movement')
                stopWalk(); menu(); click('leave'); stage='rejoin'; modeAt=now
            else walk(view) end
        elseif stage=='receipt' then
            local result=lp.network.lastCommandResult
            if result and result.requestId==guestRequest and not view.inventory.pending then
                check(result.ok and result.durable,'guest command rejected: '..tostring(result.reason))
                check(not view.runtime.saveData.inventory[1],'guest supply not projected')
                guestRequest=nil; app.draw()
                if touch then press(bag(view.inventory.closeButton)) else app.keypressed('i') end
                stage='modes'; walk(view)
            end
        elseif stage=='rejoin' and now-modeAt>.4 then menu(); click('join'); stage='second'
        elseif stage=='second' and view and view.ready then
            check(view.runtime.saveData.resources.food==24 and view.runtime.saveData.resources.water==17,'rejoin lost shared receipts')
            menu(); click('leave'); finish()
        end
    end
end
local function draw()
    if finished or not app then return end; app.draw()
    if capture then
        local name=capture; capture=nil
        love.graphics.captureScreenshot(function(data) data:encode('png',name); captured[name]=true end)
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        io.stderr:write('LAN_WORLD_ERROR '..tostring(reason)..'\n'); io.stderr:flush()
        if keyboardQuery then love.keyboard.isDown=keyboardQuery end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() guarded(draw) end
