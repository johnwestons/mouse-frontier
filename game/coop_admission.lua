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
    if self.management then return nil,'management_busy' end
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

-- Host management revokes access using a never-issued token. Its raw bytes are
-- discarded locally; only the digest enters an argument or durable receipt.
function Admission:_management(kind,value)
    local previous=self.management
    if previous then
        if previous.kind~=kind or previous.value~=value then return nil,'management_busy' end
        return self:managementResult()
    end
    if not self:preflight() then return nil,'save_not_ready' end
    if self.pending then return nil,'pending_admission' end
    local authority=self.authority;local network=authority.campaign.coop.network
    if not network or not authority.campaign.players.companion then return nil,'companion_missing' end
    if kind=='replace' then
        if authority.bindings.companion then return nil,'companion_connected' end
        if not P.text(value,128) then return nil,'invalid_character' end
    elseif kind=='kick' then
        if not P.integer(value,1,2147483647) or authority.bindings.companion~=value then return nil,'stale_generation' end
    else return nil,'invalid_management' end
    local token=invoke(self.token,32)
    if not Crypto.isHex(token,64) then return nil,'entropy_unavailable' end
    local digest=invoke(self.hash,token);token=nil
    if not Crypto.isHex(digest,64) then return nil,'hash_unavailable' end
    local args={companionId=network.companionId,credentialHash=digest}
    if kind=='replace' then
        args.previousCompanionId=network.companionId;args.character=value
        args.companionId=invoke(self.token,16)
        if not Crypto.isHex(args.companionId,32) then return nil,'entropy_unavailable' end
    else args.generation=value end
    local request,reason=authority:prepareRequest('host','session.'..kind,args)
    if not request then return nil,reason end
    local reply=authority:execute('host',0,request)
    if reply.ok then self.management={kind=kind,value=value,request=request} end
    return reply
end
function Admission:replace(character)return self:_management('replace',character)end
function Admission:kick(generation)return self:_management('kick',generation)end
function Admission:managementResult()
    if not self.management then return nil,'management_missing' end
    return self.authority:execute('host',0,self.management.request)
end
function Admission:clearManagement()self.management=nil end
return Admission
