"""Actual ambush Source pause/readiness against unmodified enemy timing."""
import unittest
import test_coop_guns_behavior as guns


class AmbushReadinessTests(unittest.TestCase):
    setUp = guns.AmbushCommandTests.setUp

    def source(self):
        self.lua.execute('''
            setup(); data.scene='train'; data.trainAmbush=nil
            Rules=require('game.train_ambush_rules'); Personal=require('game.coop_ambush_state')
            Shooting=require('game.first_person_shooting'); Sessions=require('game.coop_shooter_sessions')
            convoy=Rules.start(data); hgun=Shooting.new(host,Catalog,convoy,960,720)
            Personal.owner(convoy,'companion',true); ggun=Shooting.new(guest,Catalog,convoy,960,720)
            ids={'host','companion'}; menuPaused=false; reports=0
            Shooting.playReport=function() reports=reports+1 end
            runtime={state='game',saveData=data,session={networkMode='host'}}
            input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings={axisValue=function() return 0 end},writeSave=function() end,enterStop=function() end,
                participants=function() return ids end,inputPaused=function() return menuPaused end})
            input:mousemoved(250,250,0,0,false)
            function advance(seconds) for _=1,math.ceil(seconds/.1) do input:update(seconds/math.ceil(seconds/.1)) end end
        ''')

    def test_paused_host_with_ready_guest_targets_guest_and_keeps_shared_simulation(self):
        self.source()
        self.lua.execute('''
            input:keypressed('p',nil,false); local hp=host.health; local guestHP=guest.health
            advance(5)
            assert(convoy.clock>4.9 and reports>0 and convoy.trainDamage>0)
            assert(host.health==hp and convoy.playerDamage==0 and guest.health<guestHP)
            for _,v in ipairs(convoy.vehicles) do for _,crew in ipairs(v.crew) do
                if crew.targetActorId then assert(crew.targetActorId=='companion') end
            end end
            assert(input:commandState('host').paused and not input:commandState('companion').paused)
        ''')

    def test_no_ready_participant_freezes_convoy_guns_reload_and_health(self):
        self.source()
        self.lua.execute('''
            ids={'host'}; menuPaused=true
            assert(Shooting.fire(hgun,host,convoy)); assert(Shooting.reload(hgun,host,convoy)); ggun.cooldown=.5
            local clock,phase,timer,mag=convoy.clock,convoy.phase,hgun.reloadTimer,hgun.magazine
            local hp,guestHP,condition=host.health,guest.health,data.maintenance.condition
            advance(10)
            assert(convoy.clock==clock and convoy.phase==phase and hgun.reloadTimer==timer and hgun.magazine==mag)
            assert(host.health==hp and guest.health==guestHP and data.maintenance.condition==condition and reports==0)
            menuPaused=false; advance(.2); assert(convoy.clock>clock and hgun.reloadTimer<timer)
        ''')

    def test_normal_ready_host_and_guest_remain_real_enemy_targets(self):
        self.source()
        self.lua.execute('''
            local hp,guestHP=host.health,guest.health; advance(5)
            assert(convoy.clock>4.9 and host.health<hp and guest.health<guestHP and reports>=2)
            local seen={}; for _,v in ipairs(convoy.vehicles) do for _,crew in ipairs(v.crew) do
                if crew.targetActorId then seen[crew.targetActorId]=true end
            end end
            assert(seen.host and seen.companion and convoy.trainDamage>0)
        ''')

    def test_offline_private_pause_and_resume_preserve_original_timing(self):
        self.source()
        self.lua.execute('''
            runtime.session.networkMode='offline'; ids={'host'}; input:keypressed('p',nil,false)
            advance(5); assert(convoy.clock==0 and reports==0)
            input:keypressed('p',nil,false); advance(5)
            assert(convoy.clock>4.9 and convoy.playerDamage>0 and convoy.trainDamage>0)
        ''')


class AmbushProgressionTests(unittest.TestCase):
    setUp = guns.AmbushCommandTests.setUp

    def progression(self):
        self.lua.execute('''
            setup(); data.scene='train'; data.trainAmbush=nil
            Rules=require('game.train_ambush_rules'); Shooting=require('game.first_person_shooting')
            Personal=require('game.coop_ambush_state'); Sessions=require('game.coop_shooter_sessions')
            convoy=Rules.start(data); hgun=Shooting.new(host,Catalog,convoy,960,720)
            Personal.owner(convoy,'companion',true); ggun=Shooting.new(guest,Catalog,convoy,960,720)
            states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
            ready={active=true,paused=false,encounterId=convoy.entityId}
            ctx={catalog=Catalog,actorState=function(id) return states[id] end,ambushState=function() return ready end}
            require('game.coop_ambush_progression').install(service,ctx)
            function progress(id,name,extra)
                local a={encounterId=convoy.entityId}; for k,v in pairs(extra or {}) do a[k]=v end
                return run(id,name,a)
            end
            writes=0
        ''')

    def test_start_restores_only_existing_active_encounter_without_refill_or_reset(self):
        self.progression()
        self.lua.execute('''
            assert(Shooting.fire(hgun,host,convoy)); assert(Shooting.reload(hgun,host,convoy))
            local timer,mag,clock,item=hgun.reloadTimer,hgun.magazine,convoy.clock,hgun.itemId
            local r=progress('host','ambush.start'); assert(r.ok and r.durable and writes==1)
            assert(convoy.clock==clock and convoy.weaponSession.reloadTimer==timer and convoy.weaponSession.magazine==mag
                and convoy.weaponSession.itemId==item and host.ammo['22lr']==19)
            assert(progress('companion','ambush.start').reason=='host_only')
            data.trainAmbush=nil; assert(progress('host','ambush.start').reason=='ambush_unavailable')
        ''')

    def test_withdraw_failure_replay_applies_original_train_cost_once(self):
        self.progression()
        self.lua.execute('''
            local before=data.maintenance.condition or 72
            local request=assert(service:prepareRequest('host','ambush.withdraw',{encounterId=convoy.entityId}))
            failSave=true; local r=service:execute('host',0,request)
            assert(r.ok and r.savePending and convoy.outcome=='withdrawn' and data.maintenance.condition==before-6)
            assert(service:execute('host',0,request).savePending and data.maintenance.condition==before-6)
            assert(progress('host','ambush.continue').reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('host',0,request).durable and data.maintenance.condition==before-6)
            assert(progress('host','ambush.withdraw').reason=='withdraw_unavailable')
        ''')

    def test_host_continuation_places_both_actors_and_preserves_personal_costs(self):
        self.progression()
        self.lua.execute('''
            assert(Shooting.fire(hgun,host,convoy)); assert(Shooting.fire(ggun,guest,convoy))
            local hm,gm=hgun.magazine,ggun.magazine; local hostHP,guestHP=host.health,guest.health
            assert(progress('host','ambush.withdraw').ok)
            Rules.update(data,convoy,2.1,nil,{'host','companion'})
            local epoch=data.coop.sceneEpoch; local r=progress('host','ambush.continue')
            assert(r.ok and r.durable and r.result.partyTransition and data.scene=='stop' and not convoy.active)
            assert(data.coop.sceneEpoch==epoch+1 and r.result.actors.host and r.result.actors.companion)
            assert(host.ammo['22lr']==19 and guest.ammo['22lr']==8 and host.health==hostHP and guest.health==guestHP)
            assert(convoy.weaponSession.magazine==hm and convoy.shooterSessions.companion.weaponSession.magazine==gm)
            assert(Schema.validate(saved) and saved.scene=='stop' and not saved.trainAmbush.active)
            assert(progress('companion','ambush.continue').reason=='host_only')
        ''')

    def test_invalid_story_claims_result_early_continue_and_nonexistent_retry_rejected(self):
        self.progression()
        self.lua.execute('''
            assert(progress('host','ambush.continue').reason=='result_unavailable')
            assert(progress('host','ambush.retry').reason=='retry_unavailable')
            for _,extra in ipairs({{outcome='crew'},{reward=99},{scene='stop'},{actorId='companion'},{phase='result'}}) do
                assert(progress('host','ambush.withdraw',extra).reason=='invalid_args')
            end
            ready.paused=true; assert(progress('host','ambush.withdraw').reason=='ambush_unavailable')
            ready.paused=false; states.host.traveling=true
            assert(progress('host','ambush.withdraw').reason=='ambush_unavailable')
            assert(writes==0 and convoy.outcome==nil)
        ''')

    def test_actual_runtime_source_continue_waits_for_save_and_applies_party_once(self):
        self.progression()
        self.lua.execute('''
            local session=require('game.game_session').new(); local applications,directSaves=0,0
            data.coop.randomState=728431
            runtime={state='game',scene='train',saveData=data,player={x=host.playerX,y=host.playerY}}
            session:activate(data,runtime.player); session:setScreen('game'); session.networkMode='host'; runtime.session=session
            local input; local commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                clock=function() return 0 end,ambushState=function(id) return input and input:commandState(id) end,
                checkpoint=function(value) writes=writes+1;if failSave then return false end;saved=assert(Schema.copy(value));return true end,
                applyParty=function(result) applications=applications+1;session:acceptPartyState(result);runtime.scene=result.scene end})
            input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings={axisValue=function() return 0 end},participants=function() return {'host'} end,
                writeSave=function() directSaves=directSaves+1 end,enterStop=function() error('direct enterStop invoked') end,
                submit=commands.submit})
            input:mousemoved(250,250,0,0,false)
            assert(data.trainAmbush.weaponSession and writes>0)
            failSave=true; input:keypressed('x',nil,false)
            assert(session.checkpointPending and data.trainAmbush.outcome=='withdrawn' and directSaves==0)
            failSave=false; assert(commands.retryCheckpoint())
            Rules.update(data,data.trainAmbush,2.1,nil,{'host'})
            local epoch=data.coop.sceneEpoch; failSave=true; input:keypressed('return',nil,false)
            assert(session.checkpointPending and data.scene=='stop' and runtime.scene=='train' and applications==0)
            assert(data.coop.sceneEpoch==epoch+1 and not data.trainAmbush.active and directSaves==0)
            failSave=false; assert(commands.retryCheckpoint())
            assert(runtime.scene=='stop' and applications==1 and saved.scene=='stop' and not saved.trainAmbush.active)
            assert(commands.retryCheckpoint() and applications==1)
            assert(data.players.host.ammo['22lr']==20 and data.players.companion.ammo['22lr']==9)
        ''')

    def test_natural_terminal_reward_is_checkpointed_once_and_hidden_until_retry(self):
        self.progression()
        self.lua.execute('''
            runtime={state='game',scene='train',saveData=data,session={networkMode='host'}}
            local input; local checkpoints=0
            input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings={axisValue=function() return 0 end},participants=function() return {'host','companion'} end,
                writeSave=function() end,enterStop=function() error('undurable natural result continued') end,
                submit=function(name,args) return service:submitLocal(name,args) end,
                checkpointSettlement=function() checkpoints=checkpoints+1;return service:checkpointNow() end,
                checkpointPending=function() return service.pendingSave~=nil end})
            ctx.ambushState=function(id) return input:commandState(id) end
            input:mousemoved(250,250,0,0,false)
            input:keypressed('p',nil,false)
            local scrap=data.scrap; local before=assert(Schema.copy(saved))
            -- A legitimately retained lane with its final crews already down:
            -- original Rules.update is responsible for natural completion.
            convoy.phase='combat'
            for _,v in ipairs(convoy.vehicles) do for _,crew in ipairs(v.crew) do crew.hp=0;crew.phase='down' end end
            failSave=true; input:update(.1)
            assert(checkpoints==1 and service.pendingSave and convoy.outcome=='crew' and convoy.reward==5)
            assert(data.scrap==scrap+5 and saved.scrap==before.scrap and saved.trainAmbush.outcome==nil)
            local clock=convoy.clock
            for _=1,5 do input:update(.1); input:keypressed('return',nil,false) end
            assert(convoy.clock==clock and data.scrap==scrap+5 and checkpoints==1 and data.scene=='train')
            failSave=false; assert(service:retryCheckpoint())
            local loaded=assert(Schema.migrate(saved))
            assert(loaded.trainAmbush.outcome=='crew' and loaded.trainAmbush.reward==5 and loaded.scrap==scrap+5)
            input:update(.1); assert(not service.pendingSave and checkpoints==1 and data.scrap==scrap+5)
            assert(input:commandState('host').paused and not input:commandState('companion').paused)
            assert(service:retryCheckpoint() and data.scrap==scrap+5)
        ''')


if __name__ == '__main__':
    unittest.main()
