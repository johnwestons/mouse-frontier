-- Shared local-host and admitted-guest command adapter. Remote actor states
-- come from host simulation; each guest capability is connected explicitly.
local Authority=require("game.coop_authority")
local Entities=require("game.coop_entities")
local InventoryCommands=require("game.coop_inventory")
local TradeCommands=require("game.coop_trade")
local GiftCommands=require("game.coop_gifts")
local ActivityCommands=require("game.coop_activities")
local QuestCommands=require("game.coop_quests")
local ConversationCommands=require('game.coop_conversations')
local QuestDecisions=require('game.coop_quest_decisions')
local EventCommands=require('game.coop_events')
local FinaleCommands=require('game.coop_finale')
local EncounterCommands=require('game.coop_encounters')
local BattleCommands=require('game.coop_battles')
local RoamingCommands=require('game.coop_roaming')
local ExpeditionCommands=require('game.coop_expedition_assistance')
local TrainObjectCommands=require("game.coop_train_objects")
local SceneCommands=require("game.coop_scenes")
local CarCommands=require("game.coop_cars")
local PoseCommands=require('game.coop_player_pose')
local TravelRequests=require('game.coop_travel_requests')
local Capabilities=require("game.coop_capabilities")
local Schema=require("game.save_schema")
local Items=require("game.item_instances")
local Runtime={}

function Runtime.new(context)
    local runtime,session=context.runtime,context.session
    assert(runtime and session and context.catalog,"inventory commands require runtime, session and catalog")
    local authority,campaign,positionContext,poseContext
    local carTransitions={}
    local remoteActorState
    local function carBusy(id)
        local transition=carTransitions[id]
        if not transition then return false end
        local now=context.clock and context.clock() or runtime.animationClock or 0
        if campaign~=runtime.saveData or transition.epoch~=campaign.coop.sceneEpoch or now>=transition.endsAt then
            carTransitions[id]=nil; return false
        end
        return true
    end
    local sequence=0
    local appliedParty
    local appliedField={}
    local appliedAssistance={}
    local pendingAssistance
    local pendingAmbushParty
    local function current()
        if not session:canWriteCampaign() then return nil,"host_only" end
        if not runtime.saveData then return nil,"no_campaign" end
        if campaign==runtime.saveData and authority and authority.pendingSave then return authority end
        if context.checkpoint and runtime.syncForSave and not (authority and authority.pendingSave) then runtime:syncForSave() end
        session:syncSceneEpoch(runtime.scene)
        if not Entities.ensure(runtime.saveData) then return nil,"invalid_campaign" end
        if Items.enabled(runtime.saveData) and not Items.ensure(runtime.saveData) then return nil,"invalid_campaign" end
        if campaign~=runtime.saveData then
            carTransitions={}
            pendingAssistance=nil
            pendingAmbushParty=nil
            if not Schema.validate(runtime.saveData) then return nil,"invalid_campaign" end
            sequence=sequence+1
            local nextAuthority=Authority.new({campaign=runtime.saveData,sessionId="offline-inventory-"..sequence,
                checkpoint=context.checkpoint,
                randomSeed=runtime.saveData.coop.randomState or (love and love.math and love.math.random(1,2147483646)) or 1,
                clock=context.clock or function() return runtime.animationClock or 0 end})
            local function activityState(state,actorId)
                if not state then return nil end
                for _,lease in pairs(nextAuthority.activityState.resources) do
                    local kind=lease.payload and lease.payload.kind
                    if lease.actorId==actorId and (kind=='weaponRepair' or kind=='maintenance' or kind=='sewing' or kind=='firstAid' or kind=='lastStandAid' or kind=='range') then
                        state.activityBlocked=true; state.activeActivity=kind; break
                    end
                end
                return state
            end
            local domainContext={catalog=context.catalog,car=context.car,actorState=function(actorId)
                if actorId~="host" then
                    local state=remoteActorState and remoteActorState()
                    if state then state.changingCar=carBusy(actorId) end
                    return activityState(state,actorId)
                end
                if not runtime.player then return nil end
                local npc=runtime.npcActor
                return activityState({screen=runtime.state,scene=runtime.scene,x=runtime.player.x,y=runtime.player.y,traveling=runtime.travelTransition~=nil,
                    facing=runtime.player.facing,intentX=runtime.player.intentX,intentY=runtime.player.intentY,
                    changingCar=runtime.carTransition~=nil or carBusy(actorId),
                    travelTime=runtime.travelTransition and runtime.travelTransition.t,
                    encounterActive=not not runtime.battle or (runtime.lastStand and runtime.lastStand.capture)==true
                        or (runtime.trainAmbush and runtime.trainAmbush.phase~="complete") or false,
                    activityBlocked=not not runtime.firstAid or not not runtime.shootingRange or runtime.outfitCraftingOpen==true
                        or (runtime.lastStand and runtime.lastStand.capture)==true or (context.maintenanceSession and context.maintenanceSession.open)==true,
                    activeActivity=runtime.shootingRange and 'range' or runtime.firstAid and "firstAid" or runtime.outfitCraftingOpen and "sewing" or (context.maintenanceSession and context.maintenanceSession.open) and "maintenance" or nil,
                    npc=npc and {id=campaign.currentNPC,x=npc.x,y=npc.y} or nil},actorId)
            end}
            local nextPoseContext={actorState=function(id)
                local base=domainContext.actorState(id); if not base then return nil end
                local result={};for key,value in pairs(base) do result[key]=value end
                local extra=context.poseActorState and context.poseActorState(id)
                for key,value in pairs(extra or {}) do result[key]=value end
                return result
            end}
            PoseCommands.install(nextAuthority,nextPoseContext)
            TravelRequests.install(nextAuthority,domainContext)
            if context.scene then
                for key,value in pairs(context.scene) do domainContext[key]=value end
                SceneCommands.install(nextAuthority,domainContext)
                if domainContext.carArrival then CarCommands.install(nextAuthority,domainContext) end
            end
            domainContext.fieldState=context.fieldState
            domainContext.ambushState=context.ambushState
            domainContext.lastStandState=context.lastStandState
            domainContext.lastStandScene=context.lastStandScene
            domainContext.lastStandPhase=context.lastStandPhase
            domainContext.rangeState=context.rangeState
            domainContext.rangeRandomSeed=nextAuthority.randomSeed
            InventoryCommands.install(nextAuthority,domainContext)
            TradeCommands.install(nextAuthority,domainContext)
            GiftCommands.install(nextAuthority,domainContext)
            ActivityCommands.install(nextAuthority,domainContext)
            QuestCommands.install(nextAuthority,domainContext)
            ConversationCommands.install(nextAuthority,domainContext)
            QuestDecisions.install(nextAuthority,domainContext)
            EventCommands.install(nextAuthority,domainContext)
            FinaleCommands.install(nextAuthority,domainContext)
            EncounterCommands.install(nextAuthority,domainContext)
            BattleCommands.install(nextAuthority,domainContext)
            RoamingCommands.install(nextAuthority,domainContext)
            ExpeditionCommands.install(nextAuthority,domainContext)
            require('game.coop_guns').install(nextAuthority,domainContext)
            require('game.coop_ambush_progression').install(nextAuthority,domainContext)
            require('game.coop_last_stand_progression').install(nextAuthority,domainContext)
            require('game.coop_last_stand_aid').install(nextAuthority,domainContext)
            require('game.coop_last_stand_positions').install(nextAuthority,domainContext)
            require('game.coop_range').install(nextAuthority,domainContext)
            require('game.coop_roaming_encounters').install(nextAuthority,domainContext)
            TrainObjectCommands.install(nextAuthority,domainContext)
            campaign,authority,positionContext,poseContext=runtime.saveData,nextAuthority,domainContext,nextPoseContext
            session.checkpointPending=authority.pendingSave~=nil
        end
        return authority
    end
    local appliedCars={}
    local function accept(service,actorId,name,reply)
        session.checkpointPending=service.pendingSave~=nil
        if reply.ok and actorId=='host' and (name=='expedition.survey' or name=='expedition.cache') and context.applyExpedition then
            if reply.savePending then pendingAssistance={service=service,name=name,reply=reply}
            elseif reply.durable or not context.checkpoint then
                local last=appliedAssistance.host
                if not last or last.sessionId~=service.sessionId or reply.requestId>last.requestId then
                    appliedAssistance.host={sessionId=service.sessionId,requestId=reply.requestId}
                    context.applyExpedition(reply.result)
                end
                pendingAssistance=nil
            end
        end
        if reply.ok and name=='roaming.attack' and context.applyField then
            local last=appliedField[actorId]
            if not last or last.sessionId~=service.sessionId or reply.requestId>last.requestId then
                appliedField[actorId]={sessionId=service.sessionId,requestId=reply.requestId}
                context.applyField(reply.result)
            end
        end
        if reply.ok and reply.result.partyTransition and context.applyParty then
            if name=='ambush.continue' and reply.savePending then
                pendingAmbushParty={service=service,name=name,reply=reply}
                return reply
            end
            if not appliedParty or appliedParty.sessionId~=service.sessionId or reply.requestId>appliedParty.requestId then
                appliedParty={sessionId=service.sessionId,requestId=reply.requestId}
                context.applyParty(reply.result,name)
            end
        end
        if reply.ok and reply.result.personalCar then
            local last=appliedCars[actorId]
            if not last or last.sessionId~=service.sessionId or reply.requestId>last.requestId then
                appliedCars[actorId]={sessionId=service.sessionId,requestId=reply.requestId}
                local now=context.clock and context.clock() or runtime.animationClock or 0
                carTransitions[actorId]={epoch=service.campaign.coop.sceneEpoch,endsAt=now+CarCommands.DURATION}
                if actorId=='host' and context.applyCar then context.applyCar(reply.result) end
            end
        end
        return reply
    end
    local function submit(service,name,args) return accept(service,'host',name,service:submitLocal(name,args)) end
    return {
        clock=context.clock or function() return runtime.animationClock or 0 end,
        authority=current,
        travelRequest=function()
            local service=current();if not service then return nil end
            return TravelRequests.notice(service,positionContext)
        end,
        dismissTravelRequest=function(serial)
            local service=current();return service and TravelRequests.dismiss(service,serial) or false
        end,
        poseState=function(id)
            local service=current();if not service or service.pendingSave then return nil end
            PoseCommands.advance(service,poseContext)
            return PoseCommands.get(service,poseContext,id)
        end,
        rangeView=function(id)
            local service=current(); if not service or service.pendingSave then return nil end
            local range=require('game.coop_range'); local now=service:sweepActivities()
            return range.view(service.campaign,service.activityState,service.bindings,now,id,positionContext)
        end,
        advanceRange=function(dt)
            local service=current(); if not service or service.pendingSave then return false end
            if service.campaign.coop.revision>=2147483647 then return false end
            local range=require('game.coop_range'); local now=service:sweepActivities()
            local completed,changed=range.advance(service.campaign,service.activityState,service.bindings,now,positionContext,dt)
            if changed then
                service.campaign.coop.revision=service.campaign.coop.revision+1
            end
            for _,id in ipairs(completed) do
                if id=='host' then
                    local lease=range.occupied(service.campaign,service.activityState,service.bindings,now,id,positionContext)
                    local saved=require('game.coop_range_state').session(service.campaign,id)
                    if lease and saved then submit(service,'range.configure',{leaseId=lease.id,roundRevision=saved.roundRevision,action='complete'}) end
                end
            end
            session.checkpointPending=service.pendingSave~=nil
            return changed
        end,
        lastStandPosition=function(id)
            local service=current(); if not service or service.pendingSave then return nil end
            local positions=require('game.coop_last_stand_positions'); local now=service:sweepActivities()
            if not positions.maintain or not positions.occupied then return nil end
            positions.maintain(service.campaign,service.activityState,service.bindings,now,positionContext)
            local lease=positions.occupied(service.campaign,service.activityState,service.bindings,now,id)
            if not lease then return nil end
            return {windowId=lease.windowId,leaseId=lease.id,domain=lease.domain,phaseRevision=lease.domain.phaseRevision}
        end,
        carBusy=carBusy,
        activityBusy=function(id,kind)
            if campaign~=runtime.saveData or not authority then return false end
            authority:sweepActivities()
            for _,lease in pairs(authority.activityState.resources) do
                if lease.actorId==id and lease.payload and lease.payload.kind==kind then return true end
            end
            return false
        end,
        patientBusy=function(npc)
            if campaign~=runtime.saveData or not authority then return false end
            local now=context.clock and context.clock() or runtime.animationClock or 0
            for _,lease in pairs(authority.activityState.resources) do
                local payload=lease.payload
                if payload and (payload.kind=='firstAid' or payload.kind=='conversation') and payload.npc==npc
                    and lease.sceneEpoch==campaign.coop.sceneEpoch and now<lease.expiresAt
                    and authority.bindings[lease.actorId]==lease.generation then return true end
            end
            return false
        end,
        setRemoteActorState=function(provider) remoteActorState=provider end,
        renewConversation=function(id)
            if campaign~=runtime.saveData or not authority then return false end
            return ConversationCommands.renew(authority,id)
        end,
        remote=function(generation,request)
            local service,reason=current()
            if not service then return {ok=false,reason=reason} end
            local allowed,errorMessage=Capabilities.authorize(request.command,'guest')
            if not allowed then return {ok=false,reason=errorMessage} end
            -- Expand this list only with each domain's live remote actor/UI audit.
            if not ({['progression.request']=true,['player.pose']=true,['player.car']=true,['inventory.swap']=true,['inventory.consume']=true,['loot.drop']=true,['loot.pickup']=true,
                ['storage.transfer']=true,['mailbox.collect']=true,['merchant.buy']=true,['merchant.sell']=true,
                ['train.fuel']=true,['train.upgrade']=true,['train.engineUpgrade']=true,['radio.station']=true,
                ['decoration.acquire']=true,['decoration.place']=true,['decoration.collect']=true,['activity.release']=true,
                ['npc.gift']=true,['passenger.equip']=true,['npc.chatter']=true,['passenger.chatter']=true,
                ['maintenance.acquire']=true,['maintenance.step']=true,['maintenance.complete']=true,
                ['weaponRepair.acquire']=true,['weaponRepair.step']=true,['weaponRepair.complete']=true,
                ['outfit.craft']=true,['firstAid.acquire']=true,['firstAid.step']=true,['firstAid.complete']=true,
                ['quest.help']=true,['quest.deliver']=true,['battle.move']=true,['battle.attack']=true,['battle.guard']=true,
                ['battle.heal']=true,['battle.item']=true,['battle.swap']=true,['battle.ability']=true,['battle.endTurn']=true,
                ['roaming.attack']=true,['expedition.survey']=true,['expedition.cache']=true,
                ['gun.fire']=true,['gun.reload']=true,['gun.cover']=true,['gun.mode']=true,['gun.select']=true,
                ['lastStand.supply']=true,['lastStand.aid']=true,['lastStand.position']=true,
                ['range.acquire']=true,['range.configure']=true,['range.ammo']=true,['range.fire']=true,
                ['range.reload']=true,['range.release']=true})[request.command] then return {ok=false,reason='guest_action_unavailable'} end
            if (request.command=='npc.gift' or request.command=='passenger.equip') and request.args.sourceItem==nil then return {ok=false,reason='item_selection_required'} end
            if (request.command=='train.upgrade' or request.command=='train.engineUpgrade')
                and (request.args.quotedPrice==nil or request.command=='train.engineUpgrade' and request.args.quotedLevel==nil) then return {ok=false,reason='quote_required'} end
            if request.command=='train.fuel' and (request.args.source==nil or request.args.sourceItem==nil) then return {ok=false,reason='item_selection_required'} end
            if request.command=='merchant.buy' and (request.args.quotedPrice==nil or request.args.quotedItem==nil) then
                return {ok=false,reason='quote_required'}
            end
            if request.command=='merchant.sell' and request.args.sourceItem==nil then return {ok=false,reason='item_selection_required'} end
            if request.command=='inventory.swap' or request.command=='inventory.consume' or request.command=='loot.drop'
                or request.command=='storage.transfer' or request.command=='mailbox.collect' then
                if request.args.sourceItem==nil or request.command=='inventory.swap' and request.args.targetItem==nil then
                    return {ok=false,reason='item_selection_required'}
                end
            end
            return accept(service,'companion',request.command,service:execute('companion',generation,request))
        end,
        sceneTransitions=context.scene~=nil,
        checkpointStatus=function()
            local status=campaign==runtime.saveData and authority and authority:checkpointStatus() or {pending=false}
            session.checkpointPending=status.pending
            return status
        end,
        retryCheckpoint=function()
            if campaign~=runtime.saveData or not authority then return true end
            local saved=authority:retryCheckpoint()
            session.checkpointPending=authority.pendingSave~=nil
            if saved and pendingAssistance and pendingAssistance.service==authority then
                local pending=pendingAssistance; pending.reply.durable=true; pending.reply.savePending=nil
                accept(authority,'host',pending.name,pending.reply)
            end
            if saved and pendingAmbushParty and pendingAmbushParty.service==authority then
                local pending=pendingAmbushParty; pendingAmbushParty=nil
                pending.reply.durable=true; pending.reply.savePending=nil
                accept(authority,'host',pending.name,pending.reply)
            end
            return saved
        end,
        suspendActivities=function()
            if campaign==runtime.saveData and authority then authority:suspendActivities() end
        end,
        submit=function(name,args)
            local service,reason=current()
            if not service then return {ok=false,reason=reason} end
            return submit(service,name,args)
        end,
        identify=function(value)
            local service=current()
            if not service or type(value)~="table" then return nil end
            return value.entityId
        end,
        trade=function(name,source,index,quote)
            local service,reason=current()
            if not service then return {ok=false,reason=reason} end
            local target,merchantId,listingId
            if source.kind=="stop" then target=source.budgetOwner; merchantId=source.merchant
            elseif source.kind=="caravan" then
                merchantId=runtime.tradeMerchantId
                for _,record in ipairs(Entities.records(campaign)) do
                    if record.kind=="caravan" and record.value.id==campaign.crowCaravans.activeCampId then target=record.value; break end
                end
                if name=="merchant.buy" then listingId=source.stock[index] and source.stock[index].id end
            end
            local reply=submit(service,name,{targetId=target and target.entityId,merchantId=merchantId,index=index,listingId=listingId,
                quotedPrice=quote and quote.price,quotedItem=quote and quote.itemName})
            return reply.ok and reply.result or {ok=false,reason=reply.reason}
        end,
        gift=function(npc,source,chest,equipOnly)
            local service,reason=current()
            if not service then return {ok=false,reason=reason} end
            local target
            if runtime.scene=="train" then
                for _,passenger in ipairs(campaign.passengers) do
                    if passenger.npc==npc then target=passenger; break end
                end
            else target=campaign.stopLayouts[tostring(campaign.location)] end
            local command=equipOnly and runtime.scene=="train" and "passenger.equip" or "npc.gift"
            local reply=submit(service,command,{targetId=target and target.entityId,npc=npc,source=source,
                containerId=source.kind=="chest" and chest and chest.entityId or nil})
            if reply.ok and reply.result.equipped and runtime.scene~="train" and runtime.npcActor then
                runtime.npcActor.weapon=reply.result.item
            end
            return reply.ok and reply.result or {ok=false,reason=reply.reason}
        end,
        chatter=function(npc,passenger)
            local service,reason=current(); if not service then return nil,{name='Unavailable',reason=reason} end
            local target=passenger or campaign.stopLayouts[tostring(campaign.location)]
            local reply=submit(service,passenger and 'passenger.chatter' or 'npc.chatter',{targetId=target and target.entityId,npc=npc})
            if not reply.ok then return nil,{name='Unavailable',reason=reply.reason} end
            return context.catalog.dialogueLines[reply.result.lineIndex],reply.result.status
        end,
    }
end

return Runtime
