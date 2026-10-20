local GuiArt=require('game.gui_art')
-- Shared, screen-relative aiming: the thumb stays on the pad, not on the gun.
local Typography=require('game.typography')
local Pad={}; Pad.__index=Pad
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
function Pad.new() return setmetatable({x=0,y=0},Pad) end
function Pad.layout(width,height)
    width,height=width or 960,height or 720
    local scale=math.min(width/960,height/720)
    return {x=112*scale,y=height-220*scale,r=64*scale,
        fireX=width-108*scale,fireY=height-220*scale,fireR=48*scale}
end
function Pad.hit(x,y,width,height)
    local p=Pad.layout(width,height)
    if (x-p.x)^2+(y-p.y)^2<=(p.r+10)^2 then return 'aim' end
    if (x-p.fireX)^2+(y-p.fireY)^2<=(p.fireR+8)^2 then return 'fire' end
end
function Pad:move(id,x,y,width,height)
    if self.aimTouch~=id then return self.fireTouch==id end
    local p=Pad.layout(width,height)
    local dx,dy=(x-p.x)/p.r,(y-p.y)/p.r
    local length=math.sqrt(dx*dx+dy*dy)
    local divisor=math.max(1,length)
    self.x,self.y=dx/divisor,dy/divisor
    return true
end
function Pad:press(id,x,y,width,height)
    local action=Pad.hit(x,y,width,height)
    if action=='aim' and not self.aimTouch then
        self.aimTouch=id; self:move(id,x,y,width,height)
        return 'aim'
    elseif action=='fire' and not self.fireTouch then self.fireTouch=id; return 'fire' end
    return action and 'blocked' or nil
end
function Pad:release(id)
    if self.aimTouch==id then self.aimTouch=nil; self.x,self.y=0,0; return 'aim' end
    if self.fireTouch==id then self.fireTouch=nil; return 'fire' end
end
function Pad:cancel() self.aimTouch=nil; self.fireTouch=nil; self.x,self.y=0,0 end
function Pad:step(dt,gun,width,height,bounds)
    if not self.aimTouch or not gun then return end
    local length=math.sqrt(self.x*self.x+self.y*self.y)
    -- A small dead zone removes resting-thumb jitter. Squaring the remaining
    -- travel leaves a wide precision band, then ramps up to a fast screen sweep.
    if length<=.10 then return end
    local travel=clamp((length-.10)/.90,0,1)
    local speed=math.min(width,height)*1.20*travel^2
    if gun.ads or gun.aimMode=='sights' then speed=speed*.55 end
    local step=speed*clamp(dt or 0,0,.05)
    bounds=bounds or {left=0,top=0,right=width,bottom=height}
    return clamp(gun.aimX+self.x/length*step,bounds.left,bounds.right),
        clamp(gun.aimY+self.y/length*step,bounds.top,bounds.bottom)
end
function Pad:draw(width,height,opacity)
    local g=love.graphics; local p=Pad.layout(width,height); opacity=opacity or .8
    g.push('all')
    GuiArt.circle(p.x,p.y,p.r,{alpha=.65*opacity})
    g.setColor(.96,.66,.22,.94*opacity); g.circle('fill',p.x+self.x*p.r*.66,p.y+self.y*p.r*.66,p.r*.34)
    GuiArt.circle(p.fireX,p.fireY,p.fireR,{alpha=opacity,selected=self.fireTouch~=nil})
    g.setColor(1,.93,.75,opacity)
    Typography.drawText(g,'FIRE',p.fireX-p.fireR,p.fireY-15,p.fireR*2,30,{scale=1,minScale=.8,align='center',valign='center'})
    Typography.drawText(g,'AIM',p.x-p.r,p.y+p.r+4,p.r*2,22,{scale=.8,minScale=.7,align='center',valign='center'})
    g.pop()
end
return Pad
