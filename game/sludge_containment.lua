local SludgeContainment={}

SludgeContainment.version=1
SludgeContainment.maximumMistakes=3
SludgeContainment.barrierZones={{x=330,y=330},{x=480,y=385},{x=630,y=330}}
SludgeContainment.absorbZones={{x=365,y=360},{x=480,y=325},{x=595,y=360}}

local objectives={
    "Read the flow arrows and place the barrier downstream.",
    "Pack moss into each pulsing leak before it spreads.",
    "Seal the source, then scoop the contained sludge.",
}

local function clampIndex(value)
    return math.max(1,math.min(3,math.floor(tonumber(value) or 1)))
end

function SludgeContainment.new(options)
    options=options or {}
    local progress=type(options.progress)=="table" and options.progress or {}
    progress.phase=clampIndex(progress.phase)
    progress.step=math.max(1,math.floor(tonumber(progress.step) or 1))
    progress.mistakes=math.max(0,math.floor(tonumber(progress.mistakes) or 0))
    progress.barrierTarget=clampIndex(progress.barrierTarget or (((tonumber(options.location) or 1)-1)%3)+1)
    return {version=SludgeContainment.version,kind="sludge-containment",location=options.location or 1,helpQuestId=options.helpQuestId,
        progress=progress,phase=progress.phase,maximumMistakes=SludgeContainment.maximumMistakes,message=nil,
        failureMessage="The barrier slipped. The supplies were recovered; try again.",pauseMessage="Containment paused. Your progress is saved."}
end

function SludgeContainment.objective(session)
    return objectives[(session and session.phase) or 1]
end

local function miss(session,message)
    session.progress.mistakes=session.progress.mistakes+1
    session.message=message
    if session.progress.mistakes>=session.maximumMistakes then return "failed" end
    return "wrong"
end

local function advance(session,phase,message)
    session.phase=phase; session.progress.phase=phase; session.progress.step=1; session.message=message
    return "progress"
end

function SludgeContainment.choose(session,index)
    if not session then return nil end
    index=math.floor(tonumber(index) or 0)
    if session.phase==1 then
        if index~=session.progress.barrierTarget then return miss(session,"The seep slips around that side. Follow the cyan flow arrows.") end
        return advance(session,2,"Barrier anchored. Now pack the pulsing leaks with absorbent moss.")
    elseif session.phase==2 then
        local target=((session.location+session.progress.step-2)%3)+1
        if index~=target then return miss(session,"That pocket is stable. Find the brighter pulsing leak.") end
        session.progress.step=session.progress.step+1
        if session.progress.step>3 then return advance(session,3,"The spread has stopped. Seal the source before collecting it.") end
        session.message="Leak packed. Find the next pulsing pocket."
        return "progress"
    end
    local expected=session.progress.step==1 and 1 or 2
    if index~=expected then return miss(session,expected==1 and "Scooping now would reopen the seep. Seal it first." or "The source is sealed. Collect the trapped sludge now.") end
    if expected==1 then session.progress.step=2; session.message="Seal secured. Use the pan to collect the trapped sludge."; return "progress" end
    return "complete"
end

function SludgeContainment.keypressed(session,key)
    if key=="escape" or key=="q" then return "cancelled" end
    local index=tonumber(key)
    if index and index>=1 and index<=3 and session.phase<3 then return SludgeContainment.choose(session,index) end
    if session.phase==3 and (index==1 or index==2) then return SludgeContainment.choose(session,index) end
end

function SludgeContainment.mousepressed(session,x,y)
    local zones=session.phase==2 and SludgeContainment.absorbZones or SludgeContainment.barrierZones
    if session.phase==3 then zones={{x=395,y=425},{x=565,y=425}} end
    for index,zone in ipairs(zones) do
        local dx,dy=x-zone.x,y-zone.y
        if dx*dx+dy*dy<=58*58 then return SludgeContainment.choose(session,index) end
    end
end

local function drawAtlasSprite(image,index,x,y,size)
    if not image then return end
    local iw,ih=image:getDimensions(); local sw,sh=iw/2,ih/2
    local column=(index-1)%2; local row=math.floor((index-1)/2)
    local quad=love.graphics.newQuad(column*sw,row*sh,sw,sh,iw,ih)
    local scale=size/math.max(sw,sh)
    love.graphics.draw(image,quad,x,y,0,scale,scale,sw/2,sh/2)
end

function SludgeContainment.draw(session,colors,image,clock)
    if not session then return end
    local panel=colors.panel or {.08,.055,.035}; local cream=colors.cream or {1,.92,.74}; local brass=colors.brass or {.86,.57,.22}
    love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,960,720)
    love.graphics.setColor(panel); love.graphics.rectangle("fill",155,70,650,580,12,12)
    love.graphics.setColor(brass); love.graphics.setLineWidth(4); love.graphics.rectangle("line",155,70,650,580,12,12)
    love.graphics.setColor(cream); love.graphics.printf("CONTAIN THE SLUDGE",190,94,580,"center",0,1.25,1.25)
    love.graphics.printf("STAGE "..session.phase.." OF 3  •  "..SludgeContainment.objective(session),195,142,570,"center",0,.68,.68)
    love.graphics.setColor(.04,.42,.45,.78); love.graphics.ellipse("fill",480,340,175,82)
    love.graphics.setColor(.12,.88,.84,.9); love.graphics.setLineWidth(3); love.graphics.ellipse("line",480,340,175,82)
    local pulse=1+math.sin((clock or 0)*5)*.08
    if session.phase==1 then
        local target=SludgeContainment.barrierZones[session.progress.barrierTarget]
        love.graphics.setColor(.15,.9,.88,.9); love.graphics.line(480,340,target.x,target.y)
        for index,zone in ipairs(SludgeContainment.barrierZones) do
            love.graphics.setColor(index==session.progress.barrierTarget and {.15,.95,.88,1} or {.95,.72,.30,1})
            love.graphics.circle("line",zone.x,zone.y,48); drawAtlasSprite(image,1,zone.x,zone.y,82)
            love.graphics.setColor(cream); love.graphics.print(tostring(index),zone.x-5,zone.y+50)
        end
    elseif session.phase==2 then
        local target=((session.location+session.progress.step-2)%3)+1
        for index,zone in ipairs(SludgeContainment.absorbZones) do
            love.graphics.setColor(index==target and {.2,.98,.86,1} or {.5,.72,.58,.8})
            love.graphics.circle("line",zone.x,zone.y,index==target and 48*pulse or 38)
            drawAtlasSprite(image,2,zone.x,zone.y,72)
            love.graphics.setColor(cream); love.graphics.print(tostring(index),zone.x-5,zone.y+45)
        end
    else
        love.graphics.setColor(session.progress.step==1 and {.2,.98,.86,1} or {.95,.72,.30,1}); love.graphics.circle("line",395,425,58)
        love.graphics.setColor(session.progress.step==2 and {.2,.98,.86,1} or {.95,.72,.30,1}); love.graphics.circle("line",565,425,58)
        drawAtlasSprite(image,3,395,425,105); drawAtlasSprite(image,4,565,425,105)
        love.graphics.setColor(cream); love.graphics.printf("1  SEAL",335,486,120,"center",0,.7,.7); love.graphics.printf("2  SCOOP",505,486,120,"center",0,.7,.7)
    end
    love.graphics.setColor(cream); love.graphics.printf(session.message or "Choose carefully. Three mistakes end the attempt for a safe retry.",205,535,550,"center",0,.7,.7)
    love.graphics.setColor(brass); love.graphics.printf("MISTAKES  "..session.progress.mistakes.." / "..session.maximumMistakes.."     •     1–3 / TAP     •     Q / BACK TO PAUSE",205,592,550,"center",0,.62,.62)
    love.graphics.setLineWidth(1); love.graphics.setColor(1,1,1,1)
end

function SludgeContainment.audit()
    local clean=SludgeContainment.new({location=2,progress={}})
    local barrier=clean.progress.barrierTarget
    local first=SludgeContainment.choose(clean,barrier)
    local packed=true
    for _=1,3 do local target=((clean.location+clean.progress.step-2)%3)+1; packed=packed and SludgeContainment.choose(clean,target)=="progress" end
    local sealed=SludgeContainment.choose(clean,1); local completed=SludgeContainment.choose(clean,2)
    local failed=SludgeContainment.new({location=1,progress={}}); local wrong=failed.progress.barrierTarget%3+1; local failure
    for _=1,failed.maximumMistakes do failure=SludgeContainment.choose(failed,wrong) end
    local restored=SludgeContainment.new({location=clean.location,progress=clean.progress})
    return {ready=first=="progress" and packed and sealed=="progress" and completed=="complete" and failure=="failed"
            and restored.phase==3 and restored.progress.step==2,stages=3,maximumMistakes=3,persistent=true,keyboard=true,touch=true,
        curve="sludge-containment-v1"}
end

return SludgeContainment
