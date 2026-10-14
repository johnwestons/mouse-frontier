local Players=require("game.coop_players")
local Entities=require("game.coop_entities")
local Leases=require("game.coop_leases")
local Inventory=require("game.inventory")
local Items=require("game.item_instances")
local Config=require("game.config")
local Access=require('game.coop_object_access')
local Commands={}
local limits={x={0,Config.baseWidth},y={0,Config.baseHeight},scale={.5,2.5},rotation={0,math.pi*2},
    layer={-100000,100000},hue={0,1},saturation={0,2}}
local function fields(args,allowed)
    for key in pairs(args) do if not allowed[key] then return false end end
    return true
end
local function object(data,actorId,id,context)
    local actor=Players.forActor(data,actorId)
    local state=context.actorState(actorId)
    local item,entry=Access.decoration(actor,id,state)
    if not item or data.trainAmbush and data.trainAmbush.active then
        return nil,"object_unavailable"
    end
    return item,entry
end

function Commands.install(authority,context)
    authority:register("decoration.acquire",function(data,actorId,args,transaction)
        if not fields(args,{entityId=true}) then return nil,"invalid_args" end
        local item,reason=object(data,actorId,args.entityId,context); if not item then return nil,reason end
        local resource="decoration:"..item.entityId
        return {scopes={"activity:"..resource,"entity:"..item.entityId},apply=function()
            local lease,errorMessage=Leases.acquire(transaction.state,resource,actorId,transaction.generation,data.coop.sceneEpoch,
                transaction.now,{kind="decoration",entityId=item.entityId,carIndex=item.carIndex or 1})
            if not lease then return nil,errorMessage end
            return {ok=true,leaseId=lease.id,entityId=item.entityId}
        end}
    end)
    for _,command in ipairs({"decoration.place","decoration.collect"}) do
        authority:register(command,function(data,actorId,args,transaction)
            if not fields(args,command=="decoration.place" and {leaseId=true,values=true} or {leaseId=true}) then return nil,"invalid_args" end
            if command=="decoration.place" then
                if type(args.values)~="table" then return nil,"invalid_args" end
                for key,value in pairs(args.values) do
                    local range=limits[key]
                    if not range or type(value)~="number" or value~=value or value<range[1] or value>range[2]
                        or key=="layer" and value%1~=0 then return nil,"invalid_placement" end
                end
            end
            local lease,reason=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
            if not lease then return nil,reason end
            if lease.payload.kind~="decoration" then return nil,"wrong_activity" end
            local item,entry=object(data,actorId,lease.payload.entityId,context); if not item then return nil,entry end
            if (item.carIndex or 1)~=lease.payload.carIndex then return nil,"object_unavailable" end
            local actor=Players.forActor(data,actorId)
            local scopes={"activity:"..lease.resource,"entity:"..item.entityId}
            if command=="decoration.collect" then
                if item.permanent then return nil,"permanent" end
                if item.storage and next(item.storage) then return nil,"container_not_empty" end
                if not Inventory.firstEmptySlot(actor) then return nil,"inventory_full" end
                scopes[#scopes+1]="player:"..actorId
            end
            return {scopes=scopes,apply=function()
                if command=="decoration.collect" then
                    local slot=Inventory.firstEmptySlot(actor)
                    Items.write(actor,nil,{kind="inventory",index=slot},item.name,item.itemInstance)
                    table.remove(entry.parent,entry.key); Leases.release(transaction.state,lease)
                    return {ok=true,item=item.name,slot=slot}
                end
                -- Preserve the existing canvas editor, including layering and
                -- intentional overlap. These visual props do not block paths.
                for key,value in pairs(args.values) do item[key]=value end
                lease.expiresAt=transaction.now+Leases.TIMEOUT
                return {ok=true,entityId=item.entityId}
            end}
        end)
    end

    authority:register("radio.station",function(data,actorId,args)
        if not fields(args,{entityId=true,station=true,rainEnabled=true})
            or (args.station==nil and args.rainEnabled==nil)
            or args.station~=nil and args.station~="8bit" and args.station~="chill" and args.station~="vibes"
            or args.rainEnabled~=nil and type(args.rainEnabled)~="boolean" then return nil,"invalid_args" end
        local actor=Players.forActor(data,actorId)
        local state=context.actorState(actorId)
        local item=Access.radio(actor,args.entityId,state)
        if not item then return nil,"radio_unavailable" end
        return {scopes={"radio","entity:"..item.entityId},apply=function()
            data.audio=data.audio or {}
            if args.station~=nil then data.audio.station=args.station end
            if args.rainEnabled~=nil then data.audio.rainEnabled=args.rainEnabled end
            return {ok=true,station=data.audio.station or 'chill',rainEnabled=data.audio.rainEnabled~=false}
        end}
    end)
end
return Commands
