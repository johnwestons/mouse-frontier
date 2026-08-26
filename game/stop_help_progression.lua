local StopHelp={}

StopHelp.policyVersion=3
StopHelp.itemRequests={
    {item="water-bottle",label="a bottle of clean water",text="Our well tastes like rust. Could you spare a bottle of clean water?"},
    {item="food-ration",label="a food ration",text="We have a hungry youngster here. Could you spare a food ration?"},
    {item="field-bandage-roll",label="a bandage roll",text="We used our last clean bandage. Could you bring us a bandage roll?"},
    {item="coal-chunk",label="a chunk of coal",text="The night will be cold. Could you spare a chunk of coal for our stove?"},
    {item="small-oil-canister",label="a small oil canister",text="Our water pump is seizing up. Could you spare a small oil canister?"},
}

local function hash(text)
    local result=0
    for index=1,#(text or "") do result=(result*31+text:byte(index))%100000 end
    return result
end

function StopHelp.ensure(data)
    data.goodwill=math.max(0,math.floor(tonumber(data.goodwill) or 0))
    data.helpHistory=type(data.helpHistory)=="table" and data.helpHistory or {}
    return data.goodwill,data.helpHistory
end

function StopHelp.tier(points)
    points=math.max(0,math.floor(tonumber(points) or 0))
    if points>=24 then return {name="Trail Guardian",minimum=24,ending="A whole network of settlements remembers your help."} end
    if points>=12 then return {name="Trusted Friend",minimum=12,ending="Families along the rails know they can rely on you."} end
    if points>=5 then return {name="Helping Hand",minimum=5,ending="Word of your kindness is spreading down the tracks."} end
    return {name="New Neighbor",minimum=0,ending="Every act of help can make the frontier kinder."}
end

function StopHelp.status(data)
    local points,history=StopHelp.ensure(data); local tier=StopHelp.tier(points)
    return {points=points,tier=tier.name,helpCount=#history,ending=tier.ending}
end

function StopHelp.add(data,amount,kind,npc,location)
    local points,history=StopHelp.ensure(data)
    local gained=math.max(0,math.floor(tonumber(amount) or 0))
    data.goodwill=points+gained
    if gained>0 then history[#history+1]={kind=kind or "help",npc=npc,location=math.max(1,math.floor(tonumber(location) or 1)),points=gained} end
    return gained,data.goodwill,StopHelp.tier(data.goodwill)
end

function StopHelp.ensureRequest(layout,npc,kind,location)
    layout.helpRequests=layout.helpRequests or {}
    if kind~="item" and kind~="aid" then return nil end
    local request=layout.helpRequests[npc]
    if not request or request.kind~=kind then
        request={kind=kind,accepted=false,complete=false}
        if kind=="item" then
            local index=(hash((npc or "traveler")..":"..tostring(location or 1))%#StopHelp.itemRequests)+1
            local profile=StopHelp.itemRequests[index]
            request.item=profile.item; request.label=profile.label; request.text=profile.text; request.goodwill=2
        else
            request.text="I took a bad fall and this wound needs attention. Could you help patch me up?"
            request.goodwill=3
        end
        layout.helpRequests[npc]=request
    end
    return request
end

function StopHelp.request(layout,npc)
    return layout and layout.helpRequests and layout.helpRequests[npc] or nil
end

function StopHelp.findItem(data,item)
    for slot=1,(data.inventoryCapacity or 6) do if data.inventory[slot]==item then return slot end end
end

function StopHelp.medicalItem(data,catalog)
    for slot=1,(data.inventoryCapacity or 6) do
        local name=data.inventory[slot]; local effect=name and catalog.itemEffects[name]
        if effect and effect.health then return slot,name end
    end
end

local function consume(data,slot,name)
    if slot and data.inventory[slot]==name then data.inventory[slot]=nil; return true end
    local fallback=StopHelp.findItem(data,name)
    if fallback then data.inventory[fallback]=nil; return true end
    return false
end

function StopHelp.completeItem(data,request,npc,location)
    if not request or request.complete then return {completed=request and request.complete==true,gained=0} end
    local slot=StopHelp.findItem(data,request.item)
    if not slot then return {completed=false,missing=request.item,label=request.label} end
    data.inventory[slot]=nil; request.accepted=true; request.complete=true
    local gained,total,tier=StopHelp.add(data,request.goodwill or 2,"item",npc,location)
    return {completed=true,gained=gained,total=total,tier=tier.name,item=request.item}
end

function StopHelp.completeAid(data,request,session,npc,location)
    if not request or request.complete then return {completed=request and request.complete==true,gained=0} end
    if not session or not consume(data,session.itemSlot,session.itemName) then return {completed=false,missing=session and session.itemName} end
    request.accepted=true; request.complete=true
    local gained,total,tier=StopHelp.add(data,request.goodwill or 3,"first-aid",npc,location)
    return {completed=true,gained=gained,total=total,tier=tier.name,item=session.itemName}
end

function StopHelp.audit(catalog)
    local layout={}; local itemRequest=StopHelp.ensureRequest(layout,"settler.png","item",4)
    local aidRequest=StopHelp.ensureRequest(layout,"medic.png","aid",7)
    local data={inventory={itemRequest.item,"field-bandage-roll"},inventoryCapacity=2,goodwill=0,helpHistory={}}
    local itemResult=StopHelp.completeItem(data,itemRequest,"settler.png",4)
    local aidResult=StopHelp.completeAid(data,aidRequest,{itemSlot=2,itemName="field-bandage-roll"},"medic.png",7)
    local status=StopHelp.status(data); local noEvil=StopHelp.add(data,-99,"refused","nobody",1)==0 and data.goodwill==5
    local ready=itemResult.completed and aidResult.completed and status.points==5 and status.helpCount==2
        and status.tier=="Helping Hand" and data.inventory[1]==nil and data.inventory[2]==nil and noEvil
        and catalog.itemEffects["field-bandage-roll"].health>0
    return {ready=ready,points=status.points,tier=status.tier,helpCount=status.helpCount,itemGoodwill=itemResult.gained,
        aidGoodwill=aidResult.gained,noNegativeAlignment=noEvil,policyVersion=StopHelp.policyVersion,curve="goodwill-v1"}
end

return StopHelp
