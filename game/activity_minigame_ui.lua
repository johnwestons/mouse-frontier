local UI={}

function UI.hit(zones,x,y,radius)
    radius=radius or 58
    for index,zone in ipairs(zones or {}) do local dx,dy=x-zone.x,y-zone.y; if dx*dx+dy*dy<=radius*radius then return index end end
end

function UI.variantZones(zones,session)
    local offsets=session and session.difficulty and session.difficulty.offsets or {}
    local result={}
    for index,zone in ipairs(zones or {}) do local offset=offsets[index] or {0,0}; result[index]={x=zone.x+offset[1],y=zone.y+offset[2]} end
    return result
end

function UI.sprite(image,index,x,y,size)
    if not image then return end
    local iw,ih=image:getDimensions(); local sw,sh=iw/2,ih/2; local column=(index-1)%2; local row=math.floor((index-1)/2)
    local quad=love.graphics.newQuad(column*sw,row*sh,sw,sh,iw,ih); local scale=size/math.max(sw,sh)
    love.graphics.draw(image,quad,x,y,0,scale,scale,sw/2,sh/2)
end

function UI.begin(colors,title,session,objective)
    local theme=session.difficulty and session.difficulty.palette or {}; local panel=theme.panel or colors.panel or {.08,.055,.035}; local cream=colors.cream or {1,.92,.74}; local brass=theme.accent or colors.brass or {.86,.57,.22}
    love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,960,720)
    love.graphics.setColor(panel); love.graphics.rectangle("fill",145,64,670,592,12,12)
    love.graphics.setColor(brass); love.graphics.setLineWidth(4); love.graphics.rectangle("line",145,64,670,592,12,12)
    love.graphics.setColor(cream); love.graphics.printf(title,185,90,590,"center",0,1.25,1.25)
    love.graphics.printf((session.difficulty and session.difficulty.name.."  •  " or "").."STAGE "..session.phase.." OF 3  •  "..objective,190,138,580,"center",0,.68,.68)
    return cream,brass
end

function UI.footer(session,cream,brass,defaultMessage)
    love.graphics.setColor(cream); love.graphics.printf(session.message or defaultMessage,205,535,550,"center",0,.7,.7)
    love.graphics.setColor(brass); love.graphics.printf("MISTAKES  "..session.progress.mistakes.." / "..session.maximumMistakes.."     •     1–3 / TAP     •     Q / BACK TO PAUSE",205,596,550,"center",0,.62,.62)
    love.graphics.setLineWidth(1); love.graphics.setColor(1,1,1,1)
end

function UI.miss(session,message)
    session.progress.mistakes=session.progress.mistakes+1; session.message=message
    return session.progress.mistakes>=session.maximumMistakes and "failed" or "wrong"
end

function UI.advance(session,phase,message)
    session.phase=phase; session.progress.phase=phase; session.progress.step=1; session.message=message
    return "progress"
end

return UI
