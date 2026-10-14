local P=require('game.net.protocol')
local R={}
local fields={actorId=true,questId=true,revision=true,action=true,windowId=true,previousWindowId=true,
    leaseId=true,expiresIn=true,phaseRevision=true}
local function window(value) return value=='wide' or value=='tall' end
function R.valid(value)
    return P.fields(value,fields) and (value.actorId=='host' or value.actorId=='companion')
        and P.text(value.questId,32) and value.questId:match('^e[1-9]%d*$')~=nil
        and P.integer(value.revision,1,1e9)
        and ((value.action=='select' or value.action=='ready') and window(value.windowId)
            and P.text(value.leaseId,32) and value.leaseId:match('^p[1-9]%d*$')~=nil and value.expiresIn==30
            or value.action=='release' and value.windowId==nil and value.leaseId==nil and value.expiresIn==nil)
        and (value.action=='select' and value.phaseRevision==nil
            or value.action=='ready' and P.integer(value.phaseRevision,1,1e9)
            or value.action=='release' and (value.phaseRevision==nil or P.integer(value.phaseRevision,1,1e9)))
        and (value.previousWindowId==nil or window(value.previousWindowId))
end
function R.project(value)
    if type(value)~='table' then return nil,'invalid_public_result' end
    local result={}; for key in pairs(fields) do result[key]=value[key] end
    if not R.valid(result) then return nil,'invalid_public_result' end
    return result
end
return R
