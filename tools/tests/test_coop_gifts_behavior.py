"""Actual host gift transactions, access checks, replay and offline UI route."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopGiftsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures')
            Schema=require('game.save_schema'); Catalog=require('game.catalog')
            Items=require('game.item_instances'); Entities=require('game.coop_entities')
            Inventory=require('game.inventory'); Players=require('game.coop_players')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data))
            data.scene='train'
            passenger={npc='medic-mouse.png',x=200,y=250,carIndex=1,weapon='frontier-short-sword'}
            data.passengers={passenger}
            assert(Entities.ensure(data)); assert(Items.ensure(data))
            states={host={screen='game',scene='train',x=200,y=250},
                companion={screen='game',scene='train',x=200,y=250}}
            authority=require('game.coop_authority').new({campaign=data,sessionId='gift-test'})
            require('game.coop_gifts').install(authority,{catalog=Catalog,actorState=function(id) return states[id] end})
            authority:admit('companion',1)
            function args() return {targetId=passenger.entityId,npc=passenger.npc,source={kind='equipment',index=1}} end
            function request(actor,command,arguments) return assert(authority:prepareRequest(actor,command,arguments or args())) end
            function run(actor,req) return authority:execute(actor,actor=='host' and 0 or 1,req) end
        ''')

    def test_competing_gifts_and_retry_commit_one_item_and_one_relationship_change(self):
        self.lua.execute('''
            local hostId=data.itemSlots.equipment[1].id
            local friendId=data.players.companion.itemSlots.equipment[1].id
            local oldId=passenger.weaponInstance.id
            local host=request('host','npc.gift'); local friend=request('companion','npc.gift')
            local result=run('host',host); assert(result.ok)
            assert(result.result.retiredItemId==oldId and result.result.itemId==hostId)
            assert(passenger.weaponInstance.id==hostId and passenger.weaponInstance.durability==67)
            assert(run('companion',friend).reason=='stale_revision')
            assert(run('host',host).ok and data.relationships[passenger.npc].gifts==1)
            assert(data.equipment[1]==nil and data.players.companion.itemSlots.equipment[1].id==friendId)
            assert(Items.validate(data))
        ''')

    def test_source_selector_and_unavailable_actor_cannot_consume_replacement_gear(self):
        self.lua.execute('''
            local offer=args(); offer.sourceItem=require('game.coop_item_contract').selection(Players.forActor(data,'companion'),nil,offer.source)
            local req=request('companion','passenger.equip',offer)
            data.players.companion.itemSlots.equipment[1].id='replacement-test-gear'
            assert(run('companion',req).reason=='stale_item' and passenger.weapon=='frontier-short-sword')
            for _,flag in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                states.companion[flag]=true; local prepared,reason=authority:prepareRequest('companion','npc.gift',args())
                assert(not prepared and reason=='unavailable'); states.companion[flag]=nil
            end
            data.players.companion.health=0; local prepared,reason=authority:prepareRequest('companion','npc.gift',args())
            assert(not prepared and reason=='unavailable' and not data.relationships[passenger.npc])
        ''')

    def test_chatter_only_cycles_approved_pool_and_persists_shared_history_without_story(self):
        self.lua.execute('''
            local original=table.concat(Catalog.dialogueLines,'|'); local previous; local seen={}
            local conversations=assert(Schema.copy(data.conversations))
            for i=1,#Catalog.dialogueLines do
                local req=request('companion','passenger.chatter',{targetId=passenger.entityId,npc=passenger.npc})
                local reply=run('companion',req); assert(reply.ok and reply.result.npc==passenger.npc)
                local index=reply.result.lineIndex; assert(not seen[index] and Catalog.dialogueLines[index])
                seen[index]=true; previous=index
                assert(run('companion',req).result.lineIndex==index and data.relationships[passenger.npc].talks==i)
            end
            local reply=run('host',request('host','passenger.chatter',{targetId=passenger.entityId,npc=passenger.npc}))
            assert(reply.ok and reply.result.lineIndex~=previous and passenger.relationshipTalks==#Catalog.dialogueLines+1)
            assert(table.concat(Catalog.dialogueLines,'|')==original and data.scene=='train' and data.location==1)
            assert(data.conversations.completed.example.answer==conversations.completed.example.answer)
            local saved=assert(Schema.migrate(data)); assert(saved.relationships[passenger.npc].talks==#Catalog.dialogueLines+1)
            local bad={targetId=passenger.entityId,npc=passenger.npc,lineIndex=1}
            local prepared,reason=authority:prepareRequest('companion','passenger.chatter',bad); assert(not prepared and reason=='invalid_arguments')
        ''')

    def test_recipient_scene_car_distance_and_identity_checked_at_execution(self):
        self.lua.execute('''
            local first=request('companion','passenger.equip')
            data.players.companion.activeCar=2
            assert(run('companion',first).reason=='recipient_unavailable')
            data.players.companion.activeCar=1
            local second=request('companion','passenger.equip')
            states.companion.x=800
            assert(run('companion',second).reason=='recipient_unavailable')
            states.companion.x=200
            local third=request('companion','passenger.equip'); third.args.npc='fake.png'
            assert(run('companion',third).reason=='recipient_unavailable')
            local fourth=request('companion','passenger.equip')
            states.companion.screen='battle'
            assert(run('companion',fourth).reason=='unavailable')
            assert(data.players.companion.equipment[1]=='frontier-short-sword')
            assert(data.relationships[passenger.npc]==nil and Items.validate(data))
        ''')

    def test_source_container_and_backpack_capacity_cannot_be_bypassed(self):
        self.lua.execute('''
            local chest={name='mailbox-reward',scene='train',x=220,y=250,carIndex=1,storage={'field-bandage-roll'}}
            data.droppedItems={chest}; assert(Entities.ensure(data))
            local offer=args(); offer.source={kind='chest',index=1}; offer.containerId=chest.entityId
            local valid=request('companion','npc.gift',offer)
            chest.carIndex=2
            assert(run('companion',valid).reason=='container_unavailable' and chest.storage[1]=='field-bandage-roll')
            chest.carIndex=1
            local accepted=run('companion',request('companion','npc.gift',offer))
            assert(accepted.ok and chest.storage[1]==nil)
            local actor=Players.forActor(data,'companion')
            local pack
            for name,profile in pairs(Catalog.wearableItems) do if profile.slot=='backpack' and profile.capacity>6 then pack=name; break end end
            assert(pack)
            Inventory.setValue(actor,nil,{kind='wearable',slot='backpack'},pack,Catalog.wearableItems)
            actor.inventory[7]='food-ration'
            offer=args(); offer.source={kind='wearable',slot='backpack'}
            local prepared,reason=authority:prepareRequest('companion','npc.gift',offer)
            assert(prepared==nil and reason=='backpack_full' and actor.wearables.backpack==pack)
        ''')

    def test_stop_gifts_require_the_active_resident_and_do_not_progress_story(self):
        self.lua.execute('''
            data.scene='house'; data.currentNPC='crow-merchant.png'; data.activeHouseDoor=2
            local layout={npcWeapon='trail-slingshot'}; data.stopLayouts['1']=layout
            data.npcStates['house:1:2']={weapon='trail-slingshot'}
            assert(Entities.ensure(data)); assert(Items.ensure(data))
            states.companion={screen='game',scene='house',x=200,y=250,npc={id=data.currentNPC,x=210,y=250}}
            local offer={targetId=layout.entityId,npc=data.currentNPC,source={kind='equipment',index=1}}
            local request=request('companion','npc.gift',offer)
            local result=run('companion',request)
            assert(result.ok and layout.npcWeaponInstance.id==result.result.itemId)
            assert(data.npcStates['house:1:2'].weapon=='frontier-short-sword')
            assert(data.scene=='house' and data.location==1 and data.activeHouseDoor==2)
            assert(data.conversations.completed.example.answer==2 and Items.validate(data))
        ''')

    def test_offline_inventory_gift_uses_authority_and_preserves_feedback(self):
        self.lua.execute('''
            local GameSession=require('game.game_session')
            local runtime={saveData=data,state='game',scene='train',player={x=200,y=250},nearPassenger=1,
                draggedSlot={kind='equipment',index=1}}
            local session=GameSession.new({runtime=runtime}); session:setSaveData(data)
            local adapter=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog})
            local saves=0
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,
                catalog=Catalog,util=require('game.util'),trainUpgradeBalance=require('game.train_upgrade_balance'),
                lootProgression=require('game.loot_progression'),commands=adapter,
                writeSave=function() saves=saves+1 end,useBattleHealingItem=function() end,useBattlePotion=function() end})
            assert(actions.consumeSelected())
            assert(data.equipment[1]==nil and passenger.weaponInstance.durability==67)
            assert(data.relationships[passenger.npc].gifts==1 and runtime.dialogue.inventoryResult)
            assert(saves==1 and Items.validate(data))
        ''')

    def test_gift_failure_rolls_back_recipient_item_and_relationship_together(self):
        self.lua.execute('''
            local Relationships=require('game.npc_relationships')
            local real=Relationships.recordGift
            Relationships.recordGift=function(...)
                real(...)
                error('forced failure after relationship update')
            end
            local oldId=passenger.weaponInstance.id
            local playerId=data.itemSlots.equipment[1].id
            local result=run('host',request('host','npc.gift'))
            assert(not result.ok and result.reason=='handler_error')
            assert(passenger.weaponInstance.id==oldId and data.itemSlots.equipment[1].id==playerId)
            assert(data.relationships[passenger.npc]==nil and data.coop.revision==0)
            assert(Items.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
