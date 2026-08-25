local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"mobile runtime requires "..name)
  if expected then assert(type(value)==expected,"mobile runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","mobile runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local MobileControls=required(context,"mobileControls","table")
  local Viewport=required(context,"viewport","table")
  local Camera=required(context,"camera","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local getGameplayInput=required(context,"getGameplayInput","function")
  local controls

  local function gameplayInput()
      local input=getGameplayInput()
      assert(type(input)=="table","mobile runtime gameplay input is unavailable")
      return input
  end

  local function gameplayActive()
      return runtime.state=="game" and not runtime.travelConfirm and not runtime.travelTransition and not maintenanceSession.open
          and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.editMode
          and not runtime.poseMenu and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not runtime.exitPrompt
  end

  local function backVisible()
      if runtime.exitPrompt then return true end
      if runtime.state=="slots" or runtime.state=="characters" then return true end
      if runtime.state=="battle" then return runtime.inventoryOpen end
      return runtime.state=="game" and (runtime.travelConfirm or maintenanceSession.open or runtime.inventoryOpen or runtime.mapOpen or runtime.tradeOpen or runtime.trainUpgradeOpen
          or runtime.editMode or runtime.poseMenu or ui.optionsOpen or ui.radioOpen or ui.mobileMenuOpen or runtime.dialogue~=nil)
  end

  local function menuVisible()
      return runtime.state=="game" and not runtime.travelConfirm and not runtime.travelTransition and not maintenanceSession.open and not runtime.exitPrompt
          and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.editMode
          and not runtime.poseMenu and not ui.optionsOpen and not ui.radioOpen and not runtime.dialogue
  end

  local function primaryAction()
      if runtime.dialogue then return "q","CLOSE" end
      local kind=ui.interaction and ui.interaction.kind
      if kind=="radio" then return "p","RADIO"
      elseif kind=="item" then return "e","PICK UP"
      elseif kind=="chest" then return "i","OPEN"
      elseif kind=="fire" then return "e","COAL"
      elseif kind=="npc" or kind=="passenger" then return "q","TALK"
      elseif kind=="house" then return "q","ENTER"
      elseif kind=="houseExit" then return "q","EXIT"
      elseif kind=="returnTrain" then return "q","BOARD"
      elseif kind=="carNext" or kind=="carPrev" then return "q","DOOR"
      end
      return "e","USE"
  end

  local function secondaryAction()
      local kind=ui.interaction and ui.interaction.kind
      if kind=="npc" or kind=="passenger" then return "g","GIVE" end
  end

  local function initialize()
      if controls then controls:cancelAll() end
      controls=MobileControls.new({
          width=W,
          height=H,
          toGame=function(x,y) return Viewport.toGame(x,y,W,H) end,
          gameplayActive=gameplayActive,
          getZoom=function() return Camera.zoom end,
          setZoom=function(value) Camera:setZoom(value) end,
          backVisible=backVisible,
          backLabel=function() return runtime.state=="slots" and "EXIT" or "BACK" end,
          menuVisible=menuVisible,
          menuLabel=function() return ui.mobileMenuOpen and "CLOSE" or "MENU" end,
          menuAction=function() ui.mobileMenuOpen=not ui.mobileMenuOpen; Camera:endPan() end,
          primaryAction=primaryAction,
          secondaryAction=secondaryAction,
          pressKey=function(key) gameplayInput().keypressed(key) end,
          releaseKey=function(key) gameplayInput().keyreleased(key) end,
          pressPointer=function(x,y,button) gameplayInput().mousepressed(x,y,button) end,
          movePointer=function(x,y,dx,dy) gameplayInput().mousemoved(x,y,dx,dy) end,
          releasePointer=function(x,y,button) gameplayInput().mousereleased(x,y,button) end,
      })
      return controls
  end

  local function get() return controls end
  local function isEnabled() return controls and controls:isEnabled() or false end
  local function movement()
      if controls then return controls:movement() end
      return 0,0
  end
  local function isHeld(key) return controls and controls:isHeld(key) or false end
  local function isSprinting() return controls and controls:isSprinting() or false end

  local function pointerPosition()
      local x,y=love.mouse.getPosition()
      if controls then return controls:pointer(x,y) end
      return x,y
  end

  local function draw(...)
      if controls then return controls:draw(...) end
  end

  local function mousepressed(x,y,button,isTouch,...)
      if controls and controls:ignoreSyntheticMouse(isTouch) then return end
      return gameplayInput().mousepressed(x,y,button,...)
  end

  local function mousemoved(x,y,dx,dy,isTouch,...)
      if controls and controls:ignoreSyntheticMouse(isTouch) then return end
      return gameplayInput().mousemoved(x,y,dx,dy,...)
  end

  local function mousereleased(x,y,button,isTouch,...)
      if controls and controls:ignoreSyntheticMouse(isTouch) then return end
      return gameplayInput().mousereleased(x,y,button,...)
  end

  local function keypressed(key,...)
      if key=="acback" then key="escape" end
      return gameplayInput().keypressed(key,...)
  end

  local function keyreleased(...) return gameplayInput().keyreleased(...) end
  local function touchpressed(...) return controls and controls:touchpressed(...) end
  local function touchmoved(...) return controls and controls:touchmoved(...) end
  local function touchreleased(...) return controls and controls:touchreleased(...) end

  local function focus(focused)
      if not focused and controls then controls:cancelAll() end
  end

  return {
      initialize=initialize,
      get=get,
      isEnabled=isEnabled,
      movement=movement,
      isHeld=isHeld,
      isSprinting=isSprinting,
      pointerPosition=pointerPosition,
      draw=draw,
      mousepressed=mousepressed,
      mousemoved=mousemoved,
      mousereleased=mousereleased,
      keypressed=keypressed,
      keyreleased=keyreleased,
      touchpressed=touchpressed,
      touchmoved=touchmoved,
      touchreleased=touchreleased,
      focus=focus,
  }
end

return {new=new}
