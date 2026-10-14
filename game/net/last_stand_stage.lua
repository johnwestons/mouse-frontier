-- Host-authored passive presentation. No speech, decisions or save data.
local P=require('game.net.protocol')
local Wire={INTERVAL=1/20,STALE_SECONDS=.35}
local modes={offer=true,escort=true,aftermath=true,returning=true}
local function scout(value)
    return P.fields(value,{x=true,y=true,walkDistance=true,arrival=true})
        and P.integer(value.x,-100000000,100000000) and P.integer(value.y,-100000000,100000000)
        and P.integer(value.walkDistance,0,1000000000000) and P.integer(value.arrival,0,3600000)
end
local function pose(value)
    return P.fields(value,{x=true,y=true,facing=true}) and P.integer(value.x,0,960000)
        and P.integer(value.y,0,720000) and (value.facing==1 or value.facing==-1)
end
function Wire.snapshot(message)
    return P.envelope(message,'last_stand_stage') and P.fields(message,{type=true,game=true,protocol=true,
        sessionId=true,sceneEpoch=true,questId=true,lifeRevision=true,mode=true,serial=true,clock=true,paused=true,
        offerPage=true,scout=true,hostPose=true}) and P.text(message.sessionId,64) and P.text(message.questId,32)
        and P.integer(message.sceneEpoch,0,2147483647) and P.integer(message.lifeRevision,1,1000000000)
        and modes[message.mode]==true and P.integer(message.serial,1,2147483647)
        and P.integer(message.clock,0,1000000000000) and type(message.paused)=='boolean'
        and (message.offerPage==nil or message.mode=='offer' and P.integer(message.offerPage,1,16))
        and (message.scout==nil or scout(message.scout)) and (message.hostPose==nil or pose(message.hostPose))
end
local function quantize(value) return math.floor((value or 0)*1000+.5) end
function Wire.pack(source)
    local result={questId=source.questId,lifeRevision=source.lifeRevision,mode=source.mode,
        clock=quantize(source.clock),paused=source.paused==true,offerPage=source.offerPage}
    if source.scout then local s=source.scout; result.scout={x=quantize(s.x),y=quantize(s.y),
        walkDistance=quantize(s.walkDistance),arrival=quantize(s.arrival)} end
    if source.hostPose then local p=source.hostPose; result.hostPose={x=quantize(p.x),y=quantize(p.y),facing=p.facing} end
    return result
end
function Wire.unpack(frame)
    assert(Wire.snapshot(frame),'invalid Last Stand stage')
    local result={mode=frame.mode,clock=frame.clock/1000,paused=frame.paused,offerPage=frame.offerPage}
    if frame.scout then local s=frame.scout; result.scout={x=s.x/1000,y=s.y/1000,walkDistance=s.walkDistance/1000,arrival=s.arrival/1000} end
    if frame.hostPose then local p=frame.hostPose; result.hostPose={x=p.x/1000,y=p.y/1000,facing=p.facing} end
    return result
end
return Wire
