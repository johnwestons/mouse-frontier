local Players=require("game.coop_players")
local Leases=require("game.coop_leases")
local Crafting=require("game.outfit_crafting")
local Sewing={}
local RESOURCE="train:sewing"
local FIELDS={acquire={action=true},renew={action=true,leaseId=true},suspend={action=true,leaseId=true},
    start={action=true,leaseId=true,recipeId=true},point={action=true,leaseId=true,x=true,y=true},
    pullStart={action=true,leaseId=true},pullRelease={action=true,leaseId=true},
    adjust={action=true,leaseId=true,direction=true},collect={action=true,leaseId=true}}

local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function clamp(value) return math.max(0,math.min(1,value)) end
local function tension(payload,now)
    return clamp((payload.tension or 0)+(payload.pullStartedAt and math.max(0,now-payload.pullStartedAt)*.24 or 0))
end

function Sewing.install(authority,context)
    authority:register("outfit.craft",function(data,actorId,args,transaction)
        local allowed=type(args)=="table" and FIELDS[args.action]
        if not allowed then return nil,"invalid_args" end
        for key in pairs(args) do if not allowed[key] then return nil,"invalid_args" end end
        local actor,reason=context.trainActor(data,actorId,"sewing"); if not actor then return nil,reason end
        local scopes={"activity:"..RESOURCE,"outfit"}
        local project=Crafting.project(data)
        local ownerId=project and (project.ownerPlayerId or "host") or actorId
        if not Players.get(data,ownerId) then return nil,"project_unavailable" end
        if args.action=="acquire" then
            return {scopes=scopes,apply=function()
                local lease,message=Leases.acquire(transaction.state,RESOURCE,actorId,transaction.generation,
                    data.coop.sceneEpoch,transaction.now,{kind="sewing",carIndex=actor.activeCar,tension=0})
                if not lease then return nil,message end
                if project then project.ownerPlayerId=ownerId end
                return {ok=true,action='acquire',leaseId=lease.id,expiresAt=lease.expiresAt,expiresIn=Leases.TIMEOUT,
                    ownerPlayerId=ownerId,tension=0,pulling=false}
            end}
        end
        if type(args.leaseId)~="string" or not args.leaseId:match("^l[1-9]%d*$") then return nil,"invalid_args" end
        local lease,leaseError=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
        if not lease then return nil,leaseError end
        if lease.resource~=RESOURCE or lease.payload.kind~="sewing" then return nil,"wrong_activity" end
        if actor.activeCar~=lease.payload.carIndex then return nil,"activity_unavailable" end
        local stage=Crafting.stage(data)
        if args.action=="start" then
            if type(args.recipeId)~="string" or #args.recipeId>80 then return nil,"invalid_args" end
            scopes[#scopes+1]="player:"..actorId
        elseif args.action=="collect" then scopes[#scopes+1]="player:"..ownerId
        elseif args.action=="point" then
            if not stage or stage.kind~="point" then return nil,"wrong_step" end
            if not finite(args.x) or not finite(args.y) or args.x<0 or args.x>1 or args.y<0 or args.y>1 then return nil,"invalid_args" end
        elseif args.action=="pullStart" or args.action=="pullRelease" or args.action=="adjust" then
            if not stage or stage.kind~="tension" then return nil,"wrong_step" end
            if args.action=="adjust" and args.direction~=-1 and args.direction~=1 then return nil,"invalid_args" end
        end
        return {scopes=scopes,apply=function()
            local payload=lease.payload
            local result
            if args.action=="start" then
                result=Crafting.start(actor,args.recipeId)
                if result.ok then result.project.ownerPlayerId=actorId; ownerId=actorId; payload.tension=0; payload.pullStartedAt=nil end
            elseif args.action=="point" then result=Crafting.act(actor,{kind="point",x=args.x,y=args.y})
            elseif args.action=="pullStart" then
                if payload.pullStartedAt then return nil,"already_pulling" end
                payload.pullStartedAt=transaction.now
                result={ok=true,tension=payload.tension or 0}
            elseif args.action=="adjust" then
                payload.tension=tension(payload,transaction.now)
                payload.pullStartedAt=nil
                payload.tension=clamp((payload.tension or 0)+args.direction*.05)
                result={ok=true,tension=payload.tension}
            elseif args.action=="pullRelease" then
                local value=tension(payload,transaction.now)
                payload.tension=value; payload.pullStartedAt=nil
                result=Crafting.act(actor,{kind="tension",value=value}); result.tension=value
            elseif args.action=="suspend" then
                payload.pullStartedAt=nil; payload.tension=0; result={ok=true,tension=0}
            elseif args.action=="collect" then
                result=Crafting.finish(Players.forActor(data,ownerId))
                if result.ok and ownerId~=actorId then
                    result.message=ownerId=="host" and "Finished upgrade added to the host's backpack."
                        or "Finished upgrade added to the companion's backpack."
                end
            else result={ok=true,tension=tension(payload,transaction.now)} end
            if result.stageComplete then payload.tension=0; payload.pullStartedAt=nil end
            lease.expiresAt=transaction.now+Leases.TIMEOUT
            result.action=args.action; result.leaseId=lease.id; result.expiresIn=Leases.TIMEOUT
            result.expiresAt=lease.expiresAt; result.ownerPlayerId=ownerId
            result.tension=tension(payload,transaction.now); result.pulling=payload.pullStartedAt~=nil
            if not result.ok then
                result.reason=args.action=='start' and (project and 'project_busy' or 'materials')
                    or result.inventoryFull and 'inventory_full' or 'project_incomplete'
            end
            return result
        end}
    end)
end

return Sewing
