local QuestProgression={}

QuestProgression.offerOrder={"mail","ride","supplies","trade","item","aid","dialogue","none"}
QuestProgression.deliveryKinds={"food","water","medicine","repair","ammunition","recovery"}

local deliveryProfiles={
    food={amount=3,label="3 food portions",objective="FOOD SUPPLIES",request="Settlers farther west are hungry. Could you deliver three food portions?",accepted="Please take three food portions to stop %d. Your backpack food will be used first, then the train pantry.",thanks="Those food supplies will keep us going. Thank you!"},
    water={amount=3,label="3 water supplies",objective="WATER SUPPLIES",request="Our neighbors' well ran dry. Could you deliver three water supplies?",accepted="Please take three water supplies to stop %d. Bottled water will be used first, then the train tank.",thanks="Clean water means everything out here. Thank you!"},
    medicine={amount=2,label="2 medical supplies",objective="MEDICAL SUPPLIES",request="The next settlement is running out of medicine. Could you bring them two medical supplies?",accepted="Please bring two bandages, salves, tonics, splints, or medkits to stop %d.",thanks="This medicine will save lives. Thank you!"},
    repair={amount=3,label="3 repair materials",objective="REPAIR MATERIALS",request="A settlement farther on needs materials to repair its pump. Can you bring three?",accepted="Please bring three repair materials to stop %d. Coal or oil canisters in your pack count before train coal.",thanks="We can get the pump running again. Thank you!"},
    ammunition={amount=8,label="8 rounds of ammunition",objective="AMMUNITION",request="Bandits have been circling the next settlement. Could you spare eight rounds of ammunition?",accepted="Please deliver eight rounds from your ammunition reserves to stop %d.",thanks="Now we can defend the settlement. Thank you!"},
    recovery={amount=1,label="a lost keepsake",objective="RECOVERY",request="A family lost a keepsake near the next settlement. Could you search for it once the area is safe?",accepted="Search the area around stop %d after dealing with any danger there.",thanks="You found it. Our family will treasure this. Thank you!"},
}

function QuestProgression.deliveryProfile(kind)
    return deliveryProfiles[kind] or deliveryProfiles.food
end

local function randomFloat(rng)
    return rng and rng() or love.math.random()
end

function QuestProgression.offerWeights(location)
    local progress=(math.max(1,math.min(50,location or 1))-1)/49
    local result={
        mail=.08-.04*progress,
        ride=.06-.03*progress,
        supplies=.06-.01*progress,
        trade=.04+.03*progress,
        item=.03+.01*progress,
        aid=.04,
        dialogue=.08,
    }
    result.none=1-result.mail-result.ride-result.supplies-result.trade-result.item-result.aid-result.dialogue
    return result
end

function QuestProgression.rollOffer(location,rng)
    local weights=QuestProgression.offerWeights(location); local roll=randomFloat(rng); local total=0
    for _,kind in ipairs(QuestProgression.offerOrder) do
        total=total+weights[kind]
        if roll<=total then return kind end
    end
    return "none"
end

function QuestProgression.rollDelivery(location,rng)
    local progress=(math.max(1,math.min(50,location or 1))-1)/49
    local early={.30,.22,.20,.12,.08,.08}
    local late={.18,.15,.16,.18,.18,.15}
    local roll=randomFloat(rng); local total=0
    for index,kind in ipairs(QuestProgression.deliveryKinds) do
        total=total+early[index]+(late[index]-early[index])*progress
        if roll<=total then return kind end
    end
    return "recovery"
end

local function matchingSlots(data,catalog,predicate,limit)
    local slots={}
    for slot=1,(data.inventoryCapacity or 6) do
        local name=data.inventory and data.inventory[slot]
        if name and predicate(name,catalog.itemEffects and catalog.itemEffects[name]) then
            slots[#slots+1]=slot
            if #slots>=limit then break end
        end
    end
    return slots
end

local function consumeInventoryAndResource(data,catalog,profile,predicate,resource)
    local slots=matchingSlots(data,catalog,predicate,profile.amount)
    local required=profile.amount-#slots
    local stored=(data.resources and data.resources[resource]) or 0
    if stored<required then return {completed=false,shortage=required-stored,kind=resource,label=profile.label} end
    for _,slot in ipairs(slots) do data.inventory[slot]=nil end
    if required>0 then data.resources[resource]=stored-required end
    return {completed=true,inventoryUsed=#slots,resourceUsed=required,label=profile.label}
end

function QuestProgression.consumeCargo(data,catalog,quest)
    local kind=quest.cargoKind or "food"
    local profile=QuestProgression.deliveryProfile(kind)
    if kind=="food" then
        return consumeInventoryAndResource(data,catalog,profile,function(_,effect) return effect and effect.food end,"food")
    elseif kind=="water" then
        return consumeInventoryAndResource(data,catalog,profile,function(_,effect) return effect and effect.water end,"water")
    elseif kind=="medicine" then
        local slots=matchingSlots(data,catalog,function(_,effect) return effect and effect.health end,profile.amount)
        if #slots<profile.amount then return {completed=false,shortage=profile.amount-#slots,kind=kind,label=profile.label} end
        for _,slot in ipairs(slots) do data.inventory[slot]=nil end
        return {completed=true,inventoryUsed=#slots,resourceUsed=0,label=profile.label}
    elseif kind=="repair" then
        return consumeInventoryAndResource(data,catalog,profile,function(name,effect)
            return name=="coal-chunk" or name=="coal-bucket" or (effect and effect.oil)
        end,"coal")
    elseif kind=="ammunition" then
        local available=0
        for name in pairs(catalog.ammoPickupAmounts or {}) do available=available+math.max(0,(data.ammo and data.ammo[name]) or 0) end
        if available<profile.amount then return {completed=false,shortage=profile.amount-available,kind=kind,label=profile.label} end
        local remaining=profile.amount
        local order={"rocks","arrows","ball-bearings","22lr","9mm","45-cal","380-acp","32-acp","30-carbine","12-gauge","556","762x39","8mm"}
        local visited={}
        for _,name in ipairs(order) do
            visited[name]=true
            local held=(data.ammo and data.ammo[name]) or 0; local used=math.min(held,remaining)
            if used>0 then data.ammo[name]=held-used; remaining=remaining-used end
            if remaining<=0 then break end
        end
        if remaining>0 then
            local extras={}; for name in pairs(catalog.ammoPickupAmounts or {}) do if not visited[name] then extras[#extras+1]=name end end
            table.sort(extras)
            for _,name in ipairs(extras) do
                local held=(data.ammo and data.ammo[name]) or 0; local used=math.min(held,remaining)
                if used>0 then data.ammo[name]=held-used; remaining=remaining-used end
                if remaining<=0 then break end
            end
        end
        return {completed=true,inventoryUsed=0,resourceUsed=profile.amount,label=profile.label}
    elseif kind=="recovery" then
        local encounter=data.encounters and data.encounters[tostring(quest.destination)]
        local ready=not encounter or not encounter.hasMob or encounter.resolved
        return {completed=ready,shortage=ready and 0 or 1,kind=kind,label=profile.label}
    end
    return {completed=false,shortage=profile.amount,kind=kind,label=profile.label}
end

function QuestProgression.questDistance(kind,location,rng)
    location=math.max(1,math.min(50,math.floor(location or 1)))
    local remaining=50-location
    if remaining<=0 then return 0 end
    local range=kind=="mail" and {3,8} or (kind=="supplies" and {2,6} or {3,6})
    local low=math.min(remaining,range[1]); local high=math.min(remaining,range[2])
    return low+math.floor(randomFloat(rng)*(high-low+1))
end

function QuestProgression.rewardProfile(kind,distance,trait,destination)
    distance=math.max(1,math.floor(distance or 1)); destination=math.max(1,math.floor(destination or distance+1))
    local base=({mail={coal=1,scrap=2,xp=3},supplies={coal=2,scrap=2,xp=4},food={coal=2,scrap=2,xp=4},water={coal=2,scrap=2,xp=4},medicine={coal=2,scrap=3,xp=5},repair={coal=2,scrap=3,xp=5},ammunition={coal=2,scrap=4,xp=5},recovery={coal=2,scrap=4,xp=6},ride={coal=2,scrap=3,xp=4}})[kind] or {coal=1,scrap=2,xp=3}
    local multiplier=(trait and trait.reward) or 1
    local coal=math.max(1,math.floor((base.coal+math.floor(distance/4))*multiplier+.5))
    local scrap=math.max(1,math.floor((base.scrap+math.ceil(distance/2))*multiplier+.5))
    local rarity=(distance>=7 or destination>=37) and "rare" or ((distance>=4 or destination>=15) and "uncommon" or "common")
    return {kind=kind,distance=distance,coal=coal,scrap=scrap,xp=base.xp+distance,minimumRarity=rarity}
end

function QuestProgression.rollReward(catalog,LootProgression,kind,origin,destination,trait,rng)
    origin=math.max(1,math.floor(origin or 1)); destination=math.max(origin+1,math.floor(destination or origin+1))
    local reward=QuestProgression.rewardProfile(kind,destination-origin,trait,destination)
    reward.item=LootProgression.rollItem(catalog,destination,{minimumRarity=reward.minimumRarity,allowWeapon=false,rng=rng})
        or catalog.questRewardItems[1]
    return reward
end

function QuestProgression.storeRewardItem(data,catalog,Inventory,name,fallback)
    local ammoAmount=catalog.ammoPickupAmounts[name]
    if ammoAmount then
        data.ammo=data.ammo or {}; data.ammo[name]=(data.ammo[name] or 0)+ammoAmount
        return "ammunition"
    end
    local slot=Inventory.firstEmptySlot(data)
    if slot then data.inventory[slot]=name; return "backpack" end
    for _,item in ipairs(data.droppedItems or {}) do
        if item.name=="mailbox-reward" and item.scene=="train" then
            item.storage=item.storage or {}
            for index=1,(catalog.storageCapacities[item.name] or 20) do
                if not item.storage[index] then item.storage[index]=name; item.mailUnread=true; return "mailbox" end
            end
        end
    end
    if fallback then fallback(name); return "local supply crate" end
    return "unclaimed"
end

function QuestProgression.passengerContribution(job,preferredCar)
    local profile
    if job=="greenhouse" then profile={kind="resource",resource="food",amount=preferredCar and 2 or 1,verb="grew"}
    elseif job=="fireman" then profile={kind="resource",resource="coal",amount=preferredCar and 2 or 1,verb="salvaged"}
    elseif job=="medic" then profile={kind="health",amount=preferredCar and 3 or 1,verb="restored"}
    else profile={kind="scrap",amount=preferredCar and 2 or 1,verb="found"} end
    profile.job=job or "scavenger"; profile.preferredCar=preferredCar==true
    return profile
end

function QuestProgression.activeObjectives(data)
    local result={}
    for _,quest in ipairs(data.mailQuests or {}) do if not quest.complete then
        result[#result+1]={kind="mail",destination=quest.destination or 50,label="MAIL delivery to Stop "..tostring(quest.destination or "?")}
    end end
    for _,quest in ipairs(data.supplyQuests or {}) do if not quest.complete then
        local profile=QuestProgression.deliveryProfile(quest.cargoKind)
        result[#result+1]={kind="supplies",destination=quest.destination or 50,label=profile.objective.." to Stop "..tostring(quest.destination or "?").." ("..profile.label..")"}
    end end
    for _,passenger in ipairs(data.passengers or {}) do
        result[#result+1]={kind="ride",destination=passenger.destination or 50,label="PASSENGER ride to Stop "..tostring(passenger.destination or "?")}
    end
    table.sort(result,function(a,b) if a.destination==b.destination then return a.kind<b.kind end return a.destination<b.destination end)
    return result
end

function QuestProgression.summary(data)
    local objectives=QuestProgression.activeObjectives(data)
    return {count=#objectives,first=objectives[1] and objectives[1].label or nil,objectives=objectives}
end

function QuestProgression.audit(catalog,LootProgression,Passengers,Inventory)
    local early,late=QuestProgression.offerWeights(1),QuestProgression.offerWeights(50)
    local near=QuestProgression.rewardProfile("mail",2,{reward=1},3)
    local far=QuestProgression.rewardProfile("mail",8,{reward=1},40)
    local diplomat=QuestProgression.rewardProfile("mail",8,{reward=1.35},40)
    local greenhouseBase=QuestProgression.passengerContribution("greenhouse",false)
    local greenhousePreferred=QuestProgression.passengerContribution("greenhouse",true)
    local scavenger=QuestProgression.passengerContribution("scavenger",false)
    local sample={mailQuests={{recipient="courier",destination=8}},supplyQuests={},passengers={{npc="medic",destination=5}}}
    for index,kind in ipairs(QuestProgression.deliveryKinds) do sample.supplyQuests[index]={destination=5+index,cargoKind=kind} end
    local reward=QuestProgression.rollReward(catalog,LootProgression,"supplies",1,7,{reward=1},function() return .5 end)
    local deliveryData={inventory={"occupied"},inventoryCapacity=1,droppedItems={{name="mailbox-reward",scene="train",storage={}}}}
    local delivery=QuestProgression.storeRewardItem(deliveryData,catalog,Inventory,"food-ration")
    local ammoData={inventory={},inventoryCapacity=1,droppedItems={},ammo={rocks=2}}
    local ammoDelivery=QuestProgression.storeRewardItem(ammoData,catalog,Inventory,"rocks")
    local stockedRide=Passengers.rideLength("medic",20,10,10,0)
    local lowSupplyRide=Passengers.rideLength("medic",20,2,2,0)
    local cargo={inventory={"food-ration","bread-loaf"},inventoryCapacity=2,resources={food=1}}
    local cargoResult=QuestProgression.consumeCargo(cargo,catalog,{cargoKind="food"})
    local shortage={inventory={"food-ration"},inventoryCapacity=1,resources={food=1}}
    local shortageResult=QuestProgression.consumeCargo(shortage,catalog,{cargoKind="food"})
    local legacy={inventory={},inventoryCapacity=1,resources={food=3}}
    local legacyResult=QuestProgression.consumeCargo(legacy,catalog,{cargoStored=true,amount=3})
    local waterCargo={inventory={"water-bottle"},inventoryCapacity=1,resources={water=2}}
    local waterResult=QuestProgression.consumeCargo(waterCargo,catalog,{cargoKind="water"})
    local medicineCargo={inventory={"field-bandage-roll","healing-salve"},inventoryCapacity=2,resources={}}
    local medicineResult=QuestProgression.consumeCargo(medicineCargo,catalog,{cargoKind="medicine"})
    local repairCargo={inventory={"small-oil-canister"},inventoryCapacity=1,resources={coal=2}}
    local repairResult=QuestProgression.consumeCargo(repairCargo,catalog,{cargoKind="repair"})
    local ammoCargo={inventory={},inventoryCapacity=1,resources={},ammo={rocks=5,arrows=4}}
    local ammoResult=QuestProgression.consumeCargo(ammoCargo,catalog,{cargoKind="ammunition"})
    local recoveryCargo={inventory={},resources={},encounters={["9"]={hasMob=true,resolved=false}}}
    local recoveryBlocked=QuestProgression.consumeCargo(recoveryCargo,catalog,{cargoKind="recovery",destination=9})
    recoveryCargo.encounters["9"].resolved=true
    local recoveryResult=QuestProgression.consumeCargo(recoveryCargo,catalog,{cargoKind="recovery",destination=9})
    local rolls={}
    for _,roll in ipairs({.05,.33,.52,.68,.82,.95}) do rolls[QuestProgression.rollDelivery(25,function() return roll end)]=true end
    local rollCount=0; for _ in pairs(rolls) do rollCount=rollCount+1 end
    local totalEarly,totalLate=0,0
    for _,kind in ipairs(QuestProgression.offerOrder) do totalEarly=totalEarly+early[kind]; totalLate=totalLate+late[kind] end
    local ready=math.abs(totalEarly-1)<.0001 and math.abs(totalLate-1)<.0001
        and early.mail>late.mail and early.ride>late.ride and late.trade>early.trade
        and early.none>=.5999 and late.none>=.6399 and early.item>0 and late.aid>0 and early.dialogue==.08 and late.dialogue==.08
        and far.scrap>near.scrap and far.xp>near.xp and diplomat.scrap>far.scrap
        and far.minimumRarity=="rare" and reward.item~=nil
        and greenhousePreferred.amount>greenhouseBase.amount and scavenger.kind=="scrap"
        and #QuestProgression.activeObjectives(sample)==8 and stockedRide>lowSupplyRide
        and delivery=="mailbox" and deliveryData.droppedItems[1].mailUnread and deliveryData.droppedItems[1].storage[1]=="food-ration"
        and ammoDelivery=="ammunition" and ammoData.ammo.rocks==2+(catalog.ammoPickupAmounts.rocks or 0)
        and #QuestProgression.deliveryKinds==6 and rollCount==6
        and cargoResult.completed and cargoResult.inventoryUsed==2 and cargoResult.resourceUsed==1 and cargo.resources.food==0
        and not shortageResult.completed and shortage.inventory[1]=="food-ration" and shortage.resources.food==1
        and legacyResult.completed and legacy.resources.food==0
        and waterResult.completed and waterResult.inventoryUsed==1 and waterResult.resourceUsed==2 and waterCargo.resources.water==0
        and medicineResult.completed and medicineCargo.inventory[1]==nil and medicineCargo.inventory[2]==nil
        and repairResult.completed and repairResult.inventoryUsed==1 and repairResult.resourceUsed==2 and repairCargo.resources.coal==0
        and ammoResult.completed and ammoCargo.ammo.rocks==0 and ammoCargo.ammo.arrows==1
        and not recoveryBlocked.completed and recoveryResult.completed
    return {ready=ready,earlyWeights=early,lateWeights=late,nearReward=near,farReward=far,diplomatReward=diplomat,
        greenhouseBase=greenhouseBase,greenhousePreferred=greenhousePreferred,scavenger=scavenger,objectiveCount=#QuestProgression.activeObjectives(sample),
        stockedRide=stockedRide,lowSupplyRide=lowSupplyRide,rewardItem=reward.item,mailboxDelivery=delivery,ammoDelivery=ammoDelivery,
        earlyRequestRate=1-early.none,lateRequestRate=1-late.none,deliveryKinds=#QuestProgression.deliveryKinds,
        foodInventoryUsed=cargoResult.inventoryUsed,foodStorageUsed=cargoResult.resourceUsed,atomicShortage=not shortageResult.completed,
        legacyStorageUsed=legacyResult.resourceUsed,waterMixed=waterResult.completed,medicineReady=medicineResult.completed,
        repairMixed=repairResult.completed,ammunitionReady=ammoResult.completed,recoveryGated=not recoveryBlocked.completed and recoveryResult.completed,
        curve="quest-v5"}
end

return QuestProgression
