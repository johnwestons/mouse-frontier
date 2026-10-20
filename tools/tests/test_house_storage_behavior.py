"""Painted home storage: image coverage, migration, persistence and interaction."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class HouseStorageBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures')
            love={math={random=function(low,high) if high then return low elseif low then return 1 else return .99 end end},
                filesystem=F.filesystem()}
            Catalog=require('game.catalog'); House=require('game.house'); Storage=require('game.house_storage')
            Furniture=require('game.furniture_catalog'); Items=require('game.item_instances')
            Inventory=require('game.inventory'); Schema=require('game.save_schema'); Save=require('game.save')
            function campaign(stop,door,index)
                return F.campaign(stop,{scene='house',activeHouseDoor=door or 1,inventory={},equipment={},
                    droppedItems={},stopLayouts={[tostring(stop)]={interior=index or (5+(stop-1)*5+1)}}})
            end
            function ensure(data) House.ensure(data,Catalog,Furniture.isFurniture,function() return .99 end) end
            function roundtrip(data) assert(Save.write(99,data)); return assert(Save.read(99)) end
        ''')

    def test_every_furnished_image_has_an_individual_in_bounds_storage_anchor(self):
        storage = self.lua.globals().Storage
        filenames = set()
        for index in range(6, 256):
            spot = storage.definition(index)
            filenames.add(spot.filename)
            self.assertTrue((ROOT / "assets/sprites/interiors" / spot.filename).is_file())
            self.assertGreater(spot.u, 0)
            self.assertLess(spot.u, 1)
            self.assertGreater(spot.v, 0)
            self.assertLess(spot.v, 1)
            self.assertAlmostEqual(spot.x, 105 + spot.u * 750)
            self.assertAlmostEqual(spot.y, 205 + spot.v * 445)
        self.assertEqual(filenames, {p.name for p in (ROOT / "assets/sprites/interiors").glob("stop*-interior-*.png")})
        self.assertEqual(len(filenames), 250)

    def test_all_interiors_spawn_one_fixed_fixture_and_zero_lootable_furniture(self):
        self.lua.execute(r'''
            for index=6,255 do
                local stop=math.floor((index-6)/5)+1
                local data=campaign(stop,1,index)
                ensure(data)
                assert(#data.droppedItems==1,'home produced decorative furniture')
                local fixture=data.droppedItems[1]; local spot=Storage.definition(index)
                assert(fixture.name=='house-storage' and fixture.houseStorageHotspot and fixture.permanent)
                assert(fixture.x==spot.x and fixture.y==spot.y and fixture.entityId)
                assert(not Furniture.isFurniture(fixture.name) and not fixture.generatedFurniture)
                assert(Catalog.storageCapacities[fixture.name]==20)
                for slot,name in pairs(fixture.storage) do
                    assert(slot<=20 and not Furniture.isFurniture(name),'furniture leaked into home loot')
                end
                local x,y=require('game.util').clampHouseFloor(fixture.x,fixture.y)
                assert((x-fixture.x)^2+(y-fixture.y)^2<75^2,'fixture cannot be reached')
            end
        ''')

    def test_legacy_empty_rooms_switch_to_matching_furnished_room(self):
        self.lua.execute(r'''
            for stop=1,50 do for legacy=1,5 do
                local data=campaign(stop,2,legacy)
                data.stopLayouts[tostring(stop)].houseDoors={['2']={interior=legacy,npc=3}}
                ensure(data)
                local expected=5+(stop-1)*5+legacy
                local layout=data.stopLayouts[tostring(stop)]
                assert(layout.interior==expected and layout.houseDoors['2'].interior==expected)
                assert(layout.houseDoors['2'].npc==3,'storage migration changed resident identity')
            end end
        ''')

    def test_migration_removes_free_furniture_preserves_contents_gear_and_player_items(self):
        self.lua.execute(r'''
            local data=campaign(4,1,22)
            local legacy={name='travel-chest',scene='house',location=4,houseDoor=1,x=410,y=400,storage={}}
            local decoration={name='single-bed',scene='house',location=4,houseDoor=1,generatedFurniture=true,x=300,y=450}
            local legacyBedroll={name='bedroll',scene='house',location=4,houseDoor=1,x=320,y=450}
            local player={name='wooden-chair',scene='house',location=4,houseDoor=1,droppedByPlayer=true,x=300,y=400}
            local otherDoor={name='supply-crate',scene='house',location=4,houseDoor=2,x=400,y=400,storage={[1]='food-ration'}}
            local train={name='travel-chest',scene='train',carIndex=1,x=450,y=450,storage={[1]='water-bottle'}}
            data.droppedItems={legacy,decoration,legacyBedroll,player,otherDoor,train}
            Items.write(data,legacy,{kind='chest',index=1},'frontier-short-sword')
            local gear=Items.get(data,legacy,{kind='chest',index=1}); gear.durability=37
            require('game.coop_entities').ensure(data)
            local originalId=legacy.entityId; local gearId=gear.id
            ensure(data)
            assert(#data.droppedItems==4 and data.droppedItems[1]==legacy)
            assert(legacy.name=='house-storage' and legacy.entityId==originalId and legacy.permanent)
            assert(Items.get(data,legacy,{kind='chest',index=1}).id==gearId)
            assert(Items.get(data,legacy,{kind='chest',index=1}).durability==37)
            assert(data.droppedItems[2]==player and player.name=='wooden-chair' and player.x==300)
            assert(data.droppedItems[3]==otherDoor and otherDoor.name=='supply-crate' and otherDoor.storage[1]=='food-ration')
            assert(data.droppedItems[4]==train and train.name=='travel-chest' and train.storage[1]=='water-bottle')
        ''')

    def test_consumed_fixed_storage_survives_save_load_without_restocking(self):
        self.lua.execute(r'''
            local data=campaign(7,1,36); ensure(data)
            local fixture=data.droppedItems[1]; local id=fixture.entityId
            local keys={}; for slot in pairs(fixture.storage) do keys[#keys+1]=slot end
            for _,slot in ipairs(keys) do Items.write(data,fixture,{kind='chest',index=slot},nil) end
            data=roundtrip(data); ensure(data); ensure(data)
            assert(#data.droppedItems==1 and data.droppedItems[1].entityId==id)
            assert(data.droppedItems[1].houseStorageHotspot and data.droppedItems[1].permanent)
            assert(not next(data.droppedItems[1].storage),'reentering replenished consumed loot')
            Inventory.setValue(data,data.droppedItems[1],{kind='chest',index=20},'coal-chunk',Catalog.wearableItems)
            data=roundtrip(data); ensure(data)
            assert(data.droppedItems[1].storage[20]=='coal-chunk','player storage did not persist')
        ''')

    def test_destination_probe_is_read_only_before_reward_transaction(self):
        self.lua.execute(r'''
            local data=campaign(3,2,16)
            data.stopLayouts=nil
            local destination,slot,index,count=House.lootDestination(data,Catalog,3)
            assert(destination==nil and slot==1 and index==nil and count==0)
            assert(#data.droppedItems==0 and data.stopLayouts==nil,
                'authorization probe generated an uncommitted storage entity')
            local old={name='travel-chest',scene='house',location=3,houseDoor=2,storage={},x=444,y=555}
            data.droppedItems[1]=old
            assert(require('game.coop_entities').ensure(data))
            assert(House.lootDestination(data,Catalog,3)==old)
            assert(old.name=='travel-chest' and old.x==444 and old.y==555 and not old.houseStorageHotspot,
                'authorization probe migrated storage before mutation was authorized')
            for i=1,10 do old.storage[i]='food-ration' end
            local predicted,predictedSlot=House.lootDestination(data,Catalog,3)
            assert(predicted==old and predictedSlot==11 and old.name=='travel-chest')
            House.storeLoot(data,Catalog,'coal-chunk',3)
            assert(data.droppedItems[1]==predicted and predicted.storage[predictedSlot]=='coal-chunk',
                'legacy conversion changed the container chosen for reward authorization')
        ''')

    def test_seeding_unvisited_home_does_not_preempt_stop_world_generation(self):
        self.lua.execute(r'''
            local data=campaign(1); data.stopLayouts={}
            data.npcRoster={'crow-merchant.png','cook-mouse.png','conductor-cat.png'}
            House.storeLoot(data,Catalog,'coal-chunk',5)
            assert(data.stopLayouts['5']==nil,'reward storage created a partial unvisited stop')
            assert(#data.droppedItems==1 and data.droppedItems[1].location==5)
            data.location=5
            local seed=951
            local function random() seed=(seed*16807)%2147483647; return (seed-1)/2147483646 end
            local layout=require('game.stops').ensure(data,Catalog,'stop',random)
            assert(layout.houseX and layout.treeA and layout.treeB and layout.house and layout.tree,
                'normal stop generation was bypassed by preseeded house loot')
            ensure(data)
            assert(#data.droppedItems==1 and data.droppedItems[1].storage[1]=='coal-chunk')
        ''')

    def test_keyboard_and_mouse_open_hotspot_instead_of_picking_it_up(self):
        self.lua.execute(r'''
            local Router=require('game.interaction_router')
            local data=campaign(2,1,11); ensure(data); local chest=data.droppedItems[1]
            local selected=Router.select({scene='house',data=data,player={x=chest.x,y=chest.y},
                itemIsHere=function() return true end,storageCapacities=Catalog.storageCapacities,
                car={x=0,w=700},layout=function() return data.stopLayouts['2'] end,
                interiorPoint=function() return 400,600 end,nearInteriorDoor=function() return false end,
                choose=function(candidates) assert(#candidates==1); return candidates[1] end})
            assert(selected.kind=='chest' and selected.label=='HOUSE STORAGE' and selected.houseStorageHotspot)
            local action,index=Router.keyAction({selected=selected},'e')
            assert(action=='openStorage' and index==1)
            selected.hovered=true
            for _,button in ipairs({1,2}) do assert(Router.mouseAction(selected,button)=='openStorage') end
            assert(Router.keyAction({selected={kind='chest',index=1}},'e')=='holdPickup',
                'purchased movable chests lost pickup behavior')
        ''')

    def test_local_pickup_cannot_turn_fixture_into_an_inventory_item(self):
        self.lua.execute(r'''
            local data=campaign(1); ensure(data); data.droppedItems[1].storage={}
            local runtime={saveData=data,nearbyItem=1}; local writes=0
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,catalog=Catalog,
                util=require('game.util'),trainUpgradeBalance=require('game.train_upgrade_balance'),
                lootProgression=require('game.loot_progression'),writeSave=function() writes=writes+1 end,
                useBattleHealingItem=function() end,useBattlePotion=function() end})
            local ok,reason=actions.pickUpNearby()
            assert(ok==false and reason=='fixed_storage' and writes==0)
            assert(#data.droppedItems==1 and not next(data.inventory))
        ''')

    def test_host_rejects_fixture_pickup_but_allows_content_transfer_for_both_players(self):
        self.lua.execute(r'''
            local data=campaign(1); assert(F.enroll(data)); ensure(data)
            local fixture=data.droppedItems[1]; local commands={}
            local authority={register=function(_,name,handler) commands[name]=handler end}
            require('game.coop_inventory').install(authority,{catalog=Catalog,actorState=function()
                return {screen='game',scene='house',x=fixture.x,y=fixture.y}
            end})
            local Players=require('game.coop_players'); local Contract=require('game.coop_item_contract')
            for _,actorId in ipairs({'host','companion'}) do
                local plan,reason=commands['loot.pickup'](data,actorId,{entityId=fixture.entityId},{state={resources={}}})
                assert(not plan and reason=='fixed_storage')
                local actor=Players.forActor(data,actorId); actor.inventory={}
                Items.write(data,fixture,{kind='chest',index=20},'coal-chunk')
                local ref={kind='chest',index=20}
                local transfer=assert(commands['storage.transfer'](data,actorId,{containerId=fixture.entityId,
                    source=ref,sourceItem=Contract.selection(actor,fixture,ref)}))
                assert(transfer.apply() and actor.inventory[1]=='coal-chunk' and not fixture.storage[20])
            end
            assert(#data.droppedItems==1 and fixture.permanent)
        ''')


if __name__ == "__main__":
    unittest.main()
