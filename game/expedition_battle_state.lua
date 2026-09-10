local Areas=require("game.expedition_areas")
local Rewards=require("game.expedition_rewards")

local State={VERSION=1}

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

function State.isExpedition(battle)
    return type(battle)=="table" and type(battle.encounter)=="table" and battle.encounter.source=="expedition"
end

-- Keep the plain battle table attached to the save while it is active. Focus
-- and shutdown saves then include the same turn, HP, ammo and item transaction,
-- even when they run between a player action and the next update checkpoint.
function State.capture(data,battle)
    if not State.isExpedition(battle) then return false end
    data.expeditionBattle={version=State.VERSION,battle=battle}
    return true
end

function State.pending(data)
    local pending=data and data.expeditionBattle
    if pending==nil then return nil end
    if type(pending)~="table" or pending.version~=State.VERSION or not State.isExpedition(pending.battle) then
        return nil,"invalid expedition battle checkpoint"
    end
    local battle=pending.battle
    local encounter=battle.encounter
    local destination=encounter.returnContext
    if not Areas.isArea(encounter.areaId) or type(destination)~="table" or destination.areaId~=encounter.areaId
        or not finite(destination.x) or not finite(destination.y) then return nil,"invalid battle return point" end
    if type(battle.units)~="table" or #battle.units<2 or not finite(battle.active)
        or battle.active%1~=0 or not battle.units[battle.active] then return nil,"invalid battle roster" end
    local player,enemy=false,false
    for _,unit in ipairs(battle.units) do
        if type(unit)~="table" or not finite(unit.hp) or not finite(unit.maxHP) or unit.maxHP<=0
            or not finite(unit.q) or not finite(unit.r) then return nil,"invalid battle unit" end
        if unit.id=="player" and unit.team=="ally" then player=true end
        if unit.team=="enemy" then
            if not Areas.mobDefinition(encounter.areaId,unit.mobId) then return nil,"unknown expedition enemy" end
            enemy=true
        end
    end
    if not player or not enemy or type(battle.tiles)~="table" or type(battle.tileVariants)~="table"
        or type(battle.obstacles)~="table" then return nil,"incomplete expedition battlefield" end
    if battle.finished and battle.finished~="win" and battle.finished~="loss" then return nil,"invalid expedition outcome" end
    return battle
end

function State.syncEnemies(data,catalog,battle)
    if not State.isExpedition(battle) then return end
    local areaState=Areas.state(data,battle.encounter.areaId)
    if not areaState then return end
    for _,unit in ipairs(battle.units or {}) do
        local saved=unit.team=="enemy" and unit.mobId and areaState.mobs[unit.mobId]
        if saved then
            saved.hp=math.max(0,math.min(saved.maxHp or unit.maxHP,unit.hp or 0))
            saved.dead=saved.hp<=0
        end
    end
    local receipt=Rewards.claimBattle(data,catalog,battle)
    Areas.updateGates(data,battle.encounter.areaId)
    return receipt
end

function State.settle(data,catalog,battle,outcome)
    if not State.isExpedition(battle) then return nil end
    State.syncEnemies(data,catalog,battle)
    data.expeditionBattle=nil
    data.battlePotionLootChance=nil
    battle.expeditionDestinationApplied=true
    if outcome=="win" then
        local destination=battle.encounter.returnContext
        data.scene="expedition"; data.activeExpeditionArea=destination.areaId
        data.playerX,data.playerY=destination.x,destination.y
        return {scene="expedition",areaId=destination.areaId,x=destination.x,y=destination.y}
    end
    data.scene="train"; data.activeExpeditionArea=nil
    data.playerX,data.playerY=nil,nil
    if outcome=="loss" then data.health=math.max(1,math.floor((data.maxHealth or 20)/2))
    else data.health=math.max(1,data.health or 1) end
    return {scene="train"}
end

-- Run before creating the player. A completed result interrupted before its
-- destination was applied is reconciled exactly once; an invalid checkpoint
-- recovers safely to the train without discarding the rest of the save.
function State.recover(data,catalog)
    local battle,errorMessage=State.pending(data)
    if errorMessage then
        data.expeditionBattle=nil; data.scene="train"; data.activeExpeditionArea=nil
        data.playerX,data.playerY=nil,nil
        data.health=math.max(1,data.health or 1)
        return nil,true,errorMessage
    end
    if not battle then return nil,false end
    if battle.finished then State.settle(data,catalog,battle,battle.finished); return nil,true end
    local destination=battle.encounter.returnContext
    data.scene="expedition"; data.activeExpeditionArea=destination.areaId
    data.playerX,data.playerY=destination.x,destination.y
    return battle,false
end

return State
