-- Both local and remote field attacks use owned equipment and host simulation.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Areas=require('game.expedition_areas')
local Roaming=require('game.roaming_mobs')
local Random=require('game.coop_random')
local Rewards=require('game.expedition_rewards')
local Schema=require('game.save_schema')
local State=require('game.roaming_combat_state')
local Commands={}
function Commands.scopes(data,id)
    local result={'world:scene','combat:roaming','entity:'..data.expeditions[data.activeExpeditionArea].entityId,
        'rng','resources','player:host'}
    if data.players.companion then result[#result+1]='player:companion' end
    return result
end
function Commands.weapon(data,id,catalog)
    local actor=Players.get(data,id)
    for i=1,2 do
        local item=actor and actor.itemSlots and actor.itemSlots.equipment[i]
        local combat=item and catalog.weaponCombat[item.name]
        if item and item.name~='scratch' and catalog.weaponStats[item.name] and (not combat or combat.kind~='ranged')
            and (item.durability or 100)>0 then return item.id end
    end
    return 'scratch'
end
function Commands.install(authority,context)
    authority:register('roaming.attack',function(data,id,args,t)
        if not P.fields(args,{areaId=true,weaponId=true,targetX=true,targetY=true}) or not P.text(args.areaId,64)
            or not P.text(args.weaponId,64) or (args.targetX~=nil or args.targetY~=nil)
                and (not State.point(args.targetX) or not State.point(args.targetY)) then return nil,'invalid_args' end
        local actor=context.actorState(id); local own=Players.forActor(data,id)
        local area=Areas.current(data); local saved=area and data.expeditions[area.id]
        if not actor or actor.screen~='game' or actor.scene~='expedition' or data.scene~='expedition' or not area
            or area.stop~=data.location or not saved or args.areaId~=area.id or own.health<=0
            or actor.traveling or actor.changingCar or actor.encounterActive or actor.activityBlocked
            or data.tacticalBattle or data.expeditionBattle or data.roamingEncounter or data.events.current or data.coop.journey
            or not State.point(actor.x) or not State.point(actor.y) or not Areas.isWalkable(data,area.id,actor.x,actor.y) then return nil,'field_unavailable' end
        local ref
        for i=1,2 do
            local item=own.itemSlots and own.itemSlots.equipment[i]
            if item and item.id==args.weaponId then
                local combat=context.catalog.weaponCombat[item.name]
                if item.name=='scratch' or not context.catalog.weaponStats[item.name] or combat and combat.kind=='ranged' then return nil,'melee_required' end
                ref={kind='equipment',index=i}; break
            end
        end
        local unarmed=args.weaponId=='scratch'
        if unarmed and Commands.weapon(data,id,context.catalog)~='scratch' then return nil,'ownership' end
        if not ref and not unarmed then return nil,'ownership' end
        local cooldown=t.state.fieldCooldowns and t.state.fieldCooldowns[id]
        if cooldown and cooldown.epoch==data.coop.sceneEpoch and t.now+1e-9<cooldown.untilTime then return nil,'attack_cooldown' end
        if data.roamingCombat and data.roamingCombat.serial>=2147483647 then return nil,'field_serial_exhausted' end
        return {scopes=Commands.scopes(data,id),checkpoint=true,apply=function()
            local sys=context.fieldState and Schema.copy(context.fieldState()) or Roaming.new()
            if not sys then return nil,'field_unavailable' end
            sys.attackTimer=0
            local pose={x=actor.x,y=actor.y,facing=actor.facing or own.playerFacing or 1,intentX=actor.intentX,intentY=actor.intentY}
            local alerts={}
            local ctx={data=own,area=area,areaState=saved,player=pose,actorId=id,catalog=context.catalog,weaponRef=ref,unarmed=unarmed,
                rng=Random.range(Random.generator(data,t.randomSeed)),isWeapon=function(name) return context.catalog.weaponStats[name]~=nil end,
                isActive=function(mob) return Areas.isMobActive(data,area.id,mob) end,
                canReach=function(x1,y1,x2,y2) return Areas.canReach(data,area.id,x1,y1,x2,y2) end,
                onAlert=function(mobId) alerts[#alerts+1]=mobId end,
                onDefeated=function(definition,mob)
                    local ids=authority.bindings.companion and {'host','companion'} or {'host'}
                    return Rewards.summary(Rewards.claimEnemy(data,context.catalog,definition,mob,ids))
                end}
            local used,reason,result=Roaming.attack(sys,ctx,args.targetX,args.targetY)
            if not used then return nil,reason and 'weapon_broken' or 'field_unavailable' end
            own.playerFacing=pose.facing
            Areas.updateGates(data,area.id)
            data.roamingCombat=data.roamingCombat or {version=1,serial=0,actors={}}
            local combat=data.roamingCombat; combat.serial=combat.serial+1
            result.serial=combat.serial; result.epoch=data.coop.sceneEpoch; result.areaId=area.id; result.actorId=id
            result.x=actor.x; result.y=actor.y; result.alerts=alerts
            combat.actors[id]=result
            t.state.fieldCooldowns=t.state.fieldCooldowns or {}
            t.state.fieldCooldowns[id]={epoch=data.coop.sceneEpoch,untilTime=t.now+result.duration}
            return result
        end}
    end)
end
return Commands
