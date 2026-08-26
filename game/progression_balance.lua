local Balance={}

Balance.resourceCap=30
Balance.passengerSurchargeCap=3
Balance.terrains={"plains","desert","mountains","ruins","forest"}

local function terrainFor(location)
  return Balance.terrains[((math.max(1,location or 1)-1)%#Balance.terrains)+1]
end

local function passengerLoad(data,TrainUpgradeBalance)
  local passengers=#(data.passengers or {})
  local load=TrainUpgradeBalance and TrainUpgradeBalance.passengerLoad(data,passengers) or passengers
  return math.min(Balance.passengerSurchargeCap,load),passengers
end

local function baseCosts(location)
  local leg=math.max(0,(location or 1)-1)
  local terrain=terrainFor(location)
  local terrainCoal=terrain=="mountains" and 2 or (terrain=="ruins" and 1 or 0)
  return 1+math.floor(leg/10),1+math.floor(leg/8),1+math.floor(leg/10)+terrainCoal,terrain
end

function Balance.travelCost(data,EngineUpgrades,Maintenance,defaultTrait,TrainUpgradeBalance)
  local food,water,coal,terrain=baseCosts(data.location)
  local load,passengers=passengerLoad(data,TrainUpgradeBalance)
  local trait=data.trait or defaultTrait or {}
  food,water,coal=EngineUpgrades.applyCosts(data.engineLevel,(food+load)*(trait.food or 1),
    (water+load)*(trait.water or 1),coal*(trait.coal or 1))
  local maintenanceCoal=Maintenance.coalPenalty(data)
  local navigatorSaved=TrainUpgradeBalance and TrainUpgradeBalance.navigatorCoalSavings(data,terrain) or 0
  return {
    food=food,water=water,coal=math.max(1,coal+maintenanceCoal-navigatorSaved),passengers=passengers,
    passengerLoad=load,terrain=terrain,maintenanceCoal=maintenanceCoal,navigatorSaved=navigatorSaved,
  }
end

function Balance.travelStatus(data,cost)
  cost=cost or {food=0,water=0,coal=0}
  local resources=data.resources or {}
  local missing={
    food=math.max(0,cost.food-(resources.food or 0)),
    water=math.max(0,cost.water-(resources.water or 0)),
    coal=math.max(0,cost.coal-(resources.coal or 0)),
  }
  local affordable=missing.food==0 and missing.water==0 and missing.coal==0
  local shortage={}
  for _,name in ipairs({"food","water","coal"}) do
    if missing[name]>0 then shortage[#shortage+1]=missing[name].." "..name end
  end
  return {affordable=affordable,cost=cost,missing=missing,shortage=table.concat(shortage,", ")}
end

function Balance.audit(EngineUpgrades,TrainUpgradeBalance)
  local totals={food=0,water=0,coal=0}
  local maximum={food=0,water=0,coal=0}
  for location=1,49 do
    local food,water,coal=baseCosts(location)
    food,water,coal=EngineUpgrades.applyCosts(0,food,water,coal)
    totals.food,totals.water,totals.coal=totals.food+food,totals.water+water,totals.coal+coal
    maximum.food,maximum.water,maximum.coal=math.max(maximum.food,food),math.max(maximum.water,water),math.max(maximum.coal,coal)
  end
  local shortage=Balance.travelStatus({resources={food=4,water=7,coal=6}},{food=5,water=7,coal=6})
  local shortageDetected=not shortage.affordable and shortage.missing.food==1 and shortage.shortage=="1 food"
  local sleeperLoad=TrainUpgradeBalance and TrainUpgradeBalance.passengerLoad({trainCars={"living-car","sleeper"}},3) or 2
  return {
    ready=totals.food==145 and totals.water==175 and totals.coal==175 and shortageDetected and sleeperLoad==2,
    legs=49,totals=totals,maximum=maximum,resourceCap=Balance.resourceCap,
    curve="milestone-v1",shortageDetected=shortageDetected,sleeperLoad=sleeperLoad,
  }
end

return Balance
