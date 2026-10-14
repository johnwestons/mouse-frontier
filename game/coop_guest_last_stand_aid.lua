-- A private view of the single defender treatment. Only host commands advance it.
local Life=require('game.coop_last_stand_lifecycle')
local Aid=require('game.coop_last_stand_aid')
local Gestures=require('game.coop_guest_first_aid')
local Presentation=require('game.coop_aid_presentation')
local Model=require('game.first_aid')
local Art=require('game.coop_aid_art')
local Style=require('game.ui_layout')
local Panel={}; Panel.__index=Panel
local bounds={x=105,y=40,w=750,h=635}
function Panel.new(view,c,parent)
    return setmetatable({view=view,c=c,parent=parent,runtime=view.runtime,art=c.aidArt or Art,queue={}},Panel)
end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed end
function Panel:busy() return self.opened or self.pending or self.lease or self.wantPause or self.resumeAcquire end
function Panel:allowed()
    local v=self.view
    -- Host motion pauses while this actor holds the patient. Private input stays live.
    return v.ready and v.focused and not v.controller.menuOpen and not self.parent.paused
        and not v.carRequest and not v.carTransition and not v.prediction:stale()
        and self.key==Life.key(self.runtime.saveData)
end
function Panel:submit(action,x,y,index,cleanup)
    if self.pending or not cleanup and (not self.opened or not self:allowed()) then return false end
    local data=self.runtime.saveData; local life=data.lastStand and data.lastStand.lifecycle
    if not life or Life.key(data)~=self.key then return false end
    local expected={}; for _,scope in ipairs(Aid.scopes(data)) do expected[scope]=data.coop.revisions[scope] or 0 end
    local args={questId=life.entityId,revision=life.revision,action=action}
    if action~='acquire' and action~='inspect' then args.leaseId=self.lease end
    if x~=nil then args.x=x; args.y=y end; if index~=nil then args.index=index end
    local id,reason=self.view.controller.network:submitCommand('lastStand.aid',args,self.epoch,expected)
    if not id then self.notice='Treatment unavailable. Please try again.'; return false,reason end
    self.pending={id=id,action=action}; self.nextSendAt=self:now()+.18; self.view:neutralize()
    return true
end
function Panel:open()
    if self:busy() or not self.view:inputAllowed() then return false end
    local data=self.runtime.saveData; local life=data.lastStand and data.lastStand.lifecycle
    if not life or life.mode~='backyard' then return false end
    self.key=Life.key(data); self.epoch=self.view.epoch; self.questId=life.entityId
    self.opened=true; self.runtime.guestActivityOpen=true; self.completed=nil; self.session=nil
    self.queue={}; self.localPointer=nil; self.notice='Waiting for treatment...'; self.nextSendAt=0
    if not self:submit('acquire') then self:suspend(); return false end
    return true
end
function Panel:releaseArt() self.art.release(self.assets); self.assets=nil end
function Panel:suspend()
    self.opened=false; self.runtime.guestActivityOpen=false; self.touch=nil; self.queue={}; self.localPointer=nil
    self.resumeAcquire=nil
    self:releaseArt()
    if self.session then self.session.dragging=false end
    if self.lease or self.pending and self.pending.action=='acquire' then self.wantPause=true end
end
function Panel:display(facts)
    return Presentation.new(facts,self.runtime.saveData,'guard-fox.png',self.runtime.saveData.lastStand.treatmentProgress)
end
function Panel:apply(facts,pending)
    if not facts or facts.actorId~='companion' or facts.questId~=self.questId then self:suspend(); return end
    if facts.completed or facts.inspected then
        self.lease=nil; self.wantPause=nil; self.queue={}; self.completed=true
        self.notice=facts.completed and 'Treatment complete. Defense integrity: '..facts.integrity..'.'
            or facts.treated and 'The defender has already been treated.' or 'The defender needs treatment.'
        return
    end
    local previous=self.session and self.session.phase
    self.lease=facts.leaseId; self.session=self:display(facts); self.renewAt=self:now()+10
    if previous~=facts.phase then
        local queue={}; for _,entry in ipairs(self.queue) do
            if not entry.phase or entry.phase==facts.phase then queue[#queue+1]=entry end
        end; self.queue=queue; self.localPointer=nil
    end
    if facts.outcome=='cancelled' then self.lease=nil; self.wantPause=nil; self.notice='Treatment paused. Progress is saved.'
    elseif pending.action=='acquire' then
        self.resumeAcquire=nil
        self:releaseArt(); if self.opened then self.assets=self.art.new('guard-fox.png',facts.itemName) end; self.notice=nil
    else self.notice=nil end
end
function Panel:update()
    local data=self.runtime.saveData; if not data then return end
    if self.key and (self.key~=Life.key(data) or self.epoch~=self.view.epoch) then
        self:suspend(); self.lease=nil; self.wantPause=nil; self.pending=nil; self.key=nil; return
    end
    if self.opened and not self:allowed() then self:suspend() end
    local p=self.pending; local reply=self.view.controller.network.lastCommandResult
    if p and reply and reply.requestId==p.id then
        if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then
            self.notice='Waiting for the host to save treatment...'; return
        end
        if reply.ok and data.coop.revision<reply.revision then self.notice='Updating treatment...'; return end
        self.pending=nil; self.lastOutcome=reply
        if reply.ok then self:apply(reply.details or reply.result,p)
        else
            self.notice='Treatment unavailable. Stay near the defender and reopen it to continue.'
            if p.action=='pause' and reply.reason~='lease_expired' and reply.reason~='lease_owner'
                and reply.reason~='stale_scene' and reply.reason~='stale_phase' and reply.reason~='patient_unavailable' then
                self.nextSendAt=self:now()+.6
            elseif p.action=='acquire' and self.resumeAcquire and reply.reason=='rate_limited' then
                self.nextSendAt=self:now()+.6
            elseif p.action=='acquire' or p.action=='pause' or reply.reason=='lease_expired' or reply.reason=='lease_owner' then
                self.resumeAcquire=self.opened and p.action~='acquire' and p.action~='pause' and reply.reason=='lease_expired' or nil
                self.lease=nil; self.wantPause=nil; self.queue={}
                self.localPointer=nil; if self.session then self.session.dragging=false end
            elseif reply.reason=='treatment_incomplete' and self.session then self.session.ready=false; self.queue={}
            else self:suspend() end
        end
    end
    if self.pending or self:now()<(self.nextSendAt or 0) then return end
    if self.wantPause and self.lease then self:submit('pause',nil,nil,nil,true); return end
    if self.resumeAcquire then if self.opened and self:allowed() then self:submit('acquire') end; return end
    if not self.opened or not self.lease or not self:allowed() then return end
    if self.session.ready then self:submit('complete'); return end
    local entry=self.queue[1]
    if entry then
        if self:submit(entry.action,entry.x,entry.y,entry.index) then table.remove(self.queue,1) end
    elseif self.session.phase==2 or self:now()>=(self.renewAt or 0) then self:submit('tick') end
end
-- The ordinary aid panel already preserves turns and bounded ointment samples.
Panel.enqueue=Gestures.enqueue; Panel.point=Gestures.point
Panel.move=Gestures.move; Panel.releasePointer=Gestures.releasePointer
function Panel:press(x,y)
    if self.completed or not self.session then
        if x>=335 and x<=625 and y>=534 and y<=584 then self:suspend() end; return true
    end
    x,y=self:point(x,y)
    if x>=350 and x<=610 and y>=608 and y<=650 then self:suspend(); return true end
    self.localPointer={x=x,y=y}; self:enqueue('press',x,y); return true
end
function Panel:keypressed(key)
    if key=='p' then self.parent.paused=true; self:suspend(); self.view:neutralize()
    elseif key=='q' or key=='escape' or key=='acback' then self:suspend()
    elseif self.completed then if key=='return' or key=='space' or key=='kpenter' then self:suspend() end
    elseif self.session then
        if key=='return' or key=='space' or key=='kpenter' then self:enqueue('choose',nil,nil,self.session.phase)
        elseif tonumber(key) then self:enqueue('choose',nil,nil,tonumber(key)) end
    end
    return true
end
function Panel:draw()
    if self.session and not self.completed then
        local display=self:display({questId=self.questId,itemName=self.session.itemName,phase=self.session.phase,
            ready=self.session.ready,dragging=self.session.dragging,pointer=self.session.pointer})
        display.message=self.notice; if self.localPointer then display.pointer=self.localPointer end
        local assets=self.assets or {}; assets.drawFrame=self.c.drawMenuFrame
        Style.scope('firstAid',bounds,function() Model.draw(display,self.c.colors,assets) end)
    else
        self.view.inventory:frame(120,80,720,570,1,1)
        self.view.trade:textBox(self.notice or 'Waiting for treatment...',155,230,650,160,.9,'center')
        self.view.inventory:button('CLOSE',335,534,290,50,true,.85)
    end
end
return Panel
