"""Private guest ambush controls, bounded results and shared host simulation."""
import unittest
import test_coop_guns_behavior as guns


class GuestAmbushTests(unittest.TestCase):
    setUp = guns.AmbushCommandTests.setUp
    ambush = guns.AmbushCommandTests.ambush

    def panel(self):
        self.ambush()
        self.lua.execute('''
            local Net=require('game.net.game_state'); local Ownership=require('game.replica_ownership')
            producer=Net.producer(); replica=Net.replica(); requests={}
            network={submitCommand=function(self,name,args,epoch,expected)
                if self.pendingCommand then return nil,'command_pending' end
                local request={sessionId=service.sessionId,requestId=#requests+1,command=name,args=args,sceneEpoch=epoch,expected=expected}
                requests[#requests+1]=request; self.pendingCommand=request; return request.requestId
            end}
            bindings={axisValue=function() return 0 end,translateButton=function(self,button)
                return ({x='space',a='r',b='c',y='tab',leftshoulder='v'})[button] end}
            view={runtime={},ui={},ready=true,focused=true,paused=true,epoch=data.coop.sceneEpoch,motionId=1,elapsed=0,
                controller={network=network,menuOpen=false,motionFrame={ready=true,motionId=1,sceneEpoch=data.coop.sceneEpoch}}}
            function view.controller:open() self.menuOpen=true end
            function project()
                local packet=assert(producer:capture(data,true)); assert(replica:apply(packet))
                view.runtime.saveData=Players.forActor(Ownership.mark(assert(Schema.copy(replica.data))),'companion')
                view.runtime.scene='train'; view.revision=replica.revision
            end
            project(); panel=require('game.coop_guest_ambush').new(view,{catalog=Catalog,bindings=bindings}); panel:update(0)
            function deliver(index)
                local request=requests[index or #requests]
                local response=service:execute('companion',1,request)
                network.lastCommandResult=assert(require('game.net.commands').outcome(service.sessionId,request.requestId,response,request.command))
                if not response.savePending and response.reason~='save_pending' and response.reason~='busy' then network.pendingCommand=nil end
                return response
            end
            function accept() local result=deliver(); project(); panel:update(0); return result end
        ''')

    def enemy_audio(self):
        self.panel()
        self.lua.execute('''
            cueClock=10; reports=0; ownReports=0; network.status='ready'; network.sessionId=service.sessionId
            panel.c.clock=function() return cueClock end
            Shooting.playReport=function(name,catalog,actor,distant)
                assert(name=='frontier-22-lever-rifle' and catalog==Catalog and actor==view.runtime.saveData)
                if distant then reports=reports+1 else ownReports=ownReports+1 end
            end
            function project()
                local packet,reason=producer:capture(data); assert(not reason,reason)
                if packet then assert(replica:apply(packet)) end
                view.runtime.saveData=Players.forActor(require('game.replica_ownership').mark(assert(Schema.copy(replica.data))),'companion')
                view.runtime.scene='train'; view.revision=replica.revision
                return packet
            end
            function enemyFire(dt)
                dt=dt or .02; pickup.crew[1].phase='aim'; pickup.crew[1].timer=.01
                Ambush.update(data,convoy,dt,nil,{'host','companion'})
                cueClock=cueClock+dt; local packet=project(); panel:update(dt); return packet
            end
            panel.enemyAudio=nil; project(); panel:update(0); assert(reports==0)
        ''')

    def test_actual_rules_enemy_fire_delta_cues_once_without_campaign_revision_change(self):
        self.enemy_audio()
        self.lua.execute('''
            local sourceRevision=data.coop.revision; local wireRevision=view.revision
            local ammo=guest.ammo['22lr']; local health=guest.health
            Personal.owner(convoy,'companion').cover=true; Personal.owner(convoy,'companion').coverProgress=1
            convoy.lastTargetActorId='host'
            local packet=enemyFire()
            assert(data.coop.revision==sourceRevision and view.revision>wireRevision and packet.mode=='delta')
            assert(convoy.protection==22 and pickup.crew[1].phase=='fire' and reports==1)
            assert(view.paused and guest.health==health and guest.ammo['22lr']==ammo)
            panel:update(.02); project(); panel:update(.02); assert(reports==1)
            enemyFire(); assert(reports==2 and #requests==0 and convoy.shots==0)
        ''')

    def test_enemy_audio_baselines_encounter_network_session_epoch_and_motion_silently(self):
        self.enemy_audio()
        self.lua.execute('''
            enemyFire(); assert(reports==1)
            panel.enemyAudio=nil; enemyFire(); assert(reports==1) -- First/late-join projection contains history.
            network.sessionId='replacement-session'; enemyFire(); assert(reports==1)
            local previous=network; network={status='ready',sessionId=previous.sessionId,
                submitCommand=previous.submitCommand}; view.controller.network=network
            enemyFire(); assert(reports==1)
            view.motionId=2; view.controller.motionFrame.motionId=2; enemyFire(); assert(reports==1)
            data.coop.sceneEpoch=data.coop.sceneEpoch+1; view.epoch=data.coop.sceneEpoch
            view.controller.motionFrame.sceneEpoch=view.epoch; enemyFire(); assert(reports==1)
            enemyFire(); assert(reports==2)
        ''')

    def test_enemy_audio_consumes_pause_menu_focus_and_unready_drops_without_replay(self):
        self.enemy_audio()
        self.lua.execute('''
            local gates={
                {off=function() panel.paused=true end,on=function() panel.paused=false end},
                {off=function() view.controller.menuOpen=true end,on=function() view.controller.menuOpen=false end},
                {off=function() view.focused=false end,on=function() view.focused=true end},
                {off=function() view.ready=false end,on=function() view.ready=true end},
                {off=function() view.controller.motionFrame.ready=false end,on=function() view.controller.motionFrame.ready=true end},
            }
            for _,gate in ipairs(gates) do
                gate.off(); enemyFire(); assert(reports==0)
                gate.on(); project(); panel:update(0); assert(reports==0)
            end
            enemyFire(); assert(reports==1)
        ''')

    def test_enemy_audio_stale_packets_batches_and_terminal_phases_stay_bounded(self):
        self.enemy_audio()
        self.lua.execute('''
            cueClock=cueClock+1; enemyFire(); assert(reports==0)
            enemyFire(.4); assert(reports==0)
            pickup.crew[2].phase='aim'; pickup.crew[2].timer=.01
            local before=convoy.protection; enemyFire(); assert(convoy.protection==before-4 and reports==1)
            local observed=panel.enemyAudio; local oldRevision=view.revision
            -- Older/refilled facts cannot turn their duplicate into another cue.
            local current=view.runtime.saveData.trainAmbush
            current.clock=current.clock-.1; current.protection=current.protection+2; view.revision=view.revision+1
            panel:observeEnemyFire(current); assert(reports==1)
            project(); panel:update(0); assert(reports==1)
            convoy.phase='result'; convoy.outcome='escaped'; project(); panel:update(0)
            assert(reports==1 and #requests==0)
        ''')

    def test_owned_fire_and_withdrawal_wear_do_not_emit_enemy_audio(self):
        self.enemy_audio()
        self.lua.execute('''
            local protection=convoy.protection
            panel:aim(250,250); panel:fire(); assert(accept().ok)
            assert(reports==0 and ownReports==1 and convoy.protection==protection and convoy.shots==1)
            assert(Ambush.withdraw(data,convoy)); project(); panel:update(0)
            assert(convoy.trainDamage>=6 and reports==0 and ownReports==1)
        ''')

    def test_enemy_audio_save_pending_facts_are_consumed_quietly_and_do_not_replay(self):
        self.enemy_audio()
        self.lua.execute('''
            panel:aim(250,250); assert(panel:fire()); failSave=true; assert(deliver().savePending)
            panel:update(0); assert(panel.pending and reports==0 and ownReports==0)
            local waiting=panel:statusHint(view.runtime.saveData.trainAmbush,{cover=false})
            assert(waiting=='Waiting for the host to finish saving...')
            enemyFire(); assert(reports==0 and panel.pending)
            failSave=false; assert(service:retryCheckpoint()); assert(deliver().durable)
            project(); panel:update(0); assert(not panel.pending and reports==0 and ownReports==1)
            enemyFire(); assert(reports==1 and guest.ammo['22lr']==8)
        ''')

    def test_enemy_report_uses_existing_distant_audio_and_device_volume(self):
        self.panel()
        self.lua.execute('''
            local volumes={}; local plays=0
            love.audio={newSource=function()
                return {stop=function() end,setPitch=function() end,
                    setVolume=function(_,value) volumes[#volumes+1]=value end,play=function() plays=plays+1 end}
            end}
            network.status='ready'; network.sessionId=service.sessionId; cueClock=10
            panel.c.clock=function() return cueClock end
            local store=require('game.local_preferences').new(F.filesystem()); store.values.audio.sfxVolume=.1
            local rootData=Players.campaignOf(view.runtime.saveData); store:bind(rootData,function() return 'client' end)
            panel.enemyAudio=nil; panel:update(0)
            local function fire()
                pickup.crew[1].phase='aim'; pickup.crew[1].timer=.01
                Ambush.update(data,convoy,.02,nil,{'host','companion'}); cueClock=cueClock+.02
                project(); store:bind(Players.campaignOf(view.runtime.saveData),function() return 'client' end); panel:update(.02)
            end
            fire(); assert(plays==1 and volumes[1]>0 and volumes[1]<.1)
            store.values.audio.sfxVolume=0; fire(); assert(plays==2 and volumes[2]==0)
            assert(data.audio.sfxVolume~=.1 and data.coop.sceneEpoch==view.epoch and #requests==0)
        ''')

    def test_terminal_status_supersedes_real_stale_rejection_but_preserves_pending_save(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:fire(); assert(cover('host',true).ok)
            assert(deliver().reason=='stale_revision'); project(); panel:update(0)
            assert(panel.notice and not panel.pending)
            assert(Ambush.finish(data,convoy,'escaped')); project(); panel:update(0)
            local state=view.runtime.saveData.trainAmbush
            assert(not panel.notice and panel:statusHint(state,{cover=true})=='The convoy is falling behind. The host will continue when ready.')
            convoy.phase='result'; project(); panel:update(0); panel.paused=true
            assert(panel:statusHint(view.runtime.saveData.trainAmbush,{cover=true})=='Encounter ended. The host will continue when ready.')
            local count=#requests; panel:keypressed('return'); panel:keypressed('x'); assert(#requests==count)
            panel.pending={id=99,epoch=view.epoch,encounterId=convoy.entityId,name='gun.fire'}
            panel.notice='Waiting for the host to finish saving...'
            assert(panel:statusHint(view.runtime.saveData.trainAmbush,{cover=true})==panel.notice)
            network.lastCommandResult={requestId=99,ok=true,durable=false,savePending=true}
            panel:update(0); assert(panel.pending and panel.notice=='Waiting for the host to finish saving...')
            network.lastCommandResult={requestId=99,ok=true,durable=true,revision=data.coop.revision,details={}}
            panel:update(0); assert(not panel.pending and not panel.notice)
            assert(panel:statusHint(view.runtime.saveData.trainAmbush,{cover=true})=='Encounter ended. The host will continue when ready.')
        ''')

    def test_private_aim_ads_and_animation_never_mutate_host_or_replica_gun(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:action('aim'); panel:update(.1)
            assert(panel.gun.aimX==250 and panel.gun.ads and not ggun.ads)
            assert(not replica.data.trainAmbush.shooterSessions.companion.weaponSession.aimX)
            assert(guest.ammo['22lr']==9 and convoy.shots==0 and #requests==0)
        ''')

    def test_keyboard_fire_quotes_owned_item_and_waits_for_durable_projection(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:keypressed('space'); panel:keyreleased('space')
            local request=requests[1]; assert(request.command=='gun.fire' and request.args.weaponId==ggun.itemId)
            assert(request.args.x==math.floor(250/960*1000000+.5) and request.args.actorId==nil and request.args.damage==nil)
            assert(request.expected['player:companion']~=nil and guest.ammo['22lr']==9)
            local response=deliver(); assert(response.ok and response.durable); panel:update(0); assert(panel.pending)
            project(); panel:update(0); assert(not panel.pending and panel.lastOutcome.ok and panel.impact)
            assert(guest.ammo['22lr']==8 and host.ammo['22lr']==20 and not view.runtime.saveData.trainAmbush.weaponSession.aimX)
        ''')

    def test_pending_fire_blocks_other_sources_and_repeated_updates(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:keypressed('space'); panel:pointer(250,250,1)
            panel:update(.1); panel:keypressed('r'); assert(#requests==1 and guest.ammo['22lr']==9)
            panel:keyreleased('space'); panel:mousereleased(1); assert(accept().ok and #requests==1)
            panel:update(.1); assert(#requests==1)
        ''')

    def test_touch_drag_uses_authored_grip_and_submits_only_canonical_reticle(self):
        self.panel()
        self.lua.execute('''
            local Aim=require('game.mobile_weapon_aim')
            local x,y=Aim.gripForAim(panel.gun.weapon,'hip',250,250,960,720)
            panel:touchpressed('aim',x,y); panel:touchmoved('aim',x,y)
            assert(math.abs(panel.gun.aimX-250)<.001 and math.abs(panel.gun.aimY-250)<.001)
            local r=panel:rect(1); panel:touchpressed('fire',r.x+10,r.y+10); panel:touchreleased('fire'); panel:touchreleased('aim')
            assert(requests[1].args.x==math.floor(250/960*1000000+.5) and not next(panel.held))
            assert(not replica.data.trainAmbush.shooterSessions.companion.weaponSession.touchAim and accept().ok)
        ''')

    def test_cover_is_owned_and_transition_blocks_guest_fire_only(self):
        self.panel()
        self.lua.execute('''
            panel:keypressed('c'); assert(requests[1].command=='gun.cover' and requests[1].args.weaponId==nil)
            assert(accept().ok and convoy.defenders.companion.cover and not convoy.cover)
            panel:aim(250,250); assert(not panel:fire() and #requests==1)
            tick(.2); project(); panel:update(0); panel:keypressed('c'); assert(accept().ok)
            assert(not panel:fire()); tick(.2); project(); panel:update(0); assert(panel:fire())
        ''')

    def test_reload_uses_host_timing_and_private_frame_clock_does_not_fill_magazine(self):
        self.panel()
        self.lua.execute('''
            guest.ammo['22lr']=30; ggun.magazine=1; project(); panel:update(0)
            panel:keypressed('r'); assert(accept().ok and ggun.reloadTimer>0)
            local remaining,magazine=ggun.reloadTimer,ggun.magazine
            panel:update(.1); assert(ggun.reloadTimer==remaining and ggun.magazine==magazine and guest.ammo['22lr']==30)
            tick(.75); project(); panel:update(0); assert(panel.gun.reloadTimer==ggun.reloadTimer)
        ''')

    def test_switching_quotes_exact_owned_duplicates_and_never_selects_a_loan(self):
        self.panel()
        self.lua.execute('''
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle'); project(); panel:update(0)
            local old=panel.gun.itemId; panel:keypressed('tab')
            assert(requests[1].args.weaponId~=old and requests[1].args.borrowed==nil)
            assert(accept().ok and panel.gun.itemId~=old and host.ammo['22lr']==20)
            for _,option in ipairs(panel:options()) do assert(not option.borrowed and option.itemId) end
        ''')

    def test_bootstrap_selects_a_real_owned_gun_and_never_manufactures_ammo(self):
        self.panel()
        self.lua.execute('''
            convoy.shooterSessions.companion.weaponSession=nil; project(); panel:update(0)
            assert(requests[1].command=='gun.select' and requests[1].args.weaponId==ggun.itemId and guest.ammo['22lr']==9)
            assert(accept().ok and panel.gun.itemId==ggun.itemId and guest.ammo['22lr']==9)
        ''')

    def test_unarmed_guest_can_use_cover_without_inventing_a_loan(self):
        self.panel()
        self.lua.execute('''
            Items.write(guest,nil,{kind='equipment',index=2},nil); convoy.shooterSessions.companion.weaponSession=nil
            project(); panel:update(0); assert(#requests==0 and #panel:options()==0)
            panel:keypressed('c'); assert(accept().ok and not convoy.shooterSessions.companion.loanActive)
        ''')

    def test_pause_menu_focus_and_unready_scene_block_personal_input_only(self):
        self.panel()
        self.lua.execute('''
            assert(panel:canAct() and view.paused) -- Tactical movement is intentionally paused.
            panel:keypressed('p'); assert(not panel:fire() and #requests==0)
            panel:keypressed('p'); view.focused=false; panel:update(.1); assert(not panel:canAct())
            view.focused=true; view.controller.motionFrame.ready=false; assert(not panel:canAct())
            view.controller.motionFrame.ready=true; panel:keypressed('f8'); assert(view.controller.menuOpen and #requests==0)
            assert(convoy.clock==0 and guest.ammo['22lr']==9)
        ''')

    def test_guest_story_keys_and_results_never_submit_progression(self):
        self.panel()
        self.lua.execute('''
            panel:keypressed('x'); panel:keypressed('return'); assert(#requests==0)
            convoy.phase='result'; convoy.outcome='withdrawn'; project(); panel:update(0)
            panel:keypressed('space'); panel:keyreleased('space'); panel:keypressed('return'); panel:gamepadpressed('b')
            assert(#requests==0 and convoy.active and not panel:canAct())
        ''')

    def test_failed_save_feedback_waits_then_replay_resolves_once(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:fire(); failSave=true; assert(deliver().savePending)
            panel:update(0); assert(panel.pending and not panel.impact and #requests==1)
            failSave=false; assert(service:retryCheckpoint()); assert(deliver().durable)
            project(); panel:update(0); assert(not panel.pending and panel.impact and guest.ammo['22lr']==8)
            local impact=panel.impact; panel:update(.1); assert(panel.impact==impact and convoy.shots==1)
        ''')

    def test_new_encounter_cancels_private_pending_input_and_old_feedback(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:keypressed('space'); local old=panel.encounterId
            convoy.active=false; convoy=Ambush.start(data); convoy.phase='combat'; ready.encounterId=convoy.entityId
            project(); panel:update(0)
            assert(panel.encounterId~=old and not panel.pending and not next(panel.held))
            assert(guest.ammo['22lr']==9 and convoy.shots==0)
        ''')

    def test_public_gun_results_reject_private_fields_unknown_guns_and_invalid_counts(self):
        self.panel()
        self.lua.execute('''
            panel:aim(250,250); panel:fire(); local response=deliver()
            local R=require('game.net.gun_results'); local valid=assert(R.project('gun.fire',response.result))
            for _,edit in ipairs({function(r) r.aimX=4 end,function(r) r.weapon='invented' end,
                function(r) r.weaponId='loan' end,function(r) r.magazine=999 end,
                function(r) r.hit=1 end,function(r) r.encounterId='wrong' end}) do
                local copy=assert(Schema.copy(valid)); edit(copy); assert(not R.valid('gun.fire',copy))
            end
            response.result.aimX=500; assert(not R.project('gun.fire',response.result).aimX)
        ''')

    def test_actual_view_routes_capture_input_and_disables_normal_movement(self):
        self.panel()
        self.lua.execute('''
            local View=require('game.coop_guest_view'); view.ambush=panel
            view.actionsAllowed=function() return true end
            assert(not View.inputAllowed(view))
            View.keypressed(view,'r',nil,false); assert(requests[1].command=='gun.reload')
            View.keyreleased(view,'space'); View.gamepadreleased(view,nil,'x')
        ''')

    def test_host_shared_pause_keeps_both_guns_and_convoy_running_but_blocks_host_commands(self):
        self.panel()
        self.lua.execute('''
            local runtime={state='game',saveData=data,session={networkMode='host'}}
            local input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings=bindings,writeSave=function() end,enterStop=function() end,
                participants=function() return {'host','companion'} end})
            input:mousemoved(250,250,0,0,false); input:keypressed('p',nil,false)
            ggun.cooldown=.5; hgun.cooldown=.5; local clock=convoy.clock
            input:update(.1)
            assert(convoy.clock>clock and ggun.cooldown==.4 and hgun.cooldown==.4)
            assert(input:commandState('host').paused and not input:commandState('companion').paused)
            runtime.session.networkMode='offline'; clock=convoy.clock; input:update(.1); assert(convoy.clock==clock)
        ''')

    def test_firearm_rate_supports_authored_automatic_fire_and_retains_bounded_bursts(self):
        self.lua.execute('''
            local Rate=require('game.net.command_rate'); local link={}
            local fire={command='gun.fire',args={mode='ambush'}}
            local story={command='ambush.continue',args={}}
            for _=1,4 do assert(Rate.allow(link,fire,0) and Rate.allow(link,story,0)) end
            for _=1,100 do assert(not Rate.allow(link,fire,0) and not Rate.allow(link,story,0)) end
            for i=1,20 do
                assert(Rate.allow(link,fire,i*.1))
                if i==1 then assert(not Rate.allow(link,story,.1)) end
            end
            assert(Rate.allow(link,story,2))
            local burst={}
            for _,name in ipairs({'gun.reload','gun.cover','gun.select','gun.mode'}) do
                assert(Rate.allow(burst,{command=name,args={}},0))
            end
            assert(not Rate.allow(burst,fire,0))
            assert(Rate.allow(burst,fire,.1))
            assert(Rate.allow(burst,{command='inventory.swap',args={}},.1))
        ''')


if __name__ == '__main__':
    unittest.main()
