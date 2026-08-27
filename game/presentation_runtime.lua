local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"presentation runtime requires "..name)
  if expected then assert(type(value)==expected,"presentation runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","presentation runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local screens=required(context,"screens","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local Viewport=required(context,"viewport","table")
  local Camera=required(context,"camera","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local Maintenance=required(context,"maintenance","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local drawExitPrompt=required(context,"drawExitPrompt","function")
  local drawMobileControls=required(context,"drawMobileControls","function")

  Camera:configure(W,H)

  local function surface()
      if runtime.state~="game" then
          return runtime.state..(runtime.state=="battle" and runtime.inventoryOpen and ":inventory" or "")
      end
      local overlay=runtime.exitPrompt and "exit" or runtime.firstAid and "first-aid" or runtime.activityMinigame and "activity-minigame" or runtime.travelConfirm and "travel"
          or maintenanceSession.open and "maintenance" or ui.radioOpen and "radio" or runtime.inventoryOpen and "inventory"
          or runtime.mapOpen and "map" or runtime.tradeOpen and "trade" or runtime.trainUpgradeOpen and "upgrades"
          or runtime.editMode and "editor" or runtime.poseMenu and "pose" or ui.optionsOpen and "options"
          or ui.mobileMenuOpen and "mobile-menu" or runtime.dialogue and "dialogue" or runtime.scene or "world"
      return "game:"..overlay
  end

  local function activateSurface()
      Camera:setScope(surface())
  end

  local function focus()
      local worldSurface=runtime.state=="game" and not runtime.exitPrompt and not runtime.firstAid and not runtime.activityMinigame and not runtime.travelConfirm
          and not maintenanceSession.open and not ui.radioOpen and not runtime.inventoryOpen and not runtime.mapOpen
          and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.editMode and not runtime.poseMenu
          and not ui.optionsOpen and not ui.mobileMenuOpen and not runtime.dialogue
      if worldSurface and runtime.player then return runtime.player.x,runtime.player.y end
      return W/2,H/2
  end

  local function viewportToGame(x,y)
      return Viewport.toGame(x,y,W,H)
  end

  local function screenToGame(x,y)
      activateSurface()
      x,y=viewportToGame(x,y)
      if Camera:isActive() then
          local focusX,focusY=focus()
          x,y=Camera:toWorld(x,y,focusX,focusY)
      end
      return x,y
  end

  local function drawTravelFade()
      if not runtime.travelTransition then return end
      local t=runtime.travelTransition.t
      local timing=EngineUpgrades.timings(runtime.saveData.engineLevel,runtime.travelTransition.maintenanceCondition or Maintenance.condition(runtime.saveData))
      local alpha=t<timing.change and math.max(0,math.min(1,(t-timing.fadeOut)/timing.fadeDuration))
          or math.max(0,1-(t-timing.change)/timing.finishFade)
      local windowWidth,windowHeight=love.graphics.getDimensions()
      love.graphics.setColor(0,0,0,alpha)
      love.graphics.rectangle("fill",0,0,windowWidth,windowHeight)
  end

  local function draw()
      love.graphics.clear(0.025,0.02,0.025,1)
      if screens:is("intro") then
          local windowWidth,windowHeight=love.graphics.getDimensions()
          screens:draw(windowWidth,windowHeight)
          return
      end

      local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
      activateSurface()
      love.graphics.push()
      love.graphics.translate(offsetX,offsetY)
      love.graphics.scale(scaleX,scaleY)
      if Camera:isActive() then
          local focusX,focusY=focus()
          Camera:apply(focusX,focusY)
      end
      screens:draw()
      if runtime.exitPrompt then drawExitPrompt() end
      love.graphics.pop()

      drawMobileControls(offsetX,offsetY,scaleX,scaleY)
      drawTravelFade()
  end

  local function isPanning() return Camera.panning end
  local function beginPan(x,y) activateSurface(); return Camera:beginPan(x,y) end
  local function movePan(x,y)
      local _,_,viewportScale=Viewport.transform(W,H)
      return Camera:movePan(x,y,viewportScale)
  end
  local function endPan() return Camera:endPan() end
  local function wheel(delta,x,y)
      activateSurface()
      if x and y then x,y=viewportToGame(x,y) else x,y=W/2,H/2 end
      local focusX,focusY=focus()
      return Camera:wheel(delta,x,y,focusX,focusY)
  end
  local function getZoom() activateSurface(); return Camera.zoom end
  local function setZoom(value,x,y)
      activateSurface()
      if x and y then
          x,y=viewportToGame(x,y)
          local focusX,focusY=focus()
          return Camera:setZoomAt(value,x,y,focusX,focusY)
      end
      return Camera:setZoom(value)
  end
  local function resetCamera(all) activateSurface(); if all then Camera:resetAll() else Camera:reset() end end
  local function panCamera(dx,dy) activateSurface(); return Camera:panBy(dx,dy) end
  local function cameraAudit() return Camera:audit() end
  local function getSurface() activateSurface(); return Camera.scope end

  return {
      draw=draw,
      viewportToGame=viewportToGame,
      screenToGame=screenToGame,
      isPanning=isPanning,
      beginPan=beginPan,
      movePan=movePan,
      endPan=endPan,
      wheel=wheel,
      getZoom=getZoom,
      setZoom=setZoom,
      resetCamera=resetCamera,
      panCamera=panCamera,
      cameraAudit=cameraAudit,
      getSurface=getSurface,
  }
end

return {new=new}
