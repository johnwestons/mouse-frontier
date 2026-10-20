local Style=require('game.ui_layout')
local GuiArt=require('game.gui_art')
local Art={}
local images,quads={},{}
function Art.setFrames(value) GuiArt.setFrames(value) end
-- Bounds of the authored glyphs (transparent atlas padding is excluded).
local glyphs={{51,92,243,205},{387,80,219,235},{658,110,263,193},{991,79,192,227},
    {62,407,211,187},{368,468,216,56},{683,374,184,243},{1001,369,171,248},
    {42,723,270,149},{375,695,213,191},{668,683,241,210},{969,706,235,187},
    {63,965,222,221},{387,983,186,185},{702,981,160,187},{990,971,196,208}}
local indexes={poses=1,leave=2,travel=3,backpack=4,map=5,more=6,idle=7,sit=8,lay=9,use=10,
    upgrade=11,maintenance=11,decorate=11,journal=12,settings=13,editor=13,close=14,pause=15,launcher=16,localPlay=16}
function Art.image(name)
    if not images[name] then
        local file=(name=='tile' or name=='panel') and 'frame' or name
        images[name]=love.graphics.newImage('assets/sprites/ui/actions/simple/'..file..'.png')
        images[name]:setFilter('linear','linear')
    end
    return images[name]
end
function Art.wheel(name,cx,cy,radius)
    local img=Art.image(name)
    -- Source-circle bounds and seam orientation from the generated sprites.
    local rotation=name=='radial' and math.pi/6 or 0
    local diameter=name=='radial' and 1051 or 1058
    local ox,oy=626,name=='radial' and 625 or 622
    local scale=radius*2/diameter
    love.graphics.draw(img,cx,cy,rotation,scale,scale,ox,oy)
end
function Art.frame(name,r,highlight,disabled)
    GuiArt.frame(r.x,r.y,r.w,r.h,{circle=name=='center',simple=true,selected=highlight,disabled=disabled})
end
function Art.icon(id,x,y,size,disabled)
    local g=love.graphics;local img=Art.image('icons');local index=indexes[id] or 16
    if not quads[index] then
        local w,h=img:getDimensions();local r=glyphs[index]
        quads[index]=g.newQuad(r[1]-2,r[2]-2,r[3]+4,r[4]+4,w,h)
    end
    size=math.min(size*Style.iconScale(),size*1.7)
    g.setColor(1,1,1,disabled and .5 or 1)
    local r=glyphs[index];local w,h=r[3]+4,r[4]+4;local scale=size/math.max(w,h)
    g.draw(img,quads[index],x,y,0,scale,scale,w/2,h/2)
end
return Art
