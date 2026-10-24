-- Actual two-player tactical controls, owned ammo, save retry and reconnect.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'); local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local expedition=os.getenv('MOUSE_FRONTIER_BATTLE_SCENE')=='expedition'
local lateJoin=os.getenv('MOUSE_FRONTIER_BATTLE_LATE_JOIN')=='1'
local boss=os.getenv('MOUSE_FRONTIER_BATTLE_BOSS')=='1'
local hostRestart=os.getenv('MOUSE_FRONTIER_BATTLE_HOST_RESTART')=='1'
local searchRuins=os.getenv('MOUSE_FRONTIER_BATTLE_SEARCH')=='1'
local Search=require('game.battle_search')
local resumed=os.getenv('MOUSE_FRONTIER_BATTLE_RESUMED')=='1'
local harnessRoot=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT')
local requestedOutcome=os.getenv('MOUSE_FRONTIER_BATTLE_OUTCOME')
local outcome=({win=true,loss=true,retreat=true})[requestedOutcome]and requestedOutcome or'win'
local Areas=require('game.expedition_areas')
local areaId=boss and Areas.DUNGEON_ID or Areas.SURFACE_ID
local mobId=boss and 'sludge-badger-boss' or 'surface-bandit-a'
local stopId=expedition and 6 or boss and 15 or 2
local Save=require('game.save'); local Items=require('game.item_instances'); local Players=require('game.coop_players')
local Viewport=require('game.viewport'); local Grid=require('game.battle_grid'); local Style=require('game.ui_layout')
local BattleCommands=require('game.coop_battles')
local Inventory=require('game.inventory')
local Native=require('game.battle_native_ui')
local Field=require('game.battle_field')
local app,c,stage,started,finished,capture,restoreWrite,requestId,rejoinAt,encounterId
local captured={}; local denied=0; local generation; local connections=0; local diagnosticAt=0
local enemyHP,shotSignature,oldSessionId
local function file(name,bytes)
    local f=io.open(harnessRoot..'/'..name,bytes and 'wb' or 'rb')
    if not f then return nil end
    local result=bytes and f:write(bytes) or f:read('*a'); f:close(); return result
end
local function signature(data)
    local s=assert(data.tacticalBattle); local b=s.battle; local h=data.players.host; local g=data.players.companion
    return assert(require('game.net.codec').encode({epoch=data.coop.sceneEpoch,rng=data.coop.randomState,
        encounterId=s.encounterId,revision=s.revision,active=b.active,round=b.round,phase=b.phase,
        guestQ=b.units[2].q,guestR=b.units[2].r,guestHP=b.units[2].hp,enemyHP=b.units[3].hp,
        hostAmmo=h.ammo['22lr'],guestAmmo=g.ammo['22lr'],hostWeapon=h.itemSlots.equipment[2].id,
        guestWeapon=g.itemSlots.equipment[2].id,hostWear=h.itemSlots.equipment[2].durability,
        guestWear=g.itemSlots.equipment[2].durability,ruinClaim=Search.receipt(data,b,1)or false,guestInventory=g.inventory,scrap=data.scrap}))
end
local function destination() return outcome=='win' and (expedition and 'expedition' or 'stop') or 'train' end
local function enemyId(data)
    return expedition and data.expeditions[areaId].mobs[mobId].entityId or data.encounters[tostring(stopId)].entityId
end
local function resolved(data)
    return expedition and data.expeditions[areaId].mobs[mobId].rewardResolved or not expedition and data.encounters[tostring(stopId)].resolved
end
local function battleEntry(data)
    return expedition and {source='expedition',areaId=areaId,enemyStates={{mobId=mobId}}} or data.encounters[tostring(stopId)]
end
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing control '..tostring(stage)); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('battle-test',x,y); app.touchreleased('battle-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function cell(q,r)
    local view=c.ui.localPlay.clientView
    local b=role=='guest'and view and view.runtime.battle or c.runtime.battle
    local ui=role=='guest'and view and view.ui or c.ui
    if b and b.field then
        app.draw();local camera=assert(Native.camera(ui,b));camera:focus(q,r,Field.cellHeight(b.field,q,r));app.draw()
        local x,y=Native.project({battle=b,ui=ui},q,r);press({x=x,y=y,w=0,h=0});return
    end
    local x,y=Grid.boardToScreen(1,q,r)
    if role=='guest' and view then x,y=view.battles.worldView.toScreen(x,y) end
    press(Style.transformRectFor('battle',{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0}))
end
local function menu()
    if c.ui.localPlay.menuOpen then return end
    local view=c.ui.localPlay.clientView
    if touch and role=='guest' and view and view.runtime.battle then
        app.draw(); press(Style.transformRectFor('mobileControls',view.mobile:uiBounds(),view.mobile.menu))
        check(c.ui.localPlay.menuOpen,'battle touch Local Play menu did not open')
    else app.keypressed('f8'); app.keyreleased('f8') end
end
local function gearDrag(from,to)
    local bounds={x=25,y=35,w=910,h=660}
    local function rect(ref)
        local r=ref.kind=='equipment' and (touch and Inventory.mobileEquipmentSlotRect(ref.index) or Inventory.equipmentSlotRect(ref.index))
            or (touch and Inventory.mobileInventorySlotRect(ref.index) or Inventory.inventorySlotRect(ref.index))
        r=Style.transformRectFor('inventory',bounds,r)
        local ox,oy,sx,sy=Viewport.transform(960,720); return ox+(r.x+r.w/2)*sx,oy+(r.y+r.h/2)*sy
    end
    local x,y=rect(from); local nx,ny=rect(to)
    if touch then app.touchpressed('gear',x,y); app.touchmoved('gear',nx,ny); app.touchreleased('gear',nx,ny)
    else app.mousepressed(x,y,1,false); app.mousemoved(nx,ny); app.mousereleased(nx,ny,1,false) end
end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true battles=true source='..(expedition and 'expedition' or 'ordinary')..' boss='..tostring(boss)..' diskResume='..tostring(hostRestart)..' lateJoin='..tostring(lateJoin)..' outcome='..outcome..' checkpointRetry=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99
        local data
        if resumed then
            data=assert(Save.read(99)); check(signature(data)==file('battle-resume.expected'),'disk checkpoint changed before load')
        else
            Save.remove(99); data=c.newSave(c.characters[1]);local home=require('game.home_stop')
            assert(home.advance(data,'enterOffice'));for _=1,6 do assert(home.advance(data,'talk'))end
            assert(home.advance(data,'exitOffice'));assert(home.advance(data,'supplies'));assert(home.advance(data,'repair'))
            assert(home.advance(data,'enterOffice'));assert(home.advance(data,'talk'));assert(home.advance(data,'talk'))
            assert(home.advance(data,'exitOffice'));assert(home.depart(data))
            data.location=stopId; data.passengers={}
            if expedition then
                data.scene=Areas.SCENE; data.activeExpeditionArea=areaId; Areas.ensure(data)
                if boss then
                    -- Open the authored boss route in this isolated fixture.
                    for _,id in ipairs(Areas.definition(areaId).gateRequired) do local mob=data.expeditions[areaId].mobs[id]; mob.hp=0; mob.dead=true end
                    Areas.updateGates(data,areaId)
                end
            end
        end
        check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
        if resumed then
            check(c.runtime.state=='battle' and c.runtime.battle==data.tacticalBattle.battle and lp:canHost(),'loaded battle is not hostable')
            check(signature(data)==file('battle-resume.expected'),'entry replayed the saved turn or costs')
        else Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=20 end
        if expedition and not resumed then
            local mob=data.expeditions[areaId].mobs[mobId]
            c.runtime.player.x,c.runtime.player.y=Areas.clamp(data,areaId,mob.x,mob.y)
            data.playerX,data.playerY=c.runtime.player.x,c.runtime.player.y
            c.runtime.expeditionGraceTimer=999 -- pause roaming handoff during admission
            check(Areas.canReach(data,areaId,mob.x,mob.y,data.playerX,data.playerY),'expedition fixture path blocked')
        elseif not resumed then
            local tier=require('game.combat_balance').tierFor(stopId)
            data.encounters[tostring(stopId)]={rolled=true,hasMob=true,resolved=false,tier=tier,boss=boss,maxHP=200,mobFiles={c.catalog.mobTiers[tier][1]}}
        end
        check(require('game.coop_entities').ensure(data),'encounter identity failed'); encounterId=enemyId(data)
        menu(); click('port',port); click('host'); check(lp.network,'host failed '..tostring(lp.error))
        local original=lp.network.context.command
        lp.network.context.command=function(gen,request)
            local reply=original(gen,request)
            if request.command=='battle.begin' or request.command=='battle.continue' or request.command=='battle.guard' and request.args.unitId=='player' then
                check(not reply.ok,'guest foreign/progression command accepted'); denied=denied+1
            end
            return reply
        end
        if lateJoin and not resumed then
            local begun,reason=c.beginEncounter(battleEntry(data)); check(begun,'solo entry failed '..tostring(reason))
            check(#c.runtime.battle.units==2,'solo fixture roster differs')
        end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        -- Current Local Play joins with a selected owned save, rather than
        -- the retired next/previous transient-character controls.
        assert(Save.write(1,c.newSave(c.characters[2]or c.characters[1])))
        c.runtime.state='slots';c.runtime.selectedSlot=nil;menu();click('address','127.0.0.1:'..port)
        click('name','Battle test friend');click('saveSlot');click('slot_1');click('join');stage='joining'
    end
end
local function stable(b)
    if not b or b.intro or b.projectile or b.attackTimer>0 or (b.enemyDelay or 0)>0 then return false end
    for _,u in ipairs(b.units) do if (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 or u.moveAnim then return false end end
    return true
end
local function update(dt)
    if finished then return end
    local now=love.timer.getTime(); check(now-started<105,'battle fixture deadline '..tostring(stage))
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; app.focus(true)
    if now-diagnosticAt>10 then
        diagnosticAt=now; local b=c.runtime.battle or lp.clientView and lp.clientView.runtime.battle
        print('LAN_BATTLE_STATE role='..role..' stage='..tostring(stage)..' connections='..connections..' denied='..denied
            ..' active='..tostring(b and b.units[b.active].id)..' phase='..tostring(b and b.phase)..' result='..tostring(b and b.finished))
    end
    if role=='host' then
        if lp:pending() then click('approve'); check(not lp.error,'admission failed '..tostring(lp.error)) end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then generation=link.generation; connections=connections+1 end
        local data=c.runtime.saveData; local b=c.runtime.battle
        if stage=='hosting' and resumed and link and link.phase=='ready' and denied>=1 then
            check(signature(data)==file('battle-resume.expected'),'re-admission changed saved ownership/turn')
            if lp.menuOpen then click('close') end
            capture='host-battle-resumed.png'; stage='reconnect'
        elseif stage=='hosting' and link and link.phase=='ready' and denied>=1 then
            if lp.menuOpen then click('close') end
            local guest=Players.forActor(data,'companion'); Items.write(guest,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); guest.ammo['22lr']=9
            if not lateJoin then
                local begun,reason=c.beginEncounter(battleEntry(data)); check(begun,'battle entry failed '..tostring(reason)..' screen='..c.runtime.state); b=c.runtime.battle
                check(#b.units==3 and b.units[2].actorId=='companion','two owned player units missing')
            else check(#b.units==2 and b.pendingActorId=='companion','late join was not queued for next turn') end
            b.intro=nil; b.obstacles={}; b.units[#b.units].q,b.units[#b.units].r=2,5; b.tiles[1][6]=1
            -- Keep the guest's turn open after its shot so a disk restart tests
            -- resuming guest ownership before the next enemy/host turn.
            if hostRestart then b.units[2].extraAttacks=1 end
            capture='host-battle-start.png'; stage='start'
        elseif stage=='start' and denied>=2 and stable(b) then
            app.draw(); press(c.ui.battleMove); cell(1,4)
            check(b.units[1].q==1 and b.units[1].r==4,'host move control failed'); stage='host-moved'
        elseif stage=='host-moved' and stable(b) then
            restoreWrite=love.filesystem.write
            love.filesystem.write=function(path,bytes)
                if path==Save.path(99) and data.players.companion.ammo['22lr']==8 then return false,'injected guest shot save failure' end
                return restoreWrite(path,bytes)
            end
            app.draw(); if touch then press(c.ui.battleEnd) else app.keypressed('space'); app.keyreleased('space') end
            check(b.units[b.active].actorId=='companion','host end turn failed'); stage='guest-turn'
        elseif stage=='guest-turn' and lp.authority.pendingSave then
            check(data.players.companion.ammo['22lr']==8 and data.ammo['22lr']==20,'guest shot charged wrong actor')
            capture='host-battle-retry.png'; stage='retry'
        elseif stage=='retry' and captured['host-battle-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r'); app.keyreleased('r') end
            check(not lp.authority.pendingSave and data.players.companion.ammo['22lr']==8,'shot retry repeated cost')
            if searchRuins then
                local p=Search.list(b)[1];local u=b.units[2];u.q,u.r=p.q,p.r;u.moveAnim=nil;b.active=2;b.enemyDelay=0;b.attackTimer=0
                u.actionTimer=0;u.hitTimer=0;b.projectile=nil
                check(file('ruin-search.ready','ready'),'search barrier failed');stage='search-wait'
            else stage=hostRestart and 'restart-pending' or 'reconnect'end
        elseif stage=='search-wait'and Search.receipt(data,b,1)and stable(b)and b.units[b.active].actorId=='host'then
            local receipt=Search.receipt(data,b,1)
            check(receipt.actorId=='companion'and receipt.delivery=='inventory','search paid the wrong player')
            local disk=assert(Save.read(99));check(Search.receipt(disk,disk.tacticalBattle.battle,1),'search receipt was not durable')
            app.draw();press(c.ui.battleEnd);check(b.units[b.active].actorId=='companion','search restart barrier has no guest turn')
            print('LAN_RUIN_SEARCH_OK role=host durable=true companionOwnsLoot=true')
            stage=hostRestart and 'restart-pending' or 'reconnect'
        elseif stage=='restart-pending' and stable(b) and file('guest-shot.ready') then
            local before=signature(data); check(app.quit()~=true,'restart quit cancelled')
            local disk=assert(Save.read(99)); check(signature(disk)==before,'shutdown changed the saved turn or equipment')
            check(file('battle-resume.expected',before),'resume manifest failed')
            finished=true; print('LAN_SMOKE_RESTART role=host battleSaved=true ownItems=true ownAmmo=true turn=true'); love.event.quit(42)
        elseif stage=='reconnect' and connections==(resumed and 1 or 2) and stable(b) and b.units[b.active].actorId=='host' and denied>=(resumed and 1 or 3) then
            -- Shorten the private fixture's final enemy HP. Both actual player
            -- actions, AI, ownership and settlement still use production code.
            enemyHP=b.units[3].hp
            if outcome=='retreat' then
                app.draw(); press(c.ui.battleEnd); check(b.units[b.active].actorId=='companion','retreat fixture did not reach guest turn')
                app.draw(); check(c.ui.battleRetreat and not c.ui.battleWeapons[1],'host guest-turn controls leaked')
                capture='host-battle-retreat.png'; stage='retreat'
            elseif outcome=='loss' then
                -- Set the private fixture's party to fallen. Production enemy
                -- authority commits defeat/recovery and the host dismisses it.
                b.units[1].hp=0; b.units[2].hp=0; data.health=0; data.players.companion.health=0
                b.active=3; b.enemyDelay=0; stage='losing'
            else
                b.units[3].hp=1; b.units[1].perfectAccuracy=true
                if b.field then
                    -- Stage the result near extraction. Full route traversal
                    -- is covered separately; this fixture tests wire/UI costs.
                    b.units[1].q,b.units[1].r=b.field.exitColumn,3
                    b.units[2].q,b.units[2].r=b.field.exitColumn,5
                    b.units[3].q,b.units[3].r=b.field.exitColumn-1,4
                end
                app.draw(); press(c.ui.battleWeapons[3]); cell(b.units[3].q,b.units[3].r)
                if b.finished=='win' then capture='host-battle-victory.png'; stage='won' end
            end
        elseif stage=='retreat' and captured['host-battle-retreat.png'] then
            app.draw(); press(c.ui.battleRetreat); check(not data.tacticalBattle and c.runtime.scene=='train','host guest-turn retreat failed'); stage='continued'
        elseif stage=='losing' and b.finished=='loss' then
            capture='host-battle-victory.png'; stage='won'
        elseif stage=='won' and denied>=(resumed and 2 or 4) and captured['host-battle-victory.png'] then
            app.draw(); press(c.ui.battleContinue)
            check(not data.tacticalBattle and c.runtime.scene==destination(),'host continuation failed'); stage='continued'
        elseif stage=='continued' and not link then
            local saved=assert(Save.read(99)); check((resolved(saved)==true)==(outcome=='win') and not saved.tacticalBattle,'battle result lost')
            check(saved.players.companion.ammo['22lr']==8 and (outcome=='win' and saved.ammo['22lr']<20 or outcome~='win' and saved.ammo['22lr']==20),'owned ammo save differs')
            if expedition and outcome~='win' then
                check(saved.expeditions[areaId].mobs[mobId].hp==enemyHP,'surviving enemy damage lost')
            end
            if boss and expedition then check(saved.expeditions[areaId].gates.bossDefeated==(outcome=='win'),'boss vault gate settlement differs') end
            if outcome=='loss' then check(saved.health==math.floor(saved.maxHealth/2) and saved.players.companion.health==math.floor(saved.players.companion.maxHealth/2),'party loss recovery differs') end
            print('LAN_TACTICAL_OK role=host twoPlayers=true move=true retry=true oneResult=true'); finish()
        end
    else
        if lp.error and not (hostRestart and stage=='host-lost' and (lp.error=='host_disconnected' or lp.error=='application_closed')) then error('Local Play failed '..lp.error) end
        if stage=='leaving'and lp.phase=='idle'and not lp.network then
            print('LAN_TACTICAL_OK role=guest ownTurn=true ownAmmo=true saveRetry=true reconnect=true hostContinueOnly=true');finish();return
        end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.motionFrame and lp.motionFrame.ready then
            click('close'); local d=lp.replica.data
            requestId=assert(lp.network:submitCommand('battle.begin',{encounterId=enemyId(d)},d.coop.sceneEpoch,{})); stage='start-denied'
        elseif stage=='start-denied' then
            local r=lp.network.lastCommandResult
            if r and r.requestId==requestId then check(not r.ok and r.reason=='host_only','guest started battle'); stage='start' end
        elseif stage=='rejoin' and now-rejoinAt>.5 then menu(); click('join'); stage='resumed'
        elseif stage=='host-lost'and lp.phase=='connected'and lp.network and lp.network.sessionId~=oldSessionId then
            stage='resumed' -- The current reconnect policy may finish automatically.
        elseif stage=='host-lost' and not lp.network and lp.phase=='idle' then
            check(c.runtime.state=='slots' and not c.session.replicaData,'host loss did not release guest replica')
            if not captured['guest-host-disconnected.png'] then capture='guest-host-disconnected.png'
            elseif file('host-resumed.ready') then click('join'); stage='resumed' end
        elseif lp.clientView and lp.replica.data then
            local d=lp.replica.data; local view=lp.clientView; local b=view.runtime.battle; local s=d.tacticalBattle
            if stage=='start' and b and lp.motionFrame and lp.motionFrame.ready then
                local expected={}; for _,scope in ipairs(BattleCommands.scopes(d)) do expected[scope]=d.coop.revisions[scope] or 0 end
                requestId=assert(lp.network:submitCommand('battle.guard',{encounterId=s.encounterId,turnRevision=s.revision,unitId='player'},d.coop.sceneEpoch,expected)); stage='foreign-denied'
            elseif stage=='foreign-denied' then
                local r=lp.network.lastCommandResult
                if r and r.requestId==requestId then check(not r.ok and r.reason=='not_your_turn','guest controlled host'); stage='turn' end
            elseif stage=='turn' and b and stable(b) and b.units[b.active].actorId=='companion' then
                app.draw(); check(view.ui.battleWeapons[3] and not view.ui.battleRetreat,'guest attack controls missing or retreat leaked')
                check(view.battles:context().mobImages[b.units[3].file],'guest enemy sprite missing')
                capture='guest-battle-turn.png'; stage='pack-open'
            elseif stage=='pack-open' and captured['guest-battle-turn.png'] then
                app.draw(); press(view.ui.battleInventory); app.draw()
                check(view.runtime.inventoryOpen and not d.players.companion.inventory[6],'battle backpack unavailable/full fixture slot')
                gearDrag({kind='equipment',index=2},{kind='inventory',index=6}); stage='stored'
            elseif stage=='stored' and not view.battles.pending and d.players.companion.inventory[6]=='frontier-22-lever-rifle' then
                app.draw(); gearDrag({kind='inventory',index=6},{kind='equipment',index=2}); stage='equipped'
            elseif stage=='equipped' and not view.battles.pending and d.players.companion.equipment[2]=='frontier-22-lever-rifle' then
                app.draw(); press(Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},view.inventory.closeButton))
                check(not view.runtime.inventoryOpen,'battle backpack close failed')
                view.camera:setZoom(1.15); app.draw(); press(view.ui.battleMove); cell(1,6); stage='moved'
            elseif stage=='moved' and not view.battles.pending and b.units[2].r==6 and stable(b) then
                app.draw(); press(view.ui.battleWeapons[3]); stage='target'
            elseif stage=='target' and b and(view.battles.mode or b.phase)=='target'and not view.battles.pending then cell(2,5);stage='shot'
            elseif stage=='shot' and d.players.companion.ammo['22lr']==8 and not view.battles.pending then
                check(d.players.host.ammo['22lr']==20,'guest shot consumed host ammo')
                if searchRuins then
                    local p=Search.list(b)[1]
                    if file('ruin-search.ready')and b.units[2].q==p.q and b.units[2].r==p.r and stable(b)then
                        app.draw();check(view.ui.battleSearch,'guest ruin search control missing');press(view.ui.battleSearch);stage='searched'
                    end
                else capture='guest-battle-shot.png';stage='disconnect'end
            elseif stage=='searched'and not view.battles.pending and Search.receipt(d,b,1)and stable(b)and b.units[b.active].actorId=='companion'then
                local receipt=Search.receipt(d,b,1);local found=false
                for _,item in pairs(d.players.companion.inventory)do if item==receipt.item then found=true end end
                check(found and receipt.actorId=='companion','replicated personal loot missing')
                print('LAN_RUIN_SEARCH_OK role=guest replicated=true input='..(touch and'touch'or'desktop'))
                capture='guest-battle-shot.png';stage='disconnect'
            elseif stage=='disconnect' and captured['guest-battle-shot.png'] then
                if hostRestart then
                    shotSignature=signature(d); oldSessionId=lp.network.sessionId
                    check(file('guest-shot.ready','captured'),'guest restart barrier failed'); stage='host-lost'
                else lp:stop('test_connection_drop');rejoinAt=now;stage='rejoin'end
            elseif stage=='resumed' and lp.phase=='connected' and lp.motionFrame and lp.motionFrame.ready then
                check(b and #b.units==3 and d.players.companion.ammo['22lr']==8,'battle reconnect lost model/ammo')
                check(view.battles:context().mobImages[b.units[3].file],'guest resumed enemy sprite missing')
                if hostRestart then
                    check(signature(d)==shotSignature and lp.network.sessionId~=oldSessionId,'fresh host lost the saved board or session identity')
                end
                click('close'); capture='guest-battle-rejoined.png'
                requestId=assert(lp.network:submitCommand('battle.continue',{encounterId=s.encounterId,turnRevision=s.revision},d.coop.sceneEpoch,{})); stage=hostRestart and 'resume-denied' or 'victory'
            elseif stage=='resume-denied' and lp.network.lastCommandResult and lp.network.lastCommandResult.requestId==requestId then
                check(not lp.network.lastCommandResult.ok and lp.network.lastCommandResult.reason=='host_only','guest progressed resumed encounter')
                app.draw(); press(view.ui.battleEnd); stage='victory'
            elseif stage=='victory' and b and b.finished==outcome then
                app.draw(); check(not view.ui.battleContinue and not view.ui.battleRetreat,'guest result controls leaked')
                capture='guest-battle-victory.png'; requestId=assert(lp.network:submitCommand('battle.continue',{encounterId=s.encounterId,turnRevision=s.revision},d.coop.sceneEpoch,{})); stage='continued'
            elseif (stage=='continued' or stage=='victory' and outcome=='retreat') and not s and d.scene==destination() then
                check((resolved(d)==true)==(outcome=='win') and d.players.companion.ammo['22lr']==8,'committed result differs')
                menu();click('leave');stage='leaving'
            end
        end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
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
