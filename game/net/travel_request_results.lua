-- Host-derived next-leg inspection; no event, dialogue, roll or future terrain.
local P=require('game.net.protocol')
local R={}
local fields={from=true,to=true,food=true,water=true,coal=true,available=true,missing=true,
    affordable=true,terrain=true,passengers=true,passengerLoad=true,maintenanceCoal=true,navigatorSaved=true,
    sourceRevision=true,serial=true,requested=true,already=true}
local resources={food=true,water=true,coal=true}
local terrains={plains=true,desert=true,mountains=true,ruins=true,forest=true}
local function number(n)return type(n)=='number' and n==n and n>=0 and n<=1000000000 end
function R.valid(v)
    if not P.fields(v,fields) or not P.integer(v.from,1,49) or v.to~=v.from+1
        or not terrains[v.terrain] or not P.integer(v.sourceRevision,1,2147483647)
        or not P.integer(v.serial,0,2147483647) or type(v.requested)~='boolean' or type(v.already)~='boolean'
        or v.requested~=(v.serial>0) or v.already and not v.requested
        or not P.fields(v.available,resources) or not P.fields(v.missing,resources)
        or type(v.affordable)~='boolean' or not P.integer(v.passengers,0,1000000)
        or not number(v.passengerLoad) or not number(v.maintenanceCoal) or not number(v.navigatorSaved) then return false end
    local affordable=true
    for name in pairs(resources)do
        if not number(v[name]) or not number(v.available[name]) or not number(v.missing[name])
            or v.missing[name]~=math.max(0,v[name]-v.available[name]) then return false end
        affordable=affordable and v.missing[name]==0
    end
    return affordable==v.affordable
end
function R.project(v)
    if not R.valid(v)then return nil,'invalid_public_result'end
    local copy={};for key in pairs(fields)do copy[key]=v[key]end
    for _,key in ipairs({'available','missing'})do
        copy[key]={};for name in pairs(resources)do copy[key][name]=v[key][name]end
    end
    return copy
end
return R
