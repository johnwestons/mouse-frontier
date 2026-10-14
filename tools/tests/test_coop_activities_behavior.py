"""Host-clock activity ownership through the real staged command authority."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopActivitiesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Players=require('game.coop_players'); Items=require('game.item_instances')
            Schema=require('game.save_schema'); Loot=require('game.loot_progression')
            Authority=require('game.coop_authority'); Activities=require('game.coop_activities')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data)); data.scrap=700; data.stopped=true
            now=10
            states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
            actors={host=Players.forActor(data,'host'),companion=Players.forActor(data,'companion')}
            weapons={}
            for id,actor in pairs(actors) do
                local item=Items.get(actor,nil,{kind='equipment',index=1}); item.durability=20; weapons[id]=item.id
                Items.write(actor,nil,{kind='inventory',index=2},Catalog.weaponRepairParts[item.name])
            end
            service=Authority.new({campaign=data,sessionId='activities',clock=function() return now end})
            Activities.install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            require('game.coop_inventory').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1)
            function req(actor,command,args) return assert(service:prepareRequest(actor,command,args)) end
            function execute(actor,request,generation) return service:execute(actor,generation or (actor=='host' and 0 or 1),request) end
            function run(actor,command,args)
                local request,reason=service:prepareRequest(actor,command,args)
                if not request then return {ok=false,reason=reason} end
                return execute(actor,request)
            end
            function acquire(actor) return run(actor,'weaponRepair.acquire',{itemId=weapons[actor]}) end
            function complete(actor,lease) return run(actor,'weaponRepair.complete',{leaseId=lease}) end
            function condition(actor) return Items.condition(actors[actor],weapons[actor]) end
            function perfect() now=now+.655/.86 end
        ''')

    def test_health_encounter_and_existing_activity_guards_apply_to_every_train_station(self):
        self.lua.execute('''
            for _,command in ipairs({'weaponRepair.acquire','maintenance.acquire','outfit.craft'}) do
                local args=command=='weaponRepair.acquire' and {itemId=weapons.companion} or command=='outfit.craft' and {action='acquire'} or {}
                actors.companion.health=0; assert(run('companion',command,args).reason=='activity_unavailable'); actors.companion.health=20
                states.companion.encounterActive=true; assert(run('companion',command,args).reason=='activity_unavailable'); states.companion.encounterActive=nil
                states.companion.activityBlocked=true; states.companion.activeActivity='firstAid'
                assert(run('companion',command,args).reason=='activity_unavailable'); states.companion.activityBlocked=nil; states.companion.activeActivity=nil
            end
            assert(not next(service.activityState.resources) and data.scrap==700)
        ''')

    def test_repair_renewal_reports_host_elapsed_without_resetting_gauge_or_claimed_quality(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId; local started=service.activityState.resources['train:weapon-repair'].startedAt
            now=now+5; states.companion.activityBlocked=true; states.companion.activeActivity='weaponRepair'
            local renew=run('companion','weaponRepair.step',{leaseId=lease,renew=true})
            assert(renew.ok and renew.result.elapsed==5 and renew.result.expiresIn==30)
            assert(service.activityState.resources['train:weapon-repair'].startedAt==started)
            assert(run('companion','weaponRepair.step',{leaseId=lease,renew=true,elapsed=100}).reason=='invalid_args')
            now=started+(5+.655)/.86; local done=complete('companion',lease)
            assert(done.ok and done.result.quality=='perfect' and condition('companion')==100)
        ''')

    def test_guest_repairs_own_weapon_and_host_obeys_same_exclusive_bench(self):
        self.lua.execute('''
            local offer=req('host','weaponRepair.acquire',{itemId=weapons.host})
            local guest=acquire('companion'); assert(guest.ok)
            assert(next(service.activityState.resources) and data.activityState==nil)
            local host=execute('host',offer); assert(not host.ok and host.reason=='stale_revision')
            host=acquire('host'); assert(not host.ok and host.reason=='activity_busy')
            local cost=Loot.repairStatus(actors.companion,Catalog,weapons.companion).cost
            perfect(); local done=complete('companion',guest.result.leaseId)
            assert(done.ok and done.result.ok and done.result.quality=='perfect')
            assert(condition('companion')==100 and condition('host')==20 and data.scrap==700-cost)
            assert(actors.companion.inventory[2]==nil and actors.host.inventory[2]~=nil)
            assert(data.location==1 and data.scene=='train' and not next(service.activityState.resources))
            assert(acquire('host').ok)
        ''')

    def test_prepare_does_not_reserve_and_replays_do_not_charge_or_allocate_twice(self):
        self.lua.execute('''
            local request=req('host','weaponRepair.acquire',{itemId=weapons.host})
            req('host','weaponRepair.acquire',{itemId=weapons.host})
            assert(not next(service.activityState.resources) and service.activityState.nextId==1)
            local started=execute('host',request)
            local repeated=execute('host',request)
            assert(started.ok and repeated.result.leaseId==started.result.leaseId and service.activityState.nextId==2)
            perfect(); local finish=req('host','weaponRepair.complete',{leaseId=started.result.leaseId})
            local done=execute('host',finish); assert(done.ok and done.result.ok)
            local scrap=data.scrap; local revision=data.coop.revision
            assert(execute('host',finish).result.restored==100)
            assert(data.scrap==scrap and data.coop.revision==revision and not next(service.activityState.resources))
        ''')

    def test_client_cannot_supply_quality_elapsed_time_or_another_actors_item(self):
        self.lua.execute('''
            local wrong=run('companion','weaponRepair.acquire',{itemId=weapons.host})
            assert(not wrong.ok and wrong.reason=='ownership')
            local lease=acquire('host').result.leaseId
            for _,extra in ipairs({'quality','elapsed','startedAt','actorId'}) do
                local args={leaseId=lease}; args[extra]=extra=='quality' and 'perfect' or 1
                local forged=run('host','weaponRepair.complete',args)
                assert(not forged.ok and forged.reason=='invalid_args')
            end
            local miss=complete('host',lease)
            assert(miss.ok and not miss.result.ok and miss.result.reason=='miss')
            assert(condition('host')==20 and data.scrap==700 and actors.host.inventory[2]~=nil)
            assert(not next(service.activityState.resources))
        ''')

    def test_other_actor_cannot_finish_or_release_and_binding_change_invalidates(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            assert(complete('host',lease).reason=='lease_owner')
            assert(run('host','activity.release',{leaseId=lease}).reason=='lease_owner')
            service:disconnect('companion',99); assert(next(service.activityState.resources))
            service:disconnect('companion',1); assert(not next(service.activityState.resources))
            service:admit('companion',2)
            local request={sessionId='activities',requestId=2,sceneEpoch=data.coop.sceneEpoch,
                command='weaponRepair.complete',args={leaseId=lease},expected={}}
            assert(execute('companion',request,1).reason=='unbound_peer')
            assert(execute('companion',request,2).reason=='lease_expired')
            assert(condition('companion')==20 and data.scrap==700)
        ''')

    def test_expiry_scene_change_and_reload_never_restore_old_leases(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            now=41; assert(complete('host',lease).reason=='lease_expired')
            local nextLease=acquire('companion').result.leaseId; assert(nextLease~=lease)
            local saved=assert(Schema.migrate(data))
            local reopened=Authority.new({campaign=saved,sessionId='new-session',clock=function() return now end})
            assert(not next(reopened.activityState.resources) and saved.activityState==nil)
            data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(complete('companion',nextLease).reason=='lease_expired')
            assert(acquire('host').ok)
        ''')

    def test_changed_car_scene_travel_and_combat_prevent_repair(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            data.trainCars[2]='storage'; actors.host.activeCar=2
            assert(complete('host',lease).reason=='activity_unavailable')
            assert(run('host','activity.release',{leaseId=lease}).ok)
            for _,mode in ipairs({'battle','stop','travel','moving','changingCar','activity','ambush','unknownStop'}) do
                states.host.screen=mode=='battle' and 'battle' or 'game'
                states.host.scene=mode=='stop' and 'stop' or 'train'
                states.host.traveling=mode=='travel'; data.stopped=mode~='moving'
                states.host.changingCar=mode=='changingCar'; states.host.activityBlocked=mode=='activity'
                data.trainAmbush={active=mode=='ambush'}
                if mode=='unknownStop' then data.stopped=nil end
                local answer=acquire('host'); assert(not answer.ok and answer.reason=='activity_unavailable')
            end
            assert(condition('host')==20 and data.scrap==700)
        ''')

    def test_replaced_or_moved_inventory_cancels_ownership_without_spending(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            assert(run('host','inventory.swap',{source={kind='equipment',index=1},target={kind='inventory',index=3}}).ok)
            perfect(); assert(complete('host',lease).reason=='activity_changed')
            assert(run('host','activity.release',{leaseId=lease}).ok)
            lease=acquire('host').result.leaseId
            Items.write(actors.host,nil,{kind='inventory',index=3},'frontier-short-sword')
            assert(complete('host',lease).reason=='activity_changed' and data.scrap==700)
        ''')

    def test_live_resource_loss_finishes_without_partial_cost_or_stuck_lock(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            data.scrap=0; perfect()
            local result=complete('host',lease)
            assert(result.ok and not result.result.ok and result.result.reason=='scrap')
            assert(condition('host')==20 and actors.host.inventory[2]~=nil and data.scrap==0)
            assert(not next(service.activityState.resources))
        ''')

    def test_failed_domain_operation_rolls_back_campaign_and_lease_together(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId; perfect()
            local original=Loot.completeRepair
            Loot.completeRepair=function(actor,...)
                original(actor,...)
                error('forced failure after item and resource edits')
            end
            local result=complete('host',lease)
            assert(not result.ok and result.reason=='handler_error')
            assert(condition('host')==20 and data.scrap==700 and actors.host.inventory[2]~=nil)
            assert(service.activityState.resources['train:weapon-repair'].id==lease)
            Loot.completeRepair=original
            assert(complete('host',lease).result.ok)
        ''')

    def test_concurrent_resource_change_rejects_old_finish_without_consuming_attempt(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId; perfect()
            local pending=req('host','weaponRepair.complete',{leaseId=lease})
            service:register('merchant.buy',function(draft)
                return {scopes={'resources'},apply=function() draft.scrap=draft.scrap-3; return {ok=true} end}
            end)
            assert(run('companion','merchant.buy',{}).ok)
            local rejected=execute('host',pending)
            assert(not rejected.ok and rejected.reason=='stale_revision')
            assert(data.scrap==697 and condition('host')==20 and actors.host.inventory[2]~=nil)
            assert(service.activityState.resources['train:weapon-repair'].id==lease)
            assert(run('host','activity.release',{leaseId=lease}).ok)
            assert(acquire('companion').ok)
        ''')

    def test_acquisition_and_release_never_serialize_an_active_lease(self):
        self.lua.execute('''
            local lease=acquire('host').result.leaseId
            local copied=assert(Schema.copy(data)); assert(copied.activityState==nil and copied.coop.leases==nil)
            local reopened=Authority.new({campaign=copied,sessionId='reopened',clock=function() return now end})
            assert(not next(reopened.activityState.resources))
            local release=req('host','activity.release',{leaseId=lease})
            assert(execute('host',release).ok)
            local second=acquire('companion'); assert(second.ok)
            assert(execute('host',release).ok)
            assert(service.activityState.resources['train:weapon-repair'].actorId=='companion')
            local stale=run('host','activity.release',{leaseId=lease})
            assert(not stale.ok and stale.reason=='lease_expired')
        ''')

    def test_actor_cannot_hold_multiple_activities_and_exhaustion_is_atomic(self):
        self.lua.execute('''
            local Leases=require('game.coop_leases')
            local lease=assert(Leases.acquire(service.activityState,'patient:e9','host',0,data.coop.sceneEpoch,now,{}))
            local reply=acquire('host'); assert(not reply.ok and reply.reason=='actor_busy')
            assert(service.activityState.nextId==2 and service.activityState.resources['patient:e9'].id==lease.id)
            assert(run('host','activity.release',{leaseId=lease.id}).ok)
            service.activityState.nextId=2147483647
            reply=acquire('host'); assert(not reply.ok and reply.reason=='lease_ids_exhausted')
            assert(not next(service.activityState.resources) and service.activityState.nextId==2147483647)
            assert(data.scrap==700 and condition('host')==20)
        ''')

    def test_real_offline_action_adapter_uses_host_clock_not_passed_quality(self):
        self.lua.execute('''
            local Session=require('game.game_session'); local session=Session.new()
            local runtime={saveData=data,state='game',scene='train',player={x=100,y=200},animationClock=20}
            session:activate(data,runtime.player); session:setScreen('game')
            local commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog})
            local saves=0
            local actions=require('game.inventory_actions').new({runtime=runtime,commands=commands,
                inventory=require('game.inventory'),catalog=Catalog,util=require('game.util'),
                trainUpgradeBalance={},lootProgression=Loot,writeSave=function() saves=saves+1 end,
                useBattleHealingItem=function() end,useBattlePotion=function() end})
            assert(actions.beginWeaponRepair(weapons.host).ok)
            local miss=actions.repairWeapon(weapons.host,'perfect')
            assert(not miss.ok and miss.reason=='miss' and saves==0 and data.scrap==700)
            local started=actions.beginWeaponRepair(weapons.host)
            runtime.animationClock=started.startedAt+.655/.86
            assert(actions.repairWeapon(weapons.host,'miss').ok)
            assert(condition('host')==100 and saves==1)
            assert(not actions.repairWeapon(weapons.host,'perfect').ok and saves==1)
        ''')

    def test_real_focus_loss_cancels_the_local_attempt_before_save(self):
        self.lua.execute('''
            local session=require('game.game_session').new()
            local runtime={saveData=data,state='game',scene='train',player={x=100,y=200},animationClock=20,
                selectedSlot=1,syncForSave=function() end}
            session:activate(data,runtime.player); session:setScreen('game')
            session:selectSlot(1)
            local commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog})
            local actions=require('game.inventory_actions').new({runtime=runtime,commands=commands,
                inventory=require('game.inventory'),catalog=Catalog,util=require('game.util'),
                trainUpgradeBalance={},lootProgression=Loot,writeSave=function() error('must not write repair') end,
                useBattleHealingItem=function() end,useBattlePotion=function() end})
            assert(actions.beginWeaponRepair(weapons.host).ok)
            local flushed,queued=0,false
            local persistence=require('game.persistence_runtime').new({runtime=runtime,session=session,
                ui={cancelWeaponRepair=actions.cancelWeaponRepair},save={
                    schedule=function(slot,value) assert(slot==1 and value==data); queued=true; return true end,
                    flush=function() assert(queued); flushed=flushed+1; return true end},
                maintenance={},maintenanceSession={},focusMobile=function() end,focusAudio=function() end,shutdownAudio=function() end})
            assert(persistence.focus(false) and flushed==1)
            runtime.animationClock=21
            assert(actions.repairWeapon(weapons.host,'perfect').reason=='lease_expired')
            assert(data.scrap==700 and condition('host')==20)
            assert(actions.beginWeaponRepair(weapons.host).ok)
            actions.cancelWeaponRepair(); assert(actions.beginWeaponRepair(weapons.host).ok)
        ''')


if __name__ == '__main__':
    unittest.main()
