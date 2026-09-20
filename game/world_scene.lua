local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"world scene requires "..name)
  if expected then assert(type(value)==expected,"world scene "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","world scene requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local scenery=required(context,"scenery","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local House=required(context,"house","table")
  local Stops=required(context,"stops","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Wildlife=required(context,"wildlife","table")
  local Mice=required(context,"mice","table")
  local StopSludges=required(context,"stopSludges","table")
  local ShootingRange=required(context,"shootingRange","table")
  local Events=required(context,"events","table")
  local StopHelpProgression=required(context,"stopHelpProgression","table")
  local CrowCaravans=required(context,"crowCaravans","table")
  local CrowCaravanArea=required(context,"crowCaravanArea","table")
  local ExpeditionAreas=required(context,"expeditionAreas","table")
  local ExpeditionRuntime=required(context,"expeditionRuntime","table")
  local RoamingMobs=required(context,"roamingMobs","table")
  local getBeginEncounter=required(context,"getBeginEncounter","function")
  local getIsWeapon=required(context,"getIsWeapon","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local writeSave=required(context,"writeSave","function")
  local activeStopSludges=StopSludges.new()
  local caravanSession=nil
  local expedition=ExpeditionRuntime.new({
      runtime=runtime,ui=ui,catalog=Catalog,areas=ExpeditionAreas,roamingMobs=RoamingMobs,
      getIsWeapon=getIsWeapon,getBeginEncounter=getBeginEncounter,writeSave=writeSave,
      clampToStop=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
      width=required(context,"width","number"),height=required(context,"height","number"),
      mobImages=required(context,"mobImages","table"),mobIdleImages=required(context,"mobIdleImages","table"),
      mobWalkImages=required(context,"mobWalkImages","table"),mobAttackImages=required(context,"mobAttackImages","table"),
      mobHitImages=required(context,"mobHitImages","table"),mobDeathImages=required(context,"mobDeathImages","table"),
      mobRangedImages=required(context,"mobRangedImages","table"),
  })

  local function isWeapon(name)
      local check=getIsWeapon()
      assert(type(check)=="function","world scene requires an available weapon check")
      return check(name)
  end

  local function resetStopSludges()
      activeStopSludges=StopSludges.new()
  end

  local function ensureStopLayout()
      local layout=Stops.ensure(runtime.saveData,Catalog,runtime.scene)
      ShootingRange.ensure(layout,runtime.saveData.location,Settlements)
      return layout
  end

  local function ensureHouseItems()
      House.ensure(runtime.saveData,Catalog,isFurnitureItem)
  end

  local function itemIsHere(item)
      if item.scene~=runtime.scene then return false end
      if runtime.scene=="train" then return (item.carIndex or 1)==(runtime.saveData.activeCar or 1) end
      if runtime.scene=="house" then return item.location==runtime.saveData.location and (item.houseDoor or 1)==(runtime.saveData.activeHouseDoor or 1) end
      if runtime.scene==ExpeditionAreas.SCENE then return item.expeditionAreaId==runtime.saveData.activeExpeditionArea end
      if runtime.scene==CrowCaravanArea.SCENE then
          local root=runtime.saveData.crowCaravans
          return type(root)=="table" and item.caravanCampId==root.activeCampId
      end
      return item.location==runtime.saveData.location
  end

  local function setupNPC()
      if runtime.scene=="train" or runtime.scene==ExpeditionAreas.SCENE or runtime.scene==CrowCaravanArea.SCENE then runtime.npcActor=nil; return end
      local layout=ensureStopLayout()
      runtime.saveData.currentNPC=(runtime.scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
      local key=Util.sceneKey(runtime.scene,runtime.saveData.location)..(runtime.scene=="house" and (":"..tostring(runtime.saveData.activeHouseDoor or 1)) or "")
      local saved=runtime.saveData.npcStates[key]
      local defaults=runtime.scene=="house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
      saved=saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
      saved.weapon=saved.weapon or layout.npcWeapon
      if runtime.scene=="house" then
          saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
          saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
      elseif runtime.scene=="stop" then
          saved.x,saved.y=Settlements.clamp(saved.x,saved.y,runtime.saveData.location)
          saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,runtime.saveData.location)
      end
      runtime.saveData.npcStates[key]=saved
      runtime.npcActor=saved
      Family.ensure(runtime.npcActor,runtime.saveData.currentNPC)
  end

  local function caravanScheduleOptions()
      local excluded={[1]=true,[50]=true}
      for _,stop in ipairs(ShootingRange.hostStops or {}) do excluded[stop]=true end
      for _,stop in ipairs(Events.storyStops or {}) do excluded[stop]=true end
      for _,stop in ipairs((runtime.saveData and runtime.saveData.mysteryStops) or {}) do excluded[stop]=true end
      for stop=1,50 do if ExpeditionAreas.availableAtStop(stop) then excluded[stop]=true end end
      for stop=1,50 do if not CrowCaravanArea.hasStopGate(stop) then excluded[stop]=true end end
      return {excludedStops=excluded}
  end

  local function caravanGatePoint()
      if runtime.scene~="stop" or not runtime.saveData then return nil end
      local gate=CrowCaravanArea.stopGate(runtime.saveData.location)
      if not gate then return nil end
      return gate.x,gate.y
  end

  local function currentCaravanSession()
      if runtime.scene~=CrowCaravanArea.SCENE or not runtime.saveData then return nil end
      local activeId=runtime.saveData.crowCaravans and runtime.saveData.crowCaravans.activeCampId
      if caravanSession and caravanSession.id==activeId and caravanSession.data==runtime.saveData then return caravanSession end
      caravanSession=CrowCaravanArea.restore(runtime.saveData)
      return caravanSession
  end

  local function currentCaravanInteraction()
      if not runtime.saveData or not runtime.player then return nil end
      if runtime.scene=="stop" then
          local available=CrowCaravans.isScheduled(runtime.saveData,runtime.saveData.location,caravanScheduleOptions())
          if not available then return nil end
          local camp=CrowCaravans.lookup(runtime.saveData,runtime.saveData.location)
          if camp and not CrowCaravans.isActive(camp) then return nil end
          local x,y=caravanGatePoint()
          if not x then return nil end
          return CrowCaravanArea.stopEntrance(runtime.saveData.location,{x=x,y=y,label="VISIT CROW CARAVAN"})
      end
      if runtime.scene==CrowCaravanArea.SCENE then return CrowCaravanArea.interaction(currentCaravanSession(),runtime.player) end
      return nil
  end

  local function enterCaravan(selected)
      if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return false end
      local location=runtime.saveData.location
      if selected and selected.stop and selected.stop~=location then return false end
      local camp,errorMessage=CrowCaravans.ensureCamp(runtime.saveData,Catalog,location,caravanScheduleOptions())
      if not camp then
          runtime.dialogue={speaker="Crow Caravan",text=errorMessage=="not-scheduled" and "Only wagon tracks remain here." or "The caravan cannot make camp here yet.",timer=3.5}
          return false
      end
      local firstVisit=camp.visited~=true
      local session,x,y=CrowCaravanArea.enter(runtime.saveData,location,
          {x=runtime.player.x,y=runtime.player.y,facing=runtime.player.facing},{camp=camp})
      if not session then return false end
      caravanSession=session
      runtime.scene=CrowCaravanArea.SCENE
      runtime.player.x,runtime.player.y=x,y
      runtime.player.velocityX,runtime.player.velocityY=0,0
      runtime.npcActor=nil
      runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0
      local root=runtime.saveData.crowCaravans
      if firstVisit then root.meetings=math.max(0,math.floor(tonumber(root.meetings) or 0))+1 end
      runtime.dialogue={speaker="CARAVAN",text="Three merchant wagons. Trading available at each stall.",timer=5}
      ui.playSfx("doors"); writeSave(); return true
  end

  local function returnFromCaravan()
      if runtime.scene~=CrowCaravanArea.SCENE or not runtime.saveData or not runtime.player then return false end
      local session=currentCaravanSession()
      if not session then runtime.scene="stop"; setupNPC(); return false end
      CrowCaravanArea.savePosition(session,runtime.player)
      local x,y,facing=CrowCaravanArea.leave(runtime.saveData,session)
      runtime.scene="stop"
      runtime.player.x,runtime.player.y=Settlements.clamp(x or 480,y or 620,runtime.saveData.location)
      if facing~=nil then runtime.player.facing=facing end
      runtime.player.velocityX,runtime.player.velocityY=0,0
      runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0
      runtime.dialogue=nil; caravanSession=nil
      setupNPC(); ui.playSfx("doors"); writeSave(); return true
  end

  local function activateCaravanInteraction(selected)
      selected=selected or currentCaravanInteraction()
      if not selected or selected.kind~=CrowCaravanArea.KIND then return false end
      if selected.action=="enterCaravan" then return enterCaravan(selected) end
      if selected.action=="returnStop" then return returnFromCaravan() end
      if selected.action=="trade" then
          local session=currentCaravanSession()
          local camp=session and session.state
          local merchant=session and CrowCaravanArea.merchant(session,selected.merchantId)
          if not merchant then return false end
          runtime.tradeMerchantId=selected.merchantId
          runtime.tradeNPC=camp.relationshipKey or CrowCaravans.relationshipKey
          runtime.tradeBuyPage=0; runtime.tradeSellPage=0; runtime.tradeMessage=nil; runtime.tradeOpen=true; runtime.dialogue=nil
          ui.playSfx("menu"); return true
      end
      return false
  end

  local function currentTradeSource()
      if runtime.scene==CrowCaravanArea.SCENE and runtime.tradeMerchantId then
          local session=currentCaravanSession(); local camp=session and session.state
          local merchant=camp and CrowCaravans.merchant(camp,runtime.tradeMerchantId)
          if not merchant then return nil end
          local root=runtime.saveData.crowCaravans
          camp.purchaseHistory=type(camp.purchaseHistory)=="table" and camp.purchaseHistory or {}
          return {
              kind="caravan",title=string.upper(merchant.name).."  •  THE ROOKERY CARAVAN",
              merchant=CrowCaravans.relationshipKey,relationshipId=camp.relationshipKey or root.groupRelationshipId or CrowCaravans.relationshipKey,
              stock=CrowCaravans.tradeListings(camp,merchant.id,Catalog),allowGifts=false,directAmmo=true,mailboxOverflow=true,
              availableBudget=function(terms) return CrowCaravans.availableBudget(camp,terms) end,
              spendBudget=function(amount,terms) return CrowCaravans.spendBudget(camp,amount,terms) end,
              onPurchase=function(_,name,delivery,listing)
                  root.trades=math.max(0,math.floor(tonumber(root.trades) or 0))+1
                  camp.purchaseHistory[#camp.purchaseHistory+1]={merchantId=merchant.id,item=name,delivery=delivery,stop=camp.stop,listingId=listing and listing.id}
              end,
              onSale=function(_,name,price)
                  root.trades=math.max(0,math.floor(tonumber(root.trades) or 0))+1
                  local resale=CrowCaravans.addResaleListing(camp,merchant.id,name,Catalog,nil,price)
                  camp.purchaseHistory[#camp.purchaseHistory+1]={merchantId=merchant.id,item=name,soldToCaravan=true,price=price,
                      stop=camp.stop,resaleListingId=resale and resale.id or nil}
              end,
          }
      end
      if runtime.tradeOpen then
          local layout=ensureStopLayout(); layout.tradeStock=layout.tradeStock or {}
          local merchant=runtime.tradeNPC or runtime.saveData.currentNPC
          return {kind="stop",title=Util.titleFromFile(merchant).."'S TRADING POST",merchant=merchant,relationshipId=merchant,
              stock=layout.tradeStock,budgetOwner=layout,budgetKey="tradeBudget",allowGifts=true,directAmmo=false,mailboxOverflow=false}
      end
      return nil
  end

  local function moveCaravan(oldX,oldY,newX,newY)
      if not currentCaravanSession() then return oldX,oldY end
      return CrowCaravanArea.move(oldX,oldY,newX,newY)
  end

  local function drawCaravan(options)
      local session=currentCaravanSession()
      if session then CrowCaravanArea.draw(session,options or {}) end
  end

  local function drawCaravanGate()
      if runtime.scene~="stop" or not currentCaravanInteraction() then return end
      local x,y=caravanGatePoint(); if not x then return end
      local caravanAssets=scenery.crowCaravanAssets
      local banner=caravanAssets and caravanAssets.crowBanner
      assert(banner,"The Rookery Caravan requires its crow banner sprite")
      local width,height=banner:getDimensions()
      assert(width>0 and height>0,"The Rookery Caravan crow banner sprite has invalid dimensions")
      local scale=94/height
      local settings=runtime.saveData and runtime.saveData.accessibility
      local still=settings and settings.reducedMotion==true
      local sway=still and 0 or math.sin((runtime.animationClock or 0)*1.7)*math.rad(1.6)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(banner,x,y+12,sway,scale,scale,width/2,height)
  end

  local function updateStopSludges(dt)
      if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return end
      StopSludges.update(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          clamp=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
          dropCoal=function(x,y)
              runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=runtime.saveData.location,droppedByPlayer=false}
              writeSave()
          end},dt)
  end

  local function attackStopSludge(x,y)
      if runtime.scene~="stop" or runtime.inventoryOpen or runtime.mapOpen or runtime.dialogue or runtime.editMode or ui.radioOpen or runtime.trainUpgradeOpen or runtime.poseMenu or ui.optionsOpen then return false end
      return StopSludges.attack(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          onAction=function(weapon) runtime.actionHeldItem=weapon; runtime.actionKind="melee"; runtime.actionTimer=.42 end,
          playSfx=function(kind) ui.playSfx(kind) end},x,y)
  end

  local function updateWildlife(dt)
      if runtime.scene~="stop" or not runtime.saveData then return end
      local layout=ensureStopLayout()
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      local ecology={player=runtime.player}
      Wildlife.update(layout.wildlife,dt,runtime.saveData.location,Settlements,ecology)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.update(layout.mice,dt,runtime.saveData.location,Settlements,ecology)
  end

  local function update(dt)
      updateStopSludges(dt)
      updateWildlife(dt)
      expedition.update(dt)
      if runtime.scene==CrowCaravanArea.SCENE then
          local session=currentCaravanSession()
          if session then CrowCaravanArea.update(session,dt); CrowCaravanArea.savePosition(session,runtime.player) end
      end
  end

  local function currentShootingRange()
      if runtime.scene~="stop" or not runtime.saveData then return nil end
      return ensureStopLayout().shootingRange
  end

  local function beginShootingRange()
      if runtime.scene~="stop" or not runtime.player then return false end
      local spot=currentShootingRange()
      if not ShootingRange.near(spot,runtime.player.x,runtime.player.y) then return false end
      local session,message=ShootingRange.new(runtime.saveData,spot,Catalog,{npc=runtime.saveData.currentNPC})
      if not session then
          runtime.dialogue={speaker="Target Range",text=message,timer=6}
          return false
      end
      runtime.dialogue=nil; runtime.shootingRange=session
      return true
  end

  local function handleShootingRange(outcome)
      local session=runtime.shootingRange
      if not session then return nil end
      if outcome=="complete" then
          local result=ShootingRange.complete(session,runtime.saveData,currentShootingRange(),StopHelpProgression)
          writeSave(); return result
      end
      if outcome=="close" then
          ShootingRange.releaseWeaponViews(scenery.shootingRangeAssets)
          runtime.shootingRange=nil; writeSave(); return true
      end
      if outcome=="shot" or outcome=="purchase" then writeSave() end
      return outcome
  end

  local function drawShootingRangeSpot()
      if runtime.scene=="stop" then
          local spot=currentShootingRange()
          ShootingRange.drawSpot(spot,scenery.shootingRangeAssets and scenery.shootingRangeAssets.entrance,runtime.animationClock)
      end
  end

  local function drawStopSludges(images)
      StopSludges.draw(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,clock=runtime.animationClock,images=images})
  end

  local function drawWildlife(layout)
      if not layout or runtime.scene~="stop" then return end
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      Wildlife.draw(layout.wildlife,scenery.stopWildlife,runtime.animationClock)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.draw(layout.mice,scenery.stopWildlife,runtime.animationClock)
  end

  return {
      resetStopSludges=resetStopSludges,
      ensureStopLayout=ensureStopLayout,
      ensureHouseItems=ensureHouseItems,
      itemIsHere=itemIsHere,
      setupNPC=setupNPC,
      update=update,
      attackStopSludge=attackStopSludge,
      attackExpeditionMob=expedition.attack,
      moveExpedition=expedition.move,
      currentExpeditionInteraction=expedition.currentInteraction,
      activateExpeditionInteraction=expedition.activateInteraction,
      drawExpedition=expedition.draw,
      resetExpedition=expedition.reset,
      prepareExpeditionBattleAssets=expedition.ensureAssets,
      expeditionObjective=expedition.objective,
      drawExpeditionLocalMap=expedition.drawLocalMap,
      drawExpeditionTrailhead=expedition.drawTrailhead,
      expeditionCameraOffset=expedition.cameraOffset,
      expeditionAudit=expedition.audit,
      moveCaravan=moveCaravan,
      currentCaravanInteraction=currentCaravanInteraction,
      activateCaravanInteraction=activateCaravanInteraction,
      returnFromCaravan=returnFromCaravan,
      currentTradeSource=currentTradeSource,
      drawCaravan=drawCaravan,
      drawCaravanGate=drawCaravanGate,
      caravanAudit=CrowCaravanArea.audit,
      drawStopSludges=drawStopSludges,
      currentShootingRange=currentShootingRange,
      beginShootingRange=beginShootingRange,
      handleShootingRange=handleShootingRange,
      drawShootingRangeSpot=drawShootingRangeSpot,
      drawWildlife=drawWildlife,
  }
end

return {new=new}
