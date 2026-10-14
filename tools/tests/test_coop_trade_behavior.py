"""Shared-wallet trading with real stop/caravan sources on staged campaigns."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopTradeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures')
            Schema=require('game.save_schema')
            Entities=require('game.coop_entities')
            Catalog=require('game.catalog')
            Trade=require('game.merchant_trade')
            data=Fixtures.campaign(20); assert(Fixtures.enroll(data))
            data.scene='stop'; data.scrap=200
            data.currentNPC='crow-merchant.png'
            layout={npcOffers={['crow-merchant.png']='trade'},tradeStock={'bean-tin','field-bandage-roll'},tradeBudget=40}
            data.stopLayouts['20']=layout
            guest=data.players.companion
            states={host={screen='game',scene='stop',x=200,y=250,npc={id=data.currentNPC,x=210,y=250}},
                companion={screen='game',scene='stop',x=200,y=250,npc={id=data.currentNPC,x=210,y=250}}}
            authority=require('game.coop_authority').new({campaign=data,sessionId='trade-test'})
            require('game.coop_trade').install(authority,{catalog=Catalog,actorState=function(id) return states[id] end})
            authority:admit('companion',1)
            function req(actor,command,args) return assert(authority:prepareRequest(actor,command,args)) end
            function run(actor,request) return authority:execute(actor,actor=='host' and 0 or 1,request) end
            function stopArgs(index) return {targetId=layout.entityId,merchantId=data.currentNPC,index=index} end
            function caravan()
                local Caravans=require('game.crow_caravans')
                data.crowCaravans={}
                local root=assert(Caravans.ensureSchedule(data,{rng=function() return .5 end}))
                data.location=root.scheduledStops[1]; data.scene='caravan'
                camp=assert(Caravans.ensureCamp(data,Catalog,data.location,{rng=function() return .5 end}))
                root.activeCampId=camp.id
                mailbox={name='mailbox-reward',scene='train',mailbox=true,storage={}}
                data.droppedItems={mailbox}; assert(Entities.ensure(data))
                for _,state in pairs(states) do state.scene='caravan'; state.x=286; state.y=385 end
                for index=1,guest.inventoryCapacity do guest.inventory[index]='cowboy-hat' end
                return camp
            end
        ''')

    def test_simultaneous_stop_purchase_and_replay_charge_once(self):
        self.lua.execute('''
            local price=Trade.buyPrice(data,Catalog,Trade.stopSource(layout,data.currentNPC),1)
            local host=req('host','merchant.buy',stopArgs(1))
            local friend=req('companion','merchant.buy',stopArgs(1))
            local result=run('companion',friend)
            assert(result.ok and data.scrap==200-price and guest.inventory[1]=='bean-tin')
            assert(data.inventory[1]=='orange-rose-vase' and layout.tradeStock[1]==nil)
            assert(run('host',host).reason=='stale_revision')
            assert(run('companion',friend).ok and data.scrap==200-price)
            local forged=req('host','merchant.buy',stopArgs(2)); forged.args.price=0
            assert(run('host',forged).reason=='invalid_arguments')
            local stale=req('host','merchant.buy',stopArgs(2))
            stale.args.quotedPrice=0; stale.args.quotedItem='field-bandage-roll'
            assert(run('host',stale).reason=='quote_changed' and layout.tradeStock[2]=='field-bandage-roll')
            assert(data.scrap==200-price)
        ''')

    def test_sale_spends_merchant_budget_and_only_the_sellers_item(self):
        self.lua.execute('''
            guest.inventory[1]='cowboy-hat'
            local source=Trade.stopSource(layout,data.currentNPC)
            local price=Trade.sellPrice(require('game.coop_players').forActor(data,'companion'),Catalog,source,1)
            local request=req('companion','merchant.sell',stopArgs(1))
            assert(run('companion',request).ok)
            assert(data.scrap==200+price and layout.tradeBudget==40-price)
            assert(guest.inventory[1]==nil and data.inventory[1]=='orange-rose-vase')
            local budget=layout.tradeBudget
            assert(run('companion',request).ok and layout.tradeBudget==budget)
            guest.inventory[1]='cowboy-hat'; states.companion.x=900
            assert(not authority:prepareRequest('companion','merchant.sell',stopArgs(1)))
            states.companion.x=200
            local wrong=stopArgs(1); wrong.merchantId='other-npc'
            assert(not authority:prepareRequest('companion','merchant.sell',wrong))
            assert(guest.inventory[1]=='cowboy-hat')
        ''')

    def test_caravan_mailbox_delivery_and_history_commit_together(self):
        self.lua.execute('''
            caravan()
            local source=Trade.caravanSource(data,Catalog,camp,'packmaster')
            local index,listing
            for i,entry in ipairs(source.stock) do
                if not Catalog.ammoPickupAmounts[entry.item] then index,listing=i,entry; break end
            end
            assert(listing)
            local args={targetId=camp.entityId,merchantId='packmaster',index=index,listingId=listing.id}
            local before=listing.quantity
            local request=req('companion','merchant.buy',args)
            local price=Trade.buyPrice(data,Catalog,source,index)
            local result=run('companion',request)
            assert(result.ok and result.result.delivery=='train' and mailbox.storage[1]==listing.item)
            assert(listing.quantity==before-1 and #camp.purchaseHistory==1)
            assert(data.crowCaravans.trades==1 and data.scrap==200-price)
            assert(run('companion',request).ok and #camp.purchaseHistory==1)
            assert(guest.inventory[1]=='cowboy-hat' and data.inventory[1]=='orange-rose-vase')
            local loaded=assert(Schema.migrate(data))
            assert(loaded.crowCaravans.trades==1 and loaded.droppedItems[1].storage[1]==listing.item)
        ''')

    def test_guest_availability_and_sale_identity_are_rechecked_without_charging(self):
        self.lua.execute('''
            local Players=require('game.coop_players'); local Contract=require('game.coop_item_contract'); local Items=require('game.item_instances')
            guest.inventory[1]='frontier-short-sword'; assert(Items.ensure(data))
            local args=stopArgs(1); args.sourceItem=Contract.selection(Players.forActor(data,'companion'),nil,{kind='inventory',index=1})
            local request=req('companion','merchant.sell',args)
            Items.assign(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'frontier-short-sword')
            assert(run('companion',request).reason=='stale_item' and data.scrap==200 and layout.tradeBudget==40)
            for _,flag in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                states.companion[flag]=true; assert(not authority:prepareRequest('companion','merchant.buy',stopArgs(1)))
                states.companion[flag]=nil
            end
            guest.health=0; assert(not authority:prepareRequest('companion','merchant.buy',stopArgs(1)))
            assert(data.scrap==200 and layout.tradeStock[1]=='bean-tin')
        ''')

    def test_caravan_callbacks_never_leak_when_transaction_fails(self):
        self.lua.execute('''
            caravan()
            local source=Trade.caravanSource(data,Catalog,camp,'packmaster')
            local listing=source.stock[1]
            local count=listing.quantity
            local request=req('companion','merchant.buy',{targetId=camp.entityId,merchantId='packmaster',index=1,listingId=listing.id})
            local original=Trade.buy
            Trade.buy=function(...)
                local result=original(...)
                assert(result.ok)
                return {ok=false,reason='test_failure_after_callback'}
            end
            local result=run('companion',request)
            Trade.buy=original
            assert(not result.ok and result.reason=='test_failure_after_callback')
            assert(data.scrap==200 and listing.quantity==count and next(mailbox.storage)==nil)
            assert(#camp.purchaseHistory==0 and not data.crowCaravans.trades)
            assert(guest.ammo.rocks==12)
        ''')


if __name__ == '__main__':
    unittest.main()
