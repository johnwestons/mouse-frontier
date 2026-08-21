local Catalog = {}

Catalog.characterTraitProfiles = {
    {name="Scrapper",combat=1,armor=0,coal=1.00,reward=1.25,description="Finds 25% more scrap and quest rewards."},
    {name="Engineer",combat=0,armor=1,coal=0.80,reward=1.00,description="Uses 20% less coal and has extra armor."},
    {name="Trailblazer",combat=1,armor=0,coal=0.90,reward=1.00,description="Better aim and efficient travel."},
    {name="Diplomat",combat=0,armor=0,coal=1.00,reward=1.35,description="Earns better rewards from critters."}
}

Catalog.trainCarCatalog = {
    {id="coal-hauler",name="Coal Hauler",cost=20,description="Coal capacity +10"},
    {id="greenhouse",name="Greenhouse",cost=28,description="Produces food while traveling"},
    {id="sleeper",name="Sleeper Car",cost=24,description="Passengers consume less food"},
    {id="storage",name="Storage Car",cost=22,description="Food and water capacity +10"},
    {id="medical",name="Medical Car",cost=30,description="Heal after every journey"},
    {id="navigator",name="Navigator Car",cost=34,description="Reveals terrain and route hazards"}
}

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
    ["blue-water-bottle"]={water=3,label="DRINK"}, ["rainwater-jar"]={water=5,label="DRINK"},
    ["patched-canteen"]={water=5,label="DRINK"}, ["boxed-fruit-drink"]={water=3,food=1,label="DRINK"},
    ["ceramic-water-crock"]={water=7,label="DRINK"}
}

Catalog.weaponStats = {
    scratch={name="Scratch",min=1,max=3,tier=0},
    ["mob-claw"]={name="Savage Claw",min=4,max=8,tier=3},
    ["mob-spit"]={name="Toxic Spit",min=3,max=7,tier=3},
    ["brass-knuckle-duster"]={name="Brass Knuckles",min=2,max=4,tier=1},
    ["train-wrench"]={name="Train Wrench",min=2,max=5,tier=1},
    ["scrap-hatchet"]={name="Scrap Hatchet",min=3,max=5,tier=2},
    ["rusty-cleaver"]={name="Rusty Cleaver",min=3,max=6,tier=2},
    ["frontier-short-sword"]={name="Frontier Sword",min=3,max=6,tier=2},
    ["miners-pick"]={name="Miner's Pick",min=4,max=7,tier=3},
    ["hunting-bow"]={name="Hunting Bow",min=4,max=7,tier=3},
    ["gear-hammer"]={name="Gear Hammer",min=5,max=8,tier=4},
    ["rail-spike-spear"]={name="Rail Spike Spear",min=5,max=9,tier=4},
    ["critter-crossbow"]={name="Critter Crossbow",min=6,max=10,tier=5},
    ["chain-flail"]={name="Chain Flail",min=6,max=11,tier=5},
    ["scrap-pistol"]={name="Scrap Pistol",min=7,max=12,tier=6},
    ["sawed-off-shotgun"]={name="Sawed-Off Shotgun",min=8,max=14,tier=7},
    ["trail-slingshot"]={name="Trail Slingshot",min=2,max=4,tier=1},
    ["rail-spike-dagger"]={name="Rail Spike Dagger",min=3,max=5,tier=2},
    ["scrap-boomerang"]={name="Scrap Boomerang",min=4,max=7,tier=3},
    ["steam-shock-baton"]={name="Steam Shock Baton",min=7,max=11,tier=6},
    ["frontier-lever-rifle"]={name="Frontier Lever Rifle",min=9,max=15,tier=8},
    ["compact-scrap-pistol"]={name="Compact Scrap Pistol",min=5,max=9,tier=4},
    ["long-barrel-22-pistol"]={name="Long-Barrel .22 Pistol",min=5,max=8,tier=4},
    ["heavy-frontier-pistol"]={name="Heavy Frontier Pistol",min=7,max=12,tier=6},
    ["machine-pistol"]={name="Machine Pistol",min=6,max=10,tier=6},
    ["weathered-lever-rifle"]={name="Weathered Lever Rifle",min=8,max=13,tier=7},
    ["improvised-service-rifle"]={name="Improvised Service Rifle",min=9,max=15,tier=8},
    ["compact-carbine"]={name="Compact Carbine",min=8,max=14,tier=7},
    ["rugged-submachine-gun"]={name="Rugged Submachine Gun",min=7,max=12,tier=7},
    ["wrist-braced-slingshot"]={name="Wrist-Braced Slingshot",min=3,max=5,tier=2},
    ["metal-scrap-slingshot"]={name="Metal Scrap Slingshot",min=4,max=6,tier=3},
    ["long-hunting-slingshot"]={name="Long Hunting Slingshot",min=5,max=8,tier=4},
    ["patched-22-survival-rifle"]={name="Patched .22 Survival Rifle",min=7,max=12,tier=6},
    ["improvised-556-rifle"]={name="Improvised 5.56 Rifle",min=10,max=16,tier=9},
    ["frontier-long-barrel-revolver"]={name="Long-Barrel Frontier Revolver",min=7,max=12,tier=6},
    ["frontier-22-lever-rifle"]={name="Frontier .22 Lever Rifle",min=7,max=12,tier=6},
    ["frontier-45-1911"]={name="Frontier .45 1911",min=9,max=15,tier=7},
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
    , ["frontier-hatchet"]={name="Frontier Hatchet",min=5,max=9,tier=4}
    , ["frontier-hand-axe"]={name="Frontier Hand Axe",min=7,max=11,tier=6}
    , ["frontier-556-carbine"]={name="Frontier 5.56 Carbine",min=10,max=16,tier=9}
    , ["frontier-9mm-smg"]={name="Frontier 9mm SMG",min=8,max=13,tier=8}
    , ["frontier-22-target-pistol"]={name="Frontier .22 Target Pistol",min=5,max=9,tier=4}
    , ["frontier-380-pocket-pistol"]={name="Frontier .380 Pocket Pistol",min=6,max=10,tier=6}
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
    scratch={kind="melee",range=4}, ["brass-knuckle-duster"]={kind="melee",range=4},
    ["mob-claw"]={kind="melee",range=4}, ["mob-spit"]={kind="ranged",range=24,projectile="toxic"},
    ["train-wrench"]={kind="melee",range=4}, ["scrap-hatchet"]={kind="melee",range=4},
    ["rusty-cleaver"]={kind="melee",range=4}, ["frontier-short-sword"]={kind="melee",range=5},
    ["miners-pick"]={kind="melee",range=5}, ["gear-hammer"]={kind="melee",range=4},
    ["rail-spike-spear"]={kind="melee",range=6}, ["chain-flail"]={kind="melee",range=6},
    ["rail-spike-dagger"]={kind="melee",range=4}, ["scrap-boomerang"]={kind="ranged",range=18,capacity=1,projectile="boomerang"},
    ["steam-shock-baton"]={kind="melee",range=5}, ["hunting-bow"]={kind="ranged",range=24,ammo="arrows",capacity=1},
    ["trail-slingshot"]={kind="ranged",range=18,ammo="rocks",capacity=1}, ["critter-crossbow"]={kind="ranged",range=26,ammo="arrows",capacity=1},
    ["scrap-pistol"]={kind="ranged",range=24,ammo="9mm",capacity=8}, ["sawed-off-shotgun"]={kind="ranged",range=12,ammo="45-cal",capacity=2},
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
    , ["frontier-katana"]={kind="melee",range=6}
    , ["frontier-mace"]={kind="melee",range=5}
    , ["frontier-battle-axe"]={kind="melee",range=5}
    , ["frontier-longsword"]={kind="melee",range=6}
    , ["frontier-machete"]={kind="melee",range=5}
    , ["frontier-spear"]={kind="melee",range=7}
    , ["frontier-hatchet"]={kind="melee",range=4}
    , ["frontier-hand-axe"]={kind="melee",range=5}
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
    "trail-slingshot","brass-knuckle-duster","train-wrench","rail-spike-dagger","scrap-hatchet","rusty-cleaver",
    "scrap-boomerang","miners-pick","hunting-bow","gear-hammer","rail-spike-spear","critter-crossbow",
    "steam-shock-baton","chain-flail","scrap-pistol","sawed-off-shotgun","frontier-lever-rifle",
    "compact-scrap-pistol","long-barrel-22-pistol","heavy-frontier-pistol","machine-pistol","weathered-lever-rifle",
    "compact-carbine","rugged-submachine-gun","improvised-service-rifle","wrist-braced-slingshot",
    "metal-scrap-slingshot","long-hunting-slingshot","patched-22-survival-rifle","improvised-556-rifle",
    "frontier-long-barrel-revolver","wood-stock-survival-carbine","vintage-bolt-action-rifle","frontier-22-target-pistol","frontier-380-pocket-pistol","frontier-9mm-smg","frontier-556-carbine","frontier-12g-pump-shotgun","frontier-762-carbine","frontier-sr22-pistol","frontier-9mm-service-pistol","frontier-compact-9mm","frontier-32-pocket-pistol","frontier-22-pocket-pistol","frontier-silver-22-revolver","frontier-22-lever-rifle","frontier-45-1911","frontier-380-revolver","frontier-long-22-target-pistol","frontier-ak-compact","frontier-9mm-glock","frontier-pearl-pocket-pistol","frontier-silver-compact-pistol","frontier-compact-9mm-pistol","frontier-single-shot-hunter","frontier-lever-carbine","frontier-katana","frontier-mace","frontier-battle-axe","frontier-longsword","frontier-machete","frontier-spear","frontier-hatchet","frontier-hand-axe"
}

function Catalog.weaponFamily(name)
    local combat=Catalog.weaponCombat[name] or Catalog.weaponCombat.scratch
    if combat.kind=="melee" then return "melee" end
    if combat.ammo=="arrows" then return "bows" end
    if name and (name:find("slingshot") or name:find("boomerang")) then return "slingshots" end
    return "firearms"
end

Catalog.mobTiers = {
    easy={"flower-bird.png","ghost-small.png","pumpkin-bat.png","dust-beetle.png","cactus-rat.png","red-hood-mouse.png","shield-mouse.png","cowboy-mouse-no-skull.png"},
    medium={"attacking-eagle.png","pumpkin-cat.png","pumpkin-vampire.png","wasteland-scorpion.png","raccoon-cape.png","raccoon-heart.png"},
    hard={"ghost-tall.png","purple-dragon.png","mutant-horned-owl.png","tunnel-badger-raider.png","wasteland-human-zombie.png","vampire-mouse.png"}
}

function Catalog.encounterMobCount(tier, location)
    local chance = tier=="easy" and 0.10 or (tier=="medium" and 0.38 or 0.68)
    if (location or 1) >= 20 then chance=math.min(.82,chance+.10) end
    if love.math.random() >= chance then return 1 end
    return tier=="hard" and 3 or 2
end

Catalog.dialogueLines = {
    "Hello", "Howdy stranger", "Nice train", "Sure is hot out", "Where'd you come from?", "Where you headed?",
    "Be careful out there", "Hi", "Don't get much visitors these days", "How's yer mom and them?",
    "Hope you find what you're looking for", "Got any grapes?", "Can I borrow $3.50?",
    "What happened to the rest of the people?", "I hope my family is ok...", "What are we gonna do come winter...",
    "How far have you traveled so far?", "Some critters got mutated in the great flash.",
    "We need more people like you...", "Wow, what an adventure!"
}

Catalog.mailRequestLines={"Could you take this letter west for me?","If you see my brother, will you give him this letter?","My sister went west. If you see her, will you give her this letter?","My family is out there somewhere. Could you carry this letter?","If my dad is still alive, please show him the picture in this letter."}
Catalog.rideRequestLines={"I have to get to the next town. Could I ride with you?","Could I bother you for a ride down the tracks?","My family went west. Could I ride on your train for a couple stops?","Do you have room on your train for little ol' me?","Can I ride with you for a few? I won't take up much room."}
Catalog.passengerLines={"Thank you so much for your help.","Thank you for sharing some food with me.","I'll see my family again one day thanks to you.","I don't know what I'd do if you hadn't come along.","Wow, this old train is somethin' else, huh.","*Hums softly*","This is the most peaceful I've been in a while.","Those mean critters can't get us in here.","You're a life saver.","I hope we can be friends..."}
Catalog.mailThanksLines={"A letter for me?!","Oh my gosh, thank you so much!","It's from my family! Where did you get this? Thank you!","I can't believe they are okay and still looking for me...","A letter from my family—this brings me so much hope.","I knew they would make it! I'm so happy!"}
Catalog.questRewardItems={"food-ration","water-bottle","field-bandage-roll","wrapped-sweet","coal-chunk","herbal-tonic"}
Catalog.ammoPickupAmounts={rocks=8,arrows=6,["ball-bearings"]=8,["9mm"]=12,["45-cal"]=8,["556"]=10,["22lr"]=15,["30-carbine"]=10,["8mm"]=8,["380-acp"]=8,["32-acp"]=8,["12-gauge"]=6,["762x39"]=10}

Catalog.lootPools = {
    food={"food-ration","bread-loaf","red-apple","carrot","hand-pie","jam-jar","berry-jar","trail-beans-can","dried-berry-pouch","cornbread-square","jerky-bundle","smoked-trout","honey-biscuits","roasted-squash","acorn-cluster","oat-porridge"},
    water={"water-bottle","water-canteen","metal-water-flask","blue-water-bottle","rainwater-jar","patched-canteen","boxed-fruit-drink"},
    common={"food-ration","bread-loaf","red-apple","carrot","water-bottle","water-canteen","coal-chunk","rocks","arrows","ball-bearings","wrapped-sweet","honey-biscuits","acorn-cluster"},
    uncommon={"hand-pie","jam-jar","trail-mix-pouch","trail-cheese","metal-water-flask","rainwater-jar","field-bandage-roll","herbal-tonic","9mm","22lr","45-cal","30-carbine","380-acp","32-acp","12-gauge","patched-canvas-pack","frontier-380-revolver"},
    rare={"mushroom-stew","preserved-peaches","ceramic-water-crock","healing-salve","frontier-medkit","compact-scrap-pistol","long-barrel-22-pistol","heavy-frontier-pistol","weathered-lever-rifle","compact-carbine","frontier-long-barrel-revolver","wood-stock-survival-carbine","frontier-22-target-pistol","frontier-380-pocket-pistol","frontier-12g-pump-shotgun","frontier-762-carbine","frontier-sr22-pistol","frontier-9mm-service-pistol","frontier-compact-9mm","frontier-32-pocket-pistol","frontier-22-pocket-pistol","frontier-silver-22-revolver","frontier-22-lever-rifle","frontier-45-1911","frontier-long-22-target-pistol","frontier-katana","frontier-mace","frontier-battle-axe","frontier-longsword","frontier-machete","frontier-spear","frontier-hatchet","frontier-hand-axe","weathered-leather-pack","red-leather-pack","compact-sling-pack","black-sling-pack","556","762x39","8mm","bedroll-hiking-pack","frontier-leather-pack"},
    legendary={"rose-heart-arrow","blade-hearts","machine-pistol","rugged-submachine-gun","improvised-service-rifle","vintage-bolt-action-rifle","emergency-syringe-case","scavenger-frame-pack"}
}

return Catalog
