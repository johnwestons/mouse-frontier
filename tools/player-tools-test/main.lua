local function check()
    local Host=require("game.player_tools_host")
    local captured
    local wrap=Host.wrap
    Host.wrap=function(app,context) captured=context; return wrap(app,context) end
    local app=require("game.app")
    app.load()
    captured.runtime.state="slots"
    local Model=require("game.player_tools_model")
    local Layout=require("game.control_layout")
    local Catalog=require("game.catalog")
    local Schema=require("game.save_schema")
    local Save=require("game.save")
    local data=assert(Schema.migrate({character="scout-frog.png",inventory={"cowboy-hat"},inventoryCapacity=6}))
    local entries=Model.build(love.filesystem,captured.ui.atlasItems)
    local byId={}
    for _,entry in ipairs(entries) do
        assert(not byId[entry.id],"duplicate item "..entry.id); byId[entry.id]=entry
        assert(captured.ui.atlasItems[entry.id] or captured.ui.propImages[entry.id],"missing sprite "..entry.id)
        assert(#entry.detail>20,"missing detail "..entry.id)
    end
    assert(#entries>150)
    assert(not byId["scratch"] and not byId["mob-claw"] and not byId["backpack-upgrades-v1"])
    for _,field in ipairs({"weaponStats","itemEffects","ammoPickupAmounts","backpackUpgrades","storageCapacities"}) do
        for name in pairs(Catalog[field]) do if name~="scratch" and not name:match("^mob%-") then assert(byId[name],"missing catalog item "..name) end end
    end
    local results=Model.filter(entries,"FRONTIER pistol","Weapons","All")
    assert(#results>0)
    for _,entry in ipairs(results) do assert(entry.category=="Weapons" and entry.search:find("pistol",1,true)) end
    assert(#Model.filter(entries,"no-such-item-xyz","All","All")==0)
    for _,entry in ipairs(Model.filter(entries,"","All","legendary")) do assert(entry.rarity=="legendary") end
    for _,resource in ipairs(Model.resources(data)) do
        local old=Model.resourceValue(data,resource)
        assert(Model.grantResource(data,resource,123)); assert(Model.resourceValue(data,resource)==old+123)
    end
    for _,bad in ipairs({0,-1,.5,math.huge,"nan",1000000}) do assert(not Model.grantItem(data,byId["food-ration"],bad)) end
    assert(not Model.grantItem(nil,byId["food-ration"],1))
    assert(Model.grantItem(data,byId["food-ration"],2)); assert(data.inventory[1]=="cowboy-hat" and data.inventory[2]=="food-ration" and data.inventory[3]=="food-ration")
    assert(not Model.grantItem(data,byId["food-ration"],4)); assert(data.inventory[4]==nil)
    assert(Model.grantItem(data,byId["scavenger-frame-pack"],1)); assert(data.inventoryCapacity==6)
    assert(Model.grantItem(data,byId["travel-chest"],2))
    assert(not Model.grantItem(data,byId["food-ration"],1))
    local ammo=data.ammo["9mm"]
    assert(Model.grantItem(data,byId["9mm"],37)); assert(data.ammo["9mm"]==ammo+37)
    assert(Save.write(1,data)); local restored=assert(Save.read(1))
    assert(restored.inventory[4]=="scavenger-frame-pack" and restored.ammo["9mm"]==ammo+37 and restored.resources.oil==data.resources.oil)
    local controls=captured.mobile.get()
    local moved=controls:layout(); moved.joystick={x=.48,y=.45}; moved.primary={x=.85,y=.85}
    assert(Layout.save(love.filesystem,moved)); controls:setLayout(Layout.load(love.filesystem))
    assert(math.abs(controls:layout().joystick.x-.48)<.001)
    local pressed={}
    local Mobile=require("game.mobile_controls")
    local mobile=Mobile.new({enabled=true,width=960,height=720,toGame=function(x,y) return x,y end,
        gameplayActive=function() return true end,pressKey=function(key) pressed[key]=true end,releaseKey=function(key) pressed[key]=nil end,
        pressPointer=function() end,movePointer=function() end,releasePointer=function() end})
    mobile:setLayout(moved)
    mobile:touchpressed(1,mobile.joystick.x+30,mobile.joystick.y)
    assert(mobile.joystickTouch==1 and select(1,mobile:movement())>0,"moved joystick hit test")
    mobile:touchreleased(1,0,0)
    mobile:touchpressed(2,mobile.primary.x,mobile.primary.y); assert(pressed.e,"moved action hit test")
    mobile:cancelAll(); assert(not pressed.e and select(1,mobile:movement())==0)
    mobile:touchpressed(3,10,700); assert(mobile.joystickTouch==nil,"old joystick gutter must not capture")
    mobile:cancelAll()
    local normalized=Layout.normalize({joystick={x=0/0,y=math.huge},primary={x=-100,y=100}})
    assert(normalized.primary.x==.1 and normalized.primary.y==.9)
    assert(Layout.reset(love.filesystem)); assert(Layout.load(love.filesystem)==nil)
    local ui=require("game.player_tools_ui").new({filesystem=love.filesystem,ui=captured.ui,controls=function() return mobile end,
        data=function() return data end,save=function() return Save.write(1,data) end,cancelInput=function() end})
    ui:show()
    local canvas=love.graphics.newCanvas(960,720)
    local function capture(name)
        love.graphics.setCanvas(canvas); love.graphics.clear(); ui:draw(); love.graphics.setCanvas()
        local image=canvas:newImageData(); image:encode("png",name..".png"); image:release()
    end
    ui.query="pistol"; ui:refresh(); ui.selected=ui.filtered[1]; capture("items")
    ui:focus("query"); ui.query=""; ui:textinput("water"); assert(#ui.filtered>0); ui:key("backspace"); assert(ui.query=="wate")
    ui:focus("quantity"); ui.quantity=""; ui:textinput("20abc"); assert(ui.quantity=="20"); ui:key("return"); assert(ui.field==nil)
    ui.tab="Cheats"; capture("cheats")
    ui.tab="Controls"; capture("controls")
    local r=ui.controlRects[1]; ui:press(r.x+20,r.y+20,1); assert(ui.drag=="joystick")
    ui:move(420,370); ui:finishDrag(); assert(Layout.load(love.filesystem))
    ui:close(); assert(not ui.open and not ui.field)
    assert(Layout.reset(love.filesystem))
    -- Exercise lifecycle/input routing against the actual composed application.
    app.draw(); app.keypressed("f2"); app.draw(); app.textinput("x"); app.wheelmoved(0,-1); app.update(.1)
    app.keypressed("escape"); app.draw()
    app.touchpressed(100,750,680); app.draw()
    app.touchreleased(100,750,680)
    app.touchpressed(101,850,40); app.touchreleased(101,850,40); app.draw()
    app.focus(false); app.focus(true)
    love.window.setMode(1600,720)
    local viewport=require("game.viewport")
    mobile.toGame=function(x,y) return viewport.toGame(x,y,960,720) end
    mobile:setLayout(moved)
    local gx,gy=mobile.joystick.x,mobile.joystick.y
    mobile:touchpressed(10,gx+320+30,gy)
    assert(mobile.joystickTouch==10 and select(1,mobile:movement())>0,"wide-screen moved joystick")
    mobile:cancelAll()
    app.keypressed("f2"); app.draw()
    app.touchpressed(102,1170,40); app.touchreleased(102,1170,40)
    app.draw()
    -- The tooltip and presets also render at the phone's aspect ratio.
    ui:show(); ui.tab="Controls"; capture("controls-wide")
    ui.tab="Items"; ui.query="potion"; ui:refresh(); capture("potions")
    ui:move(220,220); assert(ui.hover); capture("tooltip")
    ui:saveResult(false,"Could not save."); assert(ui.message=="Could not save.")
    ui:close()
    print("PLAYER_TOOLS_OK items="..#entries.." resources="..#Model.resources(data).." captures="..love.filesystem.getSaveDirectory())
end
function love.load()
    local ok,err=xpcall(check,debug.traceback)
    if not ok then print("PLAYER_TOOLS_FAILED "..err) end
    love.event.quit(ok and 0 or 1)
end
