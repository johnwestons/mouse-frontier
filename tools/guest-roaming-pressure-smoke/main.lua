-- Real AI catches the guest; save retry/reconnect retain the prompt. The owner
-- alone chooses a battle, whose return point stays at their distant position.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local outcome=os.getenv('MOUSE_FRONTIER_PRESSURE_OUTCOME') or 'fight'
local Areas=require('game.expedition_areas'); local Save=require('game.save'); local Viewport=require('game.viewport')
local app,c,stage,started,finished,capture,epoch,health,guestHealth,restoreWrite,pressureId,rejoinAt
local captured={}; local connections=0; local generation; local denied=0; local firstGuestMotion
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('pressure-test',x,y); app.touchreleased('pressure-test',x,y)
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
    print('LAN_SMOKE_OK role='..role..' application=true roamingPressure=true guestTarget=true ownerDecision=true saveRetry=true reconnect=true outcome='..outcome..' input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=5; data.scene=Areas.SCENE; data.activeExpeditionArea=Areas.BADLANDS_SURFACE_ID; data.passengers={}
        Areas.ensure(data); check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
        local dead=data.expeditions[data.activeExpeditionArea].mobs['surface-cactus-rat']; dead.hp=0; dead.dead=true
        c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,data.activeExpeditionArea,1264,397)
        data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y; c.runtime.expeditionGraceTimer=999; health=data.health
        lp.context.placeCompanion=function(value)
            local guest=value.players.companion; guest.playerX,guest.playerY=Areas.clamp(value,value.activeExpeditionArea,914,565)
            return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local command=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=command(gen,request)
            if request.command=='roaming.pressure' or request.command=='battle.begin' or request.command=='scene.returnTrain' then
                check(not reply.ok and reply.reason=='host_only','guest made an encounter decision'); denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Encounter helper'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'pressure fixture deadline '..tostring(stage))
    app.update(math.min(.025,dt)); app.focus(true)
    local lp=c.ui.localPlay
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local data=c.runtime.saveData; local motion=lp.motion; local link=lp.network and lp.network.link
        if link and link.phase=='ready' and link.generation~=generation then generation=link.generation; connections=connections+1 end
        if stage=='hosting' and motion and motion.generation and motion.actor and motion.readyEpoch==motion.epoch then
            if lp.menuOpen then click('close') end
            epoch=data.coop.sceneEpoch; guestHealth=data.players.companion.health; firstGuestMotion=motion.motionId
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.roamingEncounter then return false,'injected pressure save failure' end
                return restoreWrite(path,bytes)
            end
            c.runtime.expeditionGraceTimer=0; stage='contact'
        elseif stage=='contact' and lp.authority.pendingSave then
            local s=data.roamingEncounter; check(s and s.actorId=='companion','guest pressure was not captured')
            check(data.coop.sceneEpoch==epoch and data.scene=='expedition' and not c.runtime.battle,'contact progressed story')
            check(data.health==health and data.players.companion.health==guestHealth,'contact invented field damage')
            pressureId=s.id; capture='host-pressure-save-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-pressure-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'pressure save retry failed'); stage='rejoin'
        elseif stage=='rejoin' and connections==2 and motion and motion.readyEpoch==motion.epoch and denied==3 then
            if lp.menuOpen then click('close') end
            check(data.roamingEncounter and data.roamingEncounter.id==pressureId and not motion:allowed(),'rejoin lost/advanced pressure')
            check((c.runtime.player.x-data.roamingEncounter.x)^2+(c.runtime.player.y-data.roamingEncounter.y)^2>330^2,'fixture host is not distant')
            app.draw(); capture='host-pressure-choice.png'; stage='choose'
        elseif stage=='choose' and captured['host-pressure-choice.png'] then
            press(c.ui.roamingEncounterControls[outcome=='fight' and 1 or 2]); check(not data.roamingEncounter,'host choice failed')
            if outcome=='fight' then
                check(c.runtime.battle,'host battle choice failed')
                local point=c.runtime.battle.encounter.returnContext
                check(point.x==1264 and point.y==397,'battle teleported host return point to guest')
                check(c.runtime.battle.units[2].actorId=='companion','companion has no owned tactical unit')
            else check(data.scene=='train' and not c.runtime.battle,'host withdrawal failed') end
            stage='battle'
        elseif stage=='battle' and not link then
            local saved=assert(Save.read(99)); check(not saved.roamingEncounter,'host choice was not durable')
            if outcome=='fight' then
                check(saved.tacticalBattle and saved.tacticalBattle.battle.encounter.returnContext.x==1264,'saved return point changed')
            else check(saved.scene=='train' and saved.players.companion.health==guestHealth and saved.health==health,'withdrawal changed health or did not save') end
            finish()
        end
    else
        if lp.error then error('Local Play failed '..lp.error) end
        local view=lp.clientView; local data=lp.replica and lp.replica.data
        if stage=='joining' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); epoch=data.coop.sceneEpoch; stage='contact'
        elseif stage=='contact' and data and data.roamingEncounter and view then
            check(view.runtime.scene=='expedition' and not view.runtime.battle and not view:actionsAllowed(),'guest was not held in field')
            pressureId=data.roamingEncounter.id; capture='guest-pressure-wait.png'; stage='denied'; denied=0
        elseif stage=='denied' then
            local reply=lp.network.lastCommandResult
            if reply and reply.reason=='host_only' and reply.requestId==firstGuestMotion then denied=denied+1; firstGuestMotion=nil end
            if not firstGuestMotion and denied<3 then
                local name=({'roaming.pressure','battle.begin','scene.returnTrain'})[denied+1]
                firstGuestMotion=assert(lp.network:submitCommand(name,{},data.coop.sceneEpoch,{}))
            elseif denied==3 then
                menu(); click('leave'); rejoinAt=now+.3; stage='rejoin'
            end
        elseif stage=='rejoin' and now>=rejoinAt then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            check(data.roamingEncounter and data.roamingEncounter.id==pressureId and not view:actionsAllowed(),'guest resumed outside saved wait')
            click('close'); stage='battle'
        elseif stage=='battle' and view and (outcome=='fight' and view.runtime.battle or outcome=='withdraw' and view.runtime.scene=='train') then
            check(not data.roamingEncounter and data.coop.sceneEpoch==epoch+1,'owner battle choice did not advance exactly once')
            if outcome=='fight' then check(view.runtime.battle.units[2].actorId=='companion','guest tactical ownership missing')
            else check(not view.runtime.battle,'withdrawal started a battle') end
            capture='guest-pressure-battle.png'; stage='finish'
        elseif stage=='finish' and captured['guest-pressure-battle.png'] then menu(); click('leave'); finish() end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' stage='..tostring(stage)..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
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
