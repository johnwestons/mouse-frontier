-- A combat unit addresses one personal record; NPCs retain host supplies.
local Players=require('game.coop_players')
local Actors={}
function Actors.id(unit)
    if not unit then return nil end
    if unit.actorId=='host' or unit.actorId=='companion' then return unit.actorId end
    if unit.actorId~=nil then return nil end
    if unit.id=='player' then return 'host' end -- legacy expedition checkpoints
end
function Actors.data(data,unit)
    local id=Actors.id(unit) or 'host'
    if data.players then return Players.forActor(Players.campaignOf(data),id) end
    return data
end
function Actors.syncHealth(data,unit)
    if not Actors.id(unit) then return end
    local actor=Actors.data(data,unit)
    -- Temporary combat HP can exceed the character's permanent maximum.
    actor.health=math.max(0,math.min(actor.maxHealth,unit.hp))
end
function Actors.units(battle)
    local result,seen={},{}
    for _,unit in ipairs(battle.units or {}) do
        local id=Actors.id(unit)
        if id and not seen[id] then result[#result+1]=unit; seen[id]=true end
    end
    return result
end
return Actors
