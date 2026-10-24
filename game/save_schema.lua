local AudioCatalog = require("game.audio_catalog")
local Accessibility = require("game.accessibility")
local HelpQuestSession = require("game.help_quest_session")
local CoopPlayers = require("game.coop_players")
local CoopEntities = require("game.coop_entities")
local ItemInstances = require("game.item_instances")
local ReplicaOwnership = require("game.replica_ownership")

local SaveSchema = {
    CURRENT_VERSION = 50,
    LEGACY_VERSION = 1,
}

local CROW_CARAVAN_DATA_VERSION = 1

local STRUCTURAL_TABLES = {
    "resources", "droppedItems", "visitedStops", "houseInitialized", "houseLayoutsArranged",
    "npcStates", "stopLayouts", "stopSludges", "events", "weaponDurability",
    "weaponProficiency", "supplyQuests", "mailQuests", "passengers", "questAsked",
    "lootRolls", "nextBattlePotions", "npcOffers", "npcWeapons", "audio", "trainCars",
    "stats", "inventory", "equipment", "ammo", "encounters", "choices", "npcRoster",
    "maintenance", "eventCategoryHistory", "helpHistory", "relationships", "accessibility", "finale", "helpQuestSessions", "expeditions", "crowCaravans", "lastStand", "conversations",
    "supplyDeliveryCycle", "trainAmbush", "wearables", "outfitCrafting", "homeStop", "npcIdentities",
}

local SUPPLY_DELIVERY_KINDS={food=true,water=true,medicine=true,repair=true,ammunition=true,recovery=true}

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
    if ReplicaOwnership.isReplica(data) then return false,"network replicas cannot be saved as campaigns" end
    if CoopPlayers.isActorView(data) then return false,"actor views cannot be saved as campaigns" end
    local playersValid,playersError=CoopPlayers.validateShape(data)
    if not playersValid then return false,playersError end
    local version=versionOf(data)
    if not version or version<SaveSchema.LEGACY_VERSION then return false,"invalid save version" end
    if version>SaveSchema.CURRENT_VERSION then return false,"future save version "..tostring(version) end
    if type(data.coop)=="table" and data.coop.preferencesDetached then
        if data.accessibility~=nil then return false,"device accessibility cannot be stored in a detached campaign" end
        for key in pairs(type(data.audio)=="table" and data.audio or {}) do
            if key~="station" and key~="rainEnabled" then return false,"device audio cannot be stored in a detached campaign" end
        end
    end
    for _,field in ipairs(STRUCTURAL_TABLES) do
        if data[field]~=nil and type(data[field])~="table" then
            return false,field.." must be a table"
        end
    end
    for _,field in ipairs({"location","health","maxHealth","activeCar","engineLevel","inventoryCapacity","scrap","goodwill"}) do
        local value=data[field]
        if value~=nil and tonumber(value)==nil then return false,field.." must be numeric" end
    end
    if data.character~=nil and type(data.character)~="string" then return false,"character must be text" end
    if data.scene~=nil and type(data.scene)~="string" then return false,"scene must be text" end
    if data.activeHelpQuestId~=nil and type(data.activeHelpQuestId)~="string" then return false,"activeHelpQuestId must be text" end
    if data.activeExpeditionArea~=nil and type(data.activeExpeditionArea)~="string" then return false,"activeExpeditionArea must be text" end
    local homeValid,homeError=require('game.home_stop').validate(data)
    if not homeValid then return false,homeError end
    local peopleValid,peopleError=require('game.npc_identity').validate(data)
    if not peopleValid then return false,peopleError end
    local targetsValid,targetsError=require('game.npc_targets').validate(data)
    if not targetsValid then return false,targetsError end
    if not require('game.coop_quest_decisions').validateOffers(data) then return false,'invalid saved quest offer' end
    if not require('game.coop_events').validateCurrent(data) then return false,'invalid saved event' end
    if not require('game.coop_finale').validate(data) then return false,'invalid saved finale' end
    if not require('game.tactical_battle_state').validate(data) then return false,'invalid saved tactical battle' end
    if not require('game.battle_search').validate(data) then return false,'invalid saved ruin caches' end
    if not require('game.roaming_combat_state').validate(data) then return false,'invalid saved field combat' end
    if not require('game.roaming_encounter_state').validate(data) then return false,'invalid saved field encounter' end
    if not require('game.coop_shooter_sessions').validate(data) then return false,'invalid saved shooter session' end
    if not require('game.coop_ambush_state').validate(data) then return false,'invalid saved ambush actor' end
    if not require('game.coop_last_stand_state').validate(data) then return false,'invalid saved Last Stand combat' end
    if not require('game.coop_last_stand_lifecycle').validate(data) then return false,'invalid saved Last Stand lifecycle' end
    if not require('game.coop_last_stand_aid_state').validate(data) then return false,'invalid saved Last Stand treatment' end
    if not require('game.coop_last_stand_position_state').validate(data) then return false,'invalid saved Last Stand positions' end
    if not require('game.coop_range_state').validate(data) then return false,'invalid saved range session' end
    if data.conversations then
        local state=data.conversations
        for _,field in ipairs({"assignments","completed","seen"}) do
            if state[field]~=nil and type(state[field])~="table" then return false,"conversations."..field.." must be a table" end
        end
        if state.nextStop~=nil and (not finiteNumber(state.nextStop) or state.nextStop<1) then return false,"invalid conversation spacing" end
        for key,entry in pairs(state.assignments or {}) do
            if type(key)~="string" or type(entry)~="table" or type(entry.id)~="string" or type(entry.npc)~="string"
                or not finiteNumber(entry.location) or tostring(entry.location)~=key then return false,"invalid conversation assignment" end
        end
        if not require('game.npc_conversations').validateActive(data) then return false,'invalid active conversation' end
    end
    local caravans=data.crowCaravans
    if caravans then
        if caravans.version~=nil then
            local caravanVersion=tonumber(caravans.version)
            if not finiteNumber(caravanVersion) or caravanVersion<1 or caravanVersion~=math.floor(caravanVersion) then
                return false,"crowCaravans.version must be a positive integer"
            end
        end
        if caravans.scheduleVersion~=nil then
            local scheduleVersion=tonumber(caravans.scheduleVersion)
            if not finiteNumber(scheduleVersion) or scheduleVersion<0 or scheduleVersion~=math.floor(scheduleVersion) then
                return false,"crowCaravans.scheduleVersion must be a nonnegative integer"
            end
        end
        if caravans.scheduledStops~=nil and type(caravans.scheduledStops)~="table" then return false,"crowCaravans.scheduledStops must be a table" end
        if caravans.camps~=nil and type(caravans.camps)~="table" then return false,"crowCaravans.camps must be a table" end
        if caravans.scheduleMode~=nil and caravans.scheduleMode~="journey" and caravans.scheduleMode~="legacy-future" then
            return false,"crowCaravans.scheduleMode is invalid"
        end
        for _,field in ipairs({"activeCampId","activeAreaId","groupRelationshipId"}) do
            if caravans[field]~=nil and type(caravans[field])~="string" then return false,"crowCaravans."..field.." must be text" end
        end
        for key,stop in pairs(caravans.scheduledStops or {}) do
            if type(key)~="number" or not finiteNumber(tonumber(stop)) then return false,"crowCaravans.scheduledStops contains an invalid stop" end
        end
        for key,camp in pairs(caravans.camps or {}) do
            if (type(key)~="string" and type(key)~="number") or type(camp)~="table" then return false,"crowCaravans.camps contains an invalid camp" end
            for _,field in ipairs({"returnX","returnY","returnFacing","playerX","playerY","playerFacing"}) do
                if camp[field]~=nil and not finiteNumber(tonumber(camp[field])) then return false,"crowCaravans camp "..field.." must be numeric" end
            end
        end
    end
    for _,field in ipairs({"droppedItems","passengers"}) do
        for key,value in pairs(data[field] or {}) do
            if type(key)~="number" or type(value)~="table" then return false,field.." contains an invalid entry" end
        end
    end
    for key,value in pairs(data.trainCars or {}) do
        if type(key)~="number" or type(value)~="string" then return false,"trainCars contains an invalid entry" end
    end
    return CoopEntities.validate(data,true)
end

local function deepCopy(value, seen, depth)
    local valueType=type(value)
    if valueType~="table" then
        if valueType=="number" and not finiteNumber(value) then return nil,"save contains a non-finite number" end
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
        if type(key)=="number" and not finiteNumber(key) then return nil,"save contains a non-finite table key" end
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

local function normalizedFacing(value)
    value=tonumber(value)
    if not finiteNumber(value) or value==0 then return nil end
    return value<0 and -1 or 1
end

local function ensureCrowCaravans(data)
    local caravans=data.crowCaravans
    caravans.version=CROW_CARAVAN_DATA_VERSION
    caravans.scheduleVersion=math.floor(nonnegative(caravans.scheduleVersion,0))
    caravans.scheduleMode=(caravans.scheduleMode=="journey" or caravans.scheduleMode=="legacy-future") and caravans.scheduleMode or nil
    caravans.groupRelationshipId="crow-caravan"
    local activeCampId=caravans.activeCampId
    if (type(activeCampId)~="string" or activeCampId=="") and type(caravans.activeAreaId)=="string" then
        activeCampId=caravans.activeAreaId
    end
    caravans.activeCampId=type(activeCampId)=="string" and activeCampId~="" and activeCampId or nil
    caravans.activeAreaId=nil

    local scheduledStops,seen={},{}
    for _,value in ipairs(type(caravans.scheduledStops)=="table" and caravans.scheduledStops or {}) do
        local stop=tonumber(value)
        if finiteNumber(stop) then
            stop=math.max(1,math.min(50,math.floor(stop)))
            if not seen[stop] then scheduledStops[#scheduledStops+1]=stop; seen[stop]=true end
        end
    end
    table.sort(scheduledStops)
    caravans.scheduledStops=scheduledStops

    local camps={}
    for key,camp in pairs(type(caravans.camps)=="table" and caravans.camps or {}) do
        if type(camp)=="table" then
            local oldId=camp.id
            local stop=tonumber(camp.stop) or tonumber(key)
            if finiteNumber(stop) then
                stop=math.max(1,math.min(50,math.floor(stop)))
                camp.stop=stop
                camp.id="crow-caravan-stop-"..stop
                if caravans.activeCampId and (caravans.activeCampId==oldId or caravans.activeCampId==camp.id) then caravans.activeCampId=camp.id end
                key=tostring(stop)
            else key=tostring(key) end
            for _,field in ipairs({"returnX","returnY","playerX","playerY"}) do
                local value=tonumber(camp[field])
                camp[field]=finiteNumber(value) and value or nil
            end
            camp.returnFacing=normalizedFacing(camp.returnFacing)
            camp.playerFacing=normalizedFacing(camp.playerFacing)
            camp.relationshipKey=caravans.groupRelationshipId
            camps[key]=camp
        end
    end
    caravans.camps=camps
end

local function removeRetiredStopActivities(data)
    -- Stop activities are retired. Clear every saved stop and any orphaned
    -- quest session while preserving rewards already earned and other quests.
    for _,layout in pairs(data.stopLayouts) do
        if type(layout)=="table" then
            layout.dialogueHelpRequests=nil
            for npc,kind in pairs(layout.npcOffers or {}) do
                if kind=="dialogue" then layout.npcOffers[npc]="none" end
            end
            local activity=layout.worldActivity
            if type(activity)=="table" and activity.sessionId then
                data.helpQuestSessions[activity.sessionId]=nil
            end
            layout.worldActivity=nil
        end
    end
    for id,session in pairs(data.helpQuestSessions) do
        if type(session)=="table" and (session.kind=="settlement-activity" or session.source=="community-water-pump" or session.kind=="dialogue-help") then
            data.helpQuestSessions[id]=nil
            if data.activeHelpQuestId==id then data.activeHelpQuestId=nil end
        end
    end
end

local function latestAssignedDelivery(data)
    local latestStop,latestNpc,latestKind
    for key,layout in pairs(data.stopLayouts or {}) do
        local stop=tonumber(key) or (type(layout)=="table" and tonumber(layout.location))
        if stop and type(layout)=="table" then
            local npcs={}
            for npc,kind in pairs(layout.deliveryOffers or {}) do
                if SUPPLY_DELIVERY_KINDS[kind] then npcs[#npcs+1]=npc end
            end
            table.sort(npcs)
            for _,npc in ipairs(npcs) do
                if not latestStop or stop>latestStop or (stop==latestStop and npc>latestNpc) then
                    latestStop,latestNpc,latestKind=stop,npc,layout.deliveryOffers[npc]
                end
            end
        end
    end
    return latestKind
end

local function ensureRootTables(data)
    local hadDeliveryCycle=type(data.supplyDeliveryCycle)=="table"
    local detached=data.coop and data.coop.preferencesDetached
    for _,field in ipairs(STRUCTURAL_TABLES) do
        if field~="accessibility" or not detached then data[field]=data[field] or {} end
    end
    if data.wearables.backpack==nil and type(data.backpack)=="string" then
        data.wearables.backpack=data.backpack
    end
    data.backpack=data.wearables.backpack
    if not hadDeliveryCycle then
        data.supplyDeliveryCycle={seen={}}
        data.supplyDeliveryCycle.last=latestAssignedDelivery(data)
    elseif type(data.supplyDeliveryCycle.seen)~="table" then
        data.supplyDeliveryCycle.seen={}
    end
    ensureCrowCaravans(data)
    data.location=math.max(1,math.min(50,math.floor(tonumber(data.location) or 1)))
    if data.scene~="train" and data.scene~="stop" and data.scene~="house" and data.scene~="expedition" and data.scene~="caravan" then data.scene="train" end
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
    data.goodwill=math.floor(nonnegative(data.goodwill,0))
    data.visitedStops[data.location]=true
    if #data.trainCars==0 then data.trainCars={"living-car"} end
    data.activeCar=math.max(1,math.min(#data.trainCars,math.floor(nonnegative(data.activeCar,1))))
    data.engineLevel=math.floor(nonnegative(data.engineLevel,0))
    data.audio.station=AudioCatalog.normalizeStation(data.audio.station)
    data.audio.rainEnabled=data.audio.rainEnabled==true
    if not detached then
        data.audio.musicVolume=math.min(1,nonnegative(data.audio.musicVolume,.10))
        data.audio.sfxVolume=math.min(1,nonnegative(data.audio.sfxVolume,.55))
        data.audio.rainVolume=math.min(1,nonnegative(data.audio.rainVolume,.20))
        data.audio.musicPaused=data.audio.musicPaused==true
        data.audio.musicMuted=data.audio.musicMuted==true
        Accessibility.ensure(data)
    end
    require("game.npc_conversations").ensure(data)
    removeRetiredStopActivities(data)
    HelpQuestSession.ensureData(data)
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
    -- Existing ledgers are persisted ownership, not a spawn request. Missing
    -- records must not silently turn into fresh, fully repaired equipment.
    if ItemInstances.enabled(data) then
        local itemsValid,itemsError=ItemInstances.validate(data)
        if not itemsValid then return nil,itemsError end
    end
    local wasCanonical=SaveSchema.validate(data)==true
    local migrated,copyError=deepCopy(data)
    if not migrated then return nil,copyError end
    local prepared,playersError=CoopPlayers.prepare(migrated)
    if not prepared then return nil,playersError end
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
    CoopPlayers.normalize(migrated)
    require('game.npc_identity').prepare(migrated)
    require('game.npc_targets').prepare(migrated)
    require('game.coop_last_stand_lifecycle').prepare(migrated)
    require('game.coop_last_stand_aid_state').prepare(migrated)
    require('game.coop_last_stand_position_state').prepare(migrated)
    local entities,entitiesError=CoopEntities.ensure(migrated)
    if not entities then return nil,entitiesError end
    local items,itemsError=ItemInstances.ensure(migrated)
    if not items then return nil,itemsError end
    require('game.coop_shooter_sessions').prepare(migrated)
    require('game.coop_last_stand_state').prepare(migrated)
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
    if type(data)=='table' and data.lastStand and data.lastStand.positionVersion~=1 then
        return false,'saved Last Stand positions require migration'
    end
    if type(data)=='table' and type(data.lastStand)=='table' and data.lastStand.treatmentProgress and data.lastStand.treatmentVersion~=1 then
        return false,'Last Stand treatment requires migration'
    end
    local valid,errorMessage=validateShape(data)
    if not valid then return false,errorMessage end
    if data.version~=SaveSchema.CURRENT_VERSION then return false,"save is not at the current version" end
    if data.lastStand and data.lastStand.lifecycle and data.lastStand.lifecycle.version~=require('game.coop_last_stand_lifecycle').VERSION then
        return false,'Last Stand lifecycle needs migration'
    end
    if data.lastStand and data.lastStand.combat and data.lastStand.combat.version~=require('game.coop_last_stand_state').VERSION then
        return false,'Last Stand combat requires migration'
    end
    local playersValid,playersError=CoopPlayers.validate(data)
    if not playersValid then return false,playersError end
    local presenceValid,presenceError=require('game.coop_presence').validate(data)
    if not presenceValid then return false,presenceError end
    local travelerValid,travelerError=require('game.coop_traveler').validate(data)
    if not travelerValid then return false,travelerError end
    local entitiesValid,entitiesError=CoopEntities.validate(data)
    if not entitiesValid then return false,entitiesError end
    local itemsValid,itemsError=ItemInstances.validate(data)
    if not itemsValid then return false,itemsError end
    -- A decoded canonical save is a plain table. Validate through a detached
    -- host bridge without modifying the caller or requiring duplicate fields.
    local projected,projectionError=deepCopy(data)
    if not projected then return false,projectionError end
    data=CoopPlayers.attachHost(projected)
    for _,field in ipairs(STRUCTURAL_TABLES) do
        if type(data[field])~="table" and not (field=="accessibility" and data.coop.preferencesDetached) then
            return false,field.." is missing from the current schema"
        end
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

function SaveSchema.copy(data)
    if CoopPlayers.isActorView(data) then return nil,"actor views cannot be copied as campaigns" end
    local result,message=deepCopy(data)
    if result and result.players then
        local valid,playersError=CoopPlayers.validateShape(result)
        if not valid then return nil,playersError end
        CoopPlayers.attachHost(result)
    end
    return result,message
end
SaveSchema.migrations=migrations
return SaveSchema
