local WorkbenchUI=require("game.outfit_crafting_ui")
local Viewport=require("game.viewport")
local Host={}

-- The bench owns input and pauses the world while a saved sewing project is open.
function Host.wrap(application,context)
    local original={}; for key,value in pairs(application) do original[key]=value end
    local runtime,ui=context.runtime,context.ui
    local touches,keys,buttons={},{},{}
    local touchOwner,mouseOwner,openedData,origin
    local swallowedTouchMouse=false
    local bench
    local function cancelInput()
        local controls=context.mobile.get(); if controls then controls:cancelAll() end
        context.presentation.endPan()
        for _,key in ipairs({"w","a","s","d","up","down","left","right","e","space","lshift","rshift"}) do
            if original.keyreleased then original.keyreleased(key) end
        end
        runtime.draggedSlot=nil; runtime.inventoryDragActive=false
        runtime.holdPickupIndex=nil; runtime.holdPickupTime=0
    end
    local function allowed()
        local data=runtime.saveData
        if runtime.state~="game" or runtime.scene~="train" or not data or data.stopped~=true then
            return false,"Return to the stopped train to use the sewing bench."
        end
        if runtime.travelTransition or runtime.carTransition or runtime.travelConfirm
            or runtime.lastStand and runtime.lastStand.capture
            or data.trainAmbush and data.trainAmbush.active
            or runtime.firstAid or runtime.shootingRange or runtime.helpDialogue
            or runtime.tradeOpen or runtime.giftOpen or context.maintenanceSession.open
            or ui.escMenuOpen or ui.optionsOpen or runtime.exitPrompt or runtime.pendingConfirmation
            or runtime.dialogue and not runtime.dialogue.inventoryResult then
            return false,"Finish the current activity before opening the sewing bench."
        end
        return true
    end
    bench=WorkbenchUI.new({
        data=function() return runtime.saveData end,
        save=function()
            if context.persistence.schedule()==false then return false end
            return context.persistence.flush()
        end,
        mobileEnabled=context.mobile.isEnabled,
        cancelInput=cancelInput,
        onClose=function()
            local restore=runtime.outfitCraftingOpen and runtime.saveData==openedData and runtime.state=="game"
            runtime.outfitCraftingOpen=false
            touchOwner=nil; mouseOwner=nil
            if restore then
                if origin=="workshop" then runtime.trainUpgradeOpen=true
                else runtime.inventoryOpen=true; runtime.inventoryMode="wearables" end
            end
            openedData=nil
        end,
    })
    ui.canOpenOutfitWorkbench=allowed
    ui.suspendOutfitWorkbench=function()
        bench:suspend()
        touchOwner=nil; mouseOwner=nil
    end
    ui.openOutfitWorkbench=function()
        if not allowed() then return false end
        if bench:isOpen() then return true end
        openedData=runtime.saveData
        origin=runtime.trainUpgradeOpen and "workshop" or "inventory"
        cancelInput()
        runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
        runtime.trainUpgradeOpen=false; runtime.weaponRepairOpen=false; runtime.weaponRepairStartedAt=nil
        runtime.mapOpen=false; runtime.journeyLogOpen=false; runtime.poseMenu=false; runtime.editMode=false
        if runtime.dialogue and runtime.dialogue.inventoryResult then runtime.dialogue=nil end
        ui.mobileMenuOpen=false; ui.radioOpen=false; ui.keyboardFocusVisible=false
        runtime.outfitCraftingOpen=true
        bench:show()
        return true
    end
    local function active()
        if not bench:isOpen() then return false end
        if runtime.state~="game" or runtime.saveData~=openedData or not runtime.outfitCraftingOpen then
            runtime.outfitCraftingOpen=false; bench:close(); return false
        end
        return true
    end
    local function position(x,y) return context.presentation.screenToGame(x,y) end
    function application.update(dt)
        if active() then
            bench:update(dt)
            context.persistence.update(dt)
            if context.audio then context.audio.update() end
            return true
        end
        return original.update(dt)
    end
    function application.draw()
        if not active() then return original.draw() end
        love.graphics.push("all")
        love.graphics.clear(.055,.035,.022,1)
        local x,y,sx,sy=Viewport.transform(960,720)
        love.graphics.translate(x,y); love.graphics.scale(sx,sy)
        bench:draw()
        love.graphics.pop()
    end
    function application.mousepressed(x,y,button,istouch,...)
        if istouch then
            if active() or next(touches) or swallowedTouchMouse then swallowedTouchMouse=true; return true end
            return original.mousepressed(x,y,button,istouch,...)
        end
        if active() then
            buttons[button]=true
            if button==1 and not touchOwner then
                mouseOwner=true
                local gx,gy=position(x,y); bench:mousepressed(gx,gy,button)
            end
            return true
        end
        return original.mousepressed(x,y,button,istouch,...)
    end
    function application.mousemoved(x,y,dx,dy,istouch,...)
        if istouch then
            if active() or next(touches) or swallowedTouchMouse then return true end
            return original.mousemoved(x,y,dx,dy,istouch,...)
        end
        if active() then
            if not istouch and not touchOwner then bench:mousemoved(position(x,y)) end
            return true
        end
        return original.mousemoved(x,y,dx,dy,istouch,...)
    end
    function application.mousereleased(x,y,button,istouch,...)
        if istouch then
            if active() or next(touches) or swallowedTouchMouse then swallowedTouchMouse=false; return true end
            return original.mousereleased(x,y,button,istouch,...)
        end
        if active() or buttons[button] then
            buttons[button]=nil
            if not istouch and mouseOwner and button==1 then
                mouseOwner=nil
                if active() then local gx,gy=position(x,y); bench:mousereleased(gx,gy,button) end
            end
            return true
        end
        return original.mousereleased(x,y,button,istouch,...)
    end
    function application.touchpressed(id,x,y,...)
        if active() then
            touches[id]=true; swallowedTouchMouse=true
            if not touchOwner and not mouseOwner then
                touchOwner=id
                local gx,gy=position(x,y); bench:mousepressed(gx,gy,1)
            end
            return true
        end
        return original.touchpressed(id,x,y,...)
    end
    function application.touchmoved(id,x,y,...)
        if active() or touches[id] then
            if active() and touchOwner==id then bench:mousemoved(position(x,y)) end
            return true
        end
        return original.touchmoved(id,x,y,...)
    end
    function application.touchreleased(id,x,y,...)
        if active() or touches[id] then
            touches[id]=nil
            if touchOwner==id then
                touchOwner=nil
                if active() then local gx,gy=position(x,y); bench:mousereleased(gx,gy,1) end
            end
            return true
        end
        return original.touchreleased(id,x,y,...)
    end
    function application.keypressed(key,scancode,isrepeat)
        if active() then
            if isrepeat then return true end
            local mapped,known=context.bindings:translateKey(key)
            if known and not mapped then keys[key]=false; return true end
            keys[key]=mapped or key
            bench:keypressed(mapped or key)
            return true
        end
        if keys[key]~=nil then return true end
        return original.keypressed(key,scancode,isrepeat)
    end
    function application.keyreleased(key,...)
        if active() or keys[key]~=nil then
            local mapped=keys[key]; keys[key]=nil
            if active() and mapped then bench:keyreleased(mapped) end
            return true
        end
        return original.keyreleased(key,...)
    end
    local padKeys={}
    function application.gamepadpressed(joystick,button)
        if active() then
            local mapped=context.bindings:translateButton(button,"menu")
            padKeys[button]=mapped or false
            if mapped then bench:keypressed(mapped) else bench:gamepadpressed(button) end
            return true
        end
        return original.gamepadpressed(joystick,button)
    end
    function application.gamepadreleased(joystick,button)
        if active() or padKeys[button]~=nil then
            local mapped=padKeys[button]; padKeys[button]=nil
            if active() then
                if mapped then bench:keyreleased(mapped) else bench:gamepadreleased(button) end
            end
            return true
        end
        return original.gamepadreleased(joystick,button)
    end
    function application.gamepadaxis(...)
        if active() then return true end
        return original.gamepadaxis(...)
    end
    function application.wheelmoved(x,y)
        if active() then bench:wheelmoved(x,y); return true end
        return original.wheelmoved(x,y)
    end
    function application.focus(focused)
        if not focused and active() then
            if bench.suspend then bench:suspend() end
            mouseOwner=nil; touchOwner=nil
        end
        return original.focus(focused)
    end
    return application
end
return Host
