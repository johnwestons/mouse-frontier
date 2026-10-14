-- Two source apps: admission inside the farmhouse, independent motion and rejoin.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT')); local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Life=require('game.coop_last_stand_lifecycle'); local Save=require('game.save'); local Schema=require('game.save_schema')
local Viewport=require('game.viewport')
local Style=require('game.ui_layout')
local app,c,stage,started,finished,oldKeyboard,movementKey,capture,initialId,epoch,hostX,hostY,guestX,guestY,requestId,seenAt
local lastReport=0; local connections=0; local captures={}
local restoreWrite; local supplyCommands=0; local loanCheckpoint=false; local providerStopSequence
local aidFailed=false; local aidActiveFailed=false; local aidRecovered=false; local aidContended=false; local lastGesture=0; local moves; local moveIndex=1
local function check(value,message) assert(value,message) end
local function marker(name,value) local f=assert(io.open(root..'/'..name,'w')); f:write(tostring(value or true)); f:close() end
local function read(name) local f=io.open(root..'/'..name,'r'); if not f then return nil end; local v=f:read('*a'); f:close(); return v end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function button(key) app.keypressed(key); app.keyreleased(key) end
local function press(r)
    check(r,'missing control '..tostring(stage)); local x,y=coords(r.x+r.w/2,r.y+r.h/2)
    if touch then app.touchpressed('button',x,y); app.touchreleased('button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); button('return') end
end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function walk(view,clickDestination)
    if touch then
        app.draw(); local stick=view.mobile.joystick; local x,y=coords(stick.x,stick.y)
        app.touchpressed('farm-walk',x,y); x,y=coords(stick.x,stick.y-stick.radius*.95); app.touchmoved('farm-walk',x,y,0,0)
    elseif clickDestination then
        local x,y=coords(505,450); app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false)
        check(view.lastStand.destination,'guest click destination missing')
    else movementKey='w' end
end
local function stopWalk()
    movementKey=nil
    if touch then app.touchreleased('farm-walk',0,0,0,0) end
    local lp=c and c.ui.localPlay; local view=lp and lp.clientView
    if view and view.lastStand then view.lastStand:suspend(); if lp.network and view.ready then view:neutralize() end end
end
local function walkDirection(view,key)
    stopWalk()
    if touch then
        app.draw(); local stick=view.mobile.joystick; local x,y=coords(stick.x,stick.y)
        app.touchpressed('farm-walk',x,y)
        x,y=coords(stick.x+(key=='a' and -1 or key=='d' and 1 or 0)*stick.radius*.95,
            stick.y+(key=='w' and -1 or key=='s' and 1 or 0)*stick.radius*.95)
        app.touchmoved('farm-walk',x,y,0,0)
    else movementKey=key end
end
local function aidPointer(action,x,y,other)
    local rect=Style.transformRectFor('firstAid',{x=105,y=40,w=750,h=635},{x=x,y=y,w=0,h=0})
    x,y=coords(rect.x,rect.y)
    if touch then
        local id=other and 'other-finger' or 'defender-aid'
        if action=='press' then app.touchpressed(id,x,y)
        elseif action=='move' then app.touchmoved(id,x,y,0,0)
        else app.touchreleased(id,x,y) end
    elseif action=='press' then app.mousepressed(x,y,1,false)
    elseif action=='move' then app.mousemoved(x,y,0,0,false)
    else app.mousereleased(x,y,1,false) end
end
local function finish()
    if finished then return end; finished=true; stopWalk(); check(app.quit()~=true,'quit cancelled')
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    print('LAN_SMOKE_OK role='..role..' lastStand=true movement=true modalReady=true reconnect=true provider=true failedCheckpoint=true input='..(touch and 'touch' or 'desktop')
        ..' defenderAid=true partialAidRejoin=true aidSaveRetry=true aidLockRecovery=true patientContention=true'
        ..' schema='..Schema.CURRENT_VERSION..' protocol='..require('game.net.protocol').VERSION..' connections='..connections)
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(12102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if key==movementKey then return true end; return oldKeyboard(key,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    local originalBuild=lp.context.compatibility or require('game.net.compatibility').compute
    lp.context.compatibility=function(fs)
        local ok,result,reason=xpcall(function() return originalBuild(fs) end,debug.traceback)
        if not ok then print('LAN_LAST_STAND_BUILD_ERROR '..tostring(result)); error(result) end
        return result,reason
    end
    local originalView=lp.context.createGuestView
    lp.context.createGuestView=function(controller)
        local ok,value=xpcall(function() return originalView(controller) end,debug.traceback)
        if not ok then print('LAN_LAST_STAND_VIEW_ERROR '..tostring(value)); error(value) end
        local originalUpdate=value.update
        value.update=function(view,dt)
            local success,result,reason=xpcall(function() return originalUpdate(view,dt) end,debug.traceback)
            if not success then print('LAN_LAST_STAND_UPDATE_ERROR '..tostring(result)); error(result) end
            return result,reason
        end
        return value
    end
    if role=='host' then
        c.runtime.selectedSlot=99
        local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
        draft.lastStand={state='interior',originStop=12,returnX=270,returnY=490}
        check(c.enterGame(draft),'host campaign load failed'); app.update(.01)
        hostX,hostY=c.runtime.saveData.playerX,c.runtime.saveData.playerY; epoch=c.runtime.saveData.coop.sceneEpoch
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error)); back()
        local command=lp.network.context.command
        lp.network.context.command=function(gen,request)
            if request.command=='lastStand.supply' then
                local p=Life.pose(c.runtime.saveData,'companion'); local m=lp.motion.actor
                print('LAN_PROVIDER_POSITION saved='..p.x..','..p.y..' motion='..m.x..','..m.y..' intent='..tostring(m.intentX)..','..tostring(m.intentY))
            end
            if request.command=='lastStand.supply' and request.args.mode=='farmhouse' and supplyCommands==0 then
                supplyCommands=1; restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    if path=='saves/slot99.lua.tmp' then return false,'provider fixture write failure' end
                    return restoreWrite(path,...)
                end
            end
            local progress=c.runtime.saveData.lastStand.treatmentProgress
            if request.command=='lastStand.aid' and request.args.action=='move' and progress and progress.phase==6
                and progress.wrapPasses==2 and not aidActiveFailed then
                aidActiveFailed=true; restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    if path=='saves/slot99.lua.tmp' then return false,'ready defender aid fixture write failure' end
                    return restoreWrite(path,...)
                end
            end
            if request.command=='lastStand.aid' and request.args.action=='acquire' and aidActiveFailed
                and require('game.coop_last_stand_aid_state').ready(progress) then aidRecovered=true end
            local patientLease=lp.authority.activityState.resources[require('game.coop_last_stand_aid').resource(c.runtime.saveData.lastStand.lifecycle.entityId)]
            if request.command=='lastStand.aid' and request.args.action=='complete' and not aidFailed
                and patientLease and patientLease.id==request.args.leaseId then
                aidFailed=true; restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    if path=='saves/slot99.lua.tmp' then return false,'defender aid fixture write failure' end
                    return restoreWrite(path,...)
                end
            end
            local reply=command(gen,request)
            print('LAN_LAST_STAND_COMMAND name='..request.command..' action='..tostring(request.args.action)..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason)..' durable='..tostring(reply.durable))
            return reply
        end
        button('p'); check(c.runtime.lastStand.paused,'host private pause failed')
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port); click('name','Farm friend'); click('join')
        check(lp.network,'guest join failed '..tostring(lp.error))
        stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local q=data.lastStand
    local pending=lp:pending(); if pending then connections=connections+1; click('approve'); back() end
    if lp.authority.pendingSave and restoreWrite and read('guest.supply.pending') then
        if aidFailed then
            if read('guest.aid.pending') then
                check(q.woundedTreated and q.positionIntegrity==62 and not q.residentChecked,'pending aid changed host story or integrity twice')
                love.filesystem.write=restoreWrite; restoreWrite=nil
                check(c.ui.retryCheckpoint(),'aid checkpoint retry failed'); marker('host.aid.retry')
            end
        elseif aidActiveFailed then
            if read('guest.aid.active.pending') then
                check(not q.woundedTreated and q.positionIntegrity==50 and q.treatmentProgress.wrapPasses==3,'ready treatment applied benefit before confirmation')
                love.filesystem.write=restoreWrite; restoreWrite=nil
                check(c.ui.retryCheckpoint(),'ready treatment checkpoint retry failed'); marker('host.aid.active.retry')
            end
        else
        check(q.shooterSessions.companion.loanAmmo==48 and not q.loanActive,'pending supply affected another actor')
        love.filesystem.write=restoreWrite; restoreWrite=nil
        check(c.ui.retryCheckpoint(),'provider save retry failed'); marker('host.supply.retry')
        end
    end
    if stage=='rejoin' and read('guest.supply.saved') and not loanCheckpoint then
        check(q.shooterSessions.companion.loanAmmo==48 and not q.shooterSessions.companion.weaponSession and not q.loanActive,'guest supply ownership failed')
        check(lp.authority:checkpointNow(),'provider position checkpoint failed')
        local disk=assert(Save.read(99)); local pose=Life.pose(data,'companion')
        check(disk.lastStand.shooterSessions.companion.loanAmmo==48 and disk.players.companion.ammo.rocks==12,'provider disk ownership failed')
        marker('host.disk',pose.y); marker('host.supply.disk'); loanCheckpoint=true
    end
    if stage=='hosting' and data.players.companion then
        guestX,guestY=guestX or data.players.companion.playerX,guestY or data.players.companion.playerY
        if read('guest.interior') then
            local pose=Life.pose(data,'companion')
            check(pose and pose.y<530 and c.runtime.lastStand.paused,'guest did not move independently of host pause')
            check(Life.pose(data,'host').x==480 and Life.pose(data,'host').y==590,'guest moved host farmhouse pose')
            check(data.players.companion.playerX==guestX and data.players.companion.playerY==guestY,'guest changed ordinary stop position')
            check(lp.authority:checkpointNow(),'farm position checkpoint failed'); local disk=assert(Save.read(99))
            check(math.abs(disk.lastStand.lifecycle.positions.companion.y-pose.y)<.001 and Schema.validate(disk),'farm position disk restore failed')
            marker('host.disk',pose.y); stage='rejoin'; capture='interior'
        end
    elseif stage=='rejoin' and read('guest.rejoined') then
        check(data.playerX==hostX and data.playerY==hostY and data.coop.sceneEpoch==epoch,'farm motion changed ordinary host scene/position')
        button('p'); check(not c.runtime.lastStand.paused,'host did not unpause')
        check(q.shooterSessions.companion.loanAmmo==48,'rejoin changed companion supplies')
        c.runtime.lastStand.scene.player.x,c.runtime.lastStand.scene.player.y=300,335
        local high=lp.authority.requests.host and lp.authority.requests.host.high or 0
        button('e'); check(q.loanActive and q.loanAmmo==48 and q.shooterSessions.companion.loanAmmo==48,'host supply was not independent')
        check(lp.authority.requests.host.high>high and c.runtime.lastStand.notice.text:find('received'),'host supply bypassed durable command')
        capture='provider'; stage='host-provider'
    elseif stage=='host-provider' then
        c.runtime.lastStand.scene.player.x,c.runtime.lastStand.scene.player.y=480,620
        button('e'); check(q.lifecycle.mode=='backyard' and q.lifecycle.positions.companion.y==610,'host phase transition failed')
        marker('host.backyard'); stage='backyard'
    elseif stage=='backyard' and read('guest.backyard') then
        check(Life.pose(data,'companion').y<555 and Life.pose(data,'host').y==610,'independent backyard positions failed')
        check(data.coop.sceneEpoch==epoch and data.players.companion.playerX==guestX,'farm transition changed ordinary positions/epoch')
        check(lp.authority:checkpointNow(),'final provider checkpoint failed'); local disk=assert(Save.read(99))
        check(disk.lastStand.loanAmmo==48 and disk.lastStand.shooterSessions.companion.loanAmmo==48,'final loan pools changed')
        capture='backyard'
        -- Exercise the source host controller and keyboard cancellation before the guest helps.
        q.positionIntegrity=50
        c.runtime.lastStand.scene.player.x,c.runtime.lastStand.scene.player.y=750,455
        button('e'); check(c.runtime.lastStand.treatment and c.runtime.lastStand.treatment.command,'host treatment bypassed command binding')
        button('q'); check(not c.runtime.lastStand.treatment and not next(lp.authority.activityState.resources),'host cancel retained patient lock')
        check(not q.woundedTreated and q.treatmentProgress.phase==1,'host cancel completed treatment')
        button('p'); check(c.runtime.lastStand.paused,'host aid pause failed')
        marker('host.aid.ready'); stage='aid'
    elseif stage=='aid' then
        local held=lp.authority.activityState.resources[require('game.coop_last_stand_aid').resource(q.lifecycle.entityId)]
        if held and held.actorId=='companion' and not aidContended then
            button('p'); button('e')
            check(not c.runtime.lastStand.treatment and held.actorId=='companion','host stole guest patient')
            button('p'); aidContended=true; marker('host.aid.contention')
        end
        if read('guest.aid.paused') and not read('host.aid.partial') then
            local disk=assert(Save.read(99))
            check(disk.lastStand.treatmentProgress.phase==3 and disk.lastStand.treatmentProgress.rubDistance==90,'partial aid was not saved')
            check(not disk.lastStand.woundedTreated and disk.lastStand.positionIntegrity==50,'partial aid applied completion')
            marker('host.aid.partial')
        end
        if read('guest.aid.complete') then
            local disk=assert(Save.read(99))
            check(aidFailed and aidActiveFailed and aidRecovered and aidContended and disk.lastStand.woundedTreated and disk.lastStand.positionIntegrity==62,'aid completion not durable exactly once')
            check(not disk.lastStand.residentChecked and not next(lp.authority.activityState.resources),'guest aid progressed story or held patient')
            check(disk.lastStand.loanAmmo==48 and disk.lastStand.shooterSessions.companion.loanAmmo==48,'aid changed supplies')
            marker('host.done'); stage='done'
        end
    elseif stage=='done' and read('guest.done') then finish() end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView
    check(lp.phase~='idle' or lp.error==nil,'guest session failed '..tostring(lp.error))
    if (stage=='joining' or stage=='rejoined' or stage=='aid-rejoined') and view and view.ready and lp.menuOpen then back() end
    if stage=='joining' and lp.phase=='connected' and view and view:inputAllowed() then
        back(); check(view.lastStand:available() and view.lastStand.scene.mode=='interior','guest farmhouse presentation missing')
        if touch then
            local x,y=coords(700,32); app.touchpressed('private-pause',x,y); app.touchreleased('private-pause',x,y)
            check(view.lastStand.paused and not view:inputAllowed(),'guest touch pause failed')
            app.touchpressed('private-resume',x,y); app.touchreleased('private-resume',x,y)
            check(not view.lastStand.paused,'guest touch resume failed')
        end
        initialId=view.motionId; epoch=view.epoch; walk(view); stage='interior'
    elseif stage=='interior' and lp.motionFrame and lp.motionFrame.companion.y<515000 then
        stopWalk(); marker('guest.interior'); stage='disconnect'
    elseif stage=='disconnect' and read('host.disk') then
        walkDirection(view,'w'); stage='provider-up'
    elseif stage=='provider-up' and lp.motionFrame and lp.motionFrame.companion.y<355000 then
        walkDirection(view,'a'); stage='provider-left'
    elseif stage=='provider-left' and lp.motionFrame and lp.motionFrame.companion.x<345000 then
        stopWalk(); providerStopSequence=view.sequence; stage='provider-send'
    elseif stage=='provider-send' and view:inputAllowed() and lp.motionFrame.ack>=providerStopSequence
        and lp.motionFrame.companion.vx==0 and lp.motionFrame.companion.vy==0 then
        check(view.lastStand:action().id=='borrow-rifle','provider assistance control missing')
        capture='provider-ready'
        if touch then local x,y=coords(700,602); app.touchpressed('provider',x,y); app.touchreleased('provider',x,y)
        else button('e') end
        check(view.lastStand.pending,'provider request missing'); stage='provider-result'
    elseif stage=='provider-result' then
        local reply=lp.network.lastCommandResult
        check(not reply or reply.ok or reply.reason=='save_pending' or reply.reason=='busy','provider command denied: '..tostring(reply and reply.reason))
        if reply and reply.savePending then
            check(view.lastStand.pending and not view.lastStand.notice:find('received'),'pending loan was presented as saved')
            marker('guest.supply.pending')
        end
        if not view.lastStand.pending and read('host.supply.retry') then
            check(view.runtime.saveData.lastStand.shooterSessions.companion.loanAmmo==48 and view.lastStand.notice:find('received'),'guest durable supply missing')
            capture='provider-saved'; marker('guest.supply.saved'); stage='provider-disk'
        end
    elseif stage=='provider-disk' and read('host.supply.disk') then
        check(lp:stop('fixture_disconnect'),'guest leave failed'); marker('guest.left'); seenAt=love.timer.getTime(); stage='reconnecting'
    elseif stage=='reconnecting' and love.timer.getTime()-seenAt>.3 then
        menu(); click('join'); stage='rejoined'
    elseif stage=='rejoined' and lp.phase=='connected' and view and view:inputAllowed() then
        back(); local savedY=tonumber(read('host.disk'))
        check(math.abs(lp.motionFrame.companion.y/1000-savedY)<8 and view.lastStand.scene.mode=='interior','rejoin lost farmhouse position')
        check(view.runtime.saveData.lastStand.shooterSessions.companion.loanAmmo==48 and not view.runtime.saveData.lastStand.loanActive,'rejoin lost independent loan pool')
        marker('guest.rejoined'); initialId=view.motionId; stage='phase'
    elseif stage=='phase' and read('host.backyard') and view and view.lastStand.scene and view.lastStand.scene.mode=='backyard' and view:inputAllowed() then
        check(view.epoch==epoch and view.motionId>initialId,'modal transition did not reset motion generation')
        requestId=assert(lp.network:submitCommand('loot.pickup',{},view.epoch,{})); stage='denial'
    elseif stage=='denial' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        check(lp.network.lastCommandResult.reason=='modal_scene','ordinary outdoor command survived farmhouse scene')
        walk(view,true); stage='walk-backyard'
    elseif stage=='walk-backyard' and lp.motionFrame and lp.motionFrame.companion.y<540000 then
        stopWalk(); marker('guest.backyard'); capture='backyard'; stage='aid-walk'
    elseif stage=='aid-walk' and read('host.aid.ready') then
        walkDirection(view,'w'); stage='aid-up'
    elseif stage=='aid-up' and lp.motionFrame.companion.y<380000 then
        walkDirection(view,'d'); stage='aid-right'
    elseif stage=='aid-right' and lp.motionFrame.companion.x>755000 then
        walkDirection(view,'s'); stage='aid-down'
    elseif stage=='aid-down' and lp.motionFrame.companion.y>440000 then
        stopWalk(); providerStopSequence=view.sequence; stage='aid-open'
    elseif stage=='aid-open' and view:inputAllowed() and lp.motionFrame.ack>=providerStopSequence
        and lp.motionFrame.companion.vx==0 and lp.motionFrame.companion.vy==0 then
        check(view.lastStand:action().id=='help-wounded','defender aid action missing')
        if touch then local x,y=coords(700,602); app.touchpressed('aid-open',x,y); app.touchreleased('aid-open',x,y)
        else button('e') end
        check(view.lastStand.aid.opened,'guest treatment did not open'); stage='aid-injury'
    elseif stage=='aid-reconnect' and love.timer.getTime()-seenAt>.3 then
        menu(); click('join'); stage='aid-rejoined'
    elseif stage=='aid-rejoined' and lp.phase=='connected' and view and view:inputAllowed() then
        back(); check(view.runtime.saveData.lastStand.treatmentProgress.phase==3,'rejoin lost treatment phase')
        check(view.runtime.saveData.lastStand.treatmentProgress.rubDistance==90,'rejoin lost partial rub')
        button('e'); check(view.lastStand.aid.opened,'rejoined aid did not open'); stage='aid-resume'
    elseif stage:match('^aid%-') and view then
        local panel=view.lastStand.aid; local now=love.timer.getTime(); local reply=lp.network.lastCommandResult
        if reply and reply.savePending and panel.pending and panel.pending.action=='complete' then
            check(not panel.completed,'pending treatment was presented as saved'); marker('guest.aid.pending')
        elseif reply and reply.savePending and panel.pending and panel.pending.action=='move' and stage=='aid-complete' then
            check(not panel.completed,'ready treatment was presented as completed'); marker('guest.aid.active.pending')
        end
        if stage=='aid-complete' and panel.completed then
            check(read('host.aid.retry') and read('host.aid.active.retry') and view.runtime.saveData.lastStand.positionIntegrity==62,'aid completion projection missing')
            check(not view.runtime.saveData.lastStand.residentChecked and view.epoch==epoch,'guest treatment progressed story')
            capture='aid-completed'; marker('guest.aid.complete'); stage='done'
        elseif stage=='aid-paused' and not panel:busy() then
            marker('guest.aid.paused'); check(lp:stop('aid_partial_disconnect'),'partial aid disconnect failed')
            seenAt=now; stage='aid-reconnect'
        elseif panel.session and not panel.pending and #panel.queue==0 and now-lastGesture>.22 then
            if stage=='aid-injury' then
                check(panel.session.phase==1,'wrong initial treatment phase'); aidPointer('press',512,420); aidPointer('release',512,420); stage='aid-pour'
            elseif stage=='aid-pour' and panel.session.phase==2 then
                aidPointer('move',480,370); stage='aid-wait-pour'
            elseif stage=='aid-wait-pour' and panel.session.phase==3 then
                aidPointer('press',410,370); stage='aid-partial'
            elseif stage=='aid-partial' then
                if touch then local n=#panel.queue; aidPointer('move',550,370,true); check(#panel.queue==n,'unowned aid finger moved wound') end
                aidPointer('move',500,370); aidPointer('release',500,370); stage='aid-pause'
            elseif stage=='aid-pause' then
                check(panel.session.progress.rubDistance==90,'partial rub display missing'); capture='aid-partial'; button('escape'); stage='aid-paused'
            elseif stage=='aid-resume' then
                check(panel.session.phase==3 and panel.session.progress.rubDistance==90,'resumed treatment progress missing')
                aidPointer('press',410,370); moves={550,410,550,410}; moveIndex=1; stage='aid-rub'
            elseif stage=='aid-rub' then
                if panel.session.phase==4 then aidPointer('release',410,370); stage='aid-ointment-start'
                else aidPointer('move',moves[moveIndex],370); moveIndex=moveIndex+1; check(moveIndex<=5,'rub did not advance') end
            elseif stage=='aid-ointment-start' then
                aidPointer('press',410,370); moveIndex=1; stage='aid-ointment'; capture='aid-ointment'
            elseif stage=='aid-ointment' then
                if panel.session.phase==5 then aidPointer('release',480,370); stage='aid-gauze'
                else
                    local previous=moveIndex%2==0 and 550 or 410; local target=moveIndex%2==0 and 410 or 550
                    for i=1,70 do aidPointer('move',previous+(target-previous)*i/70,370) end
                    moveIndex=moveIndex+1; check(moveIndex<=15,'ointment did not advance')
                end
            elseif stage=='aid-gauze' then aidPointer('press',480,370); aidPointer('release',480,370); stage='aid-wrap-start'
            elseif stage=='aid-wrap-start' then
                check(panel.session.phase==6,'gauze did not advance'); aidPointer('press',398,370); moves={562,398,562}; moveIndex=1; stage='aid-wrap'; capture='aid-wrap'
            elseif stage=='aid-wrap' and not panel.session.ready then
                aidPointer('move',moves[moveIndex],370); moveIndex=moveIndex+1; check(moveIndex<=4,'wrap did not complete')
                if moveIndex==4 then stage='aid-complete' end
            end
            lastGesture=now
        end
    elseif stage=='done' and read('host.done') then
        check(c.runtime.saveData==nil or c.runtime.saveData==false,'guest acquired a writable host campaign')
        marker('guest.done'); finish()
    end
end
local function update(dt)
    if finished or not app then return end
    app.update(math.min(.05,dt))
    if role=='host' then hostUpdate() else guestUpdate() end
    if love.timer.getTime()-lastReport>4 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        print('LAN_LAST_STAND_STAGE role='..role..' stage='..tostring(stage)..' phase='..tostring(lp.phase)..' error='..tostring(lp.error))
    end
    check(love.timer.getTime()-started<110,'fixture timed out at '..tostring(stage))
end
local function guarded(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not captures[capture] then
            local name=role..'-'..capture..'.png'
            love.graphics.captureScreenshot(function(pixels)
                local file=assert(io.open(root..'/'..name,'wb')); file:write(pixels:encode('png'):getString()); file:close()
            end)
            captures[capture]=true
        end
        capture=nil
    end)
end
