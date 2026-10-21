local P=require('game.net.protocol')
local Areas=require('game.expedition_areas')
local Roaming=require('game.roaming_mobs')
local State=require('game.roaming_encounter_state')
local Cue=require('game.roaming_combat_state')
local Commands={}
local Players=require('game.coop_players')
function Commands.install(authority,context)
    authority:register('roaming.pressure',function(data,id,args,t)
        if not P.fields(args,{areaId=true,leadId=true}) or not P.text(args.areaId,64) or not P.text(args.leadId,32) then return nil,'invalid_args' end
        local own=data.players.companion
        local visitor=own and Players.forActor(data,'companion')
        local area=visitor and Areas.current(visitor)
        local host=context.actorState('host'); local target=context.actorState('companion')
        local lead,definition=State.enemy(data,args.areaId,args.leadId)
        local system=context.fieldState and context.fieldState()
        local transient=system and system.transient and system.transient[args.areaId] and definition and system.transient[args.areaId][definition.id]
        if not authority.bindings.companion or not own or own.health<=0 or data.health<=0 or not host or host.screen~='game'
            or host.encounterActive or host.traveling or host.changingCar
            or not target or target.screen~='game' or target.scene~='expedition' or target.movementReady==false or target.encounterActive
            or not area or args.areaId~=area.id or area.stop~=data.location or visitor.scene~='expedition'
            or data.roamingEncounter or data.tacticalBattle or data.expeditionBattle or data.events.current or data.coop.journey
            or not lead or lead.dead or lead.hp<=0 or not transient or transient.state~='windup' or transient.targetId~='companion'
            or not Cue.point(transient.timer) or transient.timer>0 or transient.timer< -1
            or not Cue.point(target.x) or not Cue.point(target.y)
            or (lead.x-target.x)^2+(lead.y-target.y)^2>((definition.reach or 82)+(definition.boss and 20 or 8))^2
            or not Areas.canReach(data,area.id,lead.x,lead.y,target.x,target.y,true) then return nil,'pressure_unavailable' end
        local roster=Roaming.participants(system,{area=area,areaState=data.expeditions[area.id],player=host,
            isActive=function(mob) return not mob.requires or data.expeditions[area.id].gates[mob.requires]==true end,
            canReach=function(x1,y1,x2,y2) return Areas.canReach(data,area.id,x1,y1,x2,y2,true) end},definition,target)
        local ids={}; for _,enemy in ipairs(roster) do ids[#ids+1]=data.expeditions[area.id].mobs[enemy.mobId].entityId end
        if ids[1]~=args.leadId then return nil,'pressure_unavailable' end
        return {scopes={'world:scene','combat:roaming','party','entity:'..data.expeditions[area.id].entityId,
            'player:host','player:companion'},checkpoint=true,apply=function()
            data.roamingEncounter={version=1,id=State.id(data.coop.sceneEpoch,args.leadId),epoch=data.coop.sceneEpoch,
                areaId=area.id,actorId='companion',leadId=args.leadId,enemyIds=ids,x=target.x,y=target.y}
            t.state.resources={}
            return {pressureId=data.roamingEncounter.id}
        end}
    end)
end
return Commands
