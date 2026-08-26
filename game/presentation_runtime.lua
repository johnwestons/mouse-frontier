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
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local drawExitPrompt=required(context,"drawExitPrompt","function")
  local drawMobileControls=required(context,"drawMobileControls","function")

  local function focus()
      return runtime.player and runtime.player.x or W/2,runtime.player and runtime.player.y or H/2
  end

  -- The camera must be disabled for overlays that are drawn and hit-tested in
  -- virtual screen space. Keeping this predicate here prevents rendering and
  -- pointer conversion from drifting apart as more overlays are added.
  local function worldCameraActive()
      return runtime.state=="game" and not runtime.travelConfirm and not maintenanceSession.open
          and not ui.radioOpen and not ui.mobileMenuOpen and Camera:isActive()
  end

  local function viewportToGame(x,y)
      return Viewport.toGame(x,y,W,H)
  end

  local function screenToGame(x,y)
      x,y=viewportToGame(x,y)
      if worldCameraActive() then
          local focusX,focusY=focus()
          x,y=Camera:toWorld(x,y,focusX,focusY)
      end
      return x,y
  end

  local function drawTravelFade()
      if not runtime.travelTransition then return end
      local t=runtime.travelTransition.t
      local timing=EngineUpgrades.timings(runtime.saveData.engineLevel)
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
      love.graphics.push()
      love.graphics.translate(offsetX,offsetY)
      love.graphics.scale(scaleX,scaleY)
      if worldCameraActive() then
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
  local function beginPan(x,y) return Camera:beginPan(x,y) end
  local function movePan(x,y)
      local _,_,viewportScale=Viewport.transform(W,H)
      return Camera:movePan(x,y,viewportScale)
  end
  local function endPan() return Camera:endPan() end
  local function wheel(delta) return Camera:wheel(delta) end
  local function getZoom() return Camera.zoom end
  local function setZoom(value) return Camera:setZoom(value) end

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
  }
end

return {new=new}
