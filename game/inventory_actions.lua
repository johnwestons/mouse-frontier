local Consumables=require("game.consumables")
local Items=require("game.item_instances")
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
  local commands=context.commands
  local function personalData()
      local b=runtime.state=='battle' and runtime.battle
      local u=b and b.units[b.active]
      if u and require('game.battle_actors').id(u) then return require('game.battle_actors').data(runtime.saveData,u) end
      return runtime.saveData
  end

  local function commandArgs(source,target,needsContainer)
      local args={source=source,target=target}
      if needsContainer or (source and source.kind=="chest") or (target and target.kind=="chest") then
          args.containerId=commands.identify(runtime.activeChest)
      end
      return args
  end

  local function isWeapon(name) return Inventory.isWeapon(name,Catalog.weaponStats) end

  local function containerValue(ref)
      return Inventory.value(personalData(),runtime.activeChest,ref)
  end

  local function setContainerValue(ref,value)
      Inventory.setValue(runtime.saveData,runtime.activeChest,ref,value,Catalog.wearableItems)
  end

  local function inventoryResult(speaker,text,timer)
      runtime.dialogue={speaker=speaker,text=text,timer=timer,inventoryResult=true}
  end

  local function moveBetweenSlots(source,target)
      if commands then
          local state=runtime.saveData.tacticalBattle
          if state and runtime.state=='battle' then
              local b=state.battle; local u=b.units[b.active]
              local data=require('game.battle_actors').data(runtime.saveData,u)
              local contract=require('game.coop_item_contract')
              local result=commands.submit('battle.swap',{encounterId=state.encounterId,turnRevision=state.revision,unitId=u.id,
                  source=source,target=target,sourceItem=contract.selection(data,nil,source),targetItem=contract.selection(data,nil,target)})
              return result.ok,result.reason
          end
          local result=commands.submit("inventory.swap",commandArgs(source,target))
          if result.ok then writeSave() end
          return result.ok,result.reason
      end
      local moved,reason=Inventory.move(runtime.saveData,runtime.activeChest,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems)
      if moved then writeSave() end
      return moved,reason
  end

  local function quickTransfer(ref)
      if not runtime.chestOpen then return false end
      if commands then
          local result=commands.submit("storage.transfer",commandArgs(ref,nil,true))
          if result.ok then writeSave() end
          return result.ok,result.reason
      end
      local moved=Inventory.quickTransfer(runtime.saveData,runtime.activeChest,ref,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems)
      if moved then writeSave() end
      return moved
  end

  local function collectAmmo(ref)
      if not ref or ref.kind~="chest" then return false end
      local name=containerValue(ref); local amount=name and Catalog.ammoPickupAmounts[name]
      if not amount then return false end
      if commands then
          local result=commands.submit("mailbox.collect",commandArgs(ref,nil,true))
          if not result.ok then return false,result.reason end
      else
          runtime.saveData.ammo[name]=(runtime.saveData.ammo[name] or 0)+amount
          setContainerValue(ref,nil)
      end
      runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave()
      inventoryResult("Ammo","Collected "..amount.." "..Util.titleFromFile(name).." ammunition.",1.6)
      return true
  end

  local function dropFromContainer(ref)
      if commands then
          local result=commands.submit("loot.drop",commandArgs(ref))
          if not result.ok then
              if result.reason=="backpack_full" then inventoryResult("Backpack Full","Move items out of the extra backpack slots before removing it.",2.2) end
              return false,result.reason
          end
          runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      local name=containerValue(ref); if not name then return false end
      if ref.kind=="wearable" and ref.slot=="backpack" then
          local canRemove=Inventory.canChangeBackpack(runtime.saveData,nil,Catalog.wearableItems)
          if not canRemove then
              inventoryResult("Backpack Full","Move items out of the extra backpack slots before removing it.",2.2)
              return false
          end
      end
      local dropped={name=name,x=runtime.player.x+35,y=runtime.player.y,scene=runtime.scene,scale=1,rotation=0,droppedByPlayer=true}
      dropped.itemInstance=Items.get(runtime.saveData,runtime.activeChest,ref)
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
          if commands then
              local passenger=runtime.nearPassenger and runtime.saveData.passengers[runtime.nearPassenger]
              local recipient=passenger and passenger.npc or runtime.saveData.currentNPC
              local result=commands.gift(recipient,runtime.draggedSlot,runtime.activeChest,true)
              if not result.ok then return false,result.reason end
          elseif runtime.nearPassenger then
              local passenger=runtime.saveData.passengers[runtime.nearPassenger]
              passenger.weapon=name; passenger.weaponInstance=Items.get(runtime.saveData,runtime.activeChest,runtime.draggedSlot)
          else
              local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]
              if layout then layout.npcWeapon=name; layout.npcWeaponInstance=Items.get(runtime.saveData,runtime.activeChest,runtime.draggedSlot) end
              if runtime.npcActor then runtime.npcActor.weapon=name end
          end
          inventoryResult("Weapon Given",Util.titleFromFile(name).." is now equipped by your ally.",2)
          if not commands then setContainerValue(runtime.draggedSlot,nil) end
          runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
      end
      local wearable=Catalog.wearableItems[name]
      if wearable then
          local source=runtime.draggedSlot
          local target
          if source.kind=="wearable" then
              local slot=Inventory.firstEmptySlot(runtime.saveData)
              if not slot then
                  inventoryResult("Inventory Full","Free a backpack slot before removing this gear upgrade.",2.2)
                  return false
              end
              target={kind="inventory",index=slot}
          else target={kind="wearable",slot=wearable.slot} end
          local moved,reason=moveBetweenSlots(source,target)
          if not moved then
              -- Domain explanations are UI text; wire rejection codes are not.
              if reason and reason:find(" ",1,true) then inventoryResult("Gear Upgrades",reason,2.2)
              else inventoryResult("Gear Upgrades","That item cannot be placed in this upgrade slot.",2.2) end
              return false
          end
          runtime.inventoryMode="wearables"
          local result=source.kind=="wearable" and "Gear upgrade removed." or (wearable.slot=="backpack" and "Backpack equipped." or "Outfit upgrade installed.")
          if wearable.slot=="backpack" then result=result.." Backpack capacity: "..(runtime.saveData.inventoryCapacity or 6).." slots." end
          inventoryResult("Gear Upgrades",result,2)
          runtime.draggedSlot=nil; runtime.inventoryDragActive=false; return true
      end
      local result
      if commands then
          local reply=commands.submit("inventory.consume",commandArgs(runtime.draggedSlot))
          result=reply.ok and reply.result or {ok=false,reason=reply.reason}
      else
          result=Consumables.use(runtime.saveData,Catalog,TrainUpgradeBalance,name)
          if result.ok then setContainerValue(runtime.draggedSlot,nil) end
      end
      if not result.ok then
          if result.reason=="storage_full" then
              local foodFull=effect.food and runtime.saveData.resources.food>=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"food")
              local waterFull=effect.water and runtime.saveData.resources.water>=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"water")
              local oilFull=effect.oil and runtime.saveData.resources.oil>=TrainUpgradeBalance.resourceCapacity(runtime.saveData,"oil")
              local fullName=oilFull and "Oil storage is full." or (foodFull and waterFull and "Food and water storage are full." or (foodFull and "Food storage is full." or "Water storage is full."))
              inventoryResult("Storage Full",fullName,2.2)
          end
          return false,result.reason
      end
      if result.heart then inventoryResult("Special Heart","Your maximum health increased by 5!",2.5)
      elseif result.potion then inventoryResult(Util.titleFromFile(name),effect.description.." It will activate at the next battle.",2.5)
      else inventoryResult(Util.titleFromFile(name),effect.oil and ("Stored +"..effect.oil.." train oil.") or ("That helped. "..(effect.health and ("+"..effect.health.." health") or "Supplies restored.")),1.4) end
      runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave(); return true
  end

  local function pickUpNearby()
      if not runtime.nearbyItem then return end
      local item=runtime.saveData.droppedItems[runtime.nearbyItem]
      if not item then runtime.nearbyItem=nil; return end
      if commands then
          local result=commands.submit("loot.pickup",{entityId=commands.identify(item)})
          if result.ok then
              if result.result.heart then runtime.dialogue={speaker="Special Heart",text="Your maximum health increased by 5!",timer=2.5}
              elseif result.result.amount then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="Picked up "..result.result.amount.." rounds.",timer=1.6} end
              runtime.nearbyItem=nil; writeSave()
          elseif result.reason=="permanent" then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}
          elseif result.reason=="container_not_empty" then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}
          elseif result.reason=="inventory_full" then runtime.dialogue={speaker="Backpack Full",text="There is no room in your backpack.",timer=2.2} end
          return result.ok,result.reason
      end
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
      Inventory.setValue(runtime.saveData,nil,{kind="inventory",index=slot},item.name,Catalog.wearableItems,item.itemInstance)
      table.remove(runtime.saveData.droppedItems,runtime.nearbyItem); runtime.nearbyItem=nil; writeSave()
  end

  local function addCoalToFire()
      local result
      if commands then
          local reply=commands.submit("train.fuel",{})
          result=reply.ok and reply.result or {ok=false,reason=reply.reason}
      else result=Consumables.fuel(runtime.saveData,TrainUpgradeBalance) end
      if not result.ok then
          if result.reason=="storage_full" then runtime.dialogue={speaker="Storage Full",text="Coal storage is full.",timer=2.2}
          elseif result.reason=="missing_coal" then runtime.dialogue={speaker="Fire",text="Coal from the backpack is required.",timer=2} end
          return false,result.reason
      end
      runtime.dialogue={speaker="Fire",text="Fuel added: +"..result.gained.." fuel",timer=2}
      writeSave()
      return true
  end

  local function giveWeaponToNearby()
      local targetPassenger=runtime.nearPassenger and runtime.saveData.passengers[runtime.nearPassenger]
      if not runtime.nearNPC and not targetPassenger then return false end
      runtime.giftOpen=true
      runtime.giftNPC=targetPassenger and targetPassenger.npc or runtime.saveData.currentNPC
      runtime.giftSlot=nil; runtime.inventoryOpen=true; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil
      return true
  end

  local function repairStatus(name)
      return LootProgression.repairStatus(runtime.saveData,Catalog,name)
  end
  local function repairElapsed(startedAt)
      local now=commands and commands.clock and commands.clock() or runtime.animationClock
      return math.max(0,now-startedAt)
  end

  local function repairEquipped()
      runtime.weaponRepairOpen=true
      runtime.weaponRepairSelected=runtime.weaponRepairSelected or (LootProgression.repairChoices(runtime.saveData,Catalog)[1])
      return repairStatus(runtime.weaponRepairSelected)
  end

  local repairLease
  local function cancelWeaponRepair()
      if repairLease and commands then commands.submit("activity.release",{leaseId=repairLease.leaseId}) end
      repairLease=nil
  end

  local function beginWeaponRepair(name)
      cancelWeaponRepair()
      if not commands then return {ok=true,startedAt=runtime.animationClock} end
      local reply=commands.submit("weaponRepair.acquire",{itemId=name})
      if reply.ok then repairLease=reply.result; return reply.result end
      runtime.weaponRepairMessage=reply.reason=="activity_busy" and "The workbench is in use."
          or "Repair is unavailable. Return to the stopped train and check your weapon and supplies."
      return {ok=false,reason=reply.reason}
  end

  local function repairWeapon(name,quality)
      local result
      if commands then
          if not repairLease or repairLease.itemId~=name then result={ok=false,reason="lease_expired"}
          else
              local reply=commands.submit("weaponRepair.complete",{leaseId=repairLease.leaseId})
              result=reply.ok and reply.result or {ok=false,reason=reply.reason}
          end
          cancelWeaponRepair()
      else result=LootProgression.completeRepair(runtime.saveData,Catalog,name,quality) end
      if result.ok then
          runtime.weaponRepairMessage="Repair complete: "..Util.titleFromFile(result.name).." at "..result.restored.."% condition."
          writeSave()
      elseif result.reason=="miss" then
          runtime.weaponRepairMessage="Missed the mark. No scrap or parts were used."
      elseif result.reason=="precision" then
          runtime.weaponRepairMessage="A perfect hit is needed above 95%. No scrap or parts were used."
      elseif result.reason=="part" then
          runtime.weaponRepairMessage="Required part is missing from your backpack."
      elseif result.reason=="scrap" then
          runtime.weaponRepairMessage="Not enough scrap for this repair."
      elseif result.reason=="ready" then
          runtime.weaponRepairMessage="This weapon does not need repair."
      elseif result.reason=="lease_expired" or result.reason=="activity_changed" or result.reason=="activity_unavailable" or result.reason=="stale_revision" then
          runtime.weaponRepairMessage="Repair attempt ended. Check your weapon and start again."
      else
          runtime.weaponRepairMessage="Select a weapon you own."
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
    personalData=personalData,
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
    repairElapsed=repairElapsed,
    repairEquipped=repairEquipped,
    repairWeapon=repairWeapon,
    beginWeaponRepair=beginWeaponRepair,cancelWeaponRepair=cancelWeaponRepair,
    balanceAudit=function() return LootProgression.audit(Catalog) end,
    consumeBattleSelected=consumeBattleSelected
  }
end

return {new=new}
