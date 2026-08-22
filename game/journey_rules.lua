local function install(resolve,assign)
  assert(type(resolve)=="function","journey rules require a dependency resolver")
  assert(type(assign)=="function","journey rules require a dependency writer")
  local env=setmetatable({}, {
    __index=function(_,key)
      local value=resolve(key)
      if value~=nil then return value end
      return _G[key]
    end,
    __newindex=function(_,key,value)
      if not assign(key,value) then error("journey rules cannot assign "..tostring(key),2) end
    end
  })
  setfenv(install,env)

  local function travelCost()
      local leg=math.max(0,(saveData.location or 1)-1)
      local passengers=#(saveData.passengers or {})
      local terrain=({"plains","desert","mountains","ruins","forest"})[((saveData.location or 1)-1)%5+1]
      local terrainCoal=terrain=="mountains" and 2 or (terrain=="ruins" and 1 or 0); local trait=saveData.trait or Catalog.characterTraitProfiles[1]
      local sleeper=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="sleeper" then sleeper=true end end
      local passengerCost=sleeper and math.ceil(passengers/2) or passengers
      local food,water,coal=EngineUpgrades.applyCosts(saveData.engineLevel,(1+math.floor(leg/4)+passengerCost)*(trait.food or 1),(1+math.floor(leg/3)+passengerCost)*(trait.water or 1),(1+math.floor(leg/5)+terrainCoal)*(trait.coal or 1))
      local maintenanceCoal=Maintenance.coalPenalty(saveData)
      coal=coal+maintenanceCoal
      return {food=food,water=water,coal=coal,passengers=passengers,terrain=terrain,maintenanceCoal=maintenanceCoal}
  end

  local function processPassengerArrivals()
      for i=#saveData.passengers,1,-1 do
          local passenger=saveData.passengers[i]
          if saveData.location>=passenger.destination then
              table.remove(saveData.passengers,i)
              local coal=math.max(1,math.floor(love.math.random(1,3)*(saveData.trait.reward or 1))); saveData.resources.coal=math.min(20,saveData.resources.coal+coal)
              local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(saveData); if slot then saveData.inventory[slot]=item end
              saveData.arrivalNotice=(Util.titleFromFile(passenger.npc).." reached their stop and left you "..coal.." coal"..(slot and " and "..Util.titleFromFile(item) or "")..".")
          end
      end
  end

  local function passengerContributions()
      local notes={}; local hasGreenhouse=false; for _,id in ipairs(saveData.trainCars or {}) do if id=="greenhouse" then hasGreenhouse=true end end
      for _,p in ipairs(saveData.passengers or {}) do
          p.job=p.job or Passengers.jobFor(p.npc); local gained
          if p.job=="greenhouse" and hasGreenhouse then saveData.resources.food=math.min(30,saveData.resources.food+2); gained="grew 2 food"
          elseif p.job=="fireman" then saveData.resources.coal=math.min(30,saveData.resources.coal+1); gained="salvaged 1 coal"
          elseif p.job=="medic" then local before=saveData.health; saveData.health=math.min(saveData.maxHealth,saveData.health+2); gained="restored "..(saveData.health-before).." health"
          else local resource=({"food","water","coal"})[love.math.random(3)]; saveData.resources[resource]=math.min(30,saveData.resources[resource]+1); gained="scavenged 1 "..resource end
          notes[#notes+1]=Util.titleFromFile(p.npc).." "..gained
      end
      if #notes>0 then saveData.arrivalNotice=table.concat(notes,". ").."." end
  end

  local function giveQuestReward(message)
      local coal=math.max(1,math.floor(love.math.random(1,3)*(saveData.trait.reward or 1))); saveData.resources.coal=math.min(20,saveData.resources.coal+coal)
      local item=Catalog.questRewardItems[love.math.random(#Catalog.questRewardItems)]; local slot=Inventory.firstEmptySlot(saveData)
      if slot then saveData.inventory[slot]=item else House.storeLoot(saveData,Catalog,item,saveData.location) end
      dialogue={speaker="Traveler",text=(message or "Thank you!").."  You received "..coal.." coal and "..Util.titleFromFile(item)..".",timer=4}
  end

  local function pendingMailHere()
      for _,quest in ipairs(saveData.mailQuests or {}) do
          if not quest.complete and quest.destination==saveData.location and quest.recipient==saveData.currentNPC then return quest end
      end
  end

  local function acceptQuest(kind)
      if kind=="mail" then
          local maxAhead=math.max(1,math.min(8,50-saveData.location)); local destination=math.min(50,saveData.location+love.math.random(1,maxAhead))
          local layout=saveData.stopLayouts[tostring(destination)] or {houseX=love.math.random(390,700),treeA=love.math.random(110,250),treeB=love.math.random(760,860),house=love.math.random(1,8),tree=love.math.random(1,7)}
          local roster=saveData.npcRoster or {}; layout.npc=layout.npc or roster[love.math.random(math.max(1,#roster))] or saveData.currentNPC; saveData.stopLayouts[tostring(destination)]=layout
          saveData.mailQuests[#saveData.mailQuests+1]={sender=saveData.currentNPC,recipient=layout.npc,origin=saveData.location,destination=destination,complete=false}
          dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Thank you. Please look for "..Util.titleFromFile(layout.npc).." around stop "..destination..".",timer=4}
      elseif kind=="ride" then
          local remaining=math.max(1,50-saveData.location); local job=Passengers.jobFor(saveData.currentNPC); local rideStops=Passengers.rideLength(job,remaining,saveData.resources.food,saveData.resources.water,love.math.random(-1,1))
          local index=#saveData.passengers+1; local px=car.x+225+(index-1)*85
          local layout=ensureStopLayout()
          saveData.passengers[index]={npc=saveData.currentNPC,destination=saveData.location+rideStops,x=px,y=car.y+285,homeX=px,homeY=car.y+285,wait=1,job=job,pose="idle",weapon=layout.npcWeapon}
          dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Thank you! I'll ride for "..rideStops..(rideStops==1 and " stop" or " stops").." and help as your "..job..".",timer=4}
      elseif kind=="trade" then
          tradeOpen=true; tradeNPC=saveData.currentNPC; dialogue=nil
      elseif kind=="supplies" then
          local destination=math.min(50,saveData.location+love.math.random(1,math.max(1,math.min(6,50-saveData.location))))
          local amount=3; local added=0; local addedSlots={}
          for _=1,amount do
              local slot=Inventory.firstEmptySlot(saveData)
              if not slot then break end
              saveData.inventory[slot]=({"food-ration","bread-loaf","jerky-bundle"})[love.math.random(3)]; addedSlots[#addedSlots+1]=slot; added=added+1
          end
          if added<amount then
              for _,slot in ipairs(addedSlots) do saveData.inventory[slot]=nil end
              saveData.resources.food=math.min(30,saveData.resources.food+amount)
              saveData.supplyQuests[#saveData.supplyQuests+1]={origin=saveData.location,destination=destination,amount=amount,complete=false,foodItems=0,storedAtTrain=true}
              dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Your backpack is full, so the 3 food items were sent to the train stores for stop "..destination..".",timer=5}
          else
              saveData.supplyQuests[#saveData.supplyQuests+1]={origin=saveData.location,destination=destination,amount=amount,complete=false,foodItems=amount}
              dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text="Take these 3 food items to the settlers at stop "..destination..". They will reward you when it arrives.",timer=5}
          end
      end
      questOffer=nil; writeSave()
  end

  local function talkToNPC()
      for _,supply in ipairs(saveData.supplyQuests or {}) do
          if not supply.complete and supply.destination==saveData.location then
              if supply.storedAtTrain or supply.foodItems==nil then
                  if saveData.resources.food>=supply.amount then saveData.resources.food=saveData.resources.food-supply.amount; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
                  else dialogue={speaker="Settler",text="You don't have enough food stored for our delivery. We're hungry and disappointed.",timer=4} end
                  return
              end
              local remaining=supply.foodItems or supply.amount; local consumed={}
              for i=1,(saveData.inventoryCapacity or 6) do
                  local n=saveData.inventory[i]; if n and Catalog.itemEffects[n] and Catalog.itemEffects[n].food and remaining>0 then consumed[#consumed+1]=i; remaining=remaining-1 end
              end
              if remaining<=0 then for _,i in ipairs(consumed) do saveData.inventory[i]=nil end; supply.complete=true; giveQuestReward("Those supplies will keep us going. Thank you!"); writeSave()
              else dialogue={speaker="Settler",text="You need the 3 food items I gave you for this delivery.",timer=4} end
              return
          end
      end
      local mail=pendingMailHere()
      if mail then mail.complete=true; giveQuestReward(Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]); writeSave(); return end
      local key=tostring(saveData.location)..":"..tostring(saveData.currentNPC); local layout=ensureStopLayout()
      -- Read the offer for the NPC being spoken to.  A stop can have several
      -- critters, and their quest rolls must not leak between conversations.
      local kind=(layout.npcOffers and layout.npcOffers[saveData.currentNPC]) or "none"
      if not saveData.questAsked[key] and kind~="none" and saveData.location<50 then
          saveData.questAsked[key]=true; questOffer={kind=kind}
          local text=kind=="mail" and Catalog.mailRequestLines[love.math.random(#Catalog.mailRequestLines)] or (kind=="ride" and Catalog.rideRequestLines[love.math.random(#Catalog.rideRequestLines)] or (kind=="supplies" and "Settlers farther west are hungry. Could you deliver some food for us?" or "I've got supplies to trade. Want to take a look?"))
          dialogue={speaker=Util.titleFromFile(saveData.currentNPC),text=text,timer=30,choice=true}; writeSave(); return
      end
      dialogue={speaker=Util.titleFromFile(saveData.currentNPC or "Traveler"),text=Catalog.dialogueLines[love.math.random(#Catalog.dialogueLines)],timer=6}
  end

  local function enterStop()
      scene=session:setScene("stop"); player.x,player.y=270,490; setupNPC(); writeSave()
  end

  local function attemptLeaveTrain()
      local key=tostring(saveData.location); local encounter=saveData.encounters[key]
      local requiredEvent=not saveData.events[key] and Events.required(saveData,saveData.location)
      if requiredEvent then randomEvent=requiredEvent; screens:transition("event"); state=session.screen; return end
      if not encounter then
          -- Battles should be the primary stop interruption; trail events remain less common.
          -- Story and mystery chapters are checked above; ordinary stops still
          -- favor combat while leaving room for the five random event families.
          local hasMob=love.math.random()<0.58
          local tier=saveData.location<=4 and "easy" or (saveData.location<=8 and "medium" or "hard")
          encounter={rolled=true,hasMob=hasMob,resolved=not hasMob,tier=tier}
          local pool=Catalog.mobTiers[tier]
          if hasMob and #pool>0 then
              encounter.mobFiles={}
              for i=1,Catalog.encounterMobCount(tier,saveData.location) do
                  encounter.mobFiles[i]=pool[love.math.random(#pool)]
              end
              encounter.mobFile=encounter.mobFiles[1]
          end
          saveData.encounters[key]=encounter; writeSave()
      end
      if encounter.hasMob and not encounter.resolved and (encounter.mobFile or encounter.mobFiles) then beginEncounter(encounter)
      elseif not encounter.hasMob and not saveData.events[tostring(saveData.location)] then
          randomEvent=Events.random(saveData); screens:transition("event"); state=session.screen
      else enterStop() end
  end

  return {
    travelCost=travelCost,
    processPassengerArrivals=processPassengerArrivals,
    passengerContributions=passengerContributions,
    pendingMailHere=pendingMailHere,
    acceptQuest=acceptQuest,
    talkToNPC=talkToNPC,
    enterStop=enterStop,
    attemptLeaveTrain=attemptLeaveTrain
  }
end

return {install=install}
