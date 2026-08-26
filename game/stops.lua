local Stops = {}
local LootProgression = require("game.loot_progression")
local QuestProgression = require("game.quest_progression")

local props={"pine-tree","fir-tree","small-broadleaf-tree","large-broadleaf-tree","autumn-tree","white-birch","dead-white-tree","dead-brown-tree","tall-stump","mossy-stump","flowering-shrub","white-flower-shrub","red-berry-bush","fern-cluster","tall-reeds","red-mushrooms","brown-mushrooms","wild-herb-patch","butterfly-flowers","mossy-boulders","fallen-log","hollow-log","branch-pile","broken-fence","signpost","straight-fence","stone-fire-ring","lit-campfire","patched-tent","rusty-barrel","wooden-barrel","supply-crate","reinforced-crate","old-stone-well","weathered-gravestone","loose-stones"}
local wildlife={"gray-rabbit","brown-rabbit","young-deer","adult-deer","sparrow","crow","owl","blue-butterfly","orange-butterfly","small-lizard","field-mouse","perched-songbird"}
local decorationSpots={{65,535},{215,590},{335,660},{515,600},{690,670},{825,575},{920,650}}

local function offerRoll(location) return QuestProgression.rollOffer(location) end

local function stock(catalog,location) return LootProgression.tradeStock(catalog,location) end

local function differentNpc(roster,outside)
    if #roster<=1 then return outside end
    local inside
    repeat inside=roster[love.math.random(#roster)] until inside~=outside
    return inside
end

local function generatedInteriorIndex(stop)
    -- The legacy five interiors occupy slots 1-5. Generated stop interiors
    -- follow them in five-image groups, one group per stop.
    local first=6+((math.max(1,math.min(50,stop))-1)*5)
    return first+love.math.random(0,4)
end

function Stops.ensureDoor(data,catalog,doorIndex)
    local layout=Stops.ensure(data,catalog,"house")
    local door=math.max(1,doorIndex or 1)
    layout.houseDoors=layout.houseDoors or {}
    local key=tostring(door); local home=layout.houseDoors[key]
    if not home then
        local roster=data.npcRoster or {}
        local used={}
        for _,entry in pairs(layout.houseDoors) do if entry.npc then used[entry.npc]=true end end
        local candidates={}
        for _,npc in ipairs(roster) do if not used[npc] and npc~=layout.npcOutside then candidates[#candidates+1]=npc end end
        if #candidates==0 then for _,npc in ipairs(roster) do if npc~=layout.npcOutside then candidates[#candidates+1]=npc end end end
        home={interior=generatedInteriorIndex(data.location or 1),npc=(#candidates>0 and candidates[love.math.random(#candidates)] or layout.npcInside or layout.npcOutside),door=door}
        layout.houseDoors[key]=home
    end
    layout.activeHouseDoor=door
    layout.interior=home.interior
    layout.npcInside=home.npc
    return layout
end

function Stops.ensure(data,catalog,scene)
    local key=tostring(data.location); local layout=data.stopLayouts[key]; local roster=data.npcRoster or {}
    if not layout then
        layout={houseX=love.math.random(390,700),treeA=love.math.random(110,250),treeB=love.math.random(760,860),house=love.math.random(1,8),tree=love.math.random(1,7),interior=generatedInteriorIndex(data.location or 1)}
        if #roster>0 then layout.npcOutside=roster[love.math.random(#roster)]; layout.npcInside=differentNpc(roster,layout.npcOutside); layout.npc=layout.npcOutside end
        layout.offer=offerRoll(data.location); data.stopLayouts[key]=layout
    end
    if (data.location or 1)<=5 and (not layout.interior or layout.interior<=5) then layout.interior=generatedInteriorIndex(data.location or 1) end
    layout.interior=layout.interior or generatedInteriorIndex(data.location or 1); layout.npcOutside=layout.npcOutside or layout.npc or roster[1]
    layout.npcInside=layout.npcInside or differentNpc(roster,layout.npcOutside); layout.npc=layout.npcOutside
    -- Offers belong to the individual critter, never to the whole stop.  Keep
    -- the old `offer` field only as a compatibility value for older UI code.
    layout.npcOffers=layout.npcOffers or {}
    local function ensureOffer(npc)
        if not npc then return end
        local lower=npc:lower()
        if lower:find("crow%-merchant") then
            layout.npcOffers[npc]="trade"
        elseif layout.npcOffers[npc]==nil then
            layout.npcOffers[npc]=offerRoll(data.location)
        end
    end
    ensureOffer(layout.npcOutside); ensureOffer(layout.npcInside)
    -- Avoid the old “everyone repeats the same quest” presentation when both
    -- visible residents happen to roll the same non-empty offer.
    if layout.npcOutside and layout.npcInside and layout.npcOutside~=layout.npcInside then
        local first,second=layout.npcOffers[layout.npcOutside],layout.npcOffers[layout.npcInside]
        if first and second and first==second and first~="none" and layout.npcInside:lower():find("crow%-merchant") == nil then
            local replacement=second
            for _=1,4 do replacement=offerRoll(data.location); if replacement~=first then break end end
            layout.npcOffers[layout.npcInside]=replacement==first and "none" or replacement
        end
    end
    layout.offer=layout.npcOffers[layout.npcOutside] or layout.offer or "none"
    if not layout.npcWeapon then layout.npcWeapon=LootProgression.rollWeapon(catalog,data.location,"common") end
    if layout.offer=="trade" then layout.tradeStock=layout.tradeStock or stock(catalog,data.location); layout.tradeBudget=layout.tradeBudget or (10+math.floor((data.location or 1)*1.8)); layout.tradeNpc=layout.tradeNpc or layout.npc end
    if not layout.decorations then
        layout.decorations={}
        for index=1,love.math.random(5,7) do local spot=decorationSpots[index]; local name=props[love.math.random(#props)]; local tall=name:find("tree") or name:find("birch"); layout.decorations[#layout.decorations+1]={kind="prop",name=name,x=spot[1]+love.math.random(-18,18),y=spot[2]+love.math.random(-12,12),scale=tall and .52 or (.27+love.math.random()*.12)} end
        local spot=decorationSpots[love.math.random(#decorationSpots)]; layout.decorations[#layout.decorations+1]={kind="wildlife",name=wildlife[love.math.random(#wildlife)],x=spot[1]+love.math.random(-25,25),y=spot[2]-15,scale=.24+love.math.random()*.08}
    end
    data.currentNPC=(scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    -- Additional house doors can introduce NPCs beyond the two legacy slots.
    -- Give those residents their own independent offer as well.
    if data.currentNPC and layout.npcOffers[data.currentNPC]==nil then
        local lower=data.currentNPC:lower()
        layout.npcOffers[data.currentNPC]=lower:find("crow%-merchant") and "trade" or offerRoll(data.location)
    end
    local currentOffer=layout.npcOffers[data.currentNPC]
    layout.offer=currentOffer or layout.offer or "none"
    if currentOffer=="trade" then layout.tradeStock=layout.tradeStock or stock(catalog,data.location); layout.tradeBudget=layout.tradeBudget or (10+math.floor((data.location or 1)*1.8)); layout.tradeNpc=data.currentNPC end
    return layout
end

return Stops
