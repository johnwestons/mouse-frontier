-- Production keyboard/controller/touch sewing, real ENet and isolated saves.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Model=require('game.outfit_crafting'); local Definitions=require('game.outfit_catalog')
local recipe=Definitions.recipes[1]
local app,c,started,finished,stage,capture,restoreWrite,retried,request,action,nextStage,lastAction,projectOwner
local captured={}; local connections=0; local generation,hostGear,hostX,epoch,location,rejoinAt,guestUpgrade,hostUpgrade,pullRect
local function check(value,message) assert(value,message) end
local function xy(rect)
    check(rect,'missing sewing control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    return ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
end
local function press(rect)
    local x,y=xy(rect)
    if touch then app.touchpressed('sewing-test',x,y); app.touchreleased('sewing-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function button(panel,id)
    app.draw(); for _,b in ipairs(panel.bench.buttons) do if b.id==id then return {x=b.x,y=b.y,w=b.w,h=b.h} end end
    error('missing sewing button '..id)
end
local function bundles(actor)
    for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil) end
    local i=1; for _,m in ipairs(recipe.materials) do for _=1,m.count do Items.write(actor,nil,{kind='inventory',index=i},m.id); i=i+1 end end
end
local function waiting(panel,expected,after)
    check(panel.pending and panel.pending.action==expected,'missing sewing request '..expected)
    request=panel.pending.id; action=expected; nextStage=after
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true sewing=true reconnect=true input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.stopped=true; c.runtime.nextStopDestination=data.location+5
        hostX=c.runtime.player.x; Items.get(data,nil,{kind='equipment',index=1}).durability=67
        hostGear=data.players.host.itemSlots.equipment[1].id; bundles(Players.forActor(data,'host'))
        -- Start the first project through the ordinary host bench UI.
        check(c.ui.openOutfitWorkbench(),'host bench did not open'); app.draw(); app.keypressed('space'); app.keyreleased('space')
        check(Model.project(data) and Model.project(data).ownerPlayerId=='host','host project did not start')
        app.keypressed('escape'); app.keyreleased('escape')
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            bundles(Players.forActor(campaign,'companion')); return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Sewing test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<105,'sewing fixture deadline: '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; local now=love.timer.getTime()
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed: '..tostring(lp.error)); if not lp.menuOpen then menu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            connections=connections+1; generation=link.generation
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    if path==Save.path(99) and not Model.project(c.runtime.saveData) then return false,'injected sewing collection failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave and not captured['host-sewing-save-retry.png'] then capture='host-sewing-save-retry.png'; stage='save-retry' end
        if stage=='save-retry' and captured['host-sewing-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'sewing checkpoint retry failed'); retried=true; stage='hosting'
        end
        local resources=lp.authority and lp.authority.activityState.resources
        if resources and resources['train:sewing'] and not c.fixtureContention then
            check(lp.authority:submitLocal('outfit.craft',{action='acquire'}).reason=='activity_busy','host bypassed occupied sewing bench'); c.fixtureContention=true
        end
        if connections==1 and not link then
            local saved=assert(Save.read(99)); check(retried and c.fixtureContention,'checkpoint or contention not exercised')
            check(not saved.outfitCrafting.project and saved.inventory[1]==recipe.outputIds.masterwork and saved.players.companion.inventory[1]==recipe.outputIds.masterwork,'owner delivery was not durable')
            check(saved.players.host.itemSlots.equipment[1].id==hostGear and saved.players.host.itemSlots.equipment[1].durability==67 and c.runtime.player.x==hostX,'host gear or position changed')
            check(not next(lp.authority.activityState.resources),'disconnect retained sewing lease')
        elseif connections==2 and not link then finish() end
    else
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            epoch=lp.replica.data.coop.sceneEpoch; location=lp.replica.data.location
            click('close'); stage='world'; projectOwner='host'; capture='guest-sewing-world.png'
        elseif stage=='rejoin' and now-rejoinAt>.4 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local d=lp.replica.data
            check(d.players.host.itemSlots.inventory[1].id==hostUpgrade and d.players.companion.itemSlots.inventory[1].id==guestUpgrade,'rejoin changed upgrade identity')
            check(d.coop.sceneEpoch==epoch and d.location==location and d.scene=='train' and not d.outfitCrafting.project,'sewing progressed story or lost work')
            click('leave'); print('LAN_SEWING_OK role=guest hostOwner=true guestOwner=true timedPull=true saved=true hostOnlyStory=true'); finish()
        elseif lp.clientView and stage~='joining' then
            local view=lp.clientView; local panel=view.activities.sewing
            if request then
                local r=panel.lastOutcome
                if r and r.requestId==request and (not panel.pending or panel.pending.id~=request) then
                    check(r.ok and r.command=='outfit.craft' and r.details.success,'sewing request failed: '..tostring(r.reason)..' / '..tostring(r.details and r.details.reason))
                    if action=='point' or action=='pullRelease' then check(r.details.correct,'sewing mark or tension missed') end
                    if action=='start' or action=='collect' then check(r.durable,'material or output checkpoint not confirmed') end
                    if action=='start' then capture='guest-sewing-own-project.png' end
                    if action=='collect' then
                        check(r.details.ownerPlayerId==projectOwner and r.details.quality=='masterwork','wrong owner or workmanship')
                        if projectOwner=='host' then
                            hostUpgrade=lp.replica.data.players.host.itemSlots.inventory[1].id
                            check(view.runtime.saveData.inventory[1]=='thread-spool','helping consumed guest supplies')
                        else guestUpgrade=view.runtime.saveData.itemSlots.inventory[1].id end
                        capture='guest-sewing-collected-'..projectOwner..'.png'
                    end
                    check(view.runtime.saveData.coop.sceneEpoch==epoch,'sewing advanced scene'); request=nil; stage=nextStage; lastAction=now
                end
            elseif panel.pending or capture or lastAction and now-lastAction<.16 or stage~='world' and not panel:ready() then return
            elseif stage=='world' and captured['guest-sewing-world.png'] and view:inputAllowed() then
                app.draw(); check(view.ui.guestSewing.x+view.ui.guestSewing.w<550,'sewing overlaps nearby fuel/trade controls')
                if touch then press(view.ui.guestSewing) else app.keypressed('c'); app.keyreleased('c') end
                check(view.runtime.guestActivityOpen and view.activities.kind=='sewing','guest sewing did not open')
                waiting(panel,'acquire','work'); capture='guest-sewing-host-project.png'
            elseif stage=='work' then
                local project=Model.view.project(view.runtime.saveData); local current=Model.view.stage(view.runtime.saveData)
                if project and project.complete then
                    press(button(panel,'collect')); waiting(panel,'collect',projectOwner=='host' and 'own-start' or 'done')
                elseif current and current.kind=='point' then
                    if touch then press(button(panel,'work')) else app.draw(); app.gamepadpressed({},'x'); app.gamepadreleased({},'x') end
                    waiting(panel,'point','work')
                elseif current and current.kind=='tension' then
                    if touch then pullRect=button(panel,'work'); local x,y=xy(pullRect); app.touchpressed('sewing-pull',x,y)
                    else app.draw(); app.keypressed('space') end
                    waiting(panel,'pullStart','pulling'); capture='guest-sewing-tension.png'
                else error('missing current sewing step') end
            elseif stage=='pulling' then
                local current=Model.view.stage(view.runtime.saveData); local center=(current.targetRange.min+current.targetRange.max)/2
                if panel.bench.tension>=center then
                    if touch then local x,y=xy(pullRect); app.touchreleased('sewing-pull',x,y)
                    else app.keyreleased('space') end
                    waiting(panel,'pullRelease','work')
                end
            elseif stage=='own-start' then
                projectOwner='companion'; press(button(panel,'start')); waiting(panel,'start','work')
            elseif stage=='done' then press(button(panel,'close')); menu(); click('leave'); stage='rejoin'; rejoinAt=now end
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
