-- Checked action facts only. Target geometry and saved sessions use the state channel.
local P=require('game.net.protocol')
local Catalog=require('game.catalog')
local Manifest=require('game.first_person_weapon_manifest')
local R={}
local commands={['range.acquire']=true,['range.configure']=true,['range.fire']=true,
    ['range.reload']=true,['range.ammo']=true,['range.release']=true}
local common={actorId=true,spotId=true,roundRevision=true,phase=true,weaponId=true,weapon=true,
    loaded=true,rounds=true,fireMode=true}
local complete={completed=true,score=true,accuracy=true,rank=true,gained=true,rewardTier=true,
    earnedRewardTier=true,highScore=true,newBest=true}
local actions={start=true,setup=true,change=true,weapon=true,mode=true,complete=true,pause=true}
local ranks={SHARPSHOOTER=true,MARKSMOUSE=true,['TRAIL HAND']=true,BEGINNER=true}
local function reference(v,prefix) return P.text(v,32) and v:match('^'..prefix..'[1-9]%d*$')~=nil end
local function number(v,low,high) return type(v)=='number' and v==v and v>=low and v<=high end
local function allowed(name,value)
    local fields={}; for k in pairs(common) do fields[k]=true end
    if name=='range.acquire' then fields.leaseId=true; fields.expiresIn=true; fields.paused=true
    elseif name=='range.release' then fields.leaseId=true; fields.released=true
    elseif name=='range.fire' then fields.fired=true; fields.hit=true
    elseif name=='range.reload' then fields.reloading=true
    elseif name=='range.ammo' then fields.ammoType=true; fields.purchasedRounds=true; fields.cost=true
    elseif name=='range.configure' then
        fields.action=true
        if value.action=='pause' then fields.paused=true end
        if value.action=='complete' then for k in pairs(complete) do fields[k]=true end end
    end
    return fields
end
function R.supports(name) return commands[name]==true end
function R.valid(name,value)
    if not R.supports(name) or type(value)~='table' or not P.fields(value,allowed(name,value)) then return false end
    local spec=Catalog.weaponCombat[value.weapon]
    if value.actorId~='host' and value.actorId~='companion' or not reference(value.spotId,'e')
        or not P.integer(value.roundRevision,1,1e9) or not reference(value.weaponId,'i')
        or not spec or spec.kind~='ranged' or not P.integer(value.loaded,0,spec.capacity or 1)
        or not Manifest.fireModeValid(value.weapon,value.fireMode) and value.fireMode~='single'
        or value.phase~='lobby' and value.phase~='play' and value.phase~='results'
        or spec.ammo and not P.integer(value.rounds,0,1e9)
        or not spec.ammo and value.rounds~=nil then return false end
    if name=='range.acquire' then return reference(value.leaseId,'l') and value.expiresIn==30 and type(value.paused)=='boolean' end
    if name=='range.release' then return reference(value.leaseId,'l') and value.released==true end
    if name=='range.fire' then return value.phase=='play' and value.fired==true and type(value.hit)=='boolean' end
    if name=='range.reload' then return type(value.reloading)=='boolean' end
    if name=='range.ammo' then return value.ammoType==spec.ammo and P.integer(value.purchasedRounds,1,100)
        and P.integer(value.cost,1,100) end
    if not actions[value.action] then return false end
    if value.action=='pause' then return type(value.paused)=='boolean' end
    if value.action~='complete' then return true end
    return value.phase=='results' and value.completed==true and number(value.score,0,1e9)
        and number(value.accuracy,0,7) and ranks[value.rank]==true and P.integer(value.gained,0,3)
        and P.integer(value.rewardTier,0,3) and P.integer(value.earnedRewardTier,0,3)
        and value.gained<=value.rewardTier and value.earnedRewardTier<=value.rewardTier
        and number(value.highScore,value.score,1e9) and type(value.newBest)=='boolean'
end
function R.project(name,value)
    if not R.supports(name) or type(value)~='table' then return nil,'invalid_public_result' end
    local result={}; for key in pairs(allowed(name,value)) do result[key]=value[key] end
    if not R.valid(name,result) then return nil,'invalid_public_result' end
    return result
end
return R
