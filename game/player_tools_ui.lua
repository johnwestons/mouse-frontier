local Model=require("game.player_tools_model")
local Layout=require("game.control_layout")
local Typography=require("game.typography")
local UI={}
local function hit(r,x,y) return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end
local function text(value,x,y,w,h,scale)
    love.graphics.setColor(1,.93,.78,1)
    Typography.drawText(love.graphics,tostring(value),x,y,w,h,{scale=scale or .8,minScale=.58,valign="center"})
end
local function panel(x,y,w,h,selected)
    love.graphics.setColor(selected and .28 or .10,selected and .23 or .085,selected and .14 or .065,1)
    love.graphics.rectangle("fill",x,y,w,h,7,7)
    love.graphics.setColor(.64,.46,.24,1)
    love.graphics.rectangle("line",x,y,w,h,7,7)
end
function UI.new(context)
    local self={open=false,tab="Items",query="",category="All",rarity="All",page=1,quantity="1",resourcePage=1,buttons={},message="",context=context}
    function self:focus(field)
        self.field=field
        if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(field~=nil) end
    end
    function self:show()
        self.open=true; self.buttons={}; self.hover=nil; self.message=""
        self.entries=Model.build(context.filesystem,context.ui.atlasItems)
        self:refresh()
        local controls=context.controls()
        if controls then controls:cancelAll(); self.layout=controls:layout() else self.layout=Layout.normalize() end
    end
    function self:close()
        self:finishDrag(); self.open=false; self:focus(nil); self.buttons={}; self.hover=nil
        context.cancelInput()
    end
    function self:refresh()
        self.filtered=Model.filter(self.entries or {},self.query,self.category,self.rarity)
        self.page=math.max(1,math.min(self.page,math.max(1,math.ceil(#self.filtered/6))))
        local found=false
        for _,entry in ipairs(self.filtered) do if entry==self.selected then found=true end end
        if not found then self.selected=self.filtered[1] end
        self.hover=nil
    end
    function self:button(label,x,y,w,h,action,selected)
        local r={x=x,y=y,w=w,h=h,action=action}
        self.buttons[#self.buttons+1]=r
        panel(x,y,w,h,selected); text(label,x+10,y+3,w-20,h-6)
        return r
    end
    function self:saveResult(ok,message)
        self.message=message
        if ok then
            local saved=context.save()
            if not saved then self.message=message.." Save pending; retry on close." end
        end
    end
    function self:preview(entry,x,y,w,h)
        local atlas=context.ui.atlasItems and context.ui.atlasItems[entry.id]
        local img=atlas and atlas.image or context.ui.propImages and context.ui.propImages[entry.id]
        if img then
            local iw,ih=atlas and atlas.w or img:getWidth(),atlas and atlas.h or img:getHeight()
            local scale=math.min((w-12)/iw,(h-12)/ih)
            love.graphics.setColor(1,1,1,1)
            if atlas then love.graphics.draw(img,atlas.quad,x+w/2,y+h/2,0,scale,scale,iw/2,ih/2)
            else love.graphics.draw(img,x+w/2,y+h/2,0,scale,scale,iw/2,ih/2) end
        else text("No sprite",x+5,y+5,w-10,h-10,.65) end
    end
    function self:quantityControls(x,y)
        self:button("-",x,y,46,44,function() self.quantity=tostring(math.max(1,(tonumber(self.quantity) or 1)-1)) end)
        self:button(self.quantity=="" and "Quantity" or self.quantity,x+54,y,120,44,function() self.quantity=""; self:focus("quantity") end,self.field=="quantity")
        self:button("+",x+182,y,46,44,function() self.quantity=tostring(math.min(999999,(tonumber(self.quantity) or 0)+1)) end)
    end
    function self:drawItems()
        self:button(self.query=="" and "Search items..." or self.query,32,132,400,44,function() self:focus("query") end,self.field=="query")
        self:button("Clear",440,132,80,44,function() self.query=""; self.page=1; self:refresh(); self:focus(nil) end)
        local rarities={"All","common","uncommon","rare","legendary"}
        self:button("Rarity: "..self.rarity,530,132,220,44,function()
            local index=1; for i,v in ipairs(rarities) do if v==self.rarity then index=i end end
            self.rarity=rarities[index%#rarities+1]; self.page=1; self:refresh()
        end)
        text(#self.filtered.." items",766,132,164,44)
        for i,category in ipairs(Model.categories) do
            self:button(category,32,190+(i-1)*35,158,31,function() self.category=category; self.page=1; self:refresh() end,self.category==category)
        end
        for row=1,6 do
            local entry=self.filtered[(self.page-1)*6+row]
            if entry then
                local y=190+(row-1)*66
                local r=self:button("",202,y,382,60,function() self.selected=entry; self.hover=nil end,self.selected==entry)
                r.entry=entry
                self:preview(entry,206,y+2,60,56)
                text(entry.label,272,y+4,302,30,.82); text(entry.category.." | "..entry.rarity,272,y+34,302,20,.62)
            end
        end
        if #self.filtered==0 then text("No matching items. Clear search or change filters.",220,230,345,100) end
        panel(600,190,328,414)
        local entry=self.selected
        if entry then
            self:preview(entry,688,200,148,130)
            text(entry.label,614,334,300,42,1)
            text(entry.detail,614,381,300,155,.74)
            text(entry.id,614,554,300,40,.58)
        end
        self:button("Previous",202,596,110,42,function() self.page=math.max(1,self.page-1); self.hover=nil end)
        text(self.page.." / "..math.max(1,math.ceil(#self.filtered/6)),324,596,130,42)
        self:button("Next",474,596,110,42,function() self.page=math.min(math.max(1,math.ceil(#self.filtered/6)),self.page+1); self.hover=nil end)
        self:quantityControls(600,614)
        self:button("ADD",836,614,92,44,function() if self.selected then self:saveResult(Model.grantItem(context.data(),self.selected,self.quantity)) end end)
    end
    function self:drawResources()
        text("Add supplies, scrap, and every ammunition type to the current journey.",34,132,880,42)
        local entries=Model.resources(context.data())
        for row=1,7 do
            local entry=entries[(self.resourcePage-1)*7+row]
            if entry then
                local y=186+(row-1)*55
                panel(36,y,888,49)
                text(entry.label,52,y+4,370,41)
                text("Owned: "..Model.resourceValue(context.data(),entry),435,y+4,250,41)
                self:button("ADD",760,y+3,148,43,function() self:saveResult(Model.grantResource(context.data(),entry,self.quantity)) end)
            end
        end
        self:button("Previous",36,578,140,42,function() self.resourcePage=math.max(1,self.resourcePage-1) end)
        text(self.resourcePage.." / "..math.ceil(#entries/7),196,578,120,42)
        self:button("Next",306,578,140,42,function() self.resourcePage=math.min(math.ceil(#entries/7),self.resourcePage+1) end)
        text("Quantity to add",696,582,228,24,.7); self:quantityControls(696,614)
        for i,value in ipairs({1,10,100,1000}) do self:button(tostring(value),36+(i-1)*106,628,96,36,function() self.quantity=tostring(value) end) end
    end
    function self:controlPreview()
        local w,h=love.graphics.getDimensions()
        local scale=math.min(888/w,412/h)
        return {x=480-w*scale/2,y=192+(412-h*scale)/2,w=w*scale,h=h*scale}
    end
    function self:drawControls()
        text("Drag a control to move it. Positions save for all journeys on this device.",34,132,890,42)
        local p=self:controlPreview(); panel(p.x,p.y,p.w,p.h)
        self.controlRects={}
        for _,key in ipairs(Layout.order) do
            local point=self.layout[key]
            local r={x=p.x+point.x*p.w-37,y=p.y+point.y*p.h-23,w=74,h=46,key=key}
            self.controlRects[#self.controlRects+1]=r
            panel(r.x,r.y,r.w,r.h,self.drag==key); text(Layout.labels[key],r.x+5,r.y+5,r.w-10,r.h-10,.65)
        end
        self:button("RESET POSITIONS",36,616,240,46,function()
            local controls=context.controls()
            if controls then controls:setLayout(nil); self.layout=controls:layout() else self.layout=Layout.normalize() end
            self.message=Layout.reset(context.filesystem) and "Default control positions restored." or "Reset for this session; settings file could not be removed."
        end)
        text("MOVE / USE / ACTION / BACK / MENU / PACK",304,616,612,46,.78)
    end
    function self:draw()
        self.buttons={}
        love.graphics.setColor(.045,.035,.025,1); love.graphics.rectangle("fill",0,0,960,720)
        text("PLAYER OPTIONS",32,20,680,46,1.35)
        self:button("CLOSE",804,24,124,44,function() self:close() end)
        for i,tab in ipairs({"Items","Cheats","Controls"}) do
            self:button(tab:upper(),32+(i-1)*300,80,288,42,function() self:finishDrag(); self.tab=tab; self.hover=nil; self:focus(nil) end,self.tab==tab)
        end
        if self.tab=="Items" then self:drawItems() elseif self.tab=="Cheats" then self:drawResources() else self:drawControls() end
        local data=context.data()
        local status=self.message
        if status=="" then status=data and "Changes apply to your current journey.  F2 / Esc: close" or "Load a journey to add items or resources. Control positions can be edited now." end
        text(status,32,670,896,40,.72)
        if self.hover and self.tab=="Items" then
            local entry=self.hover
            panel(600,190,328,414,true)
            self:preview(entry,688,200,148,130)
            text(entry.label,614,334,300,42,1); text(entry.detail,614,381,300,175,.74)
            text("Click to select",614,563,300,30,.65)
        end
    end
    function self:press(x,y,button)
        if button~=1 then return true end
        for i=#self.buttons,1,-1 do if hit(self.buttons[i],x,y) then self.buttons[i].action(); return true end end
        if self.tab=="Controls" then
            for _,r in ipairs(self.controlRects or {}) do if hit(r,x,y) then self.drag=r.key; self.dragOffsetX=x-(r.x+r.w/2); self.dragOffsetY=y-(r.y+r.h/2); return true end end
        end
        self:focus(nil); return true
    end
    function self:move(x,y)
        self.hover=nil
        if self.drag then
            local p=self:controlPreview()
            self.layout[self.drag]={x=(x-self.dragOffsetX-p.x)/p.w,y=(y-self.dragOffsetY-p.y)/p.h}
            self.layout=Layout.normalize(self.layout)
            local controls=context.controls(); if controls then controls:setLayout(self.layout) end
        else for _,r in ipairs(self.buttons) do if r.entry and hit(r,x,y) then self.hover=r.entry end end end
    end
    function self:finishDrag()
        if self.drag then
            self.drag=nil
            self.message=Layout.save(context.filesystem,self.layout) and "Control positions saved." or "Positions changed for this session; could not save settings."
        end
    end
    function self:key(key)
        if key=="escape" or key=="acback" then if self.field then self:focus(nil) else self:close() end
        elseif key=="f2" then self:close()
        elseif key=="return" or key=="kpenter" then self:focus(nil)
        elseif key=="backspace" and self.field then
            local value=self[self.field]
            self[self.field]=value:gsub("[%z\1-\127\194-\244][\128-\191]*$","")
            if self.field=="query" then self.page=1; self:refresh() end
        elseif key=="tab" then self:finishDrag(); self.tab=self.tab=="Items" and "Cheats" or self.tab=="Cheats" and "Controls" or "Items"; self:focus(nil)
        elseif not self.field and (key=="pagedown" or key=="pageup") then self:wheel(key=="pagedown" and -1 or 1) end
        return true
    end
    function self:textinput(value)
        if self.field=="query" then
            if #self.query+#value<=100 then self.query=self.query..value end
            self.page=1; self:refresh()
        elseif self.field=="quantity" then self.quantity=(self.quantity..value:gsub("[^0-9]","")):sub(1,6) end
    end
    function self:wheel(delta)
        if self.tab=="Items" then self.page=math.max(1,math.min(math.max(1,math.ceil(#self.filtered/6)),self.page+(delta<0 and 1 or -1))); self.hover=nil
        elseif self.tab=="Cheats" then self.resourcePage=math.max(1,math.min(math.ceil(#Model.resources(context.data())/7),self.resourcePage+(delta<0 and 1 or -1))) end
    end
    return self
end
return UI
