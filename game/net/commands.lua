-- Bounded command envelopes and outcome metadata. Campaign data continues on
-- the state channel; arbitrary domain return tables never enter control packets.
local P=require('game.net.protocol')
local Results=require('game.net.item_results')
local Wire={}
local MAX=2147483647
local function envelope(m,kind,fields)
    local allowed={type=true,game=true,protocol=true,sessionId=true}
    for _,key in ipairs(fields) do allowed[key]=true end
    return P.envelope(m,kind) and P.fields(m,allowed) and P.text(m.sessionId,64)
end
function Wire.request(m)
    if not envelope(m,'command',{'requestId','sceneEpoch','command','args','expected'})
        or not P.integer(m.requestId,1,MAX) or not P.integer(m.sceneEpoch,1,MAX)
        or not P.text(m.command,64) or type(m.args)~='table' or type(m.expected)~='table' then return false end
    local count=0
    for scope,revision in pairs(m.expected) do
        count=count+1
        if count>12 or not P.text(scope,80) or not P.integer(revision,0,MAX) then return false end
    end
    return P.encode(m,P.CONTROL)~=nil
end
function Wire.unpack(m)
    return {sessionId=m.sessionId,requestId=m.requestId,sceneEpoch=m.sceneEpoch,
        command=m.command,args=m.args,expected=m.expected}
end
function Wire.ready(m)
    return envelope(m,'commands_ready',{'nextRequestId'}) and P.integer(m.nextRequestId,1,MAX)
end
function Wire.result(m)
    return envelope(m,'command_result',{'requestId','ok','reason','durable','savePending','revision','command','details'})
        and P.integer(m.requestId,1,MAX) and type(m.ok)=='boolean' and type(m.durable)=='boolean'
        and type(m.savePending)=='boolean' and (m.reason==nil or P.text(m.reason,64))
        and (m.revision==nil or P.integer(m.revision,1,MAX))
        and (not m.ok or m.revision~=nil) and (m.ok or m.reason~=nil)
        and (not m.durable or m.ok and not m.savePending)
        and (m.command==nil or P.text(m.command,64))
        and (m.details==nil or m.ok and Results.valid(m.command,m.details))
        and (not m.ok or not Results.supports(m.command) or m.details~=nil)
end
function Wire.outcome(sessionId,requestId,reply,command)
    if type(reply)~='table' then return nil end
    local reason=reply.reason
    if reply.ok~=true and not P.text(reason,64) then reason='command_rejected' end
    local details,errorMessage
    if reply.ok then details,errorMessage=Results.project(command,reply.result) end
    if errorMessage then return nil,errorMessage end
    local m=P.message('command_result',{sessionId=sessionId,requestId=requestId,ok=reply.ok==true,command=command,details=details,
        reason=reason,durable=reply.durable==true,savePending=reply.savePending==true,revision=reply.revision})
    if not Wire.result(m) or not P.encode(m,P.CONTROL) then return nil end
    return m
end
return Wire
