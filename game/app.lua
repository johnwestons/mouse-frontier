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
local GameplayUpdate = Systems.gameplayUpdate
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
local cloudLayer
local characterWalkImages, npcWalkImages = {}, {}
local characterActionImages, mobAttackImages, mobIdleImages, mobHitImages = {}, {}, {}, {}
local familyImages, mobDeathImages, mobWalkImages, mobRangedImages = {}, {}, {}, {}
local itemIdleImages = {}
local characterAnimations = {}
local HOLD_PICKUP_SECONDS = Config.holdPickupSeconds
local maintenanceSession = Maintenance.new()


-- Rolling-stock layout: the car sits farther right to leave room for the
-- enlarged locomotive while retaining one shared rail/coupler baseline.
local car = Config.trainCar
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

Systems.worldScene=Systems.worldScene.new({
    runtime=runtime,
    ui=ui,
    scenery=scenery,
    catalog=Catalog,
    util=Util,
    house=House,
    stops=Stops,
    family=Family,
    settlements=Settlements,
    wildlife=Wildlife,
    mice=Mice,
    stopSludges=StopSludges,
    getIsWeapon=function() return Systems.inventoryActions.isWeapon end,
    isFurnitureItem=isFurnitureItem,
    writeSave=writeSave,
})

Systems.audioRuntime=Systems.audioRuntime.new({
    runtime=runtime,
    ui=ui,
    catalog=Catalog,
    audio=Audio,
})

Systems.trainCarRuntime=Systems.trainCarRuntime.new({
    runtime=runtime,
    ui=ui,
    scenery=scenery,
    car=car,
    train=Train,
    width=W,
    height=H,
    writeSave=writeSave,
})

Systems.presentationRuntime=Systems.presentationRuntime.new({
    runtime=runtime,
    ui=ui,
    screens=screens,
    maintenanceSession=maintenanceSession,
    viewport=Viewport,
    camera=Camera,
    engineUpgrades=EngineUpgrades,
    width=W,
    height=H,
    drawExitPrompt=function(...) return Systems.screenUI.drawExitPrompt(...) end,
    drawMobileControls=function(...) return Systems.mobileRuntime.draw(...) end,
})

Systems.mobileRuntime=Systems.mobileRuntime.new({
    runtime=runtime,
    ui=ui,
    maintenanceSession=maintenanceSession,
    mobileControls=MobileControls,
    width=W,
    height=H,
    viewportToGame=Systems.presentationRuntime.viewportToGame,
    getCameraZoom=Systems.presentationRuntime.getZoom,
    setCameraZoom=Systems.presentationRuntime.setZoom,
    endCameraPan=Systems.presentationRuntime.endPan,
    getGameplayInput=function() return Systems.gameplayInput end,
})

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
    settlements=Settlements,
    trainObjectBounds=Systems.trainCarRuntime.objectBounds,
    trainFloorBounds=Systems.trainCarRuntime.floorBounds,
    clampToTrainFloor=Systems.trainCarRuntime.clampToFloor,
    isFurnitureItem=isFurnitureItem,
    resetStopSludges=Systems.worldScene.resetStopSludges,
})
Systems.battleRuntime=Systems.battleRuntime.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    scenery=scenery,
    colors=colors,
    characterImages=characterImages,
    npcImages=npcImages,
    mobImages=mobImages,
    characterWalkImages=characterWalkImages,
    npcWalkImages=npcWalkImages,
    mobAttackImages=mobAttackImages,
    mobIdleImages=mobIdleImages,
    mobHitImages=mobHitImages,
    mobDeathImages=mobDeathImages,
    mobWalkImages=mobWalkImages,
    mobRangedImages=mobRangedImages,
    getCharacterAnimations=function() return characterAnimations end,
    mobileEnabled=Systems.mobileRuntime.isEnabled,
    getWorldRenderer=function() return Systems.worldRenderer end,
    getScreenUI=function() return Systems.screenUI end,
    catalog=Catalog,
    util=Util,
    battleRules=BattleRules,
    events=Events,
    battleController=BattleController,
    battleUI=Systems.battleUI,
    writeSave=writeSave,
    screenToGame=Systems.presentationRuntime.screenToGame,
    pointerPosition=Systems.mobileRuntime.pointerPosition,
    enterStop=function(...) return Systems.journeyRules.enterStop(...) end,
    handleInventoryClick=function(x,y) return Systems.inventoryPresenter.handleClick(x,y,ui.offerGift) end,
})

Systems.inventoryActions=Systems.inventoryActions.new({
    runtime=runtime,
    inventory=Inventory,
    catalog=Catalog,
    util=Util,
    writeSave=writeSave,
    useBattleHealingItem=Systems.battleRuntime.useHealingItem,
    useBattlePotion=Systems.battleRuntime.usePotion,
})
Systems.journeyRules=Systems.journeyRules.new({
    runtime=runtime,
    car=car,
    inventory=Inventory,
    catalog=Catalog,
    engineUpgrades=EngineUpgrades,
    maintenance=Maintenance,
    passengers=Passengers,
    util=Util,
    house=House,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    setupNPC=Systems.worldScene.setupNPC,
    writeSave=writeSave,
    beginEncounter=Systems.battleRuntime.beginEncounter,
    beginRequiredEvent=function(location) return Systems.eventRuntime.beginRequired(location) end,
    beginRandomEvent=function() return Systems.eventRuntime.beginRandom() end,
})

Systems.eventRuntime=Systems.eventRuntime.new({
    runtime=runtime,
    ui=ui,
    events=Events,
    eventUI=EventUI,
    catalog=Catalog,
    pointIn=Util.pointIn,
    writeSave=writeSave,
    beginEncounter=Systems.battleRuntime.beginEncounter,
    enterStop=Systems.journeyRules.enterStop,
})

function App.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setFont(love.graphics.newFont(16))
    Systems.audioRuntime.initialize()
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
    Systems.mobileRuntime.initialize()
    Systems.gameplayUpdate=GameplayUpdate.new({
        runtime=runtime,
        width=W,
        holdPickupSeconds=HOLD_PICKUP_SECONDS,
        ui=ui,
        car=car,
        scenery=scenery,
        cloudLayer=cloudLayer,
        maintenanceSession=maintenanceSession,
        mobileEnabled=Systems.mobileRuntime.isEnabled,
        mobileMovement=Systems.mobileRuntime.movement,
        mobileHeld=Systems.mobileRuntime.isHeld,
        mobileSprinting=Systems.mobileRuntime.isSprinting,
        interactionRouter=Systems.interactions,
        inventoryActions=Systems.inventoryActions,
        journeyRules=Systems.journeyRules,
        catalog=Catalog,
        settlements=Settlements,
        interiorDoors=InteriorDoors,
        interactions=Interactions,
        save=Save,
        clouds=Clouds,
        screens=screens,
        engineUpgrades=EngineUpgrades,
        maintenance=Maintenance,
        family=Family,
        util=Util,
        passengers=Passengers,
        screenToGame=Systems.presentationRuntime.screenToGame,
        updateAudio=Systems.audioRuntime.update,
        ensureStopLayout=Systems.worldScene.ensureStopLayout,
        updateWorldScene=Systems.worldScene.update,
        clampToTrainFloor=Systems.trainCarRuntime.clampToFloor,
        itemIsHere=Systems.worldScene.itemIsHere,
        setupNPC=Systems.worldScene.setupNPC,
        trainFloorBounds=Systems.trainCarRuntime.floorBounds,
        updateCarTransition=Systems.trainCarRuntime.updateTransition,
        writeSave=writeSave,
    })
end

screens:register("intro",{update=function(dt)
    if Systems.intro.update(ui.introCinematic,dt) then runtime.state="slots" end
    return true
end})
screens:register("slots",{update=function() return true end})
screens:register("characters",{update=function() return true end})
screens:register("battle",{update=Systems.battleRuntime.update})
screens:register("event",{update=function() return true end})
screens:register("ending",{update=function() return true end})
screens:register("game",{update=function() return false end})

function App.update(dt) return Systems.gameplayUpdate.update(dt) end

Systems.screenUI=Systems.screenUI.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    colors=colors,
    scenery=scenery,
    characters=characters,
    characterImages=characterImages,
    npcImages=npcImages,
    save=Save,
    util=Util,
    catalog=Catalog,
    inventory=Inventory,
    eventUI=EventUI,
    canChooseEvent=Systems.eventRuntime.canChoose,
    engineUpgrades=EngineUpgrades,
    writeSave=writeSave,
    screenToGame=Systems.presentationRuntime.screenToGame,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    mobileEnabled=Systems.mobileRuntime.isEnabled,
    drawLandscape=function(...) return Systems.worldRenderer.drawLandscape(...) end,
    drawTracks=function(...) return Systems.worldRenderer.drawTracks(...) end,
    drawLocomotive=function(...) return Systems.worldRenderer.drawLocomotive(...) end,
    drawTrainCar=function(...) return Systems.worldRenderer.drawTrainCar(...) end,
    isWeapon=Systems.inventoryActions.isWeapon,
    travelCost=Systems.journeyRules.travelCost,
})

Systems.inventoryPresenter=Systems.inventoryPresenter.new({
    runtime=runtime,
    ui=ui,
    inventoryUI=Systems.inventory,
    inventory=Inventory,
    catalog=Catalog,
    colors=colors,
    mobileEnabled=Systems.mobileRuntime.isEnabled,
    pointIn=Util.pointIn,
    title=Util.titleFromFile,
    isWeapon=Systems.inventoryActions.isWeapon,
    drawMenuFrame=Systems.screenUI.drawMenuFrame,
    button=Systems.screenUI.button,
    pointer=function() return Systems.presentationRuntime.screenToGame(Systems.mobileRuntime.pointerPosition()) end,
    value=Systems.inventoryActions.containerValue,
    move=Systems.inventoryActions.moveBetweenSlots,
    quickTransfer=Systems.inventoryActions.quickTransfer,
    collectAmmo=Systems.inventoryActions.collectAmmo,
    drop=Systems.inventoryActions.dropFromContainer,
    consume=Systems.inventoryActions.consumeSelected,
    consumeBattle=Systems.inventoryActions.consumeBattleSelected,
})

Systems.worldRenderer=Systems.worldRenderer.new({
    runtime=runtime,
    width=W,
    height=H,
    backgroundImages=backgroundImages,
    scenery=scenery,
    car=car,
    colors=colors,
    getCharacterAnimations=function() return characterAnimations end,
    characterImages=characterImages,
    characterWalkImages=characterWalkImages,
    characterActionImages=characterActionImages,
    itemIdleImages=itemIdleImages,
    npcImages=npcImages,
    npcWalkImages=npcWalkImages,
    familyImages=familyImages,
    mobImages=mobImages,
    mobIdleImages=mobIdleImages,
    mobWalkImages=mobWalkImages,
    mobHitImages=mobHitImages,
    mobDeathImages=mobDeathImages,
    drawStopSludges=Systems.worldScene.drawStopSludges,
    drawWildlife=Systems.worldScene.drawWildlife,
    train=Train,
    characterAnimation=CharacterAnimation,
    catalog=Catalog,
    family=Family,
    settlements=Settlements,
    stops=Stops,
    util=Util,
    ui=ui,
    itemIsHere=Systems.worldScene.itemIsHere,
    pendingMailHere=Systems.journeyRules.pendingMailHere,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
})


Systems.gameplayHUD=Systems.gameplayHUD.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    colors=colors,
    maintenanceSession=maintenanceSession,
    holdPickupSeconds=HOLD_PICKUP_SECONDS,
    getCloudLayer=function() return cloudLayer end,
    mobileEnabled=Systems.mobileRuntime.isEnabled,
    engineUpgrades=EngineUpgrades,
    clouds=Clouds,
    maintenance=Maintenance,
    util=Util,
    button=Systems.screenUI.button,
    drawMenuFrame=Systems.screenUI.drawMenuFrame,
    drawTrade=Systems.screenUI.drawTrade,
    isFurnitureItem=isFurnitureItem,
    containerValue=Systems.inventoryActions.containerValue,
    screenToGame=Systems.presentationRuntime.screenToGame,
    pointerPosition=Systems.mobileRuntime.pointerPosition,
    getAudioStatus=Systems.audioRuntime.status,
    drawLandscape=Systems.worldRenderer.drawLandscape,
    drawTracks=Systems.worldRenderer.drawTracks,
    drawTrainView=Systems.worldRenderer.drawTrainView,
    drawHouse=Systems.worldRenderer.drawHouse,
    drawStop=Systems.worldRenderer.drawStop,
})



screens:register("intro",{draw=function(windowWidth,windowHeight)
    Systems.intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
end})
screens:register("slots",{draw=ui.drawSlots})
screens:register("characters",{draw=ui.drawCharacterSelect})
screens:register("battle",{draw=Systems.battleRuntime.draw})
screens:register("event",{draw=ui.drawRandomEvent})
screens:register("ending",{draw=Systems.screenUI.drawEnding})
screens:register("game",{draw=function() if runtime.travelConfirm then ui.drawTravelConfirm() else Systems.gameplayHUD.draw() end end})

function App.draw() return Systems.presentationRuntime.draw() end

Systems.gameplayInput=Systems.gameplayInput.new({
    runtime=runtime,
    ui=ui,
    characters=characters,
    maintenanceSession=maintenanceSession,
    scenery=scenery,
    systems=Systems,
    inventory=Inventory,
    catalog=Catalog,
    util=Util,
    save=Save,
    engineUpgrades=EngineUpgrades,
    maintenance=Maintenance,
    battleRules=BattleRules,
    stops=Stops,
    settlements=Settlements,
    interiorDoors=InteriorDoors,
    writeSave=writeSave,
    screenToGame=Systems.presentationRuntime.screenToGame,
    viewportToGame=Systems.presentationRuntime.viewportToGame,
    cameraPanning=Systems.presentationRuntime.isPanning,
    beginCameraPan=Systems.presentationRuntime.beginPan,
    moveCameraPan=Systems.presentationRuntime.movePan,
    endCameraPan=Systems.presentationRuntime.endPan,
    zoomCamera=Systems.presentationRuntime.wheel,
    pointerPosition=Systems.mobileRuntime.pointerPosition,
    isWeapon=Systems.inventoryActions.isWeapon,
    isFurnitureItem=isFurnitureItem,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    ownsTrainCar=Systems.screenUI.ownsTrainCar,
    moveEditedItem=Systems.trainCarRuntime.moveEditedItem,
    attackStopSludge=Systems.worldScene.attackStopSludge,
    acceptQuest=Systems.journeyRules.acceptQuest,
    attemptLeaveTrain=Systems.journeyRules.attemptLeaveTrain,
    travelCost=Systems.journeyRules.travelCost,
    playTrainDepart=Systems.audioRuntime.playTrainDepart,
    audioResetMusic=Systems.audioRuntime.resetMusic,
    audioPreviousTrack=Systems.audioRuntime.previousTrack,
    audioTogglePause=Systems.audioRuntime.togglePause,
    audioNextTrack=Systems.audioRuntime.nextTrack,
    audioToggleMute=Systems.audioRuntime.toggleMute,
    enterTrain=Systems.trainCarRuntime.enterTrain,
    placeEditedItem=Systems.trainCarRuntime.placeEditedItem,
    newSave=Systems.sessionBootstrap.newSave,
    enterGame=Systems.sessionBootstrap.enterGame,
    chooseEvent=Systems.eventRuntime.choose,
    handleEventClick=Systems.eventRuntime.handleClick,
    enterStop=Systems.journeyRules.enterStop,
    handleBattleMouse=Systems.battleRuntime.handleMouse,
    battleAttack=Systems.battleRuntime.attack,
    battleHeal=Systems.battleRuntime.heal,
    battleGuard=Systems.battleRuntime.guard,
    advanceBattleTurn=Systems.battleRuntime.advanceTurn,
    setBattlePrompt=Systems.battleRuntime.setPrompt,
    beginCarTransition=Systems.trainCarRuntime.beginTransition,
    talkToNPC=Systems.journeyRules.talkToNPC,
    ensureHouseItems=Systems.worldScene.ensureHouseItems,
    setupNPC=Systems.worldScene.setupNPC,
    giveWeaponToNearby=Systems.inventoryActions.giveWeaponToNearby,
    pickUpNearby=Systems.inventoryActions.pickUpNearby,
    addCoalToFire=Systems.inventoryActions.addCoalToFire,
    handleInventoryClick=Systems.inventoryPresenter.handleClick,
    handleInventoryRelease=Systems.inventoryPresenter.handleRelease,
    requestExitPrompt=Systems.screenUI.requestExitPrompt,
    resolveExitPrompt=Systems.screenUI.resolveExitPrompt,
})
function App.mousepressed(...) return Systems.mobileRuntime.mousepressed(...) end
function App.mousemoved(...) return Systems.mobileRuntime.mousemoved(...) end
function App.mousereleased(...) return Systems.mobileRuntime.mousereleased(...) end
function App.wheelmoved(...) return Systems.gameplayInput.wheelmoved(...) end
function App.keypressed(...) return Systems.mobileRuntime.keypressed(...) end
function App.keyreleased(...) return Systems.mobileRuntime.keyreleased(...) end
function App.touchpressed(...) return Systems.mobileRuntime.touchpressed(...) end
function App.touchmoved(...) return Systems.mobileRuntime.touchmoved(...) end
function App.touchreleased(...) return Systems.mobileRuntime.touchreleased(...) end
function App.focus(focused)
    Systems.mobileRuntime.focus(focused)
    if not focused then
        writeSave(); Save.flush()
    end
end



function App.installSmoke()
if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    local smokeScope=setmetatable({}, {__index=function(_,name)
        if name=="state" then return session.screen elseif name=="selectedSlot" then return session.selectedSlot elseif name=="saveData" then return session.saveData elseif name=="characters" then return characters elseif name=="ui" then return ui elseif name=="scene" then return session.scene elseif name=="player" then return session.player elseif name=="inventoryOpen" then return runtime.inventoryOpen elseif name=="mapOpen" then return runtime.mapOpen elseif name=="mapScroll" then return runtime.mapScroll elseif name=="tradeOpen" then return runtime.tradeOpen elseif name=="trainUpgradeOpen" then return runtime.trainUpgradeOpen elseif name=="poseMenu" then return runtime.poseMenu elseif name=="randomEvent" then return runtime.randomEvent elseif name=="battle" then return runtime.battle elseif name=="travelTransition" then return runtime.travelTransition elseif name=="maintenanceSession" then return maintenanceSession elseif name=="draggedSlot" then return runtime.draggedSlot elseif name=="actionHeldItem" then return runtime.actionHeldItem elseif name=="actionTimer" then return runtime.actionTimer elseif name=="actionKind" then return runtime.actionKind elseif name=="travelConfirm" then return runtime.travelConfirm elseif name=="car" then return car elseif name=="dialogue" then return runtime.dialogue elseif name=="editMode" then return runtime.editMode elseif name=="carTransition" then return runtime.carTransition
        elseif name=="session" then return session elseif name=="runtime" then return runtime elseif name=="screens" then return screens elseif name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="SaveSchema" then return SaveSchema elseif name=="Catalog" then return Catalog elseif name=="Assets" then return Assets elseif name=="Save" then return Save elseif name=="Maintenance" then return Maintenance elseif name=="Events" then return Events elseif name=="Systems" then return Systems elseif name=="mobileControls" then return Systems.mobileRuntime.get() elseif name=="presentationRuntime" then return Systems.presentationRuntime
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return Systems.sessionBootstrap.newSave elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="ensureStopLayout" then return Systems.worldScene.ensureStopLayout elseif name=="setupNPC" then return Systems.worldScene.setupNPC elseif name=="beginEncounter" then return Systems.battleRuntime.beginEncounter elseif name=="consumeSelected" then return Systems.inventoryActions.consumeSelected elseif name=="resolveEventChoice" then return Systems.eventRuntime.choose elseif name=="advanceBattleTurn" then return Systems.battleRuntime.advanceTurn elseif name=="battleAttack" then return Systems.battleRuntime.attack elseif name=="resolveBattleAttack" then return Systems.battleRuntime.resolveAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then runtime.state=value elseif name=="selectedSlot" then runtime.selectedSlot=value elseif name=="saveData" then runtime.saveData=value elseif name=="scene" then runtime.scene=value elseif name=="player" then runtime.player=value elseif name=="inventoryOpen" then runtime.inventoryOpen=value elseif name=="mapOpen" then runtime.mapOpen=value elseif name=="mapScroll" then runtime.mapScroll=value elseif name=="tradeOpen" then runtime.tradeOpen=value elseif name=="trainUpgradeOpen" then runtime.trainUpgradeOpen=value elseif name=="poseMenu" then runtime.poseMenu=value elseif name=="randomEvent" then runtime.randomEvent=value elseif name=="battle" then runtime.battle=value elseif name=="travelTransition" then runtime.travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then runtime.draggedSlot=value elseif name=="actionHeldItem" then runtime.actionHeldItem=value elseif name=="actionTimer" then runtime.actionTimer=value elseif name=="travelConfirm" then runtime.travelConfirm=value elseif name=="dialogue" then runtime.dialogue=value elseif name=="editMode" then runtime.editMode=value elseif name=="carTransition" then runtime.carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
end

function App.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); Systems.audioRuntime.shutdown() end

return App
