if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    love.errorhandler=function(message)
        io.stderr:write("LOVE_ERROR: "..tostring(message).."\n"..debug.traceback().."\n"); io.stderr:flush()
        return function() os.exit(1) end
    end
end

local W, H = 960, 720
local CURRENT_SAVE_VERSION = 25
local Audio = require("game.audio")
local Save = require("game.save")
local Train = require("game.train")
local Viewport = require("game.viewport")
local Catalog = require("game.catalog")
local Inventory = require("game.inventory")
local CharacterAnimation = require("game.character_animation")
local Family = require("game.family")
local EngineUpgrades = require("game.engine_upgrades")
local Passengers = require("game.passengers")
local Util = require("game.util")
local House = require("game.house")
local Stops = require("game.stops")
local Roster = require("game.roster")
local Wildlife = require("game.wildlife")
local Mice = require("game.mice")
local Settlements = require("game.settlements")
local Events = require("game.events")
local EventUI = require("game.event_ui")
local Camera = require("game.camera")
local BattleRules = require("game.battle_rules")
local BattleController = require("game.battle_controller")
local Assets = require("game.assets")
local StopSludges = require("game.stop_sludges")
local InteriorDoors = require("game.interior_doors")
local Interactions = require("game.interactions")
local SmokePlaythrough = require("game.smoke_playthrough")
local Clouds = require("game.clouds")
local Maintenance = require("game.maintenance")
local Systems = {inventory=require("game.inventory_ui"),interactions=require("game.interaction_router"),intro=require("game.intro_cinematic"),battleUI=require("game.battle_ui"),session=require("game.game_session")}
local session = Systems.session.new()
local state = session.screen
local selectedSlot, saveData, player = session.selectedSlot, session.saveData, session.player
local characters, characterImages, npcImages, mobImages, mobFiles = {}, {}, {}, {}, {}
local scenery, backgroundImages, ui = {}, {}, {}
local sceneryOffset, landscapeOffset, animationClock, trainAnimationClock = 0, 0, 0, 0
local cloudLayer
local battleZoom = 1
local walkingSoundTimer = 0
local inventoryOpen, draggedSlot = false, nil
local scene, nearbyItem = session.scene, nil
local nearHouse, nearNPC, nearPassenger, nearFire, nearReturnTrain, nearCarPrev, nearCarNext, mapOpen, dialogue = false, false, nil, false, false, false, false, false, nil
local nearMailbox = nil
local npcActor = nil
local battle = nil
local stopSludges = StopSludges.new()
local travelConfirm, travelTransition, randomEvent = false, nil, nil
local mapScroll, characterScroll, questOffer = 0, 0, nil
local actionTimer = 0
local actionHeldItem = nil
local actionKind = nil
local editMode, editedItem, editDragging = false, nil, false
local chestOpen, activeChest, nearChest, inventoryDragActive = false, nil, nil, false
local characterWalkImages, npcWalkImages = {}, {}
local characterActionImages, mobAttackImages, mobIdleImages, mobHitImages = {}, {}, {}, {}
local familyImages, mobDeathImages, mobWalkImages, mobRangedImages = {}, {}, {}, {}
local itemIdleImages = {}
local characterAnimations = {}
local holdPickupIndex, holdPickupTime = nil, 0
local HOLD_PICKUP_SECONDS = 0.85
local trainUpgradeOpen=false
local poseMenu, playerPose = false, "idle"
local tradeOpen, tradeNPC = false, nil
local giftOpen, giftNPC, giftSlot = false, nil, nil
-- Kept outside the top-level local pool because LÖVE limits main.lua locals.
exitPrompt = nil
local carTransition = nil
local lastInventoryClick, lastInventoryClickTime = nil, 0
local maintenanceSession = Maintenance.new()


-- Rolling-stock layout: the car sits farther right to leave room for the
-- enlarged locomotive while retaining one shared rail/coupler baseline.
local car = { x = 315, y = 280, w = 680, h = 363, gap = 0, wall = 16 }
local function activeTrainCarImage()
    local image=scenery and scenery.trainCarImages and scenery.trainCarImages[saveData and saveData.trainCars and saveData.trainCars[saveData.activeCar or 1] or "living-car"]
    return image
end
local function trainFloorBounds()
    return Train.characterBounds(car,activeTrainCarImage(),30)
end
local function trainObjectBounds()
    -- Editor placement is intentionally unconstrained: objects may be arranged
    -- anywhere in the visible game canvas, including the roof/track margins.
    return 0, 960, 0, 720
end
local function clampToTrainFloor(x,y)
    return Train.clampCharacterToFloor(car,activeTrainCarImage(),x,y,30)
end
local colors = {
    ink = {0.10, 0.065, 0.04}, wall = {0.31, 0.20, 0.12}, trim = {0.16, 0.09, 0.05},
    floorA = {0.46, 0.30, 0.16}, floorB = {0.35, 0.21, 0.11}, brass = {0.86, 0.58, 0.18},
    cream = {0.96, 0.88, 0.68}, panel = {0.12, 0.09, 0.07, 0.94}, green = {0.32, 0.70, 0.38},
    blue = {0.25, 0.56, 0.78}, red = {0.78, 0.30, 0.24}
}


local function writeSave()
    if not selectedSlot or not saveData then return end
    session:sync(state,selectedSlot,saveData,player,scene)
    ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
    session:scheduleSave(Save)
end

local function isFurnitureItem(name)
    return name and love.filesystem.getInfo("assets/sprites/furniture/"..name..".png")~=nil
end

local function newSave(character)
    local npcRoster, seen = {}, {}
    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/NPCS")) do
        if Roster.isNpcCandidate(file) then npcRoster[#npcRoster + 1], seen[file] = file, true end
    end
    for _, file in ipairs(characters) do
        if Roster.isNpcCandidate(file) and file ~= character and not seen[file] then npcRoster[#npcRoster + 1] = file end
    end
    table.sort(npcRoster)
    local worldItems = {}
    worldItems[#worldItems+1]={name="travel-chest",x=car.x+275,y=car.y+255,scene="train",carIndex=1,scale=1,rotation=0,storage={}}
    worldItems[#worldItems+1]={name="boombox-radio",x=car.x+470,y=car.y+285,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true}
    worldItems[#worldItems+1]={name="mailbox-reward",x=car.x+560,y=car.y+270,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true,mailbox=true,mailUnread=false,storage={}}
    local result={
        version = CURRENT_SAVE_VERSION, character = character, location = 1, scene = "train", stopped = true,
        npcRoster = npcRoster, currentNPC = npcRoster[1],
        resources = {food = 10, water = 10, coal = 10, oil = 10},
        health = 20, maxHealth = 20, stats={level=1,xp=0,nextXP=10},
        equipment = {"frontier-short-sword", "trail-slingshot"},
        ammo = {rocks=12,arrows=0,["ball-bearings"]=0,["9mm"]=0,["45-cal"]=0,["556"]=0,["22lr"]=0,["30-carbine"]=0,["8mm"]=0,["380-acp"]=0,["32-acp"]=0,["12-gauge"]=0,["762x39"]=0},
        inventory = {"orange-rose-vase", "cowboy-hat", nil, nil, nil, nil},
        droppedItems = worldItems, visitedStops = {[1] = true}, houseInitialized = {}, houseLayoutsArranged = {}, npcStates = {},
        encounters = {}, weaponDropsAdded = true, starterChestAdded=true, medicalDropsAdded=true, ammoDropsAdded=true,
        choices = {}, stopLayouts = {}, stopSludges={}, events = {}, weaponDurability={}, weaponProficiency={}, mailQuests={}, supplyQuests={}, passengers={}, questAsked={}, lootRolls={}, npcOffers={}, npcWeapons={},
        maintenance={condition=72,lastServicedStop=0,totalServices=0,totalWear=0},
        inventoryCapacity=6, backpack=nil,
        scrap=0, trainCars={"living-car"}, activeCar=1, engineLevel=0,
        specialItemsAdded=true, lootContainerMigration=true, expandedLootAdded=true, radioAdded=true,lootBalanceVersion=1,
        audio={station="8bit",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=false,musicPaused=false,musicMuted=false}, playerX = car.x + 300, playerY = car.y + 285
    }
    for i,name in ipairs({"coal-bucket","pickaxe","potted-sprout","flower-pot","potted-flowers"}) do House.storeLoot(result,Catalog,name,i) end
    return result
end

local function enterGame(data)
    if type(data)~="table" then return false end
    Maintenance.close(maintenanceSession)
    ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1; ui.itemOrderCache={}
    data.version = CURRENT_SAVE_VERSION
    data.location=math.max(1,math.min(50,math.floor(tonumber(data.location) or 1)))
    data.resources=type(data.resources)=="table" and data.resources or {}
    for _,name in ipairs({"food","water","coal"}) do data.resources[name]=math.max(0,tonumber(data.resources[name]) or 0) end
    -- Existing saves predate train oil; give them the same starter reserve as
    -- a new game instead of loading them into an unwinnable empty state.
    data.resources.oil=math.max(0,tonumber(data.resources.oil) or 10)
    data.scene = data.scene or "train"
    data.stopped = data.stopped == nil and true or data.stopped
    data.droppedItems = data.droppedItems or {}
    for _, item in ipairs(data.droppedItems) do
        item.scene = item.scene or "train"
        if item.scene=="train" then
            item.carIndex=item.carIndex or 1
            local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,item.x or left)); item.y=math.max(top,math.min(bottom,item.y or top))
        end
        if item.scene ~= "train" then item.location = item.location or data.location end
    end
    data.visitedStops = data.visitedStops or {[data.location or 1] = true}
    data.visitedStops[data.location or 1] = true
    data.houseInitialized = data.houseInitialized or {}
    data.houseLayoutsArranged = data.houseLayoutsArranged or {}
    data.npcStates = data.npcStates or {}
    data.stopLayouts = data.stopLayouts or {}
    data.stopSludges = data.stopSludges or {}
    data.events = data.events or {}
    Maintenance.ensure(data)
    data.weaponDurability=data.weaponDurability or {}
    data.weaponProficiency=data.weaponProficiency or {}
    data.supplyQuests=data.supplyQuests or {}
    data.mailQuests=data.mailQuests or {}
    data.passengers=data.passengers or {}
    data.questAsked=data.questAsked or {}
    data.lootRolls=data.lootRolls or {}
    if (data.lootBalanceVersion or 0)<1 then
        for i=#data.droppedItems,1,-1 do
            local item=data.droppedItems[i]
            local rollKey=tostring(item.location or data.location)..":"..tostring(item.houseDoor or 1)
            if item.scene=="house" and Catalog.storageCapacities[item.name] and not item.droppedByPlayer and not data.lootRolls[rollKey] then
                table.remove(data.droppedItems,i)
            end
        end
        data.lootBalanceVersion=1
    end
    data.nextBattlePotions=data.nextBattlePotions or {}
    data.npcOffers=data.npcOffers or {}; data.npcWeapons=data.npcWeapons or {}
    data.inventoryCapacity=data.inventoryCapacity or 6
    data.scrap=data.scrap or 0
    data.audio=data.audio or {station="8bit",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=false}
    data.audio.musicPaused=data.audio.musicPaused or false; data.audio.musicMuted=data.audio.musicMuted or false
    data.audio.station=data.audio.station or "8bit"; if data.audio.musicVolume==nil then data.audio.musicVolume=.10 end; data.audio.sfxVolume=data.audio.sfxVolume or .55; data.audio.rainVolume=data.audio.rainVolume or .20
    if data.audio.rainEnabled==nil then data.audio.rainEnabled=data.audio.station=="chill" end
    data.trainCars=data.trainCars or {"living-car"}
    data.activeCar=math.max(1,math.min(#data.trainCars,data.activeCar or 1))
    data.engineLevel=math.max(0,math.min(#EngineUpgrades.tiers-1,data.engineLevel or 0))
    local assignedTrait=Catalog.characterTrait(data.character)
    if not data.traitBaselineApplied then
        data.maxHealth=(data.maxHealth or 20)+(assignedTrait.maxHealth or 0)
        data.traitBaselineApplied=true
    elseif not data.trait or data.trait.name~=assignedTrait.name then
        data.maxHealth=(data.maxHealth or 20)-(data.trait and data.trait.maxHealth or 0)+(assignedTrait.maxHealth or 0)
    end
    data.trait=assignedTrait
    data.health=math.min(data.maxHealth,data.health or data.maxHealth)
    for i,item in ipairs(data.droppedItems) do item.layer=item.layer or i end
    if not data.specialItemsAdded then data.specialItemsAdded=true end
    for i,passenger in ipairs(data.passengers) do
        local left,right,top,bottom=trainFloorBounds(); passenger.x,passenger.y=clampToTrainFloor(passenger.x or car.x+230+(i-1)*85,passenger.y or (top+bottom)/2)
        passenger.homeX=math.max(left,math.min(right,passenger.homeX or passenger.x)); passenger.homeY=math.max(top,math.min(bottom,passenger.homeY or passenger.y)); passenger.wait=passenger.wait or 1; passenger.job=passenger.job or Passengers.jobFor(passenger.npc); passenger.pose=passenger.pose or "idle"; passenger.carIndex=math.max(1,math.min(#data.trainCars,passenger.carIndex or 1))
    end
    data.health, data.maxHealth = data.health or 20, data.maxHealth or 20
    data.stats=data.stats or {level=1,xp=0,nextXP=10}
    data.inventory = data.inventory or {}
    data.equipment = data.equipment or {}
    data.ammo=data.ammo or {}
    for _,name in ipairs({"rocks","arrows","ball-bearings","9mm","45-cal","556","22lr","30-carbine","8mm","380-acp","32-acp","12-gauge","762x39"}) do
        data.ammo[name]=math.max(0,tonumber(data.ammo[name]) or 0)
    end
    if not data.ammoDropsAdded then data.ammoDropsAdded=true end
    data.weapons=nil
    if not data.weaponDropsAdded then data.weaponDropsAdded=true end
    if not data.starterChestAdded then
        local found=false; for _,item in ipairs(data.droppedItems) do if item.name=="travel-chest" and item.scene=="train" then item.storage=item.storage or {}; found=true end end
        if not found then data.droppedItems[#data.droppedItems+1]={name="travel-chest",x=car.x+165,y=car.y+285,scene="train",scale=1,rotation=0,storage={}} end
        data.starterChestAdded=true
    end
    for _,item in ipairs(data.droppedItems) do if Catalog.storageCapacities[item.name] then item.storage=item.storage or {} end end
    if not data.radioAdded then
        data.droppedItems[#data.droppedItems+1]={name="boombox-radio",x=car.x+470,y=car.y+285,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true}
        data.radioAdded=true
    end
    local mailboxFound=false
    for _,item in ipairs(data.droppedItems) do
        if item.name=="mailbox-reward" and item.scene=="train" then
            mailboxFound=true; item.mailbox=true; item.permanent=true; item.scale=(item.scale and item.scale>=.9) and item.scale or 1.15; item.storage=item.storage or {}; item.mailUnread=item.mailUnread==true
        end
    end
    if not mailboxFound then
        data.droppedItems[#data.droppedItems+1]={name="mailbox-reward",x=car.x+560,y=car.y+270,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true,mailbox=true,mailUnread=false,storage={}}
    end
    for _,item in ipairs(data.droppedItems) do
        if item.name=="travel-chest" and item.scene=="train" and (item.x<car.x+35 or item.x>car.x+car.w-35) then item.x,item.y=car.x+165,car.y+285 end
    end
    if not data.medicalDropsAdded then data.medicalDropsAdded=true end
    if not data.lootContainerMigration then
        local loose={}
        for i=#data.droppedItems,1,-1 do
            local item=data.droppedItems[i]
            if (item.scene=="stop" or item.scene=="house") and not item.droppedByPlayer and not isFurnitureItem(item.name) then
                loose[#loose+1]={name=item.name,location=item.location or data.location}; table.remove(data.droppedItems,i)
            end
        end
        for _,loot in ipairs(loose) do House.storeLoot(data,Catalog,loot.name,loot.location) end
        data.lootContainerMigration=true
    end
    if not data.expandedLootAdded then data.expandedLootAdded=true end
    data.lootBalanceVersion=data.lootBalanceVersion or 1
    data.encounters = data.encounters or {}
    local loadedNpcCandidates={}
    for file in pairs(npcImages) do loadedNpcCandidates[#loadedNpcCandidates+1]=file end
    Events.ensure(data)
    -- Older saves may have selected a character that is now a mob-only asset.
    -- Keep the save usable by moving that selection to the first valid hero.
    if not Roster.isPlayable(data.character) or not characterImages[data.character] then
        data.character = characters[1]
    end
    data.npcRoster = Roster.mergeNpcRoster(data.npcRoster,loadedNpcCandidates,data.character)
    local currentNpcAllowed=false
    for _,file in ipairs(data.npcRoster) do if file==data.currentNPC then currentNpcAllowed=true; break end end
    if not currentNpcAllowed then data.currentNPC = data.npcRoster[1] end
    saveData = session:setSaveData(data)
    stopSludges = StopSludges.new()
    local image = characterImages[data.character]
    local restoredX=data.playerX or car.x+90; local restoredY=data.playerY or car.y+180
    if data.scene=="train" then restoredX,restoredY=clampToTrainFloor(restoredX,restoredY) end
    if data.scene=="stop" then restoredX,restoredY=Settlements.clamp(restoredX,restoredY,data.location) end
    player = session:setPlayer({x = restoredX, y = restoredY, speed = 185,
        image = image, facing = 1, moving = false, scale = image and math.min(0.075, 90 / image:getHeight()) or 1})
    session:activate(data,player)
    scene = session.scene
    state, inventoryOpen, mapOpen, dialogue, editMode, chestOpen, activeChest = session.screen, false, false, nil, false, false, nil
    carTransition=nil
    return true
end

local function screenToGame(x,y)
    x,y=Viewport.toGame(x,y,W,H)
    -- Radio/options are screen-space overlays; camera zoom must not shift their
    -- hit testing into a neighboring station button.
    if state=="game" and not travelConfirm and not ui.radioOpen and Camera:isActive() then
        local focusX,focusY=(player and player.x or W/2),(player and player.y or H/2)
        x,y=Camera:toWorld(x,y,focusX,focusY)
    end
    return x,y
end

local function isWeapon(name) return Inventory.isWeapon(name,Catalog.weaponStats) end

local function updateStopSludges(dt)
    if scene~="stop" or not saveData or not player then return end
    StopSludges.update(stopSludges,{data=saveData,location=saveData.location,player=player,npc=npcActor,catalog=Catalog,isWeapon=isWeapon,clock=animationClock,
        clamp=function(x,y) return Settlements.clamp(x,y,saveData.location) end,
        dropCoal=function(x,y)
            saveData.droppedItems[#saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=saveData.location,droppedByPlayer=false}
            writeSave()
        end},dt)
end

local function attackStopSludge(x,y)
    if scene~="stop" or inventoryOpen or mapOpen or dialogue or editMode or ui.radioOpen or trainUpgradeOpen or poseMenu or ui.optionsOpen then return false end
    return StopSludges.attack(stopSludges,{data=saveData,location=saveData.location,player=player,npc=npcActor,catalog=Catalog,isWeapon=isWeapon,clock=animationClock,
        onAction=function(weapon) actionHeldItem=weapon; actionKind="melee"; actionTimer=.42 end,
        playSfx=function(kind) ui.playSfx(kind) end})
end

local function containerValue(ref)
    return Inventory.value(saveData,activeChest,ref)
end

local function setContainerValue(ref,value)
    Inventory.setValue(saveData,activeChest,ref,value)
end

local function moveBetweenSlots(source,target)
    local moved=Inventory.move(saveData,activeChest,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts)
    if moved then writeSave() end
    return moved
end

local function quickTransfer(ref)
    if not chestOpen then return false end
    local moved=Inventory.quickTransfer(saveData,activeChest,ref,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.storageCapacities)
    if moved then writeSave() end
    return moved
end

local function collectAmmo(ref)
    if not ref or ref.kind~="chest" then return false end
    local name=containerValue(ref); local amount=name and Catalog.ammoPickupAmounts[name]
    if not amount then return false end
    saveData.ammo[name]=(saveData.ammo[name] or 0)+amount
    setContainerValue(ref,nil); draggedSlot=nil; inventoryDragActive=false; writeSave()
    dialogue={speaker="Ammo",text="Collected "..amount.." "..Util.titleFromFile(name).." ammunition.",timer=1.6}
    return true
end

local function dropFromContainer(ref)
    local name=containerValue(ref); if not name then return false end
    local dropped={name=name,x=player.x+35,y=player.y,scene=scene,scale=1,rotation=0,droppedByPlayer=true}
    if scene=="train" then dropped.carIndex=saveData.activeCar or 1 end
    if scene~="train" then dropped.location=saveData.location end
    if Catalog.storageCapacities[name] then dropped.storage={} end
    saveData.droppedItems[#saveData.droppedItems+1]=dropped
    setContainerValue(ref,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
end

local function consumeSelected()
    if not draggedSlot then return false end
    local name=containerValue(draggedSlot); local effect=Catalog.itemEffects[name]
    actionHeldItem=name; actionKind="use"; actionTimer=.45
    if isWeapon(name) and (nearNPC or nearPassenger) then
        if nearPassenger then saveData.passengers[nearPassenger].weapon=name
        else local layout=saveData.stopLayouts[tostring(saveData.location)]; if layout then layout.npcWeapon=name end; if npcActor then npcActor.weapon=name end end
        dialogue={speaker="Weapon Given",text=Util.titleFromFile(name).." is now equipped by your ally.",timer=2}
        setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
    end
    local pack=Catalog.backpackUpgrades[name]
    if pack then
        if pack.capacity<=(saveData.inventoryCapacity or 6) then dialogue={speaker=pack.label,text="Your current backpack already carries at least that much.",timer=2}; return false end
        saveData.inventoryCapacity=pack.capacity; saveData.backpack=name
        dialogue={speaker=pack.label,text="Equipped! Carry capacity increased to "..pack.capacity.." slots.",timer=2.5}
        setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
    end
    if name=="rose-heart-arrow" or name=="blade-hearts" then
        saveData.maxHealth=saveData.maxHealth+5; saveData.health=math.min(saveData.maxHealth,saveData.health+5)
        dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
        setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
    end
    if effect and effect.potion then
        saveData.nextBattlePotions[name]=true
        dialogue={speaker=Util.titleFromFile(name),text=effect.description.." It will activate at the next battle.",timer=2.5}
        setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
    end
    if not effect then return false end
    local capacity=20; for _,id in ipairs(saveData.trainCars or {}) do if id=="storage" then capacity=30; break end end
    local foodFull=effect.food and saveData.resources.food>=capacity
    local waterFull=effect.water and saveData.resources.water>=capacity
    local oilFull=effect.oil and saveData.resources.oil>=capacity
    if (effect.food or effect.water or effect.oil) and (not effect.food or foodFull) and (not effect.water or waterFull) and (not effect.oil or oilFull) then
        local fullName=oilFull and "Oil storage is full." or (foodFull and waterFull and "Food and water storage are full." or (foodFull and "Food storage is full." or "Water storage is full."))
        dialogue={speaker="Storage Full",text=fullName,timer=2.2}
        return false
    end
    if effect.food then saveData.resources.food=math.min(capacity,saveData.resources.food+effect.food) end
    if effect.water then saveData.resources.water=math.min(capacity,saveData.resources.water+effect.water) end
    if effect.oil then saveData.resources.oil=math.min(capacity,saveData.resources.oil+effect.oil) end
    if effect.health then saveData.health=math.min(saveData.maxHealth,saveData.health+effect.health) end
    dialogue={speaker=Util.titleFromFile(name),text=effect.oil and ("Stored +"..effect.oil.." train oil.") or ("That helped. "..(effect.health and ("+"..effect.health.." health") or "Supplies restored.")),timer=1.4}
    setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
end

local function pickUpNearby()
    if not nearbyItem then return end
    local item=saveData.droppedItems[nearbyItem]
    if item.permanent then dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; return end
    if item.name=="rose-heart-arrow" or item.name=="blade-hearts" then
        saveData.maxHealth=saveData.maxHealth+5; saveData.health=math.min(saveData.maxHealth,saveData.health+5)
        dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
        table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave(); return
    end
    if Catalog.ammoPickupAmounts[item.name] then
        local amount=Catalog.ammoPickupAmounts[item.name]; saveData.ammo[item.name]=(saveData.ammo[item.name] or 0)+amount
        dialogue={speaker=Util.titleFromFile(item.name),text="Picked up "..amount.." rounds.",timer=1.6}
        table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave(); return
    end
    if Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; return end
    local slot=Inventory.firstEmptySlot(saveData)
    if not slot then
        dialogue={speaker="Backpack Full",text="There is no room in your backpack.",timer=2.2}
        return
    end
    saveData.inventory[slot]=item.name
    table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave()
end

local function itemIsHere(item)
    if item.scene ~= scene then return false end
    if scene == "train" then return (item.carIndex or 1)==(saveData.activeCar or 1) end
    if scene == "house" then return item.location == saveData.location and (item.houseDoor or 1)==(saveData.activeHouseDoor or 1) end
    return item.location == saveData.location
end

local function findInventoryItem(names)
    for i = 1, (saveData.inventoryCapacity or 6) do
        for _, name in ipairs(names) do if saveData.inventory[i] == name then return i, name end end
    end
end

local function addCoalToFire()
    local coalCapacity=20
    for _,id in ipairs(saveData.trainCars or {}) do if id=="coal-hauler" then coalCapacity=30; break end end
    if saveData.resources.coal>=coalCapacity then
        dialogue={speaker="Storage Full",text="Coal storage is full.",timer=2.2}
        return
    end
    local slot, name = findInventoryItem({"coal-bucket", "coal-chunk"})
    if not slot then dialogue = {speaker="Fire", text="Bring me coal from your backpack!", timer=2}; return end
    local amount = name == "coal-bucket" and 3 or 1
    saveData.inventory[slot] = nil
    saveData.resources.coal = math.min(coalCapacity, saveData.resources.coal + amount)
    dialogue = {speaker="Fire", text="That's the good stuff!  +"..amount.." fuel", timer=2}
    writeSave()
end

local function ensureHouseItems() House.ensure(saveData,Catalog,isFurnitureItem) end

local function giveWeaponToNearby()
    local targetPassenger=nearPassenger and saveData.passengers[nearPassenger]
    if not nearNPC and not targetPassenger then return false end
    giftOpen=true; giftNPC=targetPassenger and targetPassenger.npc or saveData.currentNPC; giftSlot=nil; inventoryOpen=true; chestOpen=false; activeChest=nil; draggedSlot=nil
    return true
end

local function ensureStopLayout() return Stops.ensure(saveData,Catalog,scene) end

local function travelCost()
    local leg=math.max(0,(saveData.location or 1)-1)
    local passengers=#(saveData.passengers or {})
    local terrain=({"plains","desert","mountains","ruins","forest"})[((saveData.location or 1)-1)%5+1]
    local terrainCoal=terrain=="mountains" and 2 or (terrain=="ruins" and 1 or 0); local trait=saveData.trait or Catalog.characterTraitProfiles[1]
    local sleeper=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="sleeper" then sleeper=true end end
    local passengerCost=sleeper and math.ceil(passengers/2) or passengers
    local food,water,coal=EngineUpgrades.applyCosts(saveData.engineLevel,(1+math.floor(leg/4)+passengerCost)*(trait.food or 1),(1+math.floor(leg/3)+passengerCost)*(trait.water or 1),(1+math.floor(leg/5)+terrainCoal)*(trait.coal or 1))
    local maintenanceCoal=Maintenance.coalPenalty(saveData)
    coal=coal+maintenanceCoal
    return {food=food,water=water,coal=coal,passengers=passengers,terrain=terrain,maintenanceCoal=maintenanceCoal}
end

local function processPassengerArrivals()
    for i=#saveData.passengers,1,-1 do
        local passenger=saveData.passengers[i]
        if saveData.location>=passenger.destination then
            table.remove(saveData.passengers,i)
            local coal=math.max(1,math.floor(love.math.random(1,3)*(saveData.trait.reward or 1))); saveData.resources.coal=math.min(20,saveData.resources.coal+coal)
            local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(saveData); if slot then saveData.inventory[slot]=item end
            saveData.arrivalNotice=(Util.titleFromFile(passenger.npc).." reached their stop and left you "..coal.." coal"..(slot and " and "..Util.titleFromFile(item) or "")..".")
        end
    end
end

local function passengerContributions()
    local notes={}; local hasGreenhouse=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="greenhouse" then hasGreenhouse=true end end
    for _,p in ipairs(saveData.passengers or {}) do
        p.job=p.job or Passengers.jobFor(p.npc); local gained
        if p.job=="greenhouse" and hasGreenhouse then saveData.resources.food=math.min(30,saveData.resources.food+2); gained="grew 2 food"
        elseif p.job=="fireman" then saveData.resources.coal=math.min(30,saveData.resources.coal+1); gained="salvaged 1 coal"
        elseif p.job=="medic" then local before=saveData.health; saveData.health=math.min(saveData.maxHealth,saveData.health+2); gained="restored "..(saveData.health-before).." health"
        else local resource=({"food","water","coal"})[love.math.random(3)]; saveData.resources[resource]=math.min(30,saveData.resources[resource]+1); gained="scavenged 1 "..resource end
        notes[#notes+1]=Util.titleFromFile(p.npc).." "..gained
    end
    if #notes>0 then saveData.arrivalNotice=table.concat(notes,". ").."." end
end

local function giveQuestReward(message)
    local coal=math.max(1,math.floor(love.math.random(1,3)*(saveData.trait.reward or 1))); saveData.resources.coal=math.min(20,saveData.resources.coal+coal)
    local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(saveData)
    if slot then saveData.inventory[slot]=item else House.storeLoot(saveData,Catalog,item,saveData.location) end
    dialogue={speaker="Traveler",text=(message or "Thank you!").."  You received "..coal.." coal and "..Util.titleFromFile(item)..".",timer=4}
end

local function pendingMailHere()
    for _,quest in ipairs(saveData.mailQuests or {}) do
        if not quest.complete and quest.destination==saveData.location and quest.recipient==saveData.currentNPC then return quest end
    end
end

local function acceptQuest(kind)
    if kind=="mail" then
        local maxAhead=math.max(1,math.min(8,50-saveData.location)); local destination=math.min(50,saveData.location+love.math.random(1,maxAhead))
        local layout=saveData.stopLayouts[tostring(destination)] or {houseX=love.math.random(390,700),treeA=love.math.random(110,250),treeB=love.math.random(760,860),house=love.math.random(1,8),tree=love.math.random(1,7)}
        local roster=saveData.npcRoster or {}; layout.npc=layout.npc or roster[love.math.random(math.max(1,#roster))] or saveData.currentNPC; saveData.stopLayouts[tostring(destination)]=layout
        saveData.mailQuests[#saveData.mailQuests+1]={sender=saveData.currentNPC,recipient=layout.npc,origin=saveData.location,destination=destination,complete=false}
        dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Thank you. Please look for "..Util.titleFromFile(layout.npc).." around stop "..destination..".",timer=4}
    elseif kind=="ride" then
        local remaining=math.max(1,50-saveData.location); local job=Passengers.jobFor(saveData.currentNPC); local rideStops=Passengers.rideLength(job,remaining,saveData.resources.food,saveData.resources.water,love.math.random(-1,1))
        local index=#saveData.passengers+1; local px=car.x+225+(index-1)*85
        local layout=ensureStopLayout()
        saveData.passengers[index]={npc=saveData.currentNPC,destination=saveData.location+rideStops,x=px,y=car.y+285,homeX=px,homeY=car.y+285,wait=1,job=job,pose="idle",weapon=layout.npcWeapon}
        dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Thank you! I'll ride for "..rideStops..(rideStops==1 and " stop" or " stops").." and help as your "..job..".",timer=4}
    elseif kind=="trade" then
        tradeOpen=true; tradeNPC=saveData.currentNPC; dialogue=nil
    elseif kind=="supplies" then
        local destination=math.min(50,saveData.location+love.math.random(1,math.max(1,math.min(6,50-saveData.location))))
        local amount=3; local added=0; local addedSlots={}
        for _=1,amount do
            local slot=Inventory.firstEmptySlot(saveData)
            if not slot then break end
            saveData.inventory[slot]=({"food-ration","bread-loaf","jerky-bundle"})[love.math.random(3)]; addedSlots[#addedSlots+1]=slot; added=added+1
        end
        if added<amount then
            for _,slot in ipairs(addedSlots) do saveData.inventory[slot]=nil end
            saveData.resources.food=math.min(30,saveData.resources.food+amount)
            saveData.supplyQuests[#saveData.supplyQuests+1]={origin=saveData.location,destination=destination,amount=amount,complete=false,foodItems=0,storedAtTrain=true}
            dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Your backpack is full, so the 3 food items were sent to the train stores for stop "..destination..".",timer=5}
        else
            saveData.supplyQuests[#saveData.supplyQuests+1]={origin=saveData.location,destination=destination,amount=amount,complete=false,foodItems=amount}
            dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Take these 3 food items to the settlers at stop "..destination..". They will reward you when it arrives.",timer=5}
        end
    end
    questOffer=nil; writeSave()
end

local function talkToNPC()
    for _,supply in ipairs(saveData.supplyQuests or {}) do
        if not supply.complete and supply.destination==saveData.location then
            if supply.storedAtTrain or supply.foodItems==nil then
                if saveData.resources.food>=supply.amount then saveData.resources.food=saveData.resources.food-supply.amount; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
                else dialogue={speaker="Settler",text="You don't have enough food stored for our delivery. We're hungry and disappointed.",timer=4} end
                return
            end
            local remaining=supply.foodItems or supply.amount; local consumed={}
            for i=1,(saveData.inventoryCapacity or 6) do
                local n=saveData.inventory[i]; if n and Catalog.itemEffects[n] and Catalog.itemEffects[n].food and remaining>0 then consumed[#consumed+1]=i; remaining=remaining-1 end
            end
            if remaining<=0 then for _,i in ipairs(consumed) do saveData.inventory[i]=nil end; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
            else dialogue={speaker="Settler",text="You need the 3 food items I gave you for this delivery.",timer=4} end
            return
        end
    end
    local mail=pendingMailHere()
    if mail then mail.complete=true; giveQuestReward(Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]); writeSave(); return end
    local key=tostring(saveData.location)..":"..tostring(saveData.currentNPC); local layout=ensureStopLayout()
    -- Read the offer for the NPC being spoken to.  A stop can have several
    -- critters, and their quest rolls must not leak between conversations.
    local kind=(layout.npcOffers and layout.npcOffers[saveData.currentNPC]) or "none"
    if not saveData.questAsked[key] and kind~="none" and saveData.location<50 then
        saveData.questAsked[key]=true; questOffer={kind=kind}
        local text=kind=="mail" and Catalog.mailRequestLines[love.math.random(#Catalog.mailRequestLines)] or (kind=="ride" and Catalog.rideRequestLines[love.math.random(#Catalog.rideRequestLines)] or (kind=="supplies" and "Settlers farther west are hungry. Could you deliver some food for us?" or "I've got supplies to trade. Want to take a look?"))
        dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text=text,timer=30,choice=true}; writeSave(); return
    end
    dialogue={speaker=Util.titleFromFile(saveData.currentNPC or "Traveler"),text=Catalog.dialogueLines[love.math.random(#Catalog.dialogueLines)],timer=6}
end

local function setupNPC()
    if scene == "train" then npcActor = nil; return end
    local layout=ensureStopLayout()
    saveData.currentNPC=(scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    local key = Util.sceneKey(scene,saveData.location)..(scene=="house" and (":"..tostring(saveData.activeHouseDoor or 1)) or "")
    local saved = saveData.npcStates[key]
    local defaults = scene == "house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
    saved = saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
    saved.weapon=saved.weapon or layout.npcWeapon
    if scene=="house" then
        saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
        saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
    elseif scene=="stop" then
        saved.x,saved.y=Settlements.clamp(saved.x,saved.y,saveData.location)
        saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,saveData.location)
    end
    saveData.npcStates[key] = saved
    npcActor = saved
    Family.ensure(npcActor,saveData.currentNPC)
end

local function enterStop()
    scene=session:setScene("stop"); player.x,player.y=270,490; setupNPC(); writeSave()
end

local beginEncounter
local function attemptLeaveTrain()
    local key=tostring(saveData.location); local encounter=saveData.encounters[key]
    local requiredEvent=not saveData.events[key] and Events.required(saveData,saveData.location)
    if requiredEvent then randomEvent=requiredEvent; state=session:setScreen("event"); return end
    if not encounter then
        -- Battles should be the primary stop interruption; trail events remain less common.
        -- Story and mystery chapters are checked above; ordinary stops still
        -- favor combat while leaving room for the five random event families.
        local hasMob=love.math.random()<0.58
        local tier=saveData.location<=4 and "easy" or (saveData.location<=8 and "medium" or "hard")
        encounter={rolled=true,hasMob=hasMob,resolved=not hasMob,tier=tier}
        local pool=Catalog.mobTiers[tier]
        if hasMob and #pool>0 then
            encounter.mobFiles={}
            for i=1,Catalog.encounterMobCount(tier,saveData.location) do
                encounter.mobFiles[i]=pool[love.math.random(#pool)]
            end
            encounter.mobFile=encounter.mobFiles[1]
        end
        saveData.encounters[key]=encounter; writeSave()
    end
    if encounter.hasMob and not encounter.resolved and (encounter.mobFile or encounter.mobFiles) then beginEncounter(encounter)
    elseif not encounter.hasMob and not saveData.events[tostring(saveData.location)] then
        randomEvent=Events.random(saveData); state=session:setScreen("event")
    else enterStop() end
end

local function battleContext()
    return {battle=battle,saveData=saveData,Catalog=Catalog,Util=Util,BattleRules=BattleRules,Events=Events,BOARD_COLS=7,BOARD_ROWS=4,playSfx=ui.playSfx,weaponSfx=ui.weaponSfx,writeSave=writeSave}
end
beginEncounter=function(encounter)
    local c=battleContext(); battle=BattleController.begin(c,encounter); battleZoom=1; state=session:setScreen("battle"); inventoryOpen=false; mapOpen=false; dialogue=nil; writeSave()
end

local function resolveEventChoice(index)
    local event=randomEvent; if not event then return end
    local result=Events.resolve(saveData,Catalog,event,index); ui.playSfx("menu")
    if result.blocked then return end
    randomEvent=nil; writeSave()
    if result.encounter then beginEncounter(result.encounter); return end
    state=session:setScreen("game"); enterStop()
    dialogue={speaker=result.clue and (event.category=="story" and "Family Trail" or "Missing Critter") or "Trail Event",text=result.clue or result.summary,timer=5}
end


local function setBattleMessage(text) BattleController.message(battleContext(),text) end
local function setBattlePrompt(text) BattleController.prompt(battleContext(),text) end
local function advanceBattleTurn() BattleController.advance(battleContext()) end
local function resolveBattleAttack(attacker,target,weaponName) return BattleController.resolve(battleContext(),attacker,target,weaponName) end
local function enemyBattleTurn() BattleController.enemyTurn(battleContext()) end
local function battleAttack(weaponName) BattleController.attack(battleContext(),weaponName) end
local function battleMoveTo(q,r) BattleController.move(battleContext(),q,r) end
local function battleHeal() BattleController.heal(battleContext()) end
local function battleGuard() BattleController.guard(battleContext()) end
local function useBattleAbility(kind) BattleController.ability(battleContext(),kind) end
local function useBattlePotion(name) return BattleController.usePotion(battleContext(),name) end
local function consumeBattleSelected()
    if not draggedSlot then return false end
    local name=containerValue(draggedSlot); if not name then return false end
    local effect=Catalog.itemEffects[name]
    if isWeapon(name) then
        local moved=moveBetweenSlots(draggedSlot,{kind="equipment",index=1})
        if moved then draggedSlot=nil; inventoryDragActive=false; writeSave() end
        return moved
    end
    local used=(effect and effect.health and BattleController.useHealingItem(battleContext(),name)) or (effect and effect.potion and useBattlePotion(name))
    if used then draggedSlot=nil; inventoryDragActive=false; inventoryOpen=false end
    return used or false
end

function ui.playSfx(kind)
    if ui.audio and saveData then return ui.audio:playSfx(kind,saveData.audio,battle) end
end

local function playTrainDepart()
    ui.departSource=ui.playSfx("trainDepart")
end

function ui.weaponSfx(weaponName,combat)
    if weaponName=="trail-slingshot" or weaponName=="scrap-boomerang" or combat.ammo=="arrows" then return "bow" end
    if combat.kind~="ranged" then return weaponName=="scratch" and "slash" or "sword" end
    local tier=(Catalog.weaponStats[weaponName] and Catalog.weaponStats[weaponName].tier) or 1
    return tier<=4 and "gunshotLight" or (tier<=6 and "gunshotMedium" or "gunshotHeavy")
end

function ui.musicCategory()
    if state=="ending" then return "endingHappy" end
    if state=="battle" then return battle and battle.encounter and battle.encounter.tier=="hard" and "bossFight" or "battle" end
    if scene=="house" then return "insideHomes" end
    if scene=="stop" or state=="event" then return "stops" end
    return "train"
end

function ui.updateMusic()
    if saveData and ui.audio then ui.audio:update(saveData.audio,ui.musicCategory()) end
end

function ui.updateChickens(dt)
    if scene~="stop" or not saveData then return end
    local stopLayout=ensureStopLayout()
    Wildlife.spawn(stopLayout,saveData.location,Settlements)
    Wildlife.update(stopLayout.wildlife,dt,saveData.location,Settlements)
end

function ui.updateMice(dt)
    if scene~="stop" or not saveData then return end
    local stopLayout=ensureStopLayout()
    Mice.spawn(stopLayout,saveData.location,Settlements)
    Mice.update(stopLayout.mice,dt,saveData.location,Settlements)
end

function ui.drawChickens(layout)
    if not layout or scene~="stop" then return end
    Wildlife.spawn(layout,saveData.location,Settlements)
    Wildlife.draw(layout.wildlife,scenery.stopWildlife,animationClock)
end

function ui.drawMice(layout)
    if not layout or scene~="stop" then return end
    Mice.spawn(layout,saveData.location,Settlements)
    Mice.draw(layout.mice,scenery.stopWildlife,animationClock)
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setFont(love.graphics.newFont(16))
    ui.audio=Audio.new(); ui.audio:installGunPools()
    love.filesystem.createDirectory("saves")
    characterAnimations=Assets.load({
        ui=ui, scenery=scenery, characters=characters, characterImages=characterImages,
        npcImages=npcImages, mobImages=mobImages, mobFiles=mobFiles, backgroundImages=backgroundImages,
        characterWalkImages=characterWalkImages, npcWalkImages=npcWalkImages, characterActionImages=characterActionImages,
        mobAttackImages=mobAttackImages, mobIdleImages=mobIdleImages, mobHitImages=mobHitImages,
        mobDeathImages=mobDeathImages, mobWalkImages=mobWalkImages, mobRangedImages=mobRangedImages,
        familyImages=familyImages, itemIdleImages=itemIdleImages,
    })
    ui.introCinematic=Systems.intro.new(10)
    cloudLayer = Clouds.new(scenery.cloudImages)
    scenery.settlements=Settlements.load(function(path)
        local ok,image=pcall(love.graphics.newImage,path)
        return ok and image or nil
    end)
    ui.assetStreamer=require("game.asset_streamer").new({
        settlements=scenery.settlements,
        interiorFiles=scenery.interiorFiles,
        characterAnimations=characterAnimations,
        legacyAnimationTables={characterWalkImages,npcWalkImages,characterActionImages,mobAttackImages,mobIdleImages,mobHitImages,mobDeathImages,mobWalkImages,mobRangedImages,npcImages,mobImages},
    })
end

local function movementAxis(a, b) return (love.keyboard.isDown(b) and 1 or 0) - (love.keyboard.isDown(a) and 1 or 0) end

function ui.updateInteraction()
    local mx,my=screenToGame(love.mouse.getPosition())
    local selected=Systems.interactions.select({data=saveData,scene=scene,player=player,npc=npcActor,car=car,mouseX=mx,mouseY=my,
        itemIsHere=itemIsHere,storageCapacities=Catalog.storageCapacities,nearTrain=Settlements.nearTrain,trainPoint=Settlements.trainPoint,
        nearDoor=Settlements.nearDoor,doorPoint=Settlements.doorPoint,hasSettlements=scenery.settlements~=nil,layout=ensureStopLayout,
        interiorPoint=InteriorDoors.point,nearInteriorDoor=InteriorDoors.near,interiorFiles=scenery.interiorFiles,choose=Interactions.select})
    local flags=Systems.interactions.flags(selected)
    ui.interaction=flags.interaction; nearbyItem=flags.nearbyItem; nearChest=flags.nearChest; nearMailbox=flags.nearMailbox
    nearHouse=flags.nearHouse or false; nearNPC=flags.nearNPC or false; nearPassenger=flags.nearPassenger
    nearReturnTrain=flags.nearReturnTrain or false; nearFire=flags.nearFire or false; nearCarPrev=flags.nearCarPrev or false; nearCarNext=flags.nearCarNext or false; ui.nearRadio=flags.nearRadio or false
end

function love.update(dt)
    Save.update(dt)
    animationClock = animationClock + dt
    Clouds.update(cloudLayer, dt)
    if state=="intro" then
        if Systems.intro.update(ui.introCinematic,dt) then state=session:setScreen("slots") end
        return
    end
    if ui.assetStreamer then ui.assetStreamer:update(state,scene,saveData,battle,npcActor) end
    -- Full settlement scenes keep only the dedicated dynamic chicken flocks;
    -- the retired random decoration wildlife remains disconnected.
    walkingSoundTimer=math.max(0,walkingSoundTimer-dt)
    ui.updateMusic()
    local trainRate=2.2
    if travelTransition then
        local t=travelTransition.t or 0; local timing=EngineUpgrades.timings(saveData.engineLevel)
        if t<timing.depart then local p=t/timing.depart; trainRate=2.2+6.3*p*p
        elseif t<timing.arrive then trainRate=8.5
        else local p=math.max(0,1-(t-timing.arrive)/timing.arrivalDuration); trainRate=2.2+6.3*p*p end
    end
    trainAnimationClock=trainAnimationClock+dt*trainRate
    actionTimer=math.max(0,actionTimer-dt); if actionTimer<=0 then actionHeldItem=nil; actionKind=nil end
    if state=="battle" and battle then BattleController.update(battleContext(),dt) end
    if state ~= "game" then return end
    updateStopSludges(dt)
    ui.updateChickens(dt)
    ui.updateMice(dt)
    if travelTransition then
        travelTransition.t=travelTransition.t+dt
        local t=travelTransition.t; local speedFactor; local timing=EngineUpgrades.timings(saveData.engineLevel)
        if ui.departSource then
            -- Let the departure cue follow the train out, then release the
            -- channel before the arrival cue begins.
            local fade=math.max(0,math.min(1,(timing.depart-t)/(.55/EngineUpgrades.profile(saveData.engineLevel).speed)))
            ui.departSource:setVolume((saveData.audio.sfxVolume or .55)*fade)
            if t>=timing.change then ui.departSource:stop(); ui.departSource=nil end
        end
        if t<timing.depart then speedFactor=(t/timing.depart)^2 elseif t<timing.arrive then speedFactor=1 else speedFactor=math.max(0,1-(t-timing.arrive)/timing.arrivalDuration)^2 end
        local sceneryDistance=(25+125*speedFactor)*EngineUpgrades.profile(saveData.engineLevel).speed*dt
        sceneryOffset=(sceneryOffset+sceneryDistance)%W
        landscapeOffset=landscapeOffset+sceneryDistance
        if not travelTransition.changed and travelTransition.t>=timing.change then
            travelTransition.changed=true; saveData.location=saveData.location+1; saveData.stopped=true; saveData.visitedStops[saveData.location]=true
            Maintenance.onTravel(saveData)
            -- The scene is still the train interior at this point. Keep the
            -- player in the active car; trainPoint coordinates belong to the
            -- destination stop map and would place the character outside the
            -- train until the next movement clamp corrected it.
            player.x,player.y=clampToTrainFloor(player.x,player.y)
            for _,id in ipairs(saveData.trainCars or {}) do if id=="greenhouse" then saveData.resources.food=math.min(30,saveData.resources.food+1) elseif id=="medical" then saveData.health=math.min(saveData.maxHealth,saveData.health+3) end end
            ensureStopLayout(); passengerContributions(); processPassengerArrivals(); writeSave()
        end
        if not travelTransition.arriveSoundPlayed and travelTransition.t>=timing.arrive then travelTransition.arriveSoundPlayed=true; ui.playSfx("trainArrive") end
        if travelTransition.t>=timing.total then travelTransition=nil; sceneryOffset=0; landscapeOffset=0; if saveData.location>=50 then state=session:setScreen("ending") elseif saveData.arrivalNotice then dialogue={speaker="Passenger",text=saveData.arrivalNotice,timer=4}; saveData.arrivalNotice=nil; writeSave() end end
        return
    end
    if holdPickupIndex then
        local item=saveData and saveData.droppedItems[holdPickupIndex]
        if not love.keyboard.isDown("e") or not item or not itemIsHere(item) or math.sqrt((player.x-item.x)^2+(player.y-item.y)^2)>=75 then
            holdPickupIndex,holdPickupTime=nil,0
        else
            holdPickupTime=holdPickupTime+dt
            if holdPickupTime>=HOLD_PICKUP_SECONDS then
                nearbyItem=holdPickupIndex; pickUpNearby(); holdPickupIndex,holdPickupTime=nil,0
            end
        end
    end
    if scene ~= "train" and not npcActor then setupNPC() end
    if dialogue then dialogue.timer = dialogue.timer - dt; if dialogue.timer <= 0 then dialogue = nil end end
    if scene=="train" then
        local sceneryDistance=18*dt
        sceneryOffset=(sceneryOffset+sceneryDistance)%W
        landscapeOffset=landscapeOffset+sceneryDistance
    end
    if carTransition then
        carTransition.t=math.min(carTransition.duration,carTransition.t+dt)
        player.moving=false
        if carTransition.t>=carTransition.duration then
            saveData.activeCar=carTransition.to
            player.x,player.y=carTransition.targetX,carTransition.targetY
            carTransition=nil; writeSave()
        end
        return
    end
    Maintenance.update(maintenanceSession,dt)
    if maintenanceSession.open or inventoryOpen or mapOpen or dialogue or editMode or ui.radioOpen then return end
    local dx = movementAxis("a", "d") + movementAxis("left", "right")
    local dy = movementAxis("w", "s") + movementAxis("up", "down")
    player.moving = dx ~= 0 or dy ~= 0
    if player.moving then
        playerPose="idle"; poseMenu=false
        local length = math.sqrt(dx*dx + dy*dy); dx, dy = dx/length, dy/length
        if dx ~= 0 then player.facing = dx > 0 and 1 or -1 end
        local sprint=love.keyboard.isDown("lshift","rshift") and 1.7 or 1
        local oldX,oldY=player.x,player.y
        player.x, player.y = player.x + dx*player.speed*sprint*dt, player.y + dy*player.speed*sprint*dt
        if walkingSoundTimer<=0 then
            ui.playSfx("walkingSteps")
            walkingSoundTimer=math.max(.18, .34/sprint)
        end
        if scene=="train" then
            player.x,player.y=clampToTrainFloor(player.x,player.y)
        elseif scene=="stop" then
            player.x,player.y=Settlements.move(saveData.location,oldX,oldY,player.x,player.y)
        else
            player.x,player.y=Util.clampHouseFloor(player.x,player.y)
        end
    end
    if npcActor then
        Family.update(npcActor,dt,function(oldX,oldY,newX,newY)
            if scene=="stop" then return Settlements.move(saveData.location,oldX,oldY,newX,newY) end
            if scene=="house" then return Util.clampHouseFloor(newX,newY) end
            return newX,newY
        end)
        npcActor.wait = (npcActor.wait or 1) - dt
        if npcActor.wait <= 0 then
            local angle = love.math.random() * math.pi * 2
            local distance = love.math.random(18, 58)
            npcActor.targetX = npcActor.homeX + math.cos(angle) * distance
            npcActor.targetY = npcActor.homeY + math.sin(angle) * distance * 0.55
            npcActor.wait = love.math.random(3, 7)
        end
        if npcActor.targetX then
            if scene=="house" then npcActor.targetX,npcActor.targetY=Util.clampHouseFloor(npcActor.targetX,npcActor.targetY) elseif scene=="stop" then npcActor.targetX,npcActor.targetY=Settlements.clamp(npcActor.targetX,npcActor.targetY,saveData.location) end
            local nx,ny=npcActor.targetX-npcActor.x,npcActor.targetY-npcActor.y; local len=math.sqrt(nx*nx+ny*ny)
            if len < 2 then npcActor.targetX=nil else
                if math.abs(nx)>0.1 then npcActor.facing=nx>0 and 1 or -1 end
                local step=math.min(len,32*dt); npcActor.x=npcActor.x+nx/len*step; npcActor.y=npcActor.y+ny/len*step
            end
        end
    end
    if scene=="train" then for _,passenger in ipairs(saveData.passengers or {}) do
        passenger.carIndex=math.max(1,math.min(#(saveData.trainCars or {1}),passenger.carIndex or 1)); passenger.wait=(passenger.wait or 1)-dt
        if passenger.wait<=0 then
            local preferred=Passengers.preferredCar(passenger,saveData.trainCars)
            if preferred~=passenger.carIndex and love.math.random()<.55 then passenger.targetCar=preferred; passenger.targetX=preferred>passenger.carIndex and car.x+car.w-35 or car.x+35; passenger.targetY=car.y+205
            else local left,right,top,bottom=trainFloorBounds(); passenger.targetX,passenger.targetY=clampToTrainFloor(love.math.random(left+20,right-20),love.math.random(top,bottom)) end
            passenger.wait=love.math.random(4,8); passenger.pose="idle"
        end
        if passenger.targetX then
            local dx,dy=passenger.targetX-passenger.x,passenger.targetY-passenger.y; local len=math.sqrt(dx*dx+dy*dy)
            if len<2 then
                passenger.targetX=nil
                if passenger.targetCar then local left,right,top,bottom=trainFloorBounds(); passenger.carIndex=passenger.targetCar; passenger.targetCar=nil; passenger.x=passenger.carIndex>1 and left or right; passenger.y=(top+bottom)/2 end
                local hasSleeper=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="sleeper" then hasSleeper=true end end; passenger.pose=(hasSleeper and love.math.random()<.25) and "lay" or (love.math.random()<.55 and "sit" or "idle")
            else local step=math.min(len,38*dt); passenger.x=passenger.x+dx/len*step; passenger.y=passenger.y+dy/len*step; passenger.facing=dx>0 and 1 or -1 end
        end
    end end
    ui.updateInteraction()
end

local function drawMenuFrame(x,y,w,h,kind,alpha)
    local frame=ui.menuFrames and ui.menuFrames[kind or 1]
    if frame then
        love.graphics.setColor(1,1,1,alpha or 1)
        local sw,sh=frame.w,frame.h; local sx=math.floor(sw*.22); local sy=math.floor(sh*.28)
        local dx=math.min(kind==4 and 11 or 16,math.floor(w/4)); local dy=math.min(kind==4 and 8 or 14,math.floor(h/4))
        local xs={0,sx,sw-sx,sw}; local ys={0,sy,sh-sy,sh}; local xd={x,x+dx,x+w-dx,x+w}; local yd={y,y+dy,y+h-dy,y+h}
        for row=1,3 do for col=1,3 do local qw,qh=xs[col+1]-xs[col],ys[row+1]-ys[row]; local dw,dh=xd[col+1]-xd[col],yd[row+1]-yd[row]; if qw>0 and qh>0 and dw>0 and dh>0 then love.graphics.draw(frame.image,frame.quads[row][col],xd[col],yd[row],0,dw/qw,dh/qh) end end end
    else love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,w,h,8,8) end
end

function ui.drawJourneyHUD()
    -- Consolidate the loose journey text into the same brass-and-iron visual
    -- language as the rest of the interface.
    drawMenuFrame(10,58,410,132,4,.90)
    love.graphics.setColor(colors.brass)
    love.graphics.rectangle("fill",25,91,378,2)
    love.graphics.setColor(colors.cream)
    love.graphics.print("STOP "..saveData.location,26,70,0,1.05,1.05)
    love.graphics.printf((saveData.trait and saveData.trait.name or "Survivor").."  •  CARS "..#(saveData.trainCars or {}),145,72,255,"right",0,.76,.76)
    love.graphics.print("MOVE",26,99,0,.70,.70)
    love.graphics.print("WASD / ARROWS",80,98,0,.80,.80)
    ui.drawHealthBar("HP",saveData.health,saveData.maxHealth,25,119,220)

    local level=saveData.stats.level or 1
    local xp=saveData.stats.xp or 0
    local nextXP=math.max(1,saveData.stats.nextXP or 10)
    love.graphics.setColor(colors.cream)
    love.graphics.print("LV "..level,265,119,0,.86,.86)
    love.graphics.print(xp.." / "..nextXP.." XP",318,119,0,.70,.70)
    love.graphics.setColor(.08,.06,.045,.92); love.graphics.rectangle("fill",265,149,130,12,3,3)
    love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",267,151,126*math.min(1,xp/nextXP),8,2,2)
    love.graphics.setColor(colors.cream); love.graphics.printf("JOURNEY STATUS",25,169,370,"center",0,.56,.56)

    local ammoParts={}
    for i=1,2 do
        local weapon=saveData.equipment[i]; local combat=weapon and Catalog.weaponCombat[weapon]
        if combat and combat.ammo then ammoParts[#ammoParts+1]=Util.titleFromFile(combat.ammo).."  "..(saveData.ammo[combat.ammo] or 0) end
    end
    if #ammoParts>0 then
        drawMenuFrame(500,143,225,42,4,.90)
        love.graphics.setColor(colors.brass); love.graphics.print("AMMO",516,156,0,.66,.66)
        love.graphics.setColor(colors.cream); love.graphics.printf(table.concat(ammoParts,"   •   "),568,155,140,"center",0,.66,.66)
    end
end

local function button(text, x, y, w, h, active, textScale)
    if ui.menuFrames and ui.menuFrames[4] then drawMenuFrame(x-3,y-3,w+6,h+6,4,active and 1 or .55) else love.graphics.setColor(active and colors.brass or colors.panel); love.graphics.rectangle("fill", x, y, w, h, 8, 8) end
    local scale=textScale or 1
    love.graphics.setColor(colors.cream); love.graphics.printf(text, x+5, y+h/2-8*scale, w-10, "center",0,scale,scale)
    return {x=x,y=y,w=w,h=h}
end

local function requestExitPrompt(kind)
    exitPrompt=kind
    if ui.playSfx then ui.playSfx("menu") end
end

local function resolveExitPrompt(choice)
    local prompt=exitPrompt
    exitPrompt=nil
    if choice~="yes" then return end
    if prompt=="title" then
        writeSave()
        state=session:setScreen("slots")
    elseif prompt=="quit" then
        love.event.quit()
    end
end

local function drawExitPrompt()
    if not exitPrompt then return end
    love.graphics.setColor(0,0,0,.70)
    love.graphics.rectangle("fill",0,0,W,H)
    drawMenuFrame(270,252,420,196,2,.99)
    love.graphics.setColor(colors.cream)
    local title=exitPrompt=="quit" and "Quit Game?" or "Return to Title Screen?"
    love.graphics.printf(title,290,290,380,"center",0,1.25,1.25)
    love.graphics.setColor(colors.brass)
    love.graphics.rectangle("fill",315,340,330,2)
    ui.exitYes=button("Yes",330,375,115,44,true,.92)
    ui.exitNo=button("No",515,375,115,44,true,.92)
end

function ui.drawSlots()
    love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
    if scenery.titleImage then
        local scale=math.min(540/scenery.titleImage:getWidth(),185/scenery.titleImage:getHeight())
        love.graphics.setColor(1,1,1)
        love.graphics.draw(scenery.titleImage,W/2,88,0,scale,scale,scenery.titleImage:getWidth()/2,scenery.titleImage:getHeight()/2)
    else
        love.graphics.printf("MOUSE FRONTIER", 0, 82, W, "center", 0, 2.2, 2.2)
    end
    love.graphics.setColor(colors.cream)
    love.graphics.printf("Choose a journey", 0, 182, W, "center")
    ui.slots, ui.slotNew, ui.slotDelete = {}, {}, {}
    for i=1,3 do
        local data, y = Save.read(i), 225+(i-1)*125
        love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", 210, y, 540, 96, 12, 12)
        love.graphics.setColor(colors.cream); love.graphics.print("SAVE "..i, 232, y+18, 0, 1.3, 1.3)
        love.graphics.print(data and (Util.titleFromFile(data.character).."  •  Stop "..tostring(data.location or 1)) or "New journey", 232, y+52)
        if data then
            ui.slots[i]=button("CONTINUE",500,y+16,105,32,true)
            ui.slotNew[i]=button("NEW",612,y+16,52,32,true)
            ui.slotDelete[i]=button("DELETE",671,y+16,65,32,true)
        else ui.slotNew[i]=button("NEW GAME",585,y+25,138,46,true) end
    end
end

function ui.drawCharacterSelect()
    love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
    love.graphics.printf("CHOOSE YOUR TRAVELER", 0, 34, W, "center", 0, 1.6, 1.6)
    love.graphics.printf("Everyone else will remain available as an NPC.", 0, 70, W, "center")
    ui.characters = {}
    local rows=math.ceil(#characters/5); local maxScroll=math.max(0,rows-3); characterScroll=math.max(0,math.min(maxScroll,characterScroll))
    local hoveredFile
    local mouseX,mouseY=screenToGame(love.mouse.getPosition())
    for i, file in ipairs(characters) do
        local col, row = (i-1)%5, math.floor((i-1)/5); local x, y = 42+col*182, 100+(row-characterScroll)*198
        local r={x=x,y=y,w=150,h=180}; ui.characters[i]=r
        if y>78 and y<700 then
        love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", x,y,r.w,r.h,10,10)
        local img=characterImages[file]
        if img then local s=math.min(112/img:getWidth(),120/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,x+75,y+68,0,s,s,img:getWidth()/2,img:getHeight()/2) end
        love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(file),x+5,y+142,r.w-10,"center",0,0.82,0.82)
        if Util.pointIn(mouseX,mouseY,r) then hoveredFile=file end
        end
    end
    if hoveredFile then
        local lower=hoveredFile:lower()
        local trait=Catalog.characterTrait(hoveredFile)
        local abilityProfile=Catalog.characterAbility(hoveredFile)
        local ability,abilityDescription=abilityProfile.name,abilityProfile.description
        local tooltipW,tooltipH=265,142
        local tx,ty=mouseX+18,mouseY+18
        if tx+tooltipW>W then tx=mouseX-tooltipW-18 end
        if ty+tooltipH>H then ty=H-tooltipH-10 end
        love.graphics.setColor(.055,.04,.03,.97); love.graphics.rectangle("fill",tx,ty,tooltipW,tooltipH,8,8)
        love.graphics.setColor(colors.brass); love.graphics.rectangle("line",tx,ty,tooltipW,tooltipH,8,8)
        love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(hoveredFile),tx+12,ty+10,tooltipW-24,"left",0,.88,.88)
        love.graphics.setColor(colors.brass); love.graphics.print("ABILITY  "..ability,tx+12,ty+34,0,.65,.65)
        love.graphics.setColor(colors.cream); love.graphics.printf(abilityDescription,tx+12,ty+51,tooltipW-24,"left",0,.62,.62)
        love.graphics.setColor(colors.brass); love.graphics.print("TRAIT  "..trait.name,tx+12,ty+79,0,.65,.65)
        love.graphics.setColor(colors.cream); love.graphics.printf(trait.description,tx+12,ty+96,tooltipW-24,"left",0,.58,.58)
    end
    ui.characterUp=button("^",905,110,38,42,characterScroll>0); ui.characterDown=button("v",905,590,38,42,characterScroll<maxScroll)
    love.graphics.setColor(colors.cream); love.graphics.print("SCROLL",898,165,0,0.65,0.65)
end

local function drawLandscape()
    local backgroundCount=#backgroundImages
    local image = backgroundCount>0 and backgroundImages[((saveData.location-1)%backgroundCount)+1] or nil
    if image then
        local s=math.max(W/image:getWidth(), H/image:getHeight())
        local iw=image:getWidth()*s; local offset=landscapeOffset%iw; love.graphics.setColor(0.78,0.78,0.78)
        for x=offset-iw, W+iw, iw do love.graphics.draw(image,x,0,0,s,s) end
    else love.graphics.clear(0.55,0.37,0.20) end
end

local function drawTracks()
    if Train.drawTracks(scenery.track,W) then return end
    -- Fallback track uses the same rail baseline as the artwork-backed path.
    local railY=Train.railY
    local farRailY=railY-(414-300)*(W/2172)
    love.graphics.setColor(0.16,0.12,0.09); love.graphics.rectangle("fill",0,farRailY-2,W,12); love.graphics.rectangle("fill",0,railY-2,W,12)
    love.graphics.setColor(0.28,0.20,0.12)
    for x=sceneryOffset%70-70, W,70 do love.graphics.rectangle("fill",x,farRailY-12,18,railY-farRailY+34) end
    love.graphics.setColor(0.52,0.48,0.42); love.graphics.rectangle("fill",0,farRailY+2,W,5); love.graphics.rectangle("fill",0,railY+2,W,5)
end

local function drawLocomotive()
    local frames=scenery.worldTrainFrames or {}; local frameIndex=(math.floor(trainAnimationClock)%3)+1; local image=frames[frameIndex] or scenery.worldTrain
    if not image then return end
    Train.drawLocomotive(image,frames[frameIndex] and frameIndex or nil,car)
end

local function drawTrainCar(index)
    local x=car.x; local y=car.y
    local carId=saveData.trainCars and saveData.trainCars[index]
    local carImage=carId and scenery.trainCarImages and scenery.trainCarImages[carId]
    if carImage then
        Train.drawCarImage(carImage,car)
        if index==1 then
            if scenery.boiler then local s=150/scenery.boiler:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.boiler,x+165,y+244,0,s,s,scenery.boiler:getWidth()/2,scenery.boiler:getHeight()/2) end
            local fireFrame=scenery.fireFrames and scenery.fireFrames[(math.floor(animationClock/0.55)%#scenery.fireFrames)+1] or scenery.fire
            if fireFrame then local s=48/fireFrame:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(fireFrame,x+165,y+252,0,s,s,fireFrame:getWidth()/2,fireFrame:getHeight()/2) end
        end
        return
    end
    love.graphics.setColor(0.10,0.09,0.08); love.graphics.circle("fill",x+35,y+car.h+13,22); love.graphics.circle("fill",x+car.w-35,y+car.h+13,22)
    love.graphics.setColor(colors.brass); love.graphics.circle("line",x+35,y+car.h+13,13); love.graphics.circle("line",x+car.w-35,y+car.h+13,13)
    love.graphics.setColor(colors.trim); love.graphics.polygon("fill",x-8,y+18,x+8,y,x+car.w-18,y,x+car.w+8,y+18,x+car.w+8,y+car.h,x-8,y+car.h)
    love.graphics.setColor(colors.wall); love.graphics.polygon("fill",x,y+18,x+car.w,y+18,x+car.w,y+car.h-10,x+12,y+car.h-10,x,y+car.h-32)
    for wx=x+25,x+car.w-60,110 do
        love.graphics.setColor(colors.trim); love.graphics.rectangle("fill",wx-4,y+30,48,76,5,5)
        love.graphics.setColor(0.52,0.72,0.76); love.graphics.rectangle("fill",wx,y+34,40,68,3,3)
        love.graphics.setColor(1,1,1,0.18); love.graphics.rectangle("fill",wx+5,y+39,7,55)
        if scenery.curtain then local cs=84/scenery.curtain:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.curtain,wx+20,y+68,0,cs,cs,scenery.curtain:getWidth()/2,scenery.curtain:getHeight()/2) end
    end
    local fy=y+118; love.graphics.setColor(colors.floorA); love.graphics.rectangle("fill",x+10,fy,car.w-20,car.h-128)
    if scenery.homeTexture then love.graphics.setColor(1,1,1); love.graphics.draw(scenery.homeTexture,x+10,fy,0,(car.w-20)/scenery.homeTexture:getWidth(),(car.h-128)/scenery.homeTexture:getHeight())
    else love.graphics.setColor(colors.floorB); for yy=fy, y+car.h-10,25 do love.graphics.rectangle("fill",x+10,yy,car.w-20,3) end end
    love.graphics.setColor(0.20,0.22,0.23); love.graphics.rectangle("line",x+10,fy,car.w-20,car.h-128)
    love.graphics.setColor(colors.brass); for rx=x+20,x+car.w-18,36 do love.graphics.circle("fill",rx,fy+5,2) end
    love.graphics.setColor(colors.trim); love.graphics.rectangle("fill",x-5,y+143,12,72); love.graphics.rectangle("fill",x+car.w-7,y+143,12,72)
    if index==1 then
        if scenery.boiler then local s=150/scenery.boiler:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.boiler,x+105,y+194,0,s,s,scenery.boiler:getWidth()/2,scenery.boiler:getHeight()/2)
        else love.graphics.setColor(0.12,0.10,0.08); love.graphics.rectangle("fill",x+38,y+135,135,118,12,12) end
        local fireFrame=scenery.fireFrames and scenery.fireFrames[(math.floor(animationClock/0.55)%#scenery.fireFrames)+1] or scenery.fire
        if fireFrame then local s=48/fireFrame:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(fireFrame,x+105,y+202,0,s,s,fireFrame:getWidth()/2,fireFrame:getHeight()/2) end
    end
end

function ui.drawResource(name, value, x, color, width)
    width=width or 150
    local barWidth=math.max(20,width-66)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,20,width,34,7,7)
    love.graphics.setColor(color); love.graphics.rectangle("fill",x+58,29,math.max(0,math.min(barWidth,value*barWidth/20)),16,4,4)
    love.graphics.setColor(colors.cream); love.graphics.print(name.." "..value,x+6,28,0,.92,.92)
end

function ui.drawHealthBar(label,value,maxValue,x,y,w)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,w,30,6,6)
    love.graphics.setColor(0.25,0.08,0.07); love.graphics.rectangle("fill",x+55,y+8,w-65,14,3,3)
    love.graphics.setColor(0.78,0.18,0.16); love.graphics.rectangle("fill",x+55,y+8,(w-65)*math.max(0,value)/math.max(1,maxValue),14,3,3)
    love.graphics.setColor(colors.cream); love.graphics.print(label.." "..value.."/"..maxValue,x+7,y+7)
end

function ui.setInventoryState(name,value)
    if name=="draggedSlot" then draggedSlot=value elseif name=="inventoryDragActive" then inventoryDragActive=value
    elseif name=="giftOpen" then giftOpen=value elseif name=="giftSlot" then giftSlot=value
    elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="lastClick" then lastInventoryClick=value
    elseif name=="lastClickTime" then lastInventoryClickTime=value end
end

function ui.inventoryContext()
    return {data=saveData,activeChest=activeChest,chestOpen=chestOpen,inventoryOpen=inventoryOpen,draggedSlot=draggedSlot,inventoryDragActive=inventoryDragActive,
        giftOpen=giftOpen,giftNPC=giftNPC,giftSlot=giftSlot,lastClick=lastInventoryClick,lastClickTime=lastInventoryClickTime,nearNPC=nearNPC,nearPassenger=nearPassenger,
        ui=ui,Inventory=Inventory,Catalog=Catalog,colors=colors,pointIn=Util.pointIn,title=Util.titleFromFile,isWeapon=isWeapon,
        drawMenuFrame=drawMenuFrame,button=button,pointer=function() return screenToGame(love.mouse.getPosition()) end,value=containerValue,set=ui.setInventoryState,
        battleMode=state=="battle",move=moveBetweenSlots,quickTransfer=quickTransfer,collectAmmo=collectAmmo,drop=state=="battle" and function() return false end or dropFromContainer,
        consume=state=="battle" and consumeBattleSelected or consumeSelected}
end

function ui.drawInventory() Systems.inventory.draw(ui.inventoryContext()) end
function ui.drawChestInventory() Systems.inventory.drawChest(ui.inventoryContext()) end
function ui.drawItem(name,r) Systems.inventory.drawItem(ui.inventoryContext(),name,r) end

local function drawTrade()
    local layout=ensureStopLayout(); layout.tradeStock=layout.tradeStock or {}
    love.graphics.setColor(0,0,0,.72); love.graphics.rectangle("fill",0,0,W,H)
    drawMenuFrame(90,65,780,600,1,1); love.graphics.setColor(colors.cream)
    love.graphics.printf(Util.titleFromFile(tradeNPC or saveData.currentNPC).."'S TRADING POST",110,95,740,"center",0,1.35,1.35)
    love.graphics.printf("YOUR SCRAP: "..(saveData.scrap or 0).."   •   Buy supplies, sell gear, or give your ally a weapon",120,135,720,"center",0,.82,.82)
    ui.tradeBuy={}; love.graphics.print("FOR SALE",135,180)
    for i=1,4 do local name=layout.tradeStock[i]; if name then local y=210+(i-1)*82; local price=Inventory.scrapPrice(name,Catalog); ui.drawItem(name,{x=135,y=y,w=62,h=62}); love.graphics.setColor(colors.cream); love.graphics.print(Util.titleFromFile(name),210,y+8,0,.82,.82); love.graphics.print(price.." SCRAP",210,y+35,0,.72,.72); ui.tradeBuy[i]=button("BUY",365,y+12,90,38,saveData.scrap>=price and Inventory.firstEmptySlot(saveData)~=nil) end end
    love.graphics.print("YOUR ITEMS",500,180); love.graphics.print("NPC BUDGET: "..(layout.tradeBudget or 0).." SCRAP",500,202); ui.tradeSell={}; ui.tradeGive={}
    local row=0; for i=1,(saveData.inventoryCapacity or 6) do local name=saveData.inventory[i]; if name and row<5 then local y=210+row*72; ui.drawItem(name,{x=495,y=y,w=54,h=54}); love.graphics.setColor(colors.cream); love.graphics.print(Util.titleFromFile(name),555,y+5,0,.72,.72); ui.tradeSell[i]=button("SELL +"..math.max(1,math.floor(Inventory.scrapPrice(name,Catalog)/2)),700,y+5,110,30,true); if isWeapon(name) then ui.tradeGive[i]=button("GIVE",700,y+37,110,28,true) end; row=row+1 end end
    ui.tradeClose=button("DONE TRADING",375,605,210,40,true)
end

local function drawAnimatedCharacter(file,action,x,y,maxW,maxH,facing,phase)
    return CharacterAnimation.draw(characterAnimations,file,action,x,y,maxW,maxH,facing,phase,animationClock)
end

local function drawPlayer()
    if not player.image then return end
    if characterAnimations[saveData.character] then
        if player.moving and actionTimer<=0 then
            love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",player.x,player.y+28,20,7)
            if drawAnimatedCharacter(saveData.character,"walk",player.x,player.y+34,82,104,player.facing,animationClock) then return end
        end
        if not player.moving or actionTimer>0 then
            local action=actionTimer>0 and (actionKind or "use") or (playerPose=="sit" and "sit" or (playerPose=="lay" and "lay" or "idle"))
            love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",player.x,player.y+28,20,7)
            local actionPhase=actionTimer>0 and math.max(0,.35-actionTimer) or animationClock
            drawAnimatedCharacter(saveData.character,action,player.x,player.y+34,82,104,player.facing,actionPhase)
            if actionTimer>0 and actionHeldItem then ui.drawItem(actionHeldItem,{x=player.x+(player.facing==1 and 12 or -42),y=player.y-22,w=32,h=32}) end
            return
        end
    end
    local actionImage=actionTimer>0 and characterActionImages[saveData.character]
    local image,drawFacing,scale=actionImage or player.image,-player.facing,player.scale
    -- Action sheets use much more of their canvas than the idle portraits. Match
    -- their visible body size, not only the PNG canvas height.
    if actionImage then scale=((player.image:getHeight()*player.scale)/actionImage:getHeight())*.78 end
    if player.moving and actionTimer<=0 then
        local walk=characterWalkImages[saveData.character]
        if walk then image=walk; drawFacing=-player.facing; scale=math.min(0.075,90/image:getHeight()) end
    end
    local bob=0
    love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",player.x,player.y+28,20,7)
    local rotation,scaleY,yOffset=0,scale,0
    if playerPose=="sit" then scaleY=scale*.72; yOffset=10 elseif playerPose=="lay" then rotation=math.pi/2; scaleY=scale*.82; yOffset=16 end
    love.graphics.setColor(1,1,1); love.graphics.draw(image,player.x,player.y+bob+yOffset,rotation,scale*drawFacing,scaleY,image:getWidth()/2,image:getHeight()/2)
end

local function drawDroppedItems(carIndex)
    local cacheKey=carIndex and ("train:"..tostring(carIndex)) or (scene..":"..tostring(saveData.location)..":"..tostring(saveData.activeHouseDoor or 0))
    local revision=ui.itemOrderRevision or 0
    ui.itemOrderCache=ui.itemOrderCache or {}
    local cached=ui.itemOrderCache[cacheKey]
    local ordered
    if cached and cached.revision==revision then ordered=cached.items else
        ordered={}
        for i,item in ipairs(saveData.droppedItems) do
            local visible=carIndex and item.scene=="train" and (item.carIndex or 1)==carIndex or (not carIndex and itemIsHere(item))
            if visible then ordered[#ordered+1]={index=i,item=item} end
        end
        table.sort(ordered,function(a,b) return (a.item.layer or a.index)<(b.item.layer or b.index) end)
        ui.itemOrderCache[cacheKey]={revision=revision,items=ordered}
    end
    for _,entry in ipairs(ordered) do local i,item=entry.index,entry.item
        local img=ui.propImages[item.name]; local scale=item.scale or 1; local rotation=item.rotation or 0
        if img then
            local idleFrames=itemIdleImages[item.name]
            if idleFrames and not editMode then img=idleFrames[(math.floor(animationClock/1.05)%#idleFrames)+1] or img end
            local s=math.min(58/img:getWidth(),58/img:getHeight())*scale
            local plant=not idleFrames and (item.name:find("tree") or item.name:find("plant") or item.name:find("potted") or item.name:find("flower") or item.name:find("sprout") or item.name:find("fern") or item.name:find("shrub") or item.name:find("reeds") or item.name:find("herb") or item.name:find("mushroom"))
            love.graphics.setColor(1,1,1)
            local tintShader=ui.objectTintShader
            if tintShader then tintShader:send("hueShift",item.hue or 0); tintShader:send("saturation",item.saturation or 1); love.graphics.setShader(tintShader) end
            if plant and not editMode then
                local phase=(item.x*.017+item.y*.011); local sway=math.sin(animationClock*.85+phase)*math.rad(.75); local bob=math.sin(animationClock*1.05+phase)*.45
                local bottom=item.y+img:getHeight()*s/2
                love.graphics.draw(img,item.x,bottom+bob,rotation+sway,s,s,img:getWidth()/2,img:getHeight())
            else love.graphics.draw(img,item.x,item.y,rotation,s,s,img:getWidth()/2,img:getHeight()/2) end
            if tintShader then love.graphics.setShader() end
        else ui.drawItem(item.name,{x=item.x-30*scale,y=item.y-30*scale,w=60*scale,h=60*scale}) end
        if item.name=="mailbox-reward" and item.mailUnread and ui.propImages["family-letter"] and not editMode then
            local mail=ui.propImages["family-letter"]; local ms=28/math.max(mail:getWidth(),mail:getHeight())
            love.graphics.setColor(1,1,1); love.graphics.draw(mail,item.x,item.y-48+math.sin(animationClock*3)*3,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2)
        end
        if editMode and (not carIndex or carIndex==(saveData.activeCar or 1)) then local hx,hy=item.x+31,item.y+31; love.graphics.setColor(1,.78,.1); love.graphics.rectangle("fill",hx-7,hy-7,14,14); love.graphics.setColor(colors.ink); love.graphics.rectangle("line",hx-7,hy-7,14,14); if editedItem==i then love.graphics.setColor(colors.brass); love.graphics.setLineWidth(3); love.graphics.circle("line",item.x,item.y,38); love.graphics.setLineWidth(1) end end
    end
end

local function trainItemAt(x,y)
    local best,bestLayer=nil,-math.huge
    for i,item in ipairs(saveData.droppedItems) do
        if itemIsHere(item) then
            local hx,hy=item.x+31,item.y+31
            if math.abs(x-hx)<=14 and math.abs(y-hy)<=14 and (item.layer or i)>bestLayer then best,bestLayer=i,item.layer or i end
        end
    end
    return best
end

local function drawNPC()
    local npcFile=saveData.currentNPC; local img=npcFile and (npcImages[npcFile] or characterImages[npcFile])
    if not (img and npcActor) then return end
    local idle=0
    if npcActor.targetX and characterAnimations[npcFile] then
        love.graphics.setColor(0,0,0,0.24); love.graphics.ellipse("fill",npcActor.x,npcActor.y+28,20,7)
        if drawAnimatedCharacter(npcFile,"walk",npcActor.x,npcActor.y+34,82,104,npcActor.facing or 1,animationClock) then
            love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(npcFile),npcActor.x-100,npcActor.y+50,200,"center")
            Family.draw(npcActor,familyImages,animationClock)
            return
        end
    elseif npcActor.targetX and (npcWalkImages[npcFile] or characterWalkImages[npcFile]) then img=npcWalkImages[npcFile] or characterWalkImages[npcFile] end
    local s=math.min(0.075,90/img:getHeight()); local facing=-(npcActor.facing or 1)
    if npcActor.targetX and (npcWalkImages[npcFile] or characterWalkImages[npcFile]) then facing=-facing end
    love.graphics.setColor(0,0,0,0.24); love.graphics.ellipse("fill",npcActor.x,npcActor.y+28,20,7)
    if not npcActor.targetX and drawAnimatedCharacter(npcFile,"idle",npcActor.x,npcActor.y+34,82,104,facing) then else love.graphics.setColor(1,1,1); love.graphics.draw(img,npcActor.x,npcActor.y+idle,0,s*facing,s,img:getWidth()/2,img:getHeight()/2) end
    love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(npcFile),npcActor.x-100,npcActor.y+50,200,"center")
    if pendingMailHere() and ui.propImages["family-letter"] then local mail=ui.propImages["family-letter"]; local ms=34/math.max(mail:getWidth(),mail:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(mail,npcActor.x,npcActor.y-82+math.sin(animationClock*4)*3,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2) end
    Family.draw(npcActor,familyImages,animationClock)
end

local function drawPassengers(carIndex)
    local visibleCar=carIndex or (saveData.activeCar or 1)
    for i,passenger in ipairs(saveData.passengers or {}) do
        if (passenger.carIndex or 1)==visibleCar then
        local moving=passenger.targetX~=nil; local legacyWalk=moving and (npcWalkImages[passenger.npc] or characterWalkImages[passenger.npc]); local img=legacyWalk or npcImages[passenger.npc] or characterImages[passenger.npc]
        if img then local s=math.min(.075,90/img:getHeight()); local face=passenger.facing or 1; love.graphics.setColor(0,0,0,0.22); love.graphics.ellipse("fill",passenger.x,passenger.y+28,20,7); if drawAnimatedCharacter(passenger.npc,moving and "walk" or (passenger.pose or "idle"),passenger.x,passenger.y+34,82,104,face,animationClock+i*.2) then else love.graphics.setColor(1,1,1); love.graphics.draw(img,passenger.x,passenger.y,0,s*(legacyWalk and -face or -face),s,img:getWidth()/2,img:getHeight()/2) end end
        end
    end
end

local function drawGround()
    if scenery.stopGround then
        local atlas=scenery.stopGround; local index=((saveData.location-1)%4)+1
        love.graphics.setColor(1,1,1)
        -- Draw one continuous surface. Repeating this non-seamless artwork in
        -- 320-pixel strips exposed the left/right borders of every copy.
        love.graphics.draw(atlas.image,atlas.quads[index],0,360,0,W/atlas.w,360/atlas.h)
        return
    end
    love.graphics.setColor(0.27,0.38,0.16); love.graphics.rectangle("fill",0,430,W,290)
    love.graphics.setColor(0.34,0.48,0.20)
    for y=442,710,24 do for x=(y/24%2)*18,950,36 do love.graphics.rectangle("fill",x,y,3,7) end end
    love.graphics.setColor(0.55,0.45,0.28)
    love.graphics.polygon("fill",120,720,255,590,440,548,610,520,960,555,960,635,650,590,460,610,300,655,230,720)
    love.graphics.setColor(0.66,0.56,0.36)
    for x=245,900,75 do love.graphics.rectangle("fill",x,590-math.sin(x)*25,18,8) end
end

local function drawStop()
    if scenery.settlements and Settlements.draw(scenery.settlements,saveData.location,W,H) then
        local trainX,trainY=Settlements.trainPoint(saveData.location)
        if scenery.redTrain then
            local image=scenery.redTrain; local scale=52/math.max(image:getWidth(),image:getHeight())
            love.graphics.setColor(1,1,1,.92)
            love.graphics.draw(image,trainX,trainY-8,0,scale,scale,image:getWidth()/2,image:getHeight()/2)
        end
        love.graphics.setColor(1,.78,.12,.78)
        love.graphics.circle("line",trainX,trainY+math.sin(animationClock*3)*2,12)
        love.graphics.setColor(colors.cream)
        love.graphics.printf("Q",trainX-12,trainY-5,24,"center",0,.7,.7)
        drawDroppedItems()
        StopSludges.draw(stopSludges,{data=saveData,location=saveData.location,clock=animationClock,images={
            idle=mobIdleImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
            walk=mobWalkImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
            hit=mobHitImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
            death=mobDeathImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"]
        }})
        ui.drawChickens(ensureStopLayout()); ui.drawMice(ensureStopLayout())
        drawNPC(); drawPlayer(); return
    end
    drawGround()
    local env=scenery.environment or {}
    local homes={"house-overgrown","house-purple","house-shed","home-water-tower","home-roadside-diner","home-burrow-mound","home-general-store","home-signal-cabin"}
    local trees={"tree-broadleaf","tree-flowering","tree-dead-cloth","tree-cottonwood","tree-mushroom","tree-burned-regrowth","tree-apple-swing"}
    local layout=(scene=="house" and Stops.ensureDoor(saveData,Catalog,saveData.activeHouseDoor or saveData.lastStopDoor)) or ensureStopLayout()
    local decorations={}; for i,decoration in ipairs(layout.decorations or {}) do decorations[i]=decoration end; table.sort(decorations,function(a,b) return a.y<b.y end)
    for _,decoration in ipairs(decorations) do
        local pool=decoration.kind=="wildlife" and scenery.stopWildlife or scenery.stopProps; local image=pool and pool[decoration.name]
        if image then
            local name=decoration.name or ""; local wildlife=decoration.kind=="wildlife"; local plant=not wildlife and (name:find("tree") or name:find("birch") or name:find("flower") or name:find("shrub") or name:find("fern") or name:find("reeds") or name:find("herb") or name:find("mushroom") or name:find("bush") or name:find("cactus"))
            local phase=decoration.x*.019+decoration.y*.013
            local feeding=scenery.stopWildlifeFeeding and scenery.stopWildlifeFeeding[name]
            if wildlife and feeding then local cycle=(animationClock+phase)%6.4; if cycle>=2.2 and cycle<5.4 then image=feeding end end
            local sway=plant and math.sin(animationClock*.72+phase)*math.rad(name:find("tree") and .85 or .55) or 0
            local bob=plant and math.sin(animationClock*.9+phase)*.55 or 0
            love.graphics.setColor(1,1,1); love.graphics.draw(image,decoration.x,decoration.y+bob,sway,decoration.scale,decoration.scale,image:getWidth()/2,image:getHeight())
        end
    end
    local house=env[homes[layout.house or 1]]
    local treeA,treeB=env[trees[layout.tree or 1]],env[trees[((layout.tree or 1)%#trees)+1]]
    if treeA then local x=layout.treeA or 135; local s=210/treeA:getHeight(); local sway=math.sin(animationClock*.64+x*.021)*math.rad(.9); love.graphics.setColor(1,1,1); love.graphics.draw(treeA,x,480,sway,s,s,treeA:getWidth()/2,treeA:getHeight()) end
    if treeB then local x=layout.treeB or 830; local s=180/treeB:getHeight(); local sway=math.sin(animationClock*.67+x*.019+1.7)*math.rad(.8); love.graphics.draw(treeB,x,495,sway,s,s,treeB:getWidth()/2,treeB:getHeight()) end
    if house then local s=280/house:getHeight(); love.graphics.draw(house,layout.houseX or 520,515,0,s,s,house:getWidth()/2,house:getHeight()) end
    if scenery.redTrain then local s=74/math.max(scenery.redTrain:getWidth(),scenery.redTrain:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.redTrain,145,405,0,s,s,scenery.redTrain:getWidth()/2,scenery.redTrain:getHeight()/2) end
    love.graphics.setColor(1,.78,.12,.72); love.graphics.circle("line",145,425+math.sin(animationClock*3)*2,11); love.graphics.setColor(colors.cream); love.graphics.printf("Q",133,421,24,"center",0,.7,.7)
    drawDroppedItems()
    StopSludges.draw(stopSludges,{data=saveData,location=saveData.location,clock=animationClock,images={
        idle=mobIdleImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
        walk=mobWalkImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
        hit=mobHitImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
        death=mobDeathImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"]
    }})
    ui.drawChickens(layout); ui.drawMice(layout)
    drawNPC(); drawPlayer()
end

local function drawHouse()
    drawLandscape()
    local layout=ensureStopLayout()
    local interior=ui.assetStreamer and ui.assetStreamer:getInterior(layout.interior or 1)
    if interior then
        love.graphics.setColor(1,1,1)
        love.graphics.draw(interior,105,205,0,750/interior:getWidth(),445/interior:getHeight())
    else
        love.graphics.setColor(0.23,0.14,0.09); love.graphics.rectangle("fill",105,205,750,445,12,12)
        love.graphics.setColor(0.63,0.48,0.29); love.graphics.rectangle("fill",125,225,710,405)
        if scenery.homeTexture then love.graphics.setColor(1,1,1); love.graphics.draw(scenery.homeTexture,125,225,0,710/scenery.homeTexture:getWidth(),405/scenery.homeTexture:getHeight()) end
    end
    drawDroppedItems(); drawNPC(); drawPlayer()
end

function ui.drawMap()
    love.graphics.setColor(0.05,0.035,0.02,0.78); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(0.76,0.59,0.34); love.graphics.rectangle("fill",70,75,820,570,18,18)
    love.graphics.setColor(0.66,0.47,0.27)
    for y=95,625,20 do for x=90+(y%37),870,43 do love.graphics.rectangle("fill",x,y,3,2) end end
    love.graphics.setColor(0.49,0.31,0.18); love.graphics.setLineWidth(8); love.graphics.rectangle("line",70,75,820,570,18,18)
    love.graphics.setColor(0.35,0.23,0.13); love.graphics.printf("THE MOUSE FRONTIER TRAIL",70,96,820,"center",0,1.5,1.5)
    local visited=math.max(1,saveData.location); local points={}; local biomes={"Desert","Wetland","Canyon","Ruins","Badlands","Forest","Old City","River","Deep Woods","Pale City","Autumn Wood","Wastes"}
    local maxScroll=math.max(0,math.floor((visited-1)/6)-2); mapScroll=math.max(0,math.min(maxScroll,mapScroll))
    for i=1,visited do
        local col=(i-1)%6; local row=math.floor((i-1)/6)
        local px=145+col*132; if row%2==1 then px=805-col*132 end
        local py=215+(row-mapScroll)*155+math.sin(i*1.73)*42
        points[#points+1]={px,py}
    end
    -- Revealed terrain sketches around every visited stop.
    for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
        local kind=((i-1)%4)+1; love.graphics.setColor(0.42,0.34,0.20,0.9)
        if kind==1 then for k=-2,2 do love.graphics.polygon("fill",p[1]+k*15,p[2]-35,p[1]+k*15-8,p[2]-20,p[1]+k*15+8,p[2]-20) end
        elseif kind==2 then love.graphics.setLineWidth(4); love.graphics.arc("line","open",p[1],p[2]-22,35,0.1,3.0)
        elseif kind==3 then for k=-2,2 do love.graphics.line(p[1]+k*13,p[2]-42,p[1]+k*13,p[2]-24); love.graphics.circle("fill",p[1]+k*13,p[2]-45,6) end
        else love.graphics.rectangle("line",p[1]-28,p[2]-53,55,27); love.graphics.polygon("fill",p[1]-32,p[2]-53,p[1],p[2]-72,p[1]+32,p[2]-53) end
    end end
    local current=points[#points]
    if current and current[2]>175 and current[2]<535 and scenery.redTrain then
        local s=72/scenery.redTrain:getWidth(); love.graphics.setColor(1,1,1)
        love.graphics.draw(scenery.redTrain,current[1]+36,current[2]-64,0,-s,s)
    end
    -- Dotted, winding path instead of straight route segments.
    love.graphics.setColor(0.61,0.16,0.12)
    for i=2,#points do local a,b=points[i-1],points[i]; if (a[2]>160 and a[2]<550) or (b[2]>160 and b[2]<550) then for step=0,12 do if step%2==0 then local t=step/12; local bend=math.sin(t*math.pi)*((i%2==0) and 22 or -22); local x=a[1]+(b[1]-a[1])*t; local y=a[2]+(b[2]-a[2])*t+bend; love.graphics.circle("fill",x,y,4) end end end end
    for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
        love.graphics.setColor(i==#points and colors.red or colors.cream); love.graphics.circle("fill",p[1],p[2],i==#points and 13 or 9)
        love.graphics.setColor(colors.ink); love.graphics.printf(tostring(i),p[1]-14,p[2]-7,28,"center")
        love.graphics.setColor(0.30,0.19,0.11); love.graphics.printf(biomes[((i-1)%#biomes)+1],p[1]-52,p[2]+16,104,"center",0,0.78,0.78)
    end end
    local enc=saveData.encounters[tostring(saveData.location)]; local status=not enc and "Unexplored stop" or (enc.hasMob and not enc.resolved and "Danger nearby" or (enc.hasMob and "Mob cleared" or "Peaceful stop"))
    love.graphics.setColor(0.39,0.25,0.14,0.92); love.graphics.rectangle("fill",105,548,750,62,8,8)
    love.graphics.setColor(colors.cream); love.graphics.printf("CURRENT: Stop "..saveData.location.." - "..biomes[((saveData.location-1)%#biomes)+1].." - "..status,120,562,720,"center")
    love.graphics.printf("Only visited country is revealed.  Press M to close.",120,586,720,"center",0,0.8,0.8)
    ui.mapUp=button("^",805,115,42,36,mapScroll>0); ui.mapDown=button("v",805,155,42,36,mapScroll<maxScroll)
    love.graphics.setColor(colors.ink); love.graphics.print("PAGE "..(mapScroll+1).."/"..(maxScroll+1),720,130,0,0.75,0.75)
    love.graphics.setLineWidth(1)
end

function ui.drawDialogue()
    if not dialogue then return end
    local x,y,w,h=230,115,500,105
    drawMenuFrame(x-6,y-6,w+12,h+12,1,1)
    love.graphics.setColor(colors.cream); love.graphics.print(dialogue.speaker or "Traveler",x+20,y+17,0,1.15,1.15); love.graphics.printf(dialogue.text,x+20,y+49,w-40,"left")
    if dialogue.choice and questOffer then
        local agreeing=questOffer.kind=="trade" and "YES, AGREE TO TRADE" or "YES, I'LL HELP"
        local declining=questOffer.kind=="trade" and "NO, DECLINE TRADE" or "SORRY, NO"
        ui.questAccept=button(agreeing,x+70,y+h+18,165,40,true); ui.questDecline=button(declining,x+265,y+h+18,165,40,true)
    else ui.questAccept=nil; ui.questDecline=nil end
end

function ui.drawTravelConfirm()
    drawLandscape(); drawTracks(); drawLocomotive(); drawTrainCar(1); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",255,185,450,330,16,16)
    local cost=travelCost(); love.graphics.setColor(colors.cream); love.graphics.printf("TRAVEL TO STOP "..(saveData.location+1),275,220,410,"center",0,1.5,1.5)
    love.graphics.printf("The next stretch is farther than the last.\nThis journey will consume:",300,275,360,"center")
    love.graphics.printf(cost.food.." FOOD     "..cost.water.." WATER     "..cost.coal.." COAL",280,350,400,"center",0,1.2,1.2)
    love.graphics.printf("TERRAIN: "..string.upper(cost.terrain or "plains"),280,377,400,"center",0,.78,.78)
    if cost.passengers>0 then love.graphics.printf(cost.passengers.." passenger"..(cost.passengers==1 and "" or "s").." add "..cost.passengers.." food and water.",280,385,400,"center",0,0.82,0.82) end
    if cost.maintenanceCoal>0 then love.graphics.setColor(colors.red); love.graphics.printf("LOW MAINTENANCE ADDS +"..cost.maintenanceCoal.." COAL",280,404,400,"center",0,.68,.68) end
    local enough=saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal
    ui.travelYes=button(enough and "CONFIRM JOURNEY" or "NOT ENOUGH SUPPLIES",305,425,220,48,enough); ui.travelNo=button("CANCEL",545,425,110,48,true)
end

function ui.drawRandomEvent()
    drawLandscape(); love.graphics.setColor(0,0,0,0.76); love.graphics.rectangle("fill",0,0,W,H)
    ui.eventChoices=EventUI.draw(randomEvent,scenery.eventArt,drawMenuFrame,button,colors,saveData.eventProgress or {},function(choice) return Events.canChoose(saveData,choice) end)
end

local function ownsTrainCar(id) for _,owned in ipairs(saveData.trainCars or {}) do if owned==id then return true end end return false end
function ui.drawTrainUpgrades()
    love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",150,70,660,580,16,16)
    love.graphics.setColor(colors.brass); love.graphics.printf("TRAIN WORKSHOP",150,95,660,"center",0,1.7,1.7)
    local engine=EngineUpgrades.profile(saveData.engineLevel); local nextEngine=EngineUpgrades.next(saveData.engineLevel)
    love.graphics.setColor(colors.cream); love.graphics.printf("Scrap: "..saveData.scrap.."   •   Buy cars and improve your locomotive",170,132,620,"center")
    love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,158,590,62,7,7)
    love.graphics.setColor(colors.brass); love.graphics.print("ENGINE  "..engine.name,205,166,0,.88,.88)
    love.graphics.setColor(colors.cream); love.graphics.print("Fuel "..math.floor(engine.coal*100).."%  •  Provisions "..math.floor(engine.supplies*100).."%  •  Speed "..math.floor(engine.speed*100).."%",205,190,0,.68,.68)
    ui.engineUpgrade=button(nextEngine and (nextEngine.cost.." SCRAP") or "MAX LEVEL",630,170,125,36,nextEngine and saveData.scrap>=nextEngine.cost or false)
    ui.trainCars={}
    for i,c in ipairs(Catalog.trainCarCatalog) do local y=230+(i-1)*58; local owned=ownsTrainCar(c.id); love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,y,590,47,7,7); love.graphics.setColor(colors.cream); love.graphics.print(c.name.."  —  "..c.description,205,y+9,0,.78,.78); ui.trainCars[i]=button(owned and "OWNED" or c.cost.." SCRAP",630,y+6,125,34,not owned and saveData.scrap>=c.cost) end
    ui.upgradeClose=button("CLOSE",405,594,150,38,true)
end

function ui.drawEditControls()
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",110,158,815,122,10,10)
    love.graphics.setColor(colors.cream); love.graphics.print(editedItem and "MOVE / SCALE SELECTED ITEM" or "SELECT A YELLOW HANDLE",132,172)
    ui.editLeft=button("<",132,222,40,36,editedItem~=nil); ui.editRight=button(">",220,222,40,36,editedItem~=nil)
    ui.editUp=button("^",176,202,40,34,editedItem~=nil); ui.editDown=button("v",176,244,40,34,editedItem~=nil)
    ui.editSmaller=button("SIZE -",280,216,82,38,editedItem~=nil)
    ui.editLarger=button("SIZE +",370,216,82,38,editedItem~=nil)
    ui.editRotate=button("ROTATE",460,216,82,38,editedItem~=nil)
    ui.editBack=button("LAYER -",560,194,82,34,editedItem~=nil); ui.editForward=button("LAYER +",650,194,82,34,editedItem~=nil)
    ui.editPickup=button("PICK UP",560,236,82,34,editedItem~=nil)
    ui.editDone=button("DONE",650,236,82,34,true)
    local item=editedItem and saveData.droppedItems[editedItem]
    local function slider(label,x,y,w,value,kind)
        love.graphics.setColor(colors.cream); love.graphics.print(label,x,y-17,0,.65,.65)
        love.graphics.setColor(.11,.07,.04,.9); love.graphics.rectangle("fill",x,y,w,9,4,4)
        local parts=18
        for n=0,parts-1 do
            local t=n/(parts-1)
            if kind=="hue" then
                local h=t*6; local sector=math.floor(h); local f=h-sector; local q=1-f
                local r,g,b=1,0,0
                if sector==0 then r,g,b=1,f,0 elseif sector==1 then r,g,b=q,1,0 elseif sector==2 then r,g,b=0,1,f elseif sector==3 then r,g,b=0,q,1 elseif sector==4 then r,g,b=f,0,1 else r,g,b=1,0,q end
                love.graphics.setColor(r,g,b,.9)
            else love.graphics.setColor(t,t,t,.9) end
            love.graphics.rectangle("fill",x+t*w-2,y+1,w/(parts-1)+3,7)
        end
        love.graphics.setColor(colors.cream); love.graphics.circle("fill",x+value*w,y+4.5,6)
        love.graphics.setColor(colors.ink); love.graphics.circle("line",x+value*w,y+4.5,6)
        return {x=x-7,y=y-7,w=w+14,h=23}
    end
    local hue=item and (item.hue or 0) or 0
    local saturation=item and math.max(0,math.min(2,item.saturation or 1)) or 1
    ui.editHue=slider("HUE  "..math.floor(hue*360).."°",755,190,145,hue,"hue")
    ui.editSaturation=slider("SATURATION  "..math.floor(saturation*100).."%",755,239,145,saturation/2,"saturation")
end

function ui.updateEditColorSlider(x)
    local item=editedItem and saveData.droppedItems[editedItem]
    local control=ui.editSliderDrag=="hue" and ui.editHue or ui.editSaturation
    if not item or not control then return end
    local value=math.max(0,math.min(1,(x-(control.x+7))/(control.w-14)))
    if ui.editSliderDrag=="hue" then item.hue=value else item.saturation=value*2 end
end

function ui.battleUIContext()
    return {
        W=W,H=H,battle=battle,battleZoom=battleZoom,scenery=scenery,colors=colors,
        characterImages=characterImages,npcImages=npcImages,mobImages=mobImages,
        characterWalkImages=characterWalkImages,npcWalkImages=npcWalkImages,
        mobAttackImages=mobAttackImages,mobIdleImages=mobIdleImages,mobHitImages=mobHitImages,
        mobDeathImages=mobDeathImages,mobWalkImages=mobWalkImages,mobRangedImages=mobRangedImages,
        animationClock=animationClock,characterAnimations=characterAnimations,
        saveData=saveData,inventoryOpen=inventoryOpen,ui=ui,
        drawLandscape=drawLandscape,drawGround=drawGround,
        drawAnimatedCharacter=drawAnimatedCharacter,button=button,screenToGame=screenToGame,
        setInventoryOpen=function(value) inventoryOpen=value end,
        resetInventoryDrag=function() draggedSlot=nil; inventoryDragActive=false end,
        battleAttack=battleAttack,setBattlePrompt=setBattlePrompt,battleHeal=battleHeal,battleGuard=battleGuard,
        useBattleAbility=useBattleAbility,useBattlePotion=useBattlePotion,advanceBattleTurn=advanceBattleTurn,
        resolveBattleAttack=resolveBattleAttack,battleMoveTo=battleMoveTo
    }
end

function ui.drawTacticalBattle() Systems.battleUI.draw(ui.battleUIContext()) end

local function drawTrainView(focusIndex,offsetX,playerCar,playerX,playerY)
    local carCount=#(saveData.trainCars or {})
    love.graphics.push(); love.graphics.translate(offsetX or 0,0)
    if focusIndex==1 then
        drawLocomotive(); drawTrainCar(1); drawDroppedItems(1); drawPassengers(1)
        if playerCar==1 then
            love.graphics.push(); love.graphics.translate((playerX or player.x)-player.x,(playerY or player.y)-player.y); drawPlayer(); love.graphics.pop()
        end
    else
        -- Additional cars use the same full-size transform as the default
        -- living car. The viewport clips the neighboring car naturally while
        -- the slide transition pans between complete, consistently scaled cars.
        local scale=1
        local first=focusIndex<carCount and focusIndex or math.max(1,focusIndex-1)
        local last=math.min(carCount,first+1)
        for index=first,last do
            local slot=index-first
            local targetX=16+slot*(car.w+16)
            love.graphics.push()
            love.graphics.translate(targetX-car.x,0)
            drawTrainCar(index); drawDroppedItems(index); drawPassengers(index)
            if playerCar==index then
                love.graphics.push(); love.graphics.translate((playerX or player.x)-player.x,(playerY or player.y)-player.y); drawPlayer(); love.graphics.pop()
            end
            love.graphics.pop()
        end
    end
    love.graphics.pop()
end

local function beginCarTransition(targetIndex)
    if carTransition or scene~="train" then return false end
    local current=saveData.activeCar or 1
    targetIndex=math.max(1,math.min(#(saveData.trainCars or {}),targetIndex))
    if targetIndex==current then return false end
    local left,right,top,bottom=trainFloorBounds()
    carTransition={from=current,to=targetIndex,t=0,duration=.78,targetX=targetIndex>current and left or right,targetY=(top+bottom)/2}
    player.moving=false; nearbyItem=nil; nearChest=nil; nearCarNext=false; nearCarPrev=false
    ui.playSfx("trainDoor")
    return true
end

local function moveEditedItem(dx,dy)
    local item=editedItem and saveData.droppedItems[editedItem]; if not item then return end
    local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,item.x+dx)); item.y=math.max(top,math.min(bottom,item.y+dy)); writeSave()
end

local function drawGame()
    ui.returnDoor=nil
    if scene=="train" then
        drawLandscape(); drawTracks(); local tx=0
        if travelTransition then
            local t=travelTransition.t; local timing=EngineUpgrades.timings(saveData.engineLevel)
            if t<timing.depart then local p=t/timing.depart; tx=-W*(p*p*p)
            elseif t<timing.arrive then tx=-W
            else local p=math.min(1,(t-timing.arrive)/timing.arrivalDuration); local eased=1-(1-p)^3; tx=W*(1-eased) end
        end
        love.graphics.push(); love.graphics.translate(tx,0)
        if carTransition then
            local p=math.min(1,carTransition.t/carTransition.duration); local eased=p*p*(3-2*p); local direction=carTransition.to>carTransition.from and -1 or 1
            drawTrainView(carTransition.from,direction*W*eased,carTransition.from,player.x,player.y)
            drawTrainView(carTransition.to,direction*W*(eased-1),nil)
        else drawTrainView(saveData.activeCar or 1,0,saveData.activeCar or 1,player.x,player.y) end
        love.graphics.pop()
    elseif scene=="house" then drawHouse() else drawStop() end
    if scene=="train" or scene=="stop" then Clouds.draw(cloudLayer,scene,W,H,sceneryOffset,saveData.location) end
    ui.drawResource("FOOD",saveData.resources.food,20,colors.green,110); ui.drawResource("WATER",saveData.resources.water,140,colors.blue,110)
    ui.drawResource("COAL",saveData.resources.coal,260,colors.red,110); ui.drawResource("OIL",saveData.resources.oil,380,colors.brass,110)
    ui.drawJourneyHUD()
    ui.travel=scene=="train" and button(saveData.location>=50 and "JOURNEY COMPLETE" or "TRAVEL TO NEXT STOP",510,20,220,36,saveData.location<50 and saveData.resources.food>0 and saveData.resources.water>0 and saveData.resources.coal>0) or nil
    -- Keep the departure control with the other scene controls, directly
    -- beneath Options, so it remains discoverable without covering the train.
    ui.leaveTrain=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and button("LEAVE TRAIN",790,194,135,32,true) or nil
    ui.backpack=button(inventoryOpen and "CLOSE" or "PACK",830,20,95,36,true)
    ui.map=button(mapOpen and "CLOSE MAP" or "MAP",735,20,87,36,true)
    ui.editMode=scene=="train" and button(editMode and "EDITING" or "MOVE / SCALE",745,70,180,36,true) or nil
    ui.trainUpgrade=scene=="train" and button("UPGRADE  "..saveData.scrap.." SCRAP",510,70,220,36,true) or nil
    ui.maintenance=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and not travelTransition and button("MAINTENANCE  "..math.floor(Maintenance.condition(saveData)).."%",510,112,220,32,true) or nil
    ui.pose=button(poseMenu and "CLOSE" or "POSES",745,112,85,32,true)
    ui.options=button(ui.optionsOpen and "CLOSE" or "OPTIONS",840,112,85,32,true)
    ui.stopAttack=scene=="stop" and button("ATTACK",790,650,135,38,true) or nil
    local pendingMail=0; for _,mail in ipairs(saveData.mailQuests or {}) do if not mail.complete then pendingMail=pendingMail+1 end end
    if pendingMail>0 and ui.propImages["family-letter"] then local mail=ui.propImages["family-letter"]; local ms=28/math.max(mail:getWidth(),mail:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(mail,470,127,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2); love.graphics.setColor(colors.cream); love.graphics.print("x"..pendingMail,487,117,0,.9,.9) end
    if #(saveData.passengers or {})>0 then love.graphics.setColor(colors.cream); love.graphics.print("Passengers: "..#saveData.passengers,560,151,0,.82,.82) end
    ui.exitTrain = nil
    local tipColor={colors.panel[1],colors.panel[2],colors.panel[3],.50}
    local nearbyFurniture=nearbyItem and isFurnitureItem(saveData.droppedItems[nearbyItem] and saveData.droppedItems[nearbyItem].name)
    local contextText,contextScale
    if not inventoryOpen and not editMode and not carTransition then
        if ui.nearRadio then contextText,contextScale="P  OPEN RADIO",.72
        elseif nearPassenger then contextText,contextScale="Q  TALK   •   G  GIVE",.72
        elseif nearCarNext then contextText,contextScale="Q  ENTER NEXT CAR",.72
        elseif nearCarPrev then contextText,contextScale="Q  RETURN TO PREVIOUS CAR",.66
        elseif nearNPC then contextText,contextScale="Q  TALK   •   G  GIVE",.72
        elseif nearMailbox then contextText,contextScale="RIGHT CLICK OPEN REWARD MAILBOX",.66
        elseif nearChest then contextText,contextScale="RIGHT CLICK OPEN   •   HOLD E PICK UP",.66
        elseif nearbyFurniture then contextText,contextScale="HOLD E  PICK UP FURNITURE",.72
        elseif nearHouse then contextText,contextScale="Q  ENTER HOME",.78
        elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="Q  LEAVE HOME",.78
        elseif nearReturnTrain then contextText,contextScale="Q  BOARD TRAIN",.78
        elseif nearFire then contextText,contextScale="E  ADD COAL",.78 end
    end
    if contextText then
        love.graphics.setColor(tipColor); love.graphics.rectangle("fill",325,300,310,40,6,6); love.graphics.setColor(colors.cream)
        love.graphics.printf(contextText,325,312,310,"center",0,contextScale,contextScale)
        if holdPickupIndex then love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",365,335,230*math.min(1,holdPickupTime/HOLD_PICKUP_SECONDS),5,2,2) end
    end
    if scene=="train" and #(saveData.trainCars or {})>1 then love.graphics.setColor(colors.cream); love.graphics.printf("CAR "..(saveData.activeCar or 1).." / "..#saveData.trainCars.."  •  "..Util.titleFromFile(saveData.trainCars[saveData.activeCar or 1]),510,188,410,"center",0,.72,.72) end
    ui.pickup = nearbyItem and not nearbyFurniture and not editMode and button("PICK UP  [E]",390,650,180,38,true) or nil
    if inventoryOpen then if chestOpen then ui.drawChestInventory() end; ui.drawInventory() end
    if inventoryOpen and inventoryDragActive and draggedSlot and containerValue(draggedSlot) then local mx,my=screenToGame(love.mouse.getPosition()); ui.drawItem(containerValue(draggedSlot),{x=mx-32,y=my-32,w=64,h=64}) end
    if mapOpen then ui.drawMap() end
    if editMode then ui.drawEditControls() end
    ui.poseIdle=nil; ui.poseSit=nil; ui.poseLay=nil; ui.poseAction=nil
    ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil; ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
    if poseMenu then love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",735,198,190,150,8,8); ui.poseIdle=button("STAND",750,212,75,34,true); ui.poseSit=button("SIT",835,212,75,34,true); ui.poseLay=button("LAY",750,256,75,34,true); ui.poseAction=button("USE",835,256,75,34,true); love.graphics.setColor(colors.cream); love.graphics.printf("Movement returns to standing",750,306,160,"center",0,.68,.68) end
    if ui.optionsOpen then
        drawMenuFrame(565,175,370,380,2,.98); love.graphics.setColor(colors.cream); love.graphics.print("AUDIO OPTIONS",595,196,0,1.05,1.05)
        love.graphics.print("MUSIC  "..math.floor((saveData.audio.musicVolume or .10)*100).."%",635,252)
        ui.musicDown=button("-",770,242,45,34,true); ui.musicUp=button("+",830,242,45,34,true)
        love.graphics.print("SOUND FX  "..math.floor((saveData.audio.sfxVolume or .55)*100).."%",635,301)
        ui.sfxDown=button("-",770,291,45,34,true); ui.sfxUp=button("+",830,291,45,34,true)
        love.graphics.print("RAIN  "..math.floor((saveData.audio.rainVolume or .20)*100).."%",635,350)
        ui.rainDown=button("-",770,340,45,34,true); ui.rainUp=button("+",830,340,45,34,true)
        local stationLabel=saveData.audio.station=="chill" and "CHILL RADIO" or (saveData.audio.station=="vibes" and "VIBES RADIO" or "8-BIT SCORE")
        love.graphics.print("STATION: "..stationLabel,635,399,0,.85,.85)
        local status=ui.audio and (ui.audio.lastError and ("ERROR: "..ui.audio.lastError) or (ui.audio.nowPlaying and ("PLAYING: "..Util.titleFromFile(ui.audio.nowPlaying:match("[^/]+$") or ui.audio.nowPlaying)) or "STARTING MUSIC...")) or "AUDIO UNAVAILABLE"
        love.graphics.setColor(ui.audio and ui.audio.lastError and colors.red or colors.cream); love.graphics.printf(status,610,431,285,"left",0,.60,.60)
        ui.musicPrevious=button("|<",600,479,68,38,true); ui.musicPause=button(saveData.audio.musicPaused and "PLAY" or "PAUSE",676,479,72,38,true)
        ui.musicNext=button(">|",756,479,68,38,true); ui.musicMute=button(saveData.audio.musicMuted and "UNMUTE" or "MUTE",832,479,82,38,true)
    end
    if ui.radioOpen then
        love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,W,H)
        if ui.radioFace then love.graphics.setColor(1,1,1); love.graphics.draw(ui.radioFace,130,95,0,700/ui.radioFace:getWidth(),450/ui.radioFace:getHeight()) else drawMenuFrame(130,95,700,450,2,1) end
        -- Keep station selectors and ambience controls on distinct rows. This
        -- prevents the rain hitbox from being interpreted as the chill button
        -- when the radio is scaled or shown fullscreen.
        ui.radio8bit={x=248,y=468,w=82,h=54}; ui.radioChill={x=343,y=468,w=82,h=54}; ui.radioVibes={x=438,y=468,w=82,h=54}
        ui.radioRain={x=533,y=468,w=82,h=54}; ui.radioClose={x=628,y=468,w=82,h=54}
        for i,r in ipairs({ui.radio8bit,ui.radioChill,ui.radioVibes,ui.radioRain,ui.radioClose}) do
            if ui.radioButtonsImage and ui.radioButtonQuads then love.graphics.setColor(1,1,1); local iw,ih=ui.radioButtonsImage:getDimensions(); local q=((i-1)%3)+1; love.graphics.draw(ui.radioButtonsImage,ui.radioButtonQuads[q],r.x,r.y,0,r.w/(iw/3),r.h/ih) else button("",r.x,r.y,r.w,r.h,true) end
        end
        local stationName=saveData.audio.station=="chill" and "CHILL RADIO" or (saveData.audio.station=="vibes" and "VIBES RADIO" or "8-BIT SCORE")
        love.graphics.setColor(colors.cream); love.graphics.printf(stationName,300,405,360,"center",0,1.1,1.1)
        love.graphics.printf(saveData.audio.rainEnabled and "RAIN: ON" or "RAIN: OFF",300,432,360,"center",0,.78,.78)
        local mx,my=screenToGame(love.mouse.getPosition()); local tip
        if Util.pointIn(mx,my,ui.radio8bit) then tip="Scene-based 8-bit score"
        elseif Util.pointIn(mx,my,ui.radioChill) then tip="Chill Radio"
        elseif Util.pointIn(mx,my,ui.radioVibes) then tip="Vibes Radio"
        elseif Util.pointIn(mx,my,ui.radioRain) then tip=saveData.audio.rainEnabled and "Turn rain ambience off" or "Turn rain ambience on"
        elseif Util.pointIn(mx,my,ui.radioClose) then tip="Close radio" end
        if tip then love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.86); love.graphics.rectangle("fill",mx-85,my-42,170,30,5,5); love.graphics.setColor(colors.cream); love.graphics.printf(tip,mx-80,my-34,160,"center",0,.72,.72) end
    end
    ui.drawDialogue()
    if trainUpgradeOpen then ui.drawTrainUpgrades() end
    if tradeOpen then drawTrade() end
    if maintenanceSession.open then
        maintenanceSession.mouseX,maintenanceSession.mouseY=screenToGame(love.mouse.getPosition())
        Maintenance.draw(maintenanceSession,saveData)
    end
end

local function drawEnding()
    drawLandscape(); love.graphics.setColor(0.08,0.05,0.03,0.72); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",120,90,720,540,20,20)
    love.graphics.setColor(colors.brass); love.graphics.printf("CALIFORNIA",120,135,720,"center",0,2.2,2.2)
    love.graphics.setColor(colors.cream); love.graphics.printf("After 50 stops, the Mouse Frontier finally reaches the end of the line.",205,215,550,"center",0,1.15,1.15)
    love.graphics.printf("You found your family. The old train became a lifeline for every critter you met along the way—and your journey west became a story they will tell for generations.",220,285,520,"center")
    local family={saveData.character,(saveData.npcRoster or {})[1],(saveData.npcRoster or {})[2]}
    for i,file in ipairs(family) do local img=characterImages[file] or npcImages[file]; if img then local s=math.min(105/img:getWidth(),145/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,360+(i-1)*120,475+math.sin(animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2) end end
    ui.endingButton=button("RETURN TO SAVE FILES",350,560,260,48,true)
end

function love.draw()
    love.graphics.clear(0.025,0.02,0.025,1)
    if state=="intro" then
        local windowWidth,windowHeight=love.graphics.getDimensions()
        Systems.intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
        return
    end
    local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
    love.graphics.push()
    love.graphics.translate(offsetX,offsetY)
    love.graphics.scale(scaleX,scaleY)
    if state=="game" and not travelConfirm and not maintenanceSession.open and Camera:isActive() then
        local focusX,focusY=(player and player.x or W/2),(player and player.y or H/2)
        Camera:apply(focusX,focusY)
    end
    if state=="slots" then ui.drawSlots() elseif state=="characters" then ui.drawCharacterSelect() elseif state=="battle" then ui.drawTacticalBattle() elseif state=="event" then ui.drawRandomEvent() elseif state=="ending" then drawEnding() elseif travelConfirm then ui.drawTravelConfirm() else drawGame() end
    if exitPrompt then drawExitPrompt() end
    love.graphics.pop()
    if travelTransition then
        local t=travelTransition.t; local timing=EngineUpgrades.timings(saveData.engineLevel)
        local alpha=t<timing.change and math.max(0,math.min(1,(t-timing.fadeOut)/timing.fadeDuration)) or math.max(0,1-(t-timing.change)/timing.finishFade)
        local windowWidth,windowHeight=love.graphics.getDimensions()
        love.graphics.setColor(0,0,0,alpha)
        love.graphics.rectangle("fill",0,0,windowWidth,windowHeight)
    end
end

function ui.offerGift(slot)
    local name=saveData.inventory[slot]; local accepted=isWeapon(name) or Catalog.itemEffects[name] or Catalog.backpackUpgrades[name] or name=="coal-chunk" or name=="coal-bucket"
    if accepted then
        local passenger; for _,p in ipairs(saveData.passengers or {}) do if p.npc==giftNPC then passenger=p; break end end
        if isWeapon(name) then
            if passenger then passenger.weapon=name
            else local layout=saveData.stopLayouts[tostring(saveData.location)]; if layout then layout.npcWeapon=name end; if npcActor then npcActor.weapon=name end end
        end
        saveData.inventory[slot]=nil; dialogue={speaker="Gift Accepted",text=Util.titleFromFile(giftNPC).." accepted the gift of "..Util.titleFromFile(name)..".",timer=2}
    else dialogue={speaker=Util.titleFromFile(giftNPC),text="I don't need that right now.",timer=2} end
    giftOpen=false; inventoryOpen=false; giftSlot=nil; writeSave()
end

function ui.handleInventoryClick(x,y)
    local ctx=ui.inventoryContext(); ctx.offerGift=ui.offerGift
    return Systems.inventory.handleClick(ctx,x,y)
end

function ui.handlePoseClick(x,y)
    if Util.pointIn(x,y,ui.pose) then poseMenu=not poseMenu; ui.optionsOpen=false; ui.playSfx("menu"); return true end
    if not poseMenu then return false end
    if Util.pointIn(x,y,ui.poseIdle) then playerPose="idle"
    elseif Util.pointIn(x,y,ui.poseSit) then playerPose="sit"
    elseif Util.pointIn(x,y,ui.poseLay) then playerPose="lay"
    elseif Util.pointIn(x,y,ui.poseAction) then playerPose="idle"; actionKind="use"; actionTimer=.45
    else return true end
    poseMenu=false; return true
end

function ui.handleTradeClick(x,y)
    local layout=ensureStopLayout()
    if Util.pointIn(x,y,ui.tradeClose) then tradeOpen=false; tradeNPC=nil; writeSave(); return true end
    for i,r in pairs(ui.tradeBuy or {}) do
        if Util.pointIn(x,y,r) then
            local name=layout.tradeStock and layout.tradeStock[i]; local price=name and Inventory.scrapPrice(name,Catalog) or 999; local slot=Inventory.firstEmptySlot(saveData)
            if slot and saveData.scrap>=price then saveData.scrap=saveData.scrap-price; saveData.inventory[slot]=name; layout.tradeStock[i]=nil; writeSave() end
            return true
        end
    end
    for i,r in pairs(ui.tradeSell or {}) do
        if Util.pointIn(x,y,r) and saveData.inventory[i] then
            local name=saveData.inventory[i]; local price=math.max(1,math.floor(Inventory.scrapPrice(name,Catalog)/2))
            if (layout.tradeBudget or 0)>=price then layout.tradeBudget=layout.tradeBudget-price; saveData.scrap=saveData.scrap+price; saveData.inventory[i]=nil; writeSave() end
            return true
        end
    end
    for i,r in pairs(ui.tradeGive or {}) do
        if Util.pointIn(x,y,r) and isWeapon(saveData.inventory[i]) then layout.npcWeapon=saveData.inventory[i]; if npcActor then npcActor.weapon=layout.npcWeapon end; saveData.inventory[i]=nil; writeSave(); return true end
    end
    return true
end

function ui.handleBattleMousePressed(x,y,rightClick)
    local result=Systems.battleUI.handleMouse(ui.battleUIContext(),x,y,rightClick)
    if result=="missing" then state=session:setScreen("game")
    elseif result=="continue_win" then battle=nil; state=session:setScreen("game"); enterStop()
    elseif result=="continue_loss" or result=="retreat" then
        battle=nil; state=session:setScreen("game"); scene=session:setScene("train"); npcActor=nil; writeSave()
    end
end

function ui.handleRadioMousePressed(x,y)
    if not ui.radioOpen then return false end
    if Util.pointIn(x,y,ui.radio8bit) then saveData.audio.station="8bit"; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
    elseif Util.pointIn(x,y,ui.radioChill) then local changed=saveData.audio.station~="chill"; saveData.audio.station="chill"; if changed then saveData.audio.rainEnabled=true end; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
    elseif Util.pointIn(x,y,ui.radioVibes) then saveData.audio.station="vibes"; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
    elseif Util.pointIn(x,y,ui.radioRain) then saveData.audio.rainEnabled=not saveData.audio.rainEnabled; ui.playSfx("menu"); writeSave()
    elseif Util.pointIn(x,y,ui.radioClose) then ui.radioOpen=false; ui.playSfx("menu") end
    return true
end

function ui.handleOptionsMousePressed(x,y)
    if not ui.optionsOpen then return false end
    if Util.pointIn(x,y,ui.options) then ui.optionsOpen=false; ui.playSfx("menu"); return true end
    if Util.pointIn(x,y,ui.pose) then ui.optionsOpen=false; poseMenu=true; ui.playSfx("menu"); return true end
    if Util.pointIn(x,y,ui.musicDown) then saveData.audio.musicVolume=math.max(0,(saveData.audio.musicVolume or .10)-.05)
    elseif Util.pointIn(x,y,ui.musicUp) then saveData.audio.musicVolume=math.min(1,(saveData.audio.musicVolume or .10)+.05)
    elseif Util.pointIn(x,y,ui.sfxDown) then saveData.audio.sfxVolume=math.max(0,(saveData.audio.sfxVolume or .55)-.05)
    elseif Util.pointIn(x,y,ui.sfxUp) then saveData.audio.sfxVolume=math.min(1,(saveData.audio.sfxVolume or .55)+.05); ui.playSfx("menu")
    elseif Util.pointIn(x,y,ui.rainDown) then saveData.audio.rainVolume=math.max(0,(saveData.audio.rainVolume or .20)-.05)
    elseif Util.pointIn(x,y,ui.rainUp) then saveData.audio.rainVolume=math.min(1,(saveData.audio.rainVolume or .20)+.05); ui.playSfx("menu")
    elseif Util.pointIn(x,y,ui.musicPrevious) then ui.audio:previousTrack(saveData.audio,ui.musicCategory()); ui.playSfx("menu")
    elseif Util.pointIn(x,y,ui.musicPause) then ui.audio:togglePause(saveData.audio); ui.playSfx("menu")
    elseif Util.pointIn(x,y,ui.musicNext) then ui.audio:nextTrack(saveData.audio,ui.musicCategory()); ui.playSfx("menu")
    elseif Util.pointIn(x,y,ui.musicMute) then ui.audio:toggleMute(saveData.audio); ui.playSfx("menu")
    else return true end
    writeSave(); return true
end

function ui.handleUpgradeMousePressed(x,y)
    if not trainUpgradeOpen then return false end
    if Util.pointIn(x,y,ui.upgradeClose) then trainUpgradeOpen=false; return true end
    if Util.pointIn(x,y,ui.engineUpgrade) then
        local nextEngine=EngineUpgrades.next(saveData.engineLevel)
        if nextEngine and saveData.scrap>=nextEngine.cost then saveData.scrap=saveData.scrap-nextEngine.cost; saveData.engineLevel=saveData.engineLevel+1; dialogue={speaker="Train Workshop",text=nextEngine.name.." installed! Future journeys use fewer supplies and finish faster.",timer=4}; writeSave() end
        return true
    end
    for i,r in ipairs(ui.trainCars or {}) do if Util.pointIn(x,y,r) then local c=Catalog.trainCarCatalog[i]; if not ownsTrainCar(c.id) and saveData.scrap>=c.cost then saveData.scrap=saveData.scrap-c.cost; saveData.trainCars[#saveData.trainCars+1]=c.id; trainUpgradeOpen=false; dialogue={speaker="Train Workshop",text=c.name.." added to your train! "..c.description,timer=3}; writeSave() end; return true end end
    return true
end

function ui.handleEditorMousePressed(x,y)
    if not editMode then return false end
    local item=editedItem and saveData.droppedItems[editedItem]
    if Util.pointIn(x,y,ui.editDone) then editMode=false; editedItem=nil; ui.editSliderDrag=nil; writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editHue) then ui.editSliderDrag="hue"; editDragging=false; ui.updateEditColorSlider(x); return true end
    if item and Util.pointIn(x,y,ui.editSaturation) then ui.editSliderDrag="saturation"; editDragging=false; ui.updateEditColorSlider(x); return true end
    if item and Util.pointIn(x,y,ui.editLeft) then moveEditedItem(-5,0); return true end
    if item and Util.pointIn(x,y,ui.editRight) then moveEditedItem(5,0); return true end
    if item and Util.pointIn(x,y,ui.editUp) then moveEditedItem(0,-5); return true end
    if item and Util.pointIn(x,y,ui.editDown) then moveEditedItem(0,5); return true end
    if item and Util.pointIn(x,y,ui.editSmaller) then item.scale=math.max(0.5,(item.scale or 1)-0.1); writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editLarger) then item.scale=math.min(2.5,(item.scale or 1)+0.1); writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editRotate) then item.rotation=((item.rotation or 0)+math.pi/4)%(math.pi*2); writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editBack) then item.layer=(item.layer or editedItem)-1; writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editForward) then item.layer=(item.layer or editedItem)+1; writeSave(); return true end
    if item and Util.pointIn(x,y,ui.editPickup) then
        if item.permanent then dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; editMode=false; editedItem=nil
        elseif Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; editMode=false; editedItem=nil
        else local slot=Inventory.firstEmptySlot(saveData); if slot then saveData.inventory[slot]=item.name; table.remove(saveData.droppedItems,editedItem); editedItem=nil; writeSave() end end
        return true
    end
    editedItem=trainItemAt(x,y); editDragging=editedItem~=nil; return true
end

function ui.handleGameMousePressed(x,y)
    if maintenanceSession.open then
        local result=Maintenance.mousepressed(maintenanceSession,x,y,saveData)
        if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
        return true
    end
    if ui.handleRadioMousePressed(x,y) then return true end
    if inventoryOpen then
        if Util.pointIn(x,y,ui.backpack) then inventoryOpen=false; chestOpen=false; activeChest=nil; draggedSlot=nil; inventoryDragActive=false; writeSave() else ui.handleInventoryClick(x,y) end
        return true
    end
    if tradeOpen then ui.handleTradeClick(x,y); return true end
    if trainUpgradeOpen then ui.handleUpgradeMousePressed(x,y); return true end
    if ui.optionsOpen then ui.handleOptionsMousePressed(x,y); return true end
    if poseMenu then if Util.pointIn(x,y,ui.options) then poseMenu=false; ui.optionsOpen=true; ui.playSfx("menu") else ui.handlePoseClick(x,y) end; return true end
    if Util.pointIn(x,y,ui.options) then ui.optionsOpen=true; poseMenu=false; ui.playSfx("menu"); return true end
    if ui.handlePoseClick(x,y) then return true end
    if mapOpen then if Util.pointIn(x,y,ui.mapUp) then mapScroll=math.max(0,mapScroll-1) elseif Util.pointIn(x,y,ui.mapDown) then mapScroll=mapScroll+1 end; return true end
    if scene=="stop" and ui.stopAttack and Util.pointIn(x,y,ui.stopAttack) then
        local mx,my=love.mouse.getPosition(); mx,my=screenToGame(mx,my)
        if not mx or not my or (math.abs(mx-player.x)<35 and math.abs(my-player.y)<35) then mx,my=player.x+(player.facing or 1)*100,player.y end
        attackStopSludge(mx,my); return true
    end
    if dialogue and dialogue.choice and questOffer then
        if Util.pointIn(x,y,ui.questAccept) then acceptQuest(questOffer.kind)
        elseif Util.pointIn(x,y,ui.questDecline) then dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="I understand. Safe travels.",timer=5}; questOffer=nil end
        return true
    end
    if Util.pointIn(x,y,ui.editMode) then editMode=not editMode; editedItem=nil; editDragging=false; ui.editSliderDrag=nil; inventoryOpen=false; mapOpen=false; writeSave(); return true end
    if Util.pointIn(x,y,ui.trainUpgrade) then trainUpgradeOpen=true; inventoryOpen=false; mapOpen=false; editMode=false; poseMenu=false; ui.optionsOpen=false; return true end
    if Util.pointIn(x,y,ui.maintenance) then
        inventoryOpen=false; mapOpen=false; editMode=false; poseMenu=false; ui.optionsOpen=false; dialogue=nil
        Camera:endPan()
        Maintenance.open(maintenanceSession,saveData); ui.playSfx("menu"); return true
    end
    if ui.handleEditorMousePressed(x,y) then return true end
    if Util.pointIn(x,y,ui.backpack) then inventoryOpen=not inventoryOpen; if not inventoryOpen then chestOpen=false; activeChest=nil end; draggedSlot=nil; inventoryDragActive=false; return true end
    if Util.pointIn(x,y,ui.map) then mapOpen=not mapOpen; if mapOpen then mapScroll=math.max(0,math.floor((saveData.location-1)/6)-2) end; inventoryOpen=false; draggedSlot=nil; return true end
    if dialogue then dialogue=nil; return true end
    if Util.pointIn(x,y,ui.leaveTrain) then attemptLeaveTrain(); return true end
    if Util.pointIn(x,y,ui.travel) and saveData.location<50 and saveData.resources.food>0 and saveData.resources.water>0 and saveData.resources.coal>0 then travelConfirm=true; return true end
    if Util.pointIn(x,y,ui.returnDoor) then local left,right,top,bottom=trainFloorBounds(); scene=session:setScene("train"); npcActor=nil; player.x,player.y=right,(top+bottom)/2; writeSave(); return true end
    if Util.pointIn(x,y,ui.pickup) then pickUpNearby(); return true end
    return false
end

function love.mousepressed(x,y,button)
    if state=="intro" then Systems.intro.skip(ui.introCinematic); return end
    if exitPrompt then
        if button==1 then
            x,y=screenToGame(x,y)
            if ui.exitYes and Util.pointIn(x,y,ui.exitYes) then resolveExitPrompt("yes")
            elseif ui.exitNo and Util.pointIn(x,y,ui.exitNo) then resolveExitPrompt("no") end
        end
        return
    end
    if button==3 and state=="game" and not travelConfirm and not maintenanceSession.open and not ui.radioOpen and not inventoryOpen and not mapOpen and not dialogue and not tradeOpen and not trainUpgradeOpen and not poseMenu and not ui.optionsOpen and not editMode then Camera:beginPan(x,y); return end
    x,y=screenToGame(x,y)
    if state=="game" and carTransition then return end
    if button==2 and state=="game" and not maintenanceSession.open and not editMode and not mapOpen and not tradeOpen and not inventoryOpen and not dialogue and not travelConfirm and not trainUpgradeOpen and not poseMenu and not ui.optionsOpen and not ui.radioOpen then
        local action,index=Systems.interactions.mouseAction(ui.interaction,button)
        if action=="openStorage" then activeChest=saveData.droppedItems[index]; activeChest.storage=activeChest.storage or {}; if activeChest.mailbox then activeChest.mailUnread=false; writeSave() end; chestOpen=true; inventoryOpen=true; draggedSlot=nil; inventoryDragActive=false end
        return
    end
    if button==2 and state=="battle" then ui.handleBattleMousePressed(x,y,true); return end
    if button~=1 then return end
    if state=="event" then local choice=EventUI.hit(x,y,ui.eventChoices,Util.pointIn); if choice then resolveEventChoice(choice) end; return end
    if state=="ending" then if Util.pointIn(x,y,ui.endingButton) then writeSave(); state=session:setScreen("slots") end; return end
    if travelConfirm then
        if Util.pointIn(x,y,ui.travelNo) then travelConfirm=false; return end
        if Util.pointIn(x,y,ui.travelYes) then local cost=travelCost(); if saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal then saveData.resources.food=saveData.resources.food-cost.food; saveData.resources.water=saveData.resources.water-cost.water; saveData.resources.coal=saveData.resources.coal-cost.coal; travelConfirm=false; travelTransition={t=0,changed=false,departSoundPlayed=true}; playTrainDepart(); writeSave() end end
        return
    end
    if state=="slots" then
        for i=1,3 do if Util.pointIn(x,y,ui.slots[i]) then local data=Save.read(i); if data then selectedSlot=session:selectSlot(i); enterGame(data) end; return elseif Util.pointIn(x,y,ui.slotNew[i]) then selectedSlot=session:selectSlot(i); state=session:setScreen("characters"); return elseif Util.pointIn(x,y,ui.slotDelete[i]) then Save.remove(i); return end end
    elseif state=="characters" then
        if Util.pointIn(x,y,ui.characterUp) then characterScroll=math.max(0,characterScroll-1); return end
        if Util.pointIn(x,y,ui.characterDown) then characterScroll=characterScroll+1; return end
        for i,r in ipairs(ui.characters or {}) do if Util.pointIn(x,y,r) then saveData=session:setSaveData(newSave(characters[i])); enterGame(saveData); writeSave(); return end end
    elseif state=="battle" then ui.handleBattleMousePressed(x,y,false)
    elseif state=="game" then
        -- UI and modal layers always get first refusal. Only an unconsumed
        -- click in the stop world is allowed to become a sludge attack.
        if ui.handleGameMousePressed(x,y) then return end
        if scene=="stop" and attackStopSludge(x,y) then return end
    end
end

function love.mousemoved(x,y)
    if Camera.panning then
        local _,_,scaleX=Viewport.transform(W,H)
        Camera:movePan(x,y,scaleX); return
    end
    x,y=screenToGame(x,y)
    if state=="game" and maintenanceSession.open then maintenanceSession.mouseX,maintenanceSession.mouseY=x,y; return end
    if state=="game" and editMode and ui.editSliderDrag then ui.updateEditColorSlider(x); return end
    if state=="game" and editMode and editDragging and editedItem then
            local item=saveData.droppedItems[editedItem]; if item then local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,x)); item.y=math.max(top,math.min(bottom,y)) end
    end
end

function love.mousereleased(x,y,button)
    if button==3 then Camera:endPan(); return end
    x,y=screenToGame(x,y)
    if button==1 and ui.editSliderDrag then ui.updateEditColorSlider(x); ui.editSliderDrag=nil; writeSave(); return end
    if button==1 and editDragging then editDragging=false; writeSave() end
    if state=="game" or (state=="battle" and inventoryOpen) then Systems.inventory.handleRelease(ui.inventoryContext(),x,y,button) end
end

function love.wheelmoved(_,y)
    if state=="battle" and battle then
        local mouseX,mouseY=love.mouse.getPosition()
        local mx,my=Viewport.toGame(mouseX,mouseY,W,H)
        if mx>=185 and mx<=775 and my>=488 and my<=570 then
            battle.logScroll=math.max(0,math.min(math.max(0,#(battle.log or {})-1),(battle.logScroll or 0)+(y>0 and 1 or -1)))
        elseif mx>=25 and mx<=935 and my>=55 and my<480 then
            battleZoom=math.max(.75,math.min(1.35,battleZoom+y*.08))
        end
    elseif state=="game" and mapOpen then mapScroll=math.max(0,mapScroll-(y>0 and 1 or -1))
    elseif state=="characters" then characterScroll=math.max(0,characterScroll-(y>0 and 1 or -1))
    elseif state=="game" and not maintenanceSession.open and not inventoryOpen and not editMode and not ui.radioOpen then
        Camera:wheel(y)
    end
end

local function keypressedGlobal(key)
    if maintenanceSession.open then
        local result=Maintenance.keypressed(maintenanceSession,key,saveData)
        if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
        return true
    end
    if tradeOpen then if key=="escape" or key=="q" then tradeOpen=false; tradeNPC=nil; writeSave() end; return end
    if state=="event" then
        local choice=key=="1" and 1 or (key=="2" and 2 or (key=="3" and 3)); if choice then resolveEventChoice(choice) end
        return
    end
    if state=="ending" then if key=="return" or key=="space" then writeSave(); state=session:setScreen("slots") end; return end
    if state=="characters" and (key=="down" or key=="s" or key=="pagedown") then characterScroll=characterScroll+1; return end
    if state=="characters" and (key=="up" or key=="w" or key=="pageup") then characterScroll=math.max(0,characterScroll-1); return end
    if travelConfirm then if key=="escape" then travelConfirm=false elseif key=="return" or key=="e" then local cost=travelCost(); if saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal then saveData.resources.food=saveData.resources.food-cost.food; saveData.resources.water=saveData.resources.water-cost.water; saveData.resources.coal=saveData.resources.coal-cost.coal; travelConfirm=false; travelTransition={t=0,changed=false,departSoundPlayed=true}; playTrainDepart(); writeSave() end end; return end
    if state=="battle" then
        if inventoryOpen then
            if key=="i" or key=="escape" then inventoryOpen=false; draggedSlot=nil; inventoryDragActive=false end
        elseif not battle.finished and key=="i" and BattleRules.activeUnit(battle) and BattleRules.activeUnit(battle).team=="ally" then inventoryOpen=true; draggedSlot=nil; inventoryDragActive=false; ui.playSfx("menu")
        elseif battle.finished and (key=="return" or key=="space" or key=="e") then
            local outcome=battle.finished; battle=nil; state=session:setScreen("game"); if outcome=="win" then enterStop() else scene=session:setScene("train"); writeSave() end
        elseif not battle.finished and tonumber(key) and battle.options and battle.options[tonumber(key)] then battleAttack(battle.options[tonumber(key)])
        elseif not battle.finished and key=="h" then battleHeal()
        elseif not battle.finished and key=="m" and not battle.moveUsed then battle.phase="move"; setBattlePrompt("Choose a highlighted terrain piece to move.")
        elseif not battle.finished and key=="g" then battleGuard()
        elseif not battle.finished and key=="space" then advanceBattleTurn()
        elseif not battle.finished and (key=="r" or key=="escape") then battle=nil; state=session:setScreen("game"); scene=session:setScene("train"); writeSave() end
        return
    end
    if state=="game" and inventoryOpen and key=="e" then inventoryOpen=false; chestOpen=false; activeChest=nil; draggedSlot=nil; inventoryDragActive=false; if giftOpen then giftOpen=false; giftSlot=nil end; writeSave(); return true end
    if state=="game" and dialogue and dialogue.choice and questOffer then if key=="y" or key=="return" or key=="e" then acceptQuest(questOffer.kind) elseif key=="n" or key=="escape" then dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="I understand. Safe travels.",timer=5}; questOffer=nil end; return end
    if state=="game" and carTransition then return true end
    return false
end

function ui.routeWorldInteraction(key)
    local action,arg=Systems.interactions.keyAction({selected=ui.interaction,dialogue=dialogue,
        blocked=state~="game" or maintenanceSession.open or inventoryOpen or mapOpen or editMode or carTransition,
        isFurniture=function(index) local item=saveData.droppedItems[index]; return isFurnitureItem(item and item.name) end},key)
    if not action then return false end
    if action=="closeDialogue" then dialogue=nil
    elseif action=="talkPassenger" then local p=saveData.passengers[arg]; dialogue={speaker=Util.titleFromFile(p.npc).." - "..Util.titleFromFile(p.job),text=Catalog.passengerLines[love.math.random(#Catalog.passengerLines)],timer=7}
    elseif action=="car" then beginCarTransition((saveData.activeCar or 1)+arg)
    elseif action=="talkNPC" then ui.playSfx("talking"); talkToNPC()
    elseif action=="enterHouse" then
        saveData.lastStopDoor=arg; saveData.activeHouseDoor=arg; ui.playSfx("doors"); scene=session:setScene("house")
        local homeLayout=Stops.ensureDoor(saveData,Catalog,arg); ensureHouseItems(); player.x,player.y=InteriorDoors.spawnPoint(homeLayout.interior,scenery.interiorFiles); setupNPC(); writeSave()
    elseif action=="exitHouse" then
        ui.playSfx("doors"); ensureStopLayout(); scene=session:setScene("stop"); saveData.activeHouseDoor=nil
        local x,y=Settlements.doorPoint(saveData.location,saveData.lastStopDoor); player.x,player.y=Settlements.clamp(x,y,saveData.location); setupNPC(); writeSave()
    elseif action=="returnTrain" then
        ui.playSfx("trainDoor"); local left,right,top,bottom=trainFloorBounds(); scene=session:setScene("train"); npcActor=nil; player.x,player.y=right,(top+bottom)/2; writeSave()
    elseif action=="give" then giveWeaponToNearby()
    elseif action=="holdPickup" then holdPickupIndex=arg; holdPickupTime=0
    elseif action=="pickup" then nearbyItem=arg; pickUpNearby()
    elseif action=="fire" then addCoalToFire() end
    return true
end

function love.keypressed(key)
    if state=="intro" then Systems.intro.skip(ui.introCinematic); return end
    if exitPrompt then
        if key=="return" or key=="y" then resolveExitPrompt("yes")
        elseif key=="escape" or key=="n" then resolveExitPrompt("no") end
        return
    end
    if keypressedGlobal(key) then return end
    if key=="escape" then if ui.radioOpen then ui.radioOpen=false; return elseif state=="game" and (inventoryOpen or mapOpen or dialogue or editMode) then inventoryOpen=false; chestOpen=false; activeChest=nil; mapOpen=false; dialogue=nil; questOffer=nil; editMode=false; editedItem=nil; draggedSlot=nil; giftOpen=false; giftSlot=nil; writeSave() elseif state~="slots" then requestExitPrompt("title") else requestExitPrompt("quit") end end
    if key=="i" and state=="game" and not editMode then
        if nearChest then activeChest=saveData.droppedItems[nearChest]; if activeChest then activeChest.storage=activeChest.storage or {}; chestOpen=true; inventoryOpen=true; draggedSlot=nil end
        else inventoryOpen=not inventoryOpen; chestOpen=false; activeChest=nil; draggedSlot=nil end
    end
    if key=="m" and state=="game" then mapOpen=not mapOpen; if mapOpen then mapScroll=math.max(0,math.floor((saveData.location-1)/6)-2) end; inventoryOpen=false; dialogue=nil end
    if state=="game" and mapOpen then if key=="down" or key=="s" then mapScroll=mapScroll+1 elseif key=="up" or key=="w" then mapScroll=math.max(0,mapScroll-1) end; return end
    if state=="game" and editMode and editedItem then
        if key=="left" or key=="a" then moveEditedItem(-5,0) elseif key=="right" or key=="d" then moveEditedItem(5,0) elseif key=="up" or key=="w" then moveEditedItem(0,-5) elseif key=="down" or key=="s" then moveEditedItem(0,5) end
        return
    end
    if key=="p" and state=="game" and ui.nearRadio and not inventoryOpen and not mapOpen and not editMode then ui.radioOpen=not ui.radioOpen; ui.optionsOpen=false; poseMenu=false; ui.playSfx("menu"); return end
    if key=="e" and state=="game" and not inventoryOpen and not mapOpen and not editMode then actionKind="use"; actionTimer=.35 end
    if (key=="q" or key=="g" or key=="e") and ui.routeWorldInteraction(key) then return end
end

function love.keyreleased(key)
    if key=="e" and holdPickupIndex then
        holdPickupIndex,holdPickupTime=nil,0
    end
end

if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    local smokeScope=setmetatable({}, {__index=function(_,name)
        if name=="state" then return session.screen elseif name=="selectedSlot" then return session.selectedSlot elseif name=="saveData" then return session.saveData elseif name=="characters" then return characters elseif name=="ui" then return ui elseif name=="scene" then return session.scene elseif name=="player" then return session.player elseif name=="inventoryOpen" then return inventoryOpen elseif name=="mapOpen" then return mapOpen elseif name=="mapScroll" then return mapScroll elseif name=="tradeOpen" then return tradeOpen elseif name=="trainUpgradeOpen" then return trainUpgradeOpen elseif name=="poseMenu" then return poseMenu elseif name=="randomEvent" then return randomEvent elseif name=="battle" then return battle elseif name=="travelTransition" then return travelTransition elseif name=="maintenanceSession" then return maintenanceSession elseif name=="draggedSlot" then return draggedSlot elseif name=="actionHeldItem" then return actionHeldItem elseif name=="actionTimer" then return actionTimer elseif name=="travelConfirm" then return travelConfirm elseif name=="car" then return car elseif name=="dialogue" then return dialogue elseif name=="editMode" then return editMode elseif name=="carTransition" then return carTransition
        elseif name=="session" then return session elseif name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="Catalog" then return Catalog elseif name=="Assets" then return Assets elseif name=="Save" then return Save elseif name=="Maintenance" then return Maintenance elseif name=="Events" then return Events elseif name=="Systems" then return Systems
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return newSave elseif name=="enterGame" then return enterGame elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="setupNPC" then return setupNPC elseif name=="beginEncounter" then return beginEncounter elseif name=="consumeSelected" then return consumeSelected elseif name=="resolveEventChoice" then return resolveEventChoice elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="battleAttack" then return battleAttack elseif name=="resolveBattleAttack" then return resolveBattleAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then state=session:setScreen(value) elseif name=="selectedSlot" then selectedSlot=session:selectSlot(value) elseif name=="saveData" then saveData=session:setSaveData(value) elseif name=="scene" then scene=session:setScene(value) elseif name=="player" then player=session:setPlayer(value) elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="mapOpen" then mapOpen=value elseif name=="mapScroll" then mapScroll=value elseif name=="tradeOpen" then tradeOpen=value elseif name=="trainUpgradeOpen" then trainUpgradeOpen=value elseif name=="poseMenu" then poseMenu=value elseif name=="randomEvent" then randomEvent=value elseif name=="battle" then battle=value elseif name=="travelTransition" then travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then draggedSlot=value elseif name=="actionHeldItem" then actionHeldItem=value elseif name=="actionTimer" then actionTimer=value elseif name=="travelConfirm" then travelConfirm=value elseif name=="dialogue" then dialogue=value elseif name=="editMode" then editMode=value elseif name=="carTransition" then carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
function love.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); if ui.audio and ui.audio.shutdown then ui.audio:shutdown() end end
