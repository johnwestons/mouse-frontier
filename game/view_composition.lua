local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"view composition requires "..name)
  if expected then assert(type(value)==expected,"view composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","view composition requires an explicit context")
  local ScreenUI=required(context,"screenUIFactory","table")
  local InventoryPresenter=required(context,"inventoryPresenterFactory","table")
  local WorldRenderer=required(context,"worldRendererFactory","table")
  local GameplayHUD=required(context,"gameplayHUDFactory","table")
  local InventoryUI=required(context,"inventoryUI","table")
  local platform=required(context,"platform","table")
  local adventure=required(context,"adventure","table")
  local world=required(context,"world","table")
  local startup=required(context,"startup","table")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local colors=required(context,"colors","table")
  local content=required(context,"content","table")
  local car=required(context,"car","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local holdPickupSeconds=required(context,"holdPickupSeconds","number")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local EventUI=required(context,"eventUI","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local PlayerProgression=required(context,"playerProgression","table")
  local StopHelpProgression=required(context,"stopHelpProgression","table")
  local NpcRelationships=required(context,"npcRelationships","table")
  local FinaleProgression=required(context,"finaleProgression","table")
  local FirstAid=required(context,"firstAid","table")
  local Train=required(context,"train","table")
  local CharacterAnimation=required(context,"characterAnimation","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Stops=required(context,"stops","table")
  local Clouds=required(context,"clouds","table")
  local Maintenance=required(context,"maintenance","table")

  local screenUI,inventoryPresenter,worldRenderer,gameplayHUD

  screenUI=ScreenUI.new({
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,scenery=content.scenery,
    characters=content.characters,characterImages=content.characterImages,npcImages=content.npcImages,
    readSave=platform.persistenceRuntime.read,util=Util,catalog=Catalog,inventory=Inventory,eventUI=EventUI,
    canChooseEvent=adventure.eventRuntime.canChoose,engineUpgrades=EngineUpgrades,trainUpgradeBalance=TrainUpgradeBalance,
    playerProgression=PlayerProgression,
    stopHelpProgression=StopHelpProgression,npcRelationships=NpcRelationships,
    finaleProgression=FinaleProgression,maintenance=Maintenance,
    writeSave=platform.persistenceRuntime.schedule,screenToGame=platform.presentationRuntime.screenToGame,
    ensureStopLayout=world.worldScene.ensureStopLayout,mobileEnabled=platform.mobileRuntime.isEnabled,
    drawLandscape=function(...) return worldRenderer.drawLandscape(...) end,
    drawTracks=function(...) return worldRenderer.drawTracks(...) end,
    drawLocomotive=function(...) return worldRenderer.drawLocomotive(...) end,
    drawTrainCar=function(...) return worldRenderer.drawTrainCar(...) end,
    isWeapon=adventure.inventoryActions.isWeapon,travelCost=adventure.journeyRules.travelCost,
    repairStatus=adventure.inventoryActions.repairStatus,
    questSummary=adventure.journeyRules.questSummary,
  })

  inventoryPresenter=InventoryPresenter.new({
    runtime=runtime,ui=ui,inventoryUI=InventoryUI,inventory=Inventory,catalog=Catalog,colors=colors,
    mobileEnabled=platform.mobileRuntime.isEnabled,pointIn=Util.pointIn,title=Util.titleFromFile,
    isWeapon=adventure.inventoryActions.isWeapon,drawMenuFrame=screenUI.drawMenuFrame,button=screenUI.button,
    pointer=function() return platform.presentationRuntime.screenToGame(platform.mobileRuntime.pointerPosition()) end,
    value=adventure.inventoryActions.containerValue,move=adventure.inventoryActions.moveBetweenSlots,
    quickTransfer=adventure.inventoryActions.quickTransfer,collectAmmo=adventure.inventoryActions.collectAmmo,
    drop=adventure.inventoryActions.dropFromContainer,consume=adventure.inventoryActions.consumeSelected,
    consumeBattle=adventure.inventoryActions.consumeBattleSelected,
  })

  worldRenderer=WorldRenderer.new({
    runtime=runtime,width=W,height=H,backgroundImages=content.backgroundImages,scenery=content.scenery,car=car,colors=colors,
    getCharacterAnimations=function() return startup.startupRuntime.characterAnimations() end,
    characterImages=content.characterImages,characterWalkImages=content.characterWalkImages,
    characterActionImages=content.characterActionImages,itemIdleImages=content.itemIdleImages,
    npcImages=content.npcImages,npcWalkImages=content.npcWalkImages,familyImages=content.familyImages,
    mobImages=content.mobImages,mobIdleImages=content.mobIdleImages,mobWalkImages=content.mobWalkImages,
    mobHitImages=content.mobHitImages,mobDeathImages=content.mobDeathImages,
    drawStopSludges=world.worldScene.drawStopSludges,drawStopActivity=world.worldScene.drawStopActivity,drawWildlife=world.worldScene.drawWildlife,
    train=Train,characterAnimation=CharacterAnimation,catalog=Catalog,family=Family,settlements=Settlements,stops=Stops,util=Util,ui=ui,
    itemIsHere=world.worldScene.itemIsHere,pendingMailHere=adventure.journeyRules.pendingMailHere,
    ensureStopLayout=world.worldScene.ensureStopLayout,
  })

  gameplayHUD=GameplayHUD.new({
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,maintenanceSession=maintenanceSession,
    holdPickupSeconds=holdPickupSeconds,getCloudLayer=function() return startup.startupRuntime.cloudLayer() end,
    mobileEnabled=platform.mobileRuntime.isEnabled,engineUpgrades=EngineUpgrades,trainUpgradeBalance=TrainUpgradeBalance,clouds=Clouds,maintenance=Maintenance,util=Util,train=Train,
    firstAid=FirstAid,
    button=screenUI.button,drawMenuFrame=screenUI.drawMenuFrame,drawTrade=screenUI.drawTrade,
    isFurnitureItem=content.isFurnitureItem,containerValue=adventure.inventoryActions.containerValue,
    travelStatus=adventure.journeyRules.travelStatus,
    screenToGame=platform.presentationRuntime.screenToGame,pointerPosition=platform.mobileRuntime.pointerPosition,
    getAudioStatus=platform.audioRuntime.status,drawLandscape=worldRenderer.drawLandscape,
    drawTracks=worldRenderer.drawTracks,drawTrainView=worldRenderer.drawTrainView,
    drawHouse=worldRenderer.drawHouse,drawStop=worldRenderer.drawStop,
  })

  local views={screenUI=screenUI,inventoryPresenter=inventoryPresenter,worldRenderer=worldRenderer,gameplayHUD=gameplayHUD}
  function views.status()
    return {
      ready=type(screenUI.drawEnding)=="function" and type(inventoryPresenter.handleClick)=="function"
        and type(worldRenderer.drawLandscape)=="function" and type(gameplayHUD.draw)=="function",
      componentCount=4,
      explicitDependencies=true,
    }
  end
  return views
end

return {new=new}
