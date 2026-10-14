-- Independent input over a host-owned sewing lease. No crafting or save writer
-- is available in this panel; the existing bench renders read-only projections.
local Crafting=require('game.outfit_crafting').view
local UI=require('game.outfit_crafting_ui')
local Access=require('game.coop_activity_access')
local Panel={}; Panel.__index=Panel
local failures={activity_busy='The sewing bench is in use.',actor_busy='Finish your current activity first.',
    activity_unavailable='Return to the stopped train to sew.',stale_revision='The project changed. Review the current step.',
    stale_scene='The host moved the party.',lease_expired='Reopen the bench to continue.',lease_owner='Reopen the bench to continue.',
    materials='Carry every required material bundle.',project_busy='Finish the existing project first.',
    inventory_full="Free a slot in the project owner's backpack. The upgrade remains on the bench.",
    project_incomplete='Finish every construction step before collecting.',wrong_step='Review the current construction step.',
    rate_limited='Please wait a moment and try again.'}
function Panel.new(view,c)
    local self=setmetatable({view=view,c=c,runtime=view.runtime},Panel)
    self.bench=UI.new({data=function() return self.runtime.saveData end,model=Crafting,
        command=function() return {ok=false} end,
        enabled=function(id) return id=='close' or self:ready() end,
        subtitle=function()
            local project=Crafting.project(self.runtime.saveData)
            local receipt=self.bench and self.bench.receipt
            return project and ('Shared project / upgrade for '..((project.ownerPlayerId or 'host')=='host' and 'the host' or 'the companion'))
                or receipt and ('Completed upgrade / for '..(receipt.ownerPlayerId=='host' and 'the host' or 'the companion'))
                or 'Your materials / upgrade for your outfit'
        end,
        onClose=function() self:suspend() end})
    local b=self.bench
    function b:suspend() self.holding=false; self.heldKey=nil; self.dragging=false; self.blockCoincident=false; self.pointer=nil end
    function b:start() local recipe=self:recipe(); if recipe then return self.context.panel:submit('start',{recipeId=recipe.id}) end end
    function b:collect() return self.context.panel:submit('collect',{}) end
    function b:place(x,y) return self.context.panel:submit('point',{x=x,y=y}) end
    function b:beginPull(source)
        local p=self.context.panel; local stage=Crafting.stage(p.runtime.saveData)
        if not stage or stage.kind~='tension' or self.holding then return false end
        if p:submit('pullStart',{}) then self.holding=true; self.heldKey=source; self.focusId='work'; return true end
        return false
    end
    function b:releasePull()
        self.holding=false; self.heldKey=nil
        local p=self.context.panel
        if p.pending and (p.pending.action=='pullStart' or p.pending.action=='renew') then p.releaseWanted=true; return true end
        return p:submit('pullRelease',{})
    end
    function b:adjustTension(amount)
        local p=self.context.panel
        if p:submit('adjust',{direction=amount<0 and -1 or 1}) then self.holding=false; self.heldKey=nil; return true end
        return false
    end
    b.context.panel=self
    return self
end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed end
function Panel:busy() return self.pending or self.lease or self.wantRelease or self.resumeAcquire end
function Panel:eligible() return self.view:actionsAllowed() and Access.train(self.runtime.saveData,{screen=self.runtime.state,scene=self.runtime.scene}) end
function Panel:ready() return self.opened and self.lease and not self.pending and not self.wantRelease and self:eligible() end
function Panel:open()
    if self:busy() or not self:eligible() then return false end
    self.epoch=self.view.epoch; self.car=self.runtime.saveData.activeCar; self.opened=true
    self.runtime.guestActivityOpen=true; self.drawn=nil; self.notice=nil; self.completedNotice=nil; self.touch=nil
    self.bench:show(); self.view:neutralize()
    return self:submit('acquire',{})
end
function Panel:suspend()
    self.opened=false; self.runtime.guestActivityOpen=false; self.bench.visible=false; self.bench:suspend()
    self.drawn=nil; self.touch=nil; self.releaseWanted=nil; self.resumeAcquire=nil
    if self.lease or self.pending and self.pending.action=='acquire' then self.wantRelease=true end
end
function Panel:expected(action,drawn)
    local data=self.runtime.saveData; local scopes={'activity:train:sewing','outfit'}
    if action=='start' then scopes[#scopes+1]='player:companion'
    elseif action=='collect' then
        local project=Crafting.project(data); scopes[#scopes+1]='player:'..(project and project.ownerPlayerId or 'host')
    end
    if action=='release' then scopes={'activity:train:sewing'} end
    local source=drawn or data.coop.revisions; local expected={}
    for _,scope in ipairs(scopes) do expected[scope]=source[scope] or 0 end
    return expected
end
function Panel:submit(action,args,cleanup)
    if self.pending or not cleanup and (not self.opened or not self:eligible()) then return false end
    if action~='acquire' and not self.lease then return false end
    local work=action=='start' or action=='point' or action=='pullStart' or action=='pullRelease' or action=='adjust' or action=='collect'
    if work and not self:ready() then return false end
    if work and not self.drawn and action~='pullRelease' then return false end
    args=args or {}; local command=action=='release' and 'activity.release' or 'outfit.craft'
    if action~='release' then args.action=action end
    if action~='acquire' then args.leaseId=self.lease end
    local id,reason=self.view.controller.network:submitCommand(command,args,self.epoch,self:expected(action,work and self.drawn))
    if not id then self.notice=failures[reason] or 'Sewing unavailable. Review the bench and try again.'; return false end
    local stage=Crafting.stage(self.runtime.saveData)
    self.pending={id=id,action=action,command=command,sentAt=self:now(),point=stage and stage.currentPoint}
    if action~='renew' then self.notice='Waiting for the host...' end
    self.view:neutralize(); return true
end
function Panel:apply(result,pending)
    local d=result.details; local b=self.bench
    if pending.action=='release' then self.lease=nil; self.wantRelease=nil; self.anchor=nil; return end
    if d.action~=pending.action then self:suspend(); return end
    self.lease=d.leaseId; self.renewAt=self:now()+10
    local received=pending.receivedAt or self:now(); local rtt=math.max(0,received-pending.sentAt)
    self.anchor={tension=d.tension,pulling=d.pulling,at=received,offset=math.min(.175,rtt/2)}
    self.notice=not d.success and failures[d.reason]
        or d.correct==false and 'Reposition the tool or adjust the seam tension and try again.'
        or pending.action=='collect' and ('Upgrade collected into '..(d.ownerPlayerId=='host' and "the host's" or "the companion's")..' backpack.')
        or pending.action=='start' and 'Materials set aside. Work the highlighted marks.'
        or d.complete and 'Construction complete. Collect the upgrade for its owner.'
        or d.stageComplete and 'Step complete. Prepare the next tool.'
        or d.pulling and (rtt>.35 and 'Connection delayed. Use the adjustment buttons for precise tension.' or 'Release in the marked snug range.')
        or nil
    if pending.action=='start' and d.success then b.receipt=nil; b.focusId='work'; self.completedNotice=nil end
    if pending.action=='collect' and d.success then b.receipt=d; b.focusId='start'; self.completedNotice=self.notice end
    if self.completedNotice and d.success and (pending.action=='renew' or pending.action=='acquire') then self.notice=self.completedNotice end
    if d.stageComplete then b:suspend(); b.focusId='work'; self.releaseWanted=nil end
    if d.correct and pending.point and b.dragging then
        local stage=Crafting.stage(self.runtime.saveData); local point=stage and stage.currentPoint
        b.blockCoincident=point and math.abs(point.x-pending.point.x)<.001 and math.abs(point.y-pending.point.y)<.001 or false
    end
end
function Panel:update(dt)
    local invalid=self.epoch and (self.epoch~=self.view.epoch or self.car~=self.runtime.saveData.activeCar)
    if invalid then self:suspend(); self.lease=nil; self.wantRelease=nil; self.anchor=nil end
    if self.opened and (not self.view.focused or self.view.controller.menuOpen or not Access.train(self.runtime.saveData,{screen=self.runtime.state,scene=self.runtime.scene})) then self:suspend() end
    local p=self.pending; local r=self.view.controller.network.lastCommandResult
    if p and r and r.requestId==p.id then
        p.receivedAt=p.receivedAt or self:now()
        if r.savePending or r.reason=='save_pending' then p.saveBarrier=true; self.notice='Waiting for the host to finish saving...'; return end
        if r.reason=='busy' then self.notice='Waiting for the host...'; return end
        if r.ok and self.runtime.saveData.coop.revision<r.revision then self.notice='Updating the shared project...'; return end
        self.pending=nil; self.drawn=nil
        self.lastOutcome=r
        if r.ok and not invalid then
            self:apply(r,p)
            -- The application's failed-save barrier cancels ephemeral leases.
            -- Check that lease after confirming the paid outcome; renew/reacquire
            -- never replays a material payment, tool motion or item collection.
            if p.saveBarrier and self.opened and self.lease then self.renewAt=self:now() end
        elseif not r.ok then
            self.notice=failures[r.reason] or 'Sewing unavailable. Review the current step and try again.'
            if p.action=='release' and r.reason~='lease_expired' and r.reason~='lease_owner' and r.reason~='stale_scene' then
                self.wantRelease=true; self.retryAt=self:now()+.6
            elseif p.action=='acquire' or p.action=='release' or r.reason=='lease_expired' or r.reason=='lease_owner' then
                self.resumeAcquire=self.opened and not self.wantRelease and p.action~='acquire' and p.action~='release' and r.reason=='lease_expired' or nil
                self.lease=nil; self.wantRelease=nil; self.anchor=nil; self.releaseWanted=nil; self.bench:suspend()
            elseif p.action=='pullStart' then self.releaseWanted=nil; self.bench:suspend()
            elseif r.reason=='activity_unavailable' or r.reason=='wrong_activity' then self:suspend()
            else self.renewAt=self:now()+.6 end
        end
    end
    if self.anchor then
        local a=self.anchor; self.bench.tension=math.min(1,a.tension+(a.pulling and math.max(0,self:now()-a.at+a.offset)*.24 or 0))
    end
    if self.pending then return end
    if self.wantRelease and self.lease then
        if self:now()>=(self.retryAt or 0) then self:submit('release',{},true) end
        return
    end
    if self.resumeAcquire and self.opened and self:eligible() then
        if self:submit('acquire',{}) then self.resumeAcquire=nil end
        return
    end
    if not self.opened or not self.lease then return end
    if self.releaseWanted then
        if self:submit('pullRelease',{}) then self.releaseWanted=nil end
    elseif self:eligible() and self:now()>=(self.renewAt or 0) then self:submit('renew',{}) end
end
function Panel:draw()
    self.drawn={}; for scope,value in pairs(self.runtime.saveData.coop.revisions) do self.drawn[scope]=value end
    self.bench.message=self.notice or ''; self.bench:draw()
end
function Panel:keypressed(key) if key=='c' then self:suspend(); return true end; return self.bench:keypressed(key) end
function Panel:keyreleased(key) return self.bench:keyreleased(key) end
function Panel:press(x,y) return self.bench:mousepressed(x,y,1) end
function Panel:move(x,y) return self.bench:mousemoved(x,y) end
function Panel:releasePointer(x,y) return self.bench:mousereleased(x,y,1) end
function Panel:wheel(dy) return self.bench:wheelmoved(0,dy) end
return Panel
