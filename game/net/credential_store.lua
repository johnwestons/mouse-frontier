-- Guest-only connection metadata. This data-only file is never a campaign
-- save and never contains character inventories, story state or host settings.
local Codec=require('game.net.codec')
local Identity=require('game.net.identity')
local P=require('game.net.protocol')
local Store={PATH='coop-connections.dat',MAX=16}
local LIMITS={maxBytes=8192,maxDepth=4,maxEntries=100,maxStringBytes=128}
local function decode(bytes)
    local data=Codec.decode(bytes,LIMITS)
    if not P.fields(data,{version=true,entries=true}) or data.version~=1 or type(data.entries)~='table' then return nil end
    local seen,count={},0
    for index,credential in pairs(data.entries) do
        if not P.integer(index,1,Store.MAX) or not Identity.credential(credential) or seen[credential.campaignId] then return nil end
        seen[credential.campaignId]=true; count=count+1
    end
    if count~=#data.entries then return nil end
    for index=1,count do if not data.entries[index] then return nil end end
    return data
end
local function read(fs,path)
    local ok,bytes=pcall(fs.read,path)
    return ok and type(bytes)=='string' and bytes or nil
end
function Store.load(fs)
    fs=fs or love.filesystem
    local primary=read(fs,Store.PATH)
    if primary then local value=decode(primary); if value then return value end end
    local temporary=read(fs,Store.PATH..'.tmp')
    if temporary then local value=decode(temporary); if value then return value end end
    if primary or temporary then return nil,'invalid_connection_store' end
    local ok,info=pcall(fs.getInfo,Store.PATH)
    local tempOk,tempInfo=pcall(fs.getInfo,Store.PATH..'.tmp')
    if not ok or not tempOk or info or tempInfo then return nil,'connection_store_unreadable' end
    return {version=1,entries={}}
end
function Store.find(data,campaignId)
    for _,credential in ipairs(data.entries) do
        if credential.campaignId==campaignId then
            return {campaignId=credential.campaignId,companionId=credential.companionId,token=credential.token}
        end
    end
end
function Store.save(credential,fs)
    if not Identity.credential(credential) then return nil,'invalid_credential' end
    fs=fs or love.filesystem
    local data,reason=Store.load(fs)
    if not data then return nil,reason end
    for index=#data.entries,1,-1 do
        if data.entries[index].campaignId==credential.campaignId then table.remove(data.entries,index) end
    end
    if #data.entries>=Store.MAX then return nil,'connection_store_full' end
    data.entries[#data.entries+1]={campaignId=credential.campaignId,companionId=credential.companionId,token=credential.token}
    local bytes=assert(Codec.encode(data,LIMITS))
    for _,path in ipairs({Store.PATH..'.tmp',Store.PATH}) do
        local ok,written=pcall(fs.write,path,bytes)
        if not ok or written~=true or read(fs,path)~=bytes then return nil,'connection_store_write_failed' end
    end
    pcall(fs.remove,Store.PATH..'.tmp')
    return true
end
return Store
