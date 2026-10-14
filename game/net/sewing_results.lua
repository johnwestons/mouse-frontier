-- Sewing replies expose presentation facts, never projects or absolute clocks.
local P=require('game.net.protocol')
local Definitions=require('game.outfit_catalog')
local R={}
local common={action=true,success=true,leaseId=true,ownerPlayerId=true,tension=true,pulling=true,expiresIn=true}
local actions={acquire={},renew={},suspend={},pullStart={},adjust={},
    start={changed=true,reason=true},
    point={changed=true,correct=true,complete=true,stageComplete=true,quality=true,outputId=true},
    pullRelease={changed=true,correct=true,complete=true,stageComplete=true,quality=true,outputId=true},
    collect={changed=true,complete=true,quality=true,outputId=true,score=true,inventoryFull=true,reason=true}}
local reasons={materials=true,project_busy=true,inventory_full=true,project_incomplete=true}
function R.valid(value)
    if type(value)~='table' or not actions[value.action] then return false end
    local allowed={}; for key in pairs(common) do allowed[key]=true end
    for key in pairs(actions[value.action]) do allowed[key]=true end
    if not P.fields(value,allowed) or type(value.success)~='boolean'
        or not P.text(value.leaseId,32) or not value.leaseId:match('^l[1-9]%d*$')
        or (value.ownerPlayerId~='host' and value.ownerPlayerId~='companion')
        or type(value.tension)~='number' or value.tension~=value.tension or value.tension<0 or value.tension>1
        or type(value.pulling)~='boolean' or not P.integer(value.expiresIn,1,30) then return false end
    for _,key in ipairs({'changed','correct','complete','stageComplete','inventoryFull'}) do
        if value[key]~=nil and type(value[key])~='boolean' then return false end
    end
    if value.success and value.reason~=nil or not value.success and not reasons[value.reason] then return false end
    if value.quality~=nil and not Definitions.qualityLabels[value.quality] then return false end
    if value.outputId~=nil and not Definitions.upgrades[value.outputId] then return false end
    if value.score~=nil and not P.integer(value.score,0,100) then return false end
    if value.action=='collect' and value.success then
        return value.changed==true and value.complete==true and value.quality~=nil and value.outputId~=nil and value.score~=nil
    end
    return true
end
function R.project(value)
    if type(value)~='table' or not actions[value.action] then return nil,'invalid_public_result' end
    local result={success=value.ok==true}
    for key in pairs(common) do if key~='success' then result[key]=value[key] end end
    for key in pairs(actions[value.action]) do result[key]=value[key] end
    if not R.valid(result) then return nil,'invalid_public_result' end
    return result
end
return R
