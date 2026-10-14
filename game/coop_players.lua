-- Persistent character ownership. Campaign tables serialize only players;
-- the legacy host-field bridge forwards to that one record, never a copy.
-- Guest domain services must receive an explicit forActor view. Never swap
-- the host bridge or runtime globals to execute another actor's command.
local Players={HOST="host",COMPANION="companion",MAX_PLAYERS=2}

Players.personalFields={
    character=true,trait=true,traitBaselineApplied=true,
    health=true,maxHealth=true,stats=true,inventory=true,inventoryCapacity=true,
    equipment=true,ammo=true,backpack=true,wearables=true,
    weaponDurability=true,weaponProficiency=true,nextBattlePotions=true,
    battlePotionLootChance=true,playerX=true,playerY=true,playerFacing=true,
    activeCar=true,weapons=true,itemSlots=true,
}
local tableFields={"trait","stats","inventory","equipment","ammo","wearables",
    "weaponDurability","weaponProficiency","nextBattlePotions","weapons","itemSlots"}
local requiredTables={"stats","inventory","equipment","ammo","wearables",
    "weaponDurability","weaponProficiency","nextBattlePotions"}
local numericFields={"health","maxHealth","inventoryCapacity","playerX","playerY",
    "playerFacing","activeCar","battlePotionLootChance"}

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function number(value,fallback,minimum)
    value=tonumber(value)
    if not finite(value) then value=fallback end
    return minimum and math.max(minimum,value) or value
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

function Players.get(campaign,id)
    return type(campaign)=="table" and type(campaign.players)=="table" and campaign.players[id] or nil
end

function Players.role(campaign,id)
    if not Players.get(campaign,id) then return nil end
    return id==Players.HOST and "host" or id==Players.COMPANION and "guest" or nil
end

function Players.validateShape(campaign)
    local records=rawget(campaign,"players")
    if records==nil then return true end -- legacy/new-game input, prepared below
    if type(records)~="table" or type(records.host)~="table" then
        return false,"players must contain the host character"
    end
    for field in pairs(Players.personalFields) do
        if rawget(campaign,field)~=nil then return false,"duplicate personal field: "..field end
    end
    for id,record in pairs(records) do
        if (id~=Players.HOST and id~=Players.COMPANION) or type(record)~="table" then
            return false,"invalid player record"
        end
        if record.id~=id then return false,"player identity does not match its record" end
        for _,field in ipairs(tableFields) do
            if record[field]~=nil and type(record[field])~="table" then return false,"player "..field.." must be a table" end
        end
        for _,field in ipairs(numericFields) do
            if record[field]~=nil and not finite(tonumber(record[field])) then return false,"invalid player "..field end
        end
        if record.character~=nil and type(record.character)~="string" then return false,"player character must be text" end
        if record.backpack~=nil and type(record.backpack)~="string" then return false,"player backpack must be text" end
        for _,field in ipairs({"level","xp","nextXP"}) do
            local value=record.stats and record.stats[field]
            if value~=nil and not finite(tonumber(value)) then return false,"invalid player stats."..field end
        end
        for _,field in ipairs({"ammo","weaponDurability","weaponProficiency"}) do
            for key,value in pairs(record[field] or {}) do
                if type(key)~="string" or not finite(tonumber(value)) or tonumber(value)<0 then
                    return false,"invalid player "..field.." entry"
                end
            end
        end
    end
    return true
end

local hostBridge={
    __index=function(campaign,key)
        if Players.personalFields[key] then return campaign.players.host[key] end
    end,
    __newindex=function(campaign,key,value)
        if Players.personalFields[key] then campaign.players.host[key]=value
        else rawset(campaign,key,value) end
    end,
}

function Players.attachHost(campaign)
    assert(type(campaign.players)=="table" and type(campaign.players.host)=="table","host record required")
    assert(getmetatable(campaign)==nil or getmetatable(campaign)==hostBridge,"unexpected campaign metatable")
    return setmetatable(campaign,hostBridge)
end

-- Called on an already detached, validated save copy. Legacy root values move
-- once. Existing canonical records may not be shadowed by stale root fields.
function Players.prepare(campaign)
    local valid,message=Players.validateShape(campaign)
    if not valid then return nil,message end
    if not campaign.players then
        local host={id=Players.HOST}
        for field in pairs(Players.personalFields) do
            host[field]=rawget(campaign,field)
            rawset(campaign,field,nil)
        end
        campaign.players={host=host}
    end
    return Players.attachHost(campaign)
end

function Players.normalize(campaign)
    for _,record in pairs(campaign.players) do
        for _,field in ipairs(requiredTables) do record[field]=record[field] or {} end
        record.maxHealth=number(record.maxHealth,20,1)
        record.health=math.min(record.maxHealth,number(record.health,20,0))
        record.inventoryCapacity=math.floor(number(record.inventoryCapacity,6,1))
        record.activeCar=math.min(#campaign.trainCars,math.floor(number(record.activeCar,1,1)))
        record.stats.level=math.floor(number(record.stats.level,1,1))
        record.stats.xp=number(record.stats.xp,0,0)
        record.stats.nextXP=number(record.stats.nextXP,10,0)
        if record.wearables.backpack==nil then record.wearables.backpack=record.backpack end
        record.backpack=record.wearables.backpack
        for _,field in ipairs({"playerX","playerY","playerFacing"}) do
            if record[field]~=nil then record[field]=tonumber(record[field]) end
        end
        for _,field in ipairs({"ammo","weaponDurability","weaponProficiency"}) do
            for key,value in pairs(record[field]) do record[field][key]=tonumber(value) end
        end
    end
end

function Players.validate(campaign)
    local valid,message=Players.validateShape(campaign)
    if not valid then return false,message end
    if not campaign.players then return false,"players are missing" end
    for _,record in pairs(campaign.players) do
        for _,field in ipairs(requiredTables) do
            if type(record[field])~="table" then return false,"player "..field.." is missing" end
        end
        if not finite(record.maxHealth) or record.maxHealth<1 or not finite(record.health)
            or record.health<0 or record.health>record.maxHealth then return false,"invalid player health range" end
        for _,field in ipairs({"inventoryCapacity","activeCar"}) do
            if not finite(record[field]) or record[field]<1 or record[field]~=math.floor(record[field]) then
                return false,"invalid player "..field
            end
        end
        for _,field in ipairs({"level","xp","nextXP"}) do
            if not finite(record.stats[field]) or record.stats[field]<(field=="level" and 1 or 0) then
                return false,"invalid player stats."..field
            end
        end
    end
    return true
end

-- A fixed actor-scoped adapter for existing data-oriented domain functions.
-- Each personal key targets exactly one record; shared keys target campaign.
-- This is not a network permission check and must never be serialized/saved.
local actorViews=setmetatable({},{__mode="k"})
local actorIds=setmetatable({},{__mode="k"})
function Players.forActor(campaign,id)
    assert(Players.get(campaign,id),"unknown actor")
    local view=setmetatable({}, {
        __index=function(_,key)
            if Players.personalFields[key] then return campaign.players[id][key] end
            return campaign[key]
        end,
        __newindex=function(_,key,value)
            if Players.personalFields[key] then campaign.players[id][key]=value
            else campaign[key]=value end
        end,
    })
    actorViews[view]=campaign
    actorIds[view]=id
    return view
end

function Players.isActorView(value) return actorViews[value]~=nil end
function Players.campaignOf(value) return actorViews[value] or value end
function Players.actorId(value) return actorIds[value] or (Players.get(value,Players.HOST) and Players.HOST) end

-- Enrollment is host administration. The caller supplies the loaded playable
-- asset allowlist; merely ending in .png does not make a network name valid.
function Players.enroll(campaign,actorId,character,catalog,allowedCharacters)
    if Players.role(campaign,actorId)~="host" then return nil,"host_only" end
    if campaign.players.companion then return nil,"companion_exists" end
    if type(character)~="string" or not allowedCharacters or allowedCharacters[character]~=true then
        return nil,"invalid_character"
    end
    local host=campaign.players.host
    local Progression=require("game.player_progression")
    local trait=copy(catalog.characterTrait(character))
    local stats=copy(host.stats)
    local record={id=Players.COMPANION,character=character,trait=trait,traitBaselineApplied=true,
        stats=stats,maxHealth=20+(trait.maxHealth or 0)+(stats.level-1)*Progression.healthPerLevel,
        inventory={},inventoryCapacity=6,equipment={"frontier-short-sword","trail-slingshot"},
        ammo={rocks=12},wearables={},weaponDurability={},weaponProficiency={},nextBattlePotions={},
        activeCar=host.activeCar or 1,
    }
    record.health=record.maxHealth
    -- Position is assigned by the authoritative scene spawn resolver at join.
    campaign.players.companion=record
    local prepared,reason=require("game.item_instances").ensure(campaign)
    if not prepared then campaign.players.companion=nil; return nil,reason end
    return record
end

return Players
