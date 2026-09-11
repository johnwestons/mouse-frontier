local Manifest=require("game.first_person_weapon_manifest")
local Grips=require("game.first_person_weapon_grips")
local Aim={}

local function gripFor(weapon,view)
    local views=Grips[weapon] or {}
    return views[view] or views.hip or {x=.5,y=.7,aspect=1}
end

-- Both shooting games use the same phone-sized weapon and grip-to-reticle
-- geometry. ADS preserves the calibrated sight; hip fire keeps a clear aiming
-- point above the hand. Coordinates are logical canvas pixels, before scaling.
function Aim.geometry(weapon,mode,width,height)
    width,height=width or 960,height or 720
    mode=mode=="sights" and "sights" or "hip"
    local grip=gripFor(weapon,mode)
    local gap=height*.20
    local artHeight=math.min(height*.50,width*.56/grip.aspect)
    local offsetX,offsetY=0,gap
    local sight,calibrated=Manifest.anchorFor(weapon)
    if mode=="sights" and calibrated and grip.y>sight.y then
        artHeight=math.min(gap/(grip.y-sight.y),height*.66,width*.65/grip.aspect)
        offsetX=(grip.x-sight.x)*artHeight*grip.aspect
        offsetY=(grip.y-sight.y)*artHeight
    end
    return {height=artHeight,offsetX=offsetX,offsetY=offsetY}
end

function Aim.gripForAim(weapon,mode,x,y,width,height)
    local geometry=Aim.geometry(weapon,mode,width,height)
    return x+geometry.offsetX,y+geometry.offsetY
end

function Aim.set(state,x,y,weapon,mode,width,height,bounds)
    width,height=width or 960,height or 720
    bounds=bounds or {left=0,top=0,right=width,bottom=height}
    state.touchAim={x=x,y=y,width=width,height=height,bounds=bounds}
    local geometry=Aim.geometry(weapon,mode,width,height)
    state.aimX=math.max(bounds.left,math.min(bounds.right,x-geometry.offsetX))
    state.aimY=math.max(bounds.top,math.min(bounds.bottom,y-geometry.offsetY))
end

function Aim.refresh(state,weapon,mode)
    local touch=state.touchAim
    if touch then Aim.set(state,touch.x,touch.y,weapon,mode,touch.width,touch.height,touch.bounds) end
end

function Aim.placement(weapon,view,mode,x,y,width,height)
    local geometry=Aim.geometry(weapon,mode,width,height)
    local grip=gripFor(weapon,view)
    local artWidth=geometry.height*grip.aspect
    local handX,handY=x+geometry.offsetX,y+geometry.offsetY
    return {x=handX-grip.x*artWidth,y=handY-grip.y*geometry.height,
        width=artWidth,height=geometry.height,gripX=handX,gripY=handY}
end

return Aim
