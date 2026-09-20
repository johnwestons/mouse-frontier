local Catalog = {}
local TrainUpgradeBalance = require("game.train_upgrade_balance")

Catalog.characterTraitProfiles = {
    {name="Scrapper",combat=1,armor=0,coal=1.00,reward=1.25,description="Finds 25% more scrap and quest rewards."},
    {name="Engineer",combat=0,armor=1,coal=0.80,reward=1.00,description="Uses 20% less coal and has extra armor."},
    {name="Trailblazer",combat=1,armor=0,coal=0.90,reward=1.00,description="Better aim and efficient travel."},
    {name="Diplomat",combat=0,armor=0,coal=1.00,reward=1.35,description="Earns better rewards from critters."},
    {name="Forager",combat=0,armor=0,coal=1.00,food=0.80,reward=1.00,description="Uses 20% less food on every journey."},
    {name="Hydrologist",combat=0,armor=0,coal=1.00,water=0.80,reward=1.00,description="Uses 20% less water on every journey."},
    {name="Ranger",combat=1,armor=0,coal=1.00,move=1,reward=1.00,description="Moves one extra space in battle and aims better."},
    {name="Field Medic",combat=0,armor=0,coal=1.00,maxHealth=4,reward=1.00,description="Has 4 extra maximum health in every battle."},
    {name="Salvager",combat=0,armor=0,coal=1.00,scrapBonus=2,reward=1.00,description="Finds 2 extra scrap after every victory."}
}

function Catalog.characterAbility(file)
    local s=(file or ""):lower()
    if s:find("medic",1,true) or s:find("botanist",1,true) then return {kind="heal",name="HEAL ALLY",description="Restore 4 HP to nearby allies."} end
    if s:find("shield",1,true) then return {kind="protect",name="PROTECT",description="Give nearby allies +2 armor this round."} end
    if s:find("scout",1,true) or s:find("courier",1,true) then return {kind="snare",name="SNARE",description="Slow the nearest enemy for one turn."} end
    if s:find("witch",1,true) then return {kind="sleep",name="SLEEP",description="Put the nearest enemy to sleep for two turns."} end
    if s:find("trapper",1,true) or s:find("ranger",1,true) then return {kind="volley",name="VOLLEY",description="Strike the nearest enemy for 5 damage."} end
    if s:find("cook",1,true) then return {kind="nourish",name="NOURISH",description="Heal nearby allies and give them +1 move."} end
    if s:find("engineer",1,true) then return {kind="repair",name="REPAIR",description="Restore nearby allies with +2 armor and 2 HP."} end
    if s:find("conductor",1,true) or s:find("signal",1,true) or s:find("radio",1,true) then return {kind="haste",name="HASTE",description="Give nearby allies +1 aim and +2 move."} end
    if s:find("merchant",1,true) or s:find("scavenger",1,true) then return {kind="disarm",name="DISARM",description="Reduce the nearest enemy's aim by 2."} end
    if s:find("frog",1,true) then return {kind="paralyze",name="PARALYZE",description="Stop the nearest enemy's next turn."} end
    if s:find("prospector",1,true) or s:find("mechanic",1,true) then return {kind="area",name="AREA ATTACK",description="Damage nearby enemies."} end
    return {kind="rally",name="RALLY",description="Give nearby allies +2 aim and movement."}
end

function Catalog.characterTrait(file)
    local s=(file or ""):lower()
    local profiles=Catalog.characterTraitProfiles
    local byName={}
    for _,profile in ipairs(profiles) do byName[profile.name]=profile end
    if s:find("medic",1,true) or s:find("herbalist",1,true) then return byName["Field Medic"] end
    if s:find("engineer",1,true) or s:find("mechanic",1,true) or s:find("tinker",1,true) then return byName["Engineer"] end
    if s:find("cook",1,true) or s:find("gardener",1,true) or s:find("botanist",1,true) or s:find("homesteader",1,true) then return byName["Forager"] end
    if s:find("river",1,true) or s:find("otter",1,true) then return byName["Hydrologist"] end
    if s:find("scout",1,true) or s:find("trapper",1,true) or s:find("ranger",1,true) or s:find("trail",1,true) then return byName["Ranger"] end
    if s:find("scavenger",1,true) or s:find("prospector",1,true) then return byName["Salvager"] end
    if s:find("courier",1,true) or s:find("conductor",1,true) or s:find("signal",1,true) then return byName["Trailblazer"] end
    if s:find("merchant",1,true) or s:find("mail",1,true) or s:find("radio",1,true) then return byName["Diplomat"] end
    return byName["Scrapper"]
end

function Catalog.characterIdentity(file)
    local trait=Catalog.characterTrait(file)
    local ability=Catalog.characterAbility(file)
    local roles={heal="Support",nourish="Support",protect="Guardian",repair="Guardian",snare="Controller",sleep="Controller",
        disarm="Controller",paralyze="Controller",volley="Striker",area="Striker",haste="Leader",rally="Leader"}
    local role=roles[ability.kind] or "Traveler"
    return {file=file,name=(file or "Traveler"):gsub("%.png$",""):gsub("%-"," "),role=role,trait=trait,ability=ability,
        summary=role.." • "..trait.name.." • "..ability.name}
end

function Catalog.characterIdentityAudit(files,Roster)
    local invalid,traitKinds,abilityKinds=0,{},{}
    for _,file in ipairs(files or {}) do
        local identity=Catalog.characterIdentity(file)
        local valid=Roster.isPlayable(file) and identity.trait and identity.trait.description and identity.trait.description~=""
            and identity.ability and identity.ability.description and identity.ability.description~="" and identity.role~=""
        if not valid then invalid=invalid+1 end
        traitKinds[identity.trait and identity.trait.name or "missing"]=true
        abilityKinds[identity.ability and identity.ability.kind or "missing"]=true
    end
    local function count(values) local result=0; for _ in pairs(values) do result=result+1 end; return result end
    local playable=#(files or {})
    return {ready=playable>0 and invalid==0 and count(traitKinds)>=5 and count(abilityKinds)>=5,
        playable=playable,invalid=invalid,traitKinds=count(traitKinds),abilityKinds=count(abilityKinds),curve="character-identity-v1"}
end

Catalog.trainCarCatalog = TrainUpgradeBalance.carCatalog

Catalog.storageCapacities = {
    ["travel-chest"]=10, ["supply-crate"]=10, ["medicine-cabinet"]=10,
    ["train-locker"]=10, ["pantry-cupboard"]=10, ["barrel-cabinet"]=10,
    ["mailbox-reward"]=20,
    ["blue-steamer-trunk"]=10
}

Catalog.backpackUpgrades = {
    ["patched-canvas-pack"]={capacity=8,label="Patched Canvas Pack"},
    ["bedroll-hiking-pack"]={capacity=10,label="Bedroll Hiking Pack"},
    ["frontier-leather-pack"]={capacity=12,label="Frontier Leather Pack"},
    ["scavenger-frame-pack"]={capacity=16,label="Scavenger Frame Pack"}
    , ["weathered-leather-pack"]={capacity=14,label="Weathered Leather Pack"}
    , ["red-leather-pack"]={capacity=12,label="Red Leather Pack"}
    , ["compact-sling-pack"]={capacity=8,label="Compact Sling Pack"}
    , ["black-sling-pack"]={capacity=10,label="Black Sling Pack"}
}

Catalog.itemEffects = {
    ["food-ration"]={food=3,label="EAT"}, ["bread-loaf"]={food=3,label="EAT"},
    ["red-apple"]={food=2,label="EAT"}, carrot={food=2,label="EAT"}, ["hand-pie"]={food=3,label="EAT"},
    ["jam-jar"]={food=2,label="EAT"}, ["berry-jar"]={food=2,label="EAT"},
    ["melon-slice"]={food=1,water=1,label="EAT"}, ["campfire-skewers"]={food=3,label="EAT"},
    ["wrapped-sweet"]={food=1,label="EAT"}, ["water-bottle"]={water=3,label="DRINK"},
    ["water-canteen"]={water=4,label="DRINK"}, ["large-water-jug"]={water=6,label="DRINK"},
    ["field-bandage-roll"]={health=5,label="USE"}, ["herbal-tonic"]={health=8,label="DRINK"},
    ["frontier-medkit"]={health=12,label="USE"}, ["bean-tin"]={food=4,label="EAT"},
    ["trail-cheese"]={food=3,label="EAT"}, ["trail-mix-pouch"]={food=3,label="EAT"},
    ["ceramic-water-flask"]={water=4,label="DRINK"}, ["berry-soda"]={water=2,food=1,label="DRINK"},
    ["healing-salve"]={health=6,label="USE"}, ["wooden-splint-kit"]={health=7,label="USE"},
    ["antidote-vial"]={health=8,label="DRINK"}, ["hot-water-bottle"]={health=5,label="USE"},
    ["emergency-syringe-case"]={health=14,label="USE"}, ["trail-beans-can"]={food=4,label="EAT"},
    ["dried-berry-pouch"]={food=3,label="EAT"}, ["cornbread-square"]={food=4,label="EAT"},
    ["mushroom-stew"]={food=5,water=1,label="EAT"}, ["jerky-bundle"]={food=4,label="EAT"},
    ["preserved-peaches"]={food=3,water=1,label="EAT"}, ["metal-water-flask"]={water=4,label="DRINK"},
    ["smoked-trout"]={food=4,label="EAT"}, ["honey-biscuits"]={food=3,label="EAT"},
    ["roasted-squash"]={food=4,label="EAT"}, ["acorn-cluster"]={food=2,label="EAT"},
    ["oat-porridge"]={food=5,water=1,label="EAT"},
    ["red-potion-vial"]={potion="attack",attack=3,label="DRINK",description="Next battle: +3 attack."},
    ["green-potion-vial"]={potion="health",healthMax=6,health=6,label="DRINK",description="Next battle: +6 max health and heal 6 HP."},
    ["yellow-potion-vial"]={potion="move",move=2,label="DRINK",description="Next battle: +2 movement."},
    ["purple-potion-vial"]={potion="loot",rareLootChance=.45,label="DRINK",description="Next battle: +45% rare-loot chance."},
    ["blue-potion-vial"]={potion="defense",defense=3,label="DRINK",description="Next battle: +3 defense."},
    ["red-double-attack-vial"]={potion="double-attack",extraAttacks=1,battleAction=true,shortName="2X ATTACK",label="DRINK",description="This battle: attack twice during one turn."},
    ["yellow-double-move-vial"]={potion="double-move",extraMoves=1,battleAction=true,shortName="2X MOVE",label="DRINK",description="This battle: move twice during one turn."},
    ["blue-guard-vial"]={potion="guard",guardAllies=true,battleAction=true,shortName="GUARD ALL",label="DRINK",description="This battle: guard yourself and allies for one turn."},
    ["purple-accuracy-vial"]={potion="accuracy",perfectAccuracy=true,battleAction=true,shortName="100% AIM",label="DRINK",description="This battle: your attacks have 100% accuracy for one turn."},
    ["green-regeneration-vial"]={potion="regeneration",regenAmount=2,regenRounds=3,battleAction=true,shortName="REGEN +2",label="DRINK",description="This battle: heal yourself and allies for 2 HP over 3 turns."},
    ["blue-water-bottle"]={water=3,label="DRINK"}, ["rainwater-jar"]={water=5,label="DRINK"},
    ["patched-canteen"]={water=5,label="DRINK"}, ["boxed-fruit-drink"]={water=3,food=1,label="DRINK"},
    ["ceramic-water-crock"]={water=7,label="DRINK"},
    ["small-oil-canister"]={oil=1,label="STORE",description="Adds 1 oil to the train supply."},
    ["medium-oil-canister"]={oil=5,label="STORE",description="Adds 5 oil to the train supply."},
    ["large-oil-canister"]={oil=10,label="STORE",description="Adds 10 oil to the train supply."}
}

Catalog.weaponStats = {
    scratch={name="Scratch",min=1,max=3,tier=0},
    ["mob-claw"]={name="Savage Claw",min=4,max=8,tier=3},
    ["mob-spit"]={name="Toxic Spit",min=3,max=7,tier=3},
    ["brass-knuckle-duster"]={name="Brass Knuckles",min=2,max=4,tier=1},
    ["train-wrench"]={name="Train Wrench",min=2,max=5,tier=1},
    ["salvage-pry-bar"]={name="Salvage Pry Bar",min=2,max=5,tier=1},
    ["scrap-hatchet"]={name="Scrap Hatchet",min=3,max=5,tier=2},
    ["rusty-cleaver"]={name="Rusty Cleaver",min=3,max=6,tier=2},
    ["frontier-short-sword"]={name="Frontier Sword",min=3,max=6,tier=2},
    ["patched-trench-knife"]={name="Patched Trench Knife",min=3,max=6,tier=2},
    ["scrap-hunting-spear"]={name="Scrap Hunting Spear",min=3,max=6,tier=2},
    ["salvaged-track-hatchet"]={name="Salvaged Track Hatchet",min=3,max=6,tier=2},
    ["miners-pick"]={name="Miner's Pick",min=4,max=7,tier=3},
    ["hunting-bow"]={name="Hunting Bow",min=4,max=7,tier=3},
    ["gear-hammer"]={name="Gear Hammer",min=5,max=8,tier=4},
    ["rail-spike-spear"]={name="Rail Spike Spear",min=5,max=9,tier=4},
    ["gear-toothed-falchion"]={name="Gear-Toothed Falchion",min=5,max=9,tier=4},
    ["frontier-fork-trident"]={name="Frontier Fork Trident",min=5,max=9,tier=4},
    ["gearwright-bearded-axe"]={name="Gearwright Bearded Axe",min=5,max=9,tier=4},
    ["critter-crossbow"]={name="Critter Crossbow",min=6,max=10,tier=5},
    ["chain-flail"]={name="Chain Flail",min=6,max=11,tier=5},
    ["scrap-pistol"]={name="Scrap Pistol",min=7,max=12,tier=6},
    ["railway-cutlass"]={name="Railway Cutlass",min=7,max=12,tier=6},
    ["hooked-railway-halberd"]={name="Hooked Railway Halberd",min=7,max=12,tier=6},
    ["rail-splitter-axe"]={name="Rail-Splitter Axe",min=7,max=12,tier=6},
    ["sawed-off-shotgun"]={name="Sawed-Off Shotgun",min=8,max=14,tier=7},
    ["trail-slingshot"]={name="Trail Slingshot",min=2,max=4,tier=1},
    ["rail-spike-dagger"]={name="Rail Spike Dagger",min=3,max=5,tier=2},
    ["scrap-boomerang"]={name="Scrap Boomerang",min=4,max=7,tier=3},
    ["frontier-hook-sickle"]={name="Frontier Hook Sickle",min=4,max=7,tier=3},
    ["frontier-curved-saber"]={name="Frontier Curved Saber",min=4,max=8,tier=3},
    ["steam-shock-baton"]={name="Steam Shock Baton",min=7,max=11,tier=6},
    ["frontier-lever-rifle"]={name="Frontier Lever Rifle",min=9,max=15,tier=8},
    ["compact-scrap-pistol"]={name="Compact Scrap Pistol",min=5,max=9,tier=4},
    ["long-barrel-22-pistol"]={name="Long-Barrel .22 Pistol",min=5,max=8,tier=4},
    ["heavy-frontier-pistol"]={name="Heavy Frontier Pistol",min=7,max=12,tier=6},
    ["machine-pistol"]={name="Machine Pistol",min=6,max=10,tier=5},
    ["weathered-lever-rifle"]={name="Weathered Lever Rifle",min=8,max=13,tier=7},
    ["improvised-service-rifle"]={name="Improvised Service Rifle",min=9,max=15,tier=8},
    ["compact-carbine"]={name="Compact Carbine",min=8,max=14,tier=7},
    ["rugged-submachine-gun"]={name="Rugged Submachine Gun",min=7,max=12,tier=6},
    ["wrist-braced-slingshot"]={name="Wrist-Braced Slingshot",min=3,max=5,tier=2},
    ["metal-scrap-slingshot"]={name="Metal Scrap Slingshot",min=4,max=6,tier=3},
    ["long-hunting-slingshot"]={name="Long Hunting Slingshot",min=5,max=8,tier=4},
    ["patched-22-survival-rifle"]={name="Patched .22 Survival Rifle",min=7,max=12,tier=6},
    ["improvised-556-rifle"]={name="Improvised 5.56 Rifle",min=10,max=16,tier=9},
    ["frontier-long-barrel-revolver"]={name="Long-Barrel Frontier Revolver",min=7,max=12,tier=6},
    ["frontier-22-lever-rifle"]={name="Frontier .22 Lever Rifle",min=7,max=12,tier=6},
    ["frontier-45-1911"]={name="Frontier .45 1911",min=9,max=15,tier=8},
    ["frontier-380-revolver"]={name="Frontier .380 Revolver",min=6,max=10,tier=5},
    ["frontier-long-22-target-pistol"]={name="Frontier Long .22 Target Pistol",min=6,max=10,tier=5},
    ["wood-stock-survival-carbine"]={name="Wood-Stock Survival Carbine",min=8,max=13,tier=7},
    ["vintage-bolt-action-rifle"]={name="Vintage Bolt-Action Rifle",min=10,max=16,tier=9}
    , ["frontier-katana"]={name="Frontier Katana",min=8,max=13,tier=7}
    , ["frontier-mace"]={name="Frontier Mace",min=7,max=12,tier=6}
    , ["frontier-battle-axe"]={name="Frontier Battle Axe",min=9,max=15,tier=8}
    , ["frontier-longsword"]={name="Frontier Longsword",min=10,max=16,tier=9}
    , ["frontier-machete"]={name="Frontier Machete",min=7,max=12,tier=6}
    , ["frontier-spear"]={name="Frontier Spear",min=6,max=10,tier=5}
    , ["frontier-cavalry-saber"]={name="Frontier Cavalry Saber",min=6,max=10,tier=5}
    , ["frontier-hatchet"]={name="Frontier Hatchet",min=5,max=9,tier=4}
    , ["frontier-hand-axe"]={name="Frontier Hand Axe",min=7,max=11,tier=6}
    , ["boiler-smith-maul"]={name="Boiler-Smith Maul",min=8,max=14,tier=7}
    , ["railway-war-pick"]={name="Railway War Pick",min=9,max=15,tier=8}
    , ["brass-backed-greatsword"]={name="Brass-Backed Greatsword",min=10,max=17,tier=9}
    , ["wasteland-partisan"]={name="Wasteland Partisan",min=10,max=17,tier=9}
    , ["frontier-executioner-axe"]={name="Frontier Executioner Axe",min=11,max=17,tier=9}
    , ["frontier-556-carbine"]={name="Frontier 5.56 Carbine",min=10,max=16,tier=9}
    , ["frontier-9mm-smg"]={name="Frontier 9mm SMG",min=8,max=13,tier=8}
    , ["frontier-22-target-pistol"]={name="Frontier .22 Target Pistol",min=5,max=9,tier=4}
    , ["frontier-380-pocket-pistol"]={name="Frontier .380 Pocket Pistol",min=6,max=10,tier=5}
    , ["frontier-12g-pump-shotgun"]={name="Frontier 12-Gauge Pump Shotgun",min=9,max=15,tier=7}
    , ["frontier-762-carbine"]={name="Frontier 7.62x39 Carbine",min=10,max=16,tier=8}
    , ["frontier-sr22-pistol"]={name="Frontier .22 Target Pistol",min=5,max=9,tier=4}
    , ["frontier-9mm-service-pistol"]={name="Frontier 9mm Service Pistol",min=7,max=12,tier=6}
    , ["frontier-compact-9mm"]={name="Frontier Compact 9mm",min=7,max=12,tier=6}
    , ["frontier-32-pocket-pistol"]={name="Frontier .32 Pocket Pistol",min=5,max=9,tier=4}
    , ["frontier-22-pocket-pistol"]={name="Frontier .22 Pocket Pistol",min=4,max=8,tier=3}
    , ["frontier-silver-22-revolver"]={name="Frontier Silver .22 Revolver",min=6,max=10,tier=5}
    , ["frontier-ak-compact"]={name="Frontier Compact AK",min=9,max=15,tier=8}
    , ["frontier-9mm-glock"]={name="Frontier 9mm Service Sidearm",min=7,max=12,tier=6}
    , ["frontier-pearl-pocket-pistol"]={name="Frontier Pearl Pocket Pistol",min=4,max=8,tier=3}
    , ["frontier-silver-compact-pistol"]={name="Frontier Silver Compact Pistol",min=6,max=10,tier=5}
    , ["frontier-compact-9mm-pistol"]={name="Frontier Compact 9mm Pistol",min=6,max=10,tier=5}
    , ["frontier-single-shot-hunter"]={name="Frontier Single-Shot Hunter",min=7,max=12,tier=6}
    , ["frontier-lever-carbine"]={name="Frontier Lever Carbine",min=8,max=13,tier=7}
}

Catalog.weaponCombat = {
    scratch={kind="melee",range=4,family="quick",accuracy=1,animation="swipe"},
    ["brass-knuckle-duster"]={kind="melee",range=4,family="quick",accuracy=2,animation="jab"},
    ["mob-claw"]={kind="melee",range=4,family="quick",accuracy=1,animation="swipe"}, ["mob-spit"]={kind="ranged",range=24,projectile="toxic"},
    ["train-wrench"]={kind="melee",range=4,family="blunt",status="stagger",statusChance=.20,animation="smash"},
    ["salvage-pry-bar"]={kind="melee",range=4,family="blunt",armorPierce=1,status="stagger",statusChance=.18,animation="smash"},
    ["scrap-hatchet"]={kind="melee",range=4,family="axe",armorPierce=1,animation="chop"},
    ["rusty-cleaver"]={kind="melee",range=4,family="blade",status="bleed",statusChance=.20,bleedDamage=1,animation="slash"},
    ["frontier-short-sword"]={kind="melee",range=5,family="blade",accuracy=1,status="bleed",statusChance=.18,bleedDamage=1,animation="slash"},
    ["patched-trench-knife"]={kind="melee",range=4,family="blade",accuracy=2,status="bleed",statusChance=.18,bleedDamage=1,animation="jab"},
    ["scrap-hunting-spear"]={kind="melee",range=6,family="polearm",armorPierce=1,animation="thrust"},
    ["salvaged-track-hatchet"]={kind="melee",range=4,family="axe",armorPierce=1,animation="chop"},
    ["miners-pick"]={kind="melee",range=5,family="piercing",armorPierce=2,animation="thrust"},
    ["gear-hammer"]={kind="melee",range=4,family="blunt",status="stagger",statusChance=.25,animation="smash"},
    ["rail-spike-spear"]={kind="melee",range=6,family="polearm",armorPierce=1,animation="thrust"},
    ["gear-toothed-falchion"]={kind="melee",range=5,family="blade",status="bleed",statusChance=.24,bleedDamage=1,animation="slash"},
    ["frontier-fork-trident"]={kind="melee",range=7,family="polearm",armorPierce=2,animation="thrust"},
    ["gearwright-bearded-axe"]={kind="melee",range=5,family="axe",armorPierce=2,animation="chop"},
    ["chain-flail"]={kind="melee",range=6,family="blunt",armorPierce=1,status="stagger",statusChance=.22,animation="swing"},
    ["rail-spike-dagger"]={kind="melee",range=4,family="quick",accuracy=2,armorPierce=1,animation="jab"},
    ["frontier-hook-sickle"]={kind="melee",range=5,family="blade",status="bleed",statusChance=.28,bleedDamage=1,animation="slash"},
    ["frontier-curved-saber"]={kind="melee",range=5,family="blade",accuracy=1,status="bleed",statusChance=.22,bleedDamage=1,animation="slash"},
    ["scrap-boomerang"]={kind="ranged",range=18,capacity=1,projectile="boomerang"},
    ["steam-shock-baton"]={kind="melee",range=5,family="blunt",status="paralyze",statusChance=.18,animation="jab"}, ["hunting-bow"]={kind="ranged",range=24,ammo="arrows",capacity=1},
    ["trail-slingshot"]={kind="ranged",range=18,ammo="rocks",capacity=1}, ["critter-crossbow"]={kind="ranged",range=26,ammo="arrows",capacity=1},
    ["scrap-pistol"]={kind="ranged",range=24,ammo="9mm",capacity=8}, ["sawed-off-shotgun"]={kind="ranged",range=12,ammo="45-cal",capacity=2},
    ["railway-cutlass"]={kind="melee",range=6,family="blade",accuracy=1,status="bleed",statusChance=.28,bleedDamage=2,animation="slash"},
    ["hooked-railway-halberd"]={kind="melee",range=7,family="polearm",armorPierce=3,animation="thrust"},
    ["rail-splitter-axe"]={kind="melee",range=5,family="axe",armorPierce=3,animation="chop"},
    ["frontier-lever-rifle"]={kind="ranged",range=32,ammo="22lr",capacity=7},
    ["compact-scrap-pistol"]={kind="ranged",range=20,ammo="9mm",capacity=7},
    ["long-barrel-22-pistol"]={kind="ranged",range=25,ammo="22lr",capacity=10},
    ["heavy-frontier-pistol"]={kind="ranged",range=20,ammo="45-cal",capacity=6},
    ["machine-pistol"]={kind="ranged",range=18,ammo="9mm",capacity=15},
    ["weathered-lever-rifle"]={kind="ranged",range=32,ammo="22lr",capacity=8},
    ["improvised-service-rifle"]={kind="ranged",range=34,ammo="556",capacity=20},
    ["compact-carbine"]={kind="ranged",range=28,ammo="556",capacity=15},
    ["rugged-submachine-gun"]={kind="ranged",range=22,ammo="45-cal",capacity=18},
    ["wrist-braced-slingshot"]={kind="ranged",range=19,ammo="rocks",capacity=1},
    ["metal-scrap-slingshot"]={kind="ranged",range=21,ammo="ball-bearings",capacity=1},
    ["long-hunting-slingshot"]={kind="ranged",range=25,ammo="ball-bearings",capacity=1},
    ["patched-22-survival-rifle"]={kind="ranged",range=32,ammo="22lr",capacity=7},
    ["improvised-556-rifle"]={kind="ranged",range=36,ammo="556",capacity=20},
    ["frontier-long-barrel-revolver"]={kind="ranged",range=24,ammo="22lr",capacity=6},
    ["frontier-22-lever-rifle"]={kind="ranged",range=32,ammo="22lr",capacity=12},
    ["frontier-45-1911"]={kind="ranged",range=24,ammo="45-cal",capacity=8},
    ["frontier-380-revolver"]={kind="ranged",range=20,ammo="380-acp",capacity=5},
    ["frontier-long-22-target-pistol"]={kind="ranged",range=30,ammo="22lr",capacity=10},
    ["wood-stock-survival-carbine"]={kind="ranged",range=30,ammo="30-carbine",capacity=15},
    ["vintage-bolt-action-rifle"]={kind="ranged",range=40,ammo="8mm",capacity=5}
    , ["frontier-katana"]={kind="melee",range=6,family="blade",accuracy=1,status="bleed",statusChance=.32,bleedDamage=2,animation="slash"}
    , ["frontier-mace"]={kind="melee",range=5,family="blunt",armorPierce=1,status="stagger",statusChance=.32,animation="smash"}
    , ["frontier-battle-axe"]={kind="melee",range=5,family="axe",armorPierce=3,animation="chop"}
    , ["frontier-longsword"]={kind="melee",range=6,family="blade",accuracy=1,status="bleed",statusChance=.30,bleedDamage=2,animation="slash"}
    , ["frontier-machete"]={kind="melee",range=5,family="blade",status="bleed",statusChance=.28,bleedDamage=2,animation="chop"}
    , ["frontier-spear"]={kind="melee",range=7,family="polearm",armorPierce=2,animation="thrust"}
    , ["frontier-hatchet"]={kind="melee",range=4,family="axe",armorPierce=2,animation="chop"}
    , ["frontier-hand-axe"]={kind="melee",range=5,family="axe",armorPierce=2,animation="chop"}
    , ["frontier-cavalry-saber"]={kind="melee",range=6,family="blade",accuracy=1,status="bleed",statusChance=.26,bleedDamage=2,animation="slash"}
    , ["boiler-smith-maul"]={kind="melee",range=5,family="blunt",armorPierce=2,status="stagger",statusChance=.38,animation="smash"}
    , ["railway-war-pick"]={kind="melee",range=6,family="piercing",armorPierce=4,animation="thrust"}
    , ["brass-backed-greatsword"]={kind="melee",range=6,family="blade",accuracy=1,status="bleed",statusChance=.36,bleedDamage=3,animation="slash"}
    , ["wasteland-partisan"]={kind="melee",range=8,family="polearm",armorPierce=4,accuracy=1,animation="thrust"}
    , ["frontier-executioner-axe"]={kind="melee",range=6,family="axe",armorPierce=4,animation="chop"}
    , ["frontier-556-carbine"]={kind="ranged",range=36,ammo="556",capacity=20}
    , ["frontier-9mm-smg"]={kind="ranged",range=24,ammo="9mm",capacity=30}
    , ["frontier-22-target-pistol"]={kind="ranged",range=27,ammo="22lr",capacity=10}
    , ["frontier-380-pocket-pistol"]={kind="ranged",range=22,ammo="380-acp",capacity=6}
    , ["frontier-12g-pump-shotgun"]={kind="ranged",range=16,ammo="12-gauge",capacity=6}
    , ["frontier-762-carbine"]={kind="ranged",range=34,ammo="762x39",capacity=10}
    , ["frontier-sr22-pistol"]={kind="ranged",range=27,ammo="22lr",capacity=10}
    , ["frontier-9mm-service-pistol"]={kind="ranged",range=24,ammo="9mm",capacity=15}
    , ["frontier-compact-9mm"]={kind="ranged",range=24,ammo="9mm",capacity=13}
    , ["frontier-32-pocket-pistol"]={kind="ranged",range=20,ammo="32-acp",capacity=8}
    , ["frontier-22-pocket-pistol"]={kind="ranged",range=20,ammo="22lr",capacity=7}
    , ["frontier-silver-22-revolver"]={kind="ranged",range=22,ammo="22lr",capacity=6}
    , ["frontier-ak-compact"]={kind="ranged",range=34,ammo="762x39",capacity=30}
    , ["frontier-9mm-glock"]={kind="ranged",range=24,ammo="9mm",capacity=17}
    , ["frontier-pearl-pocket-pistol"]={kind="ranged",range=18,ammo="32-acp",capacity=6}
    , ["frontier-silver-compact-pistol"]={kind="ranged",range=22,ammo="9mm",capacity=10}
    , ["frontier-compact-9mm-pistol"]={kind="ranged",range=22,ammo="9mm",capacity=10}
    , ["frontier-single-shot-hunter"]={kind="ranged",range=36,ammo="22lr",capacity=1}
    , ["frontier-lever-carbine"]={kind="ranged",range=32,ammo="30-carbine",capacity=8}
}

Catalog.weaponProgression = {
    "trail-slingshot","brass-knuckle-duster","train-wrench","salvage-pry-bar",
    "rail-spike-dagger","scrap-hatchet","rusty-cleaver","frontier-short-sword","patched-trench-knife","scrap-hunting-spear","salvaged-track-hatchet","wrist-braced-slingshot",
    "scrap-boomerang","miners-pick","hunting-bow","metal-scrap-slingshot","frontier-hook-sickle","frontier-curved-saber","frontier-22-pocket-pistol","frontier-pearl-pocket-pistol",
    "gear-hammer","rail-spike-spear","gear-toothed-falchion","frontier-fork-trident","gearwright-bearded-axe","compact-scrap-pistol","long-barrel-22-pistol","long-hunting-slingshot","frontier-hatchet","frontier-22-target-pistol","frontier-sr22-pistol","frontier-32-pocket-pistol",
    "critter-crossbow","chain-flail","machine-pistol","frontier-380-revolver","frontier-long-22-target-pistol","frontier-spear","frontier-cavalry-saber","frontier-silver-22-revolver","frontier-silver-compact-pistol","frontier-compact-9mm-pistol","frontier-380-pocket-pistol",
    "scrap-pistol","railway-cutlass","hooked-railway-halberd","rail-splitter-axe","steam-shock-baton","heavy-frontier-pistol","rugged-submachine-gun","patched-22-survival-rifle","frontier-long-barrel-revolver","frontier-22-lever-rifle","frontier-mace","frontier-machete","frontier-hand-axe","frontier-9mm-service-pistol","frontier-compact-9mm","frontier-9mm-glock","frontier-single-shot-hunter",
    "sawed-off-shotgun","weathered-lever-rifle","compact-carbine","wood-stock-survival-carbine","frontier-katana","boiler-smith-maul","frontier-12g-pump-shotgun","frontier-lever-carbine",
    "frontier-lever-rifle","improvised-service-rifle","frontier-battle-axe","railway-war-pick","frontier-9mm-smg","frontier-762-carbine","frontier-ak-compact","frontier-45-1911",
    "improvised-556-rifle","vintage-bolt-action-rifle","frontier-longsword","frontier-556-carbine","brass-backed-greatsword","wasteland-partisan","frontier-executioner-axe"
}

function Catalog.weaponFamily(name)
    local combat=Catalog.weaponCombat[name] or Catalog.weaponCombat.scratch
    if combat.kind=="melee" then return combat.family or "melee" end
    if combat.ammo=="arrows" then return "bows" end
    if name and (name:find("slingshot") or name:find("boomerang")) then return "slingshots" end
    return "firearms"
end

function Catalog.weaponReach(name)
    local combat=Catalog.weaponCombat[name] or Catalog.weaponCombat.scratch
    if combat.kind=="ranged" then return math.max(2,math.floor((combat.range or 12)/6)) end
    return combat.family=="polearm" and 2 or 1
end

function Catalog.weaponRole(name)
    local combat=Catalog.weaponCombat[name] or Catalog.weaponCombat.scratch
    if combat.kind~="melee" then return "RANGED" end
    local parts={string.upper(combat.family or "melee")}
    if (combat.accuracy or 0)>0 then parts[#parts+1]="AIM +"..combat.accuracy end
    if (combat.armorPierce or 0)>0 then parts[#parts+1]="PIERCE "..combat.armorPierce end
    if combat.status=="bleed" then parts[#parts+1]="BLEED" elseif combat.status=="stagger" then parts[#parts+1]="STAGGER" elseif combat.status=="paralyze" then parts[#parts+1]="SHOCK" end
    return table.concat(parts," • ")
end

Catalog.mobTiers = {
    easy={"flower-bird.png","ghost-small.png","pumpkin-bat.png","dust-beetle.png","cactus-rat.png","red-hood-mouse.png","shield-mouse.png","cowboy-mouse-no-skull.png"},
    medium={"attacking-eagle.png","pumpkin-cat.png","pumpkin-vampire.png","wasteland-scorpion.png","raccoon-cape.png","raccoon-heart.png","mouse-bandit.png"},
    -- The zombie is intentionally hard-tier. Its duplicate entry raises its
    -- selection weight so players reliably encounter it during the late game.
    hard={"ghost-tall.png","purple-dragon.png","mutant-horned-owl.png","tunnel-badger-raider.png","wasteland-human-zombie.png","wasteland-human-zombie.png","vampire-mouse.png","mouse-bandit.png"}
}

-- Original regular talk explicitly confirmed by the user on September 19, 2026.
-- Exact wording restored from docs/dialogue-review/changed-text.md (R001).
Catalog.dialogueLines = {
    "Hello", "Howdy stranger", "Nice train", "Sure is hot out", "Where'd you come from?", "Where you headed?",
    "Be careful out there", "Hi", "Don't get much visitors these days", "How's yer mom and them?",
    "Hope you find what you're looking for", "Got any grapes?", "Can I borrow $3.50?",
    "What happened to the rest of the people?", "I hope my family is ok...", "What are we gonna do come winter...",
    "How far have you traveled so far?", "Some critters got mutated in the great flash.",
    "We need more people like you...", "Wow, what an adventure!",
    "Those darn sludges keep tainting my crops...", "I would go myself but I know there will be bandits...",
    "We need to work together.", "If you see a sludge you gotta mash it!",
    "I hope you guys make it to the next stop safely.", "I've not seen my family in ages it feels like...",
    "Have you ever seen a human?", "Grab whatever you need for the journey.",
    "How are the tracks holding up?", "How many of us are out there?",
    "Wish we could all get along...", "Safe travels friend", "Maybe we will all get our happy endings..."
}
Catalog.mailRequestLines={"Delivery: carry a letter west."}
Catalog.rideRequestLines={"Passenger transport: provide a ride for a few stops."}
Catalog.passengerLines={}
Catalog.mailThanksLines={"Letter delivered."}
Catalog.questRewardItems={"food-ration","water-bottle","field-bandage-roll","wrapped-sweet","coal-chunk","herbal-tonic"}
Catalog.ammoPickupAmounts={rocks=8,arrows=6,["ball-bearings"]=8,["9mm"]=12,["45-cal"]=8,["556"]=10,["22lr"]=15,["30-carbine"]=10,["8mm"]=8,["380-acp"]=8,["32-acp"]=8,["12-gauge"]=6,["762x39"]=10}

Catalog.lootPools = {
    food={"food-ration","bread-loaf","red-apple","carrot","hand-pie","jam-jar","berry-jar","trail-beans-can","dried-berry-pouch","cornbread-square","jerky-bundle","smoked-trout","honey-biscuits","roasted-squash","acorn-cluster","oat-porridge"},
    water={"water-bottle","water-canteen","metal-water-flask","blue-water-bottle","rainwater-jar","patched-canteen","boxed-fruit-drink"},
    common={"food-ration","bread-loaf","red-apple","carrot","water-bottle","coal-chunk","small-oil-canister","rocks","arrows","ball-bearings","wrapped-sweet","honey-biscuits","acorn-cluster","dried-berry-pouch"},
    uncommon={"hand-pie","jam-jar","berry-jar","melon-slice","campfire-skewers","trail-mix-pouch","trail-cheese","bean-tin","trail-beans-can","cornbread-square","jerky-bundle","smoked-trout","roasted-squash","oat-porridge","water-canteen","ceramic-water-flask","metal-water-flask","blue-water-bottle","berry-soda","boxed-fruit-drink","medium-oil-canister","field-bandage-roll","healing-salve","hot-water-bottle","9mm","22lr","45-cal","380-acp","32-acp","patched-canvas-pack"},
    rare={"mushroom-stew","preserved-peaches","large-water-jug","rainwater-jar","patched-canteen","ceramic-water-crock","large-oil-canister","herbal-tonic","wooden-splint-kit","antidote-vial","frontier-medkit","red-potion-vial","green-potion-vial","yellow-potion-vial","purple-potion-vial","blue-potion-vial","red-double-attack-vial","yellow-double-move-vial","blue-guard-vial","purple-accuracy-vial","green-regeneration-vial","30-carbine","12-gauge","556","762x39","8mm","weathered-leather-pack","red-leather-pack","compact-sling-pack","black-sling-pack","bedroll-hiking-pack","frontier-leather-pack"},
    legendary={"rose-heart-arrow","blade-hearts","emergency-syringe-case","scavenger-frame-pack"}
}

Catalog.itemRarity={}
for _,rarity in ipairs({"common","uncommon","rare","legendary"}) do
    for _,name in ipairs(Catalog.lootPools[rarity]) do Catalog.itemRarity[name]=rarity end
end

function Catalog.rarityFor(name)
    local stats=Catalog.weaponStats[name]
    if stats then return stats.tier>=9 and "legendary" or (stats.tier>=6 and "rare" or (stats.tier>=3 and "uncommon" or "common")) end
    return Catalog.itemRarity[name] or "common"
end

return Catalog
