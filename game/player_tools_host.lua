local UI=require("game.player_tools_ui")
local Viewport=require("game.viewport")
local UIStyle=require("game.ui_layout")
local WorldPause=require("game.world_pause")
local Host={}
function Host.wrap(application,context)
    local original={}; for key,value in pairs(application) do original[key]=value end
    local menu
    local function guest() return context.guest and context.guest() end
    local function cancelInput()
        context.ui.playerToolsOpen=menu and menu.open==true or false
        local view=guest();if view then view.ui.playerToolsOpen=context.ui.playerToolsOpen;view:neutralize() end
        if context.ui.suspendOutfitWorkbench then context.ui.suspendOutfitWorkbench() end
        local controls=context.mobile.get(); if controls then controls:cancelAll() end
        context.presentation.endPan()
        for _,key in ipairs({"w","a","s","d","up","down","left","right","e","space","lshift","rshift"}) do original.keyreleased(key) end
        context.runtime.draggedSlot=nil; context.runtime.inventoryDragActive=false
    end
    local layoutEditor=UIStyle.new({filesystem=context.filesystem,screen=function()
        local view=guest();local runtime=view and view.runtime or context.runtime
        if runtime.state=="game" then return "game_"..tostring(runtime.scene or "train") end
        return tostring(runtime.state or "screen")
    end})
    menu=UI.new({filesystem=context.filesystem,ui=context.ui,minigames=context.minigames,controls=function() local view=guest();return view and view.mobile or context.mobile.get() end,uiedit=layoutEditor,
        data=function()
            if guest() then return nil end -- Device editing never mutates the host's campaign.
            local state=context.runtime.state
            return (state=="game" or state=="battle" or state=="event" or state=="ending") and context.runtime.saveData or nil
        end,
        save=function() if context.persistence.schedule()==false then return false end; return context.persistence.flush() end,cancelInput=cancelInput})
    local function accessRect()
        if context.runtime.state=="slots" then return {x=18,y=652,w=250,h=50} end
    end
    local function accessHit(x,y)
        local r=accessRect()
        return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h
    end
    local function show(tab)
        local session=context.runtime.session
        if context.ui.checkpointBlocked or session and session.checkpointPending then return false end
        cancelInput(); menu:show(); context.ui.playerToolsOpen=true; if tab then menu.tab=tab end
        return true
    end
    context.ui.openTouchControls=function() return show("Controls") end
    context.ui.openGuiEditor=function() return show('UI Editor') end
    context.ui.openDebugActivities=function() if show('Cheats') then menu.cheatPage='minigames';return true end end
    local function position(x,y) return context.presentation.screenToGame(x,y) end
    function application.update(dt)
        context.ui.playerToolsOpen=menu.open==true
        if menu.open and not guest() and not WorldPause.isSharedHost(context.runtime) then
            if context.controller then context.controller:beginFrame(dt);context.controller:finishFrame() end
            context.persistence.update(dt); return true
        end
        return original.update(dt)
    end
    function application.draw()
        layoutEditor:beginFrame()
        if menu.open and menu.tab=="UI Editor" and menu.uiElement~="options" and context.ui.optionsOpen then
            local optionsOpen=context.ui.optionsOpen
            context.ui.optionsOpen=false
            local ok,message=xpcall(original.draw,debug.traceback)
            context.ui.optionsOpen=optionsOpen
            if not ok then error(message,0) end
        else original.draw() end
        love.graphics.push("all")
        if menu.open and menu.tab~="UI Editor" then love.graphics.clear(.045,.035,.025,1) end
        local x,y,sx,sy=Viewport.transform(960,720)
        love.graphics.translate(x,y); love.graphics.scale(sx,sy)
        if menu.open then menu:draw()
        else
            local r=accessRect()
            if r then menu.buttons={}; menu:button("CHEATS / CONTROLS",r.x,r.y,r.w,r.h,show) end
        end
        love.graphics.pop()
    end
    local touches={}
    local owner
    local swallowedMouse={}
    local mouseOwner=false
    local swallowedTouchMouse=false
    local swallowedKeys={}
    function application.mousepressed(x,y,button,istouch,...)
        if istouch then
            if menu.open or next(touches) or swallowedTouchMouse then swallowedTouchMouse=true; return true end
            return original.mousepressed(x,y,button,istouch,...)
        end
        local gx,gy=position(x,y)
        if menu.open then
            swallowedMouse[button]=true
            if button==1 and not owner and not mouseOwner then mouseOwner=true; menu:press(gx,gy,button) end
            return true
        end
        if button==1 and accessHit(gx,gy) then swallowedMouse[button]=true; mouseOwner=true; show(); return true end
        return original.mousepressed(x,y,button,istouch,...)
    end
    function application.mousemoved(x,y,dx,dy,istouch,...)
        if istouch then
            if menu.open or next(touches) or swallowedTouchMouse then return true end
            return original.mousemoved(x,y,dx,dy,istouch,...)
        end
        if menu.open then if not owner then menu:move(position(x,y)) end; return true end
        if mouseOwner then return true end
        return original.mousemoved(x,y,dx,dy,istouch,...)
    end
    function application.mousereleased(x,y,button,istouch,...)
        if istouch then
            if menu.open or next(touches) or swallowedTouchMouse then swallowedTouchMouse=false; return true end
            return original.mousereleased(x,y,button,istouch,...)
        end
        if menu.open or swallowedMouse[button] then
            swallowedMouse[button]=nil
            if button==1 and mouseOwner then mouseOwner=false; menu:finishDrag() end
            return true
        end
        return original.mousereleased(x,y,button,istouch,...)
    end
    function application.touchpressed(id,x,y,...)
        local gx,gy=position(x,y)
        if menu.open then
            touches[id]=true; swallowedTouchMouse=true
            if not owner and not mouseOwner then owner=id; menu:press(gx,gy,1) end
            return true
        end
        if accessHit(gx,gy) then touches[id]=true; owner=id; swallowedTouchMouse=true; show(); return true end
        return original.touchpressed(id,x,y,...)
    end
    function application.touchmoved(id,x,y,...)
        if touches[id] or menu.open then if owner==id then menu:move(position(x,y)) end; return true end
        return original.touchmoved(id,x,y,...)
    end
    function application.touchreleased(id,x,y,...)
        if touches[id] or menu.open then
            touches[id]=nil
            if owner==id then owner=nil; menu:finishDrag() end
            return true
        end
        return original.touchreleased(id,x,y,...)
    end
    function application.keypressed(key,...)
        if menu.open then
            if swallowedKeys[key] and (key=="escape" or key=="acback" or key=="f2") then return true end
            swallowedKeys[key]=true
            return menu:key(key)
        end
        if swallowedKeys[key] then return true end
        if key=="f2" then swallowedKeys[key]=true; show(); return true end
        return original.keypressed(key,...)
    end
    function application.keyreleased(key,...)
        if swallowedKeys[key] then swallowedKeys[key]=nil; return true end
        if menu.open then return true end
        return original.keyreleased(key,...)
    end
    function application.gamepadpressed(...)
        if menu.open then return true end
        return original.gamepadpressed(...)
    end
    function application.gamepadreleased(...)
        if menu.open then return true end
        return original.gamepadreleased(...)
    end
    function application.gamepadaxis(...)
        if menu.open then return true end
        return original.gamepadaxis(...)
    end
    function application.textinput(value)
        if menu.open then menu:textinput(value); return true end
        if original.textinput then return original.textinput(value) end
    end
    function application.wheelmoved(x,y)
        if menu.open then if y~=0 then menu:wheel(y) end; return true end
        return original.wheelmoved(x,y)
    end
    function application.focus(focused)
        if not focused then
            menu:finishDrag(); menu:focus(nil); cancelInput(); owner=nil; mouseOwner=false; swallowedKeys={}
        end
        return original.focus(focused)
    end
    function application.quit() menu:finishDrag(); return original.quit() end
    return application
end
return Host
