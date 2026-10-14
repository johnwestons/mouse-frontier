"""Normal production boss rules validate the native pilot and reward checkpoint."""
import unittest
import test_coop_battles_behavior as tactical
import test_coop_local_play_behavior as local_play


class BossPressureFixtureTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def boss(self, fail_victory=False):
        self.lua.execute('''
            setup(); Fixture=assert(loadfile('tools/guest-boss-pressure-smoke/boss_fixture.lua'))()
            data.location=Fixture.STOP; data.scene='train'; data.passengers={}; data.encounters={}
            data.events[tostring(Fixture.STOP)]={id='resolved'}; data.resources.coal=0; data.coop.randomState=583921
            data.coop.network={version=1,campaignId=string.rep('a',32),companionId=string.rep('b',32),
                credentialHash=string.rep('c',64),bindingVersion=1}
            Fixture.kit(data,'host',Catalog,false); Fixture.kit(data,'companion',Catalog,true)
            require('game.coop_encounters').install(service,{catalog=Catalog,actorState=function() return state end})
            local reply=run('host','encounter.roll',{}); assert(reply.ok,reply.reason)
            assert(begin().ok); enemyCount=Fixture.normalRoster(data)
            assert(Schema.validate(data)); initialScrap=data.scrap; initialCoal=data.resources.coal
            initialWeapon={host=data.players.host.itemSlots.equipment[2].id,companion=data.players.companion.itemSlots.equipment[2].id}
            metrics={incoming=0,shots={host=0,companion=0},heals={host=0,companion=0},moves={host=0,companion=0}}
            function play()
                for step=1,6000 do
                    if service.pendingSave then return 'pending' end
                    local b=data.tacticalBattle.battle
                    Controller.animate({battle=b},.05)
                    if b.finished then return b.finished end
                    if Fixture.quiet(b) then
                        local u=Rules.activeUnit(b); local id=u.team=='enemy' and 'host' or Actors.id(u)
                        local before={host=data.players.host.health,companion=data.players.companion.health}
                        local ammo=data.players[id].ammo['556']; local q,r=u.q,u.r
                        local reply,decision
                        if u.team=='enemy' then reply=action('host','battle.enemyTurn')
                        else
                            decision=Fixture.plan(data,b,id,Catalog,metrics.incoming>0,id=='companion' and metrics.heals.companion==0,metrics.moves[id]==0)
                            if decision then
                                if decision.kind=='weapon' then
                                    local options=require('game.battle_weapon_ownership').options(data,u,Catalog)
                                    reply=action(id,'battle.attack',{weapon=options[decision.index]})
                                elseif decision.kind=='target' then
                                    local target=Rules.unitAt(b,decision.q,decision.r)
                                    reply=action(id,'battle.attack',{weapon=b.chosenItemId or b.chosenWeapon,targetId=target.id})
                                elseif decision.kind=='move' then reply=action(id,'battle.move',{q=decision.q,r=decision.r})
                                else reply=action(id,'battle.'..decision.kind) end
                            end
                        end
                        if reply then
                            assert(reply.ok,reply.reason)
                            metrics.shots[id]=metrics.shots[id]+ammo-data.players[id].ammo['556']
                            if decision and decision.kind=='heal' then metrics.heals[id]=metrics.heals[id]+1 end
                            if decision and decision.kind=='move' then metrics.moves[id]=metrics.moves[id]+1 end
                            for _,actor in ipairs({'host','companion'}) do
                                if data.players[actor].health<before[actor] then metrics.incoming=metrics.incoming+before[actor]-data.players[actor].health end
                            end
                        end
                    end
                end
                error('normal boss pilot did not finish within bounded simulation')
            end
        ''')
        if fail_victory:
            self.lua.execute('''
                failVictory=true
                service.checkpoint=function(value)
                    if failVictory and value.tacticalBattle and value.tacticalBattle.battle.finished=='win' then return false end
                    saved=assert(Schema.copy(value));return true
                end
            ''')

    def test_legitimate_initial_kit_and_rolled_normal_boss_are_not_shortened(self):
        self.boss()
        self.lua.execute('''
            assert(enemyCount>=1 and enemyCount<=3)
            local b=data.tacticalBattle.battle; local bosses=0
            for _,u in ipairs(b.units) do
                assert(not u.perfectAccuracy)
                if u.boss then bosses=bosses+1;assert(u.hp==43 and u.maxHP==43) end
            end
            assert(bosses==1 and data.players.host.stats.level==8 and data.players.companion.stats.level==8)
            assert(data.players.companion.health==data.players.companion.maxHealth-8)
            assert(initialWeapon.host~=initialWeapon.companion and host.ammo['556']==60 and guest.ammo['556']==60)
            assert(run('companion','battle.begin',{encounterId=data.tacticalBattle.encounterId}).reason=='host_only')
        ''')

    def test_native_roster_guard_rejects_hp_one_and_perfect_accuracy(self):
        self.boss()
        self.lua.execute('''
            local copy=assert(Schema.copy(data));copy.tacticalBattle.battle.units[3].hp=1
            assert(not pcall(Fixture.normalRoster,copy))
            copy=assert(Schema.copy(data));copy.tacticalBattle.battle.units[1].perfectAccuracy=true
            assert(not pcall(Fixture.normalRoster,copy))
        ''')

    def test_public_checkpoint_is_actual_projection_and_private_ownership_rng_stay_private(self):
        self.boss()
        self.lua.execute('''
            local Net=require('game.net.game_state'); local projection=assert(Net.project(data))
            local public=Fixture.publicSignature(data); local private=Fixture.privateSignature(data)
            assert(public==Fixture.encode(Fixture.publicState(projection.view)))
            local replica=Net.replica();assert(replica:apply(assert(Net.producer():capture(data,true))))
            assert(Fixture.publicSignature(replica.data)==public)
            assert(replica.data.coop.randomState==nil and replica.data.coop.network==nil)
            local copy=assert(Schema.copy(data));copy.coop.randomState=(copy.coop.randomState+1)%2147483647
            assert(Fixture.publicSignature(copy)==public and Fixture.privateSignature(copy)~=private)
            copy=assert(Schema.copy(data));copy.players.host.inventoryCapacity=copy.players.host.inventoryCapacity+1
            assert(Fixture.privateSignature(copy)~=private)
        ''')

    def test_ready_requires_current_reliable_scene_and_presented_motion_even_after_rehost(self):
        self.boss()
        self.lua.execute('''
            local replica=assert(require('game.net.game_state').project(data)).view
            local v={ready=true,focused=true,epoch=replica.coop.sceneEpoch,motionId=5,lastSerial=9,
                modalDomain='battle-domain',runtime={scene=replica.scene,saveData=replica}}
            local f={ready=true,paused=true,sessionId='fresh',sceneEpoch=v.epoch,motionId=5,serial=9,domain=v.modalDomain}
            local lp={network={status='ready',sessionId='fresh'},clientView=v,motionFrame=f,replica={data=replica}}
            assert(Fixture.ready(lp)) -- Battle forbids walking, not acknowledged tactical controls.
            f.sessionId='old';assert(not Fixture.ready(lp));f.sessionId='fresh'
            f.serial=10;assert(not Fixture.ready(lp));f.serial=9
            f.domain='old';assert(not Fixture.ready(lp));f.domain=v.modalDomain
            v.runtime.scene='stop';assert(not Fixture.ready(lp));v.runtime.scene=replica.scene
            v.runtime.saveData=assert(Schema.copy(replica));v.runtime.saveData.location=34
            assert(not Fixture.ready(lp));v.runtime.saveData=replica
            lp.menuOpen=true;assert(not Fixture.ready(lp));lp.menuOpen=false
            v.focused=false;assert(not Fixture.ready(lp));v.focused=true
            replica.tacticalBattle=nil;assert(not Fixture.ready(lp));f.paused=false;assert(Fixture.ready(lp))
        ''')

    def test_torn_or_structurally_partial_metrics_keep_last_complete_actual_proof(self):
        self.boss()
        self.lua.execute('''
            local Codec=require('game.net.codec')
            local valid={incoming=9,shots={host=2,companion=3},heals={host=1,companion=1},moves={host=1,companion=1}}
            local bytes=assert(Codec.encode(valid));local previous=assert(Fixture.metrics(bytes))
            for _,bad in ipairs({'','9','m0:','b1:',bytes:sub(1,#bytes-1),assert(Codec.encode({incoming=9}))}) do
                assert(not Fixture.metrics(bad) and Fixture.adoptMetrics(bad,previous)==previous)
            end
            assert(Fixture.adoptMetrics(nil,previous)==previous and Fixture.adoptMetrics(false,previous)==previous)
            for _,key in ipairs({'shots','heals','moves'}) do
                for _,id in ipairs({'host','companion'}) do
                    local copy=assert(Schema.copy(valid));copy[key][id]=nil
                    assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
                    copy=assert(Schema.copy(valid));copy[key][id]='2'
                    assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
                    copy=assert(Schema.copy(valid));copy[key][id]=.5
                    assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
                end
            end
            local copy=assert(Schema.copy(valid));copy.incoming='9'
            assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
            copy=assert(Schema.copy(valid));copy.shots.host=61
            assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
            copy=assert(Schema.copy(valid));copy.incoming=8
            assert(Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)==previous)
            copy=assert(Schema.copy(valid));copy.moves.companion=2
            local fresh=Fixture.adoptMetrics(assert(Codec.encode(copy)),previous)
            assert(fresh~=previous and fresh.moves.companion==2 and fresh.incoming==9 and previous.moves.companion==1)
        ''')

    def test_readonly_pilot_completes_original_boss_with_real_moves_heal_shots_and_incoming_damage(self):
        self.boss()
        self.lua.execute('''
            assert(play()=='win'); local b=data.tacticalBattle.battle
            local reward=require('game.combat_balance').rewardProfile('hard',enemyCount,false,true)
            assert(metrics.incoming>0 and metrics.moves.companion>0 and metrics.heals.companion>0)
            assert(metrics.shots.host>0 and metrics.shots.companion>0)
            for _,id in ipairs({'host','companion'}) do
                local actor=data.players[id]
                assert(actor.ammo['556']==60-metrics.shots[id])
                assert(actor.stats.xp==reward.xp and actor.itemSlots.equipment[2].id==initialWeapon[id])
                assert(actor.itemSlots.equipment[2].durability==100-metrics.shots[id])
            end
            assert(data.scrap>initialScrap and data.resources.coal>=initialCoal+reward.coalMin)
            assert(data.encounters['35'].resolved and Schema.validate(data))
        ''')

    def test_natural_victory_failed_write_retry_projection_and_fresh_authority_preserve_reward_once(self):
        self.boss(fail_victory=True)
        self.lua.execute('''
            assert(play()=='pending'); assert(data.tacticalBattle.battle.finished=='win' and service.pendingSave)
            assert(saved.scrap==initialScrap and saved.tacticalBattle.battle.finished==nil)
            local facts=Fixture.publicSignature(data); local revision=data.coop.revision
            assert(action('host','battle.endTurn').reason=='save_pending' and data.coop.revision==revision)
            failVictory=false;assert(service:retryCheckpoint())
            assert(Fixture.publicSignature(saved)==facts and service:retryCheckpoint())
            local loaded=assert(Schema.migrate(saved)); assert(State.restore(loaded,Catalog).finished=='win')
            assert(Fixture.privateSignature(loaded)==Fixture.privateSignature(data))
            local Net=require('game.net.game_state');local producer=Net.producer();local replica=Net.replica()
            assert(replica:apply(assert(producer:capture(loaded,true))))
            assert(Fixture.publicSignature(replica.data)==facts)
            local fresh=Authority.new({campaign=loaded,sessionId='boss-fresh',randomSeed=765432,checkpoint=function() return true end})
            fresh:admit('companion',1); Commands.install(fresh,{catalog=Catalog,actorState=function() return {screen='battle',scene='train'} end})
            assert(fresh.sessionId~=service.sessionId and Fixture.publicSignature(loaded)==facts)
            assert(fresh:submitLocal('battle.continue',{encounterId=loaded.tacticalBattle.encounterId,turnRevision=loaded.tacticalBattle.revision}).ok)
            assert(not loaded.tacticalBattle and loaded.scrap==data.scrap and loaded.players.companion.stats.xp==data.players.companion.stats.xp)
        ''')


class BossRestartControllerTests(unittest.TestCase):
    setUp = local_play.LocalPlayTests.setUp
    tearDown = local_play.LocalPlayTests.tearDown

    def test_actual_leave_closes_menu_and_fixture_reopens_before_real_join(self):
        self.lua.execute('''
            ready();Fixture=assert(loadfile('tools/guest-boss-pressure-smoke/boss_fixture.lua'))()
            love.graphics={newFont=function(size) return size end,getDimensions=function() return 960,720 end,
                push=function() end,pop=function() end,origin=function() end,clear=function() end,
                translate=function() end,scale=function() end,setFont=function() end,setColor=function() end,
                rectangle=function() end,printf=function() end}
            love.keyboard={setTextInput=function() end,isDown=function() return false end}
            local ctx={runtime=guestRuntime,ui={},screenToGame=function(x,y) return x,y end}
            local panel=require('game.local_play_panel').new(guest,ctx)
            guest:open();panel:draw();local leave=assert(ctx.ui.localPlayControls.leave)
            assert(panel:click(leave.x+leave.w/2,leave.y+leave.h/2))
            assert(guest.phase=='idle' and not guest.network and guestRuntime.state=='slots' and not guest.menuOpen)
            assert(Fixture.rejoinAction(guest,'replacement',{})=='wait')
            guest:open();panel:draw();local join=assert(ctx.ui.localPlayControls.join)
            assert(join.enabled and Fixture.rejoinAction(guest,'replacement',ctx.ui.localPlayControls)=='join')
            local before=joins;assert(panel:click(join.x+join.w/2,join.y+join.h/2))
            assert(joins==before+1 and guest.network and guest.phase=='joining')
            assert(Fixture.rejoinAction(guest,'replacement',ctx.ui.localPlayControls)=='wait')
            -- Real transport exists before a replacement session ID arrives.
            assert(guest.network.sessionId==nil)
        ''')

    def test_expected_real_session_and_active_reconnect_are_preserved_or_cancelled_deliberately(self):
        self.lua.execute('''
            ready();Fixture=assert(loadfile('tools/guest-boss-pressure-smoke/boss_fixture.lua'))()
            local old=guest.network.sessionId;assert(Fixture.rejoinAction(guest,old,{})=='wait')
            assert(Fixture.rejoinAction(guest,'replacement',{})=='leave')
            guest:stop();guest:open()
            guest.reconnect:remember(guest.address,guest.name);assert(guest.reconnect:begin('host_disconnected'))
            assert(Fixture.rejoinAction(guest,'replacement',{})=='cancelReconnect')
            assert(guest:cancelReconnect());assert(not guest:reconnectStatus().active)
            assert(Fixture.rejoinAction(guest,'replacement',{join={enabled=true}})=='join')
        ''')


if __name__ == '__main__':
    unittest.main()
