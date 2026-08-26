local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"journey rules require "..name)
  if expectedType then assert(type(value)==expectedType,"journey rules "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","journey rules require an explicit context")
  local runtime=required(context,"runtime","table")
  local car=required(context,"car","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local ProgressionBalance=required(context,"progressionBalance","table")
  local CombatBalance=required(context,"combatBalance","table")
  local EventBalance=required(context,"eventBalance","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local QuestProgression=required(context,"questProgression","table")
  local LootProgression=required(context,"lootProgression","table")
  local BattleRules=required(context,"battleRules","table")
  local Maintenance=required(context,"maintenance","table")
  local Passengers=required(context,"passengers","table")
  local Util=required(context,"util","table")
  local House=required(context,"house","table")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local setupNPC=required(context,"setupNPC","function")
  local writeSave=required(context,"writeSave","function")
  local beginEncounter=required(context,"beginEncounter","function")
  local beginRequiredEvent=required(context,"beginRequiredEvent","function")
  local beginRandomEvent=required(context,"beginRandomEvent","function")

  local function travelCost()
      return ProgressionBalance.travelCost(runtime.saveData,EngineUpgrades,Maintenance,Catalog.characterTraitProfiles[1],TrainUpgradeBalance)
  end

  local function travelStatus()
      return ProgressionBalance.travelStatus(runtime.saveData,travelCost())
  end

  local function storeRewardItem(name)
      return QuestProgression.storeRewardItem(runtime.saveData,Catalog,Inventory,name,function(fallbackName)
          House.storeLoot(runtime.saveData,Catalog,fallbackName,runtime.saveData.location)
      end)
  end

  local function grantProgressionReward(kind,origin,destination)
      local reward=QuestProgression.rollReward(Catalog,LootProgression,kind,origin,destination,runtime.saveData.trait)
      local coal=TrainUpgradeBalance.addResource(runtime.saveData,"coal",reward.coal)
      local overflow=math.max(0,reward.coal-coal)
      runtime.saveData.scrap=(runtime.saveData.scrap or 0)+reward.scrap+overflow
      local levels=BattleRules.gainExperience(runtime.saveData,reward.xp)
      local delivery=storeRewardItem(reward.item)
      reward.coalAdded=coal; reward.scrapAdded=reward.scrap+overflow; reward.coalConverted=overflow
      reward.levels=levels; reward.delivery=delivery
      return reward
  end

  local function rewardText(reward)
      local item=Util.titleFromFile(reward.item)
      local delivered=reward.delivery=="backpack" and item or (reward.delivery=="ammunition" and (item.." ammunition") or (item.." in your "..reward.delivery))
      return "+"..reward.xp.." XP, +"..reward.coalAdded.." coal, +"..reward.scrapAdded.." scrap, and "..delivered..(reward.levels>0 and "  LEVEL UP!" or "")
  end

  local function processPassengerArrivals()
      local notices={}
      if runtime.saveData.arrivalNotice then notices[#notices+1]=runtime.saveData.arrivalNotice end
      for i=#runtime.saveData.passengers,1,-1 do
          local passenger=runtime.saveData.passengers[i]
          if runtime.saveData.location>=passenger.destination then
              table.remove(runtime.saveData.passengers,i)
              local origin=passenger.origin or math.max(1,(passenger.destination or runtime.saveData.location)-3)
              local reward=grantProgressionReward("ride",origin,passenger.destination or runtime.saveData.location)
              notices[#notices+1]=Util.titleFromFile(passenger.npc).." reached their stop: "..rewardText(reward).."."
          end
      end
      runtime.saveData.arrivalNotice=#notices>0 and table.concat(notices," ") or nil
  end

  local function passengerContributions()
      local notes={}
      for _,passenger in ipairs(runtime.saveData.passengers or {}) do
          passenger.job=passenger.job or Passengers.jobFor(passenger.npc)
          local preferred=TrainUpgradeBalance.owns(runtime.saveData,Passengers.preferredCarId(passenger.job))
          local contribution=QuestProgression.passengerContribution(passenger.job,preferred); local amount
          if contribution.kind=="resource" then amount=TrainUpgradeBalance.addResource(runtime.saveData,contribution.resource,contribution.amount)
          elseif contribution.kind=="health" then local before=runtime.saveData.health; runtime.saveData.health=math.min(runtime.saveData.maxHealth,runtime.saveData.health+contribution.amount); amount=runtime.saveData.health-before
          else runtime.saveData.scrap=(runtime.saveData.scrap or 0)+contribution.amount; amount=contribution.amount end
          local gained=contribution.verb.." "..amount.." "..(contribution.kind=="health" and "health" or (contribution.kind=="scrap" and "scrap" or contribution.resource))
          notes[#notes+1]=Util.titleFromFile(passenger.npc).." "..gained
      end
      if #notes>0 then runtime.saveData.arrivalNotice=table.concat(notes,". ").."." end
  end

  local function giveQuestReward(kind,origin,destination,message)
      local reward=grantProgressionReward(kind,origin,destination)
      runtime.dialogue={speaker="Traveler",text=(message or "Thank you!").."  Reward: "..rewardText(reward)..".",timer=5}
      return reward
  end

  local function pendingMailHere()
      for _,quest in ipairs(runtime.saveData.mailQuests or {}) do
          if not quest.complete and quest.destination==runtime.saveData.location and quest.recipient==runtime.saveData.currentNPC then return quest end
      end
  end

  local function acceptQuest(kind)
      if kind=="mail" then
          local distance=QuestProgression.questDistance("mail",runtime.saveData.location); local destination=runtime.saveData.location+distance
          local layout=runtime.saveData.stopLayouts[tostring(destination)] or {houseX=love.math.random(390,700),treeA=love.math.random(110,250),treeB=love.math.random(760,860),house=love.math.random(1,8),tree=love.math.random(1,7)}
          local roster=runtime.saveData.npcRoster or {}; layout.npc=layout.npc or roster[love.math.random(math.max(1,#roster))] or runtime.saveData.currentNPC; runtime.saveData.stopLayouts[tostring(destination)]=layout
          runtime.saveData.mailQuests[#runtime.saveData.mailQuests+1]={sender=runtime.saveData.currentNPC,recipient=layout.npc,origin=runtime.saveData.location,destination=destination,complete=false}
          local reward=QuestProgression.rewardProfile("mail",distance,runtime.saveData.trait,destination)
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Thank you. Find "..Util.titleFromFile(layout.npc).." at stop "..destination..". Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=6}
      elseif kind=="ride" then
          local remaining=math.max(1,50-runtime.saveData.location); local job=Passengers.jobFor(runtime.saveData.currentNPC); local rideStops=Passengers.rideLength(job,remaining,runtime.saveData.resources.food,runtime.saveData.resources.water,love.math.random(-1,1))
          local index=#runtime.saveData.passengers+1; local px=car.x+225+(index-1)*85
          local layout=ensureStopLayout()
          local destination=runtime.saveData.location+rideStops
          runtime.saveData.passengers[index]={npc=runtime.saveData.currentNPC,origin=runtime.saveData.location,destination=destination,x=px,y=car.y+285,homeX=px,homeY=car.y+285,wait=1,job=job,pose="idle",weapon=layout.npcWeapon}
          local reward=QuestProgression.rewardProfile("ride",rideStops,runtime.saveData.trait,destination)
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Thank you! I'll help as your "..job.." until stop "..destination..". Arrival reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and loot.",timer=6}
      elseif kind=="trade" then
          runtime.tradeOpen=true; runtime.tradeNPC=runtime.saveData.currentNPC; runtime.dialogue=nil
      elseif kind=="supplies" then
          local distance=QuestProgression.questDistance("supplies",runtime.saveData.location); local destination=runtime.saveData.location+distance
          local amount=3; local added=0; local addedSlots={}
          for _=1,amount do
              local slot=Inventory.firstEmptySlot(runtime.saveData)
              if not slot then break end
              runtime.saveData.inventory[slot]=({"food-ration","bread-loaf","jerky-bundle"})[love.math.random(3)]; addedSlots[#addedSlots+1]=slot; added=added+1
          end
          if added<amount then
              for _,slot in ipairs(addedSlots) do runtime.saveData.inventory[slot]=nil end
              runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]={origin=runtime.saveData.location,destination=destination,amount=amount,complete=false,foodItems=0,cargoStored=true}
              local reward=QuestProgression.rewardProfile("supplies",distance,runtime.saveData.trait,destination)
              runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="The 3 food crates are secured in the cargo hold for stop "..destination..". Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=6}
          else
              runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]={origin=runtime.saveData.location,destination=destination,amount=amount,complete=false,foodItems=amount}
              local reward=QuestProgression.rewardProfile("supplies",distance,runtime.saveData.trait,destination)
              runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Take these 3 food items to stop "..destination..". Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=6}
          end
      end
      runtime.questOffer=nil; writeSave()
  end

  local function talkToNPC()
      for _,supply in ipairs(runtime.saveData.supplyQuests or {}) do
          if not supply.complete and supply.destination==runtime.saveData.location then
              if supply.cargoStored then
                  supply.complete=true; giveQuestReward("supplies",supply.origin,supply.destination,"Those supplies will keep us going. Thank you!"); writeSave(); return
              elseif supply.storedAtTrain or supply.foodItems==nil then
                  if runtime.saveData.resources.food>=supply.amount then runtime.saveData.resources.food=runtime.saveData.resources.food-supply.amount; supply.complete=true; giveQuestReward("supplies",supply.origin,supply.destination,"Those supplies will keep us going. Thank you!"); writeSave()
                  else runtime.dialogue={speaker="Settler",text="You don't have enough food stored for our delivery. We're hungry and disappointed.",timer=4} end
                  return
              end
              local remaining=supply.foodItems or supply.amount; local consumed={}
              for i=1,(runtime.saveData.inventoryCapacity or 6) do
                  local name=runtime.saveData.inventory[i]; if name and Catalog.itemEffects[name] and Catalog.itemEffects[name].food and remaining>0 then consumed[#consumed+1]=i; remaining=remaining-1 end
              end
              if remaining<=0 then for _,i in ipairs(consumed) do runtime.saveData.inventory[i]=nil end; supply.complete=true; giveQuestReward("supplies",supply.origin,supply.destination,"Those supplies will keep us going. Thank you!"); writeSave()
              else runtime.dialogue={speaker="Settler",text="You need the 3 food items I gave you for this delivery.",timer=4} end
              return
          end
      end
      local mail=pendingMailHere()
      if mail then mail.complete=true; giveQuestReward("mail",mail.origin,mail.destination,Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]); writeSave(); return end
      local key=tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.currentNPC); local layout=ensureStopLayout()
      -- Read the offer for the NPC being spoken to. A stop can have several
      -- critters, and their quest rolls must not leak between conversations.
      local kind=(layout.npcOffers and layout.npcOffers[runtime.saveData.currentNPC]) or "none"
      if not runtime.saveData.questAsked[key] and kind~="none" and runtime.saveData.location<50 then
          runtime.saveData.questAsked[key]=true; runtime.questOffer={kind=kind}
          local text=kind=="mail" and Catalog.mailRequestLines[love.math.random(#Catalog.mailRequestLines)] or (kind=="ride" and Catalog.rideRequestLines[love.math.random(#Catalog.rideRequestLines)] or (kind=="supplies" and "Settlers farther west are hungry. Could you deliver some food for us?" or "I've got supplies to trade. Want to take a look?"))
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text=text,timer=30,choice=true}; writeSave(); return
      end
      runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC or "Traveler"),text=Catalog.dialogueLines[love.math.random(#Catalog.dialogueLines)],timer=6}
  end

  local function enterStop()
      runtime.scene="stop"; runtime.player.x,runtime.player.y=270,490; setupNPC(); writeSave()
  end

  local function attemptLeaveTrain()
      local key=tostring(runtime.saveData.location); local encounter=runtime.saveData.encounters[key]
      if beginRequiredEvent(runtime.saveData.location) then return end
      if not encounter then
          -- Battles should be the primary stop interruption; trail events remain less common.
          -- Story and mystery chapters are checked above; ordinary stops still
          -- favor combat while leaving room for the five random event families.
          local hasMob=love.math.random()<EventBalance.encounterChance(runtime.saveData.location)
          local tier=CombatBalance.tierFor(runtime.saveData.location)
          encounter={rolled=true,hasMob=hasMob,resolved=not hasMob,tier=tier}
          local pool=Catalog.mobTiers[tier]
          if hasMob and #pool>0 then
              encounter.mobFiles={}
              for i=1,CombatBalance.mobCount(tier,runtime.saveData.location,love.math.random()) do
                  encounter.mobFiles[i]=pool[love.math.random(#pool)]
              end
              encounter.mobFile=encounter.mobFiles[1]
          end
          runtime.saveData.encounters[key]=encounter; writeSave()
      end
      if encounter.hasMob and not encounter.resolved and (encounter.mobFile or encounter.mobFiles) then beginEncounter(encounter)
      elseif not encounter.hasMob and not runtime.saveData.events[tostring(runtime.saveData.location)] then
          beginRandomEvent()
      else enterStop() end
  end

  return {
    travelCost=travelCost,
    travelStatus=travelStatus,
    balanceAudit=function() return ProgressionBalance.audit(EngineUpgrades,TrainUpgradeBalance) end,
    upgradeBalanceAudit=function() return TrainUpgradeBalance.audit(EngineUpgrades) end,
    questBalanceAudit=function() return QuestProgression.audit(Catalog,LootProgression,Passengers,Inventory) end,
    questSummary=function() return QuestProgression.summary(runtime.saveData) end,
    processPassengerArrivals=processPassengerArrivals,
    passengerContributions=passengerContributions,
    pendingMailHere=pendingMailHere,
    acceptQuest=acceptQuest,
    talkToNPC=talkToNPC,
    enterStop=enterStop,
    attemptLeaveTrain=attemptLeaveTrain
  }
end

return {new=new}
