local EventUI = {}
local Typography=require("game.typography")
local quadCache=setmetatable({},{__mode="k"})

function EventUI.load(loadImage)
    local result={}
    for _,name in ipairs({"battle-a","help-a","fortune-a","mishap-a","defense-a","mystery-a","story-a","story-b"}) do
        result[name]=loadImage("assets/sprites/events/"..name..".png")
    end
    return result
end

function EventUI.choiceRects()
    return {{x=135,y=511,w=220,h=140},{x=370,y=511,w=220,h=140},{x=605,y=511,w=220,h=140}}
end

function EventUI.drawArt(event,images,x,y,w,h)
    local image=images and images[event.artSheet]; if not image then return end
    local frameW=image:getWidth()/5; local index=math.max(1,math.min(5,event.artIndex or 1))
    local quads=quadCache[image]
    if not quads then quads={}; for frame=1,5 do quads[frame]=love.graphics.newQuad((frame-1)*frameW,0,frameW,image:getHeight(),image:getDimensions()) end; quadCache[image]=quads end
    local quad=quads[index]
    -- Keep the complete illustration visible.  The previous cover-style scale
    -- filled the panel by cropping the sides/top, which made the event art
    -- look dramatically zoomed in.  Contain it inside the frame instead and
    -- center any small letterbox margins.
    local scale=math.min(w/frameW,h/image:getHeight())
    local drawW,drawH=frameW*scale,image:getHeight()*scale
    local drawX,drawY=x+(w-drawW)/2,y+(h-drawH)/2
    love.graphics.setColor(0.04,0.025,0.02,.35); love.graphics.rectangle("fill",x,y,w,h)
    love.graphics.setColor(1,1,1); love.graphics.draw(image,quad,drawX,drawY,0,scale,scale)
end

function EventUI.draw(event,images,drawFrame,button,colors,progress,canChoose)
    local function text(text,x,y,w,h,scale)
        Typography.drawText(love.graphics,text,x,y,w,h,{scale=scale or 1,minScale=.75,align="center",valign="center"})
    end
    drawFrame(95,35,770,625,1,1)
    love.graphics.setColor(colors.brass); text(string.upper(event.category).." EVENT",125,48,710,32,1.05)
    drawFrame(135,86,690,258,3,1); EventUI.drawArt(event,images,142,93,676,244)
    love.graphics.setColor(0.04,0.025,0.02,.73); love.graphics.rectangle("fill",142,276,676,61)
    love.graphics.setColor(colors.cream); text(event.title,160,281,640,48,1.25)
    text(event.text,150,352,660,72,.95)
    if event.category=="story" then love.graphics.setColor(colors.brass); text("FAMILY TRAIL  "..math.min(10,(progress.story or 0)+1).." / 10",185,430,590,25,.85)
    elseif event.category=="mystery" then love.graphics.setColor(colors.brass); text("MISSING CRITTER CLUE  "..math.min(5,(progress.mystery or 0)+1).." / 5",185,430,590,25,.85) end
    love.graphics.setColor(colors.cream); text("Choose a response. Each path has a different consequence.",150,459,660,45,.85)
    local rects=EventUI.choiceRects()
    for index,choice in ipairs(event.choices) do
        local r=rects[index]; local enabled=not canChoose or canChoose(choice); button("",r.x,r.y,r.w,r.h,enabled); r.enabled=enabled
        love.graphics.setColor(colors.cream); text(enabled and choice.label or "CAN'T AFFORD",r.x+10,r.y+8,r.w-20,44,.95)
        text(choice.hint or "",r.x+10,r.y+58,r.w-20,72,.82)
    end
    return rects
end

function EventUI.hit(x,y,rects,pointIn)
    for index,rect in ipairs(rects or EventUI.choiceRects()) do if rect.enabled~=false and pointIn(x,y,rect) then return index end end
end

return EventUI
