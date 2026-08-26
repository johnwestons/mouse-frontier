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
      return ProgressionBalance.travelCost(runtime.saveData,EngineUpgrades,Maintenance,Catalog.characterTraitProfiles[1])
  end

  local function travelStatus()
      return ProgressionBalance.travelStatus(runtime.saveData,travelCost())
  end

  local function processPassengerArrivals()
      for i=#runtime.saveData.passengers,1,-1 do
          local passenger=runtime.saveData.passengers[i]
          if runtime.saveData.location>=passenger.destination then
              table.remove(runtime.saveData.passengers,i)
              local coal=math.max(1,math.floor(love.math.random(1,3)*(runtime.saveData.trait.reward or 1))); runtime.saveData.resources.coal=math.min(20,runtime.saveData.resources.coal+coal)
              local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(runtime.saveData); if slot then runtime.saveData.inventory[slot]=item end
              runtime.saveData.arrivalNotice=(Util.titleFromFile(passenger.npc).." reached their stop and left you "..coal.." coal"..(slot and " and "..Util.titleFromFile(item) or "")..".")
          end
      end
  end

  local function passengerContributions()
      local notes={}; local hasGreenhouse=false; for _,id in ipairs(runtime.saveData.trainCars or {}) do if id=="greenhouse" then hasGreenhouse=true end end
      for _,passenger in ipairs(runtime.saveData.passengers or {}) do
          passenger.job=passenger.job or Passengers.jobFor(passenger.npc); local gained
          if passenger.job=="greenhouse" and hasGreenhouse then runtime.saveData.resources.food=math.min(30,runtime.saveData.resources.food+2); gained="grew 2 food"
          elseif passenger.job=="fireman" then runtime.saveData.resources.coal=math.min(30,runtime.saveData.resources.coal+1); gained="salvaged 1 coal"
          elseif passenger.job=="medic" then local before=runtime.saveData.health; runtime.saveData.health=math.min(runtime.saveData.maxHealth,runtime.saveData.health+2); gained="restored "..(runtime.saveData.health-before).." health"
          else local resource=({"food","water","coal"})[love.math.random(3)]; runtime.saveData.resources[resource]=math.min(30,runtime.saveData.resources[resource]+1); gained="scavenged 1 "..resource end
          notes[#notes+1]=Util.titleFromFile(passenger.npc).." "..gained
      end
      if #notes>0 then runtime.saveData.arrivalNotice=table.concat(notes,". ").."." end
  end

  local function giveQuestReward(message)
      local coal=math.max(1,math.floor(love.math.random(1,3)*(runtime.saveData.trait.reward or 1))); runtime.saveData.resources.coal=math.min(20,runtime.saveData.resources.coal+coal)
      local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(runtime.saveData)
      if slot then runtime.saveData.inventory[slot]=item else House.storeLoot(runtime.saveData,Catalog,item,runtime.saveData.location) end
      runtime.dialogue={speaker="Traveler",text=(message or "Thank you!").."  You received "..coal.." coal and "..Util.titleFromFile(item)..".",timer=4}
  end

  local function pendingMailHere()
      for _,quest in ipairs(runtime.saveData.mailQuests or {}) do
          if not quest.complete and quest.destination==runtime.saveData.location and quest.recipient==runtime.saveData.currentNPC then return quest end
      end
  end

  local function acceptQuest(kind)
      if kind=="mail" then
          local maxAhead=math.max(1,math.min(8,50-runtime.saveData.location)); local destination=math.min(50,runtime.saveData.location+love.math.random(1,maxAhead))
          local layout=runtime.saveData.stopLayouts[tostring(destination)] or {houseX=love.math.random(390,700),treeA=love.math.random(110,250),treeB=love.math.random(760,860),house=love.math.random(1,8),tree=love.math.random(1,7)}
          local roster=runtime.saveData.npcRoster or {}; layout.npc=layout.npc or roster[love.math.random(math.max(1,#roster))] or runtime.saveData.currentNPC; runtime.saveData.stopLayouts[tostring(destination)]=layout
          runtime.saveData.mailQuests[#runtime.saveData.mailQuests+1]={sender=runtime.saveData.currentNPC,recipient=layout.npc,origin=runtime.saveData.location,destination=destination,complete=false}
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Thank you. Please look for "..Util.titleFromFile(layout.npc).." around stop "..destination..".",timer=4}
      elseif kind=="ride" then
          local remaining=math.max(1,50-runtime.saveData.location); local job=Passengers.jobFor(runtime.saveData.currentNPC); local rideStops=Passengers.rideLength(job,remaining,runtime.saveData.resources.food,runtime.saveData.resources.water,love.math.random(-1,1))
          local index=#runtime.saveData.passengers+1; local px=car.x+225+(index-1)*85
          local layout=ensureStopLayout()
          runtime.saveData.passengers[index]={npc=runtime.saveData.currentNPC,destination=runtime.saveData.location+rideStops,x=px,y=car.y+285,homeX=px,homeY=car.y+285,wait=1,job=job,pose="idle",weapon=layout.npcWeapon}
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Thank you! I'll ride for "..rideStops..(rideStops==1 and " stop" or " stops").." and help as your "..job..".",timer=4}
      elseif kind=="trade" then
          runtime.tradeOpen=true; runtime.tradeNPC=runtime.saveData.currentNPC; runtime.dialogue=nil
      elseif kind=="supplies" then
          local destination=math.min(50,runtime.saveData.location+love.math.random(1,math.max(1,math.min(6,50-runtime.saveData.location))))
          local amount=3; local added=0; local addedSlots={}
          for _=1,amount do
              local slot=Inventory.firstEmptySlot(runtime.saveData)
              if not slot then break end
              runtime.saveData.inventory[slot]=({"food-ration","bread-loaf","jerky-bundle"})[love.math.random(3)]; addedSlots[#addedSlots+1]=slot; added=added+1
          end
          if added<amount then
              for _,slot in ipairs(addedSlots) do runtime.saveData.inventory[slot]=nil end
              runtime.saveData.resources.food=math.min(30,runtime.saveData.resources.food+amount)
              runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]={origin=runtime.saveData.location,destination=destination,amount=amount,complete=false,foodItems=0,storedAtTrain=true}
              runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Your backpack is full, so the 3 food items were sent to the train stores for stop "..destination..".",timer=5}
          else
              runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]={origin=runtime.saveData.location,destination=destination,amount=amount,complete=false,foodItems=amount}
              runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text="Take these 3 food items to the settlers at stop "..destination..". They will reward you when it arrives.",timer=5}
          end
      end
      runtime.questOffer=nil; writeSave()
  end

  local function talkToNPC()
      for _,supply in ipairs(runtime.saveData.supplyQuests or {}) do
          if not supply.complete and supply.destination==runtime.saveData.location then
              if supply.storedAtTrain or supply.foodItems==nil then
                  if runtime.saveData.resources.food>=supply.amount then runtime.saveData.resources.food=runtime.saveData.resources.food-supply.amount; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
                  else runtime.dialogue={speaker="Settler",text="You don't have enough food stored for our delivery. We're hungry and disappointed.",timer=4} end
                  return
              end
              local remaining=supply.foodItems or supply.amount; local consumed={}
              for i=1,(runtime.saveData.inventoryCapacity or 6) do
                  local name=runtime.saveData.inventory[i]; if name and Catalog.itemEffects[name] and Catalog.itemEffects[name].food and remaining>0 then consumed[#consumed+1]=i; remaining=remaining-1 end
              end
              if remaining<=0 then for _,i in ipairs(consumed) do runtime.saveData.inventory[i]=nil end; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
              else runtime.dialogue={speaker="Settler",text="You need the 3 food items I gave you for this delivery.",timer=4} end
              return
          end
      end
      local mail=pendingMailHere()
      if mail then mail.complete=true; giveQuestReward(Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]); writeSave(); return end
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
          local hasMob=love.math.random()<.58
          local tier=runtime.saveData.location<=4 and "easy" or (runtime.saveData.location<=8 and "medium" or "hard")
          encounter={rolled=true,hasMob=hasMob,resolved=not hasMob,tier=tier}
          local pool=Catalog.mobTiers[tier]
          if hasMob and #pool>0 then
              encounter.mobFiles={}
              for i=1,Catalog.encounterMobCount(tier,runtime.saveData.location) do
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
    balanceAudit=function() return ProgressionBalance.audit(EngineUpgrades) end,
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
