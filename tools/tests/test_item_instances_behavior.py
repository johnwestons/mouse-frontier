"""Persistent ownership and conservation using real Lua inventory/commands."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class ItemInstancesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures')
            Schema=require('game.save_schema')
            Players=require('game.coop_players')
            Entities=require('game.coop_entities')
            Items=require('game.item_instances')
            Inventory=require('game.inventory')
            Catalog=require('game.catalog')
            data=Fixtures.campaign(nil,{inventory={[1]='orange-rose-vase',[2]='frontier-short-sword',[4]='cowboy-hat'}})
            assert(Fixtures.enroll(data))
            data.scene='train'
            chest={name='mailbox-reward',scene='train',carIndex=1,x=200,y=250,storage={}}
            data.droppedItems={chest}
            assert(Entities.ensure(data)); assert(Items.ensure(data)); assert(Schema.validate(data))
            host=Players.forActor(data,'host'); friend=Players.forActor(data,'companion')
            function ref(kind,index) return {kind=kind,index=index} end
            function move(actor,box,source,target)
                return Inventory.move(actor,box,source,target,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems)
            end
        ''')

    def test_legacy_migration_distinguishes_duplicates_and_only_inherits_condition_once(self):
        self.lua.execute('''
            local first=Items.get(host,nil,ref('equipment',1))
            local second=Items.get(host,nil,ref('inventory',2))
            local guest=Items.get(friend,nil,ref('equipment',1))
            assert(first.id~=second.id and second.id~=guest.id and first.id~=guest.id)
            assert(first.durability==67 and second.durability==67 and guest.durability==100)
            local nextId=data.itemIdentity.nextId
            assert(Items.ensure(data)); assert(data.itemIdentity.nextId==nextId)
            Inventory.setValue(host,nil,ref('inventory',2),nil)
            Inventory.setValue(host,nil,ref('inventory',2),'frontier-short-sword')
            local fresh=Items.get(host,nil,ref('inventory',2))
            assert(fresh.id~=second.id and fresh.durability==100 and first.durability==67)
            assert(Items.validate(data))
        ''')

    def test_chest_transfer_changes_owner_without_repairing_or_cloning(self):
        self.lua.execute('''
            local original=Items.get(host,nil,ref('equipment',1)); original.durability=13
            assert(move(host,chest,ref('equipment',1),ref('chest',3)))
            assert(move(friend,chest,ref('chest',3),ref('inventory',5)))
            assert(Items.get(friend,nil,ref('inventory',5))==original)
            assert(Items.get(host,nil,ref('equipment',1))==nil and chest.storage[3]==nil)
            assert(original.durability==13 and host.weaponProficiency.firearms==3)
            assert(Items.validate(data)); assert(Schema.validate(data))
            local saved=assert(Schema.migrate(assert(Schema.copy(data))))
            local reloaded=Items.get(saved.players.companion,nil,ref('inventory',5))
            assert(reloaded.id==original.id and reloaded.durability==13)
            assert(Items.validate(saved))
        ''')

    def test_swapping_same_named_weapons_preserves_distinct_condition(self):
        self.lua.execute('''
            local first=Items.get(host,nil,ref('equipment',1))
            local second=Items.get(host,nil,ref('inventory',2)); second.durability=4
            assert(move(host,nil,ref('equipment',1),ref('inventory',2)))
            assert(Items.get(host,nil,ref('equipment',1))==second)
            assert(Items.condition(host,second.name,ref('equipment',1))==4)
            assert(Items.get(host,nil,ref('inventory',2))==first and first.durability==67)
            assert(Items.setCondition(host,second.id,3)); assert(first.durability==67)
            assert(Items.validate(data))
        ''')

    def test_rejected_transfer_has_no_item_or_counter_side_effects(self):
        self.lua.execute('''
            chest.mailbox=true
            local original=Items.get(host,nil,ref('equipment',1))
            local nextId=data.itemIdentity.nextId
            assert(not move(host,chest,ref('equipment',1),ref('chest',1)))
            assert(Items.get(host,nil,ref('equipment',1))==original and chest.storage[1]==nil)
            assert(data.itemIdentity.nextId==nextId and Items.validate(data))
        ''')

    def test_corruption_and_sequence_exhaustion_fail_without_mutating(self):
        self.lua.execute('''
            local original=Items.get(host,nil,ref('equipment',1))
            local old=Items.get(friend,nil,ref('equipment',1))
            friend.itemSlots.equipment[1]=original
            assert(not Items.validate(data)); assert(not Schema.validate(data))
            assert(Items.ensure(data)==nil)
            friend.itemSlots.equipment[1]=old
            local nextId=data.itemIdentity.nextId
            original.durability=0/0; assert(not Items.validate(data)); original.durability=67
            original.name='trail-slingshot'; assert(Items.ensure(data)==nil); original.name='frontier-short-sword'
            assert(data.itemIdentity.nextId==nextId)
            data.itemIdentity.nextId=2147483647
            data.inventory[3]='trail-slingshot'
            assert(Items.ensure(data)==nil and data.itemIdentity.nextId==2147483647)
            assert(Items.get(host,nil,ref('inventory',3))==nil)
        ''')

    def test_network_drop_pickup_replay_conserves_one_instance(self):
        self.lua.execute('''
            local authority=require('game.coop_authority').new({campaign=data,sessionId='items'})
            require('game.coop_inventory').install(authority,{catalog=Catalog,
                actorState=function() return {screen='game',scene='train',x=200,y=250} end})
            authority:admit('companion',1)
            local original=Items.get(host,nil,ref('equipment',1)); local id=original.id
            local drop=authority:submitLocal('loot.drop',{source=ref('equipment',1)})
            assert(drop.ok)
            local object=Entities.find(data,drop.result.entityId)
            assert(object.itemInstance.id==id and object.itemInstance.durability==67)
            local request=assert(authority:prepareRequest('companion','loot.pickup',{entityId=object.entityId}))
            local result=authority:execute('companion',1,request); assert(result.ok)
            assert(authority:execute('companion',1,request).ok)
            local owned=Items.get(friend,nil,ref('inventory',1))
            assert(owned.id==id and owned.durability==67 and host.equipment[1]==nil)
            assert(Entities.find(data,object.entityId)==nil and Items.validate(data))
        ''')

    def test_merged_caravan_resales_and_repurchases_keep_each_instance(self):
        self.lua.execute('''
            local Caravans=require('game.crow_caravans'); local Trade=require('game.merchant_trade')
            data.crowCaravans={}; data.scrap=1000
            local root=assert(Caravans.ensureSchedule(data,{rng=function() return .5 end}))
            data.location=root.scheduledStops[1]
            local camp=assert(Caravans.ensureCamp(data,Catalog,data.location,{rng=function() return .5 end}))
            camp.resaleBudgetBase=1000
            assert(Entities.ensure(data)); assert(Items.ensure(data))
            local first=Items.get(host,nil,ref('inventory',2)); first.durability=7
            local second=Items.get(host,nil,ref('equipment',1)); second.durability=43
            local source=Trade.caravanSource(data,Catalog,camp,'packmaster')
            assert(Trade.sell(host,Catalog,source,2).ok)
            assert(move(host,nil,ref('equipment',1),ref('inventory',2)))
            assert(Trade.sell(host,Catalog,source,2).ok)
            assert(Items.validate(data))
            -- Rendering/opening the shop repeatedly normalizes and merges
            -- resale entries; doing so must not discard their item records.
            source=Trade.caravanSource(data,Catalog,camp,'packmaster')
            source=Trade.caravanSource(data,Catalog,camp,'packmaster')
            local index,listing
            for i,entry in ipairs(source.stock) do if entry.item==first.name then index=i; listing=entry; break end end
            assert(listing and #listing.instances==2)
            assert(listing.instances[1].id==first.id and listing.instances[2].id==second.id)
            assert(Trade.buy(friend,Catalog,source,index).ok)
            assert(Trade.buy(friend,Catalog,source,index).ok)
            assert(Items.get(friend,nil,ref('inventory',1)).id==first.id)
            assert(Items.get(friend,nil,ref('inventory',1)).durability==7)
            assert(Items.get(friend,nil,ref('inventory',2)).id==second.id)
            assert(Items.get(friend,nil,ref('inventory',2)).durability==43)
            assert(#listing.instances==0 and Items.validate(data))
        ''')

    def test_missing_or_hidden_instance_cannot_silently_create_another_weapon(self):
        self.lua.execute('''
            data.itemSlots.inventory[2]=nil
            local nextId=data.itemIdentity.nextId
            local moved,reason=move(host,nil,ref('inventory',2),ref('equipment',1))
            assert(not moved and reason=='missing_item_identity' and data.itemIdentity.nextId==nextId)
            assert(Items.ensure(data))
            data.itemSlots.hidden={Items.get(host,nil,ref('equipment',1))}
            assert(not Items.validate(data)); assert(Items.ensure(data)==nil)
            data.itemSlots.hidden=nil
            data.itemSlots.inventory[2].durability=101
            assert(not Items.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
