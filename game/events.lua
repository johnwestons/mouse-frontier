local Events = {}
local LootProgression = require("game.loot_progression")

local function C(label,hint,data)
    data=data or {}; data.label=label; data.hint=hint; return data
end

local function E(category,id,title,text,artSheet,artIndex,choices,clue)
    return {category=category,id=id,title=title,text=text,artSheet=artSheet,artIndex=artIndex,choices=choices,clue=clue}
end

Events.storyStops={3,7,12,17,22,27,32,37,43,48}

local definitions={
    battle={
        E("battle","rail-bandits","RAIL BANDITS","Masked scavengers have chained scrap across the rails and demand your provisions.","battle-a",1,{
            C("BREAK THE BLOCKADE","Fight for valuable gear; risk health and ammunition.",{battle=true,rewardQuality=2}),
            C("PAY THE TOLL","Lose supplies, but avoid wounds.",{cost={food=2,coal=2}}),
            C("CUT A SIDE PATH","Spend coal and arrive safely with a little salvage.",{cost={coal=3},reward={scrap=2}})}),
        E("battle","tunnel-nest","NEST IN THE TUNNEL","Mutated creatures have nested between the sleepers inside a dark tunnel.","battle-a",2,{
            C("CLEAR THE NEST","Hard fight; strong weapon and ammunition rewards.",{battle=true,count=3,rewardQuality=3}),
            C("SMOKE THEM OUT","Spend coal and lose some health, but collect scrap.",{cost={coal=3,health=2},reward={scrap=5}}),
            C("WAIT FOR DAYLIGHT","Lose food and water, avoiding combat.",{cost={food=2,water=2}})}),
        E("battle","derailed-raiders","DERAILED RAIDERS","Raiders are stripping a derailed freight car and turn their weapons toward your train.","battle-a",3,{
            C("TAKE THE FREIGHT","Fight multiple raiders for premium loot.",{battle=true,count=4,rewardQuality=3}),
            C("TRADE INFORMATION","Spend scrap to learn a safe route and gain water.",{cost={scrap=4},reward={water=3}}),
            C("BACK THE TRAIN UP","Burn extra coal and avoid the confrontation.",{cost={coal=3}})}),
        E("battle","bridge-ambush","AMBUSH AT THE BRIDGE","Shapes move beneath a patched bridge as the locomotive slows to cross.","battle-a",4,{
            C("CHARGE ACROSS","Immediate battle with increased salvage.",{battle=true,count=3,rewardQuality=2}),
            C("REINFORCE THE BRIDGE","Spend supplies and cross without a fight.",{cost={coal=2,food=1},reward={scrap=2}}),
            C("SCOUT THE RIVERBED","Risk injury but uncover ammunition.",{cost={health=3},ammo=true})}),
        E("battle","night-stalkers","NIGHT STALKERS","Glowing eyes pace the train while everyone tries to sleep.","battle-a",5,{
            C("HUNT THE PACK","Dangerous battle; excellent equipment reward.",{battle=true,count=4,rewardQuality=3}),
            C("KEEP THE FIRE HIGH","Consume coal and remain safe.",{cost={coal=4}}),
            C("MOVE WITHOUT LIGHTS","Save fuel but suffer damage and lose food.",{cost={health=3,food=2},reward={coal=1}})})
    },
    help={
        E("help","dry-camp","THE DRY CAMP","A tired family has no water left and their cart animal cannot stand.","help-a",1,{
            C("SHARE WATER","Lose water; receive scrap and goodwill.",{cost={water=3},reward={scrap=5}}),
            C("REPAIR THEIR CART","Spend coal and gain a useful item.",{cost={coal=2},itemPool="uncommon"}),
            C("MARK A WELL","No cost or reward, but they can help themselves.",{})}),
        E("help","injured-courier","INJURED COURIER","A courier lies beside a torn mailbag while shapes circle in the brush.","help-a",2,{
            C("TREAT THE WOUND","Use food and gain medicine plus scrap.",{cost={food=2},itemPool="medical",reward={scrap=3}}),
            C("ESCORT THE COURIER","Fight the circling mobs for good loot.",{battle=true,count=3,rewardQuality=2,defense=true}),
            C("TAKE THE MAIL WEST","Lose time and water, but gain scrap.",{cost={water=2},reward={scrap=4}})}),
        E("help","broken-pump","SETTLEMENT PUMP","A settlement's hand pump has seized and their storage jars are nearly empty.","help-a",3,{
            C("FIX THE PUMP","Spend coal; settlers share food and water.",{cost={coal=2},reward={food=3,water=4}}),
            C("DONATE WATER","Large water cost, larger scrap reward.",{cost={water=4},reward={scrap=7}}),
            C("POINT TO THE OLD ROAD","Share a safe route without spending supplies.",{})}),
        E("help","lost-caravan","LOST CARAVAN","A caravan has followed old rails into a dead end and asks for directions west.","help-a",4,{
            C("GUIDE THEM PERSONALLY","Spend food and water; earn a rare item.",{cost={food=2,water=2},itemPool="rare"}),
            C("DRAW A ROUTE","Small food cost for scrap.",{cost={food=1},reward={scrap=4}}),
            C("POINT TO THE TRACKS","Neutral; save your provisions.",{})}),
        E("help","cold-shelter","COLD NIGHT SHELTER","Several critters huddle around a dead stove while freezing wind tears at their tent.","help-a",5,{
            C("SHARE THE TRAIN","Spend food; receive coal and medicine.",{cost={food=3},reward={coal=4},itemPool="medical"}),
            C("REPAIR THE STOVE","Spend coal; receive scrap and ammunition.",{cost={coal=2},reward={scrap=4},ammo=true}),
            C("BUILD A WINDBREAK","Help them brace the tent without spending supplies.",{})})
    },
    fortune={
        E("fortune","sealed-pantry","SEALED PANTRY","A collapsed station wall hides a pantry untouched since the flash.","fortune-a",1,{
            C("OPEN IT CAREFULLY","Gain food and water, spend time and health.",{cost={health=1},reward={food=4,water=4}}),
            C("PRY OUT THE LOCKBOX","Gain a scaled item and scrap.",{itemPool="scaled",reward={scrap=4}}),
            C("MARK IT FOR OTHERS","Take only a little food.",{reward={food=2}})}),
        E("fortune","coal-seam","EXPOSED COAL SEAM","Rain has uncovered a dark coal seam beside the tracks.","fortune-a",2,{
            C("MINE DEEPLY","Gain plenty of coal, lose health.",{cost={health=2},reward={coal=7}}),
            C("TAKE THE LOOSE PIECES","Safe, moderate coal reward.",{reward={coal=4}}),
            C("SEARCH THE CUT","Gain scrap and ammunition instead.",{reward={scrap=3},ammo=true})}),
        E("fortune","supply-drop","OLD RELIEF CACHE","A faded relief marker points toward buried emergency supplies.","fortune-a",3,{
            C("DIG UP EVERYTHING","Gain mixed supplies but lose health.",{cost={health=2},reward={food=3,water=3,coal=3}}),
            C("TAKE THE MEDICAL CASE","Receive scaled medicine.",{itemPool="medical"}),
            C("TAKE THE AMMO TIN","Receive level-appropriate ammunition.",{ammo=true})}),
        E("fortune","friendly-merchant","TRAVELING TINKER","A cheerful tinker offers one favorable exchange before moving east.","fortune-a",4,{
            C("BUY A WEAPON","Spend scrap for a scaled weapon.",{cost={scrap=5},weapon=true}),
            C("BUY PROVISIONS","Spend scrap for food and water.",{cost={scrap=3},reward={food=3,water=3}}),
            C("TRADE STORIES","No cost; the tinker gifts a little scrap.",{reward={scrap=2}})}),
        E("fortune","rain-catch","CLEAN RAIN","A brief clean storm fills every sound container around the stop.","fortune-a",5,{
            C("FILL EVERY VESSEL","Gain lots of water but lose food to wet storage.",{cost={food=1},reward={water=7}}),
            C("WASH AND REST","Recover health and some water.",{reward={health=5,water=3}}),
            C("KEEP MOVING","Gain a little water without delay.",{reward={water=2}})})
    },
    mishap={
        E("mishap","broken-axle","BROKEN AXLE","The train lurches sideways as a patched axle begins to split.","mishap-a",1,{
            C("USE PROPER PARTS","Spend scrap and coal; avoid injury.",{cost={scrap=3,coal=2}}),
            C("IMPROVISE A SPLINT","Lose health but use less coal.",{cost={health=3,coal=1}}),
            C("LIMP TO THE STOP","Use whatever food and water remain; this last resort never blocks.",{cost={food=2,water=2},fallback=true})}),
        E("mishap","spoiled-rations","SPOILED RATIONS","A leaking roof has soaked several sacks of food.","mishap-a",2,{
            C("SALVAGE WHAT YOU CAN","Lose some food and health.",{cost={food=2,health=1}}),
            C("BURN THE SPOILED FOOD","Lose more food; preserve health.",{cost={food=3}}),
            C("DISCARD WHAT REMAINS","Lose up to two food; this last resort never blocks.",{cost={food=2},fallback=true})}),
        E("mishap","dry-boiler","DRY BOILER","The boiler drinks the last clean water during a steep climb.","mishap-a",3,{
            C("USE DRINKING WATER","Lose water but protect the engine.",{cost={water=4}}),
            C("RUN IT LOW","Lose health and coal from the rough ride.",{cost={health=2,coal=2}}),
            C("COLLECT MUDDY WATER","Use what water remains and risk health; this last resort never blocks.",{cost={health=3,water=1},fallback=true})}),
        E("mishap","cargo-shift","SHIFTING CARGO","A hard turn sends unsecured furniture and crates across the car.","mishap-a",4,{
            C("STOP AND SECURE IT","Lose coal and water.",{cost={coal=2,water=1}}),
            C("CATCH THE HEAVY CRATE","Lose health but find scrap.",{cost={health=3},reward={scrap=2}}),
            C("LET IT SETTLE","Risk one backpack item; this last resort never blocks.",{loseItem=true,fallback=true})}),
        E("mishap","ash-storm","ASH STORM","A wall of ash swallows the tracks and chokes the locomotive.","mishap-a",5,{
            C("PUSH THROUGH FAST","Spend coal and suffer some damage.",{cost={coal=4,health=2}}),
            C("SEAL THE TRAIN","Lose food and water while waiting.",{cost={food=2,water=2}}),
            C("FOLLOW OLD SIGNALS","Use whatever scrap and coal remain; this last resort never blocks.",{cost={scrap=4,coal=1},fallback=true})})
    },
    defense={
        E("defense","settlement-siege","SETTLEMENT UNDER SIEGE","A ring of mobs closes around a patched settlement while defenders wave from the roofs.","defense-a",1,{
            C("JOIN THE DEFENDERS","Large allied battle; premium rewards.",{battle=true,count=4,allies=3,defense=true,rewardQuality=3}),
            C("EVACUATE THE CHILDREN","Spend food and water; earn scrap and medicine.",{cost={food=3,water=3},reward={scrap=7},itemPool="medical"}),
            C("DRAW THE MOBS AWAY","Lose coal and health; settlement survives.",{cost={coal=4,health=3},reward={scrap=4}})}),
        E("defense","caravan-circle","CARAVAN CIRCLE","Travelers have circled their wagons as predators test the barricade.","defense-a",2,{
            C("HOLD THE BARRICADE","Fight beside three travelers for good gear.",{battle=true,count=4,allies=3,defense=true,rewardQuality=3}),
            C("REPAIR THEIR WAGONS","Spend coal; gain food, water, and scrap.",{cost={coal=3},reward={food=2,water=2,scrap=5}}),
            C("COVER THEIR ESCAPE","Lose ammunition and health; gain an item.",{cost={health=2},ammoCost=true,itemPool="uncommon"})}),
        E("defense","farm-raid","FARM RAID","Mutated pests tear through a settlement's final crop while farmers fight with tools.","defense-a",3,{
            C("SAVE THE HARVEST","Allied battle; receive food and scaled loot.",{battle=true,count=4,allies=3,defense=true,rewardQuality=2}),
            C("MOVE THE FOOD","Lose health; gain part of the harvest.",{cost={health=3},reward={food=5}}),
            C("FORTIFY THE HOUSE","Spend scrap and coal; gain water.",{cost={scrap=3,coal=2},reward={water=3}})}),
        E("defense","station-stand","LAST STAND AT THE STATION","A handful of railway workers are trapped inside an old signal house.","defense-a",4,{
            C("STORM THE PLATFORM","Hard allied battle with weapon reward.",{battle=true,count=5,allies=3,defense=true,rewardQuality=3}),
            C("OPEN AN ESCAPE ROUTE","Spend coal and health; gain scrap.",{cost={coal=3,health=2},reward={scrap=6}}),
            C("DISTRACT THE PACK","Spend food and water; recover ammo.",{cost={food=2,water=2},ammo=true})}),
        E("defense","bridge-refugees","REFUGEES AT THE BRIDGE","Refugees are pinned against a broken bridge with nowhere left to run.","defense-a",5,{
            C("FORM A FIRING LINE","Large allied battle; best scaled loot.",{battle=true,count=5,allies=3,defense=true,rewardQuality=3}),
            C("FERRY THEM ACROSS","Lose food, water, and health; receive scrap.",{cost={food=2,water=3,health=2},reward={scrap=8}}),
            C("REBUILD THE SPAN","Spend coal and scrap; gain supplies.",{cost={coal=3,scrap=4},reward={food=3,water=3}})})
    },
    mystery={
        E("mystery","missing-1","THE EMPTY BEDROLL","A tiny bedroll and a carved acorn token lie beside cold ashes. A young critter vanished before dawn.","mystery-a",1,{
            C("SEARCH THE CAMPSITE","Lose water; recover the first clue.",{cost={water=1},reward={scrap=1}}),
            C("QUESTION THE CAMPERS","Share food and learn which way the tracks lead.",{cost={food=1}}),
            C("STUDY THE FOOTPRINTS","Read the trail carefully without spending supplies.",{})},"The acorn token bears three parallel scratches."),
        E("mystery","missing-2","PRINTS IN THE ASH","Small pawprints cross a field of ash, joined by a much larger set of tracks.","mystery-a",2,{
            C("FOLLOW BOTH TRACKS","Lose health; find the second clue and ammunition.",{cost={health=2},ammo=true}),
            C("CIRCLE AHEAD BY TRAIN","Spend coal; intercept the trail safely.",{cost={coal=2}}),
            C("WATCH FROM COVER","Study where the two trails separate.",{})},"The larger tracks stop wherever old signal bells still hang."),
        E("mystery","missing-3","THE TORN RED THREAD","A red thread matching the missing critter's scarf hangs from a thorn beside a service tunnel.","mystery-a",3,{
            C("ENTER THE TUNNEL","Fight tunnel creatures and secure the clue.",{battle=true,count=3,rewardQuality=2}),
            C("CLEAR THE ENTRANCE","Spend coal and health to search safely.",{cost={coal=2,health=1}}),
            C("MARK IT AND LISTEN","Lose food while waiting; hear a distant bell.",{cost={food=2}})},"The critter followed someone ringing a hand-sized railway bell."),
        E("mystery","missing-4","THE FALSE SIGNAL","An abandoned signal flashes at night though no power reaches the tower.","mystery-a",4,{
            C("CLIMB THE TOWER","Lose health; find a map marked with an acorn.",{cost={health=2},itemPool="uncommon"}),
            C("POWER THE SIGNAL","Spend coal and reveal the marked destination.",{cost={coal=3}}),
            C("WAIT FOR DAWN","Observe the signal safely until its route is clear.",{})},"The marked route ends at a garden built inside a ruined depot."),
        E("mystery","missing-5","THE DEPOT GARDEN","A hidden garden fills a ruined depot. The missing youngster is safe, sheltering with a lonely old signal keeper.","mystery-a",5,{
            C("REUNITE THEM","Spend food for a celebration; receive a rare reward.",{cost={food=2},itemPool="legendary",reward={scrap=8}}),
            C("INVITE THE KEEPER ALONG","Share water and receive equipment.",{cost={water=2},weapon=true,reward={scrap=5}}),
            C("REST IN THE GARDEN","Recover health, food, and water.",{reward={health=8,food=4,water=4}})},"The missing critter is found alive. The acorn trail is complete.")
    },
    story={
        E("story","family-1","A FAMILIAR RIBBON","A faded ribbon tied to a milepost matches one your family carried when they fled west.","story-a",1,{
            C("SEARCH THE MILEPOST","Spend water; find a written date.",{cost={water=1}}),C("ASK THE SETTLERS","Share food; learn they passed safely.",{cost={food=1}}),C("COPY THE MARK","Take the clue without cost.",{})},"Your family passed here only weeks before you."),
        E("story","family-2","THE SOUP POT","A cook remembers serving your family from a dented communal pot.","story-a",2,{
            C("HELP WITH SUPPER","Spend food; receive details and water.",{cost={food=2},reward={water=2}}),C("TRADE A STORY","Lose time and water; gain scrap.",{cost={water=1},reward={scrap=2}}),C("ASK WHICH WAY WEST","Receive the clue without a reward.",{})},"They followed the northern rail to avoid a bandit camp."),
        E("story","family-3","WRITING ON THE WALL","Your family name is scratched into the wall of an abandoned station.","story-a",3,{
            C("SEARCH THE STATION","Risk injury; find medicine.",{cost={health=2},itemPool="medical"}),C("LIGHT THE SIGNAL ROOM","Spend coal and uncover a message.",{cost={coal=2}}),C("READ AND MOVE ON","Take the clue safely.",{})},"The message says they were headed toward a water tower settlement."),
        E("story","family-4","THE WATER TOWER","A water keeper recognizes the description of your family and saved something they left behind.","story-a",4,{
            C("REPAIR THE PUMP","Spend coal; receive their keepsake and water.",{cost={coal=2},reward={water=3},itemPool="uncommon"}),C("BUY THE KEEPSAKE BACK","Spend scrap, preserve supplies.",{cost={scrap=3}}),C("JUST HEAR THE STORY","Take the clue neutrally.",{})},"They traded their keepsake to buy medicine for an injured traveler."),
        E("story","family-5","THE HEALED TRAVELER","The traveler your family helped now guards a tiny roadside shrine.","story-a",5,{
            C("HELP GUARD THE SHRINE","Fight mobs; earn scaled loot and the clue.",{battle=true,count=3,rewardQuality=2}),C("LEAVE AN OFFERING","Spend food and gain health.",{cost={food=2},reward={health=4}}),C("ASK ABOUT YOUR FAMILY","Receive the clue safely.",{})},"They were healthy, but traveling with a child who needed rest."),
        E("story","family-6","THE CHILD'S DRAWING","A child at a forest camp shows you a drawing of your family beside your train's red engine.","story-b",1,{
            C("GIVE THEM ART SUPPLIES","Lose one item; gain scrap and the clue.",{loseItem=true,reward={scrap=3}}),C("SHARE A SWEET","Spend food; receive the drawing.",{cost={food=1}}),C("MEMORIZE THE DRAWING","Keep supplies and take the clue.",{})},"Mountains and a broken viaduct appear behind your family in the drawing."),
        E("story","family-7","THE BROKEN VIADUCT","At the viaduct, fresh repair marks carry your family's familiar three-line symbol.","story-b",2,{
            C("CROSS THEIR REPAIR","Risk health and gain scrap.",{cost={health=2},reward={scrap=3}}),C("REINFORCE IT","Spend coal and travel safely.",{cost={coal=2}}),C("CAMP BELOW THE BRIDGE","Wait and study their route without spending supplies.",{})},"They repaired the viaduct, then turned south toward warmer country."),
        E("story","family-8","LETTER IN A BOTTLE","A sealed bottle caught in desert reeds contains a note addressed to you.","story-b",3,{
            C("WADE INTO THE MARSH","Lose health; retrieve the letter and water.",{cost={health=1},reward={water=2}}),C("HOOK IT WITH WIRE","Spend scrap and preserve health.",{cost={scrap=2}}),C("TRACE THE RIVERBANK","Follow the bottle until it reaches shore.",{})},"The letter says: 'Keep coming west. We are leaving signs where we can.'"),
        E("story","family-9","THE LAST EASTBOUND TRAIN","An old conductor arrives from California carrying news of a family matching yours.","story-b",4,{
            C("TRADE RAIL MAPS","Spend scrap; receive ammo and precise directions.",{cost={scrap=3},ammo=true}),C("SHARE PROVISIONS","Spend food and water; receive a rare item.",{cost={food=2,water=2},itemPool="rare"}),C("LISTEN CLOSELY","Take the clue without cost.",{})},"Your family reached a safe settlement less than fifty miles ahead."),
        E("story","family-10","THE CALIFORNIA SIGN","A hand-painted sign bears your family symbol and an arrow toward the final valley.","story-b",5,{
            C("FOLLOW IT NOW","Spend coal; receive a family cache of supplies.",{cost={coal=2},reward={food=4,water=4},itemPool="legendary"}),C("HELP REPAIR THE SIGN","Spend scrap; receive a weapon and ammunition.",{cost={scrap=3},weapon=true,ammo=true}),C("REST BEFORE THE LAST LEG","Recover health and provisions.",{reward={health=8,food=2,water=2}})},"The trail is complete. Your family is waiting in the California valley.")
    }
}

Events.definitions=definitions

local function find(category,index)
    return definitions[category] and definitions[category][index]
end

function Events.ensure(data)
    data.eventProgress=data.eventProgress or {story=0,mystery=0}
    data.eventHistory=data.eventHistory or {}
    data.eventCategoryHistory=data.eventCategoryHistory or {}
    local bossStops={[15]=true,[35]=true,[47]=true}; local overlapsBoss=false
    for _,stop in ipairs(data.mysteryStops or {}) do if bossStops[stop] then overlapsBoss=true; break end end
    if not data.mysteryStops or #data.mysteryStops~=5 or overlapsBoss then
        data.mysteryStops={}
        local bands={{4,10},{11,19},{20,29},{30,39},{40,47}}
        local occupied={[15]=true,[35]=true,[47]=true}; for _,stop in ipairs(Events.storyStops) do occupied[stop]=true end
        for _,band in ipairs(bands) do
            local choices={}; for stop=band[1],band[2] do if not occupied[stop] then choices[#choices+1]=stop end end
            local selected=choices[love.math.random(#choices)]; data.mysteryStops[#data.mysteryStops+1]=selected; occupied[selected]=true
        end
        table.sort(data.mysteryStops)
    end
end

function Events.required(data,location)
    Events.ensure(data)
    -- The >= check also migrates journeys already beyond an assigned clue:
    -- the next unplayed chapter appears at the next available stop.
    for index,stop in ipairs(Events.storyStops) do if location>=stop and (data.eventProgress.story or 0)<index then return find("story",index) end end
    for index,stop in ipairs(data.mysteryStops or {}) do if location>=stop and (data.eventProgress.mystery or 0)<index then return find("mystery",index) end end
end

function Events.random(data,EventBalance)
    Events.ensure(data)
    local category=EventBalance.pickCategory(data.location,data.eventCategoryHistory,love.math.random())
    local pool=definitions[category]; local recent=data.eventHistory or {}; local event
    for _=1,8 do
        event=pool[love.math.random(#pool)]
        if recent[#recent]~=event.id and recent[#recent-1]~=event.id then break end
    end
    return event
end

function Events.record(data,event,choiceIndex)
    Events.ensure(data)
    data.events[tostring(data.location)]={id=event.id,title=event.title,category=event.category,choice=choiceIndex}
    data.eventHistory[#data.eventHistory+1]=event.id
    while #data.eventHistory>8 do table.remove(data.eventHistory,1) end
    data.eventCategoryHistory[#data.eventCategoryHistory+1]=event.category
    while #data.eventCategoryHistory>8 do table.remove(data.eventCategoryHistory,1) end
    if event.category=="story" then data.eventProgress.story=math.max(data.eventProgress.story or 0,event.artIndex+(event.artSheet=="story-b" and 5 or 0)) end
    if event.category=="mystery" then data.eventProgress.mystery=math.max(data.eventProgress.mystery or 0,event.artIndex) end
end

local function applyValues(data,values,sign,TrainUpgradeBalance)
    for name,amount in pairs(values or {}) do
        amount=amount*sign
        if name=="health" then data.health=math.max(1,math.min(data.maxHealth,data.health+amount))
        elseif name=="scrap" then data.scrap=math.max(0,(data.scrap or 0)+amount)
        elseif data.resources[name]~=nil then
            if amount>0 then TrainUpgradeBalance.addResource(data,name,amount)
            else data.resources[name]=math.max(0,data.resources[name]+amount) end
        end
    end
end

function Events.canChoose(data,choice)
    if choice and choice.fallback then return true end
    for name,amount in pairs((choice and choice.cost) or {}) do
        local available=name=="health" and data.health or (name=="scrap" and (data.scrap or 0) or data.resources[name])
        if available==nil or available<amount then return false end
    end
    if choice and choice.ammoCost then
        local total=0
        for _,count in pairs(data.ammo or {}) do total=total+math.max(0,count or 0) end
        if total<3 then return false end
    end
    if choice and choice.loseItem then for i=1,(data.inventoryCapacity or 6) do if data.inventory[i] then return true end end; return false end
    return true
end

local function scaledItem(catalog,location,quality)
    if quality=="medical" then return LootProgression.rollMedical(catalog,location,"uncommon") end
    local minimum=LootProgression.qualityRarity(quality)
    return LootProgression.rollItem(catalog,location,{minimumRarity=minimum,weaponChance=quality=="legendary" and .45 or .12})
end

local function giveItem(data,catalog,item)
    for index=1,(data.inventoryCapacity or 6) do if not data.inventory[index] then data.inventory[index]=item; return item end end
    -- Event/battle rewards that do not fit go to the train mailbox.  Supplies
    -- quests do not use this helper; their food/water is applied directly to
    -- the resource stores, so their overflow remains intentionally excluded.
    local mailbox
    for _,placed in ipairs(data.droppedItems or {}) do
        if placed.name=="mailbox-reward" and placed.scene=="train" then mailbox=placed; break end
    end
    if mailbox then
        mailbox.storage=mailbox.storage or {}
        for slot=1,(catalog.storageCapacities["mailbox-reward"] or 20) do
            if not mailbox.storage[slot] then mailbox.storage[slot]=item; mailbox.mailUnread=true; return item end
        end
    end
    data.pendingRewards=data.pendingRewards or {}; data.pendingRewards[#data.pendingRewards+1]=item
    return item
end

local function scaledWeapon(catalog,location,quality)
    return LootProgression.rollWeapon(catalog,location,LootProgression.qualityRarity(quality))
end

local function giveAmmo(data,catalog,weapon)
    local combat=weapon and catalog.weaponCombat[weapon]; local ammo=(combat and combat.ammo) or LootProgression.rollAmmo(catalog,data.location)
    local amount=(catalog.ammoPickupAmounts[ammo] or 6)+math.floor((data.location or 1)/10)
    data.ammo[ammo]=(data.ammo[ammo] or 0)+amount; return ammo,amount
end

local function title(name)
    return (name or ""):gsub("%-"," "):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
end

function Events.resolve(data,catalog,event,choiceIndex,CombatBalance,TrainUpgradeBalance)
    local choice=event and event.choices[choiceIndex]; if not choice then return {} end
    if not Events.canChoose(data,choice) then return {blocked=true} end
    applyValues(data,choice.cost,-1,TrainUpgradeBalance); applyValues(data,choice.reward,1,TrainUpgradeBalance)
    local notes={}
    if choice.loseItem then for i=1,(data.inventoryCapacity or 6) do if data.inventory[i] then notes[#notes+1]="lost "..data.inventory[i]; data.inventory[i]=nil; break end end end
    local weapon
    if choice.weapon then weapon=scaledWeapon(catalog,data.location,2); giveItem(data,catalog,weapon); notes[#notes+1]="found "..weapon end
    if choice.itemPool then local item=scaledItem(catalog,data.location,choice.itemPool); giveItem(data,catalog,item); notes[#notes+1]="found "..item end
    if choice.ammo then local ammo,amount=giveAmmo(data,catalog,weapon); notes[#notes+1]="received "..amount.." "..ammo end
    if choice.ammoCost then
        local remaining=3
        for _,name in ipairs({"rocks","arrows","ball-bearings","22lr","9mm","45-cal","556","30-carbine","8mm","380-acp","32-acp","12-gauge","762x39"}) do
            local count=data.ammo[name] or 0; local spent=math.min(count,remaining)
            data.ammo[name]=count-spent; remaining=remaining-spent
            if remaining<=0 then break end
        end
    end
    Events.record(data,event,choiceIndex)
    local encounter
    if choice.battle then
        local tier=CombatBalance.tierFor(data.location); local pool=catalog.mobTiers[tier]
        encounter={rolled=true,hasMob=true,resolved=false,tier=tier,mobFiles={},eventBattle=true,eventReward=true,eventRewardQuality=choice.rewardQuality or 2,defenseBattle=choice.defense,defenseTitle=event.title}
        local count=choice.count or CombatBalance.mobCount(tier,data.location,love.math.random())
        for i=1,count do encounter.mobFiles[i]=pool[love.math.random(#pool)] end
        if choice.allies then encounter.temporaryAllies={}; local available={}; for _,file in ipairs(data.npcRoster or {}) do available[#available+1]=file end; for i=1,math.min(choice.allies,#available) do encounter.temporaryAllies[i]=table.remove(available,love.math.random(#available)) end end
    end
    local summary=choice.hint or "The journey continues."
    if #notes>0 then
        local readable={}; for _,note in ipairs(notes) do readable[#readable+1]=title(note) end
        summary=summary.."  "..table.concat(readable,", ").."."
    end
    return {encounter=encounter,notes=notes,clue=event.clue,summary=summary}
end

function Events.grantBattleLoot(data,catalog,encounter)
    if not encounter or not encounter.eventReward then return "" end
    local weapon=scaledWeapon(catalog,data.location,encounter.eventRewardQuality or 2); giveItem(data,catalog,weapon)
    local ammo,amount=giveAmmo(data,catalog,weapon); local quality=(encounter.eventRewardQuality or 2)>=3 and "rare" or "uncommon"
    if (data.battlePotionLootChance or 0)>0 and love.math.random()<data.battlePotionLootChance then quality="rare" end
    local item=scaledItem(catalog,data.location,quality); giveItem(data,catalog,item)
    return " Event loot: "..title(weapon)..", "..title(item)..", and "..amount.." "..title(ammo).."."
end

return Events
