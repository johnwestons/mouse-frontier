local CoopProgression=require("game.coop_progression")
local SavedEvents=require('game.coop_events')
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
  local commands=context.commands

  local function open(mode,id)
      local reply=commands.submit('event.begin',{mode=mode,id=id})
      if not reply.ok then return false,reply.reason end
      SavedEvents.restore(runtime)
      runtime.state='event'
      return runtime.randomEvent
  end

  local function begin(event)
      if not CoopProgression.allowed(runtime,"event.continue") then return false,"host_only" end
      if not event then return false end
      if commands then return open('named',event.id) end
      runtime.randomEvent=event
      runtime.state="event"
      return event
  end

  local function beginRequired(location)
      if not CoopProgression.allowed(runtime,"event.continue") then return false,"host_only" end
      local data=runtime.saveData
      if not data then return false end
      location=location or data.location
      if data.events[tostring(location)] then return false end
      if commands then
          if location~=data.location then return false,'event_unavailable' end
          return open('required')
      end
      return begin(Events.required(data,location))
  end

  local function beginRandom()
      if not CoopProgression.allowed(runtime,"event.continue") then return false,"host_only" end
      if not runtime.saveData then return false end
      if commands then return open('random') end
      return begin(Events.random(runtime.saveData,EventBalance))
  end

  local function balanceAudit() return EventBalance.audit(Events.definitions) end

  local function canChoose(choice)
      return not runtime.eventOutcome and runtime.saveData and Events.canChoose(runtime.saveData,choice,Catalog) or false
  end

  local function finish(event,result)
      runtime.randomEvent=nil; runtime.eventOutcome=nil
      runtime.state='game'
      if result.trainAmbush then return result end
      if result.encounter then beginEncounter(result.encounter); return result end
      enterStop()
      runtime.dialogue={speaker=result.clue and (event.category=='story' and 'Family Trail' or 'Missing Critter') or 'Trail Event',
          text=result.clue or result.summary,timer=5}
      return result
  end

  local function continueEvent()
      if not CoopProgression.allowed(runtime,'event.continue') then return false,'host_only' end
      local event=runtime.randomEvent
      if not event or not runtime.eventOutcome or not commands then return false,'event_unavailable' end
      local reply=commands.submit('event.continue',{id=event.id})
      if not reply.ok then return false,reply.reason end
      -- Retry owns the failed checkpoint. Leave Train can finish the staged
      -- encounter/scene handoff afterward, without repeating choice effects.
      if reply.savePending then runtime.randomEvent=nil; runtime.eventOutcome=nil; return reply.result.outcome end
      return finish(event,reply.result.outcome)
  end

  local function choose(index)
      if not CoopProgression.allowed(runtime,"event.choose") then return false,"host_only" end
      local event=runtime.randomEvent
      if not event then return end
      if commands then
          local reply=commands.submit('event.choose',{id=event.id,index=index})
          if not reply.ok then return false,reply.reason end
          SavedEvents.restore(runtime); ui.playSfx('menu')
          return reply.result.outcome
      end
      local result=Events.resolve(runtime.saveData,Catalog,event,index,CombatBalance,TrainUpgradeBalance)
      ui.playSfx("menu")
      if result.blocked then return result end
      writeSave()
      return finish(event,result)
  end

  local function handleClick(x,y)
      if runtime.eventOutcome then
          if ui.eventContinue and pointIn(x,y,ui.eventContinue) then return continueEvent() end
          return false
      end
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
      continueEvent=continueEvent,
      handleClick=handleClick,
  }
end

return {new=new}
