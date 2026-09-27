"""Inventory touch behavior: result dismissal and quick transfers."""
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


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class InventoryInputBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            local now=0
            love={timer={getTime=function() return now end},keyboard={isDown=function() return false end}}
            local noop=function() end
            Inventory=require('game.inventory')
            InventoryUI=require('game.inventory_ui')
            Catalog=require('game.catalog')
            Util=require('game.util')
            Schema=require('game.save_schema')
            function setTime(value) now=value end
            function newInventoryContext(data,chest)
                local ctx
                ctx={data=data,activeChest=chest,chestOpen=chest~=nil,inventoryOpen=true,
                    draggedSlot=nil,inventoryDragActive=false,giftOpen=false,ui={},Inventory=Inventory,
                    Catalog=Catalog,colors={},mobileEnabled=false,pointIn=Util.pointIn,
                    title=Util.titleFromFile,isWeapon=function(name) return Inventory.isWeapon(name,Catalog.weaponStats) end,
                    value=function(ref) return Inventory.value(data,chest,ref) end,
                    set=function(key,value) ctx[key]=value end,
                    quickTransfer=function(ref) return Inventory.quickTransfer(data,chest,ref,Catalog.weaponStats,
                        Catalog.ammoPickupAmounts,Catalog.storageCapacities) end,
                    collectAmmo=function(ref) return Inventory.quickTransfer(data,chest,ref,Catalog.weaponStats,
                        Catalog.ammoPickupAmounts,Catalog.storageCapacities) end,
                    consume=function() ctx.consumeCount=(ctx.consumeCount or 0)+1 end,
                    move=function(source,target) return Inventory.move(data,chest,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts) end,
                    drop=noop,consumeCount=0}
                return ctx
            end
        ''')

    def test_double_tap_weapon_transfers_between_chest_and_backpack(self) -> None:
        self.lua.execute(r'''
            local data=assert(Schema.migrate({character='mouse-engineer.png'}))
            local chest={name='travel-chest',storage={[1]='frontier-short-sword'}}
            local ctx=newInventoryContext(data,chest)
            InventoryUI.handleClick(ctx,60,240)
            setTime(.2)
            InventoryUI.handleClick(ctx,60,240)
            assert(data.inventory[1]=='frontier-short-sword' and chest.storage[1]==nil,
                'double tapping chest weapons should fill the next backpack slot')
            assert(ctx.draggedSlot==nil and not ctx.inventoryDragActive)

            ctx=newInventoryContext(data,chest)
            InventoryUI.handleClick(ctx,590,240)
            setTime(.4)
            InventoryUI.handleClick(ctx,590,240)
            assert(data.inventory[1]==nil and chest.storage[1]=='frontier-short-sword',
                'double tapping backpack weapons should fill the next storage slot')
        ''')

    def test_double_tap_food_keeps_its_consume_behavior(self) -> None:
        self.lua.execute(r'''
            local data=assert(Schema.migrate({character='mouse-engineer.png'}))
            data.inventory[1]='food-ration'
            local chest={name='travel-chest',storage={}}
            local ctx=newInventoryContext(data,chest)
            InventoryUI.handleClick(ctx,590,240)
            setTime(.2)
            InventoryUI.handleClick(ctx,590,240)
            assert(ctx.consumeCount==1 and chest.storage[1]==nil,
                'food remains a consume action instead of a quick transfer')
        ''')

    def test_inventory_result_tap_dismisses_then_next_tap_reaches_inventory(self) -> None:
        self.lua.execute(r'''
            local noop=function() end
            local runtime={state='game',scene='caravan',inventoryOpen=true,
                dialogue={speaker='Food',text='Supplies restored.',timer=1.4,inventoryResult=true}}
            local operations,returns=0,0
            local ui={handleRadioMousePressed=function() return false end,returnStop={x=0,y=0,w=100,h=100}}
            local context={runtime=runtime,ui=ui,characters={},maintenanceSession={},scenery={},inventory={},
                catalog={},npcRelationships={},merchantTrade={},util=Util,engineUpgrades={},trainUpgradeBalance={},
                maintenance={},battleRules={},stops={},settlements={},interiorDoors={},firstAid={},shootingRange={},
                screenToGame=function(x,y) return x,y end,
                returnFromCaravan=function() returns=returns+1 end,
                handleInventoryClick=function() operations=operations+1 end}
            setmetatable(context,{__index=function() return noop end})
            local input=require('game.gameplay_input').new(context)
            input.mousepressed(20,20,1)
            assert(runtime.inventoryOpen and not runtime.dialogue and operations==0 and returns==0,
                'the first touch anywhere should only dismiss the item result')
            input.mousepressed(200,200,1)
            assert(runtime.inventoryOpen and operations==1,
                'the next touch should resume inventory input')
        ''')

    def test_raw_mobile_touch_dismisses_before_controls_capture_it(self) -> None:
        self.lua.execute(r'''
            local runtime={state='game',scene='train',inventoryOpen=true,
                dialogue={speaker='Food',text='Supplies restored.',timer=1.4,inventoryResult=true}}
            local controlTouches=0
            local controls={touchpressed=function() controlTouches=controlTouches+1; return true end}
            local MobileRuntime=require('game.mobile_runtime').new({runtime=runtime,ui={},maintenanceSession={},
                mobileControls={new=function() return controls end},width=960,height=720,
                viewportToGame=function(x,y) return x,y end,getCameraZoom=function() return 1 end,
                setCameraZoom=function() end,beginCameraPan=function() end,moveCameraPan=function() end,
                endCameraPan=function() end,getGameplayInput=function() return {} end})
            MobileRuntime.initialize()
            MobileRuntime.touchpressed('back-control',960,24)
            assert(not runtime.dialogue and controlTouches==0,
                'mobile controls must not consume the tap that dismisses the item result')
            MobileRuntime.touchpressed('back-control',960,24)
            assert(controlTouches==1,
                'the next tap should reach the mobile control as usual')
        ''')

    def test_consumption_marks_its_message_for_inventory_dismissal(self) -> None:
        self.lua.execute(r'''
            local data=assert(Schema.migrate({character='mouse-engineer.png'}))
            data.inventory[1]='food-ration'
            local runtime={saveData=data,draggedSlot={kind='inventory',index=1}}
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,
                catalog=Catalog,util=Util,trainUpgradeBalance=require('game.train_upgrade_balance'),
                lootProgression=require('game.loot_progression'),writeSave=function() end,
                useBattleHealingItem=function() return false end,useBattlePotion=function() return false end})
            assert(actions.consumeSelected())
            assert(runtime.dialogue and runtime.dialogue.inventoryResult,
                'consume feedback should be tagged for touch-to-dismiss while the inventory is open')
        ''')


if __name__ == "__main__":
    unittest.main()
