local WorldView=require("game.world_view")
local Train=require("game.cinematic_train")
local IntroCinematic = {}

-- Anchors are proportions of the authored images so the mobile optimizer can
-- resize the scenery without moving the train below the visible screen.
local backgroundRailRatio = Train.railRatio

function IntroCinematic.new(duration)
    return {timer=0,duration=duration or 10,skipFast=false,finished=false}
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
    Train.draw(scenery,couplerX,railY,sceneScale,intro.timer)

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
