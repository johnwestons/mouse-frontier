local checks=0
local function expect(value,message) assert(value,message); checks=checks+1 end
local function run()
    local c
    require("game.smoke_playthrough").install=function(value) c=value end
    local app=require("game.application_composition").new({engine=love})
    app.installSmoke(); app.load()
    local g,ui,p=c.runtime,c.ui,c.presentationRuntime
    c.enterGame(c.newSave(c.characters[1]))
    local data=g.saveData
    local controls=c.getMobileControls()
    local canvas=love.graphics.newCanvas(1560,720)
    local function step(seconds)
        for _=1,math.ceil(seconds/.05) do app.update(.05) end
    end
    local function fixture(name,zoom,storage)
        controls:cancelAll(); p.resetCamera(true)
        g.state="game"; g.scene="house"; data.scene="house"; data.activeHouseDoor=1
        g.dialogue=nil; g.inventoryOpen=false; g.chestOpen=false; g.activeChest=nil
        g.holdPickupIndex=nil; g.holdPickupTime=0; g.lastStand=nil
        g.player.x,g.player.y=480,500
        g.player.velocityX,g.player.velocityY=0,0
        data.inventory={}; data.droppedItems={{name=name,x=500,y=500,scene="house",location=data.location,
            houseDoor=1,scale=1.4,storage=storage}}
        ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
        c.ensureStopLayout(); c.setupNPC()
        if g.npcActor then g.npcActor.x,g.npcActor.y=800,350 end
        step(.05); p.setZoom(zoom or 1); controls:_updateCornerLayout()
        local ox,oy,sx,sy=require("game.viewport").transform(960,720)
        local x,y=require("game.world_view").toScreen(500,500)
        return ox+x*sx,oy+y*sy
    end
    local function screenControl(control) return control.x+300,control.y end
    local function picked()
        expect(#data.droppedItems==0,"furniture still in room after hold")
        expect(data.inventory[1]~=nil and data.inventory[2]==nil,"pickup did not add exactly one item")
        expect(g.holdPickupIndex==nil,"completed hold did not clear")
    end
    fixture("armchair-green")
    local px,py=screenControl(controls.primary)
    app.touchpressed("primary",px,py); step(1); picked()
    app.touchreleased("primary",px,py)
    expect(not controls:isHeld("e"),"pickup button stayed held")
    for _,zoom in ipairs({1,2}) do
        local x,y=fixture("armchair-green",zoom)
        app.touchpressed("furniture",x,y); step(.3)
        expect(g.holdPickupTime>.2,"direct furniture touch did not advance hold")
        love.graphics.setCanvas(canvas); love.graphics.origin(); app.draw(); love.graphics.setCanvas()
        local hint=ui.contextHint
        local bottomHint=hint and hint.y>=670 and hint.h<=36 and hint.w<=440 and hint.alpha<=.5
        local sideHint=hint and ui.sideHudLayout and hint.x==ui.sideHudLayout.leftX
            and hint.w<=ui.sideHudLayout.panelWidth and hint.h<=48 and hint.alpha<=.5
        expect(bottomHint or sideHint,"pickup hint overlaps gameplay or is too opaque")
        local image=canvas:newImageData(); image:encode("png","home-hold-zoom-"..zoom..".png"); image:release()
        step(.65); picked(); app.touchreleased("furniture",x,y)
        expect(not controls:isHeld("e"),"world hold stayed held")
    end
    local x,y=fixture("armchair-green")
    app.touchpressed("short",x,y); step(.3); app.touchreleased("short",x,y); step(1)
    expect(#data.droppedItems==1 and not data.inventory[1] and g.holdPickupIndex==nil,"short hold picked furniture")
    x,y=fixture("armchair-green")
    app.touchpressed("drag",x,y); step(.2); app.touchmoved("drag",x+50,y,50,0); step(1)
    app.touchreleased("drag",x+50,y)
    expect(#data.droppedItems==1 and not controls:isHeld("e"),"moving finger failed to cancel pickup")
    x,y=fixture("armchair-green")
    app.touchpressed("a",x,y); step(.2); app.touchpressed("b",x+150,y)
    app.touchmoved("b",x+230,y,80,0); step(1)
    app.touchreleased("b",x+230,y); app.touchreleased("a",x,y)
    expect(#data.droppedItems==1 and not controls:isHeld("e") and g.holdPickupIndex==nil,"pinch picked furniture")
    x,y=fixture("armchair-green")
    app.touchpressed("lost-focus",x,y); step(.2); app.focus(false); step(1)
    expect(#data.droppedItems==1 and not controls:isHeld("e") and g.holdPickupIndex==nil,"focus loss failed to cancel pickup")
    fixture("supply-crate",1,{})
    expect(select(1,controls.primaryAction())=="i","container lost Open button")
    expect(select(1,controls.secondaryAction())=="e","container has no Pick Up button")
    px,py=screenControl(controls.primary)
    app.touchpressed("open",px,py); app.touchreleased("open",px,py)
    expect(g.inventoryOpen and g.chestOpen,"container Open button failed")
    fixture("supply-crate",1,{})
    local sx,sy=screenControl(controls.secondary)
    app.touchpressed("pickup",sx,sy); step(1); picked(); app.touchreleased("pickup",sx,sy)
    fixture("supply-crate",1,{"apple"})
    app.touchpressed("full",sx,sy); step(1); app.touchreleased("full",sx,sy)
    expect(#data.droppedItems==1 and data.droppedItems[1].storage[1]=="apple" and not data.inventory[1],"pickup discarded container contents")
    x,y=fixture("armchair-green")
    app.touchpressed("pause",x,y); step(.2); g.inventoryOpen=true; step(1)
    app.touchreleased("pause",x,y)
    expect(#data.droppedItems==1 and g.holdPickupIndex==nil,"pickup completed behind inventory")
    fixture("supply-crate",2,{"apple"})
    expect(controls.backpackVisible(),"backpack shortcut hidden in house")
    local bag=controls.backpack
    local bx,by=screenControl({x=bag.x+bag.w/2,y=bag.y+bag.h/2})
    local stick=controls.joystick
    app.touchpressed("walking",stick.x+300+stick.radius/2,stick.y)
    app.touchpressed("bag",bx,by); app.touchreleased("bag",bx,by)
    expect(g.inventoryOpen and not g.chestOpen and not g.activeChest,"backpack shortcut opened nearby chest")
    expect(not controls.backpackVisible() and not controls:isGameplayActive(),"backpack shortcut leaked into inventory")
    expect(select(1,controls:movement())==0 and not controls:isHeld("e"),"backpack kept movement or pickup held")
    expect(data.droppedItems[1].storage[1]=="apple","backpack changed nearby chest contents")
    app.keypressed("escape")
    expect(not g.inventoryOpen and controls.backpackVisible(),"backpack did not close normally")
    for _,scene in ipairs({"train","stop","house","expedition","crowCaravan"}) do
        g.scene=scene
        expect(controls.backpackVisible(),"backpack shortcut hidden in "..scene)
    end
    g.scene="house"; ui.mobileMenuOpen=true
    expect(not controls.backpackVisible(),"backpack shortcut overlaps menu")
    ui.mobileMenuOpen=false; g.dialogue={}
    expect(not controls.backpackVisible(),"backpack shortcut overlaps dialogue")
    g.dialogue=nil
    g.lastStand={capture=true,mode="interior",paused=false}
    controls:cancelAll(); controls:_updateCornerLayout()
    expect(controls:isMovementActive() and not controls:isGameplayActive(),"Last Stand house did not enable its movement control")
    local stickX,stickY=controls.joystick.x+300+controls.joystick.radius*.5,controls.joystick.y
    controls:touchpressed("last-stand-joystick",stickX,stickY)
    local moveX=select(1,controls:movement())
    expect(moveX>0,string.format("Last Stand joystick did not produce movement input: active=%s x=%.1f y=%.1f radius=%.1f touch=%s axis=%.2f",
        tostring(controls:isMovementActive()),controls.joystick.x,controls.joystick.y,controls.joystick.radius,
        tostring(controls.touches["last-stand-joystick"] and controls.touches["last-stand-joystick"].kind),moveX))
    controls:touchreleased("last-stand-joystick",stickX,stickY)
    expect(select(1,controls:movement())==0,"Last Stand joystick stayed active after release")
    g.lastStand.mode="shootout"
    expect(not controls:isMovementActive(),"Last Stand movement control appeared during first-person shooting")
    g.lastStand.mode="interior"; g.lastStand.paused=true
    expect(not controls:isMovementActive(),"Last Stand movement control remained active while paused")
    g.lastStand=nil; controls:cancelAll()
    local layout=require("game.control_layout").normalize({menu={x=.8,y=.1}})
    expect(layout.backpack and layout.menu.x==.8,"old control positions lost on upgrade")
    local bagX,bagY=bag.x,bag.y
    p.setZoom(1); controls:_updateCornerLayout()
    expect(bag.x==bagX and bag.y==bagY,"zoom moved backpack shortcut")
    love.graphics.setCanvas(canvas); love.graphics.origin(); app.draw(); love.graphics.setCanvas()
    local image=canvas:newImageData(); image:encode("png","backpack-shortcut.png"); image:release()
    print("MOBILE_PICKUP_OK checks="..checks.." screenshots="..love.filesystem.getSaveDirectory())
end
function love.load()
    local ok,err=xpcall(run,debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
