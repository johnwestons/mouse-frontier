-- Personal inspection of the host's next leg. Requesting never departs.
local Requests=require('game.coop_travel_requests')
local Results=require('game.net.travel_request_results')
local Life=require('game.coop_last_stand_lifecycle')
local Style=require('game.ui_layout')
local Typography=require('game.typography')
local Panel={};Panel.__index=Panel
local bounds={x=200,y=105,w=560,h=510}
local function hit(r,x,y)return r and x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
function Panel.new(view,c)return setmetatable({view=view,c=c,opened=false,controls={},selected=1},Panel)end
function Panel:identity()return self.view.journey:identity()end
function Panel:domain(retain)
    local v=self.view;local n=v.controller.network;local f=v.controller.motionFrame
    local d=v.runtime.saveData;local copy=v.controller.replica and v.controller.replica.data
    local status=n and (n.status=='ready' or retain and self.opened and n.snapshot and (n.status=='snapshot' or n.status=='acknowledging'))
    local pending=n and n.pendingCommand
    return v.ready and v.focused~=false and not v.paused and n and not n.closed and status
        and not v.controller.menuOpen and not n.savePending and (not pending or self.pending and pending.requestId==self.pending.id
            and pending.command=='progression.request')
        and d and copy and d.scene=='train' and v.runtime.scene==d.scene and copy.scene==d.scene
        and d.stopped==true and d.location<50 and d.location==copy.location
        and d.coop.sceneEpoch==v.epoch and copy.coop.sceneEpoch==v.epoch and f and f.ready and not f.paused
        and f.sessionId==n.sessionId and f.sceneEpoch==v.epoch and f.motionId==v.motionId
        and f.serial==v.lastSerial and f.domain==v.modalDomain and (retain or not v.prediction:stale())
        and not d.coop.journey and not d.tacticalBattle and not d.roamingEncounter and not Life.active(d)
        and not (d.trainAmbush and d.trainAmbush.active) and not (d.events and d.events.current)
        and not v.runtime.saving and not v.carRequest and not v.carTransition and not v:activityBusy()
        and not v.runtime.inventoryOpen and not v.runtime.tradeOpen and not v.runtime.trainUpgradeOpen
        and not v.runtime.peopleOpen and not v:objectsOpen() and not v.poses.opened and not v.journey.opened
        and not v.controllerFocus
end
function Panel:submit(action)
    if not self.opened or not self:domain(false) or self.pending then return false end
    local v=self.view;local n=v.controller.network;local args={action=action,motionId=v.motionId}
    if action=='depart'then
        if not self.model then return false end
        args.quote={};for _,key in ipairs({'from','to','food','water','coal','sourceRevision'})do args.quote[key]=self.model[key]end
    end
    local expected={};for _,scope in ipairs(Requests.scopes())do expected[scope]=v.runtime.saveData.coop.revisions[scope] or 0 end
    local id,reason=n:submitCommand('progression.request',args,v.epoch,expected)
    if not id then self.notice='Travel inspection is unavailable. Wait for the host connection.';return false,reason end
    self.pending={id=id,action=action,identity=self:identity(),network=n}
    self.notice=action=='inspect' and 'Reading the host route...' or 'Sending the departure request...'
    self.view:neutralize();return true
end
function Panel:open()
    if self.opened then return true end
    if not self:domain(false) or not self.view:inputAllowed()then return false end
    self.opened=true;self.openIdentity=self:identity();self.model=nil;self.notice=nil;self.controls={};self.selected=1
    self.view:neutralize();return self:submit('inspect')
end
function Panel:close()
    local wasOpen=self.opened;self.opened=false;self.pending=nil;self.model=nil;self.controls={};self.openIdentity=nil
    if wasOpen then self.view:neutralize()end;return true
end
function Panel:release()return self:close()end
function Panel:focus(focused)if not focused then self:close()end end
function Panel:update()
    if not self.opened then return end
    if not self:domain(true) or self.openIdentity~=self:identity()then self:close();return end
    local pending=self.pending;local n=self.view.controller.network;local result=n.lastCommandResult
    if not pending or not result or result.requestId~=pending.id or result.sessionId~=n.sessionId
        or result.command~='progression.request'then return end
    if result.savePending or result.reason=='save_pending' or result.reason=='busy'then return end
    if result.ok and self.view.runtime.saveData.coop.revision<result.revision then return end
    self.pending=nil
    if not result.ok then
        self.notice=result.reason=='request_cooldown' and 'Wait before sending another request.'
            or 'The host route changed. Use REFRESH before requesting departure.'
        if result.reason=='stale_revision' or result.reason=='travel_quote_changed'then self.model=nil end
        return
    end
    if not Results.valid(result.details) or result.details.from~=self.view.runtime.saveData.location then self:close();return end
    self.model=Results.project(result.details)
    self.notice=self.model.requested and (self.model.already and 'The host already has this request.' or 'Request sent. The host chooses when to depart.')
        or 'Only the host can pay for and start the next leg.'
end
function Panel:action(index)
    if index==1 then return self:submit('depart')elseif index==2 then return self:submit('inspect')else return self:close()end
end
function Panel:keypressed(key)
    if not self.opened then return false end
    if key=='escape' or key=='acback' or key=='v'then self:close()
    elseif key=='up' or key=='left' or key=='w' or key=='a'then self.selected=(self.selected-2)%3+1
    elseif key=='down' or key=='right' or key=='s' or key=='d' or key=='tab'then self.selected=self.selected%3+1
    elseif key=='return' or key=='space' or key=='e'then self:action(self.selected)end
    return true
end
function Panel:pointer(x,y)
    if not self.opened then return false end
    x,y=Style.inversePoint(x,y,'guest-travel',bounds)
    for index,r in ipairs(self.controls)do if hit(r,x,y)then self.selected=index;self:action(index);break end end
    return true
end
function Panel:draw()
    if not self.opened then return false end
    local g=love.graphics;g.setColor(.025,.02,.015,.80);g.rectangle('fill',0,0,960,720)
    Style.scope('guest-travel',bounds,function()
        self.view.inventory:frame(bounds.x,bounds.y,bounds.w,bounds.h,2,.99)
        local function text(value,y,height,scale)
            g.setColor(self.c.colors.cream);Typography.drawText(g,value,228,y,504,height,
                {scale=scale or .9,minScale=.65,align='center',valign='center'})
        end
        text('NEXT LEG / HOST JOURNEY',127,40,1.1)
        local m=self.model
        if m then
            text('STOP '..m.from..' TO STOP '..m.to,183,38,1.1)
            text('Host travel cost: '..m.terrain..' route',225,30,.85)
            for index,name in ipairs({'food','water','coal'})do
                text(name:upper()..' '..m[name]..'   /   SHARED '..m.available[name],261+(index-1)*38,34,.9)
            end
            text(m.affordable and 'Shared supplies cover this leg.' or ('Still needed: FOOD '..m.missing.food..' / WATER '..m.missing.water..' / COAL '..m.missing.coal),380,42,.8)
        else text('Waiting for a current host inspection.',225,145,.9)end
        local height=self.view.mobile.enabled and 52 or 44
        self.controls={
            self.view.inventory:button('REQUEST DEPARTURE',228,440,504,height,m~=nil and not self.pending,.85),
            self.view.inventory:button('REFRESH',228,498,243,height,not self.pending,.85),
            self.view.inventory:button('CLOSE',489,498,243,height,true,.85)}
        local r=self.controls[self.selected];g.setColor(.94,.74,.31,1);g.rectangle('line',r.x-2,r.y-2,r.w+4,r.h+4,6,6)
        text(self.notice or 'Only the host progresses the journey.',551,46,.75)
    end)
    return true
end
return Panel
