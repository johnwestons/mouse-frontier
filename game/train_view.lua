local Train=require("game.train")

local View={}

function View.bounds(car)
    local engine=Train.locomotiveLayout(car)
    local carScale=car.w/(Train.carVisibleRight-Train.carVisibleLeft)
    local carTop=Train.railY-Train.carWheelY*carScale
    -- Union of all seven authored car silhouettes, the engine and every
    -- running-gear/smoke phase. Medical-car roof is highest (source y=65).
    -- Small margins include antialiasing and rotating wheel corners.
    return {left=engine.nose-3,right=car.x+car.w+3,
        top=math.min(carTop+65*carScale,engine.bodyY)-2,
        bottom=Train.railY+4*math.max(1,carScale),rail=Train.railY}
end

function View.layout(car,width,height,windowWidth,windowHeight,options)
    options=options or {}
    local viewportScale=math.min(windowWidth/width,windowHeight/height)
    local visibleWidth=windowWidth/viewportScale
    local visibleLeft=(width-visibleWidth)/2
    local visibleRight=visibleLeft+visibleWidth
    local bounds=View.bounds(car)
    local margin=20
    local top=options.mobile and ((options.carCount or 1)>1 and 324 or 214) or 238
    local rail=height-50
    local scale=math.min((visibleWidth-2*margin)/(bounds.right-bounds.left),
        (rail-top)/(bounds.rail-bounds.top))
    local x=width/2-(bounds.left+bounds.right)/2*scale
    local y=rail-bounds.rail*scale
    return {x=x,y=y,scale=scale,bounds=bounds,
        left=x+bounds.left*scale,right=x+bounds.right*scale,
        top=y+bounds.top*scale,bottom=y+bounds.bottom*scale,rail=rail,
        visibleLeft=visibleLeft,visibleRight=visibleRight,headerBottom=top,
        worldLeft=(visibleLeft-x)/scale,worldRight=(visibleRight-x)/scale,
        transitionDistance=visibleWidth/scale+40,
        couplerX=x+car.x*scale,viewportScale=viewportScale}
end

function View.toView(layout,x,y)
    return layout.x+x*layout.scale,layout.y+y*layout.scale
end

function View.toWorld(layout,x,y)
    return (x-layout.x)/layout.scale,(y-layout.y)/layout.scale
end

function View.apply(layout)
    love.graphics.translate(layout.x,layout.y)
    love.graphics.scale(layout.scale,layout.scale)
end

return View
