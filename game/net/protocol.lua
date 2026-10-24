local Codec=require('game.net.codec')
local P={GAME='mouse-frontier',VERSION=33,CONTROL=0,REALTIME=1,STATE=2,
    PACKET_BYTES=1200,CHUNK_BYTES=16384,PART_BYTES=7168,BASELINE_BYTES=8*1024*1024,
    MAX_PARTS=1200,TRANSFER_SECONDS=30,HELLO_SECONDS=8,APPROVAL_SECONDS=60}
local limits={maxBytes=P.PACKET_BYTES,maxDepth=8,maxEntries=80,maxStringBytes=256}
function P.fields(value,allowed)
    if type(value)~='table' then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
function P.integer(value,minimum,maximum)
    return type(value)=='number' and value==math.floor(value) and value>=minimum and value<=maximum
end
function P.clock(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end
function P.text(value,maximum)
    return type(value)=='string' and #value>0 and #value<=maximum and not value:find('[%z\1-\31\127]')
end
function P.encode(message,channel)
    if channel~=P.CONTROL and channel~=P.REALTIME and channel~=P.STATE then return nil,'invalid_channel' end
    if channel==P.STATE then
        return Codec.encode(message,{maxBytes=P.CHUNK_BYTES,maxDepth=4,maxEntries=16,maxStringBytes=P.PART_BYTES*2})
    end
    return Codec.encode(message,limits)
end
function P.decode(payload,channel)
    if channel~=P.CONTROL and channel~=P.REALTIME and channel~=P.STATE then return nil,'invalid_channel' end
    if type(payload)~='string' then return nil,'invalid_packet' end
    if channel==P.STATE then
        return Codec.decode(payload,{maxBytes=P.CHUNK_BYTES,maxDepth=4,maxEntries=16,maxStringBytes=P.PART_BYTES*2})
    end
    return Codec.decode(payload,limits)
end
function P.envelope(message,kind)
    return type(message)=='table' and message.type==kind and message.game==P.GAME and message.protocol==P.VERSION
end
function P.message(kind,values)
    local message={type=kind,game=P.GAME,protocol=P.VERSION}
    for key,value in pairs(values or {}) do message[key]=value end
    return message
end
return P
