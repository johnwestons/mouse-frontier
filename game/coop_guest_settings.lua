-- Device-only guest settings. No campaign writer or gameplay command is available.
local Preferences=require('game.local_preferences')
local Accessibility=require('game.accessibility')
local Bindings=require('game.control_bindings')
local Layout=require('game.control_layout')
local Focus=require('game.ui_focus')
local Style=require('game.ui_layout')
local Typography=require('game.typography')
local Viewport=require('game.viewport')
local Settings={}; Settings.__index=Settings
local bounds={x=30,y=20,w=900,h=680}
local canvas={x=70,y=230,w=820,h=300}
local function clamp(n,low,high) return math.max(low,math.min(high,n)) end
local function contains(r,x,y) return r and x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
local function bindingRecords(binding)
    local result={}
    for _,group in ipairs({{'key',binding:keyActions(),binding.keyboard},{'button',binding:buttonActions(),binding.buttons},{'axis',binding:axisActions(),binding.axes}}) do
        for _,entry in ipairs(group[2]) do result[group[1]..':'..entry.id]=group[3][entry.id] or 'none' end
    end
    return result
end
local function checkedBindings(binding)
    local ok,text=pcall(binding.filesystem.read,Bindings.PATH)
    if not ok or type(text)~='string' then return false end
    local expected=bindingRecords(binding)
    for line in text:gmatch('[^\r\n]+') do
        local device,id,value=line:match('^(%a+)%s+([%w_]+)%s+(%S+)$')
        local key=device and device..':'..id
        if not key or expected[key]~=value then return false end
        expected[key]=nil
    end
    return next(expected)==nil
end
function Settings.new(view,c)
    local self=setmetatable({view=view,c=c,preferences=assert(c.preferences),bindings=assert(c.bindings),
        filesystem=assert(c.filesystem or love and love.filesystem),page='audio',device='keyboard',section='buttons',
        scroll=0,controls={},ui={},pressedKeys={},pressedButtons={},empty={},touches={}},Settings)
    self.preferences:bind(self.empty,function() return 'client' end)
    return self
end
function Settings:data() return self.c.data and self.c.data() or self.view.runtime.saveData or self.empty end
function Settings:values() return Preferences.view(self:data()) end
function Settings:mobile() return self.c.mobile and self.c.mobile() or self.view.mobile end
function Settings:isOpen() return self.opened==true end
function Settings:resetInput()
    self.pressedKeys={}; self.pressedButtons={}; self.drag=nil; self.owner=nil; self.mouseOwner=false; self.touches={}
    self.view:neutralize()
end
function Settings:open()
    if not self.view.ready then return false end
    self.view.controller:open() -- Retain the existing checked private-menu pause.
    self.opened=true; self.notice=self.bindingsDirty and 'Control changes could not be saved. Close to retry.'
        or self.layoutDirty and 'Touch controls could not be saved. Try SAVE again.' or nil
    self.controls={}; self.ui={}; self:resetInput()
    return true
end
function Settings:savePreferences()
    local ok,value=pcall(self.preferences.save,self.preferences,true)
    self.preferencesDirty=not (ok and value==true)
    if self.preferencesDirty then self.notice=self.preferences.lastError or 'Device settings could not be saved. Close to retry.' end
    return not self.preferencesDirty
end
function Settings:saveBindings()
    local ok,value=pcall(self.bindings.save,self.bindings)
    self.bindingsDirty=not (ok and value==true and checkedBindings(self.bindings))
    if self.bindingsDirty then self.notice='Control changes could not be saved. Close to retry.' end
    return not self.bindingsDirty
end
function Settings:close()
    self.bindings:cancelCapture()
    if self.preferencesDirty then self:savePreferences() end
    if self.bindingsDirty then self:saveBindings() end
    if self.layoutDirty then self:saveTouch() end
    self.opened=false; self.controls={}; self.ui={}; self:resetInput()
    -- Closing returns to Local Play; it does not resume held gameplay input.
    return true
end
function Settings:release() self:close() end
function Settings:focus(focused)
    if not focused then self.bindings:cancelCapture(); self:resetInput() end
    return self.opened==true
end
function Settings:update()
    if not self.opened then return end
    if not self.view.controller.menuOpen then self:close(); return end
    local epoch=self.view.epoch
    if self.epoch~=epoch or self.view.focused==false then self.epoch=epoch; self.bindings:cancelCapture(); self:resetInput() end
end
function Settings:audio(action,value)
    local data=self:data(); local audio=self:values().audio
    if action=='musicVolume' or action=='sfxVolume' or action=='rainVolume' then audio[action]=clamp(audio[action]+value,0,1)
    elseif action=='station' then audio.station=value; if self.c.audio then self.c.audio.resetMusic() end
    elseif action=='rainEnabled' then audio.rainEnabled=not audio.rainEnabled; if self.c.audio then self.c.audio.resetMusic() end
    elseif action=='follow' then Preferences.followRadio(data); if self.c.audio then self.c.audio.resetMusic() end
    elseif self.c.audio and self.c.audio[action] then self.c.audio[action](self.view.runtime)
    else return false end
    self.notice=nil; return self:savePreferences()
end
function Settings:accessibility(key,delta)
    if key=='textSize' then Accessibility.cycleTextSize(self:values())
    elseif key=='aimAssist' or key=='aimSensitivity' then Accessibility.adjustAim(self:values(),key,delta)
    else Accessibility.toggle(self:values(),key) end
    self.notice=nil; return self:savePreferences()
end
function Settings:beginCapture(device,id)
    self:resetInput(); self.bindings:beginCapture(device,id); self.notice=nil
end
function Settings:bindingChange(kind,device,id)
    self:resetInput()
    if kind=='clear' then pcall(self.bindings.clear,self.bindings,device,id) else pcall(self.bindings.reset,self.bindings,device) end
    self.notice=nil; return self:saveBindings()
end
function Settings:list()
    if self.device=='keyboard' then return self.bindings:keyActions(),'key' end
    if self.section=='axes' then return self.bindings:axisActions(),'axis' end
    return self.bindings:buttonActions(),'button'
end
function Settings:touchLayout()
    local mobile=self:mobile()
    if not self.layout then self.layout=Layout.normalize(mobile and mobile:layout() or Layout.load(self.filesystem)); self.layout.opacity=self.layout.opacity or .8 end
    return self.layout
end
function Settings:saveTouch()
    if not self.layout then return false end
    local ok,value=pcall(Layout.save,self.filesystem,self.layout)
    local readOk,restored=false,nil
    if ok and value==true then readOk,restored=pcall(Layout.load,self.filesystem) end
    local valid=readOk and type(restored)=='table'
    if valid then for _,id in ipairs(Layout.order) do for _,axis in ipairs({'x','y'}) do
        valid=valid and math.abs(restored[id][axis]-self.layout[id][axis])<=.000001
    end end; valid=valid and math.abs((restored.opacity or .8)-(self.layout.opacity or .8))<=.000001 end
    self.layoutDirty=not valid
    if not valid then self.notice='Touch controls could not be saved. Try SAVE again.'; return false end
    local mobile=self:mobile(); if mobile then mobile:setLayout(restored); mobile:setOpacity(restored.opacity or .8) end
    self.notice='Touch controls saved on this device.'; return true
end
function Settings:touchChange(id,dx,dy)
    local layout=self:touchLayout(); self.selectedControl=id or self.selectedControl or 'joystick'
    if dx=='opacity' then layout.opacity=clamp(layout.opacity+dy,Layout.MIN_OPACITY,Layout.MAX_OPACITY)
    else local p=layout[self.selectedControl]; p.x=clamp(p.x+dx,.1,.9); p.y=clamp(p.y+dy,.08,.9) end
    self.layoutDirty=true; return self:saveTouch()
end
function Settings:resetTouch()
    self.layout=Layout.normalize(); self.layout.opacity=.8; self.layoutDirty=true; return self:saveTouch()
end
-- Physical gameplay events are translated once by the outer guest router.
-- Remember press tokens so a changed binding cannot strand a held action.
function Settings:translateGameplayKey(key,released)
    if released then local token=self.pressedKeys[key]; self.pressedKeys[key]=nil
        if token then return token,false end
        return self.bindings:translateKey(key)
    end
    local token,known=self.bindings:translateKey(key)
    if token then self.pressedKeys[key]=token end
    return token,known
end
function Settings:translateGameplayButton(button,scope,released)
    if released then local token=self.pressedButtons[button]; self.pressedButtons[button]=nil; return token end
    local token=self.bindings:translateButton(button,scope); self.pressedButtons[button]=token; return token
end
function Settings:targets() return self.controls end
function Settings:screenKey() return 'guest-settings:'..self.page..':'..self.device..':'..self.section end
function Settings:keypressed(key,translated)
    if not self.opened then return false end
    if self.bindings:isCapturing() then
        if key=='escape' or key=='acback' or key=='f8' then self.bindings:cancelCapture()
        elseif self.bindings.capture.device=='key' then local ok=pcall(self.bindings.captureKey,self.bindings,key)
            if not ok or not self.bindings:isCapturing() then self:saveBindings() end end
        return true
    end
    if key=='escape' or key=='acback' or key=='f8' then return self:close() end
    if not translated then local mapped,known=self.bindings:translateKey(key)
        if known and not mapped then return true end; key=mapped
    end
    if key=='pageup' or key=='pagedown' then self:wheel(key=='pageup' and 1 or -1); return true end
    if key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        Focus.move(self.ui,self.controls,self:screenKey(),key,love.keyboard and love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then
        local target=Focus.current(self.ui,self.controls,self:screenKey()); if target and target.enabled~=false then target.action() end
    end
    return true
end
function Settings:keyreleased() return self.opened==true end
function Settings:gamepadpressed(button)
    if not self.opened then return false end
    if self.bindings:isCapturing() then
        if self.bindings.capture.device=='button' then local ok=pcall(self.bindings.captureButton,self.bindings,button)
            if not ok or not self.bindings:isCapturing() then self:saveBindings() end end
        return true
    end
    if button=='start' or button=='back' then return self:close() end
    local key=self.bindings:translateButton(button,'menu'); if key then self:keypressed(key,true) end; return true
end
function Settings:gamepadreleased() return self.opened==true end
function Settings:gamepadaxis(axis,value)
    if not self.opened then return false end
    if self.bindings:isCapturing() and self.bindings.capture.device=='axis' then
        local ok=pcall(self.bindings.captureAxis,self.bindings,axis,value)
        if not ok or not self.bindings:isCapturing() then self:saveBindings() end
    end
    return true
end
function Settings:wheel(y)
    if not self.opened then return false end
    if self.page=='controls' and self.device~='touch' then local list=self:list(); self.scroll=clamp(self.scroll+(y>0 and -8 or 8),0,math.max(0,#list-8)) end
    return true
end
function Settings:wheelmoved(_,y) return self:wheel(y) end
function Settings:point(x,y)
    for _,target in ipairs(self.controls) do if contains(target.rect,x,y) then
        self.ui.keyboardFocusId=target.id; self.ui.keyboardFocusVisible=false
        if target.enabled~=false then target.action() end; return true
    end end
    if self.page=='controls' and self.device=='touch' then
        local px,py=Style.inversePoint(x,y,'guest-settings',bounds)
        for _,id in ipairs(Layout.order) do local p=self:touchLayout()[id]
            if math.abs(px-canvas.x-p.x*canvas.w)<42 and math.abs(py-canvas.y-p.y*canvas.h)<25 then self.selectedControl=id; self.drag=id; return true end
        end
    end
    return true
end
function Settings:move(x,y)
    if self.drag then local px,py=Style.inversePoint(x,y,'guest-settings',bounds); local p=self:touchLayout()[self.drag]
        p.x=clamp((px-canvas.x)/canvas.w,.1,.9); p.y=clamp((py-canvas.y)/canvas.h,.08,.9); self.layoutDirty=true
    end
    return true
end
function Settings:finishDrag() if self.drag then self.drag=nil; self:saveTouch() end end
function Settings:pointer(x,y,button)
    if not self.opened then return false end
    if button==1 and not self.owner then self.mouseOwner=true; self:point(x,y) end; return true
end
function Settings:mousemoved(x,y) if not self.opened then return false end; if self.mouseOwner then self:move(x,y) end; return true end
function Settings:mousereleased(button) if not self.opened then return false end; if button==1 and self.mouseOwner then self.mouseOwner=false; self:finishDrag() end; return true end
function Settings:touchpressed(id,x,y)
    if not self.opened then return false end
    self.touches[id]=true
    if not self.owner and not self.mouseOwner then self.owner=id; self:point(x,y) end; return true
end
function Settings:touchmoved(id,x,y) if not self.opened then return false end; if id==self.owner then self:move(x,y) end; return true end
function Settings:touchreleased(id)
    if not self.opened then return false end
    self.touches[id]=nil; if id==self.owner then self.owner=nil; self:finishDrag() end; return true
end
function Settings:draw()
    if not self.opened then return false end
    local g=love.graphics; self.controls={}; local settings=self:values()
    local function text(value,x,y,w,h,scale)
        g.setColor(1,.93,.78,1); Typography.drawText(g,value,x,y,w,h,{scale=(scale or 1)*Accessibility.textScale(settings),minScale=.62,align='left',valign='center'})
    end
    local function add(id,label,x,y,w,action,enabled,h)
        h=h or 44; g.setColor(enabled==false and .12 or .23,.17,.09,1); g.rectangle('fill',x,y,w,h,6,6)
        g.setColor(.84,.65,.32,1); g.rectangle('line',x,y,w,h,6,6)
        text(label,x+8,y+3,w-16,h-6,.8)
        self.controls[#self.controls+1]={id=id,rect=Style.transformRect({x=x,y=y,w=w,h=h}),action=action,enabled=enabled~=false}
    end
    g.push('all'); g.origin(); local ox,oy,sx,sy=Viewport.transform(960,720); g.translate(ox,oy); g.scale(sx,sy)
    g.clear(.045,.035,.025,1); g.setFont(Typography.font(g))
    Style.scope('guest-settings',bounds,function()
        g.setColor(.075,.055,.035,1); g.rectangle('fill',bounds.x,bounds.y,bounds.w,bounds.h,9,9)
        text('DEVICE SETTINGS',60,36,590,40,1.2); add('close','BACK TO LOCAL PLAY',690,36,210,function() self:close() end)
        for i,page in ipairs({'audio','accessibility','controls'}) do local chosen=page
            add(page,page:upper(),60+(i-1)*285,94,270,function() self.page=chosen; self.scroll=0; self.ui={} end)
        end
        if self.page=='audio' then
            for i,entry in ipairs({{'musicVolume','MUSIC'},{'sfxVolume','SOUND FX'},{'rainVolume','RAIN'}}) do
                local key=entry[1]; local y=165+(i-1)*64
                text(entry[2]..'  '..math.floor(settings.audio[key]*100)..'%',80,y,430,44)
                add(key..'-','-',560,y,140,function() self:audio(key,-.05) end)
                add(key..'+','+',720,y,140,function() self:audio(key,.05) end)
            end
            for i,id in ipairs({'8bit','chill','vibes'}) do local station=id
                add('station-'..id,id:upper(),80+(i-1)*260,373,245,function() self:audio('station',station) end)
            end
            add('rain','RAIN '..(settings.audio.rainEnabled and 'ON' or 'OFF'),80,432,245,function() self:audio('rainEnabled') end)
            add('follow','FOLLOW SHARED RADIO',340,432,505,function() self:audio('follow') end)
            for i,entry in ipairs({{'previousTrack','PREV'},{'togglePause',settings.audio.musicPaused and 'PLAY' or 'PAUSE'},
                {'nextTrack','NEXT'},{'toggleMute',settings.audio.musicMuted and 'UNMUTE' or 'MUTE'}}) do local action=entry[1]
                add(action,entry[2],80+(i-1)*195,496,180,function() self:audio(action) end)
            end
            text('Personal station: '..settings.audio.station..'. Volume and playback apply to this device.',80,558,765,64,.83)
        elseif self.page=='accessibility' then
            local access=Accessibility.ensure(settings)
            for i,entry in ipairs({{'textSize','TEXT SIZE',Accessibility.textLabel(settings)},{'highContrast','HIGH CONTRAST'},
                {'reducedMotion','REDUCED MOTION'},{'controlHints','CONTROL HINTS'},{'touchFeedback','TOUCH FEEDBACK'},{'largeTouchTargets','LARGE TOUCH TARGETS'}}) do
                local key=entry[1]; local y=150+(i-1)*49; text(entry[2],80,y,485,44,.94)
                add(key,entry[3] or (access[key] and 'ON' or 'OFF'),625,y,220,function() self:accessibility(key) end,true,44)
            end
            for i,entry in ipairs({{'aimSensitivity','TOUCH AIM SPEED',.1},{'aimAssist','TOUCH AIM ASSIST',.05}}) do
                local key,step=entry[1],entry[3]; local y=453+(i-1)*58
                text(entry[2]..'  '..Accessibility.aimLabel(settings,key),80,y,485,48,.94)
                add(key..'-','-',625,y,100,function() self:accessibility(key,-step) end,true,48)
                add(key..'+','+',745,y,100,function() self:accessibility(key,step) end,true,48)
            end
            text('Aim assist gently pulls the touch reticle toward nearby targets. Set it to OFF for manual aim.',80,574,765,64,.83)
        else
            for i,id in ipairs({'keyboard','controller','touch'}) do local device=id
                add('device-'..id,id=='touch' and 'TOUCH LAYOUT' or id:upper(),70+(i-1)*280,151,265,function() self.device=device; self.scroll=0; self.ui={}; self.bindings:cancelCapture() end)
            end
            if self.device=='touch' then
                local layout=self:touchLayout(); text('Drag a control. Positions and opacity save on this device.',75,202,805,28,.8)
                g.setColor(.11,.105,.075,1); g.rectangle('fill',canvas.x,canvas.y,canvas.w,canvas.h,6,6)
                for _,id in ipairs(Layout.order) do local p=layout[id]; local x,y=canvas.x+p.x*canvas.w,canvas.y+p.y*canvas.h
                    g.setColor(id==self.selectedControl and .48 or .28,.25,.12,layout.opacity); g.rectangle('fill',x-42,y-23,84,46,5,5)
                    text(Layout.labels[id],x-36,y-18,72,36,.7)
                end
                local selected=self.selectedControl or 'joystick'; text('Selected: '..Layout.labels[selected],75,540,310,32,.8)
                for i,entry in ipairs({{'left',-.02,0},{'right',.02,0},{'up',0,-.02},{'down',0,.02}}) do local dx,dy=entry[2],entry[3]
                    add(entry[1],entry[1]:upper(),75+(i-1)*195,579,180,function() self:touchChange(selected,dx,dy) end)
                end
                add('opacity-','OPACITY -',75,631,180,function() self:touchChange(nil,'opacity',-.05) end,true,38)
                add('opacity+','OPACITY +',270,631,180,function() self:touchChange(nil,'opacity',.05) end,true,38)
                add('reset-touch','RESET POSITIONS',465,631,180,function() self:resetTouch() end,true,38)
                add('save-touch','SAVE',660,631,180,function() self:saveTouch() end,true,38)
            else
                if self.device=='controller' then
                    add('buttons','BUTTONS',70,200,270,function() self.section='buttons'; self.scroll=0 end,true,36)
                    add('axes','STICKS / TRIGGERS',350,200,270,function() self.section='axes'; self.scroll=0 end,true,36)
                end
                local list,device=self:list(); self.scroll=clamp(self.scroll,0,math.max(0,#list-8))
                for row=1,8 do local entry=list[self.scroll+row]
                    if entry then local id=entry.id; local y=246+(row-1)*43
                        local label=self.c.bindingLabel and self.c.bindingLabel(entry,device) or entry.label
                        text(label,75,y,470,38,.78)
                        add('bind-'..id,self.bindings:display(device,id),560,y,210,function() self:beginCapture(device,id) end,true,38)
                        add('clear-'..id,'CLEAR',780,y,100,function() self:bindingChange('clear',device,id) end,true,38)
                    end
                end
                add('up','UP',70,598,145,function() self.scroll=math.max(0,self.scroll-8) end,self.scroll>0)
                add('down','DOWN',230,598,145,function() self.scroll=math.min(math.max(0,#list-8),self.scroll+8) end,self.scroll+8<#list)
                add('reset','RESET DEFAULTS',590,598,290,function() self:bindingChange('reset',device) end)
                text(self.bindings:isCapturing() and 'Press the new physical input. ESC cancels capture.'
                    or self.bindings.notice or 'Select a binding, then press its new input.',75,648,800,30,.65)
            end
        end
        if self.page~='controls' or self.device~='touch' then
            text(self.notice or self.preferences.lastError or 'Settings save on this device. The host journey is unchanged.',60,664,830,26,.66)
        elseif self.notice then text(self.notice,390,540,470,32,.67) end
    end)
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self.controls,self:screenKey())) end
    g.pop(); return true
end
return Settings
