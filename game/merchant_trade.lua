local Inventory = require("game.inventory")
local Relationships = require("game.npc_relationships")

local MerchantTrade = {}

local function merchantFor(source)
    return source and (source.relationshipId or source.merchant) or nil
end

local function budgetOwner(source)
    return source and (source.budgetOwner or source) or nil
end

local function budgetKey(source)
    return source and source.budgetKey or "budget"
end

function MerchantTrade.stockItem(source,index)
    local entry=source and source.stock and source.stock[index]
    if type(entry)=="table" then
        if (tonumber(entry.quantity) or 0)<=0 then return nil,entry end
        return entry.item or entry.name,entry
    end
    return entry,nil
end

local function findMailboxSpace(data,catalog)
    for _,item in ipairs(data.droppedItems or {}) do
        if item.name=="mailbox-reward" and item.scene=="train" and item.mailbox then
            item.storage=type(item.storage)=="table" and item.storage or {}
            local capacity=(catalog.storageCapacities and catalog.storageCapacities[item.name]) or 20
            for index=1,capacity do
                if item.storage[index]==nil then return item,index end
            end
        end
    end
end

function MerchantTrade.stopSource(layout,merchant,title)
    if type(layout)~="table" then return nil end
    layout.tradeStock=type(layout.tradeStock)=="table" and layout.tradeStock or {}
    return {
        kind="stop",
        title=title,
        merchant=merchant,
        relationshipId=merchant,
        stock=layout.tradeStock,
        budgetOwner=layout,
        budgetKey="tradeBudget",
        allowGifts=true,
        directAmmo=false,
        mailboxOverflow=false,
    }
end

function MerchantTrade.terms(data,source)
    return Relationships.merchantTerms(data,merchantFor(source))
end

function MerchantTrade.availableBudget(data,source)
    local terms=MerchantTrade.terms(data,source)
    if source and type(source.availableBudget)=="function" then
        return math.max(0,tonumber(source.availableBudget(terms)) or 0)
    end
    local owner=budgetOwner(source)
    local base=owner and tonumber(owner[budgetKey(source)]) or 0
    return math.max(0,(base or 0)+terms.budgetBonus)
end

function MerchantTrade.buyPrice(data,catalog,source,index)
    local name,entry=MerchantTrade.stockItem(source,index)
    if not name then return nil end
    return Relationships.buyPrice(data,merchantFor(source),tonumber(entry and entry.basePrice) or Inventory.scrapPrice(name,catalog))
end

function MerchantTrade.sellPrice(data,catalog,source,index)
    local name=data.inventory and data.inventory[index]
    if not name then return nil end
    return Relationships.sellPrice(data,merchantFor(source),Inventory.resalePrice(name,catalog,data))
end

function MerchantTrade.deliveryTarget(data,catalog,source,name,entry)
    if not name then return nil end
    if source and (source.directAmmo or (entry and entry.delivery=="ammo")) and catalog.ammoPickupAmounts and catalog.ammoPickupAmounts[name] then
        return "ammo"
    end
    local slot=Inventory.firstEmptySlot(data)
    if slot then return "inventory",slot end
    if source and source.mailboxOverflow then
        local mailbox,index=findMailboxSpace(data,catalog)
        if mailbox then return "train",index,mailbox end
    end
    return nil
end

function MerchantTrade.canBuy(data,catalog,source,index)
    local price=MerchantTrade.buyPrice(data,catalog,source,index)
    if not price or (tonumber(data.scrap) or 0)<price then return false,nil,price end
    local name,entry=MerchantTrade.stockItem(source,index)
    local target=MerchantTrade.deliveryTarget(data,catalog,source,name,entry)
    return target~=nil,target,price
end

function MerchantTrade.buy(data,catalog,source,index)
    if type(source)~="table" or type(source.stock)~="table" then return {ok=false,reason="source"} end
    local name,entry=MerchantTrade.stockItem(source,index)
    if not name then return {ok=false,reason="sold"} end
    local affordable,target,price=MerchantTrade.canBuy(data,catalog,source,index)
    if not affordable then
        return {ok=false,reason=(tonumber(data.scrap) or 0)<(price or math.huge) and "scrap" or "space",price=price,name=name}
    end
    local _,slot,mailbox=MerchantTrade.deliveryTarget(data,catalog,source,name,entry)
    data.scrap=(tonumber(data.scrap) or 0)-price
    if target=="ammo" then
        data.ammo=type(data.ammo)=="table" and data.ammo or {}
        local amount=catalog.ammoPickupAmounts[name]
        data.ammo[name]=(data.ammo[name] or 0)+amount
    elseif target=="inventory" then
        data.inventory[slot]=name
    elseif target=="train" then
        mailbox.storage[slot]=name
        mailbox.mailUnread=true
    end
    if entry then entry.quantity=math.max(0,(tonumber(entry.quantity) or 1)-1)
    else source.stock[index]=nil end
    Relationships.recordTrade(data,merchantFor(source))
    if type(source.onPurchase)=="function" then source.onPurchase(index,name,target,entry) end
    return {ok=true,name=name,price=price,delivery=target}
end

function MerchantTrade.sell(data,catalog,source,index)
    if type(source)~="table" then return {ok=false,reason="source"} end
    local name=data.inventory and data.inventory[index]
    if not name then return {ok=false,reason="item"} end
    local price=MerchantTrade.sellPrice(data,catalog,source,index)
    if MerchantTrade.availableBudget(data,source)<price then return {ok=false,reason="budget",name=name,price=price} end
    if type(source.spendBudget)=="function" then
        local spent=source.spendBudget(price,MerchantTrade.terms(data,source))
        if spent==false then return {ok=false,reason="budget",name=name,price=price} end
    else
        local owner=budgetOwner(source)
        local key=budgetKey(source)
        owner[key]=(tonumber(owner[key]) or 0)-price
    end
    data.scrap=(tonumber(data.scrap) or 0)+price
    data.inventory[index]=nil
    Relationships.recordTrade(data,merchantFor(source))
    if type(source.onSale)=="function" then source.onSale(index,name,price) end
    return {ok=true,name=name,price=price}
end

function MerchantTrade.audit(catalog)
    local data={scrap=20,inventory={[1]="food-ration"},inventoryCapacity=1,ammo={rocks=0},droppedItems={
        {name="mailbox-reward",scene="train",mailbox=true,storage={}},
    },relationships={},goodwill=0}
    local source={merchant="crow-merchant.png",relationshipId="crow-merchant.png",stock={"rocks"},budget=20,directAmmo=true}
    local buy=MerchantTrade.buy(data,catalog,source,1)
    local mailSource={merchant="crow-caravan",relationshipId="crow-caravan",stock={"food-ration"},budget=20,mailboxOverflow=true}
    local mail=MerchantTrade.buy(data,catalog,mailSource,1)
    local ordinarySource={merchant="merchant.png",relationshipId="merchant.png",stock={"food-ration"},budget=20}
    local ordinary=MerchantTrade.buy(data,catalog,ordinarySource,1)
    local saleSource={merchant="crow-merchant.png",relationshipId="crow-merchant.png",stock={},budget=20}
    local sale=MerchantTrade.sell(data,catalog,saleSource,1)
    return {ready=buy.ok and buy.delivery=="ammo" and data.ammo.rocks==(catalog.ammoPickupAmounts.rocks or 0)
        and mail.ok and mail.delivery=="train" and not ordinary.ok and ordinary.reason=="space"
        and sale.ok and saleSource.budget<20,curve="merchant-trade-v1"}
end

return MerchantTrade
