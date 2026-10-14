"""Saved host event decisions, deterministic outcomes and continuation."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class EventCommandTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path; love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Catalog=require('game.catalog'); Events=require('game.events'); Commands=require('game.coop_events')
            Authority=require('game.coop_authority'); Players=require('game.coop_players'); Items=require('game.item_instances')
            function setup(stop)
                data=F.campaign(stop or 4); assert(F.enroll(data)); failSave=false; writes=0
                data.scene='train'; data.playerX=200; data.playerY=250
                data.players.companion.playerX=240; data.players.companion.playerY=250
                states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
                context={catalog=Catalog,actorState=function(id) return states[id] end}
                service=Authority.new({campaign=data,sessionId='events',randomSeed=123987,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                Commands.install(service,context); service:admit('companion',1); writes=0
            end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return service:execute(actor,actor=='host' and 0 or 1,req)
            end
            function begin(id)
                local reply=run('host','event.begin',{mode='named',id=id})
                if reply.ok then states.host.screen='event' end
                return reply
            end
            function choose(index) return run('host','event.choose',{id=data.events.current.id,index=index}) end
            function continue() return run('host','event.continue',{id=data.events.current.id}) end
            function production()
                local GameSession=require('game.game_session'); local Runtime=require('game.runtime_state')
                session=GameSession.new()
                runtime=Runtime.new({session=session,transition=function(screen) session:setScreen(screen) end})
                runtime:activate(data,{x=data.playerX,y=data.playerY}); stopCalls=0; battleCalls=0
                context.actorState=function() return {screen=runtime.state,scene=runtime.scene} end
                local commands={submit=function(name,args)
                    local reply=run('host',name,args)
                    session.checkpointPending=service.pendingSave~=nil
                    if reply.ok and reply.result.partyTransition then
                        session:acceptPartyState(reply.result); runtime.state=reply.result.screen
                    end
                    return reply
                end}
                eventRuntime=require('game.event_runtime').new({runtime=runtime,ui={playSfx=function() end},commands=commands,
                    events=Events,eventUI=require('game.event_ui'),catalog=Catalog,combatBalance=require('game.combat_balance'),
                    eventBalance=require('game.event_balance'),trainUpgradeBalance=require('game.train_upgrade_balance'),
                    pointIn=function() return false end,writeSave=function() error('direct event save bypass') end,
                    beginEncounter=function() battleCalls=battleCalls+1 end,enterStop=function() stopCalls=stopCalls+1 end})
            end
            setup()
        ''')

    def test_guest_has_no_event_decision_capability(self):
        self.lua.execute('''
            for _,name in ipairs({'event.begin','event.choose','event.continue'}) do
                assert(run('companion',name,{mode='random'}).reason=='host_only')
            end
            assert(not data.events.current and data.coop.randomState==nil and writes==0)
        ''')

    def test_every_existing_event_choice_is_valid_and_uses_host_rng(self):
        self.lua.execute('''
            love.math.random=function() error('event must use the campaign stream') end
            for _,pool in pairs(Events.definitions) do
                for _,event in ipairs(pool) do
                    for index,choice in ipairs(event.choices) do
                        setup(14); data.health=23
                        Items.write(data,nil,{kind='equipment',index=1},'scrap-pistol'); data.ammo['9mm']=50
                        data.resources.food=30; data.resources.water=30; data.resources.coal=30; data.resources.oil=30
                        assert(begin(event.id).ok,event.id..': begin')
                        assert(Events.canChoose(data,choice,Catalog),event.id..':'..index..': fixture cannot choose')
                        if Events.canChoose(data,choice,Catalog) then
                            local reply=choose(index)
                            assert(reply.ok,event.id..':'..index..': '..tostring(reply.reason))
                            assert(reply.durable and Commands.validateCurrent(data) and Schema.validate(data))
                            local read=assert(Commands.readAlong(data)); assert(read.answer==choice.label and not read.waiting and not read.choices)
                            local nextReply=continue(); assert(nextReply.ok,event.id..': continue '..tostring(nextReply.reason))
                            assert(nextReply.durable and not data.events.current and Schema.validate(saved))
                        end
                    end
                end
            end
        ''')

    def test_saved_prompt_restores_without_a_new_roll_or_progress(self):
        self.lua.execute('''
            local reply=run('host','event.begin',{mode='random'}); assert(reply.ok and reply.durable)
            local before=assert(Schema.copy(saved)); local runtime={saveData=assert(Schema.migrate(saved))}
            assert(Commands.restore(runtime) and runtime.randomEvent.id==before.events.current.id and runtime.eventOutcome==nil)
            assert(runtime.saveData.coop.randomState==before.coop.randomState and #runtime.saveData.eventHistory==0)
            local read=assert(Commands.readAlong(runtime.saveData)); assert(read.waiting and not read.answer and not read.choices)
        ''')

    def test_choice_and_continue_replay_cannot_repeat_cost_reward_or_roll(self):
        self.lua.execute('''
            assert(begin(Events.definitions.fortune[1].id).ok)
            local req=assert(service:prepareRequest('host','event.choose',{id=data.events.current.id,index=1}))
            local reply=service:execute('host',0,req); assert(reply.ok,reply.reason)
            local revision=data.coop.revision; local rng=data.coop.randomState; local scrap=data.scrap
            assert(service:execute('host',0,req).ok and data.coop.revision==revision and data.coop.randomState==rng and data.scrap==scrap)
            assert(not choose(1).ok)
            local c=assert(service:prepareRequest('host','event.continue',{id=data.events.current.id}))
            assert(service:execute('host',0,c).ok)
            revision=data.coop.revision
            assert(service:execute('host',0,c).ok and data.coop.revision==revision and data.scrap==scrap)
            states.host.screen='game'
            assert(run('host','event.begin',{mode='random'}).reason=='event_already_played')
        ''')

    def test_write_failure_blocks_next_decision_and_preserves_chosen_state(self):
        self.lua.execute('''
            assert(begin(Events.definitions.help[1].id).ok); failSave=true
            local reply=choose(1); assert(reply.ok and reply.savePending and not reply.durable)
            local rng=data.coop.randomState; local resource=data.resources.food
            assert(data.events.current.phase=='chosen' and continue().reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint())
            assert(saved.events.current.phase=='chosen' and data.coop.randomState==rng and data.resources.food==resource)
            local runtime={saveData=assert(Schema.migrate(saved))}; assert(Commands.restore(runtime) and runtime.eventOutcome)
            assert(continue().ok and data.coop.randomState==rng and data.resources.food==resource)
        ''')

    def test_unavailable_choice_and_invalid_context_are_rollback_safe(self):
        self.lua.execute('''
            local event=Events.definitions.help[1]; assert(begin(event.id).ok)
            data.resources.food=0; data.resources.water=0; data.scrap=0
            for index,choice in ipairs(event.choices) do
                if not Events.canChoose(data,choice,Catalog) then
                    local rng=data.coop.randomState; local revision=data.coop.revision
                    assert(not choose(index).ok and data.coop.randomState==rng and data.coop.revision==revision)
                end
            end
            assert(run('host','event.choose',{id=event.id,index=1,reward=999}).reason=='invalid_args')
            states.host.traveling=true; assert(not choose(3).ok); states.host.traveling=false
            states.host.screen='game'; assert(not choose(3).ok)
            setup(); states.host.changingCar=true; assert(not begin(event.id).ok and not data.events.current)
        ''')

    def test_battle_continuation_stages_one_saved_encounter(self):
        self.lua.execute('''
            assert(begin(Events.definitions.battle[2].id).ok); assert(choose(1).ok)
            local encounter=data.events.current.outcome.encounter; assert(encounter and not data.encounters['4'])
            local reply=continue(); assert(reply.ok,reply.reason)
            assert(#data.encounters['4'].mobFiles==3 and reply.result.outcome.encounter.mobFiles[1]==data.encounters['4'].mobFiles[1])
            assert(saved.encounters['4'].mobFiles[1]==data.encounters['4'].mobFiles[1] and not data.events.current)
            local id=data.encounters['4'].entityId; assert(id and reply.result.outcome.encounter.entityId==id)
            assert(saved.encounters['4'].entityId==id and Schema.migrate(saved).encounters['4'].entityId==id)
        ''')

    def test_schema_rejects_forged_phase_epoch_outcome_and_sparse_notes(self):
        self.lua.execute('''
            assert(begin(Events.definitions.fortune[1].id).ok); assert(choose(1).ok)
            for _,edit in ipairs({
                function(c) c.sceneEpoch=c.sceneEpoch+1 end,
                function(c) c.id='unknown' end,
                function(c) c.phase='prompt' end,
                function(c) c.outcome.summary='forged' end,
                function(c) c.outcome.notes={[2]='found item'} end,
                function(c) c.index=0 end,
                function(c) c.outcome.cost=999 end,
            }) do
                local bad=assert(Schema.copy(data)); edit(bad.events.current); local ok,result=pcall(Schema.validate,bad)
                assert(ok and not result)
            end
            assert(Schema.validate(data))
        ''')

    def test_production_runtime_requires_host_continue_after_saved_choice(self):
        self.lua.execute('''
            production(); local before=data.coop.sceneEpoch
            assert(eventRuntime.begin(Events.findById('dry-camp')))
            assert(runtime.state=='event' and data.coop.sceneEpoch==before+1)
            local outcome=eventRuntime.choose(1); assert(outcome.summary and runtime.eventOutcome)
            assert(runtime.state=='event' and stopCalls==0 and battleCalls==0 and data.resources.water==7)
            assert(not eventRuntime.choose(1) and data.resources.water==7)
            assert(eventRuntime.continueEvent() and stopCalls==1 and runtime.state=='game')
            assert(not data.events.current and not runtime.randomEvent and data.coop.sceneEpoch==before+2)
            assert(not eventRuntime.continueEvent() and stopCalls==1)
        ''')

    def test_production_pending_continuation_does_not_start_an_unsaved_encounter(self):
        self.lua.execute('''
            production(); assert(eventRuntime.begin(Events.findById('tunnel-nest')))
            assert(eventRuntime.choose(1)); failSave=true
            assert(eventRuntime.continueEvent())
            assert(service.pendingSave and runtime.state=='game' and battleCalls==0 and stopCalls==0)
            assert(data.encounters['4'] and not data.events.current and not runtime.randomEvent)
            failSave=false; assert(service:retryCheckpoint())
            assert(saved.encounters['4'] and not saved.events.current and battleCalls==0)
        ''')

    def test_session_reload_keeps_event_epoch_and_presentation(self):
        self.lua.execute('''
            production(); assert(eventRuntime.begin(Events.findById('dry-camp'))); assert(eventRuntime.choose(1))
            local epoch=data.coop.sceneEpoch; local rng=data.coop.randomState
            local loaded=assert(Schema.migrate(saved))
            local fresh=require('game.game_session').new()
            local host=require('game.runtime_state').new({session=fresh,transition=function(screen) fresh:setScreen(screen) end})
            host:activate(loaded,{x=loaded.playerX,y=loaded.playerY}); host:resetForGameEntry(); assert(Commands.restore(host))
            host:syncForSave(); fresh:syncSceneEpoch('train')
            assert(host.state=='event' and host.randomEvent.id=='dry-camp' and host.eventOutcome.summary)
            assert(loaded.coop.sceneEpoch==epoch and loaded.coop.randomState==rng and loaded.resources.water==7)
            assert(Schema.validate(loaded))
        ''')

    def test_required_event_selection_discards_unused_rolls_and_saves_due_chapter(self):
        self.lua.execute('''
            setup(1); love.math.random=function() error('global RNG') end
            local before=data.coop.sceneEpoch
            assert(run('host','event.begin',{mode='required'}).reason=='event_unavailable')
            assert(data.coop.randomState==nil and data.mysteryStops==nil and not data.events.current and data.coop.sceneEpoch==before)
            setup(3)
            local reply=run('host','event.begin',{mode='required'}); assert(reply.ok,reply.reason)
            assert(data.events.current.id==Events.definitions.story[1].id and #saved.mysteryStops==5)
            assert(saved.eventProgress.story==0 and saved.events['3']==nil)
        ''')

    def test_host_choice_reward_uses_host_pack_and_full_mailbox_delivery_once(self):
        self.lua.execute('''
            for slot=1,data.inventoryCapacity do Items.write(data,nil,{kind='inventory',index=slot},'cowboy-hat') end
            data.droppedItems={{name='mailbox-reward',scene='train',carIndex=1,x=400,y=400,storage={}}}
            assert(require('game.coop_entities').ensure(data)); assert(Items.ensure(data))
            Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'frontier-short-sword')
            local guestItem=assert(Items.get(Players.forActor(data,'companion'),nil,{kind='inventory',index=1}))
            local guestHealth=data.players.companion.health; local guestAmmo=data.players.companion.ammo.rocks
            assert(begin('friendly-merchant').ok)
            local req=assert(service:prepareRequest('host','event.choose',{id='friendly-merchant',index=1}))
            local reply=service:execute('host',0,req); assert(reply.ok,reply.reason)
            local mailbox=data.droppedItems[1]; local weapon=mailbox.storage[1]
            assert(Catalog.weaponCombat[weapon] and mailbox.mailUnread and data.scrap==35)
            local instance=assert(Items.get(data,mailbox,{kind='chest',index=1}))
            assert(service:execute('host',0,req).ok and mailbox.storage[2]==nil and data.scrap==35)
            assert(Items.get(data,mailbox,{kind='chest',index=1})==instance)
            assert(Items.get(saved,saved.droppedItems[1],{kind='chest',index=1}).id==instance.id)
            assert(Items.get(Players.forActor(data,'companion'),nil,{kind='inventory',index=1})==guestItem)
            assert(data.players.companion.health==guestHealth and data.players.companion.ammo.rocks==guestAmmo and Schema.validate(saved))
        ''')

    def test_begin_write_failure_keeps_prompt_and_blocks_choice_until_retry(self):
        self.lua.execute('''
            production(); failSave=true
            assert(eventRuntime.begin(Events.findById('dry-camp')))
            assert(service.pendingSave and runtime.state=='event' and data.events.current.phase=='prompt')
            assert(not eventRuntime.choose(1) and data.resources.water==10 and not data.events['4'])
            failSave=false; assert(service:retryCheckpoint()); session.checkpointPending=false
            assert(saved.events.current.phase=='prompt' and eventRuntime.choose(1) and data.resources.water==7)
        ''')


    def test_title_focus_save_does_not_stale_prompt_or_committed_outcome(self):
        self.lua.execute('''
            for _,chosen in ipairs({false,true}) do
                setup(); production(); assert(eventRuntime.begin(Events.findById('dry-camp')))
                if chosen then assert(eventRuntime.choose(1)) end
                local epoch=data.coop.sceneEpoch; local rng=data.coop.randomState
                runtime.state='slots'; runtime:syncForSave()
                assert(data.coop.sceneEpoch==epoch and Commands.validateCurrent(data) and Schema.validate(data))
                local persisted=assert(Schema.copy(data)); runtime:activate(persisted,{x=persisted.playerX,y=persisted.playerY})
                runtime:resetForGameEntry(); assert(Commands.restore(runtime)); runtime:syncForSave()
                assert(runtime.state=='event' and persisted.coop.sceneEpoch==epoch and persisted.coop.randomState==rng)
                assert((runtime.eventOutcome~=nil)==chosen and persisted.resources.water==(chosen and 7 or 10))
            end
        ''')


if __name__ == '__main__':
    unittest.main()
