local Bindings={}
Bindings.__index=Bindings

local PATH="control-bindings.txt"
local KEY_ACTIONS={
    {id="move_up",label="Move up",group="Movement",token="w",default="w"},
    {id="move_left",label="Move left",group="Movement",token="a",default="a"},
    {id="move_down",label="Move down",group="Movement",token="s",default="s"},
    {id="move_right",label="Move right",group="Movement",token="d",default="d"},
    {id="navigate_up",label="Move / navigate up",group="Movement / menus",token="up",default="up"},
    {id="navigate_left",label="Move / navigate left",group="Movement / menus",token="left",default="left"},
    {id="navigate_down",label="Move / navigate down",group="Movement / menus",token="down",default="down"},
    {id="navigate_right",label="Move / navigate right",group="Movement / menus",token="right",default="right"},
    {id="interact",label="Interact / use",group="World",token="e",default="e"},
    {id="give_guard",label="Give / guard",group="World",token="g",default="g"},
    {id="attack",label="Attack",group="World",token="f",default="f"},
    {id="inventory",label="Inventory",group="World",token="i",default="i"},
    {id="map",label="Map / move",group="World",token="m",default="m"},
    {id="journey",label="Journey log",group="World",token="j",default="j"},
    {id="radio",label="Radio",group="World",token="p",default="p"},
    {id="sprint",label="Sprint / quick transfer",group="World",token="lshift",default="lshift"},
    {id="right_shift",label="Right shift",group="World",token="rshift",default="rshift"},
    {id="zoom_in",label="Zoom in",group="World",token="=",default="="},
    {id="zoom_in_shift",label="Zoom in (shifted)",group="World",token="+",default="+"},
    {id="zoom_out",label="Zoom out",group="World",token="-",default="-"},
    {id="zoom_reset",label="Reset zoom",group="World",token="0",default="0"},
    {id="keypad_zoom_in",label="Zoom in (keypad)",group="World",token="kp+",default="kp+"},
    {id="keypad_zoom_out",label="Zoom out (keypad)",group="World",token="kp-",default="kp-"},
    {id="keypad_zoom_reset",label="Reset zoom (keypad)",group="World",token="kp0",default="kp0"},
    {id="cancel",label="Back / cancel",group="Menus",token="escape",default="escape"},
    {id="confirm",label="Confirm / continue",group="Menus",token="return",default="return"},
    {id="keypad_confirm",label="Confirm (keypad)",group="Menus",token="kpenter",default="kpenter"},
    {id="system_back",label="System back",group="Menus",token="acback",default="acback"},
    {id="action",label="Action / fire / advance",group="World",token="space",default="space"},
    {id="cycle",label="Cycle / setup",group="World",token="tab",default="tab"},
    {id="alternate_back",label="Alternate back / decline",group="Menus",token="q",default="q"},
    {id="reload_retreat",label="Reload / retreat",group="Combat",token="r",default="r"},
    {id="buy_ammo",label="Buy ammunition",group="Combat",token="b",default="b"},
    {id="fire_mode",label="Fire mode",group="Combat",token="v",default="v"},
    {id="accept",label="Accept",group="Menus",token="y",default="y"},
    {id="decline",label="Decline",group="Menus",token="n",default="n"},
    {id="heal",label="Heal",group="Combat",token="h",default="h"},
    {id="cover",label="Take cover",group="Combat",token="c",default="c"},
    {id="loan_ammo",label="Borrow ammunition",group="Combat",token="l",default="l"},
    {id="return_interior",label="Return inside",group="Combat",token="t",default="t"},
    {id="choice_1",label="Choice 1",group="Choices",token="1",default="1"},
    {id="choice_2",label="Choice 2",group="Choices",token="2",default="2"},
    {id="choice_3",label="Choice 3",group="Choices",token="3",default="3"},
    {id="choice_4",label="Choice 4",group="Choices",token="4",default="4"},
    {id="choice_5",label="Choice 5",group="Choices",token="5",default="5"},
    {id="choice_6",label="Choice 6",group="Choices",token="6",default="6"},
    {id="scroll_up",label="Scroll up",group="Menus",token="pageup",default="pageup"},
    {id="scroll_down",label="Scroll down",group="Menus",token="pagedown",default="pagedown"},
}

local BUTTON_ACTIONS={
    {id="move_up",label="Move up",group="Movement",scope="game",token="w",default="dpadup"},
    {id="move_left",label="Move left",group="Movement",scope="game",token="a",default="dpleft"},
    {id="move_down",label="Move down",group="Movement",scope="game",token="s",default="dpdown"},
    {id="move_right",label="Move right",group="Movement",scope="game",token="d",default="dpright"},
    {id="interact",label="Interact / use",group="World",scope="game",token="e",default="a"},
    {id="give_guard",label="Give / guard",group="World",scope="game",token="g",default="rightshoulder"},
    {id="attack",label="Attack",group="World",scope="game",token="f",default="x"},
    {id="inventory",label="Inventory",group="World",scope="game",token="i",default="y"},
    {id="map",label="Map",group="World",scope="game",token="m",default="back"},
    {id="journey",label="Journey log",group="World",scope="game",token="j",default="leftshoulder"},
    {id="game_pause",label="Pause / ESC screen",group="World",scope="game",token="escape",default="start"},
    {id="radio",label="Radio",group="World",scope="game",token="p",default="rightstick"},
    {id="sprint",label="Sprint",group="World",scope="game",token="lshift",default="leftstick"},
    {id="navigate_up",label="Navigate up",group="Menus",scope="menu",token="up",default="dpup"},
    {id="navigate_left",label="Navigate left",group="Menus",scope="menu",token="left",default="dpleft"},
    {id="navigate_down",label="Navigate down",group="Menus",scope="menu",token="down",default="dpdown"},
    {id="navigate_right",label="Navigate right",group="Menus",scope="menu",token="right",default="dpright"},
    {id="confirm",label="Confirm / continue",group="Menus",scope="menu",token="return",default="a"},
    {id="cancel",label="Back / cancel",group="Menus",scope="menu",token="escape",default="b"},
    {id="menu_pause",label="Pause / back",group="Menus",scope="menu",token="escape",default="start"},
    {id="battle_inventory",label="Open inventory",group="Battle",scope="battle",token="i",default="y"},
    {id="battle_heal",label="Heal",group="Battle",scope="battle",token="h",default="x"},
    {id="battle_move",label="Move",group="Battle",scope="battle",token="m",default="leftshoulder"},
    {id="battle_guard",label="Guard",group="Battle",scope="battle",token="g",default="rightshoulder"},
    {id="battle_advance",label="Advance turn / continue",group="Battle",scope="battle",token="space",default="a"},
    {id="battle_retreat",label="Retreat",group="Battle",scope="battle",token="r",default="b"},
    {id="battle_attack_1",label="Attack option 1",group="Battle",scope="battle",token="1",default="dpup"},
    {id="battle_attack_2",label="Attack option 2",group="Battle",scope="battle",token="2",default="dpright"},
    {id="battle_attack_3",label="Attack option 3",group="Battle",scope="battle",token="3",default="dpdown"},
    {id="battle_attack_4",label="Attack option 4",group="Battle",scope="battle",token="4",default="dpleft"},
    {id="battle_attack_5",label="Attack option 5",group="Battle",scope="battle",token="5",default="leftstick"},
    {id="battle_attack_6",label="Attack option 6",group="Battle",scope="battle",token="6",default="rightstick"},
    {id="ls_cancel",label="Cancel / leave scene",group="Last Stand",scope="last_stand",token="escape",default="b"},
    {id="ls_default_action",label="Default scene action",group="Last Stand",scope="last_stand",token="e",default="a"},
    {id="ls_reload",label="Reload",group="Last Stand",scope="last_stand_shootout",token="r",default="x"},
    {id="ls_supply",label="Borrow ammunition",group="Last Stand",scope="last_stand_shootout",token="l",default="y"},
    {id="ls_pause",label="Pause Last Stand",group="Last Stand",scope="last_stand",token="p",default="start"},
    {id="ls_cycle",label="Cycle weapon",group="Last Stand",scope="last_stand_shootout",token="tab",default="back"},
    {id="ls_cover",label="Take cover",group="Last Stand",scope="last_stand_shootout",token="c",default="leftshoulder"},
    {id="ls_fire",label="Fire",group="Last Stand",scope="last_stand_shootout",token="space",default="rightshoulder"},
    {id="ls_fire_mode",label="Fire mode",group="Last Stand",scope="last_stand_shootout",token="v",default="rightstick"},
    {id="ls_offer_accept",label="Accept offer",group="Last Stand",scope="last_stand_offer",token="y",default="a"},
    {id="ls_scene_action",label="Scene action",group="Last Stand",scope="last_stand_world",token="e",default="a"},
    {id="ls_escort_continue",label="Continue escort",group="Last Stand",scope="last_stand_escort",token="space",default="a"},
    {id="ls_treatment_confirm",label="Confirm treatment",group="Last Stand",scope="last_stand_treatment",token="return",default="a"},
}

local AXIS_ACTIONS={
    {id="move_x",label="Movement stick horizontal",group="Movement",default="leftx"},
    {id="move_y",label="Movement stick vertical",group="Movement",default="lefty"},
    {id="aim_x",label="Aim stick horizontal",group="Last Stand",default="rightx"},
    {id="aim_y",label="Aim stick vertical",group="Last Stand",default="righty"},
    {id="ads",label="Aim trigger",group="Last Stand",default="triggerleft"},
    {id="fire",label="Fire trigger",group="Last Stand",default="triggerright"},
}

local buttonNames={a=true,b=true,x=true,y=true,back=true,start=true,guide=true,
    leftstick=true,rightstick=true,leftshoulder=true,rightshoulder=true,
    dpup=true,dpdown=true,dpleft=true,dpright=true}
local axisNames={leftx=true,lefty=true,rightx=true,righty=true,triggerleft=true,triggerright=true}

local function validName(value,set)
    return type(value)=="string" and set[value] and value or nil
end

function Bindings.new(filesystem)
    assert(type(filesystem)=="table","control bindings require the filesystem")
    local self=setmetatable({filesystem=filesystem,keyboard={},buttons={},axes={},capture=nil,notice=nil,controllerHeld={}},Bindings)
    for _,entry in ipairs(KEY_ACTIONS) do self.keyboard[entry.id]=entry.default end
    for _,entry in ipairs(BUTTON_ACTIONS) do self.buttons[entry.id]=entry.default end
    for _,entry in ipairs(AXIS_ACTIONS) do self.axes[entry.id]=entry.default end
    self:load()
    return self
end

function Bindings:keyActions() return KEY_ACTIONS end
function Bindings:buttonActions() return BUTTON_ACTIONS end
function Bindings:axisActions() return AXIS_ACTIONS end

function Bindings:load()
    if not self.filesystem.getInfo(PATH) then return false end
    local source=self.filesystem.read(PATH)
    if type(source)~="string" then return false end
    for line in source:gmatch("[^\r\n]+") do
        local device,id,value=line:match("^(%a+)%s+([%w_]+)%s+(%S+)$")
        if device=="key" then
            for _,entry in ipairs(KEY_ACTIONS) do if entry.id==id then self.keyboard[id]=value~="none" and value or nil end end
        elseif device=="button" then
            for _,entry in ipairs(BUTTON_ACTIONS) do if entry.id==id then self.buttons[id]=validName(value,buttonNames) end end
        elseif device=="axis" then
            for _,entry in ipairs(AXIS_ACTIONS) do if entry.id==id then self.axes[id]=validName(value,axisNames) end end
        end
    end
    return true
end

function Bindings:save()
    local rows={}
    for _,entry in ipairs(KEY_ACTIONS) do rows[#rows+1]="key "..entry.id.." "..(self.keyboard[entry.id] or "none") end
    for _,entry in ipairs(BUTTON_ACTIONS) do rows[#rows+1]="button "..entry.id.." "..(self.buttons[entry.id] or "none") end
    for _,entry in ipairs(AXIS_ACTIONS) do rows[#rows+1]="axis "..entry.id.." "..(self.axes[entry.id] or "none") end
    local ok,message=self.filesystem.write(PATH,table.concat(rows,"\n"))
    if ok then self.notice="Controls saved on this device." else self.notice="Could not save control changes." end
    return ok,message
end

local function keyConflict(self,id,key)
    if not key then return false end
    for _,entry in ipairs(KEY_ACTIONS) do
        if entry.id~=id and self.keyboard[entry.id]==key then return entry end
    end
end

function Bindings:beginCapture(device,id)
    self.capture={device=device,id=id}
    self.notice=device=="key" and "Press a key. Escape cancels." or "Press a controller input. Escape cancels."
end
function Bindings:isCapturing() return self.capture~=nil end
function Bindings:cancelCapture()
    if not self.capture then return false end
    self.capture=nil; self.notice="Remap cancelled."; return true
end
function Bindings:clear(device,id)
    if device=="key" then self.keyboard[id]=nil
    elseif device=="button" then self.buttons[id]=nil
    elseif device=="axis" then self.axes[id]=nil
    else return false end
    self:save(); return true
end
function Bindings:reset(device)
    if device=="key" then for _,entry in ipairs(KEY_ACTIONS) do self.keyboard[entry.id]=entry.default end
    elseif device=="button" then for _,entry in ipairs(BUTTON_ACTIONS) do self.buttons[entry.id]=entry.default end
    elseif device=="axis" then for _,entry in ipairs(AXIS_ACTIONS) do self.axes[entry.id]=entry.default end
    elseif device=="controller" then
        for _,entry in ipairs(BUTTON_ACTIONS) do self.buttons[entry.id]=entry.default end
        for _,entry in ipairs(AXIS_ACTIONS) do self.axes[entry.id]=entry.default end
    else return false end
    self.capture=nil; self.notice="Default controls restored."; self:save(); return true
end

function Bindings:assign(device,id,value)
    if device=="key" then
        local exists=false; for _,entry in ipairs(KEY_ACTIONS) do if entry.id==id then exists=true end end
        if not exists then return false,"Unknown keyboard action." end
        local conflict=keyConflict(self,id,value)
        if conflict then self.notice="That key is already assigned to "..conflict.label.."."; return false,self.notice end
        self.keyboard[id]=value
    elseif device=="button" then
        local selected
        for _,entry in ipairs(BUTTON_ACTIONS) do if entry.id==id then selected=entry end end
        if not selected then return false,"Unknown controller action." end
        value=validName(value,buttonNames)
        if value then
            for _,entry in ipairs(BUTTON_ACTIONS) do
                if entry.id~=id and entry.scope==selected.scope and self.buttons[entry.id]==value then
                    self.notice="That button is already assigned to "..entry.label.."."; return false,self.notice
                end
            end
        end
        self.buttons[id]=value
    elseif device=="axis" then
        local exists=false; for _,entry in ipairs(AXIS_ACTIONS) do if entry.id==id then exists=true end end
        if not exists then return false,"Unknown controller axis." end
        self.axes[id]=validName(value,axisNames)
    else return false,"Unknown control type." end
    self.capture=nil; self.notice="Control updated."; self:save(); return true
end

function Bindings:captureKey(key)
    if not self.capture or self.capture.device~="key" then return false end
    if key=="escape" then return self:cancelCapture() end
    if key=="lctrl" or key=="rctrl" or key=="lalt" or key=="ralt" or key=="lgui" or key=="rgui" then
        self.notice="Choose a key, not a modifier by itself."; return true
    end
    local capture=self.capture
    self:assign("key",capture.id,key)
    return true
end
function Bindings:captureButton(button)
    if not self.capture or self.capture.device~="button" then return false end
    button=validName(button,buttonNames)
    if not button then return true end
    local capture=self.capture; self:assign("button",capture.id,button); return true
end
function Bindings:captureAxis(axis,value)
    if not self.capture or self.capture.device~="axis" then return false end
    axis=validName(axis,axisNames)
    if not axis then return false end
    local threshold=(axis=="triggerleft" or axis=="triggerright") and .45 or .68
    if math.abs(tonumber(value) or 0)<threshold then return true end
    local capture=self.capture; self:assign("axis",capture.id,axis); return true
end

function Bindings:translateKey(key)
    for _,entry in ipairs(KEY_ACTIONS) do if self.keyboard[entry.id]==key then return entry.token end end
    for _,entry in ipairs(KEY_ACTIONS) do if entry.token==key then return nil,true end end
    return key,false
end

function Bindings:translateButton(button,scope)
    for _,entry in ipairs(BUTTON_ACTIONS) do
        if entry.scope==scope and self.buttons[entry.id]==button then return entry.token,entry.id end
    end
    if type(scope)=="string" and scope:match("^last_stand_") then
        for _,entry in ipairs(BUTTON_ACTIONS) do
            if entry.scope=="last_stand" and self.buttons[entry.id]==button then return entry.token,entry.id end
        end
    end
    return nil
end
function Bindings:buttonDown(id)
    local button=self.buttons[id]
    if not button or not love.joystick or not love.joystick.getJoysticks then return false end
    for _,pad in ipairs(love.joystick.getJoysticks()) do
        if pad:isGamepad() and pad:isGamepadDown(button) then return true end
    end
    return false
end
function Bindings:axisValue(id)
    local axis=self.axes[id]
    if not axis or not love.joystick or not love.joystick.getJoysticks then return 0 end
    for _,pad in ipairs(love.joystick.getJoysticks()) do
        if pad:isGamepad() then
            local value=pad:getGamepadAxis(axis)
            return math.abs(value)<.16 and 0 or value
        end
    end
    return 0
end
function Bindings:movement()
    local x=self:axisValue("move_x")+(self:buttonDown("move_right") and 1 or 0)-(self:buttonDown("move_left") and 1 or 0)
    local y=self:axisValue("move_y")+(self:buttonDown("move_down") and 1 or 0)-(self:buttonDown("move_up") and 1 or 0)
    return math.max(-1,math.min(1,x)),math.max(-1,math.min(1,y))
end
function Bindings:actionDown(id)
    if self:buttonDown(id) then return true end
    return false
end
function Bindings:hasGamepad()
    if not love.joystick or not love.joystick.getJoysticks then return false end
    for _,pad in ipairs(love.joystick.getJoysticks()) do if pad:isGamepad() then return true end end
    return false
end

function Bindings:display(device,id)
    local value=device=="key" and self.keyboard[id] or (device=="button" and self.buttons[id] or self.axes[id])
    if not value then return "UNBOUND" end
    if device=="key" then
        local names={lshift="LEFT SHIFT",rshift="RIGHT SHIFT",space="SPACE",escape="ESC",["return"]="ENTER",kpenter="NUMPAD ENTER",
            pageup="PAGE UP",pagedown="PAGE DOWN",up="UP ARROW",down="DOWN ARROW",left="LEFT ARROW",right="RIGHT ARROW",["-"]="-",["="]="="}
        return names[value] or string.upper(value)
    end
    if device=="button" then
        local names={a="A",b="B",x="X",y="Y",back="VIEW / BACK",start="MENU / START",leftstick="L STICK CLICK",
            rightstick="R STICK CLICK",leftshoulder="L BUMPER",rightshoulder="R BUMPER",dpup="D-PAD UP",dpdown="D-PAD DOWN",
            dpleft="D-PAD LEFT",dpright="D-PAD RIGHT"}
        return names[value] or string.upper(value)
    end
    local names={leftx="LEFT STICK X",lefty="LEFT STICK Y",rightx="RIGHT STICK X",righty="RIGHT STICK Y",
        triggerleft="LEFT TRIGGER",triggerright="RIGHT TRIGGER"}
    return names[value] or string.upper(value)
end

function Bindings:installKeyboardQuery()
    if not love.keyboard or not love.keyboard.isDown or love.keyboard._codexControlBindings then return false end
    local original=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        local count=select("#",...)
        for index=1,count do
            local token=select(index,...)
            local physical,knownToken
            for _,entry in ipairs(KEY_ACTIONS) do
                if entry.token==token then physical=self.keyboard[entry.id]; knownToken=true; break end
            end
            if knownToken then
                if physical and original(physical) then return true end
            elseif original(token) then return true end
        end
        return false
    end
    love.keyboard._codexControlBindings=true
    return true
end

Bindings.PATH=PATH
return Bindings
