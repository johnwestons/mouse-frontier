"""Host fallback displays and selects the same companion pack it commands."""
import unittest
import test_coop_battles_behavior as ordinary


class BattleInventoryPresentationTests(unittest.TestCase):
    setUp = ordinary.TacticalCommandTests.setUp

    def test_fallback_pack_display_selector_and_consumption_address_companion(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2; service:disconnect('companion',1)
            host.inventory[1]='food-ration'; guest.inventory[1]='field-bandage-roll'
            local runtime={state='battle',saveData=data,battle=b,draggedSlot={kind='inventory',index=1}}
            local consumed
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=require('game.inventory'),
                catalog=Catalog,util=require('game.util'),trainUpgradeBalance={},lootProgression={},writeSave=function() end,
                commands={submit=function(name,a) return run('host',name,a) end},
                useBattleHealingItem=function(name) consumed=name; return true end,useBattlePotion=function() return false end})
            assert(actions.personalData().character==guest.character and actions.containerValue(runtime.draggedSlot)=='field-bandage-roll')
            assert(actions.consumeBattleSelected() and consumed=='field-bandage-roll' and host.inventory[1]=='food-ration')
            local displayed
            local ctx={runtime=runtime,data=actions.personalData,ui={},inventoryUI={draw=function(c) displayed=c.data end},
                inventory=require('game.inventory'),catalog=Catalog,colors={},mobileEnabled=function() return false end}
            for _,name in ipairs({'pointIn','title','isWeapon','drawMenuFrame','button','pointer','value','move',
                'quickTransfer','collectAmmo','drop','consume','consumeBattle'}) do ctx[name]=function() end end
            local presenter=require('game.inventory_presenter').new(ctx); presenter.drawInventory()
            assert(displayed.character==guest.character and displayed.inventory[1]=='field-bandage-roll' and displayed.ammo['22lr']==9)
            b.active=1; presenter.drawInventory(); assert(displayed.character==host.character and displayed.inventory[1]=='food-ration')
            runtime.state='game'; assert(actions.personalData()==data)
        ''')
