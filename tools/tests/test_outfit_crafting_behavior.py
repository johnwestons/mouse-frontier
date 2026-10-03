"""Real Lua checks for paid sewing projects, material operations, and save recovery."""
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
class OutfitCraftingBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            Crafting=require('game.outfit_crafting')
            Definitions=require('game.outfit_catalog')
            function prepared(recipeId)
                local data={inventory={},inventoryCapacity=6,character='mouse-engineer.png'}
                local index=1
                for _,material in ipairs(Definitions.recipesById[recipeId].materials) do
                    for _=1,material.count do data.inventory[index]=material.id; index=index+1 end
                end
                return data
            end
            function correctAction(data)
                local stage=assert(Crafting.stage(data))
                if stage.kind=='tension' then
                    return Crafting.act(data,{kind='tension',value=(stage.targetRange.min+stage.targetRange.max)/2})
                end
                local target=stage.currentPoint
                return Crafting.act(data,{kind='point',x=target.x,y=target.y})
            end
            function complete(data)
                local guard=0
                while not Crafting.project(data).complete do
                    guard=guard+1; assert(guard<1000,'project cannot get stuck')
                    assert(correctAction(data).correct)
                end
            end
            function count(data,id)
                local n=0
                for _,item in pairs(data.inventory) do if item==id then n=n+1 end end
                return n
            end
        ''')

    def test_all_patterns_produce_their_registered_stat_item(self) -> None:
        self.lua.execute(r'''
            assert(#Definitions.recipes==9)
            for _,recipe in ipairs(Definitions.recipes) do
                local bundles=0
                for _,cost in ipairs(recipe.materials) do
                    assert(Definitions.materials[cost.id])
                    bundles=bundles+cost.count
                end
                assert(bundles<=6,'patterns fit base carrying capacity')
                local data=prepared(recipe.id)
                assert(Crafting.start(data,recipe.id).ok)
                complete(data)
                local result=Crafting.finish(data)
                assert(result.ok and result.quality=='masterwork')
                assert(result.outputId==recipe.outputIds.masterwork)
                assert(Definitions.upgrades[result.outputId].slot==recipe.slot)
                assert(count(data,result.outputId)==1)
            end
        ''')

    def test_missing_materials_never_consume_partial_supplies(self) -> None:
        self.lua.execute(r'''
            local data={inventory={[1]='thread-spool',[4]='food-ration'},inventoryCapacity=6}
            local status=Crafting.status(data,'cloth-repair-patch')
            assert(not status.canStart and status.missingCount==1)
            assert(not Crafting.start(data,'cloth-repair-patch').ok)
            assert(data.inventory[1]=='thread-spool' and data.inventory[4]=='food-ration')
            assert(Crafting.project(data)==nil)
        ''')

    def test_sparse_inventory_exact_bundle_consumption_and_duplicate_start(self) -> None:
        self.lua.execute(r'''
            local data={inventory={[1]='fabric-scraps',[3]='food-ration',[4]='fabric-scraps',
                [6]='thread-spool',[8]='fabric-scraps'},inventoryCapacity=10}
            assert(Crafting.start(data,'padded-cloth-insert').ok)
            assert(data.inventory[1]==nil and data.inventory[4]==nil and data.inventory[6]==nil)
            assert(data.inventory[3]=='food-ration' and data.inventory[8]=='fabric-scraps')
            assert(not Crafting.start(data,'padded-cloth-insert').ok)
            assert(data.inventory[8]=='fabric-scraps','starting again cannot spend more supplies')
        ''')

    def test_wrong_tool_out_of_order_and_bad_tension_require_redo(self) -> None:
        self.lua.execute(r'''
            local data=prepared('cloth-repair-patch')
            assert(Crafting.start(data,'cloth-repair-patch').ok)
            assert(not Crafting.act(data,{kind='tension',value=.55}).ok)
            local first=Crafting.stage(data)
            local later=first.points[2]
            local wrong=Crafting.act(data,{kind='point',x=later.x,y=later.y})
            assert(wrong.changed and not wrong.correct)
            assert(Crafting.project(data).pointIndex==1 and Crafting.project(data).mistakes==1)
            while Crafting.stage(data).kind~='tension' do correctAction(data) end
            local stageIndex=Crafting.project(data).stageIndex
            assert(not Crafting.act(data,{kind='tension',value=0}).correct)
            assert(Crafting.project(data).stageIndex==stageIndex)
            assert(not Crafting.act(data,{kind='tension',value=1}).correct)
            assert(Crafting.project(data).stageIndex==stageIndex)
            assert(correctAction(data).stageComplete)
        ''')

    def test_material_preparation_precedes_leather_and_metal_sewing(self) -> None:
        self.lua.execute(r'''
            local leather=Definitions.recipesById['leather-padding-insert']
            local punched=false
            for _,stage in ipairs(leather.stages) do
                if stage.operation=='punch' then punched=true end
                if stage.operation=='stitch' then
                    assert(punched)
                    assert(#stage.points%2==0)
                    for i=1,#stage.points,2 do
                        local front,back=stage.points[i],stage.points[i+1]
                        assert(front.x==back.x and front.y==back.y)
                        assert(front.side=='front' and back.side=='back')
                    end
                end
            end
            local metal=Definitions.recipesById['segmented-metal-insert']
            local operations={}
            for _,stage in ipairs(metal.stages) do operations[#operations+1]=stage.operation end
            assert(table.concat(operations,',')=='mark,cut,deburr,punch,deburr,pin,stitch,bind,tension,secure')
            local punchedHoles=metal.stages[4].points
            local sewnHoles=metal.stages[7].points
            for i,hole in ipairs(punchedHoles) do
                assert(hole.x==sewnHoles[i*2-1].x and hole.y==sewnHoles[i*2-1].y)
            end
        ''')

    def test_incomplete_and_repeated_collection_cannot_duplicate_items(self) -> None:
        self.lua.execute(r'''
            local data=prepared('cloth-repair-patch')
            assert(Crafting.start(data,'cloth-repair-patch').ok)
            assert(not Crafting.finish(data).ok)
            complete(data)
            local result=Crafting.finish(data)
            assert(result.ok)
            assert(not Crafting.finish(data).ok)
            assert(count(data,result.outputId)==1)
        ''')

    def test_finished_project_waits_safely_when_backpack_is_full(self) -> None:
        self.lua.execute(r'''
            local data=prepared('segmented-metal-insert')
            assert(Crafting.start(data,'segmented-metal-insert').ok)
            complete(data)
            for index=1,6 do data.inventory[index]='food-ration' end
            local result=Crafting.finish(data)
            assert(not result.ok and result.inventoryFull)
            assert(Crafting.project(data).complete)
            assert(not Crafting.finish(data).ok)
            data.inventory[3]=nil
            result=Crafting.finish(data)
            assert(result.ok and result.slot==3)
            assert(data.inventory[3]==result.outputId and Crafting.project(data)==nil)
        ''')

    def test_workmanship_changes_grade_without_destroying_scarce_materials(self) -> None:
        self.lua.execute(r'''
            local recipe=Definitions.recipesById['cloth-repair-patch']
            for _,case in ipairs({{mistakes=0,grade='masterwork'},
                {mistakes=math.ceil(recipe.totalActions*.1),grade='fine'},
                {mistakes=recipe.totalActions,grade='usable'}}) do
                local data=prepared(recipe.id)
                assert(Crafting.start(data,recipe.id).ok)
                for _=1,case.mistakes do
                    assert(not Crafting.act(data,{kind='point',x=0,y=0}).correct)
                end
                complete(data)
                local result=Crafting.finish(data)
                assert(result.ok and result.quality==case.grade)
                assert(count(data,result.outputId)==1)
            end
            local usable=Definitions.upgrades[recipe.outputIds.usable]
            local fine=Definitions.upgrades[recipe.outputIds.fine]
            local master=Definitions.upgrades[recipe.outputIds.masterwork]
            assert(fine.basePrice>usable.basePrice)
            assert(master.bonuses.armor==usable.bonuses.armor+1)
            assert(Definitions.upgrades['mobility-gusset'].bonuses.move==1)
            assert(Definitions.upgrades['segmented-metal-insert'].bonuses.move==-1)
        ''')

    def test_pause_save_read_resume_preserves_paid_materials_and_progress(self) -> None:
        self.lua.execute(r'''
            local files={}
            love={filesystem={
                getInfo=function(path) return files[path] and {type='file'} end,
                createDirectory=function() return true end,
                write=function(path,contents) files[path]=contents; return true end,
                read=function(path) return files[path] end,
                load=function(path) return loadstring(files[path] or '',path) end,
                remove=function(path) files[path]=nil; return true end,
            }}
            local Save=require('game.save')
            local data=prepared('leather-padding-insert')
            assert(Crafting.start(data,'leather-padding-insert').ok)
            for _=1,8 do correctAction(data) end
            local stageIndex,pointIndex=Crafting.project(data).stageIndex,Crafting.project(data).pointIndex
            assert(Save.write(97,data))
            data=assert(Save.read(97))
            assert(Crafting.project(data).stageIndex==stageIndex and Crafting.project(data).pointIndex==pointIndex)
            assert(count(data,'waxed-thread')==0 and count(data,'leather-pieces')==0)
            complete(data)
            assert(Save.write(97,data))
            data=assert(Save.read(97))
            assert(Crafting.project(data).complete)
            local result=Crafting.finish(data)
            assert(result.ok)
            assert(Save.write(97,data))
            data=assert(Save.read(97))
            assert(not Crafting.finish(data).ok and count(data,result.outputId)==1)
        ''')

    def test_unknown_saved_project_is_retained_and_blocks_new_consumption(self) -> None:
        self.lua.execute(r'''
            local data=prepared('cloth-repair-patch')
            data.outfitCrafting={project={recipeId='future-pattern',stageIndex=2,pointIndex=3}}
            Crafting.ensure(data)
            assert(Crafting.project(data).recipeId=='future-pattern')
            assert(not Crafting.start(data,'cloth-repair-patch').ok)
            assert(count(data,'thread-spool')==1)
        ''')


if __name__ == '__main__':
    unittest.main()
