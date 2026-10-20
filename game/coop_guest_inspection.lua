local GuiArt=require('game.gui_art')
-- A private scenery description: opening it never submits a world mutation.
local Hotspots=require('game.stop_hotspots')
local Typography=require('game.typography')
local Util=require('game.util')
local Panel={};Panel.__index=Panel
function Panel.new(view) return setmetatable({view=view,opened=false},Panel) end
function Panel:nearest()
    if not self.view:inputAllowed() then return nil end
    return Hotspots.nearest(self.view.runtime.saveData,self.view.runtime.player)
end
function Panel:open(spot)
    if not self.view:inputAllowed() then return false end
    local runtime=self.view.runtime
    spot=spot and Hotspots.find(runtime.saveData,spot.id) or self:nearest()
    if not spot or spot.kind~='stopInspect' or not Hotspots.inReach(spot,runtime.player) then return false end
    self.spot=spot;self.epoch=self.view.epoch;self.location=runtime.saveData.location
    self.opened=true;self.view:neutralize();return true
end
function Panel:close() self.opened=false;self.spot=nil;return true end
function Panel:update()
    local data=self.view.runtime.saveData
    if self.opened and (not data or data.scene~='stop' or data.location~=self.location or self.view.epoch~=self.epoch) then self:close() end
end
function Panel:targets()
    return {{id='inspection.close',rect={x=380,y=440,w=200,h=56},action=function() return self:close() end}}
end
function Panel:pointer(x,y)
    if not self.opened then return false end
    for _,target in ipairs(self:targets()) do if Util.pointIn(x,y,target.rect) then target.action() end end
    return true
end
function Panel:keypressed(key)
    if not self.opened then return false end
    if key=='escape' or key=='acback' or key=='return' or key=='space' or key=='e' then self:close() end
    return true
end
function Panel:draw()
    if not self.opened then return end
    local g=love.graphics
    g.setColor(.025,.02,.015,.55);g.rectangle('fill',0,0,960,720)
    self.view.inventory:frame(170,205,620,315,4,.98)
    g.setColor(.96,.88,.69,1)
    Typography.drawText(g,self.spot.title,198,226,564,42,{align='center',valign='center',scale=1.2})
    Typography.drawText(g,self.spot.description,210,285,540,132,{align='left',valign='center',scale=1,minScale=.8})
    local r=self:targets()[1].rect
    g.setColor(.25,.19,.10,1);GuiArt.frame(r.x,r.y,r.w,r.h)
    g.setColor(.96,.88,.69,1);Typography.drawText(g,'CLOSE',r.x,r.y,r.w,r.h,{align='center',valign='center'})
end
return Panel
