"""Actual GuestView/Prediction/pose panel retention never grants stale actions."""
import unittest
import test_coop_player_pose_behavior as pose


class GuestPoseRefreshTests(unittest.TestCase):
    setUp = pose.PersonalPoseGuestTests.setUp
    panel = pose.PersonalPoseGuestTests.panel

    def prepare(self, scene='train'):
        self.lua.globals().fixture_scene = scene
        self.lua.execute("data.scene=fixture_scene")
        self.panel()
        self.lua.execute('''
            controller.network.campaignId='same-campaign';controller.network.snapshot=controller.replica.data
            assert(view.poses:open());poseFrame(2)
            assert(view.poses.opened and view.poses:domain())
            openIdentity=view.poses.openIdentity;before={frame=controller.motionFrame,epoch=view.epoch,motion=view.motionId,
                location=view.runtime.saveData.location,car=view.runtime.player.activeCar}
        ''')

    def test_train_and_town_existing_menu_survive_valid_snapshot_and_ack_without_actions_or_pose_facts(self):
        for scene in ('train', 'stop'):
            with self.subTest(scene=scene):
                self.setUp();self.prepare(scene)
                self.lua.execute('''
                    for _,status in ipairs({'snapshot','acknowledging'}) do
                        controller.network.status=status;assert(view:update(.01))
                        assert(view.poses.opened and view.poses.openIdentity==openIdentity and not view:inputAllowed())
                        assert(view.epoch==before.epoch and view.motionId==before.motion and controller.motionFrame==before.frame)
                        assert(view.runtime.saveData.location==before.location and view.runtime.player.activeCar==before.car)
                        assert(not view.poses:submit('use') and not view.poses:submit('sit') and not command)
                        assert(next(view.poses:presentation('host'))==nil and next(view.poses:presentation('companion'))==nil)
                        assert(view.runtime.playerPose=='idle' and view.runtime.actionTimer==0)
                    end
                    controller.network.status='ready';poseFrame(3)
                    assert(view.poses.opened and view.poses:submit('sit'))
                    assert(command.name=='player.pose' and command.args.motionId==before.motion)
                ''')

    def test_new_menu_cannot_open_during_refresh_or_stale_motion_and_no_auto_reopen(self):
        self.prepare()
        self.lua.execute('''
            view.poses:close()
            for _,status in ipairs({'snapshot','acknowledging'}) do
                controller.network.status=status;assert(not view.poses:open());assert(view:update(.01))
                assert(not view.poses.opened and not command)
            end
            controller.network.status='ready';assert(view:update(.36));assert(not view.poses:open())
            poseFrame(3);assert(not view.poses.opened,'fresh frame silently reopened old menu')
            assert(view.poses:open())
        ''')

    def test_short_motion_hitch_retains_only_existing_menu_without_stale_use_countdown(self):
        self.prepare('stop')
        self.lua.execute('''
            poseFrame(3,'idle',8,450);assert(view.runtime.actionTimer==.45)
            assert(view:update(.36));assert(view.prediction:stale() and view.poses.opened)
            assert(not view.poses:submit('use') and not command and view.runtime.actionTimer==0)
            assert(next(view.poses:presentation('companion'))==nil and not view:inputAllowed())
            poseFrame(4,'idle',8,0);assert(view.poses.opened and view.runtime.actionTimer==0)
            assert(view.poses:submit('lay'))
        ''')

    def test_network_session_campaign_epoch_motion_car_and_modal_changes_invalidate_retained_menu(self):
        changes={
            'network': "local old=controller.network;controller.network={status='acknowledging',snapshot=old.snapshot,sessionId=old.sessionId,campaignId=old.campaignId}",
            'session': "controller.network.sessionId='other-session'",
            'campaign': "controller.network.campaignId='other-campaign'",
            'epoch': "view.epoch=view.epoch+1",
            'motion': "view.motionId=view.motionId+1",
            'car': "view.runtime.player.activeCar=2",
            'scene': "view.runtime.scene='house';view.runtime.saveData.scene='house';controller.replica.data.scene='house'",
            'location': "view.runtime.saveData.location=2;controller.replica.data.location=2",
            'modal': "view.modalDomain='farmhouse-other-domain'",
            'paused-frame': "controller.motionFrame.paused=true",
            'no-existing-snapshot': "controller.network.snapshot=nil",
            'disconnect': "controller.network.closed=true",
        }
        for label, change in changes.items():
            with self.subTest(change=label):
                self.setUp();self.prepare();self.lua.execute("controller.network.status='acknowledging';"+change)
                self.lua.execute('''
                    view.poses:update();assert(not view.poses.opened and not view.poses.openIdentity)
                    assert(not view.poses:submit('use') and not command)
                    assert(next(view.poses:presentation('companion'))==nil)
                ''')

    def test_save_focus_menu_scene_transition_and_encounters_close_without_replaying_command(self):
        changes={
            'save': "controller.network.savePending=true",
            'runtime-save': "view.runtime.saving=true",
            'focus': "view:focus(false)",
            'menu': "controller.menuOpen=true",
            'car-request': "view.carRequest={car=2}",
            'car-transition': "view.carTransition={from=1,to=2}",
            'battle': "view.runtime.saveData.tacticalBattle={}",
            'roaming': "view.runtime.saveData.roamingEncounter={}",
            'ambush': "view.runtime.saveData.trainAmbush={active=true}",
            'event': "view.runtime.saveData.events={current={}}",
        }
        for label, change in changes.items():
            with self.subTest(change=label):
                self.setUp();self.prepare('stop');self.lua.execute("controller.network.status='snapshot';"+change)
                self.lua.execute('''
                    view.poses:update();assert(not view.poses.opened and not view.poses.openIdentity)
                    assert(not view.poses:submit('use') and not command)
                ''')

    def test_inflight_pose_wait_retains_refresh_but_matches_fresh_result_and_never_resubmits(self):
        self.prepare()
        self.lua.execute('''
            assert(view.poses:submit('sit'));local pending=view.poses.pending
            controller.network.pendingCommand={requestId=42,command='player.pose'}
            controller.network.status='acknowledging';assert(view:update(.01))
            assert(view.poses.opened and view.poses.pending==pending and not view.poses:submit('lay'))
            controller.network.lastCommandResult={requestId=42,sessionId='guest-test',command='player.pose',
                ok=true,durable=false,revision=view.runtime.saveData.coop.revision+1,
                details={actorId='companion',pose='sit',serial=7,useMs=0}}
            view.poses:update();assert(view.poses.pending==pending and view.poses.opened)
            controller.network.status='ready';controller.network.pendingCommand=nil
            view.runtime.saveData.coop.revision=view.runtime.saveData.coop.revision+1
            poseFrame(3,'sit',7);assert(not view.poses.pending and not view.poses.opened)
            assert(view.runtime.playerPose=='sit' and command.args.pose=='sit')
            assert(not data.players.companion.playerPose,'transient pose entered campaign actor record')
        ''')


if __name__ == '__main__':
    unittest.main()
