-- Local host administration. A durable receipt identifies the exact operation
-- and peer; a delayed save retry must never disconnect a replacement connection.
local Management={}
function Management.state(c)
    local r=c.context.runtime
    local extra=c.context.managementState and c.context.managementState() or {}
    local a=c.authority
    return {screen=r.state,scene=r.scene,saving=r.saving==true or a and a.pendingSave~=nil or false,
        pendingAdmission=c.network and c.network.link~=nil and not c.network.link.admitted or false,
        traveling=r.travelTransition~=nil and r.travelTransition~=false,
        changingCar=r.carTransition~=nil and r.carTransition~=false
            or c.context.commands.carBusy and c.context.commands.carBusy('host')==true or false,
        encounterActive=r.battle~=nil and r.battle~=false or r.lastStand and r.lastStand.capture==true
            or r.trainAmbush and r.trainAmbush.phase~='complete' or false,
        activityBlocked=extra.activityBlocked==true or r.firstAid~=nil and r.firstAid~=false
            or r.shootingRange~=nil and r.shootingRange~=false or r.outfitCraftingOpen==true
            or r.travelConfirm==true or r.exitPrompt~=nil and r.exitPrompt~=false}
end
local function current(c,m)
    local r=c.context.runtime
    return c.phase=='hosting' and c.network==m.network and not m.network.closed
        and c.authority==m.authority and c.admission==m.admission and c.campaign==m.campaign
        and r.saveData==m.campaign and r.selectedSlot==m.slot and c.hostedSlot==m.slot
        and m.authority.sessionId==m.sessionId
        and m.campaign.coop.checkpoints.sessionSerial==m.authority.sessionSerial
end
function Management.can(c,kind)
    local r=c.context.runtime; local a=c.authority; local n=c.network
    if c.phase~='hosting' or not n or n.closed or not a or not c.admission then return false,'host_only' end
    if r.saveData~=c.campaign or r.selectedSlot~=c.hostedSlot or a.campaign~=c.campaign then return false,'campaign_changed' end
    if c.management and c.management.phase=='saving' then return false,'management_busy' end
    if not c.campaign.players.companion then return false,'companion_missing' end
    if a.pendingSave or r.saving then return false,'save_not_ready' end
    local s=Management.state(c)
    if s.pendingAdmission then return false,'pending_admission' end
    if s.screen~='game' and s.screen~='battle' and s.screen~='ending' then return false,'management_unavailable' end
    if kind=='kick' then
        local link=n.link
        if not link or not link.admitted or a.bindings.companion~=link.generation then return false,'companion_missing' end
        return true
    end
    if kind~='replace' then return false,'invalid_management' end
    if n.link or a.bindings.companion or n.hasDeparting and n:hasDeparting() then return false,'companion_connected' end
    local d=c.campaign; local state=a.activityState; local range=d.rangeSessions and d.rangeSessions.companion
    if s.screen~='game' or s.scene~='train' or d.stopped~=true or d.coop.journey
        or s.traveling or s.changingCar or s.encounterActive or s.activityBlocked
        or d.tacticalBattle or d.roamingEncounter or require('game.coop_last_stand_lifecycle').active(d)
        or d.trainAmbush and d.trainAmbush.active or d.events and d.events.current
        or range and range.phase=='play' or next(state.resources)~=nil
        or state.positionOccupancy and next(state.positionOccupancy.windows)~=nil then return false,'replacement_unavailable' end
    return true
end
function Management.select(c,kind)
    local ok,reason=Management.can(c,kind); if not ok then return c:_error(reason) end
    local a=c.authority
    local m={kind=kind,phase=kind=='kick' and 'confirm' or 'select',network=c.network,authority=a,
        admission=c.admission,campaign=c.campaign,slot=c.hostedSlot,sessionId=a.sessionId,
        generation=kind=='kick' and c.network.link.generation or nil,characterIndex=1}
    if kind=='replace' then
        for index,name in ipairs(c:characters()) do if name==c.campaign.players.companion.character then m.characterIndex=index end end
    end
    c.management=m; c.error=nil; return true
end
function Management.cancel(c)
    if c.management and c.management.phase=='saving' then return false end
    c.management=nil; c.error=nil; return true
end
function Management.update(c)
    local m=c.management; if not m then return end
    if not current(c,m) then c.management=nil; c.error='management_expired'; return end
    if m.phase~='saving' then return end
    if m.authority.pendingSave then return end
    local reply,reason=m.admission:managementResult()
    if not reply or not reply.ok or not reply.durable then c.error=reason or reply and reply.reason or 'save_not_ready'; return end
    local result=reply.result; local binding=m.campaign.coop.network
    if not result or result.management~=m.kind or result.campaignId~=binding.campaignId
        or result.companionId~=binding.companionId or result.bindingVersion~=binding.bindingVersion
        or m.requestId~=reply.requestId or m.kind=='replace' and result.character~=m.character
        or m.kind=='kick' and result.generation~=m.generation then
        c.error='management_expired'; return
    end
    if m.kind=='kick' then
        local link=m.network.link
        -- A peer may have disconnected while the save was pending. Do not
        -- confuse that absence (or a newer generation) with the original peer.
        if link and link.admitted and link.generation==m.generation then
            local ok,kickError=m.network:kick(m.generation)
            if not ok then c.error=kickError or 'management_expired'; return end
        end
    end
    m.admission:clearManagement();c.management=nil;c.error=nil
    c.managementNotice=m.kind=='kick' and 'Companion disconnected. Their items and progress are saved.'
        or 'Saved companion traveler changed. Their items and progress are kept.'
end
function Management.begin(c,kind,value)
    local m=c.management
    if not m or m.kind~=kind or not current(c,m) then return c:_error('management_expired') end
    if m.phase=='saving' then return c:_error('management_busy') end
    local ok,reason=Management.can(c,kind);if not ok then return c:_error(reason) end
    if kind=='kick' and (not c.network.link or c.network.link.generation~=m.generation) then return c:_error('stale_generation') end
    local reply,errorMessage
    if kind=='kick' then reply,errorMessage=m.admission:kick(m.generation)
    else reply,errorMessage=m.admission:replace(value);m.character=value end
    if not reply or not reply.ok then return c:_error(errorMessage or reply and reply.reason) end
    m.phase='saving';m.requestId=reply.requestId;c.error=reply.durable and nil or 'save_not_ready'
    Management.update(c);return true
end
return Management
