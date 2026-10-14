"""Maintenance progress and once-per-stop costs belong to the host authority."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopMaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Authority=require('game.coop_authority'); Rules=require('game.maintenance_rules')
            Schema=require('game.save_schema')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data)); data.stopped=true
            data.resources.oil=10; data.maintenance={condition=20,totalServices=0,lastServicedStop=0}
            now=0; states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
            service=Authority.new({campaign=data,sessionId='maintenance',clock=function() return now end})
            require('game.coop_activities').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1)
            function request(actor,name,args) return assert(service:prepareRequest(actor,name,args)) end
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function acquire(actor) return assert(run(actor,'maintenance.acquire',{}).result).leaseId end
            function oil(actor,lease)
                for _,target in ipairs({1,1,2,3,3}) do
                    local reply=run(actor,'maintenance.step',{leaseId=lease,target=target})
                    assert(reply.ok and reply.result.ok)
                end
            end
        ''')

    def test_guest_services_shared_train_once_and_replay_is_exact(self):
        self.lua.execute('''
            local lease=acquire('companion')
            assert(run('host','maintenance.acquire',{}).reason=='activity_busy')
            oil('companion',lease)
            assert(data.resources.oil==10 and data.maintenance.condition==20)
            local req=request('companion','maintenance.complete',{leaseId=lease})
            local reply=execute('companion',req)
            assert(reply.ok and reply.result.ok and reply.result.cost==5)
            assert(data.resources.oil==5 and data.maintenance.condition==60 and data.maintenance.totalServices==1)
            assert(execute('companion',req).result.ok and data.resources.oil==5)
            assert(not next(service.activityState.resources) and data.location==1 and data.scene=='train')
            local host=acquire('host')
            assert(run('host','maintenance.complete',{leaseId=host}).result.reason=='already')
            assert(data.resources.oil==5 and data.maintenance.totalServices==1)
            assert(Schema.migrate(data).maintenance.lastServicedStop==1)
        ''')

    def test_incomplete_progress_forged_cost_and_foreign_lease_cannot_finish(self):
        self.lua.execute('''
            local lease=acquire('host')
            assert(run('companion','maintenance.complete',{leaseId=lease}).reason=='lease_owner')
            assert(run('host','maintenance.complete',{leaseId=lease,cost=0}).reason=='invalid_args')
            assert(run('host','maintenance.step',{leaseId=lease,target=1.5}).reason=='invalid_args')
            assert(run('host','maintenance.step',{leaseId=lease,target=1,renew=true}).reason=='invalid_args')
            assert(run('host','maintenance.complete',{leaseId=lease}).result.reason=='progress')
            assert(data.resources.oil==10 and data.maintenance.condition==20)
        ''')

    def test_replayed_click_full_hub_and_reserve_shortage_do_not_add_doses(self):
        self.lua.execute('''
            local lease=acquire('companion')
            local req=request('companion','maintenance.step',{leaseId=lease,target=1})
            assert(execute('companion',req).result.targetDoses[1]==1)
            assert(execute('companion',req).result.targetDoses[1]==1)
            assert(run('companion','maintenance.step',{leaseId=lease,target=1}).result.targetDoses[1]==2)
            assert(run('companion','maintenance.step',{leaseId=lease,target=1}).result.reason=='full')
            data.resources.oil=2
            assert(run('companion','maintenance.step',{leaseId=lease,target=2}).result.reason=='oil')
            assert(Rules.progressCount(service.activityState.resources['train:maintenance'].payload.progress)==2)
            assert(data.resources.oil==2 and data.maintenance.condition==20)
        ''')

    def test_disconnect_cancel_expiry_and_changed_stop_discard_only_unpaid_progress(self):
        self.lua.execute('''
            local lease=acquire('companion'); oil('companion',lease)
            service:disconnect('companion',1)
            local host=acquire('host')
            assert(Rules.progressCount(service.activityState.resources['train:maintenance'].payload.progress)==0)
            oil('host',host); data.location=2
            assert(run('host','maintenance.complete',{leaseId=host}).reason=='activity_unavailable')
            assert(run('host','activity.release',{leaseId=host}).ok)
            host=acquire('host'); oil('host',host); now=31
            assert(run('host','maintenance.complete',{leaseId=host}).reason=='lease_expired')
            assert(data.resources.oil==10 and data.maintenance.totalServices==0)
        ''')

    def test_live_oil_shortage_is_atomic_and_can_be_replenished(self):
        self.lua.execute('''
            local lease=acquire('host'); oil('host',lease); data.resources.oil=4
            assert(run('host','maintenance.complete',{leaseId=lease}).result.reason=='oil')
            assert(data.resources.oil==4 and data.maintenance.totalServices==0 and data.maintenance.condition==20)
            data.resources.oil=8
            assert(run('host','maintenance.complete',{leaseId=lease}).result.ok)
            assert(data.resources.oil==3 and data.maintenance.totalServices==1)
        ''')

    def test_failure_after_payment_rolls_back_service_and_lease(self):
        self.lua.execute('''
            local lease=acquire('host'); oil('host',lease)
            local original=Rules.complete
            Rules.complete=function(...) original(...); error('forced post-service failure') end
            assert(run('host','maintenance.complete',{leaseId=lease}).reason=='handler_error')
            assert(data.resources.oil==10 and data.maintenance.condition==20 and data.maintenance.totalServices==0)
            assert(not service.activityState.resources['train:maintenance'].payload.progress.completed)
            Rules.complete=original
            assert(run('host','maintenance.complete',{leaseId=lease}).result.ok)
        ''')

    def test_domain_rule_also_prevents_two_legacy_sessions_charging_at_same_stop(self):
        self.lua.execute('''
            local first,second=Rules.new(data),Rules.new(data)
            for _,target in ipairs({1,1,2,3,3}) do assert(Rules.point(first,target,data).ok); assert(Rules.point(second,target,data).ok) end
            assert(Rules.complete(first,data).ok)
            assert(Rules.complete(second,data).reason=='already')
            assert(data.resources.oil==5 and data.maintenance.totalServices==1)
        ''')


if __name__ == '__main__':
    unittest.main()
