local Players=require("game.coop_players")
local Trade=require("game.merchant_trade")
local Access=require("game.coop_merchant_access")
local Contract=require("game.coop_item_contract")
local Commands={}

function Commands.install(authority,context)
    local catalog=assert(context.catalog)
    for _,name in ipairs({"merchant.buy","merchant.sell"}) do
        local command=name
        authority:register(command,function(data,actorId,args)
            for key in pairs(args) do
                if key~="targetId" and key~="merchantId" and key~="index" and key~="listingId"
                    and key~="quotedPrice" and key~="quotedItem" and key~="sourceItem" then return nil,"invalid_arguments" end
            end
            if type(args.targetId)~="string" or type(args.merchantId)~="string"
                or type(args.index)~="number" or args.index~=math.floor(args.index) or args.index<1 or args.index>10000
                or (args.listingId~=nil and type(args.listingId)~="string") then return nil,"invalid_arguments" end
            local actor=Players.forActor(data,actorId)
            local state=context.actorState(actorId)
            if not state or state.traveling or state.changingCar or state.encounterActive or state.activityBlocked
                or (tonumber(actor.health) or 0)<=0 then return nil,"unavailable" end
            local source,reason=Access.find(data,args.targetId,args.merchantId,state,catalog)
            if not source then return nil,reason end
            local index=args.index
            if source.kind=="caravan" and command=="merchant.buy" then
                if not args.listingId then return nil,"listing_required" end
                index=nil
                for candidate,listing in ipairs(source.stock) do if listing.id==args.listingId then index=candidate; break end end
                if not index then return nil,"sold" end
            elseif args.listingId~=nil then return nil,"invalid_arguments" end
            if command=="merchant.sell" and index>actor.inventoryCapacity then return nil,"invalid_slot" end
            if command=="merchant.sell" then
                if not Contract.matches(args.sourceItem,actor,nil,{kind='inventory',index=index}) then return nil,'stale_item' end
            elseif args.sourceItem~=nil then return nil,'invalid_arguments' end
            if args.quotedPrice~=nil or args.quotedItem~=nil then
                if command~="merchant.buy" or type(args.quotedPrice)~="number" or args.quotedPrice~=args.quotedPrice
                    or args.quotedPrice<0 or args.quotedPrice>1e9 or type(args.quotedItem)~="string" then return nil,"invalid_arguments" end
                -- A quote is an expectation, not a client-supplied cost. Never
                -- silently charge a different price after a confirmation.
                local item=Trade.stockItem(source,index)
                local price=Trade.buyPrice(actor,catalog,source,index)
                if item~=args.quotedItem or price~=args.quotedPrice then return nil,"quote_changed" end
            end
            local scopes={"player:"..actorId,"entity:"..source.targetId,"resources","relationships"}
            if command=="merchant.buy" and source.mailboxOverflow then
                local item,entry=Trade.stockItem(source,index)
                local _,_,mailbox=Trade.deliveryTarget(actor,catalog,source,item,entry)
                if mailbox then scopes[#scopes+1]="entity:"..mailbox.entityId end
            end
            return {scopes=scopes,apply=function()
                local result=command=="merchant.buy" and Trade.buy(actor,catalog,source,index) or Trade.sell(actor,catalog,source,index)
                if not result.ok then return nil,result.reason end
                return result
            end}
        end)
    end
end

return Commands
