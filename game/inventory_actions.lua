local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"inventory actions require "..name)
  if expectedType then assert(type(value)==expectedType,"inventory actions "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","inventory actions require an explicit context")
  local runtime=required(context,"runtime","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local LootProgression=required(context,"lootProgression","table")
  local writeSave=required(context,"writeSave","function")
  local useBattleHealingItem=required(context,"useBattleHealingItem","function")
  local useBattlePotion=required(context,"useBattlePotion","function")

  local function isWeapon(name) return Inventory.isWeapon(name,Catalog.weaponStats) end

  local function containerValue(ref)
      return Inventory.value(runtime.saveData,runtime.activeChest,ref)
  end

  local function setContainerValue(ref,value)
      Inventory.setValue(runtime.saveData,runtime.activeChest,ref,value)
  end

  local function moveBetweenSlots(source,target)
      local moved=Inventory.move(runtime.saveData,runtime.activeChest,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts)
      if moved then writeSave() end
      return moved
  end

  local function quickTransfer(ref)
      if not runtime.chestOpen then return false end
      local moved=Inventory.quickTransfer(runtime.saveData,runtime.activeChest,ref,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.storageCapacities)
      if moved then writeSave() end
      return moved
  end

  local function collectAmmo(ref)
      if not ref or ref.kind~="chest" then return false end
      local name=containerValue(ref); local amount=name and Catalog.ammoPickupAmounts[name]
      if not amount then return false end
      runtime.saveData.ammo[name]=(runtime.saveData.ammo[name] or 0)+amount
      setContainerValue(ref,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave()
      runtime.dialogue={speaker="Ammo",text="Collected "..amount.." "..Util.titleFromFile(name).." ammunition.",timer=1.6}
      return true
  end

  local function dropFromContainer(ref)
      local name=containerValue(ref); if not name then return false end
      local dropped={name=name,x=runtime.player.x+35,y=runtime.player.y,scene=runtime.scene,scale=1,rotation=0,droppedByPlayer=true}
      if runtime.scene=="train" then dropped.carIndex=runtime.saveData.activeCar or 1 end
      if runtime.scene~="train" then dropped.location=runtime.saveData.location end
      if runtime.scene=="house" then dropped.houseDoor=runtime.saveData.activeHouseDoor or runtime.saveData.lastStopDoor or 1 end
      if runtime.scene=="expedition" then dropped.expeditionAreaId=runtime.saveData.activeExpeditionArea end
      if runtime.scene=="caravan" then dropped.caravanCampId=runtime.saveData.crowCaravans and runtime.saveData.crowCaravans.activeCampId end
      if Catalog.storageCapacities[name] then dropped.storage={} end
      runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]=dropped
      setContainerValue(ref,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
  end

  local function consumeSelected()
      if not runtime.draggedSlot then return false end
      local name=containerValue(runtime.draggedSlot); local effect=Catalog.itemEffects[name]
      runtime.actionHeldItem=name; runtime.actionKind="use"; runtime.actionTimer=.45
      if isWeapon(name) and (runtime.nearNPC or runtime.nearPassenger) then
          if runtime.nearPassenger then runtime.saveData.passengers[runtime.nearPassenger].weapon=name
          else
              local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]
              if layout then layout.npcWeapon=name end
              if runtime.npcActor then runtime.npcActor.weapon=name end
          end
          runtime.dialogue={speaker="Weapon Given",text=Util.titleFromFile(name).." is now equipped by your ally.",timer=2}
          setContainerValue(runtime.draggedSlot,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      local pack=Catalog.backpackUpgrades[name]
      if pack then
          if pack.capacity<=(runtime.saveData.inventoryCapacity or 6) then runtime.dialogue={speaker=pack.label,text="Your current backpack already carries at least that much.",timer=2}; return false end
          runtime.saveData.inventoryCapacity=pack.capacity; runtime.saveData.backpack=name
          runtime.dialogue={speaker=pack.label,text="Equipped! Carry capacity increased to "..pack.capacity.." slots.",timer=2.5}
          setContainerValue(runtime.draggedSlot,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      if name=="rose-heart-arrow" or name=="blade-hearts" then
          runtime.saveData.maxHealth=runtime.saveData.maxHealth+5; runtime.saveData.health=math.min(runtime.saveData.maxHealth,runtime.saveData.health+5)
          runtime.dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
          setContainerValue(runtime.draggedSlot,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      if effect and effect.potion then
          runtime.saveData.nextBattlePotions[name]=true
          runtime.dialogue={speaker=Util.titleFromFile(name),text=effect.description.." It will activate at the next battle.",timer=2.5}
          setContainerValue(runtime.draggedSlot,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      if not effect then return false end
      local foodCapacity=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"food")
      local waterCapacity=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"water")
      local oilCapacity=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"oil")
      local foodFull=effect.food and runtime.saveData.resources.food>=foodCapacity
      local waterFull=effect.water and runtime.saveData.resources.water>=waterCapacity
      local oilFull=effect.oil and runtime.saveData.resources.oil>=oilCapacity
      if (effect.food or effect.water or effect.oil) and (not effect.food or foodFull) and (not effect.water or waterFull) and (not effect.oil or oilFull) then
          local fullName=oilFull and "Oil storage is full." or (foodFull and waterFull and "Food and water storage are full." or (foodFull and "Food storage is full." or "Water storage is full."))
          runtime.dialogue={speaker="Storage Full",text=fullName,timer=2.2}
          return false
      end
      if effect.food then TrainUpgradeBalance.addResource(runtime.saveData,"food",effect.food) end
      if effect.water then TrainUpgradeBalance.addResource(runtime.saveData,"water",effect.water) end
      if effect.oil then TrainUpgradeBalance.addResource(runtime.saveData,"oil",effect.oil) end
      if effect.health then runtime.saveData.health=math.min(runtime.saveData.maxHealth,runtime.saveData.health+effect.health) end
      runtime.dialogue={speaker=Util.titleFromFile(name),text=effect.oil and ("Stored +"..effect.oil.." train oil.") or ("That helped. "..(effect.health and ("+"..effect.health.." health") or "Supplies restored.")),timer=1.4}
      setContainerValue(runtime.draggedSlot,nil); runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
  end

  local function pickUpNearby()
      if not runtime.nearbyItem then return end
      local item=runtime.saveData.droppedItems[runtime.nearbyItem]
      if item.permanent then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; return end
      if item.name=="rose-heart-arrow" or item.name=="blade-hearts" then
          runtime.saveData.maxHealth=runtime.saveData.maxHealth+5; runtime.saveData.health=math.min(runtime.saveData.maxHealth,runtime.saveData.health+5)
          runtime.dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
          table.remove(runtime.saveData.droppedItems,runtime.nearbyItem); runtime.nearbyItem=nil; writeSave(); return
      end
      if Catalog.ammoPickupAmounts[item.name] then
          local amount=Catalog.ammoPickupAmounts[item.name]; runtime.saveData.ammo[item.name]=(runtime.saveData.ammo[item.name] or 0)+amount
          runtime.dialogue={speaker=Util.titleFromFile(item.name),text="Picked up "..amount.." rounds.",timer=1.6}
          table.remove(runtime.saveData.droppedItems,runtime.nearbyItem); runtime.nearbyItem=nil; writeSave(); return
      end
      if Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; return end
      local slot=Inventory.firstEmptySlot(runtime.saveData)
      if not slot then
          runtime.dialogue={speaker="Backpack Full",text="There is no room in your backpack.",timer=2.2}
          return
      end
      runtime.saveData.inventory[slot]=item.name
      table.remove(runtime.saveData.droppedItems,runtime.nearbyItem); runtime.nearbyItem=nil; writeSave()
  end

  local function findInventoryItem(names)
      for i=1,(runtime.saveData.inventoryCapacity or 6) do
          for _,name in ipairs(names) do if runtime.saveData.inventory[i]==name then return i,name end end
      end
  end

  local function addCoalToFire()
      local coalCapacity=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"coal")
      if runtime.saveData.resources.coal>=coalCapacity then
          runtime.dialogue={speaker="Storage Full",text="Coal storage is full.",timer=2.2}
          return
      end
      local slot,name=findInventoryItem({"coal-bucket","coal-chunk"})
      if not slot then runtime.dialogue={speaker="Fire",text="Bring me coal from your backpack!",timer=2}; return end
      local amount=name=="coal-bucket" and 3 or 1
      runtime.saveData.inventory[slot]=nil
      local gained=TrainUpgradeBalance.addResource(runtime.saveData,"coal",amount)
      runtime.dialogue={speaker="Fire",text="That's the good stuff!  +"..gained.." fuel",timer=2}
      writeSave()
  end

  local function giveWeaponToNearby()
      local targetPassenger=runtime.nearPassenger and runtime.saveData.passengers[runtime.nearPassenger]
      if not runtime.nearNPC and not targetPassenger then return false end
      runtime.giftOpen=true
      runtime.giftNPC=targetPassenger and targetPassenger.npc or runtime.saveData.currentNPC
      runtime.giftSlot=nil; runtime.inventoryOpen=true; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil
      return true
  end

  local function repairStatus()
      return LootProgression.repairStatus(runtime.saveData,Catalog)
  end

  local function repairEquipped()
      local result=LootProgression.repairEquipped(runtime.saveData,Catalog)
      if result.ok then
          runtime.dialogue={speaker="Train Workshop",text=Util.titleFromFile(result.name).." repaired to 100% for "..result.cost.." scrap.",timer=3}
          writeSave()
      end
      return result
  end

  local function consumeBattleSelected()
      if not runtime.draggedSlot then return false end
      local name=containerValue(runtime.draggedSlot); if not name then return false end
      local effect=Catalog.itemEffects[name]
      if isWeapon(name) then
          local moved=moveBetweenSlots(runtime.draggedSlot,{kind="equipment",index=1})
          if moved then runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave() end
          return moved
      end
      local used=(effect and effect.health and useBattleHealingItem(name)) or (effect and effect.potion and useBattlePotion(name))
      if used then runtime.draggedSlot=nil; runtime.inventoryDragActive=false; runtime.inventoryOpen=false end
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
    repairStatus=repairStatus,
    repairEquipped=repairEquipped,
    balanceAudit=function() return LootProgression.audit(Catalog) end,
    consumeBattleSelected=consumeBattleSelected
  }
end

return {new=new}
