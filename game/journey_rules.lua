local Conversations=require("game.npc_conversations")
local CoopProgression=require("game.coop_progression")
local Items=require("game.item_instances")
local QuestDecisions=require('game.coop_quest_decisions')
local Home=require("game.home_stop")
local Identity=require('game.npc_identity')
local Targets=require('game.npc_targets')

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
  local HelpQuestSession=required(context,"helpQuestSession","table")
  local HelpDialogueQuests=required(context,"helpDialogueQuests","table")
  local NpcRelationships=required(context,"npcRelationships","table")
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

  local function rollSupplyDelivery()
      local data=runtime.saveData
      data.supplyDeliveryCycle=data.supplyDeliveryCycle or {seen={}}
      return QuestProgression.rollDelivery(data.location,nil,data.supplyDeliveryCycle)
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
              Identity.arrive(runtime.saveData,passenger)
              table.remove(runtime.saveData.passengers,i)
              local origin=passenger.origin or math.max(1,(passenger.destination or runtime.saveData.location)-3)
              local reward=grantProgressionReward("ride",origin,passenger.destination or runtime.saveData.location)
              local _,goodwill=StopHelpProgression.add(runtime.saveData,1,"ride",passenger.characterId or passenger.npc,passenger.destination)
              notices[#notices+1]=Identity.name(runtime.saveData,passenger).." reached their stop: "..rewardText(reward).." and +1 goodwill ("..goodwill.." total)."
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
          notes[#notes+1]=Identity.name(runtime.saveData,passenger).." "..gained
      end
      if #notes>0 then runtime.saveData.arrivalNotice=table.concat(notes,". ").."." end
  end

  local function giveQuestReward(kind,origin,destination,message)
      local reward=grantProgressionReward(kind,origin,destination)
      local _,goodwill=StopHelpProgression.add(runtime.saveData,1,kind,runtime.saveData.currentNPC,destination)
      runtime.dialogue={speaker="TASK",text=(message or "Task completed.").."  Reward: "..rewardText(reward).." and +1 goodwill ("..goodwill.." total).",timer=5}
      return reward
  end

  local function submitQuestAssistance(command,quest)
      local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]
      local reply=context.commands.submit(command,{targetId=context.commands.identify(layout),
          npc=runtime.saveData.currentNPC,questId=quest and context.commands.identify(quest) or nil})
      return reply.ok and reply.result or {ok=false,reason=reply.reason}
  end

  local function deliverQuest(quest,message)
      local result=submitQuestAssistance("quest.deliver",quest)
      if result.completed then
          runtime.dialogue={speaker="TASK",text=(message or "Task completed.").."  Reward: "..rewardText(result.reward)
              .." and +"..result.gained.." goodwill ("..result.total.." total).",timer=5}
      else
          local text=result.reason=="cargo_unavailable" and ("Delivery incomplete. Required: "..QuestProgression.deliveryProfile(quest.cargoKind).label..".")
              or "Delivery unavailable. Return to the recipient to try again."
          runtime.dialogue={speaker="TASK",text=text,timer=5}
      end
      return result
  end

  local function pendingMailHere()
      for _,quest in ipairs(runtime.saveData.mailQuests or {}) do
          if not quest.complete and Targets.matches(runtime.saveData,quest,runtime.saveData.currentNPC) then return quest end
      end
  end

  local function currentHelpRequest()
      local layout=ensureStopLayout()
      return StopHelpProgression.request(layout,runtime.saveData.currentNPC),layout
  end

  local function currentDialogueRequest()
      local layout=ensureStopLayout()
      return HelpDialogueQuests.request(layout,runtime.saveData.currentNPC),layout
  end

  local function showDialogueQuest(view)
      if not view then return false end
      runtime.helpDialogue=view
      runtime.dialogue={speaker=Identity.title(runtime.saveData,view.request.npc or runtime.saveData.currentNPC or "Traveler"),text=view.text,timer=math.huge,authored=view.authored}
      return true
  end

  local function beginDialogueQuest(request)
      if not CoopProgression.allowed(runtime,"conversation.begin") then return false,"host_only" end
      return showDialogueQuest(HelpDialogueQuests.begin(runtime.saveData,request))
  end

  local function chooseHelpDialogue(index)
      if index and not CoopProgression.allowed(runtime,"conversation.choose") then return false,"host_only" end
      local active=runtime.helpDialogue; local request=active and active.request
      if not request then return false end
      if active.authored then
          if context.commands then
              local command=index and 'conversation.choose' or 'conversation.end'
              local reply=context.commands.submit(command,{id=request.id,index=index})
              if not reply.ok then
                  local refreshed=Conversations.view(runtime.saveData,Conversations.request(runtime.saveData,request.npc))
                  if refreshed then showDialogueQuest(refreshed) end
                  return {completed=false,reason=reply.reason}
              end
              if not index then runtime.helpDialogue=nil; runtime.dialogue=nil; return true end
              local read=Conversations.readAlong(runtime.saveData)
              runtime.helpDialogue=nil
              runtime.dialogue={speaker=Identity.title(runtime.saveData,request.npc),text=read.text,notice=read.notice,authored=true,timer=math.huge}
              return {completed=true,text=read.text,notice=read.notice}
          end
          if not index then runtime.helpDialogue=nil; runtime.dialogue=nil; writeSave(); return true end
          local result=Conversations.choose(runtime.saveData,request,index,{
              storeItem=storeRewardItem,
              gainExperience=function(xp) return BattleRules.gainExperience(runtime.saveData,xp) end,
          })
          if result.completed then
              runtime.helpDialogue=nil
              runtime.dialogue={speaker=Identity.title(runtime.saveData,request.npc),text=result.text,notice=result.notice,authored=true,timer=math.huge}
          elseif result.view then showDialogueQuest(result.view) end
          writeSave(); return result
      end
      if not index then
          HelpDialogueQuests.pause(runtime.saveData,request); runtime.helpDialogue=nil; runtime.dialogue=nil; writeSave(); return true
      end
      local result=HelpDialogueQuests.choose(runtime.saveData,request,index,function(amount,kind,npc,location)
          return StopHelpProgression.add(runtime.saveData,amount,kind,npc,location)
      end)
      if result.completed then
          runtime.helpDialogue=nil
          local relationship=result.relationship or NpcRelationships.status(runtime.saveData,request.npc)
          runtime.dialogue={speaker=Identity.name(runtime.saveData,request.npc or "Traveler").." • "..relationship.name,
              text=result.text.."\n\n+"..result.gained.." goodwill. Total goodwill: "..result.total..".",timer=14}
      elseif result.view then showDialogueQuest(result.view) end
      writeSave(); return result
  end

  local function itemHelp(request)
      if not request.accepted and not CoopProgression.allowed(runtime,"quest.accept") then return false,"host_only" end
      if context.commands then
          if not request.accepted then return false,'quest_not_accepted' end
      else
          request.accepted=true
          if request.sessionId then HelpQuestSession.accept(runtime.saveData,request.sessionId) end
      end
      local result=context.commands and submitQuestAssistance("quest.help")
          or StopHelpProgression.completeItem(runtime.saveData,request,runtime.saveData.currentNPC,runtime.saveData.location)
      local speaker=Identity.title(runtime.saveData,runtime.saveData.currentNPC or "Traveler")
      if result.completed then
          runtime.dialogue={speaker="TASK",text="Item delivered. +"..result.gained.." goodwill. Total goodwill: "..result.total..".",timer=6}
      else
          runtime.dialogue={speaker="TASK",text="Required item: "..(request.label or Util.titleFromFile(request.item))..".",timer=6}
      end
      return result
  end

  local function beginFirstAid(request)
      if not request.accepted and not CoopProgression.allowed(runtime,"quest.accept") then return false,"host_only" end
      local quest=request.sessionId and HelpQuestSession.get(runtime.saveData,request.sessionId)
      if context.commands then
          if not request.accepted then return false,'quest_not_accepted' end
      else
          request.accepted=true
          if quest then HelpQuestSession.accept(runtime.saveData,quest.id) end
      end
      local slot,name=StopHelpProgression.medicalItem(runtime.saveData,Catalog)
      if not slot then
          if quest and not context.commands then HelpQuestSession.investigate(runtime.saveData,quest.id,"Find a medical supply and return to the wounded critter.") end
          runtime.dialogue={speaker="TASK",text="Treatment requires a bandage, salve, tonic, splint, or medkit.",timer=6}
          return false
      end
      if context.commands then
          local campaign=runtime.saveData
          local layout=campaign.stopLayouts[tostring(campaign.location)]
          local targetId=context.commands.identify(layout)
          local reply=context.commands.submit("firstAid.acquire",{targetId=targetId,npc=campaign.currentNPC})
          if not reply.ok then
              runtime.dialogue={speaker="TASK",text="Treatment unavailable. Stay near the patient and finish any other activity first.",timer=6}
              return false
          end
          runtime.firstAid=FirstAid.bindCommands(reply.result.session,function(command,args)
              if runtime.saveData~=campaign then return {ok=false,reason="wrong_campaign"} end
              return context.commands.submit(command,args)
          end,reply.result.leaseId)
      else
          if quest then HelpQuestSession.activate(runtime.saveData,quest.id,"Find the small cut, then complete all five treatment steps.") end
          runtime.firstAid=FirstAid.new({npc=runtime.saveData.currentNPC,itemName=name,itemSlot=slot,location=runtime.saveData.location,
              helpQuestId=quest and quest.id,progress=quest and quest.progress})
      end
      runtime.dialogue=nil
      return true
  end

  local function acceptQuest(kind)
      if not CoopProgression.allowed(runtime,"quest.accept") then return false,"host_only" end
      if kind=='ride' and Targets.pending(runtime.saveData,runtime.saveData.currentNPC) then
          runtime.dialogue={speaker='TASK',text="Complete this critter's deliveries before arranging a ride.",timer=5}
          return false,'recipient_has_delivery'
      end
      if context.commands then
          local data=runtime.saveData; local layout=data.stopLayouts[tostring(data.location)]
          local command=kind=='ride' and 'passenger.recruit' or 'quest.accept'
          local reply=context.commands.submit(command,{targetId=context.commands.identify(layout),npc=data.currentNPC,kind=kind})
          if not reply.ok then return false,reply.reason end
          local result=reply.result; local reward=result.reward
          local accepted=result.entityId and require('game.coop_entities').find(runtime.saveData,result.entityId)
          runtime.questOffer=nil
          if kind=='mail' then
              runtime.dialogue={speaker='TASK',text=Targets.label(data,accepted,'the letter')..' '..Targets.directions(data,accepted)..'. Reward: '..reward.scrap..' scrap, '..reward.xp..' XP, coal, and '..reward.minimumRarity..' loot.',timer=6}
          elseif kind=='ride' then
              runtime.dialogue={speaker='TASK',text=Identity.name(data,accepted)..' • Passenger job: '..result.job..' until stop '..result.destination..'. Arrival reward: '..reward.scrap..' scrap, '..reward.xp..' XP, coal, and loot.',timer=6}
          elseif kind=='supplies' then
              local profile=QuestProgression.deliveryProfile(result.deliveryKind)
              runtime.dialogue={speaker='TASK',text=Targets.label(data,accepted,profile.label)..' '..Targets.directions(data,accepted)..'. Reward: '..reward.scrap..' scrap, '..reward.xp..' XP, coal, and '..reward.minimumRarity..' loot.',timer=7}
          elseif kind=='trade' then
              runtime.tradeOpen=true; runtime.tradeNPC=data.currentNPC; runtime.tradeMerchantId=nil
              runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; runtime.dialogue=nil
          else
              runtime.dialogue=nil
              if not reply.savePending then
                  local request=StopHelpProgression.request(layout,data.currentNPC)
                  if kind=='item' then itemHelp(request) else beginFirstAid(request) end
              end
          end
          return reply
      end
      runtime.saveData.questAsked=runtime.saveData.questAsked or {}
      runtime.saveData.questAsked[tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.currentNPC)]=true
      if kind=="mail" then
          local distance=QuestProgression.questDistance("mail",runtime.saveData.location); local destination=runtime.saveData.location+distance
          local quest=Targets.bind(runtime.saveData,{sender=runtime.saveData.currentNPC,origin=runtime.saveData.location,destination=destination,complete=false})
          runtime.saveData.mailQuests[#runtime.saveData.mailQuests+1]=quest
          local reward=QuestProgression.rewardProfile("mail",distance,runtime.saveData.trait,destination)
          runtime.dialogue={speaker="TASK",text=Targets.label(runtime.saveData,quest,'the letter')..' '..Targets.directions(runtime.saveData,quest)..". Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=6}
      elseif kind=="ride" then
          local remaining=math.max(1,50-runtime.saveData.location); local job=Passengers.jobFor(runtime.saveData.currentNPC); local rideStops=Passengers.rideLength(job,remaining,runtime.saveData.resources.food,runtime.saveData.resources.water,love.math.random(-1,1))
          local index=#runtime.saveData.passengers+1; local px=car.x+225+(index-1)*85
          local layout=ensureStopLayout()
          local destination=runtime.saveData.location+rideStops
          if Items.enabled(runtime.saveData) then assert(Items.ensure(runtime.saveData)) end
          local person=Identity.get(runtime.saveData,runtime.saveData.currentNPC) or Identity.ensure(runtime.saveData,runtime.saveData.currentNPC,runtime.saveData.location,1)
          runtime.saveData.passengers[index]={npc=runtime.saveData.currentNPC,characterId=person.id,origin=runtime.saveData.location,destination=destination,x=px,y=car.y+285,homeX=px,homeY=car.y+285,wait=1,job=job,pose="idle",weapon=layout.npcWeapon}
          Identity.board(runtime.saveData,runtime.saveData.passengers[index])
          if Items.enabled(runtime.saveData) then
              runtime.saveData.passengers[index].weaponInstance=layout.npcWeaponInstance
              layout.npcWeapon=nil; layout.npcWeaponInstance=nil
          end
          NpcRelationships.recordRide(runtime.saveData,runtime.saveData.currentNPC)
          local reward=QuestProgression.rewardProfile("ride",rideStops,runtime.saveData.trait,destination)
          runtime.dialogue={speaker="TASK",text="Passenger job: "..job.." until stop "..destination..". Arrival reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and loot.",timer=6}
      elseif kind=="trade" then
          runtime.tradeOpen=true; runtime.tradeNPC=runtime.saveData.currentNPC; runtime.tradeMerchantId=nil
          runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; runtime.dialogue=nil
      elseif kind=="item" then
          local request=currentHelpRequest()
          if request then itemHelp(request) end
      elseif kind=="aid" then
          local request=currentHelpRequest()
          if request then beginFirstAid(request) end
      elseif kind=="dialogue" then
          local request=currentDialogueRequest()
          if request then beginDialogueQuest(request) end
      elseif kind=="supplies" then
          local distance=QuestProgression.questDistance("supplies",runtime.saveData.location); local destination=runtime.saveData.location+distance
          local cargoKind=(runtime.questOffer and runtime.questOffer.deliveryKind) or rollSupplyDelivery()
          local profile=QuestProgression.deliveryProfile(cargoKind)
          local quest=Targets.bind(runtime.saveData,{sender=runtime.saveData.currentNPC,origin=runtime.saveData.location,destination=destination,amount=profile.amount,cargoKind=cargoKind,complete=false})
          runtime.saveData.supplyQuests[#runtime.saveData.supplyQuests+1]=quest
          local reward=QuestProgression.rewardProfile(cargoKind,distance,runtime.saveData.trait,destination)
          runtime.dialogue={speaker="TASK",text=Targets.label(runtime.saveData,quest,profile.label)..' '..Targets.directions(runtime.saveData,quest)..". Reward: "..reward.scrap.." scrap, "..reward.xp.." XP, coal, and "..reward.minimumRarity.." loot.",timer=7}
      end
      runtime.questOffer=nil; writeSave()
  end

  local function declineQuestOffer()
      if not CoopProgression.allowed(runtime,'quest.decline') then return false,'host_only' end
      if not runtime.questOffer then return false end
      local data=runtime.saveData
      if context.commands then
          local layout=data.stopLayouts[tostring(data.location)]
          local reply=context.commands.submit('quest.decline',{targetId=context.commands.identify(layout),npc=data.currentNPC,kind=runtime.questOffer.kind})
          if not reply.ok then return false,reply.reason end
      else
          data.questAsked=data.questAsked or {}; data.questAsked[tostring(data.location)..':'..tostring(data.currentNPC)]=true; writeSave()
      end
      runtime.dialogue={speaker='TASK',text='Task declined.',timer=5}; runtime.questOffer=nil
      return true
  end

  local function resolveFirstAid(outcome)
      local session=runtime.firstAid
      if not session then return false end
      if session.debugPractice then runtime.firstAid=nil;return true end
      if session.command then
          local name=outcome=="complete" and "firstAid.complete" or "firstAid.step"
          local args={leaseId=session.leaseId,action=outcome~="complete" and "pause" or nil}
          local reply=session.command(name,args)
          local result=reply.ok and reply.result
          if not reply.ok then
              session.command("firstAid.step",{leaseId=session.leaseId,action="pause"})
              session.command("activity.release",{leaseId=session.leaseId})
          end
          runtime.firstAid=nil
          local text=result and result.completed and ("Treatment complete. +"..result.gained.." goodwill. Total goodwill: "..result.total..".")
              or outcome=="complete" and "Treatment not completed. Check the medical supply and return to the patient."
              or "Treatment paused."
          runtime.dialogue={speaker="TASK",text=text,timer=6}
          writeSave(); return true
      end
      runtime.firstAid=nil
      local layout=runtime.saveData.stopLayouts[tostring(session.location)]
      local request=StopHelpProgression.request(layout,session.npc)
      local speaker=Identity.title(runtime.saveData,session.npc or "Traveler")
      if outcome=="complete" then
          local result=StopHelpProgression.completeAid(runtime.saveData,request,session,session.npc,session.location)
          if result.completed then runtime.dialogue={speaker="TASK",text="Treatment complete. +"..result.gained.." goodwill. Total goodwill: "..result.total..".",timer=6}
          else runtime.dialogue={speaker="TASK",text="Medical supply unavailable. Treatment can be retried.",timer=6} end
      elseif outcome=="failed" then
          if session.helpQuestId then HelpQuestSession.retry(runtime.saveData,session.helpQuestId,"Return to the wounded critter to try treatment again.") end
          runtime.dialogue={speaker="TASK",text="Treatment failed. Retry available.",timer=6}
      else
          if session.helpQuestId then HelpQuestSession.pause(runtime.saveData,session.helpQuestId,"Return to the wounded critter to continue treatment.") end
          runtime.dialogue={speaker="TASK",text="Treatment paused.",timer=5}
      end
      writeSave(); return true
  end

  local function talkToNPC()
      ensureStopLayout()
      local authored
      if CoopProgression.allowed(runtime,'conversation.begin') then
          if context.commands then
              local request=Conversations.request(runtime.saveData,runtime.saveData.currentNPC)
              if request then
                  local layout=runtime.saveData.stopLayouts[tostring(runtime.saveData.location)]
                  local reply=context.commands.submit('conversation.begin',{id=request.id,npc=request.npc,targetId=context.commands.identify(layout)})
                  if not reply.ok then
                      runtime.dialogue={speaker='CONVERSATION',text='Conversation unavailable. Stay near the resident and finish any other activity first.',timer=5}
                      return false,reply.reason
                  end
                  authored=Conversations.view(runtime.saveData,Conversations.request(runtime.saveData,request.npc))
              end
          else authored=Conversations.begin(runtime.saveData,runtime.saveData.currentNPC) end
      end
      if authored then
          runtime.questOffer=nil
          showDialogueQuest(authored); if not context.commands then writeSave() end; return
      end
      for _,supply in ipairs(runtime.saveData.supplyQuests or {}) do
          if not supply.complete and Targets.matches(runtime.saveData,supply,runtime.saveData.currentNPC) then
              if context.commands then deliverQuest(supply,QuestProgression.deliveryProfile(supply.cargoKind).thanks); return end
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
      if mail then
          local message=Catalog.mailThanksLines[love.math.random(#Catalog.mailThanksLines)]
          if context.commands then deliverQuest(mail,message)
          else mail.complete=true; giveQuestReward("mail",mail.origin,mail.destination,message); writeSave() end
          return
      end
      local helpRequest=currentHelpRequest()
      if helpRequest and helpRequest.accepted and not helpRequest.complete then
          if helpRequest.kind=="item" then itemHelp(helpRequest) else beginFirstAid(helpRequest) end
          if not context.commands then writeSave() end; return
      end
      local dialogueRequest=currentDialogueRequest()
      if dialogueRequest and dialogueRequest.accepted and not dialogueRequest.complete then beginDialogueQuest(dialogueRequest); writeSave(); return end
      if dialogueRequest and dialogueRequest.complete then
          local followup=HelpDialogueQuests.followup(runtime.saveData,dialogueRequest)
          local status=NpcRelationships.status(runtime.saveData,runtime.saveData.currentNPC)
          runtime.dialogue={speaker=Identity.name(runtime.saveData,runtime.saveData.currentNPC).." • "..status.name,text=followup,timer=8}; writeSave(); return
      end
      local key=tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.currentNPC); local layout=ensureStopLayout()
      -- Read the offer for the NPC being spoken to. A stop can have several
      -- critters, and their quest rolls must not leak between conversations.
      local kind=(layout.npcOffers and layout.npcOffers[runtime.saveData.currentNPC]) or "none"
      if kind=="dialogue" then kind="none" end
      if CoopProgression.allowed(runtime,"quest.accept") and not runtime.saveData.questAsked[key] and kind~="none" and runtime.saveData.location<50 then
          if context.commands then
              local reply=context.commands.submit('quest.offer',{targetId=context.commands.identify(layout),npc=runtime.saveData.currentNPC})
              if not reply.ok then return false,reply.reason end
              runtime.questOffer=reply.result.offer
              runtime.dialogue={speaker='TASK',text=QuestDecisions.text(layout,runtime.saveData.currentNPC,runtime.questOffer,Catalog),timer=30,choice=true}
              return true
          end
          runtime.questOffer={kind=kind}
          local request=StopHelpProgression.request(layout,runtime.saveData.currentNPC)
          local text
          if kind=="mail" then text=Catalog.mailRequestLines[love.math.random(#Catalog.mailRequestLines)]
          elseif kind=="ride" then text=Catalog.rideRequestLines[love.math.random(#Catalog.rideRequestLines)]
          elseif kind=="supplies" then
              layout.deliveryOffers=layout.deliveryOffers or {}
              local deliveryKind=layout.deliveryOffers[runtime.saveData.currentNPC]
              if not deliveryKind then
                  deliveryKind=rollSupplyDelivery()
                  layout.deliveryOffers[runtime.saveData.currentNPC]=deliveryKind
              end
              runtime.questOffer.deliveryKind=deliveryKind
              text=QuestProgression.deliveryProfile(runtime.questOffer.deliveryKind).request
          elseif (kind=="item" or kind=="aid") and request then text=request.text
          elseif kind=="dialogue" and dialogueRequest then text=HelpDialogueQuests.offer(dialogueRequest)
          else text="Trade available." end
          runtime.dialogue={speaker="TASK",text=text,timer=30,choice=true}; writeSave(); return
      end
      local line,status
      if context.commands and context.commands.chatter then line,status=context.commands.chatter(runtime.saveData.currentNPC)
      else line,status=NpcRelationships.npcDialogue(runtime.saveData,runtime.saveData.currentNPC,Catalog.dialogueLines) end
      runtime.questOffer=nil
      runtime.dialogue={speaker=line and (Identity.name(runtime.saveData,runtime.saveData.currentNPC or "Traveler").." • "..status.name) or "CONVERSATION",
          text=line or "No new conversation available.",timer=6}
      writeSave()
  end

  local function enterStop()
      if not CoopProgression.allowed(runtime,"scene.leaveTrain") then return false,"host_only" end
      if context.commands and context.commands.sceneTransitions then
          local reply=context.commands.submit("scene.leaveTrain",{})
          return reply.ok,reply.reason
      end
      runtime.scene="stop"; runtime.player.x,runtime.player.y=270,490; setupNPC(); writeSave()
  end

  local function attemptLeaveTrain()
      if not CoopProgression.allowed(runtime,"scene.leaveTrain") then return false,"host_only" end
      if Home.isHome(runtime.saveData) then return enterStop() end
      local key=tostring(runtime.saveData.location); local encounter=runtime.saveData.encounters[key]
      if beginRequiredEvent(runtime.saveData.location) then return end
      if context.commands then
          if not encounter then
              local reply=context.commands.submit('encounter.roll',{})
              if not reply.ok or reply.savePending then return false,reply.reason or 'save_pending' end
              encounter=runtime.saveData.encounters[key]
          elseif context.commands.checkpointStatus().pending then return false,'save_pending' end
          if encounter.hasMob and not encounter.resolved and (encounter.mobFile or encounter.mobFiles) then beginEncounter(encounter)
          elseif not encounter.hasMob and not runtime.saveData.events[key] then beginRandomEvent()
          else enterStop() end
          return
      end
      -- A test save can force one event at the next travel attempt. Once the
      -- event is recorded, the ordinary stop flow resumes automatically.
      if not encounter and runtime.saveData.forceEventId and not runtime.saveData.events[key] then
          encounter={rolled=true,hasMob=false,resolved=true,testEvent=true}
          runtime.saveData.encounters[key]=encounter
          writeSave()
          beginRandomEvent()
          return
      end
      if not encounter then
          -- Battles should be the primary stop interruption; trail events remain less common.
          -- Story and mystery chapters are checked above; ordinary stops still
          -- favor combat while leaving room for the five random event families.
          local bossStop=runtime.saveData.location==15 or runtime.saveData.location==35 or runtime.saveData.location==47
          local hasMob=bossStop or love.math.random()<EventBalance.encounterChance(runtime.saveData.location)
          local tier=CombatBalance.tierFor(runtime.saveData.location)
          encounter={rolled=true,hasMob=hasMob,resolved=not hasMob,tier=tier,boss=bossStop}
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
        local result=StopHelpProgression.audit(Catalog); result.firstAid=FirstAid.audit(); result.session=HelpQuestSession.audit(); result.dialogue=HelpDialogueQuests.audit()
        result.ready=result.ready and result.firstAid.ready and result.session.ready and result.dialogue.ready
        return result
    end,
    relationshipAudit=function() return NpcRelationships.audit() end,
    questSummary=function()
        local ordinary=QuestProgression.summary(runtime.saveData)
        local help=HelpQuestSession.summary(runtime.saveData)
        local objectives={}
        for _,session in ipairs(help.sessions) do objectives[#objectives+1]={kind="help",destination=session.location,label=session.title..": "..session.objective,sessionId=session.id} end
        for _,objective in ipairs(ordinary.objectives) do objectives[#objectives+1]=objective end
        return {count=#objectives,first=objectives[1] and objectives[1].label or nil,objectives=objectives,help=help}
    end,
    processPassengerArrivals=processPassengerArrivals,
    passengerContributions=passengerContributions,
    pendingMailHere=pendingMailHere,
    acceptQuest=acceptQuest,
    declineQuestOffer=declineQuestOffer,
    chooseHelpDialogue=chooseHelpDialogue,
    updateConversation=function()
        if not context.commands or not runtime.saveData then return end
        local active=runtime.saveData.conversations and runtime.saveData.conversations.active
        if not active then return end
        local presenting=runtime.dialogue and runtime.dialogue.authored
        if presenting and active.phase=='prompt' then
            local request=Conversations.request(runtime.saveData,active.npc)
            local refreshed=Conversations.view(runtime.saveData,request)
            if refreshed then runtime.helpDialogue=refreshed end
            if context.commands.renewConversation and not context.commands.renewConversation(active.id) then
                runtime.helpDialogue=nil; runtime.dialogue=nil; presenting=false
            end
        end
        if not presenting then
            local reply=context.commands.submit('conversation.end',{id=active.id})
            if reply.ok then runtime.helpDialogue=nil end
        end
    end,
    resolveFirstAid=resolveFirstAid,
    talkToNPC=talkToNPC,
    enterStop=enterStop,
    attemptLeaveTrain=attemptLeaveTrain
  }
end

return {new=new}
