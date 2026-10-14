-- A companion contact holds the field scene until the campaign owner chooses.
local Areas=require('game.expedition_areas')
local P=require('game.net.protocol')
local State={}
function State.id(epoch,leadId) return 'p:'..epoch..':'..leadId end
function State.enemy(data,areaId,entityId)
    local area=Areas.definition(areaId); local state=data.expeditions and data.expeditions[areaId]
    for _,definition in ipairs(area and area.mobs or {}) do
        local mob=type(state)=='table' and type(state.mobs)=='table' and state.mobs[definition.id]
        if type(mob)=='table' and mob.entityId==entityId then return mob,definition end
    end
end
local function point(n) return type(n)=='number' and n==n and math.abs(n)<100000 end
function State.validate(data)
    local s=data.roamingEncounter; if s==nil then return true end
    if not P.fields(s,{version=true,id=true,epoch=true,areaId=true,actorId=true,leadId=true,enemyIds=true,x=true,y=true})
        or s.version~=1 or not data.coop or s.epoch~=data.coop.sceneEpoch or not P.integer(s.epoch,1,2147483647)
        or not P.text(s.areaId,64) or not P.text(s.leadId,32) or s.id~=State.id(s.epoch,s.leadId)
        or s.actorId~='companion' or not data.players or not data.players.companion
        or not point(data.players.companion.health) or data.players.companion.health<=0
        or data.scene~='expedition' or data.activeExpeditionArea~=s.areaId or data.tacticalBattle or data.expeditionBattle
        or data.events and data.events.current or data.coop.journey or not point(s.x) or not point(s.y)
        or not Areas.isWalkable(data,s.areaId,s.x,s.y,true) or type(s.enemyIds)~='table'
        or #s.enemyIds<1 or #s.enemyIds>6 or s.enemyIds[1]~=s.leadId then return false end
    local area=Areas.definition(s.areaId); local state=data.expeditions and data.expeditions[s.areaId]
    if not area or area.stop~=data.location or not state then return false end
    local seen,count={},0
    for key,id in pairs(s.enemyIds) do
        if not P.integer(key,1,#s.enemyIds) or not P.text(id,32) or seen[id] then return false end
        local mob,definition=State.enemy(data,s.areaId,id)
        if not mob or mob.dead or not point(mob.hp) or mob.hp<=0 or not point(mob.maxHp) or mob.hp>mob.maxHp
            or not point(mob.x) or not point(mob.y) or definition.requires and not (state.gates and state.gates[definition.requires])
            or (mob.x-s.x)^2+(mob.y-s.y)^2>330^2 or not Areas.canReach(data,s.areaId,mob.x,mob.y,s.x,s.y,true) then return false end
        seen[id]=true; count=count+1
    end
    return count==#s.enemyIds
end
return State
