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
local Systems = {inventory=require("game.inventory_ui"),inventoryActions=require("game.inventory_actions"),journeyRules=require("game.journey_rules"),sessionBootstrap=require("game.session_bootstrap"),gameplayUpdate=require("game.gameplay_update"),interactions=require("game.interaction_router"),intro=require("game.intro_cinematic"),battleUI=require("game.battle_ui"),session=require("game.game_session"),screens=require("game.screen_manager"),worldRenderer=require("game.world_renderer"),gameplayHUD=require("game.gameplay_hud"),gameplayInput=require("game.gameplay_input")}
local session = Systems.session.new()
local screens = Systems.screens.new(session)
screens:register("intro"); screens:register("slots"); screens:register("characters"); screens:register("game")
screens:register("battle"); screens:register("event"); screens:register("ending")
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

function ui.resolveSessionBootstrap(name)
    if name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="characters" then return characters
    elseif name=="characterImages" then return characterImages elseif name=="npcImages" then return npcImages
    elseif name=="saveData" then return saveData elseif name=="player" then return player elseif name=="scene" then return scene
    elseif name=="car" then return car elseif name=="ui" then return ui elseif name=="maintenanceSession" then return maintenanceSession
    elseif name=="session" then return session elseif name=="screens" then return screens
    elseif name=="Roster" then return Roster elseif name=="House" then return House elseif name=="Catalog" then return Catalog
    elseif name=="Maintenance" then return Maintenance elseif name=="EngineUpgrades" then return EngineUpgrades
    elseif name=="Passengers" then return Passengers elseif name=="Events" then return Events elseif name=="StopSludges" then return StopSludges
    elseif name=="Settlements" then return Settlements elseif name=="trainObjectBounds" then return trainObjectBounds
    elseif name=="trainFloorBounds" then return trainFloorBounds elseif name=="clampToTrainFloor" then return clampToTrainFloor
    elseif name=="isFurnitureItem" then return isFurnitureItem end
end

function ui.assignSessionBootstrap(name,value)
    if name=="saveData" then saveData=value elseif name=="stopSludges" then stopSludges=value elseif name=="player" then player=value
    elseif name=="scene" then scene=value elseif name=="state" then state=value elseif name=="inventoryOpen" then inventoryOpen=value
    elseif name=="mapOpen" then mapOpen=value elseif name=="dialogue" then dialogue=value elseif name=="editMode" then editMode=value
    elseif name=="chestOpen" then chestOpen=value elseif name=="activeChest" then activeChest=value elseif name=="carTransition" then carTransition=value
    else return false end
    return true
end

Systems.sessionBootstrap=Systems.sessionBootstrap.install(ui.resolveSessionBootstrap,ui.assignSessionBootstrap)



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


local function updateStopSludges(dt)
    if scene~="stop" or not saveData or not player then return end
    StopSludges.update(stopSludges,{data=saveData,location=saveData.location,player=player,npc=npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=animationClock,
        clamp=function(x,y) return Settlements.clamp(x,y,saveData.location) end,
        dropCoal=function(x,y)
            saveData.droppedItems[#saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=saveData.location,droppedByPlayer=false}
            writeSave()
        end},dt)
end

local function attackStopSludge(x,y)
    if scene~="stop" or inventoryOpen or mapOpen or dialogue or editMode or ui.radioOpen or trainUpgradeOpen or poseMenu or ui.optionsOpen then return false end
    return StopSludges.attack(stopSludges,{data=saveData,location=saveData.location,player=player,npc=npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=animationClock,
        onAction=function(weapon) actionHeldItem=weapon; actionKind="melee"; actionTimer=.42 end,
        playSfx=function(kind) ui.playSfx(kind) end})
end


local function itemIsHere(item)
    if item.scene ~= scene then return false end
    if scene == "train" then return (item.carIndex or 1)==(saveData.activeCar or 1) end
    if scene == "house" then return item.location == saveData.location and (item.houseDoor or 1)==(saveData.activeHouseDoor or 1) end
    return item.location == saveData.location
end


local function ensureHouseItems() House.ensure(saveData,Catalog,isFurnitureItem) end


local function ensureStopLayout() return Stops.ensure(saveData,Catalog,scene) end


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

local beginEncounter


local function battleContext()
    return {battle=battle,saveData=saveData,Catalog=Catalog,Util=Util,BattleRules=BattleRules,Events=Events,BOARD_COLS=7,BOARD_ROWS=4,playSfx=ui.playSfx,weaponSfx=ui.weaponSfx,writeSave=writeSave}
end
beginEncounter=function(encounter)
    local c=battleContext(); battle=BattleController.begin(c,encounter); battleZoom=1; screens:transition("battle"); state=session.screen; inventoryOpen=false; mapOpen=false; dialogue=nil; writeSave()
end

local function resolveEventChoice(index)
    local event=randomEvent; if not event then return end
    local result=Events.resolve(saveData,Catalog,event,index); ui.playSfx("menu")
    if result.blocked then return end
    randomEvent=nil; writeSave()
    if result.encounter then beginEncounter(result.encounter); return end
    screens:transition("game"); state=session.screen; Systems.journeyRules.enterStop()
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
function ui.resolveInventoryActions(name)
    if name=="saveData" then return saveData elseif name=="activeChest" then return activeChest elseif name=="chestOpen" then return chestOpen
    elseif name=="draggedSlot" then return draggedSlot elseif name=="inventoryDragActive" then return inventoryDragActive
    elseif name=="dialogue" then return dialogue elseif name=="player" then return player elseif name=="scene" then return scene
    elseif name=="nearNPC" then return nearNPC elseif name=="nearPassenger" then return nearPassenger elseif name=="npcActor" then return npcActor
    elseif name=="nearbyItem" then return nearbyItem elseif name=="giftOpen" then return giftOpen elseif name=="giftNPC" then return giftNPC
    elseif name=="giftSlot" then return giftSlot elseif name=="inventoryOpen" then return inventoryOpen
    elseif name=="actionHeldItem" then return actionHeldItem elseif name=="actionKind" then return actionKind elseif name=="actionTimer" then return actionTimer
    elseif name=="Inventory" then return Inventory elseif name=="Catalog" then return Catalog elseif name=="Util" then return Util
    elseif name=="writeSave" then return writeSave elseif name=="battleContext" then return battleContext
    elseif name=="BattleController" then return BattleController elseif name=="useBattlePotion" then return useBattlePotion end
end

function ui.assignInventoryActions(name,value)
    if name=="activeChest" then activeChest=value elseif name=="chestOpen" then chestOpen=value
    elseif name=="draggedSlot" then draggedSlot=value elseif name=="inventoryDragActive" then inventoryDragActive=value
    elseif name=="dialogue" then dialogue=value elseif name=="nearbyItem" then nearbyItem=value
    elseif name=="giftOpen" then giftOpen=value elseif name=="giftNPC" then giftNPC=value elseif name=="giftSlot" then giftSlot=value
    elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="actionHeldItem" then actionHeldItem=value
    elseif name=="actionKind" then actionKind=value elseif name=="actionTimer" then actionTimer=value else return false end
    return true
end

function ui.resolveJourneyRules(name)
    if name=="saveData" then return saveData elseif name=="dialogue" then return dialogue elseif name=="questOffer" then return questOffer
    elseif name=="tradeOpen" then return tradeOpen elseif name=="tradeNPC" then return tradeNPC elseif name=="car" then return car
    elseif name=="scene" then return scene elseif name=="player" then return player elseif name=="randomEvent" then return randomEvent
    elseif name=="state" then return state elseif name=="screens" then return screens elseif name=="session" then return session
    elseif name=="Inventory" then return Inventory elseif name=="Catalog" then return Catalog elseif name=="EngineUpgrades" then return EngineUpgrades
    elseif name=="Maintenance" then return Maintenance elseif name=="Passengers" then return Passengers elseif name=="Util" then return Util
    elseif name=="House" then return House elseif name=="Events" then return Events elseif name=="ensureStopLayout" then return ensureStopLayout
    elseif name=="setupNPC" then return setupNPC elseif name=="writeSave" then return writeSave elseif name=="beginEncounter" then return beginEncounter end
end

function ui.assignJourneyRules(name,value)
    if name=="dialogue" then dialogue=value elseif name=="questOffer" then questOffer=value
    elseif name=="tradeOpen" then tradeOpen=value elseif name=="tradeNPC" then tradeNPC=value
    elseif name=="scene" then scene=value elseif name=="randomEvent" then randomEvent=value elseif name=="state" then state=value
    else return false end
    return true
end

Systems.inventoryActions=Systems.inventoryActions.install(ui.resolveInventoryActions,ui.assignInventoryActions)
Systems.journeyRules=Systems.journeyRules.install(ui.resolveJourneyRules,ui.assignJourneyRules)

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

function ui.resolveGameplayUpdateState(name)
    if name=="W" then return W elseif name=="ui" then return ui elseif name=="state" then return state
    elseif name=="saveData" then return saveData elseif name=="scene" then return scene elseif name=="player" then return player
    elseif name=="npcActor" then return npcActor elseif name=="car" then return car elseif name=="battle" then return battle
    elseif name=="animationClock" then return animationClock elseif name=="cloudLayer" then return cloudLayer
    elseif name=="walkingSoundTimer" then return walkingSoundTimer elseif name=="travelTransition" then return travelTransition
    elseif name=="trainAnimationClock" then return trainAnimationClock elseif name=="actionTimer" then return actionTimer
    elseif name=="actionHeldItem" then return actionHeldItem elseif name=="actionKind" then return actionKind
    elseif name=="sceneryOffset" then return sceneryOffset elseif name=="landscapeOffset" then return landscapeOffset
    elseif name=="holdPickupIndex" then return holdPickupIndex elseif name=="holdPickupTime" then return holdPickupTime
    elseif name=="HOLD_PICKUP_SECONDS" then return HOLD_PICKUP_SECONDS elseif name=="nearbyItem" then return nearbyItem
    elseif name=="carTransition" then return carTransition elseif name=="inventoryOpen" then return inventoryOpen
    elseif name=="mapOpen" then return mapOpen elseif name=="dialogue" then return dialogue elseif name=="editMode" then return editMode
    elseif name=="maintenanceSession" then return maintenanceSession elseif name=="playerPose" then return playerPose elseif name=="poseMenu" then return poseMenu
    elseif name=="nearChest" then return nearChest elseif name=="nearMailbox" then return nearMailbox elseif name=="nearHouse" then return nearHouse
    elseif name=="nearNPC" then return nearNPC elseif name=="nearPassenger" then return nearPassenger elseif name=="nearReturnTrain" then return nearReturnTrain
    elseif name=="nearFire" then return nearFire elseif name=="nearCarPrev" then return nearCarPrev elseif name=="nearCarNext" then return nearCarNext end
end

function ui.resolveGameplayUpdateServices(name)
    if name=="Systems" then return Systems elseif name=="Catalog" then return Catalog elseif name=="Settlements" then return Settlements
    elseif name=="scenery" then return scenery elseif name=="InteriorDoors" then return InteriorDoors elseif name=="Interactions" then return Interactions
    elseif name=="Save" then return Save elseif name=="Clouds" then return Clouds elseif name=="screens" then return screens
    elseif name=="EngineUpgrades" then return EngineUpgrades elseif name=="Maintenance" then return Maintenance
    elseif name=="Family" then return Family elseif name=="Util" then return Util elseif name=="Passengers" then return Passengers
    elseif name=="session" then return session elseif name=="screenToGame" then return screenToGame
    elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="updateStopSludges" then return updateStopSludges
    elseif name=="clampToTrainFloor" then return clampToTrainFloor elseif name=="itemIsHere" then return itemIsHere
    elseif name=="setupNPC" then return setupNPC elseif name=="trainFloorBounds" then return trainFloorBounds
    elseif name=="writeSave" then return writeSave end
end

function ui.resolveGameplayUpdate(name)
    local value=ui.resolveGameplayUpdateState(name)
    if value~=nil then return value end
    return ui.resolveGameplayUpdateServices(name)
end

function ui.assignGameplayUpdate(name,value)
    if name=="state" then state=value elseif name=="animationClock" then animationClock=value
    elseif name=="walkingSoundTimer" then walkingSoundTimer=value elseif name=="travelTransition" then travelTransition=value
    elseif name=="trainAnimationClock" then trainAnimationClock=value elseif name=="actionTimer" then actionTimer=value
    elseif name=="actionHeldItem" then actionHeldItem=value elseif name=="actionKind" then actionKind=value
    elseif name=="sceneryOffset" then sceneryOffset=value elseif name=="landscapeOffset" then landscapeOffset=value
    elseif name=="dialogue" then dialogue=value elseif name=="holdPickupIndex" then holdPickupIndex=value
    elseif name=="holdPickupTime" then holdPickupTime=value elseif name=="nearbyItem" then nearbyItem=value
    elseif name=="carTransition" then carTransition=value elseif name=="playerPose" then playerPose=value elseif name=="poseMenu" then poseMenu=value
    elseif name=="nearChest" then nearChest=value elseif name=="nearMailbox" then nearMailbox=value elseif name=="nearHouse" then nearHouse=value
    elseif name=="nearNPC" then nearNPC=value elseif name=="nearPassenger" then nearPassenger=value elseif name=="nearReturnTrain" then nearReturnTrain=value
    elseif name=="nearFire" then nearFire=value elseif name=="nearCarPrev" then nearCarPrev=value elseif name=="nearCarNext" then nearCarNext=value
    else return false end
    return true
end

Systems.gameplayUpdate=Systems.gameplayUpdate.install(ui.resolveGameplayUpdate,ui.assignGameplayUpdate)



screens:register("intro",{update=function(dt)
    if Systems.intro.update(ui.introCinematic,dt) then screens:transition("slots"); state=session.screen end
    return true
end})
screens:register("slots",{update=function() return true end})
screens:register("characters",{update=function() return true end})
screens:register("battle",{update=function(dt) if battle then BattleController.update(battleContext(),dt) end; return true end})
screens:register("event",{update=function() return true end})
screens:register("ending",{update=function() return true end})
screens:register("game",{update=function() return false end})

function love.update(dt) return Systems.gameplayUpdate.update(dt) end

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
        screens:transition("slots"); state=session.screen
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
        ui=ui,Inventory=Inventory,Catalog=Catalog,colors=colors,pointIn=Util.pointIn,title=Util.titleFromFile,isWeapon=Systems.inventoryActions.isWeapon,
        drawMenuFrame=drawMenuFrame,button=button,pointer=function() return screenToGame(love.mouse.getPosition()) end,value=Systems.inventoryActions.containerValue,set=ui.setInventoryState,
        battleMode=state=="battle",move=Systems.inventoryActions.moveBetweenSlots,quickTransfer=Systems.inventoryActions.quickTransfer,collectAmmo=Systems.inventoryActions.collectAmmo,drop=state=="battle" and function() return false end or Systems.inventoryActions.dropFromContainer,
        consume=state=="battle" and Systems.inventoryActions.consumeBattleSelected or Systems.inventoryActions.consumeSelected}
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
    local row=0; for i=1,(saveData.inventoryCapacity or 6) do local name=saveData.inventory[i]; if name and row<5 then local y=210+row*72; ui.drawItem(name,{x=495,y=y,w=54,h=54}); love.graphics.setColor(colors.cream); love.graphics.print(Util.titleFromFile(name),555,y+5,0,.72,.72); ui.tradeSell[i]=button("SELL +"..math.max(1,math.floor(Inventory.scrapPrice(name,Catalog)/2)),700,y+5,110,30,true); if Systems.inventoryActions.isWeapon(name) then ui.tradeGive[i]=button("GIVE",700,y+37,110,28,true) end; row=row+1 end end
    ui.tradeClose=button("DONE TRADING",375,605,210,40,true)
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
    Systems.worldRenderer.drawLandscape(); Systems.worldRenderer.drawTracks(); Systems.worldRenderer.drawLocomotive(); Systems.worldRenderer.drawTrainCar(1); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",255,185,450,330,16,16)
    local cost=Systems.journeyRules.travelCost(); love.graphics.setColor(colors.cream); love.graphics.printf("TRAVEL TO STOP "..(saveData.location+1),275,220,410,"center",0,1.5,1.5)
    love.graphics.printf("The next stretch is farther than the last.\nThis journey will consume:",300,275,360,"center")
    love.graphics.printf(cost.food.." FOOD     "..cost.water.." WATER     "..cost.coal.." COAL",280,350,400,"center",0,1.2,1.2)
    love.graphics.printf("TERRAIN: "..string.upper(cost.terrain or "plains"),280,377,400,"center",0,.78,.78)
    if cost.passengers>0 then love.graphics.printf(cost.passengers.." passenger"..(cost.passengers==1 and "" or "s").." add "..cost.passengers.." food and water.",280,385,400,"center",0,0.82,0.82) end
    if cost.maintenanceCoal>0 then love.graphics.setColor(colors.red); love.graphics.printf("LOW MAINTENANCE ADDS +"..cost.maintenanceCoal.." COAL",280,404,400,"center",0,.68,.68) end
    local enough=saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal
    ui.travelYes=button(enough and "CONFIRM JOURNEY" or "NOT ENOUGH SUPPLIES",305,425,220,48,enough); ui.travelNo=button("CANCEL",545,425,110,48,true)
end

function ui.drawRandomEvent()
    Systems.worldRenderer.drawLandscape(); love.graphics.setColor(0,0,0,0.76); love.graphics.rectangle("fill",0,0,W,H)
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
        drawLandscape=Systems.worldRenderer.drawLandscape,drawGround=Systems.worldRenderer.drawGround,
        drawAnimatedCharacter=Systems.worldRenderer.drawAnimatedCharacter,button=button,screenToGame=screenToGame,
        setInventoryOpen=function(value) inventoryOpen=value end,
        resetInventoryDrag=function() draggedSlot=nil; inventoryDragActive=false end,
        battleAttack=battleAttack,setBattlePrompt=setBattlePrompt,battleHeal=battleHeal,battleGuard=battleGuard,
        useBattleAbility=useBattleAbility,useBattlePotion=useBattlePotion,advanceBattleTurn=advanceBattleTurn,
        resolveBattleAttack=resolveBattleAttack,battleMoveTo=battleMoveTo
    }
end

function ui.drawTacticalBattle() Systems.battleUI.draw(ui.battleUIContext()) end

local function resolveWorldRenderer(name)
    if name=="W" then return W elseif name=="H" then return H
    elseif name=="backgroundImages" then return backgroundImages elseif name=="saveData" then return saveData
    elseif name=="landscapeOffset" then return landscapeOffset elseif name=="scenery" then return scenery
    elseif name=="sceneryOffset" then return sceneryOffset elseif name=="trainAnimationClock" then return trainAnimationClock
    elseif name=="animationClock" then return animationClock elseif name=="car" then return car
    elseif name=="colors" then return colors elseif name=="characterAnimations" then return characterAnimations
    elseif name=="characterImages" then return characterImages elseif name=="characterWalkImages" then return characterWalkImages
    elseif name=="characterActionImages" then return characterActionImages elseif name=="player" then return player
    elseif name=="actionTimer" then return actionTimer elseif name=="actionHeldItem" then return actionHeldItem
    elseif name=="actionKind" then return actionKind elseif name=="playerPose" then return playerPose
    elseif name=="ui" then return ui elseif name=="editMode" then return editMode
    elseif name=="editedItem" then return editedItem elseif name=="scene" then return scene
    elseif name=="itemIdleImages" then return itemIdleImages elseif name=="npcActor" then return npcActor
    elseif name=="npcImages" then return npcImages elseif name=="npcWalkImages" then return npcWalkImages
    elseif name=="familyImages" then return familyImages elseif name=="mobImages" then return mobImages
    elseif name=="mobIdleImages" then return mobIdleImages elseif name=="mobWalkImages" then return mobWalkImages
    elseif name=="mobHitImages" then return mobHitImages elseif name=="mobDeathImages" then return mobDeathImages
    elseif name=="stopSludges" then return stopSludges elseif name=="StopSludges" then return StopSludges
    elseif name=="Train" then return Train
    elseif name=="CharacterAnimation" then return CharacterAnimation elseif name=="Catalog" then return Catalog
    elseif name=="Family" then return Family
    elseif name=="Settlements" then return Settlements elseif name=="Stops" then return Stops
    elseif name=="Util" then return Util elseif name=="itemIsHere" then return itemIsHere
    elseif name=="pendingMailHere" then return Systems.journeyRules.pendingMailHere elseif name=="ensureStopLayout" then return ensureStopLayout end
end
Systems.worldRenderer=Systems.worldRenderer.install(resolveWorldRenderer)


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

local function resolveGameplayHUD(name)
    if name=="W" then return W elseif name=="H" then return H elseif name=="ui" then return ui
    elseif name=="scene" then return scene elseif name=="saveData" then return saveData elseif name=="player" then return player
    elseif name=="travelTransition" then return travelTransition elseif name=="carTransition" then return carTransition
    elseif name=="cloudLayer" then return cloudLayer elseif name=="sceneryOffset" then return sceneryOffset
    elseif name=="colors" then return colors elseif name=="inventoryOpen" then return inventoryOpen
    elseif name=="mapOpen" then return mapOpen elseif name=="editMode" then return editMode
    elseif name=="poseMenu" then return poseMenu elseif name=="trainUpgradeOpen" then return trainUpgradeOpen
    elseif name=="tradeOpen" then return tradeOpen elseif name=="maintenanceSession" then return maintenanceSession
    elseif name=="nearbyItem" then return nearbyItem elseif name=="nearPassenger" then return nearPassenger
    elseif name=="nearCarNext" then return nearCarNext elseif name=="nearCarPrev" then return nearCarPrev
    elseif name=="nearNPC" then return nearNPC elseif name=="nearMailbox" then return nearMailbox
    elseif name=="nearChest" then return nearChest elseif name=="nearHouse" then return nearHouse
    elseif name=="nearReturnTrain" then return nearReturnTrain elseif name=="nearFire" then return nearFire
    elseif name=="holdPickupIndex" then return holdPickupIndex elseif name=="holdPickupTime" then return holdPickupTime
    elseif name=="HOLD_PICKUP_SECONDS" then return HOLD_PICKUP_SECONDS elseif name=="inventoryDragActive" then return inventoryDragActive
    elseif name=="draggedSlot" then return draggedSlot elseif name=="EngineUpgrades" then return EngineUpgrades
    elseif name=="Clouds" then return Clouds elseif name=="Maintenance" then return Maintenance
    elseif name=="Util" then return Util elseif name=="button" then return button
    elseif name=="drawMenuFrame" then return drawMenuFrame elseif name=="drawTrade" then return drawTrade
    elseif name=="isFurnitureItem" then return isFurnitureItem elseif name=="containerValue" then return Systems.inventoryActions.containerValue
    elseif name=="screenToGame" then return screenToGame elseif name=="drawLandscape" then return Systems.worldRenderer.drawLandscape
    elseif name=="drawTracks" then return Systems.worldRenderer.drawTracks elseif name=="drawTrainView" then return Systems.worldRenderer.drawTrainView
    elseif name=="drawHouse" then return Systems.worldRenderer.drawHouse elseif name=="drawStop" then return Systems.worldRenderer.drawStop end
end
Systems.gameplayHUD=Systems.gameplayHUD.install(resolveGameplayHUD)



local function drawEnding()
    Systems.worldRenderer.drawLandscape(); love.graphics.setColor(0.08,0.05,0.03,0.72); love.graphics.rectangle("fill",0,0,W,H)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",120,90,720,540,20,20)
    love.graphics.setColor(colors.brass); love.graphics.printf("CALIFORNIA",120,135,720,"center",0,2.2,2.2)
    love.graphics.setColor(colors.cream); love.graphics.printf("After 50 stops, the Mouse Frontier finally reaches the end of the line.",205,215,550,"center",0,1.15,1.15)
    love.graphics.printf("You found your family. The old train became a lifeline for every critter you met along the way—and your journey west became a story they will tell for generations.",220,285,520,"center")
    local family={saveData.character,(saveData.npcRoster or {})[1],(saveData.npcRoster or {})[2]}
    for i,file in ipairs(family) do local img=characterImages[file] or npcImages[file]; if img then local s=math.min(105/img:getWidth(),145/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,360+(i-1)*120,475+math.sin(animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2) end end
    ui.endingButton=button("RETURN TO SAVE FILES",350,560,260,48,true)
end

screens:register("intro",{draw=function()
    local windowWidth,windowHeight=love.graphics.getDimensions()
    Systems.intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
end})
screens:register("slots",{draw=ui.drawSlots})
screens:register("characters",{draw=ui.drawCharacterSelect})
screens:register("battle",{draw=ui.drawTacticalBattle})
screens:register("event",{draw=ui.drawRandomEvent})
screens:register("ending",{draw=drawEnding})
screens:register("game",{draw=function() if travelConfirm then ui.drawTravelConfirm() else Systems.gameplayHUD.draw() end end})

function love.draw()
    love.graphics.clear(0.025,0.02,0.025,1)
    if screens:is("intro") then screens:draw(); return end
    local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
    love.graphics.push()
    love.graphics.translate(offsetX,offsetY)
    love.graphics.scale(scaleX,scaleY)
    if state=="game" and not travelConfirm and not maintenanceSession.open and Camera:isActive() then
        local focusX,focusY=(player and player.x or W/2),(player and player.y or H/2)
        Camera:apply(focusX,focusY)
    end
    screens:draw()
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

function ui.resolveGameplayInputState(name)
    if name=="W" then return W elseif name=="H" then return H elseif name=="ui" then return ui
    elseif name=="state" then return state elseif name=="saveData" then return saveData elseif name=="player" then return player
    elseif name=="scene" then return scene elseif name=="selectedSlot" then return selectedSlot elseif name=="characters" then return characters
    elseif name=="characterScroll" then return characterScroll elseif name=="dialogue" then return dialogue elseif name=="questOffer" then return questOffer
    elseif name=="inventoryOpen" then return inventoryOpen elseif name=="chestOpen" then return chestOpen elseif name=="activeChest" then return activeChest
    elseif name=="draggedSlot" then return draggedSlot elseif name=="inventoryDragActive" then return inventoryDragActive
    elseif name=="giftOpen" then return giftOpen elseif name=="giftNPC" then return giftNPC elseif name=="giftSlot" then return giftSlot
    elseif name=="poseMenu" then return poseMenu elseif name=="playerPose" then return playerPose
    elseif name=="actionKind" then return actionKind elseif name=="actionTimer" then return actionTimer
    elseif name=="tradeOpen" then return tradeOpen elseif name=="tradeNPC" then return tradeNPC
    elseif name=="trainUpgradeOpen" then return trainUpgradeOpen elseif name=="maintenanceSession" then return maintenanceSession
    elseif name=="editMode" then return editMode elseif name=="editedItem" then return editedItem elseif name=="editDragging" then return editDragging
    elseif name=="mapOpen" then return mapOpen elseif name=="mapScroll" then return mapScroll
    elseif name=="travelConfirm" then return travelConfirm elseif name=="travelTransition" then return travelTransition
    elseif name=="carTransition" then return carTransition elseif name=="battle" then return battle elseif name=="battleZoom" then return battleZoom
    elseif name=="nearChest" then return nearChest elseif name=="nearbyItem" then return nearbyItem
    elseif name=="holdPickupIndex" then return holdPickupIndex elseif name=="holdPickupTime" then return holdPickupTime
    elseif name=="npcActor" then return npcActor elseif name=="exitPrompt" then return exitPrompt end
end

function ui.resolveGameplayInputServices(name)
    if name=="Systems" then return Systems elseif name=="screens" then return screens elseif name=="session" then return session
    elseif name=="Inventory" then return Inventory elseif name=="Catalog" then return Catalog elseif name=="Util" then return Util
    elseif name=="Save" then return Save elseif name=="EventUI" then return EventUI elseif name=="EngineUpgrades" then return EngineUpgrades
    elseif name=="Maintenance" then return Maintenance elseif name=="Camera" then return Camera elseif name=="Viewport" then return Viewport
    elseif name=="BattleRules" then return BattleRules elseif name=="Stops" then return Stops elseif name=="Settlements" then return Settlements
    elseif name=="InteriorDoors" then return InteriorDoors elseif name=="scenery" then return scenery
    elseif name=="writeSave" then return writeSave elseif name=="screenToGame" then return screenToGame
    elseif name=="isWeapon" then return Systems.inventoryActions.isWeapon elseif name=="isFurnitureItem" then return isFurnitureItem
    elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="ownsTrainCar" then return ownsTrainCar
    elseif name=="moveEditedItem" then return moveEditedItem elseif name=="attackStopSludge" then return attackStopSludge
    elseif name=="acceptQuest" then return Systems.journeyRules.acceptQuest elseif name=="attemptLeaveTrain" then return Systems.journeyRules.attemptLeaveTrain
    elseif name=="travelCost" then return Systems.journeyRules.travelCost elseif name=="playTrainDepart" then return playTrainDepart
    elseif name=="trainFloorBounds" then return trainFloorBounds elseif name=="newSave" then return Systems.sessionBootstrap.newSave
    elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="resolveEventChoice" then return resolveEventChoice
    elseif name=="enterStop" then return Systems.journeyRules.enterStop elseif name=="battleAttack" then return battleAttack
    elseif name=="battleHeal" then return battleHeal elseif name=="battleGuard" then return battleGuard
    elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="setBattlePrompt" then return setBattlePrompt
    elseif name=="beginCarTransition" then return beginCarTransition elseif name=="talkToNPC" then return Systems.journeyRules.talkToNPC
    elseif name=="ensureHouseItems" then return ensureHouseItems elseif name=="setupNPC" then return setupNPC
    elseif name=="giveWeaponToNearby" then return Systems.inventoryActions.giveWeaponToNearby elseif name=="pickUpNearby" then return Systems.inventoryActions.pickUpNearby
    elseif name=="addCoalToFire" then return Systems.inventoryActions.addCoalToFire elseif name=="requestExitPrompt" then return requestExitPrompt
    elseif name=="resolveExitPrompt" then return resolveExitPrompt end
end

function ui.resolveGameplayInput(name)
    local value=ui.resolveGameplayInputState(name)
    if value~=nil then return value end
    return ui.resolveGameplayInputServices(name)
end


function ui.assignGameplayInput(name,value)
    if name=="state" then state=value elseif name=="saveData" then saveData=value elseif name=="scene" then scene=value
    elseif name=="selectedSlot" then selectedSlot=value elseif name=="characterScroll" then characterScroll=value
    elseif name=="dialogue" then dialogue=value elseif name=="questOffer" then questOffer=value
    elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="chestOpen" then chestOpen=value elseif name=="activeChest" then activeChest=value
    elseif name=="draggedSlot" then draggedSlot=value elseif name=="inventoryDragActive" then inventoryDragActive=value
    elseif name=="giftOpen" then giftOpen=value elseif name=="giftSlot" then giftSlot=value
    elseif name=="poseMenu" then poseMenu=value elseif name=="playerPose" then playerPose=value
    elseif name=="actionKind" then actionKind=value elseif name=="actionTimer" then actionTimer=value
    elseif name=="tradeOpen" then tradeOpen=value elseif name=="tradeNPC" then tradeNPC=value
    elseif name=="trainUpgradeOpen" then trainUpgradeOpen=value elseif name=="editMode" then editMode=value
    elseif name=="editedItem" then editedItem=value elseif name=="editDragging" then editDragging=value
    elseif name=="mapOpen" then mapOpen=value elseif name=="mapScroll" then mapScroll=value
    elseif name=="travelConfirm" then travelConfirm=value elseif name=="travelTransition" then travelTransition=value
    elseif name=="battle" then battle=value elseif name=="battleZoom" then battleZoom=value
    elseif name=="npcActor" then npcActor=value elseif name=="nearbyItem" then nearbyItem=value
    elseif name=="holdPickupIndex" then holdPickupIndex=value elseif name=="holdPickupTime" then holdPickupTime=value
    else return false end
    return true
end

Systems.gameplayInput=Systems.gameplayInput.install(ui.resolveGameplayInput,ui.assignGameplayInput)
function love.mousepressed(...) return Systems.gameplayInput.mousepressed(...) end
function love.mousemoved(...) return Systems.gameplayInput.mousemoved(...) end
function love.mousereleased(...) return Systems.gameplayInput.mousereleased(...) end
function love.wheelmoved(...) return Systems.gameplayInput.wheelmoved(...) end
function love.keypressed(...) return Systems.gameplayInput.keypressed(...) end
function love.keyreleased(...) return Systems.gameplayInput.keyreleased(...) end



if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    local smokeScope=setmetatable({}, {__index=function(_,name)
        if name=="state" then return session.screen elseif name=="selectedSlot" then return session.selectedSlot elseif name=="saveData" then return session.saveData elseif name=="characters" then return characters elseif name=="ui" then return ui elseif name=="scene" then return session.scene elseif name=="player" then return session.player elseif name=="inventoryOpen" then return inventoryOpen elseif name=="mapOpen" then return mapOpen elseif name=="mapScroll" then return mapScroll elseif name=="tradeOpen" then return tradeOpen elseif name=="trainUpgradeOpen" then return trainUpgradeOpen elseif name=="poseMenu" then return poseMenu elseif name=="randomEvent" then return randomEvent elseif name=="battle" then return battle elseif name=="travelTransition" then return travelTransition elseif name=="maintenanceSession" then return maintenanceSession elseif name=="draggedSlot" then return draggedSlot elseif name=="actionHeldItem" then return actionHeldItem elseif name=="actionTimer" then return actionTimer elseif name=="travelConfirm" then return travelConfirm elseif name=="car" then return car elseif name=="dialogue" then return dialogue elseif name=="editMode" then return editMode elseif name=="carTransition" then return carTransition
        elseif name=="session" then return session elseif name=="screens" then return screens elseif name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="Catalog" then return Catalog elseif name=="Assets" then return Assets elseif name=="Save" then return Save elseif name=="Maintenance" then return Maintenance elseif name=="Events" then return Events elseif name=="Systems" then return Systems
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return Systems.sessionBootstrap.newSave elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="setupNPC" then return setupNPC elseif name=="beginEncounter" then return beginEncounter elseif name=="consumeSelected" then return Systems.inventoryActions.consumeSelected elseif name=="resolveEventChoice" then return resolveEventChoice elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="battleAttack" then return battleAttack elseif name=="resolveBattleAttack" then return resolveBattleAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then screens:transition(value); state=session.screen elseif name=="selectedSlot" then selectedSlot=session:selectSlot(value) elseif name=="saveData" then saveData=session:setSaveData(value) elseif name=="scene" then scene=session:setScene(value) elseif name=="player" then player=session:setPlayer(value) elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="mapOpen" then mapOpen=value elseif name=="mapScroll" then mapScroll=value elseif name=="tradeOpen" then tradeOpen=value elseif name=="trainUpgradeOpen" then trainUpgradeOpen=value elseif name=="poseMenu" then poseMenu=value elseif name=="randomEvent" then randomEvent=value elseif name=="battle" then battle=value elseif name=="travelTransition" then travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then draggedSlot=value elseif name=="actionHeldItem" then actionHeldItem=value elseif name=="actionTimer" then actionTimer=value elseif name=="travelConfirm" then travelConfirm=value elseif name=="dialogue" then dialogue=value elseif name=="editMode" then editMode=value elseif name=="carTransition" then carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
function love.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); if ui.audio and ui.audio.shutdown then ui.audio:shutdown() end end
