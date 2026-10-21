-- Small realtime DTOs. Positions/durations are host outputs, never guest input.
-- Integer millipixels keep codec payloads bounded and preserve gait phase.
local P=require('game.net.protocol')
local Wire={STEP=1/30,INPUT_INTERVAL=1/20,SNAPSHOT_INTERVAL=1/12,STALE_SECONDS=.35,MAX_CATCHUP=4}
local MAX=2147483647
local function envelope(message,kind,fields)
    local allowed={type=true,game=true,protocol=true,sessionId=true,sceneEpoch=true,motionId=true}
    for _,field in ipairs(fields) do allowed[field]=true end
    return P.envelope(message,kind) and P.fields(message,allowed) and P.text(message.sessionId,64)
        and P.integer(message.sceneEpoch,0,MAX) and P.integer(message.motionId,1,MAX)
end
function Wire.input(message)
    return envelope(message,'movement',{'sequence','x','y','sprint'})
        and P.integer(message.sequence,1,MAX) and P.integer(message.x,-1000,1000)
        and P.integer(message.y,-1000,1000) and type(message.sprint)=='boolean'
end
function Wire.ready(message) return envelope(message,'scene_ready',{}) end
local actorFields={x=true,y=true,vx=true,vy=true,f=true,ix=true,iy=true,d=true,p=true,idle=true,car=true,moving=true,mode=true,
    stance=true,poseSerial=true,useRemainingMs=true,sceneRevision=true}
function Wire.actor(actor)
    if not P.fields(actor,actorFields) then return false end
    for _,key in ipairs({'x','y'}) do if not P.integer(actor[key],-100000000,100000000) then return false end end
    for _,key in ipairs({'vx','vy'}) do if not P.integer(actor[key],-1000000,1000000) then return false end end
    for _,key in ipairs({'ix','iy'}) do if not P.integer(actor[key],-1000,1000) then return false end end
    for _,key in ipairs({'d','p'}) do if not P.integer(actor[key],0,9007199254740991) then return false end end
    return (actor.f==1 or actor.f==-1) and P.integer(actor.idle,0,3600000) and P.integer(actor.car,1,32)
        and (actor.sceneRevision==nil or P.integer(actor.sceneRevision,0,MAX))
        and type(actor.moving)=='boolean' and (actor.mode=='walk' or actor.mode=='run')
        and ({idle=true,sit=true,lay=true})[actor.stance]==true and P.integer(actor.poseSerial,0,MAX)
        and P.integer(actor.useRemainingMs,0,450)
        and (actor.poseSerial>0 or actor.stance=='idle' and actor.useRemainingMs==0)
end
function Wire.snapshot(message)
    return envelope(message,'motion',{'serial','tick','ack','ackAge','inputActive','host','companion','paused','ready','domain'})
        and (message.domain==nil or P.text(message.domain,64))
        and P.integer(message.serial,1,MAX) and P.integer(message.tick,0,MAX) and P.integer(message.ack,0,MAX)
        and type(message.paused)=='boolean' and type(message.ready)=='boolean'
        and type(message.inputActive)=='boolean' and P.integer(message.ackAge,0,350)
        and (not message.inputActive or message.ack>0) and (message.inputActive or message.ackAge==0)
        and Wire.actor(message.host) and Wire.actor(message.companion)
end
local function quantize(value) return math.floor((value or 0)*1000+.5) end
function Wire.packActor(actor,record,pose)
    return {x=quantize(actor.x),y=quantize(actor.y),vx=quantize(actor.velocityX),vy=quantize(actor.velocityY),
        f=actor.facing==-1 and -1 or 1,ix=quantize(actor.intentX),iy=quantize(actor.intentY),
        d=quantize(actor.animationDistance),p=quantize(actor.posePhase),idle=quantize(math.min(3600,actor.idleClock or 0)),
        car=record.activeCar,sceneRevision=record.presence and record.presence.revision or 0,
        moving=actor.moving==true,mode=actor.locomotionMode=='run' and 'run' or 'walk',
        stance=pose and pose.pose or 'idle',poseSerial=pose and pose.serial or 0,useRemainingMs=pose and pose.useMs or 0}
end
function Wire.unpackActor(actor)
    assert(Wire.actor(actor),'invalid motion actor')
    return {x=actor.x/1000,y=actor.y/1000,velocityX=actor.vx/1000,velocityY=actor.vy/1000,facing=actor.f,
        intentX=actor.ix/1000,intentY=actor.iy/1000,animationDistance=actor.d/1000,posePhase=actor.p/1000,
        idleClock=actor.idle/1000,activeCar=actor.car,moving=actor.moving,locomotionMode=actor.mode,
        stance=actor.stance,poseSerial=actor.poseSerial,useRemainingMs=actor.useRemainingMs}
end
return Wire
