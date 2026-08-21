local LootProgression = {}

LootProgression.rarityOrder={"common","uncommon","rare","legendary"}
LootProgression.rarityRank={common=1,uncommon=2,rare=3,legendary=4}

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

local function supplyCandidates(catalog,kind,location)
    local result={}; local tier=LootProgression.locationTier(location)
    local maximum=kind=="food" and math.min(5,2+math.floor((tier-1)/2)) or math.min(7,3+math.floor((tier-1)/2))
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
    local unlock={rocks=1,arrows=1,["ball-bearings"]=1,["22lr"]=3,["32-acp"]=3,["380-acp"]=4,["9mm"]=4,["45-cal"]=5,["30-carbine"]=5,["12-gauge"]=6,["556"]=7,["762x39"]=8,["8mm"]=8}
    local tier=LootProgression.locationTier(location); local candidates={}
    for name in pairs(catalog.ammoPickupAmounts or {}) do if (unlock[name] or 9)<=tier then candidates[#candidates+1]=name end end
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
    local pool=catalog.lootPools[rarity]
    return choice(pool,rng),rarity,"item"
end

function LootProgression.rollMedical(catalog,location,minimum,rng)
    local rarity=LootProgression.rollRarity(location,minimum,rng)
    local maximum=({common=5,uncommon=8,rare=12,legendary=99})[rarity]
    local candidates={}
    for name,effect in pairs(catalog.itemEffects or {}) do
        if effect.health and not effect.potion and effect.health<=maximum then candidates[#candidates+1]=name end
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

function LootProgression.qualityRarity(quality)
    if quality=="legendary" then return "legendary" end
    if quality=="rare" then return "rare" end
    if quality=="uncommon" then return "uncommon" end
    if type(quality)=="number" then return ({[1]="common",[2]="uncommon",[3]="rare",[4]="legendary"})[math.max(1,math.min(4,quality))] end
    return nil
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
    end
    for _,rarity in ipairs(LootProgression.rarityOrder) do
        if not catalog.lootPools[rarity] or #catalog.lootPools[rarity]==0 then errors[#errors+1]="empty loot pool: "..rarity end
    end
    for name in pairs(catalog.itemEffects or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="item missing rarity: "..name end end
    for name in pairs(catalog.backpackUpgrades or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="backpack missing rarity: "..name end end
    for name in pairs(catalog.ammoPickupAmounts or {}) do if not catalog.itemRarity[name] then errors[#errors+1]="ammunition missing rarity: "..name end end
    return #errors==0,errors
end

return LootProgression
