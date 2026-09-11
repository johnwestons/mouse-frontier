local Accessibility=require("game.accessibility")
local CharacterMotion=require("game.character_motion")
local WorldPause=require("game.world_pause")

local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"gameplay update requires "..name)
  if expectedType then assert(type(value)==expectedType,"gameplay update "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","gameplay update requires an explicit context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local holdPickupSeconds=required(context,"holdPickupSeconds","number")
  local ui=required(context,"ui","table")
  local car=required(context,"car","table")
  local landscape=required(context,"landscape","table")
  local scenery=required(context,"scenery","table")
  local cloudLayer=required(context,"cloudLayer","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local mobileMovement=required(context,"mobileMovement","function")
  local mobileHeld=required(context,"mobileHeld","function")
  local mobileSprinting=required(context,"mobileSprinting","function")
  local interactionRouter=required(context,"interactionRouter","table")
  local inventoryActions=required(context,"inventoryActions","table")
  local journeyRules=required(context,"journeyRules","table")
  local Catalog=required(context,"catalog","table")
  local Settlements=required(context,"settlements","table")
  local InteriorDoors=required(context,"interiorDoors","table")
  local Interactions=required(context,"interactions","table")
  local updatePersistence=required(context,"updatePersistence","function")
  local Clouds=required(context,"clouds","table")
  local screens=required(context,"screens","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Maintenance=required(context,"maintenance","table")
  local Family=required(context,"family","table")
  local Util=required(context,"util","table")
  local Passengers=required(context,"passengers","table")
  local screenToGame=required(context,"screenToGame","function")
  local updateAudio=required(context,"updateAudio","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local updateWorldScene=required(context,"updateWorldScene","function")
  local currentShootingRange=required(context,"currentShootingRange","function")
  local handleShootingRange=required(context,"handleShootingRange","function")
  local clampToTrainFloor=required(context,"clampToTrainFloor","function")
  local itemIsHere=required(context,"itemIsHere","function")
  local setupNPC=required(context,"setupNPC","function")
  local moveExpedition=required(context,"moveExpedition","function")
  local currentExpeditionInteraction=required(context,"currentExpeditionInteraction","function")
  local moveCaravan=required(context,"moveCaravan","function")
  local currentCaravanInteraction=required(context,"currentCaravanInteraction","function")
  local trainFloorBounds=required(context,"trainFloorBounds","function")
  local updateCarTransition=required(context,"updateCarTransition","function")
  local writeSave=required(context,"writeSave","function")
  local FirstAid=required(context,"firstAid","table")
  local ShootingRange=required(context,"shootingRange","table")

  local function movementAxis(a, b) return (love.keyboard.isDown(b) and 1 or 0) - (love.keyboard.isDown(a) and 1 or 0) end

  local function moveInCurrentScene(oldX,oldY,newX,newY)
      if runtime.scene=="train" then return clampToTrainFloor(newX,newY) end
      if runtime.scene=="stop" then return Settlements.move(runtime.saveData.location,oldX,oldY,newX,newY) end
      if runtime.scene=="expedition" then return moveExpedition(oldX,oldY,newX,newY) end
      if runtime.scene=="caravan" then return moveCaravan(oldX,oldY,newX,newY) end
      return Util.clampHouseFloor(newX,newY)
  end

  local function updateInteraction()
      local mx,my
      if mobileEnabled() then mx,my=runtime.player.x,runtime.player.y
      else mx,my=screenToGame(love.mouse.getPosition()) end
      local selected=interactionRouter.select({data=runtime.saveData,scene=runtime.scene,player=runtime.player,npc=runtime.npcActor,car=car,mouseX=mx,mouseY=my,
          itemIsHere=itemIsHere,storageCapacities=Catalog.storageCapacities,nearTrain=Settlements.nearTrain,trainPoint=Settlements.trainPoint,
          nearDoor=Settlements.nearDoor,doorPoint=Settlements.doorPoint,hasSettlements=scenery.settlements~=nil,layout=ensureStopLayout,
          interiorPoint=InteriorDoors.point,nearInteriorDoor=InteriorDoors.near,interiorFiles=scenery.interiorFiles,
          shootingRange=currentShootingRange(),expeditionInteraction=currentExpeditionInteraction(),caravanInteraction=currentCaravanInteraction(),choose=Interactions.select})
      local flags=interactionRouter.flags(selected)
      ui.interaction=flags.interaction; runtime.nearbyItem=flags.nearbyItem; runtime.nearChest=flags.nearChest; runtime.nearMailbox=flags.nearMailbox
      runtime.nearHouse=flags.nearHouse or false; runtime.nearNPC=flags.nearNPC or false; runtime.nearPassenger=flags.nearPassenger
      runtime.nearReturnTrain=flags.nearReturnTrain or false; runtime.nearFire=flags.nearFire or false
      runtime.nearShootingRange=flags.nearShootingRange or false
      runtime.nearExpedition=flags.nearExpedition or false
      runtime.nearCaravan=flags.nearCaravan or false
      runtime.nearCarPrev=flags.nearCarPrev or false; runtime.nearCarNext=flags.nearCarNext or false; ui.nearRadio=flags.nearRadio or false
  end

  local function update(dt)
      updatePersistence(dt)
      runtime.animationClock=runtime.animationClock+dt
      Clouds.update(cloudLayer,dt)
      if screens:is("intro") then screens:update(dt); return end
      if ui.assetStreamer then ui.assetStreamer:update(runtime.state,runtime.scene,runtime.saveData,runtime.battle,runtime.npcActor) end
      -- Full settlement scenes keep only the dedicated dynamic chicken flocks;
      -- the retired random decoration wildlife remains disconnected.
      runtime.walkingSoundTimer=math.max(0,runtime.walkingSoundTimer-dt)
      updateAudio()
      -- Wheel, rod, bogie, and ballast phases are derived from sceneryOffset.
      -- Keeping motion tied to traveled pixels prevents rail slip and makes
      -- animation deterministic across frame rates and travel-speed upgrades.
      runtime.actionTimer=math.max(0,runtime.actionTimer-dt)
      if runtime.actionTimer<=0 then runtime.actionHeldItem=nil; runtime.actionKind=nil end
      if screens:update(dt) then return end
      if runtime.shootingRange then
          local outcome=ShootingRange.update(runtime.shootingRange,dt)
          if outcome then handleShootingRange(outcome) end
          return
      end
      if runtime.firstAid then FirstAid.update(runtime.firstAid,dt); return end
      if not WorldPause.isPaused(runtime,ui,maintenanceSession) then updateWorldScene(dt) end
      if runtime.state~="game" then return end
      if runtime.travelTransition then
          local transition=runtime.travelTransition
          transition.t=transition.t+dt*Accessibility.motionSpeed(runtime.saveData)
          local t=transition.t; local speedFactor; local timing=EngineUpgrades.timings(runtime.saveData.engineLevel,transition.maintenanceCondition or Maintenance.condition(runtime.saveData))
          if ui.departSource then
              -- Let the departure cue follow the train out, then release the
              -- channel before the arrival cue begins.
              local fade=math.max(0,math.min(1,(timing.depart-t)/(.55/EngineUpgrades.profile(runtime.saveData.engineLevel).speed)))
              local source=ui.departSource
              local ok,playing=pcall(source.isPlaying,source)
              if ok and playing then pcall(source.setVolume,source,(runtime.saveData.audio.sfxVolume or .55)*fade)
              else ui.departSource=nil end
              if ui.departSource and t>=timing.change then pcall(ui.departSource.stop,ui.departSource); ui.departSource=nil end
          end
          if t<timing.depart then speedFactor=(t/timing.depart)^2 elseif t<timing.arrive then speedFactor=1 else speedFactor=math.max(0,1-(t-timing.arrive)/timing.arrivalDuration)^2 end
          local sceneryDistance=(25+125*speedFactor)*EngineUpgrades.profile(runtime.saveData.engineLevel).speed*dt
          runtime.sceneryOffset=runtime.sceneryOffset+sceneryDistance*(landscape.trackSpeed or 1)
          runtime.landscapeOffset=runtime.landscapeOffset+sceneryDistance
          if not transition.changed and transition.t>=timing.change then
              transition.changed=true; runtime.saveData.location=runtime.saveData.location+1; runtime.saveData.stopped=true; runtime.saveData.visitedStops[runtime.saveData.location]=true
              Maintenance.onTravel(runtime.saveData)
              -- The scene is still the train interior at this point. Keep the
              -- player in the active car; trainPoint coordinates belong to the
              -- destination stop map and would place the character outside the
              -- train until the next movement clamp corrected it.
              runtime.player.x,runtime.player.y=clampToTrainFloor(runtime.player.x,runtime.player.y)
              TrainUpgradeBalance.applyArrival(runtime.saveData)
              ensureStopLayout(); journeyRules.passengerContributions(); journeyRules.processPassengerArrivals(); writeSave()
          end
          if not transition.arriveSoundPlayed and transition.t>=timing.arrive then transition.arriveSoundPlayed=true; ui.playSfx("trainArrive") end
          if transition.t>=timing.total then
              runtime.travelTransition=nil; runtime.sceneryOffset=0; runtime.landscapeOffset=0
              if runtime.saveData.location>=50 then runtime.state="ending"
              elseif runtime.saveData.arrivalNotice then runtime.dialogue={speaker="Passenger",text=runtime.saveData.arrivalNotice,timer=4}; runtime.saveData.arrivalNotice=nil; writeSave() end
          end
          return
      end
      if runtime.holdPickupIndex then
          local item=runtime.saveData and runtime.saveData.droppedItems[runtime.holdPickupIndex]
          local useHeld=love.keyboard.isDown("e") or mobileHeld("e")
          if not useHeld or not item or not itemIsHere(item) or math.sqrt((runtime.player.x-item.x)^2+(runtime.player.y-item.y)^2)>=75 then
              runtime.holdPickupIndex,runtime.holdPickupTime=nil,0
          else
              runtime.holdPickupTime=runtime.holdPickupTime+dt
              if runtime.holdPickupTime>=holdPickupSeconds then
                  runtime.nearbyItem=runtime.holdPickupIndex; inventoryActions.pickUpNearby(); runtime.holdPickupIndex,runtime.holdPickupTime=nil,0
              end
          end
      end
      if (runtime.scene=="stop" or runtime.scene=="house") and not runtime.npcActor then setupNPC() end
      if runtime.dialogue then runtime.dialogue.timer=runtime.dialogue.timer-dt; if runtime.dialogue.timer<=0 then runtime.dialogue=nil end end
      if runtime.scene=="train" then
          local sceneryDistance=18*dt
          runtime.sceneryOffset=runtime.sceneryOffset+sceneryDistance*(landscape.trackSpeed or 1)
          runtime.landscapeOffset=runtime.landscapeOffset+sceneryDistance
      end
      if updateCarTransition(dt*Accessibility.motionSpeed(runtime.saveData)) then return end
      Maintenance.update(maintenanceSession,dt)
      if WorldPause.isPaused(runtime,ui,maintenanceSession) then
          runtime.player.moving=false
          runtime.player.velocityX,runtime.player.velocityY=0,0
          return
      end
      local dx=movementAxis("a","d")+movementAxis("left","right")
      local dy=movementAxis("w","s")+movementAxis("up","down")
      local mobileX,mobileY=mobileMovement(); dx,dy=dx+mobileX,dy+mobileY
      local motionProfile=CharacterMotion.profileFor(runtime.saveData.character)
      if motionProfile then
          if dx~=0 or dy~=0 then runtime.playerPose="idle"; runtime.poseMenu=false end
          local sprint=(love.keyboard.isDown("lshift","rshift") or mobileSprinting()) and 1.7 or 1
          CharacterMotion.updateActor(runtime.player,dx,dy,dt,{
              profile=motionProfile,speed=runtime.player.speed,speedScale=sprint,
              move=moveInCurrentScene,
          })
          if runtime.player.moving and runtime.walkingSoundTimer<=0 then
              ui.playSfx("walkingSteps")
              runtime.walkingSoundTimer=math.max(.18,.34/sprint)
          end
      else
      runtime.player.moving=dx~=0 or dy~=0
      if runtime.player.moving then
          runtime.playerPose="idle"; runtime.poseMenu=false
          local length=math.sqrt(dx*dx+dy*dy); dx,dy=dx/length,dy/length
          if dx~=0 then runtime.player.facing=dx>0 and 1 or -1 end
          local sprint=(love.keyboard.isDown("lshift","rshift") or mobileSprinting()) and 1.7 or 1
          local oldX,oldY=runtime.player.x,runtime.player.y
          runtime.player.x,runtime.player.y=runtime.player.x+dx*runtime.player.speed*sprint*dt,runtime.player.y+dy*runtime.player.speed*sprint*dt
          if runtime.walkingSoundTimer<=0 then
              ui.playSfx("walkingSteps")
              runtime.walkingSoundTimer=math.max(.18,.34/sprint)
          end
          if runtime.scene=="train" then
              runtime.player.x,runtime.player.y=clampToTrainFloor(runtime.player.x,runtime.player.y)
          elseif runtime.scene=="stop" then
              runtime.player.x,runtime.player.y=Settlements.move(runtime.saveData.location,oldX,oldY,runtime.player.x,runtime.player.y)
          elseif runtime.scene=="expedition" then
              runtime.player.x,runtime.player.y=moveExpedition(oldX,oldY,runtime.player.x,runtime.player.y)
          elseif runtime.scene=="caravan" then
              runtime.player.x,runtime.player.y=moveCaravan(oldX,oldY,runtime.player.x,runtime.player.y)
          else
              runtime.player.x,runtime.player.y=Util.clampHouseFloor(runtime.player.x,runtime.player.y)
          end
      end
      end
      if runtime.npcActor then
          Family.update(runtime.npcActor,dt,function(oldX,oldY,newX,newY)
              if runtime.scene=="stop" then return Settlements.move(runtime.saveData.location,oldX,oldY,newX,newY) end
              if runtime.scene=="house" then return Util.clampHouseFloor(newX,newY) end
              return newX,newY
          end)
          runtime.npcActor.wait=(runtime.npcActor.wait or 1)-dt
          if runtime.npcActor.wait<=0 then
              local angle=love.math.random()*math.pi*2
              local distance=love.math.random(18,58)
              runtime.npcActor.targetX=runtime.npcActor.homeX+math.cos(angle)*distance
              runtime.npcActor.targetY=runtime.npcActor.homeY+math.sin(angle)*distance*.55
              runtime.npcActor.wait=love.math.random(3,7)
          end
          if runtime.npcActor.targetX then
              if runtime.scene=="house" then runtime.npcActor.targetX,runtime.npcActor.targetY=Util.clampHouseFloor(runtime.npcActor.targetX,runtime.npcActor.targetY)
              elseif runtime.scene=="stop" then runtime.npcActor.targetX,runtime.npcActor.targetY=Settlements.clamp(runtime.npcActor.targetX,runtime.npcActor.targetY,runtime.saveData.location) end
              local nx,ny=runtime.npcActor.targetX-runtime.npcActor.x,runtime.npcActor.targetY-runtime.npcActor.y; local len=math.sqrt(nx*nx+ny*ny)
              if len<2 then runtime.npcActor.targetX=nil else
                  local npcProfile=CharacterMotion.profileFor(runtime.saveData.currentNPC)
                  if npcProfile then
                      local arrived=CharacterMotion.moveToward(runtime.npcActor,runtime.npcActor.targetX,runtime.npcActor.targetY,dt,{
                          profile=npcProfile,speed=32,stopDistance=2,move=moveInCurrentScene,
                      })
                      if arrived then runtime.npcActor.targetX=nil end
                  else
                  if math.abs(nx)>.1 then runtime.npcActor.facing=nx>0 and 1 or -1 end
                  local step=math.min(len,32*dt); runtime.npcActor.x=runtime.npcActor.x+nx/len*step; runtime.npcActor.y=runtime.npcActor.y+ny/len*step
                  end
              end
          end
      end
      if runtime.scene=="train" then for _,passenger in ipairs(runtime.saveData.passengers or {}) do
          passenger.carIndex=math.max(1,math.min(#(runtime.saveData.trainCars or {1}),passenger.carIndex or 1)); passenger.wait=(passenger.wait or 1)-dt
          if passenger.wait<=0 then
              local preferred=Passengers.preferredCar(passenger,runtime.saveData.trainCars)
              if preferred~=passenger.carIndex and love.math.random()<.55 then passenger.targetCar=preferred; passenger.targetX=preferred>passenger.carIndex and car.x+car.w-35 or car.x+35; passenger.targetY=car.y+205
              else local left,right,top,bottom=trainFloorBounds(); passenger.targetX,passenger.targetY=clampToTrainFloor(love.math.random(left+20,right-20),love.math.random(top,bottom)) end
              passenger.wait=love.math.random(4,8); passenger.pose="idle"
          end
          if passenger.targetX then
              local dx,dy=passenger.targetX-passenger.x,passenger.targetY-passenger.y; local len=math.sqrt(dx*dx+dy*dy)
              if len<2 then
                  passenger.targetX=nil
                  if passenger.targetCar then local left,right,top,bottom=trainFloorBounds(); passenger.carIndex=passenger.targetCar; passenger.targetCar=nil; passenger.x=passenger.carIndex>1 and left or right; passenger.y=(top+bottom)/2 end
                  local hasSleeper=false; for _,id in ipairs(runtime.saveData.trainCars or {}) do if id=="sleeper" then hasSleeper=true end end; passenger.pose=(hasSleeper and love.math.random()<.25) and "lay" or (love.math.random()<.55 and "sit" or "idle")
              else
                  local passengerProfile=CharacterMotion.profileFor(passenger.npc)
                  if passengerProfile then
                      CharacterMotion.moveToward(passenger,passenger.targetX,passenger.targetY,dt,{
                          profile=passengerProfile,speed=38,stopDistance=2,
                          move=function(_,_,x,y) return clampToTrainFloor(x,y) end,
                      })
                  else
                      local step=math.min(len,38*dt); passenger.x=passenger.x+dx/len*step; passenger.y=passenger.y+dy/len*step; passenger.facing=dx>0 and 1 or -1
                  end
              end
          end
      end end
      updateInteraction()
  end

  return {update=update,updateInteraction=updateInteraction}
end

return {new=new}
