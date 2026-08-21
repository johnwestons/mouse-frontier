local EventUI = {}
local quadCache=setmetatable({},{__mode="k"})

function EventUI.load(loadImage)
    local result={}
    for _,name in ipairs({"battle-a","help-a","fortune-a","mishap-a","defense-a","mystery-a","story-a","story-b"}) do
        result[name]=loadImage("assets/sprites/events/"..name..".png")
    end
    return result
end

function EventUI.choiceRects()
    return {{x=205,y=525,w=175,h=88},{x=393,y=525,w=175,h=88},{x=581,y=525,w=175,h=88}}
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
    drawFrame(95,35,770,625,1,1)
    love.graphics.setColor(colors.brass); love.graphics.printf(string.upper(event.category).." EVENT",125,58,710,"center",0,1.05,1.05)
    drawFrame(135,86,690,258,3,1); EventUI.drawArt(event,images,142,93,676,244)
    love.graphics.setColor(0.04,0.025,0.02,.73); love.graphics.rectangle("fill",142,276,676,61)
    love.graphics.setColor(colors.cream); love.graphics.printf(event.title,160,284,640,"center",0,1.32,1.32)
    love.graphics.printf(event.text,150,355,660,"center",0,.78,.78)
    if event.category=="story" then love.graphics.setColor(colors.brass); love.graphics.printf("FAMILY TRAIL  "..math.min(10,(progress.story or 0)+1).." / 10",185,430,590,"center",0,.72,.72)
    elseif event.category=="mystery" then love.graphics.setColor(colors.brass); love.graphics.printf("MISSING CRITTER CLUE  "..math.min(5,(progress.mystery or 0)+1).." / 5",185,430,590,"center",0,.72,.72) end
    love.graphics.setColor(colors.cream); love.graphics.printf("Choose a response — every path has a different consequence.",170,462,620,"center",0,.68,.68)
    local rects=EventUI.choiceRects()
    for index,choice in ipairs(event.choices) do
        local r=rects[index]; local enabled=not canChoose or canChoose(choice); button("",r.x,r.y,r.w,r.h,enabled); r.enabled=enabled
        love.graphics.setColor(colors.cream); love.graphics.printf(enabled and choice.label or "CAN'T AFFORD",r.x+8,r.y+10,r.w-16,"center",0,.92,.92)
        love.graphics.setColor(colors.cream); love.graphics.printf(choice.hint or "",r.x+8,r.y+53,r.w-16,"center",0,.58,.58)
    end
    return rects
end

function EventUI.hit(x,y,rects,pointIn)
    for index,rect in ipairs(rects or EventUI.choiceRects()) do if rect.enabled~=false and pointIn(x,y,rect) then return index end end
end

return EventUI
