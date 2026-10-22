"""End-to-end large operations through the authoritative co-op command path."""
import unittest
from tools.tests import test_coop_battles_behavior as fixtures

class OperationTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.TacticalCommandTests();fixture.setUp();self.lua=fixture.lua

    def test_both_living_players_must_extract_and_kills_alone_do_not_win(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.units[3].hp=0
            local xp=host.stats.xp;assert(action('host','battle.endTurn').ok)
            assert(not b.finished and not b.encounter.resolved and host.stats.xp==xp)
            b.active=1;b.units[1].q,b.units[1].r=71,3
            assert(action('host','battle.endTurn').ok and not b.finished)
            b.units[2].q,b.units[2].r=70,5;b.active=2;b.moveUsed=false;b.phase='select'
            local reply=action('companion','battle.move',{q=71,r=5})
            assert(reply.ok,reply.reason);assert(b.finished=='win'and b.crossingComplete and host.stats.xp>xp)
            assert(State.validate(data)and State.validate(saved))
        ''')

    def test_real_commands_cross_the_full_map_and_resume_midway(self):
        self.lua.execute('''
            local Grid=require('game.battle_grid');assert(begin().ok);local b=ready()
            b.units[3].hp=0;b.obstacles={};local moves=0;local checked=false
            for turn=1,72 do
                ready();if b.finished then break end
                local u=Rules.activeUnit(b);local owner=Actors.id(u);assert(owner)
                if u.q<71 then
                    local best
                    for _,p in pairs(Grid.reachable(b,u,Grid.moveBudget(b,u)))do
                        if p.q>u.q and(not best or p.q>best.q or p.q==best.q and math.abs(p.r-u.r)<math.abs(best.r-u.r))then best=p end
                    end
                    assert(best,'march has no forward route')
                    local reply=action(owner,'battle.move',{q=best.q,r=best.r});assert(reply.ok,reply.reason);moves=moves+1
                    assert(u.q==best.q and u.r==best.r and u.moveAnim.path and #u.moveAnim.path>1)
                    if not checked and u.q>=14 and not b.finished then
                        local loaded=assert(Schema.migrate(saved));local restored=assert(State.restore(loaded,Catalog))
                        assert(restored.field.elevationData==b.field.elevationData and restored.units[1].q==b.units[1].q)
                        checked=true
                    end
                end
                if not b.finished then ready();assert(action(owner,'battle.endTurn').ok)end
            end
            assert(b.finished=='win'and moves>=8 and checked,'operation did not cross and resume the large map')
            assert(b.units[1].q==71 and b.units[2].q==71 and State.validate(saved))
        ''')

    def test_fallen_player_is_carried_out_and_npc_cannot_prevent_defeat(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.units[1].hp=0;b.units[2].q,b.units[2].r=71,5;b.active=2
            assert(action('companion','battle.endTurn').ok)
            assert(b.finished=='win'and b.units[1].hp==1 and b.units[1].q==71 and State.validate(saved))
            setup();assert(begin().ok);b=ready();b.units[1].hp=0;b.units[2].hp=0
            b.units[#b.units+1]={id='follower',team='ally',file='guard-fox.png',name='Follower',q=2,r=3,hp=10,maxHP=10,move=2,armor=1,aim=1}
            Controller.advance({battle=b,saveData=data,BattleRules=Rules,writeSave=function()end})
            assert(b.finished=='loss','living NPC caused a player-party softlock')
        ''')

    def test_boss_gate_dormant_enemies_and_march_budget(self):
        self.lua.execute('''
            local Grid=require('game.battle_grid');local Operation=require('game.battle_operation')
            assert(begin().ok);local b=ready();local enemy=b.units[3]
            enemy.q,enemy.r=30,15;enemy.alerted=false
            assert(Grid.moveBudget(b,b.units[1])>=8)
            assert(action('host','battle.endTurn').ok);assert(action('companion','battle.endTurn').ok)
            assert(b.active==1 and enemy.q==30 and not enemy.alerted,'distant enemy consumed a turn')
            enemy.q,enemy.r=3,3;Operation.awaken(b);assert(enemy.alerted and Grid.moveBudget(b,b.units[1])==b.units[1].move)
            atExit(b);enemy.boss=true;assert(not Operation.ready(b));enemy.hp=0;assert(Operation.ready(b))
        ''')

    def test_saved_routes_reject_teleports_bad_timing_and_nonfinite_distance(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.units[3].hp=0;b.obstacles={}
            assert(action('host','battle.move',{q=9,r=3}).ok and State.validate(saved))
            for _,edit in ipairs({
                function(u)u.moveAnim.path[2].q=40 end,
                function(u)u.moveAnim.duration=0 end,
                function(u)u.moveAnim.t=0/0 end,
                function(u)u.routeDistance=math.huge end,
                function(u)u.moveAnim.toQ=10 end})do
                local copy=assert(Schema.copy(saved));edit(copy.tacticalBattle.battle.units[1]);assert(not State.validate(copy))
            end
        ''')

    def test_legacy_checkpoint_migrates_without_replacing_its_board(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.field=nil;b.fog=nil;b.crossingComplete=nil
            for q=0,71 do
                if q>9 then b.tiles[q]=nil;b.tileVariants[q]=nil
                else for r=7,40 do b.tiles[q][r]=nil;b.tileVariants[q][r]=nil end end
            end
            b.obstacles={};b.units[3].q,b.units[3].r=9,1;data.version=47
            local loaded=assert(Schema.migrate(data));assert(loaded.version==48)
            local restored=assert(State.restore(loaded,Catalog));assert(not restored.field and restored.tiles[9][6]and not restored.tiles[10])
        ''')

if __name__=='__main__':unittest.main()
