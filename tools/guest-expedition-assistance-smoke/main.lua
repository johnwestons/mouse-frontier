-- Two full source apps: assistance controls, disk failure, owned transfer and reconnect.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Areas=require('game.expedition_areas'); local Save=require('game.save'); local Items=require('game.item_instances')
local Viewport=require('game.viewport'); local Style=require('game.ui_layout'); local Inventory=require('game.inventory')
local app,c,stage,started,finished,restoreWrite,capture,epoch,gearId,rejoinAt,requestId,nextDiagnostic,archCompletedAt
local captured={}; local generation; local connections=0; local denied=0
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('assist-test',x,y); app.touchreleased('assist-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function interact(view)
    app.draw()
    if touch then
        local controls=view and view.mobile or c.getMobileControls(); local point=view and controls.primary or controls.secondary
        local r={x=point.x,y=point.y,w=0,h=0}
        press(view and r or Style.transformRectFor('mobileControls',controls:uiBounds(),r))
    else app.keypressed('e'); app.keyreleased('e') end
end
local function bag(rect) return Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect) end
local function area(data) return data.expeditions[Areas.BADLANDS_BASIN_ID] end
local function owns(data,id)
    for _,item in pairs(data.players.companion.itemSlots.inventory or {}) do if item.id==id then return true end end
    return false
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true expeditionAssistance=true survey=true cache=true itemIdentity=true saveRetry=true reconnect=true hostStoryOnly=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=5; data.scene='expedition'; data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; data.passengers={}
        Areas.ensure(data); check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
        for _,mob in pairs(area(data).mobs) do mob.dead=true; mob.hp=0 end
        c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,data.activeExpeditionArea,750,110)
        data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y; c.runtime.expeditionGraceTimer=999
        Items.write(data,area(data).chests['western-stash'],{kind='chest',index=1},'frontier-short-sword')
        gearId=area(data).chests['western-stash'].storageInstances[1].id
        area(data).chests['fossil-cache'].storage={}; area(data).chests['fossil-cache'].storageInstances={}
        lp.context.placeCompanion=function(value)
            local guest=value.players.companion; guest.playerX,guest.playerY=Areas.clamp(value,value.activeExpeditionArea,360,180); return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local command=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=command(gen,request)
            print('LAN_ASSIST_COMMAND name='..request.command..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason))
            if request.command=='scene.expedition' or request.command=='scene.returnTrain' or request.command=='battle.begin' then
                check(not reply.ok and reply.reason=='host_only','guest progressed story'); denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Expedition helper'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'assistance fixture deadline '..tostring(stage))
    app.update(math.min(.025,dt)); app.focus(true)
    local lp=c.ui.localPlay
    if now>=(nextDiagnostic or started+10) then
        nextDiagnostic=now+10
        local v=lp.clientView
        print('LAN_ASSIST_STATE role='..role..' stage='..tostring(stage)..' pending='..tostring(v and v.expedition.pending~=nil)..' panel='..tostring(v and v.runtime.chestOpen)..' notice='..tostring(v and v.expedition.notice))
    end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local data=c.runtime.saveData; local motion=lp.motion; local link=lp.network and lp.network.link
        if link and link.phase=='ready' and link.generation~=generation then generation=link.generation; connections=connections+1 end
        if stage=='hosting' and motion and motion.generation and motion.readyEpoch==motion.epoch then
            if lp.menuOpen then click('close') end
            epoch=data.coop.sceneEpoch; restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and area(data).chests['western-stash'].opened then return false,'injected cache save failure' end
                return restoreWrite(path,bytes)
            end
            stage='cache'
        elseif stage=='cache' and lp.authority.pendingSave then capture='host-cache-save-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-cache-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'cache retry failed'); stage='transfer'
        elseif stage=='transfer' and owns(data,gearId) then
            interact(); check(area(data).markers['north-cairn'],'host survey control failed')
            local x,y=Areas.clamp(data,data.activeExpeditionArea,900,500)
            check(motion:relocate(x,y),'fixture relocation failed'); capture='host-survey.png'; stage='wash'
        elseif stage=='wash' and area(data).markers['wash-cairn'] then
            local x,y=Areas.clamp(data,data.activeExpeditionArea,1580,320)
            check(motion:relocate(x,y),'fixture relocation failed'); stage='arch'
        elseif stage=='arch' and area(data).markers['arch-cairn'] then
            check(area(data).completed and area(data).gates.routeSurveyed,'survey completion missing')
            archCompletedAt=now; stage='archDone'
        elseif stage=='archDone' and now-archCompletedAt>.8 then
            local x,y=Areas.clamp(data,data.activeExpeditionArea,450,720)
            check(motion:relocate(x,y),'fixture relocation failed'); stage='empty'
        elseif stage=='empty' and area(data).chests['fossil-cache'].opened then stage='rejoin'
        elseif stage=='rejoin' and connections==2 and denied==3 and not link then
            local saved=assert(Save.read(99)); check(saved.scene=='expedition' and saved.coop.sceneEpoch==epoch,'assistance progressed scene')
            check(area(saved).completed and area(saved).gates.routeSurveyed and area(saved).chests['fossil-cache'].opened,'saved assistance missing')
            check(owns(saved,gearId),'saved gear identity lost')
            c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,data.activeExpeditionArea,450,720)
            if lp.menuOpen then click('close') end
            stage='hostCacheStart'
        elseif stage=='hostCacheStart' then
            check(c.ui.interaction and c.ui.interaction.chestId=='fossil-cache','host fixture interaction has not updated')
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) then return false,'injected host cache save failure' end
                return restoreWrite(path,bytes)
            end
            interact(); check(lp.authority.pendingSave and not c.runtime.inventoryOpen,'host cache save/panel state differs pending='..tostring(lp.authority.pendingSave~=nil)..' panel='..tostring(c.runtime.inventoryOpen))
            capture='host-empty-cache-save-retry.png'; stage='hostCacheRetry'
        elseif stage=='hostCacheRetry' and captured['host-empty-cache-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave and c.runtime.inventoryOpen and c.runtime.chestOpen,'host cache did not open after durable retry')
            check(c.runtime.activeChest.entityId==area(data).chests['fossil-cache'].entityId and not next(c.runtime.activeChest.storage),'host cache differs')
            capture='host-empty-cache-open.png'; stage='hostDone'
        elseif stage=='hostDone' and captured['host-empty-cache-open.png'] then finish()
        end
    else
        if lp.error then error('Local Play failed '..lp.error) end
        local view=lp.clientView; local data=lp.replica and lp.replica.data
        if stage=='joining' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); epoch=data.coop.sceneEpoch; stage='cache'
        elseif stage=='cache' and view and view:inputAllowed() then
            interact(view); check(view.expedition.pending and not view.runtime.inventoryOpen,'cache opened before durable receipt'); stage='opened'
        elseif stage=='opened' and view and not view.expedition.pending and view.runtime.chestOpen then
            check(view.expedition.lastOutcome and view.expedition.lastOutcome.durable,'cache receipt not durable')
            gearId=view.runtime.activeChest.storageInstances[1].id; capture='guest-cache-open.png'; stage='transfer'
        elseif stage=='transfer' and captured['guest-cache-open.png'] then
            app.draw(); press(bag(Inventory.chestSlotRect(1))); app.draw(); press(bag(view.inventory.transferButton))
            check(view.inventory.pending,'cache transfer control failed'); stage='transferred'
        elseif stage=='transferred' and not view.inventory.pending then
            check(view.inventory.notice=='Items updated.' and owns(data,gearId),'cache transfer lost identity')
            app.keypressed('i'); app.keyreleased('i'); stage='wash'
        elseif stage=='wash' and view and view:inputAllowed() and view.revision==lp.replica.revision and area(view.runtime.saveData).markers['north-cairn'] and view.expedition:nearest() and view.expedition:nearest().markerId=='wash-cairn' then
            if not view.expedition.pending and not area(data).markers['wash-cairn'] then interact(view) end
            stage='washed'
        elseif stage=='washed' and not view.expedition.pending then
            check(view.expedition.lastOutcome and view.expedition.lastOutcome.ok,'wash survey rejected '..tostring(view.expedition.lastOutcome and view.expedition.lastOutcome.reason))
            check(area(data).markers['wash-cairn'],'wash marker not projected'); stage='arch'
        elseif stage=='arch' and view and view:inputAllowed() and view.revision==lp.replica.revision and area(view.runtime.saveData).markers['wash-cairn'] and view.expedition:nearest() and view.expedition:nearest().markerId=='arch-cairn' then
            interact(view); stage='surveyed'
        elseif stage=='surveyed' and not view.expedition.pending and area(data).completed and view:inputAllowed() then
            check(view.expedition.lastOutcome.durable and view.expedition.lastOutcome.details.complete,'survey receipt incomplete')
            capture='guest-survey-complete.png'; stage='empty'
        elseif stage=='empty' and captured['guest-survey-complete.png'] and view and view:inputAllowed() and view.expedition:nearest() and view.expedition:nearest().chestId=='fossil-cache' then
            interact(view); stage='emptyOpened'
        elseif stage=='emptyOpened' and not view.expedition.pending and view.runtime.chestOpen then
            check(not next(view.runtime.activeChest.storage) and area(data).chests['fossil-cache'].opened,'empty cache did not open/save')
            capture='guest-empty-cache.png'; stage='leave'
        elseif stage=='leave' and captured['guest-empty-cache.png'] then
            app.keypressed('i'); app.keyreleased('i'); menu(); click('leave'); rejoinAt=now+.3; stage='rejoin'
        elseif stage=='rejoin' and now>=rejoinAt then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); check(area(data).completed and area(data).chests['fossil-cache'].opened and owns(data,gearId),'rejoin lost assistance')
            denied=0; stage='denied'
        elseif stage=='denied' then
            local r=lp.network.lastCommandResult
            if requestId and r and r.requestId==requestId then check(not r.ok and r.reason=='host_only','guest story command accepted'); denied=denied+1; requestId=nil end
            if not requestId and denied<3 then requestId=assert(lp.network:submitCommand(({'scene.expedition','scene.returnTrain','battle.begin'})[denied+1],{},data.coop.sceneEpoch,{}))
            elseif denied==3 then menu(); click('leave'); finish() end
        end
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
