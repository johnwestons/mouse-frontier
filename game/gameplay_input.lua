local Accessibility=require("game.accessibility")
local WorldPause=require("game.world_pause")
local UIStyle=require("game.ui_layout")
local UIFocus=require("game.ui_focus")
local LootProgression=require("game.loot_progression")
local RepairLayout=require("game.repair_workbench_layout")

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
  local controlBindings=required(context,"controlBindings","table")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local characters=required(context,"characters","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local scenery=required(context,"scenery","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local NpcRelationships=required(context,"npcRelationships","table")
  local MerchantTrade=required(context,"merchantTrade","table")
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
  local worldCoordinates=required(context,"worldCoordinates","function")
  local cameraPanning=required(context,"cameraPanning","function")
  local beginCameraPan=required(context,"beginCameraPan","function")
  local moveCameraPan=required(context,"moveCameraPan","function")
  local endCameraPan=required(context,"endCameraPan","function")
  local zoomCamera=required(context,"zoomCamera","function")
  local resetCamera=required(context,"resetCamera","function")
  local panCamera=required(context,"panCamera","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local isWeapon=required(context,"isWeapon","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local currentTradeSource=required(context,"currentTradeSource","function")
  local moveEditedItem=required(context,"moveEditedItem","function")
  local attackStopSludge=required(context,"attackStopSludge","function")
  local attackExpeditionMob=required(context,"attackExpeditionMob","function")
  local activateExpeditionInteraction=required(context,"activateExpeditionInteraction","function")
  local activateCaravanInteraction=required(context,"activateCaravanInteraction","function")
  local returnFromCaravan=required(context,"returnFromCaravan","function")
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
  local finishBattle=required(context,"finishBattle","function")
  local beginCarTransition=required(context,"beginCarTransition","function")
  local talkToNPC=required(context,"talkToNPC","function")
  local ensureHouseItems=required(context,"ensureHouseItems","function")
  local setupNPC=required(context,"setupNPC","function")
  local giveWeaponToNearby=required(context,"giveWeaponToNearby","function")
  local pickUpNearby=required(context,"pickUpNearby","function")
  local itemIsHere=required(context,"itemIsHere","function")
  local addCoalToFire=required(context,"addCoalToFire","function")
  local handleInventoryClick=required(context,"handleInventoryClick","function")
  local handleInventoryRelease=required(context,"handleInventoryRelease","function")
  local requestExitPrompt=required(context,"requestExitPrompt","function")
  local resolveExitPrompt=required(context,"resolveExitPrompt","function")
  local trainItemAt=required(context,"trainItemAt","function")
  local skipIntro=required(context,"skipIntro","function")
  local interactionMouseAction=required(context,"interactionMouseAction","function")
  local interactionKeyAction=required(context,"interactionKeyAction","function")
  local repairWeapon=required(context,"repairWeapon","function")
  local FirstAid=required(context,"firstAid","table")
  local ShootingRange=required(context,"shootingRange","table")
  local resolveFirstAid=required(context,"resolveFirstAid","function")
  local chooseHelpDialogue=required(context,"chooseHelpDialogue","function")
  local chooseFinale=required(context,"chooseFinale","function")
  local beginShootingRange=required(context,"beginShootingRange","function")
  local handleShootingRange=required(context,"handleShootingRange","function")

  local function processRangeOutcome(outcome)
      if outcome=="shot" then
          local profile=ShootingRange.soundProfile(runtime.shootingRange,Catalog)
          if profile and ui.playSfxPath then ui.playSfxPath(profile.path,profile) else ui.playSfx(ShootingRange.sound(runtime.shootingRange,Catalog)) end
      end
      if outcome=="shot" or outcome=="complete" or outcome=="close" then handleShootingRange(outcome) end
      if outcome=="start" or outcome=="reload" or outcome=="select" or outcome=="monocular" then ui.playSfx("menu") end
      return outcome
  end

  ui.menuSettings=ui.menuSettings or {}
  ui.menuSettings.audio=ui.menuSettings.audio or {
      station="chill",musicVolume=.10,sfxVolume=.55,rainVolume=.20,
      rainEnabled=true,musicPaused=false,musicMuted=false,
  }
  local function optionsData()
      local data=runtime.saveData or ui.menuSettings
      data.audio=data.audio or {
          station="chill",musicVolume=.10,sfxVolume=.55,rainVolume=.20,
          rainEnabled=true,musicPaused=false,musicMuted=false,
      }
      Accessibility.ensure(data)
      return data
  end

  local function persistOptions()
      if runtime.saveData then writeSave() end
  end

  local function activateEscapeChoice(index)
      if index==1 then
          ui.escMenuOpen=false
          ui.playSfx("menu")
      elseif index==2 then
          ui.escMenuOpen=false
          ui.optionsOpen=true
          runtime.optionsPage=runtime.optionsPage or "audio"
          ui.playSfx("menu")
      elseif index==3 or index==4 then
          ui.escMenuOpen=false
          runtime.returnEscAfterExitPrompt=true
          requestExitPrompt(index==3 and "title" or "quit")
      end
  end

  local function handleEscapeMenuKey(key)
      local selection=math.max(1,math.min(4,tonumber(ui.escMenuSelection) or 1))
      if key=="up" or key=="w" then
          ui.escMenuSelection=(selection-2)%4+1
          ui.playSfx("menu")
      elseif key=="down" or key=="s" then
          ui.escMenuSelection=selection%4+1
          ui.playSfx("menu")
      elseif key=="return" or key=="kpenter" or key=="space" then
          activateEscapeChoice(selection)
      end
      return true
  end

  local function handleOptionsKey(key)
      if key=="tab" then
          runtime.optionsPage=runtime.optionsPage=="audio" and "accessibility"
              or (runtime.optionsPage=="accessibility" and "controls" or "audio")
          ui.playSfx("menu")
      elseif runtime.optionsPage=="controls" and (key=="pageup" or key=="pagedown") then
          local device=runtime.optionsControlDevice or "keyboard"
          local list=device=="keyboard" and controlBindings:keyActions()
              or (runtime.optionsControllerSection=="axes" and controlBindings:axisActions() or controlBindings:buttonActions())
          local visible=ui.controlBindingVisibleRows or 14
          local pageSize=math.max(1,visible-1)
          runtime.optionsControlScroll=math.max(0,math.min(math.max(0,#list-visible),
              (runtime.optionsControlScroll or 0)+(key=="pageup" and -pageSize or pageSize)))
          return true
      elseif runtime.optionsPage=="accessibility" then
          local data=optionsData()
          local changed=true
          if key=="1" then Accessibility.cycleTextSize(data)
          elseif key=="2" then Accessibility.toggle(data,"highContrast")
          elseif key=="3" then Accessibility.toggle(data,"reducedMotion")
          elseif key=="4" then Accessibility.toggle(data,"controlHints")
          elseif key=="5" then Accessibility.toggle(data,"touchFeedback")
          elseif key=="6" then Accessibility.toggle(data,"largeTouchTargets")
          else changed=false end
          if changed then ui.playSfx("menu"); persistOptions() end
      end
      return true
  end

  local function handleEscapeMenuClick(x,y)
      if not ui.escMenuOpen then return false end
      if Util.pointIn(x,y,ui.escChoiceContinue) then activateEscapeChoice(1)
      elseif Util.pointIn(x,y,ui.escChoiceOptions) then activateEscapeChoice(2)
      elseif Util.pointIn(x,y,ui.escChoiceTitle) then activateEscapeChoice(3)
      elseif Util.pointIn(x,y,ui.escChoiceQuit) then activateEscapeChoice(4) end
      return true
  end

  local function quickAttackPoint()
      local player=runtime.player
      local dx,dy=player.intentX or player.facing or 1,player.intentY or 0
      local length=math.sqrt(dx*dx+dy*dy)
      if length<.01 then dx,dy,length=player.facing or 1,0,1 end
      return player.x+dx/length*100,player.y+dy/length*100
  end

  local function declineQuestOffer()
      if not runtime.questOffer then return false end
      runtime.saveData.questAsked=runtime.saveData.questAsked or {}
      runtime.saveData.questAsked[tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.currentNPC)]=true
      runtime.dialogue={speaker="TASK",text="Task declined.",timer=5}
      runtime.questOffer=nil
      writeSave()
      return true
  end

  local function chooseCharacter(file)
      if not file then return false end
      runtime.characterPreviewFile=nil
      runtime.saveData=newSave(file); enterGame(runtime.saveData); writeSave(); return true
  end

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
      runtime.travelTransition={t=0,changed=false,departSoundPlayed=true,maintenanceCondition=Maintenance.condition(runtime.saveData)}
      playTrainDepart(); writeSave(); return true
  end

  local function exitHouse()
      if runtime.scene~="house" then return false end
      ui.playSfx("doors"); ensureStopLayout(); runtime.scene="stop"; runtime.saveData.activeHouseDoor=nil
      local x,y=Settlements.doorPoint(runtime.saveData.location,runtime.saveData.lastStopDoor)
      runtime.player.x,runtime.player.y=Settlements.clamp(x,y,runtime.saveData.location)
      setupNPC(); writeSave(); return true
  end

  function ui.offerGift(slot)
      local name=runtime.saveData.inventory[slot]; local accepted=isWeapon(name) or Catalog.itemEffects[name] or Catalog.wearableItems[name] or name=="coal-chunk" or name=="coal-bucket"
      if accepted then
          local passenger; for _,p in ipairs(runtime.saveData.passengers or {}) do if p.npc==runtime.giftNPC then passenger=p; break end end
          if isWeapon(name) then
              if passenger then passenger.weapon=name
              else local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]; if layout then layout.npcWeapon=name end; if runtime.npcActor then runtime.npcActor.weapon=name end end
          end
          local effect=Catalog.itemEffects[name]
          local category=isWeapon(name) and "weapon" or (Catalog.wearableItems[name] and "gear"
              or ((name=="coal-chunk" or name=="coal-bucket") and "fuel"
              or (effect and effect.health and "medical" or (effect and effect.food and "food" or (effect and effect.water and "water" or "useful")))))
          local result=NpcRelationships.recordGift(runtime.saveData,runtime.giftNPC,name,category)
          runtime.saveData.inventory[slot]=nil; runtime.dialogue={speaker="GIFT • "..result.status.name,text=result.line,timer=5}
      else
          local result=NpcRelationships.rejection(runtime.saveData,runtime.giftNPC)
          runtime.dialogue={speaker="GIFT • "..result.status.name,text=result.line,timer=4}
      end
      runtime.giftOpen=false; runtime.inventoryOpen=false; runtime.giftSlot=nil; writeSave()
  end

  function ui.handlePoseClick(x,y)
      if Util.pointIn(x,y,ui.pose) then runtime.poseMenu=not runtime.poseMenu; ui.optionsOpen=false; ui.mobileMenuOpen=false; ui.playSfx("menu"); return true end
      if not runtime.poseMenu then return false end
      if Util.pointIn(x,y,ui.poseClose) then runtime.poseMenu=false; ui.playSfx("menu"); return true
      elseif Util.pointIn(x,y,ui.poseIdle) then runtime.playerPose="idle"
      elseif Util.pointIn(x,y,ui.poseSit) then runtime.playerPose="sit"
      elseif Util.pointIn(x,y,ui.poseLay) then runtime.playerPose="lay"
      elseif Util.pointIn(x,y,ui.poseAction) then runtime.playerPose="idle"; runtime.actionKind="use"; runtime.actionTimer=.45
      else return true end
      runtime.poseMenu=false; return true
  end

  local function requestConfirmation(kind,details)
      details=details or {}
      details.kind=kind
      runtime.pendingConfirmation=details
      ui.playSfx("menu")
      return true
  end

  local function commitConfirmation(confirmed)
      local request=runtime.pendingConfirmation
      runtime.pendingConfirmation=nil
      ui.confirmYes=nil; ui.confirmNo=nil
      ui.keyboardFocusVisible=false
      if not request or not confirmed then return true end
      if request.kind=="deleteSave" then
          removeSave(request.slot)
      elseif request.kind=="overwriteSave" then
          runtime.selectedSlot=request.slot
          runtime.characterPreviewFile=nil
          runtime.characterScroll=0
          runtime.state="characters"
      elseif request.kind=="eventChoice" then
          chooseEvent(request.choiceIndex)
      elseif request.kind=="buyItem" then
          local source=currentTradeSource()
          if source then
              local result=MerchantTrade.buy(runtime.saveData,Catalog,source,request.stockIndex)
              if result.ok then
                  runtime.tradeMessage=result.delivery=="train" and (Util.titleFromFile(result.name).." sent to the train mailbox.")
                      or (result.delivery=="ammo" and (Util.titleFromFile(result.name).." added to ammunition reserves.")
                      or ("Purchased "..Util.titleFromFile(result.name).."."))
                  writeSave()
              else
                  runtime.tradeMessage=result.reason=="scrap" and "Not enough scrap."
                      or (result.reason=="space" and (source.mailboxOverflow and "Your backpack and train mailbox are full." or "Your backpack is full.")
                      or "That item is no longer available.")
              end
          end
      elseif request.kind=="trainEngine" then
          local result=TrainUpgradeBalance.purchaseEngine(runtime.saveData,EngineUpgrades)
          if result.ok then
              runtime.dialogue={speaker="Train Workshop",text=result.entry.name.." installed! Future journeys use fewer supplies and finish faster.",timer=4}
              writeSave()
          end
      elseif request.kind=="trainCar" then
          local entry=Catalog.trainCarCatalog[request.index]
          local result=entry and TrainUpgradeBalance.purchaseCar(runtime.saveData,entry)
          if result and result.ok then
              runtime.trainUpgradeOpen=false
              runtime.dialogue={speaker="Train Workshop",text=entry.name.." added to your train! "..entry.description,timer=3}
              writeSave()
          end
      elseif request.kind=="rangeAmmo" then
          local purchased=ShootingRange.buyAmmo(runtime.shootingRange,runtime.saveData,Catalog)
          if purchased then writeSave(); ui.playSfx("menu") end
      end
      return true
  end

  local function requestEventChoice(index)
      local event=runtime.randomEvent
      local choice=event and event.choices and event.choices[index]
      local rect=ui.eventChoices and ui.eventChoices[index]
      if not choice or (rect and rect.enabled==false) then return false end
      return requestConfirmation("eventChoice",{choiceIndex=index,label=choice.label,
          message="Choose this response?\n"..tostring(choice.label or "")})
  end

  local function requestNewJourney(slot)
      if readSave(slot) then
          return requestConfirmation("overwriteSave",{slot=slot,confirmLabel="START NEW",
              message="Start a new journey in Save Slot "..slot.."? The current save will be replaced after you choose a traveler."})
      end
      runtime.selectedSlot=slot
      runtime.characterPreviewFile=nil
      runtime.characterScroll=0
      runtime.state="characters"
      return true
  end

  function ui.handleTradeClick(x,y)
      local source=currentTradeSource()
      if Util.pointIn(x,y,ui.tradeClose) then runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; writeSave(); return true end
      if not source then runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; return true end
      if Util.pointIn(x,y,ui.tradeBuyPrev) then runtime.tradeBuyPage=math.max(0,(runtime.tradeBuyPage or 0)-1); return true end
      if Util.pointIn(x,y,ui.tradeBuyNext) then runtime.tradeBuyPage=(runtime.tradeBuyPage or 0)+1; return true end
      if Util.pointIn(x,y,ui.tradePrev) then runtime.tradeSellPage=math.max(0,(runtime.tradeSellPage or 0)-1); return true end
      if Util.pointIn(x,y,ui.tradeNext) then runtime.tradeSellPage=(runtime.tradeSellPage or 0)+1; return true end
      for i,r in pairs(ui.tradeBuy or {}) do
          if Util.pointIn(x,y,r) then
              if r.enabled==false then
                  local result=MerchantTrade.buy(runtime.saveData,Catalog,source,i)
                  runtime.tradeMessage=result.reason=="scrap" and "Not enough scrap."
                      or (result.reason=="space" and (source.mailboxOverflow and "Your backpack and train mailbox are full." or "Your backpack is full.")
                      or "That item is no longer available.")
                  return true
              end
              local name=MerchantTrade.stockItem(source,i)
              local price=MerchantTrade.buyPrice(runtime.saveData,Catalog,source,i)
              requestConfirmation("buyItem",{stockIndex=i,itemName=name,price=price,
                  message="Buy "..Util.titleFromFile(name or "item").." for "..tostring(price).." scrap?"})
              return true
          end
      end
      for i,r in pairs(ui.tradeSell or {}) do
          if Util.pointIn(x,y,r) and runtime.saveData.inventory[i] then
              local result=MerchantTrade.sell(runtime.saveData,Catalog,source,i)
              if result.ok then runtime.tradeMessage="Sold "..Util.titleFromFile(result.name).." for "..result.price.." scrap."; writeSave()
              else runtime.tradeMessage=source.kind=="caravan" and "The caravan cannot afford that item." or "This merchant cannot afford that item." end
              return true
          end
      end
      for i,r in pairs(ui.tradeGive or {}) do
          if source.allowGifts and Util.pointIn(x,y,r) and isWeapon(runtime.saveData.inventory[i]) then
              local layout=ensureStopLayout(); local merchant=source.merchant or runtime.tradeNPC or runtime.saveData.currentNPC; local weapon=runtime.saveData.inventory[i]
              layout.npcWeapon=weapon; if runtime.npcActor then runtime.npcActor.weapon=layout.npcWeapon end
              NpcRelationships.recordGift(runtime.saveData,merchant,weapon,"weapon"); runtime.saveData.inventory[i]=nil; writeSave(); return true
          end
      end
      return true
  end

  function ui.handleBattleMousePressed(x,y,rightClick)
      return handleBattleMouse(x,y,rightClick)
  end

  function ui.handleRadioMousePressed(x,y)
      if not ui.radioOpen then return false end
      local iconX,iconY=x,y
      if not mobileEnabled() then iconX,iconY=UIStyle.inversePoint(x,y,"radio",{x=90,y=62,w=780,h=610}) end
      if Util.pointIn(iconX,iconY,ui.radio8bit) then if runtime.saveData.audio.station~="8bit" then runtime.saveData.audio.station="8bit"; audioResetMusic(); writeSave() end; ui.playSfx("menu")
      elseif Util.pointIn(iconX,iconY,ui.radioChill) then if runtime.saveData.audio.station~="chill" then runtime.saveData.audio.station="chill"; audioResetMusic(); writeSave() end; ui.playSfx("menu")
      elseif Util.pointIn(iconX,iconY,ui.radioVibes) then if runtime.saveData.audio.station~="vibes" then runtime.saveData.audio.station="vibes"; audioResetMusic(); writeSave() end; ui.playSfx("menu")
      elseif Util.pointIn(iconX,iconY,ui.radioRain) then runtime.saveData.audio.rainEnabled=not runtime.saveData.audio.rainEnabled; ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(iconX,iconY,ui.radioClose) then ui.radioOpen=false; ui.playSfx("menu") end
      if Util.pointIn(x,y,ui.radioPrevious) then audioPreviousTrack(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioPause) then audioTogglePause(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioNext) then audioNextTrack(); ui.playSfx("menu"); writeSave()
      elseif Util.pointIn(x,y,ui.radioMute) then audioToggleMute(); ui.playSfx("menu"); writeSave() end
      return true
  end

  function ui.handleOptionsMousePressed(x,y)
      if not ui.optionsOpen then return false end
      if controlBindings:isCapturing() then controlBindings:cancelCapture() end
      if Util.pointIn(x,y,ui.optionsBack) then ui.optionsOpen=false; ui.escMenuOpen=true; ui.playSfx("menu"); return true end
      if Util.pointIn(x,y,ui.optionsAudioTab) then runtime.optionsPage="audio"; ui.playSfx("menu"); return true
      elseif Util.pointIn(x,y,ui.optionsAccessTab) then runtime.optionsPage="accessibility"; ui.playSfx("menu"); return true
      elseif Util.pointIn(x,y,ui.optionsControlsTab) then runtime.optionsPage="controls"; runtime.optionsControlDevice=runtime.optionsControlDevice or "keyboard"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
      elseif runtime.optionsPage=="controls" then
          if Util.pointIn(x,y,ui.controlsKeyboardTab) then runtime.optionsControlDevice="keyboard"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
          elseif Util.pointIn(x,y,ui.controlsControllerTab) then runtime.optionsControlDevice="controller"; runtime.optionsControllerSection=runtime.optionsControllerSection or "buttons"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
          elseif Util.pointIn(x,y,ui.controlsTouchTab) then runtime.optionsControlDevice="touch"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
          elseif Util.pointIn(x,y,ui.controlsButtonsTab) then runtime.optionsControllerSection="buttons"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
          elseif Util.pointIn(x,y,ui.controlsAxesTab) then runtime.optionsControllerSection="axes"; runtime.optionsControlScroll=0; ui.playSfx("menu"); return true
          elseif Util.pointIn(x,y,ui.controlsEditorButton) then
              if ui.openTouchControls then ui.openTouchControls() end
              return true
          elseif Util.pointIn(x,y,ui.controlsReset) then
              local device=runtime.optionsControlDevice or "keyboard"
              local resetDevice=device=="keyboard" and "key"
                  or (device=="controller" and (runtime.optionsControllerSection=="axes" and "axis" or "button") or nil)
              if resetDevice then controlBindings:reset(resetDevice) end
              runtime.optionsControlScroll=0; return true
          elseif Util.pointIn(x,y,ui.controlsScrollUp) then runtime.optionsControlScroll=math.max(0,(runtime.optionsControlScroll or 0)-1); return true
          elseif Util.pointIn(x,y,ui.controlsScrollDown) then runtime.optionsControlScroll=(runtime.optionsControlScroll or 0)+1; return true end
          for _,row in ipairs(ui.controlBindingRows or {}) do
              if Util.pointIn(x,y,row.clear) then controlBindings:clear(row.device,row.entryId); return true end
              if Util.pointIn(x,y,row.rect) then controlBindings:beginCapture(row.device,row.entryId); return true end
          end
          return true
      elseif Util.pointIn(x,y,ui.controlsEditorButton) then
          if ui.openTouchControls then ui.openTouchControls() end
          return true
      elseif Util.pointIn(x,y,ui.optionsStation8bit) then
          local audio=optionsData().audio
          if audio.station~="8bit" then audio.station="8bit"; audioResetMusic() end
          ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.optionsStationChill) then
          local audio=optionsData().audio
          if audio.station~="chill" then audio.station="chill"; audioResetMusic() end
          ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.optionsStationVibes) then
          local audio=optionsData().audio
          if audio.station~="vibes" then audio.station="vibes"; audioResetMusic() end
          ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.optionsStationRain) then
          local audio=optionsData().audio
          audio.rainEnabled=not audio.rainEnabled
          audioResetMusic()
          ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessTextSize) then Accessibility.cycleTextSize(optionsData()); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessHighContrast) then Accessibility.toggle(optionsData(),"highContrast"); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessReducedMotion) then Accessibility.toggle(optionsData(),"reducedMotion"); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessControlHints) then Accessibility.toggle(optionsData(),"controlHints"); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessTouchFeedback) then Accessibility.toggle(optionsData(),"touchFeedback"); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.accessLargeTouchTargets) then Accessibility.toggle(optionsData(),"largeTouchTargets"); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicDown) then local audio=optionsData().audio; audio.musicVolume=math.max(0,(audio.musicVolume or .10)-.05)
      elseif Util.pointIn(x,y,ui.musicUp) then local audio=optionsData().audio; audio.musicVolume=math.min(1,(audio.musicVolume or .10)+.05)
      elseif Util.pointIn(x,y,ui.sfxDown) then local audio=optionsData().audio; audio.sfxVolume=math.max(0,(audio.sfxVolume or .55)-.05)
      elseif Util.pointIn(x,y,ui.sfxUp) then local audio=optionsData().audio; audio.sfxVolume=math.min(1,(audio.sfxVolume or .55)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.rainDown) then local audio=optionsData().audio; audio.rainVolume=math.max(0,(audio.rainVolume or .20)-.05)
      elseif Util.pointIn(x,y,ui.rainUp) then local audio=optionsData().audio; audio.rainVolume=math.min(1,(audio.rainVolume or .20)+.05); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPrevious) then audioPreviousTrack(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicPause) then audioTogglePause(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicNext) then audioNextTrack(); ui.playSfx("menu")
      elseif Util.pointIn(x,y,ui.musicMute) then audioToggleMute(); ui.playSfx("menu")
      else return true end
      persistOptions(); return true
  end

  local function cancelWeaponRepair()
      runtime.weaponRepairStartedAt=nil
      runtime.weaponRepairActiveWeapon=nil
      runtime.weaponRepairDrag=nil
      runtime.weaponRepairMessage=nil
  end

  local function selectRepairWeapon(name)
      cancelWeaponRepair()
      runtime.weaponRepairSelected=name
  end

  local function scrollRepairWeapons(value)
      local count=#LootProgression.ownedWeapons(runtime.saveData,Catalog)
      runtime.weaponRepairScroll=math.max(1,math.min(math.max(1,count-RepairLayout.visibleRows+1),math.floor(value+.5)))
  end

  local function activateWeaponRepair()
      local name=runtime.weaponRepairSelected
      local status=name and LootProgression.repairStatus(runtime.saveData,Catalog,name)
      if not status or not status.name then
          cancelWeaponRepair(); runtime.weaponRepairMessage="Select a weapon you own."
      elseif not status.needed then
          cancelWeaponRepair(); runtime.weaponRepairMessage="This weapon does not need repair."
      elseif not status.hasPart then
          cancelWeaponRepair(); runtime.weaponRepairMessage="Find this part in chests; carry it in your backpack."
      elseif (runtime.saveData.scrap or 0)<status.cost then
          cancelWeaponRepair(); runtime.weaponRepairMessage="Not enough scrap for this repair."
      elseif not runtime.weaponRepairStartedAt or runtime.weaponRepairActiveWeapon~=name then
          runtime.weaponRepairStartedAt=runtime.animationClock
          runtime.weaponRepairActiveWeapon=name
          runtime.weaponRepairMessage="Tap or press confirm on the brass mark."
          ui.keyboardFocusScreen="weapon-repair"; ui.keyboardFocusId="weapon-repair.start"
      else
          local phase=((runtime.animationClock-runtime.weaponRepairStartedAt)*.86)%1
          local quality=phase>=.62 and phase<=.69 and "perfect" or (phase>=.53 and phase<=.78 and "good" or "miss")
          local result=repairWeapon(name,quality)
          runtime.weaponRepairStartedAt=nil; runtime.weaponRepairActiveWeapon=nil
          if result.ok then
              runtime.weaponRepairMessage="Repair complete: "..tostring(result.restored).."% condition."
              ui.playSfx("trainArrive")
          else ui.playSfx("menu") end
      end
  end

  local function returnFromWeaponRepair()
      local fromInventory=runtime.weaponRepairOrigin=="inventory"
      runtime.weaponRepairOpen=false
      if fromInventory then
          runtime.trainUpgradeOpen=false
          runtime.inventoryOpen=true
          runtime.inventoryMode="wearables"
      end
      runtime.weaponRepairOrigin=nil
      cancelWeaponRepair()
  end

  ui.canOpenWeaponRepairWorkbench=function()
      if not ui.canOpenOutfitWorkbench then return false,"Return to the stopped train." end
      return ui.canOpenOutfitWorkbench()
  end
  ui.openWeaponRepairWorkbench=function()
      local allowed=ui.canOpenWeaponRepairWorkbench()
      if not allowed then return false end
      local owned=LootProgression.ownedWeapons(runtime.saveData,Catalog)
      cancelWeaponRepair()
      runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
      runtime.mapOpen=false; runtime.journeyLogOpen=false; runtime.draggedSlot=nil; runtime.inventoryDragActive=false
      runtime.weaponRepairOpen=true; runtime.weaponRepairOrigin="inventory"
      runtime.weaponRepairScroll=1; runtime.weaponRepairSelected=owned[1]
      runtime.trainUpgradeOpen=true
      ui.keyboardFocusVisible=false; ui.keyboardFocusScreen="weapon-repair"; ui.keyboardFocusId="weapon-repair.select."..tostring(owned[1] or "")
      ui.playSfx("menu")
      return true
  end

  function ui.handleUpgradeMousePressed(x,y)
      if not runtime.trainUpgradeOpen then return false end
      if runtime.weaponRepairOpen then
          local listX,listY=UIStyle.inversePoint(x,y,"trainUpgrades",RepairLayout.bounds)
          if Util.pointIn(listX,listY,RepairLayout.listBounds) then
              local name
              for _,entry in ipairs(ui.repairRows or {}) do
                  if Util.pointIn(listX,listY,entry.rect) then name=entry.name; break end
              end
              runtime.weaponRepairDrag={startX=listX,startY=listY,startScroll=runtime.weaponRepairScroll or 1,name=name,moved=false}
              return true
          end
          if ui.repairListUp and Util.pointIn(x,y,ui.repairListUp) then
              scrollRepairWeapons((runtime.weaponRepairScroll or 1)-1); return true
          end
          if ui.repairListDown and Util.pointIn(x,y,ui.repairListDown) then
              scrollRepairWeapons((runtime.weaponRepairScroll or 1)+1); return true
          end
          if ui.repairBack and Util.pointIn(x,y,ui.repairBack) then
              returnFromWeaponRepair(); ui.playSfx("menu"); return true
          end
          if ui.repairClose and Util.pointIn(x,y,ui.repairClose) then
              returnFromWeaponRepair(); runtime.trainUpgradeOpen=false; ui.playSfx("menu"); return true
          end
          if ui.repairStart and Util.pointIn(x,y,ui.repairStart) then
              activateWeaponRepair()
              return true
          end
          return true
      end
      if ui.sewingBench and ui.sewingBench.enabled and Util.pointIn(x,y,ui.sewingBench) then
          if ui.openOutfitWorkbench then ui.openOutfitWorkbench() end
          return true
      end
      if Util.pointIn(x,y,ui.upgradeClose) then runtime.trainUpgradeOpen=false; runtime.weaponRepairOpen=false; cancelWeaponRepair(); return true end
      if ui.weaponRepair and Util.pointIn(x,y,ui.weaponRepair) then
          runtime.weaponRepairOpen=true
          runtime.weaponRepairOrigin=nil
          cancelWeaponRepair(); runtime.weaponRepairScroll=1
          local owned=LootProgression.ownedWeapons(runtime.saveData,Catalog)
          runtime.weaponRepairSelected=runtime.weaponRepairSelected or owned[1]
          return true
      end
      if Util.pointIn(x,y,ui.engineUpgrade) then
          local status=TrainUpgradeBalance.engineStatus(runtime.saveData,EngineUpgrades)
          if status.entry and status.affordable then
              requestConfirmation("trainEngine",{message="Install "..status.entry.name.." for "..status.entry.cost.." scrap?"})
          end
          return true
      end
      for i,r in ipairs(ui.trainCars or {}) do if Util.pointIn(x,y,r) then
          local c=Catalog.trainCarCatalog[i]
          local status=c and TrainUpgradeBalance.carStatus(runtime.saveData,c)
          if c and status and status.affordable then
              requestConfirmation("trainCar",{index=i,message="Add "..c.name.." to your train for "..c.cost.." scrap?"})
          end
          return true
      end end
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

  local function clearCaravanExitOverlays()
      Maintenance.close(maintenanceSession)
      runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
      runtime.draggedSlot=nil; runtime.inventoryDragActive=false; runtime.giftOpen=false; runtime.giftSlot=nil
      runtime.mapOpen=false; runtime.dialogue=nil; runtime.helpDialogue=nil; runtime.questOffer=nil
      runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0
      runtime.editMode=false; runtime.editedItem=nil; runtime.editDragging=false; ui.editSliderDrag=nil
      runtime.trainUpgradeOpen=false; runtime.poseMenu=false; runtime.firstAid=nil; runtime.shootingRange=nil
      runtime.weaponRepairOpen=false; runtime.weaponRepairOrigin=nil; cancelWeaponRepair()
      runtime.travelConfirm=false; runtime.exitPrompt=nil
      ui.optionsOpen=false; ui.radioOpen=false; ui.mobileMenuOpen=false
  end

  local function activateCaravanReturnControl()
      if runtime.state~="game" or runtime.scene~="caravan" then return false end
      clearCaravanExitOverlays()
      returnFromCaravan()
      return true
  end

  local function inventoryMenuContainsPoint(x,y)
      x,y=UIStyle.inversePoint(x,y,"inventory",{x=25,y=35,w=910,h=660})
      if Util.pointIn(x,y,{x=545,y=35,w=390,h=660}) then return true end
      if ui.outfitWorkbenchPanel and Util.pointIn(x,y,ui.outfitWorkbenchPanel) then return true end
      if runtime.chestOpen and Util.pointIn(x,y,{x=25,y=145,w=505,h=490}) then return true end
      if runtime.giftOpen and Util.pointIn(x,y,{x=220,y=170,w=520,h=180}) then return true end
      return false
  end

  local function closeInventoryMenu()
      runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
      runtime.draggedSlot=nil; runtime.inventoryDragActive=false
      runtime.giftOpen=false; runtime.giftSlot=nil
      writeSave()
  end

  local function setJourneyLogOpen(open,keyboard)
      if open then
          if runtime.state~="game" or runtime.lastStand or runtime.firstAid or runtime.shootingRange then return false end
          runtime.journeyLogOpen=true
          runtime.journeyLogScroll=0
          runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
          runtime.draggedSlot=nil; runtime.inventoryDragActive=false
          runtime.mapOpen=false; runtime.poseMenu=false
          ui.mobileMenuOpen=false; ui.radioOpen=false
          ui.keyboardFocusVisible=keyboard==true
      else
          runtime.journeyLogOpen=false
      end
      ui.playSfx("menu")
      return true
  end

  function ui.handleGameMousePressed(x,y)
      if runtime.journeyLogOpen then
          if ui.journeyLogClose and Util.pointIn(x,y,ui.journeyLogClose) then setJourneyLogOpen(false)
          elseif ui.journeyLogUp and Util.pointIn(x,y,ui.journeyLogUp) then
              runtime.journeyLogScroll=math.max(0,(runtime.journeyLogScroll or 0)-math.max(1,ui.journeyLogPageSize or 1))
          elseif ui.journeyLogDown and Util.pointIn(x,y,ui.journeyLogDown) then
              runtime.journeyLogScroll=math.min(ui.journeyLogMaxScroll or 0,(runtime.journeyLogScroll or 0)+math.max(1,ui.journeyLogPageSize or 1))
          end
          return true
      end
      if runtime.inventoryOpen and runtime.dialogue and runtime.dialogue.inventoryResult then
          runtime.dialogue=nil
          if not Util.pointIn(x,y,ui.backpack) and not inventoryMenuContainsPoint(x,y) then closeInventoryMenu() end
          return true
      end
      if runtime.scene=="caravan" and ui.returnStop and Util.pointIn(x,y,ui.returnStop) then
          return activateCaravanReturnControl()
      end
      if maintenanceSession.open then
          x,y=UIStyle.inversePoint(x,y,"maintenance",{x=0,y=0,w=960,h=720})
          local result=Maintenance.mousepressed(maintenanceSession,x,y,runtime.saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if ui.handleRadioMousePressed(x,y) then return true end
      if runtime.helpDialogue then
          for index,choice in ipairs(ui.helpDialogueChoices or {}) do
              if Util.pointIn(x,y,choice) then chooseHelpDialogue(index); return true end
          end
          if ui.helpDialoguePause and Util.pointIn(x,y,ui.helpDialoguePause) then chooseHelpDialogue(nil); return true end
          return true
      end
      if runtime.inventoryOpen then
          if Util.pointIn(x,y,ui.backpack) or not inventoryMenuContainsPoint(x,y) then closeInventoryMenu()
          else handleInventoryClick(x,y,ui.offerGift) end
          return true
      end
      if runtime.tradeOpen then ui.handleTradeClick(x,y); return true end
      if runtime.trainUpgradeOpen then ui.handleUpgradeMousePressed(x,y); return true end
      if ui.optionsOpen then ui.handleOptionsMousePressed(x,y); return true end
      if runtime.poseMenu then ui.handlePoseClick(x,y); return true end
      if ui.handlePoseClick(x,y) then return true end
      if ui.journeyLog and Util.pointIn(x,y,ui.journeyLog) then setJourneyLogOpen(true,false); return true end
      if runtime.mapOpen then
          if Util.pointIn(x,y,ui.map) or Util.pointIn(x,y,ui.expeditionMapClose) then runtime.mapOpen=false
          elseif runtime.scene~="expedition" and Util.pointIn(x,y,ui.mapUp) then runtime.mapScroll=math.max(0,runtime.mapScroll-1)
          elseif runtime.scene~="expedition" and Util.pointIn(x,y,ui.mapDown) then runtime.mapScroll=runtime.mapScroll+1 end
          return true
      end
      if runtime.scene=="house" and ui.exitHome and Util.pointIn(x,y,ui.exitHome) then exitHouse(); return true end
      if runtime.scene=="stop" and ui.returnTrain and Util.pointIn(x,y,ui.returnTrain) then
          ui.mobileMenuOpen=false; enterTrain(true); return true
      end
      if (runtime.scene=="stop" or runtime.scene=="expedition") and ui.stopAttack and Util.pointIn(x,y,ui.stopAttack) then
          ui.mobileMenuOpen=false
          local mx,my=quickAttackPoint()
          if runtime.scene=="expedition" then attackExpeditionMob(mx,my) else attackStopSludge(mx,my) end
          return true
      end
      if runtime.dialogue and runtime.dialogue.choice and runtime.questOffer then
          if Util.pointIn(x,y,ui.questAccept) then acceptQuest(runtime.questOffer.kind)
          elseif Util.pointIn(x,y,ui.questDecline) then declineQuestOffer() end
          return true
      end
      for index,tab in ipairs(ui.trainCarTabs or {}) do
          if Util.pointIn(x,y,tab) then beginCarTransition(index); return true end
      end
      if Util.pointIn(x,y,ui.editMode) then runtime.editMode=not runtime.editMode; ui.mobileMenuOpen=false; runtime.editedItem=nil; runtime.editDragging=false; ui.editSliderDrag=nil; runtime.inventoryOpen=false; runtime.mapOpen=false; writeSave(); return true end
      if Util.pointIn(x,y,ui.trainUpgrade) then runtime.trainUpgradeOpen=true; runtime.weaponRepairOpen=false; cancelWeaponRepair(); ui.mobileMenuOpen=false; runtime.inventoryOpen=false; runtime.mapOpen=false; runtime.editMode=false; runtime.poseMenu=false; ui.optionsOpen=false; return true end
      if Util.pointIn(x,y,ui.pauseMenu) then
          ui.mobileMenuOpen=false
          ui.escMenuOpen=true
          ui.escMenuSelection=1
          ui.playSfx("menu")
          return true
      end
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

  local function openCharacterPreview(file)
      runtime.characterPreviewFile=file
      runtime.characterPreviewAction="walk"
      runtime.characterPreviewDirection="SE"
  end

  local function closeCharacterPreview()
      runtime.characterPreviewFile=nil
      runtime.characterPreviewAction="walk"
      runtime.characterPreviewDirection="SE"
  end

  local function mousepressed(x,y,button)
      if button==1 then ui.keyboardFocusVisible=false end
      if runtime.pendingConfirmation then
          if button==1 then
              x,y=screenToGame(x,y)
              if ui.confirmYes and Util.pointIn(x,y,ui.confirmYes) then commitConfirmation(true)
              elseif ui.confirmNo and Util.pointIn(x,y,ui.confirmNo) then commitConfirmation(false) end
          end
          return true
      end
      if runtime.exitPrompt then
          if button==1 then
              x,y=screenToGame(x,y)
              if ui.exitYes and Util.pointIn(x,y,ui.exitYes) then resolveExitPrompt("yes")
              elseif ui.exitNo and Util.pointIn(x,y,ui.exitNo) then resolveExitPrompt("no") end
          end
          return true
      end
      if ui.escMenuOpen then
          if button==1 then x,y=screenToGame(x,y); handleEscapeMenuClick(x,y) end
          return true
      end
      if ui.optionsOpen then
          if button==1 then x,y=screenToGame(x,y); ui.handleOptionsMousePressed(x,y) end
          return true
      end
      if runtime.state=="intro" then skipIntro(ui.introCinematic); return end
      if runtime.inventoryOpen and runtime.dialogue and runtime.dialogue.inventoryResult then
          runtime.dialogue=nil
          return
      end
      if button==3 then if not runtime.trainUpgradeOpen then beginCameraPan(x,y) end; return end
      -- Check the persistent campsite exit before any modal input capture. This
      -- lets it dismiss inventory, trade, settings, dialogue, and even stale
      -- overlay state in one tap/click.
      if button==1 and runtime.state=="game" and runtime.scene=="caravan" and ui.returnStop then
          local returnX,returnY=screenToGame(x,y)
          if Util.pointIn(returnX,returnY,ui.returnStop) then activateCaravanReturnControl(); return end
      end
      if runtime.shootingRange then
          if button==1 or button==2 or button==4 or button==5 then
              local rangeX,rangeY=screenToGame(x,y)
              rangeX,rangeY=UIStyle.inversePoint(rangeX,rangeY,"shootingRange",{x=0,y=0,w=960,h=720})
              if button==1 and runtime.shootingRange.phase=="lobby" and Util.pointIn(rangeX,rangeY,{x=185,y=542,w=290,h=54}) then
                  local offer=ShootingRange.ammoOffer(runtime.shootingRange,Catalog)
                  if offer and (tonumber(runtime.saveData.scrap) or 0)>=offer.cost then
                      requestConfirmation("rangeAmmo",{message="Buy "..offer.amount.." "..string.upper(offer.ammo).." ammo for "..offer.cost.." scrap?"})
                      return true
                  end
              end
              return processRangeOutcome(ShootingRange.mousepressed(runtime.shootingRange,rangeX,rangeY,runtime.saveData,Catalog,button))
          end
          return
      end
      if runtime.firstAid then
          if button==1 then
              local aidX,aidY=screenToGame(x,y)
              aidX,aidY=UIStyle.inversePoint(aidX,aidY,"firstAid",{x=105,y=40,w=750,h=635})
              local outcome=FirstAid.mousepressed(runtime.firstAid,aidX,aidY)
              if outcome=="complete" or outcome=="failed" or outcome=="cancelled" then resolveFirstAid(outcome) end
          end
          return
      end
      x,y=screenToGame(x,y)
      if runtime.state=="game" and runtime.carTransition then return end
      if button==2 and runtime.state=="game" and runtime.inventoryOpen then
          if not Util.pointIn(x,y,ui.backpack) and not inventoryMenuContainsPoint(x,y) then closeInventoryMenu() end
          return
      end
      if button==2 and not WorldPause.isPaused(runtime,ui,maintenanceSession) then
          local action,index=interactionMouseAction(ui.interaction,button)
          if action=="openStorage" then runtime.activeChest=runtime.saveData.droppedItems[index]; runtime.activeChest.storage=runtime.activeChest.storage or {}; if runtime.activeChest.mailbox then runtime.activeChest.mailUnread=false; writeSave() end; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false end
          return
      end
      if button==2 and runtime.state=="battle" then ui.handleBattleMousePressed(x,y,true); return end
      if button~=1 then return end
      if runtime.state=="event" then
          x,y=UIStyle.inversePoint(x,y,"event",{x=60,y=42,w=840,h=640})
          for index,control in ipairs(ui.eventChoices or {}) do
              if Util.pointIn(x,y,control) then requestEventChoice(index); return end
          end
          return
      end
      if runtime.state=="ending" then
          if not (runtime.saveData.finale and runtime.saveData.finale.choice) then
              for _,control in ipairs(ui.endingChoices or {}) do if Util.pointIn(x,y,control) then chooseFinale(control.id); writeSave(); return end end
          elseif Util.pointIn(x,y,ui.endingButton) then writeSave(); runtime.state="slots" end
          return
      end
      if runtime.travelConfirm then
          if Util.pointIn(x,y,ui.travelNo) then runtime.travelConfirm=false; return end
          if Util.pointIn(x,y,ui.travelYes) then startTravel() end
          return
      end
      if runtime.state=="slots" then
          for i=1,3 do if Util.pointIn(x,y,ui.slots[i]) then local data=readSave(i); if data then runtime.selectedSlot=i; enterGame(data) end; return elseif Util.pointIn(x,y,ui.slotNew[i]) then requestNewJourney(i); return elseif Util.pointIn(x,y,ui.slotDelete[i]) then
              requestConfirmation("deleteSave",{slot=i,message="Delete Save Slot "..i.."? This cannot be undone."})
              return
          end end
      elseif runtime.state=="characters" then
          if runtime.characterPreviewFile then
              if Util.pointIn(x,y,ui.characterConfirm) then chooseCharacter(runtime.characterPreviewFile)
              elseif Util.pointIn(x,y,ui.characterCancel) then closeCharacterPreview()
              else
                  for _,option in ipairs(ui.characterMovementActions or {}) do
                      if Util.pointIn(x,y,option.control) then runtime.characterPreviewAction=option.id; return end
                  end
                  for _,option in ipairs(ui.characterPoseActions or {}) do
                      if Util.pointIn(x,y,option.control) then
                          runtime.characterPreviewAction=option.id
                          if runtime.characterPreviewDirection~="W" and runtime.characterPreviewDirection~="E" then runtime.characterPreviewDirection="E" end
                          return
                      end
                  end
                  for direction,control in pairs(ui.characterDirections or {}) do
                      if control.active and Util.pointIn(x,y,control) then runtime.characterPreviewDirection=direction; return end
                  end
              end
              return
          end
          local maxScroll=ui.characterMaxScroll or 0
          if Util.pointIn(x,y,ui.characterUp) then runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll-1)); return end
          if Util.pointIn(x,y,ui.characterDown) then runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll+1)); return end
          local gridX,gridY=UIStyle.inversePoint(x,y,"characters",{x=0,y=0,w=960,h=720})
          if gridX>=20 and gridX<=940 and gridY>=94 and gridY<=708 then
              runtime.characterGridDrag={startX=x,startY=y,startScroll=runtime.characterScroll,moved=false}
              return
          end
      elseif runtime.state=="battle" then ui.handleBattleMousePressed(x,y,false)
      elseif runtime.state=="game" then
          -- UI and modal layers always get first refusal. Only an unconsumed
          -- click in the stop world is allowed to become a sludge attack.
          if ui.handleGameMousePressed(x,y) then return end
          if WorldPause.isPaused(runtime,ui,maintenanceSession) then return end
          if ui.refreshWorldInteraction then ui.refreshWorldInteraction(pointerPosition()) end
          local action,key=interactionMouseAction(ui.interaction,button)
          if action=="openStorage" then
              local chest=runtime.saveData.droppedItems[key]
              if chest then
                  runtime.activeChest=chest; runtime.activeChest.storage=runtime.activeChest.storage or {}
                  runtime.activeChest.mailUnread=false; runtime.chestOpen=true; runtime.inventoryOpen=true
                  runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave()
              end
              return
          elseif action=="routeKey" and ui.routeWorldInteraction(key) then
              require("game.interaction_beacon").notifyActivated(ui.interaction)
              return
          end
          local worldX,worldY=worldCoordinates(x,y)
          if runtime.scene=="stop" and attackStopSludge(worldX,worldY) then return end
          if runtime.scene=="expedition" and attackExpeditionMob(worldX,worldY) then return end
      end
  end

  local function mousemoved(x,y,dx,dy,touchAim)
      if runtime.weaponRepairDrag then
          if not runtime.trainUpgradeOpen or not runtime.weaponRepairOpen then runtime.weaponRepairDrag=nil; return end
          x,y=screenToGame(x,y)
          x,y=UIStyle.inversePoint(x,y,"trainUpgrades",RepairLayout.bounds)
          local drag=runtime.weaponRepairDrag
          local distance=drag.startY-y
          if math.abs(distance)>12 or drag.moved then
              drag.moved=true
              scrollRepairWeapons(drag.startScroll+distance/RepairLayout.rowStep)
          end
          return
      end
      if runtime.state=="characters" and runtime.characterGridDrag then
          x,y=screenToGame(x,y)
          local drag=runtime.characterGridDrag
          local distance=drag.startY-y
          if math.abs(distance)>12 then
              drag.moved=true
              local maximum=ui.characterMaxScroll or 0
              runtime.characterScroll=math.max(0,math.min(maximum,drag.startScroll+distance/198))
          end
          return
      end
      if cameraPanning() then moveCameraPan(x,y); return end
      if runtime.shootingRange then
          x,y=screenToGame(x,y); x,y=UIStyle.inversePoint(x,y,"shootingRange",{x=0,y=0,w=960,h=720})
          ShootingRange.mousemoved(runtime.shootingRange,x,y,touchAim); return
      end
      if runtime.firstAid then
          x,y=screenToGame(x,y)
          x,y=UIStyle.inversePoint(x,y,"firstAid",{x=105,y=40,w=750,h=635})
          local outcome=FirstAid.mousemoved(runtime.firstAid,x,y)
          if outcome=="complete" then resolveFirstAid(outcome) end
          return
      end
      x,y=screenToGame(x,y)
      if runtime.state=="game" and maintenanceSession.open then
          maintenanceSession.mouseX,maintenanceSession.mouseY=UIStyle.inversePoint(x,y,"maintenance",{x=0,y=0,w=960,h=720})
          return
      end
      if runtime.state=="game" and runtime.editMode and ui.editSliderDrag then ui.updateEditColorSlider(x); return end
      if runtime.state=="game" and runtime.editMode and runtime.editDragging and runtime.editedItem then
              placeEditedItem(x,y)
      end
  end

  local function mousereleased(x,y,button)
      if button==3 then endCameraPan(); return end
      if button==1 and runtime.weaponRepairDrag then
          local drag=runtime.weaponRepairDrag
          runtime.weaponRepairDrag=nil
          if runtime.trainUpgradeOpen and runtime.weaponRepairOpen and not drag.moved and drag.name then
              x,y=screenToGame(x,y)
              x,y=UIStyle.inversePoint(x,y,"trainUpgrades",RepairLayout.bounds)
              if math.abs(x-drag.startX)<=12 and math.abs(y-drag.startY)<=12 then selectRepairWeapon(drag.name) end
          end
          return
      end
      if button==1 and runtime.state=="characters" and runtime.characterGridDrag then
          local drag=runtime.characterGridDrag
          runtime.characterGridDrag=false
          if not drag.moved then
              for index,card in ipairs(ui.characters or {}) do
                  if card.visible and Util.pointIn(drag.startX,drag.startY,card) then openCharacterPreview(characters[index]); break end
              end
          end
          return
      end
      x,y=screenToGame(x,y)
      if runtime.shootingRange then
          ShootingRange.mousereleased(runtime.shootingRange,button)
          if button==2 then ShootingRange.setAim(runtime.shootingRange,false) end
          return
      end
      if runtime.firstAid then
          if button==1 then
              x,y=UIStyle.inversePoint(x,y,"firstAid",{x=105,y=40,w=750,h=635})
              FirstAid.mousereleased(runtime.firstAid,x,y)
          end
          return
      end
      if button==1 and ui.editSliderDrag then ui.updateEditColorSlider(x); ui.editSliderDrag=nil; writeSave(); return end
      if button==1 and runtime.editDragging then runtime.editDragging=false; writeSave() end
      if runtime.state=="game" or (runtime.state=="battle" and runtime.inventoryOpen) then handleInventoryRelease(x,y,button) end
  end

  local function wheelmoved(_,y)
      local mouseX,mouseY=pointerPosition()
      local shifted=love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lshift","rshift")
      if runtime.state=="game" and runtime.trainUpgradeOpen and not ui.optionsOpen and not ui.escMenuOpen and not runtime.exitPrompt then
          if runtime.weaponRepairOpen and y~=0 then
              local mx,my=screenToGame(mouseX,mouseY)
              mx,my=UIStyle.inversePoint(mx,my,"trainUpgrades",RepairLayout.bounds)
              if Util.pointIn(mx,my,RepairLayout.wheelBounds) then
                  scrollRepairWeapons((runtime.weaponRepairScroll or 1)+(y>0 and -1 or 1))
              end
          end
          return
      end
      if ui.optionsOpen and runtime.optionsPage=="controls" and runtime.optionsControlDevice~="touch" and y~=0 then
          local list=runtime.optionsControlDevice=="keyboard" and controlBindings:keyActions()
              or (runtime.optionsControllerSection=="axes" and controlBindings:axisActions() or controlBindings:buttonActions())
          runtime.optionsControlScroll=math.max(0,math.min(math.max(0,#list-(ui.controlBindingVisibleRows or 14)),
              (runtime.optionsControlScroll or 0)+(y>0 and -2 or 2)))
          return
      end
      if runtime.journeyLogOpen then
          runtime.journeyLogScroll=math.max(0,math.min(ui.journeyLogMaxScroll or 0,(runtime.journeyLogScroll or 0)+(y>0 and -1 or (y<0 and 1 or 0))))
          return
      end
      if runtime.state=="battle" and runtime.battle then
          local mx,my=screenToGame(mouseX,mouseY)
          if mx>=185 and mx<=775 and my>=488 and my<=570 then
              runtime.battle.logScroll=math.max(0,math.min(math.max(0,#(runtime.battle.log or {})-1),(runtime.battle.logScroll or 0)+(y>0 and 1 or -1)))
              return
          end
      end
      if shifted and runtime.state=="game" and runtime.mapOpen then
          runtime.mapScroll=math.max(0,runtime.mapScroll-(y>0 and 1 or -1)); return
      end
      if runtime.state=="characters" then
          if not runtime.characterPreviewFile and y~=0 then
              local xGame,yGame=screenToGame(mouseX,mouseY)
              if xGame>=20 and xGame<=940 and yGame>=94 and yGame<=708 then
                  local maximum=ui.characterMaxScroll or 0
                  runtime.characterScroll=math.max(0,math.min(maximum,runtime.characterScroll+(y>0 and -1 or 1)))
              end
          end
          return
      end
      zoomCamera(y,mouseX,mouseY)
  end

  local function keypressedGlobal(key)
      if ui.mobileMenuOpen and key=="escape" then ui.mobileMenuOpen=false; return true end
      if runtime.helpDialogue then
          local index=tonumber(key)
          if index and index>=1 and index<=#(runtime.helpDialogue.choices or {}) then chooseHelpDialogue(index)
          elseif key=="escape" or key=="q" then chooseHelpDialogue(nil) end
          return true
      end
      if runtime.firstAid then
          local outcome=FirstAid.keypressed(runtime.firstAid,key)
          if outcome=="complete" or outcome=="failed" or outcome=="cancelled" then resolveFirstAid(outcome) end
          return true
      end
      if maintenanceSession.open then
          local result=Maintenance.keypressed(maintenanceSession,key,runtime.saveData)
          if result=="serviced" then ui.playSfx("menu") elseif result=="completed" then ui.playSfx("trainArrive"); writeSave() end
          return true
      end
      if runtime.tradeOpen then if key=="escape" or key=="q" then runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; writeSave() end; return end
      if runtime.state=="characters" and runtime.characterPreviewFile then
          if key=="return" or key=="kpenter" or key=="e" then chooseCharacter(runtime.characterPreviewFile)
          elseif key=="escape" or key=="q" then closeCharacterPreview() end
          return
      end
      if runtime.state=="event" then
          local choice=key=="1" and 1 or (key=="2" and 2 or (key=="3" and 3)); if choice then ui.keyboardFocusVisible=true; requestEventChoice(choice) end
          return
      end
      if runtime.state=="ending" then
          if not (runtime.saveData.finale and runtime.saveData.finale.choice) then
              local index=tonumber(key); local control=index and ui.endingChoices and ui.endingChoices[index]
              if control then chooseFinale(control.id); writeSave() end
          elseif key=="return" or key=="space" or key=="escape" then writeSave(); runtime.state="slots" end
          return
      end
      if runtime.state=="characters" and (key=="down" or key=="s" or key=="pagedown") then runtime.characterScroll=runtime.characterScroll+1; return end
      if runtime.state=="characters" and (key=="up" or key=="w" or key=="pageup") then runtime.characterScroll=math.max(0,runtime.characterScroll-1); return end
      if runtime.travelConfirm then if key=="escape" then runtime.travelConfirm=false elseif key=="return" or key=="e" then startTravel() end; return end
      if runtime.state=="battle" then
          local battle=runtime.battle
          if not battle then return true end
          local active=BattleRules.activeUnit(battle)
          if runtime.inventoryOpen then
              if key=="i" or key=="escape" then runtime.inventoryOpen=false; runtime.draggedSlot=nil; runtime.inventoryDragActive=false end
          elseif runtime.battle.finished and (key=="return" or key=="space" or key=="e") then
              finishBattle(runtime.battle.finished)
          elseif runtime.battle.finished or runtime.battle.intro or not active or active.team~="ally" or active.hp<=0 then return true
          elseif key=="i" then runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; ui.playSfx("menu")
          elseif not runtime.battle.finished and tonumber(key) and runtime.battle.options and runtime.battle.options[tonumber(key)] then battleAttack(runtime.battle.options[tonumber(key)])
          elseif not runtime.battle.finished and key=="h" then battleHeal()
          elseif not runtime.battle.finished and key=="m" and not runtime.battle.moveUsed then runtime.battle.phase="move"; setBattlePrompt("Choose a highlighted terrain piece to move.")
          elseif not runtime.battle.finished and key=="g" then battleGuard()
          elseif not runtime.battle.finished and key=="space" then advanceBattleTurn()
          elseif not runtime.battle.finished and (key=="r" or key=="escape") then finishBattle("retreat") end
          return
      end
      if runtime.state=="game" and runtime.inventoryOpen and key=="e" then runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; if runtime.giftOpen then runtime.giftOpen=false; runtime.giftSlot=nil end; writeSave(); return true end
      if runtime.state=="game" and runtime.dialogue and runtime.dialogue.choice and runtime.questOffer then if key=="y" or key=="return" or key=="e" then acceptQuest(runtime.questOffer.kind) elseif key=="n" or key=="escape" then declineQuestOffer() end; return true end
      if runtime.state=="game" and runtime.carTransition then return true end
      return false
  end

  function ui.routeWorldInteraction(key)
      local action,arg=interactionKeyAction({selected=ui.interaction,dialogue=runtime.dialogue,
          blocked=WorldPause.isPaused(runtime,ui,maintenanceSession,{allowDialogue=true}),
          isFurniture=function(index) local item=runtime.saveData.droppedItems[index]; return isFurnitureItem(item and item.name) end},key)
      if not action then return false end
      if action=="closeDialogue" then runtime.dialogue=nil
      elseif action=="talkPassenger" then
          local p=runtime.saveData.passengers[arg]
          local lines=#(Catalog.passengerLines or {})>0 and Catalog.passengerLines or Catalog.dialogueLines
          local line,status=NpcRelationships.passengerDialogue(runtime.saveData,p,lines)
          runtime.questOffer=nil
          runtime.dialogue={speaker=line and (Util.titleFromFile(p.npc).." • "..status.name) or "PASSENGER",
              text=line or ("Destination: stop "..tostring(p.destination or "—")..". No new conversation available."),timer=7}; writeSave()
      elseif action=="car" then beginCarTransition((runtime.saveData.activeCar or 1)+arg)
      elseif action=="talkNPC" then ui.playSfx("talking"); talkToNPC()
      elseif action=="enterHouse" then
          runtime.saveData.lastStopDoor=arg; runtime.saveData.activeHouseDoor=arg; ui.playSfx("doors"); runtime.scene="house"
          local homeLayout=Stops.ensureDoor(runtime.saveData,Catalog,arg); ensureHouseItems(); runtime.player.x,runtime.player.y=InteriorDoors.spawnPoint(homeLayout.interior,scenery.interiorFiles); setupNPC(); writeSave()
      elseif action=="exitHouse" then exitHouse()
      elseif action=="shootingRange" then beginShootingRange()
      elseif action=="expedition" then activateExpeditionInteraction(arg)
      elseif action=="caravan" then activateCaravanInteraction(arg)
      elseif action=="returnTrain" then
          enterTrain(true)
      elseif action=="give" then giveWeaponToNearby()
      elseif action=="openStorage" then runtime.activeChest=runtime.saveData.droppedItems[arg]; runtime.activeChest.storage=runtime.activeChest.storage or {}; runtime.activeChest.mailUnread=false; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; runtime.inventoryDragActive=false; writeSave()
      elseif action=="holdPickup" then runtime.holdPickupIndex=arg; runtime.holdPickupTime=0
      elseif action=="pickup" then runtime.nearbyItem=arg; pickUpNearby()
      elseif action=="fire" then addCoalToFire() end
      return true
  end

  local function focusTargets()
      local targets={}
      local screenKey
      local function add(id,rect,activate,enabled,transformElement,transformBounds)
          if not rect or enabled==false or rect.enabled==false then return end
          if transformElement then rect=UIStyle.transformRectFor(transformElement,transformBounds,rect) end
          targets[#targets+1]={id=id,rect=rect,activate=activate,enabled=enabled}
      end
      local function sortedKeys(values)
          local keys={}
          for key in pairs(values or {}) do keys[#keys+1]=key end
          table.sort(keys)
          return keys
      end
      local function clickHandler(id,rect,handler,enabled)
          add(id,rect,function()
              handler(rect.x+rect.w/2,rect.y+rect.h/2)
          end,enabled)
      end

      if runtime.pendingConfirmation then
          screenKey="confirmation"
          local isDelete=runtime.pendingConfirmation.kind=="deleteSave"
          if isDelete then
              add("confirmation.cancel",ui.confirmNo,function() commitConfirmation(false) end)
              add("confirmation.confirm",ui.confirmYes,function() commitConfirmation(true) end)
          else
              add("confirmation.confirm",ui.confirmYes,function() commitConfirmation(true) end)
              add("confirmation.cancel",ui.confirmNo,function() commitConfirmation(false) end)
          end
      elseif runtime.exitPrompt then
          screenKey="exit-confirmation"
          add("exit.yes",ui.exitYes,function() resolveExitPrompt("yes") end)
          add("exit.no",ui.exitNo,function() resolveExitPrompt("no") end)
      elseif ui.escMenuOpen then
          screenKey="escape-menu"
          local choices={ui.escChoiceContinue,ui.escChoiceOptions,ui.escChoiceTitle,ui.escChoiceQuit}
          local start=math.max(1,math.min(4,tonumber(ui.escMenuSelection) or 1))
          for offset=0,3 do
              local choice=((start-1+offset)%4)+1
              add("escape."..choice,choices[choice],function() activateEscapeChoice(choice) end)
          end
      elseif ui.optionsOpen then
          screenKey="options:"..tostring(runtime.optionsPage or "audio")
          if runtime.optionsPage=="controls" then
              screenKey=screenKey..":"..tostring(runtime.optionsControlDevice or "keyboard")
                  ..":"..tostring(runtime.optionsControllerSection or "buttons")
          end
          local function option(id,rect) clickHandler("options."..id,rect,ui.handleOptionsMousePressed) end
          if runtime.optionsPage=="audio" then
              option("audioTab",ui.optionsAudioTab); option("accessibilityTab",ui.optionsAccessTab); option("controlsTab",ui.optionsControlsTab)
              for _,entry in ipairs({{"station8bit",ui.optionsStation8bit},{"stationChill",ui.optionsStationChill},
                  {"stationVibes",ui.optionsStationVibes},{"stationRain",ui.optionsStationRain},
                  {"musicDown",ui.musicDown},{"musicUp",ui.musicUp},{"sfxDown",ui.sfxDown},{"sfxUp",ui.sfxUp},
                  {"rainDown",ui.rainDown},{"rainUp",ui.rainUp},{"musicPrevious",ui.musicPrevious},
                  {"musicPause",ui.musicPause},{"musicNext",ui.musicNext},{"musicMute",ui.musicMute}}) do
                  option(entry[1],entry[2])
              end
          elseif runtime.optionsPage=="accessibility" then
              option("accessibilityTab",ui.optionsAccessTab); option("audioTab",ui.optionsAudioTab); option("controlsTab",ui.optionsControlsTab)
              for _,entry in ipairs({{"textSize",ui.accessTextSize},{"highContrast",ui.accessHighContrast},
                  {"reducedMotion",ui.accessReducedMotion},{"controlHints",ui.accessControlHints},
                  {"touchFeedback",ui.accessTouchFeedback},{"largeTouchTargets",ui.accessLargeTouchTargets}}) do
                  option(entry[1],entry[2])
              end
          else
              option("controlsTab",ui.optionsControlsTab); option("audioTab",ui.optionsAudioTab); option("accessibilityTab",ui.optionsAccessTab)
              add("controls.keyboard",ui.controlsKeyboardTab,function() runtime.optionsControlDevice="keyboard"; runtime.optionsControlScroll=0 end)
              add("controls.controller",ui.controlsControllerTab,function() runtime.optionsControlDevice="controller"; runtime.optionsControllerSection=runtime.optionsControllerSection or "buttons"; runtime.optionsControlScroll=0 end)
              add("controls.touch",ui.controlsTouchTab,function() runtime.optionsControlDevice="touch"; runtime.optionsControlScroll=0 end)
              add("controls.buttons",ui.controlsButtonsTab,function() runtime.optionsControllerSection="buttons"; runtime.optionsControlScroll=0 end)
              add("controls.axes",ui.controlsAxesTab,function() runtime.optionsControllerSection="axes"; runtime.optionsControlScroll=0 end)
              for _,row in ipairs(ui.controlBindingRows or {}) do
                  local actionId,device,field,clear=row.entryId,row.device,row.rect,row.clear
                  add("controls.binding."..actionId,field,function() controlBindings:beginCapture(device,actionId) end)
                  add("controls.clear."..actionId,clear,function() controlBindings:clear(device,actionId) end)
              end
              add("controls.reset",ui.controlsReset,function()
                  local device=runtime.optionsControlDevice or "keyboard"
                  local resetDevice=device=="keyboard" and "key"
                      or (device=="controller" and (runtime.optionsControllerSection=="axes" and "axis" or "button") or nil)
                  if resetDevice then controlBindings:reset(resetDevice) end
                  runtime.optionsControlScroll=0
              end)
              add("controls.scrollUp",ui.controlsScrollUp,function() runtime.optionsControlScroll=math.max(0,(runtime.optionsControlScroll or 0)-1) end,(runtime.optionsControlScroll or 0)>0)
              local controlDevice=runtime.optionsControlDevice or "keyboard"
              local controlList=controlDevice=="keyboard" and controlBindings:keyActions()
                  or (runtime.optionsControllerSection=="axes" and controlBindings:axisActions() or controlBindings:buttonActions())
              local maxControlScroll=math.max(0,#controlList-(ui.controlBindingVisibleRows or 14))
              add("controls.scrollDown",ui.controlsScrollDown,function()
                  runtime.optionsControlScroll=math.min(maxControlScroll,(runtime.optionsControlScroll or 0)+1)
              end,(runtime.optionsControlScroll or 0)<maxControlScroll)
              option("touchControls",ui.controlsEditorButton)
          end
          option("back",ui.optionsBack)
      elseif runtime.journeyLogOpen then
          screenKey="journey-log"
          add("journey-log.close",ui.journeyLogClose,function() setJourneyLogOpen(false,true) end)
          add("journey-log.up",ui.journeyLogUp,function()
              runtime.journeyLogScroll=math.max(0,(runtime.journeyLogScroll or 0)-math.max(1,ui.journeyLogPageSize or 1))
          end,(runtime.journeyLogScroll or 0)>0)
          add("journey-log.down",ui.journeyLogDown,function()
              runtime.journeyLogScroll=math.min(ui.journeyLogMaxScroll or 0,(runtime.journeyLogScroll or 0)+math.max(1,ui.journeyLogPageSize or 1))
          end,(runtime.journeyLogScroll or 0)<(ui.journeyLogMaxScroll or 0))
      elseif runtime.state=="slots" then
          screenKey="title-slots"
          for index=1,3 do
              local slot=index
              add("slot."..slot..".continue",ui.slots and ui.slots[slot],function()
                  local data=readSave(slot)
                  if data then runtime.selectedSlot=slot; enterGame(data) end
              end)
              add("slot."..slot..".new",ui.slotNew and ui.slotNew[slot],function()
                  requestNewJourney(slot)
              end)
              add("slot."..slot..".delete",ui.slotDelete and ui.slotDelete[slot],function()
                  requestConfirmation("deleteSave",{slot=slot,message="Delete Save Slot "..slot.."? This cannot be undone."})
              end)
          end
      elseif runtime.state=="characters" then
          screenKey=runtime.characterPreviewFile and "character-profile" or "character-select"
          if runtime.characterPreviewFile then
              add("character.confirm",ui.characterConfirm,function() chooseCharacter(runtime.characterPreviewFile) end)
              add("character.cancel",ui.characterCancel,closeCharacterPreview)
              for index,entry in ipairs(ui.characterMovementActions or {}) do
                  local action=entry.id
                  add("character.movement."..index,entry.control,function() runtime.characterPreviewAction=action end)
              end
              for index,entry in ipairs(ui.characterPoseActions or {}) do
                  local action=entry.id
                  add("character.pose."..index,entry.control,function() runtime.characterPreviewAction=action; if runtime.characterPreviewDirection~="W" and runtime.characterPreviewDirection~="E" then runtime.characterPreviewDirection="E" end end)
              end
              for _,direction in ipairs({"NW","N","NE","W","E","SW","S","SE"}) do
                  local control=ui.characterDirections and ui.characterDirections[direction]
                  local chosen=direction
                  if control then add("character.direction."..chosen,control,function() runtime.characterPreviewDirection=chosen end,control.active) end
              end
          else
              for index,rect in ipairs(ui.characters or {}) do
                  if rect.visible then
                      local file=characters[index]
                      add("character.card."..index,rect,function() openCharacterPreview(file) end)
                  end
              end
              local maxScroll=ui.characterMaxScroll or 0
              add("character.scrollUp",ui.characterUp,function() runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll-1)) end,runtime.characterScroll>0)
              add("character.scrollDown",ui.characterDown,function() runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll+1)) end,runtime.characterScroll<maxScroll)
          end
      elseif runtime.state=="event" then
          screenKey="random-event"
          for index,rect in ipairs(ui.eventChoices or {}) do
              local choice=index
              local transformed=UIStyle.transformRectFor("event",{x=60,y=42,w=840,h=640},rect)
              add("event.choice."..choice,transformed,function() requestEventChoice(choice) end,rect.enabled~=false)
          end
      elseif runtime.state=="ending" then
          screenKey="ending"
          if not (runtime.saveData.finale and runtime.saveData.finale.choice) then
              for index,control in ipairs(ui.endingChoices or {}) do
                  local choiceId=control.id
                  add("ending.choice."..index,control,function() chooseFinale(choiceId); writeSave() end)
              end
          else
              add("ending.return",ui.endingButton,function() writeSave(); runtime.state="slots" end)
          end
      elseif runtime.travelConfirm then
          screenKey="travel-confirmation"
          add("travel.confirm",ui.travelYes,function() startTravel() end)
          add("travel.cancel",ui.travelNo,function() runtime.travelConfirm=false end)
      elseif runtime.tradeOpen then
          screenKey="trade-shop"
          local function trade(id,rect,enabled) clickHandler("trade."..id,rect,ui.handleTradeClick,enabled) end
          local source=currentTradeSource()
          for _,index in ipairs(sortedKeys(ui.tradeBuy)) do
              local rect=ui.tradeBuy[index]
              local enabled=source and MerchantTrade.canBuy(runtime.saveData,Catalog,source,index) or false
              trade("buy."..index,rect,enabled)
          end
          for _,index in ipairs(sortedKeys(ui.tradeSell)) do local rect=ui.tradeSell[index]; trade("sell."..index,rect,rect.enabled) end
          for _,index in ipairs(sortedKeys(ui.tradeGive)) do trade("give."..index,ui.tradeGive[index]) end
          trade("buyPrevious",ui.tradeBuyPrev,ui.tradeBuyPrev and ui.tradeBuyPrev.enabled)
          trade("buyNext",ui.tradeBuyNext,ui.tradeBuyNext and ui.tradeBuyNext.enabled)
          trade("sellPrevious",ui.tradePrev,ui.tradePrev and ui.tradePrev.enabled)
          trade("sellNext",ui.tradeNext,ui.tradeNext and ui.tradeNext.enabled); trade("close",ui.tradeClose)
      elseif runtime.trainUpgradeOpen and runtime.weaponRepairOpen then
          screenKey="weapon-repair"
          for _,entry in ipairs(ui.repairRows or {}) do
              local name=entry.name
              add("weapon-repair.select."..name,entry.rect,function() selectRepairWeapon(name) end,true,"trainUpgrades",RepairLayout.bounds)
          end
          add("weapon-repair.list-up",ui.repairListUp,function() scrollRepairWeapons((runtime.weaponRepairScroll or 1)-1) end)
          add("weapon-repair.list-down",ui.repairListDown,function() scrollRepairWeapons((runtime.weaponRepairScroll or 1)+1) end)
          add("weapon-repair.start",ui.repairStart,activateWeaponRepair)
          add("weapon-repair.back",ui.repairBack,returnFromWeaponRepair)
          add("weapon-repair.close",ui.repairClose,returnFromWeaponRepair)
      elseif runtime.trainUpgradeOpen then
          screenKey="train-upgrades"
          local function upgrade(id,rect,enabled) clickHandler("upgrade."..id,rect,ui.handleUpgradeMousePressed,enabled) end
          upgrade("engine",ui.engineUpgrade,ui.engineUpgrade and ui.engineUpgrade.enabled)
          upgrade("repair",ui.weaponRepair,ui.weaponRepair and ui.weaponRepair.enabled); upgrade("close",ui.upgradeClose)
          upgrade("sewing",ui.sewingBench,ui.sewingBench and ui.sewingBench.enabled)
          for index,rect in ipairs(ui.trainCars or {}) do upgrade("car."..index,rect,rect.enabled) end
      elseif runtime.mapOpen then
          screenKey="map"
          local maxScroll=math.max(0,math.floor(((runtime.saveData.location or 1)-1)/6)-2)
          add("map.up",ui.mapUp,function() runtime.mapScroll=math.max(0,runtime.mapScroll-1) end,(runtime.mapScroll or 0)>0)
          add("map.down",ui.mapDown,function() runtime.mapScroll=math.min(maxScroll,(runtime.mapScroll or 0)+1) end,(runtime.mapScroll or 0)<maxScroll)
          add("map.close",ui.expeditionMapClose or ui.map,function() runtime.mapOpen=false end)
      elseif runtime.inventoryOpen then
          screenKey="inventory"
          local panel={x=25,y=35,w=910,h=660}
          local function inventorySlot(kind,index,rect,slotName)
              local slot={kind=kind,index=index,slot=slotName}
              local transformed=UIStyle.transformRectFor("inventory",panel,rect)
              add("inventory."..kind.."."..(slotName or index),transformed,function()
                  if runtime.giftOpen then
                      if kind=="inventory" and runtime.saveData.inventory[index] then runtime.giftSlot=index end
                  elseif runtime.draggedSlot then
                      local from=runtime.draggedSlot
                      local same=from.kind==kind and (kind=="wearable" and from.slot==slotName or kind~="wearable" and from.index==index)
                      if same then runtime.draggedSlot=nil; runtime.inventoryDragActive=false
                      elseif ui.keyboardInventoryMove and ui.keyboardInventoryMove(from,slot) then runtime.draggedSlot=nil; runtime.inventoryDragActive=false
                      elseif ui.keyboardInventoryValue and ui.keyboardInventoryValue(slot) then runtime.draggedSlot=slot; runtime.inventoryDragActive=false end
                  elseif ui.keyboardInventoryValue and ui.keyboardInventoryValue(slot) then
                      runtime.draggedSlot=slot; runtime.inventoryDragActive=false
                  end
              end)
          end
          if runtime.chestOpen then
              for index,rect in ipairs(ui.chestSlots or {}) do inventorySlot("chest",index,rect) end
          end
          local capacity=runtime.saveData.inventoryCapacity or 6
          for index=1,capacity do
              local rect
              if mobileEnabled() then
                  rect=Inventory.mobileInventorySlotRect(index)
                  if capacity>12 then rect.y=230+math.floor((index-1)/4)*56; rect.h=50 end
              else rect=Inventory.inventorySlotRect(index) end
              inventorySlot("inventory",index,rect)
          end
          for index=1,2 do
              local rect=mobileEnabled() and Inventory.mobileEquipmentSlotRect(index) or Inventory.equipmentSlotRect(index)
              inventorySlot("equipment",index,rect)
          end
          for mode,rect in pairs(ui.inventoryModeTabs or {}) do
              local selectedMode=mode
              add("inventory.mode."..selectedMode,UIStyle.transformRectFor("inventory",panel,rect),function()
                  runtime.inventoryMode=selectedMode; runtime.draggedSlot=nil; runtime.inventoryDragActive=false
              end)
          end
          if runtime.inventoryMode=="wearables" then
              for index,slot in ipairs(Catalog.wearableSlots or {}) do
                  local rect=ui.wearableSlots and ui.wearableSlots[slot.id] or Inventory.wearableSlotRect(index)
                  inventorySlot("wearable",nil,rect,slot.id)
              end
          end
          if runtime.giftOpen then
              add("inventory.giftOffer",ui.giftConfirm,function() if runtime.giftSlot then ui.offerGift(runtime.giftSlot) end end)
              add("inventory.giftCancel",ui.giftCancel,function() runtime.giftOpen=false; runtime.giftSlot=nil end)
          else
              if ui.inventoryWeaponRepair then
                  add("inventory.weaponRepair",UIStyle.transformRectFor("inventory",panel,ui.inventoryWeaponRepair),function()
                      if ui.openWeaponRepairWorkbench then ui.openWeaponRepairWorkbench() end
                  end,ui.inventoryWeaponRepair.enabled)
              end
              if ui.inventorySewingBench then
                  add("inventory.sewing",UIStyle.transformRectFor("inventory",panel,ui.inventorySewingBench),function()
                      if ui.openOutfitWorkbench then ui.openOutfitWorkbench() end
                  end,ui.inventorySewingBench.enabled)
              end
              add("inventory.use",ui.consume,function() if ui.keyboardInventoryConsume then ui.keyboardInventoryConsume() end end)
              add("inventory.drop",ui.drop,function() if runtime.draggedSlot and ui.keyboardInventoryDrop then ui.keyboardInventoryDrop(runtime.draggedSlot) end end)
          end
          add("inventory.close",ui.backpack,function() runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil; runtime.inventoryDragActive=false end)
      elseif runtime.helpDialogue then
          screenKey="help-dialogue"
          for index,rect in ipairs(ui.helpDialogueChoices or {}) do
              local choice=index
              add("dialogue.choice."..choice,rect,function() chooseHelpDialogue(choice) end)
          end
          add("dialogue.later",ui.helpDialoguePause,function() chooseHelpDialogue(nil) end)
      elseif runtime.dialogue and runtime.dialogue.choice and runtime.questOffer then
          screenKey="quest-dialogue"
          add("dialogue.accept",ui.questAccept,function() acceptQuest(runtime.questOffer.kind) end)
          add("dialogue.decline",ui.questDecline,declineQuestOffer)
      elseif runtime.dialogue then
          screenKey="dialogue"
          add("dialogue.continue",ui.dialogueContinue,function() runtime.dialogue=nil end)
      end
      return targets,screenKey
  end

  local function drawKeyboardFocus()
      local targets,screenKey=focusTargets()
      local target=UIFocus.current(ui,targets,screenKey)
      if ui.keyboardFocusVisible or screenKey=="confirmation" or screenKey=="exit-confirmation" then UIFocus.draw(target) end
  end
  ui.drawKeyboardFocus=drawKeyboardFocus

  local function handleKeyboardFocus(key)
      local targets,screenKey=focusTargets()
      if not screenKey or #targets==0 then return false end
      local direction=key
      if key=="a" then direction="left" elseif key=="d" then direction="right"
      elseif key=="w" then direction="up" elseif key=="s" then direction="down" end
      if direction=="left" or direction=="right" or direction=="up" or direction=="down" or key=="tab" then
          local reverse=key=="tab" and love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lshift","rshift")
          UIFocus.move(ui,targets,screenKey,key=="tab" and "tab" or direction,reverse)
          if screenKey=="escape-menu" then
              local selected=UIFocus.current(ui,targets,screenKey)
              ui.escMenuSelection=selected and tonumber(selected.id:match("escape%.(%d+)")) or ui.escMenuSelection
          end
          ui.playSfx("menu")
          return true
      end
      if key=="return" or key=="kpenter" or key=="space" then
          local target=UIFocus.current(ui,targets,screenKey)
          ui.keyboardFocusVisible=true
          if target and target.activate then target.activate() end
          return true
      end
      return false
  end

  local function keypressed(key,scancode,isrepeat)
      if runtime.pendingConfirmation then
          if key=="escape" or key=="q" or key=="n" then commitConfirmation(false); return true end
          if key=="y" then commitConfirmation(true); return true end
          if handleKeyboardFocus(key) then return true end
          return true
      end
      if runtime.journeyLogOpen then
          if key=="j" then setJourneyLogOpen(false,true); return true end
          local direction=key
          if key=="w" then direction="up" elseif key=="s" then direction="down" end
          if direction=="up" or key=="pageup" then
              runtime.journeyLogScroll=math.max(0,(runtime.journeyLogScroll or 0)-(key=="pageup" and math.max(1,ui.journeyLogPageSize or 1) or 1)); return true
          elseif direction=="down" or key=="pagedown" then
              runtime.journeyLogScroll=math.min(ui.journeyLogMaxScroll or 0,(runtime.journeyLogScroll or 0)+(key=="pagedown" and math.max(1,ui.journeyLogPageSize or 1) or 1)); return true
          elseif key~="escape" then
              if handleKeyboardFocus(key) then return true end
              return true
          end
      end
      if runtime.state=="game" and runtime.trainUpgradeOpen and not runtime.exitPrompt and not ui.escMenuOpen and not ui.optionsOpen then
          if isrepeat and (key=="space" or key=="return" or key=="kpenter") then return true end
          if key=="escape" or key=="q" then
              if runtime.weaponRepairOpen then returnFromWeaponRepair()
              else runtime.trainUpgradeOpen=false; cancelWeaponRepair() end
              return true
          end
          if runtime.weaponRepairOpen then
              if runtime.weaponRepairStartedAt and (key=="space" or key=="return" or key=="kpenter") then
                  activateWeaponRepair(); return true
              elseif key=="pageup" or key=="pagedown" then
                  scrollRepairWeapons((runtime.weaponRepairScroll or 1)+(key=="pageup" and -RepairLayout.visibleRows or RepairLayout.visibleRows)); return true
              end
          end
          handleKeyboardFocus(key)
          return true
      end
      if handleKeyboardFocus(key) then return true end
      if key=="escape" then
          if runtime.exitPrompt then resolveExitPrompt("no")
          elseif ui.optionsOpen then ui.optionsOpen=false; ui.escMenuOpen=true; ui.playSfx("menu")
          elseif ui.escMenuOpen then ui.escMenuOpen=false; ui.playSfx("menu")
          elseif runtime.state=="battle" and runtime.inventoryOpen then keypressedGlobal(key)
          else
              ui.escMenuOpen=true
              ui.escMenuSelection=1
              endCameraPan()
              ui.playSfx("menu")
          end
          return true
      end
      if runtime.exitPrompt then
          if key=="return" or key=="kpenter" or key=="y" then resolveExitPrompt("yes")
          elseif key=="n" then resolveExitPrompt("no") end
          return true
      end
      if ui.escMenuOpen then return handleEscapeMenuKey(key) end
      if ui.optionsOpen then return handleOptionsKey(key) end
      if key=="=" or key=="+" or key=="kp+" then zoomCamera(1); return end
      if key=="-" or key=="kp-" then zoomCamera(-1); return end
      if key=="0" or key=="kp0" then resetCamera(false); return end
      if runtime.state=="intro" then skipIntro(ui.introCinematic); return end
      if runtime.shootingRange then
          if key=="b" and runtime.shootingRange.phase=="lobby" then
              local offer=ShootingRange.ammoOffer(runtime.shootingRange,Catalog)
              if offer and (tonumber(runtime.saveData.scrap) or 0)>=offer.cost then
                  ui.keyboardFocusVisible=true
                  requestConfirmation("rangeAmmo",{message="Buy "..offer.amount.." "..string.upper(offer.ammo).." ammo for "..offer.cost.." scrap?"})
                  return true
              end
          end
          processRangeOutcome(ShootingRange.keypressed(runtime.shootingRange,key,runtime.saveData,Catalog))
          return
      end
      if love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lalt","ralt") then
          if key=="left" then panCamera(48,0); return elseif key=="right" then panCamera(-48,0); return
          elseif key=="up" then panCamera(0,48); return elseif key=="down" then panCamera(0,-48); return end
      end
      if keypressedGlobal(key) then return end
      if key=="j" and runtime.state=="game" then setJourneyLogOpen(true,true); return true end
      if key=="i" and runtime.state=="game" and not runtime.editMode then
          if runtime.inventoryOpen then
              runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil; runtime.inventoryDragActive=false
          elseif runtime.nearChest or runtime.nearMailbox then
              runtime.activeChest=runtime.saveData.droppedItems[runtime.nearChest or runtime.nearMailbox]
              if runtime.activeChest then runtime.activeChest.storage=runtime.activeChest.storage or {}; runtime.activeChest.mailUnread=false; runtime.chestOpen=true; runtime.inventoryOpen=true; runtime.draggedSlot=nil; writeSave() end
          else runtime.inventoryOpen=true; runtime.chestOpen=false; runtime.activeChest=nil; runtime.draggedSlot=nil end
      end
      if key=="m" and runtime.state=="game" then runtime.mapOpen=not runtime.mapOpen; if runtime.mapOpen then runtime.mapScroll=math.max(0,math.floor((runtime.saveData.location-1)/6)-2) end; runtime.inventoryOpen=false; runtime.dialogue=nil end
      if runtime.state=="game" and runtime.mapOpen then if key=="down" or key=="s" then runtime.mapScroll=runtime.mapScroll+1 elseif key=="up" or key=="w" then runtime.mapScroll=math.max(0,runtime.mapScroll-1) end; return end
      if runtime.state=="game" and runtime.editMode and runtime.editedItem then
          if key=="left" or key=="a" then moveEditedItem(-5,0) elseif key=="right" or key=="d" then moveEditedItem(5,0) elseif key=="up" or key=="w" then moveEditedItem(0,-5) elseif key=="down" or key=="s" then moveEditedItem(0,5) end
          return
      end
      if key=="p" and runtime.state=="game" and ui.nearRadio and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.editMode then ui.radioOpen=not ui.radioOpen; ui.optionsOpen=false; runtime.poseMenu=false; ui.playSfx("menu"); return end
      if key=="e" and runtime.state=="game" and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.editMode then runtime.actionKind="use"; runtime.actionTimer=.35 end
      if key=="f" and runtime.scene=="expedition" and not WorldPause.isPaused(runtime,ui,maintenanceSession) then
          attackExpeditionMob(quickAttackPoint()); return
      end
      if key=="g" or key=="e" then
          local selected=ui.interaction
          if ui.routeWorldInteraction(key) then
              require("game.interaction_beacon").notifyActivated(selected)
              return
          end
      end
  end

  local function keyreleased(key)
      if runtime.shootingRange then ShootingRange.keyreleased(runtime.shootingRange,key); return end
      if key=="e" and runtime.holdPickupIndex then
          runtime.holdPickupIndex,runtime.holdPickupTime=nil,0
      end
  end

  local function beginTouchPickup(x,y)
      if runtime.state~="game" or runtime.editMode or WorldPause.isPaused(runtime,ui,maintenanceSession) then return false end
      x,y=screenToGame(x,y)
      -- Keep fixed HUD buttons above the world, including while zoomed.
      if y<214 or Util.pointIn(x,y,ui.exitHome) or Util.pointIn(x,y,ui.returnStop) then return false end
      for _,tab in ipairs(ui.trainCarTabs or {}) do if Util.pointIn(x,y,tab) then return false end end
      x,y=worldCoordinates(x,y)
      local chosen,layer
      for index,item in ipairs(runtime.saveData.droppedItems) do
          if itemIsHere(item) and not item.permanent and isFurnitureItem(item.name) and not Catalog.storageCapacities[item.name] then
              local reach=math.max(32,29*(item.scale or 1)+12)
              local player=runtime.player
              if (player.x-item.x)^2+(player.y-item.y)^2<75^2
                  and math.abs(x-item.x)<=reach and math.abs(y-item.y)<=reach
                  and (not layer or (item.layer or index)>layer) then
                  chosen,layer=index,item.layer or index
              end
          end
      end
      if not chosen then return false end
      runtime.holdPickupIndex,runtime.holdPickupTime=chosen,0
      return true
  end

  return {
    beginTouchPickup=beginTouchPickup,
    mousepressed=mousepressed,
    mousemoved=mousemoved,
    mousereleased=mousereleased,
    wheelmoved=wheelmoved,
    keypressed=keypressed,
    keyreleased=keyreleased
  }
end

return {new=new}
