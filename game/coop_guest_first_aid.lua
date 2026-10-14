-- Guest gestures are queued intents. Only host facts and projected checkpoints
-- update treatment progress; the pure model is used here exclusively to draw.
local Access=require('game.coop_aid_access')
local Presentation=require('game.coop_aid_presentation')
local Model=require('game.first_aid')
local Art=require('game.coop_aid_art')
local Style=require('game.ui_layout')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local bounds={x=105,y=40,w=750,h=635}
local cancel={x=350,y=608,w=260,h=42}
local failures={activity_busy='This patient is already receiving treatment.',actor_busy='Finish your current activity first.',
    activity_unavailable='Stay near the patient outside encounters to treat them.',patient_unavailable='Return to the patient to continue.',
    quest_unavailable='The host must accept this aid quest before you can treat the patient.',medical_supply='Carry and select a medical supply.',
    medical_supply_changed='Your selected supply changed. Reopen treatment and select it again.',
    stale_revision='The patient or supply changed. Review treatment and try again.',stale_scene='The host moved the party.',
    lease_expired='The treatment session expired. Reopen it to continue.',lease_owner='Reopen treatment to continue.',
    treatment_incomplete='Finish all treatment steps first.',rate_limited='Please wait for the next treatment input.'}
function Panel.new(view,c)
    return setmetatable({view=view,c=c,art=c.aidArt or Art,runtime=view.runtime,queue={},selected=1},Panel)
end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed end
function Panel:state()
    local r=self.runtime; local npc=r.npcActor
    return {screen=r.state,scene=r.scene,x=r.player.x,y=r.player.y,
        npc=npc and {id=r.saveData.currentNPC,x=npc.x,y=npc.y} or nil}
end
function Panel:patient() return self.targetId and Access.patient(self.runtime.saveData,self:state(),self.targetId,self.npc) end
function Panel:nearest() return self.view:actionsAllowed() and Access.nearest(self.runtime.saveData,self:state()) end
function Panel:busy() return self.pending or self.lease or self.wantPause or self.wantRelease or self.resumeAcquire end
function Panel:open()
    if self:busy() then return false end
    local patient=self:nearest(); if not patient then return false end
    self.targetId=patient.targetId; self.npc=patient.npc; self.questId=patient.quest.id; self.epoch=self.view.epoch
    self.opened=true; self.runtime.guestActivityOpen=true; self.selected=1; self.drawn=nil; self.notice=nil
    self.session=nil; self.queue={}; self.localPointer=nil; self.nextSendAt=0; self.completed=nil; self.supply=nil
    self.view:neutralize(); return true
end
function Panel:releaseArt() self.art.release(self.assets); self.assets=nil end
function Panel:suspend()
    self.opened=false; self.runtime.guestActivityOpen=false; self.queue={}; self.drawn=nil; self.localPointer=nil
    self.resumeAcquire=nil
    self:releaseArt()
    if self.session then self.session.dragging=false end
    if self.lease or self.pending and self.pending.command=='firstAid.acquire' then self.wantPause=true end
end
function Panel:submit(command,args,cleanup,expected)
    if self.pending or not cleanup and (not self.opened or not self.view:actionsAllowed() or not self:patient()) then return false end
    local id,reason=self.view.controller.network:submitCommand(command,args,self.epoch,
        expected or Access.expected(self.runtime.saveData,'companion',command,self.questId,self.targetId))
    if not id then self.notice=failures[reason] or 'Treatment unavailable. Review the patient and try again.'; return false end
    self.pending={id=id,command=command,action=args.action,sentAt=self:now(),recovery=self.resumeAcquire}
    if command=='firstAid.acquire' then self.supply={source=args.source,selected=args.selected} end
    self.nextSendAt=self:now()+.18; self.view:neutralize()
    if command=='firstAid.complete' then self.notice='Waiting for the host to confirm treatment and save...' end
    return true
end
function Panel:begin()
    local offer=self.drawn and self.drawn[self.selected]
    if not offer or self.lease or self.pending then return false end
    return self:submit('firstAid.acquire',{targetId=self.targetId,npc=self.npc,source=offer.source,selected=offer.selected},false,offer.expected)
end
function Panel:enqueue(action,x,y,index)
    if not self.opened or not self.lease or not self.session or self.session.ready or self.wantPause or self.wantRelease then return false end
    local entry={action=action,x=x,y=y,index=index,phase=self.session.phase}
    if action=='release' then entry.phase=nil end
    local last,previous=self.queue[#self.queue],self.queue[#self.queue-1]
    local coalesce=action=='move' and last and last.action=='move' and self.session.phase==2
    if action=='move' and last and last.action=='move' and previous and previous.x and previous.y
        and (self.session.phase==3 or self.session.phase==4 or self.session.phase==6) then
        local ax,ay=last.x-previous.x,last.y-previous.y; local bx,by=x-last.x,y-last.y
        -- Keep turns, and retain enough ointment samples for its authored
        -- coverage rule. Straight strokes keep their newest endpoint.
        local sameDirection=ax*bx>=0 and ax*bx+ay*by>0
        local span=(x-previous.x)^2+(y-previous.y)^2
        coalesce=sameDirection and (self.session.phase~=4 or span<=14^2)
    end
    if coalesce then self.queue[#self.queue]=entry
    elseif #self.queue<16 then self.queue[#self.queue+1]=entry
    elseif action=='release' then self.queue[math.min(17,#self.queue+1)]=entry
    else return false end
    return true
end
function Panel:apply(reply,pending)
    local d=reply.details
    if pending.command=='activity.release' then self.lease=nil; self.wantRelease=nil; self.wantPause=nil; return end
    if pending.command=='firstAid.complete' then
        self.lease=nil; self.wantPause=nil; self.wantRelease=nil; self.queue={}; self.completed=d
        self.notice='Treatment complete. Used '..Util.titleFromFile(d.item)..'. +'..d.gained..' goodwill. Total '..d.total..'.'
        return
    end
    if d.questId~=self.questId then self:suspend(); return end
    local previous=self.session and self.session.phase
    self.lease=d.leaseId; self.session=Presentation.new(d,self.runtime.saveData,self.npc); self.renewAt=self:now()+10
    if previous and previous~=d.phase then
        local queue={}; for _,entry in ipairs(self.queue) do if not entry.phase or entry.phase==d.phase then queue[#queue+1]=entry end end
        self.queue=queue; self.localPointer=nil
    end
    if d.outcome=='cancelled' then
        self.lease=nil; self.wantPause=nil; self.wantRelease=nil; self.notice='Treatment paused. Your progress is saved.'
    elseif pending.command=='firstAid.acquire' then
        self:releaseArt(); if self.opened then self.assets=self.art.new(self.npc,d.itemName) end
        self.resumeAcquire=nil; self.localPointer=nil
        self.notice=pending.recovery and 'Treatment restored. Press again to continue.' or nil
    elseif not self.pending then self.notice=nil end
end
function Panel:update(dt)
    local data=self.runtime.saveData; if not data then return end
    local invalid=self.epoch and self.epoch~=self.view.epoch
    if invalid then self:suspend(); self.lease=nil; self.wantPause=nil; self.wantRelease=nil end
    if self.opened and (not self.view.focused or self.view.controller.menuOpen
        or not self.completed and not (self.pending and self.pending.command=='firstAid.complete') and not self:patient()) then self:suspend() end
    local p=self.pending; local r=self.view.controller.network.lastCommandResult
    if p and r and r.requestId==p.id then
        if r.savePending or r.reason=='save_pending' or r.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
        if r.ok and data.coop.revision<r.revision then self.notice='Updating the treatment...'; return end
        self.pending=nil; self.drawn=nil; self.lastOutcome=r
        if r.ok and not invalid then self:apply(r,p)
        elseif not r.ok then
            self.notice=failures[r.reason] or 'Treatment unavailable. Reopen it to continue.'
            if p.action=='pause' and r.reason~='lease_expired' and r.reason~='lease_owner' and r.reason~='stale_scene' then
                self.wantPause=nil; self.wantRelease=true; self.retryAt=self:now()+.6
            elseif p.command=='activity.release' and r.reason~='lease_expired' and r.reason~='lease_owner' and r.reason~='stale_scene' then
                self.wantRelease=true; self.retryAt=self:now()+.6
            elseif p.command=='firstAid.acquire' and p.recovery and r.reason=='rate_limited' then self.nextSendAt=self:now()+.6
            elseif p.command=='firstAid.acquire' or p.command=='activity.release' or r.reason=='lease_expired' or r.reason=='lease_owner' or r.reason=='stale_scene' then
                self.resumeAcquire=self.opened and self.supply and not self.wantPause and not self.wantRelease
                    and p.command~='firstAid.acquire' and p.command~='activity.release' and r.reason=='lease_expired' or nil
                self.lease=nil; self.wantPause=nil; self.wantRelease=nil; self.queue={}
                if self.session then self.session.dragging=false end
                if p.command=='firstAid.acquire' then self.session=nil; self:releaseArt() end
            elseif r.reason=='medical_supply_changed' or r.reason=='patient_unavailable' or r.reason=='quest_unavailable' or r.reason=='activity_unavailable' then self:suspend()
            elseif p.command=='firstAid.complete' and r.reason=='treatment_incomplete' then
                self.session.ready=false; self.queue={}; self.renewAt=self:now()
            elseif p.command=='firstAid.step' then self.queue={}; if self.session then self.session.dragging=false end end
        end
    end
    if self.pending then return end
    if self.wantPause and self.lease then
        if self:now()>=(self.nextSendAt or 0) then self:submit('firstAid.step',{leaseId=self.lease,action='pause'},true) end
        return
    end
    if self.wantRelease and self.lease then
        if self:now()>=(self.retryAt or 0) then self:submit('activity.release',{leaseId=self.lease},true) end
        return
    end
    if self.resumeAcquire then
        if self.opened and self.view:actionsAllowed() and self:now()>=(self.nextSendAt or 0) then
            self:submit('firstAid.acquire',{targetId=self.targetId,npc=self.npc,source=self.supply.source,selected=self.supply.selected})
        end
        return
    end
    if not self.opened or not self.lease or not self.view:actionsAllowed() or self:now()<(self.nextSendAt or 0) then return end
    if self.session.ready then self:submit('firstAid.complete',{leaseId=self.lease}); return end
    local entry=self.queue[1]
    if entry then
        if self:submit('firstAid.step',{leaseId=self.lease,action=entry.action,x=entry.x,y=entry.y,index=entry.index}) then table.remove(self.queue,1) end
    elseif self.session.phase==2 or self:now()>=(self.renewAt or 0) then self:submit('firstAid.step',{leaseId=self.lease,action='tick'}) end
end
function Panel:point(x,y) return Style.inversePoint(x,y,'firstAid',bounds) end
function Panel:press(x,y)
    if not self.session or self.completed then
        for _,row in ipairs(self.rows or {}) do if Util.pointIn(x,y,row.rect) then self.selected=row.index; return true end end
        local count=#Access.supplies(self.runtime.saveData,self.c.catalog)
        if Util.pointIn(x,y,self.prevRect) then self.selected=math.max(1,self.selected-6); return true end
        if Util.pointIn(x,y,self.nextRect) then self.selected=math.min(math.max(1,count),self.selected+6); return true end
        if Util.pointIn(x,y,self.closeRect) then self:suspend()
        elseif Util.pointIn(x,y,self.beginRect) then self:begin() end
        return true
    end
    x,y=self:point(x,y)
    if Util.pointIn(x,y,cancel) then self:suspend(); return true end
    self.localPointer={x=x,y=y}; self:enqueue('press',x,y); return true
end
function Panel:move(x,y)
    if self.session then x,y=self:point(x,y); self.localPointer={x=x,y=y}; self:enqueue('move',x,y) end
    return true
end
function Panel:releasePointer(x,y)
    if self.session then x,y=self:point(x,y); self:enqueue('release',x,y) end; return true
end
function Panel:keypressed(key)
    if key=='q' or key=='escape' or key=='acback' or key=='h' then self:suspend()
    elseif self.completed then if key=='return' or key=='kpenter' or key=='space' then self:suspend() end
    elseif not self.session then
        local count=#Access.supplies(self.runtime.saveData,self.c.catalog)
        if key=='up' or key=='left' then self.selected=math.max(1,self.selected-1)
        elseif key=='down' or key=='right' then self.selected=math.min(math.max(1,count),self.selected+1)
        elseif key=='pageup' then self.selected=math.max(1,self.selected-6)
        elseif key=='pagedown' then self.selected=math.min(math.max(1,count),self.selected+6)
        elseif key=='return' or key=='kpenter' or key=='space' then self:begin() end
    elseif key=='return' or key=='kpenter' or key=='space' then self:enqueue('choose',nil,nil,self.session.phase)
    elseif tonumber(key) then self:enqueue('choose',nil,nil,tonumber(key)) end
    return true
end
function Panel:draw()
    local g=love.graphics
    if self.session and not self.completed then
        local display=Presentation.new({questId=self.questId,itemName=self.session.itemName,phase=self.session.phase,
            ready=self.session.ready,dragging=self.session.dragging,pointer=self.session.pointer},self.runtime.saveData,self.npc)
        display.message=self.notice
        if self.localPointer then display.pointer={x=self.localPointer.x,y=self.localPointer.y} end
        local assets=self.assets or {}; assets.drawFrame=self.c.drawMenuFrame
        Style.scope('firstAid',bounds,function() Model.draw(display,self.c.colors,assets) end)
        return
    end
    self.view.inventory:frame(120,80,720,570,1,1); g.setColor(self.c.colors.cream)
    self.view.trade:textBox('FIRST AID / '..Util.titleFromFile(self.npc),145,102,670,38,1.1,'center')
    self.view.trade:textBox(self.notice or 'Select a supply from your backpack. It is used after treatment.',155,149,650,65,.85,'center')
    self.rows={}; self.drawn={}
    if self.completed then
        self.prevRect=nil; self.nextRect=nil; self.beginRect=nil; self.closeRect={x=335,y=534,w=290,h=50}
        self.view.inventory:button('CLOSE',335,534,290,50,true,.85); return
    end
    local offers=Access.supplies(self.runtime.saveData,self.c.catalog)
    local offset=math.floor((self.selected-1)/6)*6
    for i,offer in ipairs(offers) do
        if i>offset and i<=offset+6 then
            local rect={x=170,y=230+(i-offset-1)*43,w=620,h=37}; self.rows[#self.rows+1]={index=i,rect=rect}
            self.view.inventory:button((i==self.selected and '> ' or '')..Util.titleFromFile(offer.name)..' / BACKPACK '..offer.source.index,
                rect.x,rect.y,rect.w,rect.h,not self.pending,.8)
            offer.expected=Access.expected(self.runtime.saveData,'companion','firstAid.acquire',self.questId,self.targetId); self.drawn[i]=offer
        end
    end
    self.prevRect={x=170,y=490,w=100,h=30}; self.nextRect={x=690,y=490,w=100,h=30}
    self.view.inventory:button('PREV',170,490,100,30,not self.pending and offset>0,.7)
    self.view.inventory:button('NEXT',690,490,100,30,not self.pending and offset+6<#offers,.7)
    self.beginRect={x=175,y=534,w=290,h=50}; self.closeRect={x=495,y=534,w=290,h=50}
    self.view.inventory:button('BEGIN TREATMENT',175,534,290,50,not self.pending and not self.completed and self.drawn[self.selected]~=nil,.85)
    self.view.inventory:button('CLOSE',495,534,290,50,true,.85)
end
return Panel
