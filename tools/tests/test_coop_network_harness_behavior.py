"""Verify the imported transport lab before using it as session evidence."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopNetworkHarnessTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Lab=require('tools.tests.lua.coop_network_harness')
            lab=assert(Lab.new())
            host=assert(lab.factory.createHost({}))
            guest=assert(lab.factory.createClient('test-host',{}))
            assert(#host:service(64)==1 and #guest:service(64)==1)
        ''')

    def tearDown(self):
        self.lua.execute("assert(lab:dispose() and lab:isQuiescent())")

    def test_two_player_capacity_and_rejoin_identity_generation(self):
        self.lua.execute('''
            assert(not lab.factory.createClient('extra-guest',{}))
            local oldPeer=lab:peer(1)
            assert(guest:close())
            local events=host:service(64)
            assert(#events==1 and events[1].type=='disconnect')
            guest=assert(lab.factory.createClient('test-host',{}))
            assert(lab:peer(1)~=oldPeer)
            assert(not host:send(oldPeer,'stale',0,true))
            assert(#host:service(64)==1 and #guest:service(64)==1)
        ''')

    def test_unreliable_loss_reordering_and_duplicate_delivery(self):
        self.lua.execute('''
            lab:dropNext('client_to_host',1)
            assert(guest:sendToServer('lost',1,false))
            assert(#host:service(64)==0)
            lab:delayNext('client_to_host',1,3)
            assert(guest:sendToServer('older',1,false))
            lab:duplicateNext('client_to_host',1,1)
            assert(guest:sendToServer('newer',1,false))
            local events=host:service(64)
            assert(#events==2 and events[1].data=='newer' and events[2].data=='newer')
            lab:advanceSteps(3)
            events=host:service(64)
            assert(#events==1 and events[1].data=='older')
        ''')

    def test_reliable_order_is_per_channel_and_application_replay_is_explicit(self):
        self.lua.execute('''
            lab:delayNext('client_to_host',1,4)
            assert(guest:sendToServer('first',0,true))
            assert(guest:sendToServer('second',0,true))
            assert(guest:sendToServer('baseline',2,true))
            local events=host:service(64)
            assert(#events==1 and events[1].data=='baseline')
            lab:advanceSteps(4)
            events=host:service(64)
            assert(#events==2 and events[1].data=='first' and events[2].data=='second')
            lab:duplicateNext('client_to_host',1,1,true)
            assert(guest:sendToServer('retry',0,true))
            assert(#host:service(64)==2)
            lab:dropNext('client_to_host',1)
            assert(not guest:sendToServer('impossible-reliable-loss',0,true))
        ''')


if __name__ == '__main__':
    unittest.main()
