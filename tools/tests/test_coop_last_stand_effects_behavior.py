"""Bounded transient ENet effects cannot spend or replay campaign damage."""
import unittest
import test_coop_last_stand_state_behavior as combat
import test_coop_lan_session_behavior as lan


class LastStandEffectsTests(unittest.TestCase):
    def setUp(self):
        combat.LastStandStateTests.setUp(self)
        self.lua.execute('''
            Life=require('game.coop_last_stand_lifecycle'); Life.ensure(data)
            P=require('game.net.protocol'); Wire=require('game.net.last_stand_effects')
            Visual=require('game.coop_last_stand_effects'); clock=0
            replica=assert(Schema.copy(data))
            view=Visual.new({data=function() return replica end,clock=function() return clock end})
            source={encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision,clock=12,events={}}
            function event(n,id,window)
                return {serial=n,actorId=id or 'companion',windowId=window or 'tall',slot=1,point=1,
                    elapsed=.04,hit=true,decal=true,impactFrame=4,decalFrame=0}
            end
            source.events={event(1),event(2,'host','wide'),event(3)}
            function frames(serial) return assert(Visual.frames(data,source,'test-session',serial or 1)) end
        ''')

    def test_worst_case_packets_fit_and_exact_fields_reject_untrusted_facts(self):
        self.lua.execute('''
            local batches=frames(); assert(#batches==2)
            local frame=batches[1]; frame.sessionId=string.rep('s',64); frame.domain=string.rep('d',64)
            frame.encounterId=string.rep('e',64); frame.sceneEpoch=2147483647; frame.phaseRevision=1000000000
            frame.serial=2147483647; frame.clock=1000000000000
            for _,e in ipairs(frame.events) do e.n=e.n+999999990; e.e=3000; e.s=8 end
            assert(Wire.snapshot(frame)); local bytes=assert(P.encode(frame,P.REALTIME)); assert(#bytes<=1200)
            assert(Wire.snapshot(assert(P.decode(bytes,P.REALTIME))))
            frame.events[1].health=999; assert(not Wire.snapshot(frame)); frame.events[1].health=nil
            frame.events[1].p=5; assert(not Wire.snapshot(frame)); frame.events[1].p=1
            frame.events[1].s=9; assert(not Wire.snapshot(frame)); frame.events[1].s=1
            frame.events[1].e=-1; assert(not Wire.snapshot(frame))
        ''')

    def test_disjoint_batches_duplicate_order_and_private_aging_never_mutate_save(self):
        self.lua.execute('''
            local before=assert(Schema.copy(replica)); local batches=frames()
            assert(view:receive(batches[2])); assert(view:receive(batches[1])); assert(#view:get().events==3)
            clock=.1; assert(view:receive(batches[1])==false)
            local result=view:get(); assert(result.events[1].elapsed>.13)
            result.events[1].elapsed=999; assert(view:get().events[1].elapsed<1)
            source.clock=12.1; assert(view:receive(frames(2)[1])); assert(view:receive(batches[2])==false)
            assert(replica.players.companion.health==before.players.companion.health)
            assert(replica.lastStand.combat.clock==before.lastStand.combat.clock)
            assert(replica.lastStand.combat.defenders.companion.playerDamage==before.lastStand.combat.defenders.companion.playerDamage)
            clock=1; assert(view:get()==nil)
        ''')

    def test_pause_freezes_only_visual_age_and_empty_frames_are_valid(self):
        self.lua.execute('''
            source.paused=true; local frame=frames()[1]; assert(view:receive(frame))
            clock=.1; assert(view:get().events[1].elapsed==.04)
            source.events={}; local empty=frames(2); assert(#empty==1 and #empty[1].events==0 and Wire.snapshot(empty[1]))
            assert(view:receive(empty[1])); clock=.5; assert(not view:get())
        ''')

    def test_phase_domain_and_scene_changes_expire_history_and_new_process_has_no_effects(self):
        self.lua.execute('''
            local frame=frames()[1]; assert(view:receive(frame))
            replica.lastStand.combat.phaseRevision=replica.lastStand.combat.phaseRevision+1
            view:observe(); assert(not view:get() and view:receive(frame)==false)
            replica=assert(Schema.copy(data)); assert(view:receive(frame))
            replica.lastStand.lifecycle.revision=replica.lastStand.lifecycle.revision+1
            assert(not view:get() and view:receive(frame)==false)
            replica=assert(Schema.copy(data)); assert(view:receive(frame)); replica.coop.sceneEpoch=replica.coop.sceneEpoch+1
            assert(not view:get() and view:receive(frame)==false)
            local fresh=Visual.new({data=function() return data end,clock=function() return clock end})
            assert(not fresh:get() and not data.lastStand.combat.shotEvents)
        ''')

    def test_host_builder_rejects_duplicate_events_wrong_identity_and_excess_buffers(self):
        self.lua.execute('''
            source.events={event(1),event(1)}; assert(not Visual.frames(data,source,'s',1))
            source.events={}; for i=1,9 do source.events[i]=event(i) end
            assert(not Visual.frames(data,source,'s',1))
            source.events={event(1)}; source.encounterId='foreign'; assert(not Visual.frames(data,source,'s',1))
            assert(#assert(Visual.frames(data,nil,'s',1))==0)
        ''')


class LastStandEffectSessionTests(unittest.TestCase):
    def setUp(self):
        lan.LanSessionTests.setUp(self)

    def tearDown(self):
        lan.LanSessionTests.tearDown(self)

    def test_realtime_host_only_lane_keeps_admission_and_reliable_damage_separate(self):
        self.lua.execute('''
            effects=0; guest.context.lastStandEffects=function(frame) effects=effects+1; observed=frame; return true end
            ready()
            local frame=P.message('last_stand_effects',{sessionId='test-session',sceneEpoch=2,domain='e1:2:shootout',
                encounterId='e2',phaseRevision=1,serial=1,clock=12000,paused=false,
                events={{n=1,a=2,w=2,s=1,p=1,e=0,h=true,z=false,i=4,c=0}}})
            assert(host:sendLastStandEffects(frame)); step(2)
            assert(effects==1 and observed.events[1].a==2 and guest.status=='ready' and applied==1)
            frame.sessionId='foreign'; assert(not host:sendLastStandEffects(frame))
            frame.sessionId='test-session'; frame.events[1].a=3; assert(not host:sendLastStandEffects(frame))
        ''')

    def test_guest_forged_effects_cannot_enter_host_damage_or_visual_callbacks(self):
        self.lua.execute('''
            ready(); host.context.movement=function() error('must not execute') end
            local frame=P.message('last_stand_effects',{sessionId='test-session',sceneEpoch=2,domain='e1:2:shootout',
                encounterId='e2',phaseRevision=1,serial=1,clock=12000,paused=false,events={}})
            assert(guest.transport:sendToServer(assert(P.encode(frame,P.REALTIME)),P.REALTIME,false)); step(2)
            assert(host.link==nil and host.reason=='invalid_movement' and applied==1)
        ''')


if __name__=='__main__':
    unittest.main()
