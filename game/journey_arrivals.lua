-- Arrival rewards operate on the authority draft, with its random stream.
local Players=require("game.coop_players")
local Passengers=require("game.passengers")
local Train=require("game.train_upgrade_balance")
local Quest=require("game.quest_progression")
local Loot=require("game.loot_progression")
local Battle=require("game.battle_rules")
local Inventory=require("game.inventory")
local House=require("game.house")
local Help=require("game.stop_help_progression")
local Util=require("game.util")
local Identity=require('game.npc_identity')
local Arrivals={}
function Arrivals.apply(data,catalog,rng,participants)
    participants=participants or {"host"}
    local notes={}
    for _,passenger in ipairs(data.passengers) do
        local person=Identity.get(data,passenger); if person then person.lastStop=data.location end
        passenger.job=passenger.job or Passengers.jobFor(passenger.npc)
        local preferred=Train.owns(data,Passengers.preferredCarId(passenger.job))
        local contribution=Quest.passengerContribution(passenger.job,preferred); local amount
        if contribution.kind=="resource" then amount=Train.addResource(data,contribution.resource,contribution.amount)
        elseif contribution.kind=="health" then
            amount=0
            for _,id in ipairs(participants) do
                local actor=Players.get(data,id); local before=actor.health
                actor.health=math.min(actor.maxHealth,actor.health+contribution.amount); amount=amount+actor.health-before
            end
        else data.scrap=(data.scrap or 0)+contribution.amount; amount=contribution.amount end
        local gained=contribution.verb.." "..amount.." "..(contribution.kind=="health" and "health" or (contribution.kind=="scrap" and "scrap" or contribution.resource))
        notes[#notes+1]=Identity.name(data,passenger).." "..gained
    end
    if #notes>0 then data.arrivalNotice=table.concat(notes,". ").."." end
    local notices={}
    if data.arrivalNotice then notices[#notices+1]=data.arrivalNotice end
    for index=#data.passengers,1,-1 do
        local passenger=data.passengers[index]
        if data.location>=passenger.destination then
            Identity.arrive(data,passenger)
            table.remove(data.passengers,index)
            local origin=passenger.origin or math.max(1,(passenger.destination or data.location)-3)
            local reward=Quest.rollReward(catalog,Loot,"ride",origin,passenger.destination or data.location,data.trait,rng)
            local coal=Train.addResource(data,"coal",reward.coal)
            local overflow=math.max(0,reward.coal-coal)
            data.scrap=(data.scrap or 0)+reward.scrap+overflow
            local levels=0
            for _,id in ipairs(participants) do
                local gained=Battle.gainExperience(Players.forActor(data,id),reward.xp)
                if id=="host" then levels=gained end
            end
            local delivery=Quest.storeRewardItem(data,catalog,Inventory,reward.item,function(name) House.storeLoot(data,catalog,name,data.location) end)
            local item=Util.titleFromFile(reward.item)
            local delivered=delivery=="backpack" and item or (delivery=="ammunition" and (item.." ammunition") or (item.." in your "..delivery))
            local rewardText="+"..reward.xp.." XP, +"..coal.." coal, +"..(reward.scrap+overflow).." scrap, and "..delivered..(levels>0 and "  LEVEL UP!" or "")
            local _,goodwill=Help.add(data,1,"ride",passenger.characterId or passenger.npc,passenger.destination)
            notices[#notices+1]=Identity.name(data,passenger).." reached their stop: "..rewardText.." and +1 goodwill ("..goodwill.." total)."
        end
    end
    data.arrivalNotice=#notices>0 and table.concat(notices," ") or nil
end
return Arrivals
