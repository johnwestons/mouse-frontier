local Typography=require("game.typography")
local FirstAid={}

local function text(value,x,y,w,h,scale,minimum)
    return Typography.drawText(love.graphics,value,x,y,w,h,{scale=scale,minScale=minimum or scale,align="center",valign="center"})
end

FirstAid.phaseCount=6
FirstAid.treatmentStepCount=5
FirstAid.woundType="small-cut"
FirstAid.ointmentTrailOpacity=.80
FirstAid.requiredWrapPasses=3

local injury={x=512,y=420,r=58}
local wound={x=480,y=370,r=92}
local cancel={x=350,y=608,w=260,h=42}
local phaseNames={"FIND THE INJURY","DISINFECT","CLEAN","APPLY OINTMENT","PLACE GAUZE","WRAP"}
local instructions={
    "The critter is hurting. Select the red-tinted area to inspect the injury.",
    "Move the bottle opening over the cut and hold it there to pour disinfectant.",
    "Press and drag the clean rag back and forth across the cut three times.",
    "Press and swipe the ointment swab across the cut until it is covered.",
    "Move the gauze pad over the cut, then tap or click to place it.",
    "Start at LEFT, then drag the roll back and forth for three wrapping passes.",
}

local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end
local function hitCircle(x,y,zone,radius)
    local dx,dy=x-zone.x,y-zone.y
    return dx*dx+dy*dy<=(radius or zone.r)^2
end
local function hitRect(x,y,rect) return x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h end
local function distance(x1,y1,x2,y2)
    local dx,dy=(x2 or x1)-(x1 or 0),(y2 or y1)-(y1 or 0)
    return math.sqrt(dx*dx+dy*dy)
end
local function title(value) return tostring(value or "none"):gsub("%-"," "):upper() end

local function normalizeProgress(progress)
    progress=type(progress)=="table" and progress or {}
    progress.phase=clamp(math.floor(tonumber(progress.phase or progress.stage) or 1),1,FirstAid.phaseCount)
    progress.stage=progress.phase
    progress.pourTime=math.max(0,tonumber(progress.pourTime) or 0)
    progress.rubDistance=math.max(0,tonumber(progress.rubDistance) or 0)
    progress.rubTurns=math.max(0,math.floor(tonumber(progress.rubTurns) or 0))
    progress.ointmentDistance=math.max(0,tonumber(progress.ointmentDistance) or 0)
    progress.ointmentTrail=type(progress.ointmentTrail)=="table" and progress.ointmentTrail or {}
    progress.gauzePlaced=progress.gauzePlaced==true
    progress.wrapPasses=clamp(math.floor(tonumber(progress.wrapPasses) or 0),0,FirstAid.requiredWrapPasses)
    progress.wrapArmed=progress.wrapArmed==true
    progress.wrapDirection=tonumber(progress.wrapDirection)==-1 and -1 or 1
    return progress
end

function FirstAid.new(options)
    options=options or {}
    local progress=normalizeProgress(options.progress)
    return {
        npc=options.npc,itemName=options.itemName,itemSlot=options.itemSlot,
        location=math.max(1,math.floor(tonumber(options.location) or 1)),helpQuestId=options.helpQuestId,
        progress=progress,phase=progress.phase,stage=progress.phase,dragging=false,
        pointer={x=730,y=420},previousPointer=nil,lastRubDirection=0,
        elapsed=0,message=nil,
    }
end

local function sync(session)
    session.phase=clamp(math.floor(tonumber(session.phase) or 1),1,FirstAid.phaseCount)
    session.stage=session.phase
    session.progress.phase=session.phase
    session.progress.stage=session.phase
end

local function enterPhase(session,phase,message)
    session.phase=clamp(phase,1,FirstAid.phaseCount)
    session.dragging=false
    session.previousPointer=nil
    session.lastRubDirection=0
    session.message=message
    if session.phase==2 then session.pointer.x,session.pointer.y=730,420 end
    if session.phase==6 then
        session.pointer.x,session.pointer.y=wound.x-126,wound.y
        session.progress.wrapArmed=false
        session.progress.wrapDirection=1
    end
    sync(session)
    return "progress"
end

local function advance(session)
    local nextPhase=session.phase+1
    if nextPhase>FirstAid.phaseCount then return "complete" end
    local messages={
        [2]="Small cut found. Disinfect it before touching the wound.",
        [3]="Disinfected. Wipe the cut clean with the rag.",
        [4]="Clean. Spread a thin layer of healing ointment.",
        [5]="Ointment applied. Protect it with the gauze pad.",
        [6]="Gauze placed. Wrap it snugly with three alternating passes.",
    }
    return enterPhase(session,nextPhase,messages[nextPhase])
end

-- Keyboard-accessible equivalent of completing the current physical gesture.
function FirstAid.choose(session,index)
    if not session or tonumber(index)~=session.phase then return nil end
    if session.phase==5 then session.progress.gauzePlaced=true end
    if session.phase==6 then
        session.progress.wrapPasses=FirstAid.requiredWrapPasses
        session.progress.wrapArmed=true
        sync(session)
        return "complete"
    end
    return advance(session)
end

function FirstAid.update(session,dt)
    if not session then return nil end
    session.elapsed=(session.elapsed or 0)+(tonumber(dt) or 0)
    if session.phase==2 and hitCircle(session.pointer.x,session.pointer.y,wound,wound.r) then
        session.progress.pourTime=math.min(.8,session.progress.pourTime+(tonumber(dt) or 0))
        if session.progress.pourTime>=.75 then return advance(session) end
    end
end

function FirstAid.mousepressed(session,x,y)
    if not session then return nil end
    session.pointer.x,session.pointer.y=x,y
    session.previousPointer={x=x,y=y}
    if hitRect(x,y,cancel) then return "cancelled" end
    if session.phase==1 then
        if hitCircle(x,y,injury,injury.r) then return advance(session) end
        session.message="Look for the red-tinted sore area on the critter."
        return nil
    end
    if session.phase==5 then
        if hitCircle(x,y,wound,wound.r) then
            session.progress.gauzePlaced=true
            return advance(session)
        end
        session.message="Center the gauze over the cut before placing it."
        return nil
    end
    if session.phase==3 or session.phase==4 or session.phase==6 then
        session.dragging=true
        if session.phase==6 and x<=wound.x-wound.r*.72 and math.abs(y-wound.y)<=wound.r then
            session.progress.wrapArmed=true
            session.progress.wrapDirection=1
        end
    end
end

local function addOintmentPoint(progress,x,y)
    local trail=progress.ointmentTrail
    local previous=trail[#trail]
    if not previous or distance(previous.x,previous.y,x,y)>=7 then
        trail[#trail+1]={x=x,y=y}
        while #trail>80 do table.remove(trail,1) end
    end
end

local function handleRub(session,x,y,dx,dy)
    if not session.dragging or not hitCircle(x,y,wound,wound.r) then return nil end
    local amount=math.sqrt(dx*dx+dy*dy)
    if amount<1 then return nil end
    session.progress.rubDistance=session.progress.rubDistance+amount
    local direction=dx>2 and 1 or (dx<-2 and -1 or 0)
    if direction~=0 and session.lastRubDirection~=0 and direction~=session.lastRubDirection then
        session.progress.rubTurns=session.progress.rubTurns+1
    end
    if direction~=0 then session.lastRubDirection=direction end
    if session.progress.rubDistance>=220 and session.progress.rubTurns>=3 then return advance(session) end
end

local function handleOintment(session,x,y,dx,dy)
    if not session.dragging or not hitCircle(x,y,wound,wound.r) then return nil end
    local amount=math.sqrt(dx*dx+dy*dy)
    if amount<1 then return nil end
    session.progress.ointmentDistance=session.progress.ointmentDistance+amount
    addOintmentPoint(session.progress,x,y)
    if session.progress.ointmentDistance>=180 and #session.progress.ointmentTrail>=12 then return advance(session) end
end

local function handleWrap(session,x,y)
    if not session.dragging or math.abs(y-wound.y)>wound.r*.95 then return nil end
    local progress=session.progress
    local left,right=wound.x-wound.r*.82,wound.x+wound.r*.82
    if not progress.wrapArmed then
        if x<=left then progress.wrapArmed=true; progress.wrapDirection=1; session.message="Good. Now pull the roll all the way to the RIGHT marker." end
        return nil
    end
    local crossed=(progress.wrapDirection==1 and x>=right) or (progress.wrapDirection==-1 and x<=left)
    if not crossed then return nil end
    progress.wrapPasses=math.min(FirstAid.requiredWrapPasses,progress.wrapPasses+1)
    if progress.wrapPasses>=FirstAid.requiredWrapPasses then sync(session); return "complete" end
    progress.wrapDirection=-progress.wrapDirection
    session.message="Pass "..progress.wrapPasses.." secured. Pull back to the "..(progress.wrapDirection==1 and "RIGHT" or "LEFT").." marker."
end

function FirstAid.mousemoved(session,x,y)
    if not session then return nil end
    local previous=session.previousPointer or session.pointer or {x=x,y=y}
    local dx,dy=x-previous.x,y-previous.y
    session.pointer.x,session.pointer.y=x,y
    session.previousPointer={x=x,y=y}
    if session.phase==3 then return handleRub(session,x,y,dx,dy) end
    if session.phase==4 then return handleOintment(session,x,y,dx,dy) end
    if session.phase==6 then return handleWrap(session,x,y) end
end

function FirstAid.mousereleased(session,x,y)
    if not session then return nil end
    session.pointer.x,session.pointer.y=x,y
    session.previousPointer=nil
    session.dragging=false
end

function FirstAid.keypressed(session,key)
    if key=="escape" or key=="q" then return "cancelled" end
    if key=="return" or key=="kpenter" or key=="space" then return FirstAid.choose(session,session.phase) end
    local index=tonumber(key)
    if index and index>=1 and index<=FirstAid.phaseCount then return FirstAid.choose(session,index) end
end

local function drawImage(image,x,y,size,color)
    if not image then return end
    local iw,ih=image:getDimensions(); local scale=size/math.max(iw,ih)
    love.graphics.setColor(color or {1,1,1,1})
    love.graphics.draw(image,x,y,0,scale,scale,iw/2,ih/2)
end

local function drawImageSized(image,x,y,width,height,rotation)
    if not image then return end
    local iw,ih=image:getDimensions()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,x,y,rotation or 0,width/iw,height/ih,iw/2,ih/2)
end

local function drawNpcWithInjury(image,session,cream)
    love.graphics.setColor(.14,.105,.075,1); love.graphics.ellipse("fill",480,495,145,23)
    if image then
        drawImage(image,480,355,350)
        love.graphics.stencil(function() love.graphics.circle("fill",injury.x,injury.y,injury.r) end,"replace",1)
        love.graphics.setStencilTest("greater",0)
        drawImage(image,480,355,350,{1,.28,.28,.72})
        love.graphics.setStencilTest()
    else
        love.graphics.setColor(.35,.25,.18); love.graphics.ellipse("fill",480,385,108,150)
        love.graphics.setColor(.46,.33,.22); love.graphics.circle("fill",480,255,62)
    end
    local pulse=6+3*math.sin((session.elapsed or 0)*4)
    love.graphics.setColor(1,.08,.08,.22); love.graphics.circle("fill",injury.x,injury.y,injury.r+pulse)
    love.graphics.setColor(1,.30,.24,.95); love.graphics.setLineWidth(4); love.graphics.circle("line",injury.x,injury.y,injury.r+pulse)
    love.graphics.setColor(cream); text("SELECT HURT AREA",injury.x-100,injury.y+73,200,25,.82,.75)
end

local function drawOintmentTrail(progress)
    love.graphics.setColor(.76,.68,.25,FirstAid.ointmentTrailOpacity)
    love.graphics.setLineWidth(10)
    for index=2,#(progress.ointmentTrail or {}) do
        local previous,point=progress.ointmentTrail[index-1],progress.ointmentTrail[index]
        love.graphics.line(previous.x,previous.y,point.x,point.y)
    end
    for _,point in ipairs(progress.ointmentTrail or {}) do love.graphics.circle("fill",point.x,point.y,5) end
end

local function drawWrapLayers(progress,assets)
    if progress.gauzePlaced then drawImage(assets.gauze,wound.x,wound.y,122) end
    local rotations={-.025,.018,-.014}
    local offsets={-35,0,35}
    for index=1,(progress.wrapPasses or 0) do
        drawImageSized(assets.bandageStrips[index],wound.x,wound.y+offsets[index],225,48,rotations[index])
    end
end

local function progressAmount(session)
    local progress=session.progress
    if session.phase==1 then return 0 end
    if session.phase==2 then return clamp(progress.pourTime/.75,0,1) end
    if session.phase==3 then return math.min(clamp(progress.rubDistance/220,0,1),clamp(progress.rubTurns/3,0,1)) end
    if session.phase==4 then return clamp(progress.ointmentDistance/180,0,1) end
    if session.phase==5 then return progress.gauzePlaced and 1 or 0 end
    return clamp(progress.wrapPasses/FirstAid.requiredWrapPasses,0,1)
end

local function drawTreatment(session,assets,cream,brass)
    love.graphics.setColor(.10,.07,.05,1); love.graphics.rectangle("fill",245,205,470,315,15,15)
    love.graphics.setColor(.42,.29,.20,1); love.graphics.setLineWidth(3); love.graphics.rectangle("line",245,205,470,315,15,15)
    if assets.wound then drawImage(assets.wound,wound.x,wound.y,330)
    else
        love.graphics.setColor(.52,.31,.20); love.graphics.circle("fill",wound.x,wound.y,115)
        love.graphics.setColor(.65,.08,.07); love.graphics.setLineWidth(8); love.graphics.line(wound.x-42,wound.y+10,wound.x+45,wound.y-12)
    end
    if session.phase>=4 then drawOintmentTrail(session.progress) end
    if session.phase==6 then drawWrapLayers(session.progress,assets) end

    local pointer=session.pointer
    if session.phase==2 then
        if hitCircle(pointer.x,pointer.y,wound,wound.r) then
            love.graphics.setColor(.58,.84,1,.75); love.graphics.circle("fill",pointer.x,pointer.y+12,8)
            love.graphics.circle("fill",pointer.x-10,pointer.y+27,5)
        end
        drawImage(assets.disinfectant,pointer.x+30,pointer.y-32,160)
    elseif session.phase==3 then drawImage(assets.rag,pointer.x,pointer.y,145)
    elseif session.phase==4 then drawImage(assets.swab,pointer.x+33,pointer.y-70,185)
    elseif session.phase==5 then drawImage(assets.gauze,pointer.x,pointer.y,135)
    elseif session.phase==6 then
        local left,right=wound.x-wound.r*.82,wound.x+wound.r*.82
        love.graphics.setColor(brass); love.graphics.setLineWidth(3)
        love.graphics.line(left,wound.y-116,left,wound.y+116); love.graphics.line(right,wound.y-116,right,wound.y+116)
        love.graphics.setColor(cream); text("LEFT",left-38,wound.y+116,76,24,.82,.75)
        text("RIGHT",right-38,wound.y+116,76,24,.82,.75)
        drawImage(assets.bandage,pointer.x,pointer.y,170)
    end
end

function FirstAid.draw(session,colors,assets)
    if not session then return end
    assets=assets or {}; assets.bandageStrips=assets.bandageStrips or {}
    local panel=colors.panel or {.08,.055,.035}; local cream=colors.cream or {1,.92,.74}; local brass=colors.brass or {.86,.57,.22}
    love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,960,720)
    love.graphics.setColor(panel); love.graphics.rectangle("fill",105,40,750,635,18,18)
    love.graphics.setColor(brass); love.graphics.setLineWidth(4); love.graphics.rectangle("line",105,40,750,635,18,18)
    love.graphics.setColor(brass); text("FIRST AID  •  SMALL CUT",155,63,650,39,1.32,1.1)
    local step=session.phase==1 and phaseNames[1] or ("TREATMENT STEP "..(session.phase-1).." OF "..FirstAid.treatmentStepCount.."  •  "..phaseNames[session.phase])
    love.graphics.setColor(cream); text(step,160,108,640,27,.95,.82)
    text(session.message or instructions[session.phase],175,143,610,42,.90,.82)

    love.graphics.setColor(.12,.085,.06,.95); love.graphics.rectangle("fill",125,188,105,332,12,12)
    love.graphics.setColor(brass); text("SUPPLY",130,202,95,26,.90,.82)
    if assets.medical then drawImage(assets.medical,177,294,92) end
    love.graphics.setColor(cream); text(title(session.itemName),131,346,93,78,.78,.68)
    text("Used after treatment",131,428,93,76,.74,.68)

    if session.phase==1 then drawNpcWithInjury(assets.npc,session,cream) else drawTreatment(session,assets,cream,brass) end

    local amount=progressAmount(session)
    love.graphics.setColor(.10,.07,.05,1); love.graphics.rectangle("fill",245,548,470,20,8,8)
    love.graphics.setColor(brass); love.graphics.rectangle("fill",247,550,466*amount,16,7,7)
    love.graphics.setColor(cream); text(math.floor(amount*100+0.5).."%",735,545,55,27,.85,.75)
    text("DRAG TO TREAT  •  ENTER: ACCESSIBLE STEP  •  Q: PAUSE",140,574,680,27,.84,.76)
    love.graphics.setColor(brass); love.graphics.rectangle("fill",cancel.x,cancel.y,cancel.w,cancel.h,7,7)
    love.graphics.setColor(.10,.06,.025,1); text("PAUSE TREATMENT",cancel.x+8,cancel.y+5,cancel.w-16,cancel.h-10,1,.85)
    love.graphics.setLineWidth(1); love.graphics.setColor(1,1,1,1)
end

function FirstAid.audit()
    local session=FirstAid.new({location=2,itemName="field-bandage-roll",itemSlot=1})
    local results={}
    for phase=1,FirstAid.phaseCount do results[phase]=FirstAid.choose(session,phase) end
    local complete=true
    for phase=1,FirstAid.phaseCount-1 do complete=complete and results[phase]=="progress" end
    complete=complete and results[FirstAid.phaseCount]=="complete"

    local physical=FirstAid.new({location=3,itemName="healing-salve",itemSlot=2})
    local locate=FirstAid.mousepressed(physical,injury.x,injury.y)
    FirstAid.mousemoved(physical,wound.x,wound.y); FirstAid.update(physical,.8)
    FirstAid.mousepressed(physical,wound.x-70,wound.y)
    for _,x in ipairs({wound.x+70,wound.x-70,wound.x+70,wound.x-70,wound.x+70}) do FirstAid.mousemoved(physical,x,wound.y) end
    FirstAid.mousepressed(physical,wound.x-70,wound.y)
    for index=1,14 do FirstAid.mousemoved(physical,index%2==0 and wound.x-70 or wound.x+70,wound.y) end
    local gauze=FirstAid.mousepressed(physical,wound.x,wound.y)
    FirstAid.mousepressed(physical,wound.x-82,wound.y)
    FirstAid.mousemoved(physical,wound.x+82,wound.y)
    FirstAid.mousemoved(physical,wound.x-82,wound.y)
    local wrapped=FirstAid.mousemoved(physical,wound.x+82,wound.y)
    local gestures=locate=="progress" and gauze=="progress" and wrapped=="complete"
        and physical.progress.rubTurns>=3 and #physical.progress.ointmentTrail>=12
    return {
        ready=complete and gestures and session.progress.gauzePlaced and session.progress.wrapPasses==FirstAid.requiredWrapPasses,
        stages=FirstAid.phaseCount,treatmentSteps=FirstAid.treatmentStepCount,woundType=FirstAid.woundType,
        disinfectantHover=true,ragRub=true,ointmentTrailOpacity=FirstAid.ointmentTrailOpacity,
        gauzePlacement=true,bandagePasses=FirstAid.requiredWrapPasses,bandageStripSprites=3,
        keyboard=true,touch=true,gestures=gestures,
    }
end

return FirstAid
