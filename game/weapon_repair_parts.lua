-- One fitted replacement component per player weapon.
-- Art identities and source references: docs/concepts/weapon-repair/*-part-specs.json.
local Parts = {}
local specifications = {
    {weapon="brass-knuckle-duster",id="brass-knuckle-duster-palm-grip",component="Palm Grip",icon="core"},
    {weapon="train-wrench",id="train-wrench-hook-jaw",component="Hook Jaw",icon="hammer"},
    {weapon="salvage-pry-bar",id="salvage-pry-bar-grip-wrap",component="Grip Wrap",icon="core"},
    {weapon="scrap-hatchet",id="scrap-hatchet-hatchet-head",component="Hatchet Head",icon="axe"},
    {weapon="rusty-cleaver",id="rusty-cleaver-cleaver-blade",component="Cleaver Blade",icon="blade"},
    {weapon="frontier-short-sword",id="frontier-short-sword-crossguard",component="Crossguard",icon="blade"},
    {weapon="patched-trench-knife",id="patched-trench-knife-knife-blade",component="Knife Blade",icon="blade"},
    {weapon="scrap-hunting-spear",id="scrap-hunting-spear-spearhead",component="Spearhead",icon="spear"},
    {weapon="salvaged-track-hatchet",id="salvaged-track-hatchet-track-hatchet-head",component="Track Hatchet Head",icon="axe"},
    {weapon="miners-pick",id="miners-pick-pick-head",component="Pick Head",icon="hammer"},
    {weapon="gear-hammer",id="gear-hammer-gear-head",component="Gear Head",icon="hammer"},
    {weapon="rail-spike-spear",id="rail-spike-spear-spike-head",component="Spike Head",icon="spear"},
    {weapon="gear-toothed-falchion",id="gear-toothed-falchion-falchion-blade",component="Falchion Blade",icon="blade"},
    {weapon="frontier-fork-trident",id="frontier-fork-trident-trident-head",component="Trident Head",icon="spear"},
    {weapon="gearwright-bearded-axe",id="gearwright-bearded-axe-bearded-axe-head",component="Bearded Axe Head",icon="axe"},
    {weapon="chain-flail",id="chain-flail-flail-chain",component="Flail Chain",icon="hammer"},
    {weapon="rail-spike-dagger",id="rail-spike-dagger-dagger-blade",component="Dagger Blade",icon="blade"},
    {weapon="frontier-hook-sickle",id="frontier-hook-sickle-sickle-blade",component="Sickle Blade",icon="blade"},
    {weapon="frontier-curved-saber",id="frontier-curved-saber-saber-blade",component="Saber Blade",icon="blade"},
    {weapon="scrap-boomerang",id="scrap-boomerang-joining-plate",component="Joining Plate",icon="core"},
    {weapon="steam-shock-baton",id="steam-shock-baton-contact-head",component="Contact Head",icon="hammer"},
    {weapon="hunting-bow",id="hunting-bow-bowstring",component="Bowstring",icon="bow"},
    {weapon="trail-slingshot",id="trail-slingshot-leather-pouch",component="Leather Pouch",icon="bands"},
    {weapon="critter-crossbow",id="critter-crossbow-recurve-prod",component="Recurve Prod",icon="crossbow"},
    {weapon="railway-cutlass",id="railway-cutlass-knuckle-guard",component="Knuckle Guard",icon="blade"},
    {weapon="hooked-railway-halberd",id="hooked-railway-halberd-halberd-head",component="Halberd Head",icon="spear"},
    {weapon="rail-splitter-axe",id="rail-splitter-axe-splitter-head",component="Splitter Head",icon="axe"},
    {weapon="wrist-braced-slingshot",id="wrist-braced-slingshot-tube-band",component="Tube Band",icon="bands"},
    {weapon="metal-scrap-slingshot",id="metal-scrap-slingshot-fork-clamp",component="Fork Clamp",icon="bands"},
    {weapon="long-hunting-slingshot",id="long-hunting-slingshot-long-bandset",component="Long Bandset",icon="bands"},
    {weapon="frontier-katana",id="frontier-katana-blade-collar",component="Blade Collar",icon="blade"},
    {weapon="frontier-mace",id="frontier-mace-flanged-head",component="Flanged Head",icon="hammer"},
    {weapon="frontier-battle-axe",id="frontier-battle-axe-battle-axe-head",component="Battle Axe Head",icon="axe"},
    {weapon="frontier-longsword",id="frontier-longsword-wheel-pommel",component="Wheel Pommel",icon="blade"},
    {weapon="frontier-machete",id="frontier-machete-grip-scale",component="Grip Scale",icon="blade"},
    {weapon="frontier-spear",id="frontier-spear-leaf-head",component="Leaf Head",icon="spear"},
    {weapon="frontier-hatchet",id="frontier-hatchet-hickory-handle",component="Hickory Handle",icon="axe"},
    {weapon="frontier-hand-axe",id="frontier-hand-axe-grip-wrap",component="Grip Wrap",icon="axe"},
    {weapon="frontier-cavalry-saber",id="frontier-cavalry-saber-brass-guard",component="Brass Guard",icon="blade"},
    {weapon="boiler-smith-maul",id="boiler-smith-maul-maul-head",component="Maul Head",icon="hammer"},
    {weapon="railway-war-pick",id="railway-war-pick-war-pick-head",component="War Pick Head",icon="hammer"},
    {weapon="brass-backed-greatsword",id="brass-backed-greatsword-spine-plate",component="Spine Plate",icon="blade"},
    {weapon="wasteland-partisan",id="wasteland-partisan-partisan-head",component="Partisan Head",icon="spear"},
    {weapon="frontier-executioner-axe",id="frontier-executioner-axe-executioner-head",component="Executioner Head",icon="axe"},
    {weapon="scrap-pistol",id="scrap-pistol-rolling-breechblock",component="Rolling Breechblock",icon="bolt"},
    {weapon="sawed-off-shotgun",id="sawed-off-shotgun-stacked-barrel-set",component="Stacked Barrel Set",icon="barrel"},
    {weapon="frontier-lever-rifle",id="frontier-lever-rifle-brass-action-lever",component="Brass Action Lever",icon="lever"},
    {weapon="compact-scrap-pistol",id="compact-scrap-pistol-heavy-slide",component="Heavy Slide",icon="slide"},
    {weapon="long-barrel-22-pistol",id="long-barrel-22-pistol-buntline-barrel",component="Buntline Barrel",icon="barrel"},
    {weapon="heavy-frontier-pistol",id="heavy-frontier-pistol-heavy-cylinder",component="Heavy Cylinder",icon="cylinder"},
    {weapon="machine-pistol",id="machine-pistol-perforated-shroud",component="Perforated Shroud",icon="barrel"},
    {weapon="weathered-lever-rifle",id="weathered-lever-rifle-large-loop-lever",component="Large Loop Lever",icon="lever"},
    {weapon="improvised-service-rifle",id="improvised-service-rifle-piston-carrier",component="Piston Carrier",icon="bolt"},
    {weapon="compact-carbine",id="compact-carbine-charging-handle",component="Charging Handle",icon="bolt"},
    {weapon="rugged-submachine-gun",id="rugged-submachine-gun-top-cocking-bolt",component="Top-Cocking Bolt",icon="bolt"},
    {weapon="patched-22-survival-rifle",id="patched-22-survival-rifle-rotary-magazine",component="Rotary Magazine",icon="bolt"},
    {weapon="improvised-556-rifle",id="improvised-556-rifle-patched-handguard",component="Patched Handguard",icon="barrel"},
    {weapon="frontier-long-barrel-revolver",id="frontier-long-barrel-revolver-blued-cylinder",component="Blued Cylinder",icon="cylinder"},
    {weapon="frontier-22-lever-rifle",id="frontier-22-lever-rifle-takedown-lever",component="Takedown Lever",icon="lever"},
    {weapon="frontier-45-1911",id="frontier-45-1911-government-slide",component="Government Slide",icon="slide"},
    {weapon="frontier-380-revolver",id="frontier-380-revolver-five-shot-cylinder",component="Five-Shot Cylinder",icon="cylinder"},
    {weapon="frontier-long-22-target-pistol",id="frontier-long-22-target-pistol-slender-target-barrel",component="Slender Target Barrel",icon="barrel"},
    {weapon="wood-stock-survival-carbine",id="wood-stock-survival-carbine-operating-slide",component="Operating Slide",icon="bolt"},
    {weapon="vintage-bolt-action-rifle",id="vintage-bolt-action-rifle-turned-down-bolt",component="Turned-Down Bolt",icon="bolt"},
    {weapon="frontier-556-carbine",id="frontier-556-carbine-bolt-carrier-group",component="Bolt Carrier Group",icon="bolt"},
    {weapon="frontier-9mm-smg",id="frontier-9mm-smg-roller-bolt-group",component="Roller Bolt Group",icon="bolt"},
    {weapon="frontier-22-target-pistol",id="frontier-22-target-pistol-cylindrical-target-bolt",component="Cylindrical Target Bolt",icon="bolt"},
    {weapon="frontier-380-pocket-pistol",id="frontier-380-pocket-pistol-stainless-pocket-slide",component="Stainless Pocket Slide",icon="slide"},
    {weapon="frontier-12g-pump-shotgun",id="frontier-12g-pump-shotgun-sighted-pump-barrel",component="Sighted Pump Barrel",icon="barrel"},
    {weapon="frontier-762-carbine",id="frontier-762-carbine-gas-tube-handguard",component="Gas Tube Handguard",icon="barrel"},
    {weapon="frontier-sr22-pistol",id="frontier-sr22-pistol-silver-rimfire-slide",component="Silver Rimfire Slide",icon="slide"},
    {weapon="frontier-9mm-service-pistol",id="frontier-9mm-service-pistol-open-top-service-slide",component="Open-Top Service Slide",icon="slide"},
    {weapon="frontier-compact-9mm",id="frontier-compact-9mm-cheetah-slide",component="Cheetah Slide",icon="slide"},
    {weapon="frontier-32-pocket-pistol",id="frontier-32-pocket-pistol-streamlined-pocket-slide",component="Streamlined Pocket Slide",icon="slide"},
    {weapon="frontier-22-pocket-pistol",id="frontier-22-pocket-pistol-rounded-pocket-slide",component="Rounded Pocket Slide",icon="slide"},
    {weapon="frontier-silver-22-revolver",id="frontier-silver-22-revolver-silver-single-action-cylinder",component="Silver Single-Action Cylinder",icon="cylinder"},
    {weapon="frontier-ak-compact",id="frontier-ak-compact-short-gas-tube-handguard",component="Short Gas Tube Handguard",icon="barrel"},
    {weapon="frontier-9mm-glock",id="frontier-9mm-glock-square-hood-barrel",component="Square-Hood Barrel",icon="barrel"},
    {weapon="frontier-pearl-pocket-pistol",id="frontier-pearl-pocket-pistol-engraved-vest-slide",component="Engraved Vest Slide",icon="slide"},
    {weapon="frontier-silver-compact-pistol",id="frontier-silver-compact-pistol-short-target-barrel",component="Short Target Barrel",icon="barrel"},
    {weapon="frontier-compact-9mm-pistol",id="frontier-compact-9mm-pistol-micro-slide",component="Micro Slide",icon="slide"},
    {weapon="frontier-single-shot-hunter",id="frontier-single-shot-hunter-hinged-barrel",component="Hinged Barrel",icon="barrel"},
    {weapon="frontier-lever-carbine",id="frontier-lever-carbine-carbine-loop-lever",component="Carbine Loop Lever",icon="lever"},
}
-- Old test-build items resolve to exactly one weapon. They never enter new loot.
local legacyWeapons = {
    ["shotgun-barrel"]="sawed-off-shotgun",
    ["shotgun-bolt-assembly"]="frontier-12g-pump-shotgun",
    ["lever-action-group"]="frontier-lever-rifle",
    ["rifle-barrel"]="frontier-single-shot-hunter",
    ["rifle-bolt-assembly"]="vintage-bolt-action-rifle",
    ["pistol-barrel"]="frontier-45-1911",
    ["pistol-slide-assembly"]="frontier-9mm-service-pistol",
    ["revolver-cylinder"]="frontier-380-revolver",
    ["bow-limb-set"]="hunting-bow",
    ["crossbow-cable-set"]="critter-crossbow",
    ["slingshot-band-kit"]="trail-slingshot",
    ["boomerang-core"]="scrap-boomerang",
    ["blade-blank"]="frontier-short-sword",
    ["axe-head"]="scrap-hatchet",
    ["striking-head"]="gear-hammer",
    ["polearm-head"]="scrap-hunting-spear",
}

function Parts.build(weaponStats)
    local definitions, byWeapon, aliases = {}, {}, {}
    for _, spec in ipairs(specifications) do
        local stats=assert(weaponStats[spec.weapon],"Unknown repair weapon: "..spec.weapon)
        assert(not byWeapon[spec.weapon],"Duplicate repair weapon: "..spec.weapon)
        assert(not definitions[spec.id],"Duplicate repair component: "..spec.id)
        local tier=stats.tier or 1
        local rarity=tier>=9 and "legendary" or tier>=6 and "rare" or tier>=3 and "uncommon" or "common"
        definitions[spec.id]={
            name=stats.name.." — "..spec.component,
            component=spec.component, weapon=spec.weapon, rarity=rarity,
            icon=spec.icon, sprite="assets/sprites/weapon-parts/"..spec.id..".png",
            description="A fitted "..spec.component:lower().." for "..stats.name..". Fits this weapon only.",
            worldScale=.72,
        }
        byWeapon[spec.weapon]=spec.id
    end
    for weapon,stats in pairs(weaponStats) do
        if weapon~="scratch" and weapon~="mob-claw" and weapon~="mob-spit" then
            assert(byWeapon[weapon],"Missing repair component: "..weapon)
        end
    end
    for oldId,weapon in pairs(legacyWeapons) do aliases[oldId]=assert(byWeapon[weapon]) end
    setmetatable(definitions,{__index=function(t,id)
        local canonical=aliases[id]
        return canonical and rawget(t,canonical) or nil
    end})
    return {definitions=definitions,byWeapon=byWeapon,aliases=aliases}
end

return Parts
