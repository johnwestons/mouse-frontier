local UI=require("game.activity_minigame_ui")
local Wildlife={version=1,maximumMistakes=3}
Wildlife.zones={{x=350,y=390},{x=480,y=350},{x=610,y=390}}
local objectives={"Read the freshest tracks without approaching the animals.","Clean the trough in a safe sanitary order.","Measure an appropriate portion for each visitor group."}
local visitors={{name="SONGBIRDS",portion=1},{name="FIELD MICE",portion=1},{name="RABBITS",portion=2},{name="DEER",portion=3}}
local portions={"SMALL PORTION","MEDIUM PORTION","LARGE PORTION"}
local cleaning={"SCOOP OLD FEED","SCRUB TROUGH","RINSE CLEAN"}
local function phase(value) return math.max(1,math.min(3,math.floor(tonumber(value) or 1))) end
local function trackTarget(session) return ((session.progress.start+session.progress.step-2)%3)+1 end
local function visitor(session) return visitors[((session.location+session.progress.step-2)%#visitors)+1] end
function Wildlife.new(options)
    options=options or {}; local progress=type(options.progress)=="table" and options.progress or {}
    progress.phase=phase(progress.phase); progress.step=math.max(1,math.floor(tonumber(progress.step) or 1)); progress.mistakes=math.max(0,math.floor(tonumber(progress.mistakes) or 0))
    progress.start=math.max(1,math.min(3,math.floor(tonumber(progress.start) or (((tonumber(options.location) or 1)-1)%3)+1)))
    return {kind="wildlife-trough-care",location=options.location or 1,helpQuestId=options.helpQuestId,progress=progress,phase=progress.phase,maximumMistakes=3,
        failureMessage="The animals grew wary. Back away and try again after the area settles.",pauseMessage="Wildlife care paused. Your observations are saved."}
end
function Wildlife.objective(session) return objectives[session and session.phase or 1] end
function Wildlife.choose(session,index)
    index=math.floor(tonumber(index) or 0)
    if session.phase==1 then
        if index~=trackTarget(session) then return UI.miss(session,"Those tracks are old. Observe the brighter fresh trail without moving closer.") end
        session.progress.step=session.progress.step+1; if session.progress.step>3 then return UI.advance(session,2,"Visitors identified. Clean the trough before adding fresh food.") end
        session.message="Fresh trail recorded. Observe the next approach."; return "progress"
    elseif session.phase==2 then
        if index~=session.progress.step then return UI.miss(session,"Remove old feed, scrub, then rinse so the trough stays sanitary.") end
        session.progress.step=session.progress.step+1; if session.progress.step>3 then return UI.advance(session,3,"The trough is clean. Measure food for each visitor group.") end
        session.message="Cleaning step complete. Continue in order."; return "progress"
    end
    local group=visitor(session); if index~=group.portion then return UI.miss(session,"That portion is not right for "..group.name:lower()..". Avoid waste and crowding.") end
    session.progress.step=session.progress.step+1; if session.progress.step>3 then return "complete" end
    session.message="Portion placed. Prepare the next visitor's share."; return "progress"
end
function Wildlife.keypressed(session,key) if key=="escape" or key=="q" then return "cancelled" end local i=tonumber(key); if i and i>=1 and i<=3 then return Wildlife.choose(session,i) end end
function Wildlife.mousepressed(session,x,y) local i=UI.hit(Wildlife.zones,x,y); return i and Wildlife.choose(session,i) end
function Wildlife.draw(session,colors,image,clock)
    local cream,brass=UI.begin(colors,"CARE FOR THE WILDLIFE",session,Wildlife.objective(session)); local pulse=1+math.sin((clock or 0)*4.5)*.08
    love.graphics.setColor(.16,.28,.18); love.graphics.rectangle("fill",255,245,450,190,18,18)
    if session.phase==1 then
        local active=trackTarget(session); for i,z in ipairs(Wildlife.zones) do love.graphics.setColor(i==active and {.92,.78,.28,1} or {.55,.48,.3,.8}); love.graphics.ellipse("line",z.x,z.y,i==active and 47*pulse or 37,i==active and 30*pulse or 24); love.graphics.setColor(cream); love.graphics.print(tostring(i),z.x-5,z.y+42) end
    elseif session.phase==2 then
        for i,z in ipairs(Wildlife.zones) do love.graphics.setColor(brass); love.graphics.circle("line",z.x,z.y,55); UI.sprite(image,i==1 and 1 or i,z.x,z.y,92); love.graphics.setColor(cream); love.graphics.printf(i.."  "..cleaning[i],z.x-72,z.y+60,144,"center",0,.58,.58) end
    else
        love.graphics.setColor(cream); love.graphics.printf("VISITORS:  "..visitor(session).name,270,220,420,"center",0,.78,.78)
        for i,z in ipairs(Wildlife.zones) do love.graphics.setColor(brass); love.graphics.circle("line",z.x,z.y,55); UI.sprite(image,i==3 and 4 or 1,z.x,z.y,88); love.graphics.setColor(cream); love.graphics.printf(i.."  "..portions[i],z.x-72,z.y+60,144,"center",0,.58,.58) end
    end
    UI.footer(session,cream,brass,"Observe quietly. Three mistakes end the attempt without consuming food.")
end
function Wildlife.audit()
    local s=Wildlife.new({location=3,progress={}}); local ok=true
    for _=1,3 do ok=ok and Wildlife.choose(s,trackTarget(s))=="progress" end
    for i=1,3 do ok=ok and Wildlife.choose(s,i)=="progress" end
    local done; for _=1,3 do done=Wildlife.choose(s,visitor(s).portion) end
    local restored=Wildlife.new({location=3,progress=s.progress}); local bad=Wildlife.new({location=1,progress={}}); local failed
    for _=1,3 do failed=Wildlife.choose(bad,trackTarget(bad)%3+1) end
    return {ready=ok and done=="complete" and restored.phase==3 and restored.progress.step==4 and failed=="failed",stages=3,decisions=9,maximumMistakes=3,persistent=true,keyboard=true,touch=true,foodProtected=true,curve="wildlife-trough-v1"}
end
return Wildlife
