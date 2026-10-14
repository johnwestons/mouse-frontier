"""Bounded ENet enemy visuals, stale packets and independent read-only drawing."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class RoamingPresentationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Areas=require('game.expedition_areas'); P=require('game.net.protocol'); Wire=require('game.net.roaming')
            Presentation=require('game.coop_roaming_presentation')
            data=F.campaign(); assert(F.enroll(data)); data.scene='expedition'; data.location=5
            data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; Areas.ensure(data)
            definition=Areas.current(data); mobId=definition.mobs[1].id; saved=data.expeditions[definition.id].mobs[mobId]
            sys={transient={[definition.id]={[mobId]={state='windup',timer=.46,facing=-1,
                animationDistance=200,hitTimer=.38,healthTimer=3,deathTimer=0,targetId='host'}}}}
            clock=0; replica=assert(Schema.copy(data)); view=Presentation.new({data=function() return replica end,clock=function() return clock end})
            function frames(serial,paused) return assert(Presentation.frames(data,sys,'test-session',serial or 1,paused)) end
            function packet(serial,paused) return frames(serial,paused)[1] end
        ''')

    def test_authored_batches_and_worst_case_values_fit_existing_packet_limits(self):
        self.lua.execute('''
            local packets=frames(); assert(#packets==2 and #packets[1].mobs==2 and #packets[2].mobs==1)
            for _,frame in ipairs(packets) do assert(Wire.snapshot(frame)); assert(P.decode(assert(P.encode(frame,P.REALTIME)),P.REALTIME)) end
            local frame=packet(); frame.sessionId=string.rep('s',64); frame.areaId=string.rep('a',64)
            frame.sceneEpoch=2147483647; frame.sourceRevision=2147483647; frame.serial=2147483647
            for i,mob in ipairs(frame.mobs) do
                mob.id=string.rep(tostring(i),64); mob.e=string.rep('e',64); mob.x=-100000000; mob.y=100000000
                mob.t=3600000; mob.d=9007199254740991; mob.h=3600000; mob.v=3600000; mob.z=3600000
            end
            assert(Wire.snapshot(frame)); local payload=assert(P.encode(frame,P.REALTIME)); assert(#payload<=1200)
        ''')

    def test_receive_interpolation_and_telegraphs_never_change_campaign_or_ai(self):
        self.lua.execute('''
            local before=assert(Schema.copy(replica)); assert(view:receive(packet()))
            local visual=assert(view:get(mobId)); assert(visual.state=='windup' and visual.timer==.46 and visual.targetId=='host')
            local x=visual.x; saved.x=saved.x+60; sys.transient[definition.id][mobId].animationDistance=260
            clock=.04; assert(view:receive(packet(2))); clock=clock+Wire.INTERVAL/2
            visual=assert(view:get(mobId)); assert(math.abs(visual.x-(x+30))<.00001 and visual.animationDistance==230)
            assert(visual.timer<.46 and visual.hitTimer<.38 and visual.healthTimer<3)
            assert(replica.expeditions[definition.id].mobs[mobId].x==before.expeditions[definition.id].mobs[mobId].x)
            assert(sys.transient[definition.id][mobId].timer==.46 and data.scene=='expedition')
            clock=1; assert(not view:get(mobId))
        ''')

    def test_new_source_revision_waits_for_reliable_projection_and_old_frames_expire(self):
        self.lua.execute('''
            assert(view:receive(packet())); data.coop.revision=data.coop.revision+1
            local future=packet(2); assert(view:receive(future)==false)
            replica.coop.revision=data.coop.revision; assert(not view:get(mobId)); assert(view:receive(future))
            local old=packet(3); old.sourceRevision=old.sourceRevision-1; assert(view:receive(old)==false)
            replica.coop.sceneEpoch=replica.coop.sceneEpoch+1; assert(not view:get(mobId) and view:receive(future)==false)
            replica.scene='train'; assert(not view:get(mobId))
        ''')

    def test_per_mob_ordering_accepts_disjoint_batches_but_ignores_duplicates(self):
        self.lua.execute('''
            local all=frames(3); assert(view:receive(all[2])); assert(view:receive(all[1]))
            assert(view:receive(all[1])==false and view:receive(packet(2))==false)
            assert(view:get(definition.mobs[3].id) and view:get(mobId))
            clock=.5; saved.x=saved.x+500; assert(view:receive(packet(4)))
            assert(view:get(mobId).x==saved.x) -- snap after a gap or large correction
        ''')

    def test_invalid_or_unknown_batch_is_rejected_before_any_visual_is_installed(self):
        self.lua.execute('''
            local frame=packet(); frame.mobs[2].e='forged-entity'
            local ok,reason=view:receive(frame); assert(ok==nil and reason=='unknown_roaming_entity' and not view:get(mobId))
            frame=packet(); frame.mobs[2].id=frame.mobs[1].id; assert(not Wire.snapshot(frame))
            frame=packet(); frame.mobs[1].s=7; assert(not Wire.snapshot(frame))
            frame=packet(); frame.mobs[1].hp=999; assert(not Wire.snapshot(frame))
            frame=packet(); frame.mobs[3]=frame.mobs[2]; assert(not Wire.snapshot(frame))
            frame=packet(); frame.mobs.extra=frame.mobs[2]; assert(not Wire.snapshot(frame))
            frame=packet(); frame.mobs[1].x=0/0; assert(not Wire.snapshot(frame))
        ''')

    def test_pause_freezes_attack_and_death_timers_then_resume_catches_up(self):
        self.lua.execute('''
            sys.transient[definition.id][mobId].deathTimer=.2
            assert(view:receive(packet(1,true))); clock=.2
            local visual=assert(view:get(mobId)); assert(visual.timer==.46 and visual.deathTimer==.2 and visual.hitTimer==.38)
            assert(view:receive(packet(2,false))); clock=.3
            visual=assert(view:get(mobId)); assert(math.abs(visual.timer-.36)<.00001 and math.abs(visual.deathTimer-.3)<.00001)
        ''')

    def test_baseline_dead_mobs_never_replay_death_and_new_defeats_have_a_bounded_effect(self):
        self.lua.execute('''
            replica.expeditions[definition.id].mobs[mobId].dead=true
            local joined=Presentation.new({data=function() return replica end,clock=function() return clock end})
            assert(joined:receive(packet())); assert(not joined:get(mobId).allowDeath)
            view:observe(); assert(view:receive(packet())); assert(view:get(mobId).allowDeath)
            clock=.2; view:observe(); assert(view:get(mobId).allowDeath)
            clock=1.4; assert(view:receive(packet(2))); assert(not view:get(mobId).allowDeath)
            replica.expeditions[definition.id].mobs[mobId].dead=false; view:observe()
            assert(not view:get(mobId).allowDeath)
        ''')

    def test_guest_draw_uses_live_state_without_mutating_replica_or_replaying_ai(self):
        self.lua.execute('''
            package.loaded['game.expedition_runtime']={new=function(c)
                return {draw=function()
                    c.roamingMobs.draw(sys,{area=definition,areaState=replica.expeditions[definition.id],player={x=0,y=0}})
                end,ensureAssets=function() end,release=function() end}
            end}
            local observed
            package.loaded['game.roaming_mobs']={draw=function(system,context)
                observed={system=system,context=context}
                local t=system.transient[definition.id][mobId]
                if t then
                    assert(t.state=='windup' and t.targetId=='host')
                    t.lastDrawDistance=t.animationDistance; t.timer=999
                    context.areaState.mobs[mobId].x=-999
                end
            end}
            assert(view:receive(packet())); local original=replica.expeditions[definition.id].mobs[mobId].x
            local scene=require('game.coop_scene_view').new({runtime={saveData=replica,scene='expedition'},ui={},
                content={scenery={}},catalog={},roamingPresentation=view})
            scene.drawExpedition(); assert(observed and replica.expeditions[definition.id].mobs[mobId].x==original)
            assert(sys.transient[definition.id][mobId].timer==.46 and view:get(mobId).timer==.46)
            replica.expeditions[definition.id].mobs[mobId].dead=true; clock=2
            scene.drawExpedition(); assert(#observed.context.area.mobs==2)
            assert(not observed.context.areaState.mobs[mobId] and not observed.system.transient[definition.id][mobId])
        ''')

    def test_guest_art_tracks_later_streamed_images_and_keeps_atlas_assignments_private(self):
        self.lua.execute('''
            local options
            package.loaded['game.expedition_runtime']={new=function(c)
                options=c; return {ensureAssets=function() end,release=function() end}
            end}
            local content={scenery={},mobImages={}}
            require('game.coop_scene_view').new({runtime={},ui={},content=content,catalog={}})
            local later={name='later'}; content.mobImages['dust-beetle.png']=later
            assert(options.mobImages['dust-beetle.png']==later)
            content.mobImages['dust-beetle.png']=nil; assert(not options.mobImages['dust-beetle.png'])
            options.mobImages['sludge-bandit.png']={name='private-atlas'}
            assert(not content.mobImages['sludge-bandit.png'])
        ''')

    def test_expired_live_frame_drops_warning_state_and_retains_only_bounded_hit_feedback(self):
        self.lua.execute('''
            package.loaded['game.expedition_runtime']={new=function(c)
                return {draw=function()
                    c.roamingMobs.draw(sys,{area=definition,areaState=replica.expeditions[definition.id]})
                end,ensureAssets=function() end,release=function() end}
            end}
            local observed
            package.loaded['game.roaming_mobs']={draw=function(system)
                observed=system.transient[definition.id][mobId]
            end}
            assert(view:receive(packet())); clock=1
            local scene=require('game.coop_scene_view').new({runtime={saveData=replica,scene='expedition'},ui={},
                content={scenery={}},catalog={},roamingPresentation=view})
            scene.drawExpedition()
            assert(observed.state=='patrol' and observed.timer==0)
            assert(sys.transient[definition.id][mobId].state=='windup')
        ''')


if __name__ == '__main__':
    unittest.main()
