local Accessibility=require("game.accessibility")
local CoopProgression=require("game.coop_progression")
local MerchantTrade=require("game.merchant_trade")
local SceneRoutes=require('game.journey_scene_routes')
local Home=require("game.home_stop")
local SceneNPCs=require("game.scene_npcs")
local HomeFox=require("game.home_stop_fox")
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
  local rangePose=nil
  local rangePendingOpen=false
  local rangePendingAction=nil
  local rangeRetryAt=nil
  local function sharedRange()
      return runtime.session and runtime.session.networkMode=="host"
  end
  local function presentRange(view)
      local model=ShootingRange.presentation(view,rangePose)
      rangePose.aimX,rangePose.aimY,rangePose.touchAim=model.aimX,model.aimY,model.touchAim
      runtime.shootingRange=model
      return model
  end
  local function rangeBlocked()
      return runtime.state~="game" or runtime.session and runtime.session.checkpointPending
          or ui.escMenuOpen or ui.optionsOpen or ui.playerToolsOpen or ui.mobileMenuOpen or ui.radioOpen
          or ui.localPlay and (ui.localPlay.menuOpen or ui.localPlay.focused==false)
          or runtime.exitPrompt or runtime.pendingConfirmation or runtime.travelTransition or runtime.battle
          or runtime.inventoryOpen or runtime.mapOpen or runtime.journeyLogOpen or runtime.tradeOpen or runtime.poseMenu
  end
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
      if Home.isHome(runtime.saveData) then return Home.layout(runtime.saveData) end
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
      runtime.npcActors={}
      runtime.npcActor=SceneNPCs.prepare(runtime.saveData,Catalog)
      if SceneNPCs.hasResidents(runtime.saveData) and not Home.isHome(runtime.saveData) then
          SceneNPCs.refresh(runtime,SceneNPCs.locked(runtime))
      elseif runtime.npcActor then runtime.npcActors={runtime.npcActor} end
  end

  local function caravanScheduleOptions()
      return SceneRoutes.caravanSchedule(runtime.saveData)
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
      if Home.isHome(runtime.saveData) then return nil end
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
      if not CoopProgression.allowed(runtime,"scene.caravan") then return false,"host_only" end
      if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return false end
      local location=runtime.saveData.location
      if selected and selected.stop and selected.stop~=location then return false end
      if ui.transitionParty then
          local reply=ui.transitionParty('scene.caravan',{action='enter',stop=location})
          return reply.ok,reply.reason
      end
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
      if not CoopProgression.allowed(runtime,"scene.caravan") then return false,"host_only" end
      if runtime.scene~=CrowCaravanArea.SCENE or not runtime.saveData or not runtime.player then return false end
      if ui.transitionParty then
          local reply=ui.transitionParty('scene.caravan',{action='return'})
          return reply.ok,reply.reason
      end
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
          return MerchantTrade.caravanSource(runtime.saveData,Catalog,camp,merchant.id)
      end
      if runtime.tradeOpen then
          local layout=ensureStopLayout(); layout.tradeStock=layout.tradeStock or {}
          local merchant=runtime.tradeNPC or runtime.saveData.currentNPC
          return MerchantTrade.stopSource(layout,merchant,require('game.npc_identity').name(runtime.saveData,merchant).."'S TRADING POST")
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
      local settings=runtime.saveData and Accessibility.ensure(runtime.saveData)
      local still=settings and settings.reducedMotion==true
      local sway=still and 0 or math.sin((runtime.animationClock or 0)*1.7)*math.rad(1.6)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(banner,x,y+12,sway,scale,scale,width/2,height)
  end

  local function updateStopSludges(dt)
      if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return end
      if Home.isHome(runtime.saveData) then return end
      StopSludges.update(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          clamp=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
          dropCoal=function(x,y)
              runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=runtime.saveData.location,droppedByPlayer=false}
              writeSave()
          end},dt)
  end

  local function attackStopSludge(x,y)
      if Home.isHome(runtime.saveData) then return false end
      if runtime.scene~="stop" or runtime.inventoryOpen or runtime.mapOpen or runtime.dialogue or runtime.editMode or ui.radioOpen or runtime.trainUpgradeOpen or runtime.poseMenu or ui.optionsOpen then return false end
      return StopSludges.attack(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=isWeapon,clock=runtime.animationClock,
          onAction=function(weapon) local attack=require('game.character_attack'); runtime.actionHeldItem=attack.heldItem(weapon); runtime.actionKind=attack.action(weapon); runtime.actionTimer=.42; runtime.actionDuration=.42 end,
          playSfx=function(kind) ui.playSfx(kind) end},x,y)
  end

  local function updateWildlife(dt)
      if runtime.scene~="stop" or not runtime.saveData then return end
      if Home.isHome(runtime.saveData) then return end
      local layout=ensureStopLayout()
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      local ecology={player=runtime.player}
      Wildlife.update(layout.wildlife,dt,runtime.saveData.location,Settlements,ecology)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.update(layout.mice,dt,runtime.saveData.location,Settlements,ecology)
  end

  local function update(dt)
      if Home.isHome(runtime.saveData) then HomeFox.update(runtime.saveData,dt,runtime.dialogue and runtime.dialogue.homeFox and runtime.player); return end
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
      if Home.isHome(runtime.saveData) then return nil end
      return ensureStopLayout().shootingRange
  end

  local function beginShootingRange()
      if not CoopProgression.allowed(runtime,"scene.rangeEnter") then return false,"host_only" end
      if runtime.scene~="stop" or not runtime.player then return false end
      local spot=currentShootingRange()
      if not ShootingRange.near(spot,runtime.player.x,runtime.player.y) then return false end
      if sharedRange() then
          if type(context.rangeCommands)~="function" or type(context.rangeView)~="function" or not spot.entityId then return false,"range_unavailable" end
          local reply=context.rangeCommands("range.acquire",{spotId=spot.entityId})
          if not reply or not reply.ok then return false,reply and reply.reason or "range_unavailable" end
          rangePose={aimX=480,aimY=330,aimMode="hip",menuRow=1,hasMonocular=ShootingRange.hasMonocular(runtime.saveData),
              campaign=runtime.saveData,spotId=spot.entityId,location=runtime.saveData.location,epoch=runtime.saveData.coop.sceneEpoch}
          rangeRetryAt=nil
          rangePendingOpen=true; runtime.dialogue=nil
          if not reply.savePending then
              local view=context.rangeView("host")
              if view then presentRange(view); rangePendingOpen=false end
          end
          return true
      end
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
      if sharedRange() then return outcome end
      if outcome=="complete" then
          local result=ShootingRange.complete(session,runtime.saveData,currentShootingRange(),StopHelpProgression)
          writeSave(); return result
      end
      if outcome=="close" then
          if not CoopProgression.allowed(runtime,"scene.rangeExit") then return false,"host_only" end
          ShootingRange.releaseWeaponViews(scenery.shootingRangeAssets)
          runtime.shootingRange=nil; writeSave(); return true
      end
      if outcome=="shot" or outcome=="purchase" then writeSave() end
      return outcome
  end

  local function rangeSound()
      local session=runtime.shootingRange
      local profile=session and ShootingRange.soundProfile(session,Catalog)
      if profile and ui.playSfxPath then ui.playSfxPath(profile.path,profile)
      elseif session then ui.playSfx(ShootingRange.sound(session,Catalog)) end
  end
  local function rangeCommandState()
      local session=runtime.shootingRange
      local active=sharedRange() and rangePose~=nil and runtime.state=="game" and runtime.scene=="stop"
      return {active=active,ready=active and session~=nil and not rangePendingOpen,
          paused=not not rangeBlocked(),spotId=session and session.spotId,roundRevision=session and session.roundRevision}
  end
  local function rangeInput(kind,a,b,c)
      if not sharedRange() then return nil end
      local session=runtime.shootingRange
      if not session or not rangePose then return nil end
      if kind=="mousereleased" or kind=="keyreleased" then
          rangePose.fireHeld=false
          if kind=="mousereleased" and c==2 then rangePose.aimMode="hip"; session.aimMode="hip" end
          return "released"
      end
      if rangeBlocked() or rangePendingOpen or type(context.rangeCommands)~="function" then rangePose.fireHeld=false; return nil end
      local intent=ShootingRange.inputIntent(session,kind,a,b,c)
      if not intent then return nil end
      local action=intent.action
      if intent.row then rangePose.menuRow=intent.row end
      if action=="row" then rangePose.menuRow=((rangePose.menuRow-1+intent.direction)%6)+1; session.menuRow=rangePose.menuRow; return "select" end
      if action=="pointer" then
          ShootingRange.mousemoved(session,intent.x,intent.y,intent.touch)
          rangePose.aimX,rangePose.aimY,rangePose.touchAim=session.aimX,session.aimY,session.touchAim
          return "aimPointer"
      end
      if action=="aim" then
          rangePose.aimMode=intent.value==true and "sights" or (rangePose.aimMode=="sights" and "hip" or "sights")
          session.aimMode=rangePose.aimMode; ShootingRange.setAim(session,rangePose.aimMode=="sights")
          rangePose.aimX,rangePose.aimY=session.aimX,session.aimY; return "aim"
      end
      if action=="monocular" then
          if not session.hasMonocular then return nil end
          rangePose.monocularActive=not rangePose.monocularActive; session.monocularActive=rangePose.monocularActive; return "monocular"
      end
      local args={leaseId=session.leaseId,roundRevision=session.roundRevision,weaponId=session.itemId}
      local command
      if action=="configure" or action=="start" or action=="setup" or action=="mode" then
          command="range.configure"; args.action=action=="configure" and "change" or action
          args.weaponId=nil
          if action=="configure" then args.kind=intent.kind; args.direction=intent.direction end
          if action=="mode" then args.direction=1 end
          rangePose.fireHeld=false
      elseif action=="fire" then
          if intent.x then ShootingRange.mousemoved(session,intent.x,intent.y,false); rangePose.aimX,rangePose.aimY=session.aimX,session.aimY end
          local x,y=ShootingRange.canonicalAim(session,rangePose.aimX,rangePose.aimY)
          args.x=math.floor(x/960*1000000+.5); args.y=math.floor(y/720*1000000+.5)
          rangePose.fireHeld=true; command="range.fire"
      elseif action=="reload" then command="range.reload"; rangePose.fireHeld=false
      elseif action=="ammo" then command="range.ammo"
      elseif action=="release" then command="range.release"; args={leaseId=session.leaseId}; rangePose.fireHeld=false
      else return nil end
      local reply=context.rangeCommands(command,args)
      if not reply or not reply.ok then rangePose.fireHeld=false; session.message="RANGE UNAVAILABLE"; return "dry" end
      if reply.savePending then
          rangePose.fireHeld=false
          rangePendingAction={action=action,leaseId=session.leaseId,spotId=session.spotId,entityId=session.entityId,
              roundRevision=session.roundRevision,weaponId=session.itemId,shots=session.shots}
      end
      if not reply.savePending then
          if action=="release" then
              ShootingRange.releaseWeaponViews(scenery.shootingRangeAssets); runtime.shootingRange=nil; rangePose=nil; rangePendingOpen=false; return "close"
          end
          local view=context.rangeView("host"); if view then presentRange(view) end
          if action=="fire" then return "shot" end
      end
      return action=="configure" and "select" or action=="ammo" and "purchase" or action
  end
  local function closeSharedRange()
      if not rangePose then return false end
      ShootingRange.releaseWeaponViews(scenery.shootingRangeAssets)
      runtime.shootingRange=nil; rangePose=nil; rangePendingOpen=false; rangePendingAction=nil; rangeRetryAt=nil
      return true
  end
  local function rangeUpdate(dt)
      if not sharedRange() then closeSharedRange(); return end
      if not rangePose then
          -- Starting a LAN host while the offline range overlay is open must
          -- enter through a new checked lease, retaining all ammo already spent.
          if runtime.shootingRange then ShootingRange.releaseWeaponViews(scenery.shootingRangeAssets); runtime.shootingRange=nil end
          return
      end
      if type(context.rangeView)~="function" then return end
      local data=runtime.saveData
      if not data or data~=rangePose.campaign or runtime.state~="game" or runtime.scene~="stop" or data.scene~="stop"
          or data.location~=rangePose.location or not data.coop or data.coop.sceneEpoch~=rangePose.epoch or data.stopped~=true
          or (tonumber(data.health) or 0)<=0 or not runtime.player or runtime.battle or runtime.travelTransition
          or data.roamingEncounter or runtime.lastStand and runtime.lastStand.capture then closeSharedRange(); return end
      local spot=currentShootingRange()
      if not spot or spot.entityId~=rangePose.spotId or not ShootingRange.near(spot,runtime.player.x,runtime.player.y) then closeSharedRange(); return end
      if rangeBlocked() then rangePose.fireHeld=false; return end
      local view=context.rangeView("host")
      if not view then
          rangePose.fireHeld=false
          if rangePendingAction and rangePendingAction.action=="release" then closeSharedRange(); return end
          rangePendingOpen=true
          if runtime.shootingRange then runtime.shootingRange.message="Waiting for the range to be ready..." end
          local now=context.clock and context.clock() or love and love.timer and love.timer.getTime() or runtime.animationClock or 0
          if type(context.rangeCommands)~="function" or rangeRetryAt and now<rangeRetryAt then return end
          rangeRetryAt=now+.6
          local reply=context.rangeCommands("range.acquire",{spotId=rangePose.spotId})
          if not reply or not reply.ok then
              local reason=reply and reply.reason
              if reason=="range_distance" or reason=="range_unavailable" or reason=="host_only"
                  or reason=="no_campaign" or reason=="invalid_campaign" then closeSharedRange() end
              return
          end
          if reply.savePending then return end
          view=context.rangeView("host"); if not view then return end
      end
      rangePendingOpen=false; rangeRetryAt=nil; rangePose.hasMonocular=ShootingRange.hasMonocular(runtime.saveData)
      presentRange(view)
      local session=runtime.shootingRange
      if rangePendingAction then
          local pending=rangePendingAction; rangePendingAction=nil
          if pending.action=="fire" and session.spotId==pending.spotId and session.entityId==pending.entityId and session.roundRevision==pending.roundRevision
              and session.itemId==pending.weaponId and session.shots>pending.shots then rangeSound() end
      end
      if rangePose.fireHeld and session.phase=="play" and session.fireMode=="auto" and session.cooldown<=0 and session.reloadTimer<=0 and session.time>0 then
          if rangeInput("keypressed","space")=="shot" then rangeSound() end
      end
      if runtime.shootingRange then ShootingRange.updatePresentation(runtime.shootingRange,dt) end
  end

  local function drawShootingRangeSpot()
      if runtime.scene=="stop" then
          local spot=currentShootingRange()
          ShootingRange.drawSpot(spot,scenery.shootingRangeAssets and scenery.shootingRangeAssets.entrance,runtime.animationClock)
      end
  end

  local function drawStopSludges(images)
      if Home.isHome(runtime.saveData) then return end
      StopSludges.draw(activeStopSludges,{data=runtime.saveData,location=runtime.saveData.location,clock=runtime.animationClock,images=images})
  end

  local function drawWildlife(layout)
      if not layout or runtime.scene~="stop" then return end
      if Home.isHome(runtime.saveData) then return end
      Wildlife.spawn(layout,runtime.saveData.location,Settlements)
      Wildlife.draw(layout.wildlife,scenery.stopWildlife,runtime.animationClock)
      Mice.spawn(layout,runtime.saveData.location,Settlements)
      Mice.draw(layout.mice,scenery.stopWildlife,runtime.animationClock)
  end

  local function acceptParty(result,name)
      if result.expeditionReturn then return expedition.acceptBattleReturn() end
      if name=='scene.expedition' then return expedition.acceptParty(result) end
      if name~='scene.caravan' then return end
      caravanSession=nil
      runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0
      if result.caravanEntry then
          caravanSession=CrowCaravanArea.restore(runtime.saveData)
          runtime.dialogue={speaker="CARAVAN",text="Three merchant wagons. Trading available at each stall.",timer=5}
      end
      ui.playSfx('doors')
  end

  return {
      resetStopSludges=resetStopSludges,
      acceptParty=acceptParty,
      ensureStopLayout=ensureStopLayout,
      ensureHouseItems=ensureHouseItems,
      itemIsHere=itemIsHere,
      setupNPC=setupNPC,
      update=update,
      attackStopSludge=attackStopSludge,
      attackExpeditionMob=expedition.attack,
      fieldState=expedition.fieldState,
      presentFieldAttack=expedition.presentAttack,
      presentExpeditionAssistance=expedition.presentAssistance,
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
      rangeInput=rangeInput,
      rangeUpdate=rangeUpdate,
      rangeCommandState=rangeCommandState,
      closeSharedRange=closeSharedRange,
      drawShootingRangeSpot=drawShootingRangeSpot,
      drawWildlife=drawWildlife,
  }
end

return {new=new}
