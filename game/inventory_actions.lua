local function install(resolve,assign)
  assert(type(resolve)=="function","inventory actions require a dependency resolver")
  assert(type(assign)=="function","inventory actions require a dependency writer")
  local env=setmetatable({}, {
    __index=function(_,key)
      local value=resolve(key)
      if value~=nil then return value end
      return _G[key]
    end,
    __newindex=function(_,key,value)
      if not assign(key,value) then error("inventory actions cannot assign "..tostring(key),2) end
    end
  })
  setfenv(install,env)

  local function isWeapon(name) return Inventory.isWeapon(name,Catalog.weaponStats) end

  local function containerValue(ref)
      return Inventory.value(saveData,activeChest,ref)
  end

  local function setContainerValue(ref,value)
      Inventory.setValue(saveData,activeChest,ref,value)
  end

  local function moveBetweenSlots(source,target)
      local moved=Inventory.move(saveData,activeChest,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts)
      if moved then writeSave() end
      return moved
  end

  local function quickTransfer(ref)
      if not chestOpen then return false end
      local moved=Inventory.quickTransfer(saveData,activeChest,ref,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.storageCapacities)
      if moved then writeSave() end
      return moved
  end

  local function collectAmmo(ref)
      if not ref or ref.kind~="chest" then return false end
      local name=containerValue(ref); local amount=name and Catalog.ammoPickupAmounts[name]
      if not amount then return false end
      saveData.ammo[name]=(saveData.ammo[name] or 0)+amount
      setContainerValue(ref,nil); draggedSlot=nil; inventoryDragActive=false; writeSave()
      dialogue={speaker="Ammo",text="Collected "..amount.." "..Util.titleFromFile(name).." ammunition.",timer=1.6}
      return true
  end

  local function dropFromContainer(ref)
      local name=containerValue(ref); if not name then return false end
      local dropped={name=name,x=player.x+35,y=player.y,scene=scene,scale=1,rotation=0,droppedByPlayer=true}
      if scene=="train" then dropped.carIndex=saveData.activeCar or 1 end
      if scene~="train" then dropped.location=saveData.location end
      if Catalog.storageCapacities[name] then dropped.storage={} end
      saveData.droppedItems[#saveData.droppedItems+1]=dropped
      setContainerValue(ref,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
  end

  local function consumeSelected()
      if not draggedSlot then return false end
      local name=containerValue(draggedSlot); local effect=Catalog.itemEffects[name]
      actionHeldItem=name; actionKind="use"; actionTimer=.45
      if isWeapon(name) and (nearNPC or nearPassenger) then
          if nearPassenger then saveData.passengers[nearPassenger].weapon=name
          else local layout=saveData.stopLayouts[tostring(saveData.location)]; if layout then layout.npcWeapon=name end; if npcActor then npcActor.weapon=name end end
          dialogue={speaker="Weapon Given",text=Util.titleFromFile(name).." is now equipped by your ally.",timer=2}
          setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
      end
      local pack=Catalog.backpackUpgrades[name]
      if pack then
          if pack.capacity<=(saveData.inventoryCapacity or 6) then dialogue={speaker=pack.label,text="Your current backpack already carries at least that much.",timer=2}; return false end
          saveData.inventoryCapacity=pack.capacity; saveData.backpack=name
          dialogue={speaker=pack.label,text="Equipped! Carry capacity increased to "..pack.capacity.." slots.",timer=2.5}
          setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
      end
      if name=="rose-heart-arrow" or name=="blade-hearts" then
          saveData.maxHealth=saveData.maxHealth+5; saveData.health=math.min(saveData.maxHealth,saveData.health+5)
          dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
          setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
      end
      if effect and effect.potion then
          saveData.nextBattlePotions[name]=true
          dialogue={speaker=Util.titleFromFile(name),text=effect.description.." It will activate at the next battle.",timer=2.5}
          setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
      end
      if not effect then return false end
      local capacity=20; for _,id in ipairs(saveData.trainCars or {}) do if id=="storage" then capacity=30; break end end
      local foodFull=effect.food and saveData.resources.food>=capacity
      local waterFull=effect.water and saveData.resources.water>=capacity
      local oilFull=effect.oil and saveData.resources.oil>=capacity
      if (effect.food or effect.water or effect.oil) and (not effect.food or foodFull) and (not effect.water or waterFull) and (not effect.oil or oilFull) then
          local fullName=oilFull and "Oil storage is full." or (foodFull and waterFull and "Food and water storage are full." or (foodFull and "Food storage is full." or "Water storage is full."))
          dialogue={speaker="Storage Full",text=fullName,timer=2.2}
          return false
      end
      if effect.food then saveData.resources.food=math.min(capacity,saveData.resources.food+effect.food) end
      if effect.water then saveData.resources.water=math.min(capacity,saveData.resources.water+effect.water) end
      if effect.oil then saveData.resources.oil=math.min(capacity,saveData.resources.oil+effect.oil) end
      if effect.health then saveData.health=math.min(saveData.maxHealth,saveData.health+effect.health) end
      dialogue={speaker=Util.titleFromFile(name),text=effect.oil and ("Stored +"..effect.oil.." train oil.") or ("That helped. "..(effect.health and ("+"..effect.health.." health") or "Supplies restored.")),timer=1.4}
      setContainerValue(draggedSlot,nil); draggedSlot=nil; inventoryDragActive=false; writeSave(); return true
  end

  local function pickUpNearby()
      if not nearbyItem then return end
      local item=saveData.droppedItems[nearbyItem]
      if item.permanent then dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; return end
      if item.name=="rose-heart-arrow" or item.name=="blade-hearts" then
          saveData.maxHealth=saveData.maxHealth+5; saveData.health=math.min(saveData.maxHealth,saveData.health+5)
          dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
          table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave(); return
      end
      if Catalog.ammoPickupAmounts[item.name] then
          local amount=Catalog.ammoPickupAmounts[item.name]; saveData.ammo[item.name]=(saveData.ammo[item.name] or 0)+amount
          dialogue={speaker=Util.titleFromFile(item.name),text="Picked up "..amount.." rounds.",timer=1.6}
          table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave(); return
      end
      if Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; return end
      local slot=Inventory.firstEmptySlot(saveData)
      if not slot then
          dialogue={speaker="Backpack Full",text="There is no room in your backpack.",timer=2.2}
          return
      end
      saveData.inventory[slot]=item.name
      table.remove(saveData.droppedItems,nearbyItem); nearbyItem=nil; writeSave()
  end

  local function findInventoryItem(names)
      for i = 1, (saveData.inventoryCapacity or 6) do
          for _, name in ipairs(names) do if saveData.inventory[i] == name then return i, name end end
      end
  end

  local function addCoalToFire()
      local coalCapacity=20
      for _,id in ipairs(saveData.trainCars or {}) do if id=="coal-hauler" then coalCapacity=30; break end end
      if saveData.resources.coal>=coalCapacity then
          dialogue={speaker="Storage Full",text="Coal storage is full.",timer=2.2}
          return
      end
      local slot, name = findInventoryItem({"coal-bucket", "coal-chunk"})
      if not slot then dialogue = {speaker="Fire", text="Bring me coal from your backpack!", timer=2}; return end
      local amount = name == "coal-bucket" and 3 or 1
      saveData.inventory[slot] = nil
      saveData.resources.coal = math.min(coalCapacity, saveData.resources.coal + amount)
      dialogue = {speaker="Fire", text="That's the good stuff!  +"..amount.." fuel", timer=2}
      writeSave()
  end

  local function giveWeaponToNearby()
      local targetPassenger=nearPassenger and saveData.passengers[nearPassenger]
      if not nearNPC and not targetPassenger then return false end
      giftOpen=true; giftNPC=targetPassenger and targetPassenger.npc or saveData.currentNPC; giftSlot=nil; inventoryOpen=true; chestOpen=false; activeChest=nil; draggedSlot=nil
      return true
  end

  local function consumeBattleSelected()
      if not draggedSlot then return false end
      local name=containerValue(draggedSlot); if not name then return false end
      local effect=Catalog.itemEffects[name]
      if isWeapon(name) then
          local moved=moveBetweenSlots(draggedSlot,{kind="equipment",index=1})
          if moved then draggedSlot=nil; inventoryDragActive=false; writeSave() end
          return moved
      end
      local used=(effect and effect.health and BattleController.useHealingItem(battleContext(),name)) or (effect and effect.potion and useBattlePotion(name))
      if used then draggedSlot=nil; inventoryDragActive=false; inventoryOpen=false end
      return used or false
  end

  return {
    isWeapon=isWeapon,
    containerValue=containerValue,
    setContainerValue=setContainerValue,
    moveBetweenSlots=moveBetweenSlots,
    quickTransfer=quickTransfer,
    collectAmmo=collectAmmo,
    dropFromContainer=dropFromContainer,
    consumeSelected=consumeSelected,
    pickUpNearby=pickUpNearby,
    addCoalToFire=addCoalToFire,
    giveWeaponToNearby=giveWeaponToNearby,
    consumeBattleSelected=consumeBattleSelected
  }
end

return {install=install}
