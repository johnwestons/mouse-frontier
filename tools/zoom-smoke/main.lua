local checks=0
local function expect(value,message)
    assert(value,message); checks=checks+1
end
local function close(a,b) expect(math.abs(a-b)<.001,tostring(a).." differs from "..tostring(b)) end
local function run()
    local context
    require("game.smoke_playthrough").install=function(value) context=value end
    local app=require("game.application_composition").new({engine=love})
    app.installSmoke(); app.load()
    local c=context
    local g,ui,p=c.runtime,c.ui,c.presentationRuntime
    local data=c.newSave(c.characters[1])
    c.enterGame(data)
    data=g.saveData
    g.dialogue=nil
    local world=require("game.world_view")
    local range=require("game.shooting_range")
    local scene=require("game.last_stand_scene")
    local shootout=require("game.last_stand_shootout")
    local canvas=love.graphics.newCanvas(1560,720,{format="rgba8"})
    local records={}
    local originalPrint,originalPrintf=love.graphics.print,love.graphics.printf
    local function record(value,x,y)
        if type(value)~="string" then return end
        if value:match("FOOD") or value:match("WATER") or value:match("TIME  ")
            or value:match("AMMO  ") or value:match("TACTICAL ENCOUNTER")
            or value:match("OBJECTIVE") or value:match("JOURNEY MENU") then
            local px,py=love.graphics.transformPoint(x or 0,y or 0)
            local sx,sy=love.graphics.transformPoint((x or 0)+1,(y or 0)+1)
            records[value]={px,py,sx-px,sy-py}
        end
    end
    love.graphics.print=function(value,x,y,...) record(value,x,y); return originalPrint(value,x,y,...) end
    love.graphics.printf=function(value,x,y,...) record(value,x,y); return originalPrintf(value,x,y,...) end
    local function draw(name,zoom)
        p.setZoom(zoom); records={}
        love.graphics.setCanvas({canvas,stencil=true}); love.graphics.origin()
        app.draw(); love.graphics.setCanvas()
        local image=canvas:newImageData(); image:encode("png",name..".png"); image:release()
        expect(love.graphics.getStackDepth()==0,"world transform leaked into next frame")
        return records
    end
    local function pair(name)
        p.resetCamera(true)
        local before=draw(name.."-1",1)
        local after=draw(name.."-2",2)
        local count=0
        for text,a in pairs(before) do
            if after[text] then
                for i=1,4 do close(a[i],after[text][i]) end
                count=count+1
            end
        end
        print("HUD_TRANSFORMS "..name.."="..count)
    end
    pair("train")
    local wx,wy=p.screenToWorld(940,440)
    ui.mobileMenuOpen=true; draw("menu",2)
    local mx,my=p.screenToWorld(940,440); close(mx,wx); close(my,wy)
    local menu=ui.backpack
    app.touchpressed("menu-tap",300+menu.x+menu.w/2,menu.y+menu.h/2)
    app.touchreleased("menu-tap",300+menu.x+menu.w/2,menu.y+menu.h/2)
    expect(g.inventoryOpen,"fixed backpack button did not open at zoom 2")
    draw("inventory",2); g.inventoryOpen=false; ui.mobileMenuOpen=false
    g.travelConfirm=true; draw("travel",2); g.travelConfirm=false
    g.scene="stop"; data.scene="stop"; c.ensureStopLayout(); c.setupNPC(); g.dialogue=nil
    pair("stop")
    c.beginEncounter({rolled=true,hasMob=true,resolved=false,tier="easy",mobFiles={c.catalog.mobTiers.easy[1]}})
    g.battle.intro=nil; pair("battle")
    local unit=g.battle.units[1]
    local bx,by=require("game.battle_grid").boardToScreen(1,unit.q,unit.r)
    bx,by=world.toScreen(bx,by)
    local q,r=require("game.battle_ui").screenToBoardSpace({battle=g.battle},bx,by)
    expect(q==unit.q and r==unit.r,"zoomed battle tile inverse")
    g.state="game"; g.battle=nil
    data.equipment={"frontier-sr22-pistol"}; data.ammo["22lr"]=100
    g.shootingRange=assert(range.new(data,{preferences={},highScores={}},c.catalog))
    range.keypressed(g.shootingRange,"return",data,c.catalog)
    for _=1,3 do range.update(g.shootingRange,.08) end
    pair("range")
    local function pinch()
        p.resetCamera(true)
        app.touchpressed("a",760,360); app.touchpressed("b",920,360)
        app.touchmoved("b",1000,360,80,0)
        expect(p.getZoom()>1.4,"special scene pinch did not zoom")
        app.touchreleased("b",1000,360); app.touchreleased("a",760,360)
        expect(not p.isPanning(),"pinch did not release camera")
    end
    local shots=g.shootingRange.shots
    pinch(); expect(g.shootingRange.shots==shots,"range pinch fired a shot")
    app.touchpressed("a",760,360); app.touchpressed("b",920,360)
    expect(g.shootingRange.shots==shots,"second touch fired before distinguishing a pinch")
    app.touchreleased("b",920,360); app.touchreleased("a",760,360)
    expect(g.shootingRange.shots==shots+1,"second touch tap did not fire")
    local target=g.shootingRange.targets[1]
    p.resetCamera(true); p.setZoom(2)
    target.x,target.y=480,330
    local ax,ay=world.toScreen(target.x,target.y)
    local sx,sy=range.sway(g.shootingRange,c.catalog)
    range.mousepressed(g.shootingRange,ax-sx,ay-sy,data,c.catalog,1)
    expect(target.hit,"range shot missed zoomed target")
    g.shootingRange=nil
    local quest={state="interior",loanAmmo=48,loanedRifle=true,loanMag=12}
    g.lastStand={mode="interior",capture=true,quest=quest,scene=scene.new("interior",quest)}
    pair("interior")
    local x,y=world.toScreen(480,450)
    app.mousepressed(x+300,y,1)
    close(g.lastStand.scene.moveTarget.x,480); close(g.lastStand.scene.moveTarget.y,450)
    g.lastStand.mode="shootout"
    g.lastStand.shootout=shootout.new(quest,data,c.catalog,"wide",960,720)
    pair("shootout")
    local ammo=data.ammo["22lr"]
    pinch(); expect(data.ammo["22lr"]==ammo,"defense pinch fired a shot")
    g.lastStand=nil
    for _,state in ipairs({"slots","characters","intro"}) do
        g.state=state
        if state=="intro" then ui.introCinematic=c.createIntro(); ui.introCinematic.timer=3 end
        draw(state,2)
        close(p.getZoom(),2)
    end
    love.graphics.print,love.graphics.printf=originalPrint,originalPrintf
    print("ZOOM_SMOKE_OK checks="..checks.." screenshots="..love.filesystem.getSaveDirectory())
end
function love.load()
    local ok,err=xpcall(run,debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
