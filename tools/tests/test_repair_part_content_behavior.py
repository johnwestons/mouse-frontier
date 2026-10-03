"""Repair component identity, artwork, and inventory lifecycle regression checks.

Save checks use an in-memory Love filesystem and never touch player saves.
"""
from __future__ import annotations

import ast
import hashlib
import inspect
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None
from PIL import Image
from tools import build_mobile_package as mobile_package


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class RepairPartContentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            files={}
            love={math={random=function(low,high) return low or .5 end},filesystem={
                getInfo=function(path) return files[path] and {type='file'} end,
                createDirectory=function() return true end,
                write=function(path,contents) files[path]=contents; return true end,
                read=function(path) return files[path] end,
                load=function(path) return loadstring(files[path] or '',path) end,
                remove=function(path) files[path]=nil; return true end,
            }}
            Catalog=require('game.catalog')
            Loot=require('game.loot_progression')
            Inventory=require('game.inventory')
            Merchant=require('game.merchant_trade')
            Schema=require('game.save_schema')
            Save=require('game.save')
            partNames={}
            for name in pairs(Catalog.repairParts) do partNames[#partNames+1]=name end
            for name in pairs(Catalog.repairPartAliases) do partNames[#partNames+1]=name end
            table.sort(partNames)
            function prepared(name)
                return assert(Schema.migrate({character='scout-frog.png',inventory={[1]=name},
                    inventoryCapacity=6,equipment={},weaponDurability={},scrap=10000}))
            end
        ''')

    def test_exactly_one_part_for_each_player_weapon_and_sixteen_aliases(self) -> None:
        self.lua.execute(r'''
            local count,aliases,weapons,seen,labels=0,0,0,{},{}
            for weapon in pairs(Catalog.weaponStats) do
                if weapon~='scratch' and weapon~='mob-claw' and weapon~='mob-spit' then
                    weapons=weapons+1
                    local id=assert(Catalog.weaponRepairParts[weapon])
                    local part=assert(rawget(Catalog.repairParts,id))
                    assert(not seen[id] and part.weapon==weapon)
                    local label=Catalog.weaponStats[weapon].name
                    assert(not labels[label],'ambiguous repair compatibility label: '..label)
                    labels[label]=weapon
                    assert(part.name:find(Catalog.weaponStats[weapon].name,1,true))
                    assert(part.description:find(Catalog.weaponStats[weapon].name,1,true))
                    assert(part.description:find('Fits this weapon only.',1,true))
                    assert(Catalog.miscItems[id].repairPart and Catalog.itemRarity[id]==part.rarity)
                    assert(not Catalog.itemEffects[id] and not Catalog.ammoPickupAmounts[id])
                    assert(not Catalog.weaponStats[id] and not Catalog.wearableItems[id])
                    seen[id]=true
                end
            end
            for id in pairs(Catalog.repairParts) do count=count+1; assert(seen[id]) end
            for alias,id in pairs(Catalog.repairPartAliases) do
                aliases=aliases+1
                assert(not rawget(Catalog.repairParts,alias) and rawget(Catalog.repairParts,id))
                assert(Catalog.repairParts[alias]==Catalog.repairParts[id])
                assert(Catalog.miscItems[alias]==Catalog.miscItems[id])
                assert(Catalog.itemRarity[alias]==Catalog.itemRarity[id])
            end
            assert(count==83 and weapons==83 and aliases==16)
            local ok,errors=Loot.validate(Catalog); assert(ok,table.concat(errors,'; '))
        ''')

    def test_artwork_and_specs_have_matching_unique_identities(self) -> None:
        parts = self.lua.globals().Catalog.repairParts
        specs = []
        for filename in ("hand-weapon-part-specs.json", "firearm-part-specs.json"):
            specs.extend(json.loads((ROOT / "docs/concepts/weapon-repair" / filename).read_text(encoding="utf-8-sig")))
        by_id = {spec["partId"]: spec for spec in specs}
        self.assertEqual(len(specs), 83)
        self.assertEqual(len(by_id), 83)
        self.assertEqual(set(by_id), set(parts))
        paths, hashes, pixels = set(), set(), set()
        for part_id, part in parts.items():
            with self.subTest(part=part_id):
                self.assertEqual(part["weapon"], by_id[part_id]["weapon"])
                self.assertEqual(part["component"], by_id[part_id]["component"])
                path = ROOT / part["sprite"]
                self.assertTrue(path.is_file())
                self.assertNotIn(path, paths)
                paths.add(path)
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                self.assertNotIn(digest, hashes)
                hashes.add(digest)
                with Image.open(path) as image:
                    self.assertEqual(image.mode, "RGBA")
                    self.assertLessEqual(max(image.size), 512)
                    self.assertGreaterEqual(min(image.size), 64)
                    alpha = image.getchannel("A")
                    # Some approved ImageGen sources use 254 for solid pixels.
                    self.assertEqual(alpha.getextrema()[0], 0)
                    self.assertGreaterEqual(alpha.getextrema()[1], 250)
                    bounds = alpha.getbbox()
                    self.assertIsNotNone(bounds)
                    self.assertGreater(bounds[2]-bounds[0], 20)
                    self.assertGreater(bounds[3]-bounds[1], 20)
                    self.assertEqual(alpha.getpixel((0,0)), 0)
                    self.assertEqual(alpha.getpixel((image.width-1,image.height-1)), 0)
                    pixel_hash = hashlib.sha256(image.tobytes()).hexdigest()
                    self.assertNotIn(pixel_hash, pixels)
                    pixels.add(pixel_hash)

    def test_all_parts_and_aliases_move_without_equipping_or_consuming(self) -> None:
        self.lua.execute(r'''
            for _,name in ipairs(partNames) do
                local data=prepared(name)
                local chest={name='supply-crate',storage={}}
                local args={Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems}
                assert(not Inventory.move(data,chest,{kind='inventory',index=1},{kind='equipment',index=1},unpack(args)))
                assert(not Inventory.move(data,chest,{kind='inventory',index=1},{kind='wearable',slot='armor'},unpack(args)))
                assert(data.inventory[1]==name and not data.equipment[1])
                assert(Inventory.move(data,chest,{kind='inventory',index=1},{kind='chest',index=3},unpack(args)))
                assert(not data.inventory[1] and chest.storage[3]==name)
                assert(Inventory.quickTransfer(data,chest,{kind='chest',index=3},Catalog.weaponStats,
                    Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems))
                assert(data.inventory[1]==name and not chest.storage[3])
                assert(Inventory.quickTransfer(data,chest,{kind='inventory',index=1},Catalog.weaponStats,
                    Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems))
                assert(not data.inventory[1] and chest.storage[1]==name)
                for i=1,data.inventoryCapacity do data.inventory[i]='food-ration' end
                assert(not Inventory.quickTransfer(data,chest,{kind='chest',index=1},Catalog.weaponStats,
                    Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems))
                assert(chest.storage[1]==name,'full backpack must preserve the part')
            end
        ''')

    def test_mobile_package_includes_all_part_sprites_and_definition_modules(self) -> None:
        parts = self.lua.globals().Catalog.repairParts
        config = json.loads(mobile_package.CONFIG_PATH.read_text(encoding="utf-8"))
        self.assertEqual(mobile_package.ROOT, ROOT)
        included = set()
        for part_id, part in parts.items():
            with self.subTest(part=part_id):
                relative = part["sprite"]
                source = ROOT / relative
                self.assertTrue(mobile_package.runtime_asset(source))
                self.assertEqual(source.suffix.lower(), ".png")
                included.add(relative)
                with Image.open(source) as image:
                    bounds = mobile_package.image_bounds(relative, config, image.size)
                    # The authored parts already fit the mobile art budget.
                    # Keep their current resolution, including thin strings and barrels.
                    self.assertGreaterEqual(bounds[0], image.width)
                    self.assertGreaterEqual(bounds[1], image.height)
        self.assertEqual(len(included), 83)

        # Evaluate only the actual builder's read-only Lua input list. Do not call
        # build(), create a package, or write into the production staging/cache area.
        build_ast = ast.parse(inspect.getsource(mobile_package.build))
        lua_copy_loop = next(node for node in ast.walk(build_ast)
            if isinstance(node, ast.For) and isinstance(node.iter, ast.List)
            and any(isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                and call.func.attr == "copy2" for call in ast.walk(node)))
        expression = ast.Expression(body=lua_copy_loop.iter)
        copied_sources = eval(compile(expression, "<mobile-lua-inputs>", "eval"),
            {"__builtins__": {}, "ROOT": mobile_package.ROOT})
        copied_paths = {path.relative_to(ROOT).as_posix() for path in copied_sources}
        self.assertIn("game/weapon_repair_parts.lua", copied_paths)
        self.assertIn("game/catalog.lua", copied_paths)
        self.assertIn("game/inventory_ui.lua", copied_paths)
        self.assertIn("game/loot_progression.lua", copied_paths)

    def test_mobile_part_optimization_preserves_resolution_and_transparency(self) -> None:
        config = json.loads(mobile_package.CONFIG_PATH.read_text(encoding="utf-8"))
        parts = self.lua.globals().Catalog.repairParts
        # Exercise the real image path with both output and cache isolated to a
        # temporary test directory; no .love archive or device install is created.
        with tempfile.TemporaryDirectory(prefix="mouse-frontier-repair-art-") as temporary:
            directory = Path(temporary)
            with patch.object(mobile_package, "CACHE_ROOT", directory / "cache"):
                for part_id, part in parts.items():
                    with self.subTest(part=part_id):
                        source = ROOT / part["sprite"]
                        destination = directory / "sprites" / (part_id + ".png")
                        mobile_package.optimize_image(source, destination, part["sprite"], config)
                        with Image.open(source) as original, Image.open(destination) as optimized:
                            self.assertEqual(optimized.size, original.size)
                            source_alpha = original.convert("RGBA").getchannel("A")
                            alpha = optimized.convert("RGBA").getchannel("A")
                            self.assertEqual(alpha.getextrema()[0], 0)
                            self.assertGreaterEqual(alpha.getextrema()[1], 240)
                            self.assertEqual(alpha.getpixel((0, 0)), 0)
                            self.assertEqual(alpha.getpixel((alpha.width-1, alpha.height-1)), 0)
                            solid_before = sum(source_alpha.histogram()[128:])
                            solid_after = sum(alpha.histogram()[128:])
                            self.assertGreaterEqual(solid_after, solid_before * .95)
                            self.assertLessEqual(solid_after, solid_before * 1.05)

    def test_drop_pickup_all_parts_in_every_world_scene(self) -> None:
        self.lua.execute(r'''
            local Actions=require('game.inventory_actions')
            for _,name in ipairs(partNames) do
                for _,scene in ipairs({'train','stop','house','expedition','caravan'}) do
                    local data=prepared(name)
                    data.location=7; data.activeCar=2; data.activeHouseDoor=3
                    data.activeExpeditionArea='test-area'; data.crowCaravans.activeCampId='test-camp'
                    local runtime={saveData=data,player={x=100,y=200},scene=scene,
                        draggedSlot={kind='inventory',index=1}}
                    local saves=0
                    local actions=Actions.new({runtime=runtime,inventory=Inventory,catalog=Catalog,
                        util=require('game.util'),trainUpgradeBalance=require('game.train_upgrade_balance'),
                        lootProgression=Loot,writeSave=function() saves=saves+1 end,
                        useBattleHealingItem=function() return false end,useBattlePotion=function() return false end})
                    assert(not actions.consumeSelected() and data.inventory[1]==name)
                    assert(actions.dropFromContainer({kind='inventory',index=1}))
                    local dropped=assert(data.droppedItems[1])
                    assert(dropped.name==name and dropped.scene==scene and not data.inventory[1])
                    if scene=='train' then assert(dropped.carIndex==2) else assert(dropped.location==7) end
                    if scene=='house' then assert(dropped.houseDoor==3) end
                    if scene=='expedition' then assert(dropped.expeditionAreaId=='test-area') end
                    if scene=='caravan' then assert(dropped.caravanCampId=='test-camp') end
                    runtime.nearbyItem=1
                    for i=1,data.inventoryCapacity do data.inventory[i]='food-ration' end
                    actions.pickUpNearby()
                    assert(data.droppedItems[1]==dropped and runtime.nearbyItem==1 and saves==1)
                    data.inventory[2]=nil
                    actions.pickUpNearby()
                    assert(data.inventory[2]==name and #data.droppedItems==0 and not runtime.nearbyItem and saves==2)
                end
            end
        ''')

    def test_all_parts_and_aliases_survive_save_roundtrip_in_all_containers(self) -> None:
        self.lua.execute(r'''
            for _,name in ipairs(partNames) do
                local data=prepared(name)
                data.inventory[6]=name
                data.droppedItems={{name=name,scene='train',carIndex=1,x=1,y=1},
                    {name='supply-crate',scene='house',location=1,houseDoor=1,storage={[1]=name,[10]=name}},
                    {name='mailbox-reward',scene='train',carIndex=1,mailbox=true,storage={[20]=name}}}
                assert(Save.write(1,data))
                local restored=assert(Save.read(1))
                assert(restored.inventory[1]==name and restored.inventory[6]==name)
                assert(restored.droppedItems[1].name==name)
                assert(restored.droppedItems[2].storage[1]==name and restored.droppedItems[2].storage[10]==name)
                assert(restored.droppedItems[3].storage[20]==name)
            end
        ''')

    def test_parts_and_aliases_cannot_be_sold_or_enter_ordinary_loot(self) -> None:
        self.lua.execute(r'''
            for _,name in ipairs(partNames) do
                local data=prepared(name)
                local source={stock={},budget=10000,merchant='merchant.png'}
                assert(Merchant.sellPrice(data,Catalog,source,1)==nil)
                local result=Merchant.sell(data,Catalog,source,1)
                assert(not result.ok and result.reason=='protected')
                assert(data.inventory[1]==name and data.scrap==10000 and source.budget==10000)
                for _,pool in pairs(Catalog.lootPools) do
                    for _,item in ipairs(pool) do assert(item~=name) end
                end
            end
        ''')

    def test_alias_icons_and_fit_labels_use_canonical_weapon(self) -> None:
        self.lua.execute(r'''
            local texts,drawn={},{}
            local noop=function() end
            package.loaded['game.typography']={drawText=function(_,value) texts[#texts+1]=value end}
            package.loaded['game.ui_layout']={iconVariant=function() return 'atlas' end,iconScale=function() return 1 end}
            package.loaded['game.inventory_ui']=nil
            local UI=require('game.inventory_ui')
            love.graphics={setColor=noop,rectangle=noop,draw=function(img) drawn[#drawn+1]=img end}
            local images={}
            for id in pairs(Catalog.repairParts) do
                images[id]={id=id,getWidth=function() return 512 end,getHeight=function() return 512 end}
            end
            for _,name in ipairs(partNames) do
                texts={}; drawn={}
                local data=prepared(name)
                local ctx={Catalog=Catalog,Inventory=Inventory,data=data,ui={propImages=images,atlasItems={}},
                    colors={cream={1,1,1},brass={1,1,0}},title=function(s) return s end,
                    draggedSlot={kind='inventory',index=1},pointer=function() return -1,-1 end,
                    pointIn=function() return false end,value=function() return name end,
                    isWeapon=function() return false end,drawMenuFrame=noop,
                    button=function() return {} end}
                UI.draw(ctx)
                local canonical=Catalog.repairPartAliases[name] or name
                assert(drawn[1]==images[canonical],'aliases must draw their dedicated canonical sprite')
                local part=Catalog.repairParts[name]
                local foundName,foundFit=false,false
                for _,value in ipairs(texts) do
                    if value==part.name then foundName=true end
                    if value=='FITS: '..Catalog.weaponStats[part.weapon].name then foundFit=true end
                end
                assert(foundName and foundFit,'inspection must identify the exact compatible weapon')
                assert(not ctx.ui.consume.enabled,'parts cannot be consumed from the ordinary inventory')
            end
        ''')


if __name__ == '__main__':
    unittest.main()
