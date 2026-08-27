local UI=require("game.activity_minigame_ui")
local Difficulty=require("game.activity_difficulty")
local TrackDebris={}

TrackDebris.version=1
TrackDebris.maximumMistakes=3
TrackDebris.scanZones={{x=360,y=350},{x=480,y=330},{x=600,y=350}}
TrackDebris.toolZones={{x=350,y=415},{x=480,y=415},{x=610,y=415}}
TrackDebris.sortZones={{x=350,y=425},{x=480,y=425},{x=610,y=425}}

local objectives={
    "Inspect and mark the pulsing debris from the safe edge inward.",
    "Match each obstruction with the safest cleanup tool.",
    "Sort every cleared load into its safe destination.",
}
local debris={
    {name="LOOSE RAIL SPIKES",tool=3,sort=2},
    {name="JAMMED TIMBER",tool=2,sort=1},
    {name="SHARP SCRAP",tool=1,sort=3},
}
local toolNames={"WORK GLOVES","PRY BAR","MAGNETIC SWEEP"}
local sortNames={"REUSE WOOD","SCRAP METAL","SAFE SHARPS"}

local function clampPhase(value) return math.max(1,math.min(3,math.floor(tonumber(value) or 1))) end

function TrackDebris.new(options)
    options=options or {}
    local progress=type(options.progress)=="table" and options.progress or {}
    progress.phase=clampPhase(progress.phase); progress.step=math.max(1,math.floor(tonumber(progress.step) or 1))
    progress.mistakes=math.max(0,math.floor(tonumber(progress.mistakes) or 0))
    progress.scanStart=math.max(1,math.min(3,math.floor(tonumber(progress.scanStart) or (((tonumber(options.location) or 1)-1)%3)+1)))
    return Difficulty.apply({version=TrackDebris.version,kind="track-debris-clearing",location=options.location or 1,helpQuestId=options.helpQuestId,
        progress=progress,phase=progress.phase,message=nil,failureMessage="The debris shifted. Step back and begin another safe attempt.",
        pauseMessage="Track clearing paused. Your inspection marks are saved."},options.location)
end

function TrackDebris.objective(session) return objectives[(session and session.phase) or 1] end

local function scanTarget(session) return ((session.progress.scanStart+session.progress.step-2)%3)+1 end
local function currentDebris(session) return debris[((session.location+session.progress.step-2)%#debris)+1] end
local function miss(session,message)
    session.progress.mistakes=session.progress.mistakes+1; session.message=message
    return session.progress.mistakes>=session.maximumMistakes and "failed" or "wrong"
end
local function advance(session,phase,message)
    session.phase=phase; session.progress.phase=phase; session.progress.step=1; session.message=message
    return "progress"
end

function TrackDebris.choose(session,index)
    if not session then return nil end
    index=math.floor(tonumber(index) or 0)
    if session.phase==1 then
        if index~=scanTarget(session) then return miss(session,"That pile may shift. Mark the brighter loose edge first.") end
        session.progress.step=session.progress.step+1
        if session.progress.step>session.rounds then return advance(session,2,"Inspection complete. Use the safest tool for each marked obstruction.") end
        session.message="Marked. Continue inward from the newly safe edge."; return "progress"
    elseif session.phase==2 then
        local item=currentDebris(session)
        if index~=item.tool then return miss(session,"That tool could scatter the "..item.name:lower()..". Match the tool to the hazard.") end
        session.progress.step=session.progress.step+1
        if session.progress.step>session.rounds then return advance(session,3,"The path is clear. Sort the recovered material before reopening the track.") end
        session.message="Removed safely. Choose a tool for the next obstruction."; return "progress"
    end
    local item=currentDebris(session)
    if index~=item.sort then return miss(session,"That destination is unsafe for "..item.name:lower()..".") end
    session.progress.step=session.progress.step+1
    if session.progress.step>session.rounds then return "complete" end
    session.message="Load sorted. Place the next recovered material."; return "progress"
end

function TrackDebris.keypressed(session,key)
    if key=="escape" or key=="q" then return "cancelled" end
    local index=tonumber(key)
    if index and index>=1 and index<=3 then return TrackDebris.choose(session,index) end
end

function TrackDebris.mousepressed(session,x,y)
    local zones=session.phase==1 and TrackDebris.scanZones or (session.phase==2 and TrackDebris.toolZones or TrackDebris.sortZones)
    return (function(index) return index and TrackDebris.choose(session,index) end)(UI.hit(UI.variantZones(zones,session),x,y,58))
end

local function drawAtlasSprite(image,index,x,y,size)
    if not image then return end
    local iw,ih=image:getDimensions(); local sw,sh=iw/2,ih/2; local column=(index-1)%2; local row=math.floor((index-1)/2)
    local quad=love.graphics.newQuad(column*sw,row*sh,sw,sh,iw,ih); local scale=size/math.max(sw,sh)
    love.graphics.draw(image,quad,x,y,0,scale,scale,sw/2,sh/2)
end

function TrackDebris.draw(session,colors,image,clock)
    if not session then return end
    local cream,brass=UI.begin(colors,"CLEAR THE TRACK",session,TrackDebris.objective(session)); local pulse=1+math.sin((clock or 0)*5)*.08
    love.graphics.setColor(session.difficulty.palette.ground); love.graphics.rectangle("fill",260,255,440,145,10,10)
    love.graphics.setColor(.7,.62,.48); love.graphics.rectangle("fill",270,282,420,14); love.graphics.rectangle("fill",270,360,420,14)
    for x=292,668,47 do love.graphics.setColor(.38,.25,.16); love.graphics.rectangle("fill",x,267,13,116) end
    if session.phase==1 then
        local target=scanTarget(session)
        for index,zone in ipairs(UI.variantZones(TrackDebris.scanZones,session)) do
            love.graphics.setColor(index==target and {.98,.68,.2,1} or {.65,.48,.28,.85}); love.graphics.circle("line",zone.x,zone.y,index==target and 48*pulse or 38)
            love.graphics.line(zone.x-25,zone.y-12,zone.x+22,zone.y+15); love.graphics.line(zone.x-18,zone.y+18,zone.x+24,zone.y-16)
            love.graphics.setColor(cream); love.graphics.print(tostring(index),zone.x-5,zone.y+48)
        end
    elseif session.phase==2 then
        local item=currentDebris(session); love.graphics.setColor(cream); love.graphics.printf("CURRENT:  "..item.name,270,220,420,"center",0,.78,.78)
        for index,zone in ipairs(UI.variantZones(TrackDebris.toolZones,session)) do
            love.graphics.setColor(.82,.62,.32,1); love.graphics.circle("line",zone.x,zone.y,55)
            drawAtlasSprite(image,index,zone.x,zone.y,92); love.graphics.setColor(cream); love.graphics.printf(index.."  "..toolNames[index],zone.x-72,zone.y+60,144,"center",0,.58,.58)
        end
    else
        local item=currentDebris(session); love.graphics.setColor(cream); love.graphics.printf("SORT:  "..item.name,270,220,420,"center",0,.78,.78)
        for index,zone in ipairs(UI.variantZones(TrackDebris.sortZones,session)) do
            love.graphics.setColor(.82,.62,.32,1); love.graphics.circle("line",zone.x,zone.y,55)
            drawAtlasSprite(image,4,zone.x,zone.y,88); love.graphics.setColor(cream); love.graphics.printf(index.."  "..sortNames[index],zone.x-72,zone.y+60,144,"center",0,.58,.58)
        end
    end
    UI.footer(session,cream,brass,"Work from a stable edge. Mistakes end the attempt for a safe retry.")
end

function TrackDebris.audit()
    local function complete(location)
        local s=TrackDebris.new({location=location,progress={}}); local ok=true
        for _=1,s.rounds do ok=ok and TrackDebris.choose(s,scanTarget(s))=="progress" end
        for _=1,s.rounds do ok=ok and TrackDebris.choose(s,currentDebris(s).tool)=="progress" end
        local done; for _=1,s.rounds do done=TrackDebris.choose(s,currentDebris(s).sort) end
        return s,ok and done=="complete"
    end
    local early,earlyOK=complete(4); local late,lateOK=complete(45); local restored=TrackDebris.new({location=45,progress=late.progress})
    local bad=TrackDebris.new({location=45,progress={}}); local failure; for _=1,bad.maximumMistakes do failure=TrackDebris.choose(bad,scanTarget(bad)%3+1) end
    return {ready=earlyOK and lateOK and failure=="failed" and restored.phase==3 and restored.progress.step==late.rounds+1,stages=3,
        earlyDecisions=early.rounds*3,lateDecisions=late.rounds*3,lateMistakes=late.maximumMistakes,persistent=true,keyboard=true,touch=true,curve="track-debris-v2"}
end

return TrackDebris
