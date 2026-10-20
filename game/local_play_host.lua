local GuiArt=require('game.gui_art')
-- Outermost application boundary: networking runs before modal/save/workbench
-- early returns. A pending checkpoint retains priority over the LAN panel.
local Panel=require('game.local_play_panel')
local Viewport=require('game.viewport')
local WorldPause=require('game.world_pause')
local Pose=require('game.coop_player_pose')
local Typography=require('game.typography')
local AimCursor=require('game.aim_cursor')
local Attack=require('game.character_attack')
local Host={}
local launcher={x=752,y=652,w=190,h=50}
local function inside(x,y) return x>=launcher.x and x<=launcher.x+launcher.w and y>=launcher.y and y<=launcher.y+launcher.h end
function Host.wrap(application,context)
    local original={}; for name,value in pairs(application) do original[name]=value end
    local controller=context.controller; local panel=Panel.new(controller,context)
    local originalPose=context.ui.changePose
    local function configurePose()
        if WorldPause.isSharedHost(context.runtime) and context.commands.poseState then
            context.ui.changePose=function(pose) return context.commands.submit('player.pose',{pose=pose}) end
        else context.ui.changePose=originalPose end
    end
    local touches={}; local mouseOwned=false
    context.ui.localPlay=controller; context.ui.openLocalPlay=function() controller:open() end
    context.ui.coopCompanion=function()
        local motion=controller.motion
        if motion and motion.generation and motion.actor and controller.campaign then
            local cue=context.runtime.companionFieldAction; local pose
            if cue and cue.epoch==controller.campaign.coop.sceneEpoch then
                pose={actionTimer=math.max(0,cue.untilTime-(context.runtime.animationClock or 0)),actionDuration=cue.duration,actionKind=Attack.action(cue.weapon),actionHeldItem=Attack.heldItem(cue.weapon),facing=cue.facing}
            end
            if context.commands.poseState then pose=Pose.presentation(context.commands.poseState('companion'),pose) end
            return motion.actor,controller.campaign.players.companion,pose
        end
    end
    local function blocked() return context.commands.checkpointStatus().pending end
    local function client() return controller.isClient and controller:isClient() end
    local function guestSettings()
        local view=client() and controller.clientView
        local settings=view and view.settings
        return settings and settings:isOpen() and settings or nil
    end
    local travelNotice
    local dismissRect={x=706,y=84,w=28,h=28}
    local function dismissNotice(x,y)
        if not travelNotice or not context.commands.dismissTravelRequest then return false end
        local gx,gy=context.screenToGame(x,y)
        if gx<dismissRect.x or gx>dismissRect.x+dismissRect.w or gy<dismissRect.y or gy>dismissRect.y+dismissRect.h then return false end
        context.commands.dismissTravelRequest(travelNotice.serial);travelNotice=nil;return true
    end
    local function guestKey(key,released)
        local view=controller.clientView
        -- Keep the emergency Local Play key independent of user remapping.
        if key=='f8' or not view or not view.settings then return key end
        local token,known=view.settings:translateGameplayKey(key,released)
        if known and not token then return nil end
        return token
    end
    local function guestEvent(name,...)
        local view=controller.clientView
        if view and view[name] then return view[name](view,...) end
        return true -- A missing guest control must never fall into solo logic.
    end
    local function available() return context.runtime.state=='slots' or context.ui.escMenuOpen==true end
    local function forwardEntry(name,...)
        configurePose()
        local result=original[name](...)
        if controller.hostingIntent=='selecting' and (context.runtime.state=='game' or context.runtime.state=='battle') then
            controller:finishHostingEntry()
        end
        configurePose()
        return result
    end
    local function launch(x,y)
        if not available() then return false end
        x,y=context.screenToGame(x,y)
        if inside(x,y) then controller:open(); return true end
        return false
    end
    function application.update(dt)
        configurePose()
        if controller.beginFrame then controller:beginFrame(dt) else controller:update(dt) end
        local result
        if blocked() or not client() and controller.hostingIntent~='failed'
            and (not controller:captures() or WorldPause.isSharedHost(context.runtime)) then
            result=original.update(dt)
        else
            result=context.idleUpdate(dt,client() and controller.clientView and controller.clientView.runtime or nil)
        end
        if controller.finishFrame then controller:finishFrame() end
        return result
    end
    local function draw(...)
        context.ui.localPlayLauncher=nil
        if blocked() then panel:stopTextInput(); return original.draw(...) end
        local settings=guestSettings(); if settings then return settings:draw() end
        if controller:captures() then return panel:draw() end
        if client() then return guestEvent('draw') end
        local result=original.draw(...)
        travelNotice=WorldPause.isSharedHost(context.runtime) and context.runtime.state=='game'
            and not controller.menuOpen and context.commands.travelRequest and context.commands.travelRequest() or nil
        if travelNotice then
            local g=love.graphics;g.push('all');g.origin()
            local ox,oy,sx,sy=Viewport.transform(960,720);g.translate(ox,oy);g.scale(sx,sy)
            g.setColor(.08,.055,.035,.97);GuiArt.frame(226,78,510,66)
            g.setColor(.96,.88,.69,1)
            Typography.drawText(g,'Companion requested departure to Stop '..travelNotice.to..'.',240,86,454,24,
                {scale=.85,minScale=.65,align='center',valign='center'})
            Typography.drawText(g,'Host decides. Food '..travelNotice.food..' / Water '..travelNotice.water..' / Coal '..travelNotice.coal,240,112,454,24,
                {scale=.75,minScale=.60,align='center',valign='center'})
            GuiArt.frame(dismissRect.x,dismissRect.y,dismissRect.w,dismissRect.h)
            g.printf('X',dismissRect.x,dismissRect.y+5,dismissRect.w,'center');g.pop()
        end
        if available() then
            context.ui.localPlayLauncher=launcher
            local g=love.graphics; g.push('all'); g.origin()
            local ox,oy,sx,sy=Viewport.transform(960,720); g.translate(ox,oy); g.scale(sx,sy)
            g.setColor(.18,.14,.09,1); GuiArt.frame(launcher.x,launcher.y,launcher.w,launcher.h)
            g.setColor(1,.93,.78,1)
            Typography.drawText(g,'LOCAL PLAY  [F8]',launcher.x+8,launcher.y+6,launcher.w-16,launcher.h-12,{scale=.8,minScale=.65,align='center',valign='center'}); g.pop()
        end
        return result
    end
    function application.draw(...)
        AimCursor.beginFrame()
        local result=draw(...)
        local ui,runtime=context.ui,context.runtime
        AimCursor.endFrame(not not (blocked() or guestSettings() or controller:captures()
            or ui.escMenuOpen or ui.optionsOpen or ui.playerToolsOpen or runtime.exitPrompt
            or runtime.pendingConfirmation or controller.menuOpen or controller.focused==false))
        return result
    end
    function application.keypressed(key,...)
        if blocked() then return original.keypressed(key,...) end
        local settings=guestSettings(); if settings then return settings:keypressed(key) end
        if controller:captures() then return panel:key(key) end
        if client() then
            key=guestKey(key,false); if not key then return true end
            return guestEvent('keypressed',key,...)
        end
        if key=='f8' and not context.bindings:isCapturing() then controller:open(); return true end
        return forwardEntry('keypressed',key,...)
    end
    function application.textinput(text,...)
        if not blocked() and guestSettings() then return true end
        if not blocked() and controller:captures() then return panel:textinput(text) end
        if client() then return true end
        return original.textinput(text,...)
    end
    function application.mousepressed(x,y,button,istouch,...)
        if blocked() then return original.mousepressed(x,y,button,istouch,...) end
        local settings=guestSettings()
        if settings then
            if istouch then return true end
            mouseOwned=true; local gx,gy=context.screenToGame(x,y)
            return settings:pointer(gx,gy,button)
        end
        if istouch and (controller:captures() or available()) then return true end
        if controller:captures() then mouseOwned=true; return panel:click(x,y) end
        if client() then return guestEvent('mousepressed',x,y,button,istouch,...) end
        if not istouch and button==1 and dismissNotice(x,y)then mouseOwned=true;return true end
        if button==1 and launch(x,y) then mouseOwned=true; return true end
        return forwardEntry('mousepressed',x,y,button,istouch,...)
    end
    function application.touchpressed(id,x,y,...)
        if blocked() then return original.touchpressed(id,x,y,...) end
        local settings=guestSettings()
        if settings then
            touches[id]=true; local gx,gy=context.screenToGame(x,y)
            return settings:touchpressed(id,gx,gy)
        end
        if controller:captures() then touches[id]=true; return panel:click(x,y) end
        if client() then return guestEvent('touchpressed',id,x,y,...) end
        if dismissNotice(x,y)then touches[id]=true;return true end
        if launch(x,y) then touches[id]=true; return true end
        return forwardEntry('touchpressed',id,x,y,...)
    end
    function application.touchreleased(id,...)
        local settings=not blocked() and guestSettings()
        if settings then touches[id]=nil; return settings:touchreleased(id) end
        if touches[id] then touches[id]=nil; return true end
        if not blocked() and controller:captures() then return true end
        if client() then return guestEvent('touchreleased',id,...) end
        return forwardEntry('touchreleased',id,...)
    end
    function application.touchmoved(id,x,y,...)
        local settings=not blocked() and guestSettings()
        if settings then local gx,gy=context.screenToGame(x,y); return settings:touchmoved(id,gx,gy) end
        if touches[id] or (not blocked() and controller:captures()) then return true end
        if client() then return guestEvent('touchmoved',id,x,y,...) end
        return original.touchmoved(id,x,y,...)
    end
    function application.mousereleased(x,y,button,...)
        local settings=not blocked() and guestSettings()
        if settings then mouseOwned=false; return settings:mousereleased(button) end
        if mouseOwned then mouseOwned=false; return true end
        if not blocked() and controller:captures() then return true end
        if client() then return guestEvent('mousereleased',x,y,button,...) end
        return forwardEntry('mousereleased',x,y,button,...)
    end
    function application.gamepadpressed(joystick,button,...)
        local settings=not blocked() and guestSettings()
        if settings then return settings:gamepadpressed(button) end
        if not blocked() and controller:captures() then
            return panel:key(({a='return',b='escape',start='escape',dpup='up',dpdown='down',dpleft='up',dpright='down'})[button])
        end
        if client() then return guestEvent('gamepadpressed',joystick,button,...) end
        return forwardEntry('gamepadpressed',joystick,button,...)
    end
    for _,name in ipairs({'mousemoved','wheelmoved','keyreleased','gamepadreleased','gamepadaxis'}) do
        local callback=name
        application[callback]=function(...)
            local settings=not blocked() and guestSettings()
            if settings then
                local a,b,c=...
                if callback=='mousemoved' then
                    local gx,gy=context.screenToGame(a,b); return settings:mousemoved(gx,gy)
                elseif callback=='wheelmoved' then return settings:wheel(b)
                elseif callback=='gamepadreleased' then return settings:gamepadreleased(b)
                elseif callback=='gamepadaxis' then return settings:gamepadaxis(b,c)
                else return settings:keyreleased(a) end
            end
            if not blocked() and controller:captures() then return true end
            if client() and callback=='keyreleased' then
                local key=guestKey(select(1,...),true); if not key then return true end
                return guestEvent(callback,key,select(2,...))
            end
            if client() then return guestEvent(callback,...) end
            return original[callback](...)
        end
    end
    function application.focus(focused,...)
        if not focused then AimCursor.restore() end
        controller.focused=focused~=false
        if not focused then panel:stopTextInput() end
        if client() then return guestEvent('focus',focused,...) end
        return original.focus(focused,...)
    end
    function application.quit(...)
        AimCursor.restore()
        local cancelled=original.quit(...)
        if cancelled~=true then panel:stopTextInput(); controller:stop('application_closed') end
        return cancelled
    end
    return application
end
return Host
