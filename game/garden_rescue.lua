local UI=require("game.activity_minigame_ui")
local Difficulty=require("game.activity_difficulty")
local Garden={version=1,maximumMistakes=3}
Garden.zones={{x=350,y=385},{x=480,y=350},{x=610,y=385}}
local objectives={"Mark the thorn clusters without disturbing healthy vines.","Choose the safest tool for each damaged plant.","Restore the bed in the order roots need."}
local care={{name="THORN CROWN",tool=1},{name="TANGLED CUTTINGS",tool=2},{name="LEANING SEEDLING",tool=3}}
local restoration={"COMPOST ROOTS","WATER DEEPLY","MULCH THE SOIL"}
local toolNames={"PRUNING SHEARS","WORK GLOVES","SUPPORT STAKE"}
local function phase(value) return math.max(1,math.min(3,math.floor(tonumber(value) or 1))) end
local function target(session) return ((session.progress.start+session.progress.step-2)%3)+1 end
local function current(session) return care[((session.location+session.progress.step-2)%3)+1] end

function Garden.new(options)
    options=options or {}; local progress=type(options.progress)=="table" and options.progress or {}
    progress.phase=phase(progress.phase); progress.step=math.max(1,math.floor(tonumber(progress.step) or 1)); progress.mistakes=math.max(0,math.floor(tonumber(progress.mistakes) or 0))
    progress.start=math.max(1,math.min(3,math.floor(tonumber(progress.start) or (((tonumber(options.location) or 1)-1)%3)+1)))
    return Difficulty.apply({kind="garden-rescue",location=options.location or 1,helpQuestId=options.helpQuestId,progress=progress,phase=progress.phase,
        failureMessage="The thorns shifted toward a seedling. Step back and plan another careful attempt.",pauseMessage="Garden rescue paused. Your marked plants are saved."},options.location)
end
function Garden.objective(session) return objectives[session and session.phase or 1] end
function Garden.choose(session,index)
    index=math.floor(tonumber(index) or 0)
    if session.phase==1 then
        if index~=target(session) then return UI.miss(session,"That growth is healthy. Follow the pulsing thorn cluster.") end
        session.progress.step=session.progress.step+1; if session.progress.step>session.rounds then return UI.advance(session,2,"The thorns are marked. Match each plant with its safest tool.") end
        session.message="Thorn cluster marked. Check the next bed."; return "progress"
    elseif session.phase==2 then
        local task=current(session); if index~=task.tool then return UI.miss(session,"That could damage the "..task.name:lower()..". Choose a gentler tool.") end
        session.progress.step=session.progress.step+1; if session.progress.step>session.rounds then return UI.advance(session,3,"The plants are safe. Restore the soil from roots upward.") end
        session.message="Plant treated. Inspect the next one."; return "progress"
    end
    local expected=((session.progress.step-1)%3)+1
    if index~=expected then return UI.miss(session,"Healthy beds need compost, then water, then mulch.") end
    session.progress.step=session.progress.step+1; if session.progress.step>session.rounds then return "complete" end
    session.message="Good. Continue the root-to-surface restoration."; return "progress"
end
function Garden.keypressed(session,key) if key=="escape" or key=="q" then return "cancelled" end local i=tonumber(key); if i and i>=1 and i<=3 then return Garden.choose(session,i) end end
function Garden.mousepressed(session,x,y) local i=UI.hit(UI.variantZones(Garden.zones,session),x,y); return i and Garden.choose(session,i) end
function Garden.draw(session,colors,image,clock)
    local cream,brass=UI.begin(colors,"RESCUE THE GARDEN",session,Garden.objective(session)); local pulse=1+math.sin((clock or 0)*5)*.08
    local ground=session.difficulty.palette.ground; love.graphics.setColor(ground); love.graphics.rectangle("fill",255,245,450,190,18,18)
    local zones=UI.variantZones(Garden.zones,session)
    for x=295,665,74 do love.graphics.setColor(.42,.26,.12); love.graphics.rectangle("fill",x,265,38,145,10,10) end
    if session.phase==1 then
        local active=target(session); for i,z in ipairs(zones) do love.graphics.setColor(i==active and brass or {.4,.68,.25,.8}); love.graphics.circle("line",z.x,z.y,i==active and 50*pulse or 39); love.graphics.setColor(cream); love.graphics.print(tostring(i),z.x-5,z.y+48) end
    elseif session.phase==2 then
        love.graphics.setColor(cream); love.graphics.printf("CURRENT:  "..current(session).name,270,220,420,"center",0,.78,.78)
        for i,z in ipairs(zones) do love.graphics.setColor(brass); love.graphics.circle("line",z.x,z.y,55); UI.sprite(image,i,z.x,z.y,92); love.graphics.setColor(cream); love.graphics.printf(i.."  "..toolNames[i],z.x-72,z.y+60,144,"center",0,.58,.58) end
    else
        for i,z in ipairs(zones) do love.graphics.setColor(brass); love.graphics.circle("line",z.x,z.y,55); UI.sprite(image,4,z.x,z.y,88); love.graphics.setColor(cream); love.graphics.printf(i.."  "..restoration[i],z.x-72,z.y+60,144,"center",0,.58,.58) end
    end
    UI.footer(session,cream,brass,"Protect healthy growth. Mistakes end the attempt for a safe retry.")
end
function Garden.audit()
    local function complete(location)
        local s=Garden.new({location=location,progress={}}); local ok=true
        for _=1,s.rounds do ok=ok and Garden.choose(s,target(s))=="progress" end
        for _=1,s.rounds do ok=ok and Garden.choose(s,current(s).tool)=="progress" end
        local done; for _=1,s.rounds do done=Garden.choose(s,((s.progress.step-1)%3)+1) end
        return s,ok and done=="complete"
    end
    local early,earlyOK=complete(2); local late,lateOK=complete(45); local restored=Garden.new({location=45,progress=late.progress})
    local bad=Garden.new({location=45,progress={}}); local failed; for _=1,bad.maximumMistakes do failed=Garden.choose(bad,target(bad)%3+1) end
    return {ready=earlyOK and lateOK and restored.phase==3 and restored.progress.step==late.rounds+1 and failed=="failed",stages=3,
        earlyDecisions=early.rounds*3,lateDecisions=late.rounds*3,lateMistakes=late.maximumMistakes,persistent=true,keyboard=true,touch=true,curve="garden-rescue-v2"}
end
return Garden
