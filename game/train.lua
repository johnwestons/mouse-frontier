local Train = {
    -- The track art contains a far rail and a near rail. Rolling stock belongs
    -- on the near rail (source row 414), not the far rail at row 300.
    railY=670,
    trackVisibleTop=268,
    trackRailSourceY=414,
    -- Aligned PNGs are cropped to their visible alpha bounds, so the bottom
    -- edge is the wheel contact edge and no padding compensation is needed.
    -- Cropped sprites end at their visible wheel pixels. Both are anchored
    -- directly to this rail line; no per-sprite vertical fudge remains.
    locomotiveContactOffset=0,
    carContactOffset=0,
    carVisibleLeft=10,
    carVisibleRight=630,
    carWheelY=356,
    engineWheelY={740,745,742},
    engineStaticWheelY=745,
    engineVisibleLeft={80,82,82},
    engineStaticVisibleLeft=80,
    engineCouplerX={1522,1527,1532},
    engineStaticCouplerX=1537,
    -- Width from the visible engine edge to the rear coupler. This larger
    -- scale matches the reference proportions beside the enlarged car.
    engineTargetWidth=560
}

function Train.carScale(car,image)
    if not image then return 1 end
    return car.w/(Train.carVisibleRight-Train.carVisibleLeft)
end

function Train.carTransform(car,image)
    local scale=Train.carScale(car,image)
    return car.x-Train.carVisibleLeft*scale,Train.railY-Train.carWheelY*scale,scale
end

function Train.floorSurfaceBounds(car,image)
    -- Floor coordinates are defined in the common 640x360 car canvas and use
    -- the same transform as the rendered car. This envelope is for furniture;
    -- character movement uses the perspective-shaped floor below.
    local x,y,scale=Train.carTransform(car,image)
    return x+84*scale,x+556*scale,y+244*scale,y+286*scale
end

function Train.characterBounds(car,image,footOffset)
    local left,right,top,bottom=Train.floorSurfaceBounds(car,image)
    local padding=14
    footOffset=footOffset or 30
    return left+padding,right-padding,top-footOffset,bottom-footOffset
end

function Train.clampCharacterToFloor(car,image,characterX,characterY,footOffset)
    -- The visible floor narrows toward the rear wall. Clamp the character's
    -- ground-contact point (not its image center) to that trapezoid.
    local drawX,drawY,scale=Train.carTransform(car,image)
    footOffset=footOffset or 30
    local contactY=math.max(drawY+244*scale,math.min(drawY+286*scale,characterY+footOffset))
    local depth=(contactY-(drawY+244*scale))/(42*scale)
    local sourceLeft=116+(84-116)*depth
    local sourceRight=524+(556-524)*depth
    local sidePadding=14
    local left=drawX+sourceLeft*scale+sidePadding
    local right=drawX+sourceRight*scale-sidePadding
    return math.max(left,math.min(right,characterX)),contactY-footOffset
end

-- Compatibility for callers that place objects directly on the planks.
function Train.floorBounds(car,image)
    return Train.floorSurfaceBounds(car,image)
end

function Train.drawTracks(track,width)
    if not track then return false end
    -- Overscan so fractional viewport scaling and widescreen rounding never
    -- expose a gap at either edge. Anchor the near rail to the rolling-stock
    -- baseline so changing the overscan does not move the train off the rail.
    local overscan=96
    local imageWidth=track:getWidth(); local scale=(width+overscan*2)/imageWidth
    love.graphics.setColor(1,1,1)
    local trackTop=Train.railY-Train.trackRailSourceY*scale
    love.graphics.draw(track,-overscan,trackTop,0,scale,scale)
    return true
end

function Train.drawLocomotive(image,frameIndex,car)
    if not image then return end
    local visibleLeft=Train.engineVisibleLeft[frameIndex or 0] or Train.engineStaticVisibleLeft
    local couplerX=Train.engineCouplerX[frameIndex or 0] or Train.engineStaticCouplerX
    local wheelY=Train.engineWheelY[frameIndex or 0] or Train.engineStaticWheelY
    local scale=Train.engineTargetWidth/(couplerX-visibleLeft)
    love.graphics.setColor(1,1,1)
    local rightEdge=car and car.x+8 or 280
    local x=rightEdge-couplerX*scale
    love.graphics.draw(image,x,Train.railY-wheelY*scale,0,scale,scale)
end

function Train.drawCarImage(image,car)
    if not image then return false end
    local x,y,scale=Train.carTransform(car,image)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,x,y,0,scale,scale)
    return true
end

return Train
