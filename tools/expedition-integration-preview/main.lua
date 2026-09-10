-- Isolated full-application preview. It creates an unslotted in-memory journey;
-- the normal save identity and user slots are never used.
local repoRoot=assert(os.getenv("EXPEDITION_PREVIEW_ROOT"),"EXPEDITION_PREVIEW_ROOT is required"):gsub("\\","/")
local outputRoot=assert(os.getenv("EXPEDITION_PREVIEW_OUTPUT"),"EXPEDITION_PREVIEW_OUTPUT is required"):gsub("\\","/")
package.path=repoRoot.."/?.lua;"..repoRoot.."/?/init.lua;"..package.path

local app,ctx,game,ui,services,Areas
local stages,index,prepared,captureQueued,captureComplete={},1,false,false,false
local report={}
local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1"
local prefix=mobile and "mobile" or "desktop"
local battleEntry
local failed=false

local function record(text)
    report[#report+1]=text
    print(prefix..": "..text)
    io.stdout:flush()
end

local function check(value,message)
    assert(value,message)
    record("PASS "..message)
end

local function saveReport()
    local file=assert(io.open(outputRoot.."/"..prefix.."-report.txt","wb"))
    file:write(table.concat(report,"\n").."\n"); file:close()
end

local function fail(message)
    if failed then return end
    failed=true
    report[#report+1]="FAIL "..tostring(message)
    pcall(saveReport)
    io.stderr:write("EXPEDITION_PREVIEW_ERROR "..tostring(message).."\n"); io.stderr:flush()
    love.event.quit(1)
end

local function clearOverlays()
    game.dialogue=nil; game.inventoryOpen=false; game.chestOpen=false; game.activeChest=nil
    game.mapOpen=false; game.poseMenu=false; game.exitPrompt=nil; game.tradeOpen=false
    game.firstAid=nil; game.shootingRange=nil; game.helpDialogue=nil; game.lastStand=nil
    ui.optionsOpen=false; ui.mobileMenuOpen=false; ui.radioOpen=false
    game.player.moving=false; game.player.velocityX,game.player.velocityY=0,0
    services.presentationRuntime.resetCamera(true)
end

local function position(x,y)
    if game.scene=="expedition" then x,y=Areas.clamp(game.saveData,game.saveData.activeExpeditionArea,x,y) end
    game.player.x,game.player.y=x,y
    game.player.moving=false; game.player.velocityX,game.player.velocityY=0,0
    game.expeditionGraceTimer=100
    app.update(.016)
    ui.interaction=services.worldScene.currentExpeditionInteraction()
end

local function enter(areaId,spawn)
    clearOverlays()
    check(services.worldScene.activateExpeditionInteraction({kind="expedition",action="enterArea",targetArea=areaId,spawn=spawn}),"enter "..areaId)
    game.dialogue=nil
    check(game.scene=="expedition" and game.saveData.activeExpeditionArea==areaId,"scene and area agree")
    game.expeditionGraceTimer=100
    app.update(.016)
end

local function drawAndClick(control)
    app.draw()
    local box=assert(ui[control],"missing control "..control)
    local viewport=require("game.viewport")
    local ox,oy,sx,sy=viewport.transform(960,720)
    local x,y=ox+(box.x+box.w/2)*sx,oy+(box.y+box.h/2)*sy
    if mobile then app.touchpressed("qa-"..control,x,y); app.touchreleased("qa-"..control,x,y)
    else app.mousepressed(x,y,1,false,1); app.mousereleased(x,y,1,false,1) end
end

local function installStages()
    stages={
        {name="01-stop-trailhead",setup=function()
            clearOverlays(); game.scene="stop"; game.saveData.activeExpeditionArea=nil
            position(790,420)
        end},
        {name="02-surface-exploration",setup=function()
            enter(Areas.SURFACE_ID,"town")
            position(870,551)
        end},
        {name="03-surface-area-map",setup=function()
            app.keypressed("m")
            check(game.mapOpen,"M opens local area map")
        end},
        {name="04-settings-pause",setup=function()
            drawAndClick("expeditionMapClose")
            check(not game.mapOpen,"visible local map close control works")
            position(740,535)
            local state=Areas.state(game.saveData,Areas.SURFACE_ID)
            local mob=state.mobs["surface-bandit-a"]
            local px,py,mx,my=game.player.x,game.player.y,mob.x,mob.y
            ui.optionsOpen=true; game.optionsPage="accessibility"; game.expeditionGraceTimer=0
            for _=1,30 do app.update(.05) end
            check(game.state=="game" and game.player.x==px and game.player.y==py and mob.x==mx and mob.y==my,"settings pause player and pursuing mobs")
        end},
        {name="05-surface-cache",setup=function()
            clearOverlays(); position(1520,467)
            local selected=services.worldScene.currentExpeditionInteraction()
            check(selected and selected.action=="chest","surface cache is reachable and selected")
            check(services.worldScene.activateExpeditionInteraction(selected),"cache opens through real interaction")
            check(game.inventoryOpen and game.chestOpen,"cache inventory is visible")
        end},
        {name="06-dungeon-exploration",setup=function()
            enter(Areas.DUNGEON_ID,"surface")
            position(551,410)
        end},
        {name="07-dungeon-area-map",setup=function()
            app.keypressed("m")
            check(game.mapOpen,"dungeon map opens")
        end},
        {name="08-dungeon-closed-gate",setup=function()
            clearOverlays(); position(966,490)
            check(not Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossGateOpen,"guardian gate begins closed")
        end},
        {name="09-boss-arena",setup=function()
            local state=Areas.state(game.saveData,Areas.DUNGEON_ID)
            for _,id in ipairs({"dungeon-bandit-a","dungeon-bandit-b"}) do state.mobs[id].dead=true; state.mobs[id].hp=0 end
            check(Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossGateOpen,"defeating both wardens opens gate")
            position(1320,475)
            state.mobs["sludge-badger-boss"].hp=37
            local selected=services.worldScene.currentExpeditionInteraction()
            check(selected and selected.action=="challenge","boss exposes deliberate challenge interaction")
        end},
        {name="10-boss-battle",setup=function()
            local selected=services.worldScene.currentExpeditionInteraction()
            battleEntry={areaId=game.saveData.activeExpeditionArea,x=game.player.x,y=game.player.y}
            check(services.worldScene.activateExpeditionInteraction(selected),"boss challenge starts tactical encounter")
            check(game.state=="battle" and game.battle.encounter.source=="expedition","normal battle runtime entered")
            local boss
            for _,unit in ipairs(game.battle.units) do if unit.boss then boss=unit end end
            check(boss and boss.hp==37 and boss.maxHP==58,"field damage carries to boss battle exactly")
            for _=1,40 do app.update(.05) end
            check(not game.battle.intro,"battle intro finishes through normal updates")
        end},
        {name="11-battle-victory",setup=function()
            for _,unit in ipairs(game.battle.units) do if unit.team=="enemy" then unit.hp=0 end end
            services.battleRuntime.advanceTurn()
            check(game.battle.finished=="win","real battle completion resolves victory")
        end},
        {name="12-victory-return",setup=function()
            drawAndClick("battleContinue")
            check(game.state=="game" and game.scene=="expedition" and game.saveData.activeExpeditionArea==battleEntry.areaId,"victory returns to correct area")
            check(game.player.x==battleEntry.x and game.player.y==battleEntry.y,"victory restores exact battle entry point")
            check(Areas.updateGates(game.saveData,Areas.DUNGEON_ID).bossDefeated,"boss death opens corruption vault")
        end},
        {name="13-vault-reward",setup=function()
            position(1480,150)
            local selected=services.worldScene.currentExpeditionInteraction()
            check(selected and selected.chestId=="boss-vault","victory vault can be reached")
            check(services.worldScene.activateExpeditionInteraction(selected),"victory vault opens")
        end},
        {name="14-defeat-return-train",setup=function()
            enter(Areas.SURFACE_ID,"town")
            local mob=Areas.state(game.saveData,Areas.SURFACE_ID).mobs["surface-bandit-a"]
            services.battleRuntime.beginEncounter({source="expedition",areaId=Areas.SURFACE_ID,tier="easy",mobFiles={"sludge-bandit.png"},
                enemyStates={{mobId="surface-bandit-a",file="sludge-bandit.png",name="Sludge-Taken Bandit",hp=mob.hp,maxHp=mob.maxHp,weapon="mob-claw"}},
                returnContext={scene="expedition",areaId=Areas.SURFACE_ID,x=game.player.x,y=game.player.y}})
            for _=1,40 do app.update(.05) end
            for _,unit in ipairs(game.battle.units) do if unit.team=="ally" then unit.hp=0 end end
            services.battleRuntime.advanceTurn()
            check(game.battle.finished=="loss","real battle completion resolves defeat")
            drawAndClick("battleContinue")
            check(game.state=="game" and game.scene=="train" and game.saveData.activeExpeditionArea==nil,"defeat returns to train and clears area")
            local x,y=services.trainCarRuntime.clampToFloor(game.player.x,game.player.y)
            check(x==game.player.x and y==game.player.y,"defeat places player on valid train floor")
            check(game.player.x<=904,"returning player is fully inside the viewport")
            local left,right,top,bottom=services.trainCarRuntime.floorBounds()
            local safeX,safeY=services.trainCarRuntime.clampToFloor(math.min((left+right)/2,904),(top+bottom)/2)
            check(game.player.x==safeX and game.player.y==safeY,"defeat uses clear central-floor safe arrival")
            check(game.player.velocityX==0 and game.player.velocityY==0 and not game.player.moving,"defeat clears movement momentum")
            if mobile then
                app.draw()
                local primary=services.mobileRuntime.get().primary
                local ox,oy,sx,sy=require("game.viewport").transform(960,720)
                local controlX,controlY=services.presentationRuntime.screenToWorld(ox+primary.x*sx,oy+primary.y*sy)
                local edgeX=services.presentationRuntime.screenToWorld(ox+(primary.x+primary.radius)*sx,oy+primary.y*sy)
                local dx,dy=game.player.x-controlX,game.player.y-controlY
                check(math.sqrt(dx*dx+dy*dy)>math.abs(edgeX-controlX)+34,"safe arrival keeps player clear of touch USE control")
            end
        end},
    }
end

function love.load()
    local ok,message=xpcall(function()
        love.filesystem.setSymlinksEnabled(true)
        if not love.filesystem.getInfo("assets") then love.filesystem.mount(repoRoot,"",true) end
        assert(love.filesystem.getInfo("assets"),"project assets must be mounted or linked into the isolated preview directory")
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
        data.location=6; data.scene="stop"; data.playerX,data.playerY=790,420
        data.audio.musicVolume=0; data.audio.sfxVolume=0; data.audio.rainVolume=0
        check(services.sessionBootstrap.enterGame(data),"fresh isolated journey loads in full application")
        check(game.selectedSlot==nil,"QA journey remains unslotted")
        check(love.filesystem.getIdentity()=="mouse-frontier-expedition-integration-qa","QA uses isolated save identity")
        record("Full application renderer; "..prefix.." "..love.graphics.getWidth().."x"..love.graphics.getHeight())
        installStages()
    end,debug.traceback)
    if not ok then fail(message) end
end

function love.update()
    if failed or not app then return end
    local ok,message=xpcall(function()
        if captureComplete then
            index=index+1; prepared=false; captureQueued=false; captureComplete=false
        end
        if index>#stages then
            record("PASS all "..#stages.." full application captures and transition assertions")
            saveReport(); app.quit(); love.event.quit(0); return
        end
        if not prepared then stages[index].setup(); prepared=true end
    end,debug.traceback)
    if not ok then fail(message) end
end

function love.draw()
    if failed or not prepared or not stages[index] then return end
    local ok,message=xpcall(function()
        app.draw()
        if not captureQueued then
            captureQueued=true
            local name=prefix.."-"..stages[index].name..".png"
            love.graphics.captureScreenshot(function(data)
                local encoded=data:encode("png")
                local file=assert(io.open(outputRoot.."/"..name,"wb"))
                file:write(encoded:getString()); file:close(); encoded:release(); data:release()
                record("CAPTURE "..name)
                captureComplete=true
            end)
        end
    end,debug.traceback)
    if not ok then fail(message) end
end

function love.errorhandler(message)
    fail(tostring(message).."\n"..debug.traceback())
    return function() return 1 end
end
