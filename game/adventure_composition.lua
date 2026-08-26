local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"adventure composition requires "..name)
  if expected then assert(type(value)==expected,"adventure composition "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","adventure composition requires an explicit context")
  local BattleRuntime=required(context,"battleRuntimeFactory","table")
  local InventoryActions=required(context,"inventoryActionsFactory","table")
  local JourneyRules=required(context,"journeyRulesFactory","table")
  local EventRuntime=required(context,"eventRuntimeFactory","table")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local content=required(context,"content","table")
  local colors=required(context,"colors","table")
  local car=required(context,"car","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local BattleRules=required(context,"battleRules","table")
  local Events=required(context,"events","table")
  local BattleController=required(context,"battleController","table")
  local BattleUI=required(context,"battleUI","table")
  local CombatBalance=required(context,"combatBalance","table")
  local EventBalance=required(context,"eventBalance","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local LootProgression=required(context,"lootProgression","table")
  local QuestProgression=required(context,"questProgression","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local ProgressionBalance=required(context,"progressionBalance","table")
  local PlayerProgression=required(context,"playerProgression","table")
  local Maintenance=required(context,"maintenance","table")
  local Passengers=required(context,"passengers","table")
  local House=required(context,"house","table")
  local EventUI=required(context,"eventUI","table")
  local writeSave=required(context,"writeSave","function")
  local screenToGame=required(context,"screenToGame","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local setupNPC=required(context,"setupNPC","function")
  local getCharacterAnimations=required(context,"getCharacterAnimations","function")
  local getWorldRenderer=required(context,"getWorldRenderer","function")
  local getScreenUI=required(context,"getScreenUI","function")
  local handleInventoryClick=required(context,"handleInventoryClick","function")

  local battleRuntime,inventoryActions,journeyRules,eventRuntime
  battleRuntime=BattleRuntime.new({
    runtime=runtime,width=W,height=H,ui=ui,scenery=content.scenery,colors=colors,
    characterImages=content.characterImages,npcImages=content.npcImages,mobImages=content.mobImages,
    characterWalkImages=content.characterWalkImages,npcWalkImages=content.npcWalkImages,
    mobAttackImages=content.mobAttackImages,mobIdleImages=content.mobIdleImages,mobHitImages=content.mobHitImages,
    mobDeathImages=content.mobDeathImages,mobWalkImages=content.mobWalkImages,mobRangedImages=content.mobRangedImages,
    getCharacterAnimations=getCharacterAnimations,mobileEnabled=mobileEnabled,
    getWorldRenderer=getWorldRenderer,getScreenUI=getScreenUI,catalog=Catalog,util=Util,
    battleRules=BattleRules,events=Events,battleController=BattleController,battleUI=BattleUI,
    combatBalance=CombatBalance,trainUpgradeBalance=TrainUpgradeBalance,
    playerProgression=PlayerProgression,
    writeSave=writeSave,screenToGame=screenToGame,pointerPosition=pointerPosition,
    enterStop=function(...) return journeyRules.enterStop(...) end,handleInventoryClick=handleInventoryClick,
  })

  inventoryActions=InventoryActions.new({
    runtime=runtime,inventory=Inventory,catalog=Catalog,util=Util,trainUpgradeBalance=TrainUpgradeBalance,lootProgression=LootProgression,writeSave=writeSave,
    useBattleHealingItem=battleRuntime.useHealingItem,useBattlePotion=battleRuntime.usePotion,
  })

  journeyRules=JourneyRules.new({
    runtime=runtime,car=car,inventory=Inventory,catalog=Catalog,engineUpgrades=EngineUpgrades,
    progressionBalance=ProgressionBalance,combatBalance=CombatBalance,eventBalance=EventBalance,trainUpgradeBalance=TrainUpgradeBalance,
    questProgression=QuestProgression,lootProgression=LootProgression,battleRules=BattleRules,
    maintenance=Maintenance,passengers=Passengers,util=Util,house=House,
    ensureStopLayout=ensureStopLayout,setupNPC=setupNPC,writeSave=writeSave,
    beginEncounter=battleRuntime.beginEncounter,
    beginRequiredEvent=function(location) return eventRuntime.beginRequired(location) end,
    beginRandomEvent=function() return eventRuntime.beginRandom() end,
  })

  eventRuntime=EventRuntime.new({
    runtime=runtime,ui=ui,events=Events,eventUI=EventUI,catalog=Catalog,combatBalance=CombatBalance,eventBalance=EventBalance,trainUpgradeBalance=TrainUpgradeBalance,pointIn=Util.pointIn,
    writeSave=writeSave,beginEncounter=battleRuntime.beginEncounter,enterStop=journeyRules.enterStop,
  })

  local adventure={
    battleRuntime=battleRuntime,inventoryActions=inventoryActions,journeyRules=journeyRules,eventRuntime=eventRuntime,
  }
  function adventure.status()
    return {
      ready=type(battleRuntime.beginEncounter)=="function" and type(inventoryActions.consumeSelected)=="function"
        and type(journeyRules.enterStop)=="function" and type(eventRuntime.choose)=="function",
      componentCount=4,
    }
  end
  return adventure
end

return {new=new}
