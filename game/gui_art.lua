-- Shared GUI skin, using the approved action-menu sprites at every size.
-- Source coordinates scale with packaged textures; nine-slicing keeps the
-- thin outline and rounded corners consistent on buttons and large panels.
local Style=require('game.ui_layout')
local Art={}
local textures,quads={},{}
local frames
function Art.setFrames(value) frames=value end
local function image(name)
    if not textures[name] then
        local value=love.graphics.newImage('assets/sprites/ui/actions/simple/'..name..'.png')
        value:setFilter('linear','linear');textures[name]=value
    end
    return textures[name]
end
local function quad(key,texture,x,y,w,h)
    if not quads[key] then
        local iw,ih=texture:getDimensions();local sx,sy=iw/1254,ih/1254
        quads[key]=love.graphics.newQuad(x*sx,y*sy,w*sx,h*sy,iw,ih)
    end
    return quads[key]
end
function Art.frame(x,y,w,h,options)
    if w<=0 or h<=0 then return end
    options=options or {}
    local g=love.graphics
    local r,green,b,a
    if g.getColor then r,green,b,a=g.getColor() end
    local alpha=options.alpha or 1
    local brightness=options.disabled and .52 or 1
    g.setColor(brightness,brightness*(options.selected and .85 or 1),brightness*(options.selected and .55 or 1),alpha)
    local selectedFrame=options.circle~=true and options.override~=false and Style.frame and Style.frame(0) or 0
    local frame=frames and frames[selectedFrame]
    if frame then
        local sw,sh=frame.w,frame.h;local sx,sy=math.floor(sw*.22),math.floor(sh*.28)
        local dx,dy=math.min(16,w/4),math.min(14,h/4)
        local xs,ys={0,sx,sw-sx,sw},{0,sy,sh-sy,sh}
        local xd,yd={x,x+dx,x+w-dx,x+w},{y,y+dy,y+h-dy,y+h}
        for row=1,3 do for col=1,3 do
            g.draw(frame.image,frame.quads[row][col],xd[col],yd[row],0,(xd[col+1]-xd[col])/(xs[col+1]-xs[col]),(yd[row+1]-yd[row])/(ys[row+1]-ys[row]))
        end end
    elseif not rawget(g,'newImage') then
        -- Minimal graphics adapters used by headless behavioral checks.
        g.setColor(.227,.165,.11,alpha)
        if options.circle and g.circle then g.circle('fill',x+w/2,y+h/2,math.min(w,h)/2)
        else g.rectangle('fill',x,y,w,h,7,7) end
    elseif options.circle then
        local texture=image('center');local iw,ih=texture:getDimensions()
        g.draw(texture,quad('center',texture,103,113,1047,1045),x,y,0,w/(1047*iw/1254),h/(1045*ih/1254))
    else
        local texture=image('frame');local iw,ih=texture:getDimensions()
        local xs,ys={76,164,1090,1178},{80,168,1086,1174}
        local dx,dy=math.min(8,w/4),math.min(8,h/4)
        local xd,yd={x,x+dx,x+w-dx,x+w},{y,y+dy,y+h-dy,y+h}
        for row=1,3 do for col=1,3 do
            local qw,qh=xs[col+1]-xs[col],ys[row+1]-ys[row]
            g.draw(texture,quad('frame_'..row..'_'..col,texture,xs[col],ys[row],qw,qh),xd[col],yd[row],0,(xd[col+1]-xd[col])/(qw*iw/1254),(yd[row+1]-yd[row])/(qh*ih/1254))
        end end
    end
    if r then g.setColor(r,green,b,a) end
end
function Art.circle(x,y,radius,options)
    options=options or {};local circular={circle=true,alpha=options.alpha,selected=options.selected,disabled=options.disabled}
    return Art.frame(x-radius,y-radius,radius*2,radius*2,circular)
end
return Art
