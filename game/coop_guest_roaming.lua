-- Field controls send one owned swing and wait for its saved host outcome.
local Commands=require('game.coop_roaming')
local Util=require('game.util')
local Field={}; Field.__index=Field
function Field.new(view,c)
    return setmetatable({view=view,c=c,seen={},poses={}},Field)
end
function Field:available() return self.view.runtime.scene=='expedition' and not self.view.runtime.battle end
function Field:attack(x,y)
    local view=self.view; local data=view.runtime.saveData
    if not self:available() or not view:inputAllowed() or self.pending or (self.untilTime or 0)>view.elapsed then return false end
    local weapon=Commands.weapon(data,'companion',self.c.catalog)
    if not weapon then self.notice='Equip a working melee weapon in your pack.'; return false end
    local expected={}; for _,scope in ipairs(Commands.scopes(data,'companion')) do expected[scope]=data.coop.revisions[scope] or 0 end
    local id,reason=view.controller.network:submitCommand('roaming.attack',
        {areaId=data.activeExpeditionArea,weaponId=weapon,targetX=x,targetY=y},view.epoch,expected)
    if not id then self.notice='Wait for the area to update before attacking.'; return false,reason end
    self.pending={id=id,epoch=view.epoch}; self.notice='Waiting for the host to save this swing...'; return true
end
function Field:presentation(id)
    local pose=self.poses[id]
    if not pose or pose.epoch~=self.view.epoch then return {} end
    return {actionTimer=math.max(0,pose.untilTime-self.view.elapsed),actionKind='melee',actionHeldItem=pose.weapon,facing=pose.facing}
end
function Field:update()
    local view=self.view; local data=view.runtime.saveData
    if not data then return end
    local combat=data.roamingCombat
    if self.epoch~=view.epoch then
        self.epoch=view.epoch; self.seen={}; self.poses={}; self.notice=nil; self.untilTime=nil
        -- A baseline/reload may contain an old accepted swing. Never replay it.
        for id,cue in pairs(combat and combat.actors or {}) do self.seen[id]=cue.serial end
    end
    for id,cue in pairs(combat and combat.actors or {}) do
        if cue.serial>(self.seen[id] or 0) then
            self.seen[id]=cue.serial
            if self:available() and cue.epoch==view.epoch and cue.areaId==data.activeExpeditionArea then
                self.poses[id]={epoch=view.epoch,untilTime=view.elapsed+cue.duration,weapon=cue.weapon,facing=cue.facing}
                if view.scene.presentFieldAttack then view.scene.presentFieldAttack(cue) end
                if id=='companion' then self.untilTime=view.elapsed+cue.duration; self.notice=cue.message end
            end
        end
    end
    local reply=view.controller.network and view.controller.network.lastCommandResult
    local p=self.pending
    if not p or not reply or reply.requestId~=p.id then return end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if reply.ok and data.coop.revision<reply.revision then return end
    self.pending=nil; self.lastOutcome=reply
    local cue=combat and combat.actors.companion
    local serial=reply.details and reply.details.serial or reply.result and reply.result.serial
    self.notice=reply.ok and cue and cue.serial==serial and cue.message
        or not reply.ok and 'This swing is unavailable. Check your weapon and position.' or nil
    self.noticeUntil=view.elapsed+4
end
function Field:draw()
    local ui=self.view.ui; ui.guestFieldAttack=nil
    local pending=self.view.runtime.saveData and self.view.runtime.saveData.roamingEncounter
    if pending then
        local g=love.graphics
        g.setColor(.045,.035,.025,.96); g.rectangle('fill',230,268,500,94,8,8)
        g.setColor(.96,.88,.69,1); g.printf('COMPANION ENCOUNTER\nWaiting for the host to choose a battle or return to the train.',250,281,460,'center')
        return
    end
    if not self:available() then return end
    local g=love.graphics; local r={x=550,y=202,w=200,h=56}; ui.guestFieldAttack=r
    g.setColor(.17,.135,.09,.94); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
    g.setColor(.96,.88,.69,1); g.printf(self.view.mobile.enabled and 'MELEE ATTACK' or 'MELEE [SPACE / X]',r.x+6,r.y+18,r.w-12,'center')
    local data=self.view.runtime.saveData
    local environment=require('game.expedition_areas').environment(data,data.activeExpeditionArea,true)
    local hazard=environment and ({warning='THE WASH IS RISING — TAKE THE HIGH RIDGE',
        flooded='FLASH FLOOD — THE LOW WASH IS CLOSED',receding='THE FLOOD IS DRAINING — THE WASH WILL REOPEN'})[environment.phase]
    local notice=self.pending and self.notice or hazard or self.notice and (not self.noticeUntil or self.noticeUntil>self.view.elapsed) and self.notice
    if notice then
        g.setColor(.045,.035,.025,.94); g.rectangle('fill',240,268,500,76,8,8)
        g.setColor(.96,.88,.69,1); g.printf(notice,260,282,460,'center')
    end
end
function Field:pointer(x,y)
    if Util.pointIn(x,y,self.view.ui.guestFieldAttack) then self:attack(); return true end
    return false
end
return Field
