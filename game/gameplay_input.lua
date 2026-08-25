local function install(resolve,assign)
  assert(type(resolve)=="function","gameplay input requires a dependency resolver")
  assert(type(assign)=="function","gameplay input requires a dependency writer")
  local env=setmetatable({}, {
    __index=function(_,key)
      local value=resolve(key)
      if value~=nil then return value end
      return _G[key]
    end,
    __newindex=function(_,key,value)
      if not assign(key,value) then error("gameplay input cannot assign "..tostring(key),2) end
    end
  })
  setfenv(install,env)

  function ui.offerGift(slot)
      local name=saveData.inventory[slot]; local accepted=isWeapon(name) or Catalog.itemEffects[name] or Catalog.backpackUpgrades[name] or name=="coal-chunk" or name=="coal-bucket"
      if accepted then
          local passenger; for _,p in ipairs(saveData.passengers or {}) do if p.npc==giftNPC then passenger=p; break end end
          if isWeapon(name) then
              if passenger then passenger.weapon=name
              else local layout=saveData.stopLayouts[tostring(saveData.location)]; if layout then layout.npcWeapon=name end; if npcActor then npcActor.weapon=name end end
          end
          saveData.inventory[slot]=nil; dialogue={speaker="Gift Accepted",text=Util.titleFromFile(giftNPC).." accepted the gift of "..Util.titleFromFile(name)..".",timer=2}
      else dialogue={speaker=Util.titleFromFile(giftNPC),text="I don't need that right now.",timer=2} end
      giftOpen=false; inventoryOpen=false; giftSlot=nil; writeSave()
  end

  function ui.handleInventoryClick(x,y)
      local ctx=ui.inventoryContext(); ctx.offerGift=ui.offerGift
      return Systems.inventory.handleClick(ctx,x,y)
  end

  function ui.handlePoseClick(x,y)
      if Util.pointIn(x,y,ui.pose) then poseMenu=not poseMenu; ui.optionsOpen=false; ui.mobileMenuOpen=false; ui.playSfx("menu"); return true end
      if not poseMenu then return false end
      if Util.pointIn(x,y,ui.poseIdle) then playerPose="idle"
      elseif Util.pointIn(x,y,ui.poseSit) then playerPose="sit"
      elseif Util.pointIn(x,y,ui.poseLay) then playerPose="lay"
      elseif Util.pointIn(x,y,ui.poseAction) then playerPose="idle"; actionKind="use"; actionTimer=.45
      else return true end
      poseMenu=false; return true
  end

  function ui.handleTradeClick(x,y)
      local layout=ensureStopLayout()
      if Util.pointIn(x,y,ui.tradeClose) then tradeOpen=false; tradeNPC=nil; writeSave(); return true end
      for i,r in pairs(ui.tradeBuy or {}) do
          if Util.pointIn(x,y,r) then
              local name=layout.tradeStock and layout.tradeStock[i]; local price=name and Inventory.scrapPrice(name,Catalog) or 999; local slot=Inventory.firstEmptySlot(saveData)
              if slot and saveData.scrap>=price then saveData.scrap=saveData.scrap-price; saveData.inventory[slot]=name; layout.tradeStock[i]=nil; writeSave() end
              return true
          end
      end
      for i,r in pairs(ui.tradeSell or {}) do
          if Util.pointIn(x,y,r) and saveData.inventory[i] then
              local name=saveData.inventory[i]; local price=math.max(1,math.floor(Inventory.scrapPrice(name,Catalog)/2))
              if (layout.tradeBudget or 0)>=price then layout.tradeBudget=layout.tradeBudget-price; saveData.scrap=saveData.scrap+price; saveData.inventory[i]=nil; writeSave() end
              return true
          end
      end
      for i,r in pairs(ui.tradeGive or {}) do
          if Util.pointIn(x,y,r) and isWeapon(saveData.inventory[i]) then layout.npcWeapon=saveData.inventory[i]; if npcActor then npcActor.weapon=layout.npcWeapon end; saveData.inventory[i]=nil; writeSave(); return true end
      end
      return true
  end

  function ui.handleBattleMousePressed(x,y,rightClick)
      local result=Systems.battleUI.handleMouse(ui.battleUIContext(),x,y,rightClick)
      if result=="missing" then screens:transition("game"); state=session.screen
      elseif result=="continue_win" then battle=nil; screens:transition("game"); state=session.screen; enterStop()
      elseif result=="continue_loss" or result=="retreat" then
          battle=nil; screens:transition("game"); state=session.screen; scene=session:setScene("train"); npcActor=nil; writeSave()
      end
  end

  function ui.handleRadioMousePressed(x,y)
      if not ui.radioOpen then return false end
      if Util.pointIn(x,y,ui.radio8bit) then saveData.audio.station="8bit"; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioChill) then local changed=saveData.audio.station~="chill"; saveData.audio.station="chill"; if changed then saveData.audio.rainEnabled=true end; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioVibes) then saveData.audio.station="vibes"; ui.audio:resetMusic(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioRain) then saveData.audio.rainEnabled=not saveData.audio.rainEnabled; ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioClose) then ui.radioOpen=false; ui.playSfx("menu") end
      return true
  end

  function ui.handleOptionsMousePressed(x,y)
      if not ui.optionsOpen then return false end
      if Util.pointIn(x,y,ui.options) then ui.optionsOpen=false; ui.playSfx("menu"); return true end
      if Util.pointIn(x,y,ui.pose) then ui.optionsOpen=false; poseMenu=true; ui.playSfx("menu"); return true end
      if Util.pointIn(x,y,ui.musicDown) then saveData.audio.musicVolume=math.max(0,(saveData.audio.musicVolume or .10)-.05)
      elseif Util.pointIn(x,y,ui.musicUp) then saveData.audio.musicVolume=math.min(1,(saveData.audio.musicVolume or .10)+.05)
      elseif Util.pointIn(x,y,ui.sfxDown) then saveData.audio.sfxVolume=math.max(0,(saveData.audio.sfxVolume or .55)-.05)
      elseif Util.pointIn(x,y,ui.sfxUp) then saveData.audio.sfxVolume=math.min(1,(saveData.audio.sfxVolume or .55)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.rainDown) then saveData.audio.rainVolume=math.max(0,(saveData.audio.rainVolume or .20)-.05)
      elseif Util.pointIn(x,y,ui.rainUp) then saveData.audio.rainVolume=math.min(1,(saveData.audio.rainVolume or .20)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPrevious) then ui.audio:previousTrack(saveData.audio,ui.musicCategory()); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPause) then ui.audio:togglePause(saveData.audio); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicNext) then ui.audio:nextTrack(saveData.audio,ui.musicCategory()); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicMute) then ui.audio:toggleMute(saveData.audio); ui.playSfx("menu")
      else return true end
      writeSave(); return true
  end

  function ui.handleUpgradeMousePressed(x,y)
      if not trainUpgradeOpen then return false end
      if Util.pointIn(x,y,ui.upgradeClose) then trainUpgradeOpen=false; return true end
      if Util.pointIn(x,y,ui.engineUpgrade) then
          local nextEngine=EngineUpgrades.next(saveData.engineLevel)
          if nextEngine and saveData.scrap>=nextEngine.cost then saveData.scrap=saveData.scrap-nextEngine.cost; saveData.engineLevel=saveData.engineLevel+1; dialogue={speaker="Train Workshop",text=nextEngine.name.." installed! Future journeys use fewer supplies and finish faster.",timer=4}; writeSave() end
          return true
      end
      for i,r in ipairs(ui.trainCars or {}) do if Util.pointIn(x,y,r) then local c=Catalog.trainCarCatalog[i]; if not ownsTrainCar(c.id) and saveData.scrap>=c.cost then saveData.scrap=saveData.scrap-c.cost; saveData.trainCars[#saveData.trainCars+1]=c.id; trainUpgradeOpen=false; dialogue={speaker="Train Workshop",text=c.name.." added to your train! "..c.description,timer=3}; writeSave() end; return true end end
      return true
  end

  function ui.handleEditorMousePressed(x,y)
      if not editMode then return false end
      local item=editedItem and saveData.droppedItems[editedItem]
      if Util.pointIn(x,y,ui.editDone) then editMode=false; editedItem=nil; ui.editSliderDrag=nil; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editHue) then ui.editSliderDrag="hue"; editDragging=false; ui.updateEditColorSlider(x); return true end
      if item and Util.pointIn(x,y,ui.editSaturation) then ui.editSliderDrag="saturation"; editDragging=false; ui.updateEditColorSlider(x); return true end
      if item and Util.pointIn(x,y,ui.editLeft) then moveEditedItem(-5,0); return true end
      if item and Util.pointIn(x,y,ui.editRight) then moveEditedItem(5,0); return true end
      if item and Util.pointIn(x,y,ui.editUp) then moveEditedItem(0,-5); return true end
      if item and Util.pointIn(x,y,ui.editDown) then moveEditedItem(0,5); return true end
      if item and Util.pointIn(x,y,ui.editSmaller) then item.scale=math.max(0.5,(item.scale or 1)-0.1); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editLarger) then item.scale=math.min(2.5,(item.scale or 1)+0.1); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editRotate) then item.rotation=((item.rotation or 0)+math.pi/4)%(math.pi*2); writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editBack) then item.layer=(item.layer or editedItem)-1; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editForward) then item.layer=(item.layer or editedItem)+1; writeSave(); return true end
      if item and Util.pointIn(x,y,ui.editPickup) then
          if item.permanent then dialogue={speaker=Util.titleFromFile(item.name),text="This stays aboard the train.",timer=1.4}; editMode=false; editedItem=nil
          elseif Catalog.storageCapacities[item.name] and item.storage and next(item.storage) then dialogue={speaker=Util.titleFromFile(item.name),text="Empty this container before picking it up.",timer=4}; editMode=false; editedItem=nil
          else local slot=Inventory.firstEmptySlot(saveData); if slot then saveData.inventory[slot]=item.name; table.remove(saveData.droppedItems,editedItem); editedItem=nil; writeSave() end end
          return true
      end
      editedItem=Systems.worldRenderer.trainItemAt(x,y); editDragging=editedItem~=nil; return true
  end

  function ui.handleGameMousePressed(x,y)
      if maintenanceSession.open then
          local result=Maintenance.mousepressed(maintenanceSession,x,y,saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if ui.handleRadioMousePressed(x,y) then return true end
      if inventoryOpen then
          if Util.pointIn(x,y,ui.backpack) then inventoryOpen=false; chestOpen=false; activeChest=nil; draggedSlot=nil; inventoryDragActive=false; writeSave() else ui.handleInventoryClick(x,y) end
          return true
      end
      if tradeOpen then ui.handleTradeClick(x,y); return true end
      if trainUpgradeOpen then ui.handleUpgradeMousePressed(x,y); return true end
      if ui.optionsOpen then ui.handleOptionsMousePressed(x,y); return true end
      if poseMenu then if Util.pointIn(x,y,ui.options) then poseMenu=false; ui.optionsOpen=true; ui.playSfx("menu") else ui.handlePoseClick(x,y) end; return true end
      if Util.pointIn(x,y,ui.options) then ui.optionsOpen=true; poseMenu=false; ui.mobileMenuOpen=false; ui.playSfx("menu"); return true end
      if ui.handlePoseClick(x,y) then return true end
      if mapOpen then if Util.pointIn(x,y,ui.mapUp) then mapScroll=math.max(0,mapScroll-1) elseif Util.pointIn(x,y,ui.mapDown) then mapScroll=mapScroll+1 end; return true end
      if scene=="stop" and ui.stopAttack and Util.pointIn(x,y,ui.stopAttack) then
          ui.mobileMenuOpen=false
          local mx,my=pointerPosition(); mx,my=screenToGame(mx,my)
          if not mx or not my or (math.abs(mx-player.x)<35 and math.abs(my-player.y)<35) then mx,my=player.x+(player.facing or 1)*100,player.y end
          attackStopSludge(mx,my); return true
      end
      if dialogue and dialogue.choice and questOffer then
          if Util.pointIn(x,y,ui.questAccept) then acceptQuest(questOffer.kind)
          elseif Util.pointIn(x,y,ui.questDecline) then dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="I understand. Safe travels.",timer=5}; questOffer=nil end
          return true
      end
      if Util.pointIn(x,y,ui.editMode) then editMode=not editMode; ui.mobileMenuOpen=false; editedItem=nil; editDragging=false; ui.editSliderDrag=nil; inventoryOpen=false; mapOpen=false; writeSave(); return true end
      if Util.pointIn(x,y,ui.trainUpgrade) then trainUpgradeOpen=true; ui.mobileMenuOpen=false; inventoryOpen=false; mapOpen=false; editMode=false; poseMenu=false; ui.optionsOpen=false; return true end
      if Util.pointIn(x,y,ui.maintenance) then
          inventoryOpen=false; mapOpen=false; editMode=false; poseMenu=false; ui.optionsOpen=false; ui.mobileMenuOpen=false; dialogue=nil
          Camera:endPan()
          Maintenance.open(maintenanceSession,saveData); ui.playSfx("menu"); return true
      end
      if ui.handleEditorMousePressed(x,y) then return true end
      if Util.pointIn(x,y,ui.backpack) then inventoryOpen=not inventoryOpen; ui.mobileMenuOpen=false; if not inventoryOpen then chestOpen=false; activeChest=nil end; draggedSlot=nil; inventoryDragActive=false; return true end
      if Util.pointIn(x,y,ui.map) then mapOpen=not mapOpen; ui.mobileMenuOpen=false; if mapOpen then mapScroll=math.max(0,math.floor((saveData.location-1)/6)-2) end; inventoryOpen=false; draggedSlot=nil; return true end
      if dialogue then dialogue=nil; return true end
      if Util.pointIn(x,y,ui.leaveTrain) then ui.mobileMenuOpen=false; attemptLeaveTrain(); return true end
      if Util.pointIn(x,y,ui.travel) and saveData.location<50 and saveData.resources.food>0 and saveData.resources.water>0 and saveData.resources.coal>0 then ui.mobileMenuOpen=false; travelConfirm=true; return true end
      if Util.pointIn(x,y,ui.returnDoor) then local left,right,top,bottom=trainFloorBounds(); scene=session:setScene("train"); npcActor=nil; player.x,player.y=right,(top+bottom)/2; writeSave(); return true end
      if Util.pointIn(x,y,ui.pickup) then pickUpNearby(); return true end
      return false
  end

  local function mousepressed(x,y,button)
      if state=="intro" then Systems.intro.skip(ui.introCinematic); return end
      if exitPrompt then
          if button==1 then
              x,y=screenToGame(x,y)
              if ui.exitYes and Util.pointIn(x,y,ui.exitYes) then resolveExitPrompt("yes")
              elseif ui.exitNo and Util.pointIn(x,y,ui.exitNo) then resolveExitPrompt("no") end
          end
          return
      end
      if button==3 and state=="game" and not travelConfirm and not maintenanceSession.open and not ui.radioOpen and not inventoryOpen and not mapOpen and not dialogue and not tradeOpen and not trainUpgradeOpen and not poseMenu and not ui.optionsOpen and not editMode then Camera:beginPan(x,y); return end
      x,y=screenToGame(x,y)
      if state=="game" and carTransition then return end
      if button==2 and state=="game" and not maintenanceSession.open and not editMode and not mapOpen and not tradeOpen and not inventoryOpen and not dialogue and not travelConfirm and not trainUpgradeOpen and not poseMenu and not ui.optionsOpen and not ui.radioOpen then
          local action,index=Systems.interactions.mouseAction(ui.interaction,button)
          if action=="openStorage" then activeChest=saveData.droppedItems[index]; activeChest.storage=activeChest.storage or {}; if activeChest.mailbox then activeChest.mailUnread=false; writeSave() end; chestOpen=true; inventoryOpen=true; draggedSlot=nil; inventoryDragActive=false end
          return
      end
      if button==2 and state=="battle" then ui.handleBattleMousePressed(x,y,true); return end
      if button~=1 then return end
      if state=="event" then local choice=EventUI.hit(x,y,ui.eventChoices,Util.pointIn); if choice then resolveEventChoice(choice) end; return end
      if state=="ending" then if Util.pointIn(x,y,ui.endingButton) then writeSave(); screens:transition("slots"); state=session.screen end; return end
      if travelConfirm then
          if Util.pointIn(x,y,ui.travelNo) then travelConfirm=false; return end
          if Util.pointIn(x,y,ui.travelYes) then local cost=travelCost(); if saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal then saveData.resources.food=saveData.resources.food-cost.food; saveData.resources.water=saveData.resources.water-cost.water; saveData.resources.coal=saveData.resources.coal-cost.coal; travelConfirm=false; travelTransition={t=0,changed=false,departSoundPlayed=true}; playTrainDepart(); writeSave() end end
          return
      end
      if state=="slots" then
          for i=1,3 do if Util.pointIn(x,y,ui.slots[i]) then local data=Save.read(i); if data then selectedSlot=session:selectSlot(i); enterGame(data) end; return elseif Util.pointIn(x,y,ui.slotNew[i]) then selectedSlot=session:selectSlot(i); screens:transition("characters"); state=session.screen; return elseif Util.pointIn(x,y,ui.slotDelete[i]) then Save.remove(i); return end end
      elseif state=="characters" then
          if Util.pointIn(x,y,ui.characterUp) then characterScroll=math.max(0,characterScroll-1); return end
          if Util.pointIn(x,y,ui.characterDown) then characterScroll=characterScroll+1; return end
          for i,r in ipairs(ui.characters or {}) do if Util.pointIn(x,y,r) then saveData=session:setSaveData(newSave(characters[i])); enterGame(saveData); writeSave(); return end end
      elseif state=="battle" then ui.handleBattleMousePressed(x,y,false)
      elseif state=="game" then
          -- UI and modal layers always get first refusal. Only an unconsumed
          -- click in the stop world is allowed to become a sludge attack.
          if ui.handleGameMousePressed(x,y) then return end
          if scene=="stop" and attackStopSludge(x,y) then return end
      end
  end

  local function mousemoved(x,y)
      if Camera.panning then
          local _,_,scaleX=Viewport.transform(W,H)
          Camera:movePan(x,y,scaleX); return
      end
      x,y=screenToGame(x,y)
      if state=="game" and maintenanceSession.open then maintenanceSession.mouseX,maintenanceSession.mouseY=x,y; return end
      if state=="game" and editMode and ui.editSliderDrag then ui.updateEditColorSlider(x); return end
      if state=="game" and editMode and editDragging and editedItem then
              local item=saveData.droppedItems[editedItem]; if item then local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,x)); item.y=math.max(top,math.min(bottom,y)) end
      end
  end

  local function mousereleased(x,y,button)
      if button==3 then Camera:endPan(); return end
      x,y=screenToGame(x,y)
      if button==1 and ui.editSliderDrag then ui.updateEditColorSlider(x); ui.editSliderDrag=nil; writeSave(); return end
      if button==1 and editDragging then editDragging=false; writeSave() end
      if state=="game" or (state=="battle" and inventoryOpen) then Systems.inventory.handleRelease(ui.inventoryContext(),x,y,button) end
  end

  local function wheelmoved(_,y)
      if state=="battle" and battle then
          local mouseX,mouseY=pointerPosition()
          local mx,my=Viewport.toGame(mouseX,mouseY,W,H)
          if mx>=185 and mx<=775 and my>=488 and my<=570 then
              battle.logScroll=math.max(0,math.min(math.max(0,#(battle.log or {})-1),(battle.logScroll or 0)+(y>0 and 1 or -1)))
          elseif mx>=25 and mx<=935 and my>=55 and my<480 then
              battleZoom=math.max(.75,math.min(1.35,battleZoom+y*.08))
          end
      elseif state=="game" and mapOpen then mapScroll=math.max(0,mapScroll-(y>0 and 1 or -1))
      elseif state=="characters" then characterScroll=math.max(0,characterScroll-(y>0 and 1 or -1))
      elseif state=="game" and not maintenanceSession.open and not inventoryOpen and not editMode and not ui.radioOpen then
          Camera:wheel(y)
      end
  end

  local function keypressedGlobal(key)
      if ui.mobileMenuOpen and key=="escape" then ui.mobileMenuOpen=false; return true end
      if maintenanceSession.open then
          local result=Maintenance.keypressed(maintenanceSession,key,saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if tradeOpen then if key=="escape" or key=="q" then tradeOpen=false; tradeNPC=nil; writeSave() end; return end
      if state=="event" then
          local choice=key=="1" and 1 or (key=="2" and 2 or (key=="3" and 3)); if choice then resolveEventChoice(choice) end
          return
      end
      if state=="ending" then if key=="return" or key=="space" then writeSave(); screens:transition("slots"); state=session.screen end; return end
      if state=="characters" and (key=="down" or key=="s" or key=="pagedown") then characterScroll=characterScroll+1; return end
      if state=="characters" and (key=="up" or key=="w" or key=="pageup") then characterScroll=math.max(0,characterScroll-1); return end
      if travelConfirm then if key=="escape" then travelConfirm=false elseif key=="return" or key=="e" then local cost=travelCost(); if saveData.resources.food>=cost.food and saveData.resources.water>=cost.water and saveData.resources.coal>=cost.coal then saveData.resources.food=saveData.resources.food-cost.food; saveData.resources.water=saveData.resources.water-cost.water; saveData.resources.coal=saveData.resources.coal-cost.coal; travelConfirm=false; travelTransition={t=0,changed=false,departSoundPlayed=true}; playTrainDepart(); writeSave() end end; return end
      if state=="battle" then
          if inventoryOpen then
              if key=="i" or key=="escape" then inventoryOpen=false; draggedSlot=nil; inventoryDragActive=false end
          elseif not battle.finished and key=="i" and BattleRules.activeUnit(battle) and BattleRules.activeUnit(battle).team=="ally" then inventoryOpen=true; draggedSlot=nil; inventoryDragActive=false; ui.playSfx("menu")
          elseif battle.finished and (key=="return" or key=="space" or key=="e") then
              local outcome=battle.finished; battle=nil; screens:transition("game"); state=session.screen; if outcome=="win" then enterStop() else scene=session:setScene("train"); writeSave() end
          elseif not battle.finished and tonumber(key) and battle.options and battle.options[tonumber(key)] then battleAttack(battle.options[tonumber(key)])
          elseif not battle.finished and key=="h" then battleHeal()
          elseif not battle.finished and key=="m" and not battle.moveUsed then battle.phase="move"; setBattlePrompt("Choose a highlighted terrain piece to move.")
          elseif not battle.finished and key=="g" then battleGuard()
          elseif not battle.finished and key=="space" then advanceBattleTurn()
          elseif not battle.finished and (key=="r" or key=="escape") then battle=nil; screens:transition("game"); state=session.screen; scene=session:setScene("train"); writeSave() end
          return
      end
      if state=="game" and inventoryOpen and key=="e" then inventoryOpen=false; chestOpen=false; activeChest=nil; draggedSlot=nil; inventoryDragActive=false; if giftOpen then giftOpen=false; giftSlot=nil end; writeSave(); return true end
      if state=="game" and dialogue and dialogue.choice and questOffer then if key=="y" or key=="return" or key=="e" then acceptQuest(questOffer.kind) elseif key=="n" or key=="escape" then dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="I understand. Safe travels.",timer=5}; questOffer=nil end; return end
      if state=="game" and carTransition then return true end
      return false
  end

  function ui.routeWorldInteraction(key)
      local action,arg=Systems.interactions.keyAction({selected=ui.interaction,dialogue=dialogue,
          blocked=state~="game" or maintenanceSession.open or inventoryOpen or mapOpen or editMode or carTransition,
          isFurniture=function(index) local item=saveData.droppedItems[index]; return isFurnitureItem(item and item.name) end},key)
      if not action then return false end
      if action=="closeDialogue" then dialogue=nil
      elseif action=="talkPassenger" then local p=saveData.passengers[arg]; dialogue={speaker=Util.titleFromFile(p.npc).." - "..Util.titleFromFile(p.job),text=Catalog.passengerLines[love.math.random(#Catalog.passengerLines)],timer=7}
      elseif action=="car" then beginCarTransition((saveData.activeCar or 1)+arg)
      elseif action=="talkNPC" then ui.playSfx("talking"); talkToNPC()
      elseif action=="enterHouse" then
          saveData.lastStopDoor=arg; saveData.activeHouseDoor=arg; ui.playSfx("doors"); scene=session:setScene("house")
          local homeLayout=Stops.ensureDoor(saveData,Catalog,arg); ensureHouseItems(); player.x,player.y=InteriorDoors.spawnPoint(homeLayout.interior,scenery.interiorFiles); setupNPC(); writeSave()
      elseif action=="exitHouse" then
          ui.playSfx("doors"); ensureStopLayout(); scene=session:setScene("stop"); saveData.activeHouseDoor=nil
          local x,y=Settlements.doorPoint(saveData.location,saveData.lastStopDoor); player.x,player.y=Settlements.clamp(x,y,saveData.location); setupNPC(); writeSave()
      elseif action=="returnTrain" then
          ui.playSfx("trainDoor"); local left,right,top,bottom=trainFloorBounds(); scene=session:setScene("train"); npcActor=nil; player.x,player.y=right,(top+bottom)/2; writeSave()
      elseif action=="give" then giveWeaponToNearby()
      elseif action=="holdPickup" then holdPickupIndex=arg; holdPickupTime=0
      elseif action=="pickup" then nearbyItem=arg; pickUpNearby()
      elseif action=="fire" then addCoalToFire() end
      return true
  end

  local function keypressed(key)
      if state=="intro" then Systems.intro.skip(ui.introCinematic); return end
      if exitPrompt then
          if key=="return" or key=="y" then resolveExitPrompt("yes")
          elseif key=="escape" or key=="n" then resolveExitPrompt("no") end
          return
      end
      if keypressedGlobal(key) then return end
      if key=="escape" then if ui.radioOpen then ui.radioOpen=false; return elseif state=="game" and (inventoryOpen or mapOpen or dialogue or editMode or poseMenu or ui.optionsOpen or trainUpgradeOpen) then inventoryOpen=false; chestOpen=false; activeChest=nil; mapOpen=false; dialogue=nil; questOffer=nil; editMode=false; editedItem=nil; draggedSlot=nil; giftOpen=false; giftSlot=nil; poseMenu=false; ui.optionsOpen=false; trainUpgradeOpen=false; writeSave() elseif state~="slots" then requestExitPrompt("title") else requestExitPrompt("quit") end end
      if key=="i" and state=="game" and not editMode then
          if nearChest then activeChest=saveData.droppedItems[nearChest]; if activeChest then activeChest.storage=activeChest.storage or {}; chestOpen=true; inventoryOpen=true; draggedSlot=nil end
          else inventoryOpen=not inventoryOpen; chestOpen=false; activeChest=nil; draggedSlot=nil end
      end
      if key=="m" and state=="game" then mapOpen=not mapOpen; if mapOpen then mapScroll=math.max(0,math.floor((saveData.location-1)/6)-2) end; inventoryOpen=false; dialogue=nil end
      if state=="game" and mapOpen then if key=="down" or key=="s" then mapScroll=mapScroll+1 elseif key=="up" or key=="w" then mapScroll=math.max(0,mapScroll-1) end; return end
      if state=="game" and editMode and editedItem then
          if key=="left" or key=="a" then moveEditedItem(-5,0) elseif key=="right" or key=="d" then moveEditedItem(5,0) elseif key=="up" or key=="w" then moveEditedItem(0,-5) elseif key=="down" or key=="s" then moveEditedItem(0,5) end
          return
      end
      if key=="p" and state=="game" and ui.nearRadio and not inventoryOpen and not mapOpen and not editMode then ui.radioOpen=not ui.radioOpen; ui.optionsOpen=false; poseMenu=false; ui.playSfx("menu"); return end
      if key=="e" and state=="game" and not inventoryOpen and not mapOpen and not editMode then actionKind="use"; actionTimer=.35 end
      if (key=="q" or key=="g" or key=="e") and ui.routeWorldInteraction(key) then return end
  end

  local function keyreleased(key)
      if key=="e" and holdPickupIndex then
          holdPickupIndex,holdPickupTime=nil,0
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

return {install=install}
