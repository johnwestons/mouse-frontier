"""Crafting supplies, merchant migration, and save retention through real Lua modules."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class OutfitContentBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            love={math={random=function(low,high)
                if high then return low end
                if low then return 1 end
                return .5
            end}}
            Catalog=require('game.catalog')
            Loot=require('game.loot_progression')
            House=require('game.house')
            Schema=require('game.save_schema')
            Crafting=require('game.outfit_crafting')
            Merchant=require('game.merchant_trade')
        ''')

    def test_material_tiers_and_crafted_only_outputs(self) -> None:
        self.lua.execute(r'''
            local valid,errors=Loot.validate(Catalog)
            assert(valid,table.concat(errors,'; '))
            for _,stop in ipairs({1,7,13}) do
                local layout={tradeStock={}}
                Loot.ensureCraftingStock(layout,Catalog,stop)
                local names={}
                for _,entry in pairs(layout.tradeStock) do names[entry.item]=true end
                assert(names['thread-spool'] and names['fabric-scraps'] and names['wool-batting'])
                assert((names['leather-pieces']==true)==(stop>=7))
                assert((names['metal-sheet']==true)==(stop>=13))
                for index=0,99 do
                    local material=Loot.rollCraftMaterial(Catalog,stop,function() return index/100 end)
                    assert(names[material],'house salvage respects merchant material tier')
                end
            end
            for _,pool in pairs(Catalog.lootPools) do
                for _,name in ipairs(pool) do assert(not Catalog.outfitUpgrades[name]) end
            end
            assert(Loot.itemPrice(Catalog,'cloth-repair-patch-fine')>Loot.itemPrice(Catalog,'cloth-repair-patch'))
            assert(Loot.itemPrice(Catalog,'cloth-repair-patch-masterwork')>Loot.itemPrice(Catalog,'cloth-repair-patch-fine'))
        ''')

    def test_old_merchant_receives_finite_supplies_without_reroll(self) -> None:
        self.lua.execute(r'''
            local layout={tradeStock={[1]='food-ration',[4]='trail-slingshot'},tradeBudget=30}
            Loot.ensureCraftingStock(layout,Catalog,1)
            assert(layout.tradeStock[1]=='food-ration' and layout.tradeStock[4]=='trail-slingshot')
            local threadIndex,count
            count=0
            for i,entry in pairs(layout.tradeStock) do
                count=count+1
                if type(entry)=='table' and entry.item=='thread-spool' then threadIndex=i end
            end
            local data={inventory={},inventoryCapacity=6,scrap=100,relationships={},goodwill=0}
            local source=Merchant.stopSource(layout,'merchant.png')
            assert(Merchant.buy(data,Catalog,source,threadIndex).ok)
            assert(data.inventory[1]=='thread-spool')
            assert(layout.tradeStock[threadIndex].quantity==2)
            Loot.ensureCraftingStock(layout,Catalog,1)
            local after=0
            for _ in pairs(layout.tradeStock) do after=after+1 end
            assert(after==count and layout.tradeStock[threadIndex].quantity==2,'no restock on reopening')
            assert(data.inventory[2]==nil,'one bundle occupies one slot')
        ''')

    def test_old_house_cache_added_once_preserving_existing_items(self) -> None:
        self.lua.execute(r'''
            local chest={name='supply-crate',scene='house',location=1,houseDoor=1,storage={[1]='food-ration'}}
            local data={activeHouseDoor=1,droppedItems={chest},lootRolls={
                ['1:1']=true,['household:2:1:1']=true,['repair-parts:1:1:1']=true}}
            House.rollLoot(data,Catalog,1)
            assert(chest.storage[1]=='food-ration')
            assert(chest.storage[2]=='thread-spool' and chest.storage[3]=='fabric-scraps')
            assert(data.lootRolls['outfit-materials:1:1:1'])
            local fourth=chest.storage[4]
            chest.storage[2]=nil
            House.rollLoot(data,Catalog,1)
            assert(chest.storage[2]==nil and chest.storage[4]==fourth,'reopening does not replenish the cache')
            assert(chest.storage[5]==nil and #data.droppedItems==1)
        ''')

    def test_save_migration_keeps_inventory_and_resumes_committed_work(self) -> None:
        self.lua.execute(r'''
            local old={version=36,character='scout-frog.png',inventoryCapacity=16,
                inventory={[1]='thread-spool',[6]='fabric-scraps',[16]='food-ration'},
                wearables={backpack='scavenger-frame-pack'},health=13,maxHealth=20,
                conversations={completed={approved_conversation=true}}}
            local data,report=Schema.migrate(old)
            assert(data and report.fromVersion==36 and data.version==Schema.CURRENT_VERSION)
            assert(data.health==13 and data.inventory[16]=='food-ration' and data.wearables.backpack=='scavenger-frame-pack')
            assert(data.conversations.completed.approved_conversation)
            assert(Crafting.start(data,'cloth-repair-patch').ok)
            assert(data.inventory[1]==nil and data.inventory[6]==nil)
            local stage=Crafting.stage(data)
            assert(Crafting.act(data,{kind='point',x=stage.currentPoint.x,y=stage.currentPoint.y}).correct)
            local restored=assert(Schema.migrate(data))
            local resumed=Crafting.stage(restored)
            assert(resumed.pointIndex==2 and restored.outfitCrafting.project.recipeId=='cloth-repair-patch')
            assert(restored.inventory[16]=='food-ration' and restored.inventory[1]==nil)
            assert(not Crafting.start(restored,'cloth-repair-patch').ok,'cannot commit a second project')
            assert(old.inventory[1]=='thread-spool' and old.outfitCrafting==nil,'migration leaves its input unchanged')
        ''')

    def test_all_material_and_upgrade_icons_draw(self) -> None:
        sprite_pixels = self.lua.table()
        for filename in ('supplies-tools-v1.png', 'upgrades-v1.png', 'bench-controls-v1.png'):
            path = ROOT / 'assets/sprites/outfit-crafting' / filename
            with Image.open(path) as source:
                sprite_pixels[path.relative_to(ROOT).as_posix()] = self.lua.table_from({
                    'width': source.width, 'height': source.height,
                    'rgba': source.convert('RGBA').tobytes(),
                })
        self.lua.globals().spritePixels = sprite_pixels
        self.lua.execute(r'''
            local draws={}
            local noop=function() end
            love.image={newImageData=function(path)
                local pixels=assert(spritePixels[path],'unregistered production outfit art: '..path)
                return {path=path,getDimensions=function() return pixels.width,pixels.height end,
                    getPixel=function(_,x,y)
                        local offset=(y*pixels.width+x)*4+4
                        return 1,1,1,pixels.rgba:byte(offset)/255
                    end,release=noop}
            end}
            love.graphics={push=noop,pop=noop,setColor=noop,
                newImage=function(pixels)
                    return {path=pixels.path,setFilter=noop,getDimensions=pixels.getDimensions}
                end,
                newQuad=function(x,y,w,h,sw,sh)
                    assert(x>=0 and y>=0 and w>0 and h>0 and x+w<=sw and y+h<=sh)
                    return {x=x,y=y,w=w,h=h}
                end,
                draw=function(image,quad,x,y,rotation,sx,sy)
                    assert(sx>0 and sy>0,'outfit icon must have a visible positive scale')
                    draws[#draws+1]={path=image.path,quad=quad}
                end}
            local Art=require('game.outfit_item_art')
            local function check(name,rect)
                local before=#draws
                assert(Art.has(name) and Art.draw(name,rect))
                assert(#draws>before,name..' did not render its production sprite')
                assert(draws[before+1].path:find('assets/sprites/outfit%-crafting/'))
            end
            for name in pairs(Catalog.craftMaterials) do
                check(name,{x=0,y=0,w=20,h=20})
            end
            for name in pairs(Catalog.outfitUpgrades) do
                check(name,{x=0,y=0,w=48,h=36})
            end
            assert(#draws>0 and not Art.has('food-ration'))
            assert(not Art.draw('food-ration',{x=0,y=0,w=32,h=32}))
        ''')

    def test_installed_upgrades_change_real_battle_stats_and_removal_restores_them(self) -> None:
        self.lua.execute(r'''
            local Battle=require('game.battle_controller')
            local Inventory=require('game.inventory')
            local data=assert(Schema.migrate({character='scout-frog.png',stats={level=1},
                inventory={[1]='mobility-gusset',[2]='segmented-metal-insert'},equipment={},
                maxHealth=20,health=20,trait={},wearables={}}))
            local c={saveData=data,Catalog=Catalog,PlayerProgression=require('game.player_progression'),
                CombatBalance=require('game.combat_balance'),Util=require('game.util'),
                BattleGrid=require('game.battle_grid'),BOARD_COLS=8,BOARD_ROWS=6,writeSave=function() end}
            local function player() return Battle.begin(c,{mobFiles={'mouse-bandit.png'}}).units[1] end
            local before=player()
            assert(before.armor==2 and before.move==2)
            assert(Inventory.move(data,nil,{kind='inventory',index=1},{kind='wearable',slot='clothing'},
                Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            assert(player().move==3,'mobility panel increases tactical movement')
            assert(Inventory.move(data,nil,{kind='inventory',index=2},{kind='wearable',slot='armor'},
                Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            local armored=player()
            assert(armored.armor==5 and armored.move==2,'metal protection and weight both affect battle')
            assert(Inventory.move(data,nil,{kind='wearable',slot='armor'},{kind='inventory',index=2},
                Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            assert(player().armor==2 and player().move==3)
            assert(data.character=='scout-frog.png' and data.inventory[2]=='segmented-metal-insert')
        ''')


if __name__ == '__main__':
    unittest.main()
