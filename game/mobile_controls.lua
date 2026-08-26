local MobileControls = {}
MobileControls.__index = MobileControls
local Accessibility=require("game.accessibility")

local function distance(x1,y1,x2,y2)
    local dx,dy=x1-x2,y1-y2
    return math.sqrt(dx*dx+dy*dy)
end

local function defaultEnabled()
    if os.getenv("MOUSE_FRONTIER_MOBILE")=="1" then return true end
    return love and love.system and love.system.getOS and love.system.getOS()=="Android"
end

function MobileControls.new(options)
    options=options or {}
    local self=setmetatable({},MobileControls)
    self.enabled=options.enabled
    if self.enabled==nil then self.enabled=defaultEnabled() end
    self.width=options.width or 960
    self.height=options.height or 720
    self.toGame=assert(options.toGame,"mobile controls require toGame")
    self.pressKey=assert(options.pressKey,"mobile controls require pressKey")
    self.releaseKey=assert(options.releaseKey,"mobile controls require releaseKey")
    self.pressPointer=assert(options.pressPointer,"mobile controls require pressPointer")
    self.movePointer=assert(options.movePointer,"mobile controls require movePointer")
    self.releasePointer=assert(options.releasePointer,"mobile controls require releasePointer")
    self.gameplayActive=options.gameplayActive or function() return false end
    self.primaryAction=options.primaryAction or function() return "e","USE" end
    self.secondaryAction=options.secondaryAction or function() return nil end
    self.getZoom=options.getZoom or function() return 1 end
    self.setZoom=options.setZoom or function() end
    self.beginCameraPan=options.beginCameraPan or function() end
    self.moveCameraPan=options.moveCameraPan or function() end
    self.endCameraPan=options.endCameraPan or function() end
    self.cameraGesturesActive=options.cameraGesturesActive or function() return true end
    self.backVisible=options.backVisible or function() return false end
    self.backLabel=options.backLabel or function() return "BACK" end
    self.menuVisible=options.menuVisible or function() return false end
    self.menuLabel=options.menuLabel or function() return "MENU" end
    self.menuAction=options.menuAction or function() end
    self.accessibilityData=options.accessibilityData or function() return {} end
    self.touches={}
    self.axisX,self.axisY=0,0
    self.lastPointerX,self.lastPointerY=nil,nil
    self.joystick={x=116,y=self.height-116,radius=76,knob=30}
    self.primary={x=self.width-105,y=self.height-105,radius=52}
    self.secondary={x=self.width-218,y=self.height-72,radius=38}
    self.back={x=22,y=68,w=126,h=66}
    self.menu={x=self.width-166,y=68,w=144,h=66}
    self.feedback=nil
    return self
end

function MobileControls:isEnabled() return self.enabled end

function MobileControls:isGameplayActive()
    return self.enabled and self.gameplayActive()
end

function MobileControls:ignoreSyntheticMouse(isTouch)
    return self.enabled and isTouch==true
end

function MobileControls:_updateCornerLayout()
    if not self.enabled or not love or not love.graphics then return end
    local profile=Accessibility.touchProfile(self.accessibilityData())
    self.joystick.radius,self.joystick.knob=profile.joystick,profile.knob
    self.primary.radius,self.secondary.radius=profile.primary,profile.secondary
    self.back.h,self.menu.h=profile.barHeight,profile.barHeight
    local windowWidth,windowHeight=love.graphics.getDimensions()
    local left,top=self.toGame(0,0)
    local right,bottom=self.toGame(windowWidth,windowHeight)
    -- Anchor thumb controls to the actual phone edges rather than the centered
    -- 960-wide game canvas. Wide phones otherwise pull both controls inward.
    self.joystick.x=left+self.joystick.radius+24
    self.joystick.y=bottom-self.joystick.radius-20
    self.primary.x=right-self.primary.radius-24
    self.primary.y=bottom-self.primary.radius-24
    self.secondary.x=self.primary.x-self.primary.radius-self.secondary.radius-24
    self.secondary.y=bottom-self.secondary.radius-22
end

function MobileControls:_feedback(x,y)
    if not Accessibility.enabled(self.accessibilityData(),"touchFeedback") then return end
    local now=love and love.timer and love.timer.getTime and love.timer.getTime() or 0
    self.feedback={x=x,y=y,time=now}
    if love and love.system and love.system.vibrate then pcall(love.system.vibrate,.025) end
end

function MobileControls:_updateJoystick(x,y)
    local stick=self.joystick
    local dx,dy=x-stick.x,y-stick.y
    local length=math.sqrt(dx*dx+dy*dy)
    local magnitude=math.min(1,length/stick.radius)
    if length<stick.radius*.16 then
        self.axisX,self.axisY=0,0
    elseif length>0 then
        self.axisX,self.axisY=dx/length*magnitude,dy/length*magnitude
    end
end

function MobileControls:movement() return self.axisX,self.axisY end

function MobileControls:isSprinting()
    return math.sqrt(self.axisX*self.axisX+self.axisY*self.axisY)>=.88
end

function MobileControls:isHeld(key)
    for _,touch in pairs(self.touches) do if touch.key==key then return true end end
    return false
end

function MobileControls:pointer(fallbackX,fallbackY)
    if self.enabled and self.lastPointerX then return self.lastPointerX,self.lastPointerY end
    return fallbackX,fallbackY
end

function MobileControls:_registerCanvasPointer(id,x,y)
    self.touches[id]={kind="canvasPointer",x=x,y=y,startX=x,startY=y}
    if not self.cameraGesturesActive() then return true end
    local firstId,first
    for otherId,other in pairs(self.touches) do
        if otherId~=id and other.kind=="canvasPointer" then firstId,first=otherId,other; break end
    end
    if first then
        local midX,midY=(first.x+x)/2,(first.y+y)/2
        self.pinch={first=firstId,second=id,startDistance=math.max(1,distance(first.x,first.y,x,y)),
            startZoom=self.getZoom(),midX=midX,midY=midY}
        first.pinching=true; self.touches[id].pinching=true
        self.beginCameraPan(midX,midY)
    end
    return true
end

function MobileControls:touchpressed(id,x,y)
    if not self.enabled then return false end
    self:_updateCornerLayout()
    self.lastPointerX,self.lastPointerY=x,y
    local gx,gy=self.toGame(x,y)
    if self.backVisible() and gx>=self.back.x and gx<=self.back.x+self.back.w and gy>=self.back.y and gy<=self.back.y+self.back.h then
        self:_feedback(gx,gy); self.touches[id]={kind="key",key="escape"}; self.pressKey("escape"); return true
    end
    if self.menuVisible() and gx>=self.menu.x and gx<=self.menu.x+self.menu.w and gy>=self.menu.y and gy<=self.menu.y+self.menu.h then
        self:_feedback(gx,gy); self.touches[id]={kind="menu"}; self.menuAction(); return true
    end
    if self:isGameplayActive() then
        local stick=self.joystick
        if not self.joystickTouch and gx<stick.x+stick.radius*1.7 and gy>stick.y-stick.radius*1.7 then
            self.joystickTouch=id
            self.touches[id]={kind="joystick"}
            self:_updateJoystick(gx,gy)
            return true
        end
        if distance(gx,gy,self.primary.x,self.primary.y)<=self.primary.radius*1.2 then
            local key=self.primaryAction()
            if key then self:_feedback(gx,gy); self.touches[id]={kind="key",key=key}; self.pressKey(key); return true end
        end
        local secondaryKey=self.secondaryAction()
        if secondaryKey and distance(gx,gy,self.secondary.x,self.secondary.y)<=self.secondary.radius*1.2 then
            self:_feedback(gx,gy); self.touches[id]={kind="key",key=secondaryKey}; self.pressKey(secondaryKey); return true
        end
        -- Canvas taps are deferred until release. This leaves the first touch
        -- available to become a camera gesture without activating the surface.
        return self:_registerCanvasPointer(id,x,y)
    end
    return self:_registerCanvasPointer(id,x,y)
end

function MobileControls:touchmoved(id,x,y,dx,dy)
    if not self.enabled then return false end
    self.lastPointerX,self.lastPointerY=x,y
    local touch=self.touches[id]
    if not touch then return false end
    if touch.kind=="joystick" then
        local gx,gy=self.toGame(x,y)
        self:_updateJoystick(gx,gy)
    elseif touch.kind=="canvasPointer" then
        touch.x,touch.y=x,y
        if self.pinch then
            local a,b=self.touches[self.pinch.first],self.touches[self.pinch.second]
            if a and b then
                local midX,midY=(a.x+b.x)/2,(a.y+b.y)/2
                self.setZoom(self.pinch.startZoom*distance(a.x,a.y,b.x,b.y)/self.pinch.startDistance,midX,midY)
                self.moveCameraPan(midX,midY)
                self.pinch.midX,self.pinch.midY=midX,midY
            end
        elseif not touch.pinching and distance(touch.startX,touch.startY,x,y)>14 then
            if not touch.pressed then self.pressPointer(touch.startX,touch.startY,1); touch.pressed=true end
            self.movePointer(x,y,dx or 0,dy or 0)
        end
    end
    return true
end

function MobileControls:touchreleased(id,x,y)
    if not self.enabled then return false end
    self.lastPointerX,self.lastPointerY=x,y
    local touch=self.touches[id]
    if not touch then return false end
    if touch.kind=="joystick" then
        if self.joystickTouch==id then self.joystickTouch=nil; self.axisX,self.axisY=0,0 end
    elseif touch.kind=="key" then self.releaseKey(touch.key)
    elseif touch.kind=="canvasPointer" then
        if touch.pressed then self.releasePointer(x,y,1)
        elseif not touch.pinching then local gx,gy=self.toGame(x,y); self:_feedback(gx,gy); self.pressPointer(x,y,1); self.releasePointer(x,y,1) end
    end
    self.touches[id]=nil
    if self.pinch and (self.pinch.first==id or self.pinch.second==id) then
        local otherId=self.pinch.first==id and self.pinch.second or self.pinch.first
        if self.touches[otherId] then self.touches[otherId].pinching=true end
        self.endCameraPan()
        self.pinch=nil
    end
    return true
end

function MobileControls:cancelAll()
    for _,touch in pairs(self.touches) do if touch.kind=="key" then self.releaseKey(touch.key) end end
    self.touches={}
    self.joystickTouch=nil
    self.pinch=nil
    self.endCameraPan()
    self.axisX,self.axisY=0,0
end

local function drawButton(button,label,active,textScale)
    love.graphics.setColor(.055,.038,.028,.78)
    love.graphics.circle("fill",button.x,button.y,button.radius)
    love.graphics.setColor(active and .96 or .86,active and .66 or .49,active and .22 or .16,.92)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line",button.x,button.y,button.radius)
    love.graphics.setColor(1,.93,.75,.96)
    local scale=math.min(.98,.72*(textScale or 1))
    love.graphics.printf(label,button.x-button.radius,button.y-8*scale,button.radius*2,"center",0,scale,scale)
end

local function drawRectButton(button,label,active,textScale)
    love.graphics.setColor(.055,.038,.028,.92)
    love.graphics.rectangle("fill",button.x,button.y,button.w,button.h,12,12)
    love.graphics.setColor(active and .96 or .86,active and .66 or .49,active and .22 or .16,.96)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line",button.x,button.y,button.w,button.h,12,12)
    love.graphics.setColor(1,.93,.75,.98)
    local scale=math.min(1.12,.92*(textScale or 1))
    love.graphics.printf(label,button.x+6,button.y+button.h/2-9*scale,button.w-12,"center",0,scale,scale)
end

function MobileControls:draw(offsetX,offsetY,scaleX,scaleY)
    if not self.enabled then return end
    self:_updateCornerLayout()
    love.graphics.push()
    love.graphics.translate(offsetX,offsetY)
    love.graphics.scale(scaleX,scaleY)
    local textScale=Accessibility.textScale(self.accessibilityData())
    if self:isGameplayActive() then
        local stick=self.joystick
        love.graphics.setColor(.055,.038,.028,.60)
        love.graphics.circle("fill",stick.x,stick.y,stick.radius)
        love.graphics.setColor(.86,.49,.16,.78)
        love.graphics.setLineWidth(4)
        love.graphics.circle("line",stick.x,stick.y,stick.radius)
        love.graphics.line(stick.x-stick.radius*.65,stick.y,stick.x+stick.radius*.65,stick.y)
        love.graphics.line(stick.x,stick.y-stick.radius*.65,stick.x,stick.y+stick.radius*.65)
        local knobX=stick.x+self.axisX*stick.radius*.72
        local knobY=stick.y+self.axisY*stick.radius*.72
        love.graphics.setColor(.96,.66,.22,.92)
        love.graphics.circle("fill",knobX,knobY,stick.knob)
        local primaryKey,primaryLabel=self.primaryAction()
        drawButton(self.primary,primaryLabel or "USE",self:isHeld(primaryKey),textScale)
        local secondaryKey,secondaryLabel=self.secondaryAction()
        if secondaryKey then drawButton(self.secondary,secondaryLabel or "GIVE",self:isHeld(secondaryKey),textScale) end
    end
    if self.backVisible() then drawRectButton(self.back,self.backLabel(),false,textScale) end
    if self.menuVisible() then drawRectButton(self.menu,self.menuLabel(),false,textScale) end
    if self.feedback then
        local now=love and love.timer and love.timer.getTime and love.timer.getTime() or self.feedback.time+.3
        local elapsed=now-self.feedback.time
        if elapsed<.34 then
            local progress=math.max(0,math.min(1,elapsed/.34)); love.graphics.setColor(1,.88,.32,1-progress)
            love.graphics.setLineWidth(4); love.graphics.circle("line",self.feedback.x,self.feedback.y,16+progress*34)
        else self.feedback=nil end
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

return MobileControls
