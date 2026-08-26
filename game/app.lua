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
local runtime = RuntimeState.new({
    session = session,
    transition = function(screen) screens:transition(screen) end,
})
local content=Systems.contentRegistry.new({filesystem=love.filesystem})
local characters=content.characters
local scenery,ui=content.scenery,content.ui
local maintenanceSession = Maintenance.new()


-- Rolling-stock layout: the car sits farther right to leave room for the
-- enlarged locomotive while retaining one shared rail/coupler baseline.
local car = Config.trainCar
local colors = Config.colors


Systems.screenFlow=Systems.screenFlow.new({
    runtime=runtime,
    ui=ui,
    screens=screens,
    intro=Systems.intro,
    scenery=scenery,
    colors=colors,
    updateBattle=function(...) return Systems.battleRuntime.update(...) end,
    drawBattle=function(...) return Systems.battleRuntime.draw(...) end,
    drawEnding=function(...) return Systems.screenUI.drawEnding(...) end,
    drawGameplay=function(...) return Systems.gameplayHUD.draw(...) end,
})
Systems.screenFlow.install()

local platform=Systems.platformComposition.new({
    persistenceRuntimeFactory=Systems.persistenceRuntime,audioRuntimeFactory=Systems.audioRuntime,
    trainCarRuntimeFactory=Systems.trainCarRuntime,presentationRuntimeFactory=Systems.presentationRuntime,
    mobileRuntimeFactory=Systems.mobileRuntime,runtime=runtime,ui=ui,session=session,save=Save,
    maintenance=Maintenance,maintenanceSession=maintenanceSession,catalog=Catalog,audio=Audio,
    scenery=scenery,car=car,train=Train,width=W,height=H,screens=screens,viewport=Viewport,camera=Camera,
    engineUpgrades=EngineUpgrades,mobileControls=MobileControls,
    drawExitPrompt=function(...) return Systems.screenUI.drawExitPrompt(...) end,
    getGameplayInput=function() return Systems.gameplayInput end,
})
Systems.persistenceRuntime,Systems.audioRuntime=platform.persistenceRuntime,platform.audioRuntime
Systems.trainCarRuntime,Systems.presentationRuntime=platform.trainCarRuntime,platform.presentationRuntime
Systems.mobileRuntime=platform.mobileRuntime

local world=Systems.worldSessionComposition.new({
    worldSceneFactory=Systems.worldScene,sessionBootstrapFactory=Systems.sessionBootstrap,
    platform=platform,content=content,runtime=runtime,ui=ui,car=car,maintenanceSession=maintenanceSession,
    filesystem=love.filesystem,saveSchema=SaveSchema,catalog=Catalog,util=Util,house=House,stops=Stops,
    family=Family,settlements=Settlements,wildlife=Wildlife,mice=Mice,stopSludges=StopSludges,
    roster=Roster,maintenance=Maintenance,engineUpgrades=EngineUpgrades,passengers=Passengers,events=Events,
    getIsWeapon=function() return Systems.inventoryActions.isWeapon end,
})
Systems.worldScene,Systems.sessionBootstrap=world.worldScene,world.sessionBootstrap
local adventure=Systems.adventureComposition.new({
    battleRuntimeFactory=Systems.battleRuntime,inventoryActionsFactory=Systems.inventoryActions,
    journeyRulesFactory=Systems.journeyRules,eventRuntimeFactory=Systems.eventRuntime,
    runtime=runtime,width=W,height=H,ui=ui,content=content,colors=colors,car=car,
    inventory=Inventory,catalog=Catalog,util=Util,battleRules=BattleRules,events=Events,
    battleController=BattleController,battleUI=Systems.battleUI,engineUpgrades=EngineUpgrades,
    maintenance=Maintenance,passengers=Passengers,house=House,eventUI=EventUI,
    writeSave=Systems.persistenceRuntime.schedule,screenToGame=Systems.presentationRuntime.screenToGame,
    pointerPosition=Systems.mobileRuntime.pointerPosition,mobileEnabled=Systems.mobileRuntime.isEnabled,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,setupNPC=Systems.worldScene.setupNPC,
    getCharacterAnimations=function() return Systems.startupRuntime.characterAnimations() end,
    getWorldRenderer=function() return Systems.worldRenderer end,getScreenUI=function() return Systems.screenUI end,
    handleInventoryClick=function(x,y) return Systems.inventoryPresenter.handleClick(x,y,ui.offerGift) end,
})
Systems.battleRuntime,Systems.inventoryActions=adventure.battleRuntime,adventure.inventoryActions
Systems.journeyRules,Systems.eventRuntime=adventure.journeyRules,adventure.eventRuntime

Systems.startupRuntime=Systems.startupRuntime.new({
    ui=ui,
    scenery=scenery,
    graphics=love.graphics,
    filesystem=love.filesystem,
    assets=Assets,
    settlements=Settlements,
    clouds=Clouds,
    assetStreamer=Systems.assetStreamer,
    gameplayUpdate=Systems.gameplayUpdate,
    initializeAudio=Systems.audioRuntime.initialize,
    initializeMobile=Systems.mobileRuntime.initialize,
    createIntro=function() return Systems.intro.new(10) end,
    assetTargets=content.assetTargets,
    legacyAnimationTables=content.legacyAnimationTables,
    gameplayContext={
        runtime=runtime,
        width=W,
        holdPickupSeconds=Config.holdPickupSeconds,
        ui=ui,
        car=car,
        scenery=scenery,
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
        updatePersistence=Systems.persistenceRuntime.update,
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
        writeSave=Systems.persistenceRuntime.schedule,
    },
})

function App.load() return Systems.startupRuntime.load() end

function App.update(dt) return Systems.startupRuntime.update(dt) end

local views=Systems.viewComposition.new({
    systems=Systems,runtime=runtime,width=W,height=H,ui=ui,colors=colors,content=content,car=car,
    maintenanceSession=maintenanceSession,holdPickupSeconds=Config.holdPickupSeconds,
    inventory=Inventory,catalog=Catalog,util=Util,eventUI=EventUI,engineUpgrades=EngineUpgrades,
    train=Train,characterAnimation=CharacterAnimation,family=Family,settlements=Settlements,stops=Stops,
    clouds=Clouds,maintenance=Maintenance,
})
Systems.screenUI,Systems.inventoryPresenter=views.screenUI,views.inventoryPresenter
Systems.worldRenderer,Systems.gameplayHUD=views.worldRenderer,views.gameplayHUD
function App.draw() return Systems.presentationRuntime.draw() end

local input=Systems.inputComposition.new({
    gameplayInputFactory=Systems.gameplayInput,runtime=runtime,ui=ui,content=content,
    maintenanceSession=maintenanceSession,platform=platform,adventure=adventure,views=views,
    worldScene=Systems.worldScene,sessionBootstrap=Systems.sessionBootstrap,
    inventory=Inventory,catalog=Catalog,util=Util,engineUpgrades=EngineUpgrades,maintenance=Maintenance,
    battleRules=BattleRules,stops=Stops,settlements=Settlements,interiorDoors=InteriorDoors,
    intro=Systems.intro,interactions=Systems.interactions,
})
Systems.gameplayInput=input.gameplayInput
function App.mousepressed(...) return Systems.mobileRuntime.mousepressed(...) end
function App.mousemoved(...) return Systems.mobileRuntime.mousemoved(...) end
function App.mousereleased(...) return Systems.mobileRuntime.mousereleased(...) end
function App.wheelmoved(...) return Systems.gameplayInput.wheelmoved(...) end
function App.keypressed(...) return Systems.mobileRuntime.keypressed(...) end
function App.keyreleased(...) return Systems.mobileRuntime.keyreleased(...) end
function App.touchpressed(...) return Systems.mobileRuntime.touchpressed(...) end
function App.touchmoved(...) return Systems.mobileRuntime.touchmoved(...) end
function App.touchreleased(...) return Systems.mobileRuntime.touchreleased(...) end
function App.focus(focused) return Systems.persistenceRuntime.focus(focused) end



function App.installSmoke()
    return SmokePlaythrough.install({
        runtime=runtime,ui=ui,characters=characters,maintenanceSession=maintenanceSession,session=session,screens=screens,car=car,
        currentSaveVersion=CURRENT_SAVE_VERSION,saveSchema=SaveSchema,catalog=Catalog,assets=Assets,save=Save,
        maintenance=Maintenance,events=Events,battleRules=BattleRules,presentationRuntime=Systems.presentationRuntime,
        startupRuntime=Systems.startupRuntime,persistenceRuntime=Systems.persistenceRuntime,screenFlow=Systems.screenFlow,
        contentRegistry=content,viewComposition=views,adventureComposition=adventure,platformComposition=platform,
        inputComposition=input,worldSessionComposition=world,
        getMobileControls=function() return Systems.mobileRuntime.get() end,
        createIntro=function() return Systems.intro.new(10) end,
        newSave=Systems.sessionBootstrap.newSave,enterGame=Systems.sessionBootstrap.enterGame,
        ensureStopLayout=Systems.worldScene.ensureStopLayout,setupNPC=Systems.worldScene.setupNPC,
        beginEncounter=Systems.battleRuntime.beginEncounter,consumeSelected=Systems.inventoryActions.consumeSelected,
        resolveEventChoice=Systems.eventRuntime.choose,advanceBattleTurn=Systems.battleRuntime.advanceTurn,
        battleAttack=Systems.battleRuntime.attack,resolveBattleAttack=Systems.battleRuntime.resolveAttack,
    })
end

function App.quit() Systems.persistenceRuntime.shutdown() end

return App
