"""Trade-only furniture acquisition, depleted-stock persistence and furnishing use.

Save roundtrips use the production serializer with an in-memory filesystem.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


HARNESS = r'''
package.path=project_root..'/?.lua;'..package.path
files={}
love={math={random=function(low,high)
    if high then return low end
    if low then return 1 end
    return .25
end},filesystem={
    getInfo=function(path) return files[path] and {type='file'} end,
    createDirectory=function() return true end,
    write=function(path,contents) files[path]=contents; return true end,
    read=function(path) return files[path] end,
    load=function(path) return loadstring(files[path] or '',path) end,
    remove=function(path) files[path]=nil; return true end,
}}
Catalog=require('game.catalog')
Furniture=require('game.furniture_catalog')
Loot=require('game.loot_progression')
Trade=require('game.merchant_trade')
Inventory=require('game.inventory')
Schema=require('game.save_schema')
Save=require('game.save')

function campaign(stop)
    return assert(Schema.migrate({character='scout-frog.png',location=stop or 1,
        inventory={},inventoryCapacity=6,equipment={},scrap=1000,activeCar=1,
        droppedItems={},stopLayouts={},npcRoster={'crow-merchant.png'}}))
end

function roundtrip(data)
    assert(Save.write(99,data))
    return assert(Save.read(99))
end

function furnitureOffers(stock)
    local found={}
    for index,entry in pairs(stock) do
        local name=type(entry)=='table' and entry.item or entry
        if Furniture.isFurniture(name) then found[#found+1]={index=index,name=name,entry=entry} end
    end
    table.sort(found,function(a,b) return a.index<b.index end)
    return found
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class FurnitureTradeBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def test_catalog_covers_every_furniture_sprite_with_a_positive_price(self) -> None:
        furniture = self.lua.globals().Furniture
        sprite_names = {path.stem for path in (ROOT / "assets/sprites/furniture").glob("*.png")}
        self.assertEqual(set(furniture.names.values()), sprite_names)
        self.assertEqual(set(furniture["items"].keys()), sprite_names)
        self.assertEqual(set(furniture.prices.keys()), sprite_names)
        self.lua.execute(r'''
            for _,name in ipairs(Furniture.names) do
                assert(Furniture.isFurniture(name) and Catalog.furnitureItems[name])
                local price=Loot.itemPrice(Catalog,name)
                assert(price==Furniture.prices[name] and price>0 and price==math.floor(price))
                assert(Loot.resalePrice(Catalog,name)<price,'reselling cannot fund a duplicate '..name)
            end
            assert(Loot.itemPrice(Catalog,'single-bed')>Loot.itemPrice(Catalog,'round-stool'))
            assert(Loot.itemPrice(Catalog,'round-stool')>Loot.itemPrice(Catalog,'coal-chunk'))
            assert(not Furniture.isFurniture('wooden-spoon') and not Furniture.isFurniture('food-ration'))
        ''')

    def test_rotating_trade_stock_makes_every_furnishing_available_without_loot(self) -> None:
        self.lua.execute(r'''
            local seen={}
            for stop=1,50 do
                local stock=Loot.tradeStock(Catalog,stop,function() return .25 end)
                local offers=furnitureOffers(stock)
                assert(#offers==4,'every ordinary trader needs four furnishing offers')
                local unique={}
                for _,offer in ipairs(offers) do
                    assert(not unique[offer.name]); unique[offer.name]=true; seen[offer.name]=true
                    assert(offer.entry.quantity==1 and offer.entry.basePrice==Loot.itemPrice(Catalog,offer.name))
                end
                assert(stock[1] and stock[2] and stock[3] and stock[4],'furnishings must not replace supplies or equipment')
                local layout={tradeStock=stock}
                Loot.ensureFurnitureStock(layout,Catalog,stop)
                assert(#furnitureOffers(stock)==4,'first stop visit must not duplicate generated offers')
            end
            for _,name in ipairs(Furniture.names) do assert(seen[name],'unobtainable furnishing '..name) end
            for _,pool in pairs(Catalog.lootPools) do
                for _,name in ipairs(pool) do assert(not Furniture.isFurniture(name),'furniture in generic loot') end
            end
            for _,pool in pairs(Catalog.householdItemPools) do
                for _,name in ipairs(pool) do assert(not Furniture.isFurniture(name),'furniture in household salvage') end
            end
            for _,name in ipairs(Catalog.questRewardItems) do assert(not Furniture.isFurniture(name),'furniture in quest rewards') end
        ''')

    def test_generic_reward_rolls_reject_furniture_even_if_a_pool_contains_it(self) -> None:
        self.lua.execute(r'''
            for _,name in ipairs(Furniture.names) do
                Catalog.lootPools.common={name,'coal-chunk'}
                local item=Loot.rollItem(Catalog,1,{allowWeapon=false,rng=function() return 0 end})
                assert(item=='coal-chunk','generic salvage awarded purchasable furniture '..name)
            end
        ''')

    def test_existing_trader_adds_stock_once_and_save_load_never_restocks_sold_items(self) -> None:
        self.lua.execute(r'''
            local data=campaign(1)
            local original={item='field-bandage-roll',quantity=0,basePrice=6}
            local layout={tradeStock={[2]='coal-chunk',[9]=original},tradeBudget=40}
            data.stopLayouts['1']=layout
            Loot.ensureFurnitureStock(layout,Catalog,1)
            local offers=furnitureOffers(layout.tradeStock)
            assert(#offers==4 and offers[1].index==10)
            assert(layout.tradeStock[2]=='coal-chunk' and layout.tradeStock[9]==original and original.quantity==0)
            local source=Trade.stopSource(layout,'crow-merchant.png')
            local index=offers[1].index
            local before=data.scrap
            local bought=Trade.buy(data,Catalog,source,index)
            assert(bought.ok and data.inventory[1]==offers[1].name and data.scrap==before-bought.price)
            assert(layout.tradeStock[index].quantity==0)
            assert(Trade.buy(data,Catalog,source,index).reason=='sold' and data.scrap==before-bought.price)
            data=roundtrip(data); layout=data.stopLayouts['1']
            Loot.ensureFurnitureStock(layout,Catalog,1)
            assert(layout.furnitureStockVersion==1 and #furnitureOffers(layout.tradeStock)==4)
            assert(layout.tradeStock[index].quantity==0 and layout.tradeStock[9].quantity==0)
            assert(data.inventory[1]==offers[1].name)
            local other={tradeStock={}}
            Loot.ensureFurnitureStock(other,Catalog,2)
            assert(#furnitureOffers(other.tradeStock)==4,'a different trader keeps its own offers')
        ''')

    def test_stop_entry_upgrades_existing_merchant_without_replacing_prior_stock(self) -> None:
        self.lua.execute(r'''
            local data=campaign(20)
            data.stopLayouts['20']={npcOutside='crow-merchant.png',npcInside='crow-merchant.png',
                npcOffers={['crow-merchant.png']='trade'},tradeStock={[1]='coal-chunk'},tradeBudget=40}
            local Stops=require('game.stops')
            local layout=Stops.ensure(data,Catalog,'stop',function() return .25 end)
            assert(layout.tradeStock[1]=='coal-chunk' and #furnitureOffers(layout.tradeStock)==4)
            local offer=furnitureOffers(layout.tradeStock)[1]; offer.entry.quantity=0
            Stops.ensure(data,Catalog,'stop',function() return .75 end)
            assert(#furnitureOffers(layout.tradeStock)==4 and layout.tradeStock[offer.index].quantity==0)
        ''')

    def test_every_purchased_furnishing_can_be_placed_recovered_and_resold_without_duplication(self) -> None:
        self.lua.execute(r'''
            for _,name in ipairs(Furniture.names) do
                local data=campaign(1)
                local source={merchant='crow-merchant.png',stock={{item=name,quantity=1,basePrice=Loot.itemPrice(Catalog,name)}},budget=1000}
                local bought=Trade.buy(data,Catalog,source,1)
                assert(bought.ok and data.inventory[1]==name)
                local runtime={saveData=data,scene='train',player={x=400,y=420}}
                local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,catalog=Catalog,
                    util=require('game.util'),trainUpgradeBalance=require('game.train_upgrade_balance'),lootProgression=Loot,
                    writeSave=function() end,useBattleHealingItem=function() return false end,useBattlePotion=function() return false end})
                assert(actions.dropFromContainer({kind='inventory',index=1}))
                local placed=data.droppedItems[1]
                assert(not data.inventory[1] and #data.droppedItems==1 and placed.name==name)
                assert(placed.scene=='train' and placed.carIndex==1 and placed.droppedByPlayer)
                if Catalog.storageCapacities[name] then assert(type(placed.storage)=='table' and not next(placed.storage)) end
                data=roundtrip(data); runtime.saveData=data; runtime.nearbyItem=1
                actions.pickUpNearby()
                assert(data.inventory[1]==name and #data.droppedItems==0,'placed purchase could not be recovered: '..name)
                local sold=Trade.sell(data,Catalog,source,1)
                assert(sold.ok and sold.price<bought.price and not data.inventory[1])
                assert(source.stock[1].quantity==0 and Trade.buy(data,Catalog,source,1).reason=='sold')
                assert(data.scrap==1000-bought.price+sold.price,'furnishing trade generated scrap')
            end
        ''')


if __name__ == "__main__":
    unittest.main()
