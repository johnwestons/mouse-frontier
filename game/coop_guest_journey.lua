-- Private read-only journey overlays. The caller supplies the 960x720 viewport
-- for draw() and canonical coordinates for pointer(); no network command or
-- campaign writer is available here. menuOpen remains the Local Play menu.
local Panels=require('game.coop_guest_journey_panels')
local Style=require('game.ui_layout')
local Life=require('game.coop_last_stand_lifecycle')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local Preferences=require('game.local_preferences')
local Journey={};Journey.__index=Journey
local ordinary={train=true,stop=true,house=true,expedition=true,caravan=true}
local mapBounds={x=70,y=75,w=820,h=570}
local function busy(panel) return panel and (panel.pending or panel.opened) end
local function hit(rect,x,y)
    return rect and rect.enabled~=false and x>=rect.x and y>=rect.y and x<=rect.x+rect.w and y<=rect.y+rect.h
end
function Journey.new(view,c)
    return setmetatable({view=view,c=c or view.context,opened=false,controls={},scroll=0},Journey)
end
function Journey:isOpen() return self.opened==true end
function Journey:domain(retainReadOnly)
    local v=self.view;local c=v.controller;local n=c.network;local f=c.motionFrame
    local r=v.runtime;local d=r.saveData;local replica=c.replica and c.replica.data
    local networkReady=n and (n.status=='ready' or retainReadOnly==true and self.opened and n.snapshot
        and (n.status=='snapshot' or n.status=='acknowledging'))
    if not (v.ready and v.focused~=false and not v.paused and n and not n.closed and networkReady
        and d and replica and ordinary[d.scene] and r.scene==d.scene and replica.scene==d.scene
        and d.location==replica.location and f and f.ready and not f.paused
        and f.sessionId==n.sessionId and f.sceneEpoch==v.epoch and d.coop and replica.coop
        and d.coop.sceneEpoch==v.epoch and replica.coop.sceneEpoch==v.epoch
        and f.motionId==v.motionId and f.serial==v.lastSerial and f.domain==v.modalDomain
        and (retainReadOnly==true or not v.prediction:stale())) then return false end
    if c.menuOpen or n.pendingCommand or n.savePending or r.saving or v.carRequest or v.carTransition
        or d.tacticalBattle or r.battle or d.roamingEncounter or Life.active(d)
        or d.trainAmbush and d.trainAmbush.active or d.events and d.events.current
        or d.scene=='train' and d.location==50 then return false end
    if r.inventoryOpen or r.tradeOpen or r.trainUpgradeOpen or r.peopleOpen or r.guestActivityOpen
        or v:objectsOpen() or v:activityBusy() or v.controllerFocus or busy(v.poses)
        or busy(v.inventory) or busy(v.trade) or busy(v.train) or busy(v.objects) or busy(v.people)
        or v.range and v.range:available() or v.ambush and v.ambush:available()
        or v.lastStand and v.lastStand:available() then return false end
    return true
end
function Journey:identity()
    local v=self.view;local n=v.controller.network;local d=v.runtime.saveData
    return table.concat({tostring(n),tostring(n and n.sessionId),tostring(n and n.campaignId),
        tostring(v.epoch),tostring(v.motionId),tostring(v.modalDomain),tostring(d and d.scene),
        tostring(d and d.location),tostring(v.runtime.player and v.runtime.player.activeCar)},':')
end
function Journey:open(kind)
    if kind~='map' and kind~='journal' then return false end
    if not self:domain() then return false end
    self.opened=true;self.kind=kind
    if kind=='map' then self.scroll=nil else self.scroll=0 end
    self.controls={};self.openIdentity=self:identity();self.view:neutralize();return true
end
function Journey:close()
    local wasOpen=self.opened
    self.opened=false;self.kind=nil;self.controls={};self.model=nil;self.scroll=0;self.openIdentity=nil
    if wasOpen then self.view:neutralize() end
    return true
end
function Journey:release() return self:close() end
function Journey:focus(focused) if not focused then self:close() end end
function Journey:update()
    -- Movement freshness gates opening, but this already-open panel only reads
    -- the last checked campaign. A render hitch or lost motion packet must not
    -- dismiss it. A replacement baseline can also be in transit before its
    -- ready receipt applies it; retain only the already-checked read-only view.
    -- Disconnects, scene/modal changes and saves still invalidate it; world
    -- movement/actions keep their independent freshness guards.
    if self.opened and (not self:domain(true) or self.openIdentity~=self:identity()) then self:close() end
end
function Journey:refresh()
    local data=self.view.runtime.saveData
    if self.kind=='map' then self.model=Panels.trail(data,self.scroll)
    else self.model=Panels.journal(data,data.scene,Panels.expeditionObjective(data),self.scroll) end
    self.scroll=self.model.scroll
end
function Journey:step(delta)
    self:refresh()
    local maximum=self.kind=='map' and self.model.maxScroll or self.controls.journeyLogMaxScroll
    if maximum==nil then
        local mobile=self.view.mobile and self.view.mobile.enabled
        maximum=math.max(0,#self.model.rows-(mobile and 4 or 3))
    end
    self.scroll=math.max(0,math.min(maximum,self.scroll+delta));return true
end
function Journey:keypressed(key)
    self:update();if not self.opened then return false end
    if key=='escape' or key=='acback' or key=='return' or key=='space' or key=='e'
        or self.kind=='map' and key=='m' or self.kind=='journal' and key=='j' then self:close()
    elseif key=='up' or key=='w' or key=='pageup' then self:step(-1)
    elseif key=='down' or key=='s' or key=='pagedown' then self:step(1) end
    return true -- An overlay consumes all canonical action keys.
end
function Journey:pointer(x,y)
    self:update();if not self.opened then return false end
    local ui=self.controls;local map=self.kind=='map'
    x,y=Style.inversePoint(x,y,map and 'map' or 'journeyLog',map and mapBounds or ui.journeyLogBounds)
    if hit(map and ui.map or ui.journeyLogClose,x,y) then self:close()
    elseif hit(map and ui.mapUp or ui.journeyLogUp,x,y) then self:step(-1)
    elseif hit(map and ui.mapDown or ui.journeyLogDown,x,y) then self:step(1) end
    return true -- Outside clicks must not reach world interaction.
end
function Journey:wheelmoved(_,dy)
    self:update();if not self.opened then return false end
    if type(dy)=='number' and dy==dy and math.abs(dy)<math.huge and dy~=0 then self:step(dy>0 and -1 or 1) end
    return true
end
function Journey:draw()
    self:update();if not self.opened then return false end
    self:refresh();self.controls={}
    local v=self.view;local c=self.c;local g=love.graphics
    -- Accessibility.ensure repairs its argument. Read the bound private values
    -- directly instead, so detached projections remain immutable even in tests.
    local preferences=Preferences.view(v.runtime.saveData) or {}
    local accessibility=preferences.accessibility or {}
    local size=tonumber(accessibility.textSize) or 1
    local scale=Accessibility.textSizes[size] or 1
    local function text(value,x,y,w,h,factor,align)
        Typography.drawText(g,value,x,y,w,h,{scale=(factor or 1)*scale,
            minScale=.60,align=align or 'left',valign='center'})
    end
    local function frame(x,y,w,h,kind,alpha)
        if c.drawMenuFrame then c.drawMenuFrame(x,y,w,h,kind,alpha)
        else g.setColor(c.colors.panel or {.08,.055,.038,alpha or 1});g.rectangle('fill',x,y,w,h,8,8) end
        if accessibility.highContrast==true then g.setColor(1,.84,.28,1);g.rectangle('line',x,y,w,h,8,8) end
    end
    local context={controls=self.controls,colors=c.colors,scenery=c.content and c.content.scenery,
        mobileEnabled=function()return v.mobile and v.mobile.enabled or false end,
        textBox=text,drawMenuFrame=frame,
        button=function(label,x,y,w,h,enabled,factor)
            frame(x,y,w,h,4,enabled and 1 or .55);g.setColor(c.colors.cream)
            text(label,x+8,y+5,w-16,h-10,factor or .9,'center')
            return {x=x,y=y,w=w,h=h,enabled=enabled~=false}
        end}
    if self.kind=='map' then Panels.drawTrail(context,self.model) else
        Panels.drawJournal(context,self.model);self.scroll=self.controls.journeyLogScroll end
    return true
end
return Journey
