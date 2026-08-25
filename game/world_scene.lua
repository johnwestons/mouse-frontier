local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"world scene requires "..name)
  if expected then assert(type(value)==expected,"world scene "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","world scene requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local scenery=required(context,"scenery","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local House=required(context,"house","table")
  local Stops=required(context,"stops","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Wildlife=required(context,"wildlife","table")
  local Mice=required(context,"mice","table")
  local StopSludges=required(context,"stopSludges","table")
  local getIsWeapon=required(context,"getIsWeapon","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local writeSave=required(context,"writeSave","function")
  local activeStopSludges=StopSludges.new()

  local function isWeapon(name)
      local check=getIsWeapon()
      assert(type(check)=="function","world scene requires an available weapon check")
      return check(name)
  end

  local function resetStopSludges()
      activeStopSludges=StopSludges.new()
  end

  local function ensureStopLayout()
      return Stops.ensure(runtime.saveData,Catalog,runtime.scene)
  end

  local function ensureHouseItems()
      House.ensure(runtime.saveData,Catalog,isFurnitureItem)
  end

  local function itemIsHere(item)
      if item.scene~=runtime.scene then return false end
      if runtime.scene=="train" then return (item.carIndex or 1)==(runtime.saveData.activeCar or 1) end
      if runtime.scene=="house" then return item.location==runtime.saveData.location and (item.houseDoor or 1)==(runtime.saveData.activeHouseDoor or 1) end
      return item.location==runtime.saveData.location
  end

  local function setupNPC()
      if runtime.scene=="train" then runtime.npcActor=nil; return end
      local layout=ensureStopLayout()
      runtime.saveData.currentNPC=(runtime.scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
      local key=Util.sceneKey(runtime.scene,runtime.saveData.location)..(runtime.scene=="house" and (":"..tostring(runtime.saveData.activeHouseDoor or 1)) or "")
      local saved=runtime.saveData.npcStates[key]
      local defaults=runtime.scene=="house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
      saved=saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
      saved.weapon=saved.weapon or layout.npcWeapon
      if runtime.scene=="house" then
          saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
          saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
      elseif runtime.scene=="stop" then
          saved.x,saved.y=Settlements.clamp(saved.x,saved.y,runtime.saveData.location)
          saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,runtime.saveData.location)
      end
      runtime.saveData.npcStates[key]=saved
      runtime.npcActor=saved
      Family.ensure(runtime.npcActor,runtime.saveData.currentNPC)
  end

  local function updateStopSludges(dt)
      if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return end
      StopSludges.update(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          clamp=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
          dropCoal=function(x,y)
              runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=runtime.saveData.location,droppedByPlayer=false}
              writeSave()
          end},dt)
  end

  local function attackStopSludge(x,y)
      if runtime.scene~="stop" or runtime.inventoryOpen or runtime.mapOpen or runtime.dialogue or runtime.editMode or ui.radioOpen or runtime.trainUpgradeOpen or runtime.poseMenu or ui.optionsOpen then return false end
      return StopSludges.attack(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          onAction=function(weapon) runtime.actionHeldItem=weapon; runtime.actionKind="melee"; runtime.actionTimer=.42 end,
          playSfx=function(kind) ui.playSfx(kind) end},x,y)
  end

  local function updateWildlife(dt)
      if runtime.scene~="stop" or not runtime.saveData then return end
      local layout=ensureStopLayout()
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      Wildlife.update(layout.wildlife,dt,runtime.saveData.location,Settlements)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.update(layout.mice,dt,runtime.saveData.location,Settlements)
  end

  local function update(dt)
      updateStopSludges(dt)
      updateWildlife(dt)
  end

  local function drawStopSludges(images)
      StopSludges.draw(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,clock=runtime.animationClock,images=images})
  end

  local function drawWildlife(layout)
      if not layout or runtime.scene~="stop" then return end
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      Wildlife.draw(layout.wildlife,scenery.stopWildlife,runtime.animationClock)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.draw(layout.mice,scenery.stopWildlife,runtime.animationClock)
  end

  return {
      resetStopSludges=resetStopSludges,
      ensureStopLayout=ensureStopLayout,
      ensureHouseItems=ensureHouseItems,
      itemIsHere=itemIsHere,
      setupNPC=setupNPC,
      update=update,
      attackStopSludge=attackStopSludge,
      drawStopSludges=drawStopSludges,
      drawWildlife=drawWildlife,
  }
end

return {new=new}
