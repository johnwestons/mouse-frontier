"""Painted scene actions: finite harvests, actor access and read-only inspections."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class StopHotspotBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures')
            love={filesystem=F.filesystem()}
            H=require('game.stop_hotspots'); Catalog=require('game.catalog')
            Items=require('game.item_instances'); Inventory=require('game.inventory')
            Save=require('game.save'); Router=require('game.interaction_router')
            function campaign(stop)
                return F.campaign(stop or 1,{scene='stop',inventory={},equipment={},droppedItems={}})
            end
            function selectSpot(data,spot)
                return Router.select({scene='stop',data=data,player={x=spot.x,y=spot.y},
                    itemIsHere=function(item) return item.scene=='stop' and item.location==data.location end,
                    storageCapacities=Catalog.storageCapacities,car={x=0,w=700},
                    nearTrain=function() return false end,nearDoor=function() return false end,hasSettlements=true,
                    mouseX=spot.x,mouseY=spot.y,choose=require('game.interactions').select})
            end
        ''')

    def test_all_paintings_have_inspections_and_reachable_hotspots(self):
        from tools.audit_stop_hotspots import audit
        results = audit()
        self.assertEqual({r['stop'] for r in results if r['kind'] == 'stopInspect'}, set(range(1,51)))
        self.assertGreaterEqual(len([r for r in results if r['kind']=='harvest']), 30)
        self.assertFalse([r for r in results if r['reach'] >= r['radius']])
        self.lua.execute(r'''
            for stop=1,50 do
                local ids={}
                for _,spot in ipairs(H.definitions(stop)) do
                    assert(not ids[spot.id]);ids[spot.id]=true
                    assert(spot.x>0 and spot.x<960 and spot.y>0 and spot.y<720)
                    if spot.kind=='harvest' then assert(Catalog.itemEffects[spot.crop]) end
                end
            end
            assert(#H.definitions(51)==0 and #H.definitions(0)==0)
        ''')

    def test_ensure_seeds_once_and_preserves_empty_and_partial_harvests_across_save(self):
        self.lua.execute(r'''
            local data=campaign();H.ensure(data)
            local garden=data.droppedItems[1];local id=garden.entityId
            assert(#garden.storage==3 and garden.storage[1]=='carrot' and garden.permanent)
            assert(Catalog.storageCapacities[garden.name]==6)
            Items.write(data,garden,{kind='chest',index=1},nil)
            assert(Save.write(99,data));data=assert(Save.read(99));H.ensure(data)
            garden=data.droppedItems[1]
            assert(garden.entityId==id and not garden.storage[1] and garden.storage[2]=='carrot')
            garden.storage={}
            assert(Save.write(99,data));data=assert(Save.read(99));H.ensure(data);H.ensure(data)
            assert(#data.droppedItems==1 and not next(data.droppedItems[1].storage))
            data.location=2;H.ensure(data);assert(#data.droppedItems==2)
            data.location=1;H.ensure(data);assert(#data.droppedItems==2 and not next(data.droppedItems[1].storage))
        ''')

    def test_intro_home_is_excluded_and_inspection_only_stops_add_no_container(self):
        self.lua.execute(r'''
            local data=campaign();local Home=require('game.home_stop')
            data.homeStop={version=Home.VERSION,stage='briefing'}
            H.ensure(data);assert(#data.droppedItems==0)
            assert(not H.nearest(data,{x=412.5,y=525}) and not H.find(data,'well'))
            data=campaign(5);H.ensure(data);assert(#data.droppedItems==0)
        ''')

    def test_router_opens_harvest_and_inspection_with_keyboard_and_mouse(self):
        self.lua.execute(r'''
            local data=campaign();H.ensure(data)
            for _,spot in ipairs(H.definitions(1)) do
                local selected=assert(selectSpot(data,spot))
                selected.hovered=true
                local action,arg=Router.keyAction({selected=selected},'e')
                if spot.kind=='harvest' then
                    assert(action=='openStorage' and arg==1 and selected.stopHotspotId)
                    assert(Router.mouseAction(selected,1)=='openStorage')
                    assert(Router.mouseAction(selected,2)=='openStorage')
                else
                    assert(action=='inspectStop' and arg==spot.id)
                    local mouse,key=Router.mouseAction(selected,1);assert(mouse=='routeKey' and key=='e')
                end
                assert(Router.keyAction({selected=selected,blocked=true},'e')==nil)
            end
            assert(Router.keyAction({dialogue={inspection=true}},'e')=='closeDialogue')
            local data42=campaign(42);local car=H.find(data42,'car')
            assert(H.nearest(data42,{x=car.x,y=car.y-130})==car)
            assert(not H.nearest(data42,{x=car.x,y=car.y-151}))
            data42.scene='house';assert(not H.find(data42,'car'))
        ''')

    def test_both_players_harvest_with_host_authority_and_cannot_pick_up_the_garden(self):
        self.lua.execute(r'''
            local data=campaign();assert(F.enroll(data));H.ensure(data)
            local garden=data.droppedItems[1];local commands={};local far=false
            require('game.coop_inventory').install({register=function(_,name,handler) commands[name]=handler end},
                {catalog=Catalog,actorState=function() return {screen='game',scene='stop',x=garden.x+(far and 76 or 0),y=garden.y} end})
            local Players=require('game.coop_players');local Contract=require('game.coop_item_contract')
            for slot,actorId in ipairs({'host','companion'}) do
                local actor=Players.forActor(data,actorId);actor.inventory={}
                local ref={kind='chest',index=slot}
                local args={containerId=garden.entityId,source=ref,sourceItem=Contract.selection(actor,garden,ref)}
                far=true;assert(not commands['storage.transfer'](data,actorId,args));far=false
                local transfer=assert(commands['storage.transfer'](data,actorId,args))
                assert(transfer.apply() and actor.inventory[1]=='carrot' and not garden.storage[slot])
                local plan,reason=commands['loot.pickup'](data,actorId,{entityId=garden.entityId},{state={resources={}}})
                assert(not plan and reason=='fixed_storage')
            end
            assert(garden.storage[3]=='carrot' and #data.droppedItems==1)
        ''')

    def test_full_backpack_keeps_harvest_in_place_and_local_pickup_is_rejected(self):
        self.lua.execute(r'''
            local data=campaign();H.ensure(data);local garden=data.droppedItems[1]
            for slot=1,(data.inventoryCapacity or 6) do data.inventory[slot]='carrot' end
            assert(not Inventory.quickTransfer(data,garden,{kind='chest',index=1},Catalog.weaponStats,
                Catalog.ammoPickupAmounts,Catalog.storageCapacities,Catalog.wearableItems))
            assert(garden.storage[1]=='carrot')
            local runtime={saveData=data,nearbyItem=1};local writes=0
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,catalog=Catalog,
                util=require('game.util'),trainUpgradeBalance=require('game.train_upgrade_balance'),
                lootProgression=require('game.loot_progression'),writeSave=function() writes=writes+1 end,
                useBattleHealingItem=function() end,useBattlePotion=function() end})
            local ok,reason=actions.pickUpNearby();assert(ok==false and reason=='fixed_storage' and writes==0)
        ''')

    def test_guest_inspection_is_read_only_and_closes_on_scene_change(self):
        self.lua.execute(r'''
            local data=campaign(42);local spot=H.definitions(42)[1];local neutral=0
            local view={runtime={saveData=data,player={x=spot.x,y=spot.y}},epoch=3}
            function view:inputAllowed() return not (self.inspection and self.inspection.opened) end
            function view:neutralize() neutral=neutral+1 end
            local panel=require('game.coop_guest_inspection').new(view);view.inspection=panel
            local before=require('game.save_schema').copy(data)
            local function same(a,b)
                if type(a)~='table' then return a==b end
                for k,v in pairs(a) do if not same(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end
                return true
            end
            assert(panel:nearest()==spot and panel:open() and neutral==1)
            assert(panel.spot.description=="This old car hasn't moved in some time...")
            assert(not view:inputAllowed() and not panel:nearest())
            panel:keypressed('e');assert(not panel.opened)
            panel:open();panel:pointer(450,460);assert(not panel.opened)
            panel:open();view.epoch=4;panel:update();assert(not panel.opened)
            assert(same(data,before))
            view.runtime.player.x=0;assert(not panel:open(spot))
            local cap=require('game.coop_capabilities')
            assert(cap.requireInteraction('stopInspect'))
            assert(cap.commands['scene.inspect'].policy=='local_presentation')
        ''')


if __name__ == '__main__':
    unittest.main()
