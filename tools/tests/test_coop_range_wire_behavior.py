"""Range transport bounds and the production host adapter's simulation barrier."""
import unittest
import test_coop_range_behavior as ranges


class RangeWireTests(unittest.TestCase):
    setUp = ranges.RangeCommandTests.setUp
    range = ranges.RangeCommandTests.range

    def test_public_results_reject_private_claims_wrong_capacity_and_nonfinite_values(self):
        self.range()
        self.lua.execute('''
            local good=assert(Results.project('range.acquire',assert(acquire('host')).result))
            assert(Results.valid('range.acquire',good))
            local function bad(key,value)
                local copy=assert(Schema.copy(good)); copy[key]=value
                assert(not Results.valid('range.acquire',copy),key)
            end
            bad('targets',{}); bad('aimX',400); bad('actorId','stranger'); bad('loaded',13)
            bad('rounds',math.huge); bad('expiresIn',31); bad('leaseId','e1')
            bad('roundRevision',0); bad('fireMode','invented')
            local raw=assert(Schema.copy(good)); raw.targets={secret=true}; raw.aimX=400
            local clean=assert(Results.project('range.acquire',raw)); assert(not clean.targets and not clean.aimX)
        ''')

    def test_range_fire_uses_gun_budget_while_purchases_retain_discrete_budget(self):
        self.lua.execute('''
            local Rate=require('game.net.command_rate'); local gun,shop={},{}
            for i=1,4 do assert(Rate.allow(gun,{command='range.fire'},0)); assert(Rate.allow(shop,{command='range.ammo'},0)) end
            assert(not Rate.allow(gun,{command='range.fire'},0)); assert(not Rate.allow(shop,{command='range.ammo'},0))
            assert(Rate.allow(gun,{command='range.fire'},.1)); assert(not Rate.allow(shop,{command='range.ammo'},.1))
            assert(Rate.allow(shop,{command='range.ammo'},.5))
        ''')

    def adapter(self):
        self.range()
        self.lua.execute('''
            local Runtime=require('game.coop_inventory_runtime')
            runtime={saveData=data,state='game',scene='stop',animationClock=0,player={x=spot.x,y=spot.y}}
            session={canWriteCampaign=function() return true end,syncSceneEpoch=function() end}
            fail=false; writes=0
            data.coop.randomState=728431
            adapter=Runtime.new({runtime=runtime,session=session,catalog=Catalog,clock=function() return clock end,
                actorState=function(id) return states[id] end,
                rangeState=function(id) return readiness[id] end,
                checkpoint=function() writes=writes+1; return not fail end})
            adapter.setRemoteActorState(function() return states.companion end)
            service=assert(adapter.authority()); service:admit('companion',1)
            local h=assert(adapter.submit('range.acquire',{spotId=spot.entityId})); assert(h.ok)
            leases.host=h.result.leaseId
            local a=request('companion','range.acquire'); local q=assert(service:prepareRequest('companion','range.acquire',a))
            local g=adapter.remote(1,q); assert(g.ok); leases.companion=g.result.leaseId
            assert(adapter.submit('range.configure',request('host','range.configure',{action='start'})).ok)
            local q=assert(service:prepareRequest('companion','range.configure',request('companion','range.configure',{action='start'})))
            assert(adapter.remote(1,q).ok)
        ''')

    def test_runtime_tick_advances_once_without_invalidating_actor_action_scopes(self):
        self.adapter()
        self.lua.execute('''
            local rev=data.coop.revision
            local expected=assert(service:prepareRequest('companion','range.fire',request('companion','range.fire',{x=500000,y=500000}))).expected
            clock=clock+.08; assert(adapter.advanceRange(.08))
            assert(math.abs(lane('host').time-44.92)<1e-8 and math.abs(lane('companion').time-44.92)<1e-8)
            assert(data.coop.revision==rev+1)
            for scope,value in pairs(expected) do assert((data.coop.revisions[scope] or 0)==value) end
            readiness.host.paused=true; local own=lane('host').time; clock=clock+.08
            assert(adapter.advanceRange(.08)); assert(lane('host').time==own and lane('companion').time<own)
            assert(adapter.rangeView('host').leaseId==leases.host)
        ''')

    def test_runtime_pending_save_freezes_both_lanes_until_retry(self):
        self.adapter()
        self.lua.execute('''
            fail=true
            local shot=adapter.submit('range.fire',request('host','range.fire',{x=500000,y=500000}))
            assert(shot.ok and shot.savePending and adapter.checkpointStatus().pending)
            local h,g=lane('host').time,lane('companion').time
            clock=clock+.08; assert(not adapter.advanceRange(.08))
            assert(lane('host').time==h and lane('companion').time==g and not adapter.rangeView('host'))
            fail=false; assert(adapter.retryCheckpoint()); clock=clock+.08; assert(adapter.advanceRange(.08))
            assert(lane('host').time<h and lane('companion').time<g)
        ''')


if __name__ == '__main__':
    unittest.main()
