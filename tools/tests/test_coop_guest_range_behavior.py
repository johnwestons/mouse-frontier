"""Production guest range routes inputs to a private, host checked lane."""
import unittest
import test_coop_guest_view_behavior as views


class GuestRangeTests(unittest.TestCase):
    setUp = views.GuestViewTests.setUp

    def range(self):
        self.lua.execute('''
            Range=require('game.shooting_range'); State=require('game.coop_range_state')
            Items=require('game.item_instances'); Players=require('game.coop_players')
            context.catalog=require('game.catalog'); sent={}; reports=0; clock=100; axes={}
            context.clock=function() return clock end
            context.bindings.axisValue=function(_,axis) return axes[axis] or 0 end
            require('game.first_person_shooting').playReport=function() reports=reports+1 end
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                sent[#sent+1]={name=name,args=args,epoch=epoch,expected=expected}; return #sent
            end
            data.scene='stop'; data.location=8; data.stopped=true; data.stopLayouts={['8']={}}
            local spot=assert(Range.ensure(data.stopLayouts['8'],8)); spot.x,spot.y=350,400
            assert(require('game.coop_entities').ensure(data))
            Items.write(Players.forActor(data,'companion'),nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            data.players.companion.ammo['22lr']=40
            Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'monocular')
            controller.replica.revision=2; controller.motionFrame=frame(1)
            assert(view:update(.05)); panel=view.range; package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            function seedLane()
                local own=view.runtime.saveData; local spot=own.stopLayouts['8'].shootingRange
                local session=assert(Range.serverNew(own,spot,context.catalog))
                session.version=1; session.spotId=spot.entityId; session.roundRevision=1
                local campaign=Players.campaignOf(own); campaign.rangeSessions={version=1,companion=session}
                return session
            end
            function ack(name,details,revision)
                local p=assert(panel.pending); assert(p.name==name)
                controller.network.lastCommandResult={requestId=p.id,ok=true,durable=true,revision=revision or 0,
                    details=details or {actorId='companion',spotId=panel.spotId,leaseId='r1',expiresIn=30,roundRevision=1,phase='lobby'}}
                panel:update(.01)
            end
            function opened()
                assert(panel:open()); seedLane(); ack('range.acquire'); assert(panel:canAct())
            end
            function playing()
                opened(); local s=panel:state(); assert(Range.serverStart(s,view.runtime.saveData,context.catalog))
                s.roundRevision=s.roundRevision+1; panel.modelRevision=nil; panel:update(.01)
            end
        ''')

    def test_late_snapshot_does_not_rewind_or_replay_the_same_authored_shot(self):
        self.range()
        self.lua.execute('''
            playing(); local Actions=require('game.first_person_weapon_actions'); local s=panel:state()
            Actions.beginFire(s); s.weaponActionElapsed=.02; panel.modelRevision=nil
            panel:update(.05); panel:update(.08); local elapsed=panel.model.weaponActionElapsed
            s.weaponActionElapsed=.04; view.revision=view.revision+1; panel:update(.01)
            assert(panel.model.weaponActionElapsed>=elapsed,'late snapshot rewound range fire frames')
            assert(s.weaponActionElapsed==.04)
            panel:update(.08); assert(panel.model.weaponAction==nil)
            s.weaponActionElapsed=.12; view.revision=view.revision+1; panel:update(.01)
            assert(panel.model.weaponAction==nil,'completed range shot replayed')
            Actions.beginFire(s); view.revision=view.revision+1; panel:update(.01)
            assert(panel.model.weaponAction=='fire' and panel.model.weaponActionElapsed<.075,'new range shot did not restart')
        ''')

    def test_reload_frames_keep_progress_but_new_round_resets_presentation(self):
        self.range()
        self.lua.execute('''
            playing(); local A=require('game.first_person_weapon_actions'); local s=panel:state()
            A.beginReload(s,3); s.reloadTimer=2; view.revision=view.revision+1
            panel:update(.05); panel:update(.08); local elapsed=panel.model.weaponActionElapsed
            view.revision=view.revision+1; panel:update(.01)
            assert(panel.model.weaponActionElapsed>=elapsed and s.weaponActionElapsed==0)
            assert(panel.model.reloadTimer==2 and panel.model.loaded==s.loaded)
            s.roundRevision=s.roundRevision+1; panel:sync(); assert(panel.model.weaponActionElapsed==0)
        ''')

    def test_actual_proximity_opens_private_lane_without_host_range(self):
        self.range()
        self.lua.execute('''
            assert(view:interactionAvailable() and view:actionLabel()=='TARGET RANGE')
            assert(panel:nearest()); view:keypressed('e')
            assert(panel:available() and not view:inputAllowed() and #sent==1 and sent[1].name=='range.acquire')
            assert(sent[1].args.spotId==data.stopLayouts['8'].shootingRange.entityId)
            assert(sent[1].expected['activity:range:'..sent[1].args.spotId..':companion']==0)
            assert(not data.rangeSessions and not view.runtime.saveData.rangeSessions)
        ''')

    def test_acquire_waits_for_saved_receipt_and_matching_projection(self):
        self.range()
        self.lua.execute('''
            assert(panel:open()); seedLane()
            controller.network.lastCommandResult={requestId=1,ok=true,savePending=true}; panel:update(.01)
            assert(panel.pending and not panel.leaseId)
            ack('range.acquire',nil,40); assert(panel.pending and not panel:canAct())
            view.runtime.saveData.coop.revision=40; panel:update(.01); assert(panel:canAct())
        ''')

    def test_setup_six_rows_and_owned_weapon_commands_preserve_world(self):
        self.range()
        self.lua.execute('''
            opened(); local s=panel:state(); local material=s.material
            view:keypressed('down'); view:keypressed('down'); view:keypressed('down'); assert(panel.pose.menuRow==4)
            view:keypressed('right'); assert(sent[2].name=='range.configure' and sent[2].args.action=='change')
            assert(sent[2].args.kind=='pattern' and sent[2].args.direction==1 and s.material==material)
            panel.pending=nil; view:mousepressed(700,405,1,false)
            assert(sent[3].args.kind=='distance' and panel.pose.menuRow==5)
            panel.pending=nil; view:mousepressed(700,455,1,false); assert(sent[4].args.kind=='length')
            assert(not data.rangeSessions and not data.players.host.ammo['22lr'])
        ''')

    def test_personal_fire_is_canonical_and_audio_waits_for_durability(self):
        self.range()
        self.lua.execute('''
            playing(); local s=panel:state(); local loaded=s.loaded; local rounds=view.runtime.saveData.ammo['22lr']
            panel.pose.hasMonocular=true; panel:intent({action='monocular'}); panel:aim(600,390,false)
            view:keypressed('space'); local shot=sent[2]
            assert(shot.name=='range.fire' and shot.args.weaponId==s.itemId and shot.args.roundRevision==2)
            assert(shot.args.x==583333 and shot.args.y==513889)
            assert(s.loaded==loaded and view.runtime.saveData.ammo['22lr']==rounds and reports==0)
            controller.network.lastCommandResult={requestId=2,ok=true,savePending=true}; panel:update(.01); assert(reports==0 and not next(panel.held))
            ack('range.fire',{actorId='companion',spotId=panel.spotId,fired=true,weapon=s.weapon},40)
            assert(reports==0 and panel.pending)
            view.runtime.saveData.coop.revision=40; panel:update(.01); assert(reports==1 and not panel.pending)
            view:keyreleased('space'); assert(not panel.held.keyboard)
        ''')

    def test_authoritative_timers_targets_and_round_are_not_locally_advanced(self):
        self.range()
        self.lua.execute('''
            playing(); local s=panel:state(); s.cooldown=2; s.reloadTimer=3; s.loaded=2
            panel.modelRevision=nil; panel:update(.05)
            local time=s.time; for i=1,20 do panel:update(.05) end
            assert(s.time==time and s.cooldown==2 and s.reloadTimer==3 and s.loaded==2 and #s.targets==0)
            assert(panel.model.time==time and panel.model.cooldown==2 and panel.model.reloadTimer==3 and panel.model.loaded==2)
            view:keypressed('space'); assert(#sent==1)
        ''')

    def test_private_controls_and_all_modality_routes_consume_world_inputs(self):
        self.range()
        self.lua.execute('''
            playing(); view:keypressed('i'); view:keypressed('g'); view:keypressed('u'); view:keypressed('h')
            assert(not view.runtime.inventoryOpen and not view.runtime.peopleOpen and not view.runtime.trainUpgradeOpen and not view.runtime.guestActivityOpen)
            view:keypressed('lshift'); assert(panel.pose.aimMode=='sights')
            view:mousepressed(400,300,2,false); view:mousereleased(400,300,2); assert(panel.pose.aimMode=='hip')
            view:gamepadpressed(nil,'y'); assert(sent[2].name=='range.reload')
            panel.pending=nil; view:touchpressed('reload',40,670); assert(sent[3].name=='range.reload')
            panel.pending=nil; view:keypressed('p'); assert(panel.paused); view:keypressed('space'); assert(#sent==3)
            view:keypressed('p'); view:gamepadpressed(nil,'back'); assert(controller.menuOpen and not next(panel.held))
        ''')

    def test_touch_aim_and_fire_each_belong_to_their_own_finger(self):
        self.range()
        self.lua.execute('''
            playing(); view:touchpressed('aim',400,300); local x,y=panel.pose.aimX,panel.pose.aimY
            view:touchmoved('unknown',100,100); assert(panel.pose.aimX==x and panel.pose.aimY==y)
            view:touchpressed('fire',600,300); assert(panel.aimTouch=='aim' and panel.fireTouch=='fire' and #sent==2)
            view:touchreleased('unknown',0,0); assert(panel.aimTouch=='aim' and panel.held.touch)
            view:touchreleased('fire',0,0); assert(panel.aimTouch=='aim' and not panel.held.touch)
            view:touchreleased('aim',0,0); assert(not panel.aimTouch)
        ''')

    def test_real_saved_axis_ids_aim_and_fire_without_holding_fire_through_entry(self):
        self.range()
        self.lua.execute('''
            local B=require('game.control_bindings');context.bindings.axisValue=B.axisValue
            local physical={triggerleft=1};love={joystick={getJoysticks=function() return {{
                isGamepad=function() return true end,getGamepadAxis=function(_,axis) return physical[axis] or 0 end}} end}}
            assert(bindings:assign('axis','fire','triggerleft'));assert(bindings:assign('axis','ads','triggerright'))
            playing();assert(#sent==1 and not panel.controllerReady)
            physical.triggerleft=0;panel:update(.01);assert(panel.controllerReady)
            physical.triggerright=1;panel:update(.01);assert(panel.pose.aimMode=='sights' and #sent==1)
            physical.triggerleft=1;panel:update(.01);assert(sent[2].name=='range.fire')
            assert(sent[2].args.weaponId==panel:state().itemId and sent[2].args.leaseId==panel.leaseId)
        ''')

    def test_custom_range_fire_pause_and_release_use_saved_scope_once(self):
        self.range()
        self.lua.execute('''
            playing();assert(bindings:assign('button','range_fire','guide'))
            view:gamepadpressed(nil,'x');assert(#sent==1)
            view:gamepadpressed(nil,'guide');assert(sent[2].name=='range.fire' and panel.held.keyboard)
            bindings:clear('button','range_mode');assert(bindings:assign('button','range_fire','rightshoulder'))
            view:gamepadreleased(nil,'guide');assert(not next(panel.held))
            ack('range.fire',{actorId='companion',fired=true});assert(bindings:assign('button','range_pause','guide'))
            view:gamepadpressed(nil,'start');assert(not panel.paused)
            view:gamepadpressed(nil,'guide');assert(panel.paused and not next(panel.held))
            panel:update(.01);assert(sent[3].name=='range.configure' and sent[3].args.action=='pause' and sent[3].args.paused)
        ''')

    def test_close_waits_for_release_and_resume_keeps_exact_saved_weapon(self):
        self.range()
        self.lua.execute('''
            playing(); local s=panel:state(); s.loaded=3; local gun=s.itemId; panel:close()
            assert(panel:available() and panel.pending.name=='range.release')
            ack('range.release',{actorId='companion',spotId=panel.spotId})
            assert(not panel:available() and s.itemId==gun and s.loaded==3)
            assert(panel:open()); ack('range.acquire'); assert(panel:canAct() and panel:state().itemId==gun and panel.model.loaded==3)
        ''')

    def test_motion_generation_rejoin_requires_fresh_lease_and_neutral_triggers(self):
        self.range()
        self.lua.execute('''
            playing(); panel.held.mouse=true; local lease=panel.leaseId
            view.motionId=view.motionId+1; controller.motionFrame.motionId=view.motionId
            panel:update(.01); assert(not panel:canAct() and not next(panel.held))
            assert(panel.pending.name=='range.acquire' and lease=='r1')
            axes.fire=1; ack('range.acquire'); panel:update(.01); assert(#sent==2)
            axes.fire=0; panel:update(.01); axes.fire=1; panel:update(.01); assert(sent[3].name=='range.fire')
        ''')

    def test_completion_requests_checked_result_without_claiming_score_or_rewards(self):
        self.range()
        self.lua.execute('''
            playing(); local s=panel:state(); s.time=0; s.completed=true
            panel:update(.01); assert(sent[2].name=='range.configure' and sent[2].args.action=='complete')
            assert(sent[2].args.score==nil and sent[2].args.gained==nil and not s.result and s.phase=='play')
            assert(sent[2].expected['entity:'..s.spotId]==0 and sent[2].expected.resources==0)
        ''')

    def test_pause_and_resume_require_durable_confirmation_and_clear_held_fire(self):
        self.range()
        self.lua.execute('''
            playing(); panel.held.mouse=true; view:keypressed('p'); panel:update(.01)
            assert(panel.paused and not panel:canAct() and not next(panel.held))
            assert(sent[2].args.action=='pause' and sent[2].args.paused==true and panel.serverPaused==false)
            controller.network.lastCommandResult={requestId=2,ok=true,savePending=true}; panel:update(.01)
            assert(panel.pending and panel.serverPaused==false)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,action='pause',paused=true},50)
            assert(panel.pending and panel.serverPaused==false)
            view.runtime.saveData.coop.revision=50; panel:update(.01); assert(panel.serverPaused and not panel.pending)
            view:gamepadpressed(nil,'start'); panel:update(.01)
            assert(sent[3].args.action=='pause' and sent[3].args.paused==false and not panel:canAct())
            view:keypressed('space'); assert(not next(panel.held) and #sent==3)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,action='pause',paused=false})
            assert(panel:canAct() and not next(panel.held) and not panel.serverPaused)
        ''')

    def test_menu_and_focus_pause_reconcile_while_local_inputs_are_blocked(self):
        self.range()
        self.lua.execute('''
            playing(); view:keypressed('f8'); panel:update(.01)
            assert(controller.menuOpen and sent[2].args.paused==true)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,paused=true})
            controller.menuOpen=false; view:focus(false); panel:update(.01)
            assert(#sent==2 and panel.serverPaused and not panel:canAct())
            view:focus(true); panel:update(.01); assert(sent[3].args.paused==false)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,paused=false}); assert(panel:canAct())
            view:focus(false); panel:update(.01); assert(sent[4].args.paused==true)
        ''')

    def test_paused_lease_renewal_retains_confirmed_pause_and_round(self):
        self.range()
        self.lua.execute('''
            playing(); panel.paused=true; panel.serverPaused=true; clock=125
            local round=panel:state().roundRevision; panel:update(.01)
            assert(panel.pending.name=='range.acquire')
            ack('range.acquire',{actorId='companion',spotId=panel.spotId,leaseId='r1',expiresIn=30,paused=true,roundRevision=round})
            assert(panel.serverPaused and not panel:canAct() and panel:state().roundRevision==round and not panel.pending)
        ''')

    def test_touch_ads_and_controller_ads_fire_the_displayed_calibrated_reticle(self):
        self.range()
        self.lua.execute('''
            playing(); panel:aim(500,400,true)
            local expected=Range.presentation(panel:state(),panel.pose); assert(Range.setAim(expected,true))
            view:keypressed('lshift')
            assert(math.abs(panel.pose.aimX-expected.aimX)<.001 and math.abs(panel.pose.aimY-expected.aimY)<.001)
            view.revision=view.revision+1; panel:sync()
            assert(math.abs(panel.pose.aimX-panel.model.aimX)<.001 and math.abs(panel.pose.aimY-panel.model.aimY)<.001)
            assert(panel:fire()); local shot=sent[2]; local x,y=Range.canonicalAim(panel.model,panel.model.aimX,panel.model.aimY)
            assert(shot.args.x==math.floor(x/960*1000000+.5) and shot.args.y==math.floor(y/720*1000000+.5))
            panel.pending=nil; panel:intent({action='aim',value=false}); panel:aim(520,420,true)
            expected=Range.presentation(panel:state(),panel.pose); Range.setAim(expected,true)
            axes.ads=1; panel:update(.01)
            assert(math.abs(panel.pose.aimX-expected.aimX)<.001 and math.abs(panel.pose.aimY-expected.aimY)<.001)
        ''')

    def test_rate_limited_reacquire_retains_ui_without_using_stale_lease(self):
        self.range()
        self.lua.execute('''
            playing(); panel.held.mouse=true; view:keypressed('return')
            assert(panel:configure('setup')); local request=panel.pending.id
            controller.network.lastCommandResult={requestId=request,ok=false,reason='lease_expired'}
            panel:update(.01); assert(panel.pending.name=='range.acquire')
            controller.network.lastCommandResult={requestId=panel.pending.id,ok=false,reason='rate_limited'}
            panel:update(.01)
            assert(panel:available() and view.runtime.shootingRange and not panel.pending and not panel.leaseId)
            assert(not panel:canAct() and not next(panel.held)); local count=#sent
            view:keypressed('space'); panel:update(.01); assert(#sent==count and not next(panel.held))
            clock=clock+.51; panel:update(.01); assert(panel.pending.name=='range.acquire')
            ack('range.acquire'); assert(panel:available() and panel:canAct() and panel:state().roundRevision==2)
        ''')

    def test_initial_transient_acquire_retries_bounded_and_permanent_failure_closes(self):
        self.range()
        self.lua.execute('''
            assert(panel:open()); seedLane()
            for attempt=1,6 do
                assert(panel.pending and panel.pending.name=='range.acquire')
                controller.network.lastCommandResult={requestId=panel.pending.id,ok=false,reason='stale_revision'}
                panel:update(.01); assert(panel:available() and not panel:canAct())
                clock=clock+5; panel:update(.01)
            end
            assert(panel.acquireBlocked and not panel.pending); local count=#sent
            clock=clock+100; panel:update(.01); assert(#sent==count)
            view:keypressed('return'); panel:update(.01); assert(panel.pending.name=='range.acquire')
            controller.network.lastCommandResult={requestId=panel.pending.id,ok=false,reason='range_distance'}
            panel:update(.01); assert(not panel:available() and not view.runtime.shootingRange)
        ''')

    def test_closing_an_invalidated_lease_does_not_retry_release_forever(self):
        self.range()
        self.lua.execute('''
            playing(); panel:close(); assert(panel.pending.name=='range.release')
            controller.network.lastCommandResult={requestId=panel.pending.id,ok=false,reason='lease_expired'}
            panel:update(.01); assert(not panel:available() and not panel.wantRelease and not panel.pending)
            local s=panel:state(); assert(s.itemId and s.roundRevision==2 and s.loaded==12)
        ''')

    def test_real_checkpoint_wrapper_invalidates_lease_then_ui_reacquires_after_throttle(self):
        self.range()
        self.lua.execute('''
            local writesOK=true; local throttled=false; local requests={}
            local authority=require('game.coop_authority').new({campaign=data,sessionId='range-ui-checkpoint',
                clock=function() return clock end,checkpoint=function() return writesOK end})
            authority:admit('companion',7); assert(authority.bindings.companion==7)
            require('game.coop_range').install(authority,{catalog=context.catalog,
                actorState=function(id) return {screen='game',scene='stop',x=350,y=400,movementReady=true} end,
                rangeState=function() return {active=true,ready=true,paused=false} end})
            local nextId=1
            local function receive(r,id)
                controller.network.lastCommandResult={requestId=id,ok=r.ok,reason=r.reason,durable=r.durable,
                    savePending=r.savePending,revision=r.revision,details=r.result}
            end
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                local id=nextId; nextId=nextId+1
                local request={sessionId=authority.sessionId,requestId=id,sceneEpoch=epoch,command=name,args=args,expected=expected}
                requests[id]=request
                local reply
                if throttled and name=='range.acquire' then throttled=false; reply={ok=false,reason='rate_limited'}
                else reply=authority:execute('companion',7,request) end
                receive(reply,id); return id
            end
            local function publish()
                if not authority.pendingSave then
                    controller.replica.data=assert(Schema.copy(data)); controller.replica.revision=controller.replica.revision+1
                end
                assert(view:update(.01))
            end
            assert(Schema.validate(data)); assert(panel:open()); publish(); assert(panel:canAct())
            assert(panel:configure('start')); publish(); panel:aim(480,100,false); assert(panel:fire()); publish()
            assert(panel:configure('setup')); publish(); assert(panel:state().loaded==11 and reports==1)
            local oldLease=panel.leaseId; local item=panel:state().itemId; local loaded=panel:state().loaded
            data.scrap=10; publish(); writesOK=false; view:keypressed('b')
            local ammoId=panel.pending.id; publish(); assert(panel.pending and authority.pendingSave)
            local runtime={state='game',saveData=data,session={},player={x=350,y=400}}
            local app=require('game.coop_checkpoint_host').wrap({update=function() end,keypressed=function() end},
                {runtime=runtime,ui={},audio={update=function() end},commands={
                    checkpointStatus=function() return authority:checkpointStatus() end,
                    suspendActivities=function() authority:suspendActivities() end,
                    retryCheckpoint=function() return authority:retryCheckpoint() end}})
            app.update(.01); assert(next(authority.activityState.resources)==nil)
            assert(data.players.companion.ammo['22lr']==57 and data.scrap==7)
            assert(view.runtime.saveData.ammo['22lr']==39 and panel.leaseId==oldLease)
            writesOK=true; app.keypressed('r'); assert(not authority.pendingSave)
            receive(authority:execute('companion',7,requests[ammoId]),ammoId); publish()
            assert(not panel.pending and view.runtime.saveData.ammo['22lr']==57)
            throttled=true; assert(panel:configure('start')); publish(); publish()
            assert(panel:available() and not panel:canAct() and not panel.leaseId and not next(panel.held))
            clock=clock+.6; publish(); publish()
            assert(panel:canAct() and panel.leaseId~=oldLease and panel:state().itemId==item and panel:state().loaded==loaded)
            assert(panel:configure('start')); publish(); assert(panel:state().phase=='play')
            assert(data.players.companion.ammo['22lr']==57 and data.scrap==7 and reports==1 and panel:state().loaded==11)
        ''')

    def test_visible_touch_pause_button_requires_checked_resume_and_neutral_fire(self):
        self.range()
        self.lua.execute('''
            playing(); panel.held.mouse=true; local r=panel:pauseRect()
            view:touchpressed('pause',r.x+r.w/2,r.y+r.h/2); view:touchreleased('pause',0,0); panel:update(.01)
            assert(panel.paused and not next(panel.held) and not panel:canAct())
            assert(sent[2].args.action=='pause' and sent[2].args.paused==true)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,action='pause',paused=true})
            assert(panel.serverPaused and not panel:canAct())
            view:touchpressed('resume',r.x+r.w/2,r.y+r.h/2); view:touchreleased('resume',0,0); panel:update(.01)
            assert(not panel.paused and sent[3].args.paused==false and not panel:canAct())
            view:touchpressed('held-fire',450,675); assert(not next(panel.held) and #sent==3)
            ack('range.configure',{actorId='companion',spotId=panel.spotId,action='pause',paused=false})
            assert(panel:canAct() and not next(panel.held) and not panel.fireTouch)
            local copy=panel:pauseRect(); copy.x=900; assert(panel:pauseRect().x==20)
            view:mousepressed(r.x+r.w/2,r.y+r.h/2,1,false); assert(panel.paused)
        ''')


if __name__ == '__main__':
    unittest.main()
