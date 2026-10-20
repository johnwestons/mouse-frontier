local WorldGesture=require("game.world_gesture")
local WorldPause=require("game.world_pause")
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
local TrainAmbush = require("game.train_ambush")
local CoopInventoryRuntime = require("game.coop_inventory_runtime")

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
  ui.localPreferences=require("game.local_preferences").new(Filesystem)
  ui.menuSettings=ui.localPreferences.menu
  local maintenanceSession=Maintenance.new()
  local trainAmbush,lastStand
  services.screenFlow=serviceRegistry.publish("screenFlow",Modules.screenFlow.new({
    runtime=runtime,ui=ui,screens=screens,intro=Modules.intro,scenery=scenery,colors=colors,
    updateBattle=function(...) return services.battleRuntime.update(...) end,
    drawBattle=function(...) return services.battleRuntime.draw(...) end,
    drawEnding=function(...) return services.screenUI.drawEnding(...) end,
    drawGameplay=function(...)
      if trainAmbush and trainAmbush:draw() then return end
      return services.gameplayHUD.draw(...)
    end,
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

  local coopCommands
  local world=Modules.worldSessionComposition.new({
    worldSceneFactory=Modules.worldScene,sessionBootstrapFactory=Modules.sessionBootstrap,
    platform=platform,content=content,runtime=runtime,ui=ui,car=car,maintenanceSession=maintenanceSession,
    filesystem=Filesystem,saveSchema=SaveSchema,catalog=Catalog,util=Util,house=House,stops=Stops,
    family=Family,settlements=Settlements,wildlife=Wildlife,mice=Mice,stopSludges=StopSludges,
    shootingRange=Modules.shootingRange,
    rangeCommands=function(name,args) return coopCommands and coopCommands.submit(name,args) end,
    rangeView=function(id) return coopCommands and coopCommands.rangeView(id) end,
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

  coopCommands=CoopInventoryRuntime.new({runtime=runtime,session=session,catalog=Catalog,car=car,maintenanceSession=maintenanceSession,
    poseActorState=function(id)
      if id~='host' then return {} end
      local player=runtime.player
      local stopped=runtime.poseMenu or not player
      return {moving=player and player.moving==true or false,inputX=stopped and 0 or runtime.coopPoseInputX or 0,
        inputY=stopped and 0 or runtime.coopPoseInputY or 0,
        actionBusy=(runtime.actionTimer or 0)>0 and runtime.actionKind~='use'}
    end,
    rangeState=function(id)
      local paused=WorldPause.isSimulationPaused(runtime,ui,maintenanceSession)
      if id=='host' then
        local rangeStatus=world.worldScene.rangeCommandState and world.worldScene.rangeCommandState()
        if rangeStatus then rangeStatus.paused=rangeStatus.paused or paused end
        return rangeStatus
      end
      local lp=ui.localPlay
      return {active=runtime.scene=='stop',paused=paused,ready=id=='host' or lp and lp.motion
        and lp.motion.generation and lp.motion.readyEpoch==lp.motion.epoch}
    end,
    ambushState=function(id) return trainAmbush and trainAmbush:commandState(id) end,
    lastStandPhase=function(id) return lastStand and lastStand.positionCommandState and lastStand:positionCommandState(id) end,
    lastStandState=function(id)
      local shootingState=lastStand and lastStand:commandState(id)
      if id~='companion' then return shootingState end
      local lp=ui.localPlay; local data=runtime.saveData; local motion=lp and lp.motion
      local position=coopCommands and coopCommands.lastStandPosition and coopCommands.lastStandPosition(id)
      if not shootingState or not position or not lp or lp.campaign~=data or not lp.authority or not motion or not motion.generation
          or lp.authority.bindings.companion~=motion.generation or motion.readyEpoch~=motion.epoch
          or motion.domain~=require('game.coop_last_stand_lifecycle').key(data) then return nil end
      return shootingState
    end,
    lastStandScene=function() return lastStand and lastStand:progressionState() end,
    clock=function() return Engine.timer.getTime() end,
    checkpoint=platform.persistenceRuntime.checkpointCampaign,
    scene={interiorFiles=function() return scenery.interiorFiles end,isFurniture=content.isFurnitureItem,
      carArrival=function(data,id,index,forward)
        local image=(scenery.trainCarImages or {})[data.trainCars[index]]
        local left,right,top,bottom=Train.characterBounds(car,image,30)
        return Train.clampCharacterToFloor(car,image,forward and left or right,(top+bottom)/2,30)
      end,
      trainSpawn=function(data,id)
        local actor=data.players[id]; local image=(scenery.trainCarImages or {})[data.trainCars[actor.activeCar]]
        local left,right,top,bottom=Train.characterBounds(car,image,30)
        return math.min((left+right)/2-48,W-56),(top+bottom)/2
      end,
      trainClamp=function(data,id,x,y)
        local actor=data.players[id]; local image=(scenery.trainCarImages or {})[data.trainCars[actor.activeCar]]
        return Train.clampCharacterToFloor(car,image,x,y,30)
      end},
    applyParty=function(result,name) return ui.applyPartyState(result,name) end,
    applyCar=function(result) return platform.trainCarRuntime.acceptTransition(result) end,
    fieldState=world.worldScene.fieldState,applyField=world.worldScene.presentFieldAttack,
    applyExpedition=world.worldScene.presentExpeditionAssistance})
  ui.expeditionAssist=function(selected)
    local data=runtime.saveData; local areaId=selected.areaId or data.activeExpeditionArea
    if selected.action=='survey' then return coopCommands.submit('expedition.survey',{areaId=areaId,markerId=selected.markerId}) end
    local chest=data.expeditions[areaId].chests[selected.chestId]
    return coopCommands.submit('expedition.cache',{areaId=areaId,containerId=chest and chest.entityId})
  end
  ui.roamingAttack=function(x,y)
    local name=require('game.coop_roaming').weapon(runtime.saveData,'host',Catalog)
    local reply=coopCommands.submit('roaming.attack',{areaId=runtime.saveData.activeExpeditionArea,weaponId=name,targetX=x,targetY=y})
    return reply.ok,reply.reason
  end
  ui.roamingPressure=function(definition)
    local data=runtime.saveData; local mob=data.expeditions[data.activeExpeditionArea].mobs[definition.id]
    local reply=coopCommands.submit('roaming.pressure',{areaId=data.activeExpeditionArea,leadId=mob.entityId})
    return reply.ok==true
  end
  ui.changeCar=function(index) return coopCommands.submit('player.car',{car=index}) end
  ui.coopPoseMovement=function(x,y) runtime.coopPoseInputX,runtime.coopPoseInputY=x,y end
  ui.coopPlayerPresentation=function()
    if not WorldPause.isSharedHost(runtime) then return runtime end
    return require('game.coop_player_pose').presentation(coopCommands.poseState('host'),runtime)
  end
  require("game.coop_scene_runtime").install({runtime=runtime,ui=ui,commands=coopCommands,catalog=Catalog,
    applyScene=world.worldScene.acceptParty,
    closeMaintenance=function() if maintenanceSession.open then Maintenance.close(maintenanceSession) end end,
    neutralize=function() platform.mobileRuntime.focus(false); platform.presentationRuntime.endPan() end})
  require("game.coop_decoration_runtime").install({runtime=runtime,ui=ui,commands=coopCommands})
  maintenanceSession.commands=function(name,args,campaign)
    if runtime.saveData~=campaign then return {ok=false,reason="wrong_campaign"} end
    return coopCommands.submit(name,args)
  end
  local adventure=Modules.adventureComposition.new({
    inventoryCommands=coopCommands,
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
  ui.pauseFirstAid=function() return adventure.journeyRules.resolveFirstAid("cancelled") end

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

  lastStand=Modules.lastStandQuest.new({
    hostSavedJourneyPending=function()
      local lp=ui.localPlay
      return lp and lp.hostingIntent~=nil and lp.network==nil or false
    end,
    positionStatus=function(id) return coopCommands.lastStandPosition(id) end,
    globalSimulationBlocked=function()
      return runtime.session and runtime.session.checkpointPending or runtime.state~='game' or runtime.scene~='stop'
        or runtime.battle~=nil and runtime.battle~=false or runtime.saveData and not not runtime.saveData.roamingEncounter
        or runtime.saveData and runtime.saveData.coop and not not runtime.saveData.coop.journey or false
    end,
    participants=function()
      local lp=ui.localPlay
      if not lp or lp.phase~='hosting' then return {'host'} end
      local ids={}; local data=runtime.saveData
      local host=lastStand and lastStand:commandState('host')
      if host and host.active and not host.paused and coopCommands.lastStandPosition('host') then ids[#ids+1]='host' end
      local motion=lp.motion; local guest=lastStand and lastStand:commandState('companion')
      if guest and guest.active and not guest.paused and lp.campaign==data and lp.authority and motion and motion.generation
          and lp.authority.bindings.companion==motion.generation and motion.readyEpoch==motion.epoch
          and motion.domain==require('game.coop_last_stand_lifecycle').key(data)
          and coopCommands.lastStandPosition('companion') then ids[#ids+1]='companion' end
      return ids
    end,
    companionSceneActor=function()
      local lp=ui.localPlay; local motion=lp and lp.motion
      if not motion or not motion.generation or not motion.actor or not require('game.coop_last_stand_lifecycle').walking(runtime.saveData) then return nil end
      if motion.domain~=require('game.coop_last_stand_lifecycle').key(runtime.saveData) then return nil end
      local actor=runtime.saveData.players.companion
      return {player=motion.actor,visual={image=content.characterImages[actor.character],character=actor.character,
        animations=startup.startupRuntime.characterAnimations(),walkImage=content.characterWalkImages[actor.character],clock=runtime.animationClock or 0}}
    end,
    submit=function(name,args) return coopCommands.submit(name,args) end,
    inputPaused=function()
      local lp=ui.localPlay
      return runtime.exitPrompt~=nil or type(runtime.pendingConfirmation)=='table' or ui.escMenuOpen==true or ui.optionsOpen==true or ui.playerToolsOpen==true
        or lp and (lp.menuOpen or lp.focused==false) or false
    end,
    runtime=runtime,catalog=Catalog,writeSave=platform.persistenceRuntime.schedule,
    characterImages=content.characterImages,characterWalkImages=content.characterWalkImages,
    getCharacterAnimations=function() return startup.startupRuntime.characterAnimations() end,
    mobileMovement=platform.mobileRuntime.movement,mobileSprinting=platform.mobileRuntime.isSprinting,
    mobileEnabled=platform.mobileRuntime.isEnabled,
    scenery=content.scenery,npcImages=content.npcImages,
    ui=ui,maintenanceSession=maintenanceSession,width=W,height=H,
    controlBindings=controlBindings,
  })

  trainAmbush=TrainAmbush.new({
    mobileEnabled=platform.mobileRuntime.isEnabled,
    runtime=runtime,catalog=Catalog,width=W,height=H,controlBindings=controlBindings,
    writeSave=platform.persistenceRuntime.schedule,enterStop=adventure.journeyRules.enterStop,
    submit=function(name,args) return coopCommands.submit(name,args) end,
    checkpointSettlement=function()
      local authority=coopCommands.authority()
      local saved=authority and authority:checkpointNow()
      coopCommands.checkpointStatus()
      return saved==true
    end,
    checkpointPending=function() return coopCommands.checkpointStatus().pending end,
    inputPaused=function()
      local lp=ui.localPlay
      return runtime.exitPrompt~=nil or type(runtime.pendingConfirmation)=='table' or ui.escMenuOpen==true or ui.optionsOpen==true or ui.playerToolsOpen==true
        or lp and (lp.menuOpen or lp.focused==false) or false
    end,
    participants=function()
      local ids={'host'}; local lp=ui.localPlay; local motion=lp and lp.motion
      if lp and lp.campaign==runtime.saveData and lp.authority and motion and motion.generation
          and lp.authority.bindings.companion==motion.generation and motion.readyEpoch==runtime.saveData.coop.sceneEpoch then
        ids[#ids+1]='companion'
      end
      return ids
    end,
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
    commands=coopCommands,
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
    ui.updateDecoration()
    platform.mobileRuntime.update(dt)
    if WorldPause.isSharedHost(runtime) and not WorldPause.isSimulationPaused(runtime,ui,maintenanceSession) then
      coopCommands.advanceRange(dt)
    end
    if globalMenuActive() then
      trainAmbush:suspend()
      if WorldPause.isSharedHost(runtime) and trainAmbush:update(dt) then
        platform.persistenceRuntime.update(dt); platform.audioRuntime.update(); return true
      end
      if WorldPause.isSharedHost(runtime) and not WorldPause.isSimulationPaused(runtime,ui,maintenanceSession) then
        return services.startupRuntime.update(dt)
      end
      platform.persistenceRuntime.update(dt)
      platform.audioRuntime.update()
      return true
    end
    if trainAmbush:update(dt) then
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
    if trainAmbush:isCapturing() then
      local ax,ay=platform.presentationRuntime.screenToGame(x,y)
      return trainAmbush:mousepressed(ax,ay,button,istouch)
    end
    if button==3 then return services.gameplayInput.mousepressed(x,y,button,istouch,presses) end
    if istouch and lastStand:isCapturing() then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:mousepressed(gx,gy,button,istouch,presses) then return true end
    return services.mobileRuntime.mousepressed(x,y,button,istouch,presses)
  end
  function application.mousemoved(x,y,dx,dy,istouch)
    if globalMenuActive() then return true end
    if trainAmbush:isCapturing() then
      local ax,ay=platform.presentationRuntime.screenToGame(x,y)
      return trainAmbush:mousemoved(ax,ay,dx,dy,istouch)
    end
    if platform.presentationRuntime.isPanning() then return services.gameplayInput.mousemoved(x,y,dx,dy,istouch) end
    if istouch and lastStand:isCapturing() then return true end
    local gx,gy=lastStandPoint(x,y)
    if lastStand:mousemoved(gx,gy,dx,dy,istouch) then return true end
    return services.mobileRuntime.mousemoved(x,y,dx,dy,istouch)
  end
  function application.mousereleased(x,y,button,istouch,presses)
    if trainAmbush:isCapturing() then return trainAmbush:mousereleased(x,y,button) end
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
    if trainAmbush:isCapturing() then return true end
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
      if not globalMenuActive() and lastStand:isCapturing() then return lastStand:keypressed('escape',scancode,isrepeat) end
      trainAmbush:suspend()
      return services.mobileRuntime.keypressed(key,scancode,isrepeat)
    end
    if globalMenuActive() then return services.gameplayInput.keypressed(key) end
    if trainAmbush:keypressed(key,scancode,isrepeat) then return true end
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
    if trainAmbush:keyreleased(key,scancode) then return true end
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
    if not globalMenuActive() and trainAmbush:gamepadpressed(joystick,button) then return true end
    if lastStand:isCapturing() then return true end
    local key=controlBindings:translateButton(button,controllerScope())
    if key then services.gameplayInput.keypressed(key); return true end
    return false
  end
  function application.gamepadreleased(joystick,button)
    if trainAmbush:gamepadreleased(joystick,button) then return true end
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
      if platform.mobileRuntime.shooterControlAt(x,y) then return nil end
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
    if trainAmbush:isCapturing() then
      local ax,ay=platform.presentationRuntime.screenToGame(x,y)
      return trainAmbush:touchpressed(id,ax,ay)
    end
    -- Claim Last Stand's movement stick before the shared camera gesture layer
    -- can pair it with an action touch and reinterpret both as a pinch.
    if lastStandWalkControls() and services.mobileRuntime.movementTouchPressed(id,x,y) then return true end
    if sceneGesture:pressed(id,x,y) then return true end
    return sceneTouchpressed(id,x,y,dx,dy,pressure)
  end
  function application.touchmoved(id,x,y,dx,dy,pressure)
    if globalMenuTouches[id] then return true end
    if trainAmbush:isCapturing() then
      local ax,ay=platform.presentationRuntime.screenToGame(x,y)
      return trainAmbush:touchmoved(id,ax,ay)
    end
    if sceneGesture:moved(id,x,y,dx,dy) then return true end
    return sceneTouchmoved(id,x,y,dx,dy,pressure)
  end
  function application.touchreleased(id,x,y,dx,dy,pressure)
    if globalMenuTouches[id] then globalMenuTouches[id]=nil; return true end
    if trainAmbush:touchreleased(id) then return true end
    if sceneGesture:released(id,x,y) then return true end
    return sceneTouchreleased(id,x,y,dx,dy,pressure)
  end
  function application.focus(focused)
    if not focused then sceneGesture:cancel() end
    trainAmbush:focus(focused)
    lastStand:focus(focused)
    return services.persistenceRuntime.focus(focused)
  end
  function application.installSmoke() return smoke.install() end
  function application.quit() services.persistenceRuntime.shutdown() end
  application=require("game.outfit_workbench_host").wrap(application,{
    runtime=runtime,ui=ui,mobile=platform.mobileRuntime,presentation=platform.presentationRuntime,
    persistence=platform.persistenceRuntime,audio=platform.audioRuntime,bindings=controlBindings,
    maintenanceSession=maintenanceSession,commands=coopCommands,
  })
  application=require('game.coop_roaming_host').wrap(application,{
    runtime=runtime,ui=ui,commands=coopCommands,screenToGame=platform.presentationRuntime.screenToGame,
    battleEntered=function() runtime.battle=require('game.tactical_battle_state').restore(runtime.saveData,Catalog) end,
    neutralize=function()
      platform.mobileRuntime.focus(false); platform.presentationRuntime.endPan()
      if runtime.player then runtime.player.velocityX=0; runtime.player.velocityY=0; runtime.player.moving=false end
      if ui.suspendOutfitWorkbench then ui.suspendOutfitWorkbench() end
      if ui.cancelWeaponRepair then ui.cancelWeaponRepair() end
      if ui.closeDecoration then ui.closeDecoration() end
      if ui.pauseFirstAid then ui.pauseFirstAid() end
      if maintenanceSession.open then Maintenance.close(maintenanceSession) end
    end,
  })
  application=require("game.coop_checkpoint_host").wrap(application,{
    runtime=runtime,ui=ui,commands=coopCommands,audio=platform.audioRuntime,bindings=controlBindings,
    screenToGame=platform.presentationRuntime.screenToGame,
    requestQuit=function() love.event.quit() end,
    neutralize=function()
      platform.mobileRuntime.focus(false); platform.presentationRuntime.endPan(); trainAmbush:suspend()
      if ui.suspendOutfitWorkbench then ui.suspendOutfitWorkbench() end
      if ui.cancelWeaponRepair then ui.cancelWeaponRepair() end
      if ui.closeDecoration then ui.closeDecoration() end
      if ui.pauseFirstAid then ui.pauseFirstAid() end
      if maintenanceSession.open then Maintenance.close(maintenanceSession) end
    end,
  })
  local coopCollision=require("game.coop_collision").new({car=car,scenery=scenery})
  local localPlay=require("game.coop_local_play").new({
    runtime=runtime,session=session,commands=coopCommands,filesystem=Filesystem,catalog=Catalog,
    onStop=function() if world.worldScene.closeSharedRange then world.worldScene.closeSharedRange() end end,
    localPlayPreferences=ui.localPreferences:localPlay(),
    saveLocalPlayPreferences=function(value) return ui.localPreferences:setLocalPlay(value) end,
    clock=function() return Engine.timer.getTime() end,
    characters=function() return content.characters end,
    managementState=function() return {activityBlocked=maintenanceSession.open==true} end,
    roaming=function()
      return world.worldScene.fieldState(),require('game.world_pause').isSimulationPaused(runtime,ui) or (runtime.expeditionGraceTimer or 0)>0
    end,
    lastStandEffects=function() return lastStand and lastStand.effectState and lastStand:effectState() end,
    lastStandStage=function() return lastStand and lastStand.stageState and lastStand:stageState() end,
    createGuestView=function(controller)
      return require("game.coop_guest_view").new({content=content,ui=ui,catalog=Catalog,colors=colors,car=car,
        preferences=ui.localPreferences,audio=platform.audioRuntime,bindings=controlBindings,filesystem=Filesystem,mobileEnabled=platform.mobileRuntime.isEnabled,
        drawMenuFrame=views.screenUI.drawMenuFrame,
        characterAnimations=startup.startupRuntime.characterAnimations,
        move=coopCollision,clock=function() return Engine.timer.getTime() end,
        createWorldRenderer=views.worldRenderer.createView,
        rangeAssets=function() return scenery.shootingRangeAssets or {} end,
        prepareCharacters=function(players)
          for _,actor in pairs(players) do
            local animations=startup.startupRuntime.characterAnimations()[actor.character]
            assert(content.characterImages[actor.character],"missing guest traveler art")
          end
        end},controller)
    end,
    prepareCompanion=function(actor)
      -- Finish lazy character loads before the peer receives its ready receipt.
      -- A first on-screen draw must not stall input service to load this art.
      local animations=startup.startupRuntime.characterAnimations()[actor.character]
      return content.characterImages[actor.character]~=nil
    end,
    movement={
      presentation=function(id) return coopCommands.poseState(id) end,
      domain=function() return require('game.coop_last_stand_lifecycle').key(runtime.saveData) end,
      position=function(id)
        local data=runtime.saveData; local Life=require('game.coop_last_stand_lifecycle')
        if Life.walking(data) then Life.ensure(data) end
        local pose=Life.pose(data,id)
        return pose and {playerX=pose.x,playerY=pose.y,playerFacing=pose.facing} or data.players[id]
      end,
      store=function(actor)
        local pose=require('game.coop_last_stand_lifecycle').pose(runtime.saveData,'companion')
        if pose then pose.x,pose.y,pose.facing=actor.x,actor.y,actor.facing
        else local record=runtime.saveData.players.companion; record.playerX,record.playerY,record.playerFacing=actor.x,actor.y,actor.facing end
      end,
      hostActor=function() return lastStand:movementActor() or runtime.player end,
      allowed=function()
        return runtime.state=="game" and not runtime.travelTransition and not runtime.battle
          and not runtime.saveData.roamingEncounter
          and not coopCommands.carBusy('companion')
          and not coopCommands.activityBusy('companion','lastStandAid')
          and not coopCommands.activityBusy('companion','range')
          and (not require('game.coop_last_stand_lifecycle').active(runtime.saveData) or lastStand:movementActor()~=nil)
          and not (runtime.trainAmbush and runtime.trainAmbush.phase~="complete")
      end,
      move=coopCollision,
    },
    neutralize=function()
      platform.mobileRuntime.focus(false); platform.presentationRuntime.endPan()
      if runtime.player then runtime.player.moving=false; runtime.player.velocityX=0; runtime.player.velocityY=0 end
    end,
    beforeJoin=function()
      if runtime.saveData and runtime.selectedSlot then
        local authority=coopCommands.authority()
        return authority and authority:checkpointNow() or false
      end
      return platform.persistenceRuntime.flush()~=false
    end,
    placeCompanion=function(data)
      local host=data.players.host
      local hx,hy=host.playerX,host.playerY
      if type(hx)~="number" or type(hy)~="number" then return false,"spawn_unavailable" end
      local actors,reason=require("game.party_scene").place(data,function() return hx,hy end,function(x,y,id,actor)
        if data.scene=="train" then
          local image=(scenery.trainCarImages or {})[data.trainCars[actor.activeCar]]
          return Train.clampCharacterToFloor(car,image,x,y,30)
        elseif data.scene=="stop" then return Settlements.clamp(x,y,data.location)
        elseif data.scene=="house" then return Util.clampHouseFloor(x,y)
        elseif data.scene=="expedition" then return Modules.expeditionAreas.clamp(data,data.activeExpeditionArea,x,y)
        elseif data.scene=="caravan" then return Modules.crowCaravanArea.clamp(x,y)
        end
      end)
      if not actors or host.playerX~=hx or host.playerY~=hy then return false,reason or "spawn_unavailable" end
      if require('game.coop_last_stand_lifecycle').walking(data) then require('game.coop_last_stand_lifecycle').ensure(data) end
      return true
    end,
  })
  coopCommands.setRemoteActorState(function()
    local motion=localPlay.motion
    if not motion or not motion.generation or not motion.actor then return nil end
    local input=motion.input
    if input and Engine.timer.getTime()-input.received>=require('game.net.movement').STALE_SECONDS then input=nil end
    return {screen=runtime.state,scene=runtime.scene,x=motion.actor.x,y=motion.actor.y,
      facing=motion.actor.facing,intentX=motion.actor.intentX,intentY=motion.actor.intentY,
      traveling=runtime.travelTransition~=nil,encounterActive=not not runtime.battle
        or (runtime.lastStand and runtime.lastStand.capture)==true or (runtime.trainAmbush and runtime.trainAmbush.phase~='complete') or false,
      activityBlocked=motion.readyEpoch~=motion.epoch,
      movementReady=motion.readyEpoch==motion.epoch,
      motionId=motion.motionId,moving=motion.actor.moving==true,
      inputX=input and input.x or 0,inputY=input and input.y or 0,
      modalDomain=motion.domain,
      npc=runtime.npcActor and {id=runtime.saveData.currentNPC,x=runtime.npcActor.x,y=runtime.npcActor.y} or nil}
  end)
  ui.expeditionActors=function()
    local actors={}
    local campaign=runtime.saveData
    if not campaign or not campaign.players then return actors end
    if runtime.player and campaign.health>0 then
      actors[1]={id='host',x=runtime.player.x,y=runtime.player.y}
    end
    local motion=localPlay.motion
    if motion and motion.generation and motion.actor and motion.epoch==campaign.coop.sceneEpoch
        and campaign.players.companion and campaign.players.companion.health>0 then
      actors[#actors+1]={id='companion',x=motion.actor.x,y=motion.actor.y,ready=motion.readyEpoch==motion.epoch}
    end
    return actors
  end
  ui.relocateExpeditionCompanion=function(x,y)
    return localPlay.motion and localPlay.motion:relocate(x,y)
  end
  ui.coopPatientBusy=function(npc) return coopCommands.patientBusy(npc or runtime.saveData.currentNPC) end
  application=require("game.local_play_host").wrap(application,{
    controller=localPlay,runtime=runtime,ui=ui,commands=coopCommands,bindings=controlBindings,
    screenToGame=platform.presentationRuntime.screenToGame,
    idleUpdate=function(dt,presentation) platform.persistenceRuntime.update(dt); platform.audioRuntime.update(presentation); return true end,
  })
  local function guestView() return localPlay:isClient() and localPlay.clientView or nil end
  local debugActivities=require('game.debug_activities').new({
    runtime=runtime,ui=ui,controller=localPlay,catalog=Catalog,world=world.worldScene,
    enterGame=world.sessionBootstrap.enterGame,lastStand=lastStand,battle=adventure.battleRuntime,
    maintenance=Maintenance,maintenanceSession=maintenanceSession,save=platform.persistenceRuntime.schedule,
    closeActivities=function()
      if ui.actionMenu then ui.actionMenu:close() end
      if maintenanceSession.open then Maintenance.close(maintenanceSession) end
      if ui.suspendOutfitWorkbench then ui.suspendOutfitWorkbench() end
      trainAmbush:suspend();lastStand:focus(false)
    end,
  })
  ui.debugActivities=debugActivities
  application=require('game.action_menu_host').wrap(application,{
    runtime=runtime,ui=ui,mobile=platform.mobileRuntime,presentation=platform.presentationRuntime,
    controller=localPlay,guest=guestView,maintenance=maintenanceSession,
  })
  return require('game.player_tools_host').wrap(application,{
    runtime=runtime,ui=ui,filesystem=Filesystem,mobile=platform.mobileRuntime,guest=guestView,controller=localPlay,minigames=debugActivities,
    presentation=platform.presentationRuntime,persistence=platform.persistenceRuntime,
  })
end

return {new=new}
