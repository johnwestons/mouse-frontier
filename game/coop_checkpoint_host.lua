-- This wrapper stays outside workbenches/debug tools so no modal early-return
-- can bypass a pending critical checkpoint. Future networking is serviced
-- before this barrier through serviceSession, never through paused world code.
local Viewport=require("game.viewport")
local Typography=require("game.typography")
local Accessibility=require("game.accessibility")
local Host={}
local buttons={{x=190,y=438,w=185,h=58},{x=387,y=438,w=185,h=58},{x=584,y=438,w=185,h=58}}

local function contains(rect,x,y)
    return rect and x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h
end

function Host.wrap(application,context)
    local original={}; for name,value in pairs(application) do original[name]=value end
    local runtime,ui,commands=context.runtime,context.ui,context.commands
    local entered=false
    local selected=1
    local confirmQuit=false
    local forceQuit=false
    ui.checkpointStatus=commands.checkpointStatus
    local function blocked()
        return commands.checkpointStatus().pending
    end
    local function enter()
        if entered then return end
        entered=true; selected=1; confirmQuit=false
        if commands.suspendActivities then commands.suspendActivities() end
        if context.neutralize then context.neutralize() end
        if runtime.player then
            runtime.player.moving=false; runtime.player.velocityX=0; runtime.player.velocityY=0
        end
        ui.checkpointBlocked=true
    end
    local function retry()
        local saved=commands.retryCheckpoint()
        if saved then
            entered=false; ui.checkpointBlocked=false; confirmQuit=false
            ui.optionsOpen=false; ui.escMenuOpen=false
            if context.neutralize then context.neutralize() end
        end
        return saved
    end
    ui.retryCheckpoint=retry
    local function action(index)
        if index==1 then retry()
        elseif index==2 then
            if confirmQuit then confirmQuit=false else ui.optionsOpen=true; selected=1 end
        elseif index==3 then
            if confirmQuit then forceQuit=true; context.requestQuit()
            else confirmQuit=true end
        end
        return true
    end
    local function optionControls()
        local values={}
        local function add(rect) if rect then values[#values+1]=rect end end
        for _,name in ipairs({"optionsBack","optionsAudioTab","optionsAccessTab","optionsControlsTab"}) do add(ui[name]) end
        if runtime.optionsPage=="accessibility" then
            for _,name in ipairs({"accessTextSize","accessHighContrast","accessReducedMotion","accessControlHints","accessTouchFeedback","accessLargeTouchTargets"}) do add(ui[name]) end
        elseif runtime.optionsPage=="controls" then
            for _,name in ipairs({"controlsKeyboardTab","controlsControllerTab","controlsTouchTab","controlsButtonsTab","controlsAxesTab","controlsReset","controlsScrollUp","controlsScrollDown"}) do add(ui[name]) end
            for _,row in ipairs(ui.controlBindingRows or {}) do add(row.rect); add(row.clear) end
        else
            for _,name in ipairs({"musicDown","musicUp","sfxDown","sfxUp","rainDown","rainUp","optionsStation8bit","optionsStationChill","optionsStationVibes","optionsStationRain","optionsFollowRadio","musicPrevious","musicPause","musicNext","musicMute"}) do add(ui[name]) end
        end
        return values
    end
    local function closeOptions()
        ui.optionsOpen=false; ui.escMenuOpen=false; selected=1
        if context.bindings then context.bindings:cancelCapture() end
    end
    local function key(key)
        enter()
        local bindings=context.bindings
        if ui.optionsOpen and bindings and bindings:isCapturing() then
            if key=="escape" then bindings:cancelCapture()
            elseif bindings.capture.device=="key" then bindings:captureKey(key) end
            return true
        end
        if ui.optionsOpen then
            if key=="escape" or key=="acback" then closeOptions(); return true end
            local controls=optionControls()
            if key=="up" or key=="left" then selected=(selected-2)%math.max(1,#controls)+1
            elseif key=="down" or key=="right" then selected=selected%math.max(1,#controls)+1
            elseif key=="return" or key=="kpenter" or key=="space" then
                local rect=controls[selected]
                if rect then ui.handleOptionsMousePressed(rect.x+rect.w/2,rect.y+rect.h/2) end
            elseif ui.handleOptionsKey then ui.handleOptionsKey(key) end
            if not ui.optionsOpen then ui.escMenuOpen=false end
            return true
        end
        if key=="left" or key=="up" then selected=(selected-2)%3+1
        elseif key=="right" or key=="down" then selected=selected%3+1
        elseif key=="return" or key=="kpenter" or key=="space" then action(selected)
        elseif key=="escape" or key=="acback" then confirmQuit=not confirmQuit
        elseif key=="r" then retry() end
        return true
    end
    local function click(x,y)
        enter(); x,y=context.screenToGame(x,y)
        if ui.optionsOpen then
            ui.handleOptionsMousePressed(x,y)
            if not ui.optionsOpen then ui.escMenuOpen=false end
            return true
        end
        for index,rect in ipairs(buttons) do if contains(rect,x,y) then return action(index) end end
        return true
    end
    function application.update(dt)
        if context.serviceSession then context.serviceSession(dt) end
        if not blocked() then
            entered=false; ui.checkpointBlocked=false
            return original.update(dt)
        end
        enter(); context.audio.update()
        return true
    end
    function application.draw(...)
        if not blocked() then return original.draw(...) end
        enter()
        -- Draw no gameplay callbacks during a failed checkpoint: some legacy
        -- views lazily create layouts or mutate presentation-owned sessions.
        local g=love.graphics
        g.push("all"); g.clear(.025,.025,.03,1)
        local ox,oy,sx,sy=Viewport.transform(960,720)
        g.translate(ox,oy); g.scale(sx,sy)
        if ui.optionsOpen and ui.drawOptions then
            ui.drawOptions()
            local rect=optionControls()[selected]
            if rect then g.setColor(1,.8,.35,1); g.setLineWidth(3); g.rectangle("line",rect.x-3,rect.y-3,rect.w+6,rect.h+6,5,5) end
        else
            g.setColor(.12,.10,.08,1); g.rectangle("fill",160,210,640,320,12,12)
            local scale=Accessibility.textScale(runtime.saveData)
            local function text(value,y,height,size)
                g.setColor(1,.94,.78,1)
                Typography.drawText(g,value,185,y,590,height,{scale=size*scale,minScale=.6,align="center",valign="center"})
            end
            text(confirmQuit and "QUIT WITHOUT CONFIRMED SAVE?" or "SAVE NEEDS ATTENTION",232,48,1.1)
            text(confirmQuit and "The latest changes may be lost. You can keep waiting and retry the save."
                or "Saving could not be confirmed. Progress is paused. Retry to save the current campaign.",294,110,.9)
            local labels={"RETRY SAVE",confirmQuit and "KEEP WAITING" or "SETTINGS",confirmQuit and "QUIT UNSAVED" or "QUIT"}
            for index,rect in ipairs(buttons) do
                g.setColor(index==selected and .45 or .22,.24,.15,1); g.rectangle("fill",rect.x,rect.y,rect.w,rect.h,6,6)
                g.setColor(1,.94,.78,1)
                Typography.drawText(g,labels[index],rect.x+8,rect.y,rect.w-16,rect.h,{scale=.8*scale,minScale=.6,align="center",valign="center"})
            end
        end
        g.pop()
    end
    function application.keypressed(value,...)
        if blocked() then return key(value) end
        return original.keypressed(value,...)
    end
    function application.mousepressed(x,y,button,...)
        if blocked() then if button==1 then return click(x,y) end; return true end
        return original.mousepressed(x,y,button,...)
    end
    function application.touchpressed(id,x,y,...)
        if blocked() then return click(x,y) end
        return original.touchpressed(id,x,y,...)
    end
    function application.gamepadpressed(joystick,button,...)
        if not blocked() then return original.gamepadpressed(joystick,button,...) end
        local bindings=context.bindings
        if ui.optionsOpen and bindings and bindings:isCapturing() then
            if bindings.capture.device=="button" then bindings:captureButton(button) end
            return true
        end
        return key(({a="return",b="escape",dpup="up",dpdown="down",dpleft="left",dpright="right",start="escape"})[button])
    end
    function application.gamepadaxis(joystick,axis,value,...)
        if not blocked() then return original.gamepadaxis(joystick,axis,value,...) end
        local bindings=context.bindings
        if ui.optionsOpen and bindings and bindings:isCapturing() and bindings.capture.device=="axis" then bindings:captureAxis(axis,value) end
        return true
    end
    for _,name in ipairs({"keyreleased","mousereleased","mousemoved","touchreleased","touchmoved","wheelmoved","gamepadreleased","textinput"}) do
        local callback=name
        application[callback]=function(...)
            if blocked() then return true end
            if original[callback] then return original[callback](...) end
        end
    end
    function application.focus(focused,...)
        if not blocked() then return original.focus(focused,...) end
        enter(); context.audio.focus(focused)
        if not focused and ui.localPreferences then ui.localPreferences:save() end
        if focused then retry() end
        return true
    end
    function application.quit(...)
        if not blocked() then return original.quit(...) end
        if forceQuit then
            if ui.localPreferences then ui.localPreferences:save() end
            context.audio.shutdown(); return false
        end
        enter(); closeOptions(); confirmQuit=true
        return true -- LÖVE cancels this quit; the player must choose explicitly.
    end
    return application
end
return Host
