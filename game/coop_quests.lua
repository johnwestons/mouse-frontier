local Players=require("game.coop_players")
local Inventory=require("game.inventory")
local Help=require("game.stop_help_progression")
local Progression=require("game.quest_progression")
local Loot=require("game.loot_progression")
local Train=require("game.train_upgrade_balance")
local Battle=require("game.battle_rules")
local House=require("game.house")
local Random=require("game.coop_random")
local Access=require('game.coop_quest_access')
local Contract=require('game.coop_item_contract')
local P=require('game.net.protocol')
local Commands={}

local function fields(args,allowed)
    for key in pairs(args) do if not allowed[key] then return false end end
    return true
end
local function recipient(data,actorId,args,context)
    local found=Access.recipient(Players.forActor(data,actorId),context.actorState(actorId),args.targetId,args.npc)
    if not found then return nil,'recipient_unavailable' end
    return found.target
end

function Commands.install(authority,context)
    local catalog=context.catalog
    authority:register("quest.help",function(data,actorId,args)
        if not fields(args,{targetId=true,npc=true,source=true,selected=true}) then return nil,"invalid_args" end
        local target,reason=recipient(data,actorId,args,context); if not target then return nil,reason end
        local actor=Players.forActor(data,actorId)
        local request,quest=Access.itemQuest(actor,target,args.npc)
        if not request then return nil,'quest_unavailable' end
        if actorId~='host' and (args.source==nil or args.selected==nil) then return nil,'item_selection_required' end
        local slot
        if args.source~=nil then
            if not P.fields(args.source,{kind=true,index=true}) or args.source.kind~='inventory'
                or not P.integer(args.source.index,1,actor.inventoryCapacity) then return nil,'invalid_args' end
            slot=args.source.index
            if actor.inventory[slot]~=request.item or not Contract.matches(args.selected,actor,nil,args.source) then return nil,'item_changed' end
        end
        return {scopes={"entity:"..target.entityId,"quest:"..quest.id,"player:"..actorId,"relationships"},apply=function()
            local result=Help.completeItem(actor,request,args.npc,data.location,slot)
            return {ok=true,completed=result.completed,gained=result.gained,total=result.total,missing=result.missing,label=result.label,item=result.item}
        end}
    end)

    authority:register("quest.deliver",function(data,actorId,args,transaction)
        if not fields(args,{targetId=true,npc=true,questId=true}) then return nil,"invalid_args" end
        local target,reason=recipient(data,actorId,args,context); if not target then return nil,reason end
        local actor=Players.forActor(data,actorId)
        local quest,kind=Access.delivery(actor,args.questId,args.npc)
        if not quest then return nil,kind end
        -- These two existing arrays contain accepted routine deliveries only.
        -- Explicit story markers are deny-by-default for guest assistance.
        local rewardKind=kind=='mailQuest' and 'mail' or quest.cargoKind or 'food'
        local reward=Progression.rollReward(catalog,Loot,rewardKind,quest.origin,quest.destination,actor.trait,Random.generator(data,transaction.randomSeed))
        local recipientIds={}
        for _,id in ipairs({Players.HOST,Players.COMPANION}) do
            local state=context.actorState(id)
            if authority.bindings[id]~=nil and state and state.screen=="game" and state.scene==data.scene then
                recipientIds[#recipientIds+1]=id
            end
        end
        local scopes=Access.scopes(actor,actorId,'quest.deliver',quest,args.targetId,catalog,recipientIds)
        return {scopes=scopes,apply=function()
            if kind=='supplyQuest' then
                local cargo=Progression.consumeCargo(actor,catalog,quest)
                if not cargo.completed then return nil,"cargo_unavailable" end
            end
            local coal=Train.addResource(data,"coal",reward.coal)
            local overflow=math.max(0,reward.coal-coal)
            data.scrap=(data.scrap or 0)+reward.scrap+overflow
            reward.coalAdded=coal; reward.scrapAdded=reward.scrap+overflow; reward.coalConverted=overflow
            reward.levels=0; reward.recipientId=actorId
            quest.rewardRecipients={}
            for _,id in ipairs(recipientIds) do
                local levels=Battle.gainExperience(Players.forActor(data,id),reward.xp)
                quest.rewardRecipients[id]=reward.xp
                if id==actorId then reward.levels=levels end
            end
            reward.delivery=Progression.storeRewardItem(actor,catalog,Inventory,reward.item,function(name)
                House.storeLoot(data,catalog,name,data.location)
            end)
            reward.amount=reward.delivery=='ammunition' and catalog.ammoPickupAmounts[reward.item] or nil
            local gained,total=Help.add(data,1,rewardKind,args.npc,data.location)
            quest.complete=true; quest.rewardItem=reward.item; quest.completedBy=actorId
            return {ok=true,completed=true,reward=reward,gained=gained,total=total,recipients=quest.rewardRecipients}
        end}
    end)
end
return Commands
