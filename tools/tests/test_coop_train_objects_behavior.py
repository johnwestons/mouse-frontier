"""Exclusive object editing and nearby shared radio controls use host state."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopTrainObjectTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Authority=require('game.coop_authority'); Schema=require('game.save_schema')
            Players=require('game.coop_players'); Entities=require('game.coop_entities')
            Items=require('game.item_instances')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data)); data.scene='train'
            object={name='frontier-short-sword',scene='train',carIndex=1,x=300,y=350,scale=1}
            radio={name='boombox-radio',scene='train',carIndex=1,x=320,y=350,permanent=true}
            data.droppedItems={object,radio}; assert(Items.ensure(data)); data.audio={station='chill',musicVolume=.35}
            now=0; states={host={screen='game',scene='train',x=300,y=350},companion={screen='game',scene='train',x=300,y=350}}
            service=Authority.new({campaign=data,sessionId='train',clock=function() return now end})
            context={catalog=Catalog,actorState=function(id) return states[id] end}
            require('game.coop_train_objects').install(service,context)
            require('game.coop_inventory').install(service,context)
            require('game.coop_activities').install(service,context)
            service:admit('companion',1)
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function acquire(actor,item) return run(actor,'decoration.acquire',{entityId=(item or object).entityId}) end
            function place(actor,lease,values) return run(actor,'decoration.place',{leaseId=lease,values=values}) end
        ''')

    def test_guest_edits_current_car_object_under_exclusive_lease(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            assert(acquire('host').reason=='activity_busy')
            assert(run('host','loot.pickup',{entityId=object.entityId}).reason=='activity_busy')
            assert(place('host',lease,{x=100}).reason=='lease_owner')
            local result=place('companion',lease,{x=0,y=720,scale=2.5,rotation=math.pi/4,hue=.5,saturation=2,layer=-5})
            assert(result.ok and object.x==0 and object.y==720 and object.layer==-5)
            assert(data.location==1 and data.scene=='train' and data.scrap==40)
            local saved=assert(Schema.migrate(data)); assert(saved.droppedItems[1].hue==.5 and not saved.activityState)
        ''')

    def test_invalid_geometry_and_property_injection_do_not_modify_item(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            for _,values in ipairs({{x=-1},{y=721},{scale=10},{rotation=math.huge},{hue=0/0},{layer=.5},
                {name='cowboy-hat'},{permanent=false},{storage={}}, {carIndex=2},{saturation=-1}}) do
                assert(place('host',lease,values).reason=='invalid_placement')
            end
            assert(object.name=='frontier-short-sword' and object.x==300 and object.scale==1)
        ''')

    def test_exact_collect_replay_preserves_item_identity_and_array_compaction(self):
        self.lua.execute('''
            local id=object.itemInstance.id; object.itemInstance.durability=23
            local lease=acquire('companion').result.leaseId
            table.insert(data.droppedItems,1,{name='potted-sprout',scene='train',x=20,y=20}); Entities.ensure(data)
            local req=assert(service:prepareRequest('companion','decoration.collect',{leaseId=lease}))
            local reply=execute('companion',req); assert(reply.ok and execute('companion',req).ok)
            local slot=reply.result.slot
            assert(data.players.companion.inventory[slot]=='frontier-short-sword')
            assert(data.players.companion.itemSlots.inventory[slot].id==id and data.players.companion.itemSlots.inventory[slot].durability==23)
            assert(not Entities.find(data,object.entityId) and data.droppedItems[1].name=='potted-sprout' and data.droppedItems[2]==radio)
        ''')

    def test_permanent_full_container_and_full_backpack_cannot_be_collected(self):
        self.lua.execute('''
            local lease=acquire('host',radio).result.leaseId
            assert(run('host','decoration.collect',{leaseId=lease}).reason=='permanent')
            assert(run('host','activity.release',{leaseId=lease}).ok)
            object.name='supply-crate'; object.itemInstance=nil; object.storage={'water-bottle'}
            lease=acquire('host').result.leaseId
            assert(run('host','decoration.collect',{leaseId=lease}).reason=='container_not_empty')
            object.storage={}
            for i=1,data.inventoryCapacity do Items.write(data,nil,{kind='inventory',index=i},'cowboy-hat') end
            assert(run('host','decoration.collect',{leaseId=lease}).reason=='inventory_full')
            assert(Entities.find(data,object.entityId)==object and not next(object.storage))
        ''')

    def test_car_scene_expiry_and_disconnect_invalidate_edits_without_reverting_committed_positions(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            assert(place('companion',lease,{x=500}).ok)
            data.players.companion.activeCar=2
            assert(place('companion',lease,{x=200}).reason=='object_unavailable')
            data.players.companion.activeCar=1; now=31
            assert(place('companion',lease,{x=200}).reason=='lease_expired')
            lease=acquire('companion').result.leaseId; data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(not place('companion',lease,{x=200}).ok)
            lease=acquire('companion').result.leaseId; service:disconnect('companion',1)
            assert(acquire('host').ok and object.x==500)
        ''')

    def test_radio_controls_are_nearby_shared_state_and_cannot_set_personal_volume(self):
        self.lua.execute('''
            local args={entityId=radio.entityId,station='vibes',rainEnabled=false}
            assert(run('companion','radio.station',args).ok and data.audio.station=='vibes' and data.audio.musicVolume==.35)
            args.musicVolume=0; assert(run('companion','radio.station',args).reason=='invalid_args')
            args.musicVolume=nil; args.station='arbitrary-file'; assert(run('companion','radio.station',args).reason=='invalid_args')
            args.station='chill'; states.companion.x=100
            assert(run('companion','radio.station',args).reason=='radio_unavailable' and data.audio.station=='vibes')
            states.companion.x=300; data.players.companion.activeCar=2
            assert(run('companion','radio.station',args).reason=='radio_unavailable')
        ''')

    def test_actual_ui_adapter_tracks_identity_releases_on_close_and_renews(self):
        self.lua.execute('''
            runtime={saveData=data,state='game',scene='train',editMode=true,animationClock=0}; ui={}
            require('game.coop_decoration_runtime').install({runtime=runtime,ui=ui,commands={
                submit=function(name,args) return run('host',name,args) end,
                identify=function(value) return value.entityId end}})
            assert(ui.selectDecoration(2) and ui.editedDecoration()==radio)
            table.remove(data.droppedItems,1)
            assert(ui.editedDecoration()==radio and runtime.editedItem==1)
            assert(ui.placeDecoration(radio,{hue=.7}) and radio.hue==.7)
            now=11; runtime.animationClock=11; ui.updateDecoration()
            now=35; assert(ui.placeDecoration(radio,{hue=.8}))
            runtime.editMode=false; ui.updateDecoration()
            assert(not runtime.editedItem and not next(service.activityState.resources))
            runtime.editMode=true; assert(ui.selectDecoration(1)); ui.closeDecoration()
            assert(not next(service.activityState.resources))
        ''')

    def test_unavailable_actor_or_encounter_cannot_edit_or_change_radio(self):
        self.lua.execute('''
            for _,flag in ipairs({'traveling','changingCar','activityBlocked','encounterActive'}) do
                states.companion[flag]=true
                assert(acquire('companion').reason=='object_unavailable')
                assert(run('companion','radio.station',{entityId=radio.entityId,station='8bit'}).reason=='radio_unavailable')
                states.companion[flag]=nil
            end
            data.players.companion.health=0
            assert(acquire('companion').reason=='object_unavailable')
            assert(run('companion','radio.station',{entityId=radio.entityId,station='8bit'}).reason=='radio_unavailable')
            assert(not next(service.activityState.resources) and data.audio.station=='chill')
        ''')

    def test_forced_collection_failure_preserves_container_and_inventory(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            local write=Items.write
            Items.write=function(...) write(...); error('injected collection failure') end
            assert(run('companion','decoration.collect',{leaseId=lease}).reason=='handler_error')
            assert(Entities.find(data,object.entityId)==object)
            Items.write=write
            assert(run('companion','decoration.collect',{leaseId=lease}).ok and Schema.validate(data))
        ''')


if __name__ == "__main__":
    unittest.main()
