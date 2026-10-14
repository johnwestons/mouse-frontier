"""Host encounter rolls, stable identities and the production save barrier."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class EncounterCommandTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() error('global encounter RNG used') end}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Authority=require('game.coop_authority'); Commands=require('game.coop_encounters')
            Catalog=require('game.catalog'); Codec=require('game.net.codec'); Entities=require('game.coop_entities')
            function setup(stop,seed)
                data=F.campaign(stop or 15); assert(F.enroll(data)); data.scene='train'
                data.eventProgress={story=10,mystery=5}; data.mysteryStops={4,13,24,34,44}
                state={screen='game',scene='train'}; writes=0; failSave=false
                service=Authority.new({campaign=data,sessionId='encounters',randomSeed=seed or 42841,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                Commands.install(service,{catalog=Catalog,actorState=function() return state end}); service:admit('companion',1); writes=0
            end
            function run(actor,args)
                local request,reason=service:prepareRequest(actor,'encounter.roll',args or {})
                if not request then return {ok=false,reason=reason} end
                return service:execute(actor,actor=='host' and 0 or 1,request)
            end
            setup()
        ''')

    def test_all_bosses_and_normal_stop_tiers_use_campaign_rng(self):
        self.lua.execute('''
            local peaceful,battle=0,0
            for _,stop in ipairs({1,5,12,13,15,20,30,31,35,40,47,49}) do
                for _,seed in ipairs({17,111111,2000000000}) do
                    setup(stop,seed); local epoch=data.coop.sceneEpoch
                    local reply=run('host'); assert(reply.ok and reply.durable,reply.reason)
                    local e=data.encounters[tostring(stop)]; assert(e.entityId and e.rolled and e.hasMob~=e.resolved)
                    assert(e.tier==require('game.combat_balance').tierFor(stop) and reply.result.encounter.entityId==e.entityId)
                    if e.hasMob then battle=battle+1; assert(#e.mobFiles>=1 and e.mobFile==e.mobFiles[1]) else peaceful=peaceful+1 end
                    if stop==15 or stop==35 or stop==47 then assert(e.boss and e.hasMob) else assert(not e.boss) end
                    assert(data.coop.sceneEpoch==epoch and data.coop.randomState and writes==1 and data.health==17)
                    assert(data.players.companion.health==25 and saved.encounters[tostring(stop)].entityId==e.entityId)
                end
            end
            assert(peaceful>0 and battle>0)
        ''')

    def test_guest_and_forged_roll_parameters_are_rejected(self):
        self.lua.execute('''
            assert(run('companion',{actorId='host',boss=false}).reason=='host_only')
            for _,args in ipairs({{stop=1},{seed=1},{mobFiles={'forged'}},{outcome='peaceful'}}) do
                assert(run('host',args).reason=='invalid_args')
            end
            assert(not data.encounters['15'] and not data.coop.randomState and writes==0)
        ''')

    def test_existing_encounter_and_exact_replay_never_reroll(self):
        self.lua.execute('''
            local request=assert(service:prepareRequest('host','encounter.roll',{}))
            assert(service:execute('host',0,request).ok); local rng=data.coop.randomState; local sequence=data.coop.nextEntityId
            local signature=assert(Codec.encode(data.encounters['15'])); local revision=data.coop.revision
            assert(service:execute('host',0,request).ok and writes==1 and data.coop.revision==revision)
            assert(run('host').result.existing and Codec.encode(data.encounters['15'])==signature)
            assert(data.coop.randomState==rng and data.coop.nextEntityId==sequence)
        ''')

    def test_failed_checkpoint_retries_identical_roll_and_identity(self):
        self.lua.execute('''
            failSave=true; local reply=run('host'); assert(reply.ok and reply.savePending and not reply.durable)
            local signature=assert(Codec.encode(data.encounters['15'])); local rng=data.coop.randomState
            assert(run('host').reason=='save_pending'); failSave=false; assert(service:retryCheckpoint())
            local loaded=assert(Schema.migrate(saved)); assert(Codec.encode(loaded.encounters['15'])==signature and loaded.coop.randomState==rng)
        ''')

    def test_required_chapter_blocks_roll_and_discards_rng(self):
        self.lua.execute('''
            data.eventProgress.story=0; data.mysteryStops=nil
            assert(run('host').reason=='required_event')
            assert(not data.encounters['15'] and not data.coop.randomState and data.mysteryStops==nil and writes==0)
        ''')

    def test_forced_event_retains_legacy_peaceful_route(self):
        self.lua.execute('''
            data.forceEventId='dry-camp'; local reply=run('host'); assert(reply.ok,reply.reason)
            assert(data.encounters['15'].testEvent and not data.encounters['15'].hasMob and data.encounters['15'].resolved)
            setup(); data.forceEventId='unknown'; assert(run('host').reason=='invalid_forced_event')
            assert(not data.encounters['15'] and not data.coop.randomState and writes==0)
        ''')

    def test_roll_requires_idle_host_on_train_before_finale(self):
        self.lua.execute('''
            for _,field in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                state[field]=true; assert(run('host').reason=='encounter_unavailable'); state[field]=nil
            end
            state.screen='ending'; assert(not run('host').ok); state.screen='game'
            state.scene='stop'; assert(not run('host').ok); state.scene='train'
            data.location=50; assert(not run('host').ok); data.location=15
            data.health=0; assert(not run('host').ok)
            assert(not data.encounters['15'] and not data.coop.randomState and writes==0)
        ''')

    def test_legacy_encounters_gain_unique_durable_ids_without_replacing_other_entities(self):
        self.lua.execute('''
            local drop=data.droppedItems[1]; local nextId=data.coop.nextEntityId
            data.encounters['4']={rolled=true,hasMob=false,resolved=true}
            data.encounters['15']={rolled=true,hasMob=true,resolved=false,mobFile=Catalog.mobTiers.medium[1]}
            local loaded=assert(Schema.migrate(data)); local id=loaded.encounters['15'].entityId
            assert(id and id~=loaded.encounters['4'].entityId and loaded.coop.nextEntityId==nextId+2)
            assert(Schema.migrate(loaded).encounters['15'].entityId==id)
            local e,record=Entities.find(loaded,id); assert(e==loaded.encounters['15'] and record.kind=='encounter')
            if drop then assert(loaded.droppedItems[1].entityId==drop.entityId) end
        ''')

    def test_production_journey_waits_for_retry_before_battle_entry(self):
        self.lua.execute('''
            runtime={saveData=data,scene='train',state='game'}; calls=0; legacyWrites=0
            local context={runtime=runtime,ensureStopLayout=function() end,setupNPC=function() end,
                writeSave=function() legacyWrites=legacyWrites+1 end,beginRequiredEvent=function() return false end,
                beginEncounter=function(e) calls=calls+1; entered=e end,beginRandomEvent=function() error('boss became event') end,
                commands={submit=function(name,args) assert(name=='encounter.roll'); return run('host',args) end,
                    checkpointStatus=function() return service:checkpointStatus() end}}
            for name in ('car inventory catalog engineUpgrades progressionBalance combatBalance eventBalance trainUpgradeBalance questProgression lootProgression stopHelpProgression helpQuestSession helpDialogueQuests npcRelationships firstAid battleRules maintenance passengers util house'):gmatch('%S+') do context[name]={} end
            local journey=require('game.journey_rules').new(context)
            failSave=true; local ok,reason=journey.attemptLeaveTrain(); assert(ok==false and reason=='save_pending')
            assert(calls==0 and data.encounters['15'] and legacyWrites==0)
            journey.attemptLeaveTrain(); assert(calls==0 and legacyWrites==0)
            failSave=false; assert(service:retryCheckpoint()); journey.attemptLeaveTrain()
            assert(calls==1 and entered.entityId==saved.encounters['15'].entityId and legacyWrites==0)
        ''')


if __name__ == '__main__':
    unittest.main()
