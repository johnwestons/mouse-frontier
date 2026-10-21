-- Nearby door/gate actions change only the admitted companion's local visit.
local Scenes=require('game.coop_scenes')
local Home=require('game.home_stop')
local Settlements=require('game.settlements')
local Doors=require('game.interior_doors')
local Areas=require('game.expedition_areas')
local Caravan=require('game.crow_caravan_area')
local Caravans=require('game.crow_caravans')
local Visits={}; Visits.__index=Visits
local function target(command,label,args) return {command=command,label=label,args=args or {}} end
function Visits.new(view,c) return setmetatable({view=view,c=c},Visits) end
function Visits:exitTarget()
    local r=self.view.runtime; local data=r.saveData
    if not data or data.coop.journey or r.battle or require('game.coop_last_stand_lifecycle').active(data) then return end
    if r.scene=='train' then
        local e=data.encounters and data.encounters[tostring(data.location)]
        if Home.isHome(data) or (not e or not e.hasMob or e.resolved)
            and (data.events[tostring(data.location)] or e and e.hasMob and e.resolved) then
            return target('scene.leaveTrain','LEAVE TRAIN')
        end
    elseif r.scene=='house' then return target('scene.exitHouse','EXIT HOME')
    elseif r.scene=='caravan' then return target('scene.caravan','RETURN TO STOP',{action='return'})
    elseif Home.isOffice(data) then return target('scene.office','EXIT OFFICE',{action='exitOffice'})
    elseif r.scene=='stop' or r.scene=='expedition' then
        if Home.isHome(data) then
            local interaction=Home.interaction(data,r.player)
            if not interaction or interaction.action~='board' then return end
        end
        return target('scene.returnTrain','BOARD TRAIN')
    end
end
function Visits:nearest()
    local v=self.view; local r=v.runtime; local data=r.saveData; local p=r.player
    if self.pending or not data or not p or r.battle or data.coop.journey
        or require('game.coop_last_stand_lifecycle').active(data) then return end
    if Home.isHome(data) then
        local action=Home.interaction(data,p)
        if action and (action.action=='enterOffice' or action.action=='exitOffice') then
            return target('scene.office',action.action=='enterOffice' and 'ENTER TRAIN OFFICE' or 'EXIT OFFICE',{action=action.action})
        elseif action and action.action=='board' then return self:exitTarget() end
        return
    end
    if r.scene=='house' then
        local layout=v.scene.ensureStopLayout()
        local scenery=self.c.content and self.c.content.scenery
        if Doors.near(p.x,p.y,layout.interior,scenery and scenery.interiorFiles) then return self:exitTarget() end
    elseif r.scene=='stop' then
        local door=Settlements.nearDoor(p.x,p.y,data.location)
        if door then return target('scene.enterHouse','ENTER HOME',{door=door}) end
        if Settlements.nearTrain(p.x,p.y,data.location) then return self:exitTarget() end
        local camp=Caravans.lookup(data,data.location); local gate=camp and Caravans.isActive(camp) and Caravan.stopEntrance(data.location)
        if gate and (p.x-gate.x)^2+(p.y-gate.y)^2<=gate.radius^2 then
            return target('scene.caravan','ENTER CARAVAN',{action='enter',stop=data.location})
        end
    elseif r.scene=='caravan' then
        -- Restore normalizes campaign state. Query authored geometry without
        -- assigning the companion's presence overlay back into the world.
        local camp=Caravans.lookup(data,data.location)
        local session=camp and Caravan.new({stop=camp.stop,seed=camp.seed,variantId=camp.variantId})
        local action=session and Caravan.interaction(session,p)
        if action and action.action=='returnStop' then return self:exitTarget() end
    end
    local action=Areas.interaction(data,r.scene,p,true)
    if action and action.action=='enterArea' then
        return target('scene.expedition',action.label,{action='enterArea',areaId=action.targetArea,spawn=action.spawn})
    elseif action and action.action=='returnStop' then return target('scene.expedition',action.label,{action='returnStop'}) end
end
function Visits:submit(selected)
    local v=self.view
    if not selected or self.pending or not v:inputAllowed() then return false end
    local expected={}; local data=v.runtime.saveData
    for _,scope in ipairs(Scenes.localScopes('companion')) do expected[scope]=data.coop.revisions[scope] or 0 end
    local id,reason=v.controller.network:submitCommand(selected.command,selected.args,v.epoch,expected)
    if not id then self.notice='Wait for the connection, then try again.'; self.noticeUntil=v.elapsed+4; return false,reason end
    self.lastOutcome=nil
    self.pending={id=id,epoch=v.epoch,selected=selected,revision=data.coop.revision,
        sceneRevision=require('game.coop_presence').revision(data,'companion'),retries=0,started=v.elapsed}
    self.notice='Entering area...'; v:neutralize(); return true
end
function Visits:interact() return self:submit(self:nearest()) end
function Visits:leave() return self:submit(self:exitTarget()) end
function Visits:update()
    local v=self.view; local p=self.pending
    if not p then if self.noticeUntil and v.elapsed>=self.noticeUntil then self.notice=nil end; return end
    if p.epoch~=v.epoch then self.pending=nil; self.notice=nil; return end
    local reply=v.controller.network and v.controller.network.lastCommandResult
    if not reply or reply.requestId~=p.id then return end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then return end
    if reply.reason=='stale_revision' and p.retries<2 and v.elapsed-p.started<6
        and require('game.coop_presence').revision(v.runtime.saveData,'companion')==p.sceneRevision then
        if v.runtime.saveData.coop.revision<=p.revision or not v:actionsAllowed() then return end
        self.pending=nil
        if self:submit(p.selected) then self.pending.retries=p.retries+1; return end
    end
    if reply.ok and (not reply.durable or v.runtime.saveData.coop.revision<reply.revision) then return end
    self.pending=nil; self.lastOutcome=reply
    self.notice=not reply.ok and 'This entrance is unavailable. Move closer and try again.' or nil
    self.noticeUntil=v.elapsed+4
end
return Visits
