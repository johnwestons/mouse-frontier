-- Exercise the real application with a separate save identity and synthetic slots.
local root=assert(os.getenv("MOBILE_UI_AUDIT_ROOT"),"MOBILE_UI_AUDIT_ROOT is required"):gsub("\\","/")
local output=assert(os.getenv("MOBILE_UI_AUDIT_OUTPUT"),"MOBILE_UI_AUDIT_OUTPUT is required"):gsub("\\","/")
package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
local app,context,game,ui,services,catalog
local stages,index,prepared,queued,captured={},1,false,false,false
local report,overflow={},{}
local failed=false
local headerTextPoint,phoneHeaderPoint
local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1"

local function record(line)
    report[#report+1]=line; print(line); io.stdout:flush()
end
local function writeReport()
    local file=assert(io.open(output.."/report.txt","wb"))
    file:write(table.concat(report,"\n").."\n"); file:close()
end
local function fail(message)
    failed=true; record("FAIL "..tostring(message)); pcall(writeReport)
    love.event.quit(1)
end
local function clear()
    game.state="game"; game.scene="train"; game.saveData.scene="train"
    for _,key in ipairs({"dialogue","inventoryOpen","chestOpen","activeChest","mapOpen","poseMenu","exitPrompt",
        "tradeOpen","firstAid","shootingRange","helpDialogue","lastStand","travelConfirm","trainUpgradeOpen",
        "characterPreviewFile","giftOpen","draggedSlot","editMode","randomEvent"}) do game[key]=nil end
    ui.optionsOpen=false; ui.mobileMenuOpen=false; ui.radioOpen=false
    context.state.maintenanceSession.open=false
    game.saveData.accessibility.textSize=1
    game.player.moving=false; game.player.velocityX,game.player.velocityY=0,0
    services.presentationRuntime.resetCamera(true)
end
local function stop(location)
    game.scene="stop"; game.saveData.scene="stop"; game.saveData.location=location or 6
    services.worldScene.ensureStopLayout(); services.worldScene.setupNPC()
end
local function checkHeader(compareZoom)
    if not mobile then return end
    local bounds=assert(ui.mobileHeaderBounds,"mobile HUD must expose its layout bounds")
    local width,height=love.graphics.getDimensions()
    local scale=math.min(width/960,height/720)
    local offset=(width-960*scale)/2
    local left=offset+bounds.x*scale
    local right=offset+(bounds.x+bounds.w)*scale
    assert(math.abs(left-20*scale)<.01 and math.abs(right-(width-20*scale))<.01,
        "journey HUD must use the physical screen width with matching margins")
    local controls=services.mobileRuntime.get()
    assert(bounds.resourceRight+8<=controls.menu.x,"resource row must leave room for the mobile menu")
    assert(headerTextPoint,"journey heading must be rendered through measured typography")
    if compareZoom then
        assert(phoneHeaderPoint and math.abs(headerTextPoint.x-phoneHeaderPoint.x)<.01
            and math.abs(headerTextPoint.y-phoneHeaderPoint.y)<.01,"world zoom must not move the mobile HUD")
    elseif width==2340 then phoneHeaderPoint={x=headerTextPoint.x,y=headerTextPoint.y} end
    record(string.format("PASS full-width HUD %dx%d left=%.1f right=%.1f zoom=%.2f",width,height,left,right,services.presentationRuntime.getZoom()))
end
local function add(name,setup,check) stages[#stages+1]={name=name,setup=setup,check=check} end
local function shootout(result,depleted)
    assert(love.window.setMode(mobile and 2340 or 1280,mobile and 1080 or 720,{resizable=false,vsync=0}))
    local quest={loanActive=true,loanAmmo=48}
    local battle=require("game.last_stand_shootout").new(quest,game.saveData,catalog,"wide",960,720)
    battle.touchControls=mobile; battle.result=result
    battle.targets[1].status="exposed"; battle.targets[1].timer=2
    if depleted then
        battle.gun.magazine=0; quest.loanAmmo=0
        if battle.gun.ammoType then game.saveData.ammo[battle.gun.ammoType]=0 end
    end
    game.lastStand={mode="shootout",capture=true,shootout=battle,quest=quest}
end
local function setupStages()
    add("01-save-slots",function() game.state="slots" end)
    add("02-character-select",function() game.state="characters" end)
    add("03-character-profile",function() game.state="characters"; game.characterPreviewFile="mail-mouse.png" end)
    add("04-train",function() end)
    add("05-journey-menu",function() ui.mobileMenuOpen=true end)
    add("06-inventory-16",function() game.inventoryOpen=true; game.draggedSlot={kind="inventory",index=1} end)
    add("07-inventory-last-slot",function() game.inventoryOpen=true; game.draggedSlot={kind="inventory",index=16} end)
    add("08-settings-audio",function() ui.optionsOpen=true; game.optionsPage="audio" end)
    add("09-settings-normal",function() ui.optionsOpen=true; game.optionsPage="accessibility" end)
    add("10-settings-extra-large",function() game.saveData.accessibility.textSize=3; ui.optionsOpen=true; game.optionsPage="accessibility" end)
    add("11-route-map-stop50",function() game.saveData.location=50; game.mapScroll=40; game.mapOpen=true end)
    add("12-trade",function()
        stop(6); game.tradeOpen=true; game.tradeNPC="ferret-medic.png"
        local layout=services.worldScene.ensureStopLayout()
        layout.tradeStock={"frontier-short-sword","field-bandage-roll","patched-canteen","long-barrel-22-pistol"}
        layout.tradeBudget=999
    end)
    add("13-dialogue",function()
        stop(6); game.dialogue={speaker="Ferret Medic • Trusted Friend",timer=120,
            text="The next settlement is beyond the old switch house. Bring enough water and coal for the journey, and check the engine before you leave. Everyone here is counting on you to find the missing travelers."}
    end)
    add("14-dialogue-quest",function()
        stop(6)
        local quests=require("game.help_dialogue_quests")
        local request=quests.ensure(game.saveData,services.worldScene.ensureStopLayout(),"ferret-medic.png",6)
        game.helpDialogue=quests.begin(game.saveData,request)
        game.dialogue={speaker="Ferret Medic",text=game.helpDialogue.text,timer=120}
    end)
    add("15-travel-confirm",function() game.saveData.location=6; game.travelConfirm=true end)
    add("16-train-upgrades",function() game.trainUpgradeOpen=true end)
    add("17-event",function() stop(6); services.eventRuntime.beginRandom() end)
    add("18-battle",function()
        stop(6); services.battleRuntime.beginEncounter({rolled=true,hasMob=true,resolved=false,tier="easy",mobFiles={catalog.mobTiers.easy[1]}})
        game.battle.intro=nil
    end)
    add("19-first-aid",function() game.firstAid=require("game.first_aid").new({npc="ferret-medic.png",location=6,itemName="field-bandage-roll",itemSlot=1}) end)
    add("20-maintenance",function() require("game.maintenance").open(context.state.maintenanceSession,game.saveData) end)
    add("21-range-lobby",function()
        game.shootingRange=assert(require("game.shooting_range").new(game.saveData,{preferences={},highScores={}},catalog,{npc="guard-fox.png"}))
    end)
    add("22-range-active",function()
        local range=require("game.shooting_range")
        game.shootingRange=assert(range.new(game.saveData,{preferences={},highScores={}},catalog,{npc="guard-fox.png"}))
        range.keypressed(game.shootingRange,"return",game.saveData,catalog)
        range.update(game.shootingRange,.2)
        if mobile then range.mousemoved(game.shootingRange,580,530,true) end
    end)
    add("23-exit-confirm",function() game.exitPrompt="title" end)
    add("24-radio",function() ui.radioOpen=true end)
    add("25-character-poses",function() game.poseMenu=true end)
    add("26-hud-phone",function() end,function() checkHeader(false) end)
    add("27-hud-phone-zoom",function() services.presentationRuntime.setZoom(1.65) end,function() checkHeader(true) end)
    add("28-hud-16-by-9",function() assert(love.window.setMode(1280,720,{resizable=false,vsync=0})) end,function() checkHeader(false) end)
    add("29-hud-4-by-3",function() assert(love.window.setMode(960,720,{resizable=false,vsync=0})) end,function() checkHeader(false) end)
    add("30-last-stand-touch",function() shootout() end)
    add("31-last-stand-supply",function() shootout(nil,true) end)
    add("32-last-stand-retreat",function() shootout("retreat") end)
end

function love.load()
    local ok,message=xpcall(function()
        love.filesystem.setSymlinksEnabled(true)
        if not love.filesystem.getInfo("assets") then love.filesystem.mount(root,"",true) end
        assert(love.filesystem.getInfo("assets"),"project assets must be mounted or linked into the audit directory")
        love.math.setRandomSeed(9112026)
        local modules=require("game.systems")
        local original=modules.smokeComposition.new
        modules.smokeComposition.new=function(ctx) context=ctx; return original(ctx) end
        app=require("game.application_composition").new({engine=love})
        modules.smokeComposition.new=original
        app.load()
        game,ui,services=context.state.runtime,context.state.ui,context.services
        catalog=context.domain.catalog
        local data=services.sessionBootstrap.newSave("mail-mouse.png")
        data.location=6; data.scene="train"; data.scrap=999; data.inventoryCapacity=16
        local names={"field-bandage-roll","patched-canteen","frontier-short-sword","long-barrel-22-pistol",
            "trail-slingshot","green-regeneration-vial","medium-oil-canister","scrap-hunting-spear"}
        for slot=1,16 do data.inventory[slot]=names[(slot-1)%#names+1] end
        data.audio.musicVolume=0; data.audio.sfxVolume=0; data.audio.rainVolume=0
        assert(services.sessionBootstrap.enterGame(data),"isolated journey must load")
        assert(game.selectedSlot==nil,"audit journey must remain unslotted")
        assert(love.filesystem.getIdentity()==(mobile and "mouse-frontier-mobile-ui-audit" or "mouse-frontier-desktop-ui-audit"),"audit identity must stay separate")
        for slot=1,3 do assert(context.domain.save.write(slot,data),"create synthetic audit slot") end
        local typography=require("game.typography")
        local drawText=typography.drawText
        typography.drawText=function(Graphics,text,x,y,w,h,options)
            if text=="STOP "..game.saveData.location then
                local px,py=Graphics.transformPoint(x,y)
                headerTextPoint={x=px,y=py}
            end
            local scale,height,lines,fits=drawText(Graphics,text,x,y,w,h,options)
            if not fits then
                local key=stages[index].name..": "..tostring(text):gsub("\n"," / ")
                if not overflow[key] then
                    overflow[key]=true
                    record(string.format("OVERFLOW %s (box %.0fx%.0f, scale %.3f, lines %d, height %.1f)",key,w,h,scale,lines,height))
                end
            end
            return scale,height,lines,fits
        end
        record("Real application "..(mobile and "mobile" or "desktop").." audit "..love.graphics.getWidth().."x"..love.graphics.getHeight())
        setupStages()
        require("tools.mobile-ui-audit.content_fit").run({graphics=love.graphics,game=game,ui=ui,record=record})
    end,debug.traceback)
    if not ok then fail(message) end
end

function love.update()
    if failed or not app then return end
    local ok,message=xpcall(function()
        if captured then index=index+1; prepared=false; queued=false; captured=false end
        if index>#stages then
            record("COMPLETE "..#stages.." captures; isolated audit saves only")
            writeReport(); app.quit(); love.event.quit(0); return
        end
        if not prepared then clear(); headerTextPoint=nil; stages[index].setup(); prepared=true end
    end,debug.traceback)
    if not ok then fail(message) end
end

function love.draw()
    if failed or not prepared or not stages[index] then return end
    local ok,message=xpcall(function()
        app.draw()
        if not queued then
            queued=true
            if stages[index].check then stages[index].check() end
            local name=stages[index].name..".png"
            love.graphics.captureScreenshot(function(data)
                local encoded=data:encode("png")
                local file=assert(io.open(output.."/"..name,"wb"))
                file:write(encoded:getString()); file:close(); encoded:release(); data:release()
                record("CAPTURE "..name); captured=true
            end)
        end
    end,debug.traceback)
    if not ok then fail(message) end
end
function love.errorhandler(message)
    fail(tostring(message).."\n"..debug.traceback())
    return function() return 1 end
end
