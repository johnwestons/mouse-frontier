if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    love.errorhandler=function(message)
        io.stderr:write("LOVE_ERROR: "..tostring(message).."\n"..debug.traceback().."\n"); io.stderr:flush()
        return function() os.exit(1) end
    end
end

local App = {}
local Config = require("game.config")
local SaveSchema = require("game.save_schema")
local W, H = Config.baseWidth, Config.baseHeight
local CURRENT_SAVE_VERSION = SaveSchema.CURRENT_VERSION
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
local RuntimeState = require("game.runtime_state")
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
local MobileControls = require("game.mobile_controls")
local Systems = require("game.systems")
local session = Systems.session.new()
local screens = Systems.screens.new(session)
screens:register("intro"); screens:register("slots"); screens:register("characters"); screens:register("game")
screens:register("battle"); screens:register("event"); screens:register("ending")
local runtime = RuntimeState.new({
    session = session,
    transition = function(screen) screens:transition(screen) end,
})
local characters, characterImages, npcImages, mobImages, mobFiles = {}, {}, {}, {}, {}
local scenery, backgroundImages, ui = {}, {}, {}
local sceneryOffset, landscapeOffset, animationClock, trainAnimationClock = 0, 0, 0, 0
local cloudLayer
local battleZoom = 1
local walkingSoundTimer = 0
local inventoryOpen, draggedSlot = false, nil
local nearbyItem = nil
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
local HOLD_PICKUP_SECONDS = Config.holdPickupSeconds
local trainUpgradeOpen=false
local poseMenu, playerPose = false, "idle"
local tradeOpen, tradeNPC = false, nil
local giftOpen, giftNPC, giftSlot = false, nil, nil
local exitPrompt = nil
local carTransition = nil
local lastInventoryClick, lastInventoryClickTime = nil, 0
local maintenanceSession = Maintenance.new()
local mobileControls


-- Rolling-stock layout: the car sits farther right to leave room for the
-- enlarged locomotive while retaining one shared rail/coupler baseline.
local car = Config.trainCar
local function activeTrainCarImage()
    local image=scenery and scenery.trainCarImages and scenery.trainCarImages[runtime.saveData and runtime.saveData.trainCars and runtime.saveData.trainCars[runtime.saveData.activeCar or 1] or "living-car"]
    return image
end
local function trainFloorBounds()
    return Train.characterBounds(car,activeTrainCarImage(),30)
end
local function trainObjectBounds()
    -- Editor placement is intentionally unconstrained: objects may be arranged
    -- anywhere in the visible game canvas, including the roof/track margins.
    return 0, W, 0, H
end
local function clampToTrainFloor(x,y)
    return Train.clampCharacterToFloor(car,activeTrainCarImage(),x,y,30)
end
local colors = Config.colors


local function writeSave()
    if not runtime.selectedSlot or not runtime.saveData then return end
    runtime:syncForSave()
    ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
    session:scheduleSave(Save)
end

local function isFurnitureItem(name)
    return name and love.filesystem.getInfo("assets/sprites/furniture/"..name..".png")~=nil
end

Systems.sessionBootstrap=Systems.sessionBootstrap.new({
    saveSchema=SaveSchema,
    characters=characters,
    characterImages=characterImages,
    npcImages=npcImages,
    car=car,
    ui=ui,
    maintenanceSession=maintenanceSession,
    runtime=runtime,
    filesystem=love.filesystem,
    roster=Roster,
    house=House,
    catalog=Catalog,
    maintenance=Maintenance,
    engineUpgrades=EngineUpgrades,
    passengers=Passengers,
    events=Events,
    stopSludges=StopSludges,
    settlements=Settlements,
    trainObjectBounds=trainObjectBounds,
    trainFloorBounds=trainFloorBounds,
    clampToTrainFloor=clampToTrainFloor,
    isFurnitureItem=isFurnitureItem,
    setStopSludges=function(value) stopSludges=value end,
    resetTransientState=function()
        inventoryOpen,mapOpen,dialogue,editMode=false,false,nil,false
        chestOpen,activeChest,carTransition=false,nil,nil
    end,
})



local function screenToGame(x,y)
    x,y=Viewport.toGame(x,y,W,H)
    -- Radio/options are screen-space overlays; camera zoom must not shift their
    -- hit testing into a neighboring station button.
    if runtime.state=="game" and not travelConfirm and not ui.radioOpen and not ui.mobileMenuOpen and Camera:isActive() then
        local focusX,focusY=(runtime.player and runtime.player.x or W/2),(runtime.player and runtime.player.y or H/2)
        x,y=Camera:toWorld(x,y,focusX,focusY)
    end
    return x,y
end

local function pointerPosition()
    local x,y=love.mouse.getPosition()
    if mobileControls then return mobileControls:pointer(x,y) end
    return x,y
end


local function updateStopSludges(dt)
    if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return end
    StopSludges.update(stopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=animationClock,
        clamp=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
        dropCoal=function(x,y)
            runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=runtime.saveData.location,droppedByPlayer=false}
            writeSave()
        end},dt)
end

local function attackStopSludge(x,y)
    if runtime.scene~="stop" or inventoryOpen or mapOpen or dialogue or editMode or ui.radioOpen or trainUpgradeOpen or poseMenu or ui.optionsOpen then return false end
    return StopSludges.attack(stopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=animationClock,
        onAction=function(weapon) actionHeldItem=weapon; actionKind="melee"; actionTimer=.42 end,
        playSfx=function(kind) ui.playSfx(kind) end})
end


local function itemIsHere(item)
    if item.scene ~= runtime.scene then return false end
    if runtime.scene == "train" then return (item.carIndex or 1)==(runtime.saveData.activeCar or 1) end
    if runtime.scene == "house" then return item.location == runtime.saveData.location and (item.houseDoor or 1)==(runtime.saveData.activeHouseDoor or 1) end
    return item.location == runtime.saveData.location
end


local function ensureHouseItems() House.ensure(runtime.saveData,Catalog,isFurnitureItem) end


local function ensureStopLayout() return Stops.ensure(runtime.saveData,Catalog,runtime.scene) end


local function setupNPC()
    if runtime.scene == "train" then npcActor = nil; return end
    local layout=ensureStopLayout()
    runtime.saveData.currentNPC=(runtime.scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    local key = Util.sceneKey(runtime.scene,runtime.saveData.location)..(runtime.scene=="house" and (":"..tostring(runtime.saveData.activeHouseDoor or 1)) or "")
    local saved = runtime.saveData.npcStates[key]
    local defaults = runtime.scene == "house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
    saved = saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
    saved.weapon=saved.weapon or layout.npcWeapon
    if runtime.scene=="house" then
        saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
        saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
    elseif runtime.scene=="stop" then
        saved.x,saved.y=Settlements.clamp(saved.x,saved.y,runtime.saveData.location)
        saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,runtime.saveData.location)
    end
    runtime.saveData.npcStates[key] = saved
    npcActor = saved
    Family.ensure(npcActor,runtime.saveData.currentNPC)
end

local beginEncounter


local function battleContext()
    return {battle=battle,saveData=runtime.saveData,Catalog=Catalog,Util=Util,BattleRules=BattleRules,Events=Events,BOARD_COLS=7,BOARD_ROWS=4,playSfx=ui.playSfx,weaponSfx=ui.weaponSfx,writeSave=writeSave}
end
beginEncounter=function(encounter)
    local c=battleContext(); battle=BattleController.begin(c,encounter); battleZoom=1; runtime.state="battle"; inventoryOpen=false; mapOpen=false; dialogue=nil; writeSave()
end

local function resolveEventChoice(index)
    local event=randomEvent; if not event then return end
    local result=Events.resolve(runtime.saveData,Catalog,event,index); ui.playSfx("menu")
    if result.blocked then return end
    randomEvent=nil; writeSave()
    if result.encounter then beginEncounter(result.encounter); return end
    runtime.state="game"; Systems.journeyRules.enterStop()
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
    if name=="saveData" then return runtime.saveData elseif name=="activeChest" then return activeChest elseif name=="chestOpen" then return chestOpen
    elseif name=="draggedSlot" then return draggedSlot elseif name=="inventoryDragActive" then return inventoryDragActive
    elseif name=="dialogue" then return dialogue elseif name=="player" then return runtime.player elseif name=="scene" then return runtime.scene
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
    if name=="saveData" then return runtime.saveData elseif name=="dialogue" then return dialogue elseif name=="questOffer" then return questOffer
    elseif name=="tradeOpen" then return tradeOpen elseif name=="tradeNPC" then return tradeNPC elseif name=="car" then return car
    elseif name=="scene" then return runtime.scene elseif name=="player" then return runtime.player elseif name=="randomEvent" then return randomEvent
    elseif name=="state" then return runtime.state elseif name=="screens" then return screens elseif name=="session" then return session
    elseif name=="Inventory" then return Inventory elseif name=="Catalog" then return Catalog elseif name=="EngineUpgrades" then return EngineUpgrades
    elseif name=="Maintenance" then return Maintenance elseif name=="Passengers" then return Passengers elseif name=="Util" then return Util
    elseif name=="House" then return House elseif name=="Events" then return Events elseif name=="ensureStopLayout" then return ensureStopLayout
    elseif name=="setupNPC" then return setupNPC elseif name=="writeSave" then return writeSave elseif name=="beginEncounter" then return beginEncounter end
end

function ui.assignJourneyRules(name,value)
    if name=="dialogue" then dialogue=value elseif name=="questOffer" then questOffer=value
    elseif name=="tradeOpen" then tradeOpen=value elseif name=="tradeNPC" then tradeNPC=value
    elseif name=="scene" then runtime.scene=value elseif name=="randomEvent" then randomEvent=value elseif name=="state" then runtime.state=value
    else return false end
    return true
end

Systems.inventoryActions=Systems.inventoryActions.install(ui.resolveInventoryActions,ui.assignInventoryActions)
Systems.journeyRules=Systems.journeyRules.install(ui.resolveJourneyRules,ui.assignJourneyRules)

function ui.playSfx(kind)
    if ui.audio and runtime.saveData then return ui.audio:playSfx(kind,runtime.saveData.audio,battle) end
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
    if runtime.state=="ending" then return "endingHappy" end
    if runtime.state=="battle" then return battle and battle.encounter and battle.encounter.tier=="hard" and "bossFight" or "battle" end
    if runtime.scene=="house" then return "insideHomes" end
    if runtime.scene=="stop" or runtime.state=="event" then return "stops" end
    return "train"
end

function ui.updateMusic()
    if runtime.saveData and ui.audio then ui.audio:update(runtime.saveData.audio,ui.musicCategory()) end
end

function ui.updateChickens(dt)
    if runtime.scene~="stop" or not runtime.saveData then return end
    local stopLayout=ensureStopLayout()
    Wildlife.spawn(stopLayout,runtime.saveData.location,Settlements)
    Wildlife.update(stopLayout.wildlife,dt,runtime.saveData.location,Settlements)
end

function ui.updateMice(dt)
    if runtime.scene~="stop" or not runtime.saveData then return end
    local stopLayout=ensureStopLayout()
    Mice.spawn(stopLayout,runtime.saveData.location,Settlements)
    Mice.update(stopLayout.mice,dt,runtime.saveData.location,Settlements)
end

function ui.drawChickens(layout)
    if not layout or runtime.scene~="stop" then return end
    Wildlife.spawn(layout,runtime.saveData.location,Settlements)
    Wildlife.draw(layout.wildlife,scenery.stopWildlife,animationClock)
end

function ui.drawMice(layout)
    if not layout or runtime.scene~="stop" then return end
    Mice.spawn(layout,runtime.saveData.location,Settlements)
    Mice.draw(layout.mice,scenery.stopWildlife,animationClock)
end

function App.load()
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
    mobileControls=MobileControls.new({
        width=W,height=H,
        toGame=function(x,y) return Viewport.toGame(x,y,W,H) end,
        gameplayActive=function()
            return runtime.state=="game" and not travelConfirm and not travelTransition and not maintenanceSession.open
                and not inventoryOpen and not mapOpen and not tradeOpen and not trainUpgradeOpen and not editMode
                and not poseMenu and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not exitPrompt
        end,
        getZoom=function() return Camera.zoom end,
        setZoom=function(value) Camera:setZoom(value) end,
        backVisible=function()
            if exitPrompt then return true end
            if runtime.state=="slots" or runtime.state=="characters" then return true end
            if runtime.state=="battle" then return inventoryOpen end
            return runtime.state=="game" and (travelConfirm or maintenanceSession.open or inventoryOpen or mapOpen or tradeOpen or trainUpgradeOpen
                or editMode or poseMenu or ui.optionsOpen or ui.radioOpen or ui.mobileMenuOpen or dialogue~=nil)
        end,
        backLabel=function() return runtime.state=="slots" and "EXIT" or "BACK" end,
        menuVisible=function()
            return runtime.state=="game" and not travelConfirm and not travelTransition and not maintenanceSession.open and not exitPrompt
                and not inventoryOpen and not mapOpen and not tradeOpen and not trainUpgradeOpen and not editMode
                and not poseMenu and not ui.optionsOpen and not ui.radioOpen and not dialogue
        end,
        menuLabel=function() return ui.mobileMenuOpen and "CLOSE" or "MENU" end,
        menuAction=function() ui.mobileMenuOpen=not ui.mobileMenuOpen; Camera:endPan() end,
        primaryAction=function()
            if dialogue then return "q","CLOSE" end
            local kind=ui.interaction and ui.interaction.kind
            if kind=="radio" then return "p","RADIO"
            elseif kind=="item" then return "e","PICK UP"
            elseif kind=="chest" then return "i","OPEN"
            elseif kind=="fire" then return "e","COAL"
            elseif kind=="npc" or kind=="passenger" then return "q","TALK"
            elseif kind=="house" then return "q","ENTER"
            elseif kind=="houseExit" then return "q","EXIT"
            elseif kind=="returnTrain" then return "q","BOARD"
            elseif kind=="carNext" or kind=="carPrev" then return "q","DOOR"
            end
            return "e","USE"
        end,
        secondaryAction=function()
            local kind=ui.interaction and ui.interaction.kind
            if kind=="npc" or kind=="passenger" then return "g","GIVE" end
        end,
        pressKey=function(key) Systems.gameplayInput.keypressed(key) end,
        releaseKey=function(key) Systems.gameplayInput.keyreleased(key) end,
        pressPointer=function(x,y,button) Systems.gameplayInput.mousepressed(x,y,button) end,
        movePointer=function(x,y,dx,dy) Systems.gameplayInput.mousemoved(x,y,dx,dy) end,
        releasePointer=function(x,y,button) Systems.gameplayInput.mousereleased(x,y,button) end,
    })
end

function ui.resolveGameplayUpdateState(name)
    if name=="W" then return W elseif name=="ui" then return ui elseif name=="state" then return runtime.state
    elseif name=="saveData" then return runtime.saveData elseif name=="scene" then return runtime.scene elseif name=="player" then return runtime.player
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
    elseif name=="writeSave" then return writeSave elseif name=="mobileControls" then return mobileControls end
end

function ui.resolveGameplayUpdate(name)
    local value=ui.resolveGameplayUpdateState(name)
    if value~=nil then return value end
    return ui.resolveGameplayUpdateServices(name)
end

function ui.assignGameplayUpdate(name,value)
    if name=="state" then runtime.state=value elseif name=="animationClock" then animationClock=value
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
    if Systems.intro.update(ui.introCinematic,dt) then runtime.state="slots" end
    return true
end})
screens:register("slots",{update=function() return true end})
screens:register("characters",{update=function() return true end})
screens:register("battle",{update=function(dt) if battle then BattleController.update(battleContext(),dt) end; return true end})
screens:register("event",{update=function() return true end})
screens:register("ending",{update=function() return true end})
screens:register("game",{update=function() return false end})

function App.update(dt) return Systems.gameplayUpdate.update(dt) end

function ui.resolveScreenUI(name)
    if name=="W" then return W elseif name=="H" then return H elseif name=="ui" then return ui elseif name=="colors" then return colors
    elseif name=="saveData" then return runtime.saveData elseif name=="exitPrompt" then return exitPrompt elseif name=="state" then return runtime.state
    elseif name=="scenery" then return scenery elseif name=="characters" then return characters elseif name=="characterScroll" then return characterScroll
    elseif name=="characterImages" then return characterImages elseif name=="mapScroll" then return mapScroll elseif name=="dialogue" then return dialogue
    elseif name=="questOffer" then return questOffer elseif name=="tradeNPC" then return tradeNPC elseif name=="editedItem" then return editedItem
    elseif name=="randomEvent" then return randomEvent elseif name=="animationClock" then return animationClock elseif name=="npcImages" then return npcImages
    elseif name=="screens" then return screens elseif name=="session" then return session elseif name=="Systems" then return Systems
    elseif name=="Save" then return Save elseif name=="Util" then return Util elseif name=="Catalog" then return Catalog
    elseif name=="Inventory" then return Inventory elseif name=="EventUI" then return EventUI elseif name=="Events" then return Events
    elseif name=="EngineUpgrades" then return EngineUpgrades elseif name=="writeSave" then return writeSave
    elseif name=="mobileControls" then return mobileControls
    elseif name=="screenToGame" then return screenToGame elseif name=="ensureStopLayout" then return ensureStopLayout end
end

function ui.assignScreenUI(name,value)
    if name=="exitPrompt" then exitPrompt=value elseif name=="state" then runtime.state=value
    elseif name=="characterScroll" then characterScroll=value elseif name=="mapScroll" then mapScroll=value
    else return false end
    return true
end

Systems.screenUI=Systems.screenUI.install(ui.resolveScreenUI,ui.assignScreenUI)



function ui.setInventoryState(name,value)
    if name=="draggedSlot" then draggedSlot=value elseif name=="inventoryDragActive" then inventoryDragActive=value
    elseif name=="giftOpen" then giftOpen=value elseif name=="giftSlot" then giftSlot=value
    elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="lastClick" then lastInventoryClick=value
    elseif name=="lastClickTime" then lastInventoryClickTime=value end
end

function ui.inventoryContext()
    return {data=runtime.saveData,activeChest=activeChest,chestOpen=chestOpen,inventoryOpen=inventoryOpen,draggedSlot=draggedSlot,inventoryDragActive=inventoryDragActive,
        giftOpen=giftOpen,giftNPC=giftNPC,giftSlot=giftSlot,lastClick=lastInventoryClick,lastClickTime=lastInventoryClickTime,nearNPC=nearNPC,nearPassenger=nearPassenger,
        ui=ui,Inventory=Inventory,Catalog=Catalog,colors=colors,mobileControls=mobileControls,pointIn=Util.pointIn,title=Util.titleFromFile,isWeapon=Systems.inventoryActions.isWeapon,
        drawMenuFrame=Systems.screenUI.drawMenuFrame,button=Systems.screenUI.button,pointer=function() return screenToGame(pointerPosition()) end,value=Systems.inventoryActions.containerValue,set=ui.setInventoryState,
        battleMode=runtime.state=="battle",move=Systems.inventoryActions.moveBetweenSlots,quickTransfer=Systems.inventoryActions.quickTransfer,collectAmmo=Systems.inventoryActions.collectAmmo,drop=runtime.state=="battle" and function() return false end or Systems.inventoryActions.dropFromContainer,
        consume=runtime.state=="battle" and Systems.inventoryActions.consumeBattleSelected or Systems.inventoryActions.consumeSelected}
end

function ui.drawInventory() Systems.inventory.draw(ui.inventoryContext()) end
function ui.drawChestInventory() Systems.inventory.drawChest(ui.inventoryContext()) end
function ui.drawItem(name,r) Systems.inventory.drawItem(ui.inventoryContext(),name,r) end




function ui.battleUIContext()
    return {
        W=W,H=H,battle=battle,battleZoom=battleZoom,scenery=scenery,colors=colors,mobileControls=mobileControls,
        characterImages=characterImages,npcImages=npcImages,mobImages=mobImages,
        characterWalkImages=characterWalkImages,npcWalkImages=npcWalkImages,
        mobAttackImages=mobAttackImages,mobIdleImages=mobIdleImages,mobHitImages=mobHitImages,
        mobDeathImages=mobDeathImages,mobWalkImages=mobWalkImages,mobRangedImages=mobRangedImages,
        animationClock=animationClock,characterAnimations=characterAnimations,
        saveData=runtime.saveData,inventoryOpen=inventoryOpen,ui=ui,
        drawLandscape=Systems.worldRenderer.drawLandscape,drawGround=Systems.worldRenderer.drawGround,
        drawAnimatedCharacter=Systems.worldRenderer.drawAnimatedCharacter,button=Systems.screenUI.button,screenToGame=screenToGame,pointerPosition=pointerPosition,
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
    elseif name=="backgroundImages" then return backgroundImages elseif name=="saveData" then return runtime.saveData
    elseif name=="landscapeOffset" then return landscapeOffset elseif name=="scenery" then return scenery
    elseif name=="sceneryOffset" then return sceneryOffset elseif name=="trainAnimationClock" then return trainAnimationClock
    elseif name=="animationClock" then return animationClock elseif name=="car" then return car
    elseif name=="colors" then return colors elseif name=="characterAnimations" then return characterAnimations
    elseif name=="characterImages" then return characterImages elseif name=="characterWalkImages" then return characterWalkImages
    elseif name=="characterActionImages" then return characterActionImages elseif name=="player" then return runtime.player
    elseif name=="actionTimer" then return actionTimer elseif name=="actionHeldItem" then return actionHeldItem
    elseif name=="actionKind" then return actionKind elseif name=="playerPose" then return playerPose
    elseif name=="ui" then return ui elseif name=="editMode" then return editMode
    elseif name=="editedItem" then return editedItem elseif name=="scene" then return runtime.scene
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
    if carTransition or runtime.scene~="train" then return false end
    local current=runtime.saveData.activeCar or 1
    targetIndex=math.max(1,math.min(#(runtime.saveData.trainCars or {}),targetIndex))
    if targetIndex==current then return false end
    local left,right,top,bottom=trainFloorBounds()
    carTransition={from=current,to=targetIndex,t=0,duration=.78,targetX=targetIndex>current and left or right,targetY=(top+bottom)/2}
    runtime.player.moving=false; nearbyItem=nil; nearChest=nil; nearCarNext=false; nearCarPrev=false
    ui.playSfx("trainDoor")
    return true
end

local function moveEditedItem(dx,dy)
    local item=editedItem and runtime.saveData.droppedItems[editedItem]; if not item then return end
    local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,item.x+dx)); item.y=math.max(top,math.min(bottom,item.y+dy)); writeSave()
end

local function resolveGameplayHUD(name)
    if name=="W" then return W elseif name=="H" then return H elseif name=="ui" then return ui
    elseif name=="scene" then return runtime.scene elseif name=="saveData" then return runtime.saveData elseif name=="player" then return runtime.player
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
    elseif name=="mobileControls" then return mobileControls
    elseif name=="Clouds" then return Clouds elseif name=="Maintenance" then return Maintenance
    elseif name=="Util" then return Util elseif name=="button" then return Systems.screenUI.button
    elseif name=="drawMenuFrame" then return Systems.screenUI.drawMenuFrame elseif name=="drawTrade" then return Systems.screenUI.drawTrade
    elseif name=="isFurnitureItem" then return isFurnitureItem elseif name=="containerValue" then return Systems.inventoryActions.containerValue
    elseif name=="screenToGame" then return screenToGame elseif name=="pointerPosition" then return pointerPosition elseif name=="drawLandscape" then return Systems.worldRenderer.drawLandscape
    elseif name=="drawTracks" then return Systems.worldRenderer.drawTracks elseif name=="drawTrainView" then return Systems.worldRenderer.drawTrainView
    elseif name=="drawHouse" then return Systems.worldRenderer.drawHouse elseif name=="drawStop" then return Systems.worldRenderer.drawStop end
end
Systems.gameplayHUD=Systems.gameplayHUD.install(resolveGameplayHUD)



screens:register("intro",{draw=function()
    local windowWidth,windowHeight=love.graphics.getDimensions()
    Systems.intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
end})
screens:register("slots",{draw=ui.drawSlots})
screens:register("characters",{draw=ui.drawCharacterSelect})
screens:register("battle",{draw=ui.drawTacticalBattle})
screens:register("event",{draw=ui.drawRandomEvent})
screens:register("ending",{draw=Systems.screenUI.drawEnding})
screens:register("game",{draw=function() if travelConfirm then ui.drawTravelConfirm() else Systems.gameplayHUD.draw() end end})

function App.draw()
    love.graphics.clear(0.025,0.02,0.025,1)
    if screens:is("intro") then screens:draw(); return end
    local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
    love.graphics.push()
    love.graphics.translate(offsetX,offsetY)
    love.graphics.scale(scaleX,scaleY)
    if runtime.state=="game" and not travelConfirm and not maintenanceSession.open and not ui.mobileMenuOpen and Camera:isActive() then
        local focusX,focusY=(runtime.player and runtime.player.x or W/2),(runtime.player and runtime.player.y or H/2)
        Camera:apply(focusX,focusY)
    end
    screens:draw()
    if exitPrompt then Systems.screenUI.drawExitPrompt() end
    love.graphics.pop()
    if mobileControls then mobileControls:draw(offsetX,offsetY,scaleX,scaleY) end
    if travelTransition then
        local t=travelTransition.t; local timing=EngineUpgrades.timings(runtime.saveData.engineLevel)
        local alpha=t<timing.change and math.max(0,math.min(1,(t-timing.fadeOut)/timing.fadeDuration)) or math.max(0,1-(t-timing.change)/timing.finishFade)
        local windowWidth,windowHeight=love.graphics.getDimensions()
        love.graphics.setColor(0,0,0,alpha)
        love.graphics.rectangle("fill",0,0,windowWidth,windowHeight)
    end
end

function ui.resolveGameplayInputState(name)
    if name=="W" then return W elseif name=="H" then return H elseif name=="ui" then return ui
    elseif name=="state" then return runtime.state elseif name=="saveData" then return runtime.saveData elseif name=="player" then return runtime.player
    elseif name=="scene" then return runtime.scene elseif name=="selectedSlot" then return runtime.selectedSlot elseif name=="characters" then return characters
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
    elseif name=="writeSave" then return writeSave elseif name=="screenToGame" then return screenToGame elseif name=="pointerPosition" then return pointerPosition
    elseif name=="isWeapon" then return Systems.inventoryActions.isWeapon elseif name=="isFurnitureItem" then return isFurnitureItem
    elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="ownsTrainCar" then return Systems.screenUI.ownsTrainCar
    elseif name=="moveEditedItem" then return moveEditedItem elseif name=="attackStopSludge" then return attackStopSludge
    elseif name=="acceptQuest" then return Systems.journeyRules.acceptQuest elseif name=="attemptLeaveTrain" then return Systems.journeyRules.attemptLeaveTrain
    elseif name=="travelCost" then return Systems.journeyRules.travelCost elseif name=="playTrainDepart" then return playTrainDepart
    elseif name=="trainFloorBounds" then return trainFloorBounds elseif name=="trainObjectBounds" then return trainObjectBounds elseif name=="newSave" then return Systems.sessionBootstrap.newSave
    elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="resolveEventChoice" then return resolveEventChoice
    elseif name=="enterStop" then return Systems.journeyRules.enterStop elseif name=="battleAttack" then return battleAttack
    elseif name=="battleHeal" then return battleHeal elseif name=="battleGuard" then return battleGuard
    elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="setBattlePrompt" then return setBattlePrompt
    elseif name=="beginCarTransition" then return beginCarTransition elseif name=="talkToNPC" then return Systems.journeyRules.talkToNPC
    elseif name=="ensureHouseItems" then return ensureHouseItems elseif name=="setupNPC" then return setupNPC
    elseif name=="giveWeaponToNearby" then return Systems.inventoryActions.giveWeaponToNearby elseif name=="pickUpNearby" then return Systems.inventoryActions.pickUpNearby
    elseif name=="addCoalToFire" then return Systems.inventoryActions.addCoalToFire elseif name=="requestExitPrompt" then return Systems.screenUI.requestExitPrompt
    elseif name=="resolveExitPrompt" then return Systems.screenUI.resolveExitPrompt end
end

function ui.resolveGameplayInput(name)
    local value=ui.resolveGameplayInputState(name)
    if value~=nil then return value end
    return ui.resolveGameplayInputServices(name)
end


function ui.assignGameplayInput(name,value)
    if name=="state" then runtime.state=value elseif name=="saveData" then runtime.saveData=value elseif name=="scene" then runtime.scene=value
    elseif name=="selectedSlot" then runtime.selectedSlot=value elseif name=="characterScroll" then characterScroll=value
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
function App.mousepressed(x,y,button,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousepressed(x,y,button,...)
end
function App.mousemoved(x,y,dx,dy,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousemoved(x,y,dx,dy,...)
end
function App.mousereleased(x,y,button,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousereleased(x,y,button,...)
end
function App.wheelmoved(...) return Systems.gameplayInput.wheelmoved(...) end
function App.keypressed(key,...)
    if key=="acback" then key="escape" end
    return Systems.gameplayInput.keypressed(key,...)
end
function App.keyreleased(...) return Systems.gameplayInput.keyreleased(...) end
function App.touchpressed(id,x,y) if mobileControls then return mobileControls:touchpressed(id,x,y) end end
function App.touchmoved(id,x,y,dx,dy) if mobileControls then return mobileControls:touchmoved(id,x,y,dx,dy) end end
function App.touchreleased(id,x,y) if mobileControls then return mobileControls:touchreleased(id,x,y) end end
function App.focus(focused)
    if not focused then
        if mobileControls then mobileControls:cancelAll() end
        writeSave(); Save.flush()
    end
end



function App.installSmoke()
if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    local smokeScope=setmetatable({}, {__index=function(_,name)
        if name=="state" then return session.screen elseif name=="selectedSlot" then return session.selectedSlot elseif name=="saveData" then return session.saveData elseif name=="characters" then return characters elseif name=="ui" then return ui elseif name=="scene" then return session.scene elseif name=="player" then return session.player elseif name=="inventoryOpen" then return inventoryOpen elseif name=="mapOpen" then return mapOpen elseif name=="mapScroll" then return mapScroll elseif name=="tradeOpen" then return tradeOpen elseif name=="trainUpgradeOpen" then return trainUpgradeOpen elseif name=="poseMenu" then return poseMenu elseif name=="randomEvent" then return randomEvent elseif name=="battle" then return battle elseif name=="travelTransition" then return travelTransition elseif name=="maintenanceSession" then return maintenanceSession elseif name=="draggedSlot" then return draggedSlot elseif name=="actionHeldItem" then return actionHeldItem elseif name=="actionTimer" then return actionTimer elseif name=="actionKind" then return actionKind elseif name=="travelConfirm" then return travelConfirm elseif name=="car" then return car elseif name=="dialogue" then return dialogue elseif name=="editMode" then return editMode elseif name=="carTransition" then return carTransition
        elseif name=="session" then return session elseif name=="runtime" then return runtime elseif name=="screens" then return screens elseif name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="Catalog" then return Catalog elseif name=="Assets" then return Assets elseif name=="Save" then return Save elseif name=="Maintenance" then return Maintenance elseif name=="Events" then return Events elseif name=="Systems" then return Systems elseif name=="mobileControls" then return mobileControls elseif name=="Camera" then return Camera
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return Systems.sessionBootstrap.newSave elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="setupNPC" then return setupNPC elseif name=="beginEncounter" then return beginEncounter elseif name=="consumeSelected" then return Systems.inventoryActions.consumeSelected elseif name=="resolveEventChoice" then return resolveEventChoice elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="battleAttack" then return battleAttack elseif name=="resolveBattleAttack" then return resolveBattleAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then runtime.state=value elseif name=="selectedSlot" then runtime.selectedSlot=value elseif name=="saveData" then runtime.saveData=value elseif name=="scene" then runtime.scene=value elseif name=="player" then runtime.player=value elseif name=="inventoryOpen" then inventoryOpen=value elseif name=="mapOpen" then mapOpen=value elseif name=="mapScroll" then mapScroll=value elseif name=="tradeOpen" then tradeOpen=value elseif name=="trainUpgradeOpen" then trainUpgradeOpen=value elseif name=="poseMenu" then poseMenu=value elseif name=="randomEvent" then randomEvent=value elseif name=="battle" then battle=value elseif name=="travelTransition" then travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then draggedSlot=value elseif name=="actionHeldItem" then actionHeldItem=value elseif name=="actionTimer" then actionTimer=value elseif name=="travelConfirm" then travelConfirm=value elseif name=="dialogue" then dialogue=value elseif name=="editMode" then editMode=value elseif name=="carTransition" then carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
end

function App.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); if ui.audio and ui.audio.shutdown then ui.audio:shutdown() end end

return App
