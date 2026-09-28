"""Check weighted supply-task variety and its saved run state."""
from pathlib import Path
import os
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get("LUA_RUNTIME_PYTHONPATH",str(ROOT/".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class SupplyDeliveryRotationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute("""
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Q=require('game.quest_progression')
            Schema=require('game.save_schema')
        """)

    def test_first_offer_keeps_the_authored_progression_weights(self):
        self.lua.execute("""
            local fresh={seen={}}
            assert(Q.rollDelivery(1,function() return .05 end,fresh)=='food')
            assert(Q.rollDelivery(1,function() return .31 end,{seen={}})=='water')
            local late={seen={}}
            assert(Q.rollDelivery(49,function() return .01 end,late)=='food')
            assert(Q.rollDelivery(49,function() return .50 end,{seen={}})=='repair')
        """)

    def test_each_six_offer_cycle_covers_every_cargo_once(self):
        self.lua.execute("""
            for seed=1,80 do
                math.randomseed(seed)
                local data=assert(Schema.migrate({character='frog',location=1}))
                local rotation=data.supplyDeliveryCycle
                local prior
                for cycle=1,3 do
                    local seen={}
                    for index=1,6 do
                        local kind=Q.rollDelivery(1+cycle*12,math.random,rotation)
                        assert(not seen[kind],'cargo repeated inside a six-offer cycle')
                        assert(not (index==1 and kind==prior),'cycle boundary repeated the previous cargo')
                        seen[kind]=true; prior=kind
                        if cycle==1 and index==3 then
                            data=assert(Schema.migrate(data))
                            rotation=data.supplyDeliveryCycle
                        end
                    end
                    local count=0
                    for _ in pairs(seen) do count=count+1 end
                    assert(count==#Q.deliveryKinds)
                end
            end
        """)

    def test_legacy_save_seeds_rotation_from_last_visible_cargo_offer(self):
        self.lua.execute("""
            local data=assert(Schema.migrate({version=35,character='frog',location=25,stopLayouts={
                ['24']={deliveryOffers={resident='ammunition'}},
            }}))
            assert(data.supplyDeliveryCycle.last=='ammunition')
            local kind=Q.rollDelivery(25,function() return .99 end,data.supplyDeliveryCycle)
            assert(kind~='ammunition')
            assert(data.supplyDeliveryCycle.last==kind)
        """)

    def test_bad_rotation_entries_are_ignored_and_save_shape_is_enforced(self):
        self.lua.execute("""
            local rotation={seen={'food','food','invalid','water'}}
            local kind=Q.rollDelivery(20,function() return .5 end,rotation)
            assert(kind~='food' and kind~='water')
            assert(Schema.validate(assert(Schema.migrate({character='frog'}))))
            assert(not Schema.migrate({character='frog',supplyDeliveryCycle='broken'}))
        """)


if __name__=='__main__':
    unittest.main()
