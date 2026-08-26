local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"view composition requires "..name)
  if expected then assert(type(value)==expected,"view composition "..name.." must be a "..expected) end
  return value
end

local function system(systems,name)
  local value=systems[name]
  assert(type(value)=="table","view composition requires system "..name)
  return value
end

local function new(context)
  assert(type(context)=="table","view composition requires an explicit context")
  local Systems=required(context,"systems","table")
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
  local Train=required(context,"train","table")
  local CharacterAnimation=required(context,"characterAnimation","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Stops=required(context,"stops","table")
  local Clouds=required(context,"clouds","table")
  local Maintenance=required(context,"maintenance","table")

  local ScreenUI=system(Systems,"screenUI")
  local InventoryPresenter=system(Systems,"inventoryPresenter")
  local WorldRenderer=system(Systems,"worldRenderer")
  local GameplayHUD=system(Systems,"gameplayHUD")
  local screenUI,inventoryPresenter,worldRenderer,gameplayHUD

  screenUI=ScreenUI.new({
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,scenery=content.scenery,
    characters=content.characters,characterImages=content.characterImages,npcImages=content.npcImages,
    readSave=system(Systems,"persistenceRuntime").read,util=Util,catalog=Catalog,inventory=Inventory,eventUI=EventUI,
    canChooseEvent=system(Systems,"eventRuntime").canChoose,engineUpgrades=EngineUpgrades,
    writeSave=Systems.persistenceRuntime.schedule,screenToGame=system(Systems,"presentationRuntime").screenToGame,
    ensureStopLayout=system(Systems,"worldScene").ensureStopLayout,mobileEnabled=system(Systems,"mobileRuntime").isEnabled,
    drawLandscape=function(...) return worldRenderer.drawLandscape(...) end,
    drawTracks=function(...) return worldRenderer.drawTracks(...) end,
    drawLocomotive=function(...) return worldRenderer.drawLocomotive(...) end,
    drawTrainCar=function(...) return worldRenderer.drawTrainCar(...) end,
    isWeapon=system(Systems,"inventoryActions").isWeapon,travelCost=system(Systems,"journeyRules").travelCost,
  })

  inventoryPresenter=InventoryPresenter.new({
    runtime=runtime,ui=ui,inventoryUI=system(Systems,"inventory"),inventory=Inventory,catalog=Catalog,colors=colors,
    mobileEnabled=Systems.mobileRuntime.isEnabled,pointIn=Util.pointIn,title=Util.titleFromFile,
    isWeapon=Systems.inventoryActions.isWeapon,drawMenuFrame=screenUI.drawMenuFrame,button=screenUI.button,
    pointer=function() return Systems.presentationRuntime.screenToGame(Systems.mobileRuntime.pointerPosition()) end,
    value=Systems.inventoryActions.containerValue,move=Systems.inventoryActions.moveBetweenSlots,
    quickTransfer=Systems.inventoryActions.quickTransfer,collectAmmo=Systems.inventoryActions.collectAmmo,
    drop=Systems.inventoryActions.dropFromContainer,consume=Systems.inventoryActions.consumeSelected,
    consumeBattle=Systems.inventoryActions.consumeBattleSelected,
  })

  worldRenderer=WorldRenderer.new({
    runtime=runtime,width=W,height=H,backgroundImages=content.backgroundImages,scenery=content.scenery,car=car,colors=colors,
    getCharacterAnimations=function() return Systems.startupRuntime.characterAnimations() end,
    characterImages=content.characterImages,characterWalkImages=content.characterWalkImages,
    characterActionImages=content.characterActionImages,itemIdleImages=content.itemIdleImages,
    npcImages=content.npcImages,npcWalkImages=content.npcWalkImages,familyImages=content.familyImages,
    mobImages=content.mobImages,mobIdleImages=content.mobIdleImages,mobWalkImages=content.mobWalkImages,
    mobHitImages=content.mobHitImages,mobDeathImages=content.mobDeathImages,
    drawStopSludges=Systems.worldScene.drawStopSludges,drawWildlife=Systems.worldScene.drawWildlife,
    train=Train,characterAnimation=CharacterAnimation,catalog=Catalog,family=Family,settlements=Settlements,stops=Stops,util=Util,ui=ui,
    itemIsHere=Systems.worldScene.itemIsHere,pendingMailHere=Systems.journeyRules.pendingMailHere,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
  })

  gameplayHUD=GameplayHUD.new({
    runtime=runtime,width=W,height=H,ui=ui,colors=colors,maintenanceSession=maintenanceSession,
    holdPickupSeconds=holdPickupSeconds,getCloudLayer=function() return Systems.startupRuntime.cloudLayer() end,
    mobileEnabled=Systems.mobileRuntime.isEnabled,engineUpgrades=EngineUpgrades,clouds=Clouds,maintenance=Maintenance,util=Util,
    button=screenUI.button,drawMenuFrame=screenUI.drawMenuFrame,drawTrade=screenUI.drawTrade,
    isFurnitureItem=content.isFurnitureItem,containerValue=Systems.inventoryActions.containerValue,
    screenToGame=Systems.presentationRuntime.screenToGame,pointerPosition=Systems.mobileRuntime.pointerPosition,
    getAudioStatus=system(Systems,"audioRuntime").status,drawLandscape=worldRenderer.drawLandscape,
    drawTracks=worldRenderer.drawTracks,drawTrainView=worldRenderer.drawTrainView,
    drawHouse=worldRenderer.drawHouse,drawStop=worldRenderer.drawStop,
  })

  local views={screenUI=screenUI,inventoryPresenter=inventoryPresenter,worldRenderer=worldRenderer,gameplayHUD=gameplayHUD}
  function views.status()
    return {
      ready=type(screenUI.drawEnding)=="function" and type(inventoryPresenter.handleClick)=="function"
        and type(worldRenderer.drawLandscape)=="function" and type(gameplayHUD.draw)=="function",
      componentCount=4,
    }
  end
  return views
end

return {new=new}
