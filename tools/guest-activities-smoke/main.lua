-- Production maintenance/repair controls in two isolated apps over real ENet.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local Save=require('game.save'); local Viewport=require('game.viewport'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Catalog=require('game.catalog'); local Loot=require('game.loot_progression')
local app,c,started,finished,stage,capture,restoreWrite,saveRetried,request,command,verify,nextStage,lastAction
local captured={}; local connections=0; local generation,hostItem,hostX,guestItem,epoch,location,rejoinAt,repairCost,restored,hubAt
local function check(v,m) assert(v,m) end
local function file(name,value)
    local f=io.open(root..'/'..name,value and 'wb' or 'rb'); if not f then return end
    local result=value and f:write(value) or f:read('*a'); f:close(); return result
end
local function press(rect)
    check(rect,'missing activity control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('activity-test',x,y); app.touchreleased('activity-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function control(view,name)
    app.draw()
    if touch then press(view.ui['activity_'..name])
    else view.ui.keyboardFocusVisible=true; view.ui.keyboardFocusScreen='guest-activity'; view.ui.keyboardFocusId=name; app.gamepadpressed({},'a') end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true activities=true reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(9112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'; lp.port=port
    Save.remove(1)
    if role=='host' then
        c.runtime.selectedSlot=1
        local seed=c.newSave(c.characters[1]); seed.scene='train'; seed.location=2; seed.stopped=true
        seed.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        seed.events['2']={id='resolved'}; seed.encounters['2']={hasMob=false,resolved=true}
        check(c.enterGame(seed),'fixture campaign failed')
        local data=c.runtime.saveData; data.stopped=true; data.resources.oil=20; data.scrap=200
        data.maintenance={condition=40,lastServicedStop=0,totalServices=0,totalWear=0}; c.runtime.nextStopDestination=data.location+5
        Items.get(data,nil,{kind='equipment',index=1}).durability=67
        hostX=c.runtime.player.x; hostItem=data.players.host.itemSlots.equipment[1].id
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local own=campaign.players.companion
            own.playerX,own.playerY=require('game.train').clampCharacterToFloor(c.car,c.contentRegistry.scenery.trainCarImages['living-car'],650,520,30)
            return true
        end
        check(Save.write(1,data),'host seed failed'); c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.state='slots'
        app.update(0); menu(); click('saveSlot'); click('slot_1'); click('host')
        hostX=c.runtime.player.x
        check(lp.network,'hosting failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        local seed=c.newSave(c.characters[2] or c.characters[1])
        Items.write(seed,nil,{kind='equipment',index=1},'frontier-short-sword')
        Items.get(seed,nil,{kind='equipment',index=1}).durability=20
        Items.write(seed,nil,{kind='inventory',index=2},Catalog.weaponRepairParts['frontier-short-sword'])
        check(Save.write(1,seed),'guest seed failed')
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; app.update(0); menu(); click('address','127.0.0.1:'..port)
        click('name','Activity test friend'); click('saveSlot'); click('slot_1'); click('join'); stage='joining'
    end
end
local function waiting(view,name,after,fn)
    check(view.activities.pending,'missing activity command: '..name)
    request=view.activities.pending.id; command=name; nextStage=after; verify=fn
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<80,'activity fixture deadline exceeded: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    local v=lp.clientView; local p=v and v.activities
    local diagnostic=table.concat({tostring(stage),tostring(lp.phase),tostring(p and p.notice),
        tostring(p and p.lease),tostring(v and v.runtime.scene),tostring(v and v.runtime.guestActivityOpen)},':')
    if diagnostic~=c.fixtureDiagnostic then print('LAN_ACTIVITY_STATE '..role..' '..diagnostic); c.fixtureDiagnostic=diagnostic end
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            connections=connections+1; generation=link.generation
            if connections==1 then
                repairCost=Loot.repairStatus(Players.forActor(c.runtime.saveData,'companion'),Catalog,c.runtime.saveData.players.companion.itemSlots.equipment[1].id).cost
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(1) and c.runtime.saveData.maintenance.totalServices>=1 then return false,'injected service checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave then capture='host-service-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-service-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'service save retry failed'); saveRetried=true; stage='hosting'
        end
        local resources=lp.authority and lp.authority.activityState.resources
        if resources and resources['train:maintenance'] and not c.fixtureMaintenanceContention then
            check(lp.authority:submitLocal('maintenance.acquire',{}).reason=='activity_busy','host bypassed occupied service station'); c.fixtureMaintenanceContention=true
        end
        if resources and resources['train:weapon-repair'] and not c.fixtureRepairContention then
            check(lp.authority:submitLocal('weaponRepair.acquire',{itemId=hostItem}).reason=='activity_busy','host bypassed occupied repair bench'); c.fixtureRepairContention=true
            if lp.menuOpen then click('close') end
            local lease=resources['train:weapon-repair'].id
            local left=c.ui.transitionParty('scene.leaveTrain')
            check(left.ok,'host could not leave independently: '..tostring(left.reason))
            check(lp.authority.activityState.resources['train:weapon-repair'].id==lease,'host exit cancelled guest repair')
            check(Players.forActor(c.runtime.saveData,'companion').scene=='train','host exit moved guest')
            hostX=c.runtime.player.x; file('host.outside','true')
        end
        if connections==1 and not link then
            local saved=assert(Save.read(1)); local gear=saved.players.companion.itemSlots.equipment[1]
            check(saveRetried and saved.resources.oil==15 and saved.maintenance.condition==80 and saved.maintenance.totalServices==1,'service not durable once')
            check(saved.scrap==200-repairCost and gear.durability>=75 and not saved.players.companion.inventory[2],'repair costs/part not durable once')
            check(saved.players.host.itemSlots.equipment[1].id==hostItem and saved.players.host.itemSlots.equipment[1].durability==67 and c.runtime.player.x==hostX,'host equipment/position changed')
            check(c.fixtureMaintenanceContention and c.fixtureRepairContention,'host contention was not checked')
        elseif connections==2 and not link then finish() end
    else
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            local d=lp.replica.data; epoch=d.coop.sceneEpoch; location=d.location; guestItem=d.players.companion.itemSlots.equipment[1].id
            repairCost=Loot.repairStatus(Players.forActor(d,'companion'),Catalog,guestItem).cost
            click('close'); stage='world-ready'; capture='guest-activity-world.png'
        elseif stage=='rejoin' and now-rejoinAt>1 then check(lp:join(),'credential reconnect failed'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local d=lp.replica.data; local gear=d.players.companion.itemSlots.equipment[1]
            check(gear.id==guestItem and gear.durability==restored and d.resources.oil==15 and d.scrap==200-repairCost,'rejoin lost service/repair')
            check(d.coop.sceneEpoch==epoch and d.scene=='stop' and Players.forActor(d,'companion').scene=='train' and d.location==location,'activities changed independent scenes or progressed story')
            click('leave'); stage='returning'
        elseif stage=='returning' and not lp.network then
            local saved=assert(Save.read(1)); local gear=saved.itemSlots.equipment[1]
            check(gear.name=='frontier-short-sword' and gear.durability==restored and not saved.inventory[2],'repaired weapon or consumed part lost on local return')
            print('LAN_ACTIVITIES_OK role=guest maintenance=true repair=true independentScenes=true saved=true hostOnlyStory=true portableReturn=true'); finish()
        elseif lp.clientView and stage~='joining' then
            local view=lp.clientView; local panel=view.activities
            if request then
                local r=lp.network.lastCommandResult
                if r and r.requestId==request and not panel.pending then
                    check(r.command==command and r.ok,'activity action failed: '..tostring(r.reason))
                    if command:match('%.complete$') then check(r.durable and r.details.success,'activity did not complete durably: '..tostring(r.details.reason)) end
                    if verify then verify(view,r) end; check(view.runtime.saveData.coop.sceneEpoch==epoch,'activity advanced story')
                    request=nil; stage=nextStage; lastAction=now
                end
            elseif capture or lastAction and now-lastAction<.65 then return
            elseif stage=='world-ready' and captured['guest-activity-world.png'] and view:inputAllowed() then
                app.draw(); if touch then press(view.ui.guestMaintenance) else app.keypressed('m') end
                check(view.runtime.guestActivityOpen,'maintenance did not open'); hubAt=1
                waiting(view,'maintenance.acquire','hubs',function() capture='guest-maintenance-open.png' end)
            elseif stage=='hubs' then
                control(view,'hub'..({1,1,2,3,3})[hubAt]); hubAt=hubAt+1
                waiting(view,'maintenance.step',hubAt>5 and 'service' or 'hubs',function(v,r) check(r.details.success,'oil point failed') end)
            elseif stage=='service' then
                control(view,'done'); waiting(view,'maintenance.complete','repair-open',function(v,r)
                    check(v.runtime.saveData.resources.oil==15 and r.details.condition==80,'service outcome incorrect'); capture='guest-service-completed.png'
                end)
            elseif stage=='repair-open' then
                control(view,'close'); app.draw(); if touch then press(view.ui.guestRepair) else app.gamepadpressed({},'dpright') end
                check(view.runtime.guestActivityOpen and panel.kind=='weaponRepair','repair did not open'); capture='guest-repair-panel.png'; stage='repair-start'
            elseif stage=='repair-start' then
                local status=Loot.repairStatus(view.runtime.saveData,Catalog,panel.selected)
                check(status.name,'repair selection missing: '..tostring(panel.selected)..' / '..tostring(Items.weapons(view.runtime.saveData,Catalog)[1].id))
                control(view,'repair'); waiting(view,'weaponRepair.acquire','repair-timing',function(v) check(v.activities.lease,'repair lease missing'); capture='guest-repair-timing.png' end)
            elseif stage=='repair-timing' and file('host.outside') then
                local phase=panel:phase()
                if phase and phase>.60 and phase<.66 and not panel.clockUncertain then
                    if touch then control(view,'repair') else app.keypressed('space') end
                    waiting(view,'weaponRepair.complete','done',function(v,r)
                        local gear=v.runtime.saveData.itemSlots.equipment[1]; restored=r.details.restored
                        check(gear.id==guestItem and gear.durability==restored and restored>=75,'repair changed identity or did not restore')
                        check(not v.runtime.saveData.inventory[2] and v.runtime.saveData.scrap==200-repairCost,'repair did not consume exact part/scrap'); capture='guest-repair-completed.png'
                    end)
                end
            elseif stage=='done' then control(view,'close'); check(lp:stop(),'temporary disconnect failed'); stage='rejoin'; rejoinAt=now
            end
        end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw(); if capture then love.graphics.captureScreenshot(capture); captured[capture]=true; capture=nil end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
