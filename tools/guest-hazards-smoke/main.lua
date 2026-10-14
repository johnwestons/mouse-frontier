-- Two real apps: flood moves both actors, clears old prediction and preserves
-- scene ownership. Freeze only the private fixture's flooded phase for QA.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Areas=require('game.expedition_areas'); local Save=require('game.save'); local Viewport=require('game.viewport')
local Style=require('game.ui_layout')
local app,c,stage,started,finished,capture,oldMotion,epoch,health,guestHealth
local denied=0; local captured={}
local function check(value,message) assert(value,message) end
local function area(data) return data.expeditions[Areas.BADLANDS_BASIN_ID] end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('flood-test',x,y); app.touchreleased('flood-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function finish()
    if finished then return end; finished=true; check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true hazards=true twoSafeActors=true movementReset=true sameScene=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=5; data.scene=Areas.SCENE; data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; data.passengers={}
        Areas.ensure(data); check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
        for _,mob in pairs(area(data).mobs) do mob.hp=0; mob.dead=true end
        c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,Areas.BADLANDS_BASIN_ID,780,500)
        data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y; c.runtime.expeditionGraceTimer=999
        area(data).environmentClock=0; area(data).environmentPhase='dry'; health=data.health
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local original=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local r=original(gen,request)
            if request.command=='scene.returnTrain' then check(not r.ok and r.reason=='host_only','guest progressed scene'); denied=denied+1 end
            return r
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Flood test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'flood fixture deadline '..tostring(stage))
    if role=='host' and stage=='corrected' then area(c.runtime.saveData).environmentClock=14.01 end
    app.update(math.min(.05,dt)); app.focus(true)
    local lp=c.ui.localPlay
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local data=c.runtime.saveData; local motion=lp.motion; local link=lp.network and lp.network.link
        if stage=='hosting' and denied==1 and motion and motion.readyEpoch==motion.epoch and motion.input and motion.input.x>0 then
            if lp.menuOpen then click('close') end
            oldMotion=motion.motionId; epoch=data.coop.sceneEpoch; guestHealth=data.players.companion.health
            local savedArea=area(data); local phase=savedArea.environmentPhase; savedArea.environmentPhase='flooded'
            check(Areas.isInFlood(data,data.activeExpeditionArea,c.runtime.player.x,c.runtime.player.y),'host fixture is outside flood')
            check(Areas.isInFlood(data,data.activeExpeditionArea,motion.actor.x,motion.actor.y),'guest fixture is outside flood')
            savedArea.environmentPhase=phase; savedArea.environmentClock=13.99; stage='flood'
        elseif stage=='flood' and area(data).environmentPhase=='flooded' then
            check(motion.motionId==oldMotion+1,'guest correction did not reset movement generation')
            check(not Areas.isInFlood(data,data.activeExpeditionArea,c.runtime.player.x,c.runtime.player.y),'host stayed in flood')
            check(not Areas.isInFlood(data,data.activeExpeditionArea,motion.actor.x,motion.actor.y),'guest stayed in flood')
            check((c.runtime.player.x-motion.actor.x)^2+(c.runtime.player.y-motion.actor.y)^2>=24^2,'party landed on same bank point')
            check(data.coop.sceneEpoch==epoch and data.health==health and data.players.companion.health==guestHealth,'flood changed story/health')
            capture='host-flood-bank.png'; stage='corrected'
        elseif stage=='corrected' and not link then
            local saved=assert(Save.read(99)); check(saved.coop.sceneEpoch==epoch and saved.scene=='expedition','saved flood changed scene')
            check(Areas.isWalkable(saved,saved.activeExpeditionArea,saved.playerX,saved.playerY),'host saved unsafe position')
            local guest=saved.players.companion
            check(Areas.isWalkable(saved,saved.activeExpeditionArea,guest.playerX,guest.playerY),'guest saved unsafe position')
            check(guest.health==guestHealth and saved.health==health,'saved flood cost health'); finish()
        end
    else
        if lp.error then error('Local Play failed '..lp.error) end
        local view=lp.clientView; local data=lp.replica and lp.replica.data
        if stage=='joining' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); oldMotion=lp.motionFrame.motionId; epoch=data.coop.sceneEpoch
            stage='flood'
            if touch then
                app.draw(); local m=view.mobile; local j=m.joystick
                local point=Style.transformRectFor('mobileControls',m:uiBounds(),{x=j.x+j.radius*.75,y=j.y,w=0,h=0})
                local ox,oy,sx,sy=Viewport.transform(960,720)
                app.touchpressed('flood-stick',ox+point.x*sx,oy+point.y*sy)
                check(m.axisX>0,'touch movement did not start')
            else view.context.keyDown=function(...) for _,key in ipairs({...}) do if key=='d' and stage=='flood' then return true end end; return false end end
            check(lp.network:submitCommand('scene.returnTrain',{},epoch,{}),'barrier command failed')
        elseif stage=='flood' and view and lp.motionFrame and lp.motionFrame.motionId>oldMotion then
            check(lp.motionFrame.motionId==oldMotion+1,'duplicate hazard correction')
            if touch then check(view.mobile.axisX==0 and view.mobile.axisY==0,'old touch movement survived correction') end
            stage='corrected'
        elseif stage=='corrected' and view and lp.motionFrame and lp.motionFrame.ready and area(data).environmentPhase=='flooded' then
            local p=view.runtime.player
            check(Areas.isWalkable(view.runtime.saveData,data.activeExpeditionArea,p.x,p.y,true),'guest prediction stayed in flood')
            check(data.coop.sceneEpoch==epoch and view.runtime.scene=='expedition' and not view.runtime.battle,'guest scene changed')
            capture='guest-flood-bank.png'; stage='finish'
        elseif stage=='finish' and captured['guest-flood-bank.png'] then menu(); click('leave'); finish() end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' stage='..tostring(stage)..' '..tostring(reason)); finished=true
        if c and c.ui.localPlay then c.ui.localPlay:stop() end
        love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw(); if capture then love.graphics.captureScreenshot(capture); captured[capture]=true; capture=nil end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
