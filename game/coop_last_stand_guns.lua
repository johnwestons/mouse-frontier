-- Actor-owned gun commands against a saved firing phase. Story transitions remain
-- host decisions; this adapter has no scene progression or device effects.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Items=require('game.item_instances')
local Shooting=require('game.first_person_shooting')
local Sessions=require('game.coop_shooter_sessions')
local State=require('game.coop_last_stand_state')
local Shootout=require('game.last_stand_shootout')
local Window=require('game.window_scene')
local Life=require('game.coop_last_stand_lifecycle')
local Positions=require('game.coop_last_stand_positions')
local Commands={WIDTH=960,HEIGHT=720,POINT=1000000}
function Commands.scopes(data,id)
    local combat=data.lastStand and data.lastStand.combat
    if not combat or not combat.entityId then return {} end
    return {'world:scene','entity:'..combat.entityId,'player:'..id,'resources','world:maintenance','story:events'}
end
function Commands.prepare(name,data,id,args,context,transaction)
    local fields={mode=true,encounterId=true,phaseRevision=true,weaponId=true}
    if name=='gun.fire' then fields.x=true; fields.y=true end
    if name=='gun.cover' then fields.cover=true end
    if name=='gun.mode' then fields.direction=true end
    if not P.fields(args,fields) or args.mode~='lastStand' or not P.text(args.encounterId,32)
        or not P.integer(args.phaseRevision,1,1e9)
        or name~='gun.cover' and name~='lastStand.supply' and not P.text(args.weaponId,32)
        or name=='gun.cover' and (args.weaponId~=nil or type(args.cover)~='boolean')
        or name=='lastStand.supply' and args.weaponId~=nil
        or name=='gun.mode' and args.direction~=nil and args.direction~=1 and args.direction~=-1
        or name=='gun.fire' and (not P.integer(args.x,0,Commands.POINT) or not P.integer(args.y,0,Commands.POINT)) then return nil,'invalid_args' end
    local quest=data.lastStand; local combat=quest and quest.combat
    local actor=context.actorState(id); local ready=context.lastStandState and context.lastStandState(id)
    local own=Players.forActor(data,id)
    if not combat or combat.version~=State.VERSION or combat.entityId~=args.encounterId
        or quest.state~='shootout' or quest.victory or combat.result or quest.originStop~=data.location
        or data.scene~='stop' or not actor or actor.screen~='game' or actor.scene~='stop'
        or actor.traveling or actor.changingCar or actor.activeActivity
        or data.tacticalBattle or data.roamingEncounter or data.coop.journey
        or not ready or ready.active~=true or ready.paused or ready.encounterId~=combat.entityId
        or not combat.defenders[id] or own.health<=1 then return nil,'shooter_unavailable' end
    if combat.phaseRevision~=args.phaseRevision or ready.phaseRevision~=combat.phaseRevision then return nil,'stale_phase' end
    if id~='host' and (actor.movementReady~=true or actor.modalDomain~=Life.key(data)) then return nil,'shooter_unavailable' end
    local lease
    if transaction and transaction.bindings then lease=Positions.occupied(data,transaction.state,transaction.bindings,transaction.now,id)
    elseif context.lastStandPosition then lease=context.lastStandPosition(id) end
    if not lease or lease.windowId~=combat.defenders[id].windowId then return nil,'position_expired' end
    local item; local borrowed=args.weaponId=='loan:'..id
    local scope=id=='host' and quest or quest.shooterSessions and quest.shooterSessions[id]
    if name~='gun.cover' and name~='lastStand.supply' then
        if not borrowed then
            item=Items.selection(own,args.weaponId,context.catalog)
            local spec=item and context.catalog.weaponCombat[item.name]
            if not item or not spec or spec.kind~='ranged' or not spec.ammo or spec.ammo=='arrows'
                or spec.ammo=='rocks' or spec.ammo=='ball-bearings' then return nil,'ownership' end
            if item.durability<=0 then return nil,'weapon_broken' end
        end
        local selected=scope and scope.weaponSession
        if name~='gun.select' and (not selected or borrowed and (not selected.borrowed or not scope.loanActive or selected.actorId~=id)
            or not borrowed and (selected.itemId~=item.id or selected.borrowed)) then return nil,'weapon_changed' end
    end
    return {scopes=Commands.scopes(data,id),checkpoint=true,apply=function()
        local owner=combat.defenders[id]
        local result={actorId=id,mode='lastStand',encounterId=combat.entityId,phaseRevision=combat.phaseRevision}
        if name=='gun.cover' then owner.ducking=args.cover; result.cover=args.cover; return result end
        scope=Sessions.scope(own,quest)
        local gun=scope.weaponSession and Sessions.view(scope.weaponSession,Commands.WIDTH,Commands.HEIGHT)
            or Shooting.new(own,context.catalog,quest,Commands.WIDTH,Commands.HEIGHT)
        if name=='gun.select' then
            if gun.cooldown>0 or gun.reloadTimer>0 then return nil,'weapon_busy' end
            gun=Shooting.chooseWeapon(gun,{name=borrowed and 'frontier-22-lever-rifle' or item.name,
                itemId=item and item.id,borrowed=borrowed},own,context.catalog,quest)
            if borrowed and not gun.borrowed or not borrowed and gun.itemId~=item.id then return nil,'ownership' end
        elseif name=='lastStand.supply' then
            if gun.reloadTimer>0 or gun.cooldown>0 then return nil,'weapon_busy' end
            if gun.borrowed and Shooting.rounds(gun,own,quest)>0 then return nil,'supply_unavailable' end
            local before=scope.loanAmmo or 0
            gun=Shooting.useLoan(gun,own,context.catalog,quest)
            if not gun.borrowed or not Sessions.owned(gun,own) then return nil,'ownership' end
            result.suppliedRounds=math.max(0,scope.loanAmmo-before)
        elseif name=='gun.reload' then
            if not Shooting.reload(gun,own,quest) then return nil,'reload_unavailable' end
        elseif name=='gun.mode' then
            if not Shooting.cycleFireMode(gun,args.direction) then return nil,'mode_unavailable' end
        else
            if owner.ducking or owner.coverProgress>0 then return nil,'in_cover' end
            local x,y=args.x/Commands.POINT*Commands.WIDTH,args.y/Commands.POINT*Commands.HEIGHT
            if not Window.pointOpen(owner.windowId,Commands.WIDTH,Commands.HEIGHT,x,y) then return nil,'window_blocked' end
            local view=Shootout.commandView(quest,data,id,gun,Commands.WIDTH,Commands.HEIGHT)
            local shot,reason=Shootout.fireAt(view,own,Commands.WIDTH,Commands.HEIGHT,context.catalog,x,y)
            if not shot then return nil,reason end
            result.fired=true; result.hit=shot.hit
        end
        result.weaponId=gun.borrowed and 'loan:'..id or item.id; result.weapon=gun.weapon; result.magazine=gun.magazine
        result.rounds=Shooting.rounds(gun,own,quest); result.fireMode=gun.fireMode
        if name~='gun.fire' then result.reloading=gun.reloadTimer>0 end
        return result
    end}
end
return Commands
