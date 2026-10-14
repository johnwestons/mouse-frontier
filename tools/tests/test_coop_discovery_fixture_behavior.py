"""The native discovery fixture must observe a new link before claiming resume."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class DiscoveryFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        source = (ROOT / 'tools/guest-discovery-smoke/main.lua').read_text(encoding='utf-8')
        body = source.split('local function guestUpdate(lp)', 1)[1].split('local function update(dt)', 1)[0]
        self.lua.execute('''
            love={timer={getTime=function() return 10 end}}
            stage='reconnect';identity='existing-companion';sawReconnect=false;captures={};markers={['host.dropped']='true'}
            function read(name) return markers[name] end
            function marker(name,value) markers[name]=tostring(value or true) end
            function check(value,message) assert(value,message) end
            function click() error('unexpected control') end
            old={status='ready'};new={status='connecting'};initialNetwork=old
            lp={network=old,clientView={ready=true},replica={data={players={companion={id=identity}}}},
                discoveredHosts=function() return {} end,reconnectStatus=function() return {active=active==true} end}
        ''' + 'function guestUpdate(lp)' + body)

    def test_drop_marker_does_not_accept_old_ready_connection_before_disconnect_arrives(self):
        self.lua.execute('''
            guestUpdate(lp); assert(stage=='reconnect' and not markers['guest.reconnected'])
            markers['host.connected']='1';markers['host.reconnected']='2';sawReconnect=true
            guestUpdate(lp); assert(stage=='reconnect' and not markers['guest.reconnected'])
            lp.network=nil;lp.clientView=nil;active=true;guestUpdate(lp)
            assert(sawReconnect and stage=='reconnect' and capture=='guest-reconnect.png')
        ''')

    def test_new_ready_link_requires_host_admission_and_preserves_same_companion(self):
        self.lua.execute('''
            active=true;guestUpdate(lp);active=false
            lp.network=new;new.status='ready'
            guestUpdate(lp);assert(stage=='reconnect')
            markers['host.connected']='1';markers['host.reconnected']='2'
            guestUpdate(lp);assert(stage=='done' and markers['guest.reconnected']=='true')
        ''')

    def test_identity_generation_and_observed_reconnect_assertions_remain_strict(self):
        self.lua.execute('''
            markers['host.connected']='1';markers['host.reconnected']='2';lp.network=new;new.status='ready'
            assert(not pcall(guestUpdate,lp)) -- no observed reconnect
            sawReconnect=true;lp.replica.data.players.companion.id='replacement'
            assert(not pcall(guestUpdate,lp))
            lp.replica.data.players.companion.id=identity;markers['host.reconnected']='1'
            assert(not pcall(guestUpdate,lp))
            assert(not markers['guest.reconnected'] and stage=='reconnect')
        ''')


if __name__ == '__main__':
    unittest.main()
