local Catalog = require("game.catalog")
local LootProgression = require("game.loot_progression")

local CrowCaravans = {}

CrowCaravans.version = 1
CrowCaravans.relationshipKey = "crow-caravan"
CrowCaravans.sprite = "crow-merchant.png"
CrowCaravans.practicalPriceCap = 6
CrowCaravans.scheduleBands = {{7,16},{22,32},{38,48}}
CrowCaravans.defaultExcludedStops = {[15]=true,[35]=true,[47]=true}
CrowCaravans.merchantOrder = {"packmaster","ironbeak","curio-keeper"}
CrowCaravans.merchantDefinitions = {
    ["packmaster"]={name="Packmaster",role="Provisions, medicine, and ammunition"},
    ["ironbeak"]={name="Ironbeak",role="Progression-matched weapons"},
    ["curio-keeper"]={name="Curio Keeper",role="Potions, packs, and rare curios"},
}

local function copyArray(values)
    local result={}
    if type(values)~="table" then return result end
    for index,value in ipairs(values or {}) do result[index]=value end
    return result
end

local function clamp(value,low,high)
    return math.max(low,math.min(high,value))
end

local function defaultRandom()
    if love and love.math and love.math.random then return love.math.random() end
    return math.random()
end

local function randomFloat(rng)
    local value=tonumber((rng or defaultRandom)()) or 0
    return clamp(value,0,.999999999)
end

local function randomChoice(values,rng)
    if not values or #values==0 then return nil end
    return values[1+math.floor(randomFloat(rng)*#values)]
end

local function normalizedStop(value)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return nil end
    return clamp(math.floor(value),1,50)
end

local function canonicalCampId(stop)
    return "crow-caravan-stop-"..tostring(normalizedStop(stop))
end

local function addExclusions(target,values)
    if type(values)~="table" then return end
    for key,value in pairs(values) do
        local stop
        if value==true then stop=tonumber(key)
        elseif type(value)=="number" then stop=value end
        if stop then target[normalizedStop(stop)]=true end
    end
end

local function exclusionsFor(options)
    options=options or {}
    local result={}
    if options.useDefaultExclusions~=false then addExclusions(result,CrowCaravans.defaultExcludedStops) end
    addExclusions(result,options.excludedStops or options.exclusions)
    addExclusions(result,options.additionalExclusions)
    return result
end

local function bandsFor(options)
    local bands=(options and options.bands) or CrowCaravans.scheduleBands
    if type(bands)~="table" or #bands~=3 then return nil,"crow caravan scheduling requires exactly three bands" end
    local result={}
    for index,band in ipairs(bands) do
        if type(band)~="table" or tonumber(band[1])==nil or tonumber(band[2])==nil then
            return nil,"crow caravan band "..index.." is invalid"
        end
        local first,second=tonumber(band[1]),tonumber(band[2])
        local low=normalizedStop(math.min(first,second))
        local high=normalizedStop(math.max(first,second))
        result[index]={low,high}
    end
    table.sort(result,function(a,b) return a[1]<b[1] end)
    return result
end

local function minimumGapFor(options)
    return math.max(1,math.floor(tonumber(options and options.minimumGap) or 8))
end

local function canonicalSchedule(values)
    local result,seen={},{}
    local canonical=type(values)=="table"
    local sourceCount=0
    if type(values)=="table" then
        for _,value in ipairs(values) do
            sourceCount=sourceCount+1
            local stop=normalizedStop(value)
            if not stop or seen[stop] then canonical=false
            else
                result[#result+1]=stop
                seen[stop]=true
                if type(value)~="number" or value~=stop then canonical=false end
            end
        end
    end
    table.sort(result)
    if sourceCount~=#result then canonical=false end
    for index,stop in ipairs(result) do
        if type(values)~="table" or values[index]~=stop then canonical=false; break end
    end
    return result,canonical
end

local function bandIndexFor(stop,bands)
    for index,band in ipairs(bands or {}) do
        if stop>=band[1] and stop<=band[2] then return index end
    end
end

local function structurallyValidSchedule(stops,bands,options,allowPartial)
    if type(stops)~="table" or #stops>3 or (not allowPartial and #stops~=3) then return false end
    local previousStop,previousBand
    for _,stop in ipairs(stops) do
        local bandIndex=bandIndexFor(stop,bands)
        if not bandIndex or (previousBand and bandIndex<=previousBand) then return false end
        if previousStop and stop-previousStop<minimumGapFor(options) then return false end
        previousStop,previousBand=stop,bandIndex
    end
    return true
end

local function eligibleForRoll(stop,excluded,options)
    if excluded and excluded[stop] then return false end
    if options and type(options.isExcluded)=="function" and options.isExcluded(stop)==true then return false end
    return true
end

local function validNewJourneySchedule(stops,bands,excluded,options)
    if not structurallyValidSchedule(stops,bands,options,false) then return false end
    for _,stop in ipairs(stops) do
        if not eligibleForRoll(stop,excluded,options) then return false end
    end
    return true
end

local function sameSchedule(left,right)
    if type(left)~="table" or type(right)~="table" or #left~=#right then return false end
    for index,value in ipairs(left) do if value~=right[index] then return false end end
    return true
end

local function currentLocationFor(data,options)
    local value=tonumber(options and options.currentLocation) or tonumber(data and data.location) or 0
    if value~=value or value==math.huge or value==-math.huge then value=0 end
    return clamp(math.floor(value),0,50)
end

local function stopWasVisited(data,state,stop)
    local visited=data and data.visitedStops
    if type(visited)=="table" and (visited[stop]==true or visited[tostring(stop)]==true) then return true end
    local camp=state and state.camps and state.camps[tostring(stop)]
    return type(camp)=="table" and camp.visited==true
end

local function spacedFrom(stop,selected,options)
    for _,chosen in ipairs(selected or {}) do
        if math.abs(stop-chosen)<minimumGapFor(options) then return false end
    end
    return true
end

local function deterministicSeed(data,salt)
    local seed=104729
    local function mix(value)
        local text=tostring(value or "")
        for index=1,#text do seed=(seed*131+text:byte(index))%2147483647 end
        seed=(seed*131+31)%2147483647
    end
    mix(salt or "crow-caravan-schedule")
    mix(data and data.character)
    mix(data and data.location)
    local progress=data and data.eventProgress
    mix(type(progress)=="table" and progress.story or 0)
    mix(type(progress)=="table" and progress.mystery or 0)
    local visited=data and data.visitedStops
    for stop=1,50 do
        if type(visited)=="table" and (visited[stop]==true or visited[tostring(stop)]==true) then mix("visited-"..stop) end
    end
    for _,stop in ipairs(type(data and data.mysteryStops)=="table" and data.mysteryStops or {}) do
        mix("mystery-"..tostring(stop))
    end
    if seed<=0 then seed=1 end
    return seed
end

function CrowCaravans.deterministicRng(data,salt)
    local seed=deterministicSeed(data,salt)
    return function()
        seed=(seed*48271)%2147483647
        return seed/2147483647
    end
end

local function ensureState(data)
    assert(type(data)=="table","crow caravans require save data")
    if type(data.crowCaravans)~="table" then data.crowCaravans={} end
    local state=data.crowCaravans
    state.version=CrowCaravans.version
    state.groupRelationshipId=CrowCaravans.relationshipKey
    if type(state.camps)~="table" then state.camps={} end
    local normalizedCamps={}
    for key,camp in pairs(state.camps) do
        if type(camp)=="table" then
            local stop=normalizedStop(camp.stop or key)
            local oldId=camp.id
            if stop then
                camp.stop=stop
                camp.id=canonicalCampId(stop)
                camp.relationshipKey=state.groupRelationshipId
                normalizedCamps[tostring(stop)]=camp
                if state.activeCampId and (state.activeCampId==oldId or state.activeCampId==camp.id) then state.activeCampId=camp.id end
            end
        end
    end
    state.camps=normalizedCamps
    return state
end

local function candidatesForBand(data,state,band,selected,excluded,options,minimumStop,rejectVisited)
    local candidates={}
    for stop=band[1],band[2] do
        local afterCutoff=not minimumStop or stop>=minimumStop
        local unvisited=not rejectVisited or not stopWasVisited(data,state,stop)
        if afterCutoff and unvisited and eligibleForRoll(stop,excluded,options) and spacedFrom(stop,selected,options) then
            candidates[#candidates+1]=stop
        end
    end
    return candidates
end

local function rollFullSchedule(data,state,bands,excluded,options,rng)
    local selected={}
    for bandIndex,band in ipairs(bands) do
        local candidates=candidatesForBand(data,state,band,selected,excluded,options)
        if #candidates==0 then return nil,"crow caravan band "..bandIndex.." has no eligible stops" end
        selected[#selected+1]=randomChoice(candidates,rng)
    end
    table.sort(selected)
    return selected
end

local function rollFutureSchedule(data,state,bands,excluded,options,rng)
    local selected={}
    local minimumStop=currentLocationFor(data,options)+1
    for _,band in ipairs(bands) do
        local candidates=candidatesForBand(data,state,band,selected,excluded,options,minimumStop,true)
        -- An upgraded journey may already be beyond this band, or its short
        -- remaining tail may be occupied. Skipping it is preferable to placing
        -- an unreachable campsite behind the train.
        if #candidates>0 then selected[#selected+1]=randomChoice(candidates,rng) end
    end
    table.sort(selected)
    return selected
end

local function preservationScore(data,state,selected,currentLocation)
    local score={0,0,0,0}
    for _,stop in ipairs(selected) do
        local camp=state.camps and state.camps[tostring(stop)]
        if type(camp)=="table" and camp.visited==true then score[1]=score[1]+1 end
        local visited=data and data.visitedStops
        if type(visited)=="table" and (visited[stop]==true or visited[tostring(stop)]==true) then score[2]=score[2]+1 end
        if stop<=currentLocation then score[3]=score[3]+1 end
        score[4]=score[4]+1
    end
    return score
end

local function betterScore(left,right)
    if not right then return true end
    for index=1,4 do
        if left[index]~=right[index] then return left[index]>right[index] end
    end
    return false
end

local function bestExistingSchedule(data,state,stops,bands,options)
    local byBand={{},{},{}}
    for _,stop in ipairs(stops) do
        local bandIndex=bandIndexFor(stop,bands)
        if bandIndex then byBand[bandIndex][#byBand[bandIndex]+1]=stop end
    end
    local best,bestScore
    local currentLocation=currentLocationFor(data,options)
    -- There are only three schedule bands and at most eleven stops in each,
    -- so considering every one-per-band combination is small and lets repair
    -- retain the most important valid entries without special-case ordering.
    for first=0,#byBand[1] do
        for second=0,#byBand[2] do
            for third=0,#byBand[3] do
                local selected={}
                if first>0 then selected[#selected+1]=byBand[1][first] end
                if second>0 then selected[#selected+1]=byBand[2][second] end
                if third>0 then selected[#selected+1]=byBand[3][third] end
                if structurallyValidSchedule(selected,bands,options,true) then
                    local score=preservationScore(data,state,selected,currentLocation)
                    if betterScore(score,bestScore) then best,bestScore=selected,score end
                end
            end
        end
    end
    return best or {}
end

local function repairLockedSchedule(data,state,stops,bands,excluded,options)
    local selected=bestExistingSchedule(data,state,stops,bands,options)
    local occupiedBands={}
    for _,stop in ipairs(selected) do occupiedBands[bandIndexFor(stop,bands)]=true end
    local minimumStop=currentLocationFor(data,options)+1
    local rng=(options and options.rng) or CrowCaravans.deterministicRng(data,"locked-schedule-repair")
    for bandIndex,band in ipairs(bands) do
        if not occupiedBands[bandIndex] then
            local candidates=candidatesForBand(data,state,band,selected,excluded,options,minimumStop,true)
            if #candidates>0 then
                selected[#selected+1]=randomChoice(candidates,rng)
                occupiedBands[bandIndex]=true
                table.sort(selected)
            end
        end
    end
    return selected
end

function CrowCaravans.ensureSchedule(data,options)
    options=options or {}
    local state=ensureState(data)
    local bands,errorMessage=bandsFor(options)
    if not bands then return nil,errorMessage end
    local excluded=exclusionsFor(options)
    local previousSchedule=copyArray(state.scheduledStops)
    local previousMode=state.scheduleMode
    local previousVersion=math.max(0,math.floor(tonumber(state.scheduleVersion) or 0))
    local normalized,canonical=canonicalSchedule(state.scheduledStops)
    local locked=previousVersion>=CrowCaravans.version
    local lockedMode=state.scheduleMode=="legacy-future" and "legacy-future" or "journey"

    -- A successfully rolled version-one schedule is immutable with respect to
    -- later activity/event exclusions. Those exclusions are generation rules,
    -- not a reason to move an already promised or visited caravan.
    if locked and structurallyValidSchedule(normalized,bands,options,lockedMode=="legacy-future") then
        state.scheduledStops=normalized
        state.scheduleMode=lockedMode
        return state,nil,(not canonical or previousMode~=lockedMode)
    end

    if not locked and not options.futureOnly and validNewJourneySchedule(normalized,bands,excluded,options) then
        state.scheduledStops=normalized
        state.scheduleVersion=CrowCaravans.version
        state.scheduleMode="journey"
        return state,nil,(not canonical or previousVersion~=CrowCaravans.version or previousMode~="journey")
    end

    local selected
    if locked then
        selected=repairLockedSchedule(data,state,normalized,bands,excluded,options)
    elseif options.futureOnly then
        local rng=options.rng or CrowCaravans.deterministicRng(data,"legacy-future-schedule")
        selected=rollFutureSchedule(data,state,bands,excluded,options,rng)
    else
        selected,errorMessage=rollFullSchedule(data,state,bands,excluded,options,options.rng)
        if not selected then return nil,errorMessage,false end
    end
    state.scheduledStops=selected
    state.scheduleVersion=math.max(previousVersion,CrowCaravans.version)
    state.scheduleMode=(not locked and not options.futureOnly and #selected==3) and "journey"
        or (structurallyValidSchedule(selected,bands,options,false) and #selected==3 and previousMode=="journey" and "journey" or "legacy-future")
    local changed=not sameSchedule(previousSchedule,selected) or previousVersion~=state.scheduleVersion or previousMode~=state.scheduleMode
    return state,nil,changed
end

function CrowCaravans.scheduledStops(data,options)
    local state,errorMessage=CrowCaravans.ensureSchedule(data,options)
    if not state then return nil,errorMessage end
    return copyArray(state.scheduledStops)
end

function CrowCaravans.isScheduled(data,location,options)
    local state,errorMessage=CrowCaravans.ensureSchedule(data,options)
    if not state then return false,errorMessage end
    location=normalizedStop(location)
    for _,stop in ipairs(state.scheduledStops) do if stop==location then return true end end
    return false
end

function CrowCaravans.lookup(data,location)
    local state=type(data)=="table" and data.crowCaravans
    local camps=type(state)=="table" and state.camps
    local stop=normalizedStop(location)
    return type(camps)=="table" and stop and camps[tostring(stop)] or nil
end

local function rarityFor(catalog,name)
    if type(catalog.rarityFor)=="function" then return catalog.rarityFor(name) end
    return (catalog.itemRarity and catalog.itemRarity[name]) or "common"
end

local function itemPrice(catalog,lootProgression,name)
    return lootProgression.itemPrice(catalog,name)
end

local function itemListing(campId,merchantId,slot,catalog,lootProgression,name,category,quantity,delivery)
    if not name then return nil end
    local stats=catalog.weaponStats and catalog.weaponStats[name]
    return {
        id=campId..":"..merchantId..":"..slot,
        slot=slot,
        kind=delivery=="ammo" and "ammo" or (stats and "weapon" or "item"),
        category=category,
        item=name,
        rarity=rarityFor(catalog,name),
        weaponTier=stats and stats.tier or nil,
        quantity=math.max(1,math.floor(quantity or 1)),
        amount=delivery=="ammo" and ((catalog.ammoPickupAmounts and catalog.ammoPickupAmounts[name]) or 0) or nil,
        delivery=delivery or "inventory",
        basePrice=itemPrice(catalog,lootProgression,name),
    }
end

local function chooseUnique(roller,fallback,used,rng)
    for _=1,24 do
        local name=roller()
        if name and not used[name] then used[name]=true; return name end
    end
    local candidates={}
    for _,name in ipairs(fallback or {}) do if name and not used[name] then candidates[#candidates+1]=name end end
    table.sort(candidates)
    local name=randomChoice(candidates,rng)
    if name then used[name]=true end
    return name
end

local function weaponCandidates(catalog,tier,kind,used)
    local result={}
    for name,stats in pairs(catalog.weaponStats or {}) do
        local combat=(catalog.weaponCombat or {})[name]
        if name~="scratch" and not name:find("mob%-") and combat and stats.tier==tier
            and (not kind or combat.kind==kind) and not used[name] then
            result[#result+1]=name
        end
    end
    table.sort(result)
    return result
end

local function weaponFamily(catalog,name)
    if type(catalog.weaponFamily)=="function" then return catalog.weaponFamily(name) end
    local combat=(catalog.weaponCombat or {})[name] or {}
    if combat.kind=="melee" then return combat.family or "melee" end
    if combat.ammo=="arrows" then return "bows" end
    if name and (name:find("slingshot") or name:find("boomerang")) then return "slingshots" end
    return "firearms"
end

local function visitOwnedWeapons(data,catalog,callback)
    local seen={}
    for _,collection in ipairs({data and data.equipment,data and data.inventory}) do
        for _,name in pairs(type(collection)=="table" and collection or {}) do
            if type(name)=="string" and not seen[name] then
                local stats=(catalog.weaponStats or {})[name]
                local combat=(catalog.weaponCombat or {})[name]
                if stats and combat and name~="scratch" then
                    seen[name]=true
                    callback(name,stats,combat)
                end
            end
        end
    end
end

local function weaponPreferences(data,catalog)
    local result={ownedFamilies={},triedFamilies={},offeredFamilies={}}
    visitOwnedWeapons(data,catalog,function(name)
        result.ownedFamilies[weaponFamily(catalog,name)]=true
    end)
    for family,uses in pairs(type(data and data.weaponProficiency)=="table" and data.weaponProficiency or {}) do
        if type(family)=="string" and (tonumber(uses) or 0)>0 then result.triedFamilies[family]=true end
    end
    return result
end

local function preferredWeapon(catalog,candidates,preferences,rng)
    if not preferences then return randomChoice(candidates,rng) end
    local best,bestScore={},nil
    for _,name in ipairs(candidates) do
        local family=weaponFamily(catalog,name)
        local unowned=not preferences.ownedFamilies[family]
        local untried=not preferences.triedFamilies[family]
        local fresh=not preferences.offeredFamilies[family]
        local score=(unowned and untried and fresh and 1)
            or (unowned and fresh and 2)
            or (untried and fresh and 3)
            or (unowned and 4)
            or (fresh and 5)
            or 6
        if not bestScore or score<bestScore then best,bestScore={name},score
        elseif score==bestScore then best[#best+1]=name end
    end
    return randomChoice(best,rng)
end

local function chooseWeapon(catalog,targetTier,kind,used,rng,preferences,maximumTier)
    targetTier=clamp(math.floor(targetTier or 1),1,9)
    maximumTier=clamp(math.floor(maximumTier or 9),1,9)
    for distance=0,8 do
        local tiers={targetTier-distance}
        if distance>0 then tiers[#tiers+1]=targetTier+distance end
        for _,tier in ipairs(tiers) do
            if tier>=1 and tier<=maximumTier then
                local candidates=weaponCandidates(catalog,tier,kind,used)
                local name=preferredWeapon(catalog,candidates,preferences,rng)
                if name then
                    used[name]=true
                    if preferences then preferences.offeredFamilies[weaponFamily(catalog,name)]=true end
                    return name
                end
            end
        end
    end
end

local function candidateItems(catalog,lootProgression,predicate,used,minimumRank,maximumRank)
    local result={}
    local ranks=lootProgression.rarityRank or {common=1,uncommon=2,rare=3,legendary=4}
    for name,rarity in pairs(catalog.itemRarity or {}) do
        local rank=ranks[rarity] or 1
        if rank>=(minimumRank or 1) and rank<=(maximumRank or 4) and not used[name]
            and (not predicate or predicate(name)) then result[#result+1]=name end
    end
    table.sort(result)
    return result
end

local function chooseCatalogItem(catalog,lootProgression,predicate,used,minimumRank,maximumRank,rng)
    local name=randomChoice(candidateItems(catalog,lootProgression,predicate,used,minimumRank,maximumRank),rng)
    if name then used[name]=true end
    return name
end

local function unlockedAmmo(catalog,lootProgression,location,used)
    local result={}
    local tier=lootProgression.locationTier(location)
    for name in pairs(catalog.ammoPickupAmounts or {}) do
        if not used[name] and ((lootProgression.ammoUnlockTier or {})[name] or 9)<=tier then result[#result+1]=name end
    end
    table.sort(result)
    return result
end

local function chooseAmmo(data,catalog,lootProgression,location,used,rng)
    local reserve=data and data.ammo or {}
    local durability=data and data.weaponDurability or {}
    local tier=lootProgression.locationTier(location)
    local preferred,seen,lowest={}, {}, nil
    visitOwnedWeapons(data,catalog,function(name,_,combat)
        local ammo=combat.kind=="ranged" and combat.ammo
        local condition=tonumber(durability[name])
        if condition==nil then condition=100 end
        if ammo and condition>0 and not used[ammo] and (catalog.ammoPickupAmounts or {})[ammo]
            and ((lootProgression.ammoUnlockTier or {})[ammo] or 9)<=tier and not seen[ammo] then
            seen[ammo]=true
            local amount=math.max(0,math.floor(tonumber(reserve[ammo]) or 0))
            if lowest==nil or amount<lowest then preferred,lowest={ammo},amount
            elseif amount==lowest then preferred[#preferred+1]=ammo end
        end
    end)
    table.sort(preferred)
    local name=randomChoice(preferred,rng)
    if name then used[name]=true; return name end
    return chooseUnique(function() return lootProgression.rollAmmo(catalog,location,rng) end,
        unlockedAmmo(catalog,lootProgression,location,used),used,rng)
end

local function affordableFood(catalog,lootProgression,used)
    local candidates={}
    for _,name in ipairs((catalog.lootPools and catalog.lootPools.food) or {}) do
        local effect=(catalog.itemEffects or {})[name]
        local price=tonumber(itemPrice(catalog,lootProgression,name))
        if not used[name] and effect and effect.food and not effect.potion and price and price<=CrowCaravans.practicalPriceCap then
            candidates[#candidates+1]=name
        end
    end
    table.sort(candidates)
    return candidates[1]
end

local function hasAffordablePracticalListing(merchant)
    for _,listing in ipairs(merchant and merchant.listings or {}) do
        if tonumber(listing.basePrice) and listing.basePrice<=CrowCaravans.practicalPriceCap then return true end
    end
    return false
end

local function buildPackmaster(campId,data,catalog,lootProgression,location,used,rng)
    local merchant={id="packmaster",name=CrowCaravans.merchantDefinitions.packmaster.name,
        actorId=campId..":packmaster",sprite=CrowCaravans.sprite,
        role=CrowCaravans.merchantDefinitions.packmaster.role,listings={}}
    local food=chooseUnique(function() return lootProgression.rollSupply(catalog,"food",location,rng) end,
        catalog.lootPools and catalog.lootPools.food,used,rng)
    local water=chooseUnique(function() return lootProgression.rollSupply(catalog,"water",location,rng) end,
        catalog.lootPools and catalog.lootPools.water,used,rng)
    local minimum=lootProgression.locationTier(location)>=4 and "uncommon" or "common"
    local medical=chooseUnique(function() return lootProgression.rollMedical(catalog,location,minimum,rng) end,
        candidateItems(catalog,lootProgression,function(name)
            local effect=(catalog.itemEffects or {})[name]
            return effect and effect.health and not effect.potion
        end,used,1,4),used,rng)
    local ammo=chooseAmmo(data,catalog,lootProgression,location,used,rng)
    merchant.listings[1]=itemListing(campId,merchant.id,1,catalog,lootProgression,food,"food",2)
    merchant.listings[2]=itemListing(campId,merchant.id,2,catalog,lootProgression,water,"water",2)
    merchant.listings[3]=itemListing(campId,merchant.id,3,catalog,lootProgression,medical,"medical",1)
    merchant.listings[4]=itemListing(campId,merchant.id,4,catalog,lootProgression,ammo,"ammunition",2,"ammo")
    if not hasAffordablePracticalListing(merchant) then
        if food then used[food]=nil end
        local replacement=affordableFood(catalog,lootProgression,used)
        if replacement then
            used[replacement]=true
            merchant.listings[1]=itemListing(campId,merchant.id,1,catalog,lootProgression,replacement,"food",2)
        elseif food then
            used[food]=true
        end
    end
    return merchant
end

local function buildIronbeak(campId,data,catalog,lootProgression,location,used,rng)
    local merchant={id="ironbeak",name=CrowCaravans.merchantDefinitions.ironbeak.name,
        actorId=campId..":ironbeak",sprite=CrowCaravans.sprite,
        role=CrowCaravans.merchantDefinitions.ironbeak.role,listings={}}
    local tier=lootProgression.locationTier(location)
    local preferences=weaponPreferences(data,catalog)
    local maximumTier=math.min(9,tier+1)
    local weapons={
        chooseWeapon(catalog,tier,"melee",used,rng,preferences,maximumTier),
        chooseWeapon(catalog,tier,"ranged",used,rng,preferences,maximumTier),
        chooseWeapon(catalog,tier,nil,used,rng,preferences,maximumTier),
        chooseWeapon(catalog,maximumTier,nil,used,rng,preferences,maximumTier),
    }
    for slot,name in ipairs(weapons) do
        merchant.listings[slot]=itemListing(campId,merchant.id,slot,catalog,lootProgression,name,
            slot==4 and "premium-weapon" or "weapon",1)
    end
    return merchant
end

local function buildCurioKeeper(campId,data,catalog,lootProgression,location,used,rng,options)
    local merchant={id="curio-keeper",name=CrowCaravans.merchantDefinitions["curio-keeper"].name,
        actorId=campId..":curio-keeper",sprite=CrowCaravans.sprite,
        role=CrowCaravans.merchantDefinitions["curio-keeper"].role,listings={}}
    local normalPotion=chooseCatalogItem(catalog,lootProgression,function(name)
        local effect=(catalog.itemEffects or {})[name]
        return effect and effect.potion and not effect.battleAction
    end,used,3,3,rng)
    local actionPotion=chooseCatalogItem(catalog,lootProgression,function(name)
        local effect=(catalog.itemEffects or {})[name]
        return effect and effect.potion and effect.battleAction
    end,used,3,3,rng)
    local tier=lootProgression.locationTier(location)
    local maximumCapacity=tier<=3 and 10 or (tier<=6 and 14 or 16)
    local currentCapacity=math.max(6,math.floor(tonumber(data.inventoryCapacity) or 6))
    local pack=chooseCatalogItem(catalog,lootProgression,function(name)
        local profile=(catalog.backpackUpgrades or {})[name]
        return profile and profile.capacity>currentCapacity and profile.capacity<=maximumCapacity
    end,used,1,4,rng)
    if not pack then
        pack=chooseCatalogItem(catalog,lootProgression,function(name)
            return not (catalog.ammoPickupAmounts or {})[name] and not (catalog.backpackUpgrades or {})[name]
        end,used,3,3,rng)
    end
    local allowHeart=options and options.allowPermanentHealthRelic==true
    local legendary=location>=39 and randomFloat(rng)<.20
    local relic=chooseCatalogItem(catalog,lootProgression,function(name)
        if (catalog.ammoPickupAmounts or {})[name] then return false end
        if (catalog.backpackUpgrades or {})[name] then return false end
        if not allowHeart and (name=="rose-heart-arrow" or name=="blade-hearts") then return false end
        return true
    end,used,legendary and 4 or 3,legendary and 4 or 3,rng)
    if not relic and legendary then
        relic=chooseCatalogItem(catalog,lootProgression,function(name)
            return not (catalog.ammoPickupAmounts or {})[name] and not (catalog.backpackUpgrades or {})[name]
                and name~="rose-heart-arrow" and name~="blade-hearts"
        end,used,3,3,rng)
    end
    merchant.listings[1]=itemListing(campId,merchant.id,1,catalog,lootProgression,normalPotion,"potion",1)
    merchant.listings[2]=itemListing(campId,merchant.id,2,catalog,lootProgression,actionPotion,"battle-potion",1)
    merchant.listings[3]=itemListing(campId,merchant.id,3,catalog,lootProgression,pack,
        (catalog.backpackUpgrades or {})[pack] and "backpack" or "rare-item",1)
    merchant.listings[4]=itemListing(campId,merchant.id,4,catalog,lootProgression,relic,legendary and "relic" or "curio",1)
    return merchant
end

local function completeMerchant(merchant)
    if type(merchant)~="table" or type(merchant.id)~="string" or type(merchant.listings)~="table" or #merchant.listings~=4 then return false end
    for index=1,4 do
        local listing=merchant.listings[index]
        local quantity=listing and tonumber(listing.quantity)
        if type(listing)~="table" or not listing.item or not listing.id or not listing.basePrice
            or quantity==nil or quantity<0 then return false end
    end
    return true
end

local function merchantRecord(camp,merchantId)
    if type(camp)~="table" or type(merchantId)~="string" then return nil end
    for _,merchant in ipairs(camp.merchants or {}) do if merchant.id==merchantId then return merchant end end
end

local function knownCatalogItem(catalog,name)
    -- Ordinary merchant resale accepts decorative and quest-adjacent inventory
    -- names that intentionally have no item-effect or rarity record. Keep the
    -- caravan callback equally permissive while excluding malformed save data.
    return type(name)=="string" and name:match("%S")~=nil
end

local function resaleCategory(catalog,name)
    if (catalog.ammoPickupAmounts or {})[name] then return "ammunition" end
    if (catalog.weaponStats or {})[name] then return "weapon" end
    if (catalog.backpackUpgrades or {})[name] then return "backpack" end
    return "resale"
end

local function normalizedSequence(value)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return nil end
    value=math.floor(value)
    return value>=1 and value or nil
end

local function normalizedQuantity(value,default)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then value=default or 0 end
    return math.max(0,math.floor(value))
end

local function resaleListing(camp,catalog,lootProgression,merchantId,name,sequence,quantity,acquiredFor)
    local stats=(catalog.weaponStats or {})[name]
    local ammo=(catalog.ammoPickupAmounts or {})[name]
    local entry={
        id=camp.id..":"..merchantId..":resale:"..sequence,
        slot="resale-"..sequence,
        source="resale",
        merchantId=merchantId,
        resaleSequence=sequence,
        sequence=sequence,
        kind=ammo and "ammo" or (stats and "weapon" or "item"),
        category=resaleCategory(catalog,name),
        item=name,
        rarity=rarityFor(catalog,name),
        weaponTier=stats and stats.tier or nil,
        quantity=normalizedQuantity(quantity,1),
        amount=ammo or nil,
        delivery=ammo and "ammo" or "inventory",
        basePrice=itemPrice(catalog,lootProgression,name),
    }
    acquiredFor=tonumber(acquiredFor)
    if acquiredFor and acquiredFor==acquiredFor and acquiredFor>-math.huge and acquiredFor<math.huge then
        entry.acquiredFor=math.max(0,math.floor(acquiredFor))
    end
    return entry
end

local function replaceTable(target,source)
    for key in pairs(target) do target[key]=nil end
    for key,value in pairs(source) do target[key]=value end
    return target
end

local function normalizeResaleStock(camp,catalog,lootProgression)
    if type(camp)~="table" then return {} end
    catalog=catalog or Catalog
    lootProgression=lootProgression or LootProgression
    if type(camp.id)~="string" or camp.id=="" then camp.id=canonicalCampId(camp.stop) end
    local source={}
    for key,entry in pairs(type(camp.resaleStock)=="table" and camp.resaleStock or {}) do
        if type(entry)=="table" and merchantRecord(camp,entry.merchantId) and knownCatalogItem(catalog,entry.item) then
            source[#source+1]={entry=entry,key=key,sequence=normalizedSequence(entry.resaleSequence or entry.sequence)}
        end
    end
    table.sort(source,function(left,right)
        if left.sequence~=right.sequence then
            if left.sequence==nil then return false end
            if right.sequence==nil then return true end
            return left.sequence<right.sequence
        end
        local leftEntry,rightEntry=left.entry,right.entry
        local leftKey=tostring(leftEntry.id or "").."\0"..leftEntry.merchantId.."\0"..leftEntry.item.."\0"..tostring(left.key)
        local rightKey=tostring(rightEntry.id or "").."\0"..rightEntry.merchantId.."\0"..rightEntry.item.."\0"..tostring(right.key)
        return leftKey<rightKey
    end)

    local result,byItem,baseByItem,usedSequences={},{},{},{}
    for _,merchant in ipairs(camp.merchants or {}) do
        for _,listing in ipairs(merchant.listings or {}) do
            if type(listing)=="table" and type(listing.item)=="string" and not baseByItem[listing.item] then
                baseByItem[listing.item]=listing
            end
        end
    end
    local nextSequence=normalizedSequence(camp.nextResaleSequence) or 1
    for _,candidate in ipairs(source) do
        if candidate.sequence then nextSequence=math.max(nextSequence,candidate.sequence+1) end
    end
    for _,candidate in ipairs(source) do
        local original=candidate.entry
        local quantity=normalizedQuantity(original.quantity,1)
        if baseByItem[original.item] then
            local listing=baseByItem[original.item]
            listing.quantity=normalizedQuantity(listing.quantity,0)+quantity
        elseif byItem[original.item] then
            byItem[original.item].quantity=byItem[original.item].quantity+quantity
        else
            local sequence=candidate.sequence
            if not sequence or usedSequences[sequence] then
                while usedSequences[nextSequence] do nextSequence=nextSequence+1 end
                sequence=nextSequence
            end
            usedSequences[sequence]=true
            nextSequence=math.max(nextSequence,sequence+1)
            local entry=replaceTable(original,resaleListing(camp,catalog,lootProgression,
                original.merchantId,original.item,sequence,quantity,original.acquiredFor))
            result[#result+1]=entry
            byItem[original.item]=entry
        end
    end
    table.sort(result,function(left,right) return left.sequence<right.sequence end)
    camp.resaleStock=result
    camp.nextResaleSequence=nextSequence
    return result
end

local function createCamp(data,catalog,lootProgression,location,options)
    local campId=canonicalCampId(location)
    local used={}
    local rng=options and options.rng
    local merchants={
        buildPackmaster(campId,data,catalog,lootProgression,location,used,rng),
        buildIronbeak(campId,data,catalog,lootProgression,location,used,rng),
        buildCurioKeeper(campId,data,catalog,lootProgression,location,used,rng,options),
    }
    for _,merchant in ipairs(merchants) do
        if not completeMerchant(merchant) then return nil,"unable to generate four listings for "..tostring(merchant.id) end
    end
    if not hasAffordablePracticalListing(merchants[1]) then
        return nil,"unable to generate a practical listing at or below "..CrowCaravans.practicalPriceCap.." scrap"
    end
    return {
        version=CrowCaravans.version,
        id=campId,
        stop=location,
        relationshipKey=CrowCaravans.relationshipKey,
        discovered=true,
        departed=false,
        resaleBudgetBase=15+math.floor(location*2),
        resaleBudgetSpent=0,
        resaleStock={},
        nextResaleSequence=1,
        merchantOrder=copyArray(CrowCaravans.merchantOrder),
        merchants=merchants,
    }
end

function CrowCaravans.ensureCamp(data,catalog,location,options)
    catalog=catalog or Catalog
    local lootProgression=(options and options.lootProgression) or LootProgression
    local state,errorMessage=CrowCaravans.ensureSchedule(data,options)
    if not state then return nil,errorMessage end
    location=normalizedStop(location)
    local scheduled=false
    for _,stop in ipairs(state.scheduledStops) do if stop==location then scheduled=true; break end end
    if not scheduled then return nil,"not-scheduled" end
    local key=tostring(location)
    local existing=state.camps[key]
    if type(existing)=="table" then
        local complete=#(existing.merchants or {})==3
        local validMerchants={}
        for _,merchant in ipairs(existing.merchants or {}) do
            if type(merchant)=="table" and type(merchant.id)=="string" then validMerchants[merchant.id]=completeMerchant(merchant)
            else complete=false end
        end
        for _,merchantId in ipairs(CrowCaravans.merchantOrder) do complete=complete and validMerchants[merchantId]==true end
        if complete then normalizeResaleStock(existing,catalog,lootProgression); return existing end
    end
    local camp
    camp,errorMessage=createCamp(data,catalog,lootProgression,location,options)
    if not camp then return nil,errorMessage end
    camp.relationshipKey=state.groupRelationshipId
    if type(existing)=="table" then
        for _,field in ipairs({"returnX","returnY","returnFacing","playerX","playerY","playerFacing","actorStates",
            "purchaseHistory","visited","departed","present","rolled","variantId","resaleBudgetSpent","resaleStock",
            "nextResaleSequence"}) do
            if existing[field]~=nil then camp[field]=existing[field] end
        end
    end
    normalizeResaleStock(camp,catalog,lootProgression)
    state.camps[key]=camp
    return camp
end

function CrowCaravans.merchant(camp,merchantId)
    return merchantRecord(camp,merchantId)
end

function CrowCaravans.normalizeResaleStock(camp,catalog,lootProgression)
    return normalizeResaleStock(camp,catalog or Catalog,lootProgression or LootProgression)
end

function CrowCaravans.addResaleListing(camp,merchantId,name,catalog,lootProgression,acquiredFor,quantity)
    catalog=catalog or Catalog
    lootProgression=lootProgression or LootProgression
    if type(camp)~="table" then return nil,"missing-camp" end
    local merchant=merchantRecord(camp,merchantId)
    if not merchant then return nil,"missing-merchant" end
    if not knownCatalogItem(catalog,name) then return nil,"unknown-item" end
    normalizeResaleStock(camp,catalog,lootProgression)
    quantity=math.max(1,normalizedQuantity(quantity,1))
    for _,otherMerchant in ipairs(camp.merchants or {}) do
        for _,listing in ipairs(otherMerchant.listings or {}) do
            if listing.item==name then
                listing.quantity=normalizedQuantity(listing.quantity,0)+quantity
                return listing,false
            end
        end
    end
    for _,listing in ipairs(camp.resaleStock) do
        if listing.item==name then
            listing.quantity=normalizedQuantity(listing.quantity,0)+quantity
            return listing,false
        end
    end
    local sequence=normalizedSequence(camp.nextResaleSequence) or 1
    local listing=resaleListing(camp,catalog,lootProgression,merchantId,name,sequence,quantity,acquiredFor)
    camp.resaleStock[#camp.resaleStock+1]=listing
    camp.nextResaleSequence=sequence+1
    return listing,true
end

function CrowCaravans.tradeListings(camp,merchantId,catalog,lootProgression)
    local merchant=merchantRecord(camp,merchantId)
    if not merchant then return {} end
    normalizeResaleStock(camp,catalog or Catalog,lootProgression or LootProgression)
    local result={}
    for _,listing in ipairs(merchant.listings or {}) do result[#result+1]=listing end
    for _,listing in ipairs(camp.resaleStock or {}) do
        if listing.merchantId==merchantId then result[#result+1]=listing end
    end
    return result
end

function CrowCaravans.listing(camp,merchantId,listingIdOrIndex)
    local listings=CrowCaravans.tradeListings(camp,merchantId)
    if type(listingIdOrIndex)=="number" then return listings[listingIdOrIndex] end
    for _,listing in ipairs(listings) do if listing.id==listingIdOrIndex then return listing end end
end

function CrowCaravans.consumeListing(camp,merchantId,listingIdOrIndex,amount)
    local listing=CrowCaravans.listing(camp,merchantId,listingIdOrIndex)
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    if not listing then return false,"missing-listing" end
    listing.quantity=normalizedQuantity(listing.quantity,0)
    if listing.quantity<amount then return false,"sold-out" end
    listing.quantity=listing.quantity-amount
    return true,listing
end

function CrowCaravans.availableBudget(camp,terms)
    if type(camp)~="table" then return 0 end
    local bonus=type(terms)=="table" and math.max(0,math.floor(tonumber(terms.budgetBonus) or 0)) or 0
    local base=math.max(0,math.floor(tonumber(camp.resaleBudgetBase) or 0))
    local spent=math.max(0,math.floor(tonumber(camp.resaleBudgetSpent) or 0))
    return math.max(0,base+bonus-spent)
end

function CrowCaravans.spendBudget(camp,amount,terms)
    amount=math.max(0,math.floor(tonumber(amount) or 0))
    if amount==0 then return true,CrowCaravans.availableBudget(camp,terms) end
    if CrowCaravans.availableBudget(camp,terms)<amount then return false,"budget" end
    camp.resaleBudgetSpent=math.max(0,math.floor(tonumber(camp.resaleBudgetSpent) or 0))+amount
    return true,CrowCaravans.availableBudget(camp,terms)
end

function CrowCaravans.buyPrice(data,camp,listing,Relationships)
    if type(listing)~="table" then return nil end
    if Relationships and type(Relationships.buyPrice)=="function" then
        return Relationships.buyPrice(data,(camp and camp.relationshipKey) or CrowCaravans.relationshipKey,listing.basePrice)
    end
    return listing.basePrice
end

function CrowCaravans.resalePrice(data,camp,name,catalog,Relationships)
    catalog=catalog or Catalog
    local base=LootProgression.resalePrice(catalog,name,data and data.weaponDurability and data.weaponDurability[name])
    if Relationships and type(Relationships.sellPrice)=="function" then
        return Relationships.sellPrice(data,(camp and camp.relationshipKey) or CrowCaravans.relationshipKey,base)
    end
    return base
end

function CrowCaravans.markDeparted(data,location)
    local camp=CrowCaravans.lookup(data,location)
    if not camp then return false end
    camp.departed=true
    return true
end

function CrowCaravans.isActive(camp)
    return type(camp)=="table" and camp.departed~=true
end

function CrowCaravans.audit(catalog,lootProgression)
    catalog=catalog or Catalog
    lootProgression=lootProgression or LootProgression
    local seed=173
    local function rng()
        seed=(seed*1103515245+12345)%2147483648
        return seed/2147483648
    end
    local data={inventoryCapacity=6,weaponDurability={}}
    local state,errorMessage=CrowCaravans.ensureSchedule(data,{rng=rng,excludedStops={15,47}})
    if not state then return {ready=false,error=errorMessage} end
    local listingIds,itemNames={},{ }
    local listingCount,merchantCount=0,0
    local firstCamp
    for _,stop in ipairs(state.scheduledStops) do
        local camp,reason=CrowCaravans.ensureCamp(data,catalog,stop,{rng=rng,lootProgression=lootProgression})
        if not camp then return {ready=false,error=reason} end
        firstCamp=firstCamp or camp
        merchantCount=merchantCount+#camp.merchants
        for _,merchant in ipairs(camp.merchants) do
            for _,listing in ipairs(merchant.listings) do
                listingCount=listingCount+1
                if listingIds[listing.id] then return {ready=false,error="duplicate listing id"} end
                listingIds[listing.id]=true
                local campItemKey=camp.id..":"..listing.item
                if itemNames[campItemKey] then return {ready=false,error="duplicate camp item"} end
                itemNames[campItemKey]=true
            end
        end
    end
    local persistent=CrowCaravans.ensureCamp(data,catalog,firstCamp.stop,{rng=function() return .99 end,lootProgression=lootProgression})==firstCamp
    local firstListing=firstCamp.merchants[1].listings[1]
    local before=firstListing.quantity
    local consumed=CrowCaravans.consumeListing(firstCamp,"packmaster",firstListing.id)
    local budgetBefore=CrowCaravans.availableBudget(firstCamp,{budgetBonus=3})
    local spent,budgetAfter=CrowCaravans.spendBudget(firstCamp,5,{budgetBonus=3})
    local scheduledElsewhere=CrowCaravans.isScheduled(data,1)
    local repairData={inventoryCapacity=6,weaponDurability={},crowCaravans={scheduledStops=copyArray(state.scheduledStops),
        activeCampId="legacy-camp-id",camps={[tostring(firstCamp.stop)]={id="legacy-camp-id",stop=firstCamp.stop,visited=true}}}}
    local repaired=CrowCaravans.ensureCamp(repairData,catalog,firstCamp.stop,{rng=rng,lootProgression=lootProgression})
    local repairedComplete=repaired and #repaired.merchants==3 and repaired.visited==true
        and repairData.crowCaravans.activeCampId==canonicalCampId(firstCamp.stop)
    local minimumGap=math.min(state.scheduledStops[2]-state.scheduledStops[1],state.scheduledStops[3]-state.scheduledStops[2])
    local ready=#state.scheduledStops==3 and minimumGap>=8 and merchantCount==9 and listingCount==36 and persistent and consumed
        and firstCamp.relationshipKey==state.groupRelationshipId and state.groupRelationshipId==CrowCaravans.relationshipKey
        and repairedComplete and firstListing.quantity==before-1 and spent and budgetAfter==budgetBefore-5 and not scheduledElsewhere
    return {ready=ready,scheduledStops=copyArray(state.scheduledStops),camps=3,merchants=merchantCount,
        listings=listingCount,persistent=persistent,consumed=consumed,budgetBefore=budgetBefore,budgetAfter=budgetAfter,
        minimumGap=minimumGap,repairedComplete=repairedComplete,curve="crow-caravans-v1"}
end

return CrowCaravans
