local AudioCatalog = require("game.audio_catalog")

local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"gameplay HUD requires "..name)
  if expected then assert(type(value)==expected,"gameplay HUD "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","gameplay HUD requires a context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local colors=required(context,"colors","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local HOLD_PICKUP_SECONDS=required(context,"holdPickupSeconds","number")
  local getCloudLayer=required(context,"getCloudLayer","function")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Clouds=required(context,"clouds","table")
  local Maintenance=required(context,"maintenance","table")
  local FirstAid=required(context,"firstAid","table")
  local Util=required(context,"util","table")
  local Train=required(context,"train","table")
  local button=required(context,"button","function")
  local drawMenuFrame=required(context,"drawMenuFrame","function")
  local drawTrade=required(context,"drawTrade","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local containerValue=required(context,"containerValue","function")
  local travelStatus=required(context,"travelStatus","function")
  local screenToGame=required(context,"screenToGame","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local getAudioStatus=required(context,"getAudioStatus","function")
  local drawLandscape=required(context,"drawLandscape","function")
  local drawTracks=required(context,"drawTracks","function")
  local drawTrainView=required(context,"drawTrainView","function")
  local drawHouse=required(context,"drawHouse","function")
  local drawStop=required(context,"drawStop","function")

  local function drawGame()
      local cloudLayer=getCloudLayer()
      ui.returnDoor,ui.exitHome=nil,nil
      if runtime.scene=="train" then
          drawLandscape(); drawTracks(); local tx=0
          if runtime.travelTransition then
              local t=runtime.travelTransition.t; local timing=EngineUpgrades.timings(runtime.saveData.engineLevel,runtime.travelTransition.maintenanceCondition or Maintenance.condition(runtime.saveData))
              if t<timing.depart then local p=t/timing.depart; tx=-W*(p*p*p)
              elseif t<timing.arrive then tx=-W
              else local p=math.min(1,(t-timing.arrive)/timing.arrivalDuration); local eased=1-(1-p)^3; tx=W*(1-eased) end
          end
          love.graphics.push(); love.graphics.translate(tx,0)
          if runtime.carTransition then
              local p=math.min(1,runtime.carTransition.t/runtime.carTransition.duration); local eased=p*p*(3-2*p); local direction=runtime.carTransition.to>runtime.carTransition.from and -1 or 1
              drawTrainView(runtime.carTransition.from,direction*W*eased,runtime.carTransition.from,runtime.player.x,runtime.player.y)
              drawTrainView(runtime.carTransition.to,direction*W*(eased-1),nil)
          else drawTrainView(runtime.saveData.activeCar or 1,0,runtime.saveData.activeCar or 1,runtime.player.x,runtime.player.y) end
          love.graphics.pop()
      elseif runtime.scene=="house" then drawHouse() else drawStop() end
      if runtime.scene=="train" or runtime.scene=="stop" then Clouds.draw(cloudLayer,runtime.scene,W,H,runtime.sceneryOffset,runtime.saveData.location) end
      ui.drawResource("FOOD",runtime.saveData.resources.food,20,colors.green,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"food")); ui.drawResource("WATER",runtime.saveData.resources.water,140,colors.blue,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"water"))
      ui.drawResource("COAL",runtime.saveData.resources.coal,260,colors.red,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"coal")); ui.drawResource("OIL",runtime.saveData.resources.oil,380,colors.brass,110,Maintenance.oilCapacity(runtime.saveData))
      ui.drawJourneyHUD()
      local travel=travelStatus()
      local cost=travel.cost
      local travelLabel=runtime.saveData.location>=50 and "JOURNEY COMPLETE"
        or ((travel.affordable and "TRAVEL" or "NEED").."  "..cost.food.."F  "..cost.water.."W  "..cost.coal.."C")
      local mobile=mobileEnabled()
      ui.travel,ui.leaveTrain,ui.backpack,ui.map,ui.editMode,ui.trainUpgrade,ui.maintenance,ui.pose,ui.options,ui.stopAttack,ui.trainCarTabs,ui.exitHome=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
      if mobile then
          if ui.mobileMenuOpen then
              love.graphics.setColor(0,0,0,.64); love.graphics.rectangle("fill",0,0,W,H)
              drawMenuFrame(250,62,690,610,2,.99)
              love.graphics.setColor(colors.cream); love.graphics.printf("JOURNEY MENU",275,84,640,"center",0,1.35,1.35)
              love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",295,122,600,3)
              local canTravel=runtime.scene=="train" and runtime.saveData.location<50 and travel.affordable
              ui.travel=runtime.scene=="train" and button(travelLabel,295,142,600,66,canTravel) or nil
              ui.backpack=button("BACKPACK",295,226,285,66,true)
              ui.map=button("TRAIL MAP",610,226,285,66,true)
              ui.trainUpgrade=runtime.scene=="train" and button("TRAIN UPGRADES  •  "..runtime.saveData.scrap.." SCRAP",295,310,285,66,true) or nil
              ui.editMode=runtime.scene=="train" and button("MOVE / SCALE",610,310,285,66,true) or nil
              ui.maintenance=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and not runtime.travelTransition and button("MAINTENANCE  •  "..math.floor(Maintenance.condition(runtime.saveData)).."%",295,394,285,66,true) or nil
              ui.pose=button("CHARACTER POSES",610,394,285,66,true)
              ui.options=button("AUDIO OPTIONS",295,478,285,66,true)
              ui.leaveTrain=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and button("LEAVE TRAIN",610,478,285,66,true) or nil
              ui.stopAttack=runtime.scene=="stop" and button("ATTACK",610,478,285,66,true) or nil
              love.graphics.setColor(colors.cream); love.graphics.printf("Tap BACK or CLOSE to return to the world",295,575,600,"center",0,.86,.86)
          end
      else
          ui.travel=runtime.scene=="train" and button(travelLabel,510,20,220,36,runtime.saveData.location<50 and travel.affordable) or nil
          -- Keep the departure control with the other scene controls, directly
          -- beneath Options, so it remains discoverable without covering the train.
          ui.leaveTrain=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and button("LEAVE TRAIN",790,194,135,32,true) or nil
          ui.backpack=button(runtime.inventoryOpen and "CLOSE" or "PACK",830,20,95,36,true)
          ui.map=button(runtime.mapOpen and "CLOSE MAP" or "MAP",735,20,87,36,true)
          ui.editMode=runtime.scene=="train" and button(runtime.editMode and "EDITING" or "MOVE / SCALE",745,70,180,36,true) or nil
          ui.trainUpgrade=runtime.scene=="train" and button("UPGRADE  "..runtime.saveData.scrap.." SCRAP",510,70,220,36,true) or nil
          ui.maintenance=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and not runtime.travelTransition and button("MAINTENANCE  "..math.floor(Maintenance.condition(runtime.saveData)).."%",510,112,220,32,true) or nil
          ui.pose=button(runtime.poseMenu and "CLOSE" or "POSES",745,112,85,32,true)
          ui.options=button(ui.optionsOpen and "CLOSE" or "OPTIONS",840,112,85,32,true)
          ui.stopAttack=runtime.scene=="stop" and button("ATTACK",790,650,135,38,true) or nil
      end
      local exitHomeVisible=runtime.scene=="house" and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue
          and not runtime.editMode and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.poseMenu
          and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not runtime.firstAid and not maintenanceSession.open
      if exitHomeVisible then
          ui.exitHome=mobile and button("EXIT HOME",700,150,238,66,true,.92) or button("EXIT HOME",790,194,135,38,true,.78)
      end
      local pendingMail=0; for _,mail in ipairs(runtime.saveData.mailQuests or {}) do if not mail.complete then pendingMail=pendingMail+1 end end
      if pendingMail>0 and ui.propImages["family-letter"] then local mail=ui.propImages["family-letter"]; local ms=28/math.max(mail:getWidth(),mail:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(mail,470,127,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2); love.graphics.setColor(colors.cream); love.graphics.print("x"..pendingMail,487,117,0,.9,.9) end
      if #(runtime.saveData.passengers or {})>0 then love.graphics.setColor(colors.cream); love.graphics.print("Passengers: "..#runtime.saveData.passengers,560,151,0,.82,.82) end
      ui.exitTrain = nil
      local tipColor={colors.panel[1],colors.panel[2],colors.panel[3],.50}
      local nearbyFurniture=runtime.nearbyItem and isFurnitureItem(runtime.saveData.droppedItems[runtime.nearbyItem] and runtime.saveData.droppedItems[runtime.nearbyItem].name)
      local contextText,contextScale
      if not runtime.inventoryOpen and not runtime.editMode and not runtime.carTransition and not ui.mobileMenuOpen then
          if mobile then
              if ui.nearRadio then contextText,contextScale="TAP RADIO",.78
              elseif runtime.nearPassenger or runtime.nearNPC then contextText,contextScale="TAP TALK   •   TAP GIVE",.72
              elseif runtime.nearCarNext then contextText,contextScale="TAP DOOR FOR NEXT CAR",.72
              elseif runtime.nearCarPrev then contextText,contextScale="TAP DOOR FOR PREVIOUS CAR",.66
              elseif runtime.nearMailbox then contextText,contextScale="TAP OPEN FOR REWARD MAILBOX",.66
              elseif runtime.nearChest then contextText,contextScale="TAP OPEN   •   HOLD PICK UP",.66
              elseif nearbyFurniture then contextText,contextScale="HOLD PICK UP FOR FURNITURE",.68
              elseif runtime.nearHouse then contextText,contextScale="TAP ENTER",.78
              elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="TAP EXIT",.78
              elseif ui.interaction and ui.interaction.kind=="stopActivity" then contextText,contextScale="TAP HELP  •  "..(ui.interaction.label or "COMMUNITY TASK"),.62
              elseif runtime.nearReturnTrain then contextText,contextScale="TAP BOARD",.78
              elseif runtime.nearFire then contextText,contextScale="TAP COAL",.78 end
          elseif ui.nearRadio then contextText,contextScale="P  OPEN RADIO",.72
          elseif runtime.nearPassenger then contextText,contextScale="Q  TALK   •   G  GIVE",.72
          elseif runtime.nearCarNext then contextText,contextScale="Q  ENTER NEXT CAR",.72
          elseif runtime.nearCarPrev then contextText,contextScale="Q  RETURN TO PREVIOUS CAR",.66
          elseif runtime.nearNPC then contextText,contextScale="Q  TALK   •   G  GIVE",.72
          elseif runtime.nearMailbox then contextText,contextScale="RIGHT CLICK OPEN REWARD MAILBOX",.66
          elseif runtime.nearChest then contextText,contextScale="RIGHT CLICK OPEN   •   HOLD E PICK UP",.66
          elseif nearbyFurniture then contextText,contextScale="HOLD E  PICK UP FURNITURE",.72
          elseif runtime.nearHouse then contextText,contextScale="Q  ENTER HOME",.78
          elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="Q  LEAVE HOME",.78
          elseif ui.interaction and ui.interaction.kind=="stopActivity" then contextText,contextScale="Q  HELP  •  "..(ui.interaction.label or "COMMUNITY TASK"),.62
          elseif runtime.nearReturnTrain then contextText,contextScale="Q  BOARD TRAIN",.78
          elseif runtime.nearFire then contextText,contextScale="E  ADD COAL",.78 end
      end
      if contextText then
          love.graphics.setColor(tipColor); love.graphics.rectangle("fill",325,300,310,40,6,6); love.graphics.setColor(colors.cream)
          love.graphics.printf(contextText,325,312,310,"center",0,contextScale,contextScale)
          if runtime.holdPickupIndex then love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",365,335,230*math.min(1,runtime.holdPickupTime/HOLD_PICKUP_SECONDS),5,2,2) end
      end
      if runtime.scene=="train" and #(runtime.saveData.trainCars or {})>1 and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue and not runtime.editMode and not ui.mobileMenuOpen then
          local active=runtime.saveData.activeCar or 1
          ui.trainCarTabs=Train.consistLayout(W,#runtime.saveData.trainCars)
          for index,tab in ipairs(ui.trainCarTabs) do
              local selected=index==active
              love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",tab.x,tab.y,tab.w,tab.h,7,7)
              love.graphics.setColor(selected and colors.brass or colors.cream); love.graphics.setLineWidth(selected and 3 or 1)
              love.graphics.rectangle("line",tab.x,tab.y,tab.w,tab.h,7,7)
              love.graphics.printf(tostring(index),tab.x,tab.y+12,tab.w,"center",0,.78,.78)
          end
          love.graphics.setLineWidth(1); love.graphics.setColor(colors.cream)
          love.graphics.printf("CAR "..active.." / "..#runtime.saveData.trainCars.."  •  "..Util.titleFromFile(runtime.saveData.trainCars[active]),430,240,W-455,"center",0,.68,.68)
      end
      ui.pickup = runtime.nearbyItem and not nearbyFurniture and not runtime.editMode and not ui.mobileMenuOpen and button("PICK UP  [E]",390,650,180,38,true) or nil
      if runtime.inventoryOpen then if runtime.chestOpen then ui.drawChestInventory() end; ui.drawInventory() end
      if runtime.inventoryOpen and runtime.inventoryDragActive and runtime.draggedSlot and containerValue(runtime.draggedSlot) then local mx,my=screenToGame(pointerPosition()); ui.drawItem(containerValue(runtime.draggedSlot),{x=mx-32,y=my-32,w=64,h=64}) end
      if runtime.mapOpen then ui.drawMap() end
      if runtime.editMode then ui.drawEditControls() end
      ui.poseIdle=nil; ui.poseSit=nil; ui.poseLay=nil; ui.poseAction=nil
      ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil; ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
      ui.radioPrevious=nil; ui.radioPause=nil; ui.radioNext=nil; ui.radioMute=nil
      if runtime.poseMenu then
          if mobile then
              drawMenuFrame(410,150,510,390,2,.99); love.graphics.setColor(colors.cream); love.graphics.printf("CHARACTER POSE",435,180,460,"center",0,1.25,1.25)
              ui.poseIdle=button("STAND",455,235,190,70,true); ui.poseSit=button("SIT",675,235,190,70,true)
              ui.poseLay=button("LAY DOWN",455,330,190,70,true); ui.poseAction=button("USE / ACTION",675,330,190,70,true)
              love.graphics.setColor(colors.cream); love.graphics.printf("Movement returns to standing",455,442,410,"center",0,.88,.88)
          else love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",735,198,190,150,8,8); ui.poseIdle=button("STAND",750,212,75,34,true); ui.poseSit=button("SIT",835,212,75,34,true); ui.poseLay=button("LAY",750,256,75,34,true); ui.poseAction=button("USE",835,256,75,34,true); love.graphics.setColor(colors.cream); love.graphics.printf("Movement returns to standing",750,306,160,"center",0,.68,.68) end
      end
      if ui.optionsOpen then
          drawMenuFrame(mobile and 330 or 565,mobile and 90 or 175,mobile and 600 or 370,mobile and 555 or 380,2,.98); love.graphics.setColor(colors.cream); love.graphics.print("AUDIO OPTIONS",mobile and 380 or 595,mobile and 118 or 196,0,mobile and 1.35 or 1.05,mobile and 1.35 or 1.05)
          love.graphics.print("MUSIC  "..math.floor((runtime.saveData.audio.musicVolume or .10)*100).."%",mobile and 400 or 635,mobile and 200 or 252)
          ui.musicDown=button("-",mobile and 680 or 770,mobile and 177 or 242,mobile and 88 or 45,mobile and 64 or 34,true); ui.musicUp=button("+",mobile and 790 or 830,mobile and 177 or 242,mobile and 88 or 45,mobile and 64 or 34,true)
          love.graphics.print("SOUND FX  "..math.floor((runtime.saveData.audio.sfxVolume or .55)*100).."%",mobile and 400 or 635,mobile and 290 or 301)
          ui.sfxDown=button("-",mobile and 680 or 770,mobile and 267 or 291,mobile and 88 or 45,mobile and 64 or 34,true); ui.sfxUp=button("+",mobile and 790 or 830,mobile and 267 or 291,mobile and 88 or 45,mobile and 64 or 34,true)
          love.graphics.print("RAIN  "..math.floor((runtime.saveData.audio.rainVolume or .20)*100).."%",mobile and 400 or 635,mobile and 380 or 350)
          ui.rainDown=button("-",mobile and 680 or 770,mobile and 357 or 340,mobile and 88 or 45,mobile and 64 or 34,true); ui.rainUp=button("+",mobile and 790 or 830,mobile and 357 or 340,mobile and 88 or 45,mobile and 64 or 34,true)
          local stationLabel=AudioCatalog.stationLabel(runtime.saveData.audio.station)
          love.graphics.print("STATION: "..stationLabel,mobile and 400 or 635,mobile and 450 or 399,0,mobile and 1.0 or .85,mobile and 1.0 or .85)
          local audioStatus=getAudioStatus()
          local status=audioStatus.available and (audioStatus.lastError and ("ERROR: "..audioStatus.lastError) or (audioStatus.nowPlaying and ("PLAYING: "..Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying)) or "STARTING MUSIC...")) or "AUDIO UNAVAILABLE"
          love.graphics.setColor(audioStatus.lastError and colors.red or colors.cream); love.graphics.printf(status,mobile and 400 or 610,mobile and 480 or 431,mobile and 470 or 285,"left",0,mobile and .68 or .60,mobile and .68 or .60)
          ui.musicPrevious=button("|<",mobile and 375 or 600,mobile and 540 or 479,mobile and 120 or 68,mobile and 66 or 38,true); ui.musicPause=button(runtime.saveData.audio.musicPaused and "PLAY" or "PAUSE",mobile and 505 or 676,mobile and 540 or 479,mobile and 120 or 72,mobile and 66 or 38,true)
          ui.musicNext=button(">|",mobile and 635 or 756,mobile and 540 or 479,mobile and 120 or 68,mobile and 66 or 38,true); ui.musicMute=button(runtime.saveData.audio.musicMuted and "UNMUTE" or "MUTE",mobile and 765 or 832,mobile and 540 or 479,mobile and 120 or 82,mobile and 66 or 38,true)
      end
      if ui.radioOpen then
          love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,W,H)
          if ui.radioFace then love.graphics.setColor(1,1,1); love.graphics.draw(ui.radioFace,130,95,0,700/ui.radioFace:getWidth(),450/ui.radioFace:getHeight()) else drawMenuFrame(130,95,700,450,2,1) end
          ui.radio8bit={x=248,y=468,w=82,h=54}; ui.radioChill={x=343,y=468,w=82,h=54}; ui.radioVibes={x=438,y=468,w=82,h=54}
          ui.radioRain={x=533,y=468,w=82,h=54}; ui.radioClose={x=628,y=468,w=82,h=54}
          local radioButtons={ui.radio8bit,ui.radioChill,ui.radioVibes,ui.radioRain,ui.radioClose}
          local radioLabels={"8-BIT","CHILL","VIBES","RAIN","CLOSE"}
          for i,r in ipairs(radioButtons) do
              if ui.radioButtonsImage and ui.radioButtonQuads then love.graphics.setColor(1,1,1); local iw,ih=ui.radioButtonsImage:getDimensions(); local q=((i-1)%3)+1; love.graphics.draw(ui.radioButtonsImage,ui.radioButtonQuads[q],r.x,r.y,0,r.w/(iw/3),r.h/ih) else button("",r.x,r.y,r.w,r.h,true) end
              local selected=(i==1 and runtime.saveData.audio.station=="8bit") or (i==2 and runtime.saveData.audio.station=="chill") or (i==3 and runtime.saveData.audio.station=="vibes") or (i==4 and runtime.saveData.audio.rainEnabled)
              love.graphics.setColor(selected and colors.brass or colors.cream); love.graphics.setLineWidth(selected and 4 or 2); love.graphics.rectangle("line",r.x,r.y,r.w,r.h,5,5)
              love.graphics.printf(radioLabels[i],r.x+2,r.y+21,r.w-4,"center",0,.58,.58)
          end
          love.graphics.setLineWidth(1)
          local audioStatus=getAudioStatus()
          local track=audioStatus.nowPlaying and Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying) or "Starting music..."
          love.graphics.setColor(colors.cream); love.graphics.printf("NOW PLAYING:  "..track,220,385,520,"center",0,.72,.72)
          love.graphics.printf(AudioCatalog.stationLabel(runtime.saveData.audio.station).."   •   "..(runtime.saveData.audio.rainEnabled and "RAIN ON" or "RAIN OFF"),260,420,440,"center",0,.82,.82)
          drawMenuFrame(230,552,500,62,4,.94)
          ui.radioPrevious=button("|<  PREV",242,560,110,46,true,.72)
          ui.radioPause=button(runtime.saveData.audio.musicPaused and "PLAY" or "PAUSE",364,560,110,46,true,.72)
          ui.radioNext=button("NEXT  >|",486,560,110,46,true,.72)
          ui.radioMute=button(runtime.saveData.audio.musicMuted and "UNMUTE" or "MUTE",608,560,110,46,true,.72)
          local mx,my=screenToGame(pointerPosition()); local tip
          if Util.pointIn(mx,my,ui.radio8bit) then tip="Scene-based 8-bit score"
          elseif Util.pointIn(mx,my,ui.radioChill) then tip="Chill Radio"
          elseif Util.pointIn(mx,my,ui.radioVibes) then tip="Vibes Radio"
          elseif Util.pointIn(mx,my,ui.radioRain) then tip=runtime.saveData.audio.rainEnabled and "Turn rain ambience off" or "Turn rain ambience on"
          elseif Util.pointIn(mx,my,ui.radioClose) then tip="Close radio" end
          if tip then love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.86); love.graphics.rectangle("fill",mx-85,my-42,170,30,5,5); love.graphics.setColor(colors.cream); love.graphics.printf(tip,mx-80,my-34,160,"center",0,.72,.72) end
      end
      ui.drawDialogue()
      if runtime.trainUpgradeOpen then ui.drawTrainUpgrades() end
      if runtime.tradeOpen then drawTrade() end
      if maintenanceSession.open then
          maintenanceSession.mouseX,maintenanceSession.mouseY=screenToGame(pointerPosition())
          Maintenance.draw(maintenanceSession,runtime.saveData)
      end
      if runtime.firstAid then FirstAid.draw(runtime.firstAid,colors) end
  end

  return {draw=drawGame}
end

return {new=new}
