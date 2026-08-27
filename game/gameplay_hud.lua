local AudioCatalog = require("game.audio_catalog")
local Accessibility = require("game.accessibility")

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
  local ActivityMinigames=required(context,"activityMinigames","table")
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
              ui.options=button("SETTINGS",295,478,285,66,true)
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
      if Accessibility.enabled(runtime.saveData,"controlHints") and not runtime.inventoryOpen and not runtime.editMode and not runtime.carTransition and not ui.mobileMenuOpen then
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
          local highContrast=Accessibility.enabled(runtime.saveData,"highContrast")
          love.graphics.setColor(highContrast and {0,0,0,.96} or tipColor); love.graphics.rectangle("fill",325,300,310,40,6,6)
          if highContrast then love.graphics.setColor(1,.84,.28,1); love.graphics.setLineWidth(3); love.graphics.rectangle("line",325,300,310,40,6,6); love.graphics.setLineWidth(1) end
          love.graphics.setColor(colors.cream)
          local shownScale=math.min(1.05,contextScale*Accessibility.textScale(runtime.saveData))
          love.graphics.printf(contextText,325,320-8*shownScale,310,"center",0,shownScale,shownScale)
          if runtime.holdPickupIndex then love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",365,335,230*math.min(1,runtime.holdPickupTime/HOLD_PICKUP_SECONDS),5,2,2) end
      end
      if runtime.scene=="train" and #(runtime.saveData.trainCars or {})>1 and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue and not runtime.editMode and not ui.mobileMenuOpen then
          local active=runtime.saveData.activeCar or 1
          ui.trainCarTabs=Train.consistLayout(W,#runtime.saveData.trainCars,{mobile=mobile})
          for index,tab in ipairs(ui.trainCarTabs) do
              local selected=index==active
              love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",tab.x,tab.y,tab.w,tab.h,7,7)
              love.graphics.setColor(selected and colors.brass or colors.cream); love.graphics.setLineWidth(selected and 3 or 1)
              love.graphics.rectangle("line",tab.x,tab.y,tab.w,tab.h,7,7)
              local numberScale=mobile and .78 or .55
              love.graphics.printf(tostring(index),tab.x,tab.y+(mobile and 18 or 7),tab.w,"center",0,numberScale,numberScale)
          end
          love.graphics.setLineWidth(1); love.graphics.setColor(colors.cream)
          love.graphics.printf("CAR "..active.." / "..#runtime.saveData.trainCars.."  •  "..Util.titleFromFile(runtime.saveData.trainCars[active]),430,mobile and 210 or 187,mobile and W-455 or 300,"center",0,.58,.58)
      end
      ui.pickup = runtime.nearbyItem and not nearbyFurniture and not runtime.editMode and not ui.mobileMenuOpen and button("PICK UP  [E]",390,650,180,38,true) or nil
      if runtime.inventoryOpen then if runtime.chestOpen then ui.drawChestInventory() end; ui.drawInventory() end
      if runtime.inventoryOpen and runtime.inventoryDragActive and runtime.draggedSlot and containerValue(runtime.draggedSlot) then local mx,my=screenToGame(pointerPosition()); ui.drawItem(containerValue(runtime.draggedSlot),{x=mx-32,y=my-32,w=64,h=64}) end
      if runtime.mapOpen then ui.drawMap() end
      if runtime.editMode then ui.drawEditControls() end
      ui.poseIdle=nil; ui.poseSit=nil; ui.poseLay=nil; ui.poseAction=nil
      ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil; ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
      ui.optionsAudioTab=nil; ui.optionsAccessTab=nil; ui.accessTextSize=nil; ui.accessHighContrast=nil; ui.accessReducedMotion=nil
      ui.accessControlHints=nil; ui.accessTouchFeedback=nil; ui.accessLargeTouchTargets=nil
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
          runtime.optionsPage=runtime.optionsPage or "audio"
          local panelX,panelY,panelW,panelH=mobile and 250 or 485,mobile and 55 or 125,mobile and 680 or 460,mobile and 615 or 525
          drawMenuFrame(panelX,panelY,panelW,panelH,2,.99); love.graphics.setColor(colors.cream)
          love.graphics.printf("SETTINGS",panelX+20,panelY+24,panelW-40,"center",0,mobile and 1.28 or 1.08,mobile and 1.28 or 1.08)
          ui.optionsAudioTab=button("AUDIO",panelX+35,panelY+68,(panelW-85)/2,mobile and 58 or 42,runtime.optionsPage=="audio",.78)
          ui.optionsAccessTab=button("ACCESSIBILITY",panelX+50+(panelW-85)/2,panelY+68,(panelW-85)/2,mobile and 58 or 42,runtime.optionsPage=="accessibility",.72)
          if runtime.optionsPage=="audio" then
              local labelX=panelX+65; local downX=panelX+panelW-250; local upX=panelX+panelW-135
              local row1,row2,row3=panelY+155,panelY+225,panelY+295
              love.graphics.setColor(colors.cream); love.graphics.print("MUSIC  "..math.floor((runtime.saveData.audio.musicVolume or .10)*100).."%",labelX,row1+12)
              ui.musicDown=button("-",downX,row1,mobile and 95 or 58,mobile and 58 or 40,true); ui.musicUp=button("+",upX,row1,mobile and 95 or 58,mobile and 58 or 40,true)
              love.graphics.print("SOUND FX  "..math.floor((runtime.saveData.audio.sfxVolume or .55)*100).."%",labelX,row2+12)
              ui.sfxDown=button("-",downX,row2,mobile and 95 or 58,mobile and 58 or 40,true); ui.sfxUp=button("+",upX,row2,mobile and 95 or 58,mobile and 58 or 40,true)
              love.graphics.print("RAIN  "..math.floor((runtime.saveData.audio.rainVolume or .20)*100).."%",labelX,row3+12)
              ui.rainDown=button("-",downX,row3,mobile and 95 or 58,mobile and 58 or 40,true); ui.rainUp=button("+",upX,row3,mobile and 95 or 58,mobile and 58 or 40,true)
              local stationLabel=AudioCatalog.stationLabel(runtime.saveData.audio.station)
              love.graphics.print("STATION: "..stationLabel,labelX,panelY+370,0,mobile and .92 or .78,mobile and .92 or .78)
              local audioStatus=getAudioStatus()
              local status=audioStatus.available and (audioStatus.lastError and ("ERROR: "..audioStatus.lastError) or (audioStatus.nowPlaying and ("PLAYING: "..Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying)) or "STARTING MUSIC...")) or "AUDIO UNAVAILABLE"
              love.graphics.setColor(audioStatus.lastError and colors.red or colors.cream); love.graphics.printf(status,labelX,panelY+400,panelW-130,"left",0,mobile and .68 or .58,mobile and .68 or .58)
              local controlsY=panelY+465; local bw=(panelW-90)/4
              ui.musicPrevious=button("|<",panelX+30,controlsY,bw,mobile and 62 or 42,true); ui.musicPause=button(runtime.saveData.audio.musicPaused and "PLAY" or "PAUSE",panelX+40+bw,controlsY,bw,mobile and 62 or 42,true,.72)
              ui.musicNext=button(">|",panelX+50+bw*2,controlsY,bw,mobile and 62 or 42,true); ui.musicMute=button(runtime.saveData.audio.musicMuted and "UNMUTE" or "MUTE",panelX+60+bw*3,controlsY,bw,mobile and 62 or 42,true,.72)
          else
              local settings=Accessibility.ensure(runtime.saveData)
              local labels={
                  {"TEXT SIZE",Accessibility.textLabel(runtime.saveData),"accessTextSize"},
                  {"HIGH CONTRAST",settings.highContrast and "ON" or "OFF","accessHighContrast"},
                  {"REDUCED MOTION",settings.reducedMotion and "ON" or "OFF","accessReducedMotion"},
                  {"CONTROL HINTS",settings.controlHints and "ON" or "OFF","accessControlHints"},
                  {"TOUCH FEEDBACK",settings.touchFeedback and "ON" or "OFF","accessTouchFeedback"},
                  {"LARGE TOUCH TARGETS",settings.largeTouchTargets and "ON" or "OFF","accessLargeTouchTargets"},
              }
              local startY=panelY+150; local rowGap=mobile and 64 or 55
              for index,entry in ipairs(labels) do
                  local y=startY+(index-1)*rowGap; love.graphics.setColor(colors.cream); love.graphics.print((mobile and "" or (index.."  "))..entry[1],panelX+45,y+(mobile and 18 or 12),0,mobile and .84 or .72,mobile and .84 or .72)
                  ui[entry[3]]=button(entry[2],panelX+panelW-(mobile and 245 or 180),y,mobile and 195 or 140,mobile and 58 or 42,true,.72)
              end
              local note=mobile and "Settings save with this journey. Camera zoom remains available in every scene."
                  or "Keys 1–6 change settings  •  TAB changes page  •  Settings save with this journey."
              love.graphics.setColor(colors.cream); love.graphics.printf(note,panelX+45,panelY+panelH-42,panelW-90,"center",0,.60,.60)
          end
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
      if runtime.activityMinigame then ActivityMinigames.draw(runtime.activityMinigame,colors,runtime.animationClock) end
  end

  return {draw=drawGame}
end

return {new=new}
