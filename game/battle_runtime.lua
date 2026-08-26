local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"battle runtime requires "..name)
  if expected then assert(type(value)==expected,"battle runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","battle runtime requires a context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local scenery=required(context,"scenery","table")
  local colors=required(context,"colors","table")
  local characterImages=required(context,"characterImages","table")
  local npcImages=required(context,"npcImages","table")
  local mobImages=required(context,"mobImages","table")
  local characterWalkImages=required(context,"characterWalkImages","table")
  local npcWalkImages=required(context,"npcWalkImages","table")
  local mobAttackImages=required(context,"mobAttackImages","table")
  local mobIdleImages=required(context,"mobIdleImages","table")
  local mobHitImages=required(context,"mobHitImages","table")
  local mobDeathImages=required(context,"mobDeathImages","table")
  local mobWalkImages=required(context,"mobWalkImages","table")
  local mobRangedImages=required(context,"mobRangedImages","table")
  local getCharacterAnimations=required(context,"getCharacterAnimations","function")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local getWorldRenderer=required(context,"getWorldRenderer","function")
  local getScreenUI=required(context,"getScreenUI","function")
  local Catalog=required(context,"catalog","table")
  local Util=required(context,"util","table")
  local BattleRules=required(context,"battleRules","table")
  local Events=required(context,"events","table")
  local BattleController=required(context,"battleController","table")
  local BattleUI=required(context,"battleUI","table")
  local CombatBalance=required(context,"combatBalance","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local PlayerProgression=required(context,"playerProgression","table")
  local writeSave=required(context,"writeSave","function")
  local screenToGame=required(context,"screenToGame","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local enterStop=required(context,"enterStop","function")
  local handleInventoryClick=required(context,"handleInventoryClick","function")

  local function controllerContext()
      return {
          battle=runtime.battle,
          saveData=runtime.saveData,
          Catalog=Catalog,
          Util=Util,
          BattleRules=BattleRules,
          Events=Events,
          CombatBalance=CombatBalance,
          TrainUpgradeBalance=TrainUpgradeBalance,
          PlayerProgression=PlayerProgression,
          BOARD_COLS=7,
          BOARD_ROWS=4,
          playSfx=ui.playSfx,
          weaponSfx=ui.weaponSfx,
          writeSave=writeSave,
      }
  end

  local function beginEncounter(encounter)
      runtime.battle=BattleController.begin(controllerContext(),encounter)
      runtime.battleZoom=1
      runtime.state="battle"
      runtime.inventoryOpen=false
      runtime.mapOpen=false
      runtime.dialogue=nil
      writeSave()
  end

  local function balanceAudit() return CombatBalance.audit() end
  local function playerBalanceAudit() return PlayerProgression.audit() end

  local function setPrompt(text) BattleController.prompt(controllerContext(),text) end
  local function advanceTurn() BattleController.advance(controllerContext()) end
  local function resolveAttack(attacker,target,weaponName) return BattleController.resolve(controllerContext(),attacker,target,weaponName) end
  local function attack(weaponName) BattleController.attack(controllerContext(),weaponName) end
  local function moveTo(q,r) BattleController.move(controllerContext(),q,r) end
  local function heal() BattleController.heal(controllerContext()) end
  local function guard() BattleController.guard(controllerContext()) end
  local function useAbility(kind) BattleController.ability(controllerContext(),kind) end
  local function usePotion(name) return BattleController.usePotion(controllerContext(),name) end
  local function useHealingItem(name) return BattleController.useHealingItem(controllerContext(),name) end

  local function update(dt)
      if runtime.battle then BattleController.update(controllerContext(),dt) end
      return true
  end

  local function uiContext()
      local renderer=getWorldRenderer()
      local screenUI=getScreenUI()
      return {
          W=W,H=H,battle=runtime.battle,battleZoom=runtime.battleZoom,scenery=scenery,colors=colors,mobileEnabled=mobileEnabled(),
          characterImages=characterImages,npcImages=npcImages,mobImages=mobImages,
          characterWalkImages=characterWalkImages,npcWalkImages=npcWalkImages,
          mobAttackImages=mobAttackImages,mobIdleImages=mobIdleImages,mobHitImages=mobHitImages,
          mobDeathImages=mobDeathImages,mobWalkImages=mobWalkImages,mobRangedImages=mobRangedImages,
          animationClock=runtime.animationClock,characterAnimations=getCharacterAnimations(),
          saveData=runtime.saveData,inventoryOpen=runtime.inventoryOpen,ui=ui,playerProgression=PlayerProgression,
          drawLandscape=renderer.drawLandscape,drawGround=renderer.drawGround,
          drawAnimatedCharacter=renderer.drawAnimatedCharacter,button=screenUI.button,screenToGame=screenToGame,pointerPosition=pointerPosition,
          setInventoryOpen=function(value) runtime.inventoryOpen=value end,
          resetInventoryDrag=function() runtime.draggedSlot=nil; runtime.inventoryDragActive=false end,
          handleInventoryClick=handleInventoryClick,
          battleAttack=attack,setBattlePrompt=setPrompt,battleHeal=heal,battleGuard=guard,
          useBattleAbility=useAbility,useBattlePotion=usePotion,advanceBattleTurn=advanceTurn,
          resolveBattleAttack=resolveAttack,battleMoveTo=moveTo,
      }
  end

  local function draw() BattleUI.draw(uiContext()) end

  local function handleMouse(x,y,rightClick)
      local result=BattleUI.handleMouse(uiContext(),x,y,rightClick)
      if result=="missing" then runtime.state="game"
      elseif result=="continue_win" then runtime.battle=nil; runtime.state="game"; enterStop()
      elseif result=="continue_loss" or result=="retreat" then
          runtime.battle=nil; runtime.state="game"; runtime.scene="train"; runtime.npcActor=nil; writeSave()
      end
      return result
  end

  return {
      beginEncounter=beginEncounter,balanceAudit=balanceAudit,playerBalanceAudit=playerBalanceAudit,
      setPrompt=setPrompt,
      advanceTurn=advanceTurn,
      resolveAttack=resolveAttack,
      attack=attack,
      moveTo=moveTo,
      heal=heal,
      guard=guard,
      useAbility=useAbility,
      usePotion=usePotion,
      useHealingItem=useHealingItem,
      update=update,
      draw=draw,
      handleMouse=handleMouse,
  }
end

return {new=new}
