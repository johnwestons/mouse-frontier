local function required(owner,ownerName,name,expected)
  local value=owner[name]
  assert(value~=nil,"smoke composition requires "..ownerName.."."..name)
  if expected then
    assert(type(value)==expected,"smoke composition "..ownerName.."."..name.." must be a "..expected)
  end
  return value
end

local function new(context)
  assert(type(context)=="table","smoke composition requires an explicit context")
  local SmokePlaythrough=required(context,"context","playthrough","table")
  local state=required(context,"context","state","table")
  local domain=required(context,"context","domain","table")
  local services=required(context,"context","services","table")
  local graphs=required(context,"context","graphs","table")

  local runtime=required(state,"state","runtime","table")
  local ui=required(state,"state","ui","table")
  local characters=required(state,"state","characters","table")
  local maintenanceSession=required(state,"state","maintenanceSession","table")
  local session=required(state,"state","session","table")
  local screens=required(state,"state","screens","table")
  local car=required(state,"state","car","table")

  local currentSaveVersion=required(domain,"domain","currentSaveVersion","number")
  local SaveSchema=required(domain,"domain","saveSchema","table")
  local Catalog=required(domain,"domain","catalog","table")
  local Roster=required(domain,"domain","roster","table")
  local NpcRelationships=required(domain,"domain","npcRelationships","table")
  local Accessibility=required(domain,"domain","accessibility","table")
  local Assets=required(domain,"domain","assets","table")
  local Save=required(domain,"domain","save","table")
  local Maintenance=required(domain,"domain","maintenance","table")
  local Train=required(domain,"domain","train","table")
  local Events=required(domain,"domain","events","table")
  local BattleRules=required(domain,"domain","battleRules","table")
  local Intro=required(domain,"domain","intro","table")
  local FirstAid=required(domain,"domain","firstAid","table")
  local Audio=required(domain,"domain","audio","table")
  local AudioCatalog=required(domain,"domain","audioCatalog","table")
  local AudioSelfTest=required(domain,"domain","audioSelfTest","table")
  local FinaleProgression=required(domain,"domain","finaleProgression","table")
  local StopHelpProgression=required(domain,"domain","stopHelpProgression","table")
  local HelpQuestSession=required(domain,"domain","helpQuestSession","table")
  local ShootingRange=required(domain,"domain","shootingRange","table")
  local CrowCaravans=required(domain,"domain","crowCaravans","table")
  local CrowCaravanArea=required(domain,"domain","crowCaravanArea","table")
  local MerchantTrade=required(domain,"domain","merchantTrade","table")

  local presentationRuntime=required(services,"services","presentationRuntime","table")
  local startupRuntime=required(services,"services","startupRuntime","table")
  local persistenceRuntime=required(services,"services","persistenceRuntime","table")
  local audioRuntime=required(services,"services","audioRuntime","table")
  local screenFlow=required(services,"services","screenFlow","table")
  local mobileRuntime=required(services,"services","mobileRuntime","table")
  local sessionBootstrap=required(services,"services","sessionBootstrap","table")
  local worldScene=required(services,"services","worldScene","table")
  local battleRuntime=required(services,"services","battleRuntime","table")
  local inventoryActions=required(services,"services","inventoryActions","table")
  local eventRuntime=required(services,"services","eventRuntime","table")
  local journeyRules=required(services,"services","journeyRules","table")

  local content=required(graphs,"graphs","content","table")
  local views=required(graphs,"graphs","views","table")
  local adventure=required(graphs,"graphs","adventure","table")
  local platform=required(graphs,"graphs","platform","table")
  local input=required(graphs,"graphs","input","table")
  local world=required(graphs,"graphs","world","table")
  local startup=required(graphs,"graphs","startup","table")
  local serviceRegistry=required(graphs,"graphs","serviceRegistry","table")
  local applicationComposition=required(graphs,"graphs","applicationComposition","table")

  local composition={}
  function composition.caravanAudit()
    local economy=CrowCaravans.audit(Catalog)
    local area=CrowCaravanArea.audit()
    local art=CrowCaravanArea.validateAssets(content.scenery.crowCaravanAssets)
    local trade=MerchantTrade.audit(Catalog)
    local flow={entered=false,traderSelected=false,tradeOpened=false,reloadIsolated=false,purchased=false,
      resaleStocked=false,resalePaged=false,resalePurchased=false,resalePersisted=false,
      returnVisibleDuringGreeting=false,returnVisibleDuringTrade=false,returnVisibleAcrossOverlays=false,
      returnControlLarge=false,overlaysCleared=false,returned=false,returnedDuringTrade=false,positionRestored=false}
    local original={
      state=runtime.state,saveData=runtime.saveData,player=runtime.player,scene=runtime.scene,npcActor=runtime.npcActor,
      dialogue=runtime.dialogue,tradeOpen=runtime.tradeOpen,tradeNPC=runtime.tradeNPC,
      tradeMerchantId=runtime.tradeMerchantId,tradeMessage=runtime.tradeMessage,tradeBuyPage=runtime.tradeBuyPage,tradeSellPage=runtime.tradeSellPage,
      inventoryOpen=runtime.inventoryOpen,mapOpen=runtime.mapOpen,chestOpen=runtime.chestOpen,activeChest=runtime.activeChest,
      draggedSlot=runtime.draggedSlot,inventoryDragActive=runtime.inventoryDragActive,giftOpen=runtime.giftOpen,giftSlot=runtime.giftSlot,
      editMode=runtime.editMode,editedItem=runtime.editedItem,editDragging=runtime.editDragging,
      trainUpgradeOpen=runtime.trainUpgradeOpen,poseMenu=runtime.poseMenu,helpDialogue=runtime.helpDialogue,
      questOffer=runtime.questOffer,firstAid=runtime.firstAid,shootingRange=runtime.shootingRange,
      travelConfirm=runtime.travelConfirm,exitPrompt=runtime.exitPrompt,
      optionsOpen=ui.optionsOpen,radioOpen=ui.radioOpen,mobileMenuOpen=ui.mobileMenuOpen,editSliderDrag=ui.editSliderDrag,
    }
    local ok,errorMessage=xpcall(function()
      local data=sessionBootstrap.newSave(characters[1])
      local stop=data.crowCaravans.scheduledStops[1]
      local player={x=480,y=600,facing=1,velocityX=0,velocityY=0,intentX=1,intentY=0}
      data.location=stop; data.scene="stop"; data.scrap=999
      runtime.state="game"; runtime.saveData=data; runtime.player=player; runtime.scene="stop"
      worldScene.setupNPC()
      local entrance=worldScene.currentCaravanInteraction()
      assert(entrance and entrance.action=="enterCaravan","scheduled stop has no caravan entrance")
      player.x,player.y=entrance.x,entrance.y
      local returnX,returnY=player.x,player.y
      flow.entered=worldScene.activateCaravanInteraction(entrance)==true and runtime.scene=="caravan"
      views.gameplayHUD.draw()
      flow.returnVisibleDuringGreeting=runtime.dialogue~=nil and ui.returnStop~=nil
      local anchor=CrowCaravanArea.merchantDefinitions[1]
      player.x,player.y=anchor.x,anchor.y
      local interaction=worldScene.currentCaravanInteraction()
      flow.traderSelected=interaction and interaction.action=="trade" and interaction.merchantId==anchor.id or false
      flow.tradeOpened=worldScene.activateCaravanInteraction(interaction)==true and runtime.tradeOpen==true
      views.gameplayHUD.draw()
      flow.returnVisibleDuringTrade=runtime.tradeOpen==true and ui.returnStop~=nil
      local reloaded=assert(SaveSchema.copy(data))
      runtime.saveData=reloaded; data=reloaded
      local source=worldScene.currentTradeSource()
      local reloadedCamp=data.crowCaravans.camps[tostring(stop)]
      flow.reloadIsolated=source and source.stock~=reloadedCamp.merchants[1].listings
        and source.stock[1]==reloadedCamp.merchants[1].listings[1] or false
      local before=source and source.stock and source.stock[1] and source.stock[1].quantity
      local purchase=MerchantTrade.buy(data,Catalog,source,1)
      flow.purchased=purchase.ok==true and source.stock[1].quantity==before-1
      views.gameplayHUD.draw()
      local saleControl=ui.tradeSell and ui.tradeSell[1]
      if saleControl then
        local saleX,saleY=saleControl.x+saleControl.w/2,saleControl.y+saleControl.h/2
        if mobileRuntime.isEnabled() then
          love.touchpressed("smoke-caravan-sale",saleX,saleY); love.touchreleased("smoke-caravan-sale",saleX,saleY)
        else input.gameplayInput.mousepressed(saleX,saleY,1,false,1) end
      end
      local resaleCamp=data.crowCaravans.camps[tostring(stop)]
      local resale=resaleCamp.resaleStock and resaleCamp.resaleStock[1]
      local resaleId=resale and resale.id
      flow.resaleStocked=data.inventory[1]==nil and resale and resale.item=="orange-rose-vase" and resale.quantity==1 or false
      views.gameplayHUD.draw()
      local nextControl=ui.tradeBuyNext
      if nextControl then
        local nextX,nextY=nextControl.x+nextControl.w/2,nextControl.y+nextControl.h/2
        if mobileRuntime.isEnabled() then
          love.touchpressed("smoke-caravan-buy-page",nextX,nextY); love.touchreleased("smoke-caravan-buy-page",nextX,nextY)
        else input.gameplayInput.mousepressed(nextX,nextY,1,false,1) end
      end
      views.gameplayHUD.draw()
      local resaleControl=ui.tradeBuy and ui.tradeBuy[5]
      flow.resalePaged=runtime.tradeBuyPage==1 and resaleControl~=nil
      if resaleControl then
        local buyX,buyY=resaleControl.x+resaleControl.w/2,resaleControl.y+resaleControl.h/2
        if mobileRuntime.isEnabled() then
          love.touchpressed("smoke-caravan-buyback",buyX,buyY); love.touchreleased("smoke-caravan-buyback",buyX,buyY)
        else input.gameplayInput.mousepressed(buyX,buyY,1,false,1) end
      end
      flow.resalePurchased=data.inventory[1]=="orange-rose-vase" and resale.quantity==0
      local persistedData=assert(SaveSchema.copy(data))
      local persistedCamp=assert(CrowCaravans.ensureCamp(persistedData,Catalog,stop))
      local persistedResale=persistedCamp.resaleStock and persistedCamp.resaleStock[1]
      flow.resalePersisted=persistedResale and persistedResale.id==resaleId and persistedResale.quantity==0 or false
      runtime.inventoryOpen=true; runtime.mapOpen=true
      runtime.dialogue={speaker="Overlay audit",text="The exit must remain available.",timer=5}
      runtime.tradeOpen=true; runtime.trainUpgradeOpen=true; runtime.poseMenu=true
      ui.optionsOpen=true
      views.gameplayHUD.draw()
      flow.returnVisibleAcrossOverlays=ui.returnStop~=nil
      local exitControl=assert(ui.returnStop,"caravan return control disappeared behind an overlay")
      flow.returnControlLarge=exitControl.w>=(mobileRuntime.isEnabled() and 220 or 140)
          and exitControl.h>=(mobileRuntime.isEnabled() and 64 or 32)
      local exitX,exitY=exitControl.x+exitControl.w/2,exitControl.y+exitControl.h/2
      if mobileRuntime.isEnabled() then
        love.touchpressed("smoke-caravan-return",exitX,exitY)
        love.touchreleased("smoke-caravan-return",exitX,exitY)
        flow.returnInput="touch"
      else
        input.gameplayInput.mousepressed(exitX,exitY,1,false,1)
        flow.returnInput="mouse"
      end
      flow.returnedDuringTrade=runtime.tradeOpen==false and runtime.scene=="stop"
      flow.overlaysCleared=not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue
        and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.poseMenu and not ui.optionsOpen
      flow.returned=flow.returnedDuringTrade and runtime.scene=="stop"
      flow.positionRestored=math.abs(player.x-returnX)<.01 and math.abs(player.y-returnY)<.01
    end,debug.traceback)
    runtime.state=original.state; runtime.saveData=original.saveData; runtime.player=original.player; runtime.scene=original.scene
    runtime.npcActor=original.npcActor; runtime.dialogue=original.dialogue; runtime.tradeOpen=original.tradeOpen
    runtime.tradeNPC=original.tradeNPC; runtime.tradeMerchantId=original.tradeMerchantId
    runtime.tradeMessage=original.tradeMessage; runtime.tradeBuyPage=original.tradeBuyPage; runtime.tradeSellPage=original.tradeSellPage
    runtime.inventoryOpen=original.inventoryOpen; runtime.mapOpen=original.mapOpen; runtime.chestOpen=original.chestOpen
    runtime.activeChest=original.activeChest; runtime.draggedSlot=original.draggedSlot; runtime.inventoryDragActive=original.inventoryDragActive
    runtime.giftOpen=original.giftOpen; runtime.giftSlot=original.giftSlot; runtime.editMode=original.editMode
    runtime.editedItem=original.editedItem; runtime.editDragging=original.editDragging
    runtime.trainUpgradeOpen=original.trainUpgradeOpen; runtime.poseMenu=original.poseMenu
    runtime.helpDialogue=original.helpDialogue; runtime.questOffer=original.questOffer; runtime.firstAid=original.firstAid
    runtime.shootingRange=original.shootingRange; runtime.travelConfirm=original.travelConfirm; runtime.exitPrompt=original.exitPrompt
    ui.optionsOpen=original.optionsOpen; ui.radioOpen=original.radioOpen; ui.mobileMenuOpen=original.mobileMenuOpen
    ui.editSliderDrag=original.editSliderDrag
    flow.error=ok and nil or errorMessage
    flow.ready=ok and flow.entered and flow.traderSelected and flow.tradeOpened and flow.reloadIsolated
      and flow.purchased and flow.resaleStocked and flow.resalePaged and flow.resalePurchased and flow.resalePersisted
      and flow.returnVisibleDuringGreeting and flow.returnVisibleDuringTrade
      and flow.returnVisibleAcrossOverlays and flow.returnControlLarge and flow.overlaysCleared
      and flow.returned and flow.returnedDuringTrade and flow.positionRestored
    return {ready=economy.ready and area.ready and art.ready and trade.ready and flow.ready,
      economy=economy,area=area,art=art,trade=trade,flow=flow}
  end
  function composition.install()
    return SmokePlaythrough.install({
      runtime=runtime,ui=ui,characters=characters,maintenanceSession=maintenanceSession,
      session=session,screens=screens,car=car,currentSaveVersion=currentSaveVersion,
      saveSchema=SaveSchema,catalog=Catalog,assets=Assets,save=Save,maintenance=Maintenance,
      events=Events,battleRules=BattleRules,presentationRuntime=presentationRuntime,
      firstAid=FirstAid,
      startupRuntime=startupRuntime,persistenceRuntime=persistenceRuntime,audioRuntime=audioRuntime,screenFlow=screenFlow,
      contentRegistry=content,viewComposition=views,adventureComposition=adventure,
      platformComposition=platform,inputComposition=input,worldSessionComposition=world,
      startupComposition=startup,serviceRegistry=serviceRegistry,smokeComposition=composition,
      applicationComposition=applicationComposition,
      audioAudit=function() return AudioSelfTest.run(Audio,AudioCatalog) end,
      trainPresentationAudit=function() return Train.audit(car,960) end,
      finaleAudit=function() return FinaleProgression.audit(StopHelpProgression,Maintenance) end,
      shootingRangeAudit=function() return ShootingRange.audit(Catalog) end,
      caravanAudit=composition.caravanAudit,
      helpQuestAudit=function() return HelpQuestSession.audit() end,
      relationshipAudit=function() return NpcRelationships.audit() end,
      characterIdentityAudit=function() return Catalog.characterIdentityAudit(characters,Roster) end,
      accessibilityAudit=function() return Accessibility.audit() end,
      getMobileControls=mobileRuntime.get,createIntro=function() return Intro.new(10) end,
      newSave=sessionBootstrap.newSave,enterGame=sessionBootstrap.enterGame,
      ensureStopLayout=worldScene.ensureStopLayout,setupNPC=worldScene.setupNPC,
      beginEncounter=battleRuntime.beginEncounter,consumeSelected=inventoryActions.consumeSelected,
      balanceAudit=journeyRules.balanceAudit,combatBalanceAudit=battleRuntime.balanceAudit,upgradeBalanceAudit=journeyRules.upgradeBalanceAudit,
      battleGridAudit=battleRuntime.gridAudit,
      playerBalanceAudit=battleRuntime.playerBalanceAudit,
      lootBalanceAudit=inventoryActions.balanceAudit,
      questBalanceAudit=journeyRules.questBalanceAudit,
      helpBalanceAudit=journeyRules.helpBalanceAudit,
      beginRandomEvent=eventRuntime.beginRandom,eventBalanceAudit=eventRuntime.balanceAudit,
      resolveEventChoice=eventRuntime.choose,advanceBattleTurn=battleRuntime.advanceTurn,
      battleAttack=battleRuntime.attack,resolveBattleAttack=battleRuntime.resolveAttack,
    })
  end
  function composition.status()
    return {ready=type(composition.install)=="function",groupCount=4}
  end
  return composition
end

return {new=new}
