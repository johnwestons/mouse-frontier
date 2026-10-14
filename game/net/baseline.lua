local Codec=require('game.net.codec')
local P=require('game.net.protocol')
local Crypto=require('game.net.crypto')
local Baseline={}
local LIMITS={maxBytes=P.BASELINE_BYTES,maxDepth=32,maxEntries=200000,maxStringBytes=262144}
local function hex(text) return (text:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function unhex(text)
    if type(text)~='string' or #text%2~=0 or text:find('[^0-9a-f]') then return nil end
    return (text:gsub('..',function(value) return string.char(tonumber(value,16)) end))
end
function Baseline.pack(snapshot,id,hash)
    hash=hash or Crypto.hash
    if not P.integer(id,1,2147483647) then return nil,'invalid_snapshot_id' end
    if type(snapshot)~='table' or not P.integer(snapshot.revision,0,2147483647)
        or not P.integer(snapshot.sceneEpoch,1,2147483647) then return nil,'invalid_snapshot' end
    local bytes,reason=Codec.encode(snapshot,LIMITS)
    if not bytes then return nil,reason end
    local ok,digest=pcall(hash,bytes); if not ok or not Crypto.isHex(digest,64) then return nil,'hash_unavailable' end
    local count=math.ceil(#bytes/P.PART_BYTES)
    if count>P.MAX_PARTS then return nil,'baseline_too_large' end
    local header=P.message('baseline',{id=id,bytes=#bytes,parts=count,hash=digest,
        revision=snapshot.revision,sceneEpoch=snapshot.sceneEpoch})
    local transfer={header=header,bytes=bytes,index=1}
    function transfer:next()
        if self.index>self.header.parts then return nil end
        local index=self.index; self.index=index+1
        return P.message('part',{id=self.header.id,index=index,
            data=hex(self.bytes:sub((index-1)*P.PART_BYTES+1,index*P.PART_BYTES))})
    end
    return transfer
end
function Baseline.receiver(header,now,validate,hash)
    if not P.clock(now) or type(validate)~='function' then return nil,'invalid_receiver' end
    if not P.envelope(header,'baseline') or not P.fields(header,{type=true,game=true,protocol=true,id=true,bytes=true,parts=true,hash=true,revision=true,sceneEpoch=true})
        or not P.integer(header.id,1,2147483647) or not P.integer(header.bytes,1,P.BASELINE_BYTES)
        or not P.integer(header.parts,1,P.MAX_PARTS) or header.parts~=math.ceil(header.bytes/P.PART_BYTES)
        or not P.integer(header.revision,0,2147483647) or not P.integer(header.sceneEpoch,1,2147483647)
        or not Crypto.isHex(header.hash,64) then return nil,'invalid_baseline' end
    local frozen={}; for key,value in pairs(header) do frozen[key]=value end
    local receiver={header=frozen,started=now,lastNow=now,parts={},count=0,received=0,closed=false}
    function receiver:abort(reason) self.closed=true; self.parts={}; return nil,reason end
    function receiver:expired(clock)
        if not P.clock(clock) then return true end
        self.lastNow=math.max(clock,self.lastNow)
        return self.lastNow-self.started>=P.TRANSFER_SECONDS
    end
    function receiver:push(message,clock)
        if self.closed then return nil,'transfer_closed' end
        if self:expired(clock) then return self:abort('baseline_timeout') end
        if not P.envelope(message,'part') or not P.fields(message,{type=true,game=true,protocol=true,id=true,index=true,data=true})
            or message.id~=self.header.id or not P.integer(message.index,1,self.header.parts)
            or type(message.data)~='string' or #message.data>P.PART_BYTES*2 then return self:abort('invalid_part') end
        local bytes=unhex(message.data)
        local expected=message.index==self.header.parts and self.header.bytes-(message.index-1)*P.PART_BYTES or P.PART_BYTES
        if not bytes or #bytes~=expected then return self:abort('invalid_part_length') end
        local old=self.parts[message.index]
        if old then if old~=bytes then return self:abort('conflicting_part') end; return false end
        self.parts[message.index]=bytes; self.count=self.count+1; self.received=self.received+#bytes
        if self.count<self.header.parts then return false end
        self.closed=true
        local body=table.concat(self.parts); self.parts={}
        local hashOk,digest=pcall(hash or Crypto.hash,body)
        if #body~=self.header.bytes or not hashOk or digest~=self.header.hash then return nil,'baseline_checksum' end
        local snapshot,reason=Codec.decode(body,LIMITS)
        if type(snapshot)~='table' then return nil,reason or 'invalid_snapshot' end
        if snapshot.revision~=self.header.revision or snapshot.sceneEpoch~=self.header.sceneEpoch then return nil,'baseline_revision' end
        local validateOk,valid,errorMessage=pcall(validate,snapshot)
        if not validateOk or valid~=true then return nil,type(errorMessage)=='string' and errorMessage or 'invalid_snapshot' end
        return snapshot
    end
    return receiver
end
return Baseline
