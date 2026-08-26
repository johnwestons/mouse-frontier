local QuestProgression={}

QuestProgression.offerOrder={"mail","ride","supplies","trade","item","aid","none"}

local function randomFloat(rng)
    return rng and rng() or love.math.random()
end

function QuestProgression.offerWeights(location)
    local progress=(math.max(1,math.min(50,location or 1))-1)/49
    local result={
        mail=.10-.04*progress,
        ride=.07-.03*progress,
        supplies=.06-.01*progress,
        trade=.04+.03*progress,
        item=.06+.01*progress,
        aid=.07,
    }
    result.none=1-result.mail-result.ride-result.supplies-result.trade-result.item-result.aid
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
    local base=({mail={coal=1,scrap=2,xp=3},supplies={coal=2,scrap=2,xp=4},ride={coal=2,scrap=3,xp=4}})[kind] or {coal=1,scrap=2,xp=3}
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
        result[#result+1]={kind="supplies",destination=quest.destination or 50,label="SUPPLIES to Stop "..tostring(quest.destination or "?").." ("..tostring(quest.amount or 3).." food)"}
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
    local sample={mailQuests={{recipient="courier",destination=8}},supplyQuests={{destination=6,amount=3}},passengers={{npc="medic",destination=5}}}
    local reward=QuestProgression.rollReward(catalog,LootProgression,"supplies",1,7,{reward=1},function() return .5 end)
    local deliveryData={inventory={"occupied"},inventoryCapacity=1,droppedItems={{name="mailbox-reward",scene="train",storage={}}}}
    local delivery=QuestProgression.storeRewardItem(deliveryData,catalog,Inventory,"food-ration")
    local ammoData={inventory={},inventoryCapacity=1,droppedItems={},ammo={rocks=2}}
    local ammoDelivery=QuestProgression.storeRewardItem(ammoData,catalog,Inventory,"rocks")
    local stockedRide=Passengers.rideLength("medic",20,10,10,0)
    local lowSupplyRide=Passengers.rideLength("medic",20,2,2,0)
    local totalEarly,totalLate=0,0
    for _,kind in ipairs(QuestProgression.offerOrder) do totalEarly=totalEarly+early[kind]; totalLate=totalLate+late[kind] end
    local ready=math.abs(totalEarly-1)<.0001 and math.abs(totalLate-1)<.0001
        and early.mail>late.mail and early.ride>late.ride and late.trade>early.trade
        and early.none>=.5999 and late.none>=.6399 and early.item>0 and late.aid>0
        and far.scrap>near.scrap and far.xp>near.xp and diplomat.scrap>far.scrap
        and far.minimumRarity=="rare" and reward.item~=nil
        and greenhousePreferred.amount>greenhouseBase.amount and scavenger.kind=="scrap"
        and #QuestProgression.activeObjectives(sample)==3 and stockedRide>lowSupplyRide
        and delivery=="mailbox" and deliveryData.droppedItems[1].mailUnread and deliveryData.droppedItems[1].storage[1]=="food-ration"
        and ammoDelivery=="ammunition" and ammoData.ammo.rocks==2+(catalog.ammoPickupAmounts.rocks or 0)
    return {ready=ready,earlyWeights=early,lateWeights=late,nearReward=near,farReward=far,diplomatReward=diplomat,
        greenhouseBase=greenhouseBase,greenhousePreferred=greenhousePreferred,scavenger=scavenger,objectiveCount=#QuestProgression.activeObjectives(sample),
        stockedRide=stockedRide,lowSupplyRide=lowSupplyRide,rewardItem=reward.item,mailboxDelivery=delivery,ammoDelivery=ammoDelivery,
        earlyRequestRate=1-early.none,lateRequestRate=1-late.none,curve="quest-v3"}
end

return QuestProgression
