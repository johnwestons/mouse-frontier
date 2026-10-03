local Model = require("game.outfit_crafting")
local Definitions = require("game.outfit_catalog")
local Art = require("game.outfit_sprite_art")
local Typography = require("game.typography")

local UI = {}
local colors = {
    cream={.98,.90,.72}, muted={.40,.30,.20}, brass={.46,.26,.10},
    green={.17,.34,.18}, red={.61,.18,.12}, ink={.20,.12,.07},
}
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end
local function hit(rect,x,y) return rect and x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h end
local function color(value,alpha) love.graphics.setColor(value[1],value[2],value[3],alpha or 1) end
local function text(value,x,y,w,h,scale,tint,align)
    color(tint or colors.ink)
    Typography.drawText(love.graphics,tostring(value or ""),x,y,w,h,
        {scale=scale or .8,minScale=.68,align=align or "left",valign="center"})
end
local function panel(id,x,y,w,h)
    Art.draw(id,{x=x,y=y,w=w,h=h},{stretch=true})
end
local function title(value) return (tostring(value or ""):gsub("[-_]"," "):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)) end
local statNames={armor="Battle armor",maxHealth="Max health",move="Battle movement",aim="Battle aim",attack="Battle attack",coldProtection="Cold protection"}
local statOrder={"armor","move","maxHealth","aim","attack","coldProtection"}
local function benefitLines(profile)
    local lines={}
    for _,key in ipairs(statOrder) do
        local amount=profile and profile.bonuses and profile.bonuses[key]
        if amount and amount~=0 then lines[#lines+1]=(amount>0 and "+" or "")..amount.." "..statNames[key] end
    end
    return #lines>0 and table.concat(lines,"   ") or "Improves the existing outfit"
end
local function drawBenefits(profile,x,y,w,h,scale,align)
    local entries={}
    for _,key in ipairs(statOrder) do
        local amount=profile and profile.bonuses and profile.bonuses[key]
        if amount and amount~=0 then entries[#entries+1]={label=(amount>0 and "+" or "")..amount.." "..statNames[key],amount=amount} end
    end
    if #entries==0 then text("Improves the existing outfit",x,y,w,h,scale,colors.muted,align); return end
    for index,entry in ipairs(entries) do
        local height=h/#entries
        color(entry.amount>0 and colors.green or colors.red)
        Typography.drawText(love.graphics,entry.label,x,y+(index-1)*height,w,height,
            {scale=scale,minScale=.68,align=align or "left",valign="center",singleLine=true})
    end
end
local function slotLabel(slot) return slot=="armor" and "Underlayer" or "Outfit upgrade" end
local function samePoint(a,b)
    return a and b and math.abs(a.x-b.x)<.001 and math.abs(a.y-b.y)<.001
end
function UI.new(context)
    assert(type(context)=="table" and type(context.data)=="function","outfit crafting UI requires data()")
    local self={visible=false,selected=1,page=1,buttons={},focusId=nil,message="",context=context,
        tension=0,holding=false,dragging=false,time=0,workRect={x=285,y=221,w=390,h=260}}

    function self:isOpen() return self.visible end
    function self:suspend()
        self.holding=false; self.dragging=false; self.heldKey=nil; self.lastDragPoint=nil
        self.blockCoincident=false; self.pointer=nil
    end
    function self:show()
        Model.ensure(context.data()); self.visible=true; self.message=""; self.receipt=nil
        self:suspend(); self.buttons={}; self.focusId=nil
        local project=Model.project(context.data())
        if project then
            for index,recipe in ipairs(Definitions.recipes) do if recipe.id==project.recipeId then self.selected=index; break end end
        end
        self.focusId=project and (project.complete and "collect" or "work") or "start"
        self.page=math.floor((self.selected-1)/5)+1
        if context.cancelInput then context.cancelInput() end
    end
    self.open=self.show
    function self:close()
        self:suspend(); self.visible=false; self.buttons={}
        if context.save then context.save() end
        if context.cancelInput then context.cancelInput() end
        if context.onClose then context.onClose() end
    end
    function self:result(result)
        self.message=result and result.message or ""
        self.messageBad=result and (not result.ok or result.correct==false) or false
        if result and result.changed and context.save then
            if context.save()==false then self.message=self.message.." Saving will retry on close." end
        end
        if result and result.stageComplete then
            self.holding=false; self.dragging=false; self.tension=0; self.lastDragPoint=nil
            self.focusId="work"
        end
        return result
    end
    function self:recipe()
        local project=Model.project(context.data())
        return project and Definitions.recipesById[project.recipeId] or Definitions.recipes[self.selected]
    end
    function self:select(index)
        if Model.project(context.data()) then
            self.message="Finish the project on the bench before choosing another pattern."; self.messageBad=false; return
        end
        self.selected=clamp(index,1,#Definitions.recipes); self.page=math.floor((self.selected-1)/5)+1
        self.message=""; self.receipt=nil
    end
    function self:start()
        local recipe=self:recipe()
        if not recipe then return end
        self.receipt=nil
        local result=self:result(Model.start(context.data(),recipe.id))
        if result.ok then self.focusId="work"; self.tension=0 end
    end
    function self:collect()
        local result=self:result(Model.finish(context.data()))
        if result.ok then self.receipt=result; self.focusId="start" end
    end
    function self:place(x,y)
        local stage=Model.stage(context.data())
        if not stage or stage.kind~="point" then return end
        local current=stage.currentPoint
        local result=self:result(Model.act(context.data(),{kind="point",x=x,y=y}))
        if result.correct then
            self.lastDragPoint=current
            local nextStage=Model.stage(context.data())
            self.blockCoincident=nextStage and samePoint(current,nextStage.currentPoint) or false
        end
    end
    function self:nextPoint()
        local stage=Model.stage(context.data())
        if stage and stage.currentPoint then self:place(stage.currentPoint.x,stage.currentPoint.y) end
    end
    function self:beginPull(source)
        local stage=Model.stage(context.data())
        if not stage or stage.kind~="tension" or self.holding then return end
        self.holding=true; self.heldKey=source; self.focusId="work"
    end
    function self:releasePull()
        local stage=Model.stage(context.data())
        self.holding=false; self.heldKey=nil
        if stage and stage.kind=="tension" then self:result(Model.act(context.data(),{kind="tension",value=self.tension})) end
    end
    function self:adjustTension(amount)
        self.holding=false; self.heldKey=nil; self.tension=clamp(self.tension+amount,0,1)
    end
    function self:button(id,label,x,y,w,h,action,enabled,selected,hold,kind)
        local rect={id=id,x=x,y=y,w=w,h=h,action=action,enabled=enabled~=false,hold=hold}
        self.buttons[#self.buttons+1]=rect
        local focused=self.focusId==id
        local sprite=kind=="card" and ((selected or focused and self.keyboardFocus) and "card-selected" or "card")
            or not rect.enabled and "button-disabled" or (selected or focused) and "button-selected" or "button"
        panel(sprite,x,y,w,h)
        text(label,x+9,y+5,w-18,h-10,.77,kind=="card" and colors.ink or colors.cream,"center")
        return rect
    end
    function self:drawRecipes()
        local project=Model.project(context.data())
        text("PATTERN BOOK",34,130,213,28,.95,colors.ink,"center")
        text("Choose an improvement",34,158,213,23,.70,colors.muted,"center")
        for row=1,5 do
            local index=(self.page-1)*5+row
            local recipe=Definitions.recipes[index]
            if recipe then
                local selected=project and recipe.id==project.recipeId or not project and index==self.selected
                local y=186+(row-1)*67
                self:button("recipe-"..index,"",31,y,220,63,function() self:select(index) end,not project,selected,false,"card")
                Art.draw(recipe.outputIds.usable,{x=39,y=y+9,w=47,h=47})
                text(recipe.label,93,y+7,148,35,.77,colors.ink)
                text("T"..recipe.tier.." / "..(recipe.slot=="armor" and "Underlayer" or "Outfit"),93,y+38,148,21,.68,colors.brass)
            end
        end
        local pages=math.max(1,math.ceil(#Definitions.recipes/5))
        self:button("previous","",35,531,47,43,function() self.page=math.max(1,self.page-1) end,self.page>1)
        Art.draw("icon-left",{x=50,y=542,w=18,h=20})
        panel("paper",91,537,99,30)
        text(self.page.." / "..pages,84,533,109,39,.79,colors.ink,"center")
        self:button("next","",200,531,47,43,function() self.page=math.min(pages,self.page+1) end,self.page<pages)
        Art.draw("icon-right",{x=215,y=542,w=18,h=20})
    end
    function self:drawSupplies(recipe,project)
        local status=Model.status(context.data(),recipe.id)
        panel("paper",711,143,218,494)
        text(project and "PROJECT SUPPLIES" or "MATERIAL LEDGER",726,158,186,29,.83,colors.ink,"center")
        text(project and "Reserved materials" or "Backpack / Needed",726,189,186,23,.69,colors.muted,"center")
        for index,cost in ipairs(status.materials) do
            local y=223+(index-1)*33
            Art.draw(cost.id,{x=723,y=y-1,w=34,h=34})
            text(cost.label,765,y,149,18,.69,colors.ink)
            text(project and (cost.count.." reserved") or (cost.have.." / "..cost.count),765,y+17,149,16,.70,
                (project or cost.missing==0) and colors.green or colors.red)
        end
        text("Tools provided here.",727,393,184,34,.68,colors.muted,"center")
        local outputId=project and project.outputId or self.receipt and self.receipt.outputId
        local quality=project and Model.quality(context.data()) or self.receipt and self.receipt.quality
        local profile=Definitions.upgrades[outputId or recipe.outputIds[quality or "usable"]]
        text(project and "WORKMANSHIP" or self.receipt and "COMPLETED UPGRADE" or "FINISHED BENEFITS",727,435,184,25,.80,colors.ink,"center")
        text(slotLabel(recipe.slot),727,462,184,23,.71,colors.muted,"center")
        drawBenefits(profile,727,491,185,44,.82,"center")
        if project or self.receipt then
            Art.draw("quality-"..(quality or "usable"),{x=792,y=540,w=51,h=40})
            text((Definitions.qualityLabels[quality or "usable"] or title(quality))..(project and not project.complete and " so far" or " quality"),725,581,190,26,.73,colors.brass,"center")
            local _,score=Model.quality(context.data())
            text(project and ("Workmanship "..(score or 100).."%") or "Install from inventory",725,607,190,20,.68,colors.muted,"center")
        else
            local best=Definitions.upgrades[recipe.outputIds.masterwork]
            text("Masterwork: "..benefitLines(best),727,548,184, 50,.69,colors.brass,"center")
            text("Work carefully for better quality.",727,599,184,35,.68,colors.muted,"center")
        end
    end
    function self:drawStagePips(stage)
        local width=math.min(350,stage.stageCount*25)
        local x=480-width/2
        for index=1,stage.stageCount do
            Art.draw(index<stage.stageIndex and "marker-done" or index==stage.stageIndex and "marker-next" or "marker-idle",
                {x=x+(index-1)*(width/stage.stageCount),y=199,w=16,h=16})
        end
    end
    function self:drawGuide(stage)
        local r=self.workRect
        local points=stage.points or {}
        local function position(point) return r.x+point.x*r.w,r.y+point.y*r.h end
        for index=2,#points do
            local x1,y1=position(points[index-1]); local x2,y2=position(points[index])
            local stitched=index<stage.pointIndex and (stage.operation=="stitch" or stage.operation=="secure" or stage.operation=="quilt" or stage.operation=="bind")
            Art.segment(stitched and "stitch" or "chalk-dash",x1,y1,x2,y2,stitched and 6 or 3)
        end
        for index,point in ipairs(points) do
            -- Two needles visit the same saddle-stitch hole on separate presses.
            if not samePoint(point,points[index+1]) or index==stage.pointIndex then
                local x,y=position(point)
                Art.draw(index<stage.pointIndex and "marker-done" or "marker-idle",{x=x-8,y=y-8,w=16,h=16})
            end
        end
        local point=stage.currentPoint
        if point then
            local x,y=position(point)
            Art.draw("marker-next",{x=x-17,y=y-17,w=34,h=34})
            text(tostring(stage.pointIndex),x-13,y-13,26,26,.70,colors.cream,"center")
            Art.tool(stage,{x=clamp(x+18,r.x+12,r.x+r.w-75),y=clamp(y-64,r.y+4,r.y+r.h-75),w=72,h=72})
        end
        local action=stage.operation=="stitch" or stage.operation=="secure" or stage.operation=="quilt" or stage.operation=="bind"
        local detail=(action and "Pass " or "Mark ")..stage.pointIndex.." / "..stage.total
        if point and point.side then detail=detail.."  -  "..(point.side=="front" and "FRONT NEEDLE" or "BACK NEEDLE")
        else detail=detail.."  -  "..stage.tool end
        panel("paper",306,457,349,34)
        text(detail,320,462,321,23,.72,colors.ink,"center")
    end
    function self:drawFinishedSeams(recipe,stageIndex)
        local r=self.workRect
        for index=1,stageIndex-1 do
            local completed=recipe.stages[index]
            if completed.operation=="stitch" or completed.operation=="quilt" or completed.operation=="bind" then
                for pointIndex=2,#(completed.points or {}) do
                    local a,b=completed.points[pointIndex-1],completed.points[pointIndex]
                    Art.segment("stitch",r.x+a.x*r.w,r.y+a.y*r.h,r.x+b.x*r.w,r.y+b.y*r.h,4)
                end
            end
        end
    end
    function self:drawTension(stage)
        local r=self.workRect
        Art.tool(stage,{x=r.x+212,y=r.y+40,w=92,h=92})
        panel("paper",306,361,349,130)
        text("THREAD PULL  "..math.floor(self.tension*100+.5).."%",320,373,321,28,.86,colors.ink,"center")
        local x,y,w=325,412,310
        Art.draw("meter-track",{x=x-5,y=y-4,w=w+10,h=29},{stretch=true})
        Art.draw("meter-fill",{x=x+w*stage.targetRange.min,y=y+1,w=w*(stage.targetRange.max-stage.targetRange.min),h=17},{stretch=true})
        Art.draw("marker-pointer",{x=x+w*self.tension-9,y=y-9,w=18,h=37})
        text("SNUG: "..math.floor(stage.targetRange.min*100).."-"..math.floor(stage.targetRange.max*100).."%",322,450,316,28,.76,colors.green,"center")
    end
    function self:drawWork(recipe,project)
        local stage=Model.stage(context.data())
        panel("paper",286,126,389,72)
        text(recipe.label,301,137,359,30,.93,colors.ink,"center")
        if stage then
            text("STEP "..stage.stageIndex.." / "..stage.stageCount.."  "..stage.label,298,166,365,29,.74,colors.brass,"center")
            self:drawStagePips(stage)
            Art.workpiece(recipe,stage,self.workRect)
            self:drawFinishedSeams(recipe,stage.stageIndex)
            if stage.kind=="tension" then self:drawTension(stage) else self:drawGuide(stage) end
            text(stage.instruction,294,509,382,68,.75,colors.ink)
            if stage.kind=="tension" then
                self:button("less","-",289,588,44,44,function() self:adjustTension(-.05) end)
                self:button("work",self.holding and "RELEASE" or "HOLD TO PULL",338,588,143,44,function() self:beginPull("pointer") end,true,self.holding,true)
                self:button("more","+",486,588,44,44,function() self:adjustTension(.05) end)
                self:button("set","SET TENSION",535,588,143,44,function() self:releasePull() end)
            else
                local sewing=stage.operation=="stitch" or stage.operation=="secure" or stage.operation=="quilt" or stage.operation=="bind"
                self:button("work",sewing and "PLACE NEXT STITCH" or "WORK NEXT MARK",297,588,371,44,function() self:nextPoint() end)
            end
        elseif project and project.complete or self.receipt then
            local result=project or self.receipt
            local profile=Definitions.upgrades[result.outputId]
            text("CONSTRUCTION COMPLETE",302,166,357,26,.76,colors.green,"center")
            Art.workpiece(recipe,{operation="complete",complete=true},{x=285,y=195,w=390,h=230})
            Art.draw("quality-"..result.quality,{x=569,y=240,w= 70,h=70})
            panel("paper",340,387,281,105)
            text(Definitions.qualityLabels[result.quality] or title(result.quality),354,398,253,29,.92,colors.brass,"center")
            drawBenefits(profile,354,434,253,43,.80,"center")
            text(project and "Your improvement is finished. Collect it, then install it in the matching gear slot in your inventory."
                or "The improvement is in your backpack. Install it in the matching gear slot to apply its benefits.",294,509,382,68,.75,colors.ink)
            local status=Model.status(context.data(),recipe.id)
            self:button(project and "collect" or "start",project and "COLLECT UPGRADE" or "CRAFT ANOTHER",297,588,371,44,
                project and function() self:collect() end or function() self:start() end,project~=nil or status.canStart)
        else
            text("Tier "..recipe.tier.."  /  "..slotLabel(recipe.slot),302,166,357,26,.74,colors.brass,"center")
            Art.workpiece(recipe,nil,self.workRect)
            panel("paper",306,457,349,34)
            text("MARK  /  CUT  /  ASSEMBLE  /  SEW",319,462,323,23,.70,colors.ink,"center")
            text(recipe.description,294,505,382,56,.75,colors.ink)
            local status=Model.status(context.data(),recipe.id)
            text(status.canStart and "Materials are consumed when work begins." or "Gather the missing bundles to begin.",294,563,382,20,.69,status.canStart and colors.muted or colors.red,"center")
            self:button("start","BEGIN CRAFTING",297,588,371,44,function() self:start() end,status.canStart)
        end
    end
    function self:draw()
        if not self.visible then return end
        love.graphics.push("all"); self.buttons={}
        Art.background({x=0,y=0,w=960,h=720})
        text("SEWING BENCH", 90,27,665,32,1.27,colors.cream)
        text("Improvements for your character's own outfit",92,60,667,21,.73,colors.cream)
        self:button("close","PAUSE",818,28,98,46,function() self:close() end)
        panel("paper",276,498,418,145)
        self:drawRecipes()
        local project=Model.project(context.data())
        local recipe=self:recipe()
        if recipe then self:drawSupplies(recipe,project); self:drawWork(recipe,project) end
        local stage=Model.stage(context.data())
        local hint=stage and stage.kind=="tension" and "Hold Space / X, then release. Left / Right adjusts the pull. Enter sets it."
            or stage and "Click or trace the numbered marks. Space / X works the next mark."
            or "Choose a pattern. Carry its materials in your backpack. Enter / A selects."
        text(self.message~="" and self.message or hint,39,651,881,26,.72,self.messageBad and {.98,.70,.52} or colors.cream)
        text("Tab / D-pad: choose controls   Esc / B: pause   Construction progress saves as you work.",39,673,881,19,.66,colors.cream)
        love.graphics.pop()
    end
    function self:update(dt)
        if not self.visible then return end
        self.time=self.time+(dt or 0)
        if self.holding then self.tension=clamp(self.tension+math.min(dt or 0,.1)*.24,0,1) end
    end
    function self:mousepressed(x,y,button)
        if not self.visible then return false end
        if button~=1 then return true end
        self.keyboardFocus=false; self.pointer={x=x,y=y}
        for index=#self.buttons,1,-1 do
            local rect=self.buttons[index]
            if hit(rect,x,y) then
                if rect.enabled then
                    self.focusId=rect.id
                    if rect.hold then self:beginPull("pointer") else rect.action() end
                end
                return true
            end
        end
        local stage=Model.stage(context.data())
        if stage and stage.kind=="point" and hit(self.workRect,x,y) then
            self.dragging=true; self.lastDragPoint=nil; self.blockCoincident=false; self.focusId="work"
            self:place((x-self.workRect.x)/self.workRect.w,(y-self.workRect.y)/self.workRect.h)
        end
        return true
    end
    function self:mousemoved(x,y)
        if not self.visible then return false end
        self.pointer={x=x,y=y}
        local stage=Model.stage(context.data())
        if self.dragging and stage and stage.kind=="point" and not self.blockCoincident then
            local px,py=(x-self.workRect.x)/self.workRect.w,(y-self.workRect.y)/self.workRect.h
            local point=stage.currentPoint
            local dx,dy=px-point.x,py-point.y
            -- Trace only acquires the next mark. Empty space between marks is
            -- travel, and must not create hundreds of accidental mistakes.
            if dx*dx+dy*dy<=(stage.tolerance*.85)^2 then self:place(px,py) end
        end
        return true
    end
    function self:mousereleased(x,y,button)
        if not self.visible then return false end
        if button==1 then
            if self.holding and self.heldKey=="pointer" then self:releasePull() end
            self.dragging=false; self.lastDragPoint=nil; self.blockCoincident=false
        end
        return true
    end
    function self:moveFocus(direction)
        local available={}; local current=0
        for _,rect in ipairs(self.buttons) do
            if rect.enabled then
                available[#available+1]=rect
                if rect.id==self.focusId then current=#available end
            end
        end
        if #available>0 then
            self.focusId=available[(current-1+direction)%#available+1].id
            self.keyboardFocus=true
        end
    end
    function self:keypressed(key,scancode,isrepeat)
        if not self.visible then return false end
        if key=="escape" or key=="acback" then self:close(); return true end
        if isrepeat and (key=="space" or key=="return" or key=="kpenter") then return true end
        local stage=Model.stage(context.data())
        self.keyboardFocus=true
        if key=="tab" then
            local reverse=love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lshift","rshift")
            self:moveFocus(reverse and -1 or 1)
        elseif key=="left" or key=="right" then
            if stage and stage.kind=="tension" then self:adjustTension(key=="left" and -.05 or .05); self.focusId="set"
            else self:moveFocus(key=="left" and -1 or 1) end
        elseif key=="up" or key=="down" then
            if not Model.project(context.data()) and (not self.focusId or self.focusId=="start" or self.focusId:match("^recipe%-")) then
                self:select(self.selected+(key=="up" and -1 or 1)); self.focusId="recipe-"..self.selected
            else self:moveFocus(key=="up" and -1 or 1) end
        elseif key=="pageup" or key=="pagedown" then
            self:wheelmoved(0,key=="pageup" and 1 or -1)
        elseif key=="space" then
            if stage and stage.kind=="tension" then self:beginPull("space")
            elseif stage then self:nextPoint(); self.focusId="work"
            elseif Model.project(context.data()) then self:collect()
            else self:start() end
        elseif key=="return" or key=="kpenter" then
            for _,rect in ipairs(self.buttons) do
                if rect.id==self.focusId and rect.enabled then
                    if rect.hold then self:beginPull(key) else rect.action() end
                    return true
                end
            end
            if stage and stage.kind=="tension" then self:releasePull()
            elseif stage then self:nextPoint() end
        end
        return true
    end
    function self:keyreleased(key)
        if not self.visible then return false end
        if self.holding and self.heldKey==key then self:releasePull() end
        return true
    end
    function self:wheelmoved(dx,dy)
        if not self.visible then return false end
        if dy~=0 then self.page=clamp(self.page+(dy<0 and 1 or -1),1,math.max(1,math.ceil(#Definitions.recipes/5))) end
        return true
    end
    function self:gamepadpressed(button)
        local keys={a="return",b="escape",x="space",dpup="up",dpdown="down",dpleft="left",dpright="right",leftshoulder="pageup",rightshoulder="pagedown"}
        if keys[button] then return self:keypressed(keys[button]) end
        return self.visible
    end
    function self:gamepadreleased(button)
        if button=="a" then return self:keyreleased("return") end
        if button=="x" then return self:keyreleased("space") end
        return self.visible
    end

    -- Hosts using the same compact method names as the inventory tools can bind
    -- these without a second controller implementation.
    self.press=self.mousepressed; self.move=self.mousemoved; self.key=self.keypressed
    function self:wheel(delta) return self:wheelmoved(0,delta) end

    return self
end

return UI

