"""Exercise real home loot, route unlocks, and consumed-cache persistence.

Only LÖVE randomness and its filesystem are replaced. Saves are serialized by
the production Save module into an in-memory table; player saves are untouched.
Expected budgets and route gates are declared here independently of Loot.audit.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


HARNESS = r'''
    package.path=project_root..'/?.lua;'..package.path
    files={}
    randomDraw=function() return .99 end
    love={math={random=function(low,high)
        local value=randomDraw()
        if high then return low+math.floor(value*(high-low+1)) end
        if low then return 1+math.floor(value*low) end
        return value
    end},filesystem={
        getInfo=function(path) return files[path] and {type='file'} end,
        createDirectory=function() return true end,
        write=function(path,contents) files[path]=contents; return true end,
        read=function(path) return files[path] end,
        load=function(path) return loadstring(files[path] or '',path) end,
        remove=function(path) files[path]=nil; return true end,
    }}
    Catalog=require('game.catalog')
    Loot=require('game.loot_progression')
    House=require('game.house')
    Schema=require('game.save_schema')
    Save=require('game.save')

    milestoneStops={[7]=true,[13]=true,[19]=true,[25]=true,[31]=true,
        [37]=true,[43]=true,[49]=true}
    expectedAmmoTier={rocks=1,arrows=1,['ball-bearings']=1,
        ['22lr']=3,['32-acp']=3,['380-acp']=4,['9mm']=4,['45-cal']=5,
        ['30-carbine']=5,['12-gauge']=6,['556']=7,['762x39']=8,['8mm']=8}
    expectedItemTier={['patched-canvas-pack']=2,['compact-sling-pack']=2,
        ['black-sling-pack']=3,['bedroll-hiking-pack']=4,['red-leather-pack']=5,
        ['weathered-leather-pack']=6,['frontier-leather-pack']=7,
        ['scavenger-frame-pack']=9,['medium-oil-canister']=3,
        ['large-oil-canister']=6,['emergency-syringe-case']=9}
    expectedRarityTier={common=1,uncommon=1,rare=3,legendary=6}
    foodLimit={2,2,3,3,4,4,5,5,5}
    waterLimit={3,3,4,4,5,5,6,6,7}
    healthLimit={5,8,8,12,12,12,12,14,99}

    function seeded(seed)
        -- Park-Miller uses products exactly representable in Lua 5.1 doubles.
        local state=seed
        return function()
            state=(state*16807)%2147483647
            return (state-1)/2147483646
        end
    end
    function prepared(stop,door,overrides)
        local data={character='scout-frog.png',location=stop,activeHouseDoor=door,
            inventory={},inventoryCapacity=6,equipment={},weaponDurability={},
            droppedItems={},stopLayouts={},lootRolls={}}
        for key,value in pairs(overrides or {}) do data[key]=value end
        return assert(Schema.migrate(data))
    end
    function contents(data,stop,door)
        local result={}
        for _,item in ipairs(data.droppedItems) do
            if item.scene=='house' and item.location==stop and (item.houseDoor or 1)==door then
                local capacity=assert(Catalog.storageCapacities[item.name],
                    'home reward became loose ground loot: '..tostring(item.name))
                for slot,name in pairs(item.storage or {}) do
                    assert(type(slot)=='number' and slot>=1 and slot<=capacity,
                        'reward exceeded the actual container capacity')
                    result[#result+1]=name
                end
            end
        end
        return result
    end
    function countMatching(names,predicate)
        local count=0
        for _,name in ipairs(names) do if predicate(name) then count=count+1 end end
        return count
    end
    function expectedTier(stop) return math.min(9,1+math.floor((stop-1)/6)) end
    function assertItemTiming(name,stop)
        local tier=expectedTier(stop)
        assert(not Catalog.weaponStats[name],'generic item draw awarded a weapon: '..name)
        assert(not Catalog.repairParts[name],'generic draw awarded a repair component: '..name)
        assert(not Catalog.outfitUpgrades[name],'generic draw bypassed outfit crafting: '..name)
        local unlock=expectedItemTier[name] or expectedAmmoTier[name] or 1
        assert(tier>=unlock,name..' appeared before its route unlock at stop '..stop)
        local rarity=Catalog.rarityFor(name)
        assert(tier>=(expectedRarityTier[rarity] or 1),
            rarity..' item '..name..' appeared early at stop '..stop)
        local effect=Catalog.itemEffects[name] or {}
        assert(not effect.food or effect.food<=foodLimit[tier],name..' overfeeds early route')
        assert(not effect.water or effect.water<=waterLimit[tier],name..' overhydrates early route')
        assert(not effect.health or effect.health<=healthLimit[tier],name..' heals too much early')
    end
    function roundtrip(data)
        assert(Save.write(99,data),'production save serialization failed')
        return assert(Save.read(99),'production save deserialization failed')
    end
    function assertEqualTables(a,b,label)
        assert(type(a)==type(b),label..' changed type')
        if type(a)~='table' then assert(a==b,label..' changed'); return end
        for key,value in pairs(a) do assertEqualTables(value,b[key],label..'.'..tostring(key)) end
        for key in pairs(b) do assert(a[key]~=nil,label..' acquired '..tostring(key)) end
    end
    function seenItems(stop)
        local seen={}
        for _,rarity in ipairs({'common','uncommon','rare','legendary'}) do
            for sample=0,255 do
                local name=Loot.rollItem(Catalog,stop,{allowWeapon=false,
                    minimumRarity=rarity,rng=function() return sample/256 end})
                assert(name,'nonweapon reward pool unexpectedly empty at stop '..stop)
                assertItemTiming(name,stop)
                seen[name]=true
            end
        end
        return seen
    end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class HomeLootProgressionBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def test_actual_home_budgets_hold_across_every_stop_door_and_seed(self) -> None:
        self.lua.execute(r'''
            for stop=1,50 do
                for door=1,3 do
                    for seed=1,24 do
                        randomDraw=seeded(seed*1009+stop*13+door)
                        local data=prepared(stop,door)
                        House.rollLoot(data,Catalog,stop)
                        local names=contents(data,stop,door)
                        local expected=door==1 and (milestoneStops[stop] and 6 or 5) or 4
                        assert(#names==expected,'home budget at stop '..stop..' door '..door..
                            ' seed '..seed..': expected '..expected..', got '..#names)
                        local weapons=countMatching(names,function(name) return Catalog.weaponStats[name] end)
                        assert(weapons==((door==1 and milestoneStops[stop]) and 1 or 0),
                            'weapons are reserved for the first home at the eight milestones')
                        assert(countMatching(names,function(name) return Catalog.repairParts[name] end)==0,
                            'player without a damaged owned weapon received a repair component')
                    end
                end
            end
        ''')

    def test_special_first_home_rewards_do_not_depend_on_visit_order(self) -> None:
        self.lua.execute(r'''
            for _,stop in ipairs({1,6,7,12,13,19,25,31,37,43,49,50}) do
                randomDraw=function() return .99 end
                local data=prepared(stop,2)
                for _,door in ipairs({2,1,3}) do
                    data.activeHouseDoor=door
                    House.rollLoot(data,Catalog,stop)
                    local names=contents(data,stop,door)
                    local materials=countMatching(names,function(name) return Catalog.craftMaterials[name] end)
                    -- This draw selects rail-token for household salvage, avoiding
                    -- its valid thread-spool overlap with crafting materials.
                    assert(materials==(door==1 and 1 or 0),
                        'crafting salvage was duplicated into another home')
                    local weapons=countMatching(names,function(name) return Catalog.weaponStats[name] end)
                    assert(weapons==((door==1 and milestoneStops[stop]) and 1 or 0))
                end
            end
        ''')

    def test_seeded_actual_home_items_respect_route_timing(self) -> None:
        self.lua.execute(r'''
            for stop=1,50 do
                for seed=1,96 do
                    randomDraw=seeded(seed*8191+stop*31)
                    local data=prepared(stop,2)
                    House.rollLoot(data,Catalog,stop)
                    local names=contents(data,stop,2)
                    assert(#names==4)
                    for _,name in ipairs(names) do assertItemTiming(name,stop) end
                end
            end
        ''')

    def test_item_unlock_boundaries_reject_early_draws_and_allow_later_rewards(self) -> None:
        self.lua.execute(r'''
            for tier=1,9 do
                local stop=1+(tier-1)*6
                seenItems(stop)
                if stop>1 then seenItems(stop-1) end
            end
            for name,unlock in pairs(expectedItemTier) do
                local effective=math.max(unlock,expectedRarityTier[Catalog.rarityFor(name)] or 1)
                local stop=1+(effective-1)*6
                assert(seenItems(stop)[name],name..' never becomes obtainable when unlocked')
                if stop>1 then assert(not seenItems(stop-1)[name],name..' appears before its unlock') end
            end
            for _,name in ipairs({'rose-heart-arrow','blade-hearts'}) do
                assert(not seenItems(30)[name] and seenItems(31)[name],
                    'legendary household rewards must unlock at stop 31')
            end
        ''')

    def test_ammo_supply_and_healing_draws_cover_real_unlock_boundaries(self) -> None:
        self.lua.execute(r'''
            for stop=1,50 do
                local tier=expectedTier(stop)
                local seenAmmo={}
                for sample=0,255 do
                    local rng=function() return sample/256 end
                    local ammo=Loot.rollAmmo(Catalog,stop,rng)
                    assert(expectedAmmoTier[ammo] and expectedAmmoTier[ammo]<=tier,
                        'ammunition appeared before compatible weapons at stop '..stop)
                    seenAmmo[ammo]=true
                    for _,kind in ipairs({'food','water'}) do
                        local name=Loot.rollSupply(Catalog,kind,stop,rng)
                        local effect=assert(Catalog.itemEffects[name])
                        local limit=kind=='food' and foodLimit[tier] or waterLimit[tier]
                        assert(effect[kind] and not effect.potion and effect[kind]<=limit,
                            'supply draw exceeded '..kind..' budget at stop '..stop)
                        assertItemTiming(name,stop)
                    end
                    local medical=Loot.rollMedical(Catalog,stop,'legendary',rng)
                    assert(medical,'medical draw unexpectedly empty')
                    local effect=assert(Catalog.itemEffects[medical])
                    assert(effect.health and not effect.potion and effect.health<=healthLimit[tier])
                    assertItemTiming(medical,stop)
                end
                for ammo,unlock in pairs(expectedAmmoTier) do
                    assert((seenAmmo[ammo]==true)==(unlock<=tier),
                        'ammo pool lost or prematurely enabled '..ammo..' at stop '..stop)
                end
            end
        ''')

    def test_repair_components_require_critical_owned_weapon_and_exact_missing_part(self) -> None:
        self.lua.execute(r'''
            randomDraw=function() return .1 end -- Guaranteed first-home repair opportunity.
            for weapon in pairs(Catalog.weaponRepairParts) do
                local part=Catalog.weaponRepairParts[weapon]
                local cases={
                    {equipment={weapon},weaponDurability={[weapon]=25}},
                    {inventory={[6]=weapon},weaponDurability={[weapon]=0}},
                    {equipment={weapon},weaponDurability={[weapon]=26}},
                    {weaponDurability={[weapon]=0}}, -- Historical condition is not ownership.
                    {equipment={weapon},weaponDurability={[weapon]=0},inventory={[6]=part}},
                }
                for index,overrides in ipairs(cases) do
                    local data=prepared(1,1,overrides)
                    House.rollLoot(data,Catalog,1)
                    local found={}
                    for _,name in ipairs(contents(data,1,1)) do
                        if Catalog.repairParts[name] then found[#found+1]=name end
                    end
                    local expected=index<=2 and 1 or 0
                    assert(#found==expected,'repair eligibility case '..index..' failed for '..weapon)
                    assert(not found[1] or found[1]==part,'home awarded a part for an unowned weapon')
                    assert(#contents(data,1,1)==5+expected,'repair opportunity inflated home budget')
                end
                local other=prepared(1,2,{equipment={weapon},weaponDurability={[weapon]=0}})
                House.rollLoot(other,Catalog,1)
                assert(countMatching(contents(other,1,2),function(name) return Catalog.repairParts[name] end)==0,
                    'second home bypassed the first-home repair limit')
            end
            for alias,part in pairs(Catalog.repairPartAliases) do
                local weapon=Catalog.repairParts[part].weapon
                local data=prepared(1,1,{equipment={weapon},weaponDurability={[weapon]=0},inventory={[6]=alias}})
                House.rollLoot(data,Catalog,1)
                assert(countMatching(contents(data,1,1),function(name) return Catalog.repairParts[name] end)==0,
                    'legacy alias was not recognized as an already owned exact part')
            end
        ''')

    def test_repair_opportunity_boundary_is_saved_and_cannot_be_rerolled(self) -> None:
        self.lua.execute(r'''
            local weapon='frontier-short-sword'
            for _,value in ipairs({0,.299999,.30,.999999}) do
                randomDraw=function() return value end
                local data=prepared(1,1,{equipment={weapon},weaponDurability={[weapon]=0}})
                House.rollLoot(data,Catalog,1)
                local expected=value<.30 and 1 or 0
                assert(countMatching(contents(data,1,1),function(name) return Catalog.repairParts[name] end)==expected,
                    'repair opportunity changed at random draw '..value)
                data=roundtrip(data)
                local before=assert(Schema.migrate(data))
                randomDraw=function() return 0 end
                House.rollLoot(data,Catalog,1)
                assertEqualTables(before.droppedItems,data.droppedItems,'saved repair opportunity')
                assertEqualTables(before.lootRolls,data.lootRolls,'saved repair flags')
            end
        ''')

    def test_consumed_homes_stay_empty_after_real_save_load_and_other_visits(self) -> None:
        self.lua.execute(r'''
            for _,stop in ipairs({1,7,13,31,49}) do
                randomDraw=seeded(stop*1297)
                local data=prepared(stop,1)
                House.rollLoot(data,Catalog,stop)
                data.activeHouseDoor=2
                House.rollLoot(data,Catalog,stop)
                -- Claim everything in home 1, keeping its containers and roll flags.
                for _,item in ipairs(data.droppedItems) do
                    if item.scene=='house' and item.location==stop and item.houseDoor==1 then item.storage={} end
                end
                data=roundtrip(data)
                local baseline=assert(Schema.migrate(data))
                for _,door in ipairs({1,2,1,2}) do
                    data.activeHouseDoor=door
                    House.rollLoot(data,Catalog,stop)
                end
                assertEqualTables(baseline.droppedItems,data.droppedItems,'consumed and retained home loot')
                assertEqualTables(baseline.lootRolls,data.lootRolls,'visited home flags')
                data.activeHouseDoor=3
                House.rollLoot(data,Catalog,stop)
                assert(#contents(data,stop,3)==4,'a fresh door should still receive its ordinary budget')
                assert(#contents(data,stop,1)==0,'visiting a different home replenished a consumed cache')
                data.location=stop+1
                data.activeHouseDoor=1
                House.rollLoot(data,Catalog,stop+1)
                assert(#contents(data,stop+1,1)==5,'next ordinary stop lost its first-home budget')
                data=roundtrip(data)
                data.activeHouseDoor=1
                House.rollLoot(data,Catalog,stop)
                assert(#contents(data,stop,1)==0,'later-stop save restored previously claimed loot')
            end
        ''')

    def test_existing_contents_and_other_homes_survive_container_capacity_overflow(self) -> None:
        self.lua.execute(r'''
            randomDraw=function() return .99 end
            local data=prepared(13,1)
            local first={name='travel-chest',scene='house',location=13,houseDoor=1,storage={}}
            local other={name='supply-crate',scene='house',location=13,houseDoor=2,storage={[1]='water-bottle'}}
            local train={name='supply-crate',scene='train',carIndex=1,storage={[1]='food-ration'}}
            for slot=1,Catalog.storageCapacities[first.name]-1 do first.storage[slot]='coal-chunk' end
            data.droppedItems={first,other,train}
            local baseline=assert(Schema.migrate(data))
            House.rollLoot(data,Catalog,13)
            assert(#contents(data,13,1)==9+6,'full storage lost or created extra home rewards')
            for slot=1,9 do assert(first.storage[slot]=='coal-chunk','existing contents were overwritten') end
            assertEqualTables(baseline.droppedItems[2],other,'other door container')
            assertEqualTables(baseline.droppedItems[3],train,'train container')
            assert(#data.droppedItems==4,'overflow should add exactly one correctly scoped crate')
            local crate=data.droppedItems[4]
            assert(crate.name=='supply-crate' and crate.scene=='house' and crate.location==13 and crate.houseDoor==1)
            local saved=roundtrip(data)
            House.rollLoot(saved,Catalog,13)
            assertEqualTables(data.droppedItems,saved.droppedItems,'capacity overflow after save/load')
        ''')


if __name__ == '__main__':
    unittest.main()
