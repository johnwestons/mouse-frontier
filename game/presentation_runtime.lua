local WorldView=require("game.world_view")
local TrainView=require("game.train_view")

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
  local getWorldOffset=required(context,"getWorldOffset","function")
  local car=required(context,"car","table")
  local mobileEnabled=required(context,"mobileEnabled","function")

  Camera:configure(W,H)

  local function getTrainView()
      if runtime.state~="game" or runtime.scene~="train" then return nil end
      local windowWidth,windowHeight=love.graphics.getDimensions()
      return TrainView.layout(car,W,H,windowWidth,windowHeight,
          {mobile=mobileEnabled(),carCount=#(runtime.saveData and runtime.saveData.trainCars or {})})
  end

  local function activateSurface()
      Camera:setScope("world")
  end

  local function focus()
      if runtime.state=="battle" then return W/2,250 end
      local lastStandCaptures=runtime.lastStand and runtime.lastStand.capture==true and runtime.lastStand.mode~="offer"
      local worldSurface=runtime.state=="game" and not lastStandCaptures and not runtime.shootingRange
      if worldSurface and runtime.player then
          local offsetX,offsetY=getWorldOffset()
          local trainView=getTrainView()
          if trainView then return TrainView.toView(trainView,runtime.player.x,runtime.player.y) end
          return runtime.player.x-(offsetX or 0),runtime.player.y-(offsetY or 0)
      end
      return W/2,H/2
  end

  local function viewportToGame(x,y)
      return Viewport.toGame(x,y,W,H)
  end

  local function sceneCoordinates(x,y)
      activateSurface()
      local focusX,focusY=focus()
      return Camera:toWorld(x,y,focusX,focusY)
  end

  WorldView.configure({
      apply=function(options)
          activateSurface()
          if options and options.fullscreen then
              local width,height=options.fullscreen[1],options.fullscreen[2]
              local scale=height/H
              love.graphics.translate(width/2+Camera.panX*scale,height/2+Camera.panY*scale)
              love.graphics.scale(Camera.zoom,Camera.zoom)
              love.graphics.translate(-width/2,-height/2)
              return
          end
          local focusX,focusY=focus()
          Camera:apply(focusX,focusY)
      end,
      toWorld=sceneCoordinates,
      toScreen=function(x,y)
          activateSurface()
          local focusX,focusY=focus()
          return (x-focusX)*Camera.zoom+focusX+Camera.panX,
              (y-focusY)*Camera.zoom+focusY+Camera.panY
      end,
  })

  local function screenToGame(x,y)
      return viewportToGame(x,y)
  end

  local function worldCoordinates(x,y)
      x,y=sceneCoordinates(x,y)
      local trainView=getTrainView()
      if trainView then return TrainView.toWorld(trainView,x,y) end
      local offsetX,offsetY=getWorldOffset()
      return x+(offsetX or 0),y+(offsetY or 0)
  end

  local function screenToWorld(x,y)
      return worldCoordinates(screenToGame(x,y))
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
          screens:draw(love.graphics.getDimensions())
          return
      end
      local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
      activateSurface()
      love.graphics.push()
      love.graphics.translate(offsetX,offsetY)
      love.graphics.scale(scaleX,scaleY)
      screens:draw(W,H)
      if runtime.exitPrompt then drawExitPrompt() end
      love.graphics.pop()

      if not (runtime.lastStand and runtime.lastStand.capture==true) then
          drawMobileControls(offsetX,offsetY,scaleX,scaleY)
      end
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
      screenToWorld=screenToWorld,
      worldCoordinates=worldCoordinates,
      getTrainView=getTrainView,
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
