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
    return {version=TrackDebris.version,kind="track-debris-clearing",location=options.location or 1,helpQuestId=options.helpQuestId,
        progress=progress,phase=progress.phase,maximumMistakes=TrackDebris.maximumMistakes,message=nil,
        failureMessage="The debris shifted. Step back and begin another safe attempt.",pauseMessage="Track clearing paused. Your inspection marks are saved."}
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
        if session.progress.step>3 then return advance(session,2,"Inspection complete. Use the safest tool for each marked obstruction.") end
        session.message="Marked. Continue inward from the newly safe edge."; return "progress"
    elseif session.phase==2 then
        local item=currentDebris(session)
        if index~=item.tool then return miss(session,"That tool could scatter the "..item.name:lower()..". Match the tool to the hazard.") end
        session.progress.step=session.progress.step+1
        if session.progress.step>3 then return advance(session,3,"The path is clear. Sort the recovered material before reopening the track.") end
        session.message="Removed safely. Choose a tool for the next obstruction."; return "progress"
    end
    local item=currentDebris(session)
    if index~=item.sort then return miss(session,"That destination is unsafe for "..item.name:lower()..".") end
    session.progress.step=session.progress.step+1
    if session.progress.step>3 then return "complete" end
    session.message="Load sorted. Place the next recovered material."; return "progress"
end

function TrackDebris.keypressed(session,key)
    if key=="escape" or key=="q" then return "cancelled" end
    local index=tonumber(key)
    if index and index>=1 and index<=3 then return TrackDebris.choose(session,index) end
end

function TrackDebris.mousepressed(session,x,y)
    local zones=session.phase==1 and TrackDebris.scanZones or (session.phase==2 and TrackDebris.toolZones or TrackDebris.sortZones)
    for index,zone in ipairs(zones) do local dx,dy=x-zone.x,y-zone.y; if dx*dx+dy*dy<=58*58 then return TrackDebris.choose(session,index) end end
end

local function drawAtlasSprite(image,index,x,y,size)
    if not image then return end
    local iw,ih=image:getDimensions(); local sw,sh=iw/2,ih/2; local column=(index-1)%2; local row=math.floor((index-1)/2)
    local quad=love.graphics.newQuad(column*sw,row*sh,sw,sh,iw,ih); local scale=size/math.max(sw,sh)
    love.graphics.draw(image,quad,x,y,0,scale,scale,sw/2,sh/2)
end

function TrackDebris.draw(session,colors,image,clock)
    if not session then return end
    local panel=colors.panel or {.08,.055,.035}; local cream=colors.cream or {1,.92,.74}; local brass=colors.brass or {.86,.57,.22}; local pulse=1+math.sin((clock or 0)*5)*.08
    love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,960,720)
    love.graphics.setColor(panel); love.graphics.rectangle("fill",145,64,670,592,12,12)
    love.graphics.setColor(brass); love.graphics.setLineWidth(4); love.graphics.rectangle("line",145,64,670,592,12,12)
    love.graphics.setColor(cream); love.graphics.printf("CLEAR THE TRACK",185,90,590,"center",0,1.25,1.25)
    love.graphics.printf("STAGE "..session.phase.." OF 3  •  "..TrackDebris.objective(session),190,138,580,"center",0,.68,.68)
    love.graphics.setColor(.28,.23,.18); love.graphics.rectangle("fill",260,255,440,145,10,10)
    love.graphics.setColor(.7,.62,.48); love.graphics.rectangle("fill",270,282,420,14); love.graphics.rectangle("fill",270,360,420,14)
    for x=292,668,47 do love.graphics.setColor(.38,.25,.16); love.graphics.rectangle("fill",x,267,13,116) end
    if session.phase==1 then
        local target=scanTarget(session)
        for index,zone in ipairs(TrackDebris.scanZones) do
            love.graphics.setColor(index==target and {.98,.68,.2,1} or {.65,.48,.28,.85}); love.graphics.circle("line",zone.x,zone.y,index==target and 48*pulse or 38)
            love.graphics.line(zone.x-25,zone.y-12,zone.x+22,zone.y+15); love.graphics.line(zone.x-18,zone.y+18,zone.x+24,zone.y-16)
            love.graphics.setColor(cream); love.graphics.print(tostring(index),zone.x-5,zone.y+48)
        end
    elseif session.phase==2 then
        local item=currentDebris(session); love.graphics.setColor(cream); love.graphics.printf("CURRENT:  "..item.name,270,220,420,"center",0,.78,.78)
        for index,zone in ipairs(TrackDebris.toolZones) do
            love.graphics.setColor(.82,.62,.32,1); love.graphics.circle("line",zone.x,zone.y,55)
            drawAtlasSprite(image,index,zone.x,zone.y,92); love.graphics.setColor(cream); love.graphics.printf(index.."  "..toolNames[index],zone.x-72,zone.y+60,144,"center",0,.58,.58)
        end
    else
        local item=currentDebris(session); love.graphics.setColor(cream); love.graphics.printf("SORT:  "..item.name,270,220,420,"center",0,.78,.78)
        for index,zone in ipairs(TrackDebris.sortZones) do
            love.graphics.setColor(.82,.62,.32,1); love.graphics.circle("line",zone.x,zone.y,55)
            drawAtlasSprite(image,4,zone.x,zone.y,88); love.graphics.setColor(cream); love.graphics.printf(index.."  "..sortNames[index],zone.x-72,zone.y+60,144,"center",0,.58,.58)
        end
    end
    love.graphics.setColor(cream); love.graphics.printf(session.message or "Work from a stable edge. Three mistakes end the attempt for a safe retry.",205,535,550,"center",0,.7,.7)
    love.graphics.setColor(brass); love.graphics.printf("MISTAKES  "..session.progress.mistakes.." / "..session.maximumMistakes.."     •     1–3 / TAP     •     Q / BACK TO PAUSE",205,596,550,"center",0,.62,.62)
    love.graphics.setLineWidth(1); love.graphics.setColor(1,1,1,1)
end

function TrackDebris.audit()
    local clean=TrackDebris.new({location=4,progress={}}); local progressed=true
    for _=1,3 do progressed=progressed and TrackDebris.choose(clean,scanTarget(clean))=="progress" end
    for _=1,3 do progressed=progressed and TrackDebris.choose(clean,currentDebris(clean).tool)=="progress" end
    local complete
    for _=1,3 do complete=TrackDebris.choose(clean,currentDebris(clean).sort) end
    local restored=TrackDebris.new({location=clean.location,progress=clean.progress})
    local failed=TrackDebris.new({location=1,progress={}}); local failure
    for _=1,3 do failure=TrackDebris.choose(failed,scanTarget(failed)%3+1) end
    return {ready=progressed and complete=="complete" and failure=="failed" and restored.phase==3 and restored.progress.step==4,
        stages=3,decisions=9,maximumMistakes=3,persistent=true,keyboard=true,touch=true,curve="track-debris-v1"}
end

return TrackDebris
