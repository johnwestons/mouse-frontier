local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"world/session composition requires "..name)
  if expected then assert(type(value)==expected,"world/session composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","world/session composition requires an explicit context")
  local WorldScene=required(context,"worldSceneFactory","table")
  local SessionBootstrap=required(context,"sessionBootstrapFactory","table")
  local platform=required(context,"platform","table")
  local content=required(context,"content","table")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local car=required(context,"car","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local Filesystem=required(context,"filesystem","table")
  local SaveSchema=required(context,"saveSchema","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local House=required(context,"house","table")
  local Stops=required(context,"stops","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Wildlife=required(context,"wildlife","table")
  local Mice=required(context,"mice","table")
  local StopSludges=required(context,"stopSludges","table")
  local Roster=required(context,"roster","table")
  local Maintenance=required(context,"maintenance","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local Passengers=required(context,"passengers","table")
  local Events=required(context,"events","table")
  local PlayerProgression=required(context,"playerProgression","table")
  local getIsWeapon=required(context,"getIsWeapon","function")

  local worldScene=WorldScene.new({
    runtime=runtime,ui=ui,scenery=content.scenery,catalog=Catalog,util=Util,house=House,stops=Stops,
    family=Family,settlements=Settlements,wildlife=Wildlife,mice=Mice,stopSludges=StopSludges,
    getIsWeapon=getIsWeapon,isFurnitureItem=content.isFurnitureItem,
    writeSave=platform.persistenceRuntime.schedule,
  })

  local sessionBootstrap=SessionBootstrap.new({
    saveSchema=SaveSchema,characters=content.characters,characterImages=content.characterImages,
    npcImages=content.npcImages,car=car,ui=ui,maintenanceSession=maintenanceSession,runtime=runtime,
    filesystem=Filesystem,roster=Roster,house=House,catalog=Catalog,maintenance=Maintenance,
    engineUpgrades=EngineUpgrades,passengers=Passengers,events=Events,settlements=Settlements,
    playerProgression=PlayerProgression,
    trainObjectBounds=platform.trainCarRuntime.objectBounds,trainFloorBounds=platform.trainCarRuntime.floorBounds,
    clampToTrainFloor=platform.trainCarRuntime.clampToFloor,isFurnitureItem=content.isFurnitureItem,
    resetStopSludges=worldScene.resetStopSludges,
  })

  local world={worldScene=worldScene,sessionBootstrap=sessionBootstrap}
  function world.status()
    return {
      ready=type(worldScene.ensureStopLayout)=="function" and type(worldScene.resetStopSludges)=="function"
        and type(sessionBootstrap.newSave)=="function" and type(sessionBootstrap.enterGame)=="function",
      componentCount=2,
    }
  end
  return world
end

return {new=new}
