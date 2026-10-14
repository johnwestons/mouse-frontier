local Leases=require("game.coop_leases")
local Rules=require("game.maintenance_rules")
local Commands={}
local RESOURCE="train:maintenance"

function Commands.install(authority,context)
    for _,command in ipairs({"maintenance.acquire","maintenance.step","maintenance.complete"}) do
        authority:register(command,function(data,actorId,args,transaction)
            local fields=command=="maintenance.acquire" and {} or command=="maintenance.step"
                and {leaseId=true,target=true,renew=true} or {leaseId=true}
            if type(args)~="table" then return nil,"invalid_args" end
            for key in pairs(args) do if not fields[key] then return nil,"invalid_args" end end
            local actor,reason=context.trainActor(data,actorId,"maintenance"); if not actor then return nil,reason end
            if command=="maintenance.acquire" then
                return {scopes={"activity:"..RESOURCE},apply=function()
                    local progress=Rules.new(data)
                    local lease,message=Leases.acquire(transaction.state,RESOURCE,actorId,transaction.generation,
                        data.coop.sceneEpoch,transaction.now,{kind="maintenance",carIndex=actor.activeCar,progress=progress})
                    if not lease then return nil,message end
                    return {ok=true,leaseId=lease.id,targetDoses=progress.targetDoses,completed=progress.completed}
                end}
            end
            if type(args.leaseId)~="string" or not args.leaseId:match("^l[1-9]%d*$") then return nil,"invalid_args" end
            if command=="maintenance.step" then
                if args.renew~=nil then
                    if args.renew~=true or args.target~=nil then return nil,"invalid_args" end
                elseif type(args.target)~="number" or args.target%1~=0 or not Rules.DOSES[args.target] then return nil,"invalid_args" end
            end
            local lease,message=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
            if not lease then return nil,message end
            if lease.resource~=RESOURCE or lease.payload.kind~="maintenance" then return nil,"wrong_activity" end
            if actor.activeCar~=lease.payload.carIndex or lease.payload.progress.location~=data.location then return nil,"activity_unavailable" end
            local scopes={"activity:"..RESOURCE}
            if command=="maintenance.complete" then scopes[#scopes+1]="resources"; scopes[#scopes+1]="train" end
            return {scopes=scopes,apply=function()
                local result
                if command=="maintenance.complete" then
                    result=Rules.complete(lease.payload.progress,data)
                    if result.ok or result.reason=="already" then Leases.release(transaction.state,lease) end
                elseif args.renew then result={ok=true}
                else result=Rules.point(lease.payload.progress,args.target,data) end
                lease.expiresAt=transaction.now+Leases.TIMEOUT
                return result
            end}
        end)
    end
end

return Commands
