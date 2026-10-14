"""Detached leased train panels, host progress, timing, cleanup and public outcomes."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestActivityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Catalog=require('game.catalog')
            Players=require('game.coop_players'); Items=require('game.item_instances'); Codec=require('game.net.codec')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'; data.stopped=true
            data.maintenance={condition=40,lastServicedStop=0,totalServices=0,totalWear=0}
            Items.get(Players.forActor(data,'companion'),nil,{kind='equipment',index=1}).durability=67
            copy=Schema.copy(data); copy.itemIdentity=nil; runtime={saveData=Players.forActor(copy,'companion'),scene='train',state='game',player={x=300,y=400}}
            allowed=true; requests={}; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,elapsed=10,focused=true,inventory={},trade={},train={},objects={},people={},
                controller={network=network},actionsAllowed=function() return allowed end,neutralize=function() end}
            panel=require('game.coop_guest_activities').new(view,{catalog=Catalog,colors={}})
            love={keyboard={isDown=function() return false end},mouse={setVisible=function() end}}
            Maintenance=require('game.maintenance'); Maintenance.prepareArt=function(s) s.assets={} end
            function result(id,details,revision)
                network.lastCommandResult={requestId=id,ok=true,details=details,revision=revision or copy.coop.revision}
            end
            function equal(a,b)
                if type(a)~='table' then return a==b end
                if type(b)~='table' then return false end
                for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end; return true
            end
            function acquireMaintenance()
                assert(panel:open('maintenance')); result(#requests,{leaseId='l1',targetDoses={0,0,0},completed=false}); panel:update()
            end
            function acquireRepair()
                assert(panel:open('weaponRepair')); assert(panel:startRepair()); view.elapsed=10.1
                result(#requests,{leaseId='l1',elapsed=0,expiresIn=30}); panel:update()
            end
        ''')

    def test_maintenance_only_applies_host_doses_and_draws_a_detached_display(self):
        self.lua.execute('''
            local before=assert(Schema.copy(copy)); local original=assert(Schema.copy(data)); acquireMaintenance(); assert(panel.lease=='l1' and panel.session.targetDoses[1]==0)
            assert(panel:service(1) and panel.session.targetDoses[1]==0)
            assert(requests[2].args.target==1 and not requests[2].args.progress and requests[2].expected['activity:train:maintenance']==0)
            result(2,{success=true,targetDoses={1,0,0}}); panel:update(); assert(panel.session.targetDoses[1]==1)
            Maintenance.draw=function(s,display)
                assert(display~=runtime.saveData and display.maintenance~=copy.maintenance and display.resources~=copy.resources)
                display.resources.oil=0; display.maintenance.condition=0; display.accessibility.textScale=7
            end
            panel.c.colors.cream={}; love.graphics={setColor=function() end}; panel:draw()
            assert(equal(copy,before) and equal(data,original))
        ''')

    def test_maintenance_checkpoint_wait_and_obsolete_scene_do_not_complete_locally(self):
        self.lua.execute('''
            acquireMaintenance(); panel.session.targetDoses={2,1,2}; assert(panel:completeMaintenance())
            assert(requests[2].expected.resources==0 and requests[2].expected.train==0)
            network.lastCommandResult={requestId=2,ok=false,reason='save_pending',savePending=true}; panel:update()
            assert(panel.pending and not panel.session.completed and copy.maintenance.condition==40)
            result(2,{success=true,before=40,condition=80,cost=5},4); panel:update(); assert(panel.pending)
            view.epoch=view.epoch+1; copy.coop.revision=4; panel:update()
            assert(not runtime.guestActivityOpen and not panel.pending and not panel.lease and #requests==2 and copy.maintenance.condition==40)
        ''')

    def test_repair_timing_is_presentational_and_complete_carries_no_quality_or_clock(self):
        self.lua.execute('''
            local id=runtime.saveData.itemSlots.equipment[1].id; acquireRepair()
            assert(requests[1].name=='weaponRepair.acquire' and requests[1].args.itemId==id and requests[1].expected['player:companion']==0)
            view.elapsed=10.65; assert(panel:phase()>.50 and panel:phase()<.60); assert(panel:startRepair())
            local args=requests[2].args; assert(args.leaseId=='l1' and not args.quality and not args.elapsed and not args.startedAt)
            result(2,{success=true,name='frontier-short-sword',cost=10,quality='good',restored=90}); panel:update()
            assert(not panel.lease and panel.notice:find('90%%') and runtime.saveData.itemSlots.equipment[1].durability==67)
            assert(copy.itemSlots.equipment[1].durability==67 and data.players.companion.itemSlots.equipment[1].durability==67)
        ''')

    def test_close_during_acquisition_releases_returned_lease_and_retries_cleanup(self):
        self.lua.execute('''
            assert(panel:open('maintenance')); panel:suspend(); assert(panel.wantRelease)
            result(1,{leaseId='l1',targetDoses={0,0,0},completed=false}); panel:update()
            assert(requests[2].name=='activity.release' and requests[2].args.leaseId=='l1' and not runtime.guestActivityOpen)
            network.lastCommandResult={requestId=2,ok=false,reason='rate_limited'}; panel:update(); assert(panel.lease and panel.wantRelease)
            view.elapsed=view.elapsed+.7; panel:update(); assert(requests[3].name=='activity.release')
            result(3,{released=true,leaseId='l1'}); panel:update(); assert(not panel.lease and not panel.wantRelease and not panel.session)
        ''')

    def test_repair_renewal_preserves_host_elapsed_and_delayed_reply_requires_sync(self):
        self.lua.execute('''
            assert(panel:open('weaponRepair') and panel:startRepair()); view.elapsed=11
            result(1,{leaseId='l1',elapsed=0,expiresIn=30}); panel:update(); assert(panel.clockUncertain)
            assert(panel:startRepair() and requests[2].name=='weaponRepair.step' and requests[2].args.renew==true)
            view.elapsed=11.1; result(2,{leaseId='l1',elapsed=1.1,expiresIn=30}); panel:update()
            assert(not panel.clockUncertain and panel.anchorElapsed>1.1 and panel.lease=='l1')
            view.elapsed=21.2; panel:update(); assert(requests[3].name=='weaponRepair.step')
            assert(not requests[3].args.elapsed and not requests[3].args.duration)
        ''')

    def test_focus_menu_car_and_health_cleanup_with_other_modal_exclusion(self):
        self.lua.execute('''
            runtime.peopleOpen=true; assert(not panel:open('maintenance')); runtime.peopleOpen=false
            view.objects.pending={}; assert(not panel:open('weaponRepair')); view.objects.pending=nil
            runtime.saveData.health=0; assert(not panel:open('maintenance')); runtime.saveData.health=20
            acquireMaintenance(); view.focused=false; panel:update(); assert(not runtime.guestActivityOpen and requests[2].name=='activity.release')
            result(2,{released=true,leaseId='l1'}); panel:update(); view.focused=true
            assert(panel:open('maintenance')); result(3,{leaseId='l2',targetDoses={0,0,0},completed=false}); panel:update()
            runtime.saveData.activeCar=2; panel:update(); assert(not panel.lease and not runtime.guestActivityOpen and #requests==3)
        ''')

    def test_stale_supplies_allow_review_without_abandoning_valid_progress(self):
        self.lua.execute('''
            acquireMaintenance(); panel.session.targetDoses={2,1,2}; assert(panel:completeMaintenance())
            network.lastCommandResult={requestId=2,ok=false,reason='stale_revision'}; panel:update()
            assert(panel.lease=='l1' and runtime.guestActivityOpen and panel.session.targetDoses[1]==2)
            copy.coop.revisions.resources=6; assert(panel:completeMaintenance() and requests[3].expected.resources==6)
            result(3,{success=false,reason='oil'}); panel:update(); assert(panel.lease and not panel.session.completed)
        ''')

    def test_replica_without_allocation_counter_distinguishes_duplicate_owned_weapons(self):
        self.lua.execute('''
            assert(not runtime.saveData.itemIdentity)
            runtime.saveData.inventory[3]=runtime.saveData.equipment[1]
            runtime.saveData.itemSlots.inventory=runtime.saveData.itemSlots.inventory or {}
            runtime.saveData.itemSlots.inventory[3]={id='i10000',name=runtime.saveData.equipment[1],durability=42}
            local weapons=Items.weapons(runtime.saveData,Catalog); local found=0
            for _,e in ipairs(weapons) do if e.name==runtime.saveData.equipment[1] then found=found+1 end end
            assert(found==2)
            local status=require('game.loot_progression').repairStatus(runtime.saveData,Catalog,'i10000')
            assert(status.itemId=='i10000' and status.durability==42 and status.ref.index==3)
            assert(panel:open('weaponRepair') and panel:select('i10000') and panel:startRepair())
            assert(requests[1].args.itemId=='i10000' and not copy.itemIdentity)
        ''')

    def test_timing_uses_monotonic_device_clock_when_animation_frames_stop(self):
        self.lua.execute('''
            local now=50; panel.c.clock=function() return now end
            assert(panel:open('weaponRepair') and panel:startRepair()); now=50.1
            result(1,{leaseId='l1',elapsed=0,expiresIn=30}); panel:update()
            now=50.7; assert(panel:phase()>.54 and panel:phase()<.58 and view.elapsed==10)
        ''')

    def test_public_activity_dtos_filter_sessions_items_and_validate_progress(self):
        self.lua.execute('''
            local R=require('game.net.item_results')
            local d=assert(R.project('maintenance.acquire',{leaseId='l1',targetDoses={1,0,2},completed=false,payload={actorId='host'},session={}}))
            assert(d.targetDoses[1]==1 and not d.session and not d.payload); assert(not R.valid('maintenance.acquire',{leaseId='l1',targetDoses={3,0,0},completed=false}))
            local e=assert(R.project('weaponRepair.complete',{ok=false,reason='miss',status={itemId='private'},cost=100})); assert(not e.success and e.reason=='miss' and not e.status and not e.cost)
            assert(not R.valid('weaponRepair.complete',{success=false,reason='miss',restored=100}))
            local t=assert(R.project('weaponRepair.acquire',{leaseId='l1',elapsed=0,expiresIn=30,startedAt=999,expiresAt=1029,itemId='private'})); assert(not t.startedAt and not t.itemId)
            assert(not R.valid('weaponRepair.step',{leaseId='l1',elapsed=1,expiresIn=31}))
        ''')


if __name__ == '__main__':
    unittest.main()
