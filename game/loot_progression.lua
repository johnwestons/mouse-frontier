local LootProgression = {}

LootProgression.rarityOrder={"common","uncommon","rare","legendary"}
LootProgression.rarityRank={common=1,uncommon=2,rare=3,legendary=4}
LootProgression.ammoUnlockTier={rocks=1,arrows=1,["ball-bearings"]=1,["22lr"]=3,["32-acp"]=3,["380-acp"]=4,["9mm"]=4,["45-cal"]=5,["30-carbine"]=5,["12-gauge"]=6,["556"]=7,["762x39"]=8,["8mm"]=8}
LootProgression.itemRarityUnlockTier={common=1,uncommon=1,rare=3,legendary=6}
LootProgression.itemUnlockTier={
    ["patched-canvas-pack"]=2,["compact-sling-pack"]=2,["black-sling-pack"]=3,
    ["bedroll-hiking-pack"]=4,["red-leather-pack"]=5,["weathered-leather-pack"]=6,
    ["frontier-leather-pack"]=7,["scavenger-frame-pack"]=9,
    ["medium-oil-canister"]=3,["large-oil-canister"]=6,
    ["emergency-syringe-case"]=9,
}
LootProgression.materialUnlockTier={
    ["thread-spool"]=1,["fabric-scraps"]=1,["wool-batting"]=1,
    ["canvas-bundle"]=2,["leather-pieces"]=2,["waxed-thread"]=2,["metal-sheet"]=3,
}
local materialPrices={
    ["thread-spool"]=2,["fabric-scraps"]=2,["wool-batting"]=3,
    ["canvas-bundle"]=4,["leather-pieces"]=5,["waxed-thread"]=4,["metal-sheet"]=7,
}

local function randomFloat(rng)
    return rng and rng() or love.math.random()
end

local function randomInt(low,high,rng)
    if high<=low then return low end
    return low+math.floor(randomFloat(rng)*(high-low+1))
end

local function choice(list,rng)
    if not list or #list==0 then return nil end
    return list[randomInt(1,#list,rng)]
end

function LootProgression.locationTier(location)
    location=math.max(1,math.min(50,math.floor(location or 1)))
    return math.min(9,1+math.floor((location-1)/6))
end

function LootProgression.rarityWeights(location)
    local progress=(math.max(1,math.min(50,location or 1))-1)/49
    return {
        common=.78-.43*progress,
        uncommon=.20+.20*progress,
        rare=.018+.22*progress,
        legendary=.002+.01*progress,
    }
end

function LootProgression.rollRarity(location,minimum,rng)
    local weights=LootProgression.rarityWeights(location); local roll=randomFloat(rng); local total=0; local rolled="common"
    for _,rarity in ipairs(LootProgression.rarityOrder) do
        total=total+weights[rarity]
        if roll<=total then rolled=rarity; break end
    end
    local minimumRank=type(minimum)=="number" and minimum or (LootProgression.rarityRank[minimum] or 1)
    return LootProgression.rarityOrder[math.max(LootProgression.rarityRank[rolled],math.max(1,math.min(4,minimumRank)))]
end

function LootProgression.itemRarityAt(location,rarity)
    local tier=LootProgression.locationTier(location)
    local rank=LootProgression.rarityRank[rarity] or 1
    local maximum=1
    for _,candidate in ipairs(LootProgression.rarityOrder) do
        if tier>=(LootProgression.itemRarityUnlockTier[candidate] or 1) then
            maximum=LootProgression.rarityRank[candidate]
        end
    end
    return LootProgression.rarityOrder[math.min(rank,maximum)]
end

local function weaponCandidates(catalog,tier)
    local result={}
    for name,stats in pairs(catalog.weaponStats or {}) do
        if name~="scratch" and not name:find("mob%-") and stats.tier==tier and catalog.weaponCombat[name] then result[#result+1]=name end
    end
    table.sort(result)
    return result
end

function LootProgression.rollWeapon(catalog,location,minimum,rng)
    local rarity=LootProgression.rollRarity(location,minimum,rng)
    local rank=LootProgression.rarityRank[rarity]
    local base=LootProgression.locationTier(location)
    local offsets={{-1,0},{0,1},{1,2},{2,4}}
    local lowOffset,highOffset=offsets[rank][1],offsets[rank][2]
    local low=math.max(1,math.min(9,base+lowOffset)); local high=math.max(low,math.min(9,base+highOffset))
    local target=randomInt(low,high,rng); local candidates=weaponCandidates(catalog,target)
    if #candidates==0 then
        for distance=1,8 do
            candidates=weaponCandidates(catalog,math.max(1,target-distance)); if #candidates>0 then break end
            candidates=weaponCandidates(catalog,math.min(9,target+distance)); if #candidates>0 then break end
        end
    end
    return choice(candidates,rng),rarity,target
end

local function supplyMaximum(kind,tier)
    return kind=="food" and math.min(5,2+math.floor((tier-1)/2)) or math.min(7,3+math.floor((tier-1)/2))
end

local function medicalMaximum(tier)
    return ({5,8,8,12,12,12,12,14,99})[tier] or 99
end

local function itemAvailable(catalog,name,location)
    local tier=LootProgression.locationTier(location)
    local unlockTier=LootProgression.itemUnlockTier[name]
    if catalog.ammoPickupAmounts and catalog.ammoPickupAmounts[name] then
        unlockTier=LootProgression.ammoUnlockTier[name] or 9
    elseif catalog.craftMaterials and catalog.craftMaterials[name] then
        local definition=catalog.craftMaterials[name]
        unlockTier=definition.unlockTier or LootProgression.materialUnlockTier[name] or 1
    end
    if unlockTier and tier<unlockTier then return false end

    local rarity=catalog.rarityFor and catalog.rarityFor(name) or (catalog.itemRarity or {})[name]
    if tier<(LootProgression.itemRarityUnlockTier[rarity] or 1) then return false end

    local effect=(catalog.itemEffects or {})[name]
    if effect then
        for _,kind in ipairs({"food","water"}) do
            if effect[kind] and effect[kind]>supplyMaximum(kind,tier) then return false end
        end
        if effect.health and effect.health>medicalMaximum(tier) then return false end
    end
    return true
end

local function supplyCandidates(catalog,kind,location)
    local result={}; local tier=LootProgression.locationTier(location)
    local maximum=supplyMaximum(kind,tier)
    for name,effect in pairs(catalog.itemEffects or {}) do
        local value=effect[kind]
        if value and not effect.potion and value<=maximum then result[#result+1]=name end
    end
    table.sort(result); return result
end

function LootProgression.rollSupply(catalog,kind,location,rng)
    local candidates=supplyCandidates(catalog,kind,location)
    return choice(candidates,rng) or choice(catalog.lootPools[kind],rng)
end

function LootProgression.rollAmmo(catalog,location,rng)
    local tier=LootProgression.locationTier(location); local candidates={}
    for name in pairs(catalog.ammoPickupAmounts or {}) do if (LootProgression.ammoUnlockTier[name] or 9)<=tier then candidates[#candidates+1]=name end end
    table.sort(candidates); return choice(candidates,rng)
end

function LootProgression.rollItem(catalog,location,options)
    options=options or {}; local rng=options.rng
    local rarity=LootProgression.rollRarity(location,options.minimumRarity,rng)
    local weaponChance=options.weaponChance
    if weaponChance==nil then weaponChance=({common=.05,uncommon=.12,rare=.28,legendary=.40})[rarity] end
    if options.allowWeapon~=false and randomFloat(rng)<weaponChance then
        local weapon=LootProgression.rollWeapon(catalog,location,rarity,rng)
        if weapon then return weapon,rarity,"weapon" end
    end
    local firstRank=LootProgression.rarityRank[LootProgression.itemRarityAt(location,rarity)] or 1
    for rank=firstRank,1,-1 do
        local candidateRarity=LootProgression.rarityOrder[rank]
        local candidates={}
        for _,name in ipairs(catalog.lootPools[candidateRarity] or {}) do
            if itemAvailable(catalog,name,location) then candidates[#candidates+1]=name end
        end
        if #candidates>0 then return choice(candidates,rng),candidateRarity,"item" end
    end
    return nil,rarity,"item"
end

function LootProgression.rollMedical(catalog,location,minimum,rng)
    local rarity=LootProgression.itemRarityAt(location,LootProgression.rollRarity(location,minimum,rng))
    local maximum=math.min(({common=5,uncommon=8,rare=12,legendary=99})[rarity],medicalMaximum(LootProgression.locationTier(location)))
    local candidates={}
    for name,effect in pairs(catalog.itemEffects or {}) do
        if effect.health and not effect.potion and effect.health<=maximum and itemAvailable(catalog,name,location) then candidates[#candidates+1]=name end
    end
    table.sort(candidates); return choice(candidates,rng),rarity
end

function LootProgression.tradeStock(catalog,location,rng)
    local result={}
    result[1]=LootProgression.rollSupply(catalog,"food",location,rng)
    result[2]=LootProgression.rollItem(catalog,location,{minimumRarity="common",allowWeapon=false,rng=rng})
    result[3]=LootProgression.rollItem(catalog,location,{minimumRarity="uncommon",weaponChance=.10,rng=rng})
    result[4]=LootProgression.rollWeapon(catalog,location,"uncommon",rng)
    return result
end

function LootProgression.rollCraftMaterial(catalog,location,rng)
    local candidates={}
    local tier=LootProgression.locationTier(location)
    for name,definition in pairs(catalog.craftMaterials or {}) do
        if (definition.unlockTier or LootProgression.materialUnlockTier[name] or 1)<=tier then
            candidates[#candidates+1]=name
        end
    end
    table.sort(candidates)
    return choice(candidates,rng)
end

function LootProgression.ensureCraftingStock(layout,catalog,location)
    if not layout or type(layout.tradeStock)~="table" or layout.outfitStockVersion==1 then return end
    local tier=LootProgression.locationTier(location)
    local names={}
    for name,definition in pairs(catalog.craftMaterials or {}) do
        if (definition.unlockTier or LootProgression.materialUnlockTier[name] or 1)<=tier then names[#names+1]=name end
    end
    table.sort(names)
    local last=0
    for index in pairs(layout.tradeStock) do if type(index)=="number" then last=math.max(last,index) end end
    for _,name in ipairs(names) do
        last=last+1
        -- Quantities are a merchant listing feature; purchases still deliver
        -- one ordinary material bundle per inventory slot.
        layout.tradeStock[last]={item=name,quantity=3,basePrice=LootProgression.itemPrice(catalog,name)}
    end
    layout.outfitStockVersion=1
end

function LootProgression.qualityRarity(quality)
    if quality=="legendary" then return "legendary" end
    if quality=="rare" then return "rare" end
    if quality=="uncommon" then return "uncommon" end
    if type(quality)=="number" then return ({[1]="common",[2]="uncommon",[3]="rare",[4]="legendary"})[math.max(1,math.min(4,quality))] end
    return nil
end

function LootProgression.itemPrice(catalog,name)
    local material=catalog.craftMaterials and catalog.craftMaterials[name]
    if material then return material.basePrice or materialPrices[name] or 3 end
    local stats=catalog.weaponStats[name]
    if stats then
        local ranged=(catalog.weaponCombat[name] or {}).kind=="ranged" and 2 or 0
        return 4+(stats.tier or 1)*3+ranged
    end
    local wearable=catalog.wearableItems and catalog.wearableItems[name]
    if wearable and wearable.slot=="backpack" then return math.floor(wearable.capacity*2) end
    if wearable and wearable.tier then
        local quality=wearable.quality=="masterwork" and 6 or (wearable.quality=="fine" and 3 or 0)
        return wearable.basePrice or (5+wearable.tier*5+quality)
    end
    local rarity=catalog.rarityFor(name)
    local base=({common=3,uncommon=6,rare=11,legendary=18})[rarity] or 3
    if catalog.ammoPickupAmounts[name] then return base+2 end
    return base
end

function LootProgression.weaponCondition(durability)
    durability=math.max(0,math.min(100,math.floor(tonumber(durability) or 100)))
    if durability==0 then return {durability=0,label="broken",multiplier=0} end
    if durability<=25 then return {durability=durability,label="critical",multiplier=.65} end
    if durability<50 then return {durability=durability,label="worn",multiplier=.78} end
    if durability<75 then return {durability=durability,label="used",multiplier=.90} end
    return {durability=durability,label="sound",multiplier=1}
end

function LootProgression.wearWeapon(data,name,amount)
    if not name or name=="scratch" then return 100 end
    data.weaponDurability=data.weaponDurability or {}
    local before=data.weaponDurability[name]
    if before==nil then before=100 end
    data.weaponDurability[name]=math.max(0,before-math.max(0,math.floor(amount or 1)))
    return data.weaponDurability[name]
end

function LootProgression.repairCost(catalog,name,durability)
    local stats=catalog.weaponStats[name]
    if not stats or name=="scratch" then return 0 end
    durability=math.max(0,math.min(100,math.floor(tonumber(durability) or 100)))
    if durability>=100 then return 0 end
    return math.max(1,math.ceil((100-durability)/20)+math.ceil((stats.tier or 1)/2))
end

local function isPlayerWeapon(catalog,name)
    return type(name)=="string" and name~="scratch" and not name:find("mob%-")
        and catalog.weaponStats[name]~=nil
end

function LootProgression.repairPartFor(catalog,name)
    if not isPlayerWeapon(catalog,name) then return nil end
    local partName=catalog.weaponRepairParts and catalog.weaponRepairParts[name]
    local part=partName and catalog.repairParts and rawget(catalog.repairParts,partName)
    -- A component fits one named weapon. Never infer compatibility from a
    -- weapon family or from similar words in its item ID.
    if part and part.weapon==name then return partName end
    return nil
end

local function canonicalRepairPart(catalog,name)
    return (catalog.repairPartAliases and catalog.repairPartAliases[name]) or name
end

local function ownsWeapon(data,catalog,name)
    if not isPlayerWeapon(catalog,name) then return false end
    for _,equipped in pairs(data.equipment or {}) do if equipped==name then return true end end
    for index=1,(data.inventoryCapacity or 6) do if data.inventory and data.inventory[index]==name then return true end end
    return false
end

function LootProgression.ownedWeapons(data,catalog)
    local owned,seen={},{}
    local function add(name)
        if isPlayerWeapon(catalog,name) and not seen[name] then
            seen[name]=true; owned[#owned+1]=name
        end
    end
    for _,name in ipairs(catalog.weaponProgression or {}) do if ownsWeapon(data,catalog,name) then add(name) end end
    for _,name in pairs(data.equipment or {}) do add(name) end
    for index=1,(data.inventoryCapacity or 6) do add(data.inventory and data.inventory[index]) end
    return owned
end

local function inventoryPartCount(data,catalog,partName)
    local count=0
    for index=1,(data.inventoryCapacity or 6) do
        local item=data.inventory and data.inventory[index]
        if item and canonicalRepairPart(catalog,item)==partName then count=count+1 end
    end
    return count
end

function LootProgression.repairStatus(data,catalog,name)
    local candidate
    if name then
        if ownsWeapon(data,catalog,name) then
            candidate={name=name,durability=LootProgression.weaponCondition(data.weaponDurability and data.weaponDurability[name]).durability}
        end
    else
        for _,weapon in pairs(data.equipment or {}) do
            if isPlayerWeapon(catalog,weapon) then
                local durability=LootProgression.weaponCondition(data.weaponDurability and data.weaponDurability[weapon]).durability
                if durability<100 and (not candidate or durability<candidate.durability) then candidate={name=weapon,durability=durability} end
            end
        end
    end
    if not candidate then return {needed=false,affordable=false} end
    candidate.part=LootProgression.repairPartFor(catalog,candidate.name)
    candidate.major=candidate.durability<=25
    candidate.baseCost=LootProgression.repairCost(catalog,candidate.name,candidate.durability)
    candidate.cost=candidate.baseCost+(candidate.major and (6+2*((catalog.weaponStats[candidate.name] or {}).tier or 1)) or 0)
    candidate.partCount=candidate.part and inventoryPartCount(data,catalog,candidate.part) or 0
    candidate.hasPart=not candidate.major or candidate.partCount>0
    candidate.needed=candidate.durability<100
    candidate.affordable=(data.scrap or 0)>=candidate.cost and candidate.hasPart
    return candidate
end

function LootProgression.completeRepair(data,catalog,name,quality)
    local status=LootProgression.repairStatus(data,catalog,name)
    if quality~="perfect" and quality~="good" then return {ok=false,reason="miss",status=status} end
    if not status.name then return {ok=false,reason="ownership",status=status} end
    if not status.needed then return {ok=false,reason="ready",status=status} end
    if status.major and not status.hasPart then return {ok=false,reason="part",status=status} end
    if (data.scrap or 0)<status.cost then return {ok=false,reason="scrap",status=status} end
    local restored=100
    if quality=="good" then
        restored=math.min(95,math.max(75,status.durability+math.floor((100-status.durability)*.70)))
        restored=math.max(status.durability,restored)
    end
    if restored<=status.durability then return {ok=false,reason="precision",status=status} end
    data.weaponDurability=data.weaponDurability or {}
    data.scrap=data.scrap-status.cost
    data.weaponDurability[status.name]=restored
    if status.major then
        for index=1,(data.inventoryCapacity or 6) do
            local item=data.inventory and data.inventory[index]
            if item and canonicalRepairPart(catalog,item)==status.part then data.inventory[index]=nil; break end
        end
    end
    return {ok=true,name=status.name,cost=status.cost,quality=quality,restored=restored,part=status.major and status.part or nil,
        status=LootProgression.repairStatus(data,catalog,name)}
end

function LootProgression.repairEquipped(data,catalog)
    return {ok=false,reason="workbench",status=LootProgression.repairStatus(data,catalog)}
end

function LootProgression.rollRepairPart(data,catalog,location,rng,options)
    options=options or {}
    local all={}
    for name,part in pairs(catalog.repairParts or {}) do
        if LootProgression.repairPartFor(catalog,part.weapon)==name then all[#all+1]=name end
    end
    table.sort(all)
    if #all==0 then return nil end
    local targeted,hasParts={},{}
    for index=1,(data.inventoryCapacity or 6) do
        local part=canonicalRepairPart(catalog,data.inventory and data.inventory[index])
        if part then hasParts[part]=(hasParts[part] or 0)+1 end
    end
    for _,weapon in ipairs(LootProgression.ownedWeapons(data,catalog)) do
        local durability=LootProgression.weaponCondition(data.weaponDurability and data.weaponDurability[weapon]).durability
        if durability<=25 then
            local part=LootProgression.repairPartFor(catalog,weapon)
            if part and not hasParts[part] then targeted[#targeted+1]=part end
        end
    end
    if #targeted>0 then
        if options.targetedOnly then return choice(targeted,rng),"targeted" end
        if randomFloat(rng)<.72 then return choice(targeted,rng),"targeted" end
    end
    if options.targetedOnly then return nil end
    local tier=LootProgression.locationTier(location)
    -- Component rarities rise at weapon tiers 3, 6 and 9. The final tier
    -- must also unlock legendary parts before the player owns that weapon.
    local maxRank=math.min(4,math.max(2,1+math.floor(tier/3)))
    local eligible={}
    for _,name in ipairs(all) do
        local part=catalog.repairParts[name]
        if (LootProgression.rarityRank[part.rarity] or 1)<=maxRank then eligible[#eligible+1]=name end
    end
    return choice(eligible,rng) or choice(all,rng),"general"
end

function LootProgression.resalePrice(catalog,name,durability)
    local price=LootProgression.itemPrice(catalog,name)
    if catalog.weaponStats[name] then
        local condition=LootProgression.weaponCondition(durability)
        price=price*(.35+.65*condition.durability/100)
    end
    return math.max(1,math.floor(price*.45))
end

function LootProgression.validate(catalog)
    local errors={}; local seen={}; local previous=0
    for index,name in ipairs(catalog.weaponProgression or {}) do
        local stats=catalog.weaponStats[name]
        if not stats then errors[#errors+1]="weapon progression entry has no stats: "..tostring(name)
        elseif stats.tier<previous then errors[#errors+1]="weapon progression decreases at "..name
        else previous=stats.tier end
        if seen[name] then errors[#errors+1]="duplicate weapon progression entry: "..name end; seen[name]=true
        if not catalog.weaponCombat[name] then errors[#errors+1]="weapon has no combat profile: "..tostring(name) end
    end
    for name,stats in pairs(catalog.weaponStats or {}) do
        if name~="scratch" and not name:find("mob%-") and not seen[name] then errors[#errors+1]="weapon missing from progression: "..name end
        if stats.tier and (stats.tier<0 or stats.tier>9) then errors[#errors+1]="weapon tier out of range: "..name end
        if name~="scratch" and not name:find("mob%-") and not LootProgression.repairPartFor(catalog,name) then errors[#errors+1]="weapon has no compatible repair part: "..name end
    end
    for _,rarity in ipairs(LootProgression.rarityOrder) do
        if not catalog.lootPools[rarity] or #catalog.lootPools[rarity]==0 then errors[#errors+1]="empty loot pool: "..rarity end
    end
    for name in pairs(catalog.itemEffects or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="item missing rarity: "..name end end
    for name in pairs(catalog.rangeTools or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="range tool missing rarity: "..name end end
    for name,item in pairs(catalog.miscItems or {}) do
        if not catalog.itemRarity[name] then errors[#errors+1]="miscellaneous item missing rarity: "..name end
        if type(item.description)~="string" or item.description=="" then errors[#errors+1]="miscellaneous item missing tooltip: "..name end
        if type(item.worldScale)~="number" or item.worldScale<=0 then errors[#errors+1]="miscellaneous item missing world scale: "..name end
    end
    local componentOwners,spriteOwners={},{}
    for weapon,partName in pairs(catalog.weaponRepairParts or {}) do
        if not catalog.weaponStats[weapon] or weapon=="scratch" or weapon:find("mob%-") then
            errors[#errors+1]="repair compatibility references an invalid player weapon: "..tostring(weapon)
        end
        if componentOwners[partName] then
            errors[#errors+1]="repair component shared by weapons: "..tostring(partName).." -> "..componentOwners[partName]..", "..weapon
        else componentOwners[partName]=weapon end
        local part=catalog.repairParts and rawget(catalog.repairParts,partName)
        if not part or part.weapon~=weapon then errors[#errors+1]="repair compatibility does not match its component: "..weapon end
    end
    for name,part in pairs(catalog.repairParts or {}) do
        if not catalog.miscItems[name] then errors[#errors+1]="repair part missing inventory definition: "..name end
        if not part.name or not part.component or not part.weapon or not part.icon or not part.rarity then errors[#errors+1]="repair part has incomplete metadata: "..name end
        if not LootProgression.rarityRank[part.rarity] then errors[#errors+1]="repair part has invalid rarity: "..name end
        if not part.weapon or LootProgression.repairPartFor(catalog,part.weapon)~=name then errors[#errors+1]="repair part has no exact weapon compatibility: "..name end
        if type(part.sprite)~="string" or not part.sprite:match("^assets/sprites/weapon%-parts/.+%.png$") then
            errors[#errors+1]="repair part missing dedicated sprite: "..name
        elseif spriteOwners[part.sprite] then
            errors[#errors+1]="repair parts share a sprite: "..spriteOwners[part.sprite]..", "..name
        else spriteOwners[part.sprite]=name end
    end
    for alias,target in pairs(catalog.repairPartAliases or {}) do
        if rawget(catalog.repairParts or {},alias) then errors[#errors+1]="legacy repair alias shadows an active component: "..alias end
        if not rawget(catalog.repairParts or {},target) then errors[#errors+1]="legacy repair alias has no exact component: "..alias end
    end
    for name in pairs(catalog.backpackUpgrades or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="backpack missing rarity: "..name end end
    local wearableSlots={}
    for _,slot in ipairs(catalog.wearableSlots or {}) do wearableSlots[slot.id]=true end
    local wearableStats={armor=true,aim=true,attack=true,move=true,maxHealth=true}
    for name,profile in pairs(catalog.wearableItems or {}) do
        if not catalog.itemRarity[name] then errors[#errors+1]="wearable missing rarity: "..name end
        if not profile.slot or not wearableSlots[profile.slot] then errors[#errors+1]="wearable has invalid slot: "..name end
        if profile.slot=="backpack" and (type(profile.capacity)~="number" or profile.capacity<1) then errors[#errors+1]="backpack wearable has invalid capacity: "..name end
        for stat,value in pairs(profile.bonuses or {}) do
            if not wearableStats[stat] or type(value)~="number" then errors[#errors+1]="wearable has invalid bonus: "..name.." -> "..tostring(stat) end
        end
    end
    for name,material in pairs(catalog.craftMaterials or {}) do
        if not catalog.miscItems[name] then errors[#errors+1]="craft material missing inventory definition: "..name end
        if not material.label or not material.description or not material.icon then errors[#errors+1]="craft material has incomplete metadata: "..name end
    end
    for name,tier in pairs(LootProgression.itemUnlockTier) do
        if not catalog.itemRarity[name] then errors[#errors+1]="item unlock has no rarity profile: "..name end
        if type(tier)~="number" or tier<1 or tier>9 then errors[#errors+1]="item unlock tier out of range: "..name end
    end
    for _,pool in pairs(catalog.lootPools or {}) do
        for _,name in ipairs(pool) do
            if catalog.outfitUpgrades and catalog.outfitUpgrades[name] then errors[#errors+1]="crafted upgrade in random loot pool: "..name end
        end
    end
    for name in pairs(catalog.ammoPickupAmounts or {}) do
        if not catalog.itemRarity[name] then errors[#errors+1]="ammunition missing rarity: "..name end
        if not LootProgression.ammoUnlockTier[name] then errors[#errors+1]="ammunition missing route unlock: "..name end
    end
    for name,combat in pairs(catalog.weaponCombat or {}) do
        if combat.ammo and not catalog.ammoPickupAmounts[combat.ammo] then errors[#errors+1]="weapon ammunition has no pickup: "..name.." -> "..combat.ammo end
        local stats=catalog.weaponStats[name]
        if combat.ammo and stats and (LootProgression.ammoUnlockTier[combat.ammo] or 99)>(stats.tier or 0) then errors[#errors+1]="ammunition unlocks after weapon: "..name end
    end
    return #errors==0,errors
end

function LootProgression.audit(catalog)
    local valid,errors=LootProgression.validate(catalog)
    local tierCounts,averages,families,statusProfiles={},{},{},0
    for name,stats in pairs(catalog.weaponStats or {}) do
        if name~="scratch" and not name:find("mob%-") then
            tierCounts[stats.tier]=(tierCounts[stats.tier] or 0)+1
            averages[stats.tier]=(averages[stats.tier] or 0)+(stats.min+stats.max)/2
            local combat=catalog.weaponCombat[name] or {}
            if combat.kind=="melee" then families[combat.family or "melee"]=true; if combat.status then statusProfiles=statusProfiles+1 end end
        end
    end
    local familyCount=0; for _ in pairs(families) do familyCount=familyCount+1 end
    local weaponCount,damageReady,previous=0,true,0
    for tier=1,9 do
        weaponCount=weaponCount+(tierCounts[tier] or 0)
        local average=(averages[tier] or 0)/math.max(1,tierCounts[tier] or 0)
        damageReady=damageReady and (tierCounts[tier] or 0)>0 and average>previous
        previous=average
    end
    local early,late=LootProgression.rarityWeights(1),LootProgression.rarityWeights(50)
    local itemTimingReady=LootProgression.itemRarityAt(1,"legendary")=="uncommon"
        and LootProgression.itemRarityAt(13,"legendary")=="rare"
        and LootProgression.itemRarityAt(31,"legendary")=="legendary"
        and not itemAvailable(catalog,"9mm",1) and itemAvailable(catalog,"9mm",19)
        and not itemAvailable(catalog,"food-ration",1) and itemAvailable(catalog,"food-ration",13)
        and not itemAvailable(catalog,"scavenger-frame-pack",48) and itemAvailable(catalog,"scavenger-frame-pack",49)
    local repairData={equipment={"frontier-short-sword"},weaponDurability={["frontier-short-sword"]=40},scrap=20}
    local repair=LootProgression.completeRepair(repairData,catalog,"frontier-short-sword","perfect")
    local repairFlow=LootProgression.repairAudit(catalog)
    local broken=LootProgression.weaponCondition(0)
    local ready=valid and weaponCount==83 and familyCount>=6 and statusProfiles>=12 and damageReady and early.common>late.common and late.rare>early.rare
        and LootProgression.itemPrice(catalog,"frontier-longsword")>LootProgression.itemPrice(catalog,"trail-slingshot")
        and LootProgression.itemPrice(catalog,"rose-heart-arrow")>LootProgression.itemPrice(catalog,"food-ration")
        and broken.multiplier==0 and repair.ok and repairData.weaponDurability["frontier-short-sword"]==100 and repairFlow.ready and itemTimingReady
        and LootProgression.resalePrice(catalog,"frontier-short-sword",25)<LootProgression.resalePrice(catalog,"frontier-short-sword",100)
    return {ready=ready,valid=valid,errors=errors,weaponCount=weaponCount,tierCounts=tierCounts,damageReady=damageReady,familyCount=familyCount,statusProfiles=statusProfiles,
        earlyWeights=early,lateWeights=late,brokenMultiplier=broken.multiplier,repairCost=repair.cost,
        repair=repairFlow,itemTimingReady=itemTimingReady,
        commonPrice=LootProgression.itemPrice(catalog,"food-ration"),legendaryPrice=LootProgression.itemPrice(catalog,"rose-heart-arrow"),
        starterWeaponPrice=LootProgression.itemPrice(catalog,"trail-slingshot"),lateWeaponPrice=LootProgression.itemPrice(catalog,"frontier-longsword"),
        wornResale=LootProgression.resalePrice(catalog,"frontier-short-sword",25),soundResale=LootProgression.resalePrice(catalog,"frontier-short-sword",100),curve="loot-v4"}
end

function LootProgression.repairAudit(catalog)
    local firearm="frontier-22-lever-rifle"
    local firearmPart=LootProgression.repairPartFor(catalog,firearm)
    local blockedData={equipment={firearm},inventory={},inventoryCapacity=6,scrap=200,
        weaponDurability={[firearm]=10}}
    local blockedStatus=LootProgression.repairStatus(blockedData,catalog,firearm)
    local blocked=LootProgression.completeRepair(blockedData,catalog,firearm,"perfect")
    local missingPartBlocks=blocked.reason=="part" and not blockedStatus.hasPart
        and blockedData.scrap==200 and blockedData.weaponDurability[firearm]==10

    blockedData.inventory[1]=firearmPart
    local majorStatus=LootProgression.repairStatus(blockedData,catalog,firearm)
    local major=LootProgression.completeRepair(blockedData,catalog,firearm,"perfect")
    local partConsumed=major.ok and major.part==firearmPart and blockedData.inventory[1]==nil
    local majorScrapCharged=major.ok and blockedData.scrap==200-majorStatus.cost
        and blockedData.weaponDurability[firearm]==100

    local fieldWeapon="frontier-short-sword"
    local fieldData={equipment={fieldWeapon},inventory={},inventoryCapacity=6,scrap=200,
        weaponDurability={[fieldWeapon]=50}}
    local fieldStatus=LootProgression.repairStatus(fieldData,catalog,fieldWeapon)
    local field=LootProgression.completeRepair(fieldData,catalog,fieldWeapon,"good")
    local fieldServiceWorks=field.ok and not fieldStatus.major and fieldStatus.partCount==0
        and fieldData.weaponDurability[fieldWeapon]>=75 and fieldData.weaponDurability[fieldWeapon]<=95
        and fieldData.scrap==200-fieldStatus.cost

    local missData={equipment={fieldWeapon},inventory={},inventoryCapacity=6,scrap=200,
        weaponDurability={[fieldWeapon]=50}}
    local miss=LootProgression.completeRepair(missData,catalog,fieldWeapon,"miss")
    local missIsFree=not miss.ok and miss.reason=="miss" and missData.scrap==200
        and missData.weaponDurability[fieldWeapon]==50

    local targetedData={equipment={firearm},inventory={},inventoryCapacity=6,
        weaponDurability={[firearm]=0}}
    local foundPart,source=LootProgression.rollRepairPart(targetedData,catalog,1,function() return 0 end)
    local salvageTargetsCriticalWeapon=source=="targeted" and foundPart==firearmPart

    local compatible,uniqueComponents,wrongPartBlocks,eachPartRepairs=true,true,true,true
    local partOwners,weaponNames={},{}
    for name,stats in pairs(catalog.weaponStats or {}) do
        if name~="scratch" and not name:find("mob%-") then
            local part=LootProgression.repairPartFor(catalog,name)
            compatible=compatible and part~=nil and catalog.repairParts[part]~=nil and catalog.repairParts[part].weapon==name and stats~=nil
            if part then
                if partOwners[part] then uniqueComponents=false end
                partOwners[part]=name
            end
            weaponNames[#weaponNames+1]=name
        end
    end
    table.sort(weaponNames)
    for index,name in ipairs(weaponNames) do
        local correctPart=LootProgression.repairPartFor(catalog,name)
        local wrongPart=LootProgression.repairPartFor(catalog,weaponNames[index%#weaponNames+1])
        local sample={equipment={name},inventory={[1]=wrongPart},inventoryCapacity=6,scrap=200,
            weaponDurability={[name]=0}}
        local rejected=LootProgression.completeRepair(sample,catalog,name,"perfect")
        wrongPartBlocks=wrongPartBlocks and wrongPart~=nil and wrongPart~=correctPart
            and not rejected.ok and rejected.reason=="part" and sample.scrap==200
            and sample.weaponDurability[name]==0 and sample.inventory[1]==wrongPart
        sample.inventory[1]=correctPart
        local restored=LootProgression.completeRepair(sample,catalog,name,"perfect")
        eachPartRepairs=eachPartRepairs and correctPart~=nil and restored.ok
            and restored.part==correctPart and sample.inventory[1]==nil and sample.weaponDurability[name]==100
    end
    local aliasesFitExactly=true
    for alias,target in pairs(catalog.repairPartAliases or {}) do
        local part=rawget(catalog.repairParts or {},target)
        if not part then aliasesFitExactly=false
        else
            local sample={equipment={part.weapon},inventory={[1]=alias},inventoryCapacity=6,scrap=200,
                weaponDurability={[part.weapon]=0}}
            local restored=LootProgression.completeRepair(sample,catalog,part.weapon,"perfect")
            aliasesFitExactly=aliasesFitExactly and restored.ok and restored.part==target and sample.inventory[1]==nil
            for _,other in ipairs(weaponNames) do
                if other~=part.weapon then
                    sample={equipment={other},inventory={[1]=alias},inventoryCapacity=6,scrap=200,
                        weaponDurability={[other]=0}}
                    local rejected=LootProgression.completeRepair(sample,catalog,other,"perfect")
                    aliasesFitExactly=aliasesFitExactly and not rejected.ok and rejected.reason=="part"
                        and sample.inventory[1]==alias and sample.scrap==200
                    break
                end
            end
        end
    end
    local ready=compatible and uniqueComponents and wrongPartBlocks and eachPartRepairs and aliasesFitExactly
        and missingPartBlocks and partConsumed and majorScrapCharged
        and fieldServiceWorks and missIsFree and salvageTargetsCriticalWeapon
    return {ready=ready,compatibleWeapons=compatible,missingPartBlocks=missingPartBlocks,
        uniqueComponents=uniqueComponents,wrongPartBlocks=wrongPartBlocks,eachPartRepairs=eachPartRepairs,
        aliasesFitExactly=aliasesFitExactly,componentCount=#weaponNames,
        partConsumed=partConsumed,majorScrapCharged=majorScrapCharged,
        fieldServiceWorks=fieldServiceWorks,missIsFree=missIsFree,
        targetedSalvage=salvageTargetsCriticalWeapon,criticalPart=firearmPart,
        majorCost=majorStatus.cost,fieldCost=fieldStatus.cost}
end

return LootProgression
