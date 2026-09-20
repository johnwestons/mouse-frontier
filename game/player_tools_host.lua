local UI=require("game.player_tools_ui")
local Viewport=require("game.viewport")
local Host={}
function Host.wrap(application,context)
    local original={}; for key,value in pairs(application) do original[key]=value end
    local function cancelInput()
        local controls=context.mobile.get(); if controls then controls:cancelAll() end
        context.presentation.endPan()
        for _,key in ipairs({"w","a","s","d","up","down","left","right","e","space","lshift","rshift"}) do original.keyreleased(key) end
        context.runtime.draggedSlot=nil; context.runtime.inventoryDragActive=false
    end
    local menu=UI.new({filesystem=context.filesystem,ui=context.ui,controls=context.mobile.get,
        data=function()
            local state=context.runtime.state
            return (state=="game" or state=="battle" or state=="event" or state=="ending") and context.runtime.saveData or nil
        end,
        save=function() if context.persistence.schedule()==false then return false end; return context.persistence.flush() end,cancelInput=cancelInput})
    local function accessRect()
        if context.ui.optionsOpen and context.runtime.state=="game" then
            local mobile=context.mobile.isEnabled()
            return {x=mobile and 582 or 687,y=mobile and 73 or 143,w=240,h=38}
        elseif context.runtime.state=="slots" then return {x=674,y=660,w=250,h=42} end
    end
    local function accessHit(x,y)
        local r=accessRect()
        return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h
    end
    local function show() cancelInput(); menu:show() end
    local function position(x,y) return context.presentation.screenToGame(x,y) end
    function application.update(dt)
        if menu.open then context.persistence.update(dt); return true end
        return original.update(dt)
    end
    function application.draw()
        original.draw()
        love.graphics.push("all")
        if menu.open then love.graphics.clear(.045,.035,.025,1) end
        local x,y,sx,sy=Viewport.transform(960,720)
        love.graphics.translate(x,y); love.graphics.scale(sx,sy)
        if menu.open then menu:draw()
        else
            local r=accessRect()
            if r then menu.buttons={}; menu:button("CHEATS / CONTROLS",r.x,r.y,r.w,r.h,show) end
        end
        love.graphics.pop()
    end
    local swallowedMouse=false
    function application.mousepressed(x,y,button,istouch,...)
        if istouch then if menu.open then return true end; return original.mousepressed(x,y,button,istouch,...) end
        local gx,gy=position(x,y)
        if menu.open then swallowedMouse=true; return menu:press(gx,gy,button) end
        if button==1 and accessHit(gx,gy) then swallowedMouse=true; show(); return true end
        return original.mousepressed(x,y,button,istouch,...)
    end
    function application.mousemoved(x,y,...)
        if menu.open then menu:move(position(x,y)); return true end
        return original.mousemoved(x,y,...)
    end
    function application.mousereleased(x,y,...)
        if menu.open or swallowedMouse then swallowedMouse=false; menu:finishDrag(); return true end
        return original.mousereleased(x,y,...)
    end
    local touches={}
    local owner
    function application.touchpressed(id,x,y,...)
        local gx,gy=position(x,y)
        if menu.open then
            touches[id]=true
            if not owner then owner=id; menu:press(gx,gy,1) end
            return true
        end
        if accessHit(gx,gy) then touches[id]=true; owner=id; show(); return true end
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
        if menu.open then return menu:key(key) end
        if key=="f2" then show(); return true end
        return original.keypressed(key,...)
    end
    function application.keyreleased(key,...)
        if menu.open then return true end
        return original.keyreleased(key,...)
    end
    function application.textinput(value) if menu.open then menu:textinput(value); return true end end
    function application.wheelmoved(x,y)
        if menu.open then if y~=0 then menu:wheel(y) end; return true end
        return original.wheelmoved(x,y)
    end
    function application.focus(focused)
        if not focused then menu:finishDrag(); cancelInput(); owner=nil; touches={} end
        return original.focus(focused)
    end
    function application.quit() menu:finishDrag(); return original.quit() end
    return application
end
return Host
