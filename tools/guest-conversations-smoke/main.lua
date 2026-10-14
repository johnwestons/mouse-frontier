-- Two complete applications: actual host controls and passive guest story view.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local UIStyle=require('game.ui_layout')
local Conversations=require('game.npc_conversations')
local app,c,started,finished,stage,capture,restoreWrite,rejoinAt,forbiddenId,epoch,food,water,hostXp,guestXp
local captured={}; local generation; local connections=0; local npc='crow-merchant.png'
local moving,walking=false,false
local diagnosticAt=0
local function check(value,message) assert(value,message) end
local function press(rect,dialogue)
    check(rect,'missing conversation control: '..tostring(stage))
    if dialogue then rect=UIStyle.transformRectFor('dialogue',{x=80,y=45,w=800,h=630},rect) end
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('conversation-test',x,y); app.touchreleased('conversation-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function stopWalk()
    moving=false
    if walking then app.touchreleased('conversation-walk',0,0); walking=false end
end
local function walk(view)
    if not moving or not touch or not view or not view:inputAllowed() then
        if walking then app.touchreleased('conversation-walk',0,0); walking=false end
        return
    end
    if not walking then app.draw() end
    local stick=view.mobile.joystick; local ox,oy,sx,sy=Viewport.transform(960,720)
    if not walking then app.touchpressed('conversation-walk',ox+stick.x*sx,oy+stick.y*sy); walking=true end
    check(view.mobile.joystickTouch=='conversation-walk','touch joystick was not captured')
    app.touchmoved('conversation-walk',ox+(stick.x+stick.radius*.95)*sx,oy+stick.y*sy,0,0)
end
local function finish()
    if finished then return end; finished=true
    stopWalk()
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true conversations=true checkpointRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    local keyboard=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for _,key in ipairs({...}) do if not touch and role=='guest' and moving and key=='d' then return true end end
        return keyboard(...)
    end
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.location=20; data.scene='stop'; c.runtime.scene='stop'
        local layout=c.ensureStopLayout(); layout.npcOutside=npc; layout.npc=npc; layout.npcOffers={}; c.setupNPC()
        c.runtime.npcActor.x=600; c.runtime.npcActor.y=430
        c.runtime.npcActor.targetX=nil; c.runtime.npcActor.wait=100
        c.runtime.player.x=550; c.runtime.player.y=430; data.playerX=550; data.playerY=430
        data.conversations={assignments={['20']={id='food',npc=npc,location=20}},completed={},seen={}}
        data.resources.food=30; data.resources.water=30
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            campaign.players.companion.playerX=550; campaign.players.companion.playerY=430
            return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error))
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Conversation test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    check(love.timer.getTime()-started<100,'conversation fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if now-diagnosticAt>10 then
        diagnosticAt=now
        local view=lp.clientView; local actor=c.runtime.saveData and c.runtime.saveData.players.companion
        print('LAN_CONVERSATION_STATE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)
            ..' connections='..connections..' menu='..tostring(lp.menuOpen)..' moving='..tostring(moving)
            ..' ownX='..tostring(view and view.runtime.player and view.runtime.player.x)..' savedX='..tostring(actor and actor.playerX)
            ..' allowed='..tostring(view and view:inputAllowed())..' ready='..tostring(lp.motionFrame and lp.motionFrame.ready)
            ..' paused='..tostring(lp.motionFrame and lp.motionFrame.paused)..' hostState='..tostring(c.runtime.state)
            ..' hostScene='..tostring(c.runtime.scene)..' hostBattle='..tostring(c.runtime.battle~=nil)
            ..' hostRange='..tostring(c.runtime.shootingRange~=nil)..' hostTravel='..tostring(c.runtime.travelTransition~=nil)
            ..' hostStand='..tostring(c.runtime.lastStand and c.runtime.lastStand.capture)
            ..' hostAmbush='..tostring(c.runtime.trainAmbush and c.runtime.trainAmbush.phase)
            ..' pending='..tostring(lp.authority and lp.authority.pendingSave~=nil)
            ..' focused='..tostring(lp.focused)..' motionAllowed='..tostring(lp.motion and lp.motion:allowed()))
    end
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)) end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            generation=link.generation; connections=connections+1
        end
        local data=c.runtime.saveData; local guest=data.players.companion
        if stage=='hosting' and guest and guest.playerX>558 then
            if lp.menuOpen then click('close') end
            app.keypressed('e'); app.keyreleased('e')
            check(c.runtime.helpDialogue and c.runtime.helpDialogue.authored,'host talk did not begin authored prompt')
            capture='host-conversation-prompt.png'; stage='prompt'
        elseif stage=='prompt' and guest.playerX>580 then
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.conversations.completed.food then return false,'injected story checkpoint failure' end
                return restoreWrite(path,bytes)
            end
            app.draw()
            if touch then press(c.ui.helpDialogueChoices[2],true) else app.keypressed('2'); app.keyreleased('2') end
            check(data.conversations.completed.food and data.conversations.completed.food.answer==2,'host choice did not commit')
            check(lp.authority.pendingSave,'story save failure did not block persistence')
            capture='host-conversation-save-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-conversation-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'story save retry failed'); stage='response'
        elseif stage=='response' and connections==2 and guest.playerX>620 then
            app.draw(); press(c.ui.dialogueContinue,true); stage='dismissed'
        elseif stage=='dismissed' and connections==2 and not link then
            local saved=assert(Save.read(99))
            check(saved.conversations.completed.food.answer==2 and not saved.conversations.active,'dismissal not saved')
            check(saved.conversations.completed.food.rewardRecipients.host==5 and saved.conversations.completed.food.rewardRecipients.companion==5,'party XP missing')
            print('LAN_CONVERSATIONS_OK role=host sharedCostOnce=true sharedXPOnce=true hostChoice=true checkpointRetry=true reconnect=true')
            finish()
        end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local data=lp.replica.data
            epoch=data.coop.sceneEpoch; food=data.resources.food; water=data.resources.water
            hostXp=data.players.host.stats.xp; guestXp=data.players.companion.stats.xp
            moving=true; stage='wait-prompt'
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif lp.clientView and stage~='joining' and stage~='rejoin' then
            local data=lp.replica.data; local read=Conversations.readAlong(data); local view=lp.clientView
            if stage=='wait-prompt' and read and read.waiting then
                stopWalk()
                check(read.text=='Got any food i can get?' and not read.choices and not read.notice,'guest prompt differs or leaks choices')
                app.keypressed('3'); app.keyreleased('3')
                check(not data.conversations.completed.food and data.resources.food==food,'guest key chose the branch')
                forbiddenId=assert(lp.network:submitCommand('conversation.choose',{id='food',index=2},epoch,{}))
                capture='guest-conversation-prompt.png'; stage='forbidden'
            elseif stage=='forbidden' then
                local outcome=lp.network.lastCommandResult
                if outcome and outcome.requestId==forbiddenId then
                    check(not outcome.ok and outcome.reason=='host_only','guest story packet accepted')
                    moving=true; stage='wait-response'
                end
            elseif stage=='wait-response' and read and not read.waiting then
                stopWalk()
                check(read.text=='You bet I am, and yes please that would be delightful','guest response differs')
                check(data.resources.food==food-2 and data.resources.water==water-1,'story cost repeated')
                check(data.players.host.stats.xp==hostXp+5 and data.players.companion.stats.xp==guestXp+5,'story XP repeated or missing')
                check(data.coop.sceneEpoch==epoch,'conversation progressed the scene')
                capture='guest-conversation-response.png'; stage='disconnect'
            elseif stage=='disconnect' and captured['guest-conversation-response.png'] then
                menu(); click('leave'); rejoinAt=now; stage='rejoin'
            elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
                check(read and not read.waiting and data.resources.food==food-2,'reconnect lost or repeated story outcome')
                check(data.conversations.completed.food.rewardRecipients.companion==5,'reconnect lost XP receipt')
                click('close'); moving=true; capture='guest-conversation-rejoined.png'; stage='wait-dismiss'
            elseif stage=='wait-dismiss' and not read then
                stopWalk(); check(data.conversations.completed.food.answer==2,'dismissal lost completion')
                menu(); click('leave')
                print('LAN_CONVERSATIONS_OK role=guest readAlong=true choiceDenied=true keyboardDenied=true reconnect=true')
                finish()
            end
        end
        walk(lp.clientView)
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
