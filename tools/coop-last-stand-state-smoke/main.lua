-- Full source host app, real PNG apertures and isolated disk persistence.
-- The companion uses the domain adapter here; this is not LAN guest acceptance.
io.stdout:setvbuf('no')
local Save=require('game.save'); local Schema=require('game.save_schema')
local Players=require('game.coop_players'); local Items=require('game.item_instances')
local Catalog=require('game.catalog'); local Shootout=require('game.last_stand_shootout')
local State=require('game.coop_last_stand_state'); local Window=require('game.window_scene')
local Life=require('game.coop_last_stand_lifecycle'); local Positions=require('game.coop_last_stand_positions')
local Viewport=require('game.viewport')
local app,c,stage,capture,finished,battle,companion,data,epoch,encounterId,guestId,clock,remaining
local checks=0
local button,point
local function check(value,message) checks=checks+1; assert(value,message) end
local function commandChecks(index,x,y)
    local commands=c.ui.localPlay.context.commands
    local life=data.lastStand.lifecycle
    local ready=commands.submit('lastStand.position',{questId=life.entityId,revision=life.revision,
        action='ready',window='wide',phaseRevision=data.lastStand.combat.phaseRevision})
    check(ready.ok and ready.durable and ready.result.leaseId,'production host firing position did not acquire checked occupancy')
    local args={mode='lastStand',encounterId=data.lastStand.combat.entityId,
        phaseRevision=data.lastStand.combat.phaseRevision,cover=true}
    local reply=commands.submit('gun.cover',args)
    check(reply.ok and reply.durable and battle.ducking,'production host command readiness/cover failed')
    args.cover=false; reply=commands.submit('gun.cover',args)
    check(reply.ok and reply.durable and not battle.ducking,'production host uncover command failed')
    -- A detached native authority proves guest geometry and disk receipts.
    -- Its explicit fixture actor readiness is not a connected guest UI claim.
    local copy=assert(Schema.migrate(data)); local quest=copy.lastStand; local combat=quest.combat
    combat.defenders.companion.ducking=false; combat.defenders.companion.coverProgress=0
    local gun=quest.shooterSessions.companion.weaponSession
    require('game.first_person_shooting').update(require('game.coop_shooter_sessions').view(gun,960,720),20,
        Players.forActor(copy,'companion'),quest,960,720)
    local target=quest.targets[index]; target.status='exposed'; target.health=target.maxHealth; target.timer=999
    local authority=require('game.coop_authority').new({campaign=copy,sessionId='native-last-stand-guns',
        checkpoint=function(value) return Save.write(98,value) end})
    authority:admit('companion',1)
    local context={catalog=Catalog,
        actorState=function() return {screen='game',scene='stop',movementReady=true,modalDomain=Life.key(copy)} end,
        lastStandState=function() return {active=true,paused=false,encounterId=combat.entityId,phaseRevision=combat.phaseRevision} end,
        lastStandPhase=function() return {active=true,paused=false,encounterId=combat.entityId,phaseRevision=combat.phaseRevision} end,
        lastStandScene=function() local domain=copy.lastStand.lifecycle
            return {active=true,questId=domain.entityId,revision=domain.revision,mode=domain.mode,paused=false,blocked=false} end}
    Positions.install(authority,context); require('game.coop_guns').install(authority,context)
    local select=assert(authority:prepareRequest('companion','lastStand.position',{questId=quest.lifecycle.entityId,
        revision=quest.lifecycle.revision,action='ready',window='tall',phaseRevision=combat.phaseRevision}))
    reply=authority:execute('companion',1,select)
    check(reply.ok and reply.durable and reply.result.leaseId and combat.defenders.companion.windowId=='tall',
        'native guest firing position did not acquire checked tall occupancy: '..tostring(reply.reason))
    index,x,y=point({targets=quest.targets,windowId='tall'})
    target=quest.targets[index]; target.status='exposed'; target.health=target.maxHealth; target.timer=999
    local shot={mode='lastStand',encounterId=combat.entityId,phaseRevision=combat.phaseRevision,
        weaponId=gun.itemId,x=math.floor(x/960*1000000+.5),y=math.floor(y/720*1000000+.5)}
    local request=assert(authority:prepareRequest('companion','gun.fire',shot))
    local oldAmmo=copy.players.companion.ammo['22lr']; local hostAmmo=copy.players.host.ammo['22lr']; local health=target.health
    reply=authority:execute('companion',1,request)
    check(reply.ok and reply.durable and reply.result.hit,'native guest authority shot did not hit through the real aperture: '
        ..tostring(reply.reason)..' ok='..tostring(reply.ok)..' durable='..tostring(reply.durable)..' hit='..tostring(reply.result and reply.result.hit))
    check(target.health<health and copy.players.companion.ammo['22lr']==oldAmmo-1 and copy.players.host.ammo['22lr']==hostAmmo,
        'native guest command changed the wrong ammo or target')
    check(authority:execute('companion',1,request).durable and copy.players.companion.ammo['22lr']==oldAmmo-1,
        'native command replay charged ammunition twice')
    check(require('game.net.gun_results').valid('gun.fire',reply.result),'native public gun result invalid')
    local disk=assert(Save.read(98))
    check(disk.lastStand.combat.phaseRevision==combat.phaseRevision and disk.players.companion.ammo['22lr']==oldAmmo-1,
        'native guest command disk phase/cost was lost')
    local blocked={}; for key,value in pairs(shot) do blocked[key]=value end
    blocked.x=0; blocked.y=0
    check(not Window.pointOpen(combat.defenders.companion.windowId,960,720,0,0),'native blocked corner was open')
    gun.cooldown=0
    local blockRequest=assert(authority:prepareRequest('companion','gun.fire',blocked))
    check(authority:execute('companion',1,blockRequest).reason=='window_blocked'
        and copy.players.companion.ammo['22lr']==oldAmmo-1,'native blocked shot charged ammunition')
    local stale=assert(authority:prepareRequest('companion','gun.fire',shot)); check(State.open(quest),'phase reopening failed')
    check(authority:execute('companion',1,stale).reason=='stale_phase','native delayed shot survived phase reopening')
    local _,reason=authority:prepareRequest('companion','lastStand.advance',{})
    check(reason=='host_only','native guest was allowed to progress the host story')
end
local function hostInputChecks()
    local lp=c.ui.localPlay; lp.port='32179'
    check(lp:host(),lp.error or 'native Local Play host did not start')
    app.update(.01); app.update(.01)
    check(c.session.networkMode=='host' and lp.network,'actual host mode/ENet listener missing')
    local authority=lp.authority
    local function sequence() return authority.requests.host and authority.requests.host.high or 0 end
    local nextRequest=sequence()+1
    button('c'); app.update(.4)
    check(not battle.ducking and battle.coverProgress==0 and sequence()==nextRequest,'host cover input bypassed authority')
    for _,target in ipairs(battle.targets) do target.status='hidden'; target.timer=999 end
    local index,x,y=point(battle); local target=battle.targets[index]
    target.status='exposed'; target.health=target.maxHealth; target.timer=999
    local ownId=battle.gun.itemId; local ammo=data.ammo['22lr']; local hp=target.health
    nextRequest=sequence()+1
    local ox,oy,sx,sy=Viewport.transform(960,720)
    app.mousemoved(ox+x*sx,oy+y*sy,0,0,false)
    app.mousepressed(ox+x*sx,oy+y*sy,1,false); app.mousereleased(ox+x*sx,oy+y*sy,1,false)
    check(sequence()==nextRequest and data.ammo['22lr']==ammo-1 and target.health<hp,'host mouse shot bypassed or double-charged authority')
    check(next(battle.targetEffects)~=nil,'host authoritative hit lost private feedback')
    nextRequest=sequence()+1; button('r')
    check(sequence()==nextRequest and battle.gun.reloadTimer>0,'host reload input bypassed authority')
    for _=1,60 do app.update(.1) end
    check(battle.gun.reloadTimer==0,'authored host reload did not finish')
    local ownMag=battle.gun.magazine
    nextRequest=sequence()+1; button('l')
    check(sequence()==nextRequest and battle.gun.borrowed and data.lastStand.loanAmmo==48,'host loan input bypassed personal supply authority')
    check(data.ammo['22lr']==ammo-1 and data.lastStand.shooterSessions.companion.loanAmmo==0,'host borrowing changed another pool')
    nextRequest=sequence()+1; button('space')
    check(sequence()==nextRequest and data.lastStand.loanAmmo==47 and data.ammo['22lr']==ammo-1,'host keyboard loan shot charged the wrong pool')
    app.update(1); nextRequest=sequence()+1; button('tab')
    check(sequence()==nextRequest and battle.gun.itemId==ownId and not battle.gun.borrowed and battle.gun.magazine==ownMag,
        'host weapon input lost its cached exact owned magazine')
    local mode=battle.gun.fireMode; nextRequest=sequence()+1; button('v')
    check(sequence()==nextRequest and battle.gun.fireMode~=mode,'host selector input bypassed authority')
    button('v')
    local fx,fy=ox+877*sx,oy+650*sy
    nextRequest=sequence()+1
    app.touchpressed('native-host-fire',fx,fy,0,0,1); app.touchreleased('native-host-fire',fx,fy,0,0,1)
    check(sequence()==nextRequest and data.ammo['22lr']==ammo-2 and data.lastStand.loanAmmo==47,
        'simulated host touch shot bypassed authority or charged loan ammo')
    local cx,cy=ox+444*sx,oy+650*sy
    nextRequest=sequence()+1
    app.touchpressed('native-host-cover',cx,cy,0,0,1); app.touchreleased('native-host-cover',cx,cy,0,0,1)
    check(sequence()==nextRequest and battle.ducking,'simulated host touch cover bypassed authority')
    app.update(.1)
    local disk=assert(Save.read(99))
    check(disk.lastStand.loanAmmo==47 and disk.players.host.ammo['22lr']==ammo-2
        and disk.lastStand.weaponSession.itemId==ownId and disk.lastStand.combat.defenders.host.ducking,
        'native host input checkpoint lost its loan, exact gun, cost or cover')
    check(disk.players.companion.ammo['22lr']==38 and disk.lastStand.shooterSessions.companion.loanAmmo==0,
        'native host input changed the companion ammunition')
    check(lp:stop('fixture_done'),'native host listener did not stop')
end
local function hostProgressionChecks()
    local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
    check(c.enterGame(draft),'fresh host progression campaign load failed'); data=c.runtime.saveData
    local lp=c.ui.localPlay; lp.port='32179'; check(lp:host(),lp.error or 'host progression ENet listener failed')
    app.update(.01)
    local state=c.runtime.lastStand; check(state and state.mode=='approach','fresh quest did not approach')
    state.scout.x,state.scout.y=c.runtime.player.x+82,c.runtime.player.y; state.arrival=.6
    app.update(.01); check(state.mode=='offer' and data.lastStand.lifecycle.mode=='offer','offer did not use saved modal mode')
    local authority=lp.authority
    local function sequence() return authority.requests.host and authority.requests.host.high or 0 end
    local originalCheckpoint=authority.checkpoint; local nextRequest=sequence()+1
    authority.checkpoint=function() return false end
    button('y')
    check(sequence()==nextRequest and data.lastStand.state=='escort' and state.mode=='offer'
        and c.session.checkpointPending,'failed accept checkpoint advanced presentation or missed transaction')
    local revision=data.lastStand.lifecycle.revision
    button('y'); app.update(.1)
    check(state.mode=='offer' and data.lastStand.lifecycle.revision==revision and sequence()==nextRequest,
        'pending accept replayed or advanced scene')
    authority.checkpoint=originalCheckpoint
    button('r') -- Use the real Retry Save barrier; saves do not retry automatically.
    for _=1,4 do app.update(.05) end
    check(not c.session.checkpointPending and state.mode=='escort' and data.lastStand.lifecycle.revision==revision,
        'durable accept did not apply presentation exactly once')
    nextRequest=sequence()+1; button('return')
    check(sequence()==nextRequest and state.mode=='backyard' and data.lastStand.state=='backyard','escort advance bypassed command')
    state.scene.player.x,state.scene.player.y=480,360
    nextRequest=sequence()+1; button('e')
    check(sequence()==nextRequest and state.mode=='interior' and data.lastStand.conversations['enter-interior'],
        'backyard entry did not checkpoint its scene and conversation')
    state.scene.player.x,state.scene.player.y=350,285
    nextRequest=sequence()+1; button('e')
    check(state.handoff and sequence()==nextRequest and data.lastStand.firingPositions.host=='wide',
        'window selection did not checkpoint its host-owned position before handoff')
    for _=1,8 do app.update(.1) end
    check(sequence()==nextRequest+1 and state.mode=='shootout' and data.lastStand.combat
        and data.lastStand.conversations['window-wide'],'window start bypassed command or lost scene identity')
    battle=state.shootout
    local phase=data.lastStand.combat.phaseRevision
    local commands=lp.context.commands; local originalSubmit=commands.submit; local latestReply
    commands.submit=function(name,args) local reply=originalSubmit(name,args); latestReply=reply; return reply end
    nextRequest=sequence()+1; button('escape')
    commands.submit=originalSubmit
    check(sequence()==nextRequest and state.mode=='interior' and data.lastStand.combat.phaseRevision==phase+1,
        'host Escape did not invalidate the firing phase: '..tostring(latestReply and latestReply.reason)
        ..' seq='..sequence()..' expected='..nextRequest..' mode='..state.mode..' combat='..tostring(data.lastStand.combat.phaseRevision))
    state.scene.player.x,state.scene.player.y=350,285; button('e'); for _=1,8 do app.update(.1) end
    battle=state.shootout; battle.result='retreat'; battle.retreatReason='wounded'
    nextRequest=sequence()+1
    local rx,ry,rw,rh=Shootout.retryRect(960,720); local ox,oy,sx,sy=Viewport.transform(960,720)
    app.touchpressed('native-story-retry',ox+(rx+rw/2)*sx,oy+(ry+rh/2)*sy,0,0,1)
    app.touchreleased('native-story-retry',ox+(rx+rw/2)*sx,oy+(ry+rh/2)*sy,0,0,1)
    check(sequence()==nextRequest and state.mode=='shootout' and state.shootout.result==nil
        and data.lastStand.recoveries==1,'simulated host touch retry bypassed progression')
    state.shootout.result='intermission'; state.shootout.stage=2
    nextRequest=sequence()+1; app.update(.01)
    check(sequence()==nextRequest and state.mode=='interior' and data.lastStand.intermission==2,
        'combat intermission advanced without transaction')
    state.scene.player.x,state.scene.player.y=350,285; button('e'); for _=1,8 do app.update(.1) end
    state.shootout.result='victory'; nextRequest=sequence()+1; app.update(.01)
    check(sequence()==nextRequest and state.mode=='interior' and data.lastStand.victory,'victory bypassed host transaction')
    state.scene.player.x,state.scene.player.y=710,335; button('e')
    check(data.lastStand.residentChecked,'resident assistance check failed')
    state.scene.player.x,state.scene.player.y=300,335
    local scrap=data.scrap; nextRequest=sequence()+1; authority.checkpoint=function() return false end; button('e')
    check(sequence()==nextRequest and data.scrap==scrap+28 and state.mode=='interior' and c.session.checkpointPending,
        'failed reward checkpoint advanced scene or missed reward')
    button('e'); app.update(.1); check(data.scrap==scrap+28 and sequence()==nextRequest,'pending reward paid twice')
    authority.checkpoint=originalCheckpoint; button('r'); for _=1,4 do app.update(.05) end
    check(state.mode=='aftermath' and not c.session.checkpointPending,'reward presentation did not wait for durable checkpoint')
    nextRequest=sequence()+1; button('t'); check(sequence()==nextRequest and state.mode=='interior','stay longer bypassed progression')
    state.scene.player.x,state.scene.player.y=480,620; button('e'); check(state.mode=='backyard','post-victory backyard failed')
    state.scene.player.x,state.scene.player.y=480,605; button('e'); check(state.mode=='returning','backyard return route failed')
    local quest=data.lastStand; nextRequest=sequence()+1; button('return')
    check(sequence()==nextRequest and c.runtime.lastStand==nil and quest.completed and quest.state=='complete',
        'host completion bypassed saved progression')
    local disk=assert(Save.read(99)); check(disk.lastStand.completed and disk.lastStand.rewardScrap==28 and disk.scrap==scrap+28
        and disk.players.host.playerX==quest.returnX and disk.players.host.playerY==quest.returnY and Schema.validate(disk),
        'completed host progression/reward/return checkpoint was lost')
    check(lp:stop('fixture_done'),'progression host listener did not stop')
end
local function hostAidChecks()
    local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
    draft.lastStand={state='backyard',originStop=12,returnX=270,returnY=490,positionIntegrity=50}
    check(c.enterGame(draft),'host treatment campaign load failed'); app.update(.01); data=c.runtime.saveData
    local lp=c.ui.localPlay; lp.port='32179'; check(lp:host(),lp.error or 'host treatment ENet listener failed')
    app.update(.01)
    local authority=lp.authority; local checkpoint=authority.checkpoint; local state=c.runtime.lastStand
    state.scene.player.x,state.scene.player.y=750,455
    local submit=lp.context.commands.submit; local reply
    lp.context.commands.submit=function(name,args) reply=submit(name,args); return reply end
    button('e'); lp.context.commands.submit=submit
    check(state.treatment and state.treatment.command,'source host treatment was not command bound: '..tostring(reply and reply.reason)
        ..' mode='..tostring(state.mode)..' pending='..tostring(c.session.checkpointPending)
        ..' notice='..tostring(state.notice and state.notice.text))
    button('p'); check(state.paused and not state.treatment and not next(authority.activityState.resources),
        'host private pause retained the shared patient lock')
    button('p'); button('e'); check(state.treatment and state.treatment.command and not state.paused,'host treatment did not resume after private pause')
    for i=1,5 do button('return'); check(data.lastStand.treatmentProgress.phase==i+1,'source accessible treatment skipped its host command') end
    authority.checkpoint=function() return false end; button('return')
    check(c.session.checkpointPending and state.pendingAidComplete and not data.lastStand.woundedTreated,
        'final treatment gesture ignored failed checkpoint or completed early')
    button('return'); check(not data.lastStand.woundedTreated and data.lastStand.positionIntegrity==50,'pending source treatment applied benefit')
    authority.checkpoint=checkpoint
    lp.context.commands.submit=function(name,args)
        local result=submit(name,args)
        print('NATIVE_HOST_AID_RESULT command='..name..' action='..tostring(args.action)..' ok='..tostring(result.ok)..' reason='..tostring(result.reason))
        return result
    end
    button('r'); for _=1,4 do app.update(.05) end
    lp.context.commands.submit=submit
    check(not c.session.checkpointPending and not state.treatment and data.lastStand.woundedTreated
        and data.lastStand.positionIntegrity==62,'source treatment failed to resume completion after checkpoint retry: pending='
        ..tostring(c.session.checkpointPending)..' deferred='..tostring(state.pendingAidComplete)..' treatment='..tostring(state.treatment)
        ..' saved='..tostring(data.lastStand.woundedTreated)..' notice='..tostring(state.notice and state.notice.text)
        ..' last='..tostring(state.treatmentReply and state.treatmentReply.reason))
    local disk=assert(Save.read(99)); check(disk.lastStand.woundedTreated and disk.lastStand.positionIntegrity==62
        and disk.lastStand.treatmentProgress.wrapPasses==3,'source treatment completion not saved')
    button('e'); check(not state.treatment and data.lastStand.positionIntegrity==62,'source treatment repeated integrity benefit')
    check(lp:stop('host_aid_fixture_done'),'host treatment listener did not stop')
end
button=function(key) app.keypressed(key); app.keyreleased(key) end
local function openWindow()
    local state=c.runtime.lastStand
    check(state and state.mode=='interior','host did not restore the interior')
    state.scene.player.x,state.scene.player.y=350,285
    button('e'); check(state.handoff and state.handoff.window=='wide','host window action failed')
    for _=1,8 do app.update(.1) end
    check(state.mode=='shootout','host did not enter the firing phase')
    return state.shootout
end
point=function(state)
    for index=1,#state.targets do
        local x,y=Window.slotPosition(Window.layout(state.windowId,960,720),index)
        if Window.pointOpen(state.windowId,960,720,x,y) then return index,x,y end
    end
    error('no real bandit point inside the native aperture')
end
local function guard(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then print('COOP_LAST_STAND_STATE_FAIL '..tostring(reason)); finished=true; love.event.quit(1) end
end
local function load()
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    c.runtime.selectedSlot=99
    local draft=c.newSave(c.characters[1]); draft.location=12; draft.scene='stop'; draft.passengers={}
    draft.lastStand={state='interior',originStop=12,returnX=270,returnY=490,loanAmmo=0,loanActive=false}
    check(c.enterGame(draft),'campaign load failed'); data=c.runtime.saveData
    Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=40
    app.update(.01); battle=openWindow(); encounterId=data.lastStand.combat.entityId; epoch=data.coop.sceneEpoch
    check(State.campaignOf(battle)==data and Schema.validate(data),'host combat did not bind to a valid campaign')
    local character=c.characters[2] or c.characters[1]
    check(Players.enroll(data,'host',character,Catalog,{[character]=true}),'companion enrollment failed')
    local own=Players.forActor(data,'companion')
    Items.write(own,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); own.ammo['22lr']=40
    companion=assert(Shootout.forActor(battle,data,Catalog,'companion')); guestId=companion.gun.itemId
    check(guestId~=battle.gun.itemId,'host and companion shared gun identity')
    for _,target in ipairs(battle.targets) do target.status='hidden'; target.timer=999 end
    local index,x,y=point(battle); local target=battle.targets[index]; target.status='exposed'; target.timer=999
    local ox,oy,sx,sy=Viewport.transform(960,720)
    app.mousemoved(ox+x*sx,oy+y*sy,0,0,false)
    app.mousepressed(ox+x*sx,oy+y*sy,1,false); app.mousereleased(ox+x*sx,oy+y*sy,1,false)
    check(data.ammo['22lr']==39 and target.health==2,'native host shot missed or charged incorrectly')
    Shootout.setAim(companion,x,y); check(Shootout.fire(companion,own,960,720,Catalog),'companion domain shot failed')
    check(target.health==1 and own.ammo['22lr']==39 and data.ammo['22lr']==39,'shared target/personal ammunition mismatch')
    companion.gun.cooldown=0; check(Shootout.fire(companion,own,960,720,Catalog),'companion finishing shot failed')
    check(target.health==0 and data.lastStand.kills==1 and own.ammo['22lr']==38,'enemy was not eliminated exactly once')
    -- Lock a real enemy windup to the companion, then roll a deterministic hit.
    local enemy=battle.targets[index==1 and 2 or 1]; enemy.status='exposed'; enemy.timer=0
    battle.lastTargetActorId='host'; Shootout.update(battle,.01,data,Catalog,960,720,{'host','companion'})
    check(enemy.targetActorId=='companion' and enemy.status=='firing','enemy did not commit its target')
    data.coop.randomState=1; local hh,gh=data.health,own.health
    Shootout.update(battle,.01,data,Catalog,960,720,{'host','companion'})
    check(own.health==gh-1 and data.health==hh and not battle.result,'enemy damaged the wrong actor or ended the host defense')
    check(Shootout.reload(companion,own),'companion reload did not start')
    local timer=companion.gun.reloadTimer; Shootout.update(battle,.1,data,Catalog,960,720,{'host','companion'})
    check(math.abs(companion.gun.reloadTimer-(timer-.1))<.000001,'companion reload advanced more than once')
    Shootout.setCover(companion,true); Shootout.update(battle,.1,data,Catalog,960,720,{'host','companion'})
    check(companion.coverProgress>0 and not battle.ducking,'personal cover changed the host')
    check(Schema.validate(data),'post-combat campaign failed validation')
    commandChecks(index,x,y)
    check(Save.write(99,data),'native checkpoint failed')
    local disk=assert(Save.read(99)); local q=disk.lastStand; local g=q.shooterSessions.companion.weaponSession
    check(g.itemId==guestId and disk.players.companion.ammo['22lr']==38 and disk.players.host.ammo['22lr']==39,'disk gun/cost ownership mismatch')
    check(q.combat.defenders.companion.ducking and q.combat.defenders.companion.playerDamage==1 and not g.aimX,'disk defender/private-state mismatch')
    check(not q.targets[index].damageNumber and q.targets[index].health==0 and q.kills==1,'saved enemy pool or private effects mismatch')
    clock=q.combat.clock; remaining=g.reloadTimer; capture='01-native-shared-targets.png'; stage='restoring'
end
local function update(dt)
    if finished or not stage then return end
    if stage=='restoring' and not capture then
        local loaded=assert(Save.read(99)); check(c.enterGame(loaded),'disk reload failed'); data=c.runtime.saveData
        app.update(.01); battle=openWindow(); companion=assert(Shootout.forActor(battle,data,Catalog,'companion'))
        check(data.lastStand.combat.entityId==encounterId and data.coop.sceneEpoch==epoch,'restore replaced encounter or scene identity')
        check(companion.gun.itemId==guestId and data.players.companion.ammo['22lr']==38 and data.ammo['22lr']==39,'restore refilled or replaced a gun')
        check(companion.ducking and companion.playerDamage==1 and companion.gun.reloadTimer<=remaining,'restore lost the companion defender/reload')
        check(battle.clock>=clock and data.lastStand.kills==1,'restore reset combat time or eliminations')
        button('c'); app.update(.1); check(battle.ducking and battle.coverProgress>0,'restored host cover failed')
        capture='02-native-restored-cover.png'; stage='hostinput'
    elseif stage=='hostinput' and not capture then
        hostInputChecks(); capture='03-native-host-authority-cover.png'; stage='done'
    elseif stage=='done' and not capture then
        hostProgressionChecks()
        hostAidChecks()
        check(app.quit()~=true,'quit cancelled'); finished=true
        print('COOP_LAST_STAND_STATE_OK checks='..checks..' application=true nativeMasks=true actorAdapter=true commandAuthority=true hostInput=true hostTouch=true hostProgression=true hostAid=true finalAidRetry=true failedCheckpoint=true enetHost=true diskRestore=true networkGuest=false')
        love.event.quit(0)
    end
end
function love.load() guard(load) end
function love.update(dt) guard(update,dt) end
function love.draw()
    if not app or finished then return end
    guard(function() app.draw(); if capture then love.graphics.captureScreenshot(capture); capture=nil end end)
end
