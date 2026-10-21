"""Direct player gifts conserve gear identity and ammo across saved retries."""
import unittest
import test_coop_gifts_behavior as gifts


class CoopSharingTests(unittest.TestCase):
    def setUp(self):
        gifts.CoopGiftsTests.setUp(self)
        self.lua.execute('''
            require('game.coop_sharing').install(authority,{catalog=Catalog,actorState=function(id) return states[id] end})
            function offer(id,ref)
                return {recipient=id=='host' and 'companion' or 'host',source=ref,
                    sourceItem=require('game.coop_item_contract').selection(Players.forActor(data,id),nil,ref)}
            end
        ''')

    def test_weapon_transfer_preserves_instance_and_condition(self):
        self.lua.execute('''
            local ref={kind='equipment',index=1}; local instance=Items.get(data,nil,ref)
            local other=Players.forActor(data,'companion'); local index=Inventory.firstEmptySlot(other)
            local req=request('host','inventory.give',offer('host',ref)); local reply=run('host',req)
            assert(reply.ok and not data.equipment[1] and other.inventory[index]==instance.name)
            assert(Items.get(other,nil,{kind='inventory',index=index}).id==instance.id)
            assert(Items.get(other,nil,{kind='inventory',index=index}).durability==67)
            assert(run('host',req).ok and Items.validate(data))
            local back=offer('companion',{kind='inventory',index=index})
            assert(run('companion',request('companion','inventory.give',back)).ok)
            assert(not other.inventory[index] and Items.validate(data) and Schema.validate(data))
        ''')

    def test_ammo_reserve_moves_exact_quantity_and_replay_cannot_duplicate(self):
        self.lua.execute('''
            data.ammo['22lr']=37; data.players.companion.ammo['22lr']=4
            local req=request('host','ammo.give',{recipient='companion',ammo='22lr',amount=12})
            local result=run('host',req); assert(result.ok)
            assert(data.ammo['22lr']==25 and data.players.companion.ammo['22lr']==16)
            assert(run('host',req).ok and data.players.companion.ammo['22lr']==16)
            assert(require('game.net.item_results').valid('ammo.give',require('game.net.item_results').project('ammo.give',result.result)))
            local missing,reason=authority:prepareRequest('companion','ammo.give',{recipient='host',ammo='22lr',amount=17})
            assert(not missing and reason=='not_enough_ammo')
            local copied=assert(Schema.copy(data)); assert(copied.players.companion.ammo['22lr']==16)
        ''')

    def test_room_reach_full_pack_and_stale_selection_do_not_remove_items(self):
        self.lua.execute('''
            local ref={kind='equipment',index=1}; local args=offer('host',ref)
            local before=Items.get(data,nil,ref).id
            states.companion.x=900
            local req,reason=authority:prepareRequest('host','inventory.give',args)
            assert(not req and reason=='recipient_out_of_reach')
            states.companion.x=200
            local Presence=require('game.coop_presence'); Presence.ensure(data)
            data.players.companion.presence.scene='house'; data.players.companion.presence.activeHouseDoor=1
            req,reason=authority:prepareRequest('host','inventory.give',args)
            assert(not req and reason=='recipient_unavailable')
            data.players.companion.presence=nil
            local other=data.players.companion
            for i=1,other.inventoryCapacity do other.inventory[i]='apple' end
            req,reason=authority:prepareRequest('host','inventory.give',args)
            assert(not req and reason=='recipient_full' and Items.get(data,nil,ref).id==before)
            other.inventory[1]=nil; args.sourceItem.id='wrong-instance'
            req,reason=authority:prepareRequest('host','inventory.give',args)
            assert(not req and reason=='stale_item' and Items.get(data,nil,ref).id==before)
            authority:disconnect('companion',1)
            req,reason=authority:prepareRequest('host','ammo.give',{recipient='companion',ammo='22lr',amount=1})
            assert(not req and reason=='recipient_offline')
        ''')

    def test_failed_checkpoint_holds_transfer_and_retry_commits_it_once(self):
        self.lua.execute('''
            local canSave=true; local saved
            authority=require('game.coop_authority').new({campaign=data,sessionId='give-save',checkpoint=function(value)
                if not canSave then return false end; saved=assert(Schema.copy(value)); return true
            end})
            require('game.coop_sharing').install(authority,{catalog=Catalog,actorState=function(id) return states[id] end})
            authority:admit('companion',1)
            data.ammo['22lr']=20; data.players.companion.ammo['22lr']=0; assert(authority:checkpointNow())
            local req=request('host','ammo.give',{recipient='companion',ammo='22lr',amount=7})
            canSave=false; local reply=run('host',req)
            assert(reply.ok and reply.savePending and not reply.durable)
            assert(data.ammo['22lr']==13 and data.players.companion.ammo['22lr']==7)
            assert(saved.ammo['22lr']==20 and saved.players.companion.ammo['22lr']==0)
            canSave=true; assert(authority:retryCheckpoint()); reply=run('host',req)
            assert(reply.ok and reply.durable and saved.ammo['22lr']==13 and saved.players.companion.ammo['22lr']==7)
            assert(run('host',req).durable and data.players.companion.ammo['22lr']==7)
        ''')
