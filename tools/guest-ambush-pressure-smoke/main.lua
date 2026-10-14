-- Normal production convoy/enemy simulation. The pilot observes authored PNG
-- target masks and sends ordinary controls; it never edits combat after seed.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_AMBUSH_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_AMBUSH_RESUMED')=='1'
local Save=require('game.save'); local Players=require('game.coop_players'); local Items=require('game.item_instances')
local Rules=require('game.train_ambush_rules'); local Scene=require('game.train_ambush_scene')
local State=require('game.coop_ambush_state'); local Codec=require('game.net.codec')
local Checkpoint=require('checkpoint'); local Receipts=require('game.coop_receipts')
local Viewport=require('game.viewport'); local Aim=require('game.mobile_weapon_aim')
local app,c,source,stage,started,finished,restoreWrite,lastReport,requestId,oldSession,firstItem,firstMagazine
local lastFire=0; local incoming={host=0,companion=0}; local shots={host=0,companion=0}; local denied=0
local distantReports=0
local oldClock,heldClock,heldTime,pendingAt,initialScrap,initialCondition,initialHostHealth,initialGuestHealth
local savedAmmo,savedHealth,savedItem,savedMagazine,savedReload,proofSession
local capture,capturePending; local captures={}
local oldKeyboard,movementKey,returnX,returnAt
local returnHostX,returnHostY,returnFacts
local limits={maxBytes=65536,maxDepth=16,maxEntries=4096,maxStringBytes=256}
local function check(value,message) assert(value,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function button(key) app.keypressed(key); app.keyreleased(key) end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function press(r)
    check(r,'missing control at '..tostring(stage)); local x,y=coords(r.x+r.w/2,r.y+r.h/2)
    if touch then app.touchpressed('control',x,y); app.touchreleased('control',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(id,text)
    app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); button('return') end
end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function action(panel,index,key)
    if touch then
        local width=(960-40)/8
        press(panel and panel:rect(index) or {x=20+(index-1)*width,y=720-76,w=width-5,h=56})
    else button(key) end
end
local function signature(data)
    return Checkpoint.encode({campaignId=data.coop.network.campaignId,companionId=data.coop.network.companionId,
        epoch=data.coop.sceneEpoch,location=data.location,scene=data.scene,ambush=data.trainAmbush,
        host=data.players.host,companion=data.players.companion,scrap=data.scrap,maintenance=data.maintenance,events=data.events},limits)
end
local function sameSignature(data,want,label,roundTrip)
    local have=signature(data); if have==want then return end
    local a,b=assert(Codec.decode(want,limits)),assert(Codec.decode(have,limits)); local count=0
    local function compare(x,y,path)
        count=count+1; check(count<8192,'signature tree exceeded bound')
        if type(x)=='table' and type(y)=='table' then
            local seen={}; for k,v in pairs(x) do seen[k]=true; compare(v,y[k],path..'.'..tostring(k)) end
            for k,v in pairs(y) do if not seen[k] then compare(nil,v,path..'.'..tostring(k)) end end
        elseif x~=y then
            check(roundTrip and type(x)=='number' and type(y)=='number' and (x~=math.floor(x) or y~=math.floor(y))
                and math.abs(x-y)<1e-11*math.max(1,math.abs(x),math.abs(y)),label..' changed '..path..': '..tostring(x)..' -> '..tostring(y))
        end
    end
    compare(a,b,'saved')
end
local function target(state,actor)
    local view=actor=='companion' and State.view(state,actor) or state
    -- Aiming is derived from visible authored crew clips, then checked against
    -- all production aperture/near-shell/alpha-mask rules. No fake hit claims.
    local best
    for _,entry in ipairs(Scene.layout(view,960,720).vehicles) do
        for _,clip in ipairs(entry.visual.clips) do
            for py=clip.y+2,clip.y+clip.h-2,3 do for px=clip.x+2,clip.x+clip.w-2,3 do
                local x,y=entry.x+px*entry.scale,entry.y+(py-entry.sourceY)*entry.scale
                local t=Scene.target(view,960,720,x,y)
                if t and t.kind=='crew' then
                    local vehicle=Rules.vehicle(state,t.vehicle)
                    local solid=vehicle.motion.phase=='matched'
                    for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                        local nearby=Scene.target(view,960,720,x+offset[1],y+offset[2])
                        if not nearby or nearby.kind~='crew' or nearby.vehicle~=t.vehicle or nearby.index~=t.index then solid=false end
                    end
                    if solid then
                        local priority=vehicle.distance=='far' and 0 or 1
                        if not best or priority<best.priority then best={x=x,y=y,priority=priority} end
                        break
                    end
                end
            end; if best and best.priority==0 then break end end
        end
    end
    return best and best.x,best and best.y
end
local function fire(panel,state)
    local x,y=target(state,panel and 'companion' or 'host'); if not x then return false end
    if touch and panel then
        local gx,gy=Aim.gripForAim(panel.gun.weapon,panel.gun.ads and 'sights' or 'hip',x,y,960,720)
        gx,gy=coords(gx,gy); app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0)
        press(panel:rect(1)); app.touchreleased('aim',gx,gy)
    elseif touch then
        local gun=state.weaponSession
        local gx,gy=Aim.gripForAim(gun.weapon,'hip',x,y,960,720); gx,gy=coords(gx,gy)
        app.touchpressed('aim',gx,gy); app.touchmoved('aim',gx,gy,0,0); action(nil,1,'space'); app.touchreleased('aim',gx,gy)
    else local gx,gy=coords(x,y); app.mousemoved(gx,gy,0,0,false); app.mousepressed(gx,gy,1,false); app.mousereleased(gx,gy,1,false) end
    return true
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    if oldKeyboard then love.keyboard.isDown=oldKeyboard end
    check(app.quit()~=true,'quit cancelled')
    if role=='guest' then check(distantReports>0,'guest never dispatched a fresh distant enemy-shot report') end
    print('LAN_SMOKE_OK role='..role..' application=true ambushPressure=true unmodifiedEncounter=true'
        ..' normalEnemyTiming=true saveRetry=true reconnect=true hostOnlyStory=true diskResume='..tostring(restart)
        ..' guestDistantReports='..tostring(distantReports)
        ..' input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function hostEntry()
    local lp=c.ui.localPlay; lp.port=port; c.runtime.state='slots'; menu(); click('host')
    check(lp.hostingIntent=='selecting' and not lp.menuOpen,'saved hosting intent missing')
    app.draw(); press(c.ui.slots[1]); check(lp.network and c.session.networkMode=='host' and c.runtime.selectedSlot==1,'real saved host entry failed')
    back()
end
local function load()
    started=love.timer.getTime(); lastReport=started
    require('game.smoke_playthrough').install=function(value) c=value end
    local make=require('game.train_ambush').new
    require('game.train_ambush').new=function(context) source=make(context); return source end
    -- Count actual production audio dispatch while preserving its preference,
    -- asset and playback path. This observes cues, not physical audibility.
    local Shooting=require('game.first_person_shooting')
    local playReport=Shooting.playReport
    Shooting.playReport=function(weapon,catalog,data,distant)
        if role=='guest' and distant then
            distantReports=distantReports+1
            print('LAN_AMBUSH_GUEST_DISTANT_REPORT count='..distantReports)
        end
        return playReport(weapon,catalog,data,distant)
    end
    -- Passive observation only: preserve original arguments, callback and RNG.
    local update=Rules.update
    Rules.update=function(data,state,dt,onFire,participants)
        return update(data,state,dt,function(vehicle,index,actor)
            incoming[actor]=(incoming[actor] or 0)+1
            if onFire then onFire(vehicle,index,actor) end
        end,participants)
    end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...)
        if movementKey and key==movementKey then return true end
        return oldKeyboard(key,...)
    end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        if not resumed then
            Save.remove(1); c.runtime.selectedSlot=1
            local draft=c.newSave(c.characters[1]); draft.location=2; draft.scene='train'; draft.passengers={}
            check(c.enterGame(draft),'canonical seed failed'); local data=c.runtime.saveData
            Items.write(data,nil,{kind='equipment',index=2},'frontier-556-carbine'); data.ammo['556']=60
            local Events=require('game.events'); local Catalog=require('game.catalog')
            check(Events.resolve(data,Catalog,Events.findById('rail-bandits'),1).trainAmbush,'approved initial event failed')
            check(Save.write(1,data),'visible-slot seed failed'); c.runtime.saveData=nil; c.runtime.selectedSlot=nil
        else sameSignature(assert(Save.read(1)),assert(file('resume.expected')),'new-process disk',false) end
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,why=place(data); if not ok then return ok,why end
            local own=Players.forActor(data,'companion'); Items.write(own,nil,{kind='equipment',index=2},'frontier-556-carbine')
            own.ammo['556']=60; check(Items.ensure(data),'initial guest ownership failed'); return true
        end
        hostEntry()
        if resumed then
            sameSignature(c.runtime.saveData,assert(file('resume.expected')),'real host slot entry',false)
            check(lp.authority.sessionId~=file('resume.session'),'host reused network session')
            proofSession=lp.authority.sessionId; file('host.resumed.session',proofSession)
            incoming=assert(Codec.decode(assert(file('resume.incoming')),limits)); shots=assert(Codec.decode(assert(file('resume.shots')),limits))
            initialScrap=tonumber(file('initial.scrap')); initialCondition=tonumber(file('initial.condition'))
            initialHostHealth=tonumber(file('initial.hostHealth')); initialGuestHealth=tonumber(file('initial.guestHealth'))
            stage='restored'
        else
            local data=c.runtime.saveData; initialScrap=data.scrap; initialCondition=data.maintenance.condition; initialHostHealth=data.health
            file('initial.scrap',initialScrap); file('initial.condition',initialCondition); file('initial.hostHealth',initialHostHealth)
            action(nil,4,'c'); stage='hosting'
        end
        button('p'); check(source:commandState('host').paused,'host private pause absent before first tick')
        local command=lp.network.context.command
        lp.network.context.command=function(generation,request)
            local before=c.runtime.saveData.trainAmbush.shots
            if request.command=='gun.fire' and not file('shot.failed') and not restoreWrite then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,...)
                    local pending=lp.authority.pendingSave
                    local receipt=pending and pending.actorId and Receipts.find(c.runtime.saveData,pending.actorId,lp.authority.sessionId,pending.requestId)
                    local command=receipt and Codec.decode(receipt.fingerprint,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128})
                    local data=c.runtime.saveData
                    if path==Save.path(1)..'.tmp' and pending and pending.actorId=='companion'
                        and command and command.command=='gun.fire' and data.trainAmbush.shots==1
                        and data.players.companion.ammo['556']==59 then
                        file('shot.failed',true); return false,'natural ambush test checkpoint failure'
                    end
                    return restoreWrite(path,...)
                end
            end
            local reply=command(generation,request)
            if request.command=='gun.fire' and reply.ok then
                shots.companion=shots.companion+c.runtime.saveData.trainAmbush.shots-before
            end
            if request.command:match('^ambush%.') then check(not reply.ok and reply.reason=='host_only','guest progressed story'); denied=denied+1 end
            return reply
        end
        print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; menu(); click('address','127.0.0.1:'..port); click('name','Convoy friend'); click('join')
        check(lp.network and (lp.phase=='joining' or lp.phase=='connected'),'initial Join did not activate: '..tostring(lp.error)); stage='joining'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local s=data.trainAmbush
    if lp:pending() then click('approve'); back() end
    if stage=='hosting' and file('guest.covered') then
        initialGuestHealth=data.players.companion.health; file('initial.guestHealth',initialGuestHealth)
        check(s.cover and s.defenders.companion.cover,'two real cover commands missing'); button('p'); stage='pressure'
    elseif stage=='pressure' and incoming.host>=1 and incoming.companion>=1 then
        check(data.health==initialHostHealth and data.players.companion.health==initialGuestHealth,'full cover did not protect personal HP')
        check(s.trainDamage>=2 and data.maintenance.condition<initialCondition and s.protection<24,'actual enemy pressure absent')
        button('p'); file('host.pressure',s.clock); capture='actual-covered-enemy-fire'; stage='first-shot'
    elseif stage=='first-shot' and lp.authority.pendingSave and file('guest.savePending') and file('guest.pendingStable') then
        oldClock=s.clock; check(s.shots==1 and data.players.companion.ammo['556']==59,'failed-save shot cost missing')
        love.filesystem.write=restoreWrite; restoreWrite=nil
        if touch then press({x=190,y=438,w=185,h=58}) else button('r') end
        check(not c.session.checkpointPending and not lp.authority.pendingSave,'visible Retry control failed'); stage='disconnect'
    elseif stage=='disconnect' and file('guest.left') and not (lp.network.link and lp.network.link.admitted) then
        heldClock=s.clock; heldTime=love.timer.getTime(); stage='frozen'
    elseif stage=='frozen' and love.timer.getTime()-heldTime>.7 then
        check(s.clock==heldClock,'disconnected guest advanced convoy under host private pause')
        check(s.shooterSessions.companion.weaponSession.reloadTimer>0,'partial reload was not retained')
        check(lp.authority:checkpointNow(),'restart checkpoint failed'); local disk=assert(Save.read(1))
        sameSignature(data,signature(disk),'durable round trip',true)
        file('resume.expected',signature(disk)); file('resume.session',lp.authority.sessionId)
        file('resume.incoming',assert(Codec.encode(incoming,limits))); file('resume.shots',assert(Codec.encode(shots,limits)))
        file('host.restart.saved',true)
        if restart then
            finished=true; print('LAN_SMOKE_RESTART role=host ambushSaved=true ownItems=true ownAmmo=true normalClock=true'); love.event.quit(42)
        else file('host.resumed.session',lp.authority.sessionId); file('host.resumed',true); stage='resuming' end
    elseif stage=='restored' then
        check(source:commandState('host').paused,'Source restore did not retain test private pause')
        file('host.resumed',true); stage='resuming'
    elseif stage=='resuming' and file('guest.resumed') then
        check(s.shots==1 and data.players.companion.ammo['556']==59,'rejoin repeated shot cost')
        button('p'); action(nil,4,'c'); file('host.pilot',true); stage='pilot'
    elseif stage=='pilot' then
        check(s.outcome~='overrun' and s.outcome~='withdrawn','normal pilot failed encounter: '..tostring(s.outcome))
        if s.phase=='combat' and not s.cover and s.coverProgress==0 then
            local gun=s.weaponSession
            if gun.reloadTimer==0 and gun.cooldown==0 and love.timer.getTime()-lastFire>.2 then
                if gun.magazine==0 then action(nil,3,'r')
                else local before=s.shots; fire(nil,s); if s.shots>before then shots.host=shots.host+1; lastFire=love.timer.getTime() end end
            end
        elseif s.phase=='result' then
            check(shots.host>0 and shots.companion>0 and incoming.host>0 and incoming.companion>0,'missing independent real participation')
            check(s.reward==((s.outcome=='crew' or s.outcome=='disabled') and 5 or 0),'original salvage changed')
            check(data.scrap==initialScrap+s.reward and data.players.companion.health<=initialGuestHealth and data.health<=initialHostHealth,'settlement/health mismatch')
            file('host.result',s.outcome); capture='natural-result'; stage='result'
            print('LAN_AMBUSH_PRESSURE outcome='..s.outcome..' clock='..s.clock..' enemyCallbackDirected='..incoming.host..'/'..incoming.companion
                ..' fire='..shots.host..'/'..shots.companion..' damage='..s.trainDamage..' protection='..s.protection)
        end
    elseif stage=='result' and file('guest.resultDenied') then
        check(denied>=2 or resumed,'missing guest progression denials')
        if touch then press({x=960/2-130,y=720*.61,w=260,h=58}) else button('return') end
        check(c.runtime.scene=='stop' and not s.active,'checked host continuation failed'); check(Save.flush(1),'final flush failed')
        local disk=assert(Save.read(1)); check(disk.scene=='stop' and not disk.trainAmbush.active and disk.scrap==initialScrap+s.reward,'durable settlement/return mismatch')
        check(disk.players.host.ammo['556']==60-shots.host and disk.players.companion.ammo['556']==60-shots.companion,'exact disk shot costs changed')
        file('host.continued',true); stage='continued'
    elseif stage=='continued' and file('guest.stop') then finish() end
end
local reconnectRequested=false; local reconnectAt
local transient={host_disconnected=true,host_timeout=true,transport_failed=true,send_failed=true,
    join_timeout=true,connection_closed=true,application_closed=true,host_closed=true}
local function guestUpdate()
    local lp=c.ui.localPlay; local v=lp.clientView; local p=v and v.ambush
    if stage=='disconnected' or stage=='rejoining' then
        check(not lp.error or transient[lp.error],'replacement connection failed: '..tostring(lp.error))
    end
    if stage=='disconnected' then
        local expected=file('host.resumed.session')
        if file('host.resumed') and expected and (not restart or file('host-resumed.ready')) then
            menu(); app.draw(); if c.ui.localPlayControls.cancelReconnect then click('cancelReconnect') end
            app.draw(); local rect=c.ui.localPlayControls.join
            check(rect and rect.enabled~=false and c.runtime.state=='slots','replacement Join control unavailable')
            click('join'); check(lp.network and (lp.phase=='joining' or lp.phase=='connected'),'replacement Join did not activate: '..tostring(lp.error))
            reconnectAt=love.timer.getTime(); stage='rejoining'
        end
        return
    end
    if stage=='rejoining' then check(love.timer.getTime()-reconnectAt<45,'replacement scene readiness timed out') end
    if stage=='rejoining' and lp.phase=='connected' and lp.network.sessionId==oldSession and restart and file('host.resumed.session')~=oldSession and not reconnectRequested then
        reconnectRequested=true; menu(); click('leave'); stage='disconnected'; return
    end
    if not v or not v.ready then return end
    if stage=='stop' then
        local frame=lp.motionFrame
        if Checkpoint.returnReady(v,frame,oldClock) then
            check(p and not p:available(),'guest shooter remained available after return')
            returnX=frame.companion.x/1000; returnAt=love.timer.getTime()
            returnHostX,returnHostY=frame.host.x,frame.host.y
            returnFacts=Checkpoint.returnFacts(v.runtime.saveData,limits)
            if touch then
                app.draw(); local stick=v.mobile.joystick; check(stick,'returned stop joystick missing')
                local x,y=coords(stick.x,stick.y); app.touchpressed('return-walk',x,y)
                x,y=coords(stick.x+stick.radius*.95,stick.y); app.touchmoved('return-walk',x,y,0,0)
            else movementKey='d' end
            stage='return-walk'
        end
        return
    elseif stage=='return-walk' then
        local frame=lp.motionFrame
        check(love.timer.getTime()-returnAt<8,'guest could not move after checked return')
        check(frame and frame.host.x==returnHostX and frame.host.y==returnHostY,'guest return walk moved the host')
        check(Checkpoint.returnFacts(v.runtime.saveData,limits)==returnFacts,'guest return walk changed personal kit/health or shared resources')
        if frame and frame.sceneEpoch==v.epoch and frame.ready and frame.companion.x/1000>returnX+3
            and v.runtime.player.x>returnX+3 then
            movementKey=nil; if touch then app.touchreleased('return-walk',0,0) end; v:neutralize()
            capture='returned-stop-fresh-motion'; stage='return-capture'
        end
        return
    elseif stage=='return-capture' then
        local frame=lp.motionFrame
        check(frame and frame.host.x==returnHostX and frame.host.y==returnHostY,'return capture moved the host')
        check(Checkpoint.returnFacts(v.runtime.saveData,limits)==returnFacts,'return capture changed personal/shared resources')
        if captures['returned-stop-fresh-motion'] and not capturePending then file('guest.stop',true); finish() end
        return
    end
    if not p or not p.gun then return end
    local s=v.runtime.saveData.trainAmbush; if not s then return end
    local own=s.shooterSessions and s.shooterSessions.companion
    if stage=='joining' then
        back(); if p:canAct() then firstItem=p.gun.itemId; check(firstItem~=s.weaponSession.itemId,'shared gun identity'); action(p,4,'c'); stage='cover' end
    elseif stage=='cover' and not p.pending and s.defenders.companion.coverProgress==1 then file('guest.covered',true); stage='pressure'
    elseif stage=='pressure' and file('host.pressure') and p:canAct() then action(p,4,'c'); stage='first-shot'
    elseif stage=='first-shot' and p:canAct() and s.defenders.companion.coverProgress==0 then
        if fire(p,s) and p.pending then requestId=p.pending.id; stage='savePending' end
    elseif stage=='savePending' and lp.network.lastCommandResult and lp.network.lastCommandResult.savePending then
        oldClock=s.clock; pendingAt=love.timer.getTime(); file('guest.savePending',true); stage='saveBarrier'
    elseif stage=='saveBarrier' and love.timer.getTime()-pendingAt>.5 then
        check(s.clock==oldClock and p.pending and not p:canAct(),'failed checkpoint did not hold view/commands')
        file('guest.pendingStable',true); stage='saveWait'
    elseif stage=='saveWait' and not p.pending and p.lastOutcome and p.lastOutcome.ok then
        check(v.runtime.saveData.ammo['556']==59,'saved first shot cost changed'); action(p,3,'r'); stage='reload'
    elseif stage=='reload' and not p.pending and own.weaponSession.reloadTimer>0 then
        capture='retained-partial-reload'; stage='leave'
    elseif stage=='leave' and captures['retained-partial-reload'] then
        savedAmmo=v.runtime.saveData.ammo['556']; savedHealth=v.runtime.saveData.health; savedItem=p.gun.itemId
        savedMagazine=own.weaponSession.magazine; savedReload=own.weaponSession.reloadTimer; oldSession=lp.network.sessionId
        menu(); click('leave'); file('guest.left',true); stage='disconnected'
    elseif stage=='rejoining' and lp.phase=='connected' and lp.network.sessionId==file('host.resumed.session') then
        check(not restart or lp.network.sessionId~=oldSession,'host process restart did not change session')
        check(p.gun.itemId==savedItem and v.runtime.saveData.ammo['556']==savedAmmo and v.runtime.saveData.health==savedHealth,'rejoin changed personal identity/ammo/HP')
        check(own.weaponSession.magazine==savedMagazine and own.weaponSession.reloadTimer>0 and own.weaponSession.reloadTimer<=savedReload+1e-10,'rejoin refilled or lost active reload')
        check(not next(p.held) and not next(p.touches),'old input survived reconnect'); back()
        if p:canAct() then file('guest.resumed',true); capture='fresh-session-restored'; stage='pilot' end
    elseif stage=='pilot' and file('host.pilot') then
        if p:canAct() then
            if s.defenders.companion.cover then action(p,4,'c')
            elseif s.defenders.companion.coverProgress==0 and p.gun.reloadTimer==0 and p.gun.cooldown==0 and love.timer.getTime()-lastFire>.2 then
                if p.gun.magazine==0 then action(p,3,'r') elseif fire(p,s) and p.pending then lastFire=love.timer.getTime() end
            end
        end
        if s.phase=='result' and file('host.result') then
            oldClock=v.epoch; requestId=assert(lp.network:submitCommand('ambush.continue',{},v.epoch,{})); stage='deny-result'
        end
    elseif stage=='deny-result' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        capture='natural-result-host-only'
        check(lp.network.lastCommandResult.reason=='host_only' and v.epoch==oldClock and s.active,'guest result progression allowed')
        requestId=assert(lp.network:submitCommand('ambush.withdraw',{},v.epoch,{})); stage='deny-withdraw'
    elseif stage=='deny-withdraw' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        check(lp.network.lastCommandResult.reason=='host_only','guest withdrawal allowed'); file('guest.resultDenied',true); stage='stop'
    end
end
local function update(dt)
    if finished then return end; app.update(math.min(.1,dt))
    if role=='host' then hostUpdate() else guestUpdate() end
    if love.timer.getTime()-lastReport>4 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay
        local s=role=='host' and c.runtime.saveData.trainAmbush or lp.clientView and lp.clientView.runtime.saveData.trainAmbush
        local view=lp.clientView; local frame=lp.motionFrame
        print('LAN_AMBUSH_NORMAL_STAGE role='..role..' stage='..tostring(stage)..' link='..tostring(lp.phase)..' phase='..tostring(s and s.phase)
            ..' active='..tostring(s and s.active)..' scene='..tostring(role=='host' and c.runtime.scene or view and view.runtime.scene)
            ..' epoch='..tostring(role=='host' and c.runtime.saveData.coop.sceneEpoch or view and view.epoch)
            ..' motionReady='..tostring(frame and frame.ready)..' clock='..tostring(s and s.clock)..' error='..tostring(lp.error))
    end
    check(love.timer.getTime()-started<150,'normal fixture timed out at '..tostring(stage))
end
local function guarded(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
        if oldKeyboard then love.keyboard.isDown=oldKeyboard end
        print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if not finished and app then guarded(function()
        app.draw()
        if capture and not captures[capture] and not capturePending then
            local name=capture; capture=nil; capturePending=true
            love.graphics.captureScreenshot(function(pixels)
                guarded(function()
                    local path=role..'-'..name..'.png'
                    pixels:encode('png',path)
                    local info=love.filesystem.getInfo(path)
                    check(info and info.type=='file' and info.size>0,'capture PNG was not saved: '..path)
                    captures[name]=true; capturePending=false
                end)
            end)
        end
    end) end
end
