-- Disposable host-authored shot visuals. No saved state or guest inputs.
local P=require('game.net.protocol')
local Wire={INTERVAL=1/20,STALE_SECONDS=.35,BATCH=2,MAX_EVENTS=8}
local MAX=2147483647
local fields={n=true,a=true,w=true,s=true,p=true,e=true,h=true,z=true,i=true,c=true}
function Wire.event(value)
    return P.fields(value,fields) and P.integer(value.n,1,1000000000)
        and (value.a==1 or value.a==2) and (value.w==1 or value.w==2)
        and P.integer(value.s,1,8) and P.integer(value.p,1,value.w==1 and 5 or 4)
        and P.integer(value.e,0,3000) and type(value.h)=='boolean' and type(value.z)=='boolean'
        and (value.i==4 or value.i==5) and (value.c==0 or value.c==2)
end
function Wire.snapshot(message)
    if not P.envelope(message,'last_stand_effects') or not P.fields(message,{type=true,game=true,protocol=true,
        sessionId=true,sceneEpoch=true,domain=true,encounterId=true,phaseRevision=true,serial=true,
        clock=true,paused=true,events=true}) or not P.text(message.sessionId,64) or not P.text(message.domain,64)
        or not P.text(message.encounterId,64) or not P.integer(message.sceneEpoch,0,MAX)
        or not P.integer(message.phaseRevision,1,1000000000) or not P.integer(message.serial,1,MAX)
        or not P.integer(message.clock,0,1000000000000) or type(message.paused)~='boolean'
        or type(message.events)~='table' or #message.events>Wire.BATCH then return false end
    local count,seen=0,{}
    for key,event in pairs(message.events) do
        if not P.integer(key,1,#message.events) or not Wire.event(event) or seen[event.n] then return false end
        count=count+1; seen[event.n]=true
    end
    return count==#message.events
end
function Wire.pack(event)
    return {n=event.serial,a=event.actorId=='host' and 1 or event.actorId=='companion' and 2 or 0,
        w=event.windowId=='wide' and 1 or event.windowId=='tall' and 2 or 0,s=event.slot,p=event.point,
        e=math.floor((event.elapsed or 0)*1000+.5),h=event.hit==true,z=event.decal==true,
        i=event.impactFrame,c=event.decalFrame}
end
function Wire.unpack(value)
    assert(Wire.event(value),'invalid Last Stand effect')
    return {serial=value.n,actorId=value.a==1 and 'host' or 'companion',windowId=value.w==1 and 'wide' or 'tall',
        slot=value.s,point=value.p,elapsed=value.e/1000,hit=value.h,decal=value.z,
        impactFrame=value.i,decalFrame=value.c}
end
return Wire
