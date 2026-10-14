"""Headless guards for the native two-app device controls fixture; no apps launch."""
from pathlib import Path
import os
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class DeviceControlsFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            DEVICE_CONTROLS_FIXTURE_HELPERS=true
            H=assert(loadfile(root..'/tools/guest-device-controls-smoke/main.lua'))()
            function ready()
                local data={scene='train',location=1,coop={sceneEpoch=7}}
                local v={ready=true,paused=false,epoch=7,motionId=8,lastSerial=9,
                    runtime={saveData=data},prediction={stale=function()return false end}}
                return {network={status='ready',sessionId='s'},clientView=v,replica={data=data},
                    motionFrame={ready=true,paused=false,sessionId='s',sceneEpoch=7,motionId=8,serial=9}}
            end
        ''')

    def test_compiles_conf_and_runtime_fixture_without_launching_engine(self):
        self.lua.execute('''
            assert(loadfile(root..'/tools/guest-device-controls-smoke/conf.lua'))
            assert(loadfile(root..'/tools/guest-device-controls-smoke/main.lua'))
            assert(type(H.ready)=='function' and type(H.target)=='function')
            assert(love==nil)
        ''')

    def test_hashes_actual_public_host_and_replica_actor_identically_without_reprojecting_replica(self):
        self.lua.execute('''
            love={math={random=math.random}}
            local F=require('tools.tests.lua.coop_fixtures');local S=require('game.net.game_state')
            local data=F.campaign();assert(F.enroll(data))
            local projection=assert(S.project(data))
            local hostBytes=H.publicHash(data,function(bytes) return bytes end)
            local replicaBytes=H.publicHash(projection.view,function(bytes) return bytes end)
            local actor=require('game.coop_players').forActor(projection.view,'companion')
            local actorBytes=H.publicHash(actor,function(bytes) return bytes end)
            assert(type(hostBytes)=='string' and #hostBytes>0 and hostBytes==replicaBytes and actorBytes==hostBytes)
            local decoded=assert(require('game.net.state_records').decode(assert(require('game.net.codec').decode(hostBytes,
                {maxBytes=524288,maxDepth=32,maxEntries=200000,maxStringBytes=8192}))))
            assert(decoded.players.host and decoded.players.companion and not decoded.coop.network)
        ''')

    def test_connected_guest_report_uses_actual_received_state_not_ui_presentation_proxies(self):
        self.lua.execute('''
            love={math={random=math.random}}
            local F=require('tools.tests.lua.coop_fixtures');local S=require('game.net.game_state')
            local data=F.campaign();assert(F.enroll(data));local public=assert(S.project(data)).view
            local presentation={audio=setmetatable({},{__index=function() return 'private-device-setting' end})}
            local lp={clientView={runtime={saveData=presentation}},replica={data=public}}
            assert(H.reportData(lp,presentation)==public)
            assert(H.publicHash(H.reportData(lp,presentation),function(bytes) return #bytes end)>0)
            assert(H.reportData({},data)==data)
        ''')

    def test_ready_requires_exact_fresh_network_scene_generation_and_serial(self):
        self.lua.execute('''
            assert(H.ready(ready()))
            local mutations={function(p)p.network.status='joining'end,
                function(p)p.network.closed=true end,
                function(p)p.clientView.paused=true end,
                function(p)p.clientView.ready=false end,
                function(p)p.motionFrame.ready=false end,
                function(p)p.motionFrame.paused=true end,
                function(p)p.motionFrame.sessionId='old'end,
                function(p)p.motionFrame.sceneEpoch=6 end,
                function(p)p.motionFrame.motionId=7 end,
                function(p)p.motionFrame.serial=8 end,
                function(p)p.motionFrame.domain='changed'end,
                function(p)p.clientView.prediction.stale=function()return true end end,
                function(p)p.replica={data={scene='stop',location=1,coop={sceneEpoch=7}}}end,
                function(p)p.replica={data={scene='train',location=2,coop={sceneEpoch=7}}}end}
            for _,mutate in ipairs(mutations)do local p=ready();mutate(p);assert(not H.ready(p))end
        ''')

    def test_pose_observation_requires_new_correct_actor_serial_and_server_timer(self):
        self.lua.execute('''
            local f={host={stance='idle',poseSerial=4,useRemainingMs=0},
                companion={stance='sit',poseSerial=5,useRemainingMs=0}}
            assert(H.pose(f,'companion','sit',4))
            assert(not H.pose(f,'host','sit',3) and not H.pose(f,'companion','sit',5))
            assert(not H.use(f,'companion',4))
            f.companion={stance='idle',poseSerial=6,useRemainingMs=450}
            assert(H.use(f,'companion',5) and not H.pose(f,'companion','idle',5))
            f.companion.useRemainingMs=0;assert(not H.use(f,'companion',5))
            f.companion.useRemainingMs=451;assert(not H.use(f,'companion',5))
            f.companion.useRemainingMs=100;assert(not H.use(f,'companion',6))
            f.companion.stance='sit';assert(not H.use(f,'companion',5))
        ''')

    def test_target_is_actual_drawn_control_and_action_pacing_does_not_bypass_rate_limit(self):
        self.lua.execute('''
            local r={x=20,y=30,w=40,h=50}
            local settings={controls={{id='other',rect={}}, {id='bind-inventory',rect=r,enabled=true}}}
            local actual,enabled=H.target(settings,'bind-inventory');assert(actual==r and enabled)
            assert(H.target(settings,'missing')==nil)
            assert(not H.actionReady(10.6,10) and H.actionReady(10.7,10))
        ''')

    def test_actual_private_preference_binding_and_layout_files_reload_after_changes(self):
        self.lua.execute('''
            local files={};local fs={read=function(p)return files[p]end,
                write=function(p,v)files[p]=v;return true end,
                getInfo=function(p)return files[p]and{type='file'}end,
                remove=function(p)files[p]=nil;return true end}
            local Preferences=require('game.local_preferences')
            local Bindings=require('game.control_bindings');local Layout=require('game.control_layout')
            local store=Preferences.new(fs);local binding=Bindings.new(fs)
            local view={ready=true,runtime={saveData={coop={preferencesDetached=true}}},
                controller={open=function(self)self.menuOpen=true end},neutralize=function()end}
            local settings=require('game.coop_guest_settings').new(view,{preferences=store,bindings=binding,filesystem=fs})
            store:bind(view.runtime.saveData,function()return 'client'end)
            assert(settings:open());local initial=Preferences.view(view.runtime.saveData).audio.musicVolume
            assert(settings:audio('musicVolume',.05))
            settings:beginCapture('key','inventory');assert(binding:isCapturing())
            assert(settings:keypressed('z') and not binding:isCapturing())
            assert(settings:touchChange('joystick',.02,0));settings:close()
            assert(math.abs(Preferences.new(fs).values.audio.musicVolume-initial-.05)<.000001)
            local restored=Bindings.new(fs);assert(restored:translateKey('z')=='i')
            local old,known=restored:translateKey('i');assert(not old and known)
            local layout=assert(Layout.load(fs));assert(math.abs(layout.joystick.x-Layout.normalize().joystick.x-.02)<.000001)
            assert(not view.runtime.saveData.accessibility and not view.runtime.saveData.audio)
            assert(not files['slot-99.txt'] and not files['slot-1.txt'])
        ''')


if __name__=='__main__':
    unittest.main()
