local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"event runtime requires "..name)
  if expected then assert(type(value)==expected,"event runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","event runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local Events=required(context,"events","table")
  local EventUI=required(context,"eventUI","table")
  local Catalog=required(context,"catalog","table")
  local CombatBalance=required(context,"combatBalance","table")
  local EventBalance=required(context,"eventBalance","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local pointIn=required(context,"pointIn","function")
  local writeSave=required(context,"writeSave","function")
  local beginEncounter=required(context,"beginEncounter","function")
  local enterStop=required(context,"enterStop","function")

  local function begin(event)
      if not event then return false end
      runtime.randomEvent=event
      runtime.state="event"
      return event
  end

  local function beginRequired(location)
      local data=runtime.saveData
      if not data then return false end
      location=location or data.location
      if data.events[tostring(location)] then return false end
      return begin(Events.required(data,location))
  end

  local function beginRandom()
      if not runtime.saveData then return false end
      return begin(Events.random(runtime.saveData,EventBalance))
  end

  local function balanceAudit() return EventBalance.audit(Events.definitions) end

  local function canChoose(choice)
      return runtime.saveData and Events.canChoose(runtime.saveData,choice) or false
  end

  local function choose(index)
      local event=runtime.randomEvent
      if not event then return end
      local result=Events.resolve(runtime.saveData,Catalog,event,index,CombatBalance,TrainUpgradeBalance)
      ui.playSfx("menu")
      if result.blocked then return result end
      runtime.randomEvent=nil
      writeSave()
      if result.encounter then
          beginEncounter(result.encounter)
          return result
      end
      runtime.state="game"
      enterStop()
      runtime.dialogue={
          speaker=result.clue and (event.category=="story" and "Family Trail" or "Missing Critter") or "Trail Event",
          text=result.clue or result.summary,
          timer=5,
      }
      return result
  end

  local function handleClick(x,y)
      local index=EventUI.hit(x,y,ui.eventChoices,pointIn)
      if index then return choose(index) end
  end

  return {
      begin=begin,
      beginRequired=beginRequired,
      beginRandom=beginRandom,
      balanceAudit=balanceAudit,
      canChoose=canChoose,
      choose=choose,
      handleClick=handleClick,
  }
end

return {new=new}
