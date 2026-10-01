local WorldGesture=require("game.world_gesture")
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
local UIStyle = require("game.ui_layout")

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
  local controlBindings=Modules.controlBindings.new(Filesystem)
  controlBindings:installKeyboardQuery()
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
    maintenance=Maintenance,maintenanceSession=maintenanceSession,catalog=Catalog,audio=Audio,audioCatalog=Modules.audioCatalog,
    scenery=scenery,car=car,train=Train,width=W,height=H,screens=screens,viewport=Viewport,camera=Camera,
    engineUpgrades=EngineUpgrades,mobileControls=MobileControls,
    drawExitPrompt=function(...) return services.screenUI.drawExitPrompt(...) end,
    getGameplayInput=function() return services.gameplayInput end,
    getWorldOffset=function()
      if runtime.scene=="expedition" and services.worldScene and services.worldScene.expeditionCameraOffset then
        return services.worldScene.expeditionCameraOffset()
      end
      return 0,0
    end,
  })
  serviceRegistry.publishAll(platform)

  local world=Modules.worldSessionComposition.new({
    worldSceneFactory=Modules.worldScene,sessionBootstrapFactory=Modules.sessionBootstrap,
    platform=platform,content=content,runtime=runtime,ui=ui,car=car,maintenanceSession=maintenanceSession,
    filesystem=Filesystem,saveSchema=SaveSchema,catalog=Catalog,util=Util,house=House,stops=Stops,
    family=Family,settlements=Settlements,wildlife=Wildlife,mice=Mice,stopSludges=StopSludges,
    shootingRange=Modules.shootingRange,
    expeditionAreas=Modules.expeditionAreas,expeditionRuntime=Modules.expeditionRuntime,roamingMobs=Modules.roamingMobs,
    crowCaravans=Modules.crowCaravans,crowCaravanArea=Modules.crowCaravanArea,
    roster=Roster,maintenance=Maintenance,engineUpgrades=EngineUpgrades,passengers=Passengers,events=Events,
    playerProgression=Modules.playerProgression,
    stopHelpProgression=Modules.stopHelpProgression,
    npcRelationships=Modules.npcRelationships,
    getIsWeapon=function() return services.inventoryActions.isWeapon end,
    getBeginEncounter=function() return services.battleRuntime and services.battleRuntime.beginEncounter end,
    width=W,height=H,
  })
  serviceRegistry.publishAll(world)

  local adventure=Modules.adventureComposition.new({
    battleRuntimeFactory=Modules.battleRuntime,inventoryActionsFactory=Modules.inventoryActions,
    journeyRulesFactory=Modules.journeyRules,eventRuntimeFactory=Modules.eventRuntime,
    runtime=runtime,width=W,height=H,ui=ui,content=content,colors=colors,car=car,
    inventory=Inventory,catalog=Catalog,util=Util,battleRules=BattleRules,events=Events,
    battleGrid=Modules.battleGrid,
    battleController=BattleController,battleUI=Modules.battleUI,engineUpgrades=EngineUpgrades,
    combatBalance=Modules.combatBalance,
    eventBalance=Modules.eventBalance,
    trainUpgradeBalance=Modules.trainUpgradeBalance,
    lootProgression=Modules.lootProgression,
    questProgression=Modules.questProgression,
    playerProgression=Modules.playerProgression,
    stopHelpProgression=Modules.stopHelpProgression,helpQuestSession=Modules.helpQuestSession,helpDialogueQuests=Modules.helpDialogueQuests,npcRelationships=Modules.npcRelationships,firstAid=Modules.firstAid,
    progressionBalance=Modules.progressionBalance,
    maintenance=Maintenance,passengers=Passengers,house=House,eventUI=EventUI,
    writeSave=platform.persistenceRuntime.schedule,screenToGame=platform.presentationRuntime.screenToGame,
    pointerPosition=platform.mobileRuntime.pointerPosition,mobileEnabled=platform.mobileRuntime.isEnabled,
    ensureStopLayout=world.worldScene.ensureStopLayout,setupNPC=world.worldScene.setupNPC,
    getCharacterAnimations=function() return services.startupRuntime.characterAnimations() end,
    getWorldRenderer=function() return services.worldRenderer end,
    getScreenUI=function() return services.screenUI end,
    handleInventoryClick=function(x,y) return services.inventoryPresenter.handleClick(x,y,ui.offerGift) end,
    returnToTrain=platform.trainCarRuntime.enterTrain,
  })
  serviceRegistry.publishAll(adventure)

  local startup=Modules.startupComposition.new({
    startupRuntimeFactory=Modules.startupRuntime,assetStreamer=Modules.assetStreamer,
    gameplayUpdate=Modules.gameplayUpdate,platform=platform,adventure=adventure,world=world,content=content,
    runtime=runtime,width=W,holdPickupSeconds=Config.holdPickupSeconds,ui=ui,car=car,landscape=Config.landscape,
    maintenanceSession=maintenanceSession,screens=screens,graphics=Graphics,filesystem=Filesystem,
    assets=Assets,settlements=Settlements,clouds=Clouds,intro=Modules.intro,
    interactionRouter=Modules.interactions,interactions=Interactions,catalog=Catalog,interiorDoors=InteriorDoors,
    engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,maintenance=Maintenance,family=Family,util=Util,passengers=Passengers,
    firstAid=Modules.firstAid,shootingRange=Modules.shootingRange,
    controlBindings=controlBindings,
  })
  serviceRegistry.publishAll(startup)

  local lastStand=Modules.lastStandQuest.new({
    runtime=runtime,catalog=Catalog,writeSave=platform.persistenceRuntime.schedule,
    characterImages=content.characterImages,characterWalkImages=content.characterWalkImages,
    getCharacterAnimations=function() return startup.startupRuntime.characterAnimations() end,
    mobileMovement=platform.mobileRuntime.movement,mobileSprinting=platform.mobileRuntime.isSprinting,
    mobileEnabled=platform.mobileRuntime.isEnabled,
    scenery=content.scenery,npcImages=content.npcImages,
    ui=ui,maintenanceSession=maintenanceSession,width=W,height=H,
    controlBindings=controlBindings,
  })

  local views=Modules.viewComposition.new({
    screenUIFactory=Modules.screenUI,inventoryPresenterFactory=Modules.inventoryPresenter,
    worldRendererFactory=Modules.worldRenderer,gameplayHUDFactory=Modules.gameplayHUD,inventoryUI=Modules.inventory,
    platform=platform,adventure=adventure,world=world,startup=startup,
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,content=content,car=car,landscape=Config.landscape,
    maintenanceSession=maintenanceSession,holdPickupSeconds=Config.holdPickupSeconds,
    inventory=Inventory,catalog=Catalog,util=Util,eventUI=EventUI,engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,
    playerProgression=Modules.playerProgression,
    stopHelpProgression=Modules.stopHelpProgression,npcRelationships=Modules.npcRelationships,merchantTrade=Modules.merchantTrade,finaleProgression=Modules.finaleProgression,firstAid=Modules.firstAid,shootingRange=Modules.shootingRange,
    train=Train,characterAnimation=CharacterAnimation,family=Family,settlements=Settlements,stops=Stops,
    clouds=Clouds,maintenance=Maintenance,lastStand=lastStand,
    controlBindings=controlBindings,
  })
  serviceRegistry.publishAll(views)

  local input=Modules.inputComposition.new({
    gameplayInputFactory=Modules.gameplayInput,runtime=runtime,ui=ui,content=content,
    maintenanceSession=maintenanceSession,platform=platform,adventure=adventure,views=views,
    worldScene=world.worldScene,sessionBootstrap=world.sessionBootstrap,
    inventory=Inventory,catalog=Catalog,npcRelationships=Modules.npcRelationships,merchantTrade=Modules.merchantTrade,util=Util,engineUpgrades=EngineUpgrades,trainUpgradeBalance=Modules.trainUpgradeBalance,maintenance=Maintenance,
    battleRules=BattleRules,stops=Stops,settlements=Settlements,interiorDoors=InteriorDoors,
    firstAid=Modules.firstAid,shootingRange=Modules.shootingRange,resolveFirstAid=adventure.journeyRules.resolveFirstAid,chooseHelpDialogue=adventure.journeyRules.chooseHelpDialogue,
    finaleProgression=Modules.finaleProgression,
    controlBindings=controlBindings,
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
    domain={currentSaveVersion=SaveSchema.CURRENT_VERSION,saveSchema=SaveSchema,catalog=Catalog,roster=Roster,npcRelationships=Modules.npcRelationships,accessibility=Modules.accessibility,
      assets=Assets,save=Save,maintenance=Maintenance,train=Train,events=Events,battleRules=BattleRules,intro=Modules.intro,firstAid=Modules.firstAid,
      audio=Audio,audioCatalog=Modules.audioCatalog,audioSelfTest=Modules.audioSelfTest,
      finaleProgression=Modules.finaleProgression,stopHelpProgression=Modules.stopHelpProgression,helpQuestSession=Modules.helpQuestSession,helpDialogueQuests=Modules.helpDialogueQuests,
      shootingRange=Modules.shootingRange,
      crowCaravans=Modules.crowCaravans,crowCaravanArea=Modules.crowCaravanArea,merchantTrade=Modules.merchantTrade},
    services=services,
    graphs={content=content,views=views,adventure=adventure,platform=platform,input=input,
      world=world,startup=startup,serviceRegistry=serviceRegistry,applicationComposition=application},
  })

  function application.load() return services.startupRuntime.load() end
  local function lastStandPoint(x,y)
    if type(x)~="number" or type(y)~="number" then return x,y end
    x,y=platform.presentationRuntime.screenToGame(x,y)
    return UIStyle.inversePoint(x,y,"lastStand",{x=0,y=0,w=W,h=H})
  end
  local function globalMenuActive()
    return type(runtime.pendingConfirmation)=="table" or runtime.exitPrompt~=nil or ui.escMenuOpen==true or ui.optionsOpen==true
  end

  function application.update(dt)
    if globalMenuActive() then
      platform.persistenceRuntime.update(dt)
      platform.audioRuntime.update()
      return true
    end
    if lastStand:update(dt) then
      local quest=runtime.lastStand
      if quest and quest.capture and quest.mode~="offer" then
        if ui.assetStreamer then ui.assetStreamer:update(runtime.state,"lastStand",runtime.saveData,nil,nil) end
        if content.backgroundImages.release then content.backgroundImages:release() end
        Assets.releaseDormantSceneArt(scenery,runtime)
      end
      platform.persistenceRuntime.update(dt)
      return true
    end
    return services.startupRuntime.update(dt)
  end
  function application.draw() return services.presentationRuntime.draw() end
  local function lastStandWalkControls()
    local quest=runtime.lastStand
    return quest and quest.capture and (quest.mode=="backyard" or quest.mode=="interior")
  end
  function application.mousepressed(x,y,button,istouch,presses)
    if globalMenuActive() then
      if istouch then return true end
      return services.gameplayInput.mousepressed(x,y,button,istouch,presses)
    end
    if button==3 then return services.gameplayInput.mousepressed(x,y,button,istouch,presses) end
    if istouch and lastStand:isCapturing() then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:mousepressed(gx,gy,button,istouch,presses) then return true end
    return services.mobileRuntime.mousepressed(x,y,button,istouch,presses)
  end
  function application.mousemoved(x,y,dx,dy,istouch)
    if globalMenuActive() then return true end
    if platform.presentationRuntime.isPanning() then return services.gameplayInput.mousemoved(x,y,dx,dy,istouch) end
    if istouch and lastStand:isCapturing() then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:mousemoved(gx,gy,dx,dy,istouch) then return true end
    return services.mobileRuntime.mousemoved(x,y,dx,dy,istouch)
  end
  function application.mousereleased(x,y,button,istouch,presses)
    if globalMenuActive() then return true end
    if button==3 then return services.gameplayInput.mousereleased(x,y,button,istouch,presses) end
    if istouch and lastStand:isCapturing() then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:mousereleased(gx,gy,button,istouch,presses) then return true end
    return services.mobileRuntime.mousereleased(x,y,button,istouch,presses)
  end
  function application.wheelmoved(x,y)
    if globalMenuActive() then
      if ui.optionsOpen and runtime.optionsPage=="controls" then return services.gameplayInput.wheelmoved(x,y) end
      return true
    end
    return services.gameplayInput.wheelmoved(x,y)
  end
  function application.keypressed(key,scancode,isrepeat)
    if controlBindings:isCapturing() then
      if key=="escape" or key=="acback" then controlBindings:cancelCapture()
      elseif controlBindings.capture.device=="key" then controlBindings:captureKey(key) end
      return true
    end
    local knownKey
    key,knownKey=controlBindings:translateKey(key)
    if knownKey and not key then return true end
    if key=="escape" or key=="acback" then
      return services.mobileRuntime.keypressed(key,scancode,isrepeat)
    end
    if globalMenuActive() then return services.gameplayInput.keypressed(key) end
    if key=="=" or key=="+" or key=="kp+" or key=="-" or key=="kp-" or key=="0" or key=="kp0" then
      return services.gameplayInput.keypressed(key)
    end
    if lastStand:keypressed(key,scancode,isrepeat) then return true end
    return services.mobileRuntime.keypressed(key,scancode,isrepeat)
  end
  function application.keyreleased(key,scancode)
    local knownKey
    key,knownKey=controlBindings:translateKey(key)
    if knownKey and not key then return true end
    if lastStand:keyreleased(key,scancode) then return true end
    return services.mobileRuntime.keyreleased(key,scancode)
  end
  local function controllerScope()
    local state=runtime.state
    if globalMenuActive() then return "menu" end
    if state=="battle" and not runtime.inventoryOpen then return "battle" end
    if state~="game" or runtime.inventoryOpen or runtime.mapOpen or runtime.tradeOpen
        or runtime.trainUpgradeOpen or runtime.travelConfirm or runtime.helpDialogue or runtime.dialogue
        or runtime.battle or runtime.shootingRange or runtime.firstAid or runtime.journeyLogOpen
        or runtime.encounter or ui.mobileMenuOpen or maintenanceSession.open then return "menu" end
    return "game"
  end
  function application.gamepadpressed(joystick,button)
    if controlBindings:isCapturing() then
      if controlBindings.capture.device=="button" then controlBindings:captureButton(button); return true end
      return true
    end
    if lastStand:isCapturing() then return true end
    local key=controlBindings:translateButton(button,controllerScope())
    if key then services.gameplayInput.keypressed(key); return true end
    return false
  end
  function application.gamepadreleased(joystick,button)
    if lastStand:isCapturing() then return true end
    return false
  end
  function application.gamepadaxis(joystick,axis,value)
    if controlBindings:isCapturing() then
      if controlBindings.capture.device=="axis" then controlBindings:captureAxis(axis,value); return true end
      return true
    end
    return false
  end
  local globalMenuTouches={}
  local function sceneTouchpressed(id,x,y,dx,dy,pressure)
    if lastStandWalkControls() and services.mobileRuntime.movementTouchPressed(id,x,y) then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:touchpressed(id,gx,gy) then return true end
    return services.mobileRuntime.touchpressed(id,x,y,dx,dy,pressure)
  end
  local function sceneTouchmoved(id,x,y,dx,dy,pressure)
    if services.mobileRuntime.movementTouchMoved(id,x,y) then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:touchmoved(id,gx,gy) then return true end
    return services.mobileRuntime.touchmoved(id,x,y,dx,dy,pressure)
  end
  local function sceneTouchreleased(id,x,y,dx,dy,pressure)
    if services.mobileRuntime.movementTouchReleased(id) then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:touchreleased(id,gx,gy) then return true end
    return services.mobileRuntime.touchreleased(id,x,y,dx,dy,pressure)
  end
  local sceneGesture=WorldGesture.new({
    field=function(x,y)
      local gx,gy=lastStandPoint(x,y)
      if lastStand:isCapturing() then return lastStand:zoomField(gx,gy) end
      local range=runtime.shootingRange
      if range and range.phase=="play" and gy>=96 and gy<592 then return range,true end
    end,
    getZoom=platform.presentationRuntime.getZoom,setZoom=platform.presentationRuntime.setZoom,
    beginPan=platform.presentationRuntime.beginPan,movePan=platform.presentationRuntime.movePan,
    endPan=platform.presentationRuntime.endPan,
    press=sceneTouchpressed,move=sceneTouchmoved,release=sceneTouchreleased,
  })
  function application.touchpressed(id,x,y,dx,dy,pressure)
    if globalMenuActive() then
      globalMenuTouches[id]=true
      return services.gameplayInput.mousepressed(x,y,1)
    end
    -- Claim Last Stand's movement stick before the shared camera gesture layer
    -- can pair it with an action touch and reinterpret both as a pinch.
    if lastStandWalkControls() and services.mobileRuntime.movementTouchPressed(id,x,y) then return true end
    if sceneGesture:pressed(id,x,y) then return true end
    return sceneTouchpressed(id,x,y,dx,dy,pressure)
  end
  function application.touchmoved(id,x,y,dx,dy,pressure)
    if globalMenuTouches[id] then return true end
    if sceneGesture:moved(id,x,y,dx,dy) then return true end
    return sceneTouchmoved(id,x,y,dx,dy,pressure)
  end
  function application.touchreleased(id,x,y,dx,dy,pressure)
    if globalMenuTouches[id] then globalMenuTouches[id]=nil; return true end
    if sceneGesture:released(id,x,y) then return true end
    return sceneTouchreleased(id,x,y,dx,dy,pressure)
  end
  function application.focus(focused)
    if not focused then sceneGesture:cancel() end
    lastStand:focus(focused)
    return services.persistenceRuntime.focus(focused)
  end
  function application.installSmoke() return smoke.install() end
  function application.quit() services.persistenceRuntime.shutdown() end
  return require("game.player_tools_host").wrap(application,{
    runtime=runtime,ui=ui,filesystem=Filesystem,mobile=platform.mobileRuntime,
    presentation=platform.presentationRuntime,persistence=platform.persistenceRuntime,
  })
end

return {new=new}
