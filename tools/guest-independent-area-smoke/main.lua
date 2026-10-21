-- Real host/client flood checks, first together and then in separate scenes.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Areas=require('game.expedition_areas'); local Players=require('game.coop_players')
local Viewport=require('game.viewport')
local app,c,stage,started,finished,epoch,oldMotion,hostX,hostY,capture
local id=Areas.BADLANDS_BASIN_ID; local environment=Areas.definition(id).environment
local point=environment.floodZone.points[1]
local function check(value,message) assert(value,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function key(name) app.keypressed(name); app.keyreleased(name) end
local function click(name,text)
    app.draw(); local r=assert(c.ui.localPlayControls[name],name)
    local ox,oy,sx,sy=Viewport.transform(960,720); local x,y=ox+(r.x+r.w/2)*sx,oy+(r.y+r.h/2)*sy
    if touch then app.touchpressed('area',x,y); app.touchreleased('area',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
    if text then app.textinput(text); key('return') end
end
local function finish()
    finished=true; file(role..'.done','true')
    print('LAN_SMOKE_OK role='..role..' independentAreas=true togetherFlood=true clientOnlyFlood=true hostStayedOnTrain=true guestEnemyFrames=true portableReturn=true')
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'; lp.port=port; Save.remove(1)
    if role=='host' then
        c.runtime.selectedSlot=1
        local data=c.newSave(c.characters[1]); data.location=5; data.scene='expedition'; data.activeExpeditionArea=id
        data.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        Areas.ensure(data); check(c.enterGame(data),'seed failed'); data=c.runtime.saveData
        for _,mob in pairs(data.expeditions[id].mobs) do mob.hp=0; mob.dead=true end
        data.playerX,data.playerY=point.x,point.y; c.runtime.player.x,c.runtime.player.y=point.x,point.y
        check(Areas.isWalkable(data,id,point.x,point.y),'dry flood point not walkable')
        data.expeditions[id].environmentClock=0; data.expeditions[id].environmentPhase='dry'
        check(Save.write(1,data),'seed save failed'); c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.state='slots'
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,why=place(data); if not ok then return ok,why end
            data.players.companion.playerX,data.players.companion.playerY=point.x+28,point.y; return true
        end
        key('f8'); click('saveSlot'); click('slot_1'); click('host')
        check(lp.network,'host launch failed'); stage='together'; print('LAN_SMOKE_LISTENING')
    else
        check(Save.write(1,c.newSave(c.characters[2] or c.characters[1])),'guest seed failed')
        c.runtime.state='slots'; app.update(0); key('f8'); click('address','127.0.0.1:'..port)
        click('saveSlot'); click('slot_1'); click('join'); stage='first'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local motion=lp.motion
    if lp:pending() then check(lp:approve(),'approval failed') end
    if lp.menuOpen then click('close') end
    local state=data.expeditions[id]
    if stage=='together' and file('guest.ready') and motion and motion.readyEpoch==data.coop.sceneEpoch then
        epoch=data.coop.sceneEpoch; oldMotion=motion.motionId
        state.environmentClock=environment.floodAt-.01; state.environmentPhase='warning'; stage='first-flood'
    elseif stage=='first-flood' and state.environmentPhase=='flooded' then
        check(motion.motionId==oldMotion+1,'first correction generation')
        check(not Areas.isInFlood(data,id,c.runtime.player.x,c.runtime.player.y),'host remained flooded')
        check(not Areas.isInFlood(data,id,motion.actor.x,motion.actor.y),'guest remained flooded')
        check((c.runtime.player.x-motion.actor.x)^2+(c.runtime.player.y-motion.actor.y)^2>=24^2,'overlapping bank landings')
        file('first.safe','true'); stage='separate'
    elseif stage=='separate' and file('guest.firstSafe') then
        local reply=lp.context.commands.submit('scene.returnTrain',{}); check(reply.ok,reply.reason)
        check(c.runtime.scene=='train' and Players.forActor(data,'companion').scene=='expedition','host return moved guest')
        hostX,hostY=c.runtime.player.x,c.runtime.player.y
        state.environmentClock=0; state.environmentPhase='dry'
        check(lp.motion:relocate(point.x,point.y),'remote relocation failed'); stage='second-ready'
    elseif stage=='second-ready' and motion.readyEpoch==data.coop.sceneEpoch then
        oldMotion=motion.motionId; file('second.motion',oldMotion)
        state.environmentClock=environment.floodAt-.01; state.environmentPhase='warning'; stage='second-flood'
    elseif stage=='second-flood' and state.environmentPhase=='flooded' then
        check(motion.motionId==oldMotion+1,'remote flood did not correct movement')
        check(c.runtime.scene=='train' and c.runtime.player.x==hostX and c.runtime.player.y==hostY,'remote flood moved host')
        check(not Areas.isInFlood(data,id,motion.actor.x,motion.actor.y),'remote flood did not eject guest')
        check(data.coop.sceneEpoch==epoch,'local exploration advanced shared scene')
        file('second.safe','true'); capture='host-away'; stage='finish'
    elseif stage=='finish' and file('guest.done') then finish() end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView
    if stage=='returning' then
        if lp.phase=='idle' then
            local data=assert(Save.read(1)); check(not require('game.coop_traveler').isAway(data),'return incomplete')
            check(data.location==1,'host world overwrote guest save'); finish()
        end
        return
    end
    if lp.menuOpen and lp.phase=='connected' then click('close') end
    if not view or not view:inputAllowed() then return end
    local own=view.runtime.saveData; local p=view.runtime.player
    if stage=='first' then file('guest.ready','true'); stage='first-safe'
    elseif stage=='first-safe' and file('first.safe') and not Areas.isInFlood(own,id,p.x,p.y,true) then
        file('guest.firstSafe','true'); stage='second-safe'
    elseif stage=='second-safe' and file('second.safe') and lp.motionFrame.motionId>tonumber(file('second.motion')) then
        check(lp.replica.data.scene=='train' and own.scene=='expedition' and own.activeExpeditionArea==id,'independent scene lost')
        check(not Areas.isInFlood(own,id,p.x,p.y,true),'predicted guest stayed flooded')
        local mobId=Areas.definition(id).mobs[1].id
        if not lp.roamingPresentation:get(mobId) then return end
        capture='guest-alone'; stage='leave'
    elseif stage=='leave' and not capture then lp:open(); click('leave'); stage='returning' end
end
local function guard(fn)
    local ok,why=xpcall(fn,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' '..tostring(why)); finished=true; love.event.quit(1) end
end
function love.load() guard(load) end
function love.update(dt)
    if finished then return end
    guard(function()
        app.update(math.min(.05,dt)); check(not c.ui.localPlay.error,tostring(c.ui.localPlay.error))
        if role=='host' then hostUpdate() else guestUpdate() end
        check(love.timer.getTime()-started<90,'area timeout '..tostring(stage))
    end)
end
function love.draw()
    if not app or finished then return end
    guard(function()
        app.draw(); if capture then local name=capture; capture=nil
            love.graphics.captureScreenshot(function(pixels) file(name..'.png',pixels:encode('png'):getString()) end)
        end
    end)
end
function love.focus(value) if app then app.focus(value) end end
function love.quit() if app then return app.quit() end end
