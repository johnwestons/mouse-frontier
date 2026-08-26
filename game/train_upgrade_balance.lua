local Balance={}

Balance.baseResourceCapacity=20
Balance.carCatalog={
  {id="coal-hauler",name="Coal Hauler",cost=20,unlockStop=4,description="Coal capacity +10"},
  {id="storage",name="Storage Car",cost=22,unlockStop=8,description="Food and water capacity +10"},
  {id="greenhouse",name="Greenhouse",cost=28,unlockStop=12,description="Produces 2 food after every journey"},
  {id="sleeper",name="Sleeper Car",cost=24,unlockStop=16,description="Halves passenger supply load"},
  {id="medical",name="Medical Car",cost=30,unlockStop=22,description="Restores 3 health after every journey"},
  {id="navigator",name="Navigator Car",cost=34,unlockStop=28,description="Reveals terrain and saves coal on hazards"},
}

function Balance.owns(data,id)
  for _,owned in ipairs((data and data.trainCars) or {}) do if owned==id then return true end end
  return false
end

function Balance.resourceCapacity(data,name)
  local capacity=Balance.baseResourceCapacity
  if name=="coal" and Balance.owns(data,"coal-hauler") then capacity=capacity+10 end
  if (name=="food" or name=="water") and Balance.owns(data,"storage") then capacity=capacity+10 end
  return capacity
end

function Balance.addResource(data,name,amount)
  data.resources=data.resources or {}
  local before=data.resources[name] or 0
  amount=amount or 0
  local updated=math.max(0,math.min(Balance.resourceCapacity(data,name),before+amount))
  if amount>=0 then updated=math.max(before,updated) end
  data.resources[name]=updated
  return data.resources[name]-before
end

function Balance.passengerLoad(data,count)
  count=math.max(0,math.floor(count or 0))
  return Balance.owns(data,"sleeper") and math.ceil(count/2) or count
end

function Balance.applyArrival(data)
  local result={food=0,health=0}
  if Balance.owns(data,"greenhouse") then result.food=Balance.addResource(data,"food",2) end
  if Balance.owns(data,"medical") then
    local before=data.health or 0
    data.health=math.min(data.maxHealth or before,before+3)
    result.health=data.health-before
  end
  return result
end


function Balance.navigatorCoalSavings(data,terrain)
  return Balance.owns(data,"navigator") and (terrain=="mountains" or terrain=="ruins") and 1 or 0
end

function Balance.revealsTerrain(data)
  return Balance.owns(data,"navigator")
end

function Balance.carStatus(data,entry)
  local owned=Balance.owns(data,entry.id)
  local locked=(data.location or 1)<(entry.unlockStop or 1)
  local missing=math.max(0,(entry.cost or 0)-(data.scrap or 0))
  return {owned=owned,locked=locked,affordable=not owned and not locked and missing==0,missing=missing,unlockStop=entry.unlockStop or 1}
end

function Balance.engineStatus(data,EngineUpgrades)
  local nextEngine=EngineUpgrades.next(data.engineLevel)
  if not nextEngine then return {maximum=true} end
  local targetLevel=(data.engineLevel or 0)+1
  local unlockStop=nextEngine.unlockStop or 50
  local locked=(data.location or 1)<unlockStop
  local missing=math.max(0,nextEngine.cost-(data.scrap or 0))
  return {entry=nextEngine,locked=locked,affordable=not locked and missing==0,missing=missing,unlockStop=unlockStop,targetLevel=targetLevel}
end

function Balance.purchaseCar(data,entry)
  local status=Balance.carStatus(data,entry)
  if status.owned then return {ok=false,reason="owned",status=status} end
  if status.locked then return {ok=false,reason="locked",status=status} end
  if not status.affordable then return {ok=false,reason="scrap",status=status} end
  data.scrap=data.scrap-entry.cost
  data.trainCars[#data.trainCars+1]=entry.id
  return {ok=true,entry=entry,status=Balance.carStatus(data,entry)}
end

function Balance.purchaseEngine(data,EngineUpgrades)
  local status=Balance.engineStatus(data,EngineUpgrades)
  if status.maximum then return {ok=false,reason="maximum",status=status} end
  if status.locked then return {ok=false,reason="locked",status=status} end
  if not status.affordable then return {ok=false,reason="scrap",status=status} end
  data.scrap=data.scrap-status.entry.cost
  data.engineLevel=status.targetLevel
  return {ok=true,entry=status.entry,status=Balance.engineStatus(data,EngineUpgrades)}
end

function Balance.audit(EngineUpgrades)
  local base={trainCars={"living-car"},resources={food=19,water=19,coal=19},health=5,maxHealth=20,location=50,scrap=999,engineLevel=0}
  local expanded={trainCars={"living-car","coal-hauler","storage","greenhouse","sleeper","medical","navigator"},resources={food=19,water=19,coal=19},health=5,maxHealth=20,location=50,scrap=999,engineLevel=0}
  local arrival=Balance.applyArrival(expanded)
  local carCost=0; local unlocksReady=true
  for index,entry in ipairs(Balance.carCatalog) do carCost=carCost+entry.cost; unlocksReady=unlocksReady and entry.unlockStop==(index==1 and 4 or ({8,12,16,22,28})[index-1]) end
  local engineCost=0; for index=2,#EngineUpgrades.tiers do engineCost=engineCost+EngineUpgrades.tiers[index].cost end
  local carPurchaseData={trainCars={"living-car"},resources={},health=20,maxHealth=20,location=4,scrap=20,engineLevel=0}
  local carPurchase=Balance.purchaseCar(carPurchaseData,Balance.carCatalog[1])
  local enginePurchaseData={trainCars={"living-car"},resources={},health=20,maxHealth=20,location=5,scrap=15,engineLevel=0}
  local enginePurchase=Balance.purchaseEngine(enginePurchaseData,EngineUpgrades)
  local legacyOverflow={trainCars={"living-car"},resources={food=30}}
  local overflowGain=Balance.addResource(legacyOverflow,"food",3)
  local lockedEngine=Balance.engineStatus({location=4,scrap=999,engineLevel=0},EngineUpgrades)
  local ready=#Balance.carCatalog==6 and carCost==158 and engineCost==158 and unlocksReady
    and Balance.resourceCapacity(base,"food")==20 and Balance.resourceCapacity(base,"coal")==20
    and Balance.resourceCapacity(expanded,"food")==30 and Balance.resourceCapacity(expanded,"water")==30
    and Balance.resourceCapacity(expanded,"coal")==30 and Balance.passengerLoad(expanded,3)==2
    and arrival.food==2 and arrival.health==3 and Balance.navigatorCoalSavings(expanded,"mountains")==1
    and Balance.revealsTerrain(expanded) and carPurchase.ok and carPurchaseData.scrap==0
    and enginePurchase.ok and enginePurchaseData.engineLevel==1 and enginePurchaseData.scrap==0
    and overflowGain==0 and legacyOverflow.resources.food==30
    and lockedEngine.locked and lockedEngine.unlockStop==5
  return {ready=ready,carCount=#Balance.carCatalog,carCost=carCost,engineCost=engineCost,
    baseCapacity=Balance.baseResourceCapacity,expandedCapacity={food=Balance.resourceCapacity(expanded,"food"),water=Balance.resourceCapacity(expanded,"water"),coal=Balance.resourceCapacity(expanded,"coal")},
    passengerLoad=Balance.passengerLoad(expanded,3),arrival=arrival,navigatorSavings=Balance.navigatorCoalSavings(expanded,"mountains"),
    firstCarPurchase=carPurchase.ok,firstEnginePurchase=enginePurchase.ok,legacyOverflowPreserved=legacyOverflow.resources.food==30,
    firstEngineUnlock=lockedEngine.unlockStop,curve="train-upgrades-v1"}
end

return Balance
