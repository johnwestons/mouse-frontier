-- Bridges local host approval to durable authority administration. No peer
-- may enroll itself or choose campaign/companion identifiers or credentials.
local Connections=require('game.coop_connections')
local Identity=require('game.net.identity')
local Crypto=require('game.net.crypto')
local P=require('game.net.protocol')
local Admission={}; Admission.__index=Admission
local function invoke(fn,...)
    local ok,value=pcall(fn,...); return ok and value or nil
end
function Admission.new(authority,context)
    if not authority.checkpoint or authority.pendingSave then return nil,'save_not_ready' end
    if authority.bindings.companion then return nil,'companion_connected' end
    if not authority.handlers['session.host'] then Connections.install(authority,context) end
    local self=setmetatable({authority=authority,token=context.token or Crypto.token,hash=context.hash or Crypto.hash},Admission)
    if not authority.campaign.coop.network then
        local id=invoke(self.token,16)
        if not Crypto.isHex(id,32) then return nil,'entropy_unavailable' end
        local result=authority:submitLocal('session.host',{campaignId=id})
        if not result.ok or not result.durable then return nil,result.reason or 'save_not_ready' end
    end
    return self
end
function Admission:preflight()
    local authority=self.authority
    return authority.checkpoint~=nil and authority.pendingSave==nil
        and authority.campaign.coop.checkpoints.sessionSerial==authority.sessionSerial
end
function Admission:authenticate(credential)
    local network=self.authority.campaign.coop.network
    if self:preflight() and Identity.matches(network,credential,self.hash) then
        return {campaignId=network.campaignId,companionId=network.companionId}
    end
end
function Admission:issue(request)
    if not self:preflight() then return nil,'save_not_ready' end
    if self.authority.bindings.companion then return nil,'companion_connected' end
    if not P.fields(request,{generation=true,name=true,character=true}) or not P.integer(request.generation,1,2147483647)
        or not P.text(request.name,32) or not P.text(request.character,128) then return nil,'invalid_approval' end
    local network=self.authority.campaign.coop.network
    if self.pending and self.pending.generation==request.generation
        and Identity.matches(network,self.pending.credential,self.hash) then return self.pending.credential end
    local token=invoke(self.token,32)
    local companionId=network.companionId or invoke(self.token,16)
    if not Crypto.isHex(token,64) or not Crypto.isHex(companionId,32) then return nil,'entropy_unavailable' end
    local digest=invoke(self.hash,token)
    if not Crypto.isHex(digest,64) then return nil,'hash_unavailable' end
    local credential={campaignId=network.campaignId,companionId=companionId,token=token}
    local existing=self.authority.campaign.players.companion~=nil
    local args={companionId=companionId,credentialHash=digest}
    if not existing then args.character=request.character end
    local result=self.authority:submitLocal(existing and 'session.rebind' or 'session.enroll',args)
    if not result.ok then return nil,result.reason end
    self.pending={generation=request.generation,credential=credential}
    if not result.durable then return nil,'save_not_ready' end
    return credential
end
function Admission:forgetPending(generation)
    if self.pending and self.pending.generation==generation then self.pending=nil end
end
return Admission
