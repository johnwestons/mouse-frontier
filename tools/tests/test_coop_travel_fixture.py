"""Headless checks of real ENet fixture observations; no native apps launch."""
from pathlib import Path
import os
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class TravelFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            TRAVEL_FIXTURE_HELPERS=true
            H=assert(loadfile(root..'/tools/guest-travel-smoke/main.lua'))()
        ''')

    def test_fixture_and_conf_compile_without_starting_engine(self):
        self.lua.execute('''
            assert(loadfile(root..'/tools/guest-travel-smoke/conf.lua'))
            assert(loadfile(root..'/tools/guest-travel-smoke/main.lua'))
            assert(love==nil)
        ''')

    def test_campaign_fingerprint_is_order_independent_and_detects_nested_mutation(self):
        self.lua.execute('''
            local a={resources={coal=3,food=4},players={host={inventory={[2]='a'}}},coop={randomState=8}}
            local b={coop={randomState=8},players={host={inventory={[2]='a'}}},resources={food=4,coal=3}}
            assert(H.canonical(a)==H.canonical(b))
            b.players.host.inventory[2]='b';assert(H.canonical(a)~=H.canonical(b))
            b.players.host.inventory[2]='a';b.coop.randomState=9;assert(H.canonical(a)~=H.canonical(b))
        ''')

    def test_cost_equality_compares_every_host_derived_cost_and_resource_field(self):
        self.lua.execute('''
            local keys={'from','to','food','water','coal','terrain','sourceRevision','passengers',
                'passengerLoad','maintenanceCoal','navigatorSaved','affordable'}
            local a={available={food=4,water=5,coal=6},missing={food=0,water=0,coal=0}}
            local b={available={food=4,water=5,coal=6},missing={food=0,water=0,coal=0}}
            for _,key in ipairs(keys)do a[key]=1;b[key]=1 end
            assert(H.costEqual(a,b))
            for _,key in ipairs(keys)do b[key]=2;assert(not H.costEqual(a,b));b[key]=1 end
            b.available.coal=7;assert(not H.costEqual(a,b));b.available.coal=6
            b.missing.food=1;assert(not H.costEqual(a,b))
        ''')

    def test_freshness_gate_rejects_wrong_session_epoch_motion_serial_domain_and_stale_input(self):
        self.lua.execute('''
            function fresh()
                return {network={status='ready',sessionId='s'},clientView={ready=true,epoch=7,
                    motionId=8,lastSerial=9,modalDomain='d',prediction={stale=function()return false end}},
                    motionFrame={ready=true,sessionId='s',sceneEpoch=7,motionId=8,serial=9,domain='d'}}
            end
            assert(H.ready(fresh()))
            for _,key in ipairs({'sessionId','sceneEpoch','motionId','serial','domain'})do
                local lp=fresh();lp.motionFrame[key]='wrong';assert(not H.ready(lp))
            end
            local lp=fresh();lp.clientView.prediction.stale=function()return true end;assert(not H.ready(lp))
            lp=fresh();lp.network.closed=true;assert(not H.ready(lp))
        ''')

    def test_diagnostics_identify_nested_changes_without_exposing_values_or_credentials(self):
        self.lua.execute('''
            local a={players={companion={playerFacing=false}},coop={network={credentialHash='PRIVATE_A'}}}
            local b={players={companion={playerFacing=1}},coop={network={credentialHash='PRIVATE_B'}}}
            local paths=H.diffPaths(a,b)
            assert(#paths==2 and paths[1]=='campaign.coop.network.credentialHash')
            assert(paths[2]=='campaign.players.companion.playerFacing')
            for _,path in ipairs(paths)do assert(not path:find('PRIVATE',1,true))end
            assert(#H.diffPaths(a,a)==0)
        ''')

    def test_host_settling_requires_admitted_matching_generation_ready_motion_and_quiet_input(self):
        self.lua.execute('''
            function host()
                return {authority={bindings={companion=4},campaign={coop={sceneEpoch=7}}},
                    network={link={admitted=true,phase='ready',generation=4}},
                    motion={generation=4,readyEpoch=7,actor={moving=false},input={x=0,y=0}}}
            end
            assert(H.hostSettled(host()))
            local changes={function(p)p.authority.pendingSave={}end,
                function(p)p.network.link.phase='acknowledging'end,
                function(p)p.motion.readyEpoch=nil end,function(p)p.motion.generation=3 end,
                function(p)p.authority.bindings.companion=3 end,
                function(p)p.motion.actor.moving=true end,function(p)p.motion.input.x=1 end}
            for _,change in ipairs(changes)do local p=host();change(p);assert(not H.hostSettled(p))end
        ''')

    def test_real_idle_motion_can_persist_first_facing_after_ready_frame_before_any_request(self):
        self.lua.execute('''
            local now=0
            local data={coop={sceneEpoch=1},players={host={activeCar=1,playerX=20,playerY=30},
                companion={character='cook-mouse.png',health=20,activeCar=1,playerX=100,playerY=100}}}
            local before=H.canonical(data)
            local m=require('game.coop_movement').host({campaign=data,clock=function()return now end,
                hostActor=function()return {x=20,y=30,facing=1}end,allowed=function()return true end,
                move=function(_,_,_,_,x,y)return x,y end})
            m:admit(7);assert(m:ready(7,1,m.motionId))
            assert(m:snapshot('host-session').ready and data.players.companion.playerFacing==nil)
            now=require('game.net.movement').STEP;assert(m:update())
            assert(data.players.companion.playerFacing==1 and H.canonical(data)~=before)
            assert(data.players.companion.playerX==100 and data.players.companion.playerY==100)
            local stable=H.canonical(data);now=now+.5;assert(m:update());assert(H.canonical(data)==stable)
        ''')

    def test_intentional_replays_are_paced_under_actual_transport_bucket_inside_domain_cooldown(self):
        self.lua.execute('''
            local rate=require('game.net.command_rate');local link={};local last
            local sends={0,.61,1.22,1.83,2.44,3.05}
            -- inspect, request, exact replay, same-pending new ID, dismissed
            -- exact replay, and the intentional domain cooldown rejection.
            for index,now in ipairs(sends)do
                assert(H.wireReady(now,last))
                assert(rate.allow(link,{command='progression.request',args={}},now))
                last=now
            end
            assert(sends[6]-sends[2]<require('game.coop_travel_requests').COOLDOWN)
            assert(not H.wireReady(last+.59,last) and H.wireReady(last+.61,last))
            local burst={}
            for _=1,4 do assert(rate.allow(burst,{command='progression.request',args={}},0))end
            assert(not rate.allow(burst,{command='progression.request',args={}},0))
        ''')


if __name__=='__main__':unittest.main()
