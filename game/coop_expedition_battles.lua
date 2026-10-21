-- Expedition combat derives its roster from saved enemies in the host's area.
local Areas=require('game.expedition_areas')
local Entities=require('game.coop_entities')
local Actors=require('game.battle_actors')
local Party=require('game.party_scene')
local Rewards=require('game.expedition_rewards')
local P=require('game.net.protocol')
local Expedition={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<100000 end
function Expedition.entry(data,host,args)
    local lead,record=Entities.find(data,args.encounterId)
    local pressure=data.roamingEncounter
    local areaId=pressure and pressure.areaId or data.activeExpeditionArea; local definition=Areas.definition(areaId)
    if not lead or record.kind~='expeditionMob' or record.areaId~=areaId or not pressure and data.scene~=Areas.SCENE
        or not definition or definition.stop~=data.location or not finite(host.x) or not finite(host.y)
        or not pressure and not Areas.isWalkable(data,areaId,host.x,host.y,true) then return nil,'battle_unavailable' end
    local ids=args.enemyIds
    if type(ids)~='table' or #ids<1 or #ids>6 or ids[1]~=args.encounterId then return nil,'invalid_enemies' end
    local count=0; for key in pairs(ids) do if not P.integer(key,1,#ids) then return nil,'invalid_enemies' end; count=count+1 end
    if count~=#ids then return nil,'invalid_enemies' end
    local anchor=host
    if pressure then
        if not require('game.roaming_encounter_state').validate(data) or pressure.leadId~=args.encounterId
            or #pressure.enemyIds~=#ids then return nil,'pressure_unavailable' end
        for i,id in ipairs(ids) do if pressure.enemyIds[i]~=id then return nil,'pressure_unavailable' end end
        anchor={x=pressure.x,y=pressure.y}
    end
    local states,files,seen={}, {}, {}; local boss=false
    for _,id in ipairs(ids) do
        if not P.text(id,32) or seen[id] then return nil,'invalid_enemies' end; seen[id]=true
        local saved,descriptor=Entities.find(data,id)
        local mob=descriptor and descriptor.kind=='expeditionMob' and Areas.mobDefinition(areaId,descriptor.key)
        if not mob or descriptor.areaId~=areaId or saved.dead or saved.hp<=0 or not Areas.isMobActive(data,areaId,mob)
            or (saved.x-anchor.x)^2+(saved.y-anchor.y)^2>330^2
            or not Areas.canReach(data,areaId,saved.x,saved.y,anchor.x,anchor.y) then return nil,'enemy_unavailable' end
        states[#states+1]={entityId=id,mobId=mob.id,file=mob.file,name=mob.name,hp=saved.hp,maxHp=saved.maxHp,
            tier=mob.tier,boss=mob.boss==true,weapon='mob-claw'}
        files[#files+1]=mob.file; boss=boss or mob.boss==true
    end
    local point=data.scene==Areas.SCENE and data.activeExpeditionArea==areaId and host or anchor
    return {source='expedition',entityId=lead.entityId,areaId=areaId,tier=states[1].tier,boss=boss,
        rolled=true,hasMob=true,resolved=false,mobFiles=files,enemyStates=states,
        returnContext={scene=Areas.SCENE,areaId=areaId,x=point.x,y=point.y}}
end
function Expedition.validate(data,battle,id)
    local e=battle.encounter; local area=data.expeditions and data.expeditions[e.areaId]
    local definition=Areas.definition(e.areaId); local lead,record=Entities.find(data,id); local point=e.returnContext
    if not area or not definition or definition.stop~=data.location or data.scene~=Areas.SCENE
        or data.activeExpeditionArea~=e.areaId or not lead or record.kind~='expeditionMob' or record.areaId~=e.areaId
        or not P.fields(point,{scene=true,areaId=true,x=true,y=true}) or point.scene~=Areas.SCENE or point.areaId~=e.areaId
        or not finite(point.x) or not finite(point.y) or not Areas.isWalkable(data,e.areaId,point.x,point.y,true)
        or type(e.enemyStates)~='table' or type(e.mobFiles)~='table' or #e.enemyStates<1 or #e.enemyStates>6
        or #e.mobFiles~=#e.enemyStates or type(e.enemyStates[1])~='table' or e.enemyStates[1].entityId~=id then return false end
    local seen,count={},0
    for _,list in ipairs({e.enemyStates,e.mobFiles}) do
        local length=0
        for key in pairs(list) do if not P.integer(key,1,#e.enemyStates) then return false end; length=length+1 end
        if length~=#e.enemyStates then return false end
    end
    for _,unit in ipairs(battle.units) do
        if unit.team=='enemy' then
            if not P.text(unit.mobId,64) then return false end
            count=count+1; local mob=Areas.mobDefinition(e.areaId,unit.mobId); local saved=mob and area.mobs[unit.mobId]
            local initial=e.enemyStates[count]
            if not saved or seen[unit.mobId] or type(initial)~='table' or initial.entityId~=saved.entityId or initial.mobId~=unit.mobId
                or unit.file~=mob.file or e.mobFiles[count]~=mob.file then return false end
            seen[unit.mobId]=true
        end
    end
    return count==#e.enemyStates
end
function Expedition.sync(data,battle)
    local e=battle.encounter; if e.source~='expedition' then return end
    local area=data.expeditions[e.areaId]
    for _,unit in ipairs(battle.units) do
        local saved=unit.team=='enemy' and area.mobs[unit.mobId]
        if saved then saved.hp=math.max(0,math.min(saved.maxHp,unit.hp)); saved.dead=saved.hp<=0 end
    end
    Areas.updateGates(data,e.areaId)
end
function Expedition.finish(data,battle,catalog,outcome,t,context)
    Expedition.sync(data,battle); Rewards.claimBattle(data,catalog,battle)
    for _,unit in ipairs(Actors.units(battle)) do
        local actor=Actors.data(data,unit)
        actor.health=outcome=='loss' and math.max(1,math.floor(actor.maxHealth/2)) or math.max(1,actor.health)
        actor.battlePotionLootChance=nil
    end
    local e=battle.encounter; local positions,reason
    if outcome=='win' then
        data.scene=Areas.SCENE; data.activeExpeditionArea=e.areaId
        positions,reason=Party.place(data,function(id,actor)
            if id=='host' then return e.returnContext.x,e.returnContext.y end
            return actor.playerX or e.returnContext.x,actor.playerY or e.returnContext.y
        end,function(x,y) return Areas.clamp(data,e.areaId,x,y) end)
    else
        data.scene='train'; data.activeExpeditionArea=nil; data.activeHouseDoor=nil
        positions,reason=Party.place(data,function(id,actor)
            actor.activeCar=1
            if context.trainSpawn then return context.trainSpawn(data,id) end
            local car=context.car or require('game.config').trainCar; return car.x+90,car.y+180
        end,function(x,y,id)
            if context.trainClamp then return context.trainClamp(data,id,x,y) end
            local car=context.car or require('game.config').trainCar
            return math.max(car.x,math.min(car.x+car.w,x)),math.max(car.y,math.min(car.y+car.h,y))
        end)
    end
    if not positions then return nil,reason end
    data.tacticalBattle=nil
    local result,message=Party.commit(data,t,positions,'game'); if not result then return nil,message end
    result.outcome=outcome; result.battleSource='expedition'; result.expeditionReturn=true
    return result
end
return Expedition
