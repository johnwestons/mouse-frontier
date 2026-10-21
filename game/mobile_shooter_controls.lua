local GuiArt=require('game.gui_art')
-- Shared, screen-relative aiming: the thumb stays on the pad, not on the gun.
local Typography=require('game.typography')
local Pad={}; Pad.__index=Pad
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
function Pad.new() return setmetatable({x=0,y=0},Pad) end
function Pad.layout(width,height)
    width,height=width or 960,height or 720
    local scale=math.min(width/960,height/720)
    -- Keep thumbs below the target field and above the earliest shooter footer.
    return {x=80*scale,y=height-168*scale,r=52*scale,
        fireX=width-80*scale,fireY=height-168*scale,fireR=44*scale,
        guardTop=height-242*scale,guardBottom=height-110*scale,
        aimRight=160*scale,fireLeft=width-152*scale}
end
function Pad.hit(x,y,width,height)
    width,height=width or 960,height or 720
    local p=Pad.layout(width,height)
    -- Reserve the whole thumb area, including near misses beside the circle.
    -- A captured finger stays a pad finger even when dragged across the field.
    if y>=p.guardTop and y<=p.guardBottom then
        if x>=0 and x<=p.aimRight then return 'aim' end
        if x>=p.fireLeft and x<=width then return 'fire' end
    end
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
function Pad:step(dt,gun,width,height,bounds,options,targets)
    if not self.aimTouch or not gun then return end
    width,height=width or 960,height or 720
    options=options or {}
    local length=math.sqrt(self.x*self.x+self.y*self.y)
    -- Respond immediately with a gentle precision band instead of the old
    -- squared curve, which consumed most of the pad travel at a crawl.
    if length<=.06 then return end
    local travel=clamp((length-.06)/.94,0,1)
    local speed=math.min(width,height)*1.9*travel^1.35*clamp(tonumber(options.aimSensitivity) or 1,.5,2)
    if gun.ads or gun.aimMode=='sights' then speed=speed*.8 end
    dt=clamp(dt or 0,0,.1)
    local step=speed*dt
    bounds=bounds or {left=0,top=0,right=width,bottom=height}
    local x=clamp(gun.aimX+self.x/length*step,bounds.left,bounds.right)
    local y=clamp(gun.aimY+self.y/length*step,bounds.top,bounds.bottom)
    local strength=clamp(tonumber(options.aimAssist) or .35,0,1)
    -- Assistance only accompanies deliberate thumb movement. Releasing or
    -- resting the stick stops it; a fast sweep or pulling away always wins.
    if strength>0 and travel<.9 and targets then
        local scale=math.min(width/960,height/720)
        local nearest,distance,radius
        for _,target in ipairs(targets) do
            local tx,ty=target.x,target.y
            if tx and ty and tx>=bounds.left and tx<=bounds.right and ty>=bounds.top and ty<=bounds.bottom then
                local dx,dy=tx-x,ty-y
                local d=math.sqrt(dx*dx+dy*dy)
                local reach=70*scale+math.min(18*scale,(target.radius or 0)*.35)
                if d<reach and (not distance or d<distance) then nearest,distance,radius=target,d,reach end
            end
        end
        if nearest and distance>.001 then
            local dx,dy=nearest.x-x,nearest.y-y
            local toward=(self.x*dx+self.y*dy)/(length*distance)
            if toward>=0 then
                local weight=(1-distance/radius)*(1-travel/.9)^2
                local pull=1-math.exp(-strength*16*weight*dt)
                x,y=x+dx*pull,y+dy*pull
            end
        end
    end
    return clamp(x,bounds.left,bounds.right),clamp(y,bounds.top,bounds.bottom)
end
function Pad:draw(width,height,opacity)
    local g=love.graphics; local p=Pad.layout(width,height); opacity=opacity or .8
    g.push('all')
    GuiArt.circle(p.x,p.y,p.r,{alpha=.65*opacity})
    g.setColor(.96,.66,.22,.94*opacity); g.circle('fill',p.x+self.x*p.r*.66,p.y+self.y*p.r*.66,p.r*.34)
    GuiArt.circle(p.fireX,p.fireY,p.fireR,{alpha=opacity,selected=self.fireTouch~=nil})
    g.setColor(1,.93,.75,opacity)
    Typography.drawText(g,'FIRE',p.fireX-p.fireR,p.fireY-15,p.fireR*2,30,{scale=1,minScale=.8,align='center',valign='center'})
    Typography.drawText(g,'AIM',p.x-p.r,p.y+p.r-20,p.r*2,18,{scale=.7,minScale=.6,align='center',valign='center'})
    g.pop()
end
return Pad
