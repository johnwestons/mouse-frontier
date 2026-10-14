"""Application LAN lifecycle with real authority/replica and isolated storage."""
from pathlib import Path
import hashlib
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class LocalPlayTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.globals().pythonHash = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}; clock=0; failSave=false; writes=0; joins=0
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            GameSession=require('game.game_session'); Runtime=require('game.runtime_state')
            Authority=require('game.coop_authority'); LocalPlay=require('game.coop_local_play'); Net=require('game.net.session')
            Lab=require('tools.tests.lua.coop_network_harness'); lab=assert(Lab.new())
            function hash(value) return pythonHash(value) end
            function runtime(state,data,slot)
                local session=GameSession.new()
                local r=Runtime.new({session=session,transition=function(screen) session:setScreen(screen) end})
                r.saveData=data; r.player={x=200,y=250}; r.scene='train'; r.selectedSlot=slot; r.state=state
                return r,session
            end
            data=F.campaign(2,{scene='train'}); hostRuntime,hostSession=runtime('game',data,1)
            guestData=F.campaign(9,{scene='train'}); guestRuntime,guestSession=runtime('slots',guestData,2)
            service=Authority.new({campaign=data,sessionId='local-play-test',checkpoint=function(value)
                writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true
            end})
            hostFs,hostFiles=F.filesystem(); guestFs,guestFiles=F.filesystem()
            local sequence=0
            function token(bytes) sequence=sequence+1; return string.format('%0'..(bytes*2)..'x',sequence) end
            local function context(r,s,fs)
                return {runtime=r,session=s,filesystem=fs,clock=function() return clock end,hash=hash,token=token,autoReconnect=false,
                    commands={authority=function() return service end,checkpointStatus=function() return service:checkpointStatus() end},
                    compatibility=function() return {build=string.rep('e',64),schema=38} end,
                    characters=function() return {'cook-mouse.png','scout-frog.png'} end,
                    catalog={characterTrait=function() return {maxHealth=2,name='cook'} end},
                    placeCompanion=function(c) c.players.companion.playerX=240; c.players.companion.playerY=250; return true end,
                    network={host=function(options) options.transport=assert(lab.factory.createHost({})); return Net.host(options) end,
                        join=function(address,options) joins=joins+1; options.transport=assert(lab.factory.createClient(address,{})); return Net.join(address,options) end},
                    beforeJoin=function() return true end}
            end
            hostContext=context(hostRuntime,hostSession,hostFs); guestContext=context(guestRuntime,guestSession,guestFs)
            host=LocalPlay.new(hostContext); guest=LocalPlay.new(guestContext); guest.address='friend-pc:22124'
            function step(count) for _=1,count or 1 do clock=clock+.05; host:update(); guest:update(); lab:advanceSteps(1) end end
            function ready()
                assert(host:host()); assert(guest:join()); step(4)
                assert(host:pending() and host.menuOpen); assert(host:approve()); step(12)
                assert(guest.phase=='connected',guest.error or guest.phase)
            end
        ''')

    def tearDown(self):
        self.lua.execute("host:stop(); guest:stop(); assert(lab:dispose() and lab:isQuiescent())")

    def enable_cars(self):
        self.lua.execute('''
            local Commands=require('game.coop_inventory_runtime')
            data.trainCars={'living-car','medical','storage'}
            commands=Commands.new({runtime=hostRuntime,session=hostSession,catalog=require('game.catalog'),
                clock=function() return clock end,
                checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=Schema.copy(value); return true end,
                applyParty=function(r) hostSession:acceptPartyState(r) end,
                scene={carArrival=function(_,_,index,forward) return forward and 110+index or 850-index,420 end},
                applyCar=function(r) hostRuntime.player.x=r.x; hostRuntime.player.y=r.y; hostCarApplied=(hostCarApplied or 0)+1 end})
            commands.setRemoteActorState(function()
                return {screen=hostRuntime.state,scene=hostRuntime.scene,traveling=traveling,encounterActive=encounter,
                    activityBlocked=activityBlocked}
            end)
            hostContext.commands=commands; service=assert(commands.authority())
            hostContext.movement={hostActor=function() return hostRuntime.player end,
                allowed=function() return not commands.carBusy('companion') end,
                move=function(_,_,_,_,x,y) return x,y end}
            function change(car,overrides)
                local request={sessionId=service.sessionId,requestId=guest.network.nextRequestId,sceneEpoch=data.coop.sceneEpoch,
                    command='player.car',args={car=car},expected={['player:companion']=data.coop.revisions['player:companion'] or 0}}
                for key,value in pairs(overrides or {}) do request[key]=value end
                local id=assert(guest.network:submitCommand(request.command,request.args,request.sceneEpoch,request.expected))
                step(3); return guest.network.lastCommandResult,id
            end
            function motionReady()
                assert(guest.network:sceneReady(data.coop.sceneEpoch,host.motion.motionId)); step(2)
            end
        ''')

    def test_guest_car_command_is_peer_bound_durable_and_personal(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); local before=Schema.copy(data); local x=hostRuntime.player.x
            local reply=change(2); assert(reply.ok and reply.durable and not reply.result)
            assert(data.players.companion.activeCar==2 and saved.players.companion.activeCar==2)
            assert(data.players.companion.playerX==112 and data.players.companion.playerY==420)
            assert(data.players.host.activeCar==1 and hostRuntime.player.x==x and not hostCarApplied)
            assert(data.coop.sceneEpoch==before.coop.sceneEpoch and data.location==before.location and data.scene==before.scene)
            assert(data.resources.coal==before.resources.coal and data.coop.revisions.party==before.coop.revisions.party)
            assert(not host.motion.readyEpoch and commands.carBusy('companion'))
            motionReady(); assert(not host.motion:allowed()); step(16); assert(host.motion:allowed())
            assert(guest.replica.data.players.companion.activeCar==2)
            local own=commands.submit('player.car',{car=3})
            assert(own.ok and own.durable and hostCarApplied==1 and data.players.host.activeCar==3)
            assert(data.players.companion.activeCar==2 and hostRuntime.player.x==113)
        ''')

    def test_replayed_party_receipt_does_not_repeat_presentation_or_teleport_host(self):
        self.enable_cars()
        self.lua.execute('''
            data.events['2']={id='resolved'}
            local accepts=0
            local accept=hostSession.acceptPartyState
            hostSession.acceptPartyState=function(self,result) accepts=accepts+1; return accept(self,result) end
            local reply=commands.submit('scene.leaveTrain',{})
            assert(reply.ok and reply.durable and accepts==1 and hostRuntime.scene=='stop')
            local actualSubmit=service.submitLocal
            service.submitLocal=function() return reply end -- delivery of the same persisted receipt
            hostRuntime.player.x=350
            assert(commands.submit('scene.leaveTrain',{}).durable)
            assert(accepts==1 and hostRuntime.player.x==350)
            service.submitLocal=actualSubmit
        ''')

    def enable_items(self):
        self.enable_cars()
        self.lua.execute('''
            Catalog=require('game.catalog'); Players=require('game.coop_players'); Contract=require('game.coop_item_contract')
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(campaign)
                assert(place(campaign)); local actor=campaign.players.companion
                actor.inventory[1]='field-bandage-roll'; actor.inventory[2]='food-ration'; actor.health=10; return true
            end
            commands.setRemoteActorState(function()
                return {screen=hostRuntime.state,scene=hostRuntime.scene,x=testRemoteX or 240,y=250,traveling=traveling,
                    encounterActive=encounter,activityBlocked=activityBlocked}
            end)
            function itemArgs(ref,target)
                local actor=Players.forActor(guest.replica.data,'companion')
                local args={source=ref,sourceItem=Contract.selection(actor,nil,ref)}
                if target then args.target=target; args.targetItem=Contract.selection(actor,nil,target) end
                return args
            end
            function act(name,args,overrides)
                local epoch=data.coop.sceneEpoch
                local expected=Contract.expected(guest.replica.data,'companion',name,args,Catalog)
                if overrides then epoch=overrides.epoch or epoch; expected=overrides.expected or expected end
                local id=assert(guest.network:submitCommand(name,args,epoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
        ''')

    def test_live_guest_equipment_consumption_and_durable_reconnect_are_personal(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local hostItem=data.players.host.itemSlots.equipment[1].id
            local item=data.players.companion.itemSlots.equipment[1].id; local hostHealth=data.players.host.health
            local reply=act('inventory.swap',itemArgs({kind='equipment',index=1},{kind='inventory',index=3}))
            assert(reply.ok and reply.durable and reply.command=='inventory.swap' and reply.details.moved and not reply.result)
            assert(saved.players.companion.itemSlots.inventory[3].id==item and not data.players.companion.equipment[1])
            assert(data.players.host.itemSlots.equipment[1].id==hostItem)
            reply=act('inventory.consume',itemArgs({kind='inventory',index=1}))
            assert(reply.ok and reply.durable and reply.details.item=='field-bandage-roll' and reply.details.gained.health==5)
            assert(saved.players.companion.health==15 and data.players.host.health==hostHealth)
            assert(not saved.players.companion.inventory[1] and data.resources.food==10)
            local id; reply,id=act('inventory.consume',itemArgs({kind='inventory',index=2}))
            assert(reply.ok and reply.details.gained.food==3 and saved.resources.food==13)
            local revision=data.coop.revision; guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.phase=='connected' and guest.network.nextRequestId==id+1 and data.coop.revision==revision)
            assert(guest.replica.data.players.companion.itemSlots.inventory[3].id==item)
            assert(guest.replica.data.players.companion.health==15 and guest.replica.data.resources.food==13)
        ''')

    def test_live_guest_save_retry_and_duplicate_consume_have_one_effect(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); failSave=true; lab:duplicateNext('client_to_host',1,1,true)
            local reply,id=act('inventory.consume',itemArgs({kind='inventory',index=1}))
            assert(reply.ok and reply.savePending and reply.details.gained.health==5 and data.players.companion.health==15)
            local revision=data.coop.revision; step(20)
            assert(guest.network.pendingCommand and data.coop.revision==revision and data.players.companion.health==15)
            failSave=false; assert(commands.retryCheckpoint()); step(20)
            assert(not guest.network.pendingCommand and guest.network.lastCommandResult.durable and saved.players.companion.health==15)
            local request=assert(require('game.net.codec').decode(service.requests.companion.cache[id].fingerprint))
            local replay=commands.remote(host.generation,request)
            assert(replay.ok and replay.durable and replay.result.gained.health==5)
            assert(data.players.companion.health==15 and data.coop.revision==revision)
        ''')

    def test_live_drop_pickup_retains_instance_and_checks_host_position_and_car(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local item=data.players.companion.itemSlots.equipment[1].id
            local reply=act('loot.drop',itemArgs({kind='equipment',index=1}))
            assert(reply.ok and reply.durable and reply.details.item=='frontier-short-sword')
            local id=reply.details.entityId; local drop=data.droppedItems[#data.droppedItems]
            assert(drop.entityId==id and drop.itemInstance.id==item and drop.carIndex==1 and drop.x==host.motion.actor.x+35)
            local before=data.coop.revision
            testRemoteX=700; reply=act('loot.pickup',{entityId=id}); assert(not reply.ok and reply.reason=='out_of_reach')
            testRemoteX=240; data.players.companion.activeCar=2
            reply=act('loot.pickup',{entityId=id}); assert(not reply.ok and reply.reason=='out_of_reach')
            data.players.companion.activeCar=1; assert(data.coop.revision==before)
            reply=act('loot.pickup',{entityId=id}); assert(reply.ok and reply.details.item=='frontier-short-sword')
            assert(saved.players.companion.itemSlots.inventory[3].id==item and not data.players.companion.equipment[1])
            assert(not require('game.coop_entities').find(data,id))
        ''')

    def test_live_item_selection_guards_stale_revisions_forged_slots_and_story_rights(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local revision=data.coop.revision; local ref={kind='equipment',index=1}
            local args=itemArgs(ref,{kind='inventory',index=3}); args.sourceItem.id=data.players.host.itemSlots.equipment[1].id
            local reply=act('inventory.swap',args); assert(not reply.ok and reply.reason=='stale_item')
            args=itemArgs(ref,{kind='inventory',index=3}); args.targetItem={name='food-ration',id=false}
            reply=act('inventory.swap',args); assert(not reply.ok and reply.reason=='stale_item')
            args=itemArgs(ref); args.sourceItem=nil
            reply=act('loot.drop',args); assert(not reply.ok and reply.reason=='item_selection_required')
            args=itemArgs(ref); args.source.index=999
            reply=act('loot.drop',args); assert(not reply.ok and reply.reason=='invalid_slot')
            ref={kind='equipment',index=1}
            args=itemArgs(ref); args.containerId='fake'
            reply=act('loot.drop',args); assert(not reply.ok and reply.reason=='container_unavailable')
            reply=act('loot.drop',itemArgs(ref),{expected={['player:companion']=999}})
            assert(not reply.ok and reply.reason=='stale_revision')
            reply=act('scene.leaveTrain',{}); assert(not reply.ok and reply.reason=='host_only')
            assert(data.coop.revision==revision and data.scene=='train' and data.players.companion.equipment[1])
        ''')

    def test_live_guest_items_are_blocked_during_host_progression_or_encounters(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local revision=data.coop.revision
            for _,flag in ipairs({'traveling','encounter','activityBlocked'}) do
                _G[flag]=true
                local reply=act('inventory.consume',itemArgs({kind='inventory',index=1}))
                assert(not reply.ok and reply.reason=='unavailable'); _G[flag]=false
            end
            local reply=act('loot.drop',itemArgs({kind='equipment',index=1}),{epoch=data.coop.sceneEpoch+1})
            assert(not reply.ok and reply.reason=='stale_scene')
            assert(data.coop.revision==revision and data.players.companion.health==10 and data.players.companion.inventory[1])
        ''')

    def enable_storage(self, mailbox=False):
        self.enable_items()
        self.lua.globals().mailbox = mailbox
        self.lua.execute('''
            Entities=require('game.coop_entities'); Items=require('game.item_instances')
            chest={name=mailbox and 'mailbox-reward' or 'travel-chest',mailbox=mailbox,mailUnread=mailbox,permanent=mailbox,
                scene='train',carIndex=1,x=255,y=250,storage={[1]='frontier-short-sword',[2]='food-ration',[4]='rocks'}}
            data.droppedItems={chest}; assert(Entities.ensure(data)); assert(Items.ensure(data)); chestId=chest.entityId
            function storageArgs(ref,target)
                local actor=Players.forActor(guest.replica.data,'companion'); local c=Entities.find(guest.replica.data,chestId)
                local args={source=ref,sourceItem=Contract.selection(actor,c,ref),containerId=chestId}
                if target then args.target=target; args.targetItem=Contract.selection(actor,c,target) end
                return args
            end
        ''')

    def test_live_storage_roundtrip_consumption_ammo_and_reconnect_keep_ownership(self):
        self.enable_storage()
        self.lua.execute('''
            ready(); motionReady(); local gear=chest.storageInstances[1].id
            local personal=data.players.companion.itemSlots.equipment[2].id
            local hostGear=data.players.host.itemSlots.equipment[1].id
            local reply=act('storage.transfer',storageArgs({kind='chest',index=1}))
            assert(reply.ok and reply.durable and reply.details.moved and saved.players.companion.itemSlots.inventory[3].id==gear)
            reply=act('storage.transfer',storageArgs({kind='inventory',index=3}))
            assert(reply.ok and chest.storageInstances[1].id==gear and not data.players.companion.inventory[3])
            reply=act('storage.transfer',storageArgs({kind='equipment',index=2}))
            assert(reply.ok and chest.storageInstances[3].id==personal and not data.players.companion.equipment[2])
            reply=act('inventory.consume',storageArgs({kind='chest',index=2}))
            assert(reply.ok and reply.details.gained.food==3 and saved.resources.food==13 and not chest.storage[2])
            local before=data.players.companion.ammo.rocks
            reply=act('mailbox.collect',storageArgs({kind='chest',index=4}))
            assert(reply.ok and reply.details.amount==Catalog.ammoPickupAmounts.rocks and not chest.storage[4])
            assert(saved.players.companion.ammo.rocks==before+reply.details.amount and data.players.host.itemSlots.equipment[1].id==hostGear)
            guest:stop(); host:update(); assert(guest:join()); step(18)
            local shown=Entities.find(guest.replica.data,chestId)
            assert(shown.storageInstances[1].id==gear and shown.storageInstances[3].id==personal and not shown.storage[2])
            assert(guest.replica.data.scene=='train' and guest.replica.data.resources.food==13)
        ''')

    def test_live_shared_storage_rejects_host_contention_and_unknown_container_claims(self):
        self.enable_storage()
        self.lua.execute('''
            ready(); motionReady(); local args=storageArgs({kind='chest',index=2})
            local expected=Contract.expected(guest.replica.data,'companion','storage.transfer',args,Catalog)
            local taken=commands.submit('storage.transfer',{source={kind='chest',index=1},containerId=chestId})
            assert(taken.ok); local revision=data.coop.revision
            local reply=act('storage.transfer',args,{expected=expected})
            assert(not reply.ok and reply.reason=='stale_revision' and chest.storage[2]=='food-ration')
            args=storageArgs({kind='chest',index=2}); assert(commands.submit('storage.transfer',{source={kind='chest',index=2},containerId=chestId}).ok)
            reply=act('storage.transfer',args); assert(not reply.ok and reply.reason=='stale_item')
            assert(data.coop.revision==revision+1 and data.players.companion.inventory[3]==nil)
            args=storageArgs({kind='chest',index=4}); args.sourceItem=nil
            reply=act('mailbox.collect',args); assert(not reply.ok and reply.reason=='item_selection_required' and chest.storage[4]=='rocks')
            args=storageArgs({kind='chest',index=4}); args.containerId='unknown'
            reply=act('storage.transfer',args); assert(not reply.ok and reply.reason=='container_unavailable')
        ''')

    def test_live_mailbox_refuses_deposits_and_swaps_but_collects_ammo_with_full_backpack(self):
        self.enable_storage(mailbox=True)
        self.lua.execute('''
            ready(); motionReady(); local revision=data.coop.revision
            local reply=act('inventory.swap',storageArgs({kind='equipment',index=1},{kind='chest',index=3}))
            assert(not reply.ok and reply.reason=='cannot_transfer' and not chest.storage[3])
            assert(chest.mailUnread==true)
            reply=act('inventory.swap',storageArgs({kind='chest',index=1},{kind='inventory',index=1}))
            assert(not reply.ok and reply.reason=='cannot_transfer' and chest.storage[1]=='frontier-short-sword')
            for index=3,6 do data.players.companion.inventory[index]='food-ration' end
            step(22); reply=act('storage.transfer',storageArgs({kind='chest',index=1}))
            assert(not reply.ok and chest.storage[1]=='frontier-short-sword' and data.coop.revision==revision)
            local ammo=data.players.companion.ammo.rocks
            reply=act('mailbox.collect',storageArgs({kind='chest',index=4}))
            assert(reply.ok and data.players.companion.ammo.rocks==ammo+Catalog.ammoPickupAmounts.rocks)
            assert(not chest.storage[4] and data.scene=='train' and data.players.companion.inventory[6]=='food-ration')
            assert(chest.mailUnread==false and Entities.find(saved,chestId).mailUnread==false)
            reply=act('loot.pickup',{entityId=chestId}); assert(not reply.ok and reply.reason=='permanent')
        ''')

    def test_live_storage_retries_once_and_revalidates_car_reach_and_party_epoch(self):
        self.enable_storage()
        self.lua.execute('''
            ready(); motionReady(); local gear=chest.storageInstances[1].id
            failSave=true; local reply,id=act('storage.transfer',storageArgs({kind='chest',index=1}))
            assert(reply.ok and reply.savePending); local revision=data.coop.revision; step(22)
            assert(data.coop.revision==revision and data.players.companion.itemSlots.inventory[3].id==gear)
            failSave=false; assert(commands.retryCheckpoint()); step(20)
            assert(guest.network.lastCommandResult.durable and saved.players.companion.itemSlots.inventory[3].id==gear)
            testRemoteX=700; reply=act('storage.transfer',storageArgs({kind='chest',index=2}))
            assert(not reply.ok and reply.reason=='container_unavailable')
            testRemoteX=240; data.players.companion.activeCar=2
            reply=act('inventory.consume',storageArgs({kind='chest',index=2}))
            assert(not reply.ok and reply.reason=='container_unavailable')
            data.players.companion.activeCar=1
            reply=act('storage.transfer',storageArgs({kind='chest',index=2}),{epoch=data.coop.sceneEpoch+1})
            assert(not reply.ok and reply.reason=='stale_scene' and data.coop.revision==revision and chest.storage[2]=='food-ration')
        ''')

    def enable_train(self):
        self.enable_items()
        self.lua.execute('''
            TrainAccess=require('game.coop_train_access'); data.location=50; data.scrap=200
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(campaign)
                assert(place(campaign)); local own=campaign.players.companion
                own.inventory[2]='coal-bucket'; own.inventory[3]='coal-chunk'; return true
            end
            commands.setRemoteActorState(function()
                return {screen=hostRuntime.state,scene=hostRuntime.scene,x=testRemoteX or 594,y=520,
                    traveling=traveling,encounterActive=encounter,activityBlocked=activityBlocked}
            end)
            function trainAct(name,args,expected)
                expected=expected or TrainAccess.expected(guest.replica.data,name,'companion')
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
            function fuelArgs()
                local own=Players.forActor(guest.replica.data,'companion'); local ref,item=TrainAccess.coal(own)
                return {source=ref,sourceItem=item}
            end
        ''')

    def enable_objects(self):
        self.enable_train()
        self.lua.execute('''
            ObjectAccess=require('game.coop_object_access'); Entities=require('game.coop_entities'); Items=require('game.item_instances')
            data.droppedItems={{name='frontier-short-sword',scene='train',carIndex=1,x=594,y=520,scale=1},
                {name='boombox-radio',scene='train',carIndex=1,x=594,y=520,permanent=true}}
            assert(Items.ensure(data)); assert(Entities.ensure(data)); object=data.droppedItems[1]; radio=data.droppedItems[2]
            function objectAct(name,args,id,overrides)
                local expected=ObjectAccess.expected(guest.replica.data,name,'companion',id or object.entityId)
                for scope,value in pairs(overrides or {}) do expected[scope]=value end
                local request=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,request
            end
        ''')

    def test_live_decoration_lease_peer_binding_durable_placement_and_collect_retry(self):
        self.enable_objects()
        self.lua.execute('''
            ready(); motionReady(); local hostItem=data.players.host.itemSlots.equipment[1].id; local epoch=data.coop.sceneEpoch
            local id=object.itemInstance.id; object.itemInstance.durability=23
            local reply=objectAct('decoration.acquire',{entityId=object.entityId})
            assert(reply.ok and not reply.durable and reply.details.entityId==object.entityId)
            local lease=reply.details.leaseId; assert(service:submitLocal('decoration.acquire',{entityId=object.entityId}).reason=='activity_busy')
            failSave=true; reply,requestId=objectAct('decoration.place',{leaseId=lease,values={x=900,hue=.4}})
            assert(reply.savePending and object.x==900 and object.hue==.4, tostring(reply.reason)..' / '..tostring(reply.savePending)..' / '..tostring(object.x)..' / '..tostring(object.entityId)..' / '..tostring(data.droppedItems[1].x))
            failSave=false; assert(commands.retryCheckpoint()); step(16); reply=guest.network.lastCommandResult
            assert(reply.durable and saved.droppedItems[1].x==900 and object.itemInstance.id==id)
            reply=objectAct('decoration.place',{leaseId=lease,values={}}); assert(reply.ok and not reply.durable)
            failSave=true; reply,requestId=objectAct('decoration.collect',{leaseId=lease})
            assert(reply.savePending and not Entities.find(data,object.entityId))
            local own=data.players.companion; local slot=reply.details.slot
            assert(own.itemSlots.inventory[slot].id==id and own.itemSlots.inventory[slot].durability==23)
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(data.players.host.itemSlots.equipment[1].id==hostItem and data.coop.sceneEpoch==epoch)
            guest:stop(); host:update(); assert(guest:join()); step(30); assert(guest.phase=='connected')
            assert(guest.replica.data.players.companion.itemSlots.inventory[slot].id==id and #guest.replica.data.droppedItems==1)
        ''')

    def test_live_radio_selection_revisions_failed_save_and_forged_arguments(self):
        self.enable_objects()
        self.lua.execute('''
            ready(); motionReady(); local original=data.audio.station
            local reply=objectAct('radio.station',{entityId=radio.entityId,station='vibes',musicVolume=1},radio.entityId)
            assert(reply.reason=='invalid_args' and data.audio.station==original)
            local stale=ObjectAccess.expected(guest.replica.data,'radio.station','companion',radio.entityId)
            assert(service:submitLocal('radio.station',{entityId=radio.entityId,station='8bit'}).reason=='radio_unavailable') -- Host is away.
            data.coop.revisions.radio=(data.coop.revisions.radio or 0)+1
            reply=objectAct('radio.station',{entityId=radio.entityId,station='vibes'},radio.entityId,stale)
            assert(reply.reason=='stale_revision' and data.audio.station==original)
            step(12); failSave=true; reply=objectAct('radio.station',{entityId=radio.entityId,station='vibes',rainEnabled=false},radio.entityId)
            assert(reply.ok and reply.savePending and reply.details.station=='vibes' and reply.details.rainEnabled==false)
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(saved.audio.station=='vibes' and saved.audio.rainEnabled==false)
            testRemoteX=900; reply=objectAct('radio.station',{entityId=radio.entityId,station='chill'},radio.entityId)
            assert(reply.reason=='radio_unavailable' and data.audio.station=='vibes')
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.audio.station=='vibes' and guest.replica.data.audio.rainEnabled==false)
        ''')

    def test_live_expired_forged_and_disconnected_leases_cannot_apply(self):
        self.enable_objects()
        self.lua.execute('''
            ready(); motionReady()
            local reply=objectAct('decoration.acquire',{entityId=object.entityId}); local lease=reply.details.leaseId
            reply=objectAct('decoration.place',{leaseId='l999',values={x=500}}); assert(reply.reason=='lease_expired')
            assert(service:submitLocal('decoration.place',{leaseId=lease,values={x=500}}).reason=='lease_owner')
            step(620); hostRuntime.animationClock=clock; service:sweepActivities()
            reply=objectAct('decoration.place',{leaseId=lease,values={x=500}}); assert(reply.reason=='lease_expired' and object.x==594,tostring(reply.reason)..' / '..tostring(object.x)..' / '..tostring(data.droppedItems[1].x))
            reply=objectAct('decoration.acquire',{entityId=object.entityId}); assert(reply.ok)
            guest:stop(); host:update(); assert(not next(service.activityState.resources))
            assert(service:submitLocal('decoration.acquire',{entityId=object.entityId}).ok)
        ''')

    def test_live_selected_fuel_save_retry_reconnect_and_car_reach(self):
        self.enable_train()
        self.lua.execute('''
            ready(); motionReady(); local hostItem=data.players.host.itemSlots.equipment[1].id
            failSave=true; local reply,id=trainAct('train.fuel',fuelArgs())
            assert(reply.ok and reply.savePending and reply.details.gained==3 and data.resources.coal==13)
            local revision=data.coop.revision; step(22); assert(data.coop.revision==revision and guest.network.pendingCommand)
            failSave=false; assert(commands.retryCheckpoint()); step(20)
            assert(guest.network.lastCommandResult.durable and saved.resources.coal==13 and not saved.players.companion.inventory[2])
            assert(saved.players.companion.inventory[3]=='coal-chunk' and saved.players.host.itemSlots.equipment[1].id==hostItem)
            data.players.companion.activeCar=2; reply=trainAct('train.fuel',fuelArgs())
            assert(reply.reason=='out_of_reach' and data.resources.coal==13)
            data.players.companion.activeCar=1; testRemoteX=900; reply=trainAct('train.fuel',fuelArgs())
            assert(reply.reason=='out_of_reach' and data.resources.coal==13)
            testRemoteX=594; guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.replica.data.resources.coal==13 and guest.replica.data.players.companion.inventory[3]=='coal-chunk')
            local replay=require('game.net.codec').decode(service.requests.companion.cache[id].fingerprint)
            assert(commands.remote(host.generation,replay).ok and data.resources.coal==13 and data.coop.revision==revision)
        ''')

    def enable_train_activities(self):
        self.enable_train()
        self.lua.execute('''
            ActivityAccess=require('game.coop_activity_access'); Items=require('game.item_instances'); P=require('game.net.protocol')
            data.resources.oil=20; data.maintenance={condition=40,lastServicedStop=0,totalServices=0,totalWear=0}
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(campaign)
                assert(place(campaign)); local own=Players.forActor(campaign,'companion')
                local gear=Items.get(own,nil,{kind='equipment',index=1}); gear.durability=20
                Items.write(own,nil,{kind='inventory',index=2},Catalog.weaponRepairParts[gear.name]); return true
            end
            function activityAct(name,args,kind)
                local expected=ActivityAccess.expected(guest.replica.data,'companion',name,kind)
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
        ''')

    def test_live_maintenance_host_contention_checkpoint_retry_cleanup_and_rejoin(self):
        self.enable_train_activities()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch
            local reply=activityAct('maintenance.acquire',{}); assert(reply.ok and not reply.durable and not reply.details.completed)
            local lease=reply.details.leaseId; assert(service:submitLocal('maintenance.acquire',{}).reason=='activity_busy')
            assert(act('inventory.consume',itemArgs({kind='inventory',index=1})).reason=='unavailable')
            for _,target in ipairs({1,1,2,3,3}) do
                reply=activityAct('maintenance.step',{leaseId=lease,target=target}); assert(reply.ok and reply.details.success)
            end
            assert(data.resources.oil==20 and data.maintenance.condition==40)
            failSave=true; reply=activityAct('maintenance.complete',{leaseId=lease})
            assert(reply.ok and reply.savePending and reply.details.success and data.resources.oil==15 and data.maintenance.totalServices==1)
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(commands.remote(host.generation,exact).ok and data.resources.oil==15 and saved.maintenance.condition==80)
            assert(saved.maintenance.totalServices==1 and not next(service.activityState.resources) and data.coop.sceneEpoch==epoch)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.maintenance.condition==80 and guest.replica.data.resources.oil==15)
            reply=activityAct('maintenance.acquire',{}); assert(reply.details.completed)
            reply=activityAct('activity.release',{leaseId=reply.details.leaseId},'maintenance'); assert(reply.ok)
        ''')

    def enable_first_aid(self):
        self.enable_items()
        self.lua.execute('''
            AidAccess=require('game.coop_aid_access'); Help=require('game.stop_help_progression')
            Quests=require('game.help_quest_session'); P=require('game.net.protocol')
            data.scene='stop'; data.currentNPC='medic.png'; hostRuntime.scene='stop'
            hostRuntime.player.x=140; hostRuntime.player.y=100
            hostRuntime.npcActor={x=100,y=100}
            require('game.item_instances').write(Players.forActor(data,'host'),nil,{kind='inventory',index=1},'field-bandage-roll')
            layout={}; data.stopLayouts[tostring(data.location)]=layout
            aidRequest=Help.ensureRequest(layout,'medic.png','aid',data.location,data)
            aidRequest.accepted=true; Quests.accept(data,aidRequest.sessionId)
            commands.setRemoteActorState(function()
                return {screen='game',scene='stop',x=testRemoteX or 140,y=100,npc={id='medic.png',x=100,y=100},
                    traveling=traveling,encounterActive=encounter,activityBlocked=activityBlocked}
            end)
            function aid(name,args)
                args=args or {}
                if name=='firstAid.acquire' then
                    args.targetId=layout.entityId; args.npc='medic.png'; args.source={kind='inventory',index=1}
                    args.selected=Contract.selection(Players.forActor(guest.replica.data,'companion'),nil,args.source)
                end
                local expected=AidAccess.expected(Players.forActor(guest.replica.data,'companion'),'companion',name,aidRequest.sessionId,layout.entityId)
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
            function aidChoose(lease,first)
                for i=first or 1,6 do
                    local reply=aid('firstAid.step',{leaseId=lease,action='choose',index=i})
                    assert(reply.ok and not reply.details.session and not reply.details.progress,reply.reason)
                end
            end
        ''')

    def test_live_first_aid_partial_checkpoint_failure_pause_and_durable_rejoin(self):
        self.enable_first_aid()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch
            local reply=aid('firstAid.acquire'); assert(reply.ok and not reply.durable); local lease=reply.details.leaseId
            assert(service:submitLocal('firstAid.acquire',{targetId=layout.entityId,npc='medic.png'}).reason=='activity_busy')
            aid('firstAid.step',{leaseId=lease,action='choose',index=1})
            aid('firstAid.step',{leaseId=lease,action='choose',index=2})
            aid('firstAid.step',{leaseId=lease,action='press',x=410,y=370})
            aid('firstAid.step',{leaseId=lease,action='move',x=500,y=370})
            failSave=true; reply=aid('firstAid.step',{leaseId=lease,action='pause'})
            assert(reply.ok and reply.savePending and reply.details.outcome=='cancelled')
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16)
            assert(guest.network.lastCommandResult.durable and commands.remote(host.generation,exact).ok)
            local q=saved.helpQuestSessions[aidRequest.sessionId]
            assert(q.progress.phase==3 and q.progress.rubDistance==90 and q.paused and not next(service.activityState.resources))
            assert(saved.players.companion.inventory[1]=='field-bandage-roll' and data.goodwill==0)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.helpQuestSessions[aidRequest.sessionId].progress.rubDistance==90)
            reply=aid('firstAid.acquire'); assert(reply.details.phase==3 and not reply.details.dragging)
            aidChoose(reply.details.leaseId,3); reply=aid('firstAid.complete',{leaseId=reply.details.leaseId})
            assert(reply.ok and reply.durable and saved.goodwill==3 and saved.helpQuestSessions[aidRequest.sessionId].rewardClaimed)
            assert(data.coop.sceneEpoch==epoch and data.scene=='stop')
        ''')

    def test_live_first_aid_completion_retry_consumes_guest_supply_and_rewards_once(self):
        self.enable_first_aid()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local hostHealth=data.health
            local hostId=data.players.host.itemSlots.equipment[1].id; local hostX=hostRuntime.player.x
            local reply=aid('firstAid.acquire'); local lease=reply.details.leaseId; aidChoose(lease)
            failSave=true; reply=aid('firstAid.complete',{leaseId=lease})
            assert(reply.ok and reply.savePending and reply.details.completed and data.goodwill==3)
            assert(not data.players.companion.inventory[1] and data.inventory[1]=='field-bandage-roll')
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            local revision=data.coop.revision; failSave=false; assert(commands.retryCheckpoint()); step(16)
            assert(guest.network.lastCommandResult.durable and commands.remote(host.generation,exact).ok)
            assert(data.goodwill==3 and #data.helpHistory==1 and data.coop.revision==revision)
            assert(saved.helpQuestSessions[aidRequest.sessionId].rewardClaimed and not saved.players.companion.inventory[1])
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.goodwill==3 and aid('firstAid.acquire').reason=='quest_unavailable')
            assert(data.health==hostHealth and data.players.host.itemSlots.equipment[1].id==hostId and hostRuntime.player.x==hostX)
            assert(data.coop.sceneEpoch==epoch and data.location==2 and data.scene=='stop')
        ''')

    def enable_quest_assistance(self):
        self.enable_first_aid()
        self.lua.execute('''
            QuestAccess=require('game.coop_quest_access')
            layout.helpRequests={}; itemRequest=Help.ensureRequest(layout,'medic.png','item',data.location,data)
            itemRequest.item='field-bandage-roll'; itemRequest.accepted=true; Quests.accept(data,itemRequest.sessionId)
            data.mailQuests={{origin=1,destination=data.location,recipient='medic.png',complete=false}}
            data.supplyQuests={{origin=1,destination=data.location,cargoKind='medicine',complete=false}}
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(c)
                assert(place(c)); local a=require('game.coop_players').forActor(c,'companion')
                for i=1,4 do require('game.item_instances').write(a,nil,{kind='inventory',index=i},'field-bandage-roll') end
                return true
            end
            function questAct(name,quest,slot)
                local own=Players.forActor(guest.replica.data,'companion')
                local args={targetId=layout.entityId,npc='medic.png',questId=quest and quest.entityId}
                local q=quest or guest.replica.data.helpQuestSessions[itemRequest.sessionId]
                if name=='quest.help' then args.source={kind='inventory',index=slot or 2}; args.selected=Contract.selection(own,nil,args.source) end
                local expected=QuestAccess.expected(own,'companion',name,q,layout.entityId,Catalog)
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
        ''')

    def test_live_quest_help_exact_supply_checkpoint_retry_and_rejoin(self):
        self.enable_quest_assistance()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local own=data.players.companion
            failSave=true; local r,id=questAct('quest.help'); assert(r.ok and r.savePending and r.details.completed)
            assert(own.inventory[1]=='field-bandage-roll' and own.inventory[2]==nil and data.inventory[1]=='field-bandage-roll')
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16)
            assert(guest.network.lastCommandResult.durable and commands.remote(host.generation,exact).ok and data.goodwill==2)
            assert(saved.helpQuestSessions[itemRequest.sessionId].rewardClaimed)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.goodwill==2 and not guest.replica.data.players.companion.inventory[2])
            assert(questAct('quest.help').reason=='quest_unavailable' and data.coop.sceneEpoch==epoch)
        ''')

    def test_live_delivery_rewards_save_retry_rng_and_party_xp_are_once_only(self):
        self.enable_quest_assistance()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local x=hostRuntime.player.x
            local hostId=data.players.host.itemSlots.equipment[1].id
            failSave=true; local r=questAct('quest.deliver',data.mailQuests[1]); assert(r.ok and r.savePending and r.details.completed)
            local d=r.details; assert(d.recipients.host==d.xp and d.recipients.companion==d.xp and not d.reward)
            local seed=data.coop.randomState; local revision=data.coop.revision
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16)
            assert(guest.network.lastCommandResult.durable and commands.remote(host.generation,exact).ok)
            assert(data.coop.randomState==seed and data.coop.revision==revision and saved.mailQuests[1].rewardItem==d.item)
            assert(service:submitLocal('quest.deliver',{targetId=layout.entityId,npc='medic.png',questId=data.mailQuests[1].entityId}).reason=='quest_unavailable')
            r=questAct('quest.deliver',data.supplyQuests[1]); assert(r.ok and r.durable and data.goodwill==2)
            assert(not data.players.companion.inventory[2] and data.inventory[1]=='field-bandage-roll')
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.mailQuests[1].complete and guest.replica.data.supplyQuests[1].complete)
            assert(data.coop.sceneEpoch==epoch and data.players.host.itemSlots.equipment[1].id==hostId and hostRuntime.player.x==x)
        ''')

    def test_live_delivery_full_pack_mailbox_crate_identity_and_reconnect(self):
        self.enable_quest_assistance()
        self.lua.execute('''
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(c)
                assert(place(c)); local a=Players.forActor(c,'companion')
                for i=1,a.inventoryCapacity do require('game.item_instances').write(a,nil,{kind='inventory',index=i},'cowboy-hat') end
                return true
            end
            local mailbox={name='mailbox-reward',scene='train',x=10,y=20,storage={},mailbox=true}
            data.droppedItems[#data.droppedItems+1]=mailbox; assert(require('game.coop_entities').ensure(data))
            require('game.loot_progression').rollItem=function() return 'frontier-short-sword' end
            ready(); motionReady(); local r=questAct('quest.deliver',data.mailQuests[1])
            assert(r.ok and r.durable and r.details.delivery=='mailbox' and mailbox.mailUnread)
            local first=mailbox.storageInstances[1].id; assert(saved.droppedItems[1].storageInstances[1].id==first)
            for i=1,Catalog.storageCapacities['mailbox-reward'] do require('game.item_instances').write(data,mailbox,{kind='chest',index=i},'cowboy-hat') end
            data.mailQuests[2]={origin=1,destination=data.location,recipient='medic.png',complete=false}
            assert(require('game.coop_entities').ensure(data)); assert(service:checkpointNow()); step(22)
            r=questAct('quest.deliver',data.mailQuests[2]); assert(r.ok and r.durable and r.details.delivery=='local supply crate')
            local crate=data.droppedItems[2]; local id=crate.storageInstances[1].id
            assert(crate.entityId and id~=first and crate.storage[1]=='frontier-short-sword' and saved.droppedItems[2].storageInstances[1].id==id)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.droppedItems[2].storageInstances[1].id==id and guest.replica.data.goodwill==2)
        ''')

    def enable_sewing(self):
        self.enable_train_activities()
        self.lua.execute('''
            Crafting=require('game.outfit_crafting'); Definitions=require('game.outfit_catalog'); recipe=Definitions.recipes[1]
            function bundles(actor)
                for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil) end
                local i=1; for _,m in ipairs(recipe.materials) do for _=1,m.count do
                    Items.write(actor,nil,{kind='inventory',index=i},m.id); i=i+1
                end end
            end
            function sew(action,lease,args)
                args=args or {}; args.action=action; args.leaseId=lease
                local d=guest.replica.data; local scopes={'activity:train:sewing','outfit'}
                if action=='start' then scopes[#scopes+1]='player:companion'
                elseif action=='collect' then scopes[#scopes+1]='player:'..d.outfitCrafting.project.ownerPlayerId end
                local expected={}; for _,s in ipairs(scopes) do expected[s]=d.coop.revisions[s] or 0 end
                local id=assert(guest.network:submitCommand('outfit.craft',args,d.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
            function sewFinish(lease)
                while not Crafting.project(data).complete do
                    local stage=Crafting.stage(data); local reply
                    if stage.kind=='point' then reply=sew('point',lease,{x=stage.currentPoint.x,y=stage.currentPoint.y})
                    else
                        local center=(stage.targetRange.min+stage.targetRange.max)/2
                        for _=1,math.floor(center/.05+.5) do assert(sew('adjust',lease,{direction=1}).details.success) end
                        reply=sew('pullRelease',lease)
                    end
                    assert(reply.ok and reply.details.success and reply.details.correct,reply.reason)
                    assert(not reply.details.project and not reply.details.message and not reply.details.expiresAt)
                end
            end
        ''')

    def test_live_sewing_guest_materials_checkpoint_retry_full_owner_and_rejoin(self):
        self.enable_sewing()
        self.lua.execute('''
            local place=hostContext.placeCompanion
            hostContext.placeCompanion=function(c) assert(place(c)); bundles(Players.forActor(c,'companion')); return true end
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local hostInventory=Schema.copy(data.inventory)
            local reply=sew('acquire'); local lease=reply.details.leaseId; assert(reply.ok and reply.details.action=='acquire')
            assert(service:submitLocal('outfit.craft',{action='acquire'}).reason=='activity_busy')
            failSave=true; reply=sew('start',lease,{recipeId=recipe.id})
            assert(reply.ok and reply.savePending and reply.details.success and not next(data.players.companion.inventory))
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(commands.remote(host.generation,exact).ok and not next(data.players.companion.inventory))
            assert(saved.outfitCrafting.project.ownerPlayerId=='companion'); sewFinish(lease)
            local own=Players.forActor(data,'companion')
            for i=1,own.inventoryCapacity do Items.write(own,nil,{kind='inventory',index=i},'coal-chunk') end
            step(16); reply=sew('collect',lease); assert(reply.ok and not reply.details.success and reply.details.reason=='inventory_full')
            assert(Crafting.project(data).complete and reply.durable)
            Items.write(own,nil,{kind='inventory',index=1},nil); step(16)
            failSave=true; reply=sew('collect',lease); assert(reply.ok and reply.savePending and reply.details.success)
            exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            local itemId=own.itemSlots.inventory[1].id; local nextId=data.itemIdentity.nextId
            failSave=false; assert(commands.retryCheckpoint()); step(16)
            assert(guest.network.lastCommandResult.durable and commands.remote(host.generation,exact).ok)
            assert(data.itemIdentity.nextId==nextId and saved.players.companion.itemSlots.inventory[1].id==itemId)
            assert(data.coop.sceneEpoch==epoch and not Crafting.project(data))
            for k,v in pairs(hostInventory) do assert(data.inventory[k]==v) end
            guest:stop(); host:update(); step(4); assert(not next(service.activityState.resources))
            assert(guest:join()); step(30); assert(guest.replica.data.players.companion.itemSlots.inventory[1].id==itemId)
            assert(guest.replica.data.players.companion.inventory[1]==recipe.outputIds.masterwork)
        ''')

    def test_live_guest_finishes_host_project_into_host_backpack(self):
        self.enable_sewing()
        self.lua.execute('''
            bundles(Players.forActor(data,'host')); ready(); motionReady(); local location=data.location
            local lease=assert(service:submitLocal('outfit.craft',{action='acquire'}).result).leaseId
            assert(service:submitLocal('outfit.craft',{action='start',leaseId=lease,recipeId=recipe.id}).result.ok)
            assert(service:submitLocal('activity.release',{leaseId=lease}).ok); step(16)
            local guestInventory=Schema.copy(data.players.companion.inventory)
            local reply=sew('acquire'); lease=reply.details.leaseId; assert(reply.details.ownerPlayerId=='host')
            sewFinish(lease); reply=sew('collect',lease)
            assert(reply.ok and reply.durable and reply.details.success and reply.details.ownerPlayerId=='host')
            assert(saved.inventory[1]==recipe.outputIds.masterwork and not saved.outfitCrafting.project)
            for k,v in pairs(guestInventory) do assert(data.players.companion.inventory[k]==v) end
            assert(data.location==location and data.scene=='train')
        ''')

    def test_live_repair_host_time_exact_gear_and_part_checkpoint_retry_and_disconnect(self):
        self.enable_train_activities()
        self.lua.execute('''
            ready(); motionReady(); local own=data.players.companion; local id=own.itemSlots.equipment[1].id
            local hostId=data.players.host.itemSlots.equipment[1].id; local hostCondition=data.players.host.itemSlots.equipment[1].durability
            local reply=activityAct('weaponRepair.acquire',{itemId=id}); local lease=reply.details.leaseId
            assert(reply.ok and not reply.details.startedAt and not reply.details.itemId)
            assert(service:submitLocal('weaponRepair.acquire',{itemId=hostId}).reason=='activity_busy')
            local held=service.activityState.resources['train:weapon-repair']; clock=held.startedAt+(2+.655)/.86-.05
            failSave=true; reply=activityAct('weaponRepair.complete',{leaseId=lease})
            assert(reply.ok and reply.savePending and reply.details.success and reply.details.quality=='perfect')
            assert(own.itemSlots.equipment[1].id==id and own.itemSlots.equipment[1].durability==100 and not own.inventory[2])
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL)); local scrap=data.scrap
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(commands.remote(host.generation,exact).ok and data.scrap==scrap and saved.players.companion.itemSlots.equipment[1].id==id)
            assert(data.players.host.itemSlots.equipment[1].durability==hostCondition)
            own.itemSlots.equipment[2].durability=50
            reply=activityAct('weaponRepair.acquire',{itemId=own.itemSlots.equipment[2].id}); assert(reply.ok)
            reply=activityAct('weaponRepair.step',{leaseId=reply.details.leaseId,renew=true}); assert(reply.ok and reply.details.elapsed>0)
            guest:stop(); host:update(); step(4); assert(not next(service.activityState.resources))
            assert(guest:join()); step(30); assert(guest.replica.data.players.companion.itemSlots.equipment[1].id==id)
            assert(guest.replica.data.players.companion.itemSlots.equipment[1].durability==100)
        ''')

    def enable_people(self, scene='train'):
        self.enable_train()
        self.lua.globals().peopleScene = scene
        self.lua.execute('''
            RecipientAccess=require('game.coop_recipient_access'); Items=require('game.item_instances'); Entities=require('game.coop_entities'); P=require('game.net.protocol')
            data.scene=peopleScene; hostRuntime.scene=peopleScene; data.currentNPC='crow-merchant.png'
            if peopleScene=='train' then
                data.passengers={{npc=data.currentNPC,x=600,y=520,carIndex=1,weapon='trail-slingshot'}}; recipient=data.passengers[1]
            else data.stopLayouts['50']={npcWeapon='trail-slingshot'}; recipient=data.stopLayouts['50'] end
            data.droppedItems={{name='mailbox-reward',mailbox=true,mailUnread=true,scene=peopleScene,location=50,carIndex=1,
                x=594,y=520,storage={'frontier-short-sword'}}}
            assert(Items.ensure(data)); assert(Entities.ensure(data)); giftChest=data.droppedItems[1]
            commands.setRemoteActorState(function()
                return {screen=hostRuntime.state,scene=hostRuntime.scene,x=testRemoteX or 594,y=520,traveling=traveling,
                    encounterActive=encounter,activityBlocked=activityBlocked,npc={id=testNpc or data.currentNPC,x=600,y=520}}
            end)
            function personArgs(ref,chest)
                return {targetId=recipient.entityId,npc='crow-merchant.png',source=ref,
                    sourceItem=ref and Contract.selection(Players.forActor(guest.replica.data,'companion'),chest,ref),containerId=chest and chest.entityId}
            end
            function personAct(name,args,expected)
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,
                    expected or RecipientAccess.expected(guest.replica.data,'companion',name,args)))
                step(12); return guest.network.lastCommandResult,id
            end
        ''')

    def test_live_passenger_gear_gift_save_retry_mailbox_and_reconnect_preserve_identity(self):
        self.enable_people()
        self.lua.execute('''
            ready(); motionReady(); local hostItem=data.players.host.itemSlots.equipment[1].id; local own=data.players.companion
            local original=own.itemSlots.equipment[1].id; local old=recipient.weaponInstance.id; local epoch=data.coop.sceneEpoch
            failSave=true; local reply=personAct('passenger.equip',personArgs({kind='equipment',index=1}))
            assert(reply.ok and reply.savePending and reply.details.equipped and recipient.weaponInstance.id==original)
            assert(recipient.weaponInstance.id~=old and not own.equipment[1] and data.relationships[recipient.npc].gifts==1)
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(commands.remote(host.generation,exact).ok and data.relationships[recipient.npc].gifts==1)
            local source=Entities.find(guest.replica.data,giftChest.entityId); local gear=Items.get(data,giftChest,{kind='chest',index=1}).id
            reply=personAct('npc.gift',personArgs({kind='chest',index=1},source))
            assert(reply.ok and reply.durable and recipient.weaponInstance.id==gear and not giftChest.mailUnread and not giftChest.storage[1])
            assert(data.players.host.itemSlots.equipment[1].id==hostItem and data.coop.sceneEpoch==epoch)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.passengers[1].weaponInstance.id==gear and guest.replica.data.relationships[recipient.npc].gifts==2)
        ''')

    def test_live_resident_gift_exact_selection_recipient_and_availability(self):
        self.enable_people('stop')
        self.lua.execute('''
            ready(); motionReady(); local own=data.players.companion; local before=own.itemSlots.equipment[1].id
            local args=personArgs({kind='equipment',index=1}); args.sourceItem=nil
            local reply=personAct('npc.gift',args); assert(reply.reason=='item_selection_required')
            args=personArgs({kind='equipment',index=1}); args.sourceItem.id='forged-item'
            reply=personAct('npc.gift',args); assert(reply.reason=='stale_item' and own.itemSlots.equipment[1].id==before)
            args=personArgs({kind='equipment',index=1}); args.actorId='host'
            reply=personAct('npc.gift',args); assert(reply.reason=='invalid_arguments')
            testNpc='cook-mouse.png'; reply=personAct('npc.gift',personArgs({kind='equipment',index=1})); assert(reply.reason=='recipient_unavailable')
            testNpc=nil; encounter=true; reply=personAct('npc.gift',personArgs({kind='equipment',index=1})); assert(reply.reason=='unavailable')
            encounter=false; reply=personAct('npc.gift',personArgs({kind='equipment',index=1}))
            assert(reply.ok and reply.durable and recipient.npcWeaponInstance.id==before and own.equipment[1]==nil)
            assert(data.scene=='stop' and data.location==50 and data.conversations.completed.example.answer==2)
        ''')

    def test_live_approved_chatter_is_checkpointed_once_and_never_enters_story(self):
        self.enable_people()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local args={targetId=recipient.entityId,npc=recipient.npc}
            failSave=true; local reply=personAct('passenger.chatter',args)
            assert(reply.ok and reply.savePending and Catalog.dialogueLines[reply.details.lineIndex] and data.relationships[recipient.npc].talks==1)
            local first=reply.details.lineIndex
            local exact=require('game.net.commands').unpack(P.decode(guest.network.pendingCommand.bytes,P.CONTROL))
            failSave=false; assert(commands.retryCheckpoint()); step(16); assert(guest.network.lastCommandResult.durable)
            assert(commands.remote(host.generation,exact).result.lineIndex==first and data.relationships[recipient.npc].talks==1)
            reply=personAct('passenger.chatter',args); assert(reply.ok and reply.durable and reply.details.lineIndex~=first)
            reply=personAct('conversation.choose',args,{}); assert(reply.reason=='host_only')
            assert(data.coop.sceneEpoch==epoch and data.scene=='train' and data.conversations.completed.example.answer==2)
            guest:stop(); host:update(); assert(guest:join()); step(30)
            assert(guest.replica.data.relationships[recipient.npc].talks==2 and guest.replica.data.passengers[1].relationshipTalks==2)
        ''')

    def test_live_train_purchases_require_quotes_reject_contention_and_preserve_story(self):
        self.enable_train()
        self.lua.execute('''
            ready(); motionReady(); local epoch=data.coop.sceneEpoch; local revision=data.coop.revision
            local reply=trainAct('train.upgrade',{carId='coal-hauler'}); assert(reply.reason=='quote_required' and data.coop.revision==revision)
            reply=trainAct('train.engineUpgrade',{quotedPrice=15}); assert(reply.reason=='quote_required')
            local expected=TrainAccess.expected(guest.replica.data,'train.upgrade','companion')
            assert(commands.submit('train.engineUpgrade',{}).ok)
            reply=trainAct('train.upgrade',{carId='coal-hauler',quotedPrice=20},expected)
            assert(reply.reason=='stale_revision' and #data.trainCars==3 and data.scrap==185)
            lab:duplicateNext('client_to_host',1,1,true)
            reply=trainAct('train.upgrade',{carId='coal-hauler',quotedPrice=20})
            assert(reply.ok and reply.durable and reply.details.carId=='coal-hauler' and reply.details.price==20)
            assert(data.scrap==165 and #saved.trainCars==4 and data.location==50 and data.scene=='train' and data.coop.sceneEpoch==epoch)
            reply=trainAct('train.engineUpgrade',{quotedPrice=15,quotedLevel=1}); assert(reply.reason=='quote_changed')
            reply=trainAct('train.engineUpgrade',{quotedPrice=28,quotedLevel=2})
            assert(reply.ok and reply.details.level==2 and reply.details.price==28 and saved.engineLevel==2 and data.scrap==137)
            guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.replica.data.engineLevel==2 and #guest.replica.data.trainCars==4 and guest.replica.data.scrap==137)
            assert(data.players.host.activeCar==1 and data.players.companion.activeCar==1)
        ''')

    def test_live_train_fuel_and_upgrades_reject_forged_selectors_and_unavailable_actors(self):
        self.enable_train()
        self.lua.execute('''
            ready(); motionReady(); local args=fuelArgs(); args.sourceItem=nil
            local reply=trainAct('train.fuel',args); assert(reply.reason=='item_selection_required')
            args=fuelArgs(); args.source.actorId='host'
            reply=trainAct('train.fuel',args); assert(reply.reason=='invalid_slot' and data.resources.coal==10)
            args=fuelArgs(); args.sourceItem.name='coal-chunk'
            reply=trainAct('train.fuel',args); assert(reply.reason=='stale_item' and data.resources.coal==10)
            traveling=true; reply=trainAct('train.upgrade',{carId='coal-hauler',quotedPrice=20})
            assert(reply.reason=='unavailable' and data.scrap==200); traveling=nil
            data.players.companion.health=0; reply=trainAct('train.fuel',fuelArgs())
            assert(reply.reason=='unavailable' and data.resources.coal==10)
        ''')

    def enable_trade(self, caravan=False):
        self.enable_items()
        self.lua.execute('''
            Trade=require('game.merchant_trade'); Access=require('game.coop_merchant_access'); Entities=require('game.coop_entities')
            data.scene='stop'; data.location=20; hostRuntime.scene='stop'; data.currentNPC='crow-merchant.png'; data.scrap=200
            layout={npcOffers={['crow-merchant.png']='trade'},tradeStock={'frontier-short-sword','bean-tin','rocks'},tradeBudget=100}
            data.stopLayouts['20']=layout; hostRuntime.npcActor={x=250,y=250}; merchant='crow-merchant.png'
            commands.setRemoteActorState(function()
                return {screen=hostRuntime.state,scene=hostRuntime.scene,x=testRemoteX or 240,y=testRemoteY or 250,
                    traveling=traveling,encounterActive=encounter,activityBlocked=activityBlocked,
                    npc={id=data.currentNPC,x=250,y=250}}
            end)
            function merchantState()
                return {screen='game',scene=data.scene,x=testRemoteX or 240,y=testRemoteY or 250,npc={id=data.currentNPC,x=250,y=250}}
            end
            function tradeArgs(name,index)
                local actor=Players.forActor(guest.replica.data,'companion')
                local target=data.scene=='caravan' and camp.entityId or layout.entityId
                local source=assert(Access.find(actor,target,merchant,merchantState(),Catalog,true))
                local args={targetId=target,merchantId=merchant,index=index}
                if name=='merchant.buy' then
                    args.quotedItem=Trade.stockItem(source,index); args.quotedPrice=Trade.buyPrice(actor,Catalog,source,index)
                    args.listingId=source.kind=='caravan' and source.stock[index].id or nil
                else args.sourceItem=Contract.selection(actor,nil,{kind='inventory',index=index}) end
                return args,Access.expected(actor,'companion',source,name,index,Catalog)
            end
            function tradeAct(name,index,args,expected)
                if not args then args,expected=tradeArgs(name,index) end
                local id=assert(guest.network:submitCommand(name,args,data.coop.sceneEpoch,expected)); step(12)
                return guest.network.lastCommandResult,id
            end
        ''')
        if caravan:
            self.lua.execute('''
                local Caravans=require('game.crow_caravans'); data.crowCaravans={}
                local root=Caravans.ensureSchedule(data,{rng=function() return .5 end}); data.location=root.scheduledStops[1]
                data.scene='caravan'; hostRuntime.scene='caravan'
                camp=Caravans.ensureCamp(data,Catalog,data.location,{rng=function() return .5 end}); root.activeCampId=camp.id
                data.droppedItems={{name='mailbox-reward',scene='train',mailbox=true,storage={}}}
                merchant='packmaster'; testRemoteX=286; testRemoteY=385; assert(Entities.ensure(data))
                local place=hostContext.placeCompanion
                hostContext.placeCompanion=function(campaign)
                    assert(place(campaign)); campaign.players.companion.playerX=286; campaign.players.companion.playerY=385
                    return true
                end
            ''')

    def test_live_trade_duplicate_purchase_save_retry_and_reconnect_charge_once(self):
        self.enable_trade()
        self.lua.execute('''
            ready(); motionReady(); local hostId=data.players.host.itemSlots.equipment[1].id; local hostInventory=data.inventory[1]
            local args,expected=tradeArgs('merchant.buy',1); local price=args.quotedPrice
            lab:duplicateNext('client_to_host',1,1,true); failSave=true
            local reply,id=tradeAct('merchant.buy',1,args,expected)
            assert(reply.ok and reply.savePending and not reply.durable and reply.details.price==price)
            local item=data.players.companion.itemSlots.inventory[3].id; local revision=data.coop.revision
            step(24); assert(data.scrap==200-price and data.coop.revision==revision and guest.network.pendingCommand)
            failSave=false; assert(commands.retryCheckpoint()); step(22)
            assert(guest.network.lastCommandResult.durable and saved.players.companion.itemSlots.inventory[3].id==item)
            assert(data.scrap==200-price and data.inventory[1]==hostInventory and data.players.host.itemSlots.equipment[1].id==hostId)
            guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.replica.data.players.companion.itemSlots.inventory[3].id==item and guest.replica.data.scrap==200-price)
            local replay=require('game.net.codec').decode(service.requests.companion.cache[id].fingerprint)
            local receipt=commands.remote(host.generation,replay); assert(receipt.ok and receipt.durable and data.coop.revision==revision)
        ''')

    def test_live_trade_requires_quotes_and_identity_and_rechecks_host_stock_resources_and_reach(self):
        self.enable_trade()
        self.lua.execute('''
            ready(); motionReady(); local args,expected=tradeArgs('merchant.buy',1); args.quotedPrice=nil
            local reply=tradeAct('merchant.buy',1,args,expected); assert(reply.reason=='quote_required' and data.scrap==200)
            args,expected=tradeArgs('merchant.sell',1); args.sourceItem=nil
            reply=tradeAct('merchant.sell',1,args,expected); assert(reply.reason=='item_selection_required' and data.scrap==200)
            args,expected=tradeArgs('merchant.buy',1)
            assert(commands.submit('merchant.buy',{targetId=layout.entityId,merchantId=merchant,index=2}).ok)
            local scrap=data.scrap; reply=tradeAct('merchant.buy',1,args,expected)
            assert(reply.reason=='stale_revision' and data.scrap==scrap and layout.tradeStock[1]=='frontier-short-sword')
            args,expected=tradeArgs('merchant.buy',1); args.quotedPrice=args.quotedPrice+1
            reply=tradeAct('merchant.buy',1,args,expected); assert(reply.reason=='quote_changed' and data.scrap==scrap)
            args,expected=tradeArgs('merchant.buy',1); testRemoteX=900
            reply=tradeAct('merchant.buy',1,args,expected); assert(reply.reason=='merchant_unavailable' and data.scrap==scrap)
            testRemoteX=240; args,expected=tradeArgs('merchant.buy',1); args.actorId='host'
            reply=tradeAct('merchant.buy',1,args,expected); assert(reply.reason=='invalid_arguments' and data.scrap==scrap)
        ''')

    def test_live_caravan_ammo_mailbox_and_resale_preserve_instance_and_history(self):
        self.enable_trade(caravan=True)
        self.lua.execute('''
            ready(); motionReady(); local source=Trade.caravanSource(data,Catalog,camp,merchant)
            local ammoIndex,itemIndex
            for index,listing in ipairs(source.stock) do
                if Catalog.ammoPickupAmounts[listing.item] then ammoIndex=ammoIndex or index else itemIndex=itemIndex or index end
            end
            assert(ammoIndex and itemIndex)
            local name=source.stock[ammoIndex].item; local before=data.players.companion.ammo[name] or 0
            local reply=tradeAct('merchant.buy',ammoIndex)
            assert(reply.ok and reply.durable and reply.details.delivery=='ammo' and reply.details.amount==Catalog.ammoPickupAmounts[name])
            assert(data.players.companion.ammo[name]==before+reply.details.amount and #camp.purchaseHistory==1)
            for index=1,data.players.companion.inventoryCapacity do data.players.companion.inventory[index]='cowboy-hat' end
            assert(service:checkpointNow()); step(12)
            reply=tradeAct('merchant.buy',itemIndex)
            assert(reply.ok and reply.details.delivery=='train' and saved.droppedItems[1].mailUnread and #camp.purchaseHistory==2)
            local Items=require('game.item_instances'); local own=Players.forActor(data,'companion')
            own.inventory[1]='frontier-short-sword'; assert(Items.ensure(data)); local identity=own.itemSlots.inventory[1].id
            assert(service:checkpointNow()); step(22) -- Fixture seeding waits for the periodic projection audit.
            local args,expected=tradeArgs('merchant.sell',1); reply=tradeAct('merchant.sell',1,args,expected)
            assert(reply.ok and not own.inventory[1] and #camp.purchaseHistory==3,tostring(reply.reason))
            source=Trade.caravanSource(data,Catalog,camp,merchant); local resaleIndex=#source.stock
            assert(source.stock[resaleIndex].instances[1].id==identity)
            reply=tradeAct('merchant.buy',resaleIndex)
            assert(reply.ok and saved.players.companion.itemSlots.inventory[1].id==identity and #camp.purchaseHistory==4)
            assert(data.crowCaravans.trades==4 and data.players.host.inventory[1]=='orange-rose-vase')
        ''')

    def test_live_caravan_purchase_with_twenty_mailboxes_checks_only_actual_delivery(self):
        self.enable_trade(caravan=True)
        self.lua.execute('''
            ready(); motionReady()
            for slot=1,data.players.companion.inventoryCapacity do data.players.companion.inventory[slot]='cowboy-hat' end
            for index=2,20 do data.droppedItems[index]={name='mailbox-reward',scene='train',mailbox=true,storage={}} end
            for index=1,19 do for slot=1,20 do data.droppedItems[index].storage[slot]='cowboy-hat' end end
            assert(Entities.ensure(data)); assert(service:checkpointNow()); step(22)
            local source=Trade.caravanSource(data,Catalog,camp,merchant); local selected
            for index,listing in ipairs(source.stock) do if not Catalog.ammoPickupAmounts[listing.item] then selected=index; break end end
            local args,expected=tradeArgs('merchant.buy',selected); local count=0
            for _ in pairs(expected) do count=count+1 end
            assert(count==5 and expected['entity:'..data.droppedItems[20].entityId]==0)
            assert(not expected['entity:'..data.droppedItems[1].entityId])
            local reply=tradeAct('merchant.buy',selected,args,expected)
            assert(reply.ok and reply.durable and reply.details.delivery=='train' and saved.droppedItems[20].storage[1]==args.quotedItem)
            assert(saved.droppedItems[1].storage[1]=='cowboy-hat')
        ''')

    def test_car_retry_after_failed_checkpoint_applies_once_and_resolves_after_retry(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); failSave=true
            local reply=change(2); assert(reply.ok and reply.savePending and not reply.durable)
            assert(guest.network.pendingCommand and service.pendingSave and data.players.companion.activeCar==2)
            local revision=data.coop.revision; step(20)
            assert(data.coop.revision==revision and guest.network.pendingCommand and not commands.carBusy('companion'))
            failSave=false; assert(commands.retryCheckpoint()); step(20)
            assert(not guest.network.pendingCommand and guest.network.lastCommandResult.durable)
            assert(saved.players.companion.activeCar==2 and data.coop.revision==revision)
            assert(not commands.carBusy('companion')) -- Retrying a receipt cannot restart the transition.
        ''')

    def test_command_admission_rejoin_and_application_replay_do_not_repeat_car_changes(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); local before=data.coop.revisions['player:companion'] or 0
            lab:duplicateNext('client_to_host',1,1,true)
            local reply,id=change(2); assert(reply.ok and data.coop.revisions['player:companion']==before+1)
            local revision=data.coop.revision; guest:stop(); host:update(); assert(guest:join()); step(18)
            assert(guest.phase=='connected' and guest.network.nextRequestId==id+1)
            assert(guest.replica.data.players.companion.activeCar==2 and data.coop.revision==revision)
            motionReady(); reply=change(3); assert(reply.ok and data.players.companion.activeCar==3)
            step(18); assert(not commands.carBusy('companion'))
            local earlier=assert(require('game.net.codec').decode(service.requests.companion.cache[id].fingerprint))
            assert(commands.remote(host.generation,earlier).ok)
            assert(not commands.carBusy('companion') and data.players.companion.activeCar==3)
        ''')

    def test_guest_story_stale_scope_and_forged_car_arguments_are_rejected(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); local revision=data.coop.revision
            local reply=change(2,{command='travel.depart',args={},expected={}})
            assert(not reply.ok and reply.reason=='host_only' and not data.coop.journey)
            step(12); reply=change(2,{args={car=2,x=900,actorId='host'}})
            assert(not reply.ok and reply.reason=='invalid_car')
            step(12); reply=change(2,{expected={['player:companion']=99}})
            assert(not reply.ok and reply.reason=='stale_revision')
            step(12); reply=change(2,{sceneEpoch=data.coop.sceneEpoch+1})
            assert(not reply.ok and reply.reason=='stale_scene')
            assert(data.coop.revision==revision and data.players.host.activeCar==1 and data.players.companion.activeCar==1)
        ''')

    def test_car_changes_respect_party_progression_and_personal_timing(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady()
            for _,flag in ipairs({'traveling','encounter','activityBlocked'}) do
                _G[flag]=true; local reply=change(2); assert(not reply.ok and reply.reason=='car_unavailable')
                _G[flag]=false; step(12)
            end
            local reply=change(2); assert(reply.ok)
            reply=change(3); assert(not reply.ok and reply.reason=='car_transition_pending')
            data.scene='stop'; hostRuntime.scene='stop'; data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(not commands.carBusy('companion'))
            step(12); reply=change(1); assert(not reply.ok and reply.reason=='car_unavailable')
            assert(data.players.companion.activeCar==2 and data.players.host.activeCar==1)
        ''')

    def test_host_departure_interrupts_guest_car_transition_without_replaying_old_motion(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); data.events['2']={id='resolved'}
            local oldEpoch=data.coop.sceneEpoch; local oldMotion=host.motion.motionId
            local reply=change(2); assert(reply.ok and commands.carBusy('companion'))
            local departed=commands.submit('scene.leaveTrain',{})
            assert(departed.ok and departed.durable and data.scene=='stop' and data.coop.sceneEpoch==oldEpoch+1)
            assert(not commands.carBusy('companion'))
            step(3); local x=data.players.companion.playerX
            assert(not host.motion:ready(host.generation,oldEpoch,oldMotion))
            assert(guest.network:sendMovement(1,oldEpoch,1000,0,true,oldMotion)); step(3)
            assert(data.players.companion.playerX==x and not host.motion.readyEpoch)
            assert(saved.scene=='stop' and guest.replica.data.scene=='stop')
        ''')

    def test_host_approval_uses_application_authority_and_guest_keeps_its_original_save(self):
        self.lua.execute('''
            ready()
            assert(hostSession.networkMode=='host' and guestSession.networkMode=='client')
            assert(service.bindings.companion and data.players.companion and saved.players.companion)
            assert(guestSession.replicaData==guest.replica.data and guest.replica:actor().character=='cook-mouse.png')
            assert(guestRuntime.saveData==guestData and guestRuntime.selectedSlot==2 and guestData.location==9)
            assert(not guestSession:canWriteCampaign() and guestFiles['coop-connections.dat'])
            assert(not guestFiles['saves/slot1.lua'] and not guestFiles['saves/slot2.lua'])
            guest:stop(); host:update()
            assert(guestSession.networkMode=='offline' and guestRuntime.saveData==guestData and not guestSession.replicaData)
            assert(not service.bindings.companion and data.players.companion)
        ''')

    def test_preflight_failure_opens_no_socket_and_uses_existing_checkpoint_retry(self):
        self.lua.execute('''
            failSave=true; local ok,reason=host:host()
            assert(not ok and reason=='save_not_ready' and service.pendingSave and not lab.host)
            assert(hostSession.networkMode=='offline' and not data.coop.network)
            failSave=false; assert(service:retryCheckpoint()); assert(host:host())
            assert(host.phase=='hosting' and hostSession.networkMode=='host')
        ''')

    def test_failed_enrollment_checkpoint_retries_without_another_companion_kit(self):
        self.lua.execute('''
            assert(host:host()); assert(guest:join()); step(4)
            failSave=true; assert(not host:approve() and service.pendingSave)
            local item=data.players.companion.itemSlots.equipment[1].id
            assert(guest.phase=='joining' and not guestSession.replicaData)
            failSave=false; assert(service:retryCheckpoint()); assert(host:approve()); step(12)
            assert(guest.phase=='connected' and data.players.companion.itemSlots.equipment[1].id==item)
            assert(data.coop.network.bindingVersion==1)
        ''')

    def test_periodic_audit_catches_legacy_host_changes_without_a_command_revision(self):
        self.lua.execute('''
            ready(); local revision=data.coop.revision; data.resources.food=data.resources.food+3
            step(35)
            assert(data.coop.revision==revision and guest.replica.data.resources.food==data.resources.food)
            assert(guest.phase=='connected' and service.bindings.companion==1)
        ''')

    def test_returning_to_title_stops_host_and_restores_guest_local_ownership(self):
        self.lua.execute('''
            ready(); hostRuntime.state='slots'; step(5)
            assert(host.phase=='idle' and hostSession.networkMode=='offline' and not service.bindings.companion)
            assert(guest.phase=='idle' and guestSession.networkMode=='offline' and guestRuntime.saveData==guestData)
            assert(guest.menuOpen and guest.error)
        ''')

    def test_changed_save_slot_closes_host_before_delayed_guest_spending(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local health=data.players.companion.health
            local revision=data.coop.revision; local checkpointWrites=writes
            local args=itemArgs({kind='inventory',index=1})
            lab:delayNext('client_to_host',1,4)
            assert(guest.network:submitCommand('inventory.consume',args,data.coop.sceneEpoch,
                Contract.expected(guest.replica.data,'companion','inventory.consume',args,Catalog)))
            hostRuntime.selectedSlot=3; step(8)
            assert(host.phase=='idle' and hostSession.networkMode=='offline','host retained old slot session')
            assert(not service.bindings.companion and not host.network)
            assert(data.players.companion.health==health and data.coop.revision==revision)
            assert(data.players.companion.inventory[1]=='field-bandage-roll' and writes==checkpointWrites)
            assert(guest.phase=='idle' and guestRuntime.selectedSlot==2 and guestRuntime.saveData==guestData)
        ''')

    def test_replaced_campaign_closes_before_delayed_guest_command_dispatch(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local revision=data.coop.revision; local checkpointWrites=writes
            local args=itemArgs({kind='inventory',index=1}); local other=F.campaign(4,{scene='train'})
            lab:delayNext('client_to_host',1,4)
            assert(guest.network:submitCommand('inventory.consume',args,data.coop.sceneEpoch,
                Contract.expected(guest.replica.data,'companion','inventory.consume',args,Catalog)))
            hostRuntime.saveData=other; hostRuntime.selectedSlot=3; step(8)
            assert(host.phase=='idle' and guest.phase=='idle' and not service.bindings.companion)
            assert(data.players.companion.health==10 and data.coop.revision==revision and writes==checkpointWrites)
            assert(hostRuntime.saveData==other and not other.players.companion)
            assert(guestRuntime.saveData==guestData and guestRuntime.selectedSlot==2)
        ''')

    def test_slot_change_during_service_cannot_publish_old_campaign_or_issue_checkpoint(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local serviceNetwork=host.network.service
            local before=writes
            host.network.service=function(network)
                serviceNetwork(network); hostRuntime.selectedSlot=3
                data.resources.food=data.resources.food+1 -- changed local model awaiting its new slot owner
            end
            host:beginFrame(.05); host:finishFrame(); guest:update()
            assert(host.phase=='idle' and not host.network,'publish retained a changed save slot')
            assert(writes==before and not service.bindings.companion)
            assert(guest.phase=='idle' and guestRuntime.saveData==guestData)
        ''')

    def test_retained_host_callbacks_reject_changed_slot_before_frame_cleanup(self):
        self.enable_items()
        self.lua.execute('''
            ready(); motionReady(); local network=host.network; local before=writes
            local args=itemArgs({kind='inventory',index=1})
            local request=assert(service:prepareRequest('companion','inventory.consume',args))
            local revision=data.coop.revision
            hostRuntime.selectedSlot=3
            assert(network.context.preflight()==false)
            local reply,reason=network.context.command(host.generation,request)
            assert(reply==nil and reason=='campaign_changed')
            local snapshot,errorMessage=network.context.snapshot()
            assert(snapshot==nil and errorMessage=='campaign_changed')
            assert(writes==before and data.coop.revision==revision and data.players.companion.health==10)
            host:beginFrame(.05); guest:update()
            assert(host.phase=='idle' and guest.phase=='idle' and guestRuntime.saveData==guestData)
        ''')

    def test_host_restart_preserves_companion_credential_and_authority_generation(self):
        self.lua.execute('''
            ready(); local item=data.players.companion.itemSlots.equipment[1].id
            host:stop(); guest:update(); assert(guest.phase=='idle')
            assert(host:host()); assert(guest:join()); step(16)
            assert(guest.phase=='connected' and not host:pending())
            assert(service.bindings.companion==2 and data.coop.network.bindingVersion==1)
            assert(data.players.companion.itemSlots.equipment[1].id==item)
        ''')

    def saved_battle(self):
        self.lua.execute('''
            assert(F.enroll(data)); local Catalog=require('game.catalog')
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',maxHP=100,mobFiles={Catalog.mobTiers.easy[1]}}
            assert(require('game.coop_entities').ensure(data))
            require('game.coop_battles').install(service,{catalog=Catalog,actorState=function() return {screen='game',scene='train'} end})
            service:admit('companion',1)
            local args={encounterId=data.encounters['2'].entityId}
            local request=assert(service:prepareRequest('host','battle.begin',args))
            assert(service:execute('host',0,request).ok)
            data=assert(Schema.migrate(saved)); hostRuntime.saveData=data
            service=Authority.new({campaign=data,sessionId='loaded-battle',checkpoint=function(value) saved=assert(Schema.copy(value)); return true end})
            hostRuntime.battle=assert(require('game.tactical_battle_state').restore(data,Catalog)); hostRuntime.state='battle'
        ''')

    def test_disk_loaded_battle_can_host_without_rebuilding_its_board(self):
        self.saved_battle()
        self.lua.execute('''
            local b=hostRuntime.battle; local revision=data.tacticalBattle.revision; local rng=data.coop.randomState
            local item=data.players.companion.itemSlots.equipment[1].id
            assert(host:canHost() and host:host(),host.error)
            assert(hostRuntime.battle==b and data.tacticalBattle.battle==b and data.tacticalBattle.revision==revision)
            assert(data.coop.randomState==rng and data.players.companion.itemSlots.equipment[1].id==item)
            assert(guest:join()); step(4); assert(host:approve()); step(12)
            assert(guest.phase=='connected' and guest.replica.data.tacticalBattle.encounterId==data.tacticalBattle.encounterId)
            assert(hostRuntime.battle==b and data.tacticalBattle.revision==revision and data.coop.randomState==rng)
        ''')

    def test_host_eligibility_requires_owned_attached_valid_board_and_play_screen(self):
        self.saved_battle()
        self.lua.execute('''
            local b=hostRuntime.battle; assert(host:canHost())
            hostRuntime.state='slots'; assert(not host:canHost() and not host:host()); hostRuntime.state='battle'
            hostRuntime.battle=assert(Schema.copy(b)); assert(not host:canHost()); hostRuntime.battle=b
            hostSession:setNetworkMode('client'); assert(not host:canHost()); hostSession:setNetworkMode('offline')
            local active=b.active; b.active=999; assert(not host:canHost()); b.active=active
            local checkpoint=data.tacticalBattle; data.tacticalBattle=nil; assert(not host:canHost())
            hostRuntime.battle=nil; hostRuntime.state='game'; assert(host:canHost())
            hostRuntime.selectedSlot=nil; assert(not host:canHost()); hostRuntime.selectedSlot=1
            data.tacticalBattle=checkpoint; hostRuntime.state='battle'; hostRuntime.battle=b
        ''')

    def test_guest_origin_and_address_must_be_valid_before_connecting(self):
        self.lua.execute('''
            guestRuntime.state='game'; assert(not guest:join() and joins==0)
            guestRuntime.state='slots'; guest.address='http://bad'; assert(not guest:join() and joins==0)
            guest.address='friend-pc'; guestContext.beforeJoin=function() return false end
            assert(not guest:join() and joins==0 and guestSession.networkMode=='offline')
        ''')

    def test_decline_and_guest_leave_do_not_create_or_delete_host_companion(self):
        self.lua.execute('''
            assert(host:host()); assert(guest:join()); step(4); assert(host:decline()); step(4)
            assert(not data.players.companion and guest.phase=='idle')
            assert(guest:join()); step(4); assert(host:approve()); step(12)
            guest:stop(); host:update(); assert(data.players.companion and not service.bindings.companion)
        ''')

    def test_motion_keeps_peer_ownership_across_loss_scene_changes_and_reconnect(self):
        self.lua.execute('''
            hostContext.movement={hostActor=function() return hostRuntime.player end,allowed=function() return true end,
                move=function(_,_,_,_,x,y) return math.max(0,math.min(1000,x)),y end}
            ready(); step(3)
            assert(guest.motionFrame and not guest.motionFrame.ready)
            assert(guest.network:sendMovement(1,1,1000,0,false,host.motion.motionId)); step(2)
            local x=data.players.companion.playerX; assert(x==240)
            assert(guest.network:sceneReady(data.coop.sceneEpoch,host.motion.motionId)); step(2)
            for i=2,9 do assert(guest.network:sendMovement(i,data.coop.sceneEpoch,1000,0,false,host.motion.motionId)); step(1) end
            assert(data.players.companion.playerX>x and hostRuntime.player.x==200)
            step(12); local stopped=data.players.companion.playerX
            assert(guest.motionFrame.ack>0 and not guest.motionFrame.companion.moving)
            lab:delayNext('client_to_host',1,4)
            assert(guest.network:sendMovement(10,data.coop.sceneEpoch,-1000,0,false,host.motion.motionId))
            assert(guest.network:sendMovement(11,data.coop.sceneEpoch,1000,0,false,host.motion.motionId)); step(6)
            assert(host.motion.sequence==11 and host.motion.input.x==1)
            data.coop.sceneEpoch=data.coop.sceneEpoch+1; data.players.companion.playerX=400
            step(18); assert(data.players.companion.playerX==400 and not host.motion.readyEpoch)
            assert(guest.replica.data.coop.sceneEpoch==data.coop.sceneEpoch and not guest.motionFrame.ready)
            assert(not host.motion:ready(1,data.coop.sceneEpoch-1,host.motion.motionId))
            guest:stop(); step(2); assert(not host.motion.generation)
            assert(guest:join()); step(20)
            assert(guest.phase=='connected' and host.motion.generation==2 and not host.motion.readyEpoch)
            assert(data.players.companion.playerX==400 and guest.motionFrame.companion.x==400000)
        ''')

    def test_motion_frame_cannot_regress_or_replace_the_campaign_replica(self):
        self.lua.execute('''
            hostContext.movement={hostActor=function() return hostRuntime.player end,allowed=function() return true end,
                move=function(_,_,_,_,x,y) return x,y end}
            ready(); step(4); local original=guest.motionFrame; local replica=guest.replica.data
            assert(original and not guest.network.context.motion(original))
            local future=assert(Schema.copy(original)); future.serial=future.serial+100; future.sceneEpoch=future.sceneEpoch+1
            assert(not guest.network.context.motion(future) and guest.motionFrame==original and guest.replica.data==replica)
            host:stop(); step(2); assert(not guest.motionFrame and not guestSession.replicaData)
        ''')

    def test_failed_companion_art_preparation_does_not_admit_or_replace_character(self):
        self.lua.execute('''
            hostContext.prepareCompanion=function() return false end
            assert(host:host()); assert(guest:join()); step(4); assert(host:approve()); step(18)
            assert(guest.phase=='idle' and not service.bindings.companion)
            local item=data.players.companion.itemSlots.equipment[1].id
            hostContext.prepareCompanion=function(actor) return actor==data.players.companion end
            assert(guest:join()); step(20)
            assert(guest.phase=='connected' and service.bindings.companion==2)
            assert(data.players.companion.itemSlots.equipment[1].id==item and data.coop.network.bindingVersion==1)
        ''')


    def test_prepared_guest_world_opens_and_releases_without_replacing_local_runtime(self):
        self.lua.execute('''
            local created,updates,released,neutral=0,0,0,0
            guestContext.createGuestView=function(controller)
                assert(controller==guest and controller.replica.data); created=created+1
                return {ready=false,update=function(self) updates=updates+1; self.ready=true; return true end,
                    neutralize=function() neutral=neutral+1 end,release=function() released=released+1 end}
            end
            ready(); assert(created==1 and updates>0 and guest:captures() and not guest.previewOnly)
            assert(guest:closeMenu() and not guest:captures())
            guest:open(); assert(guest:captures() and neutral==1)
            assert(guestRuntime.saveData==guestData and guestRuntime.selectedSlot==2)
            guest:stop(); assert(released==1 and not guest.clientView and guest.previewOnly)
        ''')

    def test_split_frame_publishes_current_host_state_and_motion_after_simulation(self):
        self.enable_cars()
        self.lua.execute('''
            ready(); motionReady(); step(16); assert(host.network.link.phase=='ready'); local sent,frames=0,0
            local send=host.network.sendMotion
            host.network.sendMotion=function(self,frame) sent=frame; frames=frames+1; return send(self,frame) end
            local oldRevision=host.producer.revision
            clock=clock+1.1; host:beginFrame(.2)
            assert(frames==0 and host.producer.revision==oldRevision)
            hostRuntime.player.x=333; hostRuntime.player.y=444
            host:finishFrame()
            assert(frames==1 and sent.host.x==333000 and sent.host.y==444000)
            assert(host.producer.revision>oldRevision and data.players.host.playerX==333)
        ''')

    def test_live_enemy_stream_is_disposable_and_suppressed_while_save_is_pending(self):
        self.lua.execute('''
            local Areas=require('game.expedition_areas')
            data.scene='expedition'; data.location=5; data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; Areas.ensure(data)
            local area=Areas.current(data); local id=area.mobs[1].id
            local system={transient={[area.id]={[id]={state='windup',timer=.46,animationDistance=100}}}}
            hostContext.roaming=function() return system,false end
            ready(); step(4); assert(guest.roamingPresentation:get(id).state=='windup')
            local original=guest.replica.data.expeditions[area.id].mobs[id].x
            local captured=0; local send=host.network.sendRoaming
            host.network.sendRoaming=function(self,frame) captured=captured+1; return send(self,frame) end
            service.pendingSave={}; clock=clock+.2; host:finishFrame(); assert(captured==0)
            service.pendingSave=nil; data.expeditions[area.id].mobs[id].x=original+60
            clock=clock+.2; host:finishFrame(); guest:beginFrame(); assert(captured==2)
            clock=clock+.1; assert(guest.roamingPresentation:get(id).x==original+60)
            assert(guest.replica.data.expeditions[area.id].mobs[id].x==original)
            guest:stop(); assert(not guest.roamingPresentation)
        ''')

    def test_patient_hold_tracks_valid_live_lease_without_mutating_expired_state(self):
        self.enable_first_aid()
        self.lua.execute('''
            ready(); motionReady(); assert(not commands.patientBusy('medic.png'))
            local reply=aid('firstAid.acquire'); assert(reply.ok,reply.reason)
            assert(commands.patientBusy('medic.png') and not commands.patientBusy('other.png'))
            local generation=service.bindings.companion; service.bindings.companion=nil
            assert(not commands.patientBusy('medic.png')); service.bindings.companion=generation
            local epoch=data.coop.sceneEpoch; data.coop.sceneEpoch=epoch+1
            assert(not commands.patientBusy('medic.png')); data.coop.sceneEpoch=epoch
            clock=clock+31; assert(not commands.patientBusy('medic.png'))
            local count=0; for _ in pairs(service.activityState.resources) do count=count+1 end
            assert(count==1) -- Read-only query; command authority owns cleanup.
            service:disconnect('companion',generation); assert(not commands.patientBusy('medic.png'))
        ''')

    def test_guest_view_failure_closes_connection_and_restores_local_ownership(self):
        self.lua.execute('''
            local released=false
            guestContext.createGuestView=function()
                return {update=function() return nil,'missing_host_layout' end,release=function() released=true end}
            end
            assert(host:host()); assert(guest:join()); step(4); assert(host:approve()); step(12)
            assert(guest.phase=='idle' and guest.error=='missing_host_layout' and guest.menuOpen)
            assert(released and not guest.network and not guest.clientView and not guest.replica)
            assert(guestSession.networkMode=='offline' and guestRuntime.saveData==guestData and guestRuntime.selectedSlot==2)
            assert(not service.bindings.companion)
        ''')


class LocalPlayWrapperTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            log={}; modal=true; pending=false; cancelled=false; stopped=0
            local function add(name) log[#log+1]=name end
            controller={update=function() add('network') end,captures=function() return modal end,
                stop=function() stopped=stopped+1; add('stop') end,open=function() modal=true end}
            panel={stopTextInput=function() end,draw=function() add('panel') end,key=function() return true end,
                click=function() modal=false; return true end,textinput=function() return true end}
            package.loaded['game.local_play_panel']={new=function() return panel end}
            app={}
            for _,name in ipairs({'update','draw','keypressed','keyreleased','textinput','mousepressed','mousereleased','mousemoved',
                'touchpressed','touchreleased','touchmoved','gamepadpressed','gamepadreleased','gamepadaxis','wheelmoved','focus'}) do
                local label=name; app[name]=function() add(label) end
            end
            app.quit=function() add('quit'); return cancelled end
            ui={}; runtime={state='game'}
            require('game.local_play_host').wrap(app,{controller=controller,ui=ui,runtime=runtime,
                commands={checkpointStatus=function() return {pending=pending} end},
                screenToGame=function(x,y) return x,y end,bindings={isCapturing=function() return false end},
                idleUpdate=function() add('idle') end})
        ''')

    def test_network_precedes_modal_and_save_barrier_early_returns(self):
        self.lua.execute('''
            app.update(.1); assert(table.concat(log,',')=='network,idle')
            log={}; pending=true; app.update(.1); assert(table.concat(log,',')=='network,update')
            log={}; app.draw(); assert(log[1]=='draw')
            log={}; pending=false; app.draw(); assert(log[1]=='panel')
        ''')

    def test_host_lan_panel_runs_one_shared_update_between_service_and_publish(self):
        self.lua.execute('''
            runtime.session={networkMode='host'}
            controller.beginFrame=function() log[#log+1]='service' end
            controller.finishFrame=function() log[#log+1]='publish' end
            app.update(.1); assert(table.concat(log,',')=='service,update,publish')
            log={}; pending=true; app.update(.1); assert(table.concat(log,',')=='service,update,publish')
        ''')

    def test_guest_split_frame_keeps_replica_out_of_normal_world_updates(self):
        self.lua.execute('''
            runtime.session={networkMode='client'}; controller.isClient=function() return true end
            controller.beginFrame=function() log[#log+1]='service' end
            controller.finishFrame=function() log[#log+1]='finish' end
            app.update(.1); assert(table.concat(log,',')=='service,idle,finish')
        ''')

    def test_consumed_touch_release_cannot_trigger_gameplay_after_panel_closes(self):
        self.lua.execute('''
            app.touchpressed('touch',10,10); assert(not modal)
            app.touchreleased('touch',10,10); assert(#log==0)
            app.touchreleased('other',10,10); assert(log[1]=='touchreleased')
        ''')

    def test_cancelled_quit_keeps_network_until_host_confirms(self):
        self.lua.execute('''
            cancelled=true; assert(app.quit()==true and stopped==0)
            cancelled=false; assert(app.quit()==false and stopped==1)
            assert(table.concat(log,',')=='quit,quit,stop')
        ''')

    def test_guest_world_callbacks_never_fall_through_to_solo_simulation(self):
        self.lua.execute('''
            modal=false; controller.isClient=function() return true end
            local received={}; controller.clientView={}
            for _,name in ipairs({'draw','keypressed','mousepressed','touchpressed','touchreleased','focus'}) do
                local key=name; controller.clientView[name]=function() received[key]=(received[key] or 0)+1; return true end
            end
            app.update(.1); assert(table.concat(log,',')=='network,idle'); log={}
            app.draw(); app.keypressed('e'); app.mousepressed(20,30,1,false); app.touchpressed('g',20,30)
            app.touchreleased('g',20,30); app.focus(false)
            app.gamepadpressed({},'a'); app.gamepadreleased({},'a'); app.keyreleased('e'); app.wheelmoved(0,1)
            assert(#log==0 and received.draw==1 and received.keypressed==1 and received.mousepressed==1)
            assert(received.touchpressed==1 and received.touchreleased==1 and received.focus==1)
            assert(controller.focused==false)
            controller.clientView=nil; app.draw(); app.keypressed('e'); app.update(.1)
            assert(table.concat(log,',')=='network,idle')
        ''')

    def test_host_pose_callback_restores_offline_handler_at_input_boundary(self):
        self.lua.execute('''
            modal=false; local submitted={}
            local offline=function() return 'offline' end; ui.changePose=offline
            local nextApp={}
            for _,name in ipairs({'update','draw','keypressed','keyreleased','textinput','mousepressed','mousereleased','mousemoved',
                'touchpressed','touchreleased','touchmoved','gamepadpressed','gamepadreleased','gamepadaxis','wheelmoved','focus','quit'}) do
                nextApp[name]=function() end
            end
            require('game.local_play_host').wrap(nextApp,{controller=controller,ui=ui,runtime=runtime,
                commands={checkpointStatus=function() return {pending=false} end,poseState=function() return nil end,
                    submit=function(name,args) submitted[#submitted+1]={name=name,args=args}; return {ok=true,durable=false} end},
                screenToGame=function(x,y) return x,y end,bindings={isCapturing=function() return false end},idleUpdate=function() end})
            runtime.session={networkMode='host'};nextApp.update(.1)
            assert(ui.changePose('sit').ok and submitted[1].name=='player.pose' and submitted[1].args.pose=='sit')
            runtime.session.networkMode='offline';nextApp.mousepressed(100,100,1,false)
            assert(ui.changePose==offline and ui.changePose()=='offline' and #submitted==1)
        ''')

    def test_companion_pose_provider_preserves_checked_melee_presentation(self):
        self.lua.execute('''
            local provider=function(id) assert(id=='companion');return {pose='sit',useMs=450} end
            local ctx={controller=controller,ui=ui,runtime=runtime,commands={poseState=provider,
                checkpointStatus=function() return {pending=false} end},screenToGame=function(x,y) return x,y end,
                bindings={isCapturing=function() return false end},idleUpdate=function() end}
            local base={};for _,name in ipairs({'update','draw','keypressed','keyreleased','textinput','mousepressed','mousereleased','mousemoved',
                'touchpressed','touchreleased','touchmoved','gamepadpressed','gamepadreleased','gamepadaxis','wheelmoved','focus','quit'}) do base[name]=function() end end
            require('game.local_play_host').wrap(base,ctx)
            controller.motion={generation=1,actor={x=200,y=250}};controller.campaign={players={companion={id='companion'}},coop={sceneEpoch=2}}
            local _,_,pose=ui.coopCompanion();assert(pose.playerPose=='sit' and pose.actionKind=='use' and pose.actionTimer==.45)
            runtime.animationClock=1;runtime.companionFieldAction={epoch=2,untilTime=1.2,weapon='sword',facing=-1}
            _,_,pose=ui.coopCompanion();assert(pose.playerPose=='sit' and pose.actionKind=='melee' and pose.actionHeldItem=='sword')
            assert(math.abs(pose.actionTimer-.2)<1e-8 and pose.facing==-1)
        ''')

if __name__ == '__main__':
    unittest.main()
