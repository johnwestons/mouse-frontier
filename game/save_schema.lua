local SaveSchema = {
    CURRENT_VERSION = 25,
    LEGACY_VERSION = 1,
}

local STRUCTURAL_TABLES = {
    "resources", "droppedItems", "visitedStops", "houseInitialized", "houseLayoutsArranged",
    "npcStates", "stopLayouts", "stopSludges", "events", "weaponDurability",
    "weaponProficiency", "supplyQuests", "mailQuests", "passengers", "questAsked",
    "lootRolls", "nextBattlePotions", "npcOffers", "npcWeapons", "audio", "trainCars",
    "stats", "inventory", "equipment", "ammo", "encounters", "choices", "npcRoster",
    "maintenance",
}

local function finiteNumber(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function versionOf(data)
    if data.version==nil then return SaveSchema.LEGACY_VERSION end
    if not finiteNumber(data.version) or data.version~=math.floor(data.version) then return nil end
    return data.version
end

local function validateShape(data)
    if type(data)~="table" then return false,"save data must be a table" end
    local version=versionOf(data)
    if not version or version<SaveSchema.LEGACY_VERSION then return false,"invalid save version" end
    if version>SaveSchema.CURRENT_VERSION then return false,"future save version "..tostring(version) end
    for _,field in ipairs(STRUCTURAL_TABLES) do
        if data[field]~=nil and type(data[field])~="table" then
            return false,field.." must be a table"
        end
    end
    for _,field in ipairs({"location","health","maxHealth","activeCar","engineLevel","inventoryCapacity","scrap"}) do
        local value=data[field]
        if value~=nil and tonumber(value)==nil then return false,field.." must be numeric" end
    end
    if data.character~=nil and type(data.character)~="string" then return false,"character must be text" end
    if data.scene~=nil and type(data.scene)~="string" then return false,"scene must be text" end
    for _,field in ipairs({"droppedItems","passengers"}) do
        for key,value in pairs(data[field] or {}) do
            if type(key)~="number" or type(value)~="table" then return false,field.." contains an invalid entry" end
        end
    end
    for key,value in pairs(data.trainCars or {}) do
        if type(key)~="number" or type(value)~="string" then return false,"trainCars contains an invalid entry" end
    end
    return true
end

local function deepCopy(value, seen, depth)
    local valueType=type(value)
    if valueType~="table" then
        if valueType=="nil" or valueType=="string" or valueType=="number" or valueType=="boolean" then return value end
        return nil,"save contains an unsupported "..valueType.." value"
    end
    depth=depth or 0
    if depth>64 then return nil,"save nesting exceeds 64 levels" end
    seen=seen or {}
    if seen[value] then return nil,"save data contains a cycle" end
    seen[value]=true
    local result={}
    for key,item in pairs(value) do
        if type(key)~="string" and type(key)~="number" then return nil,"save contains an unsupported table key" end
        local copied,errorMessage=deepCopy(item,seen,depth+1)
        if errorMessage then return nil,errorMessage end
        result[key]=copied
    end
    seen[value]=nil
    return result
end

local function nonnegative(value,default)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return default end
    return math.max(0,value)
end

local function ensureRootTables(data)
    for _,field in ipairs(STRUCTURAL_TABLES) do data[field]=data[field] or {} end
    data.location=math.max(1,math.min(50,math.floor(tonumber(data.location) or 1)))
    if data.scene~="train" and data.scene~="stop" and data.scene~="house" then data.scene="train" end
    data.stopped=data.stopped==nil and true or data.stopped==true
    data.resources.food=nonnegative(data.resources.food,10)
    data.resources.water=nonnegative(data.resources.water,10)
    data.resources.coal=nonnegative(data.resources.coal,10)
    data.resources.oil=nonnegative(data.resources.oil,10)
    data.health=nonnegative(data.health,20)
    data.maxHealth=math.max(1,nonnegative(data.maxHealth,20))
    data.health=math.min(data.health,data.maxHealth)
    data.stats.level=math.max(1,math.floor(nonnegative(data.stats.level,1)))
    data.stats.xp=nonnegative(data.stats.xp,0)
    data.stats.nextXP=math.max(1,nonnegative(data.stats.nextXP,10))
    data.inventoryCapacity=math.max(1,math.floor(nonnegative(data.inventoryCapacity,6)))
    data.scrap=nonnegative(data.scrap,0)
    data.visitedStops[data.location]=true
    if #data.trainCars==0 then data.trainCars={"living-car"} end
    data.activeCar=math.max(1,math.min(#data.trainCars,math.floor(nonnegative(data.activeCar,1))))
    data.engineLevel=math.floor(nonnegative(data.engineLevel,0))
    data.audio.station=type(data.audio.station)=="string" and data.audio.station or "8bit"
    data.audio.musicVolume=math.min(1,nonnegative(data.audio.musicVolume,.10))
    data.audio.sfxVolume=math.min(1,nonnegative(data.audio.sfxVolume,.55))
    data.audio.rainVolume=math.min(1,nonnegative(data.audio.rainVolume,.20))
    data.audio.rainEnabled=data.audio.rainEnabled==true
    data.audio.musicPaused=data.audio.musicPaused==true
    data.audio.musicMuted=data.audio.musicMuted==true
    for _,item in pairs(data.droppedItems) do
        item.scene=type(item.scene)=="string" and item.scene or "train"
        if item.scene=="train" then item.carIndex=math.max(1,math.floor(nonnegative(item.carIndex,1)))
        else item.location=math.max(1,math.min(50,math.floor(nonnegative(item.location,data.location)))) end
    end
    return data
end

local migrations={}
for version=SaveSchema.LEGACY_VERSION,SaveSchema.CURRENT_VERSION-1 do
    migrations[version]=function(data)
        ensureRootTables(data)
        data.version=version+1
        return data
    end
end

function SaveSchema.migrate(data)
    local valid,errorMessage=validateShape(data)
    if not valid then return nil,errorMessage end
    local wasCanonical=SaveSchema.validate(data)==true
    local migrated,copyError=deepCopy(data)
    if not migrated then return nil,copyError end
    local fromVersion=versionOf(migrated)
    migrated.version=fromVersion
    local steps=0
    while migrated.version<SaveSchema.CURRENT_VERSION do
        local migration=migrations[migrated.version]
        if not migration then return nil,"missing migration from version "..tostring(migrated.version) end
        local previous=migrated.version
        migrated=migration(migrated)
        if type(migrated)~="table" or migrated.version~=previous+1 then
            return nil,"migration from version "..tostring(previous).." did not advance sequentially"
        end
        steps=steps+1
    end
    ensureRootTables(migrated)
    local current,currentError=validateShape(migrated)
    if not current then return nil,currentError end
    return migrated,{
        fromVersion=fromVersion,
        toVersion=SaveSchema.CURRENT_VERSION,
        steps=steps,
        migrated=steps>0,
        rewriteRequired=steps>0 or not wasCanonical,
    }
end

function SaveSchema.validate(data)
    local valid,errorMessage=validateShape(data)
    if not valid then return false,errorMessage end
    if data.version~=SaveSchema.CURRENT_VERSION then return false,"save is not at the current version" end
    for _,field in ipairs(STRUCTURAL_TABLES) do
        if type(data[field])~="table" then return false,field.." is missing from the current schema" end
    end
    local copied,copyError=deepCopy(data)
    if not copied then return false,copyError end
    return true
end

function SaveSchema.stamp(data)
    assert(type(data)=="table","save data must be a table")
    data.version=SaveSchema.CURRENT_VERSION
    return data
end

function SaveSchema.isCurrent(data)
    return SaveSchema.validate(data)==true
end

SaveSchema.copy=deepCopy
SaveSchema.migrations=migrations
return SaveSchema
