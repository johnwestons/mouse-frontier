-- Full application validation. The runner gives this harness an isolated
-- APPDATA directory, so slot 99 never refers to a player's real campaign.
local checks,captures,reloads=0,0,0
local app,context,routine,pendingShot,finished
local held,pointerX,pointerY={},780,360
local idleFrames=0
local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1"
local function expect(value,message)
    assert(value,message)
    checks=checks+1
end
function love.errorhandler(message)
    print(debug.traceback(tostring(message),2))
    return function() return 1 end
end

local function run()
    love.math.setRandomSeed(10162026)
    love.keyboard.isDown=function(...)
        for index=1,select("#",...) do if held[select(index,...)] then return true end end
        return false
    end
    love.mouse.getPosition=function() return pointerX,pointerY end
    local smokeChunk,smokeError=love.filesystem.load("game/smoke_playthrough.lua")
    expect(smokeChunk~=nil,"normal app smoke module does not compile: "..tostring(smokeError))
    package.loaded["game.smoke_playthrough"]={install=function(value) context=value end}
    app=require("game.application_composition").new({engine=love})
    app.installSmoke(); app.load()
    local c=context
    local g,ui,p=c.runtime,c.ui,c.presentationRuntime
    local Home=require("game.home_stop")
    local dialogue=require("game.home_stop_dialogue")
    local Save=require("game.save")
    local controls=c.getMobileControls()
    local data
    local function step(seconds)
        for _=1,math.ceil(seconds/.025) do app.update(.025) end
    end
    local function screen(x,y)
        local ox,oy,sx,sy=require("game.viewport").transform(960,720)
        return ox+x*sx,oy+y*sy
    end
    local function pointOnScreen(x,y)
        x,y=require("game.world_view").toScreen(x,y)
        return screen(x,y)
    end
    local function tap(x,y,id)
        pointerX,pointerY=x,y
        if mobile then
            app.touchpressed(id or "smoke-tap",x,y)
            app.touchreleased(id or "smoke-tap",x,y)
        else
            app.mousepressed(x,y,1)
            app.mousereleased(x,y,1)
        end
        step(.05)
    end
    local function button(rect,id)
        expect(rect~=nil,"missing control: "..tostring(id))
        local x,y=screen(rect.x+rect.w/2,rect.y+rect.h/2)
        tap(x,y,id)
    end
    local function draw()
        love.graphics.origin()
        app.draw()
    end
    local function capture(name)
        pendingShot=name..".png"
        coroutine.yield()
        expect(not pendingShot,"capture did not draw: "..name)
    end
    local function checkObjectiveSidebar()
        local panel,layout=ui.homeStopObjective,ui.sideHudLayout
        expect(panel and layout,"home instructions have no sidebar")
        expect(panel.textFits,"home instructions overflow their text boxes")
        expect(panel.x>=960 and panel.x+panel.w<=layout.right-9,"home instructions overlap the scene or leave the window")
        expect(panel.y>=100 and panel.y+panel.h<600,"home instructions overlap the sidebar controls")
        local action=ui.homeStopActionBounds
        expect(action and action.x>=960 and action.x+action.w<=layout.right-9,"action label is not in the right sidebar")
        expect(action.textFits and action.y>=panel.y+panel.h+10 and action.y+action.h<(mobile and 640 or 704),"action label clips or overlaps instructions")
        if mobile then
            local pack=controls.backpack
            expect(action.x+action.w<=pack.x or pack.x+pack.w<=action.x or action.y+action.h<=pack.y or pack.y+pack.h<=action.y,"action label overlaps touch backpack")
        end
        if ui.contextHint then
            local hint=ui.contextHint
            expect(hint.x+hint.w<=panel.x or hint.x>=panel.x+panel.w or hint.y+hint.h<=panel.y or hint.y>=panel.y+panel.h,"home instructions cover the action hint")
        end
    end
    local function checkObjectiveDuringActions()
        local style=require("game.ui_layout").manager()
        local previousLayout=style:menuLayout()
        style:setMenuLayout("drawer",false)
        ui.actionMenusEnabled=true
        ui.mobileMenuOpen=false
        step(.025);draw()
        ui.mobileMenuOpen=true
        step(.05);draw()
        local menu=ui.actionMenu
        expect(menu and menu.page=="main","Actions drawer did not open over the home yard")
        expect(ui.homeStopObjective and ui.homeStopActionBounds,"Actions drawer hid the home instructions or action card")
        checkObjectiveSidebar()
        for _,target in ipairs(menu.targets) do
            for _,card in ipairs({ui.homeStopObjective,ui.homeStopActionBounds}) do
                local r=target.rect
                local overlap=r.x<card.x+card.w and r.x+r.w>card.x and r.y<card.y+card.h and r.y+r.h>card.y
                expect(not overlap,"menu control overlaps home HUD: "..target.id)
            end
        end
        capture("actions-objective-overlay")
        ui.mobileMenuOpen=false
        step(.05);draw()
        style:setMenuLayout(previousLayout,false)
        step(.025);draw()
    end
    local function reload(stage,line)
        held={}
        if controls then controls:cancelAll() end
        expect(c.persistenceRuntime.checkpoint(),"checkpoint failed at "..stage)
        local saved=Save.read(99)
        expect(saved and saved.homeStop.stage==stage,"saved stage differs at "..stage)
        if line then expect(saved.homeStop.dialogueLine==line,"saved conductor line differs") end
        expect(c.enterGame(saved),"could not reload "..stage)
        reloads=reloads+1
        data=g.saveData
        step(.05)
        expect(data.homeStop.stage==stage,"reloaded stage differs at "..stage)
        if line then
            expect(g.dialogue and g.dialogue.homeStop and g.dialogue.text==dialogue[line],"reload skipped or repeated conductor wording")
        end
    end
    local function walk(point)
        expect(not g.dialogue,"cannot walk while conversation is open")
        local oldX,oldY=g.player.x,g.player.y
        local touchId="smoke-walk"
        local stick,stickX,stickY
        if mobile then
            controls:_updateCornerLayout()
            stick=controls.joystick
            stickX,stickY=screen(stick.x,stick.y)
            app.touchpressed(touchId,stickX,stickY)
        end
        local arrived=false
        for _=1,600 do
            local dx,dy=point.x-g.player.x,point.y-g.player.y
            local distance=math.sqrt(dx*dx+dy*dy)
            if distance<(point.arrivalDistance or math.min(48,(point.radius or 75)*.60)) then arrived=true; break end
            if mobile then
                local radius=stick.radius*.82
                local x,y=screen(stick.x+dx/distance*radius,stick.y+dy/distance*radius)
                app.touchmoved(touchId,x,y,x-stickX,y-stickY)
                stickX,stickY=x,y
            else
                held={a=dx< -8,d=dx>8,w=dy< -8,s=dy>8}
            end
            app.update(.025)
        end
        held={}
        if mobile then app.touchreleased(touchId,stickX,stickY) end
        step(.10)
        expect(arrived,string.format("movement failed to reach %.0f,%.0f; stopped at %.1f,%.1f",point.x,point.y,g.player.x,g.player.y))
        expect((g.player.x-oldX)^2+(g.player.y-oldY)^2>1,"movement did not move player")
        if not point.freeMove then expect(ui.interaction and ui.interaction.kind==(point.kind or "homeStop"),"home target has no contextual interaction") end
    end
    local function interact(usePointer)
        draw()
        if usePointer then
            local target=assert(ui.interaction,"no target to click")
            pointerX,pointerY=pointOnScreen(target.x,target.y)
            step(.05)
            tap(pointerX,pointerY,"home-action")
        elseif mobile then
            controls:_updateCornerLayout()
            local x,y=screen(controls.primary.x,controls.primary.y)
            tap(x,y,"home-primary")
        else
            app.keypressed("e"); app.keyreleased("e"); step(.05)
        end
        data=g.saveData
    end
    local function continueDialogue(usePointer)
        draw()
        if usePointer then button(ui.dialogueContinue,"dialogue-continue")
        elseif mobile then
            local x,y=screen(controls.primary.x,controls.primary.y)
            tap(x,y,"dialogue-primary")
        else app.keypressed("e"); app.keyreleased("e"); step(.05) end
        data=g.saveData
    end
    local function gate(stage)
        local before=g.player.x
        local reply=ui.transitionParty("scene.returnTrain",{})
        expect(not reply.ok and reply.reason=="home_preparation_incomplete","boarding bypassed "..stage..": "..tostring(reply.reason))
        expect(g.scene=="stop" and data.homeStop.stage==stage and g.player.x==before,"rejected boarding mutated campaign")
    end

    g.selectedSlot=99; Save.remove(99)
    expect(c.enterGame(c.newSave(c.characters[1])),"new campaign failed to enter")
    data=g.saveData
    p.resetCamera(true); step(.10)
    expect(g.state=="game" and g.scene=="stop" and data.scene=="stop" and data.location==1 and data.stopped,"new campaign did not open in stopped outdoor home yard")
    expect(Home.isHome(data) and data.homeStop.stage=="briefing","new campaign has no prologue")
    expect(data.currentNPC==Home.CONDUCTOR and g.npcActor==nil,"conductor should be inside the office")
    expect(not g.dialogue,"opening should let the player approach the conductor")
    expect(not ui.travel and not ui.leaveTrain,"train controls leaked into the opening")
    capture("01-opening")
    checkObjectiveSidebar()
    checkObjectiveDuringActions()
    gate("briefing")
    local Fox=require("game.home_stop_fox")
    local actor=Fox.actor(data)
    walk({x=actor.x,y=actor.y,radius=95,kind="homeFox"})
    expect(ui.interaction.kind=="homeFox","adult fox has no Talk action")
    capture("fox-talk-prompt")
    expect(ui.contextHint and ui.contextHint.text:find("TALK",1,true),"fox Talk hint is missing")
    interact(true)
    expect(g.dialogue and g.dialogue.homeFox and g.dialogue.speaker==require('game.npc_identity').title(data,Home.FOX),"named fox Talk did not open")
    local approved=false
    for _,line in ipairs(require("game.catalog").dialogueLines) do if g.dialogue.text==line then approved=true end end
    expect(approved,"fox used unapproved dialogue")
    expect(data.homeStop.stage=="briefing" and not data.homeStop.dialogueLine,"fox Talk advanced the conductor story")
    local fx,fy,work,route,workTime=actor.x,actor.y,actor.work,actor.routeIndex,actor.workTime
    step(.5)
    expect(actor.x==fx and actor.y==fy and actor.workTime==workTime,"talking fox moved or advanced its work")
    capture("fox-talk")
    continueDialogue(true)
    expect(not g.dialogue,"fox conversation did not close")
    step(.2)
    expect(actor.routeIndex==route and actor.work==work and actor.workTime>workTime,"fox failed to resume the interrupted work")
    local workShots={[1]="fox-supplies",[5]="fox-workbench",[9]="fox-near-engine",[15]="fox-far-engine"}
    local seen={}; local rounds=Fox.actor(data).rounds or 0
    for _=1,7000 do
        app.update(.025)
        local actor=Fox.actor(g.saveData)
        if actor.work and actor.workTime>.5 and workShots[actor.routeIndex] and not seen[actor.routeIndex] then
            seen[actor.routeIndex]=true; capture(workShots[actor.routeIndex])
        end
        if (actor.rounds or 0)>rounds then break end
    end
    expect(seen[1] and seen[5] and seen[9] and seen[15],"fox did not work at all four marked waypoints")
    expect(Fox.actor(g.saveData).rounds>rounds,"fox route failed to complete")
    walk(Home.points.officeDoor); interact(false)
    expect(Home.isOffice(g.saveData) and g.npcActor~=nil,"office entry failed or conductor is absent")
    capture("02-office")
    checkObjectiveSidebar()
    expect(g.player.x==Home.officeSpawn.x and g.player.y==Home.officeSpawn.y,"office entry missed the resized floor")
    capture("office-walkmask")
    for index,point in ipairs({{430,450},{430,295},{240,320},{220,420},{270,560},
        {480,600},{755,535},{780,390},{620,410},{480,600}}) do
        local x,y=Home.officeStandingPoint(point[1],point[2])
        walk({x=x,y=y,freeMove=true,arrivalDistance=12})
        expect(Home.officeWalkable(g.player.x,g.player.y),"player left the authored office floor")
        if index==2 then
            capture("office-upper-floor")
            checkObjectiveSidebar()
            local px,py=g.player.x,g.player.y
            reload("briefing")
            expect(math.abs(g.player.x-px)<.001 and math.abs(g.player.y-py)<.001,"reload moved player from upper office floor")
        end
    end
    walk(Home.points.conductor)
    interact(false)
    for line=1,5 do
        expect(g.dialogue and g.dialogue.homeStop and g.dialogue.text==dialogue[line],"approved briefing line "..line.." missing or changed")
        expect(data.homeStop.dialogueLine==line,"line "..line.." has no persistent receipt")
        if line==2 then reload("briefing",2); capture("02-briefing") end
        continueDialogue(line%2==0)
    end
    expect(not g.dialogue and data.homeStop.stage=="supplies","briefing did not advance to supply collection")
    walk(Home.points.officeExit); interact(false)
    expect(not Home.isOffice(g.saveData) and g.npcActor==nil,"office exit failed")
    draw(); checkObjectiveSidebar()
    reload("supplies")
    gate("supplies")
    walk(Home.points.supplies)
    local resourceBefore={}
    for _,name in ipairs({"food","water","coal","oil"}) do resourceBefore[name]=data.resources[name] end
    interact(true)
    expect(data.homeStop.stage=="repair" and data.homeStop.suppliesCollected,"supply interaction did not advance")
    for name,value in pairs(resourceBefore) do expect(data.resources[name]==value+10,"supply bundle differs for "..name) end
    if g.dialogue then continueDialogue(true) end
    reload("repair")
    for name,value in pairs(resourceBefore) do expect(data.resources[name]==value+10,"reload duplicated supplies for "..name) end
    expect(not ui.homeStopAction("supplies"),"stale supply action was accepted")
    for name,value in pairs(resourceBefore) do expect(data.resources[name]==value+10,"stale input duplicated supplies for "..name) end
    capture("03-supplies")
    checkObjectiveSidebar()
    gate("repair")
    walk(Home.points.repair)
    expect(data.maintenance.condition<100,"locomotive started fully repaired")
    interact(false)
    expect(data.homeStop.stage=="farewell" and data.homeStop.repairComplete and data.maintenance.condition==100,"preparation did not repair locomotive")
    if g.dialogue then continueDialogue(true) end
    reload("farewell")
    expect(data.maintenance.condition==100,"reload lost locomotive repairs")
    expect(not ui.homeStopAction("repair") and data.homeStop.stage=="farewell","stale repair input repeated preparation")
    capture("04-repaired")
    checkObjectiveSidebar()
    gate("farewell")
    walk(Home.points.officeDoor); interact(true)
    expect(Home.isOffice(g.saveData),"return to conductor office failed")
    walk(Home.points.conductor)
    interact(true)
    expect(g.dialogue and g.dialogue.text==dialogue[6],"approved farewell line missing or changed")
    reload("farewell",6)
    capture("05-farewell")
    continueDialogue(true)
    expect(not g.dialogue and data.homeStop.stage=="ready","farewell did not unlock train")
    reload("ready")
    expect(not g.dialogue,"completed farewell repeated on reload")
    walk(Home.points.officeExit); interact(false)
    draw(); checkObjectiveSidebar()
    walk(Home.points.train)
    interact(false)
    expect(g.scene=="train" and data.scene=="train" and data.homeStop.stage=="ready","boarding failed")
    capture("06-train")
    draw()
    local travel=ui.travel
    if ui.actionMenusEnabled and ui.actionMenu then
        for _,target in ipairs(ui.actionMenu.targets) do
            if target.id=="travel" then travel=target.rect; break end
        end
    elseif mobile and not travel then
        ui.mobileMenuOpen=true; draw(); travel=ui.travel
    end
    button(travel,"travel")
    expect(g.travelConfirm,"journey confirmation did not open")
    draw(); button(ui.travelYes,"confirm-journey")
    expect(g.travelTransition and data.homeStop.stage=="departed","first departure did not finish home state")
    for _=1,800 do
        app.update(.025)
        if not g.travelTransition then break end
    end
    data=g.saveData
    expect(data.location==2 and not g.travelTransition,"first journey did not arrive at stop 2")
    expect(not Home.isHome(data) and data.homeStop.stage=="departed","home prologue remained active after departure")
    expect(not g.dialogue or not g.dialogue.homeStop,"conductor conversation repeated after departure")
    reload("departed")
    expect(data.location==2 and not Home.isHome(data),"reload returned the player to the intro")
    capture("07-arrival")
    expect(#dialogue==6,"unexpected conductor dialogue lines")
    local legacy=assert(c.saveSchema.copy(data)); legacy.homeStop=nil
    expect(not Home.isHome(legacy) and Home.canDepart(legacy),"existing campaigns were forced through the intro")
    print("HOME_STOP_SMOKE_OK mode="..(mobile and "mobile" or "desktop").." checks="..checks.." screenshots="..captures.." approvedLines=6 reloads="..reloads.." arrival=2")
end

function love.load()
    routine=coroutine.create(run)
end
function love.update()
    if finished then
        idleFrames=idleFrames+1
        if idleFrames>=2 then love.event.quit(finished=="ok" and 0 or 1) end
        return
    end
    local ok,err=coroutine.resume(routine)
    if not ok then
        print(debug.traceback(routine,tostring(err)))
        finished="error"
    elseif coroutine.status(routine)=="dead" then finished="ok" end
end
function love.draw()
    if app then app.draw() end
    if pendingShot then
        if pendingShot=="office-walkmask.png" then
            local Home=require("game.home_stop")
            local WorldView=require("game.world_view")
            local ox,oy,sx,sy=require("game.viewport").transform(960,720)
            local vertices={}
            for _,point in ipairs(Home.officeFloor) do
                local x,y=Home.officePoint(point[1],point[2]); x,y=WorldView.toScreen(x,y)
                vertices[#vertices+1]=ox+x*sx; vertices[#vertices+1]=oy+y*sy
            end
            love.graphics.push("all"); love.graphics.origin()
            love.graphics.setColor(.15,1,.4,.27)
            for _,triangle in ipairs(love.math.triangulate(vertices)) do love.graphics.polygon("fill",triangle) end
            love.graphics.setColor(.2,1,.45,.85); love.graphics.setLineWidth(2)
            love.graphics.polygon("line",vertices)
            love.graphics.pop()
        end
        love.graphics.captureScreenshot(pendingShot)
        captures=captures+1
        pendingShot=nil
    end
end
