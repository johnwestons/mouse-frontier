-- Private companion controls wait for the saved host outcome and projection.
local Commands=require('game.coop_expedition_assistance')
local Panel={}; Panel.__index=Panel
function Panel.new(view) return setmetatable({view=view},Panel) end
function Panel:nearest()
    local v=self.view
    if self.pending or v.runtime.battle or not v:inputAllowed() then return nil end
    return Commands.nearest(v.runtime.saveData,{scene=v.runtime.scene,x=v.runtime.player.x,y=v.runtime.player.y})
end
function Panel:interact()
    local v=self.view; local spot=self:nearest(); if not spot then return false end
    local data=v.runtime.saveData; local area=data.expeditions[data.activeExpeditionArea]
    local args={areaId=data.activeExpeditionArea}; local name
    if spot.kind=='survey' then name='expedition.survey'; args.markerId=spot.markerId
    else name='expedition.cache'; args.containerId=area.chests[spot.chestId].entityId end
    local expected={}
    for _,scope in ipairs(Commands.scopes(data,'companion',args.containerId)) do expected[scope]=data.coop.revisions[scope] or 0 end
    local id,reason=v.controller.network:submitCommand(name,args,v.epoch,expected)
    if not id then self.notice='This interaction is unavailable. Move closer and try again.'; self.noticeUntil=v.elapsed+4; return false,reason end
    self.pending={id=id,epoch=v.epoch,args=args}; self.notice='Waiting for the host to save this interaction...'
    v:neutralize(); return true
end
function Panel:update()
    local v=self.view; local p=self.pending
    if p and p.epoch~=v.epoch then self.pending=nil; self.notice=nil; return end
    local reply=v.controller.network and v.controller.network.lastCommandResult
    if not p or not reply or reply.requestId~=p.id then return end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if reply.ok and (not reply.durable or v.runtime.saveData.coop.revision<reply.revision) then return end
    -- A saved receipt/projection can precede the unpaused motion frame. Keep
    -- the intent until the private panel can open, without sending it again.
    if reply.ok and p.args.containerId then
        self.pending=nil
        if not v:actionsAllowed() then self.pending=p; self.notice='Waiting for the host to continue...'; return end
        if not v.inventory:openContainer(p.args.containerId) then
            self.notice='Cache saved. Move closer to open it.'; self.noticeUntil=v.elapsed+4; self.lastOutcome=reply; return
        end
    end
    self.pending=nil; self.lastOutcome=reply; self.noticeUntil=v.elapsed+4
    if not reply.ok then
        self.notice=reply.reason=='cache_sealed' and 'This cache is sealed.'
            or reply.reason=='stale_revision' and 'The area changed. Try this interaction again.'
            or 'This interaction is unavailable. Move closer and try again.'; return
    end
    local detail=reply.details or reply.result
    self.notice=Commands.message(detail)
end
return Panel
