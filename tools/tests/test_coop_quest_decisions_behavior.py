"""Host offer/accept/decline/recruit transactions and accepted guest assistance."""
from pathlib import Path
import os
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class QuestDecisionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path; love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog'); Schema=require('game.save_schema')
            Authority=require('game.coop_authority'); Entities=require('game.coop_entities'); Items=require('game.item_instances')
            Players=require('game.coop_players'); Help=require('game.stop_help_progression'); Sessions=require('game.help_quest_session')
            Decisions=require('game.coop_quest_decisions'); now=0; failSave=false; writes=0
            function setup(kind)
                data=F.campaign(4); assert(F.enroll(data)); data.scene='stop'; npc='recipient.png'; data.currentNPC=npc
                layout={npcOutside=npc,npcOffers={[npc]=kind or 'supplies'}}; data.stopLayouts['4']=layout
                for _,id in ipairs({'host','companion'}) do
                    local actor=Players.forActor(data,id)
                    for slot=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=slot},nil) end
                end
                if kind=='item' or kind=='aid' then request=Help.ensureRequest(layout,npc,kind,4,data) else request=nil end
                states={host={screen='game',scene='stop',x=140,y=100,npc={id=npc,x=100,y=100}},
                    companion={screen='game',scene='stop',x=150,y=100,npc={id=npc,x=100,y=100}}}
                context={catalog=Catalog,car={x=80,y=290},actorState=function(id) return states[id] end}
                service=Authority.new({campaign=data,sessionId='quest-decisions',randomSeed=7823,clock=function() return now end,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                Decisions.install(service,context); require('game.coop_quests').install(service,context)
                require('game.coop_first_aid').install(service,context); service:admit('companion',1)
            end
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function args(kind) return {targetId=layout.entityId,npc=npc,kind=kind} end
            function offer() return run('host','quest.offer',args()) end
            function decide(kind,decline) return run('host',decline and 'quest.decline' or 'quest.accept',args(kind)) end
            setup('supplies')
        ''')

    def test_guest_cannot_offer_accept_decline_or_recruit(self):
        self.lua.execute('''
            for _,name in ipairs({'quest.offer','quest.accept','quest.decline','passenger.recruit'}) do
                assert(run('companion',name,args(name=='quest.offer' and nil or 'supplies')).reason=='host_only')
            end
            assert(not layout.coopOffers and not data.questAsked['4:'..npc] and #data.supplyQuests==0)
        ''')

    def test_named_mail_identity_is_saved_once_on_accept_and_retry(self):
        self.lua.execute('''
            setup('mail'); data.npcRoster={'tinker-fox.png','scout-frog.png'}
            assert(offer().ok)
            local req=assert(service:prepareRequest('host','quest.accept',args('mail')))
            local reply=execute('host',req); assert(reply.ok,reply.reason)
            local q=data.mailQuests[1]; local I=require('game.npc_identity')
            local name=I.name(data,q.recipientId)
            assert(q.senderId and q.recipientId and name~=q.recipient)
            assert(execute('host',req).ok and #data.mailQuests==1)
            local loaded=assert(Schema.migrate(saved))
            assert(loaded.mailQuests[1].recipientId==q.recipientId and I.name(loaded,q.recipientId)==name)
        ''')

    def test_named_supply_handin_rejects_another_resident_without_consuming_cargo(self):
        self.lua.execute('''
            setup('supplies'); data.npcRoster={'tinker-fox.png'}
            layout.deliveryOffers={[npc]='food'}; assert(offer().ok); assert(decide('supplies').ok)
            local q=data.supplyQuests[1]; local T=require('game.npc_targets')
            assert(q.senderId and q.recipientId)
            data.location=q.destination; layout=data.stopLayouts[tostring(q.destination)]
            npc='scout-frog.png'; data.currentNPC=npc
            for _,state in pairs(states) do state.npc={id=npc,x=100,y=100} end
            local food=data.resources.food; local scrap=data.scrap
            local wrong=run('host','quest.deliver',{targetId=layout.entityId,npc=npc,questId=q.entityId})
            assert(not wrong.ok and not q.complete and data.resources.food==food and data.scrap==scrap)
            npc=q.recipient; data.currentNPC=npc
            for _,state in pairs(states) do state.npc={id=npc,x=100,y=100} end
            assert(T.matches(data,q,npc))
            local delivered=run('companion','quest.deliver',{targetId=layout.entityId,npc=npc,questId=q.entityId})
            assert(delivered.ok and q.complete,delivered.reason)
            assert(data.relationships[q.recipientId].helpCount==1)
        ''')

    def test_recipient_cannot_board_before_their_accepted_delivery_is_finished(self):
        self.lua.execute('''
            setup('ride'); local T=require('game.npc_targets')
            local q=T.bind(data,{sender='mail-mouse.png',origin=1,destination=4,recipient=npc,complete=false},function(a,b) return b and a or 1 end)
            data.mailQuests[1]=q; assert(Entities.ensure(data)); assert(offer().ok)
            assert(run('host','passenger.recruit',args('ride')).reason=='recipient_has_delivery')
            assert(#data.passengers==0 and not data.questAsked['4:'..npc])
            q.complete=true
            local reply=run('host','passenger.recruit',args('ride')); assert(reply.ok,reply.reason)
            assert(data.passengers[1].characterId==q.recipientId)
        ''')

    def test_supply_offer_roll_is_saved_once_and_preserved_after_reload(self):
        self.lua.execute('''
            local req=assert(service:prepareRequest('host','quest.offer',args()))
            assert(not layout.coopOffers and data.coop.randomState==nil)
            local reply=execute('host',req); assert(reply.ok and reply.durable)
            local kind=reply.result.offer.deliveryKind; local rng=data.coop.randomState
            assert(layout.deliveryOffers[npc]==kind and #data.supplyDeliveryCycle.seen==1)
            assert(execute('host',req).ok and data.coop.randomState==rng)
            assert(offer().ok and data.coop.randomState==rng and #data.supplyDeliveryCycle.seen==1)
            local loaded=assert(Schema.migrate(saved)); assert(loaded.stopLayouts['4'].coopOffers[npc].deliveryKind==kind)
            assert(Decisions.text(layout,npc,reply.result.offer,Catalog)==require('game.quest_progression').deliveryProfile(kind).request)
        ''')

    def test_all_delivery_kinds_accept_the_stored_offer_without_rerolling(self):
        self.lua.execute('''
            for _,kind in ipairs(require('game.quest_progression').deliveryKinds) do
                setup('supplies'); layout.deliveryOffers={[npc]=kind}; assert(offer().ok)
                local reply=decide('supplies'); assert(reply.ok and reply.durable)
                local q=data.supplyQuests[1]
                assert(q.cargoKind==kind and q.destination>4 and q.destination<=10 and q.amount==require('game.quest_progression').deliveryProfile(kind).amount)
                assert(q.entityId==reply.result.entityId and data.questAsked['4:'..npc] and layout.coopOffers[npc].status=='accepted')
                assert(data.resources.food==10 and data.stats.xp==4 and data.players.companion.stats.xp==4)
                assert(decide('supplies').reason=='offer_unavailable' and #data.supplyQuests==1)
                assert(Schema.validate(data))
            end
        ''')

    def test_mail_destination_and_recipient_use_host_rng_without_global_random(self):
        self.lua.execute('''
            setup('mail'); data.npcRoster={'one.png','two.png'}
            love.math.random=function() error('global RNG must not make a host quest decision') end
            assert(offer().ok); local reply=decide('mail'); assert(reply.ok,reply.reason)
            local quest=data.mailQuests[1]; local stop=data.stopLayouts[tostring(quest.destination)]
            assert(quest.destination>=7 and quest.destination<=12 and quest.sender==npc and quest.recipient==stop.npc)
            assert(stop.npc=='one.png' or stop.npc=='two.png')
            assert(stop.houseX>=390 and stop.houseX<=700 and stop.entityId and quest.entityId==reply.result.entityId)
            assert(Schema.validate(data) and saved.mailQuests[1].recipient==stop.npc)
        ''')

    def test_decline_is_durable_and_never_creates_work_or_consumes_another_roll(self):
        self.lua.execute('''
            for _,kind in ipairs({'mail','ride','supplies','trade','item','aid'}) do
                setup(kind); assert(offer().ok); local rng=data.coop.randomState
                local req=assert(service:prepareRequest('host','quest.decline',args(kind)))
                local reply=execute('host',req); assert(reply.ok and reply.durable and reply.result.declined)
                assert(execute('host',req).ok and data.coop.randomState==rng)
                assert(layout.coopOffers[npc].status=='declined' and saved.questAsked['4:'..npc])
                assert(#data.mailQuests==0 and #data.supplyQuests==0 and #data.passengers==0)
                if request then assert(not request.accepted and data.helpQuestSessions[request.sessionId].state=='offered') end
                assert(offer().reason=='offer_unavailable' and not decide(kind).ok)
            end
        ''')

    def test_offer_target_kind_and_reach_cannot_be_forged(self):
        self.lua.execute('''
            assert(decide('supplies').reason=='offer_changed')
            local bad=args(); bad.targetId='e999'; assert(run('host','quest.offer',bad).reason=='recipient_unavailable')
            bad=args(); bad.reward=999; assert(run('host','quest.offer',bad).reason=='invalid_args')
            states.host.x=1000; assert(offer().reason=='recipient_unavailable')
            states.host.x=0/0; assert(offer().reason=='recipient_unavailable')
            states.host.x=140; states.host.npc.id='other'; assert(offer().reason=='recipient_unavailable')
            states.host.npc.id=npc; assert(offer().ok)
            assert(decide('mail').reason=='offer_changed' and not data.questAsked['4:'..npc])
            states.host.traveling=true; assert(not decide('supplies').ok)
            assert(#data.supplyQuests==0)
        ''')

    def test_stale_quote_fails_when_the_stored_delivery_kind_changes(self):
        self.lua.execute('''
            assert(offer().ok)
            local req=assert(service:prepareRequest('host','quest.accept',args('supplies')))
            data.coop.revisions['entity:'..layout.entityId]=data.coop.revisions['entity:'..layout.entityId]+1
            assert(execute('host',req).reason=='stale_revision')
            assert(#data.supplyQuests==0 and not data.questAsked['4:'..npc])
        ''')

    def test_failed_checkpoint_retries_without_creating_duplicate_work(self):
        self.lua.execute('''
            assert(offer().ok); failSave=true
            local req=assert(service:prepareRequest('host','quest.accept',args('supplies')))
            local reply=execute('host',req); assert(reply.ok and reply.savePending and not reply.durable)
            local rng=data.coop.randomState; local id=data.supplyQuests[1].entityId
            assert(execute('host',req).savePending and #data.supplyQuests==1 and data.coop.randomState==rng)
            failSave=false; assert(service:retryCheckpoint())
            assert(execute('host',req).durable and saved.supplyQuests[1].entityId==id and #saved.supplyQuests==1)
        ''')

    def test_recruitment_moves_the_existing_weapon_instance_once(self):
        self.lua.execute('''
            setup('ride'); layout.npcWeapon='frontier-short-sword'; assert(Items.ensure(data))
            local weapon=layout.npcWeaponInstance.id; layout.npcWeaponInstance.durability=17
            assert(offer().ok)
            local req=assert(service:prepareRequest('host','passenger.recruit',args('ride')))
            local reply=execute('host',req); assert(reply.ok and reply.durable)
            local passenger=data.passengers[1]
            assert(passenger.weapon=='frontier-short-sword' and passenger.weaponInstance.id==weapon and passenger.weaponInstance.durability==17)
            assert(not layout.npcWeapon and not layout.npcWeaponInstance and passenger.entityId==reply.result.entityId)
            assert(passenger.origin==4 and passenger.destination>4 and passenger.destination<=50 and passenger.job=='scavenger')
            assert(execute('host',req).ok and #data.passengers==1 and data.relationships[passenger.characterId].rides==1)
            assert(Schema.validate(data))
        ''')

    def test_invalid_recruitment_spawn_rolls_back_asked_rng_and_weapon_ownership(self):
        self.lua.execute('''
            setup('ride'); layout.npcWeapon='frontier-short-sword'; assert(Items.ensure(data)); local id=layout.npcWeaponInstance.id
            assert(offer().ok); local rng=data.coop.randomState
            context.car.x=0/0
            assert(run('host','passenger.recruit',args('ride')).reason=='passenger_spawn_unavailable')
            assert(#data.passengers==0 and not data.questAsked['4:'..npc] and data.coop.randomState==rng)
            assert(layout.npcWeaponInstance.id==id and layout.coopOffers[npc].status=='offered')
        ''')

    def test_accepting_aid_without_host_supplies_still_allows_guest_treatment(self):
        self.lua.execute('''
            setup('aid'); assert(offer().ok and decide('aid').ok)
            local quest=data.helpQuestSessions[request.sessionId]
            assert(request.accepted and quest.state=='investigating' and not quest.rewardClaimed)
            local guest=Players.forActor(data,'companion'); Items.write(guest,nil,{kind='inventory',index=1},'field-bandage-roll')
            local source={kind='inventory',index=1}
            local reply=run('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc,source=source,
                selected=require('game.coop_item_contract').selection(guest,nil,source)})
            assert(reply.ok,reply.reason); assert(quest.state=='active' and data.players.host.inventory[1]==nil)
        ''')

    def test_only_accepted_item_requests_can_be_completed_by_the_guest(self):
        self.lua.execute('''
            setup('item'); local guest=Players.forActor(data,'companion')
            Items.write(guest,nil,{kind='inventory',index=1},request.item)
            local source={kind='inventory',index=1}
            local params={targetId=layout.entityId,npc=npc,source=source,selected=require('game.coop_item_contract').selection(guest,nil,source)}
            assert(run('companion','quest.help',params).reason=='quest_unavailable')
            assert(offer().ok and decide('item').ok)
            assert(run('companion','quest.help',params).ok and request.complete and not guest.inventory[1])
            assert(data.players.host.inventory[1]==nil and not decide('item').ok)
        ''')

    def test_saved_offer_cannot_smuggle_text_or_mismatched_decision_state(self):
        self.lua.execute('''
            assert(offer().ok)
            local copy=assert(Schema.copy(data)); copy.stopLayouts['4'].coopOffers[npc].text='invented'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].coopOffers[npc].status='accepted'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].coopOffers[npc].deliveryKind='made-up'
            assert(not Schema.validate(copy))
        ''')

    def journey_adapter(self):
        source = (ROOT / 'game/journey_rules.lua').read_text(encoding='utf-8')
        context = self.lua.table()
        for name, kind in re.findall(r'required\(context,\s*"([^\"]+)",\s*"([^\"]+)"\)', source):
            context[name] = self.lua.table() if kind == 'table' else self.lua.eval('function() end')
        self.lua.globals().journeyContext = context
        self.lua.execute('''
            function makeJourney(kind)
                setup(kind); data.conversations={assignments={},completed={},seen={}}
                local GameSession=require('game.game_session'); session=GameSession.new()
                session.saveData=data; session.scene='stop'; session.screen='game'
                runtime={saveData=data,state='game',scene='stop',animationClock=0,session=session,
                    player={x=140,y=100},npcActor={x=100,y=100}}
                commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,car=context.car,
                    clock=function() return now end,checkpoint=function(value)
                        writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true
                    end})
                commands.setRemoteActorState(function() return states.companion end)
                commands.authority():admit('companion',1)
                journeyContext.commands=commands; journeyContext.runtime=runtime; journeyContext.catalog=Catalog
                journeyContext.car=context.car; journeyContext.util=require('game.util')
                journeyContext.stopHelpProgression=Help; journeyContext.helpQuestSession=Sessions
                journeyContext.questProgression=require('game.quest_progression')
                journeyContext.firstAid=require('game.first_aid'); journeyContext.passengers=require('game.passengers')
                journeyContext.helpDialogueQuests=require('game.help_dialogue_quests')
                journeyContext.npcRelationships=require('game.npc_relationships')
                journeyContext.ensureStopLayout=function() return layout end
                journeyContext.writeSave=function() error('quest controls must use the command checkpoint') end
                journey=require('game.journey_rules').new(journeyContext)
            end
        ''')

    def test_production_offer_accept_and_decline_use_checkpointed_commands_for_all_kinds(self):
        self.journey_adapter()
        self.lua.execute('''
            for _,kind in ipairs({'mail','ride','supplies','trade','item','aid'}) do
                makeJourney(kind); assert(journey.talkToNPC())
                assert(runtime.questOffer.kind==kind and runtime.dialogue.choice and saved.stopLayouts['4'].coopOffers[npc].status=='offered')
                local reply=journey.acceptQuest(kind); assert(reply.ok and reply.durable,kind..':'..tostring(reply.reason))
                assert(not runtime.questOffer and saved.questAsked['4:'..npc])
                assert(saved.stopLayouts['4'].coopOffers[npc].status=='accepted')
                assert(data.scene=='stop' and data.location==4 and data.coop.sceneEpoch==1)
                if kind=='item' or kind=='aid' then
                    assert(request.accepted and not runtime.firstAid)
                    journey.talkToNPC(); assert(not runtime.questOffer and request.accepted)
                end
                makeJourney(kind); assert(journey.talkToNPC() and journey.declineQuestOffer())
                assert(not runtime.questOffer and runtime.dialogue.text=='Task declined.')
                assert(saved.stopLayouts['4'].coopOffers[npc].status=='declined' and saved.questAsked['4:'..npc])
                assert(#data.passengers==0 and #data.mailQuests==0 and #data.supplyQuests==0)
            end
        ''')

    def test_failed_acceptance_clears_choice_ui_and_guest_help_waits_for_retry(self):
        self.journey_adapter()
        self.lua.execute('''
            for _,kind in ipairs({'item','aid'}) do
                makeJourney(kind); assert(journey.talkToNPC()); failSave=true
                local reply=journey.acceptQuest(kind); assert(reply.ok and reply.savePending and session.checkpointPending)
                assert(request.accepted and not runtime.questOffer and not runtime.dialogue and not runtime.firstAid)
                assert(saved.stopLayouts['4'].coopOffers[npc].status=='offered')
                local guest=Players.forActor(data,'companion'); local supply=kind=='aid' and 'field-bandage-roll' or request.item
                Items.write(guest,nil,{kind='inventory',index=1},supply)
                local source={kind='inventory',index=1}
                local command=kind=='aid' and 'firstAid.acquire' or 'quest.help'
                local params={targetId=layout.entityId,npc=npc,source=source,
                    selected=require('game.coop_item_contract').selection(guest,nil,source)}
                local authority=commands.authority()
                local req,reason=authority:prepareRequest('companion',command,params)
                assert(not req and reason=='save_pending')
                req={sessionId=authority.sessionId,requestId=1,sceneEpoch=data.coop.sceneEpoch,command=command,args=params,expected={}}
                assert(commands.remote(1,req).reason=='save_pending')
                failSave=false; assert(commands.retryCheckpoint() and not session.checkpointPending)
                req=assert(authority:prepareRequest('companion',command,params))
                local outcome=commands.remote(1,req); assert(outcome.ok and not outcome.savePending,outcome.reason)
                if kind=='item' then assert(outcome.durable) end
                assert(saved.stopLayouts['4'].coopOffers[npc].status=='accepted' and data.players.host.inventory[1]==nil)
                assert(kind=='aid' and outcome.result.session or kind=='item' and request.complete)
            end
        ''')

    def test_guest_runtime_cannot_use_host_offer_controls(self):
        self.journey_adapter()
        self.lua.execute('''
            makeJourney('supplies'); assert(journey.talkToNPC())
            session:setNetworkMode('client')
            local rng=data.coop.randomState
            local ok,reason=journey.acceptQuest('supplies'); assert(ok==false and reason=='host_only')
            ok,reason=journey.declineQuestOffer(); assert(ok==false and reason=='host_only')
            assert(runtime.questOffer and not data.questAsked['4:'..npc] and data.coop.randomState==rng and #data.supplyQuests==0)
        ''')

    def test_npc_treatment_lease_blocks_new_offer_and_decision(self):
        self.lua.execute('''
            assert(offer().ok)
            local lease=assert(require('game.coop_leases').acquire(service.activityState,'firstAid:patient','companion',1,
                data.coop.sceneEpoch,now,{kind='firstAid',targetId=layout.entityId,npc=npc}))
            assert(offer().reason=='activity_busy' and decide('supplies').reason=='activity_busy')
            assert(not data.questAsked['4:'..npc])
            now=31; assert(decide('supplies').ok)
        ''')

    def test_saved_mail_line_and_help_identity_must_match_real_records(self):
        self.lua.execute('''
            setup('mail'); assert(offer().ok)
            local copy=assert(Schema.copy(data)); copy.stopLayouts['4'].coopOffers[npc].lineIndex=99
            assert(not Schema.validate(copy))
            setup('aid'); assert(offer().ok)
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].coopOffers[npc].requestSessionId='first-aid:4:someone-else'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.helpQuestSessions[request.sessionId].npc='someone-else'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].helpRequests=4
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].helpRequests[npc]='invalid'
            assert(not Schema.validate(copy))
            assert(decide('aid').ok)
            copy=assert(Schema.copy(data)); copy.helpQuestSessions[request.sessionId].state='offered'
            assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.helpQuestSessions[request.sessionId].source='item-request'
            assert(not Schema.validate(copy))
            setup('supplies'); assert(offer().ok)
            copy=assert(Schema.copy(data)); copy.stopLayouts['4'].deliveryOffers=4
            assert(not Schema.validate(copy))
        ''')

    def test_stop_refresh_preserves_paused_guest_treatment_and_command_objective(self):
        self.lua.execute('''
            setup('aid'); assert(offer().ok and decide('aid').ok)
            local quest=data.helpQuestSessions[request.sessionId]
            quest.state='active'; quest.paused=true; quest.objective='Find the small cut, then complete all five treatment steps.'
            quest.progress={phase=3}; data.activeHelpQuestId=nil
            local again=Help.ensureRequest(layout,npc,'aid',4,data)
            assert(again==request and quest.paused and quest.state=='active' and quest.progress.phase==3)
            assert(quest.objective=='Find the small cut, then complete all five treatment steps.' and not data.activeHelpQuestId)
            request.complete=true; quest.state='resolved'; quest.rewardClaimed=true; quest.result='exceptional'; quest.rewardGoodwill=4
            Help.ensureRequest(layout,npc,'aid',4,data)
            assert(quest.rewardClaimed and quest.result=='exceptional' and quest.rewardGoodwill==4)
        ''')

    def test_recruited_resident_does_not_regenerate_the_transferred_weapon(self):
        self.lua.execute('''
            setup('ride'); layout.offerPolicyVersion=Help.policyVersion; layout.npcInside='another.png'
            layout.npcWeapon='frontier-short-sword'; assert(Items.ensure(data)); local weapon=layout.npcWeaponInstance.id
            assert(offer().ok and run('host','passenger.recruit',args('ride')).ok)
            require('game.stops').ensure(data,Catalog,'stop',function() return .4 end); assert(Items.ensure(data))
            assert(not layout.npcWeapon and not layout.npcWeaponInstance and data.passengers[1].weaponInstance.id==weapon)
            assert(Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
