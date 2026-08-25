local function install(resolve,assign)
  assert(type(resolve)=="function","gameplay update requires a dependency resolver")
  assert(type(assign)=="function","gameplay update requires a dependency writer")
  local env=setmetatable({}, {
    __index=function(_,key)
      local value=resolve(key)
      if value~=nil then return value end
      return _G[key]
    end,
    __newindex=function(_,key,value)
      if not assign(key,value) then error("gameplay update cannot assign "..tostring(key),2) end
    end
  })
  setfenv(install,env)

  local function movementAxis(a, b) return (love.keyboard.isDown(b) and 1 or 0) - (love.keyboard.isDown(a) and 1 or 0) end

  local function updateInteraction()
      local mx,my
      if mobileControls and mobileControls:isEnabled() then mx,my=player.x,player.y
      else mx,my=screenToGame(love.mouse.getPosition()) end
      local selected=Systems.interactions.select({data=saveData,scene=scene,player=player,npc=npcActor,car=car,mouseX=mx,mouseY=my,
          itemIsHere=itemIsHere,storageCapacities=Catalog.storageCapacities,nearTrain=Settlements.nearTrain,trainPoint=Settlements.trainPoint,
          nearDoor=Settlements.nearDoor,doorPoint=Settlements.doorPoint,hasSettlements=scenery.settlements~=nil,layout=ensureStopLayout,
          interiorPoint=InteriorDoors.point,nearInteriorDoor=InteriorDoors.near,interiorFiles=scenery.interiorFiles,choose=Interactions.select})
      local flags=Systems.interactions.flags(selected)
      ui.interaction=flags.interaction; nearbyItem=flags.nearbyItem; nearChest=flags.nearChest; nearMailbox=flags.nearMailbox
      nearHouse=flags.nearHouse or false; nearNPC=flags.nearNPC or false; nearPassenger=flags.nearPassenger
      nearReturnTrain=flags.nearReturnTrain or false; nearFire=flags.nearFire or false; nearCarPrev=flags.nearCarPrev or false; nearCarNext=flags.nearCarNext or false; ui.nearRadio=flags.nearRadio or false
  end

  local function update(dt)
      Save.update(dt)
      animationClock = animationClock + dt
      Clouds.update(cloudLayer, dt)
      if screens:is("intro") then screens:update(dt); return end
      if ui.assetStreamer then ui.assetStreamer:update(state,scene,saveData,battle,npcActor) end
      -- Full settlement scenes keep only the dedicated dynamic chicken flocks;
      -- the retired random decoration wildlife remains disconnected.
      walkingSoundTimer=math.max(0,walkingSoundTimer-dt)
      ui.updateMusic()
      local trainRate=2.2
      if travelTransition then
          local t=travelTransition.t or 0; local timing=EngineUpgrades.timings(saveData.engineLevel)
          if t<timing.depart then local p=t/timing.depart; trainRate=2.2+6.3*p*p
          elseif t<timing.arrive then trainRate=8.5
          else local p=math.max(0,1-(t-timing.arrive)/timing.arrivalDuration); trainRate=2.2+6.3*p*p end
      end
      trainAnimationClock=trainAnimationClock+dt*trainRate
      actionTimer=math.max(0,actionTimer-dt); if actionTimer<=0 then actionHeldItem=nil; actionKind=nil end
      if screens:update(dt) then return end
      updateStopSludges(dt)
      ui.updateChickens(dt)
      ui.updateMice(dt)
      if travelTransition then
          travelTransition.t=travelTransition.t+dt
          local t=travelTransition.t; local speedFactor; local timing=EngineUpgrades.timings(saveData.engineLevel)
          if ui.departSource then
              -- Let the departure cue follow the train out, then release the
              -- channel before the arrival cue begins.
              local fade=math.max(0,math.min(1,(timing.depart-t)/(.55/EngineUpgrades.profile(saveData.engineLevel).speed)))
              ui.departSource:setVolume((saveData.audio.sfxVolume or .55)*fade)
              if t>=timing.change then ui.departSource:stop(); ui.departSource=nil end
          end
          if t<timing.depart then speedFactor=(t/timing.depart)^2 elseif t<timing.arrive then speedFactor=1 else speedFactor=math.max(0,1-(t-timing.arrive)/timing.arrivalDuration)^2 end
          local sceneryDistance=(25+125*speedFactor)*EngineUpgrades.profile(saveData.engineLevel).speed*dt
          sceneryOffset=(sceneryOffset+sceneryDistance)%W
          landscapeOffset=landscapeOffset+sceneryDistance
          if not travelTransition.changed and travelTransition.t>=timing.change then
              travelTransition.changed=true; saveData.location=saveData.location+1; saveData.stopped=true; saveData.visitedStops[saveData.location]=true
              Maintenance.onTravel(saveData)
              -- The scene is still the train interior at this point. Keep the
              -- player in the active car; trainPoint coordinates belong to the
              -- destination stop map and would place the character outside the
              -- train until the next movement clamp corrected it.
              player.x,player.y=clampToTrainFloor(player.x,player.y)
              for _,id in ipairs(saveData.trainCars or {}) do if id=="greenhouse" then saveData.resources.food=math.min(30,saveData.resources.food+1) elseif id=="medical" then saveData.health=math.min(saveData.maxHealth,saveData.health+3) end end
              ensureStopLayout(); Systems.journeyRules.passengerContributions(); Systems.journeyRules.processPassengerArrivals(); writeSave()
          end
          if not travelTransition.arriveSoundPlayed and travelTransition.t>=timing.arrive then travelTransition.arriveSoundPlayed=true; ui.playSfx("trainArrive") end
          if travelTransition.t>=timing.total then travelTransition=nil; sceneryOffset=0; landscapeOffset=0; if saveData.location>=50 then screens:transition("ending"); state=session.screen elseif saveData.arrivalNotice then dialogue={speaker="Passenger",text=saveData.arrivalNotice,timer=4}; saveData.arrivalNotice=nil; writeSave() end end
          return
      end
      if holdPickupIndex then
          local item=saveData and saveData.droppedItems[holdPickupIndex]
          local useHeld=love.keyboard.isDown("e") or (mobileControls and mobileControls:isHeld("e"))
          if not useHeld or not item or not itemIsHere(item) or math.sqrt((player.x-item.x)^2+(player.y-item.y)^2)>=75 then
              holdPickupIndex,holdPickupTime=nil,0
          else
              holdPickupTime=holdPickupTime+dt
              if holdPickupTime>=HOLD_PICKUP_SECONDS then
                  nearbyItem=holdPickupIndex; Systems.inventoryActions.pickUpNearby(); holdPickupIndex,holdPickupTime=nil,0
              end
          end
      end
      if scene ~= "train" and not npcActor then setupNPC() end
      if dialogue then dialogue.timer = dialogue.timer - dt; if dialogue.timer <= 0 then dialogue = nil end end
      if scene=="train" then
          local sceneryDistance=18*dt
          sceneryOffset=(sceneryOffset+sceneryDistance)%W
          landscapeOffset=landscapeOffset+sceneryDistance
      end
      if carTransition then
          carTransition.t=math.min(carTransition.duration,carTransition.t+dt)
          player.moving=false
          if carTransition.t>=carTransition.duration then
              saveData.activeCar=carTransition.to
              player.x,player.y=carTransition.targetX,carTransition.targetY
              carTransition=nil; writeSave()
          end
          return
      end
      Maintenance.update(maintenanceSession,dt)
      if maintenanceSession.open or inventoryOpen or mapOpen or dialogue or editMode or ui.radioOpen then return end
      local dx = movementAxis("a", "d") + movementAxis("left", "right")
      local dy = movementAxis("w", "s") + movementAxis("up", "down")
      if mobileControls then local mobileX,mobileY=mobileControls:movement(); dx,dy=dx+mobileX,dy+mobileY end
      player.moving = dx ~= 0 or dy ~= 0
      if player.moving then
          playerPose="idle"; poseMenu=false
          local length = math.sqrt(dx*dx + dy*dy); dx, dy = dx/length, dy/length
          if dx ~= 0 then player.facing = dx > 0 and 1 or -1 end
          local sprint=(love.keyboard.isDown("lshift","rshift") or (mobileControls and mobileControls:isSprinting())) and 1.7 or 1
          local oldX,oldY=player.x,player.y
          player.x, player.y = player.x + dx*player.speed*sprint*dt, player.y + dy*player.speed*sprint*dt
          if walkingSoundTimer<=0 then
              ui.playSfx("walkingSteps")
              walkingSoundTimer=math.max(.18, .34/sprint)
          end
          if scene=="train" then
              player.x,player.y=clampToTrainFloor(player.x,player.y)
          elseif scene=="stop" then
              player.x,player.y=Settlements.move(saveData.location,oldX,oldY,player.x,player.y)
          else
              player.x,player.y=Util.clampHouseFloor(player.x,player.y)
          end
      end
      if npcActor then
          Family.update(npcActor,dt,function(oldX,oldY,newX,newY)
              if scene=="stop" then return Settlements.move(saveData.location,oldX,oldY,newX,newY) end
              if scene=="house" then return Util.clampHouseFloor(newX,newY) end
              return newX,newY
          end)
          npcActor.wait = (npcActor.wait or 1) - dt
          if npcActor.wait <= 0 then
              local angle = love.math.random() * math.pi * 2
              local distance = love.math.random(18, 58)
              npcActor.targetX = npcActor.homeX + math.cos(angle) * distance
              npcActor.targetY = npcActor.homeY + math.sin(angle) * distance * 0.55
              npcActor.wait = love.math.random(3, 7)
          end
          if npcActor.targetX then
              if scene=="house" then npcActor.targetX,npcActor.targetY=Util.clampHouseFloor(npcActor.targetX,npcActor.targetY) elseif scene=="stop" then npcActor.targetX,npcActor.targetY=Settlements.clamp(npcActor.targetX,npcActor.targetY,saveData.location) end
              local nx,ny=npcActor.targetX-npcActor.x,npcActor.targetY-npcActor.y; local len=math.sqrt(nx*nx+ny*ny)
              if len < 2 then npcActor.targetX=nil else
                  if math.abs(nx)>0.1 then npcActor.facing=nx>0 and 1 or -1 end
                  local step=math.min(len,32*dt); npcActor.x=npcActor.x+nx/len*step; npcActor.y=npcActor.y+ny/len*step
              end
          end
      end
      if scene=="train" then for _,passenger in ipairs(saveData.passengers or {}) do
          passenger.carIndex=math.max(1,math.min(#(saveData.trainCars or {1}),passenger.carIndex or 1)); passenger.wait=(passenger.wait or 1)-dt
          if passenger.wait<=0 then
              local preferred=Passengers.preferredCar(passenger,saveData.trainCars)
              if preferred~=passenger.carIndex and love.math.random()<.55 then passenger.targetCar=preferred; passenger.targetX=preferred>passenger.carIndex and car.x+car.w-35 or car.x+35; passenger.targetY=car.y+205
              else local left,right,top,bottom=trainFloorBounds(); passenger.targetX,passenger.targetY=clampToTrainFloor(love.math.random(left+20,right-20),love.math.random(top,bottom)) end
              passenger.wait=love.math.random(4,8); passenger.pose="idle"
          end
          if passenger.targetX then
              local dx,dy=passenger.targetX-passenger.x,passenger.targetY-passenger.y; local len=math.sqrt(dx*dx+dy*dy)
              if len<2 then
                  passenger.targetX=nil
                  if passenger.targetCar then local left,right,top,bottom=trainFloorBounds(); passenger.carIndex=passenger.targetCar; passenger.targetCar=nil; passenger.x=passenger.carIndex>1 and left or right; passenger.y=(top+bottom)/2 end
                  local hasSleeper=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="sleeper" then hasSleeper=true end end; passenger.pose=(hasSleeper and love.math.random()<.25) and "lay" or (love.math.random()<.55 and "sit" or "idle")
              else local step=math.min(len,38*dt); passenger.x=passenger.x+dx/len*step; passenger.y=passenger.y+dy/len*step; passenger.facing=dx>0 and 1 or -1 end
          end
      end end
      updateInteraction()
  end

  return {update=update,updateInteraction=updateInteraction}
end

return {install=install}
