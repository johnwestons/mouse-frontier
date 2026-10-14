"""Routine accepted work cannot accept offers, double-pay, or use another pack."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopQuestTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Authority=require('game.coop_authority'); Schema=require('game.save_schema')
            Players=require('game.coop_players'); Entities=require('game.coop_entities')
            Help=require('game.stop_help_progression'); Quests=require('game.help_quest_session')
            Items=require('game.item_instances'); Loot=require('game.loot_progression')
            data=Fixtures.campaign(4); assert(Fixtures.enroll(data)); data.scene='stop'
            layout={}; data.stopLayouts['4']=layout; npc='recipient.png'; data.currentNPC=npc
            for _,id in ipairs({'host','companion'}) do
                local actor=Players.forActor(data,id)
                for slot=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=slot},nil) end
            end
            states={}
            for _,id in ipairs({'host','companion'}) do
                states[id]={screen='game',scene='stop',x=140,y=100,npc={id=npc,x=100,y=100}}
            end
            service=Authority.new({campaign=data,sessionId='quests',randomSeed=4891,clock=function() return 0 end})
            require('game.coop_quests').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1)
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function addQuest(kind)
                local quest={origin=1,destination=4,recipient=npc,cargoKind=kind,complete=false}
                local collection=kind=='mail' and data.mailQuests or data.supplyQuests
                collection[#collection+1]=quest; assert(Entities.ensure(data))
                return quest
            end
            function arguments(quest)
                if quest then return {targetId=layout.entityId,npc=npc,questId=quest.entityId} end
                local actor=Players.forActor(data,'companion'); local source={kind='inventory',index=1}
                return {targetId=layout.entityId,npc=npc,source=source,selected=require('game.coop_item_contract').selection(actor,nil,source)}
            end
            function deliver(actor,quest) return run(actor,'quest.deliver',arguments(quest)) end
            function put(id,slot,name) Items.write(Players.forActor(data,id),nil,{kind='inventory',index=slot},name) end
            function oneItem(effect)
                for name,profile in pairs(Catalog.itemEffects) do if profile[effect] then return name end end
            end
        ''')

    def test_guest_mail_grants_shared_reward_once_and_records_each_connected_xp_recipient(self):
        self.lua.execute('''
            local quest=addQuest('mail'); local before=data.scrap
            local hostXp,guestXp=data.stats.xp,data.players.companion.stats.xp
            local req=assert(service:prepareRequest('companion','quest.deliver',arguments(quest)))
            assert(not quest.complete and data.coop.randomState==nil)
            local reply=execute('companion',req); assert(reply.ok and reply.result.completed)
            local reward=reply.result.reward
            assert(quest.complete and quest.completedBy=='companion' and quest.rewardItem==reward.item)
            assert(quest.rewardRecipients.host==reward.xp and quest.rewardRecipients.companion==reward.xp)
            assert(data.stats.xp==hostXp+reward.xp and data.players.companion.stats.xp==guestXp+reward.xp)
            assert(data.scrap==before+reward.scrapAdded and data.goodwill==1)
            assert(data.inventory[1]==nil and data.players.companion.inventory[1]==reward.item)
            local rng=data.coop.randomState
            assert(execute('companion',req).ok and data.coop.randomState==rng and data.goodwill==1)
            assert(deliver('host',quest).reason=='quest_unavailable')
            assert(Schema.migrate(data).mailQuests[1].rewardRecipients.companion==reward.xp)
            assert(data.location==4 and data.scene=='stop' and data.conversations.completed.example.answer==2)
        ''')

    def test_each_supply_kind_uses_only_acting_inventory_ammo_and_shared_resources(self):
        for kind in ('food', 'water', 'medicine', 'repair', 'ammunition', 'recovery'):
            with self.subTest(kind=kind):
                self.setUp()
                self.lua.globals().kind = kind
                self.lua.execute('''
                    local quest=addQuest(kind); put('host',1,'field-bandage-roll')
                    if kind=='food' or kind=='water' then
                        put('companion',1,oneItem(kind)); put('companion',2,oneItem(kind))
                    elseif kind=='medicine' then
                        put('companion',1,'field-bandage-roll'); put('companion',2,'field-bandage-roll')
                    elseif kind=='repair' then put('companion',1,'coal-chunk'); put('companion',2,'coal-chunk')
                    elseif kind=='ammunition' then data.players.companion.ammo={rocks=8}; data.ammo={rocks=25}
                    else data.encounters['4']={hasMob=true,resolved=false}
                        assert(deliver('companion',quest).reason=='cargo_unavailable' and not quest.complete)
                        data.encounters['4'].resolved=true
                    end
                    local food,water,coal=data.resources.food,data.resources.water,data.resources.coal
                    local reply=deliver('companion',quest); assert(reply.ok,reply.reason)
                    assert(quest.complete and data.inventory[1]=='field-bandage-roll' and data.ammo.rocks~=nil)
                    if kind=='food' then assert(data.resources.food==food-1)
                    elseif kind=='water' then assert(data.resources.water==water-1)
                    elseif kind=='repair' then assert(data.resources.coal==coal-1+reply.result.reward.coalAdded)
                    elseif kind=='ammunition' then
                        local extra=reply.result.reward.item=='rocks' and Catalog.ammoPickupAmounts.rocks or 0
                        assert(data.players.companion.ammo.rocks==extra and data.ammo.rocks==25)
                    end
                ''')

    def test_unaccepted_item_help_is_rejected_and_accepted_help_costs_guest_once(self):
        self.lua.execute('''
            local request=Help.ensureRequest(layout,npc,'item',4,data)
            put('companion',1,request.item); put('host',1,request.item)
            assert(run('companion','quest.help',arguments()).reason=='quest_unavailable')
            request.accepted=true; Quests.accept(data,request.sessionId)
            local req=assert(service:prepareRequest('companion','quest.help',arguments()))
            assert(execute('companion',req).result.completed and request.complete)
            assert(data.players.companion.inventory[1]==nil and data.inventory[1]==request.item)
            assert(data.goodwill==2 and execute('companion',req).result.completed and data.goodwill==2)
            assert(run('host','quest.help',arguments()).reason=='quest_unavailable')
        ''')

    def test_shortage_preserves_items_reward_markers_and_random_state(self):
        self.lua.execute('''
            local quest=addQuest('medicine'); put('companion',1,'field-bandage-roll')
            local seed=data.coop.randomState
            assert(deliver('companion',quest).reason=='cargo_unavailable')
            assert(data.coop.randomState==seed and not quest.complete and not quest.rewardRecipients)
            assert(data.players.companion.inventory[1]=='field-bandage-roll' and data.goodwill==0)
        ''')

    def test_selected_request_item_uses_that_owned_slot_and_identity_without_fallback(self):
        self.lua.execute('''
            local request=Help.ensureRequest(layout,npc,'item',4,data)
            request.item='frontier-short-sword'; request.accepted=true; Quests.accept(data,request.sessionId)
            put('companion',1,request.item); put('companion',3,request.item); put('host',1,request.item)
            local actor=Players.forActor(data,'companion'); local source={kind='inventory',index=3}
            local selected=require('game.coop_item_contract').selection(actor,nil,source)
            local args={targetId=layout.entityId,npc=npc,source=source,selected=selected}
            local req=assert(service:prepareRequest('companion','quest.help',args))
            put('companion',3,request.item); assert(execute('companion',req).reason=='item_changed')
            assert(actor.inventory[1]==request.item and actor.inventory[3]==request.item and not request.complete)
            args.selected=require('game.coop_item_contract').selection(actor,nil,source)
            assert(run('companion','quest.help',args).result.completed)
            assert(actor.inventory[1]==request.item and actor.inventory[3]==nil and data.inventory[1]==request.item and data.goodwill==2)
        ''')

    def test_dead_encounter_car_transition_and_wrong_current_recipient_block_hand_ins(self):
        self.lua.execute('''
            local q=addQuest('mail'); data.players.companion.health=0
            assert(deliver('companion',q).reason=='recipient_unavailable'); data.players.companion.health=25
            states.companion.encounterActive=true; assert(deliver('companion',q).reason=='recipient_unavailable')
            states.companion.encounterActive=false; states.companion.changingCar=true
            assert(deliver('companion',q).reason=='recipient_unavailable'); states.companion.changingCar=false
            data.currentNPC='different.png'; assert(deliver('companion',q).reason=='recipient_unavailable')
            assert(not q.complete and data.goodwill==0 and data.coop.randomState==nil)
        ''')

    def test_explicit_offers_and_story_item_requests_are_not_routine_assistance(self):
        self.lua.execute('''
            local q=addQuest('mail'); q.accepted=false; assert(deliver('companion',q).reason=='quest_unavailable')
            q.accepted=nil; q.state='offered'; assert(deliver('companion',q).reason=='quest_unavailable')
            local request=Help.ensureRequest(layout,npc,'item',4,data); request.accepted=true; Quests.accept(data,request.sessionId)
            put('companion',1,request.item); request.storyHandIn=true
            assert(run('companion','quest.help',arguments()).reason=='quest_unavailable' and not request.complete)
            assert(data.players.companion.inventory[1]==request.item and data.goodwill==0)
        ''')

    def test_hidden_ammo_roll_uses_the_same_possible_overflow_dependencies_as_guest_view(self):
        self.lua.execute('''
            local actor=Players.forActor(data,'companion'); for i=1,actor.inventoryCapacity do put('companion',i,'cowboy-hat') end
            local mailbox={name='mailbox-reward',scene='train',x=10,y=20,storage={}}; data.droppedItems[#data.droppedItems+1]=mailbox
            Entities.ensure(data); local q=addQuest('mail')
            local Access=require('game.coop_quest_access'); local expected=Access.expected(actor,'companion','quest.deliver',q,layout.entityId,Catalog)
            Loot.rollItem=function() return 'rocks' end
            local req=assert(service:prepareRequest('companion','quest.deliver',arguments(q)))
            for k,v in pairs(expected) do assert(req.expected[k]==v) end
            for k,v in pairs(req.expected) do assert(expected[k]==v) end
            assert(expected['entity:'..mailbox.entityId]==0)
            local r=execute('companion',req); assert(r.ok and r.result.reward.delivery=='ammunition' and not mailbox.storage[1])
            local dto=assert(require('game.net.item_results').project('quest.deliver',r.result)); assert(dto.amount==Catalog.ammoPickupAmounts.rocks)
        ''')

    def test_target_identity_proximity_destination_and_story_boundary_are_checked(self):
        self.lua.execute('''
            local quest=addQuest('mail'); quest.recipient='someone-else.png'
            assert(deliver('companion',quest).reason=='quest_unavailable')
            quest.recipient=npc; states.companion.x=250
            assert(deliver('companion',quest).reason=='recipient_unavailable')
            states.companion.x=140; quest.destination=5
            assert(deliver('companion',quest).reason=='quest_unavailable')
            quest.destination=4; quest.storyHandIn=true
            assert(deliver('companion',quest).reason=='story_hand_in' and not quest.complete)
            quest.storyHandIn=nil
            local args=arguments(quest); args.reward={xp=1000}
            assert(run('companion','quest.deliver',args).reason=='invalid_args')
            args=arguments(quest); args.actorId='host'
            assert(run('companion','quest.deliver',args).reason=='invalid_args')
        ''')

    def test_offline_companion_gets_no_xp_and_admission_change_invalidates_prepared_recipients(self):
        self.lua.execute('''
            local quest=addQuest('mail'); local xp=data.players.companion.stats.xp
            local req=assert(service:prepareRequest('host','quest.deliver',arguments(quest)))
            service:disconnect('companion',1)
            assert(not execute('host',req).ok and not quest.complete)
            assert(deliver('host',quest).ok)
            assert(quest.rewardRecipients.host and not quest.rewardRecipients.companion and data.players.companion.stats.xp==xp)
        ''')

    def test_failure_after_awards_rolls_back_rng_xp_items_currency_and_completion(self):
        self.lua.execute('''
            local quest=addQuest('mail'); local xp=data.stats.xp; local scrap=data.scrap
            local original=Help.add
            Help.add=function(...) original(...); error('injected failure') end
            assert(deliver('companion',quest).reason=='handler_error')
            assert(data.stats.xp==xp and data.scrap==scrap and data.goodwill==0 and data.coop.randomState==nil)
            assert(not quest.complete and data.players.companion.inventory[1]==nil)
            Help.add=original
            local before=assert(Schema.copy(data))
            local result=deliver('companion',quest); assert(result.ok)
            local expected=require('game.quest_progression').rollReward(Catalog,Loot,'mail',1,4,
                before.players.companion.trait,require('game.coop_random').generator(before,4891))
            assert(result.result.reward.item==expected.item and data.coop.randomState==before.coop.randomState)
        ''')

    def test_full_pack_reward_uses_mailbox_then_local_crate_with_unique_gear(self):
        self.lua.execute('''
            for slot=1,data.players.companion.inventoryCapacity do put('companion',slot,'cowboy-hat') end
            local mailbox={name='mailbox-reward',scene='train',x=10,y=20,storage={}}
            data.droppedItems[#data.droppedItems+1]=mailbox; Entities.ensure(data)
            Loot.rollItem=function() return 'frontier-short-sword' end
            local first=deliver('companion',addQuest('mail')); assert(first.ok and first.result.reward.delivery=='mailbox')
            local identity=assert(mailbox.storageInstances[1].id)
            for slot=1,Catalog.storageCapacities['mailbox-reward'] do
                Items.write(data,mailbox,{kind='chest',index=slot},'cowboy-hat')
            end
            local second=deliver('companion',addQuest('mail'))
            assert(second.ok and second.result.reward.delivery=='local supply crate')
            local crate=data.droppedItems[#data.droppedItems]
            assert(crate.name=='supply-crate' and crate.location==4 and crate.storage[1]=='frontier-short-sword')
            assert(crate.storageInstances[1].id~=identity and crate.entityId and Schema.validate(data))
        ''')

    def test_saved_rng_continues_after_reload_and_invalid_state_is_rejected(self):
        self.lua.execute('''
            assert(deliver('host',addQuest('mail')).ok)
            local reloaded=assert(Schema.migrate(data)); local original=assert(Schema.copy(data))
            local random=require('game.coop_random')
            local a,b=random.generator(original,1),random.generator(reloaded,999)
            for i=1,10 do assert(a()==b()) end
            reloaded.coop.randomState=0; assert(not Schema.validate(reloaded))
        ''')


if __name__ == "__main__":
    unittest.main()
