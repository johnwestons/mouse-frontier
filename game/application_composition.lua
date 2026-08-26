local Config = require("game.config")
local SaveSchema = require("game.save_schema")
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
local Clouds = require("game.clouds")
local Maintenance = require("game.maintenance")
local MobileControls = require("game.mobile_controls")
local Modules = require("game.systems")

local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"application composition requires "..name)
  if expected then assert(type(value)==expected,"application composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","application composition requires an explicit context")
  local Engine=required(context,"engine","table")
  local Graphics=required(Engine,"graphics","table")
  local Filesystem=required(Engine,"filesystem","table")
  local W,H=Config.baseWidth,Config.baseHeight
  local car,colors=Config.trainCar,Config.colors
  local serviceRegistry=Modules.serviceRegistry.new(Modules)
  local services=serviceRegistry.services
  local session=Modules.session.new()
  local screens=Modules.screens.new(session)
  local runtime=RuntimeState.new({session=session,transition=function(screen) screens:transition(screen) end})
  local content=Modules.contentRegistry.new({filesystem=Filesystem})
  local scenery,ui=content.scenery,content.ui
  local maintenanceSession=Maintenance.new()

  services.screenFlow=serviceRegistry.publish("screenFlow",Modules.screenFlow.new({
    runtime=runtime,ui=ui,screens=screens,intro=Modules.intro,scenery=scenery,colors=colors,
    updateBattle=function(...) return services.battleRuntime.update(...) end,
    drawBattle=function(...) return services.battleRuntime.draw(...) end,
    drawEnding=function(...) return services.screenUI.drawEnding(...) end,
    drawGameplay=function(...) return services.gameplayHUD.draw(...) end,
  }))
  services.screenFlow.install()

  local platform=Modules.platformComposition.new({
    persistenceRuntimeFactory=Modules.persistenceRuntime,audioRuntimeFactory=Modules.audioRuntime,
    trainCarRuntimeFactory=Modules.trainCarRuntime,presentationRuntimeFactory=Modules.presentationRuntime,
    mobileRuntimeFactory=Modules.mobileRuntime,runtime=runtime,ui=ui,session=session,save=Save,
    maintenance=Maintenance,maintenanceSession=maintenanceSession,catalog=Catalog,audio=Audio,
    scenery=scenery,car=car,train=Train,width=W,height=H,screens=screens,viewport=Viewport,camera=Camera,
    engineUpgrades=EngineUpgrades,mobileControls=MobileControls,
    drawExitPrompt=function(...) return services.screenUI.drawExitPrompt(...) end,
    getGameplayInput=function() return services.gameplayInput end,
  })
  serviceRegistry.publishAll(platform)

  local world=Modules.worldSessionComposition.new({
    worldSceneFactory=Modules.worldScene,sessionBootstrapFactory=Modules.sessionBootstrap,
    platform=platform,content=content,runtime=runtime,ui=ui,car=car,maintenanceSession=maintenanceSession,
    filesystem=Filesystem,saveSchema=SaveSchema,catalog=Catalog,util=Util,house=House,stops=Stops,
    family=Family,settlements=Settlements,wildlife=Wildlife,mice=Mice,stopSludges=StopSludges,
    roster=Roster,maintenance=Maintenance,engineUpgrades=EngineUpgrades,passengers=Passengers,events=Events,
    getIsWeapon=function() return services.inventoryActions.isWeapon end,
  })
  serviceRegistry.publishAll(world)

  local adventure=Modules.adventureComposition.new({
    battleRuntimeFactory=Modules.battleRuntime,inventoryActionsFactory=Modules.inventoryActions,
    journeyRulesFactory=Modules.journeyRules,eventRuntimeFactory=Modules.eventRuntime,
    runtime=runtime,width=W,height=H,ui=ui,content=content,colors=colors,car=car,
    inventory=Inventory,catalog=Catalog,util=Util,battleRules=BattleRules,events=Events,
    battleController=BattleController,battleUI=Modules.battleUI,engineUpgrades=EngineUpgrades,
    combatBalance=Modules.combatBalance,
    eventBalance=Modules.eventBalance,
    trainUpgradeBalance=Modules.trainUpgradeBalance,
    lootProgression=Modules.lootProgression,
    progressionBalance=Modules.progressionBalance,
    maintenance=Maintenance,passengers=Passengers,house=House,eventUI=EventUI,
    writeSave=platform.persistenceRuntime.schedule,screenToGame=platform.presentationRuntime.screenToGame,
    pointerPosition=platform.mobileRuntime.pointerPosition,mobileEnabled=platform.mobileRuntime.isEnabled,
    ensureStopLayout=world.worldScene.ensureStopLayout,setupNPC=world.worldScene.setupNPC,
    getCharacterAnimations=function() return services.startupRuntime.characterAnimations() end,
    getWorldRenderer=function() return services.worldRenderer end,
    getScreenUI=function() return services.screenUI end,
    handleInventoryClick=function(x,y) return services.inventoryPresenter.handleClick(x,y,ui.offerGift) end,
  })
  serviceRegistry.publishAll(adventure)

  local startup=Modules.startupComposition.new({
    startupRuntimeFactory=Modules.startupRuntime,assetStreamer=Modules.assetStreamer,
    gameplayUpdate=Modules.gameplayUpdate,platform=platform,adventure=adventure,world=world,content=content,
    runtime=runtime,width=W,holdPickupSeconds=Config.holdPickupSeconds,ui=ui,car=car,
    maintenanceSession=maintenanceSession,screens=screens,graphics=Graphics,filesystem=Filesystem,
    assets=Assets,settlements=Settlements,clouds=Clouds,intro=Modules.intro,
    interactionRouter=Modules.interactions,interactions=Interactions,catalog=Catalog,interiorDoors=InteriorDoors,
    engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,maintenance=Maintenance,family=Family,util=Util,passengers=Passengers,
  })
  serviceRegistry.publishAll(startup)

  local views=Modules.viewComposition.new({
    screenUIFactory=Modules.screenUI,inventoryPresenterFactory=Modules.inventoryPresenter,
    worldRendererFactory=Modules.worldRenderer,gameplayHUDFactory=Modules.gameplayHUD,inventoryUI=Modules.inventory,
    platform=platform,adventure=adventure,world=world,startup=startup,
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,content=content,car=car,
    maintenanceSession=maintenanceSession,holdPickupSeconds=Config.holdPickupSeconds,
    inventory=Inventory,catalog=Catalog,util=Util,eventUI=EventUI,engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,
    train=Train,characterAnimation=CharacterAnimation,family=Family,settlements=Settlements,stops=Stops,
    clouds=Clouds,maintenance=Maintenance,
  })
  serviceRegistry.publishAll(views)

  local input=Modules.inputComposition.new({
    gameplayInputFactory=Modules.gameplayInput,runtime=runtime,ui=ui,content=content,
    maintenanceSession=maintenanceSession,platform=platform,adventure=adventure,views=views,
    worldScene=world.worldScene,sessionBootstrap=world.sessionBootstrap,
    inventory=Inventory,catalog=Catalog,util=Util,engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,maintenance=Maintenance,
    battleRules=BattleRules,stops=Stops,settlements=Settlements,interiorDoors=InteriorDoors,
    intro=Modules.intro,interactions=Modules.interactions,
  })
  serviceRegistry.publishAll(input)

  local smoke
  local application={}
  function application.status()
    local registryStatus=serviceRegistry.status()
    local compositions={platform,world,adventure,startup,views,input,smoke}
    local ready=registryStatus.immutable and registryStatus.separated and registryStatus.serviceCount==18
    for _,composition in ipairs(compositions) do ready=ready and composition.status().ready end
    return {ready=ready,compositionCount=#compositions,serviceCount=registryStatus.serviceCount}
  end

  smoke=Modules.smokeComposition.new({
    playthrough=Modules.smokePlaythrough,
    state={runtime=runtime,ui=ui,characters=content.characters,maintenanceSession=maintenanceSession,
      session=session,screens=screens,car=car},
    domain={currentSaveVersion=SaveSchema.CURRENT_VERSION,saveSchema=SaveSchema,catalog=Catalog,
      assets=Assets,save=Save,maintenance=Maintenance,events=Events,battleRules=BattleRules,intro=Modules.intro},
    services=services,
    graphs={content=content,views=views,adventure=adventure,platform=platform,input=input,
      world=world,startup=startup,serviceRegistry=serviceRegistry,applicationComposition=application},
  })

  function application.load() return services.startupRuntime.load() end
  function application.update(dt) return services.startupRuntime.update(dt) end
  function application.draw() return services.presentationRuntime.draw() end
  function application.mousepressed(...) return services.mobileRuntime.mousepressed(...) end
  function application.mousemoved(...) return services.mobileRuntime.mousemoved(...) end
  function application.mousereleased(...) return services.mobileRuntime.mousereleased(...) end
  function application.wheelmoved(...) return services.gameplayInput.wheelmoved(...) end
  function application.keypressed(...) return services.mobileRuntime.keypressed(...) end
  function application.keyreleased(...) return services.mobileRuntime.keyreleased(...) end
  function application.touchpressed(...) return services.mobileRuntime.touchpressed(...) end
  function application.touchmoved(...) return services.mobileRuntime.touchmoved(...) end
  function application.touchreleased(...) return services.mobileRuntime.touchreleased(...) end
  function application.focus(focused) return services.persistenceRuntime.focus(focused) end
  function application.installSmoke() return smoke.install() end
  function application.quit() services.persistenceRuntime.shutdown() end
  return application
end

return {new=new}
