-- Cosmetic requests use the reliable authority channel; only fresh host
-- motion facts supply either actor's displayed pose or USE countdown.
local Util=require('game.util')
local Life=require('game.coop_last_stand_lifecycle')
local Typography=require('game.typography')
local Panel={};Panel.__index=Panel
local choices={{'idle','STAND'},{'sit','SIT'},{'lay','LAY DOWN'},{'use','USE / ACTION'}}
function Panel.new(view) return setmetatable({view=view,opened=false,selected=1},Panel) end
function Panel:identity()
    local v=self.view;local n=v.controller.network;local data=v.runtime.saveData
    return table.concat({tostring(n),tostring(n and n.sessionId),tostring(n and n.campaignId),
        tostring(v.epoch),tostring(v.motionId),tostring(v.modalDomain),tostring(data and data.scene),
        tostring(data and data.location),tostring(v.runtime.player and v.runtime.player.activeCar)},':')
end
function Panel:domain(retainMenu)
    local v=self.view;local c=v.controller;local f=c.motionFrame;local data=v.runtime.saveData
    local replica=c.replica and c.replica.data;local network=c.network
    local ready=network and (network.status=='ready' or retainMenu==true and self.opened and network.snapshot
        and (network.status=='snapshot' or network.status=='acknowledging'))
    return ready and not network.closed and not network.savePending and v.ready and v.focused~=false
        and not c.menuOpen and not v.runtime.saving and not v.carRequest and not v.carTransition
        and data and replica and not data.tacticalBattle and not v.runtime.battle
        and not data.roamingEncounter and not Life.active(data) and not (data.trainAmbush and data.trainAmbush.active)
        and not (data.events and data.events.current) and not (data.scene=='train' and data.location==50)
        and f and f.ready and not f.paused and f.sessionId==network.sessionId
        and f.sceneEpoch==v.epoch and replica.coop.sceneEpoch==v.epoch and data.coop.sceneEpoch==v.epoch
        and v.runtime.scene==data.scene and data.scene==replica.scene and data.location==replica.location
        and f.motionId==v.motionId and f.serial==v.lastSerial and f.domain==v.modalDomain
        and (retainMenu==true or not v.prediction:stale())
end
function Panel:open()
    if self.opened then self:update();return self.opened end
    if not self:domain() or not self.view:inputAllowed() then return false end
    self.opened=true;self.openIdentity=self:identity();self.notice=nil
    self.view:neutralize();self.neutralSequence=self.view.sequence;return true
end
function Panel:close() self.opened=false;self.openIdentity=nil;self.view:neutralize();return true end
function Panel:submit(pose)
    if not ({idle=true,sit=true,lay=true,use=true})[pose] then return false end
    local v=self.view;local n=v.controller.network;local f=v.controller.motionFrame
    if not self.opened or self.openIdentity~=self:identity() or not self:domain()
        or not v:actionsAllowed() or self.pending or n.pendingCommand then return false end
    if (pose=='sit' or pose=='lay') and (f.ack<(self.neutralSequence or 0)
        or f.companion.moving) then
        self.notice='Wait until your movement has stopped.';return false
    end
    local id,reason=n:submitCommand('player.pose',{pose=pose,motionId=v.motionId},v.epoch,
        {['player:companion']=v.runtime.saveData.coop.revisions['player:companion'] or 0})
    if not id then self.notice='Pose unavailable. Wait for the host connection.';return false,reason end
    self.pending={id=id,network=n,epoch=v.epoch,motionId=v.motionId};self.notice='Waiting for the host...';return true
end
function Panel:update()
    local v=self.view;local c=v.controller;local f=c.motionFrame
    if self.pending and (self.pending.network~=c.network or self.pending.epoch~=v.epoch or self.pending.motionId~=v.motionId) then
        self.pending=nil;self.opened=false;self.openIdentity=nil;self.notice=nil
    end
    if not self:domain(self.opened) or self.opened and self.openIdentity~=self:identity() then
        -- Session still owns any reliable request; a cosmetic panel cannot
        -- retain an obsolete pose wait through a modal/readiness handoff.
        self.frame=nil;self.opened=false;self.openIdentity=nil;self.pending=nil;self.notice=nil
        return
    end
    -- An existing menu may survive a same-identity baseline refresh or brief
    -- motion delay. Commands, displayed poses and receipt acceptance still
    -- require fresh ready facts; menu retention never grants gameplay input.
    if not self:domain() then self.frame=nil;return end
    if self.frame~=f then self.frame=f;self.observedAt=v.elapsed end
    local p=self.pending;local reply=c.network.lastCommandResult
    if not p or not reply or reply.requestId~=p.id or reply.sessionId~=c.network.sessionId or reply.command~='player.pose' then return end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then return end
    if reply.ok then
        local facts=reply.details
        if not facts or facts.actorId~='companion' or v.runtime.saveData.coop.revision<reply.revision
            or f.companion.poseSerial<facts.serial then return end
        -- This cosmetic action is acknowledged, intentionally not checkpointed.
        self.pending=nil;self.notice=nil;self.opened=false;self.openIdentity=nil
    else self.pending=nil;self.notice='Pose unavailable. Wait until the scene is ready.' end
end
function Panel:presentation(id)
    if not self:domain() or self.frame~=self.view.controller.motionFrame then return {} end
    local actor=self.frame[id];if not actor then return {} end
    local remaining=math.max(0,(actor.useRemainingMs or 0)/1000-(self.view.elapsed-(self.observedAt or self.view.elapsed)))
    return {playerPose=actor.stance or 'idle',actionTimer=remaining,actionKind=remaining>0 and 'use' or nil}
end
function Panel:targets()
    local targets={};for index,entry in ipairs(choices) do
        local pose=entry[1];local rect={x=230+(index-1)%2*260,y=240+math.floor((index-1)/2)*90,w=240,h=70}
        targets[#targets+1]={id='pose.'..pose,rect=rect,action=function() return self:submit(pose) end}
    end
    targets[#targets+1]={id='pose.close',rect={x=490,y=450,w=240,h=52},action=function() return self:close() end}
    return targets
end
function Panel:pointer(x,y)
    if not self.opened then return false end
    for _,target in ipairs(self:targets()) do if Util.pointIn(x,y,target.rect) then target.action();return true end end
    return true
end
function Panel:keypressed(key)
    if not self.opened then return false end
    local count=#choices+1
    if key=='escape' or key=='acback' then return self:close()
    elseif key=='left' or key=='up' or key=='a' or key=='w' then self.selected=(self.selected-2)%count+1
    elseif key=='right' or key=='down' or key=='d' or key=='s' then self.selected=self.selected%count+1
    elseif key=='return' or key=='space' or key=='e' then self:targets()[self.selected].action()
    elseif tonumber(key) and tonumber(key)==math.floor(tonumber(key)) and tonumber(key)>=1 and tonumber(key)<=4 then
        self:submit(choices[tonumber(key)][1]) end
    return true
end
function Panel:draw()
    if not self.opened then return end
    local g=love.graphics;g.setColor(.045,.035,.025,.98);g.rectangle('fill',200,150,560,390,10,10)
    g.setColor(1,.93,.78,1)
    Typography.drawText(g,'CHARACTER POSE',228,174,504,42,{align='center',valign='center'})
    for index,target in ipairs(self:targets()) do
        local r=target.rect;g.setColor(index==self.selected and .3 or .17,.135,.09,1);g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
        g.setColor(1,.93,.78,1)
        Typography.drawText(g,choices[index] and choices[index][2] or 'DONE',r.x+8,r.y+8,r.w-16,r.h-16,
            {scale=.85,minScale=.7,align='center',valign='center'})
    end
    if self.notice then
        g.setColor(1,.93,.78,1)
        Typography.drawText(g,self.notice,228,412,504,30,{scale=.75,minScale=.65,align='center'})
    end
end
return Panel
