local InteractionRouter = {}

function InteractionRouter.select(ctx)
    local candidates={}
    for i,item in ipairs(ctx.data.droppedItems) do
        if ctx.itemIsHere(item) and math.sqrt((ctx.player.x-item.x)^2+(ctx.player.y-item.y)^2)<75 then
            local kind=item.name=="mailbox-reward" and "mailbox" or (item.name=="boombox-radio" and "radio" or (ctx.storageCapacities[item.name] and "chest" or "item"))
            candidates[#candidates+1]={kind=kind,index=i,x=item.x,y=item.y,hoverRadius=kind=="item" and 38 or 52}
        end
    end
    local activeCar=ctx.data.activeCar or 1
    local exitX=ctx.car.x+ctx.car.w-44
    local carCount=#(ctx.data.trainCars or {})
    if ctx.scene=="train" and activeCar>1 and math.abs(ctx.player.x-(ctx.car.x+35))<65 and ctx.player.y>ctx.car.y+115 then
        candidates[#candidates+1]={kind="carPrev",x=ctx.car.x+35,y=ctx.car.y+205,hoverRadius=50}
    end
    if ctx.scene=="train" and activeCar<carCount and math.abs(ctx.player.x-exitX)<65 and ctx.player.y>ctx.car.y+115 then
        candidates[#candidates+1]={kind="carNext",x=exitX,y=ctx.car.y+205,hoverRadius=50}
    end
    if ctx.scene=="stop" and ctx.nearTrain(ctx.player.x,ctx.player.y,ctx.data.location) then
        local x,y=ctx.trainPoint(ctx.data.location); candidates[#candidates+1]={kind="returnTrain",x=x,y=y,hoverRadius=48}
    end
    local activity=ctx.scene=="stop" and ctx.stopActivity
    if activity and not activity.completed and math.sqrt((ctx.player.x-activity.x)^2+(ctx.player.y-activity.y)^2)<82 then
        candidates[#candidates+1]={kind="stopActivity",x=activity.x,y=activity.y,hoverRadius=62,label=activity.label}
    end
    if ctx.scene=="train" and activeCar==1 and math.sqrt((ctx.player.x-(ctx.car.x+165))^2+(ctx.player.y-(ctx.car.y+240))^2)<95 then
        candidates[#candidates+1]={kind="fire",x=ctx.car.x+165,y=ctx.car.y+240,hoverRadius=58}
    end
    if ctx.scene=="stop" then
        local door=ctx.nearDoor(ctx.player.x,ctx.player.y,ctx.data.location)
        if door then
            local x,y=ctx.doorPoint(ctx.data.location,door); candidates[#candidates+1]={kind="house",index=door,x=x,y=y,hoverRadius=52}
        elseif not ctx.hasSettlements then
            local layout=ctx.layout(); local x=layout.houseX or 520
            if math.sqrt((ctx.player.x-x)^2+(ctx.player.y-485)^2)<115 then candidates[#candidates+1]={kind="house",index=1,x=x,y=485,hoverRadius=58} end
        end
    elseif ctx.scene=="house" then
        local layout=ctx.layout(); local x,y=ctx.interiorPoint(layout.interior,ctx.interiorFiles)
        if ctx.nearInteriorDoor(ctx.player.x,ctx.player.y,layout.interior,ctx.interiorFiles) then candidates[#candidates+1]={kind="houseExit",x=x,y=y,hoverRadius=55} end
    end
    if ctx.npc and math.sqrt((ctx.player.x-ctx.npc.x)^2+(ctx.player.y-ctx.npc.y)^2)<95 then
        candidates[#candidates+1]={kind="npc",x=ctx.npc.x,y=ctx.npc.y,hoverRadius=48}
    end
    if ctx.scene=="train" then
        for i,passenger in ipairs(ctx.data.passengers or {}) do
            if (passenger.carIndex or 1)==activeCar and math.abs(ctx.player.x-passenger.x)<75 and math.abs(ctx.player.y-passenger.y)<90 then
                candidates[#candidates+1]={kind="passenger",index=i,x=passenger.x,y=passenger.y,hoverRadius=48}
            end
        end
    end
    return ctx.choose(candidates,ctx.mouseX,ctx.mouseY,ctx.player)
end

function InteractionRouter.flags(selected)
    local result={interaction=selected}
    if not selected then return result end
    if selected.kind=="item" then result.nearbyItem=selected.index
    elseif selected.kind=="chest" then result.nearChest=selected.index
    elseif selected.kind=="mailbox" then result.nearMailbox=selected.index
    elseif selected.kind=="radio" then result.nearRadio=true
    elseif selected.kind=="house" then result.nearHouse=selected.index
    elseif selected.kind=="npc" then result.nearNPC=true
    elseif selected.kind=="passenger" then result.nearPassenger=selected.index
    elseif selected.kind=="returnTrain" then result.nearReturnTrain=true
    elseif selected.kind=="stopActivity" then result.nearStopActivity=true
    elseif selected.kind=="fire" then result.nearFire=true
    elseif selected.kind=="carPrev" then result.nearCarPrev=true
    elseif selected.kind=="carNext" then result.nearCarNext=true end
    return result
end

function InteractionRouter.keyAction(ctx,key)
    if ctx.blocked then return nil end
    local selected=ctx.selected
    if key=="q" then
        if ctx.dialogue then return "closeDialogue"
        elseif selected and selected.kind=="passenger" then return "talkPassenger",selected.index
        elseif selected and selected.kind=="carNext" then return "car",1
        elseif selected and selected.kind=="carPrev" then return "car",-1
        elseif selected and selected.kind=="npc" then return "talkNPC"
        elseif selected and selected.kind=="house" then return "enterHouse",selected.index
        elseif selected and selected.kind=="houseExit" then return "exitHouse"
        elseif selected and selected.kind=="stopActivity" then return "stopActivity"
        elseif selected and selected.kind=="returnTrain" then return "returnTrain" end
    elseif key=="g" then
        if selected and (selected.kind=="npc" or selected.kind=="passenger") then return "give",selected.index end
    elseif key=="e" then
        if ctx.dialogue then return "closeDialogue"
        elseif selected and selected.kind=="mailbox" then return "openStorage",selected.index
        elseif selected and selected.kind=="chest" then return "holdPickup",selected.index
        elseif selected and selected.kind=="item" then return ctx.isFurniture(selected.index) and "holdPickup" or "pickup",selected.index
        elseif selected and selected.kind=="fire" then return "fire" end
    end
end

function InteractionRouter.mouseAction(selected,button)
    if button==1 and selected and selected.hovered then
        local qKinds={passenger=true,carNext=true,carPrev=true,npc=true,house=true,houseExit=true,stopActivity=true,returnTrain=true}
        local eKinds={mailbox=true,chest=true,item=true,fire=true}
        if qKinds[selected.kind] then return "routeKey","q" end
        if eKinds[selected.kind] then return "routeKey","e" end
    end
    if button==2 and selected and (selected.kind=="chest" or selected.kind=="mailbox") then
        return "openStorage",selected.index
    end
end

return InteractionRouter
