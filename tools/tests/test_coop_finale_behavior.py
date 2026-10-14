"""Saved host finale decisions and pure shared ending presentation."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class FinaleCommandTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path; love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Authority=require('game.coop_authority'); Commands=require('game.coop_finale')
            Finale=require('game.finale_progression'); Players=require('game.coop_players')
            function equal(a,b)
                if type(a)~='table' or type(b)~='table' then return a==b end
                for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
                for key in pairs(b) do if a[key]==nil then return false end end
                return true
            end
            function setup()
                data=F.campaign(50); assert(F.enroll(data)); data.scene='train'
                states={host={screen='ending',scene='train'},companion={screen='game',scene='train'}}
                failSave=false; writes=0
                service=Authority.new({campaign=data,sessionId='finale',randomSeed=42331,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                Commands.install(service,{actorState=function(id) return states[id] end}); service:admit('companion',1); writes=0
            end
            function run(actor,args)
                local request,reason=service:prepareRequest(actor,'finale.choose',args)
                if not request then return {ok=false,reason=reason} end
                return service:execute(actor,actor=='host' and 0 or 1,request)
            end
            setup()
        ''')

    def test_all_existing_choices_are_saved_without_charging_either_actor(self):
        self.lua.execute('''
            for _,choice in ipairs(Finale.choices) do
                setup(); local epoch=data.coop.sceneEpoch; local health=data.health; local guest=data.players.companion.health
                local reply=run('host',{id=choice.id}); assert(reply.ok and reply.durable,reply.reason)
                assert(saved.finale.choice==choice.id and saved.finale.completed and data.coop.sceneEpoch==epoch)
                assert(data.health==health and data.players.companion.health==guest and data.scrap==40 and data.resources.water==10)
                assert(data.coop.randomState==nil and data.stats.xp==4 and data.players.companion.stats.xp==4)
                assert(Schema.validate(saved) and Commands.readAlong(saved).choice.id==choice.id)
            end
        ''')

    def test_guest_cannot_choose_even_with_host_identity_in_args(self):
        self.lua.execute('''
            assert(run('companion',{id='family',actorId='host'}).reason=='host_only')
            assert(not data.finale.choice and writes==0)
        ''')

    def test_choice_requires_actual_completed_arrival_and_host_ending_surface(self):
        self.lua.execute('''
            states.host.screen='game'; assert(run('host',{id='haven'}).reason=='finale_unavailable')
            states.host.screen='ending'; data.location=49; assert(not run('host',{id='haven'}).ok)
            data.location=50; data.coop.journey={from=49,to=50,phase='arrived',epoch=data.coop.sceneEpoch,maintenanceCondition=72}
            assert(not run('host',{id='haven'}).ok and not Commands.readAlong(data))
            data.coop.journey=nil; states.host.scene='stop'; assert(not run('host',{id='haven'}).ok)
            states.host.scene='train'; states.host.encounterActive=true; assert(not run('host',{id='haven'}).ok)
            states.host.encounterActive=false; states.host.activityBlocked=true; assert(not run('host',{id='haven'}).ok)
            states.host.activityBlocked=false; states.host.traveling=true; assert(not run('host',{id='haven'}).ok)
            assert(not data.finale.choice and writes==0)
        ''')

    def test_payload_cannot_supply_a_reward_outcome_or_unknown_branch(self):
        self.lua.execute('''
            for _,args in ipairs({{id='unknown'},{id='family',scrap=999},{id='haven',outcome='forged'},{}}) do
                assert(run('host',args).reason=='invalid_args')
            end
            assert(not data.finale.choice and writes==0)
        ''')

    def test_exact_replay_and_new_choice_cannot_change_the_ending(self):
        self.lua.execute('''
            local request=assert(service:prepareRequest('host','finale.choose',{id='lifeline'}))
            assert(service:execute('host',0,request).ok); local revision=data.coop.revision
            assert(service:execute('host',0,request).ok and data.coop.revision==revision and writes==1)
            assert(run('host',{id='lifeline'}).reason=='finale_already_chosen')
            assert(run('host',{id='family'}).reason=='finale_already_chosen' and data.finale.choice=='lifeline')
        ''')

    def test_failed_choice_save_holds_the_barrier_and_retry_preserves_outcome(self):
        self.lua.execute('''
            failSave=true; local reply=run('host',{id='haven'})
            assert(reply.ok and reply.savePending and not reply.durable and data.finale.choice=='haven')
            assert(run('host',{id='family'}).reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint()); local loaded=assert(Schema.migrate(saved))
            assert(loaded.finale.choice=='haven' and loaded.finale.completed and Commands.readAlong(loaded).choice.id=='haven')
        ''')

    def test_guest_summary_uses_host_level_and_never_normalizes_the_campaign(self):
        self.lua.execute('''
            data.players.host.stats.level=3; data.players.companion.stats.level=12
            data.maintenance={condition=61.4}; data.goodwill=8; data.eventProgress={story=6,mystery=2}
            local original=assert(Schema.copy(data)); local view=Players.forActor(data,'companion')
            local read=assert(Commands.readAlong(view)); assert(read.level==3 and read.condition==61 and not read.choice and not read.choices)
            assert(equal(data,original) and data.relationships~=nil)
            assert(run('host',{id='family'}).ok); original=assert(Schema.copy(data))
            read=assert(Commands.readAlong(view)); read.choice.title='local edit'
            assert(Finale.choice('family').title~='local edit' and equal(data,original))
        ''')

    def test_malformed_saved_choice_is_rejected_without_throwing(self):
        self.lua.execute('''
            for _,state in ipairs({{choice='unknown',completed=true},{choice=5},{completed=true},{choice='haven',completed=false},
                {choice='family',reward=999},{completed='true'}}) do
                local bad=assert(Schema.copy(data)); bad.finale=state
                local ok,result=pcall(Schema.validate,bad); assert(ok and not result)
            end
            assert(Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
