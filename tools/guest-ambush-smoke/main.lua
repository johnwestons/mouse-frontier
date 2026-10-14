-- Two full source apps: private shooter controls, real ENet and isolated saves.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT')); local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Rules=require('game.train_ambush_rules'); local Scene=require('game.train_ambush_scene')
local State=require('game.coop_ambush_state'); local Viewport=require('game.viewport'); local Aim=require('game.mobile_weapon_aim')
local app,c,ambush,stage,started,finished,restoreWrite,capture,requestId,firstId,duplicateId,smgId,oldEpoch,pausedClock,retryAt
local lastReport=0; local denied=0; local connections=0; local pendingShotHP; local captures={}
local function check(value,message) assert(value,message) end
local function marker(name,value) local f=assert(io.open(root..'/'..name,'w')); f:write(tostring(value or true)); f:close() end
local function exists(name) local f=io.open(root..'/'..name,'r'); if f then f:close(); return true end end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function press(r)
    check(r,'missing control '..tostring(stage)); local x,y=coords(r.x+r.w/2,r.y+r.h/2)
    if touch then app.touchpressed('button',x,y); app.touchreleased('button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then app.keypressed('f8'); app.keyreleased('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function target(s)
    for y=170,455,4 do for x=170,800,4 do
        local t=Scene.target(s,960,720,x,y)
        if t and t.kind=='hull' and t.vehicle=='pickup' then
            local solid=true
            for _,o in ipairs({{-2,0},{2,0},{0,-2},{0,2}}) do local n=Scene.target(s,960,720,x+o[1],y+o[2])
                if not n or n.kind~='hull' or n.vehicle~='pickup' then solid=false end end
            if solid then return x,y end
        end
    end end
    error('no solid pickup pixel')
end
local function shoot(panel,state)
    local x,y=target(panel and State.view(state,'companion') or state)
    if touch and panel then
        x,y=Aim.gripForAim(panel.gun.weapon,panel.gun.ads and 'sights' or 'hip',x,y,960,720)
        local sx,sy=coords(x,y); app.touchpressed('aim-drag',sx,sy); app.touchmoved('aim-drag',sx,sy)
        press(panel:rect(1)); app.touchreleased('aim-drag',sx,sy)
    else local sx,sy=coords(x,y); app.mousemoved(sx,sy,0,0,false); app.mousepressed(sx,sy,1,false); app.mousereleased(sx,sy,1,false) end
end
local function action(panel,index,key)
    if touch then press(panel:rect(index)) else app.keypressed(key); app.keyreleased(key) end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true ambush=true ownedGuns=true reload=true cover=true mode=true saveRetry=true reconnect=true hostStoryOnly=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    local Ambush=require('game.train_ambush'); local create=Ambush.new
    Ambush.new=function(context) ambush=create(context); return ambush end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99
        local data=c.newSave(c.characters[1]); data.location=2; data.scene='train'; data.passengers={}
        check(c.enterGame(data),'campaign load failed'); data=c.runtime.saveData
        Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=40
        local Events=require('game.events'); local Catalog=require('game.catalog')
        check(Events.resolve(data,Catalog,Events.findById('rail-bandits'),1).trainAmbush,'authored ambush event failed')
        local s=data.trainAmbush; s.phase='combat'
        for _,v in ipairs(s.vehicles) do if v.active then v.motion.phase='matched'; v.motion.clock=0 end
            for _,crew in ipairs(v.crew) do crew.phase='hidden'; crew.timer=999 end end
        app.update(.01)
        lp.context.placeCompanion=function(d)
            local own=Players.forActor(d,'companion'); own.playerX,own.playerY=d.playerX,d.playerY
            Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            Items.write(own,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            Items.write(own,nil,{kind='inventory',index=2},'frontier-9mm-smg')
            firstId=assert(Items.get(own,nil,{kind='equipment',index=2})).id
            duplicateId=assert(Items.get(own,nil,{kind='inventory',index=1})).id
            smgId=assert(Items.get(own,nil,{kind='inventory',index=2})).id
            own.ammo['22lr']=40; own.ammo['9mm']=40; return true
        end
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local disconnected=lp.network.context.disconnected
        lp.network.context.disconnected=function(generation,reason)
            print('LAN_AMBUSH_DISCONNECTED generation='..tostring(generation)..' reason='..tostring(reason))
            return disconnected(generation,reason)
        end
        local command=lp.network.context.command
        lp.network.context.command=function(gen,request)
            if request.command=='gun.fire' and not pendingShotHP then
                pendingShotHP=Rules.vehicle(data.trainAmbush,'pickup').hull
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    if path=='saves/slot99.lua.tmp' then return false,'ambush fixture write failure' end
                    return restoreWrite(path,...)
                end
            end
            local reply=command(gen,request)
            print('LAN_AMBUSH_COMMAND name='..request.command..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason)..' durable='..tostring(reply.durable))
            if request.command=='ambush.withdraw' or request.command=='ambush.continue' then
                check(not reply.ok and reply.reason=='host_only','guest progressed the story'); denied=denied+1
            end
            return reply
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port); click('name','Ambush friend'); click('join')
        stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local s=c.runtime.saveData.trainAmbush
    for _,v in ipairs(s.vehicles) do if v.motion then v.motion.matchClock=0 end end -- Fixed convoy for repeatable aiming.
    local pending=lp:pending(); if pending then connections=connections+1; click('approve'); back() end
    if stage=='hosting' and lp.authority.pendingSave then
        check(s.shots==1 and c.runtime.saveData.players.companion.ammo['22lr']==39,'guest shot cost mismatch')
        retryAt=retryAt or love.timer.getTime()
        if exists('guest.pending') then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            check(c.ui.retryCheckpoint(),'retry failed'); stage='shot-saved'
        end
    elseif stage=='shot-saved' and exists('guest.first-saved') then
        check(s.shots==1 and Rules.vehicle(s,'pickup').hull==pendingShotHP-1,'first shot/replay hit mismatch')
        local cs=ambush:commandState('host')
        print('LAN_AMBUSH_HOST_INPUT state='..tostring(cs~=nil)..' paused='..tostring(cs and cs.paused)..' phase='..tostring(s.phase)
            ..' exit='..tostring(c.runtime.exitPrompt)..' confirm='..tostring(c.runtime.pendingConfirmation))
        shoot(nil,s); check(s.shots==2 and c.runtime.saveData.ammo['22lr']==39,
            'host gun was not independent: shots='..tostring(s.shots)..' rounds='..tostring(c.runtime.saveData.ammo['22lr'])
            ..' menu='..tostring(lp.menuOpen)..' focus='..tostring(lp.focused)..' paused='..tostring(c.ui.escMenuOpen))
        app.keypressed('p'); app.keyreleased('p'); pausedClock=s.clock
        marker('host.paused'); menu(); stage='host-menu'
    elseif stage=='host-menu' and exists('guest.before-rejoin') and not (lp.network.link and lp.network.link.admitted) then
        check(s.clock>pausedClock+1,'host menu paused the shared convoy')
        marker('host.disconnected'); stage='rejoining'
    elseif stage=='rejoining' and exists('guest.rejoined') then
        check(denied==2,'missing host-only decisions')
        back(); app.keypressed('p'); app.keyreleased('p'); app.keypressed('x'); app.keyreleased('x')
        check(s.outcome=='withdrawn','host withdrawal failed'); stage='result'
    elseif stage=='result' and exists('guest.result') then
        check(s.phase=='result' and s.active,'host result changed before continuation')
        app.keypressed('return'); app.keyreleased('return'); check(c.runtime.scene=='stop','host continuation failed')
        check(Save.flush(99),'flush failed'); marker('host.continued'); stage='continued'
    elseif stage=='continued' and exists('guest.stop') then
        local disk=assert(Save.read(99)); local owner=disk.trainAmbush.shooterSessions.companion
        check(disk.players.host.ammo['22lr']==39 and disk.players.companion.ammo['22lr']==39 and disk.players.companion.ammo['9mm']==39,'disk actor ammo mismatch')
        check(owner.weaponSession.itemId==smgId and owner.weaponSession.weapon=='frontier-9mm-smg','disk guest selection mismatch')
        check(owner.weaponSessions[firstId].itemId==firstId and owner.weaponSessions[duplicateId].itemId==duplicateId,'disk rifle history mismatch')
        check(not owner.weaponSession.aimX and disk.scene=='stop' and not disk.trainAmbush.active,'saved story/input mismatch')
        finish()
    end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local v=lp.clientView; local p=v and v.ambush
    if stage=='disconnected' then
        if exists('host.disconnected') then menu(); click('join'); stage='rejoining' end
        return
    end
    if stage=='joining' and v and v.ready and p and p.gun and p:canAct()==false and lp.menuOpen then back() end
    if not v or not v.ready or not p then return end
    local s=v.runtime.saveData.trainAmbush; local own=s and s.shooterSessions and s.shooterSessions.companion
    if stage=='joining' and p:canAct() and p.gun then
        oldEpoch=v.epoch; firstId=p.gun.itemId; check(firstId~=s.weaponSession.itemId,'actors share item identity')
        shoot(p,s); requestId=p.pending and p.pending.id; check(requestId,'guest input did not submit a shot'); stage='pending'
    elseif stage=='pending' and lp.network.lastCommandResult and lp.network.lastCommandResult.savePending then
        marker('guest.pending'); capture='01-save-pending'; stage='saving'
    elseif stage=='saving' and not p.pending and p.lastOutcome and p.lastOutcome.ok then
        check(v.runtime.saveData.ammo['22lr']==39 and s.shots>=1,'guest first shot mismatch'); marker('guest.first-saved'); stage='reload'
    elseif stage=='reload' and exists('host.paused') and s.shots==2 and p:canAct() then
        action(p,3,'r'); check(p.pending,'reload did not submit while host paused'); stage='reloading'
    elseif stage=='reloading' and not p.pending then
        check(p.lastOutcome and p.lastOutcome.ok,'reload rejected: '..tostring(p.lastOutcome and p.lastOutcome.reason))
        check(own.weaponSession.reloadTimer>0,'reload never entered a timed stage')
        capture='02-guest-reloading'; stage='reload-wait'
    elseif stage=='reload-wait' and p:canAct() and own.weaponSession.reloadTimer==0 then
        check(own.weaponSession.magazine==own.weaponSession.capacity,'guest reload did not finish under host menu')
        action(p,4,'c'); stage='cover'
    elseif stage=='cover' and p:canAct() and s.defenders.companion.coverProgress==1 then
        check(not s.cover,'guest cover changed host cover'); capture='03-guest-cover'
        action(p,4,'c'); stage='uncover'
    elseif stage=='uncover' and p:canAct() and s.defenders.companion.coverProgress==0 then
        action(p,5,'tab'); stage='duplicate'
    elseif stage=='duplicate' and p:canAct() and p.gun.itemId~=firstId then
        duplicateId=p.gun.itemId; check(p.gun.weapon=='frontier-22-lever-rifle','duplicate rifle selection failed')
        action(p,5,'tab'); stage='smg'
    elseif stage=='smg' and p:canAct() and p.gun.weapon=='frontier-9mm-smg' then
        smgId=p.gun.itemId; action(p,6,'v'); stage='mode'
    elseif stage=='mode' and p:canAct() and p.gun.fireMode=='auto' then
        shoot(p,s)
        check(p.pending,'SMG input did not submit: magazine='..tostring(p.gun.magazine)..' cooldown='..tostring(p.gun.cooldown)
            ..' reload='..tostring(p.gun.reloadTimer)..' cover='..tostring(s.defenders.companion.coverProgress)..' phase='..tostring(s.phase))
        stage='smg-shot'
    elseif stage=='smg-shot' and p:canAct() then
        check(p.lastOutcome and p.lastOutcome.ok,'SMG shot rejected: '..tostring(p.lastOutcome and p.lastOutcome.reason))
        check(v.runtime.saveData.ammo['9mm']==39,'SMG ammunition mismatch: '..tostring(v.runtime.saveData.ammo['9mm']))
        capture='04-guest-smg'; requestId=assert(lp.network:submitCommand('ambush.withdraw',{},v.epoch,{})); stage='deny-withdraw'
    elseif stage=='deny-withdraw' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        check(lp.network.lastCommandResult.reason=='host_only','withdraw was allowed')
        requestId=assert(lp.network:submitCommand('ambush.continue',{},v.epoch,{})); stage='deny-continue'
    elseif stage=='deny-continue' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        check(lp.network.lastCommandResult.reason=='host_only','continue was allowed'); check(v.epoch==oldEpoch,'guest changed story epoch')
        marker('guest.before-rejoin'); menu(); click('leave'); stage='disconnected'
    elseif stage=='rejoining' and p.gun and p.gun.itemId==smgId and lp.phase=='connected' then
        back()
        if p:canAct() then
            check(v.runtime.saveData.ammo['22lr']==39 and v.runtime.saveData.ammo['9mm']==39,'rejoin refilled ammunition')
            check(p.gun.magazine==p.gun.capacity-1 and p.gun.fireMode=='auto','rejoin changed magazine/mode')
            check(own.weaponSessions[firstId].itemId==firstId and own.weaponSessions[duplicateId].itemId==duplicateId,'rejoin lost gun history')
            marker('guest.rejoined'); capture='05-guest-rejoined'; stage='result'
        end
    elseif stage=='result' and s.phase=='result' then
        app.keypressed('return'); app.keyreleased('return'); check(s.active and v.runtime.scene=='train','guest continued from result')
        capture='06-guest-result'; marker('guest.result'); stage='stop'
    elseif stage=='stop' and v.runtime.scene=='stop' then
        check(not p:available() and v.epoch>oldEpoch,'guest did not follow host continuation'); marker('guest.stop'); finish()
    end
end
local function update(dt)
    if finished then return end; app.update(math.min(.1,dt))
    if role=='host' then hostUpdate() else guestUpdate() end
    if love.timer.getTime()-lastReport>4 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        print('LAN_AMBUSH_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)..' error='..tostring(lp.error))
        if role=='guest' and lp.clientView then
            local p=lp.clientView.ambush; local r=lp.network and lp.network.lastCommandResult; local s=p:state()
            print('LAN_AMBUSH_INPUT pending='..tostring(p.pending and p.pending.name)..' result='..tostring(r and r.reason)
                ..' phase='..tostring(s and s.phase)..' ready='..tostring(p:canAct())..' rounds='..tostring(lp.clientView.runtime.saveData.ammo['9mm']))
        end
    end
    check(love.timer.getTime()-started<65,'fixture timed out at '..tostring(stage))
end
local function guarded(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then
        if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
        print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not captures[capture] then love.graphics.captureScreenshot(role..'-'..capture..'.png'); captures[capture]=true end
        capture=nil
    end)
end
