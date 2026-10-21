local Accessibility={}
local Players=require("game.coop_players")
local bindings=setmetatable({},{__mode="k"})

function Accessibility.bind(data,settings,mode)
    bindings[data]={settings=settings,mode=mode}
end

Accessibility.version=1
Accessibility.textSizes={1,1.15,1.30}
Accessibility.defaults={
    textSize=1,
    highContrast=false,
    reducedMotion=false,
    controlHints=true,
    touchFeedback=true,
    largeTouchTargets=true,
    aimAssist=.35,
    aimSensitivity=1,
}

local aimLimits={aimAssist={0,1},aimSensitivity={.5,2}}
local function aimValue(name,value)
    local limits=aimLimits[name]
    if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then
        return Accessibility.defaults[name]
    end
    return math.max(limits[1],math.min(limits[2],value))
end

local function boolean(value,default)
    if type(value)=="boolean" then return value end
    return default
end

function Accessibility.ensure(data)
    data=data or {}
    local binding=bindings[Players.campaignOf(data)]
    local settings=binding and binding.settings or type(data.accessibility)=="table" and data.accessibility or {}
    if not binding and not (data.coop and data.coop.preferencesDetached) then data.accessibility=settings end
    settings.version=Accessibility.version
    settings.textSize=math.max(1,math.min(#Accessibility.textSizes,math.floor(tonumber(settings.textSize) or Accessibility.defaults.textSize)))
    for _,name in ipairs({"highContrast","reducedMotion","controlHints","touchFeedback","largeTouchTargets"}) do
        settings[name]=boolean(settings[name],Accessibility.defaults[name])
    end
    for name in pairs(aimLimits) do settings[name]=aimValue(name,settings[name]) end
    return settings
end

function Accessibility.aimSettings(data)
    local settings=Accessibility.ensure(data)
    return {aimAssist=settings.aimAssist,aimSensitivity=settings.aimSensitivity}
end

function Accessibility.adjustAim(data,name,delta)
    assert(aimLimits[name],"unknown aiming preference "..tostring(name))
    local settings=Accessibility.ensure(data)
    settings[name]=aimValue(name,math.floor((settings[name]+delta)*100+.5)/100)
    return settings[name]
end

function Accessibility.aimLabel(data,name)
    local value=Accessibility.aimSettings(data)[name]
    if name=="aimAssist" then return value==0 and "OFF" or (math.floor(value*100+.5).."%") end
    return string.format("%.1fx",value)
end

function Accessibility.textScale(data)
    local settings=Accessibility.ensure(data)
    return Accessibility.textSizes[settings.textSize] or 1
end

function Accessibility.textLabel(data)
    return ({"NORMAL","LARGE","EXTRA LARGE"})[Accessibility.ensure(data).textSize]
end

function Accessibility.cycleTextSize(data)
    local settings=Accessibility.ensure(data)
    settings.textSize=settings.textSize%#Accessibility.textSizes+1
    return settings.textSize,Accessibility.textLabel(data)
end

function Accessibility.toggle(data,name)
    assert(type(Accessibility.defaults[name])=="boolean","unknown accessibility toggle "..tostring(name))
    local settings=Accessibility.ensure(data)
    settings[name]=not settings[name]
    return settings[name]
end

function Accessibility.enabled(data,name)
    return Accessibility.ensure(data)[name]==true
end

function Accessibility.motionSpeed(data)
    local binding=bindings[Players.campaignOf(data)]
    if binding and binding.mode and binding.mode()~="offline" then return 1 end
    return Accessibility.enabled(data,"reducedMotion") and 4 or 1
end

function Accessibility.touchProfile(data)
    local large=Accessibility.enabled(data,"largeTouchTargets")
    return large and {joystick=82,knob=34,primary=58,secondary=44,barHeight=70}
        or {joystick=70,knob=28,primary=50,secondary=36,barHeight=62}
end

function Accessibility.audit()
    local data={}
    local settings=Accessibility.ensure(data)
    local defaults=settings.controlHints and settings.touchFeedback and settings.largeTouchTargets and not settings.highContrast and not settings.reducedMotion
    Accessibility.cycleTextSize(data); Accessibility.toggle(data,"highContrast"); Accessibility.toggle(data,"reducedMotion")
    local profile=Accessibility.touchProfile(data)
    return {ready=defaults and Accessibility.textScale(data)>1 and settings.highContrast and settings.reducedMotion
            and Accessibility.motionSpeed(data)==4 and profile.primary>=58,
        textLabel=Accessibility.textLabel(data),motionSpeed=Accessibility.motionSpeed(data),touchRadius=profile.primary,
        curve="accessibility-mobile-v1"}
end

return Accessibility
