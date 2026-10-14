"""Source host controls advance one shared fight while private controls pause."""
import unittest
import test_coop_last_stand_state_behavior as combat


class LastStandSourceTests(unittest.TestCase):
    def setUp(self):
        combat.LastStandStateTests.setUp(self)
        self.lua.execute('''
            Life=require('game.coop_last_stand_lifecycle'); Position=require('game.coop_last_stand_position_state')
            Life.ensure(data); Position.ensure(data); assert(Position.claim(data,'host','wide'))
            companion.windowId='tall'; assert(Position.claim(data,'companion','tall'))
            love.keyboard={isDown=function() return false end}
            runtime={saveData=data,player={x=400,y=500,speed=185},scene='stop',state='game',
                session={networkMode='host',checkpointPending=false},
                lastStand={mode='shootout',capture=true,quest=quest,shootout=battle}}
            privatePaused=false; globallyBlocked=false; selectedSavePending=false; positionReady=true
            actors={'host','companion'}; submissions={}; saves=0
            local bindings={actionDown=function() return false end,translateButton=function() return nil end,
                movement=function() return 0,0 end,axisValue=function() return 0 end}
            context={runtime=runtime,catalog=Catalog,writeSave=function() saves=saves+1; return true end,
                characterImages={},width=960,height=720,controlBindings=bindings,
                inputPaused=function() return privatePaused end,
                globalSimulationBlocked=function() return globallyBlocked end,
                participants=function() return actors end,
                positionStatus=function(id)
                    if not positionReady or not Position.selected(data,id) then return nil end
                    return {windowId=Position.selected(data,id),leaseId='p1',phaseRevision=quest.combat.phaseRevision}
                end,
                submit=function(name,args)
                    submissions[#submissions+1]={name=name,args=args}
                    if name=='lastStand.position' then
                        if positionDenied then return {ok=false,reason='position_occupied'} end
                        assert(Position.claim(data,'host',args.window)); positionReady=true
                        if selectedSavePending then runtime.session.checkpointPending=true end
                        return {ok=true,savePending=selectedSavePending,result={windowId=args.window}}
                    end
                    return {ok=false,reason='test_denied'}
                end}
            Source=require('game.last_stand_quest').new(context)
            function sourceTick(dt) return Source:update(dt) end
            function submitted(name)
                local count=0; for _,entry in ipairs(submissions) do if entry.name==name then count=count+1 end end
                return count
            end
            function interior()
                assert(Life.move(quest,'interior')); Life.ensure(data); quest.state='interior'
                local scene=require('game.last_stand_scene').new('interior',quest)
                scene.player.x=350; scene.player.y=300; Life.bind(scene.player,data,'host',true)
                runtime.lastStand={mode='interior',capture=true,quest=quest,scene=scene}
            end
        ''')

    def test_private_host_pause_advances_only_ready_guest_once_and_neutralizes_held_inputs(self):
        self.lua.execute('''
            runtime.lastStand.paused=true; actors={'host','companion','companion'}
            battle.fireHeldSources={keyboard=true}; hgun.fireHeld=true; hgun.fireMode='auto'
            hgun.cooldown=.8; ggun.cooldown=.8; local clock=battle.clock; local elapsed=battle.elapsed
            local ammo=host.ammo['22lr']; sourceTick(.2)
            assert(battle.clock==clock+.2 and battle.elapsed==elapsed+.2)
            assert(hgun.cooldown==.8 and math.abs(ggun.cooldown-.6)<.000001)
            assert(not hgun.fireHeld and not next(battle.fireHeldSources) and host.ammo['22lr']==ammo)
            assert(submitted('lastStand.advance')==0)
        ''')

    def test_host_menu_pause_does_not_pause_guest_or_accept_host_fire(self):
        self.lua.execute('''
            privatePaused=true; local clock=battle.clock; local ammo=host.ammo['22lr']
            Source:keypressed('space'); Source:mousepressed(480,300,1)
            sourceTick(.2); assert(battle.clock==clock+.2 and host.ammo['22lr']==ammo)
            assert(not hgun.fireHeld and #submissions==0)
            assert(Source:positionCommandState('host').paused and not Source:positionCommandState('companion').paused)
            assert(Source:commandState('companion').active)
        ''')

    def test_global_save_barrier_and_scene_block_freeze_both_actors(self):
        self.lua.execute('''
            runtime.session.checkpointPending=true; hgun.fireHeld=true
            local clock,ht,gt=battle.clock,hgun.cooldown,ggun.cooldown
            sourceTick(.2); assert(battle.clock==clock and hgun.cooldown==ht and ggun.cooldown==gt and not hgun.fireHeld)
            runtime.session.checkpointPending=false; globallyBlocked=true; sourceTick(.2)
            assert(battle.clock==clock and Source:positionCommandState('companion').paused)
        ''')

    def test_no_readied_actor_freezes_enemy_and_gun_time(self):
        self.lua.execute('''
            actors={}; local clock,elapsed=battle.clock,battle.elapsed; ggun.cooldown=.8
            sourceTick(.2); assert(battle.clock==clock and battle.elapsed==elapsed and ggun.cooldown==.8)
        ''')

    def test_inactive_guest_has_no_automatic_timer_updates(self):
        self.lua.execute('''
            actors={'host'}; hgun.cooldown=.8; ggun.cooldown=.8
            sourceTick(.2); assert(math.abs(hgun.cooldown-.6)<.000001 and ggun.cooldown==.8)
        ''')

    def test_intermission_retreat_and_victory_wait_for_host_controls(self):
        self.lua.execute('''
            for _,result in ipairs({'intermission','retreat','victory'}) do
                submissions={}; battle.result=result; runtime.lastStand.paused=true
                sourceTick(.1); assert(submitted('lastStand.advance')==0 and runtime.lastStand.mode=='shootout')
                runtime.lastStand.paused=false; sourceTick(.1)
                assert(submitted('lastStand.advance')==1)
            end
        ''')

    def test_offline_pause_retains_original_simulation_pause(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; runtime.lastStand.paused=true
            local clock=battle.clock; sourceTick(.2); assert(battle.clock==clock)
        ''')

    def test_position_selection_is_checked_before_handoff_and_waits_for_durable_save(self):
        self.lua.execute('''
            interior(); selectedSavePending=true; Source:keypressed('e')
            assert(submitted('lastStand.position')==1 and not runtime.lastStand.handoff)
            assert(runtime.lastStand.pendingPosition and runtime.session.checkpointPending)
            sourceTick(1); assert(not runtime.lastStand.handoff and submitted('lastStand.start')==0)
            selectedSavePending=false; runtime.session.checkpointPending=false; sourceTick(.01)
            assert(runtime.lastStand.handoff and runtime.lastStand.handoff.window=='wide')
            sourceTick(.8); assert(submitted('lastStand.start')==1)
        ''')

    def test_occupied_selection_does_not_start_or_present_a_handoff(self):
        self.lua.execute('''
            interior(); positionDenied=true; Source:keypressed('e')
            assert(submitted('lastStand.position')==1 and not runtime.lastStand.handoff)
            sourceTick(1); assert(submitted('lastStand.start')==0)
        ''')

    def test_old_pending_position_cannot_handoff_after_scene_change(self):
        self.lua.execute('''
            interior(); selectedSavePending=true; Source:keypressed('e')
            assert(Life.move(quest,'backyard')); Life.ensure(data)
            selectedSavePending=false; runtime.session.checkpointPending=false; sourceTick(.01)
            assert(not runtime.lastStand.pendingPosition and not runtime.lastStand.handoff)
        ''')

    def test_missing_occupancy_uses_raw_phase_to_reclaim_before_gun_commands(self):
        self.lua.execute('''
            positionReady=false; assert(Source:positionCommandState('host').active and not Source:commandState('host'))
            sourceTick(.1); assert(submitted('lastStand.position')==1)
            local request=submissions[1].args
            assert(request.action=='ready' and request.window=='wide' and request.phaseRevision==quest.combat.phaseRevision)
            assert(Source:commandState('host').windowId=='wide' and Source:commandState('host').leaseId=='p1')
        ''')

    def test_host_can_reclaim_remaining_window_after_guest_claims_old_window(self):
        self.lua.execute('''
            Position.release(data,'host'); Position.release(data,'companion'); assert(Position.claim(data,'companion','wide'))
            positionReady=false; sourceTick(.1)
            assert(submitted('lastStand.position')==1 and submissions[1].args.window=='tall')
        ''')

    def test_guest_only_spawn_checks_guest_window_apertures(self):
        self.lua.execute('''
            runtime.lastStand.paused=true; actors={'companion'}
            Window.pointOpen=function(window) return window=='tall' end
            for _,target in ipairs(battle.targets) do target.timer=-1 end
            sourceTick(.1); local spawned=false
            for _,target in ipairs(battle.targets) do if target.status=='appearing' then spawned=true end end
            assert(spawned)
        ''')

    def test_guest_draw_state_does_not_bind_or_create_persisted_sessions(self):
        self.lua.execute('''
            local before=Schema.copy(data); local copy=Schema.copy(data)
            local actor=Players.forActor(copy,'companion')
            local gun=Sessions.view(copy.lastStand.shooterSessions.companion.weaponSession,960,720)
            local view=assert(Shootout.guestView(copy.lastStand,actor,gun,960,720))
            assert(view.guestPresentation and not State.record(view) and view.windowId=='tall' and view.targets==copy.lastStand.targets)
            local Codec=require('game.net.codec'); assert(Codec.encode(data)==Codec.encode(before))
            local clock=battle.clock; local _,reason=Shootout.update(companion,.1,guest,Catalog,960,720,{'companion'})
            assert(reason=='host_only' and battle.clock==clock)
        ''')

    def test_legacy_standalone_offline_data_can_select_a_window_without_actor_records(self):
        self.lua.execute('''
            local legacy={character=data.character,health=20,maxHealth=20,ammo={},equipment={},inventory={},
                lastStand={state='interior',originStop=12,loanActive=true,loanAmmo=48}}
            local scene=require('game.last_stand_scene').new('interior',legacy.lastStand)
            scene.player.x=350; scene.player.y=285
            runtime.saveData=legacy; runtime.session.networkMode='offline'
            runtime.lastStand={mode='interior',capture=true,quest=legacy.lastStand,scene=scene}
            Source:keypressed('e')
            assert(runtime.lastStand.handoff and runtime.lastStand.handoff.window=='wide' and #submissions==0)
        ''')

    def test_controller_start_can_resume_internal_pause_without_repeated_held_toggles(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; local buttons={start=true}
            love.joystick={getJoysticks=function() return {{isGamepad=function() return true end,
                isGamepadDown=function(_,button) return buttons[button]==true end}} end}
            context.controlBindings.translateButton=function(_,button) return button=='start' and 'p' or nil end
            sourceTick(.01); assert(runtime.lastStand.paused)
            sourceTick(.01); assert(runtime.lastStand.paused, 'held Start toggled pause repeatedly')
            buttons.start=false; sourceTick(.01); assert(runtime.lastStand.paused)
            buttons.start=true; sourceTick(.01); assert(not runtime.lastStand.paused, 'Start could not resume')
            sourceTick(.01); assert(not runtime.lastStand.paused, 'held Start paused again after resume')
        ''')

    def test_offline_reload_then_rehost_preserves_saved_host_farmhouse_pose(self):
        self.lua.execute('''
            for _,row in ipairs({{mode='interior',x=350,y=300},{mode='backyard',x=750,y=455}}) do
                assert(Life.move(quest,row.mode)); Life.ensure(data)
                local savedPose=Life.pose(data,'host'); savedPose.x,savedPose.y,savedPose.facing=row.x,row.y,-1
                local guestPose=Life.pose(data,'companion'); local gx,gy=guestPose.x,guestPose.y
                runtime.lastStand=nil; runtime.session.networkMode='offline'
                sourceTick(0); local player=runtime.lastStand.scene.player
                assert(player.x==row.x and player.y==row.y and player.facing==-1)
                runtime.session.networkMode='host'; sourceTick(0)
                assert(savedPose.x==row.x and savedPose.y==row.y and savedPose.facing==-1)
                assert(guestPose.x==gx and guestPose.y==gy)
            end
        ''')

    def test_canonical_offline_movement_updates_saved_modal_pose_before_rehosting(self):
        self.lua.execute('''
            assert(Life.move(quest,'interior')); Life.ensure(data)
            local savedPose=Life.pose(data,'host'); savedPose.x,savedPose.y=400,300
            runtime.lastStand=nil; runtime.session.networkMode='offline'; sourceTick(0)
            runtime.lastStand.scene.player.x=450; runtime.lastStand.scene.player.y=310
            assert(savedPose.x==450 and savedPose.y==310)
            runtime.session.networkMode='host'; sourceTick(0)
            assert(runtime.lastStand.scene.player.x==450 and runtime.lastStand.scene.player.y==310)
        ''')

    def test_title_hosting_intent_freezes_offline_restore_until_host_success(self):
        self.lua.execute('''
            local pending=true; context.hostSavedJourneyPending=function() return pending end
            local phase,clock,mode,life=quest.combat.phaseRevision,quest.combat.clock,quest.state,quest.lifecycle.revision
            local ownGun,otherGun=quest.weaponSession,quest.shooterSessions.companion.weaponSession
            runtime.lastStand=nil; runtime.session.networkMode='offline'
            sourceTick(.5); sourceTick(1)
            assert(runtime.lastStand==nil and quest.state==mode and quest.lifecycle.revision==life)
            assert(quest.combat.clock==clock and quest.combat.phaseRevision==phase)
            pending=false; runtime.session.networkMode='host'; sourceTick(0)
            assert(runtime.lastStand.mode=='shootout' and quest.lifecycle.revision==life and quest.combat.phaseRevision==phase)
            assert(quest.weaponSession==ownGun and quest.shooterSessions.companion.weaponSession==otherGun)
        ''')

    def test_cancelled_title_hosting_intent_restores_original_offline_mode_policy(self):
        self.lua.execute('''
            local pending=true; context.hostSavedJourneyPending=function() return pending end
            runtime.lastStand=nil; runtime.session.networkMode='offline'; sourceTick(1)
            assert(runtime.lastStand==nil and quest.state=='shootout')
            pending=false; sourceTick(0)
            assert(runtime.lastStand.mode=='interior' and quest.state=='interior' and quest.lifecycle.mode=='interior')
        ''')

    def story_authority(self):
        self.lua.execute('''
            local Authority=require('game.coop_authority'); failStorySave=false
            story=Authority.new({campaign=data,sessionId='source-story-controls',checkpoint=function(value)
                if failStorySave then return false end; disk=assert(Schema.copy(value)); return true end})
            require('game.coop_last_stand_progression').install(story,{catalog=Catalog,
                actorState=function() return {screen=runtime.state,scene=runtime.scene,x=runtime.player.x,y=runtime.player.y} end,
                lastStandScene=function() return Source:progressionState() end})
            context.submit=function(name,args)
                submissions[#submissions+1]={name=name,args=args}
                local reply=story:submitLocal(name,args); runtime.session.checkpointPending=story.pendingSave~=nil; return reply
            end
            function retryStory()
                failStorySave=false; assert(story:retryCheckpoint()); runtime.session.checkpointPending=false; sourceTick(0)
            end
            function win()
                battle.result='victory'; sourceTick(0)
                assert(quest.victory and runtime.lastStand.mode=='interior' and disk.lastStand.victory)
            end
            function standAt(x,y) runtime.lastStand.scene.player.x=x; runtime.lastStand.scene.player.y=y end
        ''')

    def test_real_host_gecko_and_fox_controls_wait_for_durable_story_flags_and_reward(self):
        self.story_authority()
        self.lua.execute('''
            win(); standAt(710,335); failStorySave=true; local oldNotice=runtime.lastStand.notice.text
            Source:keypressed('e')
            assert(quest.residentChecked and quest.conversations['talk-gecko'] and runtime.session.checkpointPending)
            assert(not disk.lastStand.residentChecked and runtime.lastStand.notice.text==oldNotice)
            local count=#submissions; Source:keypressed('e'); assert(#submissions==count)
            retryStory()
            assert(disk.lastStand.residentChecked and disk.lastStand.conversations['talk-gecko'])
            assert(runtime.lastStand.notice.text=='Resident checked. Defense complete.')
            assert(runtime.lastStand.scene.player.x==710 and runtime.lastStand.scene.player.y==335)
            standAt(300,335); failStorySave=true; local scrap=data.scrap
            Source:keypressed('e'); assert(quest.rewardClaimed and data.scrap==scrap+28 and runtime.session.checkpointPending)
            assert(not disk.lastStand.rewardClaimed and runtime.lastStand.mode=='interior')
            count=#submissions; Source:keypressed('e'); assert(#submissions==count and data.scrap==scrap+28)
            retryStory(); assert(runtime.lastStand.mode=='aftermath' and disk.scrap==scrap+28 and disk.lastStand.rewardClaimed)
            Source:keypressed('e'); assert(data.scrap==scrap+28)
        ''')

    def test_real_host_scout_control_records_resident_without_changing_host_only_reward(self):
        self.story_authority()
        self.lua.execute('''
            win(); standAt(480,620); Source:keypressed('e'); assert(runtime.lastStand.mode=='backyard')
            standAt(370,410); local scrap=data.scrap
            Source:keypressed('e')
            assert(disk.lastStand.residentChecked and disk.lastStand.conversations['talk-scout'])
            assert(runtime.lastStand.notice.text=='Resident checked. Return route: backyard gate.')
            assert(data.scrap==scrap and not quest.rewardClaimed and runtime.lastStand.scene.player.x==370)
        ''')

    def test_guest_or_host_private_pause_cannot_make_resident_story_choice(self):
        self.story_authority()
        self.lua.execute('''
            win(); standAt(710,335); runtime.lastStand.paused=true; local count=#submissions
            Source:keypressed('e'); assert(#submissions==count and not quest.residentChecked)
            runtime.lastStand.paused=false; privatePaused=true; Source:keypressed('e')
            assert(#submissions==count and not quest.residentChecked)
            privatePaused=false; runtime.session.networkMode='client'; Source:keypressed('e')
            assert(#submissions==count and not quest.residentChecked
                and (not quest.conversations or not quest.conversations['talk-gecko']))
        ''')
