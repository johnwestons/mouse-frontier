local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"train-car runtime requires "..name)
  if expected then assert(type(value)==expected,"train-car runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","train-car runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local scenery=required(context,"scenery","table")
  local car=required(context,"car","table")
  local Train=required(context,"train","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local writeSave=required(context,"writeSave","function")

  local function activeImage()
      local data=runtime.saveData
      local carId=data and data.trainCars and data.trainCars[data.activeCar or 1] or "living-car"
      return scenery.trainCarImages and scenery.trainCarImages[carId]
  end

  local function floorBounds()
      return Train.characterBounds(car,activeImage(),30)
  end

  local function objectBounds()
      -- Editor placement is intentionally unconstrained: objects may be
      -- arranged anywhere in the visible game canvas.
      return 0,W,0,H
  end

  local function clampToFloor(x,y)
      return Train.clampCharacterToFloor(car,activeImage(),x,y,30)
  end

  local function beginTransition(targetIndex)
      if runtime.carTransition or runtime.scene~="train" or not runtime.saveData then return false end
      local current=runtime.saveData.activeCar or 1
      targetIndex=math.max(1,math.min(#(runtime.saveData.trainCars or {}),targetIndex))
      if targetIndex==current then return false end
      local left,right,top,bottom=floorBounds()
      runtime.carTransition={
          from=current,
          to=targetIndex,
          t=0,
          duration=.78,
          targetX=targetIndex>current and left or right,
          targetY=(top+bottom)/2,
      }
      runtime.player.moving=false
      runtime.nearbyItem=nil
      runtime.nearChest=nil
      runtime.nearCarNext=false
      runtime.nearCarPrev=false
      ui.playSfx("trainDoor")
      return true
  end

  local function updateTransition(dt)
      local transition=runtime.carTransition
      if not transition then return false end
      transition.t=math.min(transition.duration,transition.t+dt)
      runtime.player.moving=false
      if transition.t>=transition.duration then
          runtime.saveData.activeCar=transition.to
          runtime.player.x,runtime.player.y=transition.targetX,transition.targetY
          runtime.carTransition=nil
          writeSave()
      end
      return true
  end

  local function editedItem()
      return runtime.editedItem and runtime.saveData and runtime.saveData.droppedItems[runtime.editedItem]
  end

  local function placeEditedItem(x,y)
      local item=editedItem()
      if not item then return false end
      local left,right,top,bottom=objectBounds()
      item.x=math.max(left,math.min(right,x))
      item.y=math.max(top,math.min(bottom,y))
      return true
  end

  local function moveEditedItem(dx,dy)
      local item=editedItem()
      if not item or not placeEditedItem(item.x+dx,item.y+dy) then return false end
      writeSave()
      return true
  end

  local function enterTrain(playDoorSound)
      if playDoorSound then ui.playSfx("trainDoor") end
      local _,right,top,bottom=floorBounds()
      runtime.scene="train"
      runtime.npcActor=nil
      runtime.player.x,runtime.player.y=right,(top+bottom)/2
      writeSave()
      return true
  end

  return {
      activeImage=activeImage,
      floorBounds=floorBounds,
      objectBounds=objectBounds,
      clampToFloor=clampToFloor,
      beginTransition=beginTransition,
      updateTransition=updateTransition,
      placeEditedItem=placeEditedItem,
      moveEditedItem=moveEditedItem,
      enterTrain=enterTrain,
  }
end

return {new=new}
