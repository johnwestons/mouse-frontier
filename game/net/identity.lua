-- Persist only the credential digest in the host campaign. The raw credential
-- belongs to the joining device's connection store and the admission exchange.
local Crypto=require('game.net.crypto')
local P=require('game.net.protocol')
local Identity={}
local networkFields={version=true,campaignId=true,companionId=true,credentialHash=true,bindingVersion=true}
local credentialFields={campaignId=true,companionId=true,token=true}
function Identity.credential(value)
    return P.fields(value,credentialFields) and Crypto.isHex(value.campaignId,32)
        and Crypto.isHex(value.companionId,32) and Crypto.isHex(value.token,64)
end
function Identity.validate(campaign)
    local value=campaign.coop and campaign.coop.network
    if value==nil then return true end
    if not P.fields(value,networkFields) or value.version~=1 or not Crypto.isHex(value.campaignId,32)
        or not P.integer(value.bindingVersion,0,2147483647) then return false,'invalid connection identity' end
    if value.bindingVersion==0 then
        if value.companionId~=nil or value.credentialHash~=nil then return false,'invalid unbound identity' end
    elseif not (campaign.players and campaign.players.companion) or not Crypto.isHex(value.companionId,32)
        or not Crypto.isHex(value.credentialHash,64) then return false,'invalid companion binding' end
    return true
end
function Identity.matches(network,credential,hash)
    if type(network)~='table' or not Identity.credential(credential) or network.campaignId~=credential.campaignId
        or network.companionId~=credential.companionId then return false end
    local ok,digest=pcall(hash or Crypto.hash,credential.token)
    return ok and Crypto.isHex(digest,64) and Crypto.equal(network.credentialHash,digest)
end
return Identity
