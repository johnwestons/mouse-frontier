-- Owns only the selected local slot. Remote world state never becomes a save.
local Traveler=require('game.coop_traveler')
local Schema=require('game.save_schema')
local Crypto=require('game.net.crypto')
local Codec=require('game.net.codec')
local Client={}; Client.__index=Client
local function signature(profile)
    return Codec.encode(assert(Traveler.pack(profile)),{maxBytes=65536,maxDepth=12,maxEntries=4096,maxStringBytes=256})
end
function Client.new(context) return setmetatable({c=context,nextSave=0},Client) end
function Client:write(data)
    local ok,result=pcall(self.c.write,self.c.slot,data)
    if not ok or result~=true then self.error='traveler_save_failed'; self.retryAfter=self.c.clock()+2; return nil,self.error end
    self.data=data; self.error=nil; self.retryAfter=nil; return true
end
function Client:checkout(campaignId)
    local data=self.c.read(self.c.slot)
    if not data then return nil,'selected_save_unavailable' end
    if data.tacticalBattle or data.roamingEncounter or data.trainAmbush and data.trainAmbush.active
        or require('game.coop_last_stand_lifecycle').active(data) then return nil,'traveler_local_combat' end
    local token=self.c.token or Crypto.token
    local checked,profile=Traveler.checkout(data,campaignId,self.c.address,token(16),token(16))
    if not checked then return nil,profile end
    if not Traveler.validEnvelope(profile,self.c.allowed) then return nil,'invalid_traveler' end
    if not self:write(checked) then return nil,self.error end
    self.profile=profile; self.campaignId=campaignId; self.lastSignature=signature(profile)
    self.nextSave=self.c.clock()+2
    return profile
end
function Client:observe(data)
    if not self.profile or not data then return true end
    local actor=data.players.companion
    if not actor or not Traveler.sameVisit(actor.travelIdentity,self.profile) then return nil,'traveler_identity_mismatch' end
    self.latest=data
    if actor.travelReturn then self.leaving=true end
    return true
end
function Client:saveLatest(force)
    if self.done then return true end
    if not self.latest or not self.profile then return true end
    local actor=self.latest.players.companion; local returned=actor.travelReturn
    local now=self.c.clock()
    if not force and now<self.nextSave then return true end
    self.nextSave=now+2
    local profile=returned and Traveler.unpack(returned.profile) or {
        version=1,profileId=self.profile.profileId,tripId=self.profile.tripId,serial=self.profile.serial,
        actor=Traveler.exportActor(self.latest,'companion')}
    if not profile then return nil,'invalid_traveler' end
    local bytes=signature(profile)
    if not returned and bytes==self.lastSignature then return true end
    local draft,why=Traveler.applyCheckpoint(self.data,profile,{campaignId=self.campaignId,
        revision=returned and returned.revision or self.latest.coop.revision,returned=returned~=nil},self.c.allowed)
    if not draft then return nil,why end
    if returned then draft.localTraveler.lastReturn.pending=true end
    if why~='already_returned' or not self.data.localTraveler.lastReturn.pending then
        if not self:write(draft) then return nil,self.error end
    end
    self.lastSignature=bytes
    if returned then self.savedReturn=true end
    return true
end
function Client:finishAck()
    local draft=assert(Schema.copy(self.data)); local last=draft.localTraveler.lastReturn
    if not last or last.id~=self.profile.tripId or last.serial~=self.profile.serial then return nil,'traveler_visit_mismatch' end
    last.pending=nil
    if not self:write(draft) then return nil,self.error end
    self.done=true; return true
end
function Client:connectionFailed(reason)
    if reason=='traveler_already_returned' and self.profile and self.data.localTraveler.lastReturn
        and self.data.localTraveler.lastReturn.pending then return self:finishAck() end
    if (reason=='host_declined' or reason=='traveler_return_pending') and self.profile and not self.latest then
        local draft=assert(Schema.copy(self.data)); draft.localTraveler.trip=nil
        return self:write(draft)
    end
    return self:saveLatest(true)
end
function Client:requestReturn() self.leaving=true; self.error=nil end
function Client:update(network)
    if self.done then return end
    if self.retryAfter and self.c.clock()<self.retryAfter then return end
    if not self.latest then return end
    local actor=self.latest.players.companion
    local ok,why=self:saveLatest(actor.travelReturn~=nil and not self.savedReturn)
    if not ok then self.error=why; return end
    if self.savedReturn and actor.travelIdentity.status=='closed' then self:finishAck(); return end
    local pending=self.pending
    if pending then
        local reply=network.lastCommandResult
        if not reply or reply.requestId~=pending or reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then return end
        if reply.ok and (not reply.durable or self.latest.coop.revision<reply.revision) then return end
        self.pending=nil
        if not reply.ok and reply.reason~='stale_revision' and reply.reason~='stale_scene' then
            self.error=reply.reason; self.leaving=false; return
        end
    end
    if not self.leaving or network.status~='ready' then return end
    local command=self.savedReturn and 'traveler.ack' or 'traveler.return'
    local expected={}; for _,scope in ipairs({'player:companion','session'}) do expected[scope]=self.latest.coop.revisions[scope] or 0 end
    self.pending=network:submitCommand(command,{tripId=self.profile.tripId,serial=self.profile.serial},self.latest.coop.sceneEpoch,expected)
end
return Client
