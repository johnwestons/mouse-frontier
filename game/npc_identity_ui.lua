-- Presentation only. No name allocation, quest preparation, or actor changes.
local Identity=require('game.npc_identity')
local Targets=require('game.npc_targets')
local Typography=require('game.typography')
local Wide=require('game.wide_layout')
local Accessibility=require('game.accessibility')
local Preferences=require('game.local_preferences')
local UI={}
function UI.model(data,reference)
    local person=reference and Identity.get(data,reference)
    local quest=person and Targets.pending(data,person.id)
    if not person and (data.scene=='stop' or data.scene=='house') then
        for _,collection in ipairs({data.mailQuests or {},data.supplyQuests or {}}) do
            for _,q in ipairs(collection) do if not q.complete and q.destination==data.location and q.recipientId then
                quest=q; person=Identity.get(data,q.recipientId); break
            end end
            if person then break end
        end
    end
    if not person then return nil end
    return {id=person.id,name=person.name,role=person.species..' • '..person.role,portrait=person.file,
        location=quest and Targets.directions(data,quest) or ('Home: Stop '..person.homeStop),
        nearby=reference~=nil,delivery=quest~=nil}
end
function UI.draw(c)
    local model=UI.model(c.data,c.reference)
    if not model then return nil end
    local g=love.graphics; local ww,wh=g.getDimensions(); local layout=Wide.measure(960,720,ww,wh)
    local x,w=layout.sidePanels and layout.rightX or 764,layout.sidePanels and layout.panelWidth or 184
    local y,h=252,280
    g.setColor(.065,.045,.030,.96); g.rectangle('fill',x,y,w,h,8,8)
    local img=c.images and c.images[model.portrait] or c.characterImages and c.characterImages[model.portrait]
    if img then
        local iw,ih=img:getDimensions(); local scale=math.min(54/iw,64/ih)
        g.setColor(1,1,1); g.draw(img,x+w/2,y+42,0,scale,scale,iw/2,ih/2)
    end
    local settings=(Preferences.view(c.data) or {}).accessibility or {}
    local fits=true; local scale=Accessibility.textSizes[tonumber(settings.textSize) or 1] or 1
    local function line(value,offset,height,size,color)
        g.setColor(color)
        local _,_,_,ok=Typography.drawText(g,value,x+12,y+offset,w-24,height,
            {scale=size*scale,minScale=.65,align='center',valign='center'})
        fits=fits and ok
    end
    line(model.name,78,48,.85,{.85,.62,.28,1})
    line(model.role,130,38,.72,{.87,.80,.65,1})
    line(model.location,172,50,.68,{.87,.80,.65,1})
    local hint=model.nearby and ((c.key or 'E')..'  TALK') or 'FIND RECIPIENT'
    if model.delivery and model.nearby then hint=(c.key or 'E')..'  DELIVER' end
    if settings.controlHints==false then hint=model.delivery and 'DELIVERY TARGET' or '' end
    line(hint,232,34,.68,{.85,.62,.28,1})
    model.x,model.y,model.w,model.h=x,y,w,h; model.textFits=fits
    return model
end
return UI
