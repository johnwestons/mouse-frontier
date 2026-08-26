local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"platform composition requires "..name)
  if expected then assert(type(value)==expected,"platform composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","platform composition requires an explicit context")
  local PersistenceRuntime=required(context,"persistenceRuntimeFactory","table")
  local AudioRuntime=required(context,"audioRuntimeFactory","table")
  local TrainCarRuntime=required(context,"trainCarRuntimeFactory","table")
  local PresentationRuntime=required(context,"presentationRuntimeFactory","table")
  local MobileRuntime=required(context,"mobileRuntimeFactory","table")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local session=required(context,"session","table")
  local Save=required(context,"save","table")
  local Maintenance=required(context,"maintenance","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local Catalog=required(context,"catalog","table")
  local Audio=required(context,"audio","table")
  local AudioCatalog=required(context,"audioCatalog","table")
  local scenery=required(context,"scenery","table")
  local car=required(context,"car","table")
  local Train=required(context,"train","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local screens=required(context,"screens","table")
  local Viewport=required(context,"viewport","table")
  local Camera=required(context,"camera","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local MobileControls=required(context,"mobileControls","table")
  local drawExitPrompt=required(context,"drawExitPrompt","function")
  local getGameplayInput=required(context,"getGameplayInput","function")

  local persistenceRuntime,audioRuntime,trainCarRuntime,presentationRuntime,mobileRuntime
  persistenceRuntime=PersistenceRuntime.new({
    runtime=runtime,ui=ui,session=session,save=Save,maintenance=Maintenance,maintenanceSession=maintenanceSession,
    focusMobile=function(...) return mobileRuntime.focus(...) end,
    focusAudio=function(...) return audioRuntime.focus(...) end,
    shutdownAudio=function(...) return audioRuntime.shutdown(...) end,
  })

  audioRuntime=AudioRuntime.new({runtime=runtime,ui=ui,catalog=Catalog,audio=Audio,audioCatalog=AudioCatalog})

  trainCarRuntime=TrainCarRuntime.new({
    runtime=runtime,ui=ui,scenery=scenery,car=car,train=Train,width=W,height=H,
    writeSave=persistenceRuntime.schedule,
  })

  presentationRuntime=PresentationRuntime.new({
    runtime=runtime,ui=ui,screens=screens,maintenanceSession=maintenanceSession,
    viewport=Viewport,camera=Camera,engineUpgrades=EngineUpgrades,width=W,height=H,
    drawExitPrompt=drawExitPrompt,drawMobileControls=function(...) return mobileRuntime.draw(...) end,
  })

  mobileRuntime=MobileRuntime.new({
    runtime=runtime,ui=ui,maintenanceSession=maintenanceSession,mobileControls=MobileControls,width=W,height=H,
    viewportToGame=presentationRuntime.viewportToGame,getCameraZoom=presentationRuntime.getZoom,
    setCameraZoom=presentationRuntime.setZoom,endCameraPan=presentationRuntime.endPan,
    beginCameraPan=presentationRuntime.beginPan,moveCameraPan=presentationRuntime.movePan,
    getGameplayInput=getGameplayInput,
  })

  local platform={
    persistenceRuntime=persistenceRuntime,audioRuntime=audioRuntime,trainCarRuntime=trainCarRuntime,
    presentationRuntime=presentationRuntime,mobileRuntime=mobileRuntime,
  }
  function platform.status()
    return {
      ready=type(persistenceRuntime.schedule)=="function" and type(audioRuntime.update)=="function"
        and type(trainCarRuntime.floorBounds)=="function" and type(presentationRuntime.screenToGame)=="function"
        and type(mobileRuntime.initialize)=="function",
      componentCount=5,
    }
  end
  return platform
end

return {new=new}
