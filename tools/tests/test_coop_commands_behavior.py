"""Command wire bounds and result ownership, without accessing game saves."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class CommandWireTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            P=require('game.net.protocol'); Wire=require('game.net.commands')
            function request()
                return P.message('command',{sessionId=string.rep('s',64),requestId=2147483647,
                    sceneEpoch=2147483647,command='player.car',args={car=32},expected={['player:companion']=2147483647}})
            end
        ''')

    def test_actor_claims_unknown_fields_nested_payloads_and_oversize_are_rejected(self):
        self.lua.execute('''
            local m=request(); assert(Wire.request(m) and #assert(P.encode(m,P.CONTROL))<=1200)
            m.actorId='host'; assert(not Wire.request(m)); m=request()
            m.args.payload=string.rep('x',1201); assert(not Wire.request(m)); m=request()
            local next=m.args; for _=1,12 do next.inner={}; next=next.inner end
            assert(not Wire.request(m)); m=request()
            m.expected={}; for i=1,13 do m.expected['scope'..i]=0 end; assert(not Wire.request(m))
        ''')

    def test_command_outcome_never_serializes_domain_results_or_private_fields(self):
        self.lua.execute('''
            local m=assert(Wire.outcome('session',1,{ok=true,durable=true,revision=5,
                result={secret='private',huge=string.rep('x',1000000)},revisions={party=5},internal='hidden'}))
            local encoded=assert(P.encode(m,P.CONTROL))
            assert(#encoded<400 and not encoded:find('private') and not encoded:find('hidden'))
            assert(not m.result and not m.revisions and Wire.result(assert(P.decode(encoded,P.CONTROL))))
            assert(not Wire.outcome('session',1,{ok=true,durable=true,savePending=true,revision=5}))
            assert(not Wire.outcome('session',1,{ok=true,durable=false}))
        ''')

    def test_failure_metadata_is_bounded_and_admission_cannot_reset_sequence(self):
        self.lua.execute('''
            local m=assert(Wire.outcome('session',2,{ok=false,reason=string.rep('x',1000)}))
            assert(m.reason=='command_rejected' and not m.durable and not m.savePending)
            for _,id in ipairs({0,-1,2147483648,1.5}) do
                assert(not Wire.ready(P.message('commands_ready',{sessionId='session',nextRequestId=id})))
            end
            assert(Wire.ready(P.message('commands_ready',{sessionId='session',nextRequestId=2147483647})))
            m.actorId='host'; assert(not Wire.result(m))
        ''')

    def test_item_results_project_only_actual_public_facts_and_fit_control_packets(self):
        self.lua.execute('''
            local cases={
                {'inventory.swap',{moved=true}},
                {'storage.transfer',{moved=true}},
                {'mailbox.collect',{item='rocks',amount=8}},
                {'inventory.consume',{item='mushroom-stew',gained={food=5,water=1}}},
                {'inventory.consume',{item='rose-heart-arrow',heart=true}},
                {'inventory.consume',{item='green-potion-vial',potion=true}},
                {'loot.drop',{item='frontier-short-sword',entityId='drop-1'}},
                {'loot.pickup',{item='rocks',amount=12}}}
            for _,case in ipairs(cases) do
                case[2].secret='private'; case[2].campaign=string.rep('x',10000)
                if case[2].gained then case[2].gained.private=100 end
                local m=assert(Wire.outcome(string.rep('s',64),2147483647,
                    {ok=true,durable=true,revision=2147483647,result=case[2]},case[1]))
                local bytes=assert(P.encode(m,P.CONTROL)); assert(#bytes<=1200 and not bytes:find('private') and not bytes:find('campaign'))
                assert(m.command==case[1] and Wire.result(assert(P.decode(bytes,P.CONTROL))))
            end
        ''')

    def test_item_results_reject_forged_details_nonfinite_gains_and_missing_outcomes(self):
        self.lua.execute('''
            local m=assert(Wire.outcome('session',1,{ok=true,durable=true,revision=1,
                result={item='field-bandage-roll',gained={health=5}}},'inventory.consume'))
            m.details.gained.health=0/0; assert(not Wire.result(m))
            m.details.gained.health=math.huge; assert(not Wire.result(m))
            m.details.gained.health=-1; assert(not Wire.result(m))
            m.details.gained.health=5; m.details.gained.scrap=9; assert(not Wire.result(m))
            m.details.gained.scrap=nil; m.details.secret='x'; assert(not Wire.result(m))
            m.details=nil; assert(not Wire.result(m))
            assert(not Wire.outcome('session',1,{ok=true,durable=true,revision=1,result={}},'loot.drop'))
            assert(not Wire.outcome('session',1,{ok=true,durable=true,revision=1,result={item='rocks'}},'mailbox.collect'))
            m.ok=false; m.reason='stale_item'; m.durable=false; assert(Wire.result(m))
            m.details={item='field-bandage-roll',gained={health=5}}; assert(not Wire.result(m))
        ''')


if __name__ == '__main__':
    unittest.main()
