local PlayerProgression = require("game.player_progression")
local BattleRules = {}

BattleRules.directions = {{1, 0}, {0, -1}, {-1, 0}, {0, 1}}

function BattleRules.distance(a, b)
    return math.abs(a.q - b.q) + math.abs(a.r - b.r)
end

function BattleRules.unitAt(battle, q, r)
    if not battle then return nil end
    for index, unit in ipairs(battle.units or {}) do
        if unit.hp > 0 and unit.q == q and unit.r == r then
            return unit, index
        end
    end
end

function BattleRules.terrainAt(battle, q, r)
    local value = battle and battle.tiles and battle.tiles[q] and battle.tiles[q][r] or 1
    if value == 3 or value == 4 or value == 6 then return "cover", 2 end
    if value == 2 or value == 5 then return "rough", 1 end
    return "open", 0
end

function BattleRules.isBoardSpace(battle, q, r)
    return battle and battle.tiles and battle.tiles[q] and battle.tiles[q][r] ~= nil or false
end

function BattleRules.activeUnit(battle)
    return battle and battle.units and battle.units[battle.active] or nil
end

function BattleRules.selectedUnit(battle)
    if not battle then return nil end
    for _, unit in ipairs(battle.units or {}) do
        if unit.id == battle.selected then return unit end
    end
    return BattleRules.activeUnit(battle)
end

function BattleRules.facing(battle, unit)
    local nearest, nearestDistance
    for _, other in ipairs(battle and battle.units or {}) do
        if other.hp > 0 and other.team ~= unit.team then
            local distance = BattleRules.distance(unit, other)
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = other, distance
            end
        end
    end
    if not nearest then return unit.facing or 1 end
    return nearest.q < unit.q and -1 or 1
end

function BattleRules.weaponRange(catalog, name)
    local combat = catalog.weaponCombat[name] or catalog.weaponCombat.scratch
    return combat.kind == "ranged" and math.max(2, math.floor((combat.range or 12) / 6)) or 1
end

function BattleRules.gainExperience(data, amount)
    return PlayerProgression.gainExperience(data,amount)
end

function BattleRules.applyTemporaryStat(unit, stat, amount, rounds)
    local bonusKey = stat .. "Bonus"
    local roundsKey = stat .. "BonusRounds"
    unit[stat] = (unit[stat] or 0) + amount
    unit[bonusKey] = (unit[bonusKey] or 0) + amount
    unit[roundsKey] = math.max(unit[roundsKey] or 0, (rounds or 1) + 1)
end

function BattleRules.endTurn(unit)
    if not unit then return end
    for _, stat in ipairs({"aim", "armor", "move"}) do
        local bonusKey = stat .. "Bonus"
        local roundsKey = stat .. "BonusRounds"
        if (unit[roundsKey] or 0) > 0 then
            unit[roundsKey] = unit[roundsKey] - 1
            if unit[roundsKey] <= 0 then
                unit[stat] = (unit[stat] or 0) - (unit[bonusKey] or 0)
                unit[bonusKey], unit[roundsKey] = nil, nil
            end
        end
    end
end

return BattleRules
