local WorldView=require("game.world_view")
local IntroCinematic = {}

-- Anchors are proportions of the authored images so the mobile optimizer can
-- resize the scenery without moving the train below the visible screen.
local backgroundRailRatio = 750/1086
local consistBaselineRatio = 584/724

-- The generated sheet is not a uniform grid. These measured rectangles keep
-- neighboring locomotive frames from being sliced into one another.
local locomotiveFrames = {
    {x=0,y=0,w=371,h=443,rear=358,bodyWidth=350,baseline=344},
    {x=371,y=0,w=368,h=443,rear=363,bodyWidth=352,baseline=345},
    {x=739,y=0,w=339,h=443,rear=335,bodyWidth=331,baseline=345},
    {x=1078,y=0,w=336,h=443,rear=334,bodyWidth=332,baseline=345},
    {x=1414,y=0,w=360,h=443,rear=345,bodyWidth=345,baseline=345},
    {x=0,y=443,w=364,h=444,rear=360,bodyWidth=352,baseline=221},
    {x=364,y=443,w=365,h=444,rear=355,bodyWidth=352,baseline=221},
    {x=729,y=443,w=353,h=444,rear=350,bodyWidth=341,baseline=221},
    {x=1082,y=443,w=340,h=444,rear=336,bodyWidth=335,baseline=221},
    {x=1422,y=443,w=352,h=444,rear=339,bodyWidth=337,baseline=221},
}

function IntroCinematic.new(duration)
    return {timer=0,duration=duration or 10,skipFast=false,finished=false,locomotiveQuads=nil}
end

function IntroCinematic.update(intro,dt)
    if not intro or intro.finished then return true end
    local frameTime=math.min(dt,.1)
    intro.timer=intro.timer+frameTime*(intro.skipFast and 3 or 1)
    if intro.timer>=intro.duration then intro.timer=intro.duration; intro.finished=true end
    return intro.finished
end

function IntroCinematic.skip(intro)
    if not intro or intro.finished then return end
    intro.timer=math.max(intro.timer,intro.duration-1.5)
    intro.skipFast=true
end

function IntroCinematic.draw(intro,scenery,colors,width,height)
    love.graphics.clear(0,0,0,1)
    WorldView.begin({fullscreen={width,height}})
    local background=scenery.introBackground
    local sceneScale=height/720
    local railY=height*backgroundRailRatio
    if background then
        local backgroundWidth,backgroundHeight=background:getDimensions()
        local scale=math.max(width/backgroundWidth,height/backgroundHeight)
        sceneScale=scale/(720/backgroundHeight)
        railY=height/2+scale*(backgroundHeight*backgroundRailRatio-backgroundHeight/2)
        love.graphics.setColor(1,1,1)
        love.graphics.draw(background,width/2,height/2,0,scale,scale,backgroundWidth/2,backgroundHeight/2)
    end

    local progress=math.max(0,math.min(1,intro.timer/intro.duration))
    local locomotiveX=width+160*sceneScale-progress*(width+980*sceneScale)
    local couplerX=locomotiveX+128*sceneScale
    local cars=scenery.introCars
    if cars then
        love.graphics.setColor(1,1,1)
        love.graphics.draw(cars,couplerX+257*sceneScale,railY,0,.24*sceneScale,.24*sceneScale,cars:getWidth()/2,cars:getHeight()*consistBaselineRatio)
    end
    local sheet=scenery.introLocomotiveSheet
    if sheet then
        if not intro.locomotiveQuads then
            intro.locomotiveQuads={}
            for index,frame in ipairs(locomotiveFrames) do
                intro.locomotiveQuads[index]=love.graphics.newQuad(frame.x,frame.y,frame.w,frame.h,sheet:getDimensions())
            end
        end
        local frameIndex=(math.floor(intro.timer*12)%#locomotiveFrames)+1
        local frame=locomotiveFrames[frameIndex]
        local scaleX=.72*(355/frame.bodyWidth)*sceneScale
        love.graphics.setColor(1,1,1)
        love.graphics.draw(sheet,intro.locomotiveQuads[frameIndex],couplerX,railY,0,scaleX,.52*sceneScale,frame.rear,frame.baseline)
    elseif scenery.introLocomotive then
        local locomotive=scenery.introLocomotive
        love.graphics.setColor(1,1,1)
        love.graphics.draw(locomotive,couplerX,railY,0,.15*sceneScale,.15*sceneScale,1741,782)
    end

    WorldView.finish()
    local hintAlpha=math.min(1,math.max(0,(intro.timer-.8)/.8))*math.min(1,math.max(0,(intro.duration-1-intro.timer)/.8))
    love.graphics.setColor(colors.cream[1],colors.cream[2],colors.cream[3],hintAlpha*.8)
    love.graphics.printf("PRESS ANY KEY OR CLICK TO SKIP",0,height-46,width,"center",0,.68,.68)

    local fadeAlpha=0
    if intro.timer<1.25 then fadeAlpha=1-intro.timer/1.25
    elseif intro.timer>intro.duration-1.5 then fadeAlpha=(intro.timer-(intro.duration-1.5))/1.5 end
    love.graphics.setColor(0,0,0,math.max(0,math.min(1,fadeAlpha)))
    love.graphics.rectangle("fill",0,0,width,height)
end

return IntroCinematic
