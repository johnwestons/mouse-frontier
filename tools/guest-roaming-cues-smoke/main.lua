-- Real apps/ENet and the authored host-targeted patrol -> chase -> windup AI.
-- Freeze the private fixture at its first windup only to capture the guest UI.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Areas=require('game.expedition_areas'); local Save=require('game.save'); local Viewport=require('game.viewport')
local app,c,stage,started,finished,capture,health,guestHealth,epoch,firstX,firstY
local captured={}; local chased=false; local renderedWindup=false; local id='surface-dust-beetle'; local deadId='surface-cactus-rat'
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('cue-test',x,y); app.touchreleased('cue-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function finish()
    if finished then return end; finished=true; check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true roamingCues=true hostAI=true liveGait=true windup=true baselineDeadHidden=true sameScene=true input='..(touch and 'touch' or 'desktop'))
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
        local state=data.expeditions[data.activeExpeditionArea]; state.mobs[deadId].hp=0; state.mobs[deadId].dead=true
        c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,data.activeExpeditionArea,849,663)
        data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y; c.runtime.expeditionGraceTimer=999; health=data.health
        check(Areas.canReach(data,data.activeExpeditionArea,c.runtime.player.x,c.runtime.player.y,state.mobs[id].x,state.mobs[id].y),'fixture enemy LOS blocked')
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        local circle=love.graphics.circle
        love.graphics.circle=function(mode,x,y,radius,...)
            local r,g,b=love.graphics.getColor()
            if mode=='line' and radius>=80 and radius<=110 and r>.9 and g<.3 and b<.3 then renderedWindup=true end
            return circle(mode,x,y,radius,...)
        end
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Attack cue friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    check(love.timer.getTime()-started<100,'enemy cue fixture deadline '..tostring(stage))
    app.update(math.min(.025,dt)); app.focus(true)
    local lp=c.ui.localPlay
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local data=c.runtime.saveData; local motion=lp.motion; local link=lp.network and lp.network.link
        if stage=='hosting' and motion and motion.generation and motion.actor and motion.readyEpoch==motion.epoch then
            if lp.menuOpen then click('close') end
            epoch=data.coop.sceneEpoch; guestHealth=data.players.companion.health
            c.runtime.expeditionGraceTimer=0; stage='chase'
        elseif stage=='chase' then
            local system=lp.context.roaming(); local transient=system.transient[data.activeExpeditionArea][id]
            if transient.state=='windup' then c.runtime.expeditionGraceTimer=999; capture='host-enemy-windup.png'; stage='windup' end
        elseif stage=='windup' and not link then
            check(data.scene=='expedition' and data.coop.sceneEpoch==epoch and not c.runtime.battle,'cue changed host scene')
            check(data.health==health and data.players.companion.health==guestHealth,'presentation changed health')
            local saved=assert(Save.read(99)); check(saved.scene=='expedition' and saved.coop.sceneEpoch==epoch,'cue changed saved story')
            finish()
        end
    else
        if lp.error then error('Local Play failed '..lp.error) end
        local view=lp.clientView; local replica=lp.replica and lp.replica.data
        if stage=='joining' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); epoch=replica.coop.sceneEpoch; stage='chase'
        elseif stage=='chase' then
            local live=lp.roamingPresentation and lp.roamingPresentation:get(id)
            if live then
                firstX,firstY=firstX or live.x,firstY or live.y
                if live.state=='chase' and live.animationDistance>0 then chased=true end
                local dead=lp.roamingPresentation:get(deadId)
                check(not dead or not dead.allowDeath,'baseline enemy death replayed')
                if live.state=='windup' then
                    check(chased and (live.x-firstX)^2+(live.y-firstY)^2>1,'guest never received enemy gait/movement')
                    check(replica.coop.sceneEpoch==epoch and view.runtime.scene=='expedition' and not view.runtime.battle,'enemy cue progressed guest scene')
                    check(live.timer>0 and live.timer<=.46,'guest attack timer invalid')
                    capture='guest-enemy-windup.png'; stage='finish'
                end
            end
        elseif stage=='finish' and captured['guest-enemy-windup.png'] then
            check(renderedWindup,'guest did not draw the enemy sprite/windup circle')
            menu(); click('leave'); finish()
        end
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
