-- Ephemeral treatment facts only. Persisted progress arrives on the state
-- channel, so a long ointment trail cannot overflow the small control packet.
local P=require('game.net.protocol')
local R={}
local fields={leaseId=true,questId=true,itemName=true,phase=true,ready=true,dragging=true,pointer=true,outcome=true,expiresIn=true}
local outcomes={progress=true,complete=true,cancelled=true}
local function bounded(n,min,max) return type(n)=='number' and n==n and n>=min and n<=max end
function R.valid(command,value)
    if command=='firstAid.complete' then
        return P.fields(value,{completed=true,gained=true,total=true,item=true}) and value.completed==true
            and P.integer(value.gained,0,1000000000) and P.integer(value.total,0,1000000000) and P.text(value.item,128)
    end
    return P.fields(value,fields) and P.text(value.leaseId,32) and value.leaseId:match('^l[1-9]%d*$')~=nil
        and P.text(value.questId,62) and P.text(value.itemName,128) and P.integer(value.phase,1,6)
        and type(value.ready)=='boolean' and (not value.ready or value.phase==6) and type(value.dragging)=='boolean'
        and P.fields(value.pointer,{x=true,y=true}) and bounded(value.pointer.x,-4096,4096) and bounded(value.pointer.y,-4096,4096)
        and (value.outcome==nil or outcomes[value.outcome]) and P.integer(value.expiresIn,0,30)
        and (value.outcome=='cancelled' and value.expiresIn==0 or value.outcome~='cancelled' and value.expiresIn>0)
        and (value.outcome~='complete' or value.ready)
end
function R.project(command,value)
    if type(value)~='table' then return nil,'invalid_public_result' end
    local result={}; local allowed=command=='firstAid.complete' and {completed=true,gained=true,total=true,item=true} or fields
    for key in pairs(allowed) do
        if key=='pointer' and type(value.pointer)=='table' then result.pointer={x=value.pointer.x,y=value.pointer.y}
        else result[key]=value[key] end
    end
    if not R.valid(command,result) then return nil,'invalid_public_result' end
    return result
end
return R
