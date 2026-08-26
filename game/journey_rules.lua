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
  local StopHelpProgression=required(context,"stopHelpProgression","table")
  local FirstAid=required(context,"firstAid","table")
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
              local _,goodwill=StopHelpProgression.add(runtime.saveData,1,"ride",passenger.npc,passenger.destination)
              notices[#notices+1]=Util.titleFromFile(passenger.npc).." reached their stop: "..rewardText(reward).." and +1 goodwill ("..goodwill.." total)."
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
      local _,goodwill=StopHelpProgression.add(runtime.saveData,1,kind,runtime.saveData.currentNPC,destination)
      runtime.dialogue={speaker="Traveler",text=(message or "Thank you!").."  Reward: "..rewardText(reward).." and +1 goodwill ("..goodwill.." total).",timer=5}
      return reward
  end

  local function pendingMailHere()
      for _,quest in ipairs(runtime.saveData.mailQuests or {}) do
          if not quest.complete and quest.destination==runtime.saveData.location and quest.recipient==runtime.saveData.currentNPC then return quest end
      end
  end

  local function currentHelpRequest()
      local layout=ensureStopLayout()
      return StopHelpProgression.request(layout,runtime.saveData.currentNPC),layout
  end

  local function itemHelp(request)
      request.accepted=true
      local result=StopHelpProgression.completeItem(runtime.saveData,request,runtime.saveData.currentNPC,runtime.saveData.location)
      local speaker=Util.titleFromFile(runtime.saveData.currentNPC or "Traveler")
      if result.completed then
          runtime.dialogue={speaker=speaker,text="That is exactly what we needed. Thank you! +"..result.gained.." goodwill. Total goodwill: "..result.total..".",timer=6}
      else
          runtime.dialogue={speaker=speaker,text="Thank you for offering. Please bring me "..(request.label or Util.titleFromFile(request.item)).." when you find one.",timer=6}
      end
      return result
  end

  local function beginFirstAid(request)
      request.accepted=true
      local slot,name=StopHelpProgression.medicalItem(runtime.saveData,Catalog)
      if not slot then
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC or "Traveler"),text="I still need help, but you need a bandage, salve, tonic, splint, or medkit to treat this wound.",timer=6}
          return false
      end
      runtime.firstAid=FirstAid.new({npc=runtime.saveData.currentNPC,itemName=name,itemSlot=slot,location=runtime.saveData.location})
      runtime.dialogue=nil
      return true
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
      elseif kind=="item" then
          local request=currentHelpRequest()
          if request then itemHelp(request) end
      elseif kind=="aid" then
          local request=currentHelpRequest()
          if request then beginFirstAid(request) end
      elseif kind=="supplies" then
          local distance=QuestProgression.questDistance("supplies",runtime.saveData.location); local destination=runtime.saveData.location+distance
          local cargoKind=(runtime.questOffer and runtime.questOffer.deliveryKind) or QuestProgression.rollDelivery(runtime.saveData.location)
          local profile=QuestProgression.deliveryProfile(cargoKind)
          runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]={origin=runtime.saveData.location,destination=destination,amount=profile.amount,cargoKind=cargoKind,complete=false}
          local reward=QuestProgression.rewardProfile(cargoKind,distance,runtime.saveData.trait,destination)
          runtime.dialogue={speaker=Util.titleFromFile(runtime.saveData.currentNPC),text=string.format(profile.accepted,destination).." Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=7}
      end
      runtime.questOffer=nil; writeSave()
  end

  local function resolveFirstAid(outcome)
      local session=runtime.firstAid
      if not session then return false end
      runtime.firstAid=nil
      local layout=runtime.saveData.stopLayouts[tostring(session.location)]
      local request=StopHelpProgression.request(layout,session.npc)
      local speaker=Util.titleFromFile(session.npc or "Traveler")
      if outcome=="complete" then
          local result=StopHelpProgression.completeAid(runtime.saveData,request,session,session.npc,session.location)
          if result.completed then runtime.dialogue={speaker=speaker,text="You patched me up. I won't forget this. +"..result.gained.." goodwill. Total goodwill: "..result.total..".",timer=6}
          else runtime.dialogue={speaker=speaker,text="The medical supply went missing before the treatment was finished. We can try again.",timer=6} end
      elseif outcome=="failed" then runtime.dialogue={speaker=speaker,text="That did not work, but thank you for trying. We can try again when you're ready.",timer=6}
      else runtime.dialogue={speaker=speaker,text="We can try the treatment again when you're ready.",timer=5} end
      writeSave(); return true
  end

  local function talkToNPC()
      for _,supply in ipairs(runtime.saveData.supplyQuests or {}) do
          if not supply.complete and supply.destination==runtime.saveData.location then
              local result=QuestProgression.consumeCargo(runtime.saveData,Catalog,supply)
              local profile=QuestProgression.deliveryProfile(supply.cargoKind)
              if result.completed then
                  supply.complete=true; giveQuestReward(supply.cargoKind or "food",supply.origin,supply.destination,profile.thanks); writeSave()
              else
                  local text=supply.cargoKind=="recovery" and "The keepsake is still somewhere in the dangerous area. Make the stop safe first."
                      or ("You still need "..result.shortage.." more for this delivery ("..profile.label.." total). Nothing has been taken yet.")
                  runtime.dialogue={speaker="Settler",text=text,timer=5}
              end
              return
          end
      end
      local mail=pendingMailHere()
      if mail then mail.complete=true; giveQuestReward("mail",mail.origin,mail.destination,Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]); writeSave(); return end
      local helpRequest=currentHelpRequest()
      if helpRequest and helpRequest.accepted and not helpRequest.complete then
          if helpRequest.kind=="item" then itemHelp(helpRequest) else beginFirstAid(helpRequest) end
          writeSave(); return
      end
      local key=tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.currentNPC); local layout=ensureStopLayout()
      -- Read the offer for the NPC being spoken to. A stop can have several
      -- critters, and their quest rolls must not leak between conversations.
      local kind=(layout.npcOffers and layout.npcOffers[runtime.saveData.currentNPC]) or "none"
      if not runtime.saveData.questAsked[key] and kind~="none" and runtime.saveData.location<50 then
          runtime.saveData.questAsked[key]=true; runtime.questOffer={kind=kind}
          local request=StopHelpProgression.request(layout,runtime.saveData.currentNPC)
          local text
          if kind=="mail" then text=Catalog.mailRequestLines[love.math.random(#Catalog.mailRequestLines)]
          elseif kind=="ride" then text=Catalog.rideRequestLines[love.math.random(#Catalog.rideRequestLines)]
          elseif kind=="supplies" then
              runtime.questOffer.deliveryKind=QuestProgression.rollDelivery(runtime.saveData.location)
              text=QuestProgression.deliveryProfile(runtime.questOffer.deliveryKind).request
          elseif (kind=="item" or kind=="aid") and request then text=request.text
          else text="I've got supplies to trade. Want to take a look?" end
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
    helpBalanceAudit=function()
        local result=StopHelpProgression.audit(Catalog); result.firstAid=FirstAid.audit(); result.ready=result.ready and result.firstAid.ready
        return result
    end,
    questSummary=function() return QuestProgression.summary(runtime.saveData) end,
    processPassengerArrivals=processPassengerArrivals,
    passengerContributions=passengerContributions,
    pendingMailHere=pendingMailHere,
    acceptQuest=acceptQuest,
    resolveFirstAid=resolveFirstAid,
    talkToNPC=talkToNPC,
    enterStop=enterStop,
    attemptLeaveTrain=attemptLeaveTrain
  }
end

return {new=new}
