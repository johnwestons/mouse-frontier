local UI=require("game.activity_minigame_ui")
local Difficulty=require("game.activity_difficulty")
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
    return Difficulty.apply({version=SludgeContainment.version,kind="sludge-containment",location=options.location or 1,helpQuestId=options.helpQuestId,
        progress=progress,phase=progress.phase,message=nil,failureMessage="The barrier slipped. The supplies were recovered; try again.",
        pauseMessage="Containment paused. Your progress is saved."},options.location)
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
        if session.progress.step>session.rounds then return advance(session,3,"The spread has stopped. Seal the source before collecting it.") end
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
    if session.phase<3 then zones=UI.variantZones(zones,session) end
    local index=UI.hit(zones,x,y,58); return index and SludgeContainment.choose(session,index)
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
    local cream,brass=UI.begin(colors,"CONTAIN THE SLUDGE",session,SludgeContainment.objective(session))
    love.graphics.setColor(session.difficulty.palette.ground); love.graphics.ellipse("fill",480,340,175,82)
    love.graphics.setColor(.12,.88,.84,.9); love.graphics.setLineWidth(3); love.graphics.ellipse("line",480,340,175,82)
    local pulse=1+math.sin((clock or 0)*5)*.08
    if session.phase==1 then
        local zones=UI.variantZones(SludgeContainment.barrierZones,session); local target=zones[session.progress.barrierTarget]
        love.graphics.setColor(.15,.9,.88,.9); love.graphics.line(480,340,target.x,target.y)
        for index,zone in ipairs(zones) do
            love.graphics.setColor(index==session.progress.barrierTarget and {.15,.95,.88,1} or {.95,.72,.30,1})
            love.graphics.circle("line",zone.x,zone.y,48); drawAtlasSprite(image,1,zone.x,zone.y,82)
            love.graphics.setColor(cream); love.graphics.print(tostring(index),zone.x-5,zone.y+50)
        end
    elseif session.phase==2 then
        local target=((session.location+session.progress.step-2)%3)+1
        for index,zone in ipairs(UI.variantZones(SludgeContainment.absorbZones,session)) do
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
    UI.footer(session,cream,brass,"Choose carefully. Mistakes end the attempt for a safe retry.")
end

function SludgeContainment.audit()
    local function complete(location)
        local s=SludgeContainment.new({location=location,progress={}}); local ok=SludgeContainment.choose(s,s.progress.barrierTarget)=="progress"
        for _=1,s.rounds do local target=((s.location+s.progress.step-2)%3)+1; ok=ok and SludgeContainment.choose(s,target)=="progress" end
        local sealed=SludgeContainment.choose(s,1); local done=SludgeContainment.choose(s,2)
        return s,ok and sealed=="progress" and done=="complete"
    end
    local early,earlyOK=complete(2); local late,lateOK=complete(45); local restored=SludgeContainment.new({location=45,progress=late.progress})
    local bad=SludgeContainment.new({location=45,progress={}}); local wrong=bad.progress.barrierTarget%3+1; local failure
    for _=1,bad.maximumMistakes do failure=SludgeContainment.choose(bad,wrong) end
    return {ready=earlyOK and lateOK and failure=="failed" and restored.phase==3 and restored.progress.step==2,stages=3,
        earlyAbsorbs=early.rounds,lateAbsorbs=late.rounds,lateMistakes=late.maximumMistakes,persistent=true,keyboard=true,touch=true,
        curve="sludge-containment-v2"}
end

return SludgeContainment
