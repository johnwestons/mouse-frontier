"""Populated crossings, coherent ruins, bounded patrols and shared search state."""
import unittest
from tools.tests import test_coop_battles_behavior as fixtures


class BattlefieldPopulationTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.TacticalCommandTests();fixture.setUp();self.lua=fixture.lua
        self.lua.execute('''
            Op=require('game.battle_operation');Grid=require('game.battle_grid')
            Field=require('game.battle_field');Sites=require('game.battle_sites')
            function populated(tier)
                setup();data.encounters['2'].maxHP=nil;data.encounters['2'].tier=tier or 'easy'
                assert(begin().ok);return ready()
            end
        ''')

    def test_normal_crossings_have_six_saved_groups_at_each_difficulty(self):
        self.lua.execute('''
            for tier,count in pairs({easy=12,medium=18,hard=24})do
                local b=populated(tier);local groups={};local spaces={};local enemies=0
                for _,u in ipairs(b.units)do
                    assert(not spaces[u.q..':'..u.r]);spaces[u.q..':'..u.r]=true
                    assert(not b.obstacles[u.q..':'..u.r])
                    if u.team=='enemy'then
                        enemies=enemies+1;groups[u.pocket]=(groups[u.pocket]or 0)+1
                        assert(u.patrolQ and not u.alerted,'unsafe opening or missing patrol')
                    end
                end
                assert(enemies==count and #b.encounter.mobFiles==count)
                local families={};local kinds=0
                for _,file in ipairs(b.encounter.mobFiles)do if not families[file]then families[file]=true;kinds=kinds+1 end end
                assert(kinds<=3,'crossing allocated too many animation families')
                for i=1,6 do assert(groups[i]==count/6)end
                assert(State.validate(saved)and State.restore(assert(Schema.migrate(saved)),Catalog))
                local Net=require('game.net.game_state');local p=Net.producer();local r=Net.replica()
                assert(r:apply(assert(p:capture(data,true))))
                assert(#r.data.tacticalBattle.battle.units==count+2)
            end
        ''')

    def test_population_is_stable_on_reentry_and_preserves_scripted_rosters(self):
        self.lua.execute('''
            local Pop=require('game.battle_population');local calls=0
            local function random(a,b)calls=calls+1;return a end
            local e={tier='easy',mobFiles={Catalog.mobTiers.easy[1]}}
            assert(Pop.prepare(e,Catalog,random)and #e.mobFiles==12);local first=calls
            e.maxHP=10;assert(Pop.prepare(e,Catalog,random)and calls==first)
            local older={tier='easy',maxHP=10,mobFiles={Catalog.mobTiers.easy[1]}}
            assert(Pop.prepare(older,Catalog,random,10)and #older.mobFiles==12,'older normal encounter was mistaken for a scripted HP override')
            for _,v in ipairs({{maxHP=100},{boss=true},{eventBattle=true},{source='expedition'},{enemyStates={}}})do
                v.tier='easy';v.mobFiles={Catalog.mobTiers.easy[1]}
                assert(not Pop.prepare(v,Catalog,random)and #v.mobFiles==1)
            end
        ''')

    def test_ruined_houses_have_open_doors_rooms_and_preserved_main_routes(self):
        self.lua.execute('''
            local f,t,v,o=Field.generate(1847,1,'hard');assert(f.version==3 and #Sites.list(f)==12)
            local walls=0;for _,p in pairs(o)do if p.kind:find('ruin-wall',1,true)then walls=walls+1 end end
            assert(walls>=150,'house walls were lost to generation fallback')
            for _,s in ipairs(Sites.list(f))do
                for _,r in ipairs({s.r,s.r+s.d-1})do for q=s.q+2,s.q+3 do
                    assert(not o[q..':'..r],'door blocked')
                end end
                for q=s.q+1,s.q+s.w-2 do for r=s.r+1,s.r+s.d-2 do
                    assert(not o[q..':'..r],'interior blocked by random props')
                    assert(Field.cellHeight(f,q,r)==.125,'room is not on a level foundation')
                end end
            end
            assert(Field.connectedCount(f,o)>=2400 and Field.playableCount(f,o)==2432)
            f.version=2;assert(Field.validate(f)and #Sites.list(f)==0,'older field was redecorated')
        ''')

    def test_passive_patrols_move_legally_only_once_per_round(self):
        self.lua.execute('''
            local b=populated();b.obstacles={};b.round=2;local before={}
            for _,u in ipairs(b.units)do before[u.id]={q=u.q,r=u.r}end
            Op.patrol(b);local moved=0
            for _,u in ipairs(b.units)do if u.patrolQ then
                local d=Grid.distance(before[u.id],u);assert(d<=2)
                if d>0 then moved=moved+1;assert(u.moveAnim.path and #u.moveAnim.path>=2)end
                before[u.id]={q=u.q,r=u.r}
            end end
            assert(moved>=6 and State.validate(data))
            Op.patrol(b);for _,u in ipairs(b.units)do assert(Grid.distance(u,before[u.id])==0)end
        ''')

    def test_sight_hearing_and_search_do_not_track_hidden_player_positions(self):
        self.lua.execute('''
            local b=populated();local e=b.units[3]
            b.units[1].q,b.units[1].r=10,10;b.units[2].q,b.units[2].r=1,1;e.q,e.r=14,10
            b.obstacles={['12:10']={q=12,r=10,kind='ruin-wall-z'}}
            assert(not Op.seen(b,e),'enemy sees through a solid wall')
            Op.noise(b,b.units[1],12);assert(e.lastSeenQ==10 and e.lastSeenR==10)
            b.units[1].q,b.units[1].r=60,10;local remembered=Op.target(b,e)
            assert(remembered.remembered and remembered.q==10,'hunter tracked a hidden position')
            b.round=e.searchUntil+1;assert(not Op.target(b,e),'search never expired')
        ''')

    def test_only_two_groups_can_pursue_at_once(self):
        self.lua.execute('''
            local b=populated('hard');b.units[1].q,b.units[1].r=0,1;b.units[2].q,b.units[2].r=0,2
            for _,u in ipairs(b.units)do if u.patrolQ then u.lastSeenQ,u.lastSeenR=30,20;u.searchUntil=5 end end
            Op.awaken(b);local groups={};local count=0
            for _,u in ipairs(b.units)do if u.team=='enemy'and u.alerted then
                if not groups[u.pocket]then groups[u.pocket]=true;count=count+1 end
            end end
            assert(count==2,'whole battlefield swarmed the player')
        ''')

    def test_host_enemy_turn_pursues_then_investigates_only_the_last_known_position(self):
        self.lua.execute('''
            local b=populated();b.obstacles={};local e=b.units[3]
            for _,u in ipairs(b.units)do if u.team=='enemy'and u~=e then u.hp=0 end end
            b.units[1].q,b.units[1].r=9,3;b.units[2].q,b.units[2].r=0,40;e.q,e.r=14,3
            b.active=3;Op.awaken(b);assert(e.alerted)
            assert(action('host','battle.enemyTurn').ok);assert(e.q<14 and e.lastSeenQ==9 and State.validate(saved))
            ready();b.units[1].q=50;b.active=3;local prior=e.q
            assert(action('host','battle.enemyTurn').ok)
            assert(e.q<prior and e.lastSeenQ==9,'hunter followed a hidden player instead of investigating the sighting')
            ready();b.round=e.searchUntil+1;b.active=3;prior=e.q
            assert(action('host','battle.enemyTurn').ok)
            assert(not e.alerted and e.lastSeenQ==9 and b.patrolRound==b.round and State.validate(saved),'expired hunter did not resume its patrol')
        ''')

    def test_hunters_navigate_out_of_a_room_instead_of_sticking_to_the_wall(self):
        self.lua.execute('''
            local b=populated();b.obstacles={}
            b.field.elevationData=string.rep('01',73*41)
            for _,u in ipairs(b.units)do if u.team=='enemy'then u.hp=0 end end
            local e=b.units[3];e.hp=10;e.q,e.r=9,8
            b.units[1].q,b.units[1].r=15,8;b.units[2].q,b.units[2].r=1,1
            for q=7,12 do for r=6,10 do
                if (q==7 or q==12 or r==6 or r==10)and not(q==9 and r==6)then
                    b.obstacles[q..':'..r]={q=q,r=r,kind='ruin-wall-x'}
                end
            end end
            for turn=1,12 do
                local p=Grid.bestAdvance(b,e,b.units[1],2,1)
                assert(Grid.path(b,e,p.q,p.r,2),'pursuit crossed a wall')
                e.q,e.r=p.q,p.r
                if Grid.distance(e,b.units[1])<=1 then break end
            end
            assert(Grid.distance(e,b.units[1])<=1,'hunter remained stuck inside the house')
        ''')

    def test_saved_brains_validate_and_static_terrain_stays_out_of_moves(self):
        self.lua.execute('''
            local b=populated();local Net=require('game.net.game_state');local Codec=require('game.net.codec')
            local p=Net.producer();local r=Net.replica();assert(r:apply(assert(p:capture(data,true))))
            assert(action('host','battle.move',{q=9,r=3}).ok)
            local delta=assert(p:capture(data));assert(r:apply(delta))
            for _,domain in ipairs(delta.domains)do assert(domain.id~='battlefield')end
            assert(#assert(Codec.encode(delta,{maxBytes=32768,maxDepth=32,maxEntries=20000,maxStringBytes=16000}))<16384)
            for _,change in ipairs({function(u)u.patrolQ=math.huge end,function(u)u.patrolIndex=5 end,
                function(u)u.lastSeenQ=0/0;u.lastSeenR=1;u.searchUntil=4 end})do
                local copy=assert(Schema.copy(saved));change(copy.tacticalBattle.battle.units[3]);assert(not State.validate(copy))
            end
        ''')


if __name__=='__main__':unittest.main()
