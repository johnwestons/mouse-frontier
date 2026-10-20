-- Shared presentation/input model. Campaign actions are supplied by the host
-- or guest adapter; this module never writes campaign state.
local Style=require('game.ui_layout')
local Typography=require('game.typography')
local Art=require('game.action_menu_art')
local Menu={}; Menu.__index=Menu
Menu.layouts={{id='radial',label='RADIAL WHEEL'},{id='dock',label='QUICK DOCK'},{id='drawer',label='BUTTON DRAWER'}}
local primary={'poses','leave','travel','backpack','map','more'}
local poses={'idle','sit','lay','use'}
local secondary={'upgrade','maintenance','decorate','journal','settings','editor','localPlay'}
local labels={poses='POSES',leave='LEAVE TRAIN',travel='TRAVEL',backpack='BACKPACK',map='MAP',more='MORE',
    idle='STAND',sit='SIT',lay='LAY DOWN',use='USE',upgrade='UPGRADES',maintenance='MAINTENANCE',
    decorate='MOVE / SCALE',journal='JOURNAL',settings='SETTINGS',editor='GUI EDITOR',pause='PAUSE',localPlay='LOCAL PLAY',launcher='ACTIONS',close='CLOSE'}
local function text(value,r,scale,singleLine)
    love.graphics.setColor(1,.94,.79,1)
    Typography.drawText(love.graphics,value,r.x,r.y,r.w,r.h,
        {scale=scale or .85,minScale=singleLine and .52 or .68,align='center',valign='center',singleLine=singleLine})
end
function Menu.element(layout,page,id) return 'actions_'..layout..'_'..page..(id and '_'..id or '') end
function Menu.editorElements()
    local result={}
    for _,layout in ipairs(Menu.layouts) do
        for _,page in ipairs({'dock','main','poses','more'}) do
            result[#result+1]={id=Menu.element(layout.id,page),label=layout.label..' / '..page}
            local list=page=='poses' and poses or page=='more' and secondary or page=='main' and primary or {'launcher','poses','leave','travel','backpack','more','pause'}
            for _,id in ipairs(list) do result[#result+1]={id=Menu.element(layout.id,page,id),label=layout.id..' / '..labels[id]} end
            if page~='dock' then result[#result+1]={id=Menu.element(layout.id,page,'close'),label=layout.id..' / '..page..' close'} end
        end
    end
    return result
end
function Menu.new(options)
    return setmetatable({options=options or {},targets={},pressed={},selected=1,generation=0,visible=false},Menu)
end
function Menu:layout()
    local manager=Style.manager()
    return manager and manager:menuLayout() or 'dock'
end
function Menu:setPage(page)
    self.page=page; self.notice=nil; self.selected=1; self.targets={}; self.generation=self.generation+1
    if self.options.changed then self.options.changed(page) end
end
function Menu:close() self:setPage(nil) end
function Menu:cancelInput() self.pressed={}; self.owner=nil end
function Menu:activate(id)
    if id=='close' then
        return self:setPage(self.page=='more' and (self:layout()~='dock' and 'main' or nil) or nil)
    elseif id=='launcher' then return self:setPage(self.page and nil or 'main')
    elseif id=='poses' then return self:setPage(self.page=='poses' and nil or 'poses')
    elseif id=='more' then return self:setPage(self.page=='more' and nil or 'more') end
    local action=self.actions and self.actions[id]
    if not action or action.enabled==false then self.notice=action and action.reason or 'Unavailable here.'; return false end
    -- Re-query before dispatch: train/connection state may change while open.
    local fresh=self.options.actions and self.options.actions()[id] or action
    if not fresh or fresh.enabled==false then self.notice=fresh and fresh.reason or 'Unavailable here.'; return false end
    self:close()
    local ok,message=fresh.run()
    if ok==false then self.notice=message or 'Action unavailable. Try again when ready.' end
    return ok
end
function Menu:target(id,bounds,shape)
    local r=Style.inputRegion(bounds,shape)
    local action=self.actions[id]
    self.targets[#self.targets+1]={id=id,rect=r,enabled=not action or action.enabled~=false}
    return r
end
function Menu:tile(layout,page,id,r,frame)
    Style.scope(Menu.element(layout,page,id),r,function()
        local a=self.actions[id];local disabled=a and a.enabled==false
        local selected=self.focus and self.selected==#self.targets+1
        Art.frame(frame or 'tile',r,selected,disabled)
        local iconSize=frame=='center' and math.min(r.w,r.h)*.34 or math.min(r.w*.50,r.h*.40)
        Art.icon(id,r.x+r.w/2,r.y+r.h*(frame=='center' and .38 or .34),iconSize,disabled)
        local label=a and a.label or labels[id]
        if page=='dock' and id=='leave' and label=='LEAVE TRAIN' then label='LEAVE' end
        if page=='dock' and id=='backpack' then label='PACK' end
        text(label,{x=r.x+4,y=r.y+r.h*.55,w=r.w-8,h=r.h*.34},.85,true)
        self:target(id,r,frame=='center' and function(x,y)
            local dx,dy=(x-r.x-r.w/2)/(r.w/2),(y-r.y-r.h/2)/(r.h/2)
            return dx*dx+dy*dy<=1
        end or nil)
    end)
end
function Menu:wheel(layout,page,list,cx,cy,radius)
    local g=love.graphics;local count=#list;local step=math.pi*2/count
    local bounds={x=cx-radius,y=cy-radius,w=radius*2,h=radius*2}
    Style.scope(Menu.element(layout,page),bounds,function()
        for i,id in ipairs(list) do
            local angle=-math.pi/2+(i-1)*step
            local function inside(x,y)
                local dx,dy=x-cx,y-cy;local distance=math.sqrt(dx*dx+dy*dy)
                local a=(math.atan2(dy,dx)-angle+math.pi)%(2*math.pi)-math.pi
                return distance>=radius*.36 and distance<=radius and math.abs(a)<=step/2
            end
            -- Each authored slice is independently editable. Its original
            -- bounds describe only that slice, not the entire wheel.
            local points={};local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
            for n=0,24 do
                local a=angle-step/2+step*n/24
                for _,dist in ipairs({radius*.36,radius}) do
                    local x,y=cx+math.cos(a)*dist,cy+math.sin(a)*dist
                    minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
                end
            end
            local rect={x=minX,y=minY,w=maxX-minX,h=maxY-minY}
            Style.scope(Menu.element(layout,page,id),rect,function()
                local a=self.actions[id];local disabled=a and a.enabled==false
                -- Stencil clips the authored ring into movable pieces. It
                -- never generates the visible frame artwork.
                local vertices={cx,cy}
                for n=0,24 do
                    local theta=angle-step/2+step*n/24
                    vertices[#vertices+1]=cx+math.cos(theta)*radius*1.2
                    vertices[#vertices+1]=cy+math.sin(theta)*radius*1.2
                end
                g.stencil(function() g.polygon('fill',vertices) end,'replace',1)
                g.setStencilTest('greater',0)
                local selected=self.focus and self.selected==#self.targets+1
                g.setColor(disabled and .52 or 1,disabled and .52 or (selected and .82 or 1),disabled and .52 or (selected and .45 or 1),1)
                Art.wheel(count==4 and 'poses' or 'radial',cx,cy,radius)
                g.setStencilTest()
                local px,py=cx+math.cos(angle)*radius*.67,cy+math.sin(angle)*radius*.67
                -- Keep the combined glyph/label block inside the wheel outline.
                py=py-(math.sin(angle)>0 and 13 or 0)
                Art.icon(id,px,py-13,count==4 and 46 or 42,disabled)
                local label=a and a.label or labels[id]
                if id=='leave' then label=({['LEAVE TRAIN']='LEAVE',['BOARD TRAIN']='BOARD',['RETURN TO STOP']='RETURN',['EXIT HOME']='EXIT'})[label] or label end
                text(label,{x=px-49,y=py+11,w=98,h=32},.82)
                self:target(id,rect,inside)
            end)
        end
        local center={x=cx-radius*.36,y=cy-radius*.36,w=radius*.72,h=radius*.72}
        self:tile(layout,page,'close',center,'center')
    end)
end
function Menu:draw(canvas,preview)
    local layout=self:layout()
    if layout~=self.lastLayout then self.lastLayout=layout; self:close(); self:cancelInput() end
    local previouslySelected=self.targets[self.selected]
    local previouslySelectedId=previouslySelected and previouslySelected.id
    self.visible=true; self.actions=self.options.actions and self.options.actions() or {}; self.targets={}
    local right=canvas.right-18
    local sidebar=self.options.rightHudX and self.options.rightHudX()
    -- Wide play screens reserve a right gutter for the home objective. Keep
    -- the controls just left of that gutter; compact screens use the full
    -- available width instead.
    local safeRight=sidebar and math.min(right,sidebar-51) or right
    local warning=self.notice
    if not warning and self.focus then
        local action=previouslySelectedId and self.actions[previouslySelectedId]
        warning=action and action.enabled==false and action.reason
    end
    local page=preview or self.page
    if page=='closed' then page=nil end
    local buttonW,buttonH,gap=60,50,5
    local dockY=canvas.bottom-116
    local dockWidth=layout=='dock' and buttonW*5+gap*4 or buttonW*2+gap
    local dock={x=safeRight-dockWidth,y=dockY,w=dockWidth,h=buttonH}
    Style.scope(Menu.element(layout,'dock'),dock,function()
        if layout=='dock' then
            for i,id in ipairs({'poses','leave','travel','backpack','more'}) do
                self:tile(layout,'dock',id,{x=dock.x+(i-1)*(buttonW+gap),y=dock.y,w=buttonW,h=buttonH})
            end
        else
            self:tile(layout,'dock','backpack',{x=dock.x,y=dock.y,w=buttonW,h=buttonH})
            self:tile(layout,'dock','launcher',{x=dock.x+buttonW+gap,y=dock.y,w=buttonW,h=buttonH})
        end
    end)
    self:tile(layout,'dock','pause',{x=canvas.right-102,y=canvas.top+6,w=84,h=64})
    if page=='main' and layout=='radial' or page=='poses' and layout~='drawer' then
        local radius=120
        self:wheel(layout,page,page=='poses' and poses or primary,safeRight-radius-4,dockY-12-radius,radius)
    elseif page then
        local list=page=='poses' and poses or page=='more' and secondary or primary
        local rows=math.ceil(#list/2);local panelWidth=216;local panelHeight=64+rows*56
        local warningHeight=warning and 36 or 0
        local panelBottom=dockY-2-warningHeight
        local r={x=safeRight-panelWidth,y=math.max(canvas.top+12,panelBottom-panelHeight),w=panelWidth,h=panelHeight}
        Style.scope(Menu.element(layout,page),r,function()
            Art.frame('panel',r)
            text(page=='poses' and 'POSES' or page=='more' and 'MORE ACTIONS' or 'ACTIONS',{x=r.x+12,y=r.y+8,w=124,h=36},.82,true)
            self:tile(layout,page,'close',{x=r.x+r.w-72,y=r.y+10,w=60,h=36})
            for i,id in ipairs(list) do
                self:tile(layout,page,id,{x=r.x+12+(i-1)%2*104,y=r.y+52+math.floor((i-1)/2)*56,w=96,h=50})
            end
        end)
        if warning then
            local noticeRect={x=safeRight-panelWidth,y=dockY-34,w=panelWidth,h=28}
            Art.frame('panel',noticeRect);text(warning,noticeRect,.62)
        end
    end
    if warning and page and (layout=='radial' and (page=='main' or page=='poses')) then
        local r={x=safeRight-216,y=dockY-12-240-34,w=216,h=28}
        Art.frame('panel',r);text(warning,r,.62)
    elseif warning and not page then
        local r={x=safeRight-216,y=dockY-34,w=216,h=28}
        Art.frame('panel',r);text(warning,r,.62)
    end
end
function Menu:hide()
    self.visible=false;self.targets={}
    if self.page then self:close() end
    -- Retain captured pointer IDs until release, so hidden controls never leak
    -- their release into a newly opened minigame or another screen.
end
function Menu:at(x,y)
    for i=#self.targets,1,-1 do if self.targets[i].rect:contains(x,y) then return self.targets[i],i end end
end
function Menu:press(pointer,x,y)
    if not self.visible then return false end
    local target,index=self:at(x,y)
    if not target and not self.page then return false end
    self.pressed[pointer]={id=target and target.id,generation=self.generation}
    if not self.owner then self.owner=pointer; self.selected=index or self.selected end
    self.focus=false
    return true
end
function Menu:release(pointer,x,y)
    local down=self.pressed[pointer]
    if not down then return false end
    self.pressed[pointer]=nil
    if self.owner~=pointer then return true end
    self.owner=nil
    if not self.visible or down.generation~=self.generation then return true end
    local target=self:at(x,y)
    if target and down.id==target.id then self:activate(target.id)
    elseif not down.id and not target then self:close() end
    return true
end
function Menu:key(key)
    if not self.visible then return false end
    if key=='f2' or key=='f8' then return false end
    if key=='escape' or key=='acback' then if self.page then self:close();return true end;return false end
    if not self.page then return false end
    self.focus=true
    if key=='left' or key=='up' or key=='dpup' or key=='dpleft' then self.selected=(self.selected-2)%math.max(1,#self.targets)+1
    elseif key=='right' or key=='down' or key=='tab' or key=='dpdown' or key=='dpright' then self.selected=self.selected%math.max(1,#self.targets)+1
    elseif key=='return' or key=='space' or key=='a' then local t=self.targets[self.selected];if t then self:activate(t.id) end
    elseif key=='b' then self:close() end
    return true
end
return Menu
