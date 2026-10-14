-- Representative ordinary Stop35 boss, not every boss route. Initial level8
-- kits/wounded companion and deterministic saved RNG are explicit preconditions.
-- No board/HP/accuracy/AI/RNG/turn/timer edits occur after the initial campaign.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_BOSS_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_BOSS_RESUMED')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema'); local Players=require('game.coop_players')
local Codec=require('game.net.codec'); local Receipts=require('game.coop_receipts')
local Rules=require('game.battle_rules'); local Actors=require('game.battle_actors'); local Grid=require('game.battle_grid')
local Balance=require('game.combat_balance'); local Viewport=require('game.viewport'); local Style=require('game.ui_layout')
local WorldView=require('game.world_view'); local Fixture=require('boss_fixture')
local app,c,stage,started,finished,restoreWrite,oldKeyboard,movementKey
local capture,capturePending; local captures={}; local lastInput=0; local lastReport=0
local metrics={incoming=0,shots={host=0,companion=0},heals={host=0,companion=0},moves={host=0,companion=0}}
local previousHP={}; local oldSession,rejoinAt,replacementAt; local rejoinAttempts=0; local requestId,denialAt
local pendingAt,enemyCount,initialXp,baselineScrap,baselineCoal,initialItems
local returnEpoch,returnX,returnHostX,returnHostY,returnOwnership,walkAt
local limits={maxBytes=131072,maxDepth=20,maxEntries=8192,maxStringBytes=2048}
local function check(value,message) assert(value,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function button(key) app.keypressed(key); app.keyreleased(key); lastInput=love.timer.getTime() end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function press(rect)
    check(rect and rect.enabled~=false,'production control unavailable at '..tostring(stage))
    local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('boss-control',x,y); app.touchreleased('boss-control',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
    lastInput=love.timer.getTime()
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(name,text) app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); button('return') end end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function ready(lp)
    return Fixture.ready(lp)
end
local function photo(name) check(not capture and not capturePending,'overlapping captures'); capture=name end
local function cell(q,r)
    local x,y=Grid.boardToScreen(1,q,r)
    if role=='guest' then x,y=c.ui.localPlay.clientView.battles.worldView.toScreen(x,y) else x,y=WorldView.toScreen(x,y) end
    press(Style.transformRectFor('battle',{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0}))
end
local function hostControl(name)
    app.draw()
    if not c.ui[name] and touch then
        local controls=c.getMobileControls(); press(Style.transformRectFor('mobileControls',controls:uiBounds(),controls.menu)); app.draw()
    end
    press(c.ui[name])
end
local function hostEntry()
    local lp=c.ui.localPlay; lp.port=port; c.runtime.state='slots'; menu(); click('host')
    check(lp.hostingIntent=='selecting','real saved-host intent absent'); app.draw(); press(c.ui.slots[1])
    check(lp.network and c.session.networkMode=='host' and c.runtime.selectedSlot==1,'real saved-slot hosting failed '..tostring(lp.error)); back()
end
local function unit(data,id)
    local b=data.tacticalBattle and data.tacticalBattle.battle
    for _,u in ipairs(b and b.units or {}) do if Actors.id(u)==id then return u end end
end
local function auditCommand(id,name,args,invoke)
    local data=c.runtime.saveData; local actor=data.players[id]; local beforeAmmo=actor.ammo['556']; local beforeHP=actor.health
    local u=unit(data,id); local q,r=u and u.q,u and u.r
    local reply=invoke()
    if reply and reply.ok then
        actor=data.players[id]; u=unit(data,id)
        local rounds=beforeAmmo-actor.ammo['556']; check(rounds>=0 and rounds<=1,'command changed unexpected owned ammunition')
        metrics.shots[id]=metrics.shots[id]+rounds
        if name=='battle.heal' and actor.health>beforeHP then metrics.heals[id]=metrics.heals[id]+1 end
        if name=='battle.move' and u and (u.q~=q or u.r~=r) then metrics.moves[id]=metrics.moves[id]+1 end
    end
    return reply
end
local function installObservation(lp)
    local submit=lp.context.commands.submit
    lp.context.commands.submit=function(name,args) return auditCommand('host',name,args,function() return submit(name,args) end) end
    local command=lp.network.context.command
    lp.network.context.command=function(generation,request)
        local reply=auditCommand('companion',request.command,request.args,function() return command(generation,request) end)
        if request.command=='battle.begin' or request.command=='battle.continue' or request.command=='battle.retreat' then
            check(not reply.ok and reply.reason=='host_only','guest progressed boss story')
        end
        return reply
    end
    if not resumed then
        restoreWrite=love.filesystem.write
        love.filesystem.write=function(path,...)
            local pending=lp.authority.pendingSave; local data=c.runtime.saveData
            local receipt=pending and pending.actorId and Receipts.find(data,pending.actorId,lp.authority.sessionId,pending.requestId)
            local request=receipt and Codec.decode(receipt.fingerprint,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128})
            local b=data.tacticalBattle and data.tacticalBattle.battle
            if path==Save.path(1)..'.tmp' and request and request.command:match('^battle%.')
                and request.command~='battle.continue' and request.command~='battle.retreat' and b and b.finished=='win' then
                file('victory.failed',true); return false,'normal boss victory checkpoint failure'
            end
            return restoreWrite(path,...)
        end
    end
end
local function load()
    started=love.timer.getTime(); lastReport=started
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(key,...) if movementKey and key==movementKey then return true end; return oldKeyboard(key,...) end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        if not resumed then
            Save.remove(1); c.runtime.selectedSlot=1
            local draft=c.newSave(c.characters[1]); draft.location=Fixture.STOP; draft.scene='train'; draft.stopped=true; draft.passengers={}
            draft.events[tostring(Fixture.STOP)]={id='resolved'}; draft.coop.randomState=583921; draft.resources.coal=0
            check(c.enterGame(draft),'initial boss campaign failed'); Fixture.kit(c.runtime.saveData,'host',c.catalog,false)
            check(Schema.validate(c.runtime.saveData) and Save.write(1,c.runtime.saveData),'initial owned boss kit invalid')
            c.runtime.saveData=nil; c.runtime.selectedSlot=nil
            local place=lp.context.placeCompanion
            lp.context.placeCompanion=function(data)
                local ok,reason=place(data); if not ok then return ok,reason end
                Fixture.kit(data,'companion',c.catalog,true); return true
            end
        else check(Fixture.privateSignature(assert(Save.read(1)))==file('resume.expected'),'fresh-process boss checkpoint changed') end
        hostEntry()
        if resumed then
            check(Fixture.privateSignature(c.runtime.saveData)==file('resume.expected'),'saved-slot replayed settled boss')
            check(c.runtime.state=='battle' and c.runtime.battle.finished=='win','saved natural result was not restored')
            check(lp.authority.sessionId~=file('resume.session'),'host process reused session')
            metrics=assert(Fixture.metrics(file('resume.metrics')),'incomplete settled boss metrics'); initialItems=assert(Codec.decode(file('initial.items'),limits))
            enemyCount=tonumber(file('initial.enemyCount')); baselineScrap=tonumber(file('initial.scrap')); baselineCoal=tonumber(file('initial.coal'))
            initialXp=assert(Codec.decode(file('initial.xp'),limits)); file('host.resumed.session',lp.authority.sessionId); stage='resumed'
        else stage='hosting' end
        installObservation(lp); print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; menu(); click('address','127.0.0.1:'..port); click('name','Boss companion'); click('join')
        check(lp.network and lp.phase=='joining','initial Join failed '..tostring(lp.error)); stage='joining'
    end
end
local function pilot(data,b,id,ui)
    if not Fixture.quiet(b) or b.finished or love.timer.getTime()-lastInput<.65 then return end
    local decision=Fixture.plan(data,b,id,c.catalog,metrics.incoming>0,id=='companion' and metrics.heals.companion==0,metrics.moves[id]==0)
    if not decision then return end
    app.draw()
    if decision.kind=='heal' then press(ui.battleHeal)
    elseif decision.kind=='guard' then press(ui.battleGuard)
    elseif decision.kind=='endTurn' then press(ui.battleEnd)
    elseif decision.kind=='weapon' then press(ui.battleWeapons[decision.index])
    elseif decision.kind=='target' then cell(decision.q,decision.r)
    elseif decision.kind=='move' then press(ui.battleMove); cell(decision.q,decision.r) end
end
local function verifyRewards(data)
    local profile=Balance.rewardProfile('hard',enemyCount,false,true)
    local trait=data.players.host.trait or {}; local multiplier=trait.reward or 1
    local scrap=data.scrap-baselineScrap
    check(scrap>=math.floor(profile.scrapMin*multiplier)+(trait.scrapBonus or 0)
        and scrap<=math.floor(profile.scrapMax*multiplier)+(trait.scrapBonus or 0),'original boss scrap reward changed')
    check(data.resources.coal-baselineCoal>=profile.coalMin and data.resources.coal-baselineCoal<=profile.coalMax,'original boss coal reward changed')
    for _,id in ipairs({'host','companion'}) do
        local actor=data.players[id]
        check(actor.stats.level==Fixture.LEVEL and actor.stats.xp==initialXp[id]+profile.xp,'boss XP repeated or charged wrong actor')
        check(actor.ammo['556']==Fixture.AMMO-metrics.shots[id] and metrics.shots[id]>0,'owned boss shot cost mismatch')
        check(actor.itemSlots.equipment[2].id==initialItems[id].id
            and actor.itemSlots.equipment[2].durability==initialItems[id].durability-metrics.shots[id],'boss replaced owned gun or charged wrong wear')
    end
    check(data.encounters[tostring(Fixture.STOP)].resolved and metrics.incoming>0 and metrics.moves.companion>0
        and metrics.heals.companion>0,'normal enemy pressure/guest moves/heal or settlement missing')
end
local function finish()
    if finished then return end; finished=true; movementKey=nil
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    if oldKeyboard then love.keyboard.isDown=oldKeyboard end
    check(app.quit()~=true,'boss quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true bossPressure=true stop=35 originalBossHP=true normalAI=true'
        ..' naturalWin=true victorySaveRetry=true rewardOnce=true hostOnlyContinue=true diskResume='..tostring(restart)
        ..' input='..(touch and 'touch' or 'desktop')); love.event.quit(0)
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local b=c.runtime.battle
    if lp:pending() then menu(); click('approve'); check(not lp.error,'boss admission failed '..tostring(lp.error)); back() end
    if b then for _,u in ipairs(b.units) do if Actors.id(u) then
        if previousHP[u.id] and u.hp<previousHP[u.id] then metrics.incoming=metrics.incoming+previousHP[u.id]-u.hp end
        previousHP[u.id]=u.hp
    end end end
    if stage=='hosting' and file('guest.initial.ready') then
        initialXp={host=data.players.host.stats.xp,companion=data.players.companion.stats.xp}
        initialItems={}; for _,id in ipairs({'host','companion'}) do local item=data.players[id].itemSlots.equipment[2]
            initialItems[id]={id=item.id,durability=item.durability} end
        baselineScrap,baselineCoal=data.scrap,data.resources.coal
        file('initial.xp',assert(Codec.encode(initialXp,limits))); file('initial.items',assert(Codec.encode(initialItems,limits)))
        file('initial.scrap',baselineScrap); file('initial.coal',baselineCoal)
        back(); hostControl('leaveTrain'); b=c.runtime.battle
        check(b and b.intro and data.encounters[tostring(Fixture.STOP)].boss,'actual Leave Train did not roll/start boss')
        enemyCount=Fixture.normalRoster(data); file('initial.enemyCount',enemyCount)
        photo('host-normal-boss-roster.png'); file('host.playing',true); stage='playing'
    elseif stage=='playing' then
        check(b and b.finished~='loss','normal boss pilot lost')
        if lp.authority.pendingSave and b.finished=='win' then
            check(file('victory.failed'),'natural victory write failure absent')
            local old=assert(Save.read(1)); check(old.scrap==baselineScrap and old.players.host.stats.xp==initialXp.host,'failed victory appeared on disk')
            verifyRewards(data); file('host.victory.pending',true); pendingAt=love.timer.getTime()
            photo('host-natural-boss-victory-retry.png'); stage='victory-retry'
        elseif not capturePending and not capture then pilot(data,b,'host',c.ui) end
    elseif stage=='victory-retry' and captures['host-natural-boss-victory-retry.png'] and file('guest.victory.wait') and love.timer.getTime()-pendingAt>.5 then
        love.filesystem.write=restoreWrite; restoreWrite=nil
        if touch then press({x=190,y=438,w=185,h=58}) else button('r') end
        check(not lp.authority.pendingSave and not c.session.checkpointPending,'actual Retry failed natural boss rewards')
        verifyRewards(data); file('host.victory.saved',true); stage='settled'
    elseif stage=='settled' and Fixture.quiet(b) and file('guest.victory.ready') then
        verifyRewards(data); menu(); check(lp.authority:checkpointNow(),'natural boss result checkpoint failed')
        local disk=assert(Save.read(1)); verifyRewards(disk)
        check(Fixture.privateSignature(data)==Fixture.privateSignature(disk),'durable boss result differs from live result')
        file('resume.expected',Fixture.privateSignature(disk)); file('resume.public',Fixture.publicSignature(disk))
        file('resume.session',lp.authority.sessionId); file('resume.metrics',assert(Codec.encode(metrics,limits)))
        file('campaign.id',disk.coop.network.campaignId); file('companion.id',disk.coop.network.companionId)
        file('host.restart.saved',true); back(); photo('host-settled-boss-result.png'); stage='restart'
    elseif stage=='restart' and captures['host-settled-boss-result.png'] and file('guest.restart.ready') then
        if restart then
            check(app.quit()~=true,'boss restart quit cancelled'); finished=true
            print('LAN_SMOKE_RESTART role=host bossSaved=true naturalWin=true rewardOnce=true'); love.event.quit(42)
        else file('host.resumed.session',lp.authority.sessionId); stage='resumed' end
    elseif stage=='resumed' and file('guest.resumed') then
        verifyRewards(data); back(); app.draw(); press(c.ui.battleContinue)
        check(not data.tacticalBattle and data.scene=='stop' and c.runtime.scene=='stop','actual host Continue did not return party to stop')
        verifyRewards(data); check(lp.authority:checkpointNow(),'post-boss continuation checkpoint failed')
        verifyRewards(assert(Save.read(1))); file('host.continued',true); stage='continued'
    elseif stage=='continued' and file('guest.stop') then verifyRewards(data); finish() end
end
local transient={host_disconnected=true,host_timeout=true,transport_failed=true,send_failed=true,join_timeout=true,
    connection_closed=true,application_closed=true,host_closed=true}
local function guestUpdate()
    local lp=c.ui.localPlay; local v=lp.clientView
    if stage=='restart-wait' then
        check(not lp.error or transient[lp.error],'boss replacement failed '..tostring(lp.error))
        local expected=file('host.resumed.session')
        if expected and lp.network and lp.network.sessionId==expected and v and v.ready then back() end
        if expected and ready(lp) and lp.network.sessionId==expected then
            check(not restart or expected~=oldSession,'new host reused old boss session')
            check(lp.network.campaignId==file('campaign.id') and lp.network.credential.companionId==file('companion.id'),'boss rejoin replaced membership')
            check(Fixture.publicSignature(lp.replica.data)==file('resume.public'),'rejoin changed settled boss/owned reward')
            photo('guest-settled-boss-rejoined.png'); returnEpoch=v.epoch; stage='resume-capture'
        elseif expected then
            replacementAt=replacementAt or love.timer.getTime()
            check(love.timer.getTime()-replacementAt<60,'boss replacement never reached fresh ready scene: phase='..tostring(lp.phase)
                ..' status='..tostring(lp.network and lp.network.status)..' session='..tostring(lp.network and lp.network.sessionId))
            if not rejoinAt or love.timer.getTime()-rejoinAt>3 then
                menu(); app.draw()
                local action=Fixture.rejoinAction(lp,expected,c.ui.localPlayControls)
                if action=='leave' then click('leave') -- This closes the menu; reopen on the next update.
                elseif action=='cancelReconnect' then
                    if c.ui.localPlayControls.cancelReconnect then click('cancelReconnect') end
                elseif action=='join' then
                    check(rejoinAttempts<3,'boss replacement join attempts exhausted')
                    click('join'); check(lp.network and (lp.phase=='joining' or lp.phase=='connected'),'boss Join did not activate '..tostring(lp.error))
                    rejoinAt=love.timer.getTime(); rejoinAttempts=rejoinAttempts+1
                end
            end
        end
        return
    end
    check(not lp.error,'boss Local Play error '..tostring(lp.error))
    if not v or not v.ready then return end
    if stage=='resume-capture' then
        if captures['guest-settled-boss-rejoined.png'] then file('guest.resumed',true); stage='return' end
        return
    end
    if stage=='joining' then back(); if ready(lp) then file('guest.initial.ready',true); stage='playing' end; return end
    local data=v.runtime.saveData; local b=v.runtime.battle
    if stage=='playing' then
        if file('host.victory.pending') then file('guest.victory.wait',true); stage='victory-wait'; return end
        if b and not v.battles.pending and not capturePending and not capture then
            -- Another process can observe an empty/truncated wb write. Only
            -- adopt a complete validated proof snapshot; keep the last one.
            metrics=Fixture.adoptMetrics(file('natural.metrics'),metrics)
            local current=Rules.activeUnit(b)
            if current and v.battles:canAct(current) then
                pilot(data,b,'companion',v.ui)
            end
        end
    elseif stage=='victory-wait' and file('host.victory.saved') and b and b.finished=='win' and not v.battles.pending then
        check(data.encounters[tostring(Fixture.STOP)].resolved,'guest victory lacks resolved original encounter')
        photo('guest-natural-boss-victory.png')
        requestId=assert(lp.network:submitCommand('battle.continue',{},v.epoch,{})); denialAt=love.timer.getTime(); stage='deny-continue'
    elseif stage=='deny-continue' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        local result=lp.network.lastCommandResult
        check(result.reason=='host_only','guest boss Continue was not rejected')
        check(b and b.finished=='win' and data.tacticalBattle and v.runtime.state=='battle','guest denial progressed the result')
        if love.timer.getTime()-denialAt>.55 then
            requestId=assert(lp.network:submitCommand('battle.retreat',{},v.epoch,{})); stage='deny-retreat'
        end
    elseif stage=='deny-retreat' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
        check(lp.network.lastCommandResult.reason=='host_only','guest boss Retreat was not rejected')
        file('guest.victory.ready',true); stage='checkpoint'
    elseif stage=='checkpoint' and file('host.restart.saved') and not capturePending and not capture then
        check(Fixture.publicSignature(lp.replica.data)==file('resume.public'),'guest final boss baseline differs')
        oldSession=lp.network.sessionId; file('guest.restart.ready',true); stage='restart-wait'
    elseif stage=='return' and ready(lp) and data.scene=='stop' and not data.tacticalBattle and v.epoch>returnEpoch and file('host.continued') then
        local f=lp.motionFrame; check(v:inputAllowed(),'guest ordinary input remains blocked after boss')
        returnX=f.companion.x/1000; returnHostX,returnHostY=f.host.x,f.host.y
        returnOwnership=Fixture.encode({host=Fixture.ownership(data.players.host),guest=Fixture.ownership(data.players.companion),resources=data.resources,scrap=data.scrap})
        if touch then
            app.draw(); local stick=v.mobile.joystick; local x,y=coords(stick.x,stick.y); app.touchpressed('boss-walk',x,y)
            x,y=coords(stick.x+stick.radius*.95,stick.y); app.touchmoved('boss-walk',x,y,0,0)
        else movementKey='d' end
        walkAt=love.timer.getTime(); stage='walk'
    elseif stage=='walk' then
        local f=lp.motionFrame; check(love.timer.getTime()-walkAt<8,'guest cannot move after natural boss return')
        check(f.host.x==returnHostX and f.host.y==returnHostY,'guest walk moved host')
        check(Fixture.encode({host=Fixture.ownership(data.players.host),guest=Fixture.ownership(data.players.companion),resources=data.resources,scrap=data.scrap})==returnOwnership,'return walk changed kit/rewards')
        if f.companion.x/1000>returnX+3 and v.runtime.player.x>returnX+3 then
            movementKey=nil; if touch then app.touchreleased('boss-walk',0,0) end; v:neutralize()
            photo('guest-natural-boss-returned-stop.png'); stage='stop-capture'
        end
    elseif stage=='stop-capture' and captures['guest-natural-boss-returned-stop.png'] then file('guest.stop',true); finish() end
end
local function update(dt)
    if finished then return end
    if c.ui.localPlay.focused==false then app.focus(true) end
    app.update(math.min(.05,dt))
    if role=='host' then
        file('natural.metrics',assert(Codec.encode(metrics,limits))); hostUpdate()
    else guestUpdate() end
    if love.timer.getTime()-lastReport>5 then
        lastReport=love.timer.getTime(); local lp=c.ui.localPlay; local r=role=='host' and c.runtime or lp.clientView and lp.clientView.runtime
        local b=r and r.battle; local u=b and Rules.activeUnit(b)
        print('LAN_BOSS_STAGE role='..role..' stage='..tostring(stage)..' round='..tostring(b and b.round)..' active='..tostring(u and u.id)
            ..' result='..tostring(b and b.finished)..' incoming='..metrics.incoming..' shots='..metrics.shots.host..'/'..metrics.shots.companion
            ..' error='..tostring(lp.error)..' pending='..tostring(role=='host' and lp.authority.pendingSave~=nil or lp.network and lp.network.pendingCommand~=nil))
        if stage=='restart-wait' then print('LAN_BOSS_REJOIN phase='..tostring(lp.phase)..' status='..tostring(lp.network and lp.network.status)
            ..' session='..tostring(lp.network and lp.network.sessionId)..' menu='..tostring(lp.menuOpen)..' attempts='..rejoinAttempts) end
    end
    check(love.timer.getTime()-started<330,'normal boss deadline at '..tostring(stage))
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
        if oldKeyboard then love.keyboard.isDown=oldKeyboard end
        print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' '..tostring(reason)); finished=true; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not capturePending then
            local name=capture; capture=nil; capturePending=true
            love.graphics.captureScreenshot(function(pixels) guarded(function()
                local bytes=pixels:encode('png'); check(file(name,bytes:getString()),'boss PNG write failed')
                check(#assert(file(name))>0,'boss PNG not confirmed'); captures[name]=true; capturePending=false
            end) end)
        end
    end)
end
function love.focus(focused) if app then app.focus(focused) end end
