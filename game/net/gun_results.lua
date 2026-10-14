-- Bounded post-action gun facts. No private aim, target claims or save tables.
local P=require('game.net.protocol')
local Catalog=require('game.catalog')
local Manifest=require('game.first_person_weapon_manifest')
local R={}
local commands={['gun.fire']=true,['gun.reload']=true,['gun.cover']=true,['gun.mode']=true,['gun.select']=true,['lastStand.supply']=true}
local base={actorId=true,mode=true,encounterId=true,phaseRevision=true}
local gun={weaponId=true,weapon=true,magazine=true,rounds=true,fireMode=true}
local provider={actorId=true,mode=true,questId=true,revision=true,loanActive=true,loanAmmo=true,suppliedRounds=true}
function R.supports(name) return commands[name]==true end
function R.valid(name,value)
    if not R.supports(name) then return false end
    if name=='lastStand.supply' and value.mode=='farmhouse' then
        return P.fields(value,provider) and (value.actorId=='host' or value.actorId=='companion')
            and P.text(value.questId,32) and value.questId:match('^e[1-9]%d*$')~=nil
            and P.integer(value.revision,1,1e9) and value.loanActive==true
            and (value.loanAmmo==12 or value.loanAmmo==48) and P.integer(value.suppliedRounds,0,value.loanAmmo)
    end
    local fields={}; for key in pairs(base) do fields[key]=true end
    if name=='gun.cover' then fields.cover=true else
        for key in pairs(gun) do fields[key]=true end
        if name=='gun.fire' then fields.fired=true; fields.hit=true else fields.reloading=true end
        if name=='lastStand.supply' then fields.suppliedRounds=true end
    end
    if not P.fields(value,fields) or value.actorId~='host' and value.actorId~='companion'
        or value.mode~='ambush' and value.mode~='lastStand'
        or value.mode=='ambush' and value.phaseRevision~=nil
        or value.mode=='lastStand' and not P.integer(value.phaseRevision,1,1e9)
        or not P.text(value.encounterId,32) or not value.encounterId:match('^e[1-9]%d*$') then return false end
    if name=='gun.cover' then return type(value.cover)=='boolean' end
    local spec=Catalog.weaponCombat[value.weapon]
    local loan=value.mode=='lastStand' and value.weaponId=='loan:'..value.actorId and value.weapon=='frontier-22-lever-rifle'
    if not spec or spec.kind~='ranged' or not spec.ammo or spec.ammo=='arrows' or spec.ammo=='rocks' or spec.ammo=='ball-bearings'
        or not P.text(value.weaponId,32) or not loan and not value.weaponId:match('^i[1-9]%d*$')
        or not P.integer(value.magazine,0,spec.capacity or 1) or not P.integer(value.rounds,0,1e9)
        or not Manifest.fireModeValid(value.weapon,value.fireMode) then return false end
    if name=='gun.fire' then return value.fired==true and type(value.hit)=='boolean' end
    if name=='lastStand.supply' then
        return loan and value.reloading==false and (value.suppliedRounds==0 or value.suppliedRounds==12 or value.suppliedRounds==48)
    end
    return type(value.reloading)=='boolean'
end
function R.project(name,value)
    if not R.supports(name) or type(value)~='table' then return nil,'invalid_public_result' end
    if name=='lastStand.supply' and value.mode=='farmhouse' then
        local result={}; for key in pairs(provider) do result[key]=value[key] end
        if not R.valid(name,result) then return nil,'invalid_public_result' end
        return result
    end
    local result={}; for key in pairs(base) do result[key]=value[key] end
    if name=='gun.cover' then result.cover=value.cover else
        for key in pairs(gun) do result[key]=value[key] end
        if name=='gun.fire' then result.fired=value.fired; result.hit=value.hit else result.reloading=value.reloading end
        if name=='lastStand.supply' then result.suppliedRounds=value.suppliedRounds end
    end
    if not R.valid(name,result) then return nil,'invalid_public_result' end
    return result
end
return R
