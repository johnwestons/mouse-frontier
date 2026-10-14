"""Passive scene packets cannot choose a story outcome or advance source time."""
import unittest
import test_coop_last_stand_state_behavior as combat
import test_coop_lan_session_behavior as lan


class LastStandStageTests(unittest.TestCase):
    def setUp(self):
        combat.LastStandStateTests.setUp(self)
        self.lua.execute('''
            Life=require('game.coop_last_stand_lifecycle'); Life.ensure(data); assert(Life.move(quest,'returning'))
            P=require('game.net.protocol'); Wire=require('game.net.last_stand_stage'); Stage=require('game.coop_last_stand_stage')
            replica=assert(Schema.copy(data)); clock=0
            view=Stage.new({data=function() return replica end,clock=function() return clock end})
            source={questId=quest.lifecycle.entityId,lifeRevision=quest.lifecycle.revision,mode='returning',clock=3.25,paused=false,
                scout={x=400,y=500,walkDistance=220,arrival=.75},hostPose={x=500,y=590,facing=-1}}
            function packet(n) return assert(Stage.frame(data,source,'test-session',n or 1)) end
        ''')

    def test_checked_packet_limits_reject_speech_choices_and_out_of_bounds_values(self):
        self.lua.execute('''
            local frame=packet(); frame.sessionId=string.rep('s',64); frame.questId=string.rep('e',32)
            frame.sceneEpoch=2147483647; frame.lifeRevision=1000000000; frame.serial=2147483647
            frame.clock=1000000000000; frame.scout.walkDistance=1000000000000
            assert(Wire.snapshot(frame)); local bytes=assert(P.encode(frame,P.REALTIME)); assert(#bytes<=1200)
            assert(Wire.snapshot(assert(P.decode(bytes,P.REALTIME))))
            frame.text='speech'; assert(not Wire.snapshot(frame)); frame.text=nil
            frame.action='complete'; assert(not Wire.snapshot(frame)); frame.action=nil
            frame.offerPage=1; assert(not Wire.snapshot(frame)); frame.offerPage=nil
            frame.hostPose.x=960001; assert(not Wire.snapshot(frame)); frame.hostPose.x=500000
            frame.clock=-1; assert(not Wire.snapshot(frame))
        ''')

    def test_private_visual_time_is_bounded_and_paused_frames_cannot_advance(self):
        self.lua.execute('''
            local before=assert(Schema.copy(replica)); assert(view:receive(packet()))
            clock=.2; assert(view:get().clock==3.35)
            local visual=view:get(); visual.hostPose.x=999; assert(view:get().hostPose.x==500)
            assert(replica.lastStand.lifecycle.mode==before.lastStand.lifecycle.mode)
            assert(replica.lastStand.holdElapsed==before.lastStand.holdElapsed and source.clock==3.25)
            source.paused=true; assert(view:receive(packet(2))); clock=.3; assert(view:get().clock==3.25)
            clock=1; assert(not view:get())
        ''')

    def test_old_packets_duplicate_clock_regressions_and_wrong_lifecycles_are_discarded(self):
        self.lua.execute('''
            local first=packet(); assert(view:receive(first)); assert(view:receive(first)==false)
            assert(view:receive(packet(2))); assert(view:receive(first)==false)
            source.clock=2; assert(view:receive(packet(3))==false); source.clock=3.25
            replica.lastStand.lifecycle.revision=replica.lastStand.lifecycle.revision+1
            view:observe(); assert(not view:get() and view:receive(packet(4))==false)
            replica=assert(Schema.copy(data)); assert(view:receive(packet(5)))
            replica.coop.sceneEpoch=replica.coop.sceneEpoch+1; assert(not view:get())
        ''')

    def test_optional_offer_pages_and_inactive_source_have_no_outcome_fields(self):
        self.lua.execute('''
            assert(Stage.frame(data,nil,'s',1)==false)
            source.questId='foreign'; assert(not Stage.frame(data,source,'s',1)); source.questId=quest.lifecycle.entityId
            assert(Life.move(quest,'offer','paused')); source.mode='offer'; source.lifeRevision=quest.lifecycle.revision
            source.offerPage=2; source.scout=nil; source.hostPose=nil; replica=assert(Schema.copy(data))
            assert(view:receive(packet(2))); local offer=view:get()
            assert(offer.mode=='offer' and offer.offerPage==2 and not offer.action and not offer.reward and not offer.text)
            source.offerPage=17; assert(not Stage.frame(data,source,'s',3))
        ''')


class LastStandStageSessionTests(unittest.TestCase):
    setUp = lan.LanSessionTests.setUp
    tearDown = lan.LanSessionTests.tearDown

    def test_passive_host_lane_follows_real_admission_and_keeps_baseline_separate(self):
        self.lua.execute('''
            stages=0; guest.context.lastStandStage=function(m) stages=stages+1; observed=m; return true end
            ready()
            local m=P.message('last_stand_stage',{sessionId='test-session',sceneEpoch=2,questId='e1',lifeRevision=2,
                mode='offer',serial=1,clock=1200,paused=true,offerPage=1})
            assert(host:sendLastStandStage(m)); step(2)
            assert(stages==1 and observed.offerPage==1 and guest.status=='ready' and applied==1)
            m.sessionId='foreign'; assert(not host:sendLastStandStage(m)); m.sessionId='test-session'
            m.action='accept'; assert(not host:sendLastStandStage(m))
        ''')

    def test_guest_cannot_submit_host_stage_packets_as_story_progression(self):
        self.lua.execute('''
            ready(); host.context.movement=function() error('must never execute') end
            local m=P.message('last_stand_stage',{sessionId='test-session',sceneEpoch=2,questId='e1',lifeRevision=2,
                mode='returning',serial=1,clock=1200,paused=false})
            assert(guest.transport:sendToServer(assert(P.encode(m,P.REALTIME)),P.REALTIME,false)); step(2)
            assert(host.link==nil and host.reason=='invalid_movement' and applied==1)
        ''')


if __name__=='__main__':
    unittest.main()
