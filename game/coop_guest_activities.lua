-- Detached train activity presentation. Progress, payment and quality are host outputs.
local Access=require('game.coop_activity_access')
local Sewing=require('game.coop_guest_sewing')
local FirstAid=require('game.coop_guest_first_aid')
local Items=require('game.item_instances')
local Loot=require('game.loot_progression')
local Maintenance=require('game.maintenance')
local RepairArt=require('game.repair_workbench_art')
local RepairLayout=require('game.repair_workbench_layout')
local OutfitArt=require('game.outfit_sprite_art')
local Schema=require('game.save_schema')
local Focus=require('game.ui_focus')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local failures={activity_busy='This station is in use. Try again when it is free.',actor_busy='Finish your current activity first.',
    activity_unavailable='Return to the stopped train to use this station.',activity_changed='Your weapon changed. Start a new repair.',
    lease_expired='The session expired. Reopen the station.',lease_owner='Reopen the station to continue.',
    stale_revision='The activity or supplies changed. Review them and try again.',stale_scene='The host moved the party.',
    oil='There is not enough train oil.',scrap='There is not enough shared scrap.',part='Carry the required part in your backpack.',
    ready='This weapon is ready.',ownership='Select a weapon you own.',rate_limited='Please wait a moment and try again.',
    miss='Missed the mark. No scrap or parts were used.',precision='Aim for the brass mark to improve this weapon.',
    already='The running gear is already serviced at this stop.',progress='Oil all three hubs before finishing.',full='This hub is fully oiled.'}
function Panel.new(view,c) return setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui,page=1,sewing=Sewing.new(view,c),firstAid=FirstAid.new(view,c)},Panel) end
function Panel:now() return self.c.clock and self.c.clock() or self.view.elapsed end
function Panel:state() return {screen=self.runtime.state,scene=self.runtime.scene} end
function Panel:eligible() return self.view:actionsAllowed() and Access.train(self.runtime.saveData,self:state()) end
function Panel:busy()
    local v,r=self.view,self.runtime
    return self.pending or self.lease or self.wantRelease or self.sewing:busy() or self.firstAid:busy() or v.inventory.pending or v.trade.pending or v.train.pending
        or v.objects and v.objects.pending or v.people and v.people.pending
        or r.inventoryOpen or r.tradeOpen or r.trainUpgradeOpen or r.editMode or self.ui.radioOpen or r.peopleOpen
end
function Panel:open(kind)
    if kind=='firstAid' then
        if self:busy() then return false end
        self:releaseArt(); self.kind=kind; return self.firstAid:open()
    end
    if not Access.resources[kind] or self:busy() or not self:eligible() then return false end
    if kind=='sewing' then self.kind=kind; return self.sewing:open() end
    self.kind=kind; self.epoch=self.view.epoch; self.car=self.runtime.saveData.activeCar
    self.runtime.guestActivityOpen=true; self.notice=nil; self.controls=nil; self.drawn=nil; self.page=1
    self.selected=nil; self.ui.keyboardFocusId=nil; self.view:neutralize()
    if kind=='maintenance' then return self:submit('maintenance.acquire',{}) end
    local weapons=Items.weapons(self.runtime.saveData,self.c.catalog); self.selected=weapons[1] and weapons[1].id
    return true
end
function Panel:suspend()
    if self.kind=='firstAid' then self.firstAid:suspend(); return end
    if self.kind=='sewing' then self.sewing:suspend(); return end
    self.runtime.guestActivityOpen=false; self.controls=nil; self.drawn=nil; self.ui.keyboardFocusId=nil
    if self.lease or self.pending and self.pending.command:match('%.acquire$') then self.wantRelease=true end
end
function Panel:releaseArt()
    if self.session then Maintenance.release(self.session); self.session=nil end
end
function Panel:release() self:suspend(); self:releaseArt() end
function Panel:submit(command,args,cleanup)
    if self.pending or not cleanup and (not self.runtime.guestActivityOpen or not self:eligible()) then return false end
    local id,reason=self.view.controller.network:submitCommand(command,args,self.epoch,
        Access.expected(self.runtime.saveData,'companion',command,self.kind))
    if not id then self.notice=failures[reason] or 'Activity unavailable. Try again when ready.'; return false end
    self.pending={id=id,command=command,sentAt=self:now(),target=args.target,itemId=args.itemId,renew=args.renew}
    self.notice='Waiting for the host...'; self.view:neutralize(); return true
end
function Panel:select(id)
    if self.pending or self.lease or not self.runtime.guestActivityOpen then return false end
    if not Items.owned(self.runtime.saveData,id) then return false end
    self.selected=id; self.notice=nil; return true
end
function Panel:startRepair()
    if self.kind~='weaponRepair' or self.pending then return false end
    if self.lease then
        if self.clockUncertain then return self:submit('weaponRepair.step',{leaseId=self.lease,renew=true}) end
        return self:submit('weaponRepair.complete',{leaseId=self.lease})
    end
    local selected=self.drawn and self.drawn.selected or self.selected
    local status=selected and Loot.repairStatus(self.runtime.saveData,self.c.catalog,selected)
    if not status or not status.needed or not status.affordable then return false end
    return self:submit('weaponRepair.acquire',{itemId=selected})
end
function Panel:service(index)
    if self.kind~='maintenance' or not self.lease or self.pending or not self.session or self.session.completed then return false end
    return self:submit('maintenance.step',{leaseId=self.lease,target=index})
end
function Panel:completeMaintenance()
    if self.kind~='maintenance' or not self.lease or not self.session or self.session.completed then return false end
    return self:submit('maintenance.complete',{leaseId=self.lease})
end
function Panel:phase()
    return self.lease and self.kind=='weaponRepair' and self.anchorElapsed and ((self.anchorElapsed+self:now()-self.anchorAt)*.86)%1 or nil
end
function Panel:apply(result,pending)
    local d=result.details
    if pending.command:match('%.acquire$') then
        self.lease=d.leaseId; self.renewAt=self:now()+10
        if self.kind=='maintenance' then
            self:releaseArt(); self.session=Maintenance.new(); self.session.open=true
            self.session.targetDoses=Schema.copy(d.targetDoses); self.session.completed=d.completed
            self.session.conditionFrom=self.runtime.saveData.maintenance.condition; self.session.conditionTo=self.session.conditionFrom
            Maintenance.prepareArt(self.session); self.session.cursorActive=false
            self.notice=d.completed and failures.already or 'Oil all three hubs, then press Done.'
        else self.selected=pending.itemId end
    end
    if pending.command=='weaponRepair.acquire' or pending.command=='weaponRepair.step' then
        local received=pending.receivedAt or self:now(); local rtt=math.max(0,received-pending.sentAt)
        self.anchorAt=received; self.anchorElapsed=d.elapsed+math.min(.175,rtt/2)
        self.clockUncertain=rtt>.35; self.renewAt=self:now()+(self.clockUncertain and 1 or 10)
        self.notice=self.clockUncertain and 'Connection delayed. Wait for the timing check to synchronize.' or 'Tap or press confirm on the brass mark.'
    elseif pending.command=='maintenance.step' then
        self.renewAt=self:now()+10
        if d.targetDoses and self.session then
            self.session.targetDoses=Schema.copy(d.targetDoses)
            local index=pending.target
            if index then self.session.targetMotion[index]=.42; self.session.canPump=.22 end
        end
        if not pending.renew then self.notice=d.success and 'Oil applied. Light all five lamps, then press Done.' or failures[d.reason] end
    elseif pending.command=='maintenance.complete' then
        if d.success or d.reason=='already' then
            self.lease=nil; self.wantRelease=nil
            if self.session then
                self.session.completed=true; self.session.conditionFrom=d.before or self.runtime.saveData.maintenance.condition
                self.session.conditionTo=d.condition or self.session.conditionFrom; self.session.conditionMotion=.6; self.session.testMotion=.7
            end
        end
        self.notice=d.success and ('Service complete. '..d.cost..' oil used. Condition '..d.condition..'%.') or failures[d.reason]
    elseif pending.command=='weaponRepair.complete' then
        self.lease=nil; self.wantRelease=nil; self.anchorElapsed=nil; self.clockUncertain=nil
        self.notice=d.success and ('Repair complete: '..Util.titleFromFile(d.name)..' at '..d.restored..'%. Used '..d.cost..' scrap.') or failures[d.reason]
    elseif pending.command=='activity.release' then self.lease=nil; self.wantRelease=nil; self.anchorElapsed=nil end
end
function Panel:update(dt)
    self.firstAid:update(dt)
    if self.kind=='firstAid' then self.notice=self.firstAid.notice; return end
    self.sewing:update(dt)
    if self.kind=='sewing' then self.notice=self.sewing.notice; return end
    if self.session then Maintenance.update(self.session,dt or 0) end
    local invalid=self.epoch and (self.epoch~=self.view.epoch or self.car~=self.runtime.saveData.activeCar)
    if invalid then self:suspend(); self.lease=nil; self.wantRelease=nil; self.anchorElapsed=nil; self:releaseArt() end
    if self.runtime.guestActivityOpen and (not self.view.focused or self.view.controller.menuOpen or not Access.train(self.runtime.saveData,self:state())) then self:suspend() end
    local pending=self.pending; local result=self.view.controller.network.lastCommandResult
    if pending and result and result.requestId==pending.id then
        pending.receivedAt=pending.receivedAt or self:now()
        if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
        if result.ok and self.runtime.saveData.coop.revision<result.revision then self.notice='Updating the activity...'; return end
        self.pending=nil; self.drawn=nil
        if result.ok and not invalid then self:apply(result,pending)
        elseif not result.ok then
            self.notice=failures[result.reason] or 'Activity unavailable. Review it and try again.'
            if pending.command=='activity.release' and result.reason~='lease_expired' and result.reason~='lease_owner' and result.reason~='stale_scene' then
                self.wantRelease=true; self.retryReleaseAt=self:now()+.6
            elseif pending.command:match('%.acquire$') or pending.command=='activity.release' or result.reason=='lease_expired' or result.reason=='lease_owner' then
                self.lease=nil; self.wantRelease=nil; self.anchorElapsed=nil
            elseif self.lease and (result.reason=='activity_changed' or result.reason=='activity_unavailable' or result.reason=='wrong_activity') then self:suspend()
            else self.renewAt=self:now()+.6 end
        end
    end
    if self.pending then return end
    if self.wantRelease and self.lease then
        if self:now()>=(self.retryReleaseAt or 0) then self:submit('activity.release',{leaseId=self.lease},true) end
        return
    end
    if not self.runtime.guestActivityOpen then self:releaseArt(); return end
    if self.lease and self:eligible() and self:now()>=(self.renewAt or 0) then
        self:submit(self.kind..'.step',{leaseId=self.lease,renew=true})
    end
end
function Panel:targets() return self.controls or {} end
function Panel:keypressed(key)
    if self.kind=='firstAid' then return self.firstAid:keypressed(key) end
    if self.kind=='sewing' then return self.sewing:keypressed(key) end
    if key=='escape' or key=='acback' or key=='m' or key=='r' then self:suspend()
    elseif self.kind=='maintenance' and tonumber(key) and tonumber(key)>=1 and tonumber(key)<=3 then self:service(tonumber(key))
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then Focus.move(self.ui,self:targets(),'guest-activity',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='space' and self.kind=='weaponRepair' then self:startRepair()
    elseif key=='return' or key=='kpenter' or key=='space' then local t=Focus.current(self.ui,self:targets(),'guest-activity'); if t and t.enabled then t.action() end end
    return true
end
function Panel:press(x,y)
    if self.kind=='firstAid' then return self.firstAid:press(x,y) end
    if self.kind=='sewing' then return self.sewing:press(x,y) end
    self:move(x,y)
    for _,target in ipairs(self:targets()) do if Util.pointIn(x,y,target.rect) then
        if target.enabled then self.ui.keyboardFocusId=target.id; target.action() end; break
    end end
    return true
end
function Panel:move(x,y) if self.kind=='firstAid' then return self.firstAid:move(x,y) end; if self.kind=='sewing' then return self.sewing:move(x,y) end; if self.session then self.session.mouseX=x; self.session.mouseY=y end; return true end
function Panel:keyreleased(key) if self.kind=='sewing' then return self.sewing:keyreleased(key) end; return true end
function Panel:releasePointer(x,y) if self.kind=='firstAid' then return self.firstAid:releasePointer(x,y) end; if self.kind=='sewing' then return self.sewing:releasePointer(x,y) end; return true end
function Panel:wheel(dy) if self.kind=='sewing' then return self.sewing:wheel(dy) end; return true end
function Panel:draw()
    if self.kind=='firstAid' then return self.firstAid:draw() end
    if self.kind=='sewing' then return self.sewing:draw() end
    local g=love.graphics; self.controls={}
    local text=function(...) return self.view.trade:textBox(...) end
    local add=function(id,rect,action,enabled)
        self.ui['activity_'..id]=rect; self.controls[#self.controls+1]={id=id,rect=rect,action=action,enabled=enabled~=false}; return rect
    end
    if self.kind=='maintenance' then
        if self.session then
            -- The legacy renderer may normalize display readings. Give it only
            -- detached presentation values, never either player's projection.
            local source=self.runtime.saveData
            local display={resources={oil=source.resources.oil},maintenance=Schema.copy(source.maintenance),trainCars=Schema.copy(source.trainCars),
                accessibility=Schema.copy(source.accessibility or {}),location=source.location,engineLevel=source.engineLevel}
            self.session.message=self.notice; Maintenance.draw(self.session,display)
            for i=1,3 do local index=i; local x,y=Maintenance.targetPosition(i)
                add('hub'..i,{x=x-22,y=y-22,w=44,h=44},function() self:service(index) end,not self.pending and not self.session.completed and self.lease~=nil)
            end
            add('done',{x=659,y=512,w=106,h=64},function() self:completeMaintenance() end,not self.pending and self.lease~=nil and Maintenance.progressCount(self.session)==5 and not self.session.completed)
            add('close',{x=881,y=104,w=42,h=34},function() self:suspend() end,true)
        else
            self.view.inventory:frame(150,190,660,350,1,1); g.setColor(self.c.colors.cream); text(self.notice or 'Opening maintenance...',175,235,610,90,1,'center')
            local rect=self.view.inventory:button('CLOSE',315,410,330,60,true,.9); add('close',rect,function() self:suspend() end,true)
        end
    else
        RepairArt.surface(0,0,960,720)
        for _,r in ipairs({{x=276,y=498,w=418,h=145},{x=711,y=143,w=218,h=494},{x=286,y=126,w=389,h=72}}) do OutfitArt.draw('paper',r,{stretch=true}) end
        local ink={.22,.14,.085,1}; g.setColor(self.c.colors.cream); text('WEAPON WORKBENCH',90,27,665,32,1.27)
        text('SHARED SCRAP '..tostring(self.runtime.saveData.scrap or 0)..'   /   YOUR WEAPONS',92,60,812,25,.75)
        local weapons=Items.weapons(self.runtime.saveData,self.c.catalog)
        self.page=math.max(1,math.min(self.page,math.max(1,math.ceil(#weapons/5))))
        self.drawn={selected=self.selected}; g.setColor(ink); text('OWNED WEAPONS',34,130,213,28,.95,'center')
        for row=1,5 do
            local entry=weapons[(self.page-1)*5+row]
            if entry then local id=entry.id; local r=RepairLayout.row(row)
                RepairArt.draw(id==self.selected and 'selectedRow' or 'normalRow',r.x,r.y,r.w,r.h)
                g.setColor(self.c.colors.cream); text(Util.titleFromFile(entry.name)..'\n'..(entry.ref.kind=='equipment' and 'WEAPON ' or 'BACKPACK ')..entry.ref.index,r.x+9,r.y+8,r.w-45,35,.65)
                text(entry.durability..'%',r.x+r.w-42,r.y+8,36,22,.68,'right'); RepairArt.condition(r.x+10,r.y+48,r.w-20,5,entry.durability)
                add('weapon'..row,r,function() self:select(id) end,not self.pending and not self.lease)
            end
        end
        local button=function(id,label,rect,action,enabled)
            self.view.inventory:button(label,rect.x,rect.y,rect.w,rect.h,enabled,.8); return add(id,rect,action,enabled)
        end
        button('up','^',RepairLayout.listUp,function() self.page=math.max(1,self.page-1) end,not self.pending and not self.lease and self.page>1)
        button('down','v',RepairLayout.listDown,function() self.page=self.page+1 end,not self.pending and not self.lease and self.page*5<#weapons)
        local status=self.selected and Loot.repairStatus(self.runtime.saveData,self.c.catalog,self.selected)
        if status and status.name then
            g.setColor(ink); text(Util.titleFromFile(status.name),299,136,363,49,.98,'center'); RepairArt.item(status.name,RepairLayout.weapon,self.ui,self.c.catalog)
            text('CONDITION '..status.durability..'%',729,170,182,36,.83,'center'); RepairArt.condition(729,212,182,10,status.durability)
            if status.part then
                RepairArt.item(status.part,RepairLayout.part,self.ui,self.c.catalog); text(Util.titleFromFile(status.part),729,280,182,76,.82,'center')
                text(not status.major and 'PART ONLY BELOW 26%' or status.hasPart and 'PART IN BACKPACK' or 'CARRY REQUIRED PART',729,375,182,50,.76,'center')
            end
            text(status.needed and (status.cost..' SCRAP') or 'READY',729,471,182,40,.84,'center')
        end
        RepairArt.timing(RepairLayout.rail,self:phase()); g.setColor(ink)
        text(self.notice or 'Start repair, then tap or press Space on the brass mark.',294,510,382,64,.77,'center')
        button('repair',self.lease and 'TAP / SPACE' or 'BEGIN REPAIR',RepairLayout.start,function() self:startRepair() end,
            not self.pending and status and status.needed and status.affordable or false)
        button('close','CLOSE',RepairLayout.close,function() self:suspend() end,true)
    end
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-activity')) end
end
return Panel
