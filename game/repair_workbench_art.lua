local RepairArt={}

local ROOT="assets/sprites/ui/repair/"
local SURFACE=ROOT.."workbench-surface-v1.png"
local ATLAS=ROOT.."workbench-controls-v1.png"
local ATLAS_WIDTH,ATLAS_HEIGHT=1254,1254

-- Bounds identify authored artwork inside the atlas; all layout stays in the
-- workbench's existing logical coordinates.
local SPRITES={
    normalRow={58,135,511,136},
    selectedRow={686,135,510,136},
    conditionTrack={48,469,531,67},
    greenFill={679,475,525,53},
    redFill={51,767,526,53},
    timingTrack={675,750,531,84},
    brassFill={51,1063,526,60},
    cursor={921,927,41,285},
}

local images={}
local sprites={}
local itemFrames={}

local function image(path)
    local value=images[path]
    if not value then
        value=love.graphics.newImage(path)
        value:setFilter("nearest","nearest")
        images[path]=value
    end
    return value
end

local function sprite(name)
    local value=sprites[name]
    if not value then
        local rect=assert(SPRITES[name],"Unknown workbench sprite: "..tostring(name))
        local texture=image(ATLAS)
        local width,height=texture:getDimensions()
        -- Mobile packaging may resize the complete atlas. Map both source
        -- edges into the installed texture before creating any sprite quad.
        local sx,sy=width/ATLAS_WIDTH,height/ATLAS_HEIGHT
        local left=math.max(0,math.min(width-1,math.floor(rect[1]*sx+.5)))
        local top=math.max(0,math.min(height-1,math.floor(rect[2]*sy+.5)))
        local right=math.max(left+1,math.min(width,math.floor((rect[1]+rect[3])*sx+.5)))
        local bottom=math.max(top+1,math.min(height,math.floor((rect[2]+rect[4])*sy+.5)))
        local w,h=right-left,bottom-top
        value={image=texture,x=left,y=top,w=w,h=h,imageW=width,imageH=height,
            quad=love.graphics.newQuad(left,top,w,h,width,height)}
        sprites[name]=value
    end
    return value
end

function RepairArt.surface(x,y,w,h)
    local texture=image(SURFACE)
    local width,height=texture:getDimensions()
    local r,g,b,a=love.graphics.getColor()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(texture,x,y,0,w/width,h/height)
    love.graphics.setColor(r,g,b,a)
end

function RepairArt.draw(name,x,y,w,h,fraction)
    local amount=math.max(0,math.min(1,fraction or 1))
    if amount==0 then return end
    local art=sprite(name)
    local quad=art.quad
    if amount<1 then
        if not art.fillQuad then
            art.fillQuad=love.graphics.newQuad(art.x,art.y,art.w,art.h,art.imageW,art.imageH)
        end
        -- Crop the painted fill, retaining its scale and the parent's scissor.
        art.fillQuad:setViewport(art.x,art.y,art.w*amount,art.h,art.imageW,art.imageH)
        quad=art.fillQuad
    end
    local r,g,b,a=love.graphics.getColor()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(art.image,quad,x,y,0,w/art.w,h/art.h)
    love.graphics.setColor(r,g,b,a)
end

function RepairArt.condition(x,y,w,h,percent)
    local condition=math.max(0,math.min(100,tonumber(percent) or 0))
    RepairArt.draw("conditionTrack",x,y,w,h)
    RepairArt.draw(condition<=25 and "redFill" or "greenFill",x,y,w,h,condition/100)
end

function RepairArt.item(name,rect,ui,catalog)
    local canonical=(catalog.repairPartAliases or {})[name] or name
    local texture=ui.propImages and ui.propImages[canonical]
    if not texture then return false end
    local frame=itemFrames[canonical]
    if not frame then
        local part=(catalog.repairParts or {})[canonical]
        local path=part and part.sprite or ("assets/sprites/weapons/"..canonical..".png")
        local pixels=love.image.newImageData(path)
        local width,height=pixels:getDimensions()
        local left,top,right,bottom=width,height,-1,-1
        -- Alpha bounds are display metadata. Authored weapon pixels stay intact.
        for y=0,height-1 do for x=0,width-1 do
            local _,_,_,alpha=pixels:getPixel(x,y)
            if alpha>=32/255 then
                left=math.min(left,x); top=math.min(top,y)
                right=math.max(right,x); bottom=math.max(bottom,y)
            end
        end end
        pixels:release()
        if right<left then left,top,right,bottom=0,0,width-1,height-1 end
        local w,h=right-left+1,bottom-top+1
        frame={w=w,h=h,quad=love.graphics.newQuad(left,top,w,h,width,height)}
        itemFrames[canonical]=frame
    end
    local scale=math.min(rect.w/frame.w,rect.h/frame.h)
    local r,g,b,a=love.graphics.getColor()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(texture,frame.quad,rect.x+rect.w/2,rect.y+rect.h/2,0,scale,scale,frame.w/2,frame.h/2)
    love.graphics.setColor(r,g,b,a)
    return true
end

function RepairArt.timing(rail,phase)
    RepairArt.draw("timingTrack",rail.x,rail.y,rail.w,rail.h)
    RepairArt.draw("greenFill",rail.x+rail.w*.53,rail.y+4,rail.w*.25,rail.h-8)
    RepairArt.draw("brassFill",rail.x+rail.w*.62,rail.y,rail.w*.07,rail.h)
    if phase then
        RepairArt.draw("cursor",rail.x+phase*rail.w-3,rail.y-7,6,rail.h+14)
    end
end

return RepairArt
