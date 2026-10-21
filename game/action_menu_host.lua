local Menu=require('game.action_menu')
local Viewport=require('game.viewport')
local Host={}
local blockedFields={'inventoryOpen','mapOpen','journeyLogOpen','tradeOpen','trainUpgradeOpen','editMode','outfitCraftingOpen',
    'travelConfirm','travelTransition','carTransition','exitPrompt','pendingConfirmation','dialogue','helpDialogue','firstAid','shootingRange','battle',
    'peopleOpen','guestActivityOpen'}
function Host.available(runtime,ui,extra)
    if not runtime or runtime.state~='game' or not runtime.saveData or extra then return false end
    for _,key in ipairs(blockedFields) do if runtime[key] then return false end end
    if runtime.lastStand and runtime.lastStand.capture or runtime.trainAmbush and runtime.trainAmbush.phase~='complete' then return false end
    if runtime.saveData.roamingEncounter or runtime.session and runtime.session.checkpointPending then return false end
    return not (ui.escMenuOpen or ui.optionsOpen or ui.radioOpen or ui.checkpointBlocked)
end
local function guestActions(v,ui)
    local d=v.runtime.saveData or {};local train=v.runtime.scene=='train';local a={}
    local function add(id,run,enabled,reason,label) a[id]={run=run,enabled=enabled~=false,reason=reason,label=label} end
    add('backpack',function() return v.inventory:toggle() end)
    add('map',function() return v.journey:open('map') end)
    add('journal',function() return v.journey:open('journal') end)
    local exit=v.visits and v.visits:exitTarget()
    add('leave',function() return v.visits and v.visits:leave() end,exit~=nil,'This exit is unavailable.',exit and exit.label)
    add('travel',function() return v.travel:open() end,train and d.stopped==true and (d.location or 50)<50,'Wait for the train and host connection.','NEXT LEG')
    add('upgrade',function() return v.train:open() end,train,'Board the train first.')
    add('decorate',function() return v.objects:openEditor() end,train,'Board the train first.')
    add('maintenance',function() return v.activities:open('maintenance') end,train and d.stopped==true,'Stop the train first.')
    add('pause',function() v.controller:open();return true end)
    add('localPlay',function() v.controller:open();return true end)
    add('settings',function() return v.settings and v.settings:open() end,v.settings~=nil)
    add('editor',function() return ui.openGuiEditor and ui.openGuiEditor() end)
    for _,id in ipairs({'idle','sit','lay','use'}) do local pose=id
        add(id,function() if not v.poses:open() then return false end;return v.poses:submit(pose) end)
    end
    return a
end
function Host.wrap(application,c)
    local original={};for k,v in pairs(application) do original[k]=v end
    local states=setmetatable({},{__mode='k'});local current
    local function guest() return c.guest and c.guest() end
    local function prepare()
        local v=guest();local runtime=v and v.runtime or c.runtime;local ui=v and v.ui or c.ui
        if not states[runtime] then
            local s={runtime=runtime,ui=ui,guest=v}
            s.menu=Menu.new({actions=function() return v and guestActions(v,c.ui) or c.ui.quickActions and c.ui.quickActions() or {} end,
                rightHudX=function() return ui.sideHudLayout and ui.sideHudLayout.rightX end,
                changed=function(page)
                    ui.mobileMenuOpen=page~=nil
                    if page then
                        if v then v:neutralize() else c.mobile.focus(false);c.presentation.endPan() end
                    end
                end})
            states[runtime]=s
        end
        local s=states[runtime]
        if current and current~=s then current.menu:hide();current.menu:cancelInput();current.ui.actionMenuVisible=false end
        current=s;ui.actionMenusEnabled=true;ui.playerToolsOpen=c.ui.playerToolsOpen
        local extra=c.controller and (c.controller.menuOpen or c.controller.focused==false)
            or c.maintenance.open
        if v then extra=extra or not v.ready or not v:actionsAllowed() or v:activityBusy() or v:objectsOpen()
            or v.poses.opened or v.journey.opened or v.travel.opened or v.controllerFocus
            or v.ambush:available() or v.lastStand:available() or v.range:available() end
        s.allowed=Host.available(runtime,ui,extra)
        if s.allowed and runtime.poseMenu then runtime.poseMenu=false;s.menu:setPage('poses') end
        if s.allowed and ui.mobileMenuOpen and not s.menu.page then s.menu:setPage('main') end
        if s.menu.page and not ui.mobileMenuOpen then s.menu:close() end
        ui.actionMenuVisible=s.allowed
        if not s.allowed then s.menu:hide() end
        c.ui.actionMenu=s.menu
        return s
    end
    local function point(x,y) return Viewport.toGame(x,y,960,720) end
    local function press(id,x,y)
        local s=prepare()
        if not s.allowed then return false end
        local gx,gy=point(x,y)
        return s.menu:press(id,gx,gy)
    end
    function application.draw(...)
        local s=prepare();local result=original.draw(...)
        if s.allowed then
            require('game.action_menu_art').setFrames(c.ui.menuFrames)
            local g=love.graphics;local w,h=g.getDimensions();local x,y,sx,sy=Viewport.transform(960,720)
            g.push('all');g.origin();g.translate(x,y);g.scale(sx,sy)
            s.menu:draw({left=-x/sx,top=-y/sy,right=(w-x)/sx,bottom=(h-y)/sy},c.ui.actionMenuPreview)
            g.pop()
        end
        return result
    end
    function application.update(dt,...)
        prepare()
        return original.update(dt,...)
    end
    function application.mousepressed(x,y,button,istouch,...)
        if istouch and current and (current.menu.page or next(current.menu.pressed)) then return true end
        if not istouch and button==1 and press('mouse',x,y) then return true end
        if current and current.menu.page then return true end
        return original.mousepressed(x,y,button,istouch,...)
    end
    function application.mousereleased(x,y,button,istouch,...)
        if not istouch and button==1 and current then
            local gx,gy=point(x,y);if current.menu:release('mouse',gx,gy) then return true end
        end
        if current and current.menu.page then return true end
        return original.mousereleased(x,y,button,istouch,...)
    end
    function application.mousemoved(...)
        if current and (current.menu.page or current.menu.pressed.mouse) then return true end
        return original.mousemoved(...)
    end
    function application.touchpressed(id,x,y,...)
        if press(id,x,y) then return true end
        return original.touchpressed(id,x,y,...)
    end
    function application.touchmoved(id,...)
        if current and (current.menu.pressed[id] or current.menu.page) then return true end
        return original.touchmoved(id,...)
    end
    function application.touchreleased(id,x,y,...)
        if current then local gx,gy=point(x,y);if current.menu:release(id,gx,gy) then return true end end
        if current and current.menu.page then return true end
        return original.touchreleased(id,x,y,...)
    end
    function application.keypressed(key,...)
        if current and current.menu:key(key) then return true end
        return original.keypressed(key,...)
    end
    function application.gamepadpressed(joystick,button,...)
        if current and current.menu:key(button) then return true end
        return original.gamepadpressed(joystick,button,...)
    end
    function application.wheelmoved(...)
        if current and current.menu.page then return true end
        return original.wheelmoved(...)
    end
    function application.focus(focused,...)
        if not focused and current then current.menu:close();current.menu:cancelInput() end
        return original.focus(focused,...)
    end
    return application
end
return Host
