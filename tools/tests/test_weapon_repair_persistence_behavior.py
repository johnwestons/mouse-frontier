"""Repair-component loot, inventory, and saved-state checks using real Lua modules.

The filesystem is a Lua table; these tests never read or change player saves.
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


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class WeaponRepairPersistenceBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            files={}; writes=0; randomValue=0
            love={math={random=function(low,high)
                if high then return low end
                if low then return 1 end
                return randomValue
            end},filesystem={
                getInfo=function(path) return files[path] and {type='file'} end,
                createDirectory=function() return true end,
                write=function(path,contents) writes=writes+1; files[path]=contents; return true end,
                read=function(path) return files[path] end,
                load=function(path) return loadstring(files[path] or '',path) end,
                remove=function(path) files[path]=nil; return true end,
            }}
            Catalog=require('game.catalog')
            Loot=require('game.loot_progression')
            House=require('game.house')
            Inventory=require('game.inventory')
            Schema=require('game.save_schema')
            Save=require('game.save')
            Merchant=require('game.merchant_trade')
            Crow=require('game.crow_caravans')
            function prepared(overrides)
                local data={character='scout-frog.png',inventory={},equipment={},
                    inventoryCapacity=6,scrap=1000,weaponDurability={},droppedItems={}}
                for key,value in pairs(overrides or {}) do data[key]=value end
                return assert(Schema.migrate(data))
            end
            function roundtrip(data)
                assert(Save.write(1,data),'in-memory save write succeeds')
                return assert(Save.read(1),'in-memory save read succeeds')
            end
            function repairCount(data,door)
                local count=0
                for _,item in ipairs(data.droppedItems) do
                    if not door or item.houseDoor==door then
                        for _,name in pairs(item.storage or {}) do
                            if Catalog.repairParts[name] then count=count+1 end
                        end
                    end
                end
                return count
            end
            function visitedHouse(data,location,door)
                local key=tostring(location)..':'..tostring(door)
                data.lootRolls[key]=true
                data.lootRolls['household:2:'..key]=true
                data.lootRolls['outfit-materials:1:'..key]=true
                data.activeHouseDoor=door
            end
            function transfer(data,chest,ref)
                return Inventory.quickTransfer(data,chest,ref,Catalog.weaponStats,
                    Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems)
            end
        ''')

    def test_all_parts_and_legacy_aliases_survive_real_save_serialization(self) -> None:
        self.lua.execute(r'''
            local names={}
            for name in pairs(Catalog.repairParts) do names[#names+1]=name end
            assert(#names==83,'all player weapons have active components')
            for name in pairs(Catalog.repairPartAliases) do names[#names+1]=name end
            table.sort(names)
            local data=prepared({inventoryCapacity=#names})
            local chest={name='supply-crate',scene='house',location=7,houseDoor=2,storage={}}
            data.droppedItems[1]=chest
            for index,name in ipairs(names) do
                data.inventory[index]=name
                chest.storage[index*2]=name
                data.droppedItems[index+1]={name=name,scene='train',carIndex=1,x=300,y=400}
                data.weaponDurability[Catalog.repairParts[name].weapon]=23
            end
            data.lootRolls['repair-parts:1:7:2']=true
            local saved=roundtrip(data)
            for index,name in ipairs(names) do
                assert(saved.inventory[index]==name)
                assert(saved.droppedItems[1].storage[index*2]==name,'sparse stored parts persist')
                assert(saved.droppedItems[index+1].name==name,'loose dropped parts persist')
                assert(saved.weaponDurability[Catalog.repairParts[name].weapon]==23)
            end
            assert(saved.lootRolls['repair-parts:1:7:2'])
            assert(saved.droppedItems[1].houseDoor==2)
            saved.inventory[1]=nil
            assert(data.inventory[1]==names[1],'restored state has no references into the original')
        ''')

    def test_first_home_salvage_survives_collection_and_reload_without_other_door_restock(self) -> None:
        self.lua.execute(r'''
            local weapon='scrap-hatchet'
            local part=Catalog.weaponRepairParts[weapon]
            local data=prepared({equipment={weapon},weaponDurability={[weapon]=0}})
            visitedHouse(data,7,1)
            House.rollLoot(data,Catalog,7)
            assert(repairCount(data,1)==1 and repairCount(data,2)==0)
            assert(data.droppedItems[1].storage[1]==part,'critical owned weapon gets targeted part')
            assert(transfer(data,data.droppedItems[1],{kind='chest',index=1}))
            assert(data.inventory[1]==part and repairCount(data,1)==0)
            data=roundtrip(data)
            House.rollLoot(data,Catalog,7)
            assert(repairCount(data,1)==0,'collected salvage never replenishes after load')
            visitedHouse(data,7,2)
            House.rollLoot(data,Catalog,7)
            assert(repairCount(data,2)==0,'other house doors cannot add repair salvage')
            assert(data.lootRolls['repair-parts:1:7:2'],'other door persists its completed salvage opportunity')
            House.rollLoot(data,Catalog,7)
            assert(repairCount(data,2)==0,'reopening the second door never adds a component')
        ''')

    def test_failed_salvage_roll_is_saved_without_rerolling(self) -> None:
        self.lua.execute(r'''
            local data=prepared()
            visitedHouse(data,1,1)
            randomValue=.99
            House.rollLoot(data,Catalog,1)
            assert(repairCount(data)==0 and data.lootRolls['repair-parts:1:1:1'])
            data=roundtrip(data)
            randomValue=0
            House.rollLoot(data,Catalog,1)
            assert(repairCount(data)==0,'opening/loading cannot reroll a missed cache')
        ''')

    def test_full_house_storage_allocates_space_in_the_correct_house(self) -> None:
        self.lua.execute(r'''
            local full={name='supply-crate',scene='house',location=3,houseDoor=2,storage={}}
            for i=1,Catalog.storageCapacities[full.name] do full.storage[i]='food-ration' end
            local other={name='supply-crate',scene='house',location=3,houseDoor=1,storage={}}
            local data=prepared({activeHouseDoor=2,droppedItems={full,other}})
            local part=Catalog.weaponRepairParts['hunting-bow']
            House.storeLoot(data,Catalog,part,3)
            assert(#data.droppedItems==3)
            local extra=data.droppedItems[3]
            assert(extra.houseDoor==2 and extra.location==3 and extra.storage[1]==part)
            assert(next(other.storage)==nil,'a different house does not receive this loot')
            for i=1,Catalog.storageCapacities[full.name] do assert(full.storage[i]=='food-ration') end
        ''')

    def test_full_backpack_rejects_every_part_without_removing_chest_item(self) -> None:
        self.lua.execute(r'''
            for part in pairs(Catalog.repairParts) do
                local data=prepared({inventoryCapacity=6,inventory={
                    'food-ration','food-ration','food-ration','food-ration','food-ration','food-ration'}})
                local chest={name='supply-crate',storage={[4]=part}}
                assert(not transfer(data,chest,{kind='chest',index=4}))
                assert(chest.storage[4]==part and data.inventory[6]=='food-ration')
                assert(not Inventory.move(data,chest,{kind='chest',index=4},{kind='equipment',index=1},
                    Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
                assert(chest.storage[4]==part and data.equipment[1]==nil,'components cannot be equipped')
                data.inventory[3]=nil
                assert(transfer(data,chest,{kind='chest',index=4}))
                assert(data.inventory[3]==part and chest.storage[4]==nil)
                assert(transfer(data,chest,{kind='inventory',index=3}))
                assert(data.inventory[3]==nil and chest.storage[1]==part)
            end
        ''')

    def test_part_in_storage_is_preserved_until_taken_and_only_one_matching_part_is_used(self) -> None:
        self.lua.execute(r'''
            for weapon,part in pairs(Catalog.weaponRepairParts) do
                local wrong=Catalog.weaponRepairParts[weapon=='hunting-bow' and 'scrap-hatchet' or 'hunting-bow']
                local chest={name='supply-crate',scene='train',carIndex=1,storage={[2]=part}}
                local data=prepared({equipment={weapon},inventory={[1]=wrong},
                    weaponDurability={[weapon]=0},droppedItems={chest}})
                chest=data.droppedItems[1]
                local failure=Loot.completeRepair(data,Catalog,weapon,'perfect')
                assert(not failure.ok and failure.reason=='part')
                assert(data.scrap==1000 and data.weaponDurability[weapon]==0)
                assert(data.inventory[1]==wrong and chest.storage[2]==part)
                assert(transfer(data,chest,{kind='chest',index=2}))
                data.inventory[4]=part
                local success=Loot.completeRepair(data,Catalog,weapon,'perfect')
                assert(success.ok and data.weaponDurability[weapon]==100)
                assert(data.inventory[1]==wrong and data.inventory[2]==nil and data.inventory[4]==part)
                local saved=roundtrip(data)
                assert(saved.inventory[1]==wrong and saved.inventory[2]==nil and saved.inventory[4]==part)
                assert(saved.droppedItems[1].storage[2]==nil)
                assert(saved.scrap==1000-success.cost and saved.weaponDurability[weapon]==100)
            end
        ''')

    def test_legacy_alias_repairs_only_its_exact_weapon_after_load(self) -> None:
        self.lua.execute(r'''
            for alias,part in pairs(Catalog.repairPartAliases) do
                local weapon=Catalog.repairParts[part].weapon
                local other=weapon=='hunting-bow' and 'scrap-hatchet' or 'hunting-bow'
                local data=roundtrip(prepared({equipment={weapon,other},inventory={[3]=alias},
                    weaponDurability={[weapon]=0,[other]=0}}))
                local refused=Loot.completeRepair(data,Catalog,other,'perfect')
                assert(not refused.ok and refused.reason=='part')
                assert(data.inventory[3]==alias and data.scrap==1000)
                local repaired=Loot.completeRepair(data,Catalog,weapon,'perfect')
                assert(repaired.ok and data.inventory[3]==nil)
                assert(data.weaponDurability[other]==0 and data.weaponDurability[weapon]==100)
            end
        ''')

    def test_merchants_do_not_buy_components_or_generate_them_as_curios(self) -> None:
        self.lua.execute(r'''
            local names={}
            for name in pairs(Catalog.repairParts) do names[#names+1]=name end
            for alias in pairs(Catalog.repairPartAliases) do names[#names+1]=alias end
            local source={merchant='merchant.png',stock={},budget=1000}
            for _,name in ipairs(names) do
                local data=prepared({inventory={[1]=name}})
                assert(Merchant.sellPrice(data,Catalog,source,1)==nil)
                local sale=Merchant.sell(data,Catalog,source,1)
                assert(not sale.ok and sale.reason=='protected')
                assert(data.inventory[1]==name and data.scrap==1000 and source.budget==1000)
            end
            for _,roll in ipairs({0,.25,.5,.75,.99}) do
                local data=prepared()
                local options={rng=function() return roll end,lootProgression=Loot}
                local stops=Crow.scheduledStops(data,options)
                assert(#stops>0)
                for _,stop in ipairs(stops) do
                    local camp=assert(Crow.ensureCamp(data,Catalog,stop,options))
                    for _,merchant in ipairs(camp.merchants) do
                        for _,listing in ipairs(merchant.listings) do
                            assert(not Catalog.repairParts[listing.item],'parts remain chest salvage')
                        end
                    end
                end
            end
        ''')

    def test_repair_action_saves_success_only_and_reloads_consumption(self) -> None:
        self.lua.execute(r'''
            local weapon='hunting-bow'
            local part=Catalog.weaponRepairParts[weapon]
            local runtime={saveData=prepared({equipment={weapon},inventory={[2]=part},
                weaponDurability={[weapon]=0}})}
            local saveCalls=0
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,
                catalog=Catalog,util=require('game.util'),trainUpgradeBalance={},lootProgression=Loot,
                writeSave=function() saveCalls=saveCalls+1; assert(Save.write(1,runtime.saveData)) end,
                useBattleHealingItem=function() end,useBattlePotion=function() end})
            assert(not actions.repairWeapon(weapon,'miss').ok)
            assert(saveCalls==0 and runtime.saveData.inventory[2]==part and runtime.saveData.scrap==1000)
            local result=actions.repairWeapon(weapon,'perfect')
            assert(result.ok and saveCalls==1)
            local saved=assert(Save.read(1))
            assert(saved.inventory[2]==nil and saved.weaponDurability[weapon]==100 and saved.scrap==1000-result.cost)
            assert(not actions.repairWeapon(weapon,'perfect').ok and saveCalls==1,'repeat click cannot charge twice')
        ''')

    def test_drop_and_pickup_preserve_parts_and_do_not_bypass_backpack_capacity(self) -> None:
        self.lua.execute(r'''
            local names={}
            for name in pairs(Catalog.repairParts) do names[#names+1]=name end
            for alias in pairs(Catalog.repairPartAliases) do names[#names+1]=alias end
            for _,name in ipairs(names) do
                local runtime={saveData=prepared({inventory={[5]=name},activeHouseDoor=2}),
                    scene='house',player={x=320,y=410},draggedSlot={kind='inventory',index=5}}
                local saveCalls=0
                local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,
                    catalog=Catalog,util=require('game.util'),trainUpgradeBalance={},lootProgression=Loot,
                    writeSave=function() saveCalls=saveCalls+1 end,
                    useBattleHealingItem=function() end,useBattlePotion=function() end})
                assert(actions.dropFromContainer(runtime.draggedSlot))
                local drop=runtime.saveData.droppedItems[1]
                assert(drop.name==name and drop.scene=='house' and drop.houseDoor==2)
                assert(runtime.saveData.inventory[5]==nil and saveCalls==1)
                runtime.saveData=roundtrip(runtime.saveData)
                runtime.nearbyItem=1
                for index=1,6 do runtime.saveData.inventory[index]='food-ration' end
                actions.pickUpNearby()
                assert(runtime.saveData.droppedItems[1].name==name and runtime.nearbyItem==1 and saveCalls==1)
                runtime.saveData.inventory[4]=nil
                actions.pickUpNearby()
                assert(runtime.saveData.inventory[4]==name and #runtime.saveData.droppedItems==0)
                assert(runtime.nearbyItem==nil and saveCalls==2)
            end
        ''')

    def test_use_action_never_consumes_components(self) -> None:
        self.lua.execute(r'''
            for part in pairs(Catalog.repairParts) do
                local runtime={saveData=prepared({inventory={[2]=part}}),
                    draggedSlot={kind='inventory',index=2}}
                local saveCalls=0
                local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,
                    catalog=Catalog,util=require('game.util'),trainUpgradeBalance={},lootProgression=Loot,
                    writeSave=function() saveCalls=saveCalls+1 end,
                    useBattleHealingItem=function() end,useBattlePotion=function() end})
                assert(not actions.consumeSelected())
                assert(not actions.consumeBattleSelected())
                assert(runtime.saveData.inventory[2]==part and saveCalls==0)
            end
        ''')


if __name__ == '__main__':
    unittest.main()
