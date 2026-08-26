local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"gameplay input requires "..name)
  if expectedType then assert(type(value)==expectedType,"gameplay input "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","gameplay input requires an explicit context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local characters=required(context,"characters","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local scenery=required(context,"scenery","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local readSave=required(context,"readSave","function")
  local removeSave=required(context,"removeSave","function")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Maintenance=required(context,"maintenance","table")
  local BattleRules=required(context,"battleRules","table")
  local Stops=required(context,"stops","table")
  local Settlements=required(context,"settlements","table")
  local InteriorDoors=required(context,"interiorDoors","table")
  local writeSave=required(context,"writeSave","function")
  local screenToGame=required(context,"screenToGame","function")
  local viewportToGame=required(context,"viewportToGame","function")
  local cameraPanning=required(context,"cameraPanning","function")
  local beginCameraPan=required(context,"beginCameraPan","function")
  local moveCameraPan=required(context,"moveCameraPan","function")
  local endCameraPan=required(context,"endCameraPan","function")
  local zoomCamera=required(context,"zoomCamera","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local isWeapon=required(context,"isWeapon","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local moveEditedItem=required(context,"moveEditedItem","function")
  local attackStopSludge=required(context,"attackStopSludge","function")
  local acceptQuest=required(context,"acceptQuest","function")
  local attemptLeaveTrain=required(context,"attemptLeaveTrain","function")
  local travelStatus=required(context,"travelStatus","function")
  local playTrainDepart=required(context,"playTrainDepart","function")
  local audioResetMusic=required(context,"audioResetMusic","function")
  local audioPreviousTrack=required(context,"audioPreviousTrack","function")
  local audioTogglePause=required(context,"audioTogglePause","function")
  local audioNextTrack=required(context,"audioNextTrack","function")
  local audioToggleMute=required(context,"audioToggleMute","function")
  local enterTrain=required(context,"enterTrain","function")
  local placeEditedItem=required(context,"placeEditedItem","function")
  local newSave=required(context,"newSave","function")
  local enterGame=required(context,"enterGame","function")
  local chooseEvent=required(context,"chooseEvent","function")
  local handleEventClick=required(context,"handleEventClick","function")
  local enterStop=required(context,"enterStop","function")
  local handleBattleMouse=required(context,"handleBattleMouse","function")
  local battleAttack=required(context,"battleAttack","function")
  local battleHeal=required(context,"battleHeal","function")
  local battleGuard=required(context,"battleGuard","function")
  local advanceBattleTurn=required(context,"advanceBattleTurn","function")
  local setBattlePrompt=required(context,"setBattlePrompt","function")
  local beginCarTransition=required(context,"beginCarTransition","function")
  local talkToNPC=required(context,"talkToNPC","function")
  local ensureHouseItems=required(context,"ensureHouseItems","function")
  local setupNPC=required(context,"setupNPC","function")
  local giveWeaponToNearby=required(context,"giveWeaponToNearby","function")
  local pickUpNearby=required(context,"pickUpNearby","function")
  local addCoalToFire=required(context,"addCoalToFire","function")
  local handleInventoryClick=required(context,"handleInventoryClick","function")
  local handleInventoryRelease=required(context,"handleInventoryRelease","function")
  local requestExitPrompt=required(context,"requestExitPrompt","function")
  local resolveExitPrompt=required(context,"resolveExitPrompt","function")
  local trainItemAt=required(context,"trainItemAt","function")
  local skipIntro=required(context,"skipIntro","function")
  local interactionMouseAction=required(context,"interactionMouseAction","function")
  local interactionKeyAction=required(context,"interactionKeyAction","function")
  local repairEquipped=required(context,"repairEquipped","function")

  local function startTravel()
      local status=travelStatus()
      if not status.affordable then
          runtime.travelConfirm=false
          runtime.dialogue={speaker="Supplies",text="The next leg still needs "..status.shortage..".",timer=3}
          return false
      end
      local cost=status.cost
      runtime.saveData.resources.food=runtime.saveData.resources.food-cost.food
      runtime.saveData.resources.water=runtime.saveData.resources.water-cost.water
      runtime.saveData.resources.coal=runtime.saveData.resources.coal-cost.coal
      runtime.travelConfirm=false
      runtime.travelTransition={t=0,changed=false,departSoundPlayed=true}
      playTrainDepart(); writeSave(); return true
  end

  function ui.offerGift(slot)
      local name=runtime.saveData.inventory[slot]; local accepted=isWeapon(name) or Catalog.itemEffects[name] or Catalog.backpackUpgrades[name] or name=="coal-chunk" or name=="coal-bucket"
      if accepted then
          local passenger; for _,p in ipairs(runtime.saveData.passengers or {}) do if p.npc==runtime.giftNPC then passenger=p; break end end
          if isWeapon(name) then
              if passenger then passenger.weapon=name
              else local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]; if layout then layout.npcWeapon=name end; if runtime.npcActor then runtime.npcActor.weapon=name end end
          end
          runtime.saveData.inventory[slot]=nil; runtime.dialogue={speaker="Gift Accepted",text=Util.titleFromFile(runtime.giftNPC).." accepted the gift of "..Util.titleFromFile(name)..".",timer=2}
      else runtime.dialogue={speaker=Util.titleFromFile(runtime.giftNPC),text="I don't need that right now.",timer=2} end
      runtime.giftOpen=false; runtime.inventoryOpen=false; runtime.giftSlot=nil; writeSave()
  end

  function ui.handlePoseClick(x,y)
      if Util.pointIn(x,y,ui.pose) then runtime.poseMenu=not runtime.poseMenu; ui.optionsOpen=false; ui.mobileMenuOpen=false; ui.playSfx("menu"); return true end
      if not runtime.poseMenu then return false end
      if Util.pointIn(x,y,ui.poseIdle) then runtime.playerPose="idle"
      elseif Util.pointIn(x,y,ui.poseSit) then runtime.playerPose="sit"
      elseif Util.pointIn(x,y,ui.poseLay) then runtime.playerPose="lay"
      elseif Util.pointIn(x,y,ui.poseAction) then runtime.playerPose="idle"; runtime.actionKind="use"; runtime.actionTimer=.45
      else return true end
      runtime.poseMenu=false; return true
  end

  function ui.handleTradeClick(x,y)
      local layout=ensureStopLayout()
      if Util.pointIn(x,y,ui.tradeClose) then runtime.tradeOpen=false; runtime.tradeNPC=nil; writeSave(); return true end
      for i,r in pairs(ui.tradeBuy or {}) do
          if Util.pointIn(x,y,r) then
              local name=layout.tradeStock and layout.tradeStock[i]; local price=name and Inventory.scrapPrice(name,Catalog) or 999; local slot=Inventory.firstEmptySlot(runtime.saveData)
              if slot and runtime.saveData.scrap>=price then runtime.saveData.scrap=runtime.saveData.scrap-price; runtime.saveData.inventory[slot]=name; layout.tradeStock[i]=nil; writeSave() end
              return true
          end
      end
      for i,r in pairs(ui.tradeSell or {}) do
          if Util.pointIn(x,y,r) and runtime.saveData.inventory[i] then
              local name=runtime.saveData.inventory[i]; local price=Inventory.resalePrice(name,Catalog,runtime.saveData)
              if (layout.tradeBudget or 0)>=price then layout.tradeBudget=layout.tradeBudget-price; runtime.saveData.scrap=runtime.saveData.scrap+price; runtime.saveData.inventory[i]=nil; writeSave() end
              return true
          end
      end
      for i,r in pairs(ui.tradeGive or {}) do
          if Util.pointIn(x,y,r) and isWeapon(runtime.saveData.inventory[i]) then layout.npcWeapon=runtime.saveData.inventory[i]; if runtime.npcActor then runtime.npcActor.weapon=layout.npcWeapon end; runtime.saveData.inventory[i]=nil; writeSave(); return true end
      end
      return true
  end

  function ui.handleBattleMousePressed(x,y,rightClick)
      return handleBattleMouse(x,y,rightClick)
  end

  function ui.handleRadioMousePressed(x,y)
      if not ui.radioOpen then return false end
      if Util.pointIn(x,y,ui.radio8bit) then runtime.saveData.audio.station="8bit"; audioResetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioChill) then local changed=runtime.saveData.audio.station~="chill"; runtime.saveData.audio.station="chill"; if changed then runtime.saveData.audio.rainEnabled=true end; audioResetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioVibes) then runtime.saveData.audio.station="vibes"; audioResetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioRain) then runtime.saveData.audio.rainEnabled=not runtime.saveData.audio.rainEnabled; ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioClose) then ui.radioOpen=false; ui.playSfx("menu") end
      return true
  end

  function ui.handleOptionsMousePressed(x,y)
      if not ui.optionsOpen then return false end
      if Util.pointIn(x,y,ui.options) then ui.optionsOpen=false; ui.playSfx("menu"); return true end
      if Util.pointIn(x,y,ui.pose) then ui.optionsOpen=false; runtime.poseMenu=true; ui.playSfx("menu"); return true end
      if Util.pointIn(x,y,ui.musicDown) then runtime.saveData.audio.musicVolume=math.max(0,(runtime.saveData.audio.musicVolume or .10)-.05)
      elseif Util.pointIn(x,y,ui.musicUp) then runtime.saveData.audio.musicVolume=math.min(1,(runtime.saveData.audio.musicVolume or .10)+.05)
      elseif Util.pointIn(x,y,ui.sfxDown) then runtime.saveData.audio.sfxVolume=math.max(0,(runtime.saveData.audio.sfxVolume or .55)-.05)
      elseif Util.pointIn(x,y,ui.sfxUp) then runtime.saveData.audio.sfxVolume=math.min(1,(runtime.saveData.audio.sfxVolume or .55)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.rainDown) then runtime.saveData.audio.rainVolume=math.max(0,(runtime.saveData.audio.rainVolume or .20)-.05)
      elseif Util.pointIn(x,y,ui.rainUp) then runtime.saveData.audio.rainVolume=math.min(1,(runtime.saveData.audio.rainVolume or .20)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPrevious) then audioPreviousTrack(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPause) then audioTogglePause(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicNext) then audioNextTrack(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicMute) then audioToggleMute(); ui.playSfx("menu")
      else return true end
      writeSave(); return true
  end

  function ui.handleUpgradeMousePressed(x,y)
      if not runtime.trainUpgradeOpen then return false end
      if Util.pointIn(x,y,ui.upgradeClose) then runtime.trainUpgradeOpen=false; return true end
      if ui.weaponRepair and Util.pointIn(x,y,ui.weaponRepair) then repairEquipped(); return true end
      if Util.pointIn(x,y,ui.engineUpgrade) then
          local result=TrainUpgradeBalance.purchaseEngine(runtime.saveData,EngineUpgrades)
          if result.ok then runtime.dialogue={speaker="Train Workshop",text=result.entry.name.." installed! Future journeys use fewer supplies and finish faster.",timer=4}; writeSave() end
          return true
      end
      for i,r in ipairs(ui.trainCars or {}) do if Util.pointIn(x,y,r) then local c=Catalog.trainCarCatalog[i]; local result=TrainUpgradeBalance.purchaseCar(runtime.saveData,c); if result.ok then runtime.trainUpgradeOpen=false; runtime.dialogue={speaker="Train Workshop",text=c.name.." added to your train! "..c.description,timer=3}; writeSave() end; return true end end
      return true
  end

  function ui.handleEditorMousePressed(x,y)
      if not runtime.editMode then return false end
      local item=runtime.editedItem and runtime.saveData.droppedItems[runtime.editedItem]
      if Util.pointIn(x,y,ui.editDone) then runtime.editMode=false; runtime.editedItem=nil; ui.editSliderDrag=nil; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editHue) then ui.editSliderDrag="hue"; runtime.editDragging=false; ui.updateEditColorSlider(x); return true end
      if item and Util.pointIn(x,y,ui.editSaturation) then ui.editSliderDrag="saturation"; runtime.editDragging=false; ui.updateEditColorSlider(x); return true end
      if item and Util.pointIn(x,y,ui.editLeft) then moveEditedItem(-5,0); return true end
      if item and Util.pointIn(x,y,ui.editRight) then moveEditedItem(5,0); return true end
      if item and Util.pointIn(x,y,ui.editUp) then moveEditedItem(0,-5); return true end
      if item and Util.pointIn(x,y,ui.editDown) then moveEditedItem(0,5); return true end
      if item and Util.pointIn(x,y,ui.editSmaller) then item.scale=math.max(0.5,(item.scale or 1)-0.1); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editLarger) then item.scale=math.min(2.5,(item.scale or 1)+0.1); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editRotate) then item.rotation=((item.rotation or 0)+math.pi/4)%(math.pi*2); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editBack) then item.layer=(item.layer or runtime.editedItem)-1; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editForward) then item.layer=(item.layer or runtime.editedItem)+1; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editPickup) then
          if item.permanent then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; runtime.editMode=false; runtime.editedItem=nil
          elseif Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then runtime.dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; runtime.editMode=false; runtime.editedItem=nil
          else local slot=Inventory.firstEmptySlot(runtime.saveData); if slot then runtime.saveData.inventory[slot]=item.name; table.remove(runtime.saveData.droppedItems,runtime.editedItem); runtime.editedItem=nil; writeSave() end end
          return true
      end
      runtime.editedItem=trainItemAt(x,y); runtime.editDragging=runtime.editedItem~=nil; return true
  end

  function ui.handleGameMousePressed(x,y)
      if maintenanceSession.open then
          local result=Maintenance.mousepressed(maintenanceSession,x,y,runtime.saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if ui.handleRadioMousePressed(x,y) then return true end
      if runtime.inventoryOpen then
          if Util.pointIn(x,y,ui.backpack) then runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave() else handleInventoryClick(x,y,ui.offerGift) end
          return true
      end
      if runtime.tradeOpen then ui.handleTradeClick(x,y); return true end
      if runtime.trainUpgradeOpen then ui.handleUpgradeMousePressed(x,y); return true end
      if ui.optionsOpen then ui.handleOptionsMousePressed(x,y); return true end
      if runtime.poseMenu then if Util.pointIn(x,y,ui.options) then runtime.poseMenu=false; ui.optionsOpen=true; ui.playSfx("menu") else ui.handlePoseClick(x,y) end; return true end
      if Util.pointIn(x,y,ui.options) then ui.optionsOpen=true; runtime.poseMenu=false; ui.mobileMenuOpen=false; ui.playSfx("menu"); return true end
      if ui.handlePoseClick(x,y) then return true end
      if runtime.mapOpen then if Util.pointIn(x,y,ui.mapUp) then runtime.mapScroll=math.max(0,runtime.mapScroll-1) elseif Util.pointIn(x,y,ui.mapDown) then runtime.mapScroll=runtime.mapScroll+1 end; return true end
      if runtime.scene=="stop" and ui.stopAttack and Util.pointIn(x,y,ui.stopAttack) then
          ui.mobileMenuOpen=false
          local mx,my=pointerPosition(); mx,my=screenToGame(mx,my)
          if not mx or not my or (math.abs(mx-runtime.player.x)<35 and math.abs(my-runtime.player.y)<35) then mx,my=runtime.player.x+(runtime.player.facing or 1)*100,runtime.player.y end
          attackStopSludge(mx,my); return true
      end
      if runtime.dialogue and runtime.dialogue.choice and runtime.questOffer then
          if Util.pointIn(x,y,ui.questAccept) then acceptQuest(runtime.questOffer.kind)
          elseif Util.pointIn(x,y,ui.questDecline) then runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="I understand. Safe travels.",timer=5}; runtime.questOffer=nil end
          return true
      end
      if Util.pointIn(x,y,ui.editMode) then runtime.editMode=not runtime.editMode; ui.mobileMenuOpen=false; runtime.editedItem=nil; runtime.editDragging=false; ui.editSliderDrag=nil; runtime.inventoryOpen=false; runtime.mapOpen=false; writeSave(); return true end
      if Util.pointIn(x,y,ui.trainUpgrade) then runtime.trainUpgradeOpen=true; ui.mobileMenuOpen=false; runtime.inventoryOpen=false; runtime.mapOpen=false; runtime.editMode=false; runtime.poseMenu=false; ui.optionsOpen=false; return true end
      if Util.pointIn(x,y,ui.maintenance) then
          runtime.inventoryOpen=false; runtime.mapOpen=false; runtime.editMode=false; runtime.poseMenu=false; ui.optionsOpen=false; ui.mobileMenuOpen=false; runtime.dialogue=nil
          endCameraPan()
          Maintenance.open(maintenanceSession,runtime.saveData); ui.playSfx("menu"); return true
      end
      if ui.handleEditorMousePressed(x,y) then return true end
      if Util.pointIn(x,y,ui.backpack) then runtime.inventoryOpen=not runtime.inventoryOpen; ui.mobileMenuOpen=false; if not runtime.inventoryOpen then runtime.chestOpen=false; runtime.activeChest=nil end; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; return true end
      if Util.pointIn(x,y,ui.map) then runtime.mapOpen=not runtime.mapOpen; ui.mobileMenuOpen=false; if runtime.mapOpen then runtime.mapScroll=math.max(0,math.floor((runtime.saveData.location-1)/6)-2) end; runtime.inventoryOpen=false; runtime.draggedSlot=nil; return true end
      if runtime.dialogue then runtime.dialogue=nil; return true end
      if Util.pointIn(x,y,ui.leaveTrain) then ui.mobileMenuOpen=false; attemptLeaveTrain(); return true end
      if Util.pointIn(x,y,ui.travel) and runtime.saveData.location<50 then
          ui.mobileMenuOpen=false
          local status=travelStatus()
          if status.affordable then runtime.travelConfirm=true
          else runtime.dialogue={speaker="Supplies",text="The next leg still needs "..status.shortage..".",timer=3} end
          return true
      end
      if Util.pointIn(x,y,ui.returnDoor) then enterTrain(false); return true end
      if Util.pointIn(x,y,ui.pickup) then pickUpNearby(); return true end
      return false
  end

  local function mousepressed(x,y,button)
      if runtime.state=="intro" then skipIntro(ui.introCinematic); return end
      if runtime.exitPrompt then
          if button==1 then
              x,y=screenToGame(x,y)
              if ui.exitYes and Util.pointIn(x,y,ui.exitYes) then resolveExitPrompt("yes")
              elseif ui.exitNo and Util.pointIn(x,y,ui.exitNo) then resolveExitPrompt("no") end
          end
          return
      end
      if button==3 and runtime.state=="game" and not runtime.travelConfirm and not maintenanceSession.open and not ui.radioOpen and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.poseMenu and not ui.optionsOpen and not runtime.editMode then beginCameraPan(x,y); return end
      x,y=screenToGame(x,y)
      if runtime.state=="game" and runtime.carTransition then return end
      if button==2 and runtime.state=="game" and not maintenanceSession.open and not runtime.editMode and not runtime.mapOpen and not runtime.tradeOpen and not runtime.inventoryOpen and not runtime.dialogue and not runtime.travelConfirm and not runtime.trainUpgradeOpen and not runtime.poseMenu and not ui.optionsOpen and not ui.radioOpen then
          local action,index=interactionMouseAction(ui.interaction,button)
          if action=="openStorage" then runtime.activeChest=runtime.saveData.droppedItems[index]; runtime.activeChest.storage=runtime.activeChest.storage or {}; if runtime.activeChest.mailbox then runtime.activeChest.mailUnread=false; writeSave() end; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false end
          return
      end
      if button==2 and runtime.state=="battle" then ui.handleBattleMousePressed(x,y,true); return end
      if button~=1 then return end
      if runtime.state=="event" then handleEventClick(x,y); return end
      if runtime.state=="ending" then if Util.pointIn(x,y,ui.endingButton) then writeSave(); runtime.state="slots" end; return end
      if runtime.travelConfirm then
          if Util.pointIn(x,y,ui.travelNo) then runtime.travelConfirm=false; return end
          if Util.pointIn(x,y,ui.travelYes) then startTravel() end
          return
      end
      if runtime.state=="slots" then
          for i=1,3 do if Util.pointIn(x,y,ui.slots[i]) then local data=readSave(i); if data then runtime.selectedSlot=i; enterGame(data) end; return elseif Util.pointIn(x,y,ui.slotNew[i]) then runtime.selectedSlot=i; runtime.state="characters"; return elseif Util.pointIn(x,y,ui.slotDelete[i]) then removeSave(i); return end end
      elseif runtime.state=="characters" then
          if Util.pointIn(x,y,ui.characterUp) then runtime.characterScroll=math.max(0,runtime.characterScroll-1); return end
          if Util.pointIn(x,y,ui.characterDown) then runtime.characterScroll=runtime.characterScroll+1; return end
          for i,r in ipairs(ui.characters or {}) do if Util.pointIn(x,y,r) then runtime.saveData=newSave(characters[i]); enterGame(runtime.saveData); writeSave(); return end end
      elseif runtime.state=="battle" then ui.handleBattleMousePressed(x,y,false)
      elseif runtime.state=="game" then
          -- UI and modal layers always get first refusal. Only an unconsumed
          -- click in the stop world is allowed to become a sludge attack.
          if ui.handleGameMousePressed(x,y) then return end
          if runtime.scene=="stop" and attackStopSludge(x,y) then return end
      end
  end

  local function mousemoved(x,y)
      if cameraPanning() then
          moveCameraPan(x,y); return
      end
      x,y=screenToGame(x,y)
      if runtime.state=="game" and maintenanceSession.open then maintenanceSession.mouseX,maintenanceSession.mouseY=x,y; return end
      if runtime.state=="game" and runtime.editMode and ui.editSliderDrag then ui.updateEditColorSlider(x); return end
      if runtime.state=="game" and runtime.editMode and runtime.editDragging and runtime.editedItem then
              placeEditedItem(x,y)
      end
  end

  local function mousereleased(x,y,button)
      if button==3 then endCameraPan(); return end
      x,y=screenToGame(x,y)
      if button==1 and ui.editSliderDrag then ui.updateEditColorSlider(x); ui.editSliderDrag=nil; writeSave(); return end
      if button==1 and runtime.editDragging then runtime.editDragging=false; writeSave() end
      if runtime.state=="game" or (runtime.state=="battle" and runtime.inventoryOpen) then handleInventoryRelease(x,y,button) end
  end

  local function wheelmoved(_,y)
      if runtime.state=="battle" and runtime.battle then
          local mouseX,mouseY=pointerPosition()
          local mx,my=viewportToGame(mouseX,mouseY)
          if mx>=185 and mx<=775 and my>=488 and my<=570 then
              runtime.battle.logScroll=math.max(0,math.min(math.max(0,#(runtime.battle.log or {})-1),(runtime.battle.logScroll or 0)+(y>0 and 1 or -1)))
          elseif mx>=25 and mx<=935 and my>=55 and my<480 then
              runtime.battleZoom=math.max(.75,math.min(1.35,runtime.battleZoom+y*.08))
          end
      elseif runtime.state=="game" and runtime.mapOpen then runtime.mapScroll=math.max(0,runtime.mapScroll-(y>0 and 1 or -1))
      elseif runtime.state=="characters" then runtime.characterScroll=math.max(0,runtime.characterScroll-(y>0 and 1 or -1))
      elseif runtime.state=="game" and not maintenanceSession.open and not runtime.inventoryOpen and not runtime.editMode and not ui.radioOpen then
          zoomCamera(y)
      end
  end

  local function keypressedGlobal(key)
      if ui.mobileMenuOpen and key=="escape" then ui.mobileMenuOpen=false; return true end
      if maintenanceSession.open then
          local result=Maintenance.keypressed(maintenanceSession,key,runtime.saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if runtime.tradeOpen then if key=="escape" or key=="q" then runtime.tradeOpen=false; runtime.tradeNPC=nil; writeSave() end; return end
      if runtime.state=="event" then
          local choice=key=="1" and 1 or (key=="2" and 2 or (key=="3" and 3)); if choice then chooseEvent(choice) end
          return
      end
      if runtime.state=="ending" then if key=="return" or key=="space" then writeSave(); runtime.state="slots" end; return end
      if runtime.state=="characters" and (key=="down" or key=="s" or key=="pagedown") then runtime.characterScroll=runtime.characterScroll+1; return end
      if runtime.state=="characters" and (key=="up" or key=="w" or key=="pageup") then runtime.characterScroll=math.max(0,runtime.characterScroll-1); return end
      if runtime.travelConfirm then if key=="escape" then runtime.travelConfirm=false elseif key=="return" or key=="e" then startTravel() end; return end
      if runtime.state=="battle" then
          if runtime.inventoryOpen then
              if key=="i" or key=="escape" then runtime.inventoryOpen=false; runtime.draggedSlot=nil; runtime.inventoryDragActive=false end
          elseif not runtime.battle.finished and key=="i" and BattleRules.activeUnit(runtime.battle) and BattleRules.activeUnit(runtime.battle).team=="ally" then runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; ui.playSfx("menu")
          elseif runtime.battle.finished and (key=="return" or key=="space" or key=="e") then
              local outcome=runtime.battle.finished; runtime.battle=nil; runtime.state="game"; if outcome=="win" then enterStop() else runtime.scene="train"; writeSave() end
          elseif not runtime.battle.finished and tonumber(key) and runtime.battle.options and runtime.battle.options[tonumber(key)] then battleAttack(runtime.battle.options[tonumber(key)])
          elseif not runtime.battle.finished and key=="h" then battleHeal()
          elseif not runtime.battle.finished and key=="m" and not runtime.battle.moveUsed then runtime.battle.phase="move"; setBattlePrompt("Choose a highlighted terrain piece to move.")
          elseif not runtime.battle.finished and key=="g" then battleGuard()
          elseif not runtime.battle.finished and key=="space" then advanceBattleTurn()
          elseif not runtime.battle.finished and (key=="r" or key=="escape") then runtime.battle=nil; runtime.state="game"; runtime.scene="train"; writeSave() end
          return
      end
      if runtime.state=="game" and runtime.inventoryOpen and key=="e" then runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; if runtime.giftOpen then runtime.giftOpen=false; runtime.giftSlot=nil end; writeSave(); return true end
      if runtime.state=="game" and runtime.dialogue and runtime.dialogue.choice and runtime.questOffer then if key=="y" or key=="return" or key=="e" then acceptQuest(runtime.questOffer.kind) elseif key=="n" or key=="escape" then runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="I understand. Safe travels.",timer=5}; runtime.questOffer=nil end; return end
      if runtime.state=="game" and runtime.carTransition then return true end
      return false
  end

  function ui.routeWorldInteraction(key)
      local action,arg=interactionKeyAction({selected=ui.interaction,dialogue=runtime.dialogue,
          blocked=runtime.state~="game" or maintenanceSession.open or runtime.inventoryOpen or runtime.mapOpen or runtime.editMode or runtime.carTransition,
          isFurniture=function(index) local item=runtime.saveData.droppedItems[index]; return isFurnitureItem(item and item.name) end},key)
      if not action then return false end
      if action=="closeDialogue" then runtime.dialogue=nil
      elseif action=="talkPassenger" then local p=runtime.saveData.passengers[arg]; runtime.dialogue={speaker=Util.titleFromFile(p.npc).." - "..Util.titleFromFile(p.job),text=Catalog.passengerLines[love.math.random(#Catalog.passengerLines)],timer=7}
      elseif action=="car" then beginCarTransition((runtime.saveData.activeCar or 1)+arg)
      elseif action=="talkNPC" then ui.playSfx("talking"); talkToNPC()
      elseif action=="enterHouse" then
          runtime.saveData.lastStopDoor=arg; runtime.saveData.activeHouseDoor=arg; ui.playSfx("doors"); runtime.scene="house"
          local homeLayout=Stops.ensureDoor(runtime.saveData,Catalog,arg); ensureHouseItems(); runtime.player.x,runtime.player.y=InteriorDoors.spawnPoint(homeLayout.interior,scenery.interiorFiles); setupNPC(); writeSave()
      elseif action=="exitHouse" then
          ui.playSfx("doors"); ensureStopLayout(); runtime.scene="stop"; runtime.saveData.activeHouseDoor=nil
          local x,y=Settlements.doorPoint(runtime.saveData.location,runtime.saveData.lastStopDoor); runtime.player.x,runtime.player.y=Settlements.clamp(x,y,runtime.saveData.location); setupNPC(); writeSave()
      elseif action=="returnTrain" then
          enterTrain(true)
      elseif action=="give" then giveWeaponToNearby()
      elseif action=="openStorage" then runtime.activeChest=runtime.saveData.droppedItems[arg]; runtime.activeChest.storage=runtime.activeChest.storage or {}; runtime.activeChest.mailUnread=false; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave()
      elseif action=="holdPickup" then runtime.holdPickupIndex=arg; runtime.holdPickupTime=0
      elseif action=="pickup" then runtime.nearbyItem=arg; pickUpNearby()
      elseif action=="fire" then addCoalToFire() end
      return true
  end

  local function keypressed(key)
      if runtime.state=="intro" then skipIntro(ui.introCinematic); return end
      if runtime.exitPrompt then
          if key=="return" or key=="y" then resolveExitPrompt("yes")
          elseif key=="escape" or key=="n" then resolveExitPrompt("no") end
          return
      end
      if keypressedGlobal(key) then return end
      if key=="escape" then if ui.radioOpen then ui.radioOpen=false; return elseif runtime.state=="game" and (runtime.inventoryOpen or runtime.mapOpen or runtime.dialogue or runtime.editMode or runtime.poseMenu or ui.optionsOpen or runtime.trainUpgradeOpen) then runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.mapOpen=false; runtime.dialogue=nil; runtime.questOffer=nil; runtime.editMode=false; runtime.editedItem=nil; runtime.draggedSlot=nil; runtime.giftOpen=false; runtime.giftSlot=nil; runtime.poseMenu=false; ui.optionsOpen=false; runtime.trainUpgradeOpen=false; writeSave() elseif runtime.state~="slots" then requestExitPrompt("title") else requestExitPrompt("quit") end end
      if key=="i" and runtime.state=="game" and not runtime.editMode then
          if runtime.nearChest or runtime.nearMailbox then runtime.activeChest=runtime.saveData.droppedItems[runtime.nearChest or runtime.nearMailbox]; if runtime.activeChest then runtime.activeChest.storage=runtime.activeChest.storage or {}; runtime.activeChest.mailUnread=false; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; writeSave() end
          else runtime.inventoryOpen=not runtime.inventoryOpen; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil end
      end
      if key=="m" and runtime.state=="game" then runtime.mapOpen=not runtime.mapOpen; if runtime.mapOpen then runtime.mapScroll=math.max(0,math.floor((runtime.saveData.location-1)/6)-2) end; runtime.inventoryOpen=false; runtime.dialogue=nil end
      if runtime.state=="game" and runtime.mapOpen then if key=="down" or key=="s" then runtime.mapScroll=runtime.mapScroll+1 elseif key=="up" or key=="w" then runtime.mapScroll=math.max(0,runtime.mapScroll-1) end; return end
      if runtime.state=="game" and runtime.editMode and runtime.editedItem then
          if key=="left" or key=="a" then moveEditedItem(-5,0) elseif key=="right" or key=="d" then moveEditedItem(5,0) elseif key=="up" or key=="w" then moveEditedItem(0,-5) elseif key=="down" or key=="s" then moveEditedItem(0,5) end
          return
      end
      if key=="p" and runtime.state=="game" and ui.nearRadio and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.editMode then ui.radioOpen=not ui.radioOpen; ui.optionsOpen=false; runtime.poseMenu=false; ui.playSfx("menu"); return end
      if key=="e" and runtime.state=="game" and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.editMode then runtime.actionKind="use"; runtime.actionTimer=.35 end
      if (key=="q" or key=="g" or key=="e") and ui.routeWorldInteraction(key) then return end
  end

  local function keyreleased(key)
      if key=="e" and runtime.holdPickupIndex then
          runtime.holdPickupIndex,runtime.holdPickupTime=nil,0
      end
  end

  return {
    mousepressed=mousepressed,
    mousemoved=mousemoved,
    mousereleased=mousereleased,
    wheelmoved=wheelmoved,
    keypressed=keypressed,
    keyreleased=keyreleased
  }
end

return {new=new}
