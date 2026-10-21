io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local caravan=os.getenv('MOUSE_FRONTIER_VISIT_CARAVAN')=='1'
local stop=caravan and 9 or 2
local visitingScene=caravan and 'caravan' or 'house'
local entranceCommand=caravan and 'scene.caravan' or 'scene.enterHouse'
local Caravan=require('game.crow_caravan_area')
local Save=require('game.save'); local Schema=require('game.save_schema'); local Players=require('game.coop_players')
local Presence=require('game.coop_presence'); local Settlements=require('game.settlements'); local Viewport=require('game.viewport')
local app,c,stage,started,finished,capture,movementKey,initialX,initialY,moveX,moveY
local timings={}; local transitionAt
local function timing(label,seconds)
    local values=timings[label] or {}; timings[label]=values
    values[#values+1]=seconds*1000
end
local function measure(label,fn,...)
    local before=love.timer.getTime(); local args={...}
    local ok,a,b,c=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_VISIT_OPERATION '..label..' '..tostring(a)); error(a) end
    timing(label,love.timer.getTime()-before); return a,b,c
end
local function check(value,reason) assert(value,reason) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function key(value) app.keypressed(value); app.keyreleased(value) end
local function press(rect)
    check(rect,'missing control at '..tostring(stage))
    local ox,oy,sx,sy=Viewport.transform(960,720); local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('visit',x,y); app.touchreleased('visit',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function click(id,text)
    app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); key('return') end
end
local function interact(view)
    if role=='guest' then transitionAt=love.timer.getTime() end
    app.draw()
    if touch and view then
        local p=view.mobile.primary; press({x=p.x-p.radius,y=p.y-p.radius,w=2*p.radius,h=2*p.radius})
    else key('e') end
end
local function leave()
    if role=='guest' then transitionAt=love.timer.getTime() end
    app.draw()
    for _,t in ipairs(c.ui.actionMenu.targets) do if t.id=='leave' then check(t.enabled,'exit disabled'); press(t.rect); return end end
    error('exit action absent')
end
local function finish()
    if finished then return end
    finished=true; file(role..'.done','true')
    local rows={'operation,count,mean_ms,p95_ms,max_ms'}
    for label,values in pairs(timings) do
        table.sort(values); local sum=0; for _,value in ipairs(values) do sum=sum+value end
        rows[#rows+1]=string.format('%s,%d,%.3f,%.3f,%.3f',label,#values,sum/#values,values[math.ceil(#values*.95)],values[#values])
    end
    file(role..'-timings.csv',table.concat(rows,'\n'))
    print('LAN_SMOKE_OK role='..role..' independentVisits=true differentHomes='..tostring(not caravan)..' independentCaravan='..tostring(caravan)..' ownedMovement=true reconnect=true sharedTravel=true touch='..tostring(touch))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); require('game.smoke_playthrough').install=function(value) c=value end
    local World=require('game.coop_scene_view'); local newWorld=World.new
    World.new=function(...)
        local scene=newWorld(...); local prepare=scene.prepare
        scene.prepare=function(...) return measure('scene.prepare',prepare,...) end
        return scene
    end
    local GameState=require('game.net.game_state'); local newReplica=GameState.replica
    GameState.replica=function(...)
        local replica=newReplica(...); local prepare=replica.prepare
        replica.prepare=function(...) return measure('replica.prepare',prepare,...) end
        return replica
    end
    local newImage=love.graphics.newImage
    love.graphics.newImage=function(...) return measure('graphics.newImage',newImage,...) end
    local Streamer=require('game.asset_streamer'); local stream=Streamer.update
    Streamer.update=function(...) return measure('assets.stream',stream,...) end
    local copy=Schema.copy
    Schema.copy=function(...) return measure('save.copy',copy,...) end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    print('LAN_VISIT_LOADED role='..role)
    local original=love.keyboard.isDown
    love.keyboard.isDown=function(k,...) if k==movementKey then return true end; return original(k,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'; lp.port=port
    if role=='host' then
        Save.remove(1); c.runtime.selectedSlot=1
        local draft=c.newSave(c.characters[1]); draft.location=stop; draft.scene='stop'; draft.stopped=true
        draft.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        draft.events[tostring(stop)]={id='resolved'}
        draft.encounters[tostring(stop)]={hasMob=false,resolved=true}
        if caravan then draft.crowCaravans={scheduledStops={9,24,40},scheduleVersion=1,scheduleMode='journey',camps={}} end
        for _,name in ipairs({'food','water','coal','oil'}) do draft.resources[name]=20 end
        check(c.enterGame(draft),'seed entry failed'); c.ensureStopLayout()
        local d=c.runtime.saveData; d.playerX,d.playerY=Settlements.doorPoint(stop,2)
        if caravan then assert(require('game.crow_caravans').ensureCamp(d,c.catalog,stop)) end
        c.runtime.player.x,c.runtime.player.y=d.playerX,d.playerY; initialX,initialY=d.playerX,d.playerY
        check(require('game.item_instances').ensure(d),'seed item identities failed')
        check(Save.write(1,d),'seed save failed'); c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.state='slots'
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,reason=place(data); if not ok then return ok,reason end
            local p=data.players.companion
            if caravan then local gate=Caravan.stopEntrance(stop); p.playerX,p.playerY=gate.x,gate.y
            else p.playerX,p.playerY=Settlements.doorPoint(stop,1) end
            return true
        end
        key('f8'); click('saveSlot'); click('slot_1'); click('host')
        initialX,initialY=c.runtime.player.x,c.runtime.player.y
        check(lp.network,'host saved entry failed: '..tostring(lp.error)); stage='wait-home'; print('LAN_SMOKE_LISTENING')
    else
        Save.remove(1); check(Save.write(1,c.newSave(c.characters[2] or c.characters[1])),'guest local save seed failed')
        debug.sethook(function()
            if love.timer.getTime()-started>35 then error('guest startup stalled: '..debug.traceback()) end
        end,'',1000000)
        c.runtime.state='slots'; app.update(0); key('f8'); print('LAN_VISIT_MENU')
        click('address','127.0.0.1:'..port); click('name','Local visitor'); click('saveSlot'); click('slot_1')
        print('LAN_VISIT_PROFILE'); click('join')
        debug.sethook(); print('LAN_VISIT_JOINED')
        check(lp.network,'join failed'); stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local d=c.runtime.saveData
    if lp:pending() then lp:approve() end
    if lp.menuOpen then click('close') end
    if stage=='wait-home' and file('guest.home') then
        check(d.scene=='stop' and c.runtime.player.x==initialX and c.runtime.player.y==initialY,'guest door moved host')
        check(Players.forActor(d,'companion').scene==visitingScene and Schema.validate(d),'guest visit not saved')
        if caravan then check(c.ui.transitionParty('scene.returnTrain').ok,'host boarding failed')
        else interact(); check(d.scene=='house' and d.activeHouseDoor==2,'host could not enter second home') end
        file('host.home','true'); stage='wait-rejoin'
    elseif stage=='wait-rejoin' and file('guest.restored') then
        if caravan then check(d.scene=='train' and Players.forActor(d,'companion').scene=='caravan','reconnect merged visits')
        else check(Players.forActor(d,'companion').activeHouseDoor==1 and d.activeHouseDoor==2,'reconnect merged homes') end
        check(Schema.validate(d),'independent homes invalid')
        if not caravan then check(c.ui.transitionParty('scene.returnTrain').ok,'host boarding failed') end
        check(Players.forActor(d,'companion').scene==visitingScene,'host boarding dragged guest')
        check(c.ui.transitionParty('travel.depart').ok,'host departure failed')
        check(Players.forActor(d,'companion').scene=='train' and not d.players.companion.presence,'departure did not reunite')
        file('host.departed','true'); stage='finish'
    elseif stage=='finish' and file('guest.done') then finish() end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local v=lp.clientView
    if lp.menuOpen and lp.phase=='connected' then click('close') end
    if not v or not v.ready then return end
    local d=v.runtime.saveData
    if v.visits.lastOutcome then check(v.visits.lastOutcome.ok,'visit rejected: '..tostring(v.visits.lastOutcome.reason)) end
    check(not c.runtime.saveData,'guest acquired writable campaign')
    if stage=='joining' and v:inputAllowed() then
        check(v.visits:nearest() and v.visits:nearest().command==entranceCommand,'guest entrance unavailable')
        interact(v); stage='home'
    elseif stage=='home' and v:inputAllowed() and v.runtime.scene==visitingScene then
        timing('transition.first_house',love.timer.getTime()-transitionAt)
        check((caravan or d.activeHouseDoor==1) and not v.ui.coopCompanion(),'remote actor visible in other scene')
        moveX,moveY=v.runtime.player.x,v.runtime.player.y; movementKey='d'; file('guest.home','true'); stage='move'
    elseif stage=='move' and file('host.home') and v.runtime.player.x>moveX+25 then
        movementKey=nil; check((caravan or d.activeHouseDoor==1) and not v.ui.coopCompanion(),'host door changed guest room')
        capture='independent-home'; leave(); stage='outside'
    elseif stage=='outside' and v:inputAllowed() and v.runtime.scene=='stop' then
        timing('transition.exit_house',love.timer.getTime()-transitionAt)
        check(v.visits:nearest() and v.visits:nearest().command==entranceCommand,'return door unavailable')
        interact(v); stage='reenter'
    elseif stage=='reenter' and v:inputAllowed() and v.runtime.scene==visitingScene then
        timing('transition.reenter_house',love.timer.getTime()-transitionAt)
        check(caravan or d.activeHouseDoor==1,'reentry changed room')
        check(lp:stop(),'guest disconnect failed'); check(lp:join(),'credential reconnect failed'); stage='rejoin'
    elseif stage=='rejoin' and v:inputAllowed() then
        check(v.runtime.scene==visitingScene and (caravan or d.activeHouseDoor==1),'reconnect lost local visit')
        check(not v.ui.coopCompanion(),'reconnect exposed host in other room')
        file('guest.restored','true'); stage='travel'
    elseif stage=='travel' and file('host.departed') and v.runtime.scene=='train' then
        check(not d.players.companion.presence and d.coop.journey,'shared travel missing'); finish()
    end
end
local function update(dt)
    if finished then return end
    measure('app.update.'..tostring(stage),app.update,math.min(dt,.05))
    local lp=c.ui.localPlay
    check(not lp.error,'local play error: '..tostring(lp.error))
    local v=lp.clientView; local reply=lp.network and lp.network.lastCommandResult
    local status=tostring(stage)..':'..tostring(lp.phase)..':'..tostring(v and v.ready)..':'..tostring(v and v.paused)
        ..':scene='..tostring(v and v.runtime.scene)..':pending='..tostring(v and v.visits.pending and v.visits.pending.id)
        ..':reply='..tostring(reply and reply.ok)..'/'..tostring(reply and reply.durable)..'/'..tostring(reply and reply.reason)
        ..':rev='..tostring(v and v.runtime.saveData and v.runtime.saveData.coop.revision)..'/'..tostring(reply and reply.revision)
    if status~=c.visitStatus then print('LAN_VISIT_STATE role='..role..' '..status); c.visitStatus=status end
    if caravan and role=='host' and not c.caravanDiagnostic and love.timer.getTime()-started>8 then
        c.caravanDiagnostic=true
        print('LAN_CARAVAN_HOST state='..tostring(c.runtime.state)..' battle='..tostring(c.runtime.battle)..' roaming='..tostring(c.runtime.saveData.roamingEncounter)..' transition='..tostring(c.runtime.travelTransition)..' allowed='..tostring(lp.context.movement.allowed())..' life='..tostring(require('game.coop_last_stand_lifecycle').key(c.runtime.saveData))..' ambush='..tostring(c.runtime.trainAmbush and c.runtime.trainAmbush.phase)..' car='..tostring(lp.context.commands.carBusy('companion'))..' aid='..tostring(lp.context.commands.activityBusy('companion','lastStandAid'))..' range='..tostring(lp.context.commands.activityBusy('companion','range')))
    end
    if role=='host' then hostUpdate() else guestUpdate() end
    check(love.timer.getTime()-started<150,'timeout at '..tostring(stage))
end
local function guard(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guard(load) end
function love.update(dt) guard(update,dt) end
function love.draw()
    if not app or finished then return end
    guard(function()
        measure('app.draw',app.draw)
        if capture then local name=role..'-'..capture..'.png'; capture=nil
            love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
            end)
        end
    end)
end
