-- Normal ordinary combat action matrix. Only the initial isolated campaign,
-- encounter selection and owned kits are seeded. No combat HP, board, obstacles,
-- AI, RNG, animation timers or turn state are changed by this fixture.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_BATTLE_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_BATTLE_RESUMED')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema')
local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Commands=require('game.coop_battles'); local Rules=require('game.battle_rules')
local Grid=require('game.battle_grid'); local Inventory=require('game.inventory')
local Style=require('game.ui_layout'); local Viewport=require('game.viewport'); local Codec=require('game.net.codec')
local Receipts=require('game.coop_receipts')
local Checkpoint=require('checkpoint')
local app,c,stage,started,finished,capture,restoreWrite,actionId,actionName,actionAfter
local captured={}; local lastInput=0; local reportAt=0; local oldSession
local hostGuarded=false; local priorHP={}; local incomingDamage=0; local moves=0
local hostEnded=false
local initialHost,initialGuest; local guestShot=false; local denialId; local denialIndex=1
local denials={'battle.begin','battle.retreat','battle.continue'}
local shotTarget
local reconnectAt,reconnectAttempts=0,0
local movementKey,oldKeyboard,battleMotion,returnMotion,returnY,returnHost,returnOwnership,returnWalkAt
local function check(v,message) assert(v,message) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local encode,ownership,signature=Checkpoint.encode,Checkpoint.ownership,Checkpoint.privateSignature
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('control',x,y); app.touchreleased('control',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
    lastInput=love.timer.getTime()
end
local function key(key) app.keypressed(key); app.keyreleased(key); lastInput=love.timer.getTime() end
local function menu() if not c.ui.localPlay.menuOpen then key('f8') end end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name]); if text then app.textinput(text); key('return') end
end
local function closeMenu() if c.ui.localPlay.menuOpen then click('close') end end
local function cell(q,r)
    local x,y=Grid.boardToScreen(1,q,r); local view=c.ui.localPlay.clientView
    if role=='guest' then x,y=view.battles.worldView.toScreen(x,y) end
    press(Style.transformRectFor('battle',{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0}))
end
local function slot(ref)
    local rect=ref.kind=='equipment' and (touch and Inventory.mobileEquipmentSlotRect(ref.index) or Inventory.equipmentSlotRect(ref.index))
        or (touch and Inventory.mobileInventorySlotRect(ref.index) or Inventory.inventorySlotRect(ref.index))
    return Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect)
end
local function drag(from,to)
    local a,b=slot(from),slot(to); local x,y=coords(a.x+a.w/2,a.y+a.h/2); local nx,ny=coords(b.x+b.w/2,b.y+b.h/2)
    if touch then app.touchpressed('gear',x,y); app.touchmoved('gear',nx,ny); app.touchreleased('gear',nx,ny)
    else app.mousepressed(x,y,1,false); app.mousemoved(nx,ny); app.mousereleased(nx,ny,1,false) end
    lastInput=love.timer.getTime()
end
local function stable(b)
    if not b or b.finished or b.intro or b.projectile or (b.attackTimer or 0)>0 or (b.enemyDelay or 0)>0 then return false end
    for _,u in ipairs(b.units) do if (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 or u.moveAnim then return false end end
    return true
end
local function nearest(b,u)
    local result; for _,enemy in ipairs(b.units) do
        if enemy.team=='enemy' and enemy.hp>0 and (not result or Rules.distance(u,enemy)<Rules.distance(u,result)) then result=enemy end
    end; return result
end
local function finish()
    if finished then return end; finished=true
    movementKey=nil; if oldKeyboard then love.keyboard.isDown=oldKeyboard end
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true battles=true actionMatrix=true normalBoard=true normalEnemyAI=true'
        ..' outcome=retreat diskResume='..tostring(restart)..' input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function hostCommands(lp)
    local original=lp.network.context.command
    lp.network.context.command=function(generation,request)
        local reply=original(generation,request)
        print('LAN_BATTLE_COMMAND id='..request.requestId..' name='..request.command..' ok='..tostring(reply and reply.ok)
            ..' durable='..tostring(reply and reply.durable)..' reason='..tostring(reply and reply.reason))
        if request.command=='battle.begin' or request.command=='battle.retreat' or request.command=='battle.continue' then
            check(not reply.ok and reply.reason=='host_only','guest story command accepted')
        end
        return reply
    end
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10132026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for index=1,select('#',...) do if select(index,...)==movementKey then return true end end
        return oldKeyboard(...)
    end
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        if resumed then
            check(signature(assert(Save.read(1)))==file('battle-resume.expected'),'fresh process changed durable combat/owned items')
        else
            Save.remove(1); c.runtime.selectedSlot=1
            local draft=c.newSave(c.characters[1]); draft.location=2; draft.scene='stop'; draft.stopped=true; draft.passengers={}
            draft.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
            local entered,reason=c.enterGame(draft); check(entered,'initial canonical seed failed: '..tostring(reason)); local data=c.runtime.saveData
            data.scene='stop'; data.location=2; data.stopped=true; c.runtime.scene='stop'; c.runtime.state='game'; c.ensureStopLayout()
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',
                mobFiles={c.catalog.mobTiers.easy[1],c.catalog.mobTiers.easy[2]}}
            Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=20
            Items.write(data,nil,{kind='inventory',index=1},'field-bandage-roll')
            check(require('game.coop_entities').ensure(data),'entity seed failed'); check(Items.ensure(data),'owned kit seed failed')
            check(Schema.validate(data),'canonical seed invalid'); check(Save.write(1,data),'initial save failed')
            file('base.goodwill',data.goodwill); file('base.scrap',data.scrap)
            c.runtime.saveData=nil; c.runtime.selectedSlot=nil
            local place=lp.context.placeCompanion
            lp.context.placeCompanion=function(campaign)
                local ok,reason=place(campaign); if not ok then return ok,reason end
                local actor=Players.forActor(campaign,'companion'); actor.health=math.min(12,actor.maxHealth-8)
                for index=1,(actor.inventoryCapacity or 6) do Items.write(actor,nil,{kind='inventory',index=index},nil) end
                Items.write(actor,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); actor.ammo['22lr']=9
                Items.write(actor,nil,{kind='inventory',index=1},'field-bandage-roll')
                Items.write(actor,nil,{kind='inventory',index=2},'green-regeneration-vial')
                check(Items.ensure(campaign),'companion kit seed failed'); return true
            end
        end
        lp.port=port; c.runtime.state='slots'; menu(); click('saveSlot'); click('slot_1'); click('host')
        check(lp.network and c.session.networkMode=='host','real saved-slot hosting entry failed'); menu(); hostCommands(lp)
        if resumed then
            check(c.runtime.state=='battle','real saved-slot entry did not restore tactical state')
            check(signature(c.runtime.saveData)==file('battle-resume.expected'),'slot entry replayed combat/owned costs')
            local prior=assert(file('battle-old-session'),'previous host session was not recorded')
            local current=assert(lp.authority.sessionId,'replacement host has no authority session')
            print('LAN_BATTLE_HOST_SESSION previous='..prior..' current='..current)
            check(current~=prior,'fresh host reused old session')
            file('actions-host.session',current); file('host-resumed.ready','ready')
        end
        stage=resumed and 'resume-wait' or 'hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; menu(); click('address','127.0.0.1:'..port); click('name','Battle friend')
        local allowed={heal=true,nourish=true,repair=true,rally=true,protect=true,haste=true,disarm=true}
        local character; for _,file in ipairs(c.characters) do if allowed[c.catalog.characterAbility(file).kind] then character=file; break end end
        check(character,'no support traveler available')
        local own=c.newSave(character); own.health=math.min(12,own.maxHealth-8)
        Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); own.ammo['22lr']=9
        Items.write(own,nil,{kind='inventory',index=1},'field-bandage-roll')
        Items.write(own,nil,{kind='inventory',index=2},'green-regeneration-vial')
        check(Save.write(1,own),'guest selected slot seed failed')
        click('saveSlot'); click('slot_1'); click('join'); stage='joining'
    end
end
local function denied(name,data)
    local s=data.tacticalBattle; local args={encounterId=s and s.encounterId or data.encounters['2'].entityId}
    if s then args.turnRevision=s.revision end
    return assert(c.ui.localPlay.network:submitCommand(name,args,data.coop.sceneEpoch,{}))
end
local function startAction(name,after,fn,view)
    local now=love.timer.getTime(); if now-lastInput<.65 then return false end
    fn(); local p=view.battles.pending
    if not p then return false end
    actionId,actionName,actionAfter=p.id,name,after; stage='action'; return true
end
local function completeAction(view,data)
    local result=view.battles.lastOutcome
    if view.battles.pending or not result or result.requestId~=actionId then return end
    if not result.ok then
        check(({rate_limited=true,stale_revision=true,stale_turn=true,battle_busy=true})[result.reason],
            actionName..' failed '..tostring(result.reason))
        stage=actionName=='approach-end' and 'weapon' or actionName; return
    end
    check(result.durable==true,'action presented before durable receipt')
    file('accepted-'..actionName,'true'); stage=actionAfter
    local own=data.players.companion
    if actionName=='heal' then
        check(not own.inventory[1] and own.health==initialGuest.health+5,'heal used wrong owned item/effect')
        check(data.players.host.inventory[1]=='field-bandage-roll','guest heal consumed host medicine')
    elseif actionName=='potion' then check(not own.inventory[2],'potion did not consume owned vial')
    elseif actionName=='ability' then check(view.runtime.battle.abilitiesUsed['player:companion'],'owned ability not committed')
    elseif actionName=='shot' then
        guestShot=true; check(own.ammo['22lr']==8 and data.players.host.ammo['22lr']==20,'shot charged wrong actor')
        check(own.itemSlots.equipment[2].id==initialGuest.itemSlots.equipment[2].id,'shot replaced owned weapon')
        check(own.itemSlots.equipment[2].durability==initialGuest.itemSlots.equipment[2].durability-1,'shot wear not exact')
        capture='guest-normal-battle-shot.png'
    end
end
local function joinReplacement(lp)
    local now=love.timer.getTime()
    check(reconnectAttempts<3,'replacement host reconnect attempts exhausted: '..tostring(lp.error))
    print('LAN_BATTLE_REJOIN_REQUEST phase='..tostring(lp.phase)..' error='..tostring(lp.error)
        ..' runtime='..tostring(c.runtime.state)..' network='..tostring(lp.network~=nil))
    menu(); app.draw()
    -- Cancel a pending convenience retry through its actual menu control before
    -- one explicit Join. Do not overlap a live Session with another join.
    if c.ui.localPlayControls.cancelReconnect then click('cancelReconnect') end
    app.draw(); local rect=c.ui.localPlayControls.join
    check(rect and rect.enabled~=false and c.runtime.state=='slots','replacement Join control not available')
    click('join'); reconnectAttempts=reconnectAttempts+1; reconnectAt=now
    check(lp.network and (lp.phase=='joining' or lp.phase=='connected'),'replacement Join did not start: '..tostring(lp.error))
end
local function walkReturned(view)
    if touch then
        app.draw(); local stick=view.mobile.joystick; local x,y=coords(stick.x,stick.y)
        app.touchpressed('return-walk',x,y)
        x,y=coords(stick.x,stick.y-stick.radius*.95); app.touchmoved('return-walk',x,y,0,0)
    else movementKey='w' end
end
local function stopReturned(view)
    movementKey=nil
    if touch then app.touchreleased('return-walk',0,0) end
    view:neutralize()
end
local function hostUpdate()
    local lp=c.ui.localPlay; local data=c.runtime.saveData; local b=c.runtime.battle
    if lp:pending() then menu(); click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
    if b then
        for _,u in ipairs(b.units) do if u.actorId then
            if priorHP[u.id] and u.hp<priorHP[u.id] then incomingDamage=incomingDamage+priorHP[u.id]-u.hp end
            priorHP[u.id]=u.hp
        end end
        if incomingDamage>0 then file('natural-incoming.damage',incomingDamage) end
    end
    if stage=='hosting' and file('guest.denials') then
        closeMenu(); check(c.beginEncounter(data.encounters['2']),'actual host encounter entry failed')
        b=c.runtime.battle; check(#b.units==4 and b.intro~=nil,'normal encounter roster/intro missing')
        initialHost=encode(ownership(data.players.host)); file('host.owned.initial',initialHost)
        -- Fail only the actual owned healing receipt. Other critical saves pass.
        restoreWrite=love.filesystem.write
        love.filesystem.write=function(path,...)
            local pending=lp.authority.pendingSave; local receipt=pending and Receipts.find(data,pending.actorId,lp.authority.sessionId,pending.requestId)
            local request=receipt and Codec.decode(receipt.fingerprint,{maxBytes=1600,maxDepth=8,maxEntries=100,maxStringBytes=128})
            if path==Save.path(1)..'.tmp' and pending and pending.actorId=='companion' and request and request.command=='battle.heal' then
                return false,'injected owned heal save failure'
            end
            return restoreWrite(path,...)
        end
        capture='host-normal-battle-board.png'; stage='playing'
    elseif stage=='playing' then
        check(b and not b.finished,'normal encounter ended before action matrix '..tostring(b and b.finished))
        if lp.authority.pendingSave then
            check(not data.players.companion.inventory[1] and data.players.host.inventory[1]=='field-bandage-roll','checkpoint changed wrong medicine')
            love.filesystem.write=restoreWrite; restoreWrite=nil; capture='host-owned-heal-retry.png'; stage='retry'
        elseif file('guest.matrix.complete') and incomingDamage>0 and stable(b) and b.units[b.active].actorId=='host' then
            app.draw(); capture='host-normal-battle-pressure.png'; stage='pressure-capture'
        elseif stable(b) and b.units[b.active].actorId=='host' then
            closeMenu(); app.draw()
            if not hostGuarded then press(c.ui.battleGuard); hostGuarded=true
            elseif not hostEnded then press(c.ui.battleEnd); hostEnded=true
            else press(c.ui.battleGuard) end
        end
    elseif stage=='retry' and captured['host-owned-heal-retry.png'] then
        if touch then press({x=190,y=438,w=185,h=58}) else key('r') end
        check(not lp.authority.pendingSave,'real Retry did not commit heal'); stage='playing'
    elseif stage=='pressure-capture' and captured['host-normal-battle-pressure.png'] then menu(); stage='checkpoint'
    elseif stage=='checkpoint' and file('guest.restart.ready') then
        check(data.players.companion.ammo['22lr']==8 and data.players.host.ammo['22lr']==20,'pre-restart owned ammo differs')
        if restart then
            check(file('battle-old-session',assert(lp.authority.sessionId)),'host session marker write failed')
            check(app.quit()~=true,'restart quit cancelled')
            local disk=assert(Save.read(1)); check(signature(disk)==signature(data),'durable combat checkpoint differs from owned state')
            file('battle-resume.expected',signature(disk)); file('battle-resume.public',Checkpoint.publicSignature(disk))
            file('actions-campaign.id',disk.coop.network.campaignId); file('actions-companion.id',disk.coop.network.companionId)
            finished=true
            print('LAN_SMOKE_RESTART role=host battleSaved=true ownItems=true ownAmmo=true turn=true normalBoard=true'); love.event.quit(42)
        else
            local disk=assert(Save.read(1)); check(signature(disk)==signature(data),'retained durable combat checkpoint differs')
            file('battle-resume.expected',signature(disk)); file('battle-resume.public',Checkpoint.publicSignature(disk))
            file('actions-campaign.id',disk.coop.network.campaignId); file('actions-companion.id',disk.coop.network.companionId)
            file('actions-host.session',assert(lp.authority.sessionId))
            file('host-resumed.ready','ready'); stage='resume-wait'
        end
    elseif stage=='resume-wait' and file('guest.resumed.denied') then
        closeMenu(); app.draw(); check(c.ui.battleRetreat,'actual host retreat control missing')
        press(c.ui.battleRetreat); check(not data.tacticalBattle and c.runtime.scene=='train','host retreat did not return party'); stage='returned'
    elseif stage=='returned' and file('guest.returned') then
        local disk=assert(Save.read(1)); check(not disk.tacticalBattle and not disk.encounters['2'].resolved,'retreat granted encounter victory')
        check(disk.players.companion.ammo['22lr']==8 and disk.players.host.ammo['22lr']==20,'retreat duplicated owned shot')
        check(not disk.players.companion.inventory[1] and not disk.players.companion.inventory[2]
            and disk.players.host.inventory[1]=='field-bandage-roll','retreat/disk restore changed consumed item ownership')
        check(disk.goodwill==tonumber(file('base.goodwill')) and disk.scrap==tonumber(file('base.scrap')),'retreat granted victory resources')
        print('LAN_TACTICAL_OK role=host naturalDamage='..tostring(file('natural-incoming.damage'))..' hostRetreatOnly=true normalBoard=true'); finish()
    end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local view=lp.clientView; local data=lp.replica and lp.replica.data
    if stage=='joining' and lp.phase=='connected' and view and view.ready and lp.motionFrame and lp.motionFrame.ready then
        closeMenu(); denialId=denied(denials[denialIndex],data); stage='denial'
    elseif stage=='denial' then
        local reply=lp.network.lastCommandResult
        if denialId and reply and reply.requestId==denialId then
            check(not reply.ok and reply.reason=='host_only','guest controlled story '..denials[denialIndex])
            denialIndex=denialIndex+1; denialId=nil
            if denialIndex>#denials then file('guest.denials','true'); stage='heal' end
        end
        if stage=='denial' and not denialId and love.timer.getTime()-lastInput>.65 then
            denialId=denied(denials[denialIndex],data); lastInput=love.timer.getTime()
        end
    elseif stage=='restart-wait' then
        local expected=file('actions-host.session'); local ready=file('host-resumed.ready')
        local transient={host_disconnected=true,host_timeout=true,transport_failed=true,send_failed=true,
            join_timeout=true,connection_closed=true,application_closed=true,host_closed=true}
        check(not lp.error or transient[lp.error],'replacement connection failed: '..tostring(lp.error))
        if ready and expected and lp.phase=='connected' and lp.network.sessionId==expected
            and view and view.ready and lp.motionFrame and lp.motionFrame.ready then
            check(not restart or lp.network.sessionId~=oldSession,'fresh process reused guest session')
            check(Checkpoint.clientIdentity(lp.network,file('actions-campaign.id'),file('actions-companion.id'),data),
                'guest resumed a different saved campaign/companion')
            check(data.tacticalBattle and Checkpoint.publicSignature(data)==file('battle-resume.public'),
                'guest fresh reliable combat/owned checkpoint differs')
            battleMotion=view.motionId
            closeMenu(); capture='guest-normal-battle-resumed.png'; denialIndex=2; denialId=denied(denials[denialIndex],data); stage='resume-denial'
        elseif restart and ready and expected and lp.phase=='connected' and lp.network.sessionId==oldSession then
            menu(); click('leave'); joinReplacement(lp)
        elseif ready and expected and lp.phase=='idle' and not lp.network and love.timer.getTime()-lastInput>.65 then
            joinReplacement(lp)
        elseif reconnectAt>0 then
            check(love.timer.getTime()-reconnectAt<45,'replacement readiness timeout: phase='..tostring(lp.phase)
                ..' status='..tostring(lp.network and lp.network.status)..' error='..tostring(lp.error))
        end
    elseif stage=='resume-denial' then
        local reply=lp.network.lastCommandResult
        if denialId and reply and reply.requestId==denialId then
            check(not reply.ok and reply.reason=='host_only','guest progressed resumed battle')
            denialId=nil
            if denialIndex==2 then denialIndex=3
            else file('guest.resumed.denied','true'); stage='return-wait' end
        end
        if stage=='resume-denial' and not denialId and love.timer.getTime()-lastInput>.65 then
            denialId=denied(denials[denialIndex],data); lastInput=love.timer.getTime()
        end
    elseif stage=='return-wait' and data and not data.tacticalBattle and data.scene=='train' and view and view.ready
        and lp.motionFrame and lp.motionFrame.ready and lp.motionFrame.domain==nil and view:inputAllowed() then
        check(data.players.companion.ammo['22lr']==8 and not data.encounters['2'].resolved,'guest retreat projection lost owned state')
        local frame=lp.motionFrame; check(frame.motionId~=battleMotion,'ordinary return reused battle movement acknowledgement')
        returnMotion,returnY=frame.motionId,frame.companion.y; returnHost={x=frame.host.x,y=frame.host.y}
        returnOwnership=encode({host=ownership(data.players.host),guest=ownership(data.players.companion)})
        returnWalkAt=love.timer.getTime(); walkReturned(view); stage='return-move'
    elseif stage=='return-move' then
        check(view and view:inputAllowed() and lp.motionFrame and lp.motionFrame.ready,'ordinary return lost movement readiness')
        local frame=lp.motionFrame
        check(frame.motionId==returnMotion and frame.host.x==returnHost.x and frame.host.y==returnHost.y,'guest movement moved host or changed movement generation')
        check(encode({host=ownership(data.players.host),guest=ownership(data.players.companion)})==returnOwnership,
            'ordinary guest movement changed owned items, ammo, health or progression')
        check(love.timer.getTime()-returnWalkAt<6,'ordinary guest movement was not accepted by host')
        if frame.companion.y<returnY-12000 then
            stopReturned(view); print('LAN_BATTLE_RETURN_MOVEMENT authoritativeMillipixels='..(returnY-frame.companion.y)
                ..' freshMotion=true hostStill=true ownedItems=true')
            stage='return-stop'
        end
    elseif stage=='return-stop' and lp.motionFrame and not lp.motionFrame.companion.moving and view:inputAllowed() then
        capture='guest-normal-battle-returned.png'; stage='return-capture'
    elseif stage=='return-capture' and captured['guest-normal-battle-returned.png'] then
        file('guest.returned','true'); menu(); click('leave'); print('LAN_TACTICAL_OK role=guest heal=true potion=true ability=true guard=true move=true swap=true shot=true endTurn=true durable=true hostStoryOnly=true'); finish()
    elseif view and data and data.tacticalBattle then
        local b=view.runtime.battle; local panel=view.battles; local u=Rules.activeUnit(b)
        if not initialGuest then initialGuest=assert(Schema.copy(data.players.companion)) end
        if stage=='action' then completeAction(view,data); return end
        check(not b.finished,'encounter ended before normal actions/retreat')
        if stage=='matrix-done' then
            if not file('guest.matrix.complete') then file('guest.matrix.complete','true') end
            if file('natural-incoming.damage') and c.ui.localPlay.menuOpen then
                oldSession=lp.network.sessionId; file('guest.restart.ready','true'); stage='restart-wait'
            elseif file('natural-incoming.damage') and stable(b) then
                oldSession=lp.network.sessionId; file('guest.restart.ready','true'); stage='restart-wait'
            elseif stable(b) and u.actorId=='companion' and panel:canAct(u) then app.draw(); press(view.ui.battleGuard) end
            return
        end
        if not stable(b) or u.actorId~='companion' or not panel:canAct(u) then return end
        app.draw(); check(not view.ui.battleRetreat and not view.ui.battleContinue,'guest story controls leaked')
        if stage=='heal' then startAction('heal','potion',function() press(view.ui.battleHeal) end,view)
        elseif stage=='potion' then
            if touch then
                if not view.runtime.inventoryOpen then press(view.ui.battleInventory); return end
                if not view.runtime.draggedSlot then press(slot({kind='inventory',index=2})); app.draw(); return end
                startAction('potion','potion-close',function()
                    press(Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},view.ui.consume))
                end,view)
            else
                local entry=view.ui.battlePotionButtons[1]; check(entry and entry.name=='green-regeneration-vial','actual potion quick control missing')
                startAction('potion','guard',function() press(entry[1]) end,view)
            end
        elseif stage=='potion-close' then press(Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},view.inventory.closeButton)); stage='guard'
        elseif stage=='guard' then startAction('guard','ability',function() press(view.ui.battleGuard) end,view)
        elseif stage=='ability' then startAction('ability','pack',function() press(view.ui.battleAbility) end,view)
        elseif stage=='pack' then press(view.ui.battleInventory); stage='store'
        elseif stage=='store' then startAction('store','equip',function() drag({kind='equipment',index=2},{kind='inventory',index=6}) end,view)
        elseif stage=='equip' then
            check(data.players.companion.itemSlots.inventory[6].id==initialGuest.itemSlots.equipment[2].id,'pack move replaced exact owned instance')
            startAction('equip','pack-close',function() drag({kind='inventory',index=6},{kind='equipment',index=2}) end,view)
        elseif stage=='pack-close' then press(Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},view.inventory.closeButton)); stage='move'
        elseif stage=='move' then
            local enemy=assert(nearest(b,u)); local step=Rules.bestAdvance(b,u,enemy,u.move,1)
            check(step.q~=u.q or step.r~=u.r,'no normal reachable guest movement')
            startAction('move','weapon',function() press(view.ui.battleMove); cell(step.q,step.r) end,view); moves=moves+1
        elseif stage=='weapon' then
            local enemy; local weapon='frontier-22-lever-rifle'
            for _,candidate in ipairs(b.units) do
                if candidate.team=='enemy' and candidate.hp>0 and Rules.distance(u,candidate)<=Rules.weaponRange(c.catalog,weapon)
                    and Rules.lineOfSight(b,u,candidate) then enemy=candidate; break end
            end
            if enemy then
                shotTarget=enemy.id
                startAction('weapon','shot',function() press(view.ui.battleWeapons[3]) end,view)
            else startAction('approach-end','move',function() press(view.ui.battleEnd) end,view) end
        elseif stage=='shot' then
            local enemy; for _,unit in ipairs(b.units) do if unit.id==shotTarget then enemy=unit end end
            check(enemy and enemy.hp>0,'chosen normal shot target disappeared')
            startAction('shot','end',function() cell(enemy.q,enemy.r) end,view)
        elseif stage=='end' then startAction('end','matrix-done',function() press(view.ui.battleEnd) end,view) end
    end
end
local function update(dt)
    if finished then return end; local now=love.timer.getTime(); check(now-started<155,'normal action fixture deadline '..tostring(stage))
    app.update(math.min(.05,dt)); app.focus(true)
    if now-reportAt>5 then
        reportAt=now; local lp=c.ui.localPlay; local view=lp.clientView; local b=c.runtime.battle or view and view.runtime.battle
        local data=c.runtime.saveData or lp.replica and lp.replica.data
        local reconnect=lp:reconnectStatus()
        print('LAN_BATTLE_ACTIONS_STATE role='..role..' stage='..tostring(stage)..' active='..tostring(b and b.units[b.active].id)
            ..' round='..tostring(b and b.round)..' turn='..tostring(data and data.tacticalBattle and data.tacticalBattle.revision)
            ..' pending='..tostring(view and view.battles.pending and view.battles.pending.id)..' damage='..incomingDamage
            ..' phase='..tostring(lp.phase)..' status='..tostring(lp.network and lp.network.status)..' error='..tostring(lp.error)
            ..' runtime='..tostring(c.runtime.state)..' menu='..tostring(lp.menuOpen)..' reconnect='..tostring(reconnect and reconnect.state)
            ..' presentedSession='..tostring(lp.network and (lp.network.sessionId or lp.network.context.sessionId))
            ..' expectedSession='..tostring(file('actions-host.session')))
    end
    if role=='host' then hostUpdate() else guestUpdate() end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        movementKey=nil; if oldKeyboard then love.keyboard.isDown=oldKeyboard end
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw(); if capture then local name=capture; capture=nil
        love.graphics.captureScreenshot(function(pixels)
            local bytes=pixels:encode('png'); check(file(name,bytes:getString()),'capture write failed '..name); captured[name]=true
        end)
    end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
