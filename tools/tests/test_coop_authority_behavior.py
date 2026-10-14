"""Actual Lua transactions, world identity, and offline inventory integration."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Schema=require('game.save_schema')
            Entities=require('game.coop_entities')
            Players=require('game.coop_players')
            Fixtures=require('tools.tests.lua.coop_fixtures')
            Catalog=require('game.catalog')
            Authority=require('game.coop_authority')
            data=Fixtures.campaign(20)
            assert(Fixtures.enroll(data))
            chest={name='travel-chest',scene='train',carIndex=1,x=215,y=250,
                storage={[1]='orange-rose-vase',[4]='rocks'}}
            drop={name='cowboy-hat',scene='train',carIndex=1,x=205,y=250}
            data.droppedItems={drop,chest}
            assert(Entities.ensure(data))
            hostInventory=data.inventory
            guest=data.players.companion
            states={host={screen='game',scene='train',x=200,y=250},
                companion={screen='game',scene='train',x=200,y=250}}
            authority=Authority.new({campaign=data,sessionId='test-session'})
            require('game.coop_inventory').install(authority,{catalog=Catalog,
                actorState=function(id) return states[id] end})
            authority:admit('companion',1)
            function request(actor,command,args)
                return assert(authority:prepareRequest(actor,command,args))
            end
            function transfer(actor,index)
                return request(actor,'storage.transfer',{source={kind='chest',index=index or 1},containerId=chest.entityId})
            end
            function run(actor,req,generation)
                return authority:execute(actor,generation or (actor=='host' and 0 or 1),req)
            end
        ''')

    def test_ids_survive_compaction_reload_and_never_recycle(self):
        self.lua.execute('''
            local dropId,chestId=drop.entityId,chest.entityId
            local reply=run('companion',request('companion','loot.pickup',{entityId=dropId}))
            assert(reply.ok and data.droppedItems[1]==chest)
            assert(guest.inventory[1]=='cowboy-hat' and data.inventory==hostInventory)
            assert(data.inventory[1]=='orange-rose-vase' and not Entities.find(data,dropId))
            local id=run('companion',request('companion','loot.drop',{source={kind='inventory',index=1}})).result.entityId
            assert(id~=dropId and Entities.find(data,id))
            local migrated,report=Schema.migrate(data)
            assert(not report.rewriteRequired and migrated.droppedItems[1].entityId==chestId)
            assert(Entities.find(migrated,id) and Schema.validate(migrated))
            local previous=migrated.coop.nextEntityId
            migrated.droppedItems={}
            assert(Schema.migrate(migrated).coop.nextEntityId==previous)
        ''')

    def test_receipt_entity_reference_never_merges_into_live_object(self):
        self.lua.execute('''
            local service=Authority.new({campaign=data,sessionId='entity-receipt',checkpoint=function() return true end})
            service:register('decoration.place',function(draft,id,args)
                local item=assert(Entities.find(draft,drop.entityId))
                return {scopes={'entity:'..item.entityId},apply=function()
                    item.x=400; return {entityId=item.entityId}
                end}
            end)
            local reply=service:submitLocal('decoration.place',{values={x=400}})
            assert(reply.ok and reply.durable and drop.x==400 and drop.name=='cowboy-hat' and drop.scene=='train')
            local receipt=data.coop.checkpoints.receipts[1].response.result
            assert(receipt~=drop and receipt.entityId==drop.entityId and receipt.x==nil and receipt.name==nil)
            local saved=assert(Schema.migrate(data)); assert(saved.droppedItems[1].x==400 and saved.droppedItems[1].name=='cowboy-hat')
            assert(Entities.find(data,drop.entityId)==drop and chest.storage[1]=='orange-rose-vase')
        ''')

    def test_identity_validation_and_deterministic_domains(self):
        self.lua.execute('''
            local a=Fixtures.campaign(5)
            local Areas=require('game.expedition_areas')
            Areas.ensure(a); assert(Entities.ensure(a))
            local areaId=Areas.BADLANDS_SURFACE_ID
            local cache=a.expeditions[areaId].chests['surface-cache']
            local _,record=Entities.find(a,cache.entityId)
            assert(record.kind=='expeditionChest' and record.areaId==areaId)
            local b=assert(Schema.migrate(a))
            assert(b.expeditions[areaId].chests['surface-cache'].entityId==cache.entityId)
            b.droppedItems={ {entityId=cache.entityId} }
            assert(not Schema.migrate(b))
            b=assert(Schema.copy(a)); b.coop.nextEntityId=1
            assert(not Schema.migrate(b))
            b=assert(Schema.copy(a)); b.coop.revisions.x=0/0
            assert(not Schema.migrate(b))
            b=assert(Schema.copy(a)); b.coop.sceneEpoch=-1
            assert(not Schema.migrate(b))
            local shared={name='travel-chest'}
            b=Fixtures.campaign(); b.droppedItems={shared,shared}
            assert(not Entities.ensure(b) and shared.entityId==nil)
        ''')

    def test_competing_transfer_is_atomic_and_replay_is_exact(self):
        self.lua.execute('''
            local first,second=transfer('companion'),transfer('host')
            local response=run('companion',first)
            assert(response.ok and not response.durable)
            assert(guest.inventory[1]=='orange-rose-vase' and chest.storage[1]==nil)
            assert(data.players.companion==guest and data.droppedItems[2]==chest)
            assert(run('host',second).reason=='stale_revision')
            local revision=data.coop.revision
            response.result.moved=false
            assert(run('companion',first).result.moved and data.coop.revision==revision)
            local conflict=assert(Schema.copy(first)); conflict.args.source.index=4
            assert(run('companion',conflict).reason=='request_conflict')
            assert(chest.storage[4]=='rocks')
        ''')

    def test_independent_personal_operations_do_not_conflict(self):
        self.lua.execute('''
            guest.inventory[1]='item-a'
            local args={source={kind='inventory',index=1},target={kind='inventory',index=2}}
            local host=request('host','inventory.swap',args)
            local friend=request('companion','inventory.swap',args)
            assert(run('host',host).ok and run('companion',friend).ok)
            assert(data.inventory[2]=='orange-rose-vase' and guest.inventory[2]=='item-a')
            assert(data.coop.revisions['player:host']==1 and data.coop.revisions['player:companion']==1)
        ''')

    def test_stale_scene_session_peer_and_payload_cannot_act(self):
        self.lua.execute('''
            local req=transfer('companion')
            local wrong=assert(Schema.copy(req)); wrong.sessionId='old'
            assert(run('companion',wrong).reason=='wrong_session')
            wrong=assert(Schema.copy(req)); wrong.actorId='host'
            assert(run('companion',wrong).reason=='invalid_request')
            wrong=assert(Schema.copy(req)); wrong.args.role='host'
            assert(run('companion',wrong).reason=='invalid_arguments')
            req=transfer('companion')
            assert(run('companion',req,2).reason=='unbound_peer')
            data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(run('companion',req).reason=='stale_scene')
            assert(chest.storage[1]=='orange-rose-vase' and next(guest.inventory)==nil)
        ''')

    def test_host_only_and_derived_story_effects_precede_commit(self):
        self.lua.execute('''
            local calls=0
            authority:register('travel.depart',function(d,id,args)
                return {scopes={'journey'},apply=function() calls=calls+1; d.location=d.location+1; return {} end}
            end)
            local req={sessionId='test-session',requestId=1,sceneEpoch=data.coop.sceneEpoch,
                command='travel.depart',args={},expected={journey=0}}
            assert(run('companion',req).reason=='host_only' and calls==0)
            authority:register('quest.deliver',function(d,id,args)
                return {scopes={'quest'},effects={story=true},apply=function() calls=calls+1; return {} end}
            end)
            req.requestId=2; req.command='quest.deliver'; req.expected={quest=0}
            assert(run('companion',req).reason=='host_only' and calls==0)
            assert(data.location==20)
            req.requestId=1; req.command='travel.depart'; req.expected={journey=0}
            assert(run('host',req).ok and data.location==21 and calls==1)
        ''')

    def test_handler_failure_discards_every_staged_mutation(self):
        self.lua.execute('''
            authority:register('merchant.buy',function(d,id,args)
                return {scopes={'resources'},apply=function()
                    d.scrap=d.scrap-20; d.players.companion.inventory[1]='unearned'
                    if args.crash then error('domain failure') end
                    if args.invalid then d.players.companion.health=-1; return {} end
                    return nil,'sold_out'
                end}
            end)
            for _,args in ipairs({{crash=true},{invalid=true},{}}) do
                local result=run('companion',request('companion','merchant.buy',args))
                assert(not result.ok and data.scrap==40 and next(guest.inventory)==nil)
                assert(data.coop.revision==0 and not authority.busy)
            end
        ''')

    def test_rejoin_retains_receipts_and_old_evicted_ids_never_execute(self):
        self.lua.execute('''
            authority.cacheLimit=2
            local req=transfer('companion',4)
            local amount=Catalog.ammoPickupAmounts.rocks
            assert(run('companion',req).ok and guest.ammo.rocks==12+amount)
            authority:disconnect('companion',1)
            assert(run('companion',req).reason=='unbound_peer')
            authority:admit('companion',2)
            assert(run('companion',req).reason=='unbound_peer')
            assert(run('companion',req,2).ok and guest.ammo.rocks==12+amount)
            for n=2,3 do
                local bad=Schema.copy(req); bad.requestId=n; bad.command='unknown'
                assert(not run('companion',bad,2).ok)
            end
            assert(run('companion',req,2).reason=='expired_request')
            assert(guest.ammo.rocks==12+amount and #authority.requests.companion.order==2)
            assert(not pcall(function() authority:admit('companion',1) end))
        ''')

    def test_proximity_capacity_slot_ownership_and_mailbox_constraints(self):
        self.lua.execute('''
            local req=transfer('companion')
            states.companion.x=900
            assert(run('companion',req).reason=='container_unavailable')
            states.companion.x=200; guest.activeCar=2
            assert(not authority:prepareRequest('companion','storage.transfer',req.args))
            guest.activeCar=1
            for _,index in ipairs({0,-1,1.5,10000}) do
                local args={source={kind='inventory',index=index},target={kind='inventory',index=1}}
                assert(not authority:prepareRequest('companion','inventory.swap',args))
            end
            local args={source={kind='inventory',index=1,actorId='host'},target={kind='inventory',index=2}}
            assert(not authority:prepareRequest('companion','inventory.swap',args))
            for n=1,guest.inventoryCapacity do guest.inventory[n]='full' end
            assert(not run('companion',transfer('companion')).ok and chest.storage[1]=='orange-rose-vase')
            local ammo=run('companion',transfer('companion',4))
            assert(ammo.ok and guest.ammo.rocks>12)
            chest.mailbox=true
            local denied=request('companion','storage.transfer',{containerId=chest.entityId,source={kind='inventory',index=1}})
            assert(not run('companion',denied).ok and guest.inventory[1]=='full')
            local swap=request('companion','inventory.swap',{containerId=chest.entityId,
                source={kind='chest',index=1},target={kind='inventory',index=1}})
            assert(not run('companion',swap).ok)
            assert(guest.inventory[1]=='full' and chest.storage[1]=='orange-rose-vase')
        ''')

    def test_offline_inventory_actions_use_the_dispatcher_and_preserve_ui_references(self):
        self.lua.execute('''
            local session=require('game.game_session').new()
            session:setSaveData(data); session:setPlayer({x=200,y=250}); session:setScreen('game')
            local runtime=require('game.runtime_state').new({session=session,transition=function() end})
            runtime.chestOpen=true; runtime.activeChest=chest
            local commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog})
            local writes=0
            local actions=require('game.inventory_actions').new({runtime=runtime,commands=commands,
                inventory=require('game.inventory'),catalog=Catalog,util=require('game.util'),
                trainUpgradeBalance=require('game.train_upgrade_balance'),lootProgression=require('game.loot_progression'),
                writeSave=function() writes=writes+1 end,useBattleHealingItem=function() end,useBattlePotion=function() end})
            assert(actions.moveBetweenSlots({kind='inventory',index=1},{kind='inventory',index=2}))
            assert(data.coop.revisions['player:host']==1 and writes==1)
            assert(actions.quickTransfer({kind='chest',index=1}))
            assert(runtime.activeChest==chest and chest.storage[1]==nil and writes==2)
            assert(actions.collectAmmo({kind='chest',index=4}) and writes==3)
            runtime.nearbyItem=1
            assert(actions.pickUpNearby() and data.droppedItems[1]==chest and writes==4)
            assert(actions.dropFromContainer({kind='inventory',index=2}) and writes==5)
            assert(runtime.activeChest==chest and data.droppedItems[2].entityId)
            session:setNetworkMode('client')
            local ok,reason=actions.moveBetweenSlots({kind='inventory',index=1},{kind='inventory',index=2})
            assert(not ok and reason=='host_only' and writes==5)
        ''')

    def test_consumables_preserve_personal_health_and_shared_supply_limits(self):
        self.lua.execute('''
            guest.health=3
            guest.inventory[1]='field-bandage-roll'
            guest.inventory[2]='green-potion-vial'
            guest.inventory[3]='bean-tin'
            local function consume(index)
                return request('companion','inventory.consume',{source={kind='inventory',index=index}})
            end
            assert(run('companion',consume(1)).ok and guest.health==8 and data.health==17)
            assert(run('companion',consume(2)).ok and guest.nextBattlePotions['green-potion-vial'])
            assert(not data.nextBattlePotions['green-potion-vial'] and guest.health==8)
            data.resources.food=19
            local req=consume(3)
            local result=run('companion',req)
            assert(result.ok and result.result.gained.food==1 and data.resources.food==20)
            assert(run('companion',req).ok and guest.inventory[3]==nil and data.resources.food==20)
            guest.inventory[3]='bean-tin'
            assert(run('companion',consume(3)).reason=='storage_full' and guest.inventory[3]=='bean-tin')
            guest.inventory[4]='blade-hearts'
            local before=guest.maxHealth
            assert(run('companion',consume(4)).ok and guest.maxHealth==before+5 and data.maxHealth==23)
            local spoof=consume(3); spoof.args.amount=99
            assert(run('companion',spoof).reason=='invalid_arguments')
        ''')

    def test_consuming_shared_chest_item_conflicts_with_another_players_transfer(self):
        self.lua.execute('''
            chest.storage[1]='field-bandage-roll'; guest.health=1
            local use=request('companion','inventory.consume',{containerId=chest.entityId,source={kind='chest',index=1}})
            local take=transfer('host')
            assert(run('companion',use).ok and guest.health==6)
            assert(run('host',take).reason=='stale_revision' and chest.storage[1]==nil)
            assert(data.inventory[2]==nil and data.health==17)
        ''')

    def test_fuel_uses_actors_coal_and_authoritative_fire_position(self):
        self.lua.execute('''
            local car=require('game.config').trainCar
            guest.inventory[1]='coal-bucket'; data.inventory[2]='coal-chunk'
            assert(not authority:prepareRequest('companion','train.fuel',{}))
            states.companion.x=car.x+165; states.companion.y=car.y+240
            data.resources.coal=19
            local req=request('companion','train.fuel',{})
            local result=run('companion',req)
            assert(result.ok and result.result.gained==1 and data.resources.coal==20)
            assert(guest.inventory[1]==nil and data.inventory[2]=='coal-chunk')
            assert(run('companion',req).ok and data.inventory[2]=='coal-chunk')
            guest.inventory[1]='coal-bucket'
            assert(run('companion',request('companion','train.fuel',{})).reason=='storage_full')
            guest.activeCar=2
            assert(not authority:prepareRequest('companion','train.fuel',{}))
            assert(guest.inventory[1]=='coal-bucket')
        ''')

    def test_train_purchases_compute_cost_and_reject_races_and_forged_prices(self):
        self.lua.execute('''
            local balance=require('game.train_upgrade_balance')
            local entry=balance.carCatalog[1]
            data.location=50; data.scrap=200
            local host=request('host','train.upgrade',{carId=entry.id})
            local friend=request('companion','train.upgrade',{carId=entry.id})
            assert(run('companion',friend).ok and data.scrap==200-entry.cost)
            assert(run('host',host).reason=='stale_revision' and #data.trainCars==2)
            assert(run('companion',friend).ok and data.scrap==200-entry.cost)
            assert(run('host',request('host','train.upgrade',{carId=entry.id})).reason=='owned')
            local engine=request('companion','train.engineUpgrade',{})
            local cost=require('game.engine_upgrades').next(data.engineLevel).cost
            assert(run('companion',engine).ok and data.engineLevel==1 and data.scrap==200-entry.cost-cost)
            engine=request('companion','train.engineUpgrade',{}); engine.args.cost=0
            assert(run('companion',engine).reason=='invalid_arguments' and data.engineLevel==1)
        ''')

    def test_selected_coal_and_upgrade_quotes_are_revalidated_without_effects(self):
        self.lua.execute('''
            guest.inventory[1]='coal-bucket'; guest.inventory[2]='coal-chunk'
            local args={source={kind='inventory',index=1},sourceItem={name='coal-bucket',id=false}}
            states.companion.x=594; states.companion.y=520
            local req=request('companion','train.fuel',args); guest.inventory[1]='coal-chunk'
            assert(run('companion',req).reason=='stale_item' and data.resources.coal==10)
            args.sourceItem.name='coal-chunk'; req=request('companion','train.fuel',args)
            assert(run('companion',req).ok and not guest.inventory[1] and guest.inventory[2]=='coal-chunk' and data.resources.coal==11)
            local quote=request('companion','train.engineUpgrade',{quotedPrice=15,quotedLevel=1})
            assert(run('host',request('host','train.engineUpgrade',{})).ok)
            assert(run('companion',quote).reason=='quote_changed' and data.engineLevel==1)
            for _,flag in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                states.companion[flag]=true
                assert(not authority:prepareRequest('companion','train.fuel',args))
                assert(not authority:prepareRequest('companion','train.upgrade',{carId='storage'}))
                states.companion[flag]=nil
            end
        ''')

    def test_wire_codec_bounds_and_data_only_roundtrip(self):
        self.lua.execute('''
            local Codec=require('game.net.codec')
            local encoded=assert(Codec.encode(transfer('companion')))
            local decoded=assert(Codec.decode(encoded))
            assert(decoded.args.containerId==chest.entityId and run('companion',decoded).ok)
            assert(not Codec.encode({[2]='sparse'}))
            assert(not Codec.encode({value=0/0}))
            assert(not Codec.encode({value=string.rep('x',1025)}))
            assert(not Codec.decode('return os.execute("anything")'))
            local cyclic={}; cyclic.value=cyclic; assert(not Codec.encode(cyclic))
            assert(not Codec.decode(encoded..'trailing'))
        ''')


if __name__ == '__main__':
    unittest.main()
