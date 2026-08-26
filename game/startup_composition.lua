local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"startup composition requires "..name)
  if expected then assert(type(value)==expected,"startup composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","startup composition requires an explicit context")
  local StartupRuntime=required(context,"startupRuntimeFactory","table")
  local AssetStreamer=required(context,"assetStreamer","table")
  local GameplayUpdate=required(context,"gameplayUpdate","table")
  local platform=required(context,"platform","table")
  local adventure=required(context,"adventure","table")
  local world=required(context,"world","table")
  local content=required(context,"content","table")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local holdPickupSeconds=required(context,"holdPickupSeconds","number")
  local ui=required(context,"ui","table")
  local car=required(context,"car","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local screens=required(context,"screens","table")
  local Graphics=required(context,"graphics","table")
  local Filesystem=required(context,"filesystem","table")
  local Assets=required(context,"assets","table")
  local Settlements=required(context,"settlements","table")
  local Clouds=required(context,"clouds","table")
  local Intro=required(context,"intro","table")
  local interactionRouter=required(context,"interactionRouter","table")
  local Interactions=required(context,"interactions","table")
  local Catalog=required(context,"catalog","table")
  local InteriorDoors=required(context,"interiorDoors","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Maintenance=required(context,"maintenance","table")
  local Family=required(context,"family","table")
  local Util=required(context,"util","table")
  local Passengers=required(context,"passengers","table")

  local startupRuntime=StartupRuntime.new({
    ui=ui,scenery=content.scenery,graphics=Graphics,filesystem=Filesystem,assets=Assets,
    settlements=Settlements,clouds=Clouds,assetStreamer=AssetStreamer,gameplayUpdate=GameplayUpdate,
    initializeAudio=platform.audioRuntime.initialize,initializeMobile=platform.mobileRuntime.initialize,
    createIntro=function() return Intro.new(10) end,assetTargets=content.assetTargets,
    legacyAnimationTables=content.legacyAnimationTables,
    gameplayContext={
      runtime=runtime,width=W,holdPickupSeconds=holdPickupSeconds,ui=ui,car=car,scenery=content.scenery,
      maintenanceSession=maintenanceSession,mobileEnabled=platform.mobileRuntime.isEnabled,
      mobileMovement=platform.mobileRuntime.movement,mobileHeld=platform.mobileRuntime.isHeld,
      mobileSprinting=platform.mobileRuntime.isSprinting,interactionRouter=interactionRouter,
      inventoryActions=adventure.inventoryActions,journeyRules=adventure.journeyRules,catalog=Catalog,
      settlements=Settlements,interiorDoors=InteriorDoors,interactions=Interactions,
      updatePersistence=platform.persistenceRuntime.update,clouds=Clouds,screens=screens,
      engineUpgrades=EngineUpgrades,trainUpgradeBalance=TrainUpgradeBalance,maintenance=Maintenance,family=Family,util=Util,passengers=Passengers,
      screenToGame=platform.presentationRuntime.screenToGame,updateAudio=platform.audioRuntime.update,
      ensureStopLayout=world.worldScene.ensureStopLayout,updateWorldScene=world.worldScene.update,currentStopActivity=world.worldScene.currentStopActivity,
      clampToTrainFloor=platform.trainCarRuntime.clampToFloor,itemIsHere=world.worldScene.itemIsHere,
      setupNPC=world.worldScene.setupNPC,trainFloorBounds=platform.trainCarRuntime.floorBounds,
      updateCarTransition=platform.trainCarRuntime.updateTransition,writeSave=platform.persistenceRuntime.schedule,
    },
  })

  local startup={startupRuntime=startupRuntime}
  function startup.status()
    return {
      ready=type(startupRuntime.load)=="function" and type(startupRuntime.update)=="function"
        and type(startupRuntime.characterAnimations)=="function" and type(startupRuntime.cloudLayer)=="function",
      componentCount=2,
    }
  end
  return startup
end

return {new=new}
