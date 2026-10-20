local Stops = {}
local Random = require("game.coop_random")
local LootProgression = require("game.loot_progression")
local QuestProgression = require("game.quest_progression")
local StopHelpProgression = require("game.stop_help_progression")
local HelpDialogueQuests = require("game.help_dialogue_quests")
local Conversations = require("game.npc_conversations")
local Home = require("game.home_stop")
local Identity=require('game.npc_identity')

local props={"pine-tree","fir-tree","small-broadleaf-tree","large-broadleaf-tree","autumn-tree","white-birch","dead-white-tree","dead-brown-tree","tall-stump","mossy-stump","flowering-shrub","white-flower-shrub","red-berry-bush","fern-cluster","tall-reeds","red-mushrooms","brown-mushrooms","wild-herb-patch","butterfly-flowers","mossy-boulders","fallen-log","hollow-log","branch-pile","broken-fence","signpost","straight-fence","stone-fire-ring","lit-campfire","patched-tent","rusty-barrel","wooden-barrel","supply-crate","reinforced-crate","old-stone-well","weathered-gravestone","loose-stones"}
local wildlife={"gray-rabbit","brown-rabbit","young-deer","adult-deer","sparrow","crow","owl","blue-butterfly","orange-butterfly","small-lizard","field-mouse","perched-songbird"}
local decorationSpots={{65,535},{215,590},{335,660},{515,600},{690,670},{825,575},{920,650}}

local function offerRoll(location,rng) return QuestProgression.rollOffer(location,rng) end

local function stock(catalog,location,rng) return LootProgression.tradeStock(catalog,location,rng) end

local function differentNpc(roster,outside,rng)
    local random=Random.range(rng)
    if #roster<=1 then return outside end
    local inside
    repeat inside=roster[random(#roster)] until inside~=outside
    return inside
end

local function generatedInteriorIndex(stop,rng)
    local random=Random.range(rng)
    -- The legacy five interiors occupy slots 1-5. Generated stop interiors
    -- follow them in five-image groups, one group per stop.
    local first=6+((math.max(1,math.min(50,stop))-1)*5)
    return first+random(0,4)
end

function Stops.ensureDoor(data,catalog,doorIndex,rng)
    local random=Random.range(rng)
    local layout=Stops.ensure(data,catalog,"house",rng)
    local door=math.max(1,doorIndex or 1)
    layout.houseDoors=layout.houseDoors or {}
    local key=tostring(door); local home=layout.houseDoors[key]
    if not home then
        local roster=data.npcRoster or {}
        local used={}
        for _,entry in pairs(layout.houseDoors) do if entry.npc then used[entry.npc]=true end end
        local reserved
        for file,targetDoor in pairs(layout.reservedResidents or {}) do
            if targetDoor==door and not used[file] then reserved=file else used[file]=true end
        end
        local candidates={}
        for _,npc in ipairs(roster) do if not used[npc] and npc~=layout.npcOutside then candidates[#candidates+1]=npc end end
        if #candidates==0 then for _,npc in ipairs(roster) do if npc~=layout.npcOutside then candidates[#candidates+1]=npc end end end
        home={interior=generatedInteriorIndex(data.location or 1,rng),npc=reserved or (#candidates>0 and candidates[random(#candidates)] or layout.npcInside or layout.npcOutside),door=door}
        layout.houseDoors[key]=home
    end
    layout.activeHouseDoor=door
    layout.interior=home.interior
    layout.npcInside=home.npc
    Identity.ensure(data,home.npc,data.location,door)
    return layout
end

function Stops.ensure(data,catalog,scene,rng)
    local selectedNPC=data.currentNPC
    if Home.isHome(data) then
        return Home.layout(data)
    end
    local random=Random.range(rng)
    local key=tostring(data.location); local layout=data.stopLayouts[key]; local roster=data.npcRoster or {}
    if not layout then
        layout={houseX=random(390,700),treeA=random(110,250),treeB=random(760,860),house=random(1,8),tree=random(1,7),interior=generatedInteriorIndex(data.location or 1,rng)}
        if #roster>0 then layout.npcOutside=roster[random(#roster)]; layout.npcInside=differentNpc(roster,layout.npcOutside,rng); layout.npc=layout.npcOutside end
        layout.offer=offerRoll(data.location,rng); data.stopLayouts[key]=layout
    end
    if (data.location or 1)<=5 and (not layout.interior or layout.interior<=5) then layout.interior=generatedInteriorIndex(data.location or 1,rng) end
    layout.interior=layout.interior or generatedInteriorIndex(data.location or 1,rng); layout.npcOutside=layout.npcOutside or layout.npc or roster[1]
    for file,door in pairs(layout.reservedResidents or {}) do
        if door==1 and not layout.npcInside then layout.npcInside=file; break end
    end
    layout.npcInside=layout.npcInside or differentNpc(roster,layout.npcOutside,rng); layout.npc=layout.npcOutside
    -- A stop now has one ordinary request opportunity rather than giving
    -- every resident an independent roll. Merchants retain their trade role.
    layout.npcOffers=layout.npcOffers or {}; layout.helpRequests=layout.helpRequests or {}
    local function assignOffer(npc,kind)
        if not npc then return end
        local lower=npc:lower()
        if lower:find("crow%-merchant") then
            layout.npcOffers[npc]="trade"
        else layout.npcOffers[npc]=kind or "none" end
        local assigned=layout.npcOffers[npc]
        if assigned=="item" or assigned=="aid" then StopHelpProgression.ensureRequest(layout,npc,assigned,data.location,data) end
        if assigned=="dialogue" then HelpDialogueQuests.ensure(data,layout,npc,data.location) end
    end
    if (layout.offerPolicyVersion or 0)<StopHelpProgression.policyVersion then
        layout.npcOffers={}; layout.helpRequests=layout.helpRequests or {}
        assignOffer(layout.npcOutside,offerRoll(data.location,rng)); assignOffer(layout.npcInside,"none")
        if layout.npcOffers[layout.npcOutside]=="dialogue" then data.questAsked[tostring(data.location)..":"..tostring(layout.npcOutside)]=nil end
        layout.offerPolicyVersion=StopHelpProgression.policyVersion
    else
        if layout.npcOffers[layout.npcOutside]==nil then assignOffer(layout.npcOutside,offerRoll(data.location,rng)) end
        if layout.npcOffers[layout.npcInside]==nil then assignOffer(layout.npcInside,"none") end
        for npc,kind in pairs(layout.npcOffers) do
            if kind=="item" or kind=="aid" then StopHelpProgression.ensureRequest(layout,npc,kind,data.location,data) end
            if kind=="dialogue" then HelpDialogueQuests.ensure(data,layout,npc,data.location) end
        end
    end
    layout.offer=layout.npcOffers[layout.npcOutside] or layout.offer or "none"
    local recruited=layout.coopOffers and layout.coopOffers[layout.npcOutside]
    if not layout.npcWeapon and not (recruited and recruited.kind=='ride' and recruited.status=='accepted') then
        layout.npcWeapon=LootProgression.rollWeapon(catalog,data.location,"common",rng)
    end
    if layout.offer=="trade" then layout.tradeStock=layout.tradeStock or stock(catalog,data.location,rng); layout.tradeBudget=layout.tradeBudget or (10+math.floor((data.location or 1)*1.8)); layout.tradeNpc=layout.tradeNpc or layout.npc end
    if not layout.decorations then
        layout.decorations={}
        for index=1,random(5,7) do local spot=decorationSpots[index]; local name=props[random(#props)]; local tall=name:find("tree") or name:find("birch"); layout.decorations[#layout.decorations+1]={kind="prop",name=name,x=spot[1]+random(-18,18),y=spot[2]+random(-12,12),scale=tall and .52 or (.27+random()*.12)} end
        local spot=decorationSpots[random(#decorationSpots)]; layout.decorations[#layout.decorations+1]={kind="wildlife",name=wildlife[random(#wildlife)],x=spot[1]+random(-25,25),y=spot[2]-15,scale=.24+random()*.08}
    end
    data.currentNPC=(scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    if layout.residentVersion==1 and type(layout.residentKeys)=='table' then
        local first,selected
        for _,residentKey in ipairs(layout.residentKeys) do
            local resident=data.npcStates and data.npcStates[residentKey]
            local offer=resident and layout.coopOffers and layout.coopOffers[resident.file]
            local departed=offer and offer.kind=='ride' and offer.status=='accepted'
            if resident then for _,passenger in ipairs(data.passengers or {}) do
                if passenger.npc==resident.file and passenger.origin==data.location then departed=true; break end
            end end
            if resident and resident.scene==scene and (scene~='house' or resident.homeDoor==(data.activeHouseDoor or 1))
                and not departed then
                first=first or resident.file
                if resident.file==selectedNPC then selected=resident.file end
            end
        end
        data.currentNPC=selected or first
    end
    -- Additional house doors can introduce NPCs beyond the two legacy slots.
    -- Give those residents their own independent offer as well.
    if data.currentNPC and layout.npcOffers[data.currentNPC]==nil then assignOffer(data.currentNPC,"none") end
    Identity.ensureStop(data,layout)
    Conversations.assign(data,layout,random)
    local currentOffer=layout.npcOffers[data.currentNPC]
    layout.offer=currentOffer or layout.offer or "none"
    if currentOffer=="trade" then layout.tradeStock=layout.tradeStock or stock(catalog,data.location,rng); layout.tradeBudget=layout.tradeBudget or (10+math.floor((data.location or 1)*1.8)); layout.tradeNpc=data.currentNPC end
    if layout.tradeStock then
        LootProgression.ensureCraftingStock(layout,catalog,data.location)
        LootProgression.ensureFurnitureStock(layout,catalog,data.location)
    end
    if scene=="stop" then require("game.stop_hotspots").ensure(data) end
    return layout
end

return Stops
