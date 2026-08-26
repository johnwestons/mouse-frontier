local Balance={}

Balance.categoryOrder={"battle","help","fortune","mishap","defense"}
Balance.phaseWeights={
  easy={battle=15,help=25,fortune=30,mishap=15,defense=15},
  medium={battle=20,help=23,fortune=22,mishap=20,defense=15},
  hard={battle=20,help=20,fortune=18,mishap=22,defense=20},
}

function Balance.phaseFor(location)
  location=math.max(1,math.min(50,math.floor(location or 1)))
  return location<=12 and "easy" or (location<=30 and "medium" or "hard")
end

function Balance.encounterChance(location)
  local phase=Balance.phaseFor(location)
  return phase=="easy" and .48 or (phase=="medium" and .58 or .64)
end

function Balance.categoryWeights(location)
  local source=Balance.phaseWeights[Balance.phaseFor(location)]
  local result={}
  for name,weight in pairs(source) do result[name]=weight end
  return result
end

function Balance.pickCategory(location,recentCategories,roll)
  local weights=Balance.categoryWeights(location)
  local previous=recentCategories and recentCategories[#recentCategories]
  if previous and weights[previous] then weights[previous]=0 end
  local total=0
  for _,name in ipairs(Balance.categoryOrder) do total=total+(weights[name] or 0) end
  local target=math.max(0,math.min(.999999,roll or 0))*total
  local cumulative=0
  for _,name in ipairs(Balance.categoryOrder) do
    cumulative=cumulative+(weights[name] or 0)
    if target<cumulative then return name end
  end
  return Balance.categoryOrder[#Balance.categoryOrder]
end

function Balance.alwaysAvailable(choice)
  if not choice then return false end
  if choice.battle or choice.fallback then return true end
  if choice.loseItem or choice.ammoCost then return false end
  return not choice.cost or next(choice.cost)==nil
end

function Balance.audit(definitions)
  local categoryCounts={}
  local eventCount,choiceCount=0,0
  local blockedEvents={}
  for category,pool in pairs(definitions or {}) do
    categoryCounts[category]=#pool
    for _,event in ipairs(pool) do
      eventCount=eventCount+1
      choiceCount=choiceCount+#(event.choices or {})
      local available=false
      for _,choice in ipairs(event.choices or {}) do
        if Balance.alwaysAvailable(choice) then available=true; break end
      end
      if not available then blockedEvents[#blockedEvents+1]=event.id end
    end
  end
  local phaseTotals={}
  for phase,weights in pairs(Balance.phaseWeights) do
    local total=0; for _,weight in pairs(weights) do total=total+weight end
    phaseTotals[phase]=total
  end
  local repeatAvoided=Balance.pickCategory(5,{"battle"},0)~="battle"
  local ready=eventCount==40 and choiceCount==120 and #blockedEvents==0
    and categoryCounts.story==10 and categoryCounts.mystery==5
    and phaseTotals.easy==100 and phaseTotals.medium==100 and phaseTotals.hard==100
    and Balance.encounterChance(1)==.48 and Balance.encounterChance(20)==.58
    and Balance.encounterChance(50)==.64 and repeatAvoided
  return {
    ready=ready,eventCount=eventCount,choiceCount=choiceCount,categoryCounts=categoryCounts,
    blockedEvents=blockedEvents,phaseTotals=phaseTotals,repeatAvoided=repeatAvoided,
    earlyWeights=Balance.categoryWeights(1),lateWeights=Balance.categoryWeights(50),
    encounterChance={easy=.48,medium=.58,hard=.64},curve="events-v1",
  }
end

return Balance
