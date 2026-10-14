-- Real full applications, event controls, save retry and passive reconnect.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Style=require('game.ui_layout')
local Events=require('game.events'); local SavedEvents=require('game.coop_events')
local app,c,stage,started,finished,capture,restoreWrite,rejoinAt,requestId,food,water,rng
local captured={}; local denied=0; local generation; local connections=0; local nextDenied=1; local diagnosticAt=0
local moving=false
local function check(value,message) assert(value,message) end
local function press(rect,event)
    check(rect,'missing control: '..tostring(stage))
    if event then rect=Style.transformRectFor('event',{x=60,y=42,w=840,h=640},rect) end
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('event-test',x,y); app.touchreleased('event-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true events=true checkpointRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    local keyboard=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for _,key in ipairs({...}) do if role=='guest' and moving and key=='d' then return true end end
        return keyboard(...)
    end
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=4; data.forceEventId='dry-camp'
        data.resources.food=30; data.resources.water=30
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error))
        local original=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=original(gen,request)
            if request.command:match('^event%.') then
                check(not reply.ok and reply.reason=='host_only','guest event command accepted')
                denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Event test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'event fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay
    if now-diagnosticAt>10 then
        diagnosticAt=now
        print('LAN_EVENT_STATE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)
            ..' hostScreen='..tostring(c.runtime.state)..' connections='..connections..' denied='..denied
            ..' current='..tostring(c.runtime.saveData and c.runtime.saveData.events.current and c.runtime.saveData.events.current.phase)
            ..' ready='..tostring(lp.motionFrame and lp.motionFrame.ready)..' paused='..tostring(lp.motionFrame and lp.motionFrame.paused))
    end
    app.focus(true)
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)) end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        local data=c.runtime.saveData
        if stage=='hosting' and link and link.admitted and link.phase=='ready' then
            if lp.menuOpen then click('close') end
            check(c.beginRandomEvent(),'host event did not open'); check(data.events.current.phase=='prompt','prompt was not saved')
            capture='host-event-prompt.png'; stage='prompt'
        elseif stage=='prompt' and denied>=3 and captured['host-event-prompt.png'] then
            food=data.resources.food; water=data.resources.water
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.events.current and data.events.current.phase=='chosen' then return false,'injected event write failure' end
                return restoreWrite(path,bytes)
            end
            app.draw()
            if touch then press(c.ui.eventChoices[1],true) else app.keypressed('1'); app.keyreleased('1') end
            app.draw(); check(c.runtime.pendingConfirmation,'host event confirmation missing')
            press(c.ui.confirmYes)
            check(data.events.current.phase=='chosen' and lp.authority.pendingSave,'choice failure did not stage barrier')
            check(data.resources.food==food and data.resources.water==water-3,'choice cost differs')
            rng=data.coop.randomState; capture='host-event-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-event-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'event checkpoint retry failed')
            check(data.coop.randomState==rng and data.resources.water==water-3,'retry repeated event')
            capture='host-event-outcome.png'; stage='chosen'
        elseif stage=='chosen' and connections==2 and denied>=4 then
            app.draw(); check(c.ui.eventContinue and not c.ui.eventChoices,'host outcome controls differ')
            if touch then press(c.ui.eventContinue,true) else app.keypressed('return'); app.keyreleased('return') end
            check(not data.events.current and c.runtime.scene=='stop','host continuation did not enter the stop')
            capture='host-event-continued.png'; stage='continued'
        elseif stage=='continued' and not link then
            local saved=assert(Save.read(99))
            check(saved.events['4'].id=='dry-camp' and saved.events['4'].choice==1 and not saved.events.current,'saved continuation lost receipt')
            check(saved.resources.food==food and saved.resources.water==water-3 and saved.coop.randomState~=nil,'saved event cost lost')
            print('LAN_EVENTS_OK role=host decisionsOnly=true saveRetry=true costOnce=true reconnect=true'); finish()
        end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready then
            click('close'); stage='prompt'
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif lp.clientView and stage~='joining' and stage~='rejoin' then
            local data=lp.replica.data; local read=SavedEvents.readAlong(data); local view=lp.clientView
            if stage=='prompt' and read and read.waiting and lp.motionFrame.ready then
                food=data.resources.food; water=data.resources.water
                check(read.id=='dry-camp' and not read.choices,'guest event prompt differs')
                app.keypressed('1'); app.keyreleased('1'); app.keypressed('return'); app.keyreleased('return')
                check(data.events.current.phase=='prompt','guest keyboard progressed event')
                app.draw(); check(view.eventReadAlong and not view.ui.eventChoices and not view.ui.eventContinue,'guest event control leak')
                capture='guest-event-prompt.png'; stage='denied'
            elseif stage=='denied' then
                local names={'event.begin','event.choose','event.continue'}
                if requestId then
                    local result=lp.network.lastCommandResult
                    if result and result.requestId==requestId then
                        check(not result.ok and result.reason=='host_only','guest event packet accepted')
                        nextDenied=nextDenied+1; requestId=nil
                    end
                elseif nextDenied<=3 then
                    requestId=assert(lp.network:submitCommand(names[nextDenied],{id='dry-camp',index=3},data.coop.sceneEpoch,{}))
                else stage='chosen' end
            elseif stage=='chosen' and read and not read.waiting then
                check(read.answer==Events.findById('dry-camp').choices[1].label and data.resources.food==food and data.resources.water==water-3,'guest outcome or cost differs')
                app.draw(); check(view.eventReadAlong and not view.ui.eventContinue,'guest outcome had Continue')
                rng=data.coop.randomState; capture='guest-event-outcome.png'; stage='disconnect'
            elseif stage=='disconnect' and captured['guest-event-outcome.png'] then
                menu(); click('leave'); rejoinAt=now; stage='rejoin'
            elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
                check(read and not read.waiting and data.resources.water==water-3 and data.coop.randomState==rng,'reconnect lost or repeated event')
                click('close'); capture='guest-event-rejoined.png'
                requestId=assert(lp.network:submitCommand('event.continue',{id='dry-camp'},data.coop.sceneEpoch,{})); stage='continued'
            elseif stage=='continued' and not read and data.scene=='stop' and lp.motionFrame and lp.motionFrame.ready then
                check(data.events['4'].choice==1 and data.resources.water==water-3,'host continuation changed committed outcome')
                menu(); click('leave')
                print('LAN_EVENTS_OK role=guest readAlong=true choiceDenied=true keyboardDenied=true reconnect=true'); finish()
            end
        end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite end
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
