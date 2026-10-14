-- Host choices use the same detached command transaction as guest assistance.
-- Saved presentation carries IDs and outcomes; speech remains in authored_dialogue.
local Players=require('game.coop_players')
local Conversations=require('game.npc_conversations')
local Access=require('game.coop_recipient_access')
local QuestAccess=require('game.coop_quest_access')
local Leases=require('game.coop_leases')
local Random=require('game.coop_random')
local Progression=require('game.quest_progression')
local Inventory=require('game.inventory')
local House=require('game.house')
local Battle=require('game.battle_rules')
local P=require('game.net.protocol')
local Commands={}

local function active(data,id)
    local value=data.conversations and data.conversations.active
    if value and value.id==id and value.sceneEpoch==data.coop.sceneEpoch
        and value.scene==data.scene and value.location==data.location then return value end
end
local function leaseFor(state,id)
    for _,lease in pairs(state.resources) do
        if lease.payload and lease.payload.kind=='conversation' and lease.payload.id==id then return lease end
    end
end

function Commands.install(authority,context)
    local function recipient(data,args)
        local found=Access.find(data,args.targetId,args.npc,context.actorState('host'),true)
        if not found or found.kind~='resident' then return nil,'recipient_unavailable' end
        return found
    end
    authority:register('conversation.begin',function(data,actorId,args,transaction)
        if not P.fields(args,{targetId=true,npc=true,id=true}) or not P.text(args.id,64) then return nil,'invalid_args' end
        local target,reason=recipient(data,args); if not target then return nil,reason end
        local request=Conversations.request(data,args.npc)
        if not request or request.id~=args.id then return nil,'conversation_unavailable' end
        local current=data.conversations.active
        if current and (not active(data,args.id) or current.phase~='prompt') then return nil,'conversation_busy' end
        if Leases.npcBusy(transaction.state,args.targetId,args.npc) then return nil,'activity_busy' end
        return {scopes={'story:conversations','activity:conversation:'..args.id},apply=function()
            local lease,err=Leases.acquire(transaction.state,'conversation:'..args.id,actorId,transaction.generation,
                data.coop.sceneEpoch,transaction.now,{kind='conversation',id=args.id,targetId=args.targetId,npc=args.npc})
            if not lease then return nil,err end
            local view=Conversations.begin(data,args.npc)
            if not view then return nil,'conversation_unavailable' end
            data.conversations.active={id=args.id,targetId=args.targetId,npc=args.npc,location=data.location,
                scene=data.scene,sceneEpoch=data.coop.sceneEpoch,phase='prompt'}
            return {ok=true,id=args.id,leaseId=lease.id}
        end}
    end)
    authority:register('conversation.choose',function(data,actorId,args,transaction)
        if not P.fields(args,{id=true,index=true}) or not P.text(args.id,64) or not P.integer(args.index,1,3) then return nil,'invalid_args' end
        local current=active(data,args.id)
        if not current or current.phase~='prompt' then return nil,'conversation_unavailable' end
        local target,reason=recipient(data,current); if not target then return nil,reason end
        local request=Conversations.request(data,current.npc)
        local view=Conversations.view(data,request)
        if not view or request.id~=args.id or not view.choices[args.index] or not view.choices[args.index].enabled then return nil,'choice_unavailable' end
        local lease=leaseFor(transaction.state,args.id)
        if not lease or not Leases.find(transaction.state,lease.id,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now) then return nil,'lease_expired' end
        local recipients,scopes={}, {'story:conversations','activity:conversation:'..args.id,'resources','rng','world:rewardDelivery'}
        for _,id in ipairs({Players.HOST,Players.COMPANION}) do
            local state=context.actorState(id)
            if authority.bindings[id]~=nil and state and state.screen=='game' and state.scene==data.scene then
                recipients[#recipients+1]=id; scopes[#scopes+1]='player:'..id
            end
        end
        local container=QuestAccess.rewardContainer(data,context.catalog)
        if container then scopes[#scopes+1]='entity:'..container.entityId end
        return {scopes=scopes,apply=function()
            local result=Conversations.choose(data,request,args.index,{
                random=Random.range(Random.generator(data,transaction.randomSeed)),
                storeItem=function(name)
                    return Progression.storeRewardItem(data,context.catalog,Inventory,name,function(item)
                        House.storeLoot(data,context.catalog,item,data.location)
                    end)
                end,
                gainExperience=function(xp)
                    for _,id in ipairs(recipients) do Battle.gainExperience(Players.forActor(data,id),xp) end
                end})
            if not result.completed then return nil,'choice_unavailable' end
            local completed=data.conversations.completed[args.id]
            completed.rewardRecipients={}
            for _,id in ipairs(recipients) do completed.rewardRecipients[id]=Conversations.xp end
            current.phase='response'; current.notice=result.notice
            Leases.release(transaction.state,lease)
            return {ok=true,completed=true,id=args.id,notice=result.notice,recipients=completed.rewardRecipients}
        end}
    end)
    authority:register('conversation.end',function(data,actorId,args,transaction)
        if not P.fields(args,{id=true}) or not P.text(args.id,64) then return nil,'invalid_args' end
        local current=active(data,args.id)
        if not current then return nil,'conversation_unavailable' end
        return {scopes={'story:conversations','activity:conversation:'..args.id},apply=function()
            local lease=leaseFor(transaction.state,args.id)
            if lease then Leases.release(transaction.state,lease) end
            data.conversations.active=nil
            return {ok=true,ended=true,id=args.id}
        end}
    end)
end

-- A trusted host frame renews only its own ephemeral presentation lease. No
-- peer packet, saved lease, reward, or campaign decision is accepted here.
function Commands.renew(authority,id)
    local lease=leaseFor(authority.activityState,id)
    if not lease then return false end
    local now=authority.clock()
    if lease.actorId~='host' or lease.generation~=authority.bindings.host
        or lease.sceneEpoch~=authority.campaign.coop.sceneEpoch or now>=lease.expiresAt then return false end
    lease.expiresAt=now+Leases.TIMEOUT
    return true
end
return Commands
