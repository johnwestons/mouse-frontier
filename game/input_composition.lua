local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"input composition requires "..name)
  if expected then assert(type(value)==expected,"input composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","input composition requires an explicit context")
  local GameplayInput=required(context,"gameplayInputFactory","table")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local content=required(context,"content","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local platform=required(context,"platform","table")
  local adventure=required(context,"adventure","table")
  local views=required(context,"views","table")
  local worldScene=required(context,"worldScene","table")
  local sessionBootstrap=required(context,"sessionBootstrap","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local NpcRelationships=required(context,"npcRelationships","table")
  local Util=required(context,"util","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Maintenance=required(context,"maintenance","table")
  local BattleRules=required(context,"battleRules","table")
  local Stops=required(context,"stops","table")
  local Settlements=required(context,"settlements","table")
  local InteriorDoors=required(context,"interiorDoors","table")
  local Intro=required(context,"intro","table")
  local Interactions=required(context,"interactions","table")
  local FirstAid=required(context,"firstAid","table")
  local resolveFirstAid=required(context,"resolveFirstAid","function")
  local chooseHelpDialogue=required(context,"chooseHelpDialogue","function")
  local FinaleProgression=required(context,"finaleProgression","table")

  local gameplayInput=GameplayInput.new({
    runtime=runtime,ui=ui,characters=content.characters,maintenanceSession=maintenanceSession,scenery=content.scenery,
    inventory=Inventory,catalog=Catalog,npcRelationships=NpcRelationships,util=Util,readSave=platform.persistenceRuntime.read,
    removeSave=platform.persistenceRuntime.remove,engineUpgrades=EngineUpgrades,trainUpgradeBalance=TrainUpgradeBalance,maintenance=Maintenance,
    battleRules=BattleRules,stops=Stops,settlements=Settlements,interiorDoors=InteriorDoors,
    writeSave=platform.persistenceRuntime.schedule,screenToGame=platform.presentationRuntime.screenToGame,
    cameraPanning=platform.presentationRuntime.isPanning,
    beginCameraPan=platform.presentationRuntime.beginPan,moveCameraPan=platform.presentationRuntime.movePan,
    endCameraPan=platform.presentationRuntime.endPan,zoomCamera=platform.presentationRuntime.wheel,
    resetCamera=platform.presentationRuntime.resetCamera,panCamera=platform.presentationRuntime.panCamera,
    pointerPosition=platform.mobileRuntime.pointerPosition,isWeapon=adventure.inventoryActions.isWeapon,
    isFurnitureItem=content.isFurnitureItem,ensureStopLayout=worldScene.ensureStopLayout,
    moveEditedItem=platform.trainCarRuntime.moveEditedItem,
    attackStopSludge=worldScene.attackStopSludge,acceptQuest=adventure.journeyRules.acceptQuest,
    attemptLeaveTrain=adventure.journeyRules.attemptLeaveTrain,travelStatus=adventure.journeyRules.travelStatus,
    playTrainDepart=platform.audioRuntime.playTrainDepart,audioResetMusic=platform.audioRuntime.resetMusic,
    audioPreviousTrack=platform.audioRuntime.previousTrack,audioTogglePause=platform.audioRuntime.togglePause,
    audioNextTrack=platform.audioRuntime.nextTrack,audioToggleMute=platform.audioRuntime.toggleMute,
    enterTrain=platform.trainCarRuntime.enterTrain,placeEditedItem=platform.trainCarRuntime.placeEditedItem,
    newSave=sessionBootstrap.newSave,enterGame=sessionBootstrap.enterGame,chooseEvent=adventure.eventRuntime.choose,
    handleEventClick=adventure.eventRuntime.handleClick,enterStop=adventure.journeyRules.enterStop,
    handleBattleMouse=adventure.battleRuntime.handleMouse,battleAttack=adventure.battleRuntime.attack,
    battleHeal=adventure.battleRuntime.heal,battleGuard=adventure.battleRuntime.guard,
    advanceBattleTurn=adventure.battleRuntime.advanceTurn,setBattlePrompt=adventure.battleRuntime.setPrompt,
    beginCarTransition=platform.trainCarRuntime.beginTransition,talkToNPC=adventure.journeyRules.talkToNPC,
    ensureHouseItems=worldScene.ensureHouseItems,setupNPC=worldScene.setupNPC,
    giveWeaponToNearby=adventure.inventoryActions.giveWeaponToNearby,
    pickUpNearby=adventure.inventoryActions.pickUpNearby,addCoalToFire=adventure.inventoryActions.addCoalToFire,
    handleInventoryClick=views.inventoryPresenter.handleClick,handleInventoryRelease=views.inventoryPresenter.handleRelease,
    requestExitPrompt=views.screenUI.requestExitPrompt,resolveExitPrompt=views.screenUI.resolveExitPrompt,
    trainItemAt=views.worldRenderer.trainItemAt,skipIntro=Intro.skip,
    interactionMouseAction=Interactions.mouseAction,interactionKeyAction=Interactions.keyAction,
    repairEquipped=adventure.inventoryActions.repairEquipped,
    firstAid=FirstAid,resolveFirstAid=resolveFirstAid,chooseHelpDialogue=chooseHelpDialogue,
    completeStopActivity=worldScene.completeStopActivity,
    chooseFinale=function(id) return FinaleProgression.choose(runtime.saveData,id) end,
  })

  local input={gameplayInput=gameplayInput}
  function input.status()
    return {
      ready=type(gameplayInput.mousepressed)=="function" and type(gameplayInput.keypressed)=="function"
        and type(gameplayInput.wheelmoved)=="function",
      commandGroups=9,
    }
  end
  return input
end

return {new=new}
