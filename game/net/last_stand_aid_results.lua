local P=require('game.net.protocol')
local Aid=require('game.net.first_aid_results')
local R={}
local actions={acquire=true,inspect=true,press=true,move=true,release=true,choose=true,tick=true,pause=true,complete=true}
local base={actorId=true,questId=true,revision=true,action=true}
local session={leaseId=true,itemName=true,phase=true,ready=true,dragging=true,pointer=true,outcome=true,expiresIn=true}
local function number(n) return type(n)=='number' and n==n and n>=0 and n<=100 end
local function fields(value)
    local f={}; for key in pairs(base) do f[key]=true end
    if value.inspected then f.inspected=true; f.treated=true
    elseif value.completed then f.completed=true; f.integrityBefore=true; f.integrity=true
    else for key in pairs(session) do f[key]=true end end
    return f
end
function R.valid(value)
    if type(value)~='table' then return false end
    if not P.fields(value,fields(value)) or value.actorId~='host' and value.actorId~='companion'
        or not P.text(value.questId,32) or not value.questId:match('^e[1-9]%d*$')
        or not P.integer(value.revision,1,1e9) or not actions[value.action] then return false end
    if value.inspected then return value.inspected==true and (value.action=='inspect' or value.action=='acquire') and type(value.treated)=='boolean' end
    if value.completed then return value.action=='complete' and value.completed==true and number(value.integrityBefore)
        and number(value.integrity) and value.integrity==math.min(100,value.integrityBefore+12) end
    if value.action=='complete' or value.action=='inspect' or value.itemName~='house medical supplies' then return false end
    local facts={questId=value.questId}; for key in pairs(session) do facts[key]=value[key] end
    return Aid.valid('firstAid.step',facts)
end
function R.project(value)
    if type(value)~='table' then return nil,'invalid_public_result' end
    local result={}
    for key in pairs(fields(value)) do
        if key=='pointer' and type(value.pointer)=='table' then result.pointer={x=value.pointer.x,y=value.pointer.y}
        else result[key]=value[key] end
    end
    if not R.valid(result) then return nil,'invalid_public_result' end
    return result
end
return R
