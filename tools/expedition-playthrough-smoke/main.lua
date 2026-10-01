-- Deterministic end-to-end expedition smoke using the real application graph.
-- All progress stays in an unslotted journey under a dedicated LÖVE identity.
local repoRoot=assert(os.getenv("EXPEDITION_SMOKE_ROOT"),"EXPEDITION_SMOKE_ROOT is required"):gsub("\\","/")
local outputRoot=assert(os.getenv("EXPEDITION_SMOKE_OUTPUT"),"EXPEDITION_SMOKE_OUTPUT is required"):gsub("\\","/")
package.path=repoRoot.."/?.lua;"..repoRoot.."/?/init.lua;"..package.path

local app,ctx,game,ui,services,Areas
local report={}
local checks=0
local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1"
local prefix=mobile and "mobile" or "desktop"
local finished=false

local function record(text)
    report[#report+1]=text
    print(prefix..": "..text)
    io.stdout:flush()
end

local function check(value,message)
    if not value then error(message,2) end
    checks=checks+1
    record("CHECKPOINT "..message.." result=PASS")
end

local function distance(ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    return math.sqrt(dx*dx+dy*dy)
end

local function saveReport(status,message)
    local file=assert(io.open(outputRoot.."/"..prefix.."-report.txt","wb"))
    if message then report[#report+1]="ERROR "..tostring(message) end
    report[#report+1]="SUMMARY status="..status.." checks="..checks.." errors="..(status=="passed" and 0 or 1)
    file:write(table.concat(report,"\n").."\n")
    file:close()
end

local function update(dt)
    app.update(dt or 1/30)
end

local function setKeys(keys)
    local held={}
    for key,value in pairs(keys) do if value then held[key]=true end end
    return held
end

local function walkDirect(targetX,targetY,areaId)
    local oldIsDown=love.keyboard.isDown
    local previousDistance=distance(game.player.x,game.player.y,targetX,targetY)
    local stalled=0
    for _=1,900 do
        local dx,dy=targetX-game.player.x,targetY-game.player.y
        if math.sqrt(dx*dx+dy*dy)<=12 then break end
        local held=setKeys({
            a=dx < -1,d=dx > 1,w=dy < -1,s=dy > 1,
        })
        love.keyboard.isDown=function(...)
            for i=1,select("#",...) do if held[select(i,...)] then return true end end
            return false
        end
        update(1/30)
        love.keyboard.isDown=oldIsDown
        assert(game.state=="game" and game.scene=="expedition" and game.saveData.activeExpeditionArea==areaId,
            "movement left the active expedition")
        local remaining=distance(game.player.x,game.player.y,targetX,targetY)
        if remaining<previousDistance-.08 then stalled=0 else stalled=stalled+1 end
        previousDistance=remaining
        if stalled>24 then
            love.keyboard.isDown=oldIsDown
            return false
        end
    end
    love.keyboard.isDown=oldIsDown
    local reached=distance(game.player.x,game.player.y,targetX,targetY)<=12
    if reached then check(true,"walked to waypoint "..targetX..","..targetY) end
    return reached
end

local function keyboardRoute(areaId,targetX,targetY)
    local area=assert(Areas.definition(areaId),"missing route area")
    local startX,startY=game.player.x,game.player.y
    local step=8
    local start={cx=0,cy=0,x=startX,y=startY}
    local queue={start}
    local visited={['0:0']=true}
    local directions={{1,0},{0,1},{-1,0},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
    local targetDx,targetDy=targetX-startX,targetY-startY
    table.sort(directions,function(a,b)
        local ad=(targetDx*a[1]+targetDy*a[2])
        local bd=(targetDx*b[1]+targetDy*b[2])
        return ad>bd
    end)
    local head,goal=1,nil
    while head<=#queue do
        local current=queue[head]
        if distance(current.x,current.y,targetX,targetY)<=5.7
            and Areas.canReach(game.saveData,areaId,current.x,current.y,targetX,targetY) then
            goal=current; break
        end
        head=head+1
        for _,direction in ipairs(directions) do
            local cx,cy=current.cx+direction[1],current.cy+direction[2]
            local key=cx..":"..cy
            if not visited[key] then
                local x,y=startX+cx*step,startY+cy*step
                if x>=24 and y>=24 and x<=area.width-24 and y<=area.height-24
                    and Areas.canReach(game.saveData,areaId,current.x,current.y,x,y) then
                    visited[key]=true
                    queue[#queue+1]={cx=cx,cy=cy,x=x,y=y,previous=current}
                else
                    visited[key]=false
                end
            end
        end
        if #queue>30000 then return nil end
    end
    if not goal then return nil end
    local cells={}
    while goal and goal.previous do
        table.insert(cells,1,goal)
        goal=goal.previous
    end
    local waypoints={}
    local previous=start
    local previousDirection
    local runLength=0
    for index,cell in ipairs(cells) do
        local direction={cell.cx-previous.cx,cell.cy-previous.cy}
        if previousDirection and (direction[1]~=previousDirection[1] or direction[2]~=previousDirection[2]) then
            local turn=cells[index-1]
            if #waypoints==0 or waypoints[#waypoints]~=turn then waypoints[#waypoints+1]=turn end
            runLength=0
        end
        runLength=runLength+1
        if runLength>=5 and index<#cells then
            waypoints[#waypoints+1]=cell
            runLength=0
        end
        previousDirection=direction
        previous=cell
    end
    if #cells>0 and waypoints[#waypoints]~=cells[#cells] then waypoints[#waypoints+1]=cells[#cells] end
    return waypoints
end

local function walkAreaTo(areaId,targetX,targetY)
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==areaId,
        "route begins in "..areaId)
    for _=1,80 do
        if distance(game.player.x,game.player.y,targetX,targetY)<=18 then break end
        local nextX,nextY=Areas.pathTarget(game.saveData,areaId,game.player.x,game.player.y,targetX,targetY)
        check(nextX~=nil and nextY~=nil,"navigation found the next route waypoint")
        record(string.format("ROUTE %s from %.1f,%.1f via %.1f,%.1f toward %.1f,%.1f",
            areaId,game.player.x,game.player.y,nextX,nextY,targetX,targetY))
        check(Areas.canReach(game.saveData,areaId,game.player.x,game.player.y,nextX,nextY),
            "next route waypoint is reachable")
        local route=keyboardRoute(areaId,targetX,targetY)
        check(route~=nil,"eight-direction movement route reaches the target")
        local waypoint
        for _,candidate in ipairs(route) do
            if distance(game.player.x,game.player.y,candidate.x,candidate.y)>14 then
                waypoint=candidate; break
            end
        end
        check(waypoint~=nil,"keyboard route supplies a movement step")
        if not walkDirect(waypoint.x,waypoint.y,areaId) then
            record(string.format("ROUTE movement replans from %.1f,%.1f after a blocked step",
                game.player.x,game.player.y))
        end
    end
    check(distance(game.player.x,game.player.y,targetX,targetY)<=18,
        "route reaches destination "..targetX..","..targetY)
    update(1/30)
end

local function openMapAndClose()
    app.keypressed("m")
    check(game.mapOpen,"area map opens from the gameplay key")
    app.draw()
    check(ui.expeditionHudBounds==nil,"area map hides the gameplay HUD")
    local guidance=assert(ui.expeditionMapObjectiveBounds,"area map shows the current next step")
    local objective=services.worldScene.expeditionObjective()
    check(objective.text and objective.text~="" and guidance.y+guidance.h<=150,
        "area map guidance sits above the route artwork")
    check(ui.expeditionMapClose and ui.expeditionMapClose.w>0,"area map has a visible close control")
    check(ui.map==nil and ui.backpack==nil and ui.pose==nil and ui.options==nil,
        "area map has no overlapping toolbar buttons")
    local box=ui.expeditionMapClose
    local ox,oy,sx,sy=require("game.viewport").transform(960,720)
    local x,y=ox+(box.x+box.w/2)*sx,oy+(box.y+box.h/2)*sy
    if mobile then
        app.touchpressed("qa-map-close",x,y)
        app.touchreleased("qa-map-close",x,y)
    else
        app.mousepressed(x,y,1,false,1)
        app.mousereleased(x,y,1,false,1)
    end
    check(not game.mapOpen,"visible close control closes the area map")
end

local function checkCompactHud()
    app.draw()
    local box=assert(ui.expeditionHudBounds,"compact expedition HUD is drawn")
    check(box.w<=300 and box.h<=58 and box.x>=0 and box.y>=0,
        "expedition HUD fits in a compact corner card")
    local objective=services.worldScene.expeditionObjective()
    local area=Areas.current(game.saveData)
    local progressPattern=area and area.progressType=="survey" and "^CAIRNS %d+/%d+$" or "^CLEARED %d+/%d+$"
    check(objective.status and objective.status:match(progressPattern),
        "compact HUD labels the active expedition progress clearly")
    check(ui.mobileHeaderBounds==nil,"journey resource and progression panels are hidden")
    if ui.contextHint then
        check(ui.contextHint.y>=670,"nearby action prompt stays on the bottom edge")
    end
    if not mobile then
        local controls={ui.map,ui.options}
        for _,control in ipairs(controls) do check(control and control.y==18,"desktop expedition control shares the top row") end
        check(ui.backpack==nil and ui.pose==nil,"secondary desktop controls do not cover the playfield")
        for _,control in ipairs(controls) do check(control.x>=736,"desktop controls stay in the upper-right corner") end
        for i=1,#controls do
            local a=controls[i]
            for j=i+1,#controls do
                local b=controls[j]
                check(a.x+a.w<=b.x or b.x+b.w<=a.x,"desktop expedition controls do not overlap")
            end
        end
    end
end

local function interact(action)
    update(1/30)
    local selected=services.worldScene.currentExpeditionInteraction()
    check(selected and selected.kind=="expedition" and selected.action==action,
        "interaction selected: "..action)
    app.keypressed("q")
    update(1/30)
end

local function setSafeGrace()
    game.expeditionGraceTimer=10000
end

local function fightMob(mobId)
    local areaId=game.saveData.activeExpeditionArea
    local areaState=Areas.state(game.saveData,areaId)
    assert(Areas.mobDefinition(areaId,mobId),"missing mob "..mobId)
    local saved=assert(areaState.mobs[mobId],"missing saved mob "..mobId)
    if saved.dead then return end
    local approachX,approachY=Areas.clamp(game.saveData,areaId,saved.x-30,saved.y)
    walkAreaTo(areaId,approachX,approachY)
    check(distance(game.player.x,game.player.y,saved.x,saved.y)<=100,
        "melee range reached for "..mobId)
    local hits=0
    while not saved.dead and hits<20 do
        local before=saved.hp
        check(services.worldScene.attackExpeditionMob(saved.x,saved.y-35),"field attack starts against "..mobId)
        check(saved.hp<before or saved.dead,"field attack damages "..mobId)
        hits=hits+1
        setSafeGrace()
        update(.5)
    end
    check(saved.dead,"field combat defeats "..mobId)
    check(saved.rewardResolved==true,"field combat claims its once-only reward")
    setSafeGrace()
end

local function clearBattleAsWin()
    for _,unit in ipairs(game.battle.units) do if unit.team=="enemy" then unit.hp=0 end end
    services.battleRuntime.advanceTurn()
    check(game.battle.finished=="win","battle win uses the normal completion path")
end

local function clickControl(control)
    app.draw()
    local box=assert(ui[control],"missing control "..control)
    local ox,oy,sx,sy=require("game.viewport").transform(960,720)
    local x,y=ox+(box.x+box.w/2)*sx,oy+(box.y+box.h/2)*sy
    if mobile then
        app.touchpressed("qa-"..control,x,y)
        app.touchreleased("qa-"..control,x,y)
    else
        app.mousepressed(x,y,1,false,1)
        app.mousereleased(x,y,1,false,1)
    end
end

local function closeExpeditionStorage()
    app.draw()
    local close=assert(ui.backpack,"expedition storage exposes a visible close control")
    local inClearStrip=mobile and close.y==0 and close.h>=44 and close.x+close.w<=545
        or not mobile and close.y>=0 and close.y+close.h<=35
    check(inClearStrip,"storage close control stays in the clear strip above the inventory")
    check(ui.map==nil and ui.options==nil and ui.stopAttack==nil,
        "expedition toolbar is hidden behind storage panels")
    clickControl("backpack")
    check(not game.inventoryOpen and not game.chestOpen and game.activeChest==nil,
        "visible storage close control returns to expedition play")
end

local function enterTrailhead(stop,areaId,description)
    game.saveData.location=stop
    game.player.x,game.player.y=875,380
    update(1/30)
    local stopEntrance=services.worldScene.currentExpeditionInteraction()
    check(Areas.availableAtStop(stop) and stopEntrance and stopEntrance.action=="enterArea",
        "Stop "..stop.." wilderness trailhead is selectable")
    app.keypressed("q")
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==areaId,
        "trailhead enters "..description)
    game.dialogue=nil
    setSafeGrace()
end

local function clearBadlandsExpedition()
    local surface,basin=Areas.BADLANDS_SURFACE_ID,Areas.BADLANDS_BASIN_ID
    enterTrailhead(5,surface,"Red Mesa Approach")
    checkCompactHud()
    openMapAndClose()

    fightMob("surface-dust-beetle")
    fightMob("surface-cactus-rat")
    check(services.worldScene.expeditionObjective().status=="CLEARED 2/2",
        "regular Badlands mobs update surface cleared progress")
    walkAreaTo(surface,1264,397)
    interact("chest")
    check(game.chestOpen and Areas.state(game.saveData,surface).chests["surface-cache"].opened,
        "Badlands supply cache opens and persists")
    closeExpeditionStorage()

    walkAreaTo(surface,1460,150)
    interact("enterArea")
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==basin,
        "Red Mesa trail leads into the open Redwash Basin")
    setSafeGrace()
    checkCompactHud()
    openMapAndClose()

    local basinState=Areas.state(game.saveData,basin)
    check(Areas.definition(basin).kind=="wilderness" and #Areas.definition(basin).mobs==3,
        "Badlands basin uses a roaming wilderness roster without a dungeon guardian")

    -- Let the warning and flood play through. The wash crossing closes while
    -- the elevated ridge remains a valid route to the north cairn.
    local warningWait=0
    while basinState.environmentPhase~="warning" and warningWait<12 do
        update(.1); warningWait=warningWait+.1
    end
    check(basinState.environmentPhase=="warning","basin warns before the timed flash flood")
    for _=1,41 do update(.1) end
    check(basinState.environmentPhase=="flooded","flash flood reaches the low wash")
    check(not Areas.isWalkable(game.saveData,basin,832,526),
        "flash flood temporarily blocks the low wash crossing")
    local entryX,entryY=game.player.x,game.player.y
    game.player.x,game.player.y=832,500
    basinState.environmentPhase="warning"; basinState.environmentClock=13.9
    update(.2)
    check(basinState.environmentPhase=="flooded" and Areas.isWalkable(game.saveData,basin,game.player.x,game.player.y),
        "a player caught in the wash is moved safely to the nearest bank")
    game.player.x,game.player.y=entryX,entryY
    local ridgeX,ridgeY=Areas.pathTarget(game.saveData,basin,game.player.x,game.player.y,750,110)
    check(ridgeX~=nil and Areas.canReach(game.saveData,basin,game.player.x,game.player.y,ridgeX,ridgeY),
        "high ridge stays reachable while the wash is flooded")
    walkAreaTo(basin,750,110)
    interact("survey")
    check(basinState.markers["north-cairn"]==true,
        "north cairn can be marked from the safe ridge during a flood")

    local floodWait=0
    while basinState.environmentPhase=="flooded" and floodWait<10 do
        update(.1); floodWait=floodWait+.1
    end
    check(basinState.environmentPhase~="flooded","wash opens again as floodwater recedes")

    walkAreaTo(basin,360,180)
    interact("chest")
    check(game.chestOpen and basinState.chests["western-stash"].opened,
        "ridge supply stash opens and persists")
    closeExpeditionStorage()

    walkAreaTo(basin,450,720)
    interact("chest")
    check(game.chestOpen and basinState.chests["fossil-cache"].opened,
        "optional fossil cache opens and persists")
    closeExpeditionStorage()

    fightMob("basin-dust-beetle")
    fightMob("basin-cactus-rat")
    fightMob("basin-scorpion")
    check(services.worldScene.expeditionObjective().status=="CAIRNS 1/3",
        "regular Badlands encounters do not replace the distinct survey objective")

    local dryWait=0
    while (basinState.environmentPhase~="dry" or (basinState.environmentClock or 0)>=8) and dryWait<45 do
        update(.1); dryWait=dryWait+.1
    end
    check(basinState.environmentPhase=="dry" and basinState.environmentClock<8,
        "smoke waits for a safe low-wash crossing window")
    walkAreaTo(basin,900,500)
    interact("survey")
    check(basinState.markers["wash-cairn"]==true,"wash cairn records persistent survey progress")
    walkAreaTo(basin,1580,320)
    interact("survey")
    check(basinState.markers["arch-cairn"]==true and basinState.completed,
        "marking all three cairns completes the open-air route")
    check(services.worldScene.expeditionObjective().status=="CAIRNS 3/3",
        "basin HUD shows all survey markers completed")

    walkAreaTo(basin,1610,410)
    interact("enterArea")
    check(game.saveData.activeExpeditionArea==surface,"basin route returns to Red Mesa Approach")
    setSafeGrace()
    walkAreaTo(surface,836,700)
    interact("returnStop")
    check(game.scene=="stop" and game.saveData.activeExpeditionArea==nil,
        "Badlands surface exit returns to Stop 5 and clears the active area")
end

local function runPlaythrough()
    check(game.selectedSlot==nil,"smoke journey has no selected user save slot")
    check(love.filesystem.getIdentity()=="mouse-frontier-expedition-playthrough-qa",
        "smoke uses its dedicated QA save identity")
    local areaAudit=Areas.audit()
    check(areaAudit.ready and areaAudit.areaCount==4 and areaAudit.firstStop==5,
        "all four stop-matched expedition maps pass their content audit")
    check(Areas.availableAtStop(5) and Areas.availableAtStop(6) and not Areas.availableAtStop(4),
        "wilderness trailheads are registered only at their authored stops")

    clearBadlandsExpedition()

    -- Stop 6 keeps the existing Riverwood route as a harder follow-up.
    enterTrailhead(6,Areas.SURFACE_ID,"Riverwood Outskirts")
    setSafeGrace()
    checkCompactHud()
    openMapAndClose()

    fightMob("surface-bandit-a")
    check(services.worldScene.expeditionObjective().status=="CLEARED 1/2",
        "surface field victory updates the cleared count")
    walkAreaTo(Areas.SURFACE_ID,1520,467)
    interact("chest")
    check(game.chestOpen and game.inventoryOpen,"surface cache opens in the inventory view")
    check(Areas.state(game.saveData,Areas.SURFACE_ID).chests["surface-cache"].opened,
        "surface cache is saved as opened")
    closeExpeditionStorage()

    walkAreaTo(Areas.SURFACE_ID,1457,218)
    interact("enterArea")
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==Areas.DUNGEON_ID,
        "waystation entrance leads to Buried Waystation")
    setSafeGrace()
    checkCompactHud()
    openMapAndClose()

    walkAreaTo(Areas.DUNGEON_ID,460,160)
    interact("chest")
    check(game.chestOpen and Areas.state(game.saveData,Areas.DUNGEON_ID).chests["dungeon-cache"].opened,
        "waystation cache opens and persists")
    closeExpeditionStorage()

    walkAreaTo(Areas.DUNGEON_ID,690,251)
    fightMob("dungeon-bandit-a")
    check(not Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossGateOpen,
        "one surviving warden keeps the guardian gate sealed")
    walkAreaTo(Areas.DUNGEON_ID,821,681)
    fightMob("dungeon-bandit-b")
    check(Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossGateOpen,
        "both field victories open the guardian gate")
    check(services.worldScene.expeditionObjective().status=="CLEARED 2/3",
        "warden victories update dungeon cleared progress")

    walkAreaTo(Areas.DUNGEON_ID,1365,460)
    local boss=Areas.state(game.saveData,Areas.DUNGEON_ID).mobs["sludge-badger-boss"]
    local originalBossHp=boss.hp
    local bossApproachX,bossApproachY=Areas.clamp(game.saveData,Areas.DUNGEON_ID,boss.x-62,boss.y)
    walkAreaTo(Areas.DUNGEON_ID,bossApproachX,bossApproachY)
    local bossHits=0
    while boss.hp>1 and bossHits<20 do
        local before=boss.hp
        check(services.worldScene.attackExpeditionMob(boss.x,boss.y-60),"field attack starts against the guardian")
        check(boss.hp<before,"field attacks weaken the guardian")
        bossHits=bossHits+1
        setSafeGrace()
        update(.5)
    end
    check(originalBossHp>boss.hp and boss.hp==1,"guardian shell stops field damage at one HP")
    local bossEntryX,bossEntryY=game.player.x,game.player.y
    interact("challenge")
    check(game.state=="battle" and game.battle.encounter.source=="expedition",
        "guardian challenge opens the normal tactical battle")
    local battleBoss
    for _,unit in ipairs(game.battle.units) do if unit.boss then battleBoss=unit end end
    check(battleBoss and battleBoss.hp==boss.hp and battleBoss.maxHP==58,
        "field damage carries exactly into the tactical battle")
    for _=1,40 do update(.05) end
    check(not game.battle.intro,"battle intro completes through normal updates")
    clearBattleAsWin()
    clickControl("battleContinue")
    check(game.state=="game" and game.scene=="expedition" and game.saveData.activeExpeditionArea==Areas.DUNGEON_ID,
        "victory returns to the dungeon")
    check(game.player.x==bossEntryX and game.player.y==bossEntryY,
        "victory returns to the exact boss challenge position")
    check(Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossDefeated,
        "battle victory opens the corruption vault")
    check(services.worldScene.expeditionObjective().status=="CLEARED 3/3",
        "guardian victory completes dungeon cleared progress")

    walkAreaTo(Areas.DUNGEON_ID,1480,150)
    interact("chest")
    check(Areas.state(game.saveData,Areas.DUNGEON_ID).chests["boss-vault"].opened,
        "guardian victory opens the vault reward")
    closeExpeditionStorage()
    walkAreaTo(Areas.DUNGEON_ID,110,405)
    interact("enterArea")
    check(game.saveData.activeExpeditionArea==Areas.SURFACE_ID,"dungeon exit returns to the surface")
    setSafeGrace()
    walkAreaTo(Areas.SURFACE_ID,836,856)
    interact("returnStop")
    check(game.scene=="stop" and game.saveData.activeExpeditionArea==nil,
        "surface exit returns to Stop 6 and clears the active area")

    -- Exercise the loss result as a separate outcome in this isolated session.
    game.player.x,game.player.y=875,380
    update(1/30)
    app.keypressed("q")
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==Areas.SURFACE_ID,
        "trailhead can be entered again for the defeat route")
    game.dialogue=nil
    local returnX,returnY=game.player.x,game.player.y
    local mob=Areas.state(game.saveData,Areas.SURFACE_ID).mobs["surface-bandit-b"]
    services.battleRuntime.beginEncounter({source="expedition",areaId=Areas.SURFACE_ID,tier="easy",
        mobFiles={"sludge-bandit.png"},enemyStates={{mobId="surface-bandit-b",file="sludge-bandit.png",
            name="Sludge-Taken Bandit",hp=mob.hp,maxHp=mob.maxHp,weapon="mob-claw"}},
        returnContext={scene="expedition",areaId=Areas.SURFACE_ID,x=returnX,y=returnY}})
    for _=1,40 do update(.05) end
    for _,unit in ipairs(game.battle.units) do if unit.team=="ally" then unit.hp=0 end end
    services.battleRuntime.advanceTurn()
    check(game.battle.finished=="loss","battle loss uses the normal completion path")
    clickControl("battleContinue")
    check(game.scene=="train" and game.saveData.activeExpeditionArea==nil,
        "defeat returns safely to the train")
    local safeX,safeY=services.trainCarRuntime.clampToFloor(game.player.x,game.player.y)
    check(safeX==game.player.x and safeY==game.player.y,"defeat arrival is on the train floor")
end

function love.load()
    local ok,message=xpcall(function()
        love.filesystem.setSymlinksEnabled(true)
        if not love.filesystem.getInfo("assets") then love.filesystem.mount(repoRoot,"",true) end
        assert(love.filesystem.getInfo("assets"),"project assets are unavailable")
        love.math.setRandomSeed(6102026)
        local Modules=require("game.systems")
        local original=Modules.smokeComposition.new
        Modules.smokeComposition.new=function(context) ctx=context; return original(context) end
        app=require("game.application_composition").new({engine=love})
        Modules.smokeComposition.new=original
        app.load()
        game,ui,services=ctx.state.runtime,ctx.state.ui,ctx.services
        Areas=require("game.expedition_areas")
        local data=services.sessionBootstrap.newSave("mail-mouse.png")
        data.location=5; data.scene="stop"; data.playerX,data.playerY=875,380
        data.audio.musicVolume=0; data.audio.sfxVolume=0; data.audio.rainVolume=0
        check(services.sessionBootstrap.enterGame(data),"fresh isolated journey loads")
        check(game.selectedSlot==nil,"QA journey is unslotted")
        check(love.filesystem.getIdentity()=="mouse-frontier-expedition-playthrough-qa",
            "QA identity isolates all save data")
    end,debug.traceback)
    if not ok then finished=true; saveReport("failed",message); love.event.quit(1) end
end

function love.update()
    if finished then return end
    finished=true
    local ok,message=xpcall(runPlaythrough,debug.traceback)
    saveReport(ok and "passed" or "failed",ok and nil or message)
    if ok then
        print(prefix..": SUMMARY status=passed checks="..checks.." errors=0")
        io.stdout:flush()
        if app then app.quit() end
        love.event.quit(0)
    else
        io.stderr:write(prefix..": EXPEDITION_SMOKE_ERROR "..tostring(message).."\n")
        io.stderr:flush()
        love.event.quit(1)
    end
end

function love.draw()
    if app and not finished then app.draw() end
end

function love.errorhandler(message)
    pcall(saveReport,"failed",tostring(message).."\n"..debug.traceback())
    io.stderr:write("EXPEDITION_SMOKE_ERROR "..tostring(message).."\n")
    io.stderr:flush()
    return function() return 1 end
end
