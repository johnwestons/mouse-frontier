-- Two full applications: saved encounter entry and passive shared ending.
-- The jump from combat to stop 50 is fixture setup, not a campaign completion.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Finale=require('game.coop_finale')
local app,c,stage,started,finished,capture,restoreWrite,rejoinAt,requestId,encounterId,rollState,score
local captured={}; local denied=0; local generation; local connections=0; local diagnosticAt=0
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control: '..tostring(stage))
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('finale-test',x,y); app.touchreleased('finale-test',x,y)
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
    print('LAN_SMOKE_OK role='..role..' application=true finale=true encounter=true checkpointRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=15; data.eventProgress={story=10,mystery=5}
        check(c.enterGame(data),'fixture campaign failed')
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error))
        local original=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=original(gen,request)
            if request.command=='encounter.roll' or request.command=='finale.choose' then
                check(not reply.ok and reply.reason=='host_only','guest progression command accepted'); denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Ending test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'finale fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; app.focus(true)
    if now-diagnosticAt>10 then
        diagnosticAt=now
        print('LAN_FINALE_STATE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)
            ..' hostScreen='..tostring(c.runtime.state)..' connections='..connections..' denied='..denied
            ..' choice='..tostring(c.runtime.saveData and c.runtime.saveData.finale and c.runtime.saveData.finale.choice)
            ..' ready='..tostring(lp.motionFrame and lp.motionFrame.ready))
    end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)) end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        local data=c.runtime.saveData
        if stage=='hosting' and link and link.admitted and link.phase=='ready' and denied>=1 then
            if lp.menuOpen then click('close') end
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.encounters['15'] then return false,'injected encounter write failure' end
                return restoreWrite(path,bytes)
            end
            c.attemptLeaveTrain()
            check(data.encounters['15'] and lp.authority.pendingSave and not c.runtime.battle,'unsaved roll entered combat')
            encounterId=data.encounters['15'].entityId; rollState=data.coop.randomState
            capture='host-encounter-retry.png'; stage='roll-retry'
        elseif stage=='roll-retry' and captured['host-encounter-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'encounter retry failed'); c.attemptLeaveTrain()
            check(c.runtime.battle and data.encounters['15'].entityId==encounterId and data.coop.randomState==rollState,'saved boss entry rerolled')
            capture='host-boss-entry.png'; stage='boss'
        elseif stage=='boss' and captured['host-boss-entry.png'] then
            -- Deliberate fixture setup for the final scene. Combat simulation
            -- and guest battle participation are not tested by this fixture.
            c.runtime.battle=nil; data.tacticalBattle=nil; data.location=50; data.coop.journey=nil
            c.runtime.scene='train'; c.runtime.state='ending'; c.session:syncSceneEpoch('train')
            score=Finale.summary(data).score; capture='host-ending-prompt.png'; stage='prompt'
        elseif stage=='prompt' and denied>=2 and captured['host-ending-prompt.png'] then
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.finale.choice then return false,'injected ending write failure' end
                return restoreWrite(path,bytes)
            end
            app.draw()
            if touch then press(c.ui.endingChoices[2]) else app.keypressed('2'); app.keyreleased('2') end
            check(data.finale.choice=='family' and lp.authority.pendingSave,'ending choice did not stage barrier')
            capture='host-ending-retry.png'; stage='ending-retry'
        elseif stage=='ending-retry' and captured['host-ending-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave and Finale.summary(data).score==score,'ending retry changed outcome')
            capture='host-ending-outcome.png'; stage='chosen'
        elseif stage=='chosen' and connections==2 and denied>=3 and not link then
            local saved=assert(Save.read(99))
            check(saved.finale.choice=='family' and saved.finale.completed and Finale.summary(saved).score==score,'ending save differs')
            check(saved.encounters['15'].entityId==encounterId and saved.coop.randomState==rollState,'encounter save changed')
            print('LAN_FINALE_OK role=host hostDecision=true encounterSavedBeforeEntry=true retryNoReroll=true'); finish()
        end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready then
            click('close'); requestId=assert(lp.network:submitCommand('encounter.roll',{actorId='host'},lp.replica.data.coop.sceneEpoch,{})); stage='roll-denied'
        elseif stage=='roll-denied' then
            local result=lp.network.lastCommandResult
            if result and result.requestId==requestId then check(not result.ok and result.reason=='host_only','guest roll accepted'); requestId=nil; stage='prompt' end
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif lp.clientView and stage~='joining' and stage~='rejoin' then
            local data=lp.replica.data; local read=Finale.readAlong(data); local view=lp.clientView
            if stage=='prompt' and read and not read.choice and lp.motionFrame and lp.motionFrame.ready then
                score=read.score; encounterId=data.encounters['15'].entityId
                app.keypressed('2'); app.keyreleased('2'); app.keypressed('return'); app.keyreleased('return')
                check(not data.finale.choice,'guest keys chose ending')
                app.draw(); check(view.finaleReadAlong and not view.ui.endingChoices and not view.ui.endingButton,'guest finale control leak')
                capture='guest-ending-prompt.png'
                requestId=assert(lp.network:submitCommand('finale.choose',{id='haven',actorId='host'},data.coop.sceneEpoch,{})); stage='denied'
            elseif stage=='denied' then
                local result=lp.network.lastCommandResult
                if result and result.requestId==requestId then check(not result.ok and result.reason=='host_only','guest ending accepted'); requestId=nil; stage='chosen' end
            elseif stage=='chosen' and read and read.choice then
                check(read.choice.id=='family' and read.score==score and data.encounters['15'].entityId==encounterId,'shared ending differs')
                app.draw(); check(view.finaleReadAlong and not view.ui.endingButton,'guest outcome return control leak')
                capture='guest-ending-outcome.png'; stage='disconnect'
            elseif stage=='disconnect' and captured['guest-ending-outcome.png'] then
                menu(); click('leave'); rejoinAt=now; stage='rejoin'
            elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
                check(read and read.choice.id=='family' and read.score==score,'reconnect lost ending')
                click('close'); capture='guest-ending-rejoined.png'
                requestId=assert(lp.network:submitCommand('finale.choose',{id='lifeline'},data.coop.sceneEpoch,{})); stage='completed'
            elseif stage=='completed' and captured['guest-ending-rejoined.png'] then
                local result=lp.network.lastCommandResult
                if result and result.requestId==requestId then
                    check(not result.ok and result.reason=='host_only' and read.choice.id=='family','reconnected guest changed ending')
                    menu(); click('leave')
                    print('LAN_FINALE_OK role=guest readAlong=true choiceDenied=true keyboardDenied=true reconnect=true'); finish()
                end
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
