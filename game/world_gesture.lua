-- Special scenes own their single-touch controls. Delay a second field tap
-- until release so two fingers can zoom without firing a weapon.
local Gesture={}
Gesture.__index=Gesture
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
function Gesture.new(options)
    return setmetatable({options=options,touches={}},Gesture)
end
function Gesture:cancel()
    for id,touch in pairs(self.touches) do
        if touch.started then self.options.release(id,touch.x,touch.y) end
    end
    self.touches={}; self.pinch=nil
    self.options.endPan()
end
function Gesture:pressed(id,x,y)
    local token,immediate=self.options.field(x,y)
    if not token then return false end
    if self.token~=token then self:cancel(); self.token=token end
    local firstId,first=next(self.touches)
    local touch={x=x,y=y,startX=x,startY=y}
    self.touches[id]=touch
    if first then
        if not self.pinch then
            self.pinch={first=firstId,second=id,distance=math.max(1,distance(first,touch)),
                zoom=self.options.getZoom(),x=(first.x+x)/2,y=(first.y+y)/2}
        else touch.suppressed=true end
    elseif immediate then
        self.options.press(id,x,y); touch.started=true
    end
    return true
end
function Gesture:moved(id,x,y,dx,dy)
    local touch=self.touches[id]
    if not touch then return false end
    touch.x,touch.y=x,y
    local pinch=self.pinch
    if pinch then
        local a,b=self.touches[pinch.first],self.touches[pinch.second]
        if a and b then
            local mx,my=(a.x+b.x)/2,(a.y+b.y)/2
            local separation=distance(a,b)
            if not pinch.active and (math.abs(separation-pinch.distance)>12
                or math.abs(mx-pinch.x)+math.abs(my-pinch.y)>12) then
                pinch.active=true; a.suppressed=true; b.suppressed=true
                self.options.beginPan(pinch.x,pinch.y)
            end
            if pinch.active then
                -- Scale about the previous midpoint, then translate to the new one.
                self.options.setZoom(pinch.zoom*separation/pinch.distance,pinch.x,pinch.y)
                self.options.movePan(mx,my)
                pinch.x,pinch.y=mx,my
            end
        end
    elseif not touch.suppressed then
        if not touch.started and distance(touch,{x=touch.startX,y=touch.startY})>14 then
            self.options.press(id,touch.startX,touch.startY); touch.started=true
        end
        if touch.started then self.options.move(id,x,y,dx,dy) end
    end
    return true
end
function Gesture:released(id,x,y)
    local touch=self.touches[id]
    if not touch then return false end
    if not touch.started and not touch.suppressed then self.options.press(id,x,y) end
    if touch.started or not touch.suppressed then self.options.release(id,x,y) end
    self.touches[id]=nil
    if self.pinch and (id==self.pinch.first or id==self.pinch.second) then
        if self.pinch.active then
            for _,other in pairs(self.touches) do other.suppressed=true end
        end
        self.options.endPan(); self.pinch=nil
    end
    return true
end
return Gesture
