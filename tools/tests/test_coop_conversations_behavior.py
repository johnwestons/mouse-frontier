"""Host-owned authored choices, shared read-along, leases and durable outcomes."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class CoopConversationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Schema=require('game.save_schema'); Authority=require('game.coop_authority')
            Players=require('game.coop_players'); Entities=require('game.coop_entities')
            Items=require('game.item_instances'); C=require('game.npc_conversations')
            Domain=require('game.coop_conversations'); Leases=require('game.coop_leases')
            clock=0; failSave=false; writes=0
            function setup(id)
                data=F.campaign(4); assert(F.enroll(data)); data.scene='stop'
                npc='recipient.png'; data.currentNPC=npc; layout={npcOutside=npc}
                data.stopLayouts['4']=layout
                data.conversations={assignments={['4']={id=id or 'food',npc=npc,location=4}},completed={},seen={}}
                states={host={screen='game',scene='stop',x=140,y=100,npc={id=npc,x=100,y=100}},
                    companion={screen='game',scene='stop',x=180,y=100,npc={id=npc,x=100,y=100}}}
                for _,actorId in ipairs({'host','companion'}) do
                    local actor=Players.forActor(data,actorId)
                    for slot=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=slot},nil) end
                end
                service=Authority.new({campaign=data,sessionId='conversations',randomSeed=4891,clock=function() return clock end,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                context={catalog=Catalog,actorState=function(actorId) return states[actorId] end}
                Domain.install(service,context); service:admit('companion',1)
                require('game.coop_first_aid').install(service,context)
                require('game.coop_quests').install(service,context)
                require('game.coop_gifts').install(service,context)
            end
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function beginArgs() return {id=data.conversations.assignments['4'].id,npc=npc,targetId=layout.entityId} end
            function begin() return run('host','conversation.begin',beginArgs()) end
            function choose(index) return run('host','conversation.choose',{id=data.conversations.active.id,index=index}) end
            setup()
        ''')

    def test_guest_cannot_begin_choose_or_dismiss_story(self):
        self.lua.execute('''
            assert(run('companion','conversation.begin',beginArgs()).reason=='host_only')
            assert(begin().ok)
            for _,name in ipairs({'conversation.choose','conversation.end'}) do
                local args={id='food'}; if name=='conversation.choose' then args.index=1 end
                assert(run('companion',name,args).reason=='host_only')
            end
            assert(not data.conversations.completed.food and data.resources.food==10)
        ''')

    def test_choice_charges_shared_cost_once_and_awards_only_admitted_characters(self):
        self.lua.execute('''
            assert(begin().ok)
            local req=assert(service:prepareRequest('host','conversation.choose',{id='food',index=2}))
            assert(data.resources.food==10 and not data.conversations.completed.food and data.coop.randomState==nil)
            local reply=execute('host',req); assert(reply.ok and reply.durable and reply.result.completed)
            assert(data.resources.food==8 and data.resources.water==9)
            assert(data.stats.xp==9 and data.players.companion.stats.xp==9)
            local completed=data.conversations.completed.food
            assert(completed.rewardRecipients.host==5 and completed.rewardRecipients.companion==5)
            local rng=data.coop.randomState; local revision=data.coop.revision
            assert(execute('host',req).ok and data.resources.food==8 and data.coop.randomState==rng and data.coop.revision==revision)
            assert(choose(2).reason=='conversation_unavailable')
            assert(Schema.validate(data))
        ''')

    def test_offline_companion_or_different_scene_receives_no_xp(self):
        for absent in ('unbound', 'different_scene'):
            with self.subTest(absent=absent):
                self.setUp()
                self.lua.execute("service:disconnect('companion',1)" if absent == 'unbound' else "states.companion.scene='train'")
                self.lua.execute('''
                    assert(begin().ok and choose(3).ok)
                    assert(data.stats.xp==9 and data.players.companion.stats.xp==4)
                    assert(data.conversations.completed.food.rewardRecipients.companion==nil)
                ''')

    def test_live_target_reach_and_authored_assignment_are_required(self):
        self.lua.execute('''
            local args=beginArgs(); args.id='wastes'
            assert(run('host','conversation.begin',args).reason=='conversation_unavailable')
            args=beginArgs(); args.targetId='e999'
            assert(run('host','conversation.begin',args).reason=='recipient_unavailable')
            states.host.x=1000; assert(begin().reason=='recipient_unavailable')
            states.host.x=140; states.host.npc.id='other'; assert(begin().reason=='recipient_unavailable')
            states.host.npc.id=npc; states.host.x=0/0; assert(begin().reason=='recipient_unavailable')
            assert(not data.conversations.active and not data.conversations.seen.food)
        ''')

    def test_shortage_stale_target_and_invalid_index_roll_back(self):
        self.lua.execute('''
            assert(begin().ok); data.resources.food=0
            assert(choose(1).reason=='choice_unavailable')
            assert(choose(4).reason=='invalid_args')
            data.resources.food=10; states.host.x=1000
            assert(choose(1).reason=='recipient_unavailable')
            assert(not data.conversations.completed.food and data.resources.food==10 and data.stats.xp==4)
            assert(data.coop.randomState==nil and data.conversations.active.phase=='prompt')
        ''')

    def test_failed_checkpoint_retries_without_repeating_cost_reward_or_choice(self):
        self.lua.execute('''
            assert(begin().ok); failSave=true
            local req=assert(service:prepareRequest('host','conversation.choose',{id='food',index=2}))
            local reply=execute('host',req)
            assert(reply.ok and reply.savePending and not reply.durable)
            assert(data.resources.food==8 and data.stats.xp==9 and data.players.companion.stats.xp==9)
            local rng=data.coop.randomState; local revision=data.coop.revision
            assert(execute('host',req).savePending and data.coop.revision==revision)
            failSave=false; assert(service:retryCheckpoint())
            assert(execute('host',req).durable and data.resources.food==8 and data.coop.randomState==rng)
            local loaded=assert(Schema.migrate(saved))
            assert(loaded.conversations.completed.food.answer==2 and loaded.conversations.completed.food.rewardRecipients.companion==5)
            assert(C.readAlong(loaded).text==C.readAlong(data).text)
        ''')

    def test_read_along_is_authored_read_only_and_hides_choices_and_rewards(self):
        self.lua.execute('''
            assert(begin().ok)
            local copy=assert(Schema.copy(data)); local before=copy.coop.revision
            local read=C.readAlong(copy)
            assert(read.waiting and read.text=='Got any food i can get?' and read.choices==nil and read.notice==nil)
            assert(copy.coop.revision==before and copy.resources.food==10)
            assert(choose(2).ok)
            read=C.readAlong(data)
            assert(not read.waiting and read.answer==C.content[6].choices[2].label)
            assert(read.text=='You bet I am, and yes please that would be delightful')
            assert(read.choices==nil and read.notice:find('+5 XP',1,true))
            assert(run('host','conversation.end',{id='food'}).ok and C.readAlong(data)==nil)
            assert(data.conversations.completed.food and begin().reason=='conversation_unavailable')
        ''')

    def test_conversation_and_treatment_share_exclusive_npc_ownership(self):
        self.lua.execute('''
            local Help=require('game.stop_help_progression'); local Quests=require('game.help_quest_session')
            local request=Help.ensureRequest(layout,npc,'aid',4,data); request.accepted=true; Quests.accept(data,request.sessionId)
            Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'field-bandage-roll')
            local source={kind='inventory',index=1}
            local selected=require('game.coop_item_contract').selection(Players.forActor(data,'companion'),nil,source)
            local args={targetId=layout.entityId,npc=npc,source=source,selected=selected}
            local aid=run('companion','firstAid.acquire',args); assert(aid.ok,aid.reason)
            assert(begin().reason=='activity_busy' and not data.conversations.seen.food)
            assert(run('companion','firstAid.step',{leaseId=aid.result.leaseId,action='pause'}).ok)
            assert(begin().ok)
            assert(run('companion','firstAid.acquire',args).reason=='activity_busy')
            assert(require('game.coop_recipient_access').find(Players.forActor(data,'companion'),layout.entityId,npc,states.companion)==nil)
            assert(run('host','conversation.end',{id='food'}).ok)
            assert(run('companion','firstAid.acquire',args).ok)
        ''')

    def test_host_frame_renews_ephemeral_lease_but_expired_choice_cannot_pay(self):
        self.lua.execute('''
            assert(begin().ok)
            for _=1,20 do clock=clock+10; assert(Domain.renew(service,'food')) end
            assert(choose(3).ok)
            setup('food'); assert(begin().ok); clock=clock+31
            assert(not Domain.renew(service,'food'))
            assert(choose(3).reason=='lease_expired' and not data.conversations.completed.food)
            assert(run('host','conversation.end',{id='food'}).ok and not next(service.activityState.resources))
        ''')

    def test_scene_commit_cancels_read_along_and_leases(self):
        self.lua.execute('''
            assert(begin().ok); data.scene='train'
            assert(require('game.party_scene').commit(data,{state=service.activityState},{}))
            assert(not data.conversations.active and C.readAlong(data)==nil and not next(service.activityState.resources))
            assert(Schema.validate(data))
        ''')

    def test_forged_saved_read_along_fails_schema_validation(self):
        self.lua.execute('''
            assert(begin().ok)
            local copy=assert(Schema.copy(data)); copy.conversations.active.text='invented'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.conversations.active.id='unknown'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.conversations.active.phase='response'
            assert(not Schema.validate(copy))
        ''')

    def test_reload_restores_prompt_without_restoring_a_lease_or_offline_xp(self):
        self.lua.execute('''
            assert(begin().ok)
            data=assert(Schema.migrate(saved)); layout=data.stopLayouts['4']
            service=Authority.new({campaign=data,sessionId='reloaded-story',randomSeed=4891,clock=function() return clock end,
                checkpoint=function(value) saved=assert(Schema.copy(value)); return true end})
            Domain.install(service,context)
            assert(C.readAlong(data).waiting and not next(service.activityState.resources))
            assert(choose(2).reason=='lease_expired' and not data.conversations.completed.food)
            assert(begin().ok and choose(2).ok)
            assert(data.stats.xp==9 and data.players.companion.stats.xp==4)
            assert(data.conversations.completed.food.rewardRecipients.companion==nil)
            assert(Schema.validate(saved))
        ''')

    def test_real_command_adapter_keeps_npc_still_and_closes_abandoned_host_ui(self):
        import re
        source = (ROOT / 'game/journey_rules.lua').read_text(encoding='utf-8')
        context = self.lua.table()
        for name, kind in re.findall(r'required\(context,\s*"([^"]+)",\s*"([^"]+)"\)', source):
            context[name] = self.lua.table() if kind == 'table' else self.lua.eval('function() end')
        self.lua.globals().journeyContext = context
        self.lua.execute('''
            local GameSession=require('game.game_session')
            local session=GameSession.new(); session.saveData=data; session.scene='stop'; session.screen='game'
            runtime={saveData=data,state='game',scene='stop',animationClock=0,session=session,
                player={x=140,y=100},npcActor={x=100,y=100}}
            commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                clock=function() return clock end,checkpoint=function(value) saved=assert(Schema.copy(value)); return true end})
            journeyContext.commands=commands; journeyContext.runtime=runtime; journeyContext.catalog=Catalog
            journeyContext.util=require('game.util'); journeyContext.ensureStopLayout=function() return layout end
            journeyContext.writeSave=function() error('story must use command checkpoint') end
            journey=require('game.journey_rules').new(journeyContext)
            journey.talkToNPC(); assert(runtime.helpDialogue.authored and commands.patientBusy(npc))
            for _=1,8 do clock=clock+10; journey.updateConversation() end
            assert(runtime.helpDialogue and commands.patientBusy(npc))
            data.resources.food=0; journey.updateConversation()
            assert(runtime.helpDialogue.choices[1].enabled==false and runtime.helpDialogue.choices[2].enabled==false)
            assert(journey.chooseHelpDialogue(2).reason=='choice_unavailable')
            assert(runtime.helpDialogue and not data.conversations.completed.food and data.stats.xp==4)
            data.resources.food=10; journey.updateConversation()
            assert(runtime.helpDialogue.choices[2].enabled==true)
            runtime.dialogue=nil; journey.updateConversation()
            assert(not runtime.helpDialogue and not data.conversations.active and not commands.patientBusy(npc))
            assert(not data.conversations.completed.food and data.resources.food==10)
            journey.talkToNPC(); assert(journey.chooseHelpDialogue(2).completed)
            assert(runtime.dialogue.authored and not runtime.helpDialogue and data.conversations.completed.food.answer==2)
            runtime.dialogue=nil; journey.updateConversation()
            assert(not saved.conversations.active and saved.conversations.completed.food.answer==2)
        ''')

    def test_all_approved_branches_complete_once_and_ammo_belongs_to_host(self):
        self.lua.execute('''
            for _,entry in ipairs(C.content) do
                for index=1,#entry.choices do
                    setup(entry.id); assert(begin().ok)
                    local before=assert(Schema.copy(data.players.companion.ammo))
                    local result=choose(index); assert(result.ok,entry.id..':'..index..':'..tostring(result.reason))
                    assert(C.readAlong(data).text==entry.choices[index].response)
                    assert(data.conversations.completed[entry.id].answer==index)
                    for key,amount in pairs(before) do assert(data.players.companion.ammo[key]==amount) end
                    for key,amount in pairs(data.players.companion.ammo) do assert(before[key]==amount) end
                    assert(Schema.validate(data))
                    assert(run('host','conversation.end',{id=entry.id}).ok and not begin().ok)
                end
            end
        ''')


if __name__ == '__main__':
    unittest.main()
