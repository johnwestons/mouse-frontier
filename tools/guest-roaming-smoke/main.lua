-- Real ENet/apps/input/save-error UI; shorten only private fixture enemy HP.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Areas=require('game.expedition_areas'); local Save=require('game.save'); local Items=require('game.item_instances')
local Players=require('game.coop_players'); local Field=require('game.coop_roaming'); local Viewport=require('game.viewport')
local Style=require('game.ui_layout')
local app,c,stage,started,finished,restoreWrite,capture,rejoinAt,requestId,hostWeapon,guestWeapon
local captured={}; local generation; local connections=0; local denied=0
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('field-test',x,y); app.touchreleased('field-test',x,y)
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
    print('LAN_SMOKE_OK role='..role..' application=true roaming=true ownWeapon=true hostStoryOnly=true saveRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function mob(data) return data.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a'] end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        local data=c.newSave(c.characters[1]); data.location=6; data.scene=Areas.SCENE; data.activeExpeditionArea=Areas.SURFACE_ID; data.passengers={}
        Areas.ensure(data); check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
        Items.write(data,nil,{kind='equipment',index=1},'frontier-short-sword'); hostWeapon=data.itemSlots.equipment[1].id
        local enemy=mob(data); enemy.hp=1
        for id,value in pairs(data.expeditions[Areas.SURFACE_ID].mobs) do if id~='surface-bandit-a' then value.hp=0; value.dead=true end end
        c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,Areas.SURFACE_ID,enemy.x,enemy.y)
        data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y; c.runtime.expeditionGraceTimer=999
        check(require('game.coop_entities').ensure(data),'fixture identity failed')
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local original=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=original(gen,request)
            print('LAN_FIELD_COMMAND name='..request.command..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason))
            if request.command=='battle.begin' or request.command=='roaming.attack' and request.args.weaponId==hostWeapon then
                check(not reply.ok,'guest foreign/story command accepted'); denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Field test friend'); click('next'); click('join'); stage='joining'
    end
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<100,'field fixture deadline '..tostring(stage))
    app.update(math.min(.05,dt)); app.focus(true)
    local lp=c.ui.localPlay
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        local data=c.runtime.saveData
        if stage=='hosting' and link and link.phase=='ready' and denied>=1 then
            if lp.menuOpen then click('close') end
            local guest=Players.forActor(data,'companion')
            if guest.equipment[1]~='frontier-short-sword' then Items.write(guest,nil,{kind='equipment',index=1},'frontier-short-sword') end
            guestWeapon=guest.itemSlots.equipment[1].id
            -- Place the private test enemy at the host-simulated guest position;
            -- input/pose ownership, hit rules, costs and rewards stay production.
            mob(data).x,mob(data).y=lp.motion.actor.x,lp.motion.actor.y
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and guest.itemSlots.equipment[1].durability==99 then return false,'injected field save failure' end
                return restoreWrite(path,bytes)
            end
            stage='swing'
        elseif stage=='swing' and lp.authority.pendingSave then
            check(mob(data).dead and mob(data).rewardResolved,'guest field hit/reward missing')
            check(data.itemSlots.equipment[1].durability==100 and data.players.companion.itemSlots.equipment[1].durability==99,'field wear charged wrong actor')
            check(data.scene=='expedition' and not c.runtime.battle,'guest progressed scene')
            capture='host-field-save-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-field-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave,'field retry failed'); stage='rejoin'
        elseif stage=='rejoin' and connections==2 and link and link.phase=='ready' and denied==2
            and data.players.companion.itemSlots.equipment[1].durability==98 then
            if lp.menuOpen then click('close') end
            app.draw()
            if touch then
                local controls=c.getMobileControls(); local point=controls.primary
                press(Style.transformRectFor('mobileControls',controls:uiBounds(),{x=point.x,y=point.y,w=0,h=0}))
            else press(c.ui.stopAttack) end
            check(data.itemSlots.equipment[1].durability==99 and data.roamingCombat.serial==3,'host field attack control failed')
            capture='host-field-two-actors.png'; stage='done'
        elseif stage=='done' and not link then
            local saved=assert(Save.read(99)); check(mob(saved).rewardResolved and saved.roamingCombat.serial==3,'field state not durable')
            check(saved.players.companion.itemSlots.equipment[1].id==guestWeapon and saved.itemSlots.equipment[1].id==hostWeapon,'weapon identity lost')
            check(saved.players.companion.itemSlots.equipment[1].durability==98 and saved.itemSlots.equipment[1].durability==99,'reconnect repeated wear')
            finish()
        end
    else
        if lp.error then error('Local Play failed '..lp.error) end
        local view=lp.clientView; local d=lp.replica and lp.replica.data
        if stage=='joining' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); requestId=assert(lp.network:submitCommand('battle.begin',{encounterId=mob(d).entityId},d.coop.sceneEpoch,{})); stage='denied'
        elseif stage=='denied' then
            local r=lp.network.lastCommandResult
            if r and r.requestId==requestId then check(not r.ok and r.reason=='host_only','guest started battle'); stage='armed' end
        elseif stage=='armed' and view and d.players.companion.equipment[1]=='frontier-short-sword' and view:inputAllowed() then
            app.draw(); if touch then press(view.ui.guestFieldAttack) else app.keypressed('space'); app.keyreleased('space') end
            check(view.field.pending,'guest field control failed'); stage='hit'
        elseif stage=='hit' and view and not view.field.pending and mob(d).dead then
            check(d.players.companion.itemSlots.equipment[1].durability==99 and d.players.host.itemSlots.equipment[1].durability==100,'guest costs differ')
            check(mob(d).rewardReceipt.playerXP.companion and d.scene=='expedition','field reward/scene differs')
            capture='guest-field-hit.png'; stage='leave'
        elseif stage=='hit' and view and not view.field.pending and view.field.lastOutcome and not view.field.lastOutcome.ok then
            error('field attack rejected '..tostring(view.field.lastOutcome.reason))
        elseif stage=='leave' and captured['guest-field-hit.png'] then menu(); click('leave'); rejoinAt=now; stage='rejoin'
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' and view and lp.motionFrame and lp.motionFrame.ready then
            click('close'); check(mob(d).dead and d.players.companion.itemSlots.equipment[1].durability==99,'field reconnect lost state')
            local expected={}; for _,scope in ipairs(Field.scopes(d,'companion')) do expected[scope]=d.coop.revisions[scope] or 0 end
            requestId=assert(lp.network:submitCommand('roaming.attack',{areaId=Areas.SURFACE_ID,weaponId=d.players.host.itemSlots.equipment[1].id},d.coop.sceneEpoch,expected)); stage='foreign'
        elseif stage=='foreign' then
            local r=lp.network.lastCommandResult
            if r and r.requestId==requestId then check(not r.ok and r.reason=='ownership','guest used host weapon'); stage='aim' end
        elseif stage=='aim' and view and view:inputAllowed() then
            view.camera:setZoom(1.3); app.draw()
            if touch then press(view.ui.guestFieldAttack)
            else
                local fx,fy=view:focusPoint(); local ox,oy=Areas.cameraOffset(view.runtime.saveData,view.runtime.player,960,720)
                local x,y=view.runtime.player.x+45-ox,view.runtime.player.y-oy
                press({x=(x-fx)*view.camera.zoom+fx+view.camera.panX,y=(y-fy)*view.camera.zoom+fy+view.camera.panY,w=0,h=0})
            end
            check(view.field.pending,'guest zoomed field control failed'); stage='aimed'
        elseif stage=='aimed' and view and not view.field.pending then
            check(view.field.lastOutcome and view.field.lastOutcome.ok and d.players.companion.itemSlots.equipment[1].durability==98,'guest aimed swing failed')
            stage='done'
        elseif stage=='done' and d and d.roamingCombat and d.roamingCombat.serial==3 then
            check(d.players.host.itemSlots.equipment[1].durability==99 and not view.runtime.battle,'host attack projection differs')
            capture='guest-field-two-actors.png'; stage='finish'
        elseif stage=='finish' and captured['guest-field-two-actors.png'] then menu(); click('leave'); finish() end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' stage='..tostring(stage)..' '..tostring(reason)); finished=true
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
