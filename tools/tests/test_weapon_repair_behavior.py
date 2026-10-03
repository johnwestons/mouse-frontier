"""Exercise exact-fit repair transactions and salvage using the real Lua catalog."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class WeaponRepairBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            Catalog=require('game.catalog')
            Repair=require('game.loot_progression')
            weapon='frontier-22-lever-rifle'
            part=Repair.repairPartFor(Catalog,weapon)
            function sample(condition)
                return {equipment={[1]=weapon},inventory={},inventoryCapacity=6,
                    scrap=200,weaponDurability={[weapon]=condition}}
            end
        ''')

    def test_catalog_exact_fit_audit(self):
        self.lua.execute(r'''
            local valid,errors=Repair.validate(Catalog)
            assert(valid,table.concat(errors,'; '))
            assert(Repair.repairAudit(Catalog).ready)
            local count=0
            for id,definition in pairs(Catalog.repairParts) do
                count=count+1
                assert(Repair.repairPartFor(Catalog,definition.weapon)==id)
            end
            assert(count==83)
        ''')

    def test_sparse_equipment_ownership_and_targeted_salvage(self):
        self.lua.execute(r'''
            local data=sample(0);data.equipment={[2]=weapon}
            assert(#Repair.ownedWeapons(data,Catalog)==1,'slot 2 is owned with slot 1 empty')
            assert(Repair.repairStatus(data,Catalog,weapon).name==weapon)
            assert(Repair.repairStatus(data,Catalog).name==weapon)
            local found,kind=Repair.rollRepairPart(data,Catalog,1,function() return 0 end)
            assert(found==part and kind=='targeted')
            data.inventory[6]=part
            assert(Repair.completeRepair(data,Catalog,weapon,'perfect').ok)
            assert(data.weaponDurability[weapon]==100 and data.inventory[6]==nil)
        ''')

    def test_general_chests_can_drop_every_part_by_last_stop(self):
        self.lua.execute(r'''
            local seen={}
            for i=0,999 do
                local item,kind=Repair.rollRepairPart({inventory={}},Catalog,50,function() return i/1000 end)
                assert(item and kind=='general')
                seen[item]=true
            end
            for id in pairs(Catalog.repairParts) do assert(seen[id],'unreachable general chest part: '..id) end
        ''')

    def test_early_general_loot_excludes_rare_parts(self):
        self.lua.execute(r'''
            for i=0,199 do
                local item=Repair.rollRepairPart({inventory={}},Catalog,1,function() return i/200 end)
                assert(Catalog.repairParts[item].rarity=='common' or Catalog.repairParts[item].rarity=='uncommon')
            end
        ''')

    def test_all_condition_boundaries_for_all_weapons(self):
        self.lua.execute(r'''
            for _,id in ipairs(Catalog.weaponProgression) do
                local required=Repair.repairPartFor(Catalog,id)
                for _,condition in ipairs({0,1,24,25,26,49,50,74,75,94,95,96,99,100}) do
                    local data={equipment={[2]=id},inventory={[2]=required,[6]=required},
                        inventoryCapacity=6,scrap=200,weaponDurability={[id]=condition}}
                    local before=Repair.repairStatus(data,Catalog,id)
                    assert(before.major==(condition<=25))
                    local result=Repair.completeRepair(data,Catalog,id,'perfect')
                    if condition==100 then
                        assert(not result.ok and result.reason=='ready' and data.scrap==200)
                    else
                        assert(result.ok and data.weaponDurability[id]==100)
                        assert(data.scrap==200-before.cost)
                        assert(data.inventory[6]==required)
                        if condition<=25 then assert(data.inventory[2]==nil)
                        else assert(data.inventory[2]==required) end
                    end
                end
            end
        ''')

    def test_failed_attempts_never_spend(self):
        self.lua.execute(r'''
            for _,quality in ipairs({'miss','invalid','good','perfect'}) do
                local data=sample(0)
                local result=Repair.completeRepair(data,Catalog,weapon,quality)
                assert(not result.ok and data.scrap==200 and data.weaponDurability[weapon]==0)
            end
            local data=sample(0);data.inventory[4]=part;data.scrap=0
            assert(Repair.completeRepair(data,Catalog,weapon,'perfect').reason=='scrap')
            assert(data.scrap==0 and data.inventory[4]==part and data.weaponDurability[weapon]==0)
            data.scrap=200
            assert(Repair.completeRepair(data,Catalog,weapon,'miss').reason=='miss')
            assert(data.scrap==200 and data.inventory[4]==part and data.weaponDurability[weapon]==0)
        ''')

    def test_good_result_precision_and_repeat_protection(self):
        self.lua.execute(r'''
            for _,condition in ipairs({0,25,26,50,94,95,96,99}) do
                local data=sample(condition);data.inventory[1]=part
                local status=Repair.repairStatus(data,Catalog,weapon)
                local result=Repair.completeRepair(data,Catalog,weapon,'good')
                if condition<95 then
                    assert(result.ok and data.weaponDurability[weapon]>condition)
                    assert(data.weaponDurability[weapon]>=75 and data.weaponDurability[weapon]<=95)
                    assert(data.scrap==200-status.cost)
                else
                    assert(not result.ok and result.reason=='precision')
                    assert(data.scrap==200 and data.inventory[1]==part)
                end
                assert(Repair.completeRepair(data,Catalog,weapon,'perfect').ok)
                local scrap=data.scrap
                assert(Repair.completeRepair(data,Catalog,weapon,'perfect').reason=='ready')
                assert(data.scrap==scrap)
            end
        ''')

    def test_only_owned_player_weapons_are_repairable(self):
        self.lua.execute(r'''
            for _,id in ipairs({'scratch','mob-claw','mob-spit','food-ration','does-not-exist'}) do
                local data={equipment={[1]=id},inventory={[2]=id},inventoryCapacity=6,
                    scrap=200,weaponDurability={[id]=50}}
                assert(#Repair.ownedWeapons(data,Catalog)==0,'invalid workbench entry '..id)
                assert(not Repair.repairStatus(data,Catalog,id).needed,'invalid repair '..id)
                assert(not Repair.completeRepair(data,Catalog,id,'perfect').ok)
                assert(data.scrap==200 and data.weaponDurability[id]==50)
            end
            local data=sample(50);data.equipment={}
            assert(Repair.completeRepair(data,Catalog,weapon,'perfect').reason=='ownership')
        ''')

    def test_condition_label_matches_critical_repair_boundary(self):
        self.lua.execute(r'''
            assert(Repair.weaponCondition(0).label=='broken')
            assert(Repair.weaponCondition(25).label=='critical')
            assert(Repair.weaponCondition(26).label=='worn')
        ''')


if __name__ == '__main__':
    unittest.main()
