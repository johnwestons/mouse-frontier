"""Detached merchant UI, immutable quotes, actor identity and host outcomes."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestTradeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Catalog=require('game.catalog'); Players=require('game.coop_players'); Items=require('game.item_instances')
            Trade=require('game.merchant_trade'); Access=require('game.coop_merchant_access')
            data=F.campaign(20); assert(F.enroll(data)); data.scene='stop'; data.scrap=200; data.currentNPC='crow-merchant.png'
            data.stopLayouts['20']={npcOffers={['crow-merchant.png']='trade'},tradeStock={'bean-tin','field-bandage-roll'},tradeBudget=40}
            data.players.companion.inventory[1]='cowboy-hat'; assert(require('game.coop_entities').ensure(data)); assert(Items.ensure(data))
            copy=assert(Schema.copy(data)); runtime={saveData=Players.forActor(copy,'companion'),state='game',scene='stop',
                player={x=200,y=250},npcActor={x=210,y=250}}
            requests={}; allowed=true; neutral=0; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},ready=true,epoch=data.coop.sceneEpoch,mobile={enabled=false},inventory={},
                controller={network=network},neutralize=function() neutral=neutral+1 end,actionsAllowed=function() return allowed end}
            panel=require('game.coop_guest_trade').new(view,{catalog=Catalog,colors={}})
            love={keyboard={isDown=function() return false end}}
            function open() assert(panel:open()); assert(runtime.tradeOpen) end
            function result(id,details,revision)
                network.lastCommandResult={requestId=id,command=requests[id].name,ok=true,durable=true,revision=revision or copy.coop.revision,details=details}
            end
            function caravan()
                local Caravans=require('game.crow_caravans'); data.crowCaravans={}
                local root=assert(Caravans.ensureSchedule(data,{rng=function() return .5 end}))
                data.location=root.scheduledStops[1]; data.scene='caravan'
                camp=assert(Caravans.ensureCamp(data,Catalog,data.location,{rng=function() return .5 end})); root.activeCampId=camp.id
                data.droppedItems={{name='mailbox-reward',mailbox=true,scene='train',storage={}}}
                assert(require('game.coop_entities').ensure(data)); assert(Items.ensure(data))
                copy=Schema.copy(data); runtime.saveData=Players.forActor(copy,'companion'); runtime.scene='caravan'
                runtime.player.x=286; runtime.player.y=385; return copy.crowCaravans.camps[tostring(data.location)]
            end
        ''')

    def test_open_and_quote_are_read_only_and_confirmation_sends_the_displayed_price(self):
        self.lua.execute('''
            local Relationships=require('game.npc_relationships'); local original=Relationships.ensure
            Relationships.ensure=function() error('guest normalized relationships') end
            copy.relationships=nil; open(); assert(not copy.relationships)
            assert(panel:buy(1)); local quoted=panel.quote.args.quotedPrice; assert(#requests==0 and neutral==1)
            copy.goodwill=100; copy.stopLayouts['20'].tradeStock[1]='water-bottle'
            panel:update(); assert(panel.quote.args.quotedItem=='bean-tin' and panel.quote.args.quotedPrice==quoted)
            assert(panel:confirm()); local r=requests[1]
            assert(r.name=='merchant.buy' and r.args.quotedPrice==quoted and r.args.quotedItem=='bean-tin')
            assert(r.expected.resources==0 and r.expected.relationships==0 and r.expected['player:companion']==0)
            assert(r.expected['entity:'..panel.targetId]==0 and neutral==2 and panel.pending and not panel.quote)
            assert(copy.scrap==200 and data.scrap==200 and not data.players.companion.inventory[2])
            Relationships.ensure=original
        ''')

    def test_stale_drawn_sale_keeps_its_selected_item_identity(self):
        self.lua.execute('''
            data.players.companion.inventory[1]='frontier-short-sword'; assert(Items.ensure(data))
            copy=Schema.copy(data); runtime.saveData=Players.forActor(copy,'companion')
            open(); local selected=require('game.coop_item_contract').selection(runtime.saveData,nil,{kind='inventory',index=1})
            panel.sales={[1]={item=selected,expected=Access.expected(runtime.saveData,'companion',panel:source(),'merchant.sell')}}
            Items.assign(runtime.saveData,nil,{kind='inventory',index=1},'frontier-short-sword')
            assert(runtime.saveData.itemSlots.inventory[1].id~=selected.id)
            assert(panel:sell(1)); assert(requests[1].args.sourceItem.id==selected.id)
            network.lastCommandResult={requestId=1,ok=false,reason='stale_item'}; panel:update()
            assert(not panel.pending and runtime.tradeMessage:find('selected item changed',1,true))
            assert(data.players.companion.itemSlots.inventory[1].id==selected.id)
        ''')

    def test_pending_save_and_projection_delay_block_new_commands_without_prediction(self):
        self.lua.execute('''
            open(); assert(panel:buy(1) and panel:confirm()); local original=copy.scrap
            network.lastCommandResult={requestId=1,ok=true,savePending=true,revision=copy.coop.revision}
            panel:update(); assert(panel.pending and not panel:sell(1) and #requests==1 and copy.scrap==original)
            result(1,{item='bean-tin',price=8,delivery='inventory'},copy.coop.revision+1); panel:update()
            assert(panel.pending and runtime.tradeMessage=='Updating trade...')
            copy.coop.revision=copy.coop.revision+1; copy.scrap=original-8; panel:update()
            assert(not panel.pending and runtime.tradeMessage=='Bought Bean Tin for 8 scrap.')
        ''')

    def test_invalid_reach_closes_only_local_panel_and_preserves_pending_receipt(self):
        self.lua.execute('''
            open(); assert(panel:sell(1)); runtime.player.x=900; panel:update()
            assert(not runtime.tradeOpen and panel.pending and #requests==1)
            result(1,{item='cowboy-hat',price=4}); panel:update()
            assert(not panel.pending and panel.notice=='Sold Cowboy Hat for 4 scrap.' and data.scene=='stop')
            runtime.player.x=200; open(); view.epoch=view.epoch+1; panel:update(); assert(not runtime.tradeOpen)
        ''')

    def test_merchant_removal_and_role_availability_prevent_open(self):
        self.lua.execute('''
            allowed=false; assert(not panel:open() and not runtime.tradeOpen)
            allowed=true; view.inventory.pending={id=1}; assert(not panel:open()); view.inventory.pending=nil
            copy.stopLayouts['20'].npcOffers[data.currentNPC]='other'; assert(not panel:open())
            copy.stopLayouts['20']=nil; assert(not panel:open() and data.stopLayouts['20'])
        ''')

    def test_caravan_readers_never_create_history_resale_or_mailbox_storage(self):
        self.lua.execute('''
            caravan(); local target
            for _,record in ipairs(require('game.coop_entities').records(copy)) do if record.kind=='caravan' then target=record.value end end
            target.purchaseHistory=nil; target.resaleStock=nil; copy.relationships=nil; copy.droppedItems[1].storage=nil
            for i=1,runtime.saveData.inventoryCapacity do runtime.saveData.inventory[i]='cowboy-hat' end
            open(); local source=panel:source(); assert(source.readOnly and not source.onSale and not source.spendBudget)
            for index in ipairs(source.stock) do Trade.canBuy(runtime.saveData,Catalog,source,index) end
            Trade.availableBudget(runtime.saveData,source); Trade.sellPrice(runtime.saveData,Catalog,source,1)
            assert(not target.purchaseHistory and not target.resaleStock and not copy.relationships and not copy.droppedItems[1].storage)
            assert(Trade.buy(runtime.saveData,Catalog,source,1).reason=='read_only' and Trade.sell(runtime.saveData,Catalog,source,1).reason=='read_only')
            assert(copy.scrap==200)
        ''')

    def test_caravan_stable_listing_and_command_specific_revision_scopes(self):
        self.lua.execute('''
            caravan(); for index=1,runtime.saveData.inventoryCapacity do runtime.saveData.inventory[index]='cowboy-hat' end
            open(); local source=panel:source(); local selected
            for index,entry in ipairs(source.stock) do if not Catalog.ammoPickupAmounts[entry.item] then selected=index; break end end
            assert(panel:buy(selected)); local listing=source.stock[selected].id
            assert(panel.quote.args.listingId==listing)
            local mailbox=copy.droppedItems[1]; assert(panel.quote.expected['entity:'..mailbox.entityId]==0)
            panel.quote=nil; assert(panel:sell(1))
            assert(not requests[1].args.listingId and not requests[1].expected['entity:'..mailbox.entityId])
            result(1,{item='cowboy-hat',price=4}); panel:update()
            assert(panel:buy(selected) and panel:confirm()); assert(requests[2].args.listingId==listing)
        ''')

    def test_local_cancel_keyboard_controller_keys_and_touch_rects_emit_only_once(self):
        self.lua.execute('''
            open(); view.ui.tradeBuy={[1]={x=10,y=20,w=40,h=30,enabled=true}}
            panel:press(20,25); assert(panel.quote and #requests==0)
            panel:keypressed('escape'); assert(not panel.quote and runtime.tradeOpen and #requests==0)
            panel:press(20,25); view.ui.guestTradeConfirm={x=100,y=100,w=100,h=50,enabled=true}
            view.ui.guestTradeCancel={x=210,y=100,w=100,h=50,enabled=true}
            panel:press(120,120); panel:press(120,120); assert(#requests==1 and panel.pending)
            panel:keypressed('escape'); assert(not runtime.tradeOpen and panel.pending)
        ''')

    def test_public_trade_results_are_bounded_and_strip_internal_data(self):
        self.lua.execute('''
            local Results=require('game.net.item_results'); local Wire=require('game.net.commands'); local P=require('game.net.protocol')
            local value=assert(Results.project('merchant.buy',{ok=true,item='rocks',name='rocks',price=4,delivery='ammo',amount=12,private={save='secret'}}))
            assert(not value.name and not value.ok and not value.private and value.amount==12)
            assert(not Results.valid('merchant.buy',{item='rocks',price=4,delivery='ammo'}))
            assert(not Results.valid('merchant.sell',{item='cowboy-hat',price=-2}))
            assert(not Results.valid('merchant.sell',{item='cowboy-hat',price=3,actor='host'}))
            local reply=assert(Wire.outcome('s',1,{ok=true,durable=true,revision=2,result={item='rocks',price=4,delivery='ammo',amount=12}},'merchant.buy'))
            assert(Wire.result(reply) and #assert(P.encode(reply,P.CONTROL))<=1200)
        ''')


if __name__ == '__main__':
    unittest.main()
