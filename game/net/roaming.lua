-- Host-only enemy presentation. Campaign health/rewards remain reliable state.
local P=require('game.net.protocol')
local Wire={INTERVAL=1/12,STALE_SECONDS=.35,BATCH=2,MAX_MOBS=64}
local MAX=2147483647
Wire.states={'patrol','alert','chase','windup','recover','stagger'}
local codes={}; for code,state in ipairs(Wire.states) do codes[state]=code end
local fields={id=true,e=true,x=true,y=true,f=true,s=true,t=true,d=true,h=true,v=true,z=true,q=true,a=true}
function Wire.mob(value)
    return P.fields(value,fields) and P.text(value.id,64) and P.text(value.e,64)
        and P.integer(value.x,-100000000,100000000) and P.integer(value.y,-100000000,100000000)
        and (value.f==1 or value.f==-1) and P.integer(value.s,1,#Wire.states)
        and P.integer(value.t,0,3600000) and P.integer(value.d,0,9007199254740991)
        and P.integer(value.h,0,3600000) and P.integer(value.v,0,3600000) and P.integer(value.z,0,3600000)
        and P.integer(value.q,0,2) and type(value.a)=='boolean'
end
function Wire.snapshot(message)
    if not P.envelope(message,'roaming_motion') or not P.fields(message,{type=true,game=true,protocol=true,
        sessionId=true,sceneEpoch=true,sourceRevision=true,serial=true,areaId=true,paused=true,mobs=true})
        or not P.text(message.sessionId,64) or not P.text(message.areaId,64)
        or not P.integer(message.sceneEpoch,0,MAX) or not P.integer(message.sourceRevision,0,MAX)
        or not P.integer(message.serial,1,MAX) or type(message.paused)~='boolean' or type(message.mobs)~='table'
        or #message.mobs<1 or #message.mobs>Wire.BATCH then return false end
    local count,seen=0,{}
    for key,mob in pairs(message.mobs) do
        if not P.integer(key,1,#message.mobs) or not Wire.mob(mob) or seen[mob.id] then return false end
        seen[mob.id]=true; count=count+1
    end
    return count==#message.mobs
end
local function quantize(value) return math.floor((value or 0)*1000+.5) end
local function timer(value) return quantize(math.max(0,math.min(3600,value or 0))) end
function Wire.pack(definition,saved,transient,active)
    transient=transient or {}
    return {id=definition.id,e=saved.entityId,x=quantize(saved.x),y=quantize(saved.y),
        f=transient.facing==-1 and -1 or 1,s=codes[transient.state or 'patrol'],t=timer(transient.timer),
        d=quantize(transient.animationDistance),h=timer(transient.hitTimer),v=timer(transient.healthTimer),
        z=timer(transient.deathTimer),q=transient.targetId=='host' and 1 or transient.targetId=='companion' and 2 or 0,a=active==true}
end
function Wire.unpack(value)
    assert(Wire.mob(value),'invalid enemy presentation')
    return {x=value.x/1000,y=value.y/1000,facing=value.f,state=Wire.states[value.s],timer=value.t/1000,
        animationDistance=value.d/1000,hitTimer=value.h/1000,healthTimer=value.v/1000,deathTimer=value.z/1000,
        targetId=value.q==1 and 'host' or value.q==2 and 'companion' or nil,active=value.a}
end
return Wire
