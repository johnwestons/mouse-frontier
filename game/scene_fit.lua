-- Authored world coordinates stay unchanged; only the presentation of a
-- compact scene is fitted into the space below the journey HUD.
local SceneFit={}
local WideLayout=require("game.wide_layout")

function SceneFit.house(width,height,windowWidth,windowHeight)
    local room={x=105,y=205,w=750,h=445}
    windowWidth=windowWidth or width
    windowHeight=windowHeight or height
    local wide=WideLayout.measure(width,height,windowWidth,windowHeight).sidePanels
    if wide then
        -- Wide layouts move information into the side gutters, so the room can
        -- grow past the stage edges and use the full vertical view.
        local scale=1.4
        return {x=width/2-(room.x+room.w/2)*scale,
            y=height/2-(room.y+room.h/2)*scale,scale=scale}
    end
    -- On narrow views keep the room below the fixed top HUD.
    local safe={x=12,y=150,w=width-24,h=height-150}
    local scale=math.min(safe.w/room.w,safe.h/room.h)
    local x=safe.x+(safe.w-room.w*scale)/2-room.x*scale
    local y=safe.y+(safe.h-room.h*scale)/2-room.y*scale
    return {x=x,y=y,scale=scale}
end

function SceneFit.toView(fit,x,y)
    return fit.x+x*fit.scale,fit.y+y*fit.scale
end

function SceneFit.toWorld(fit,x,y)
    return (x-fit.x)/fit.scale,(y-fit.y)/fit.scale
end

function SceneFit.apply(fit)
    love.graphics.translate(fit.x,fit.y)
    love.graphics.scale(fit.scale,fit.scale)
end

return SceneFit
