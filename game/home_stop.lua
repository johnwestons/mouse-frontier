-- The opening yard is stop 1 for new campaigns only. Missing/empty state is
-- deliberately inactive so an existing journey never replays the prologue.
local Home={VERSION=1,CONDUCTOR="tortoise-conductor.png",FOX="tinker-fox.png"}
Home.npc=Home.CONDUCTOR
-- Room art and room geometry share a fit; actors retain their normal world
-- size so the office furnishings no longer dwarf them.
Home.officeView={x=192,y=180,scale=.6}
Home.officeFootOffset=28
function Home.officePoint(x,y)
    local view=Home.officeView
    return view.x+x*view.scale,view.y+y*view.scale
end
function Home.officeStandingPoint(x,y)
    local px,py=Home.officePoint(x,y)
    return px,py-Home.officeFootOffset
end
-- Foot-contact mask in the artwork's 960x720 coordinate system. It follows
-- the visible floor up to the rear cabinets, around the desk/stove/crates,
-- and through the front threshold. Furniture and walls stay outside it.
Home.officeFloor={
    {200,310},{300,285},{505,275},{535,310},{565,360},{810,360},
    {825,420},{835,500},{820,575},{650,635},{585,650},{585,705},
    {375,705},{375,650},{300,635},{205,590},{190,540},{185,485},
    {165,440},{170,380},
}
local function roomPoint(x,y,radius)
    local px,py=Home.officePoint(x,y)
    return {x=px,y=py,radius=radius}
end
Home.officeSpawn=roomPoint(480,535)
Home.points={
    conductor=roomPoint(600,380,95),
    officeDoor={x=290,y=300,radius=65},
    officeExit=roomPoint(480,590,75),
    supplies={x=320,y=435,radius=75},
    repair={x=710,y=445,radius=80},
    train={x=750,y=550,radius=80},
}
local stages={briefing=true,supplies=true,repair=true,farewell=true,ready=true,departed=true}
local targets={talk="conductor",supplies="supplies",repair="repair",board="train"}
local labels={talk="Talk to conductor",supplies="Collect journey supplies",repair="Prepare the locomotive",board="Board the train"}
local objectives={
    briefing="Enter the train office and meet the conductor.",
    supplies="Collect food, water, coal, and oil from the supply crates.",
    repair="Prepare the locomotive at the repair stand.",
    farewell="Return to the conductor inside the train office.",
    ready="Board your train, then begin the journey west.",
}
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
-- Connected courtyard, porch/stairs, repair-shed approach and the narrow
-- platform around the train. The locomotive itself remains solid.
Home.yardFloor={{150,390,780,650},{50,480,160,555},{100,390,300,500},
    {250,295,390,430},{100,280,400,350},{390,300,675,430},{575,280,675,430},
    {700,580,900,650},{885,485,930,650}}
function Home.isOffice(data)
    local state=data and data.homeStop
    return Home.isHome(data) and (state.inOffice==true or (state.inOffice==nil and state.dialogueLine~=nil)) or false
end
local function project(x,y,regions)
    local bestX,bestY,bestDistance
    for _,rect in ipairs(regions) do
        local px=math.max(rect[1],math.min(rect[3],x))
        local py=math.max(rect[2],math.min(rect[4],y))
        local distance=(px-x)^2+(py-y)^2
        if not bestDistance or distance<bestDistance then bestX,bestY,bestDistance=px,py,distance end
    end
    return bestX,bestY
end
local function floorProjection(x,y)
    local polygon=Home.officeFloor
    local inside=false
    local bestX,bestY,bestDistance
    for index,a in ipairs(polygon) do
        local b=polygon[index%#polygon+1]
        if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
        local dx,dy=b[1]-a[1],b[2]-a[2]
        local t=math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/(dx*dx+dy*dy)))
        local px,py=a[1]+dx*t,a[2]+dy*t
        local distance=(px-x)^2+(py-y)^2
        if not bestDistance or distance<bestDistance then bestX,bestY,bestDistance=px,py,distance end
    end
    if inside or bestDistance<.00000001 then return x,y,true end
    return bestX,bestY,false
end
function Home.officeWalkable(x,y)
    if not finite(x) or not finite(y) then return false end
    local view=Home.officeView
    local _,_,inside=floorProjection((x-view.x)/view.scale,(y+Home.officeFootOffset-view.y)/view.scale)
    return inside
end
function Home.clamp(x,y,data)
    x,y=finite(x) and x or 420,finite(y) and y or 565
    if Home.isOffice(data) then
        local view=Home.officeView
        local roomX,roomY=(x-view.x)/view.scale,(y+Home.officeFootOffset-view.y)/view.scale
        local px,py,inside=floorProjection(roomX,roomY)
        if inside then return x,y end
        return Home.officeStandingPoint(px,py)
    end
    return project(x,y,Home.yardFloor)
end
function Home.move(oldX,oldY,newX,newY,data)
    local x,y=Home.clamp(oldX,oldY,data)
    local targetX,targetY=finite(newX) and newX or x,finite(newY) and newY or y
    local dx,dy=targetX-x,targetY-y
    local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/5))
    for _=1,steps do x,y=Home.clamp(x+dx/steps,y+dy/steps,data) end
    if math.abs(x-targetX)<.000001 then x=targetX end
    if math.abs(y-targetY)<.000001 then y=targetY end
    return x,y
end
function Home.newState()
    return {version=Home.VERSION,stage="briefing",inOffice=false,suppliesCollected=false,repairComplete=false}
end
function Home.layout(data)
    require('game.npc_identity').ensureStop(data,{homeStop=true},1)
    data.stopLayouts=data.stopLayouts or {}
    local layout=data.stopLayouts["1"]
    if not layout or not layout.homeStop then
        layout={homeStop=true,npc=Home.CONDUCTOR,npcOutside=Home.CONDUCTOR,npcInside=Home.CONDUCTOR,
            houseX=330,offer="none",npcOffers={[Home.CONDUCTOR]="none"},helpRequests={},decorations={}}
        data.stopLayouts["1"]=layout
    end
    data.currentNPC=Home.CONDUCTOR
    return layout
end
function Home.isHome(data)
    local state=type(data)=="table" and data.homeStop
    return data and data.location==1 and type(state)=="table" and state.version==Home.VERSION
        and stages[state.stage]==true and state.stage~="departed" or false
end
function Home.objective(data)
    if Home.isOffice(data) and Home.action(data)~="talk" then return "Return outside to continue preparing for departure." end
    if Home.isOffice(data) then return "Speak with the conductor inside the train office." end
    return Home.isHome(data) and objectives[data.homeStop.stage] or nil
end
function Home.action(data)
    if not Home.isHome(data) then return nil end
    local stage=data.homeStop.stage
    return (stage=="briefing" or stage=="farewell") and "talk"
        or stage=="ready" and "board" or stage
end
function Home.target(data)
    local action=Home.action(data)
    if Home.isOffice(data) and action~="talk" then
        local point=Home.points.officeExit
        return {action="exitOffice",label="Return to the train yard",x=point.x,y=point.y,radius=point.radius}
    elseif not Home.isOffice(data) and action=="talk" then
        local point=Home.points.officeDoor
        return {action="enterOffice",label="Enter train office",x=point.x,y=point.y,radius=point.radius}
    end
    local point=action and Home.points[targets[action]]
    if not point then return nil end
    return {action=action,label=labels[action],x=point.x,y=point.y,radius=point.radius}
end
function Home.interaction(data,player)
    if not player or data.scene~="stop" or not finite(player.x) or not finite(player.y) then return nil end
    local target=Home.target(data)
    if target and (player.x-target.x)^2+(player.y-target.y)^2<=target.radius^2 then return target end
    local door=Home.isOffice(data) and Home.points.officeExit or Home.points.officeDoor
    if (player.x-door.x)^2+(player.y-door.y)^2<=door.radius^2 then
        return {action=Home.isOffice(data) and "exitOffice" or "enterOffice",label=Home.isOffice(data) and "Return to the train yard" or "Enter train office",x=door.x,y=door.y,radius=door.radius}
    end
end
function Home.canAdvance(data,action,player)
    if Home.isHome(data) and data.scene=="stop" and (action=="enterOffice" or action=="exitOffice") then
        if (action=="enterOffice")==Home.isOffice(data) or data.homeStop.dialogueLine then return false,"home_step_unavailable" end
        local point=action=="enterOffice" and Home.points.officeDoor or Home.points.officeExit
        if player and (not finite(player.x) or not finite(player.y) or (player.x-point.x)^2+(player.y-point.y)^2>point.radius^2) then return false,"home_target_unavailable" end
        return true
    end
    if not Home.isHome(data) or data.scene~="stop" or action==nil or action=="board"
        or action~=Home.action(data) then return false,"home_step_unavailable" end
    if (action=="talk")~=Home.isOffice(data) then return false,"home_target_unavailable" end
    if action=="talk" and data.homeStop.dialogueLine then return true end
    local target=player and Home.interaction(data,player)
    if player and (not target or target.action~=action) then return false,"home_target_unavailable" end
    return true
end
function Home.advance(data,action)
    local allowed,reason=Home.canAdvance(data,action)
    if not allowed then return nil,reason end
    local state=data.homeStop
    local result={ok=true,action=action}
    if action=="enterOffice" or action=="exitOffice" then
        state.inOffice=action=="enterOffice"
        result.homeOfficeTransition=true
    elseif action=="talk" then
        state.inOffice=true
        if state.stage=="farewell" then
            if state.dialogueLine==6 then state.dialogueLine=nil; state.stage="ready"
            else state.dialogueLine=6 end
        else
            if state.dialogueLine==5 then state.dialogueLine=nil; state.stage="supplies"
            else state.dialogueLine=(state.dialogueLine or 0)+1 end
        end
        result.line=state.dialogueLine
    elseif action=="supplies" then
        if state.suppliesCollected then return nil,"home_step_unavailable" end
        data.resources=data.resources or {}
        for _,name in ipairs({"food","water","coal","oil"}) do
            data.resources[name]=(tonumber(data.resources[name]) or 0)+10
        end
        state.suppliesCollected=true; state.stage="repair"
        result.suppliesCollected=true
    elseif action=="repair" then
        if state.repairComplete then return nil,"home_step_unavailable" end
        data.maintenance=data.maintenance or {}
        data.maintenance.condition=100
        state.repairComplete=true; state.stage="farewell"
        result.repairComplete=true
    end
    result.stage=state.stage
    return result
end
function Home.canDepart(data)
    return not Home.isHome(data) or data.homeStop.stage=="ready"
end
function Home.depart(data)
    if not Home.isHome(data) then return true end
    if not Home.canDepart(data) then return false,"home_preparation_incomplete" end
    data.homeStop.stage="departed"
    return true
end
function Home.validate(data)
    local state=data.homeStop
    if state==nil then return true end
    if type(state)~="table" then return false,"homeStop must be a table" end
    if next(state)==nil then return true end
    local fields={version=true,stage=true,dialogueLine=true,inOffice=true,suppliesCollected=true,repairComplete=true}
    for key in pairs(state) do if not fields[key] then return false,"invalid home stop field" end end
    if state.inOffice~=nil and type(state.inOffice)~="boolean" then return false,"invalid home office state" end
    if state.inOffice and data.scene~="stop" then return false,"home office outside stop scene" end
    if state.dialogueLine and state.inOffice==false then return false,"home conversation outside office" end
    if state.version~=Home.VERSION or not stages[state.stage]
        or type(state.suppliesCollected)~="boolean" or type(state.repairComplete)~="boolean" then return false,"invalid home stop state" end
    if state.stage=="briefing" then
        if state.dialogueLine~=nil and (not finite(state.dialogueLine) or state.dialogueLine~=math.floor(state.dialogueLine)
            or state.dialogueLine<1 or state.dialogueLine>5) then return false,"invalid home briefing line" end
    elseif state.stage=="farewell" then
        if state.dialogueLine~=nil and state.dialogueLine~=6 then return false,"invalid home farewell line" end
    elseif state.dialogueLine~=nil then return false,"unexpected home briefing line" end
    local supplied=state.stage~="briefing" and state.stage~="supplies"
    local repaired=state.stage=="farewell" or state.stage=="ready" or state.stage=="departed"
    if state.suppliesCollected~=supplied or state.repairComplete~=repaired then return false,"invalid home preparation receipts" end
    if state.stage~="departed" and tonumber(data.location)~=1 then return false,"unfinished home stop outside the yard" end
    return true
end
return Home
