"""First joining a battle enters durably at a safe turn boundary."""
import unittest
import test_coop_local_play_behavior as lifecycle


class BattleAdmissionTests(unittest.TestCase):
    setUp = lifecycle.LocalPlayTests.setUp
    tearDown = lifecycle.LocalPlayTests.tearDown
    enable_cars = lifecycle.LocalPlayTests.enable_cars

    def solo_battle(self):
        self.enable_cars()
        self.lua.execute('''
            assert(host:host()); Catalog=require('game.catalog'); Players=require('game.coop_players')
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',maxHP=100,mobFiles={Catalog.mobTiers.easy[1]}}
            require('game.coop_entities').ensure(data)
            assert(commands.submit('battle.begin',{encounterId=data.encounters['2'].entityId}).ok)
            b=data.tacticalBattle.battle; hostRuntime.battle=b; b.intro=nil
            enemyId=b.units[2].id; tile=b.tiles[4][3]; round=b.round
            function endTurn()
                local s=data.tacticalBattle
                local r=commands.submit('battle.endTurn',{encounterId=s.encounterId,turnRevision=s.revision,unitId=b.units[b.active].id})
                b=data.tacticalBattle.battle; hostRuntime.battle=b; return r
            end
            function joinBattle()
                assert(guest:join()); step(4); assert(host:pending()); assert(host:approve()); step(12)
                assert(guest.phase=='connected',guest.error)
            end
        ''')

    def test_first_join_queues_then_inserts_owned_unit_without_rebuilding_board(self):
        self.solo_battle()
        self.lua.execute('''
            joinBattle(); assert(#b.units==2 and b.pendingActorId=='companion')
            assert(saved.tacticalBattle.battle.pendingActorId=='companion' and saved.players.companion)
            local rng=data.coop.randomState; assert(endTurn().ok)
            assert(#b.units==3 and not b.pendingActorId and b.units[2].actorId=='companion' and b.active==2)
            assert(b.units[3].id==enemyId and b.units[3].hp==100 and b.tiles[4][3]==tile and b.round==round)
            assert(data.coop.randomState==rng and b.units[2].file==data.players.companion.character)
            assert(saved.tacticalBattle.battle.units[2].actorId=='companion' and require('game.tactical_battle_state').validate(saved))
        ''')

    def test_pending_and_owned_roster_survive_reconnect_without_duplicate_units(self):
        self.solo_battle()
        self.lua.execute('''
            joinBattle(); local revision=data.tacticalBattle.revision; guest:stop(); host:update()
            assert(guest:join()); step(18); assert(guest.phase=='connected' and #b.units==2 and b.pendingActorId=='companion')
            assert(data.tacticalBattle.revision==revision); assert(endTurn().ok)
            guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.phase=='connected' and #b.units==3 and not b.pendingActorId)
            local loaded=assert(Schema.migrate(saved)); assert(#loaded.tacticalBattle.battle.units==3)
        ''')

    def test_failed_enrollment_save_retries_one_pending_entry_without_reapplying_potion(self):
        self.solo_battle()
        self.lua.execute('''
            assert(guest:join()); step(4); failSave=true
            local ok,reason=host:approve(); assert(not ok and reason=='save_not_ready' and service.pendingSave)
            assert(data.players.companion and b.pendingActorId=='companion' and #b.units==2)
            local revision=data.tacticalBattle.revision; failSave=false; assert(service:retryCheckpoint())
            assert(host:approve()); step(12); assert(guest.phase=='connected' and data.tacticalBattle.revision==revision)
            local a=Players.forActor(data,'companion'); a.nextBattlePotions['red-potion-vial']=true
            assert(endTurn().ok); local aim=b.units[2].aim
            assert(next(a.nextBattlePotions)==nil)
            service:disconnect('companion',host.generation)
            local s=data.tacticalBattle
            assert(commands.submit('battle.endTurn',{encounterId=s.encounterId,turnRevision=s.revision,unitId=b.units[2].id}).ok)
            assert(#b.units==3 and b.units[2].aim==aim)
        ''')

    def test_host_retreat_can_discard_pending_board_but_keeps_enrolled_character(self):
        self.solo_battle()
        self.lua.execute('''
            joinBattle(); local s=data.tacticalBattle; local item=data.players.companion.itemSlots.equipment[1].id
            assert(commands.submit('battle.retreat',{encounterId=s.encounterId,turnRevision=s.revision}).ok)
            assert(not data.tacticalBattle and data.players.companion.itemSlots.equipment[1].id==item)
            hostRuntime.battle=nil
            assert(commands.submit('battle.begin',{encounterId=data.encounters['2'].entityId}).ok)
            assert(data.tacticalBattle.battle.units[2].actorId=='companion' and not data.tacticalBattle.battle.pendingActorId)
        ''')
