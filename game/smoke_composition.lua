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
  local StopActivities=required(domain,"domain","stopActivities","table")
  local SludgeContainment=required(domain,"domain","sludgeContainment","table")

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
      stopActivityAudit=function()
        local result=StopActivities.audit(StopHelpProgression); result.sludge=SludgeContainment.audit()
        result.ready=result.ready and result.sludge.ready
        return result
      end,
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
