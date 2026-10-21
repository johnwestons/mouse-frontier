"""Production guest View routes private Last Stand shooting and position readiness."""
import unittest
import test_coop_last_stand_movement_behavior as movement


class GuestLastStandShooterTests(unittest.TestCase):
    setUp = movement.LastStandGuestMotionTests.setUp
    farm = movement.LastStandGuestMotionTests.farm

    def shooter(self):
        self.farm()
        self.lua.execute('''
            sent={}; reports=0; clock=100; axes={}; context.clock=function() return clock end
            context.bindings.axisValue=function(_,axis) return axes[axis] or 0 end
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                sent[#sent+1]={name=name,args=args,epoch=epoch,expected=expected}; return #sent
            end
            Shooting=require('game.first_person_shooting'); Sessions=require('game.coop_shooter_sessions')
            Shooting.playReport=function() reports=reports+1 end
            local q=data.lastStand
            require('game.last_stand_shootout').new(q,data,context.catalog,'wide',960,720)
            q.combat.defenders.companion={windowId='tall',ducking=false,coverProgress=0,hitRecovery=0,playerDamage=0}
            q.shooterSessions={companion={loanAmmo=48,loanActive=true,weaponSession={actorId='companion',
                weapon='frontier-22-lever-rifle',ammoType='22lr',capacity=12,borrowed=true,
                magazine=3,cooldown=0,reloadTimer=0,fireMode='single'}}}
            q.positionVersion=1; q.firingPositions={host='wide'}
            assert(Life.move(q,'shootout')); Life.ensure(data)
            controller.replica.revision=3; controller.motionFrame=modalFrame(2,3)
            controller.motionFrame.ready=false; controller.motionFrame.paused=true
            assert(view:update(.05)); panel=view.lastStand.shooter
            package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            before=Schema.copy(data)
            function ackPosition(window,revision)
                local p=assert(panel.pending)
                local q=view.runtime.saveData.lastStand
                q.firingPositions.companion=window; q.combat.defenders.companion.windowId=window or 'tall'
                controller.network.lastCommandResult={requestId=p.id,ok=true,durable=true,revision=revision or 0,
                    details={actorId='companion',questId=q.lifecycle.entityId,revision=q.lifecycle.revision,
                        phaseRevision=q.combat.phaseRevision,action=p.action,windowId=window,leaseId='p1',expiresIn=30}}
                panel:update(.01)
            end
            function positioned()
                assert(panel:requestPosition('ready','tall')); ackPosition('tall'); assert(panel:canAct())
            end
        ''')

    def test_late_snapshot_does_not_rewind_or_replay_the_same_authored_shot(self):
        self.shooter()
        self.lua.execute('''
            positioned(); local Actions=require('game.first_person_weapon_actions')
            local saved=view.runtime.saveData.lastStand.shooterSessions.companion.weaponSession
            Actions.beginFire(saved); saved.weaponActionElapsed=.02; view.revision=4
            panel:update(.05); panel:update(.08); local elapsed=panel.gun.weaponActionElapsed
            saved.weaponActionElapsed=.04; view.revision=5; panel:update(.01)
            assert(panel.gun.weaponActionElapsed>=elapsed,'late snapshot rewound fire frames')
            assert(saved.weaponActionElapsed==.04 and saved.magazine==3)
            panel:update(.1); assert(panel.gun.weaponAction==nil)
            saved.weaponActionElapsed=.12; view.revision=6; panel:update(.01)
            assert(panel.gun.weaponAction==nil,'completed shot replayed')
            Actions.beginFire(saved); view.revision=7; panel:update(.01)
            assert(panel.gun.weaponAction=='fire' and panel.gun.weaponActionElapsed<.075,'new shot did not restart')
        ''')

    def test_reload_frames_keep_progress_but_new_encounter_phase_resets_presentation(self):
        self.shooter()
        self.lua.execute('''
            positioned(); local A=require('game.first_person_weapon_actions')
            local q=view.runtime.saveData.lastStand; local saved=q.shooterSessions.companion.weaponSession
            A.beginReload(saved,3); saved.reloadTimer=2; view.revision=4
            panel:update(.05); panel:update(.08); local elapsed=panel.gun.weaponActionElapsed
            view.revision=5; panel:update(.01)
            assert(panel.gun.weaponActionElapsed>=elapsed and saved.weaponActionElapsed==0)
            assert(panel.gun.reloadTimer==2 and panel.gun.magazine==saved.magazine)
            q.combat.phaseRevision=q.combat.phaseRevision+1; view.revision=6; panel:sync()
            assert(panel.gun.weaponActionElapsed==0)
        ''')

    def test_position_ready_bootstraps_even_when_nonwalking_frame_is_paused(self):
        self.shooter()
        self.lua.execute('''
            assert(view.paused and not view:inputAllowed() and not panel:canAct())
            view:keypressed('2'); assert(#sent==1 and sent[1].name=='lastStand.position')
            local args=sent[1].args
            assert(args.action=='ready' and args.window=='tall' and args.phaseRevision==data.lastStand.combat.phaseRevision)
            assert(sent[1].expected['activity:lastStand:'..data.lastStand.lifecycle.entityId..':positions']==0)
            ackPosition('tall'); assert(panel:canAct() and not view:inputAllowed())
            assert(data.lastStand.firingPositions.companion==nil)
        ''')

    def test_position_requires_durable_receipt_and_matching_projection(self):
        self.shooter()
        self.lua.execute('''
            view:keypressed('2'); controller.network.lastCommandResult={requestId=1,ok=true,savePending=true}
            panel:update(.01); assert(panel.pending and not panel.position)
            ackPosition('tall',50); assert(panel.pending and not panel:canAct())
            view.runtime.saveData.coop.revision=50; panel:update(.01); assert(panel:canAct())
        ''')

    def test_fire_uses_personal_loan_and_current_phase_without_predicting_costs(self):
        self.shooter()
        self.lua.execute('''
            positioned(); panel:aim(480,320); view:keypressed('space')
            local shot=sent[2]; local q=view.runtime.saveData.lastStand
            assert(shot.name=='gun.fire' and shot.args.mode=='lastStand')
            assert(shot.args.weaponId=='loan:companion' and shot.args.phaseRevision==q.combat.phaseRevision)
            assert(shot.args.encounterId==q.combat.entityId and shot.args.x==500000)
            assert(shot.expected['entity:'..q.combat.entityId]==0)
            assert(panel.gun.magazine==3 and q.shooterSessions.companion.weaponSession.magazine==3 and reports==0)
            controller.network.lastCommandResult={requestId=2,ok=true,savePending=true}; panel:update(.01)
            assert(reports==0 and panel.pending)
            controller.network.lastCommandResult={requestId=2,ok=true,durable=true,revision=0,
                details={actorId='companion',encounterId=q.combat.entityId,phaseRevision=q.combat.phaseRevision,
                    fired=true,hit=true,weapon='frontier-22-lever-rifle'}}
            panel:update(.01); assert(reports==1 and panel.impact and not panel.pending)
            view:keyreleased('space'); assert(not panel.held.keyboard)
            assert(data.lastStand.shooterSessions.companion.weaponSession.magazine==3)
        ''')

    def test_personal_cover_and_reload_mode_supply_commands(self):
        self.shooter()
        self.lua.execute('''
            positioned(); view:keypressed('c'); assert(sent[2].name=='gun.cover' and sent[2].args.cover==true and not sent[2].args.weaponId)
            panel.pending=nil; view:keypressed('r'); assert(sent[3].name=='gun.reload' and sent[3].args.weaponId=='loan:companion')
            panel.pending=nil; view:keypressed('v'); assert(sent[4].name=='gun.mode')
            panel.pending=nil; view:keypressed('l'); assert(sent[5].name=='lastStand.supply' and not sent[5].args.weaponId)
            assert(not data.lastStand.combat.defenders.companion.ducking)
        ''')

    def test_cover_cooldown_reload_safe_wounds_result_and_missing_ready_block_fire(self):
        self.shooter()
        self.lua.execute('''
            positioned(); local q=view.runtime.saveData.lastStand; local owner=q.combat.defenders.companion
            owner.ducking=true; assert(not panel:fire()); owner.ducking=false
            owner.coverProgress=.2; assert(not panel:fire()); owner.coverProgress=0
            panel.gun.cooldown=.2; assert(not panel:fire()); panel.gun.cooldown=0
            panel.gun.reloadTimer=1; assert(not panel:fire()); panel.gun.reloadTimer=0
            panel.gun.fireMode='safe'; assert(not panel:fire()); panel.gun.fireMode='single'
            view.runtime.saveData.health=1; assert(not panel:fire()); view.runtime.saveData.health=20
            q.combat.result='intermission'; assert(not panel:fire()); q.combat.result=nil
            panel.position=nil; assert(not panel:fire()); assert(#sent==1)
        ''')

    def test_initial_ready_requires_matching_domain_motion_focus_and_idle_network(self):
        self.shooter()
        self.lua.execute('''
            local f=controller.motionFrame
            f.domain='old-domain'; assert(not panel:requestPosition('ready','tall')); f.domain=Life.key(view.runtime.saveData)
            f.motionId=999; assert(not panel:requestPosition('ready','tall')); f.motionId=view.motionId
            view.focused=false; assert(not panel:requestPosition('ready','tall')); view.focused=true
            controller.menuOpen=true; assert(not panel:requestPosition('ready','tall')); controller.menuOpen=false
            controller.network.pendingCommand={}; assert(not panel:requestPosition('ready','tall')); controller.network.pendingCommand=nil
            assert(#sent==0); assert(panel:requestPosition('ready','tall'))
        ''')

    def test_held_automatic_fire_waits_for_authoritative_cooldown_and_single_fire_needs_new_press(self):
        self.shooter()
        self.lua.execute('''
            positioned(); local q=view.runtime.saveData.lastStand; local saved=q.shooterSessions.companion.weaponSession
            panel.gun.fireMode='auto'; saved.fireMode='auto'
            view:keypressed('space'); assert(#sent==2)
            saved.cooldown=.3; view.revision=4
            controller.network.lastCommandResult={requestId=2,ok=true,durable=true,revision=0,
                details={actorId='companion',encounterId=q.combat.entityId,phaseRevision=q.combat.phaseRevision,
                    fired=true,hit=false,weapon='frontier-22-lever-rifle'}}
            panel:update(.1); assert(#sent==2 and panel.held.keyboard)
            panel:update(.1); assert(#sent==2 and panel.gun.cooldown==.3)
            saved.cooldown=0; view.revision=5; panel:update(.01); assert(#sent==3 and sent[3].name=='gun.fire')
            panel.pending=nil; saved.fireMode='single'; view.revision=6; panel:update(.01)
            assert(#sent==3); view:keyreleased('space'); view:keypressed('space'); assert(#sent==4)
        ''')

    def test_menu_focus_pause_and_controller_trigger_neutralization(self):
        self.shooter()
        self.lua.execute('''
            axes.fire=.8; positioned(); panel:update(.01); assert(#sent==1)
            axes.fire=0; panel:update(.01); axes.fire=.8; panel:update(.01); assert(sent[2].name=='gun.fire')
            panel.pending=nil; view:focus(false); assert(not next(panel.held) and not panel.controllerReady)
            view:focus(true); axes.fire=0; view:gamepadpressed(nil,'start'); assert(view.lastStand.paused and not panel:canAct())
            view:gamepadreleased(nil,'start');view:gamepadpressed(nil,'start'); assert(not view.lastStand.paused)
            view:gamepadpressed(nil,'b'); assert(controller.menuOpen and not next(panel.held))
        ''')

    def test_touch_has_one_aim_and_fire_owner_and_never_reaches_mobile_movement(self):
        self.shooter()
        self.lua.execute('''
            positioned()
            mobile.touchpressed=function() error('shooter touch became movement') end
            mobile.touchmoved=function() error('shooter drag became movement') end
            mobile.touchreleased=function() error('shooter release became movement') end
            view:touchpressed('aim',480,300); local aim=panel.gun.aimX
            view:touchpressed('other',650,300); view:touchmoved('other',700,300); assert(panel.gun.aimX==aim)
            view:touchmoved('aim',520,330); assert(panel.aimTouch=='aim')
            local r=panel:rect(1); view:touchpressed('fire',r.x+10,r.y+10)
            assert(sent[2].name=='gun.fire' and panel.fireTouch=='fire')
            view:touchpressed('fire2',r.x+10,r.y+10); view:touchreleased('fire2',0,0); assert(panel.held.touch)
            view:touchreleased('fire',0,0); view:touchreleased('aim',0,0)
            assert(not next(panel.held) and not panel.fireTouch and not panel.aimTouch)
        ''')

    def test_phase_and_network_changes_discard_private_ready_pending_and_held_controls(self):
        self.shooter()
        self.lua.execute('''
            positioned(); view:keypressed('space'); assert(panel.pending and panel.held.keyboard)
            view.runtime.saveData.lastStand.combat.phaseRevision=2; panel:sync()
            assert(not panel.pending and not panel.position and not next(panel.held))
            assert(not panel:canAct()); assert(panel:requestPosition('ready','tall')); ackPosition('tall')
            controller.network={}; panel:sync(); assert(not panel.position and not panel.pending and not next(panel.held))
        ''')

    def test_expired_and_save_barrier_lost_positions_reacquire_without_held_fire(self):
        self.shooter()
        self.lua.execute('''
            positioned(); view:keypressed('space')
            controller.network.lastCommandResult={requestId=2,ok=false,reason='position_expired'}
            panel:update(.01); assert(not panel.position and not next(panel.held))
            assert(sent[3].name=='lastStand.position' and sent[3].args.action=='ready')
            ackPosition('tall'); assert(panel:canAct())
            clock=130; panel:update(.01); assert(sent[4].name=='lastStand.position')
            assert(not next(panel.held))
        ''')

    def test_release_and_controller_window_selection_have_no_story_commands(self):
        self.shooter()
        self.lua.execute('''
            view:gamepadpressed(nil,'dpright'); view:gamepadpressed(nil,'a'); assert(sent[1].args.window=='tall')
            ackPosition('tall'); view:keypressed('backspace'); assert(sent[2].args.action=='release')
            ackPosition(nil); assert(not panel.position and panel.choosing)
            view:keypressed('return'); view:keypressed('e'); assert(#sent==2)
            assert(data.lastStand.state=='shootout' and data.lastStand.lifecycle.revision==before.lastStand.lifecycle.revision)
        ''')

    def test_draw_model_is_detached_actor_scoped_and_cannot_mutate_shared_targets(self):
        self.shooter()
        self.lua.execute('''
            local q=view.runtime.saveData.lastStand
            assert(panel.drawCampaign~=data and panel.drawCampaign.lastStand~=q)
            assert(require('game.coop_players').actorId(panel.drawActor)=='companion')
            local pose=require('game.last_stand_shootout').guestView(panel.drawCampaign.lastStand,panel.drawActor,panel.gun,960,720)
            assert(pose.guestPresentation and pose.windowId=='tall' and pose.gun==panel.gun)
            pose.targets[1].health=0; pose.quest.holdElapsed=999
            assert(q.targets[1].health>0 and q.holdElapsed~=999 and data.lastStand.holdElapsed~=999)
            panel.gun.magazine=0; assert(q.shooterSessions.companion.weaponSession.magazine==3)
        ''')

    def test_damage_feedback_observes_only_new_personal_damage_and_never_replays_history(self):
        self.shooter()
        self.lua.execute('''
            local q=view.runtime.saveData.lastStand
            assert(panel.seenDamage==0 and panel.hitFeedback==0 and not panel.damageNotice)
            q.combat.defenders.host.playerDamage=2; view.revision=4; panel:update(.01)
            assert(panel.hitFeedback==0 and not panel.damageNotice)
            q.combat.defenders.companion.playerDamage=1; view.revision=5; panel:update(.01)
            assert(panel.hitFeedback>0 and panel.damageNotice:find('HEALTH LOST: 1',1,true))
            assert(data.lastStand.combat.defenders.companion.playerDamage==0)
            panel:update(.5); assert(panel.hitFeedback==0)
            view.revision=6; panel:update(.01); assert(panel.hitFeedback==0)
            q.combat.phaseRevision=2; panel:sync(); assert(panel.hitFeedback==0 and not panel.damageNotice and panel.seenDamage==1)
            panel:update(.01); assert(panel.hitFeedback==0)
        ''')

    def test_damage_while_private_pause_focus_loss_or_menu_is_consumed_silently(self):
        self.shooter()
        self.lua.execute('''
            local owner=view.runtime.saveData.lastStand.combat.defenders.companion
            view.lastStand.paused=true; owner.playerDamage=1; view.revision=4; panel:update(.01)
            assert(panel.seenDamage==1 and panel.hitFeedback==0)
            view.lastStand.paused=false; view.focused=false; owner.playerDamage=2; view.revision=5; panel:update(.01)
            assert(panel.seenDamage==2 and panel.hitFeedback==0)
            view.focused=true; controller.menuOpen=true; owner.playerDamage=3; view.revision=6; panel:update(.01)
            assert(panel.seenDamage==3 and panel.hitFeedback==0)
            controller.menuOpen=false; panel:update(.01); assert(panel.hitFeedback==0 and not panel.damageNotice)
        ''')

    def test_checked_enemy_events_are_baselined_deduplicated_aged_and_actor_filtered(self):
        self.shooter()
        self.lua.execute('''
            local function event(serial,id,window,elapsed)
                return {serial=serial,actorId=id or 'companion',windowId=window or 'tall',slot=1,point=1,
                    elapsed=elapsed or 0,hit=false,decal=true,impactFrame=4,decalFrame=0}
            end
            fx={events={event(1)},clock=0,paused=false}
            controller.lastStandEffects={get=function() return fx end}
            panel:observeEffects(); assert(panel.seenEffectSerial==1 and #panel.visualEvents==0 and reports==0)
            fx.events={event(2),event(3,'host','wide')}; panel:observeEffects()
            assert(#panel.visualEvents==1 and panel.seenEffectSerial==3 and reports==1)
            panel:observeEffects(); assert(#panel.visualEvents==1 and reports==1)
            local visual=panel:visualEffects(); assert(#visual.incomingShots==1 and #visual.flashes==1)
            assert(not fx.events[1].receivedAt and not fx.events[1].decalPresented)
            panel:observeEffects(.33); visual=panel:visualEffects(); assert(#visual.incomingShots==0 and #visual.impactBursts==1 and #visual.impacts==1)
            panel:observeEffects(.67); visual=panel:visualEffects(); assert(#visual.impactBursts==0 and #visual.impacts==1 and #panel.visualEvents==0)
            view.runtime.saveData.lastStand.combat.defenders.companion.windowId='wide'; view.revision=4; panel:sync()
            assert(#panel.visualImpacts==0 and #panel.visualEvents==0)
        ''')

    def test_enemy_event_history_during_menu_is_silent_and_phase_reset_cannot_replay(self):
        self.shooter()
        self.lua.execute('''
            local function event(serial) return {serial=serial,actorId='companion',windowId='tall',slot=1,point=1,
                elapsed=0,hit=true,decal=false,impactFrame=5,decalFrame=2} end
            fx={events={},clock=0,paused=false}; controller.lastStandEffects={get=function() return fx end}
            panel:observeEffects(); controller.menuOpen=true; fx.events={event(1)}; panel:observeEffects()
            assert(panel.seenEffectSerial==1 and #panel.visualEvents==0 and reports==0)
            controller.menuOpen=false; panel:observeEffects(); assert(#panel.visualEvents==0 and reports==0)
            fx.events={event(2)}; panel:observeEffects(); assert(#panel.visualEvents==1 and reports==1)
            view.runtime.saveData.lastStand.combat.phaseRevision=2; panel:sync(); panel:observeEffects()
            assert(#panel.visualEvents==0 and panel.seenEffectSerial==2 and reports==1)
        ''')

    def test_enemy_effects_pause_with_host_barrier_and_old_events_never_report_audio(self):
        self.shooter()
        self.lua.execute('''
            local function event(serial,id,elapsed) return {serial=serial,actorId=id or 'companion',windowId=id=='host' and 'wide' or 'tall',
                slot=1,point=1,elapsed=elapsed or 0,hit=false,decal=false,impactFrame=4,decalFrame=0} end
            fx={events={},clock=0,paused=false}; controller.lastStandEffects={get=function() return fx end}
            panel:observeEffects(); fx.events={event(4,'host')}; panel:observeEffects()
            fx.events={event(3)}; panel:observeEffects(); assert(#panel.visualEvents==1 and reports==1)
            local before=panel:visualEffects().incomingShots[1].elapsed
            fx.paused=true; panel:observeEffects(2); assert(panel:visualEffects().incomingShots[1].elapsed==before)
            fx.paused=false; fx.events={event(5,nil,.5),event(6,nil,2)}; panel:observeEffects(.1)
            assert(reports==1 and #panel.visualEvents==2 and panel.seenEffectSerial==6)
            panel:observeEffects(); assert(reports==1)
        ''')

    def test_interior_selection_and_release_use_position_assistance(self):
        self.farm()
        self.lua.execute('''
            sent={}; controller.network.submitCommand=function(_,name,args,epoch,expected)
                sent[#sent+1]={name=name,args=args,epoch=epoch,expected=expected}; return #sent end
            view.runtime.player.x,view.runtime.player.y=350,300; view:keypressed('e')
            assert(sent[1].name=='lastStand.position' and sent[1].args.action=='select' and sent[1].args.window=='wide')
            assert(not sent[1].args.phaseRevision and not view:inputAllowed())
            controller.network.lastCommandResult={requestId=1,ok=true,durable=true,revision=0,
                details={actorId='companion',questId=data.lastStand.lifecycle.entityId,action='select',windowId='wide'}}
            view.lastStand:update(.01); assert(not view.lastStand.pending)
            view:keypressed('backspace'); assert(sent[2].args.action=='release')
            assert(data.lastStand.state=='interior' and not data.lastStand.firingPositions.companion)
        ''')


if __name__ == '__main__':
    unittest.main()
