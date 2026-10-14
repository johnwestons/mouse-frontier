-- Strict owned first-person commands. Private aim travels only with a shot;
-- damage, targets, ammo, timing and story outcomes are derived by the host.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Items=require('game.item_instances')
local Shooting=require('game.first_person_shooting')
local Sessions=require('game.coop_shooter_sessions')
local State=require('game.coop_ambush_state')
local Rules=require('game.train_ambush_rules')
local Scene=require('game.train_ambush_scene')
local Commands={WIDTH=960,HEIGHT=720,POINT=1000000}
local names={'gun.fire','gun.reload','gun.cover','gun.mode','gun.select'}
function Commands.scopes(data,id,mode)
    if mode=='lastStand' then return require('game.coop_last_stand_guns').scopes(data,id) end
    local state=data.trainAmbush
    if not state or not state.entityId then return {} end
    return {'world:scene','entity:'..state.entityId,'player:'..id,'resources','world:maintenance','story:events'}
end
function Commands.install(authority,context)
    authority:register('lastStand.supply',function(data,id,args,transaction)
        if args.mode=='farmhouse' then return require('game.coop_last_stand_provider').prepare(data,id,args,context) end
        return require('game.coop_last_stand_guns').prepare('lastStand.supply',data,id,args,context,transaction)
    end)
    for _,name in ipairs(names) do
        authority:register(name,function(data,id,args,transaction)
            if args.mode=='lastStand' then return require('game.coop_last_stand_guns').prepare(name,data,id,args,context,transaction) end
            local allowed={mode=true,encounterId=true,weaponId=true}
            if name=='gun.fire' then allowed.x=true; allowed.y=true end
            if name=='gun.cover' then allowed.cover=true end
            if not P.fields(args,allowed) or args.mode~='ambush' or not P.text(args.encounterId,32)
                or name~='gun.cover' and not P.text(args.weaponId,32)
                or name=='gun.cover' and (args.weaponId~=nil or type(args.cover)~='boolean')
                or name=='gun.fire' and (not P.integer(args.x,0,Commands.POINT) or not P.integer(args.y,0,Commands.POINT)) then return nil,'invalid_args' end
            local state=data.trainAmbush; local actor=context.actorState(id)
            local ready=context.ambushState and context.ambushState(id)
            local own=Players.forActor(data,id)
            if not state or state.active~=true or (state.phase~='combat' and state.phase~='approach')
                or name=='gun.fire' and state.phase~='combat' or state.outcome or state.location~=data.location
                or state.entityId~=args.encounterId or state.defendersVersion~=State.VERSION
                or data.scene~='train' or not actor or actor.screen~='game' or actor.scene~='train'
                or actor.traveling or actor.changingCar or actor.activeActivity
                or data.tacticalBattle or data.roamingEncounter or data.coop.journey
                or not ready or ready.active~=true or ready.paused or ready.encounterId~=state.entityId
                or own.health<=1 then return nil,'shooter_unavailable' end
            local item
            if name~='gun.cover' then
                item=Items.selection(own,args.weaponId,context.catalog)
                local spec=item and context.catalog.weaponCombat[item.name]
                if not item or not spec or spec.kind~='ranged' or not spec.ammo or spec.ammo=='arrows'
                    or spec.ammo=='rocks' or spec.ammo=='ball-bearings' then return nil,'ownership' end
                if item.durability<=0 then return nil,'weapon_broken' end
                local scope=id=='host' and state or state.shooterSessions and state.shooterSessions[id]
                local selected=scope and scope.weaponSession
                if name~='gun.select' and selected and (selected.itemId~=item.id or selected.borrowed) then return nil,'weapon_changed' end
            end
            return {scopes=Commands.scopes(data,id),checkpoint=true,apply=function()
                local owner=State.owner(state,id,true)
                if name=='gun.cover' then
                    owner.cover=args.cover
                    return {actorId=id,mode='ambush',encounterId=state.entityId,cover=owner.cover}
                end
                local scope=Sessions.scope(own,state)
                -- Preserve an inert old selection while switching away from
                -- a sold/broken gun. A fallback factory could overwrite the
                -- next exact gun's cached partial magazine with a fresh load.
                local gun=scope.weaponSession and Sessions.view(scope.weaponSession,Commands.WIDTH,Commands.HEIGHT)
                    or Shooting.new(own,context.catalog,state,Commands.WIDTH,Commands.HEIGHT)
                if name=='gun.select' then
                    gun=Shooting.chooseWeapon(gun,{name=item.name,itemId=item.id,borrowed=false},own,context.catalog,state)
                    if gun.itemId~=item.id then return nil,'ownership' end
                elseif gun.itemId~=item.id or gun.borrowed then return nil,'weapon_changed'
                elseif name=='gun.reload' then
                    if not Shooting.reload(gun,own,state) then return nil,'reload_unavailable' end
                elseif name=='gun.mode' then
                    if not Shooting.cycleFireMode(gun) then return nil,'mode_unavailable' end
                else
                    if owner.cover or owner.coverProgress>0 then return nil,'in_cover' end
                    local x,y=args.x/Commands.POINT*Commands.WIDTH,args.y/Commands.POINT*Commands.HEIGHT
                    local pose=State.view(state,id)
                    local open=(context.ambushOpen or Scene.pointOpen)(pose,Commands.WIDTH,Commands.HEIGHT,x,y)
                    if not open then return nil,'window_blocked' end
                    local fired,reason=Shooting.fire(gun,own,state); if not fired then return nil,reason end
                    state.shots=state.shots+1
                    local target=(context.ambushTarget or Scene.target)(pose,Commands.WIDTH,Commands.HEIGHT,x,y)
                    local hit=Rules.hit(data,state,target,gun,id)
                    return {actorId=id,mode='ambush',encounterId=state.entityId,weaponId=item.id,weapon=gun.weapon,
                        fired=true,hit=hit==true,magazine=gun.magazine,rounds=Shooting.rounds(gun,own,state),fireMode=gun.fireMode}
                end
                return {actorId=id,mode='ambush',encounterId=state.entityId,weaponId=item.id,weapon=gun.weapon,
                    magazine=gun.magazine,rounds=Shooting.rounds(gun,own,state),fireMode=gun.fireMode,reloading=gun.reloadTimer>0}
            end}
        end)
    end
end
return Commands
