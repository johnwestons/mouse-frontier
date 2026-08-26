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
  local Assets=required(domain,"domain","assets","table")
  local Save=required(domain,"domain","save","table")
  local Maintenance=required(domain,"domain","maintenance","table")
  local Events=required(domain,"domain","events","table")
  local BattleRules=required(domain,"domain","battleRules","table")
  local Intro=required(domain,"domain","intro","table")

  local presentationRuntime=required(services,"services","presentationRuntime","table")
  local startupRuntime=required(services,"services","startupRuntime","table")
  local persistenceRuntime=required(services,"services","persistenceRuntime","table")
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
      startupRuntime=startupRuntime,persistenceRuntime=persistenceRuntime,screenFlow=screenFlow,
      contentRegistry=content,viewComposition=views,adventureComposition=adventure,
      platformComposition=platform,inputComposition=input,worldSessionComposition=world,
      startupComposition=startup,serviceRegistry=serviceRegistry,smokeComposition=composition,
      applicationComposition=applicationComposition,
      getMobileControls=mobileRuntime.get,createIntro=function() return Intro.new(10) end,
      newSave=sessionBootstrap.newSave,enterGame=sessionBootstrap.enterGame,
      ensureStopLayout=worldScene.ensureStopLayout,setupNPC=worldScene.setupNPC,
      beginEncounter=battleRuntime.beginEncounter,consumeSelected=inventoryActions.consumeSelected,
      balanceAudit=journeyRules.balanceAudit,combatBalanceAudit=battleRuntime.balanceAudit,upgradeBalanceAudit=journeyRules.upgradeBalanceAudit,
      playerBalanceAudit=battleRuntime.playerBalanceAudit,
      lootBalanceAudit=inventoryActions.balanceAudit,
      questBalanceAudit=journeyRules.questBalanceAudit,
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
