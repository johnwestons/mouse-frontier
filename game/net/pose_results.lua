local P=require('game.net.protocol')
local R={}
function R.valid(value)
    return P.fields(value,{actorId=true,pose=true,serial=true,useMs=true})
        and (value.actorId=='host' or value.actorId=='companion')
        and ({idle=true,sit=true,lay=true,use=true})[value.pose]==true
        and P.integer(value.serial,1,2147483647) and P.integer(value.useMs,0,450)
        and value.useMs==(value.pose=='use' and 450 or 0)
end
function R.project(value)
    if type(value)~='table' then return nil,'invalid_public_result' end
    local result={actorId=value.actorId,pose=value.pose,serial=value.serial,useMs=value.useMs}
    if not R.valid(result) then return nil,'invalid_public_result' end
    return result
end
return R
