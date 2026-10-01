local Editor={}
local Viewport=require("game.viewport")
local WIDTH,HEIGHT=304,480
local elements={"journeyHud","resourceHud","mobileControls","sceneControls","returnTrain","returnStop","exitHome","expeditionHud","journeyMenu","journeyLog","inventory","map","dialogue","travelConfirm","event","trainUpgrades","trade","options","pauseMenu","confirmation","exitPrompt","poseMenu","radio","firstAid","maintenance","shootingRange","lastStand","battle","slots","characters","ending"}
local names={journeyHud="Journey HUD",resourceHud="Resource bars",mobileControls="Touch controls",sceneControls="Scene controls",returnTrain="Return to train",returnStop="Return to stop",exitHome="Exit home",expeditionHud="Expedition HUD",journeyMenu="Journey menu",journeyLog="Journey log",inventory="Inventory",map="Map",dialogue="Dialogue",travelConfirm="Travel panel",event="Event choices",trainUpgrades="Train workshop",trade="Trading panel",options="Options panel",pauseMenu="Pause menu",confirmation="Confirmation panel",exitPrompt="Exit prompt",poseMenu="Pose menu",radio="Radio panel",firstAid="First aid panel",maintenance="Maintenance panel",shootingRange="Shooting range",lastStand="Last Stand",battle="Battle screen",slots="Journey slots",characters="Traveler select",ending="Ending screen"}
local function clamp(value,low,high) return math.max(low,math.min(high,value)) end
local function hit(r,x,y) return r and x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function down(key) return love.keyboard and love.keyboard.isDown and love.keyboard.isDown(key) end

function Editor.attach(self,context,widgets)
    local manager=context.uiedit
    local text,panel=widgets.text,widgets.panel
    self.uiPanel={x=644,y=16,collapsed=false,section="Layout"}
    self.uiHistory={}

    function self:editorCanvas()
        local w,h=love.graphics.getDimensions()
        local x,y,sx,sy=Viewport.transform(960,720)
        return {left=-x/sx,top=-y/sy,right=(w-x)/sx,bottom=(h-y)/sy}
    end
    function self:editorRect()
        local p=self.uiPanel
        local bounds=self:editorCanvas()
        local h=p.collapsed and 40 or HEIGHT
        p.x=clamp(p.x,bounds.left+4,bounds.right-WIDTH-4)
        p.y=clamp(p.y,bounds.top+4,bounds.bottom-h-4)
        return {x=p.x,y=p.y,w=WIDTH,h=h}
    end
    function self:editorParts(all)
        local result={}
        if not manager then return result end
        for _,id in ipairs(elements) do
            if manager.liveRects[manager:elementKey(id)] then result[#result+1]=id end
        end
        if all then
            for _,id in ipairs(elements) do
                if not manager.liveRects[manager:elementKey(id)] then result[#result+1]=id end
            end
        end
        return result
    end
    function self:selectUiPart(id)
        self:finishDrag()
        self.uiElement=id; manager.selected=id; self.uiPicker=false; self.uiResetConfirm=false
        self.message=""
    end
    function self:cycleUiPart(direction)
        local list=self:editorParts(false)
        if #list==0 then list=self:editorParts(true) end
        local index=direction>0 and 0 or 1
        for i,id in ipairs(list) do if id==self.uiElement then index=i end end
        if #list>0 then self:selectUiPart(list[(index-1+direction)%#list+1]) end
    end
    function self:editorHistory()
        local slot=manager.activeSlot
        self.uiHistory[slot]=self.uiHistory[slot] or {undo={},redo={}}
        return self.uiHistory[slot]
    end
    function self:rememberUi(before)
        if same(before,manager:snapshotSlot()) then return false end
        local history=self:editorHistory()
        history.undo[#history.undo+1]=before; history.redo={}
        if #history.undo>40 then table.remove(history.undo,1) end
        return true
    end
    function self:saveUi(message)
        local saved=manager:save()
        self.message=saved and (message or ("Saved to preset "..manager.activeSlot..".")) or "Save failed. Changes kept here; tap SAVE to retry."
        return saved
    end
    function self:editUi(values)
        self:finishDrag()
        self.uiResetConfirm=false
        local before=manager:snapshotSlot()
        manager:set(self.uiElement,values,false)
        if self:rememberUi(before) then self:saveUi() end
    end
    function self:undoUi(redo)
        self:finishDrag()
        self.uiResetConfirm=false
        local history=self:editorHistory()
        local source,target=redo and history.redo or history.undo,redo and history.undo or history.redo
        if #source==0 then self.message=redo and "Nothing to redo." or "Nothing to undo."; return end
        target[#target+1]=manager:snapshotSlot()
        manager:restoreSlot(table.remove(source),false)
        self:saveUi(redo and "Change redone and saved." or "Change undone and saved.")
    end
    function self:nudgeUi(dx,dy)
        if manager.moveDelta then dx,dy=manager:moveDelta(self.uiElement,dx,dy) end
        local style=manager:get(self.uiElement)
        self:editUi({x=style.x+dx,y=style.y+dy})
    end
    function self:changeUiSlider(x,slider)
        if not manager or not slider then return end
        local progress=clamp((x-slider.trackX)/slider.trackW,0,1)
        local value=slider.low+progress*(slider.high-slider.low)
        if slider.step then value=math.floor(value/slider.step+.5)*slider.step end
        manager:set(slider.element,{[slider.key]=value},false,slider.screen)
    end
    function self:uiSlider(label,key,x,y,w,low,high,value,step)
        local display=key=="rotation" and string.format("%d deg",value)
            or key=="hue" and string.format("%+d deg",value*360)
            or string.format("%d%%",value*100+.5)
        text(label,x,y,w-80,20,.67); text(display,x+w-78,y,78,20,.67)
        local trackY=y+29
        love.graphics.setColor(.20,.16,.10,1); love.graphics.rectangle("fill",x,trackY,w,8,4,4)
        local progress=clamp((value-low)/(high-low),0,1)
        love.graphics.setColor(.84,.52,.19,1); love.graphics.rectangle("fill",x,trackY,w*progress,8,4,4)
        love.graphics.setColor(1,.84,.40,1); love.graphics.circle("fill",x+w*progress,trackY+4,9)
        -- The generous touch target is separate from the visible track endpoints.
        local rect={x=x-7,y=trackY-13,w=w+14,h=34,trackX=x,trackW=w,key=key,low=low,high=high,step=step,
            element=self.uiElement,screen=manager:screenId()}
        self.uiSliderRects[#self.uiSliderRects+1]=rect
    end
    function self:drawUiSelection()
        local r=manager.liveRects[manager:elementKey(self.uiElement)]
        self.uiSelectedRect=r; self.uiHandleRect=nil; self.uiMoveHandleRect=nil
        if not r then return end
        local gfx=love.graphics
        gfx.setColor(1,.77,.27,.95); gfx.setLineWidth(2)
        gfx.rectangle("line",r.x,r.y,r.w,r.h)
        local bounds=self:editorCanvas()
        local function grip(x,y)
            return {x=clamp(x-15,bounds.left+4,bounds.right-34),y=clamp(y-15,bounds.top+4,bounds.bottom-34),w=30,h=30}
        end
        self.uiMoveHandleRect=grip(r.x+r.w/2,r.y)
        self.uiHandleRect=grip(r.x+r.w,r.y+r.h)
        local m,s=self.uiMoveHandleRect,self.uiHandleRect
        panel(m.x,m.y,m.w,m.h,true); text("+",m.x,m.y,m.w,m.h,.9)
        panel(s.x,s.y,s.w,s.h,true)
        gfx.setColor(1,.77,.27,1); gfx.line(s.x+8,s.y+22,s.x+22,s.y+8)
        gfx.line(s.x+13,s.y+8,s.x+22,s.y+8,s.x+22,s.y+17)
        gfx.setLineWidth(1)
    end
    function self:drawUiPicker(x,y)
        local list=self:editorParts(self.uiShowAll)
        local pages=math.max(1,math.ceil(#list/5))
        self.uiPickerPage=clamp(self.uiPickerPage or 1,1,pages)
        self:button(self.uiShowAll and "ALL PARTS" or "VISIBLE PARTS",x+12,y+150,180,34,function()
            self.uiShowAll=not self.uiShowAll; self.uiPickerPage=1
        end)
        self:button("BACK",x+200,y+150,92,34,function() self.uiPicker=false end)
        for row=1,5 do
            local id=list[(self.uiPickerPage-1)*5+row]
            if id then
                local visible=manager.liveRects[manager:elementKey(id)]~=nil
                self:button((names[id] or id)..(visible and "" or " (hidden)"),x+12,y+190+(row-1)*40,280,36,
                    function() self:selectUiPart(id) end,self.uiElement==id)
            end
        end
        if #list==0 then text("No editable UI is visible on this screen.",x+20,y+202,264,80,.74) end
        self:button("<",x+12,y+398,62,34,function() self.uiPickerPage=math.max(1,self.uiPickerPage-1) end)
        text(self.uiPickerPage.." / "..pages,x+84,y+398,136,34,.75)
        self:button(">",x+230,y+398,62,34,function() self.uiPickerPage=math.min(pages,self.uiPickerPage+1) end)
        text("Tap a visible UI part to select and move it.",x+12,y+438,280,34,.62)
    end
    function self:drawUIEditor()
        self.uiSliderRects={}
        local r=self:editorRect(); local x,y=r.x,r.y
        if manager then
            local screen=manager:screenId()
            if self.uiEditorScreen~=screen then
                self.uiEditorScreen=screen
                local visible=self:editorParts(false)
                if not manager.liveRects[manager:elementKey(self.uiElement)] and visible[1] then
                    self.uiElement=visible[1]; manager.selected=self.uiElement
                end
            end
            self:drawUiSelection()
        end
        panel(x,y,r.w,r.h)
        panel(x,y,WIDTH,40,true)
        self.uiPanelHeader={x=x,y=y,w=168,h=40}
        text("UI EDITOR  ::",x+10,y+3,154,34,.78)
        self:button("<",x+168,y+3,40,34,function() self:finishDrag(); self.tab="Controls" end)
        self:button(self.uiPanel.collapsed and "+" or "-",x+212,y+3,40,34,function()
            self:finishDrag(); self.uiPanel.collapsed=not self.uiPanel.collapsed; self:editorRect()
        end)
        self:button("X",x+256,y+3,40,34,function() self:close() end)
        if self.uiPanel.collapsed then return end
        if not manager then text("UI editor is unavailable.",x+12,y+60,280,70); return end
        local style=manager:get(self.uiElement)
        local visible=manager.liveRects[manager:elementKey(self.uiElement)]~=nil
        text(manager:screenId():gsub("_"," ").." / drag title to move",x+12,y+43,280,20,.59)
        self:button("<",x+12,y+66,36,36,function() self:cycleUiPart(-1) end)
        self:button(names[self.uiElement] or self.uiElement,x+54,y+66,196,36,function()
            self:finishDrag(); self.uiPicker=not self.uiPicker; self.uiPickerPage=1
        end,true)
        self:button(">",x+256,y+66,36,36,function() self:cycleUiPart(1) end)
        for slot=1,3 do
            self:button("P"..slot,x+12+(slot-1)*72,y+110,64,32,function()
                self:finishDrag(); self.uiResetConfirm=false
                local saved=manager:useSlot(slot)
                self.message=saved and ("Preset "..slot.." active. Edits save automatically.") or "Preset active here; could not save. Tap SAVE to retry."
            end,manager.activeSlot==slot)
        end
        self:button("SAVE",x+228,y+110,64,32,function() self:finishDrag(); self:saveUi() end)
        if self.uiPicker then self:drawUiPicker(x,y); return end
        for i,section in ipairs({"Layout","Color","Art"}) do
            self:button(section:upper(),x+12+(i-1)*96,y+150,88,34,function()
                self:finishDrag(); self.uiPanel.section=section; self.uiResetConfirm=false
            end,self.uiPanel.section==section)
        end
        if self.uiPanel.section=="Layout" then
            self:uiSlider("UI SCALE","scale",x+20,y+194,264,.45,2.5,style.scale,.01)
            self:uiSlider("ROTATION","rotation",x+20,y+244,264,-180,180,style.rotation,1)
            text(string.format("POSITION  X %+.0f   Y %+.0f",style.x,style.y),x+12,y+294,280,24,.67)
            local moves={{"<",-10,0},{">",10,0},{"^",0,-10},{"v",0,10}}
            for i,move in ipairs(moves) do
                self:button(move[1],x+12+(i-1)*46,y+322,40,36,function() self:nudgeUi(move[2],move[3]) end)
            end
            self:button("HOME",x+200,y+322,92,36,function() self:editUi({x=0,y=0}) end)
            text("Drag UI to move; corner to scale. Arrow keys: 1px. Shift: 10px.",x+12,y+362,280,30,.58)
        elseif self.uiPanel.section=="Color" then
            self:uiSlider("HUE SHIFT","hue",x+20,y+194,264,-.5,.5,style.hue,.001)
            self:uiSlider("SATURATION","saturation",x+20,y+250,264,0,2,style.saturation,.01)
            self:uiSlider("COLOR TINT","colorTint",x+20,y+306,264,0,1,style.colorTint,.01)
            text("Tint adds color to pale UI. Hue chooses the color.",x+12,y+362,280,30,.6)
        else
            local fontLabel=not style.fontOverride and "AUTO" or style.font:upper()
            self:button("FONT: "..fontLabel,x+12,y+194,136,36,function()
                if not style.fontOverride then self:editUi({font="regular",fontOverride=true})
                elseif style.font=="regular" then self:editUi({font="bold",fontOverride=true})
                else self:editUi({font="regular",fontOverride=false}) end
            end)
            local frames={0}
            for index,frame in pairs(context.ui.menuFrames or {}) do
                if type(index)=="number" and index>0 and frame then frames[#frames+1]=index end
            end
            table.sort(frames)
            self:button("FRAME: "..(style.frame==0 and "AUTO" or style.frame),x+156,y+194,136,36,function()
                if #frames<2 then self.message="No alternate frame art is loaded."; return end
                local index=1; for i,id in ipairs(frames) do if id==style.frame then index=i end end
                self:editUi({frame=frames[index%#frames+1]})
            end)
            local icons={"default"}
            if self.uiElement=="inventory" or self.uiElement=="trade" or self.uiElement=="battle" then icons={"default","atlas","prop"} end
            self:button(#icons>1 and ("ICONS: "..string.upper(style.iconVariant)) or "ICONS: ORIGINAL",x+12,y+238,280,36,function()
                if #icons<2 then self.message="This UI has no alternate icon art."; return end
                local index=1; for i,id in ipairs(icons) do if id==style.iconVariant then index=i end end
                self:editUi({iconVariant=icons[index%#icons+1]})
            end)
            self:uiSlider("TEXT SIZE","textScale",x+20,y+282,264,.5,2.5,style.textScale,.01)
            self:uiSlider("ICON SIZE","iconScale",x+20,y+332,264,.5,2,style.iconScale,.01)
            text("Text follows UI scale; art varies.",x+12,y+376,280,18,.57)
        end
        self:button("UNDO",x+12,y+398,86,34,function() self:undoUi(false) end,#self:editorHistory().undo>0)
        self:button("REDO",x+108,y+398,86,34,function() self:undoUi(true) end,#self:editorHistory().redo>0)
        self:button(self.uiResetConfirm and "CONFIRM" or "RESET",x+204,y+398,88,34,function()
            if not self.uiResetConfirm then self.uiResetConfirm=true; self.message="Tap CONFIRM to reset this UI part. Undo is available."; return end
            self:finishDrag(); local before=manager:snapshotSlot()
            local snapshot=manager:snapshotSlot(); snapshot[manager:elementKey(self.uiElement)]=nil
            manager:restoreSlot(snapshot,false); self:rememberUi(before); self.uiResetConfirm=false; self:saveUi("UI part reset and saved.")
        end)
        local status=self.message~="" and self.message or (visible and "Auto-save on release. Drag title; - folds panel." or "This part is hidden. Open its screen to preview it.")
        if self.uiPanel.section=="Color" and manager.lastColorError then status="Color preview is limited on this device." end
        text(status,x+12,y+438,280,34,.59)
    end
    function self:pressUiEditor(x,y)
        if hit(self.uiPanelHeader,x,y) then
            self:finishDrag(); self.uiPanelDrag={dx=x-self.uiPanel.x,dy=y-self.uiPanel.y}; return true
        end
        for _,r in ipairs(self.uiSliderRects or {}) do
            if hit(r,x,y) then
                self:finishDrag(); self.uiResetConfirm=false; self.uiEditBefore=manager:snapshotSlot(); self.uiSliderDrag=r
                self:changeUiSlider(x,r); return true
            end
        end
        if hit(self:editorRect(),x,y) then return true end
        if not manager then return true end
        self.uiPicker=false; self.uiResetConfirm=false
        local scale=hit(self.uiHandleRect,x,y)
        local move=hit(self.uiMoveHandleRect,x,y)
        if not scale and not move then
            local best,area
            for _,id in ipairs(self:editorParts(false)) do
                local r=manager.liveRects[manager:elementKey(id)]
                local inside
                if manager.hitElement then inside=manager:hitElement(id,x,y) else inside=hit(r,x,y) end
                if inside and (not area or r.w*r.h<area) then best=id; area=r.w*r.h end
            end
            if not best then return true end
            self:selectUiPart(best)
        end
        local style=manager:get(self.uiElement)
        local rect=manager.liveRects[manager:elementKey(self.uiElement)]
        if not rect then return true end
        local cx,cy=rect.x+rect.w/2,rect.y+rect.h/2
        self.uiEditBefore=manager:snapshotSlot()
        self.uiDrag={mode=scale and "scale" or "move",startX=x,startY=y,offsetX=style.x,offsetY=style.y,scale=style.scale,
            cx=cx,cy=cy,radius=math.max(20,math.sqrt((x-cx)^2+(y-cy)^2)),element=self.uiElement,screen=manager:screenId()}
        return true
    end
    function self:moveUiEditor(x,y)
        if self.uiPanelDrag then
            self.uiPanel.x=x-self.uiPanelDrag.dx; self.uiPanel.y=y-self.uiPanelDrag.dy; self:editorRect()
        elseif self.uiSliderDrag then self:changeUiSlider(x,self.uiSliderDrag)
        elseif self.uiDrag then
            local d=self.uiDrag
            if d.mode=="scale" then
                local radius=math.sqrt((x-d.cx)^2+(y-d.cy)^2)
                manager:set(d.element,{scale=d.scale*radius/d.radius},false,d.screen)
            else
                local dx,dy=x-d.startX,y-d.startY
                if manager.moveDelta then dx,dy=manager:moveDelta(d.element,dx,dy,d.screen) end
                manager:set(d.element,{x=d.offsetX+dx,y=d.offsetY+dy},false,d.screen)
            end
        end
    end
    function self:finishUiDrag()
        if manager and self.uiEditBefore and self:rememberUi(self.uiEditBefore) then self:saveUi() end
        self.uiEditBefore=nil; self.uiDrag=nil; self.uiSliderDrag=nil; self.uiPanelDrag=nil
    end
    function self:keyUiEditor(key)
        if key=="escape" or key=="acback" then
            if self.uiPicker or self.uiResetConfirm then self.uiPicker=false; self.uiResetConfirm=false; self.message=""; return true end
            return false
        end
        if key=="h" then self:finishDrag(); self.uiPanel.collapsed=not self.uiPanel.collapsed; self:editorRect(); return true end
        if not manager then return false end
        local ctrl=down("lctrl") or down("rctrl") or down("lgui") or down("rgui")
        local shift=down("lshift") or down("rshift")
        if ctrl and (key=="z" or key=="y") then self:undoUi(key=="y" or shift); return true end
        local step=shift and 10 or 1
        if key=="left" then self:nudgeUi(-step,0)
        elseif key=="right" then self:nudgeUi(step,0)
        elseif key=="up" then self:nudgeUi(0,-step)
        elseif key=="down" then self:nudgeUi(0,step)
        elseif key=="pageup" then self:cycleUiPart(-1)
        elseif key=="pagedown" then self:cycleUiPart(1)
        else return false end
        return true
    end
end
return Editor
