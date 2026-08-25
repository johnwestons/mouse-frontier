local function install(resolve)
  assert(type(resolve)=="function","gameplay HUD requires a dependency resolver")
  local env=setmetatable({}, {
    __index=function(_,key)
      local value=resolve(key)
      if value~=nil then return value end
      return _G[key]
    end
  })
  setfenv(install,env)

  local function drawGame()
      ui.returnDoor=nil
      if scene=="train" then
          drawLandscape(); drawTracks(); local tx=0
          if travelTransition then
              local t=travelTransition.t; local timing=EngineUpgrades.timings(saveData.engineLevel)
              if t<timing.depart then local p=t/timing.depart; tx=-W*(p*p*p)
              elseif t<timing.arrive then tx=-W
              else local p=math.min(1,(t-timing.arrive)/timing.arrivalDuration); local eased=1-(1-p)^3; tx=W*(1-eased) end
          end
          love.graphics.push(); love.graphics.translate(tx,0)
          if carTransition then
              local p=math.min(1,carTransition.t/carTransition.duration); local eased=p*p*(3-2*p); local direction=carTransition.to>carTransition.from and -1 or 1
              drawTrainView(carTransition.from,direction*W*eased,carTransition.from,player.x,player.y)
              drawTrainView(carTransition.to,direction*W*(eased-1),nil)
          else drawTrainView(saveData.activeCar or 1,0,saveData.activeCar or 1,player.x,player.y) end
          love.graphics.pop()
      elseif scene=="house" then drawHouse() else drawStop() end
      if scene=="train" or scene=="stop" then Clouds.draw(cloudLayer,scene,W,H,sceneryOffset,saveData.location) end
      ui.drawResource("FOOD",saveData.resources.food,20,colors.green,110); ui.drawResource("WATER",saveData.resources.water,140,colors.blue,110)
      ui.drawResource("COAL",saveData.resources.coal,260,colors.red,110); ui.drawResource("OIL",saveData.resources.oil,380,colors.brass,110)
      ui.drawJourneyHUD()
      local mobile=mobileControls and mobileControls:isEnabled()
      ui.travel,ui.leaveTrain,ui.backpack,ui.map,ui.editMode,ui.trainUpgrade,ui.maintenance,ui.pose,ui.options,ui.stopAttack=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
      if mobile then
          if ui.mobileMenuOpen then
              love.graphics.setColor(0,0,0,.64); love.graphics.rectangle("fill",0,0,W,H)
              drawMenuFrame(250,62,690,610,2,.99)
              love.graphics.setColor(colors.cream); love.graphics.printf("JOURNEY MENU",275,84,640,"center",0,1.35,1.35)
              love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",295,122,600,3)
              local canTravel=scene=="train" and saveData.location<50 and saveData.resources.food>0 and saveData.resources.water>0 and saveData.resources.coal>0
              ui.travel=scene=="train" and button(saveData.location>=50 and "JOURNEY COMPLETE" or "TRAVEL TO NEXT STOP",295,142,600,66,canTravel) or nil
              ui.backpack=button("BACKPACK",295,226,285,66,true)
              ui.map=button("TRAIL MAP",610,226,285,66,true)
              ui.trainUpgrade=scene=="train" and button("TRAIN UPGRADES  •  "..saveData.scrap.." SCRAP",295,310,285,66,true) or nil
              ui.editMode=scene=="train" and button("MOVE / SCALE",610,310,285,66,true) or nil
              ui.maintenance=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and not travelTransition and button("MAINTENANCE  •  "..math.floor(Maintenance.condition(saveData)).."%",295,394,285,66,true) or nil
              ui.pose=button("CHARACTER POSES",610,394,285,66,true)
              ui.options=button("AUDIO OPTIONS",295,478,285,66,true)
              ui.leaveTrain=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and button("LEAVE TRAIN",610,478,285,66,true) or nil
              ui.stopAttack=scene=="stop" and button("ATTACK",610,478,285,66,true) or nil
              love.graphics.setColor(colors.cream); love.graphics.printf("Tap BACK or CLOSE to return to the world",295,575,600,"center",0,.86,.86)
          end
      else
          ui.travel=scene=="train" and button(saveData.location>=50 and "JOURNEY COMPLETE" or "TRAVEL TO NEXT STOP",510,20,220,36,saveData.location<50 and saveData.resources.food>0 and saveData.resources.water>0 and saveData.resources.coal>0) or nil
          -- Keep the departure control with the other scene controls, directly
          -- beneath Options, so it remains discoverable without covering the train.
          ui.leaveTrain=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and button("LEAVE TRAIN",790,194,135,32,true) or nil
          ui.backpack=button(inventoryOpen and "CLOSE" or "PACK",830,20,95,36,true)
          ui.map=button(mapOpen and "CLOSE MAP" or "MAP",735,20,87,36,true)
          ui.editMode=scene=="train" and button(editMode and "EDITING" or "MOVE / SCALE",745,70,180,36,true) or nil
          ui.trainUpgrade=scene=="train" and button("UPGRADE  "..saveData.scrap.." SCRAP",510,70,220,36,true) or nil
          ui.maintenance=scene=="train" and saveData.stopped and (saveData.activeCar or 1)==1 and not travelTransition and button("MAINTENANCE  "..math.floor(Maintenance.condition(saveData)).."%",510,112,220,32,true) or nil
          ui.pose=button(poseMenu and "CLOSE" or "POSES",745,112,85,32,true)
          ui.options=button(ui.optionsOpen and "CLOSE" or "OPTIONS",840,112,85,32,true)
          ui.stopAttack=scene=="stop" and button("ATTACK",790,650,135,38,true) or nil
      end
      local pendingMail=0; for _,mail in ipairs(saveData.mailQuests or {}) do if not mail.complete then pendingMail=pendingMail+1 end end
      if pendingMail>0 and ui.propImages["family-letter"] then local mail=ui.propImages["family-letter"]; local ms=28/math.max(mail:getWidth(),mail:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(mail,470,127,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2); love.graphics.setColor(colors.cream); love.graphics.print("x"..pendingMail,487,117,0,.9,.9) end
      if #(saveData.passengers or {})>0 then love.graphics.setColor(colors.cream); love.graphics.print("Passengers: "..#saveData.passengers,560,151,0,.82,.82) end
      ui.exitTrain = nil
      local tipColor={colors.panel[1],colors.panel[2],colors.panel[3],.50}
      local nearbyFurniture=nearbyItem and isFurnitureItem(saveData.droppedItems[nearbyItem] and saveData.droppedItems[nearbyItem].name)
      local contextText,contextScale
      if not inventoryOpen and not editMode and not carTransition and not ui.mobileMenuOpen then
          if mobile then
              if ui.nearRadio then contextText,contextScale="TAP RADIO",.78
              elseif nearPassenger or nearNPC then contextText,contextScale="TAP TALK   •   TAP GIVE",.72
              elseif nearCarNext then contextText,contextScale="TAP DOOR FOR NEXT CAR",.72
              elseif nearCarPrev then contextText,contextScale="TAP DOOR FOR PREVIOUS CAR",.66
              elseif nearMailbox then contextText,contextScale="TAP OPEN FOR REWARD MAILBOX",.66
              elseif nearChest then contextText,contextScale="TAP OPEN   •   HOLD PICK UP",.66
              elseif nearbyFurniture then contextText,contextScale="HOLD PICK UP FOR FURNITURE",.68
              elseif nearHouse then contextText,contextScale="TAP ENTER",.78
              elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="TAP EXIT",.78
              elseif nearReturnTrain then contextText,contextScale="TAP BOARD",.78
              elseif nearFire then contextText,contextScale="TAP COAL",.78 end
          elseif ui.nearRadio then contextText,contextScale="P  OPEN RADIO",.72
          elseif nearPassenger then contextText,contextScale="Q  TALK   •   G  GIVE",.72
          elseif nearCarNext then contextText,contextScale="Q  ENTER NEXT CAR",.72
          elseif nearCarPrev then contextText,contextScale="Q  RETURN TO PREVIOUS CAR",.66
          elseif nearNPC then contextText,contextScale="Q  TALK   •   G  GIVE",.72
          elseif nearMailbox then contextText,contextScale="RIGHT CLICK OPEN REWARD MAILBOX",.66
          elseif nearChest then contextText,contextScale="RIGHT CLICK OPEN   •   HOLD E PICK UP",.66
          elseif nearbyFurniture then contextText,contextScale="HOLD E  PICK UP FURNITURE",.72
          elseif nearHouse then contextText,contextScale="Q  ENTER HOME",.78
          elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="Q  LEAVE HOME",.78
          elseif nearReturnTrain then contextText,contextScale="Q  BOARD TRAIN",.78
          elseif nearFire then contextText,contextScale="E  ADD COAL",.78 end
      end
      if contextText then
          love.graphics.setColor(tipColor); love.graphics.rectangle("fill",325,300,310,40,6,6); love.graphics.setColor(colors.cream)
          love.graphics.printf(contextText,325,312,310,"center",0,contextScale,contextScale)
          if holdPickupIndex then love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",365,335,230*math.min(1,holdPickupTime/HOLD_PICKUP_SECONDS),5,2,2) end
      end
      if scene=="train" and #(saveData.trainCars or {})>1 then love.graphics.setColor(colors.cream); love.graphics.printf("CAR "..(saveData.activeCar or 1).." / "..#saveData.trainCars.."  •  "..Util.titleFromFile(saveData.trainCars[saveData.activeCar or 1]),510,188,410,"center",0,.72,.72) end
      ui.pickup = nearbyItem and not nearbyFurniture and not editMode and not ui.mobileMenuOpen and button("PICK UP  [E]",390,650,180,38,true) or nil
      if inventoryOpen then if chestOpen then ui.drawChestInventory() end; ui.drawInventory() end
      if inventoryOpen and inventoryDragActive and draggedSlot and containerValue(draggedSlot) then local mx,my=screenToGame(pointerPosition()); ui.drawItem(containerValue(draggedSlot),{x=mx-32,y=my-32,w=64,h=64}) end
      if mapOpen then ui.drawMap() end
      if editMode then ui.drawEditControls() end
      ui.poseIdle=nil; ui.poseSit=nil; ui.poseLay=nil; ui.poseAction=nil
      ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil; ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
      if poseMenu then
          if mobile then
              drawMenuFrame(410,150,510,390,2,.99); love.graphics.setColor(colors.cream); love.graphics.printf("CHARACTER POSE",435,180,460,"center",0,1.25,1.25)
              ui.poseIdle=button("STAND",455,235,190,70,true); ui.poseSit=button("SIT",675,235,190,70,true)
              ui.poseLay=button("LAY DOWN",455,330,190,70,true); ui.poseAction=button("USE / ACTION",675,330,190,70,true)
              love.graphics.setColor(colors.cream); love.graphics.printf("Movement returns to standing",455,442,410,"center",0,.88,.88)
          else love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",735,198,190,150,8,8); ui.poseIdle=button("STAND",750,212,75,34,true); ui.poseSit=button("SIT",835,212,75,34,true); ui.poseLay=button("LAY",750,256,75,34,true); ui.poseAction=button("USE",835,256,75,34,true); love.graphics.setColor(colors.cream); love.graphics.printf("Movement returns to standing",750,306,160,"center",0,.68,.68) end
      end
      if ui.optionsOpen then
          drawMenuFrame(mobile and 330 or 565,mobile and 90 or 175,mobile and 600 or 370,mobile and 555 or 380,2,.98); love.graphics.setColor(colors.cream); love.graphics.print("AUDIO OPTIONS",mobile and 380 or 595,mobile and 118 or 196,0,mobile and 1.35 or 1.05,mobile and 1.35 or 1.05)
          love.graphics.print("MUSIC  "..math.floor((saveData.audio.musicVolume or .10)*100).."%",mobile and 400 or 635,mobile and 200 or 252)
          ui.musicDown=button("-",mobile and 680 or 770,mobile and 177 or 242,mobile and 88 or 45,mobile and 64 or 34,true); ui.musicUp=button("+",mobile and 790 or 830,mobile and 177 or 242,mobile and 88 or 45,mobile and 64 or 34,true)
          love.graphics.print("SOUND FX  "..math.floor((saveData.audio.sfxVolume or .55)*100).."%",mobile and 400 or 635,mobile and 290 or 301)
          ui.sfxDown=button("-",mobile and 680 or 770,mobile and 267 or 291,mobile and 88 or 45,mobile and 64 or 34,true); ui.sfxUp=button("+",mobile and 790 or 830,mobile and 267 or 291,mobile and 88 or 45,mobile and 64 or 34,true)
          love.graphics.print("RAIN  "..math.floor((saveData.audio.rainVolume or .20)*100).."%",mobile and 400 or 635,mobile and 380 or 350)
          ui.rainDown=button("-",mobile and 680 or 770,mobile and 357 or 340,mobile and 88 or 45,mobile and 64 or 34,true); ui.rainUp=button("+",mobile and 790 or 830,mobile and 357 or 340,mobile and 88 or 45,mobile and 64 or 34,true)
          local stationLabel=saveData.audio.station=="chill" and "CHILL RADIO" or (saveData.audio.station=="vibes" and "VIBES RADIO" or "8-BIT SCORE")
          love.graphics.print("STATION: "..stationLabel,mobile and 400 or 635,mobile and 450 or 399,0,mobile and 1.0 or .85,mobile and 1.0 or .85)
          local status=ui.audio and (ui.audio.lastError and ("ERROR: "..ui.audio.lastError) or (ui.audio.nowPlaying and ("PLAYING: "..Util.titleFromFile(ui.audio.nowPlaying:match("[^/]+$") or ui.audio.nowPlaying)) or "STARTING MUSIC...")) or "AUDIO UNAVAILABLE"
          love.graphics.setColor(ui.audio and ui.audio.lastError and colors.red or colors.cream); love.graphics.printf(status,mobile and 400 or 610,mobile and 480 or 431,mobile and 470 or 285,"left",0,mobile and .68 or .60,mobile and .68 or .60)
          ui.musicPrevious=button("|<",mobile and 375 or 600,mobile and 540 or 479,mobile and 120 or 68,mobile and 66 or 38,true); ui.musicPause=button(saveData.audio.musicPaused and "PLAY" or "PAUSE",mobile and 505 or 676,mobile and 540 or 479,mobile and 120 or 72,mobile and 66 or 38,true)
          ui.musicNext=button(">|",mobile and 635 or 756,mobile and 540 or 479,mobile and 120 or 68,mobile and 66 or 38,true); ui.musicMute=button(saveData.audio.musicMuted and "UNMUTE" or "MUTE",mobile and 765 or 832,mobile and 540 or 479,mobile and 120 or 82,mobile and 66 or 38,true)
      end
      if ui.radioOpen then
          love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,W,H)
          if ui.radioFace then love.graphics.setColor(1,1,1); love.graphics.draw(ui.radioFace,130,95,0,700/ui.radioFace:getWidth(),450/ui.radioFace:getHeight()) else drawMenuFrame(130,95,700,450,2,1) end
          -- Keep station selectors and ambience controls on distinct rows. This
          -- prevents the rain hitbox from being interpreted as the chill button
          -- when the radio is scaled or shown fullscreen.
          ui.radio8bit={x=248,y=468,w=82,h=54}; ui.radioChill={x=343,y=468,w=82,h=54}; ui.radioVibes={x=438,y=468,w=82,h=54}
          ui.radioRain={x=533,y=468,w=82,h=54}; ui.radioClose={x=628,y=468,w=82,h=54}
          for i,r in ipairs({ui.radio8bit,ui.radioChill,ui.radioVibes,ui.radioRain,ui.radioClose}) do
              if ui.radioButtonsImage and ui.radioButtonQuads then love.graphics.setColor(1,1,1); local iw,ih=ui.radioButtonsImage:getDimensions(); local q=((i-1)%3)+1; love.graphics.draw(ui.radioButtonsImage,ui.radioButtonQuads[q],r.x,r.y,0,r.w/(iw/3),r.h/ih) else button("",r.x,r.y,r.w,r.h,true) end
          end
          local stationName=saveData.audio.station=="chill" and "CHILL RADIO" or (saveData.audio.station=="vibes" and "VIBES RADIO" or "8-BIT SCORE")
          love.graphics.setColor(colors.cream); love.graphics.printf(stationName,300,405,360,"center",0,1.1,1.1)
          love.graphics.printf(saveData.audio.rainEnabled and "RAIN: ON" or "RAIN: OFF",300,432,360,"center",0,.78,.78)
          local mx,my=screenToGame(pointerPosition()); local tip
          if Util.pointIn(mx,my,ui.radio8bit) then tip="Scene-based 8-bit score"
          elseif Util.pointIn(mx,my,ui.radioChill) then tip="Chill Radio"
          elseif Util.pointIn(mx,my,ui.radioVibes) then tip="Vibes Radio"
          elseif Util.pointIn(mx,my,ui.radioRain) then tip=saveData.audio.rainEnabled and "Turn rain ambience off" or "Turn rain ambience on"
          elseif Util.pointIn(mx,my,ui.radioClose) then tip="Close radio" end
          if tip then love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.86); love.graphics.rectangle("fill",mx-85,my-42,170,30,5,5); love.graphics.setColor(colors.cream); love.graphics.printf(tip,mx-80,my-34,160,"center",0,.72,.72) end
      end
      ui.drawDialogue()
      if trainUpgradeOpen then ui.drawTrainUpgrades() end
      if tradeOpen then drawTrade() end
      if maintenanceSession.open then
          maintenanceSession.mouseX,maintenanceSession.mouseY=screenToGame(pointerPosition())
          Maintenance.draw(maintenanceSession,saveData)
      end
  end

  return {draw=drawGame}
end

return {install=install}
