local Players=require("game.coop_players")
local Items=require("game.item_instances")
local Leases=require("game.coop_leases")
local Loot=require("game.loot_progression")
local Activities={}
local Access=require('game.coop_activity_access')
local WORKBENCH="train:weapon-repair"

local function shape(args,allowed)
    if type(args)~="table" then return false end
    for key in pairs(args) do if not allowed[key] then return false end end
    return true
end

local function reference(value,prefix)
    return type(value)=="string" and #value<=16 and value:match("^"..prefix.."[1-9]%d*$")~=nil
end

function Activities.repairQuality(elapsed)
    local phase=(elapsed*.86)%1
    return phase>=.62 and phase<=.69 and "perfect" or phase>=.53 and phase<=.78 and "good" or "miss"
end

function Activities.install(authority,context)
    local catalog=assert(context.catalog)
    local actorState=assert(context.actorState)
    local function trainActor(data,actorId,kind)
        local state=actorState(actorId)
        local actor=Players.forActor(data,actorId)
        if not Access.train(actor,state,kind) then return nil,'activity_unavailable' end
        return actor
    end

    authority:register("weaponRepair.acquire",function(data,actorId,args,transaction)
        if not shape(args,{itemId=true}) or not reference(args.itemId,"i") then return nil,"invalid_args" end
        local actor,reason=trainActor(data,actorId); if not actor then return nil,reason end
        local status=Loot.repairStatus(actor,catalog,args.itemId)
        if not status.name then return nil,"ownership" end
        if not status.needed then return nil,"ready" end
        if not status.hasPart then return nil,"part" end
        if not status.affordable then return nil,"scrap" end
        return {scopes={"activity:"..WORKBENCH,"player:"..actorId},apply=function()
            local lease,errorMessage=Leases.acquire(transaction.state,WORKBENCH,actorId,transaction.generation,
                data.coop.sceneEpoch,transaction.now,{kind="weaponRepair",itemId=args.itemId,durability=status.durability,
                    carIndex=actor.activeCar,playerRevision=(data.coop.revisions["player:"..actorId] or 0)+1})
            if not lease then return nil,errorMessage end
            return {ok=true,leaseId=lease.id,itemId=args.itemId,startedAt=lease.startedAt,expiresAt=lease.expiresAt,elapsed=0,expiresIn=Leases.TIMEOUT}
        end}
    end)

    authority:register("weaponRepair.complete",function(data,actorId,args,transaction)
        if not shape(args,{leaseId=true}) or not reference(args.leaseId,"l") then return nil,"invalid_args" end
        local actor,reason=trainActor(data,actorId,'weaponRepair'); if not actor then return nil,reason end
        local lease,leaseError=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
        if not lease then return nil,leaseError end
        local payload=lease.payload
        if payload.kind~="weaponRepair" or lease.resource~=WORKBENCH then return nil,"wrong_activity" end
        if actor.activeCar~=payload.carIndex then return nil,"activity_unavailable" end
        if (data.coop.revisions["player:"..actorId] or 0)~=payload.playerRevision then return nil,"activity_changed" end
        local item=Items.owned(actor,payload.itemId)
        if not item or item.durability~=payload.durability then return nil,"activity_changed" end
        return {scopes={"activity:"..WORKBENCH,"player:"..actorId,"resources"},apply=function()
            local quality=Activities.repairQuality(transaction.now-lease.startedAt)
            local result=Loot.completeRepair(actor,catalog,payload.itemId,quality)
            -- A miss is a completed attempt, without material/resource costs.
            -- Release even when resources changed while the gauge was running.
            Leases.release(transaction.state,lease)
            return result
        end}
    end)

    authority:register('weaponRepair.step',function(data,actorId,args,transaction)
        if not shape(args,{leaseId=true,renew=true}) or not reference(args.leaseId,'l') or args.renew~=true then return nil,'invalid_args' end
        local actor,reason=trainActor(data,actorId,'weaponRepair'); if not actor then return nil,reason end
        local lease,message=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
        if not lease then return nil,message end
        local payload=lease.payload
        if lease.resource~=WORKBENCH or payload.kind~='weaponRepair' then return nil,'wrong_activity' end
        if actor.activeCar~=payload.carIndex then return nil,'activity_unavailable' end
        local item=Items.owned(actor,payload.itemId)
        if (data.coop.revisions['player:'..actorId] or 0)~=payload.playerRevision
            or not item or item.durability~=payload.durability then return nil,'activity_changed' end
        return {scopes={'activity:'..WORKBENCH},apply=function()
            lease.expiresAt=transaction.now+Leases.TIMEOUT
            return {ok=true,leaseId=lease.id,elapsed=transaction.now-lease.startedAt,expiresIn=Leases.TIMEOUT}
        end}
    end)

    authority:register("activity.release",function(data,actorId,args,transaction)
        if not shape(args,{leaseId=true}) or not reference(args.leaseId,"l") then return nil,"invalid_args" end
        local lease,reason=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
        if not lease then return nil,reason end
        return {scopes={"activity:"..lease.resource},apply=function()
            Leases.release(transaction.state,lease)
            return {ok=true,released=true,leaseId=args.leaseId}
        end}
    end)
    require("game.coop_sewing").install(authority,{trainActor=trainActor})
    require("game.coop_maintenance").install(authority,{trainActor=trainActor})
    require("game.coop_first_aid").install(authority,context)
end

return Activities
