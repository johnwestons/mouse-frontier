-- Residents keep one saved body while moving between their home and its stop.
-- Routes and collision caches are presentation-independent, unsaved data.
local Settlements=require('game.settlements')
local Doors=require('game.interior_doors')
local Motion=require('game.character_motion')
local Util=require('game.util')
local Routines={VERSION=2}
local routes=setmetatable({},{__mode='k'})
local graphs={}
local function distance(ax,ay,bx,by) return math.sqrt((ax-bx)^2+(ay-by)^2) end
local function seed(file)
    local value=0
    for i=1,#file do value=(value*31+file:byte(i))%2147483647 end
    return value
end
-- Each resident owns a saved random stream. Frame rate, iteration order and
-- another resident's conversation cannot reroll or synchronize their day.
local function random(actor,low,high)
    actor.routineRandom=actor.routineRandom*48271%2147483647
    return low+(high-low)*(actor.routineRandom-1)/2147483646
end
local function outingLength(actor) return math.floor(random(actor,1,4)) end
local durations={[1]={8,16},[3]={7,15},[4]={2,4},[5]={2,4},[6]={9,18},[8]={40,110}}
local function duration(actor,index)
    local range=durations[index]
    return range and random(actor,range[1],range[2]) or 0
end
local function initialize(data,actor)
    if actor.routineVersion==Routines.VERSION then return end
    actor.routineRandom=seed((actor.file or '')..':'..tostring(data.location)..':'
        ..tostring(actor.homeDoor)..':'..tostring(data.journeyStarted or ''))%2147483646+1
    actor.routineCooldowns={}
    actor.routineOutdoorRemaining=outingLength(actor)
    actor.routineStep=actor.routineStep or (actor.scene=='stop' and 3 or 8)
    if actor.routinePhase~='wait' and actor.routineStep~=2 and actor.routineStep~=5 and actor.routineStep~=7 then
        if actor.scene=='stop' then actor.routineStep=({3,4,6})[math.floor(random(actor,1,4))]
        else actor.routineStep=random(actor,0,1)<.3 and 1 or 8 end
    end
    actor.routineDuration=math.max(actor.routineClock or 0,duration(actor,actor.routineStep))
    -- Let an old save finish an active chore; otherwise stagger its first move.
    actor.routineDelay=actor.routinePhase=='wait' and 0 or random(actor,8,50)
    actor.routineVersion=Routines.VERSION
end
function Routines.doorCount(stop)
    local count,lastX,lastY=0
    for i=1,16 do
        local x,y=Settlements.doorPoint(stop,i)
        if x==lastX and y==lastY then break end
        count,lastX,lastY=i,x,y
    end
    return math.max(1,count)
end
local function line(stop,x1,y1,x2,y2)
    local stride=.5
    local mask=Settlements.walkMasks and Settlements.walkMasks[((stop or 1)-1)%Settlements.count+1]
    if mask and mask.getDimensions then
        local width,height=mask:getDimensions()
        stride=math.min(stride,960/width*.25,720/height*.25)
    end
    local steps=math.max(1,math.ceil(distance(x1,y1,x2,y2)/stride))
    for i=0,steps do
        local t=i/steps
        if not Settlements.isWalkable(stop,x1+(x2-x1)*t,y1+(y2-y1)*t) then return false end
    end
    return true
end
function Routines.path(stop,x1,y1,x2,y2)
    if not Settlements.isWalkable(stop,x1,y1) or not Settlements.isWalkable(stop,x2,y2) then return nil end
    if line(stop,x1,y1,x2,y2) then return {{x=x2,y=y2}} end
    local mask=Settlements.walkMasks and Settlements.walkMasks[((stop or 1)-1)%Settlements.count+1]
    local cache=graphs[stop]
    if not cache or cache.mask~=mask then cache={mask=mask,points={},edges={}}; graphs[stop]=cache end
    local step=12
    local function key(cx,cy) return cx..':'..cy end
    local function point(cx,cy)
        local id=key(cx,cy)
        if cache.points[id]==nil then
            local x,y=6+cx*step,6+cy*step
            cache.points[id]=x>=6 and x<=954 and y>=6 and y<=714 and Settlements.isWalkable(stop,x,y)
                and {x=x,y=y,cx=cx,cy=cy,key=id} or false
        end
        return cache.points[id]
    end
    local function attachments(x,y)
        local candidates={}
        local cx,cy=math.floor((x-6)/step+.5),math.floor((y-6)/step+.5)
        for ox=-3,3 do for oy=-3,3 do
            local p=point(cx+ox,cy+oy)
            if p and line(stop,x,y,p.x,p.y) then candidates[#candidates+1]=p end
        end end
        table.sort(candidates,function(a,b) return distance(x,y,a.x,a.y)<distance(x,y,b.x,b.y) end)
        while #candidates>8 do table.remove(candidates) end
        return candidates
    end
    local starts,ends=attachments(x1,y1),attachments(x2,y2)
    local goals={}; for _,p in ipairs(ends) do goals[p.key]=true end
    if #starts==0 or #ends==0 then return nil end
    local queue,seen,head={}, {},1
    for _,p in ipairs(starts) do queue[#queue+1]={point=p}; seen[p.key]=true end
    local dirs={{1,0},{0,1},{-1,0},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
    local goal
    while head<=#queue do
        local entry=queue[head]; head=head+1
        local p=entry.point
        if goals[p.key] then goal=entry; break end
        for _,d in ipairs(dirs) do
            local nextPoint=point(p.cx+d[1],p.cy+d[2])
            if nextPoint and not seen[nextPoint.key] then
                local edge=p.key..'>'..nextPoint.key
                if cache.edges[edge]==nil then cache.edges[edge]=line(stop,p.x,p.y,nextPoint.x,nextPoint.y) end
                if cache.edges[edge] then
                    seen[nextPoint.key]=true
                    queue[#queue+1]={point=nextPoint,previous=entry}
                end
            end
        end
    end
    if not goal then return nil end
    local result={{x=x2,y=y2}}
    while goal do table.insert(result,1,{x=goal.point.x,y=goal.point.y}); goal=goal.previous end
    -- Keep the bends, removing only genuinely visible intermediate points.
    local compact={}; local x,y,index=x1,y1,1
    while index<=#result do
        local last=index
        for i=index+1,math.min(#result,index+12) do
            if line(stop,x,y,result[i].x,result[i].y) then last=i end
        end
        local p=result[last]; compact[#compact+1]=p; x,y=p.x,p.y; index=last+1
    end
    return compact
end
local function outdoorPoint(data,actor,x,y)
    x,y=Settlements.clamp(x,y,data.location)
    local homeX,homeY=Settlements.doorPoint(data.location,actor.homeDoor)
    -- Use the walkable threshold in front of the door. A painted doorway
    -- can contain tiny isolated mask islands further up the steps.
    homeX,homeY=Settlements.clamp(homeX,homeY+18,data.location)
    if Routines.path(data.location,homeX,homeY,x,y) then return {x=x,y=y} end
    return {x=homeX,y=homeY}
end
local function homeInterior(data,actor)
    local layout=data.stopLayouts[tostring(data.location)]
    local home=layout.houseDoors and layout.houseDoors[tostring(actor.homeDoor)]
    return home and home.interior or actor.interior
end
local function buildPlan(data,actor,files,interior)
    local ix,iy=Doors.spawnPoint(interior,files)
    ix,iy=Util.clampHouseFloor(ix,iy)
    local homeX,homeY=Settlements.doorPoint(data.location,actor.homeDoor)
    local porch=outdoorPoint(data,actor,homeX,homeY+18)
    local sweep=outdoorPoint(data,actor,homeX+((actor.homeDoor%2==0) and -24 or 24),homeY+28)
    local count=Routines.doorCount(data.location)
    local supplyX,supplyY=Settlements.doorPoint(data.location,actor.homeDoor%count+1)
    local supply=outdoorPoint(data,actor,supplyX,supplyY+28)
    local work=outdoorPoint(data,actor,homeX+((actor.homeDoor%2==0) and 55 or -55),homeY+48)
    -- Existing loose props are real work destinations. Wide settlement art
    -- omits generated decorations, so its fallback stays at the home porch.
    local best
    for _,item in ipairs(data.droppedItems or {}) do
        if item.scene=='stop' and item.location==data.location then
            local name=item.name or ''
            if name:find('crate') or name:find('barrel') then
                local d=distance(homeX,homeY,item.x,item.y)
                if not best or d<best then supply=outdoorPoint(data,actor,item.x,item.y+28); best=d end
            elseif name:find('plant') or name:find('flower') or name:find('sprout') or name:find('workbench') then
                work=outdoorPoint(data,actor,item.x,item.y+28)
            end
        end
    end
    local indoorX,indoorY=Util.clampHouseFloor(ix+(480-ix)*.5,iy+(440-iy)*.5)
    for _,item in ipairs(data.droppedItems or {}) do
        if item.scene=='house' and item.location==data.location and (item.houseDoor or 1)==actor.homeDoor
            and ((item.name or ''):find('workbench') or (item.name or ''):find('table')) then
            indoorX,indoorY=Util.clampHouseFloor(item.x,item.y+34); break
        end
    end
    return {
        {scene='house',x=indoorX,y=indoorY,action='tend'},
        {scene='house',x=ix,y=iy,transition='stop',arrivalX=porch.x,arrivalY=porch.y},
        {scene='stop',x=sweep.x,y=sweep.y,action='sweep'},
        {scene='stop',x=supply.x,y=supply.y,action='carry'},
        {scene='stop',x=sweep.x,y=sweep.y,travelAction='carry',action='carry'},
        {scene='stop',x=work.x,y=work.y,action='tend'},
        {scene='stop',x=porch.x,y=porch.y,transition='house',arrivalX=ix,arrivalY=iy},
        {scene='house',x=indoorX,y=indoorY},
    }
end
local plans=setmetatable({},{__mode='k'})
local function stop(actor)
    actor.moving=false; actor.velocityX,actor.velocityY=0,0
    actor.targetX,actor.targetY=nil,nil
end
local outdoorChores={{step=3,action='sweep'},{step=4,action='carry'},{step=6,action='tend'}}
local function chooseOutdoor(actor)
    if (actor.routineOutdoorRemaining or 0)<=0 then return 7 end
    local candidates,total={},0
    local preference=seed(actor.file or '')
    for index,chore in ipairs(outdoorChores) do
        if chore.action~=actor.routineLastChore and (actor.routineCooldowns[chore.action] or 0)<=0 then
            local weight=1+(math.floor(preference/3^(index-1))%3)*.3
            total=total+weight; candidates[#candidates+1]={step=chore.step,limit=total}
        end
    end
    if total==0 then return 7 end
    local roll=random(actor,0,total)
    for _,candidate in ipairs(candidates) do if roll<candidate.limit then return candidate.step end end
    return candidates[#candidates].step
end
local function finishStep(actor,plan,failed)
    local current=actor.routineStep
    local nextStep,delay
    if failed then
        nextStep=actor.scene=='stop' and 7 or 8
        delay=random(actor,16,35)
    elseif current==2 then
        actor.routineOutdoorRemaining=outingLength(actor)
        nextStep=chooseOutdoor(actor); delay=random(actor,4,12)
    elseif current==4 then
        -- Loading and delivery are one task: never abandon the carried crate.
        nextStep=5; delay=0
    elseif current==3 or current==5 or current==6 then
        local action=plan[current].action
        actor.routineLastChore=action
        actor.routineCooldowns[action]=random(actor,85,160)
        actor.routineOutdoorRemaining=math.max(0,(actor.routineOutdoorRemaining or 1)-1)
        nextStep=chooseOutdoor(actor); delay=random(actor,18,45)
    elseif current==7 then
        actor.routineIndoorWorked=false
        nextStep=8; delay=0
    elseif current==8 then
        nextStep=not actor.routineIndoorWorked and random(actor,0,1)<.45 and 1 or 2
        delay=0
    else
        actor.routineIndoorWorked=true
        nextStep=8; delay=random(actor,5,14)
    end
    actor.routineStep=nextStep
    actor.routineDuration=duration(actor,nextStep); actor.routineDelay=delay
    actor.routinePhase='travel'; actor.routineClock=0; actor.routineAction=nil
    actor.routineRetry=nil
    routes[actor]=nil; stop(actor)
end
local function transfer(actor,step,plan)
    actor.scene=step.transition; actor.x,actor.y=step.arrivalX,step.arrivalY
    for i,child in ipairs(actor.family or {}) do
        child.x,child.y=actor.x-i*10,actor.y+5; child.roamX,child.roamY=nil,nil; child.moving=false
    end
    finishStep(actor,plan)
end
function Routines.update(data,actor,dt,options)
    options=options or {}; dt=math.max(0,math.min(.1,tonumber(dt) or 0))
    if dt==0 then return end
    if options.held then stop(actor); actor.routineAction=nil; actor.routinePaused=true; return end
    actor.routinePaused=nil
    initialize(data,actor)
    for action,remaining in pairs(actor.routineCooldowns) do
        actor.routineCooldowns[action]=math.max(0,remaining-dt)
    end
    local stored=plans[actor]
    local interior=homeInterior(data,actor)
    if not stored or stored.location~=data.location or stored.files~=options.interiorFiles or stored.interior~=interior then
        if stored then
            -- A legacy room can acquire its stop-specific painting when the
            -- player enters. Its new doorway must replace an in-flight route
            -- as well as the following exit/arrival steps.
            routes[actor]=nil; stop(actor)
            actor.routinePhase='travel'; actor.routineClock=0; actor.routineAction=nil; actor.routineRetry=nil
        end
        stored={location=data.location,files=options.interiorFiles,interior=interior,
            steps=buildPlan(data,actor,options.interiorFiles,interior)}
        plans[actor]=stored
    end
    local plan=stored.steps
    local step=plan[actor.routineStep or 1]
    if not step or step.scene~=actor.scene then
        actor.routineStep=actor.scene=='stop' and chooseOutdoor(actor) or 8
        actor.routineDuration=duration(actor,actor.routineStep); actor.routineDelay=random(actor,8,35)
        actor.routinePhase='travel'; actor.routineClock=0; actor.routineAction=nil
        routes[actor]=nil; step=plan[actor.routineStep]
    end
    if (actor.routineDelay or 0)>0 then
        actor.routineDelay=math.max(0,actor.routineDelay-dt)
        stop(actor); actor.routineAction=nil
        return
    end
    if actor.routinePhase=='wait' then
        stop(actor); actor.routineAction=step.action
        if step.action then actor.facing=1; actor.intentX,actor.intentY=1,0 end
        actor.routineClock=(actor.routineClock or 0)+dt
        if actor.routineClock>=(actor.routineDuration or 0) then finishStep(actor,plan) end
        return
    end
    actor.routineAction=step.travelAction; actor.routineClock=0
    local route=routes[actor]
    if not route then
        local points
        if actor.scene=='stop' then points=Routines.path(data.location,actor.x,actor.y,step.x,step.y)
        else points={{x=step.x,y=step.y}} end
        if not points then
            stop(actor); actor.routineRetry=(actor.routineRetry or 0)+dt
            if actor.routineRetry>2 then finishStep(actor,plan,true) end
            return
        end
        route={points=points,index=1}; routes[actor]=route
    end
    local point=route.points[route.index]
    actor.targetX,actor.targetY=point.x,point.y
    local arrived=distance(actor.x,actor.y,point.x,point.y)<=2
    if not arrived then
        local oldX,oldY=actor.x,actor.y
        local profile=Motion.profileFor(actor.file) or Motion.defaults
        Motion.moveToward(actor,point.x,point.y,dt,{profile=profile,speed=32,stopDistance=2,
            move=function(ox,oy,x,y)
                if actor.scene=='stop' then return Settlements.move(data.location,ox,oy,x,y) end
                return Util.clampHouseFloor(x,y)
            end})
        if distance(oldX,oldY,actor.x,actor.y)<.001 then route.stalled=(route.stalled or 0)+dt else route.stalled=0 end
        if route.stalled>1 then
            routes[actor]=nil; stop(actor)
            actor.routineRetry=(actor.routineRetry or 0)+1
            if actor.routineRetry>=3 then finishStep(actor,plan,true) end
        end
        arrived=distance(actor.x,actor.y,point.x,point.y)<=2
    end
    if arrived then
        route.index=route.index+1
        if route.index>#route.points then
            stop(actor)
            if step.transition then transfer(actor,step,plan)
            else
                actor.routinePhase='wait'; actor.routineClock=0; actor.routineAction=step.action; actor.routineRetry=nil
                if step.action then actor.facing=1; actor.intentX,actor.intentY=1,0 end
            end
        end
    end
end
return Routines
