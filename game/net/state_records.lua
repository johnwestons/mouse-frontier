-- Flat, owned table records preserve sparse/numeric keys without evaluating
-- Lua or depending on the codec's contiguous-array inference. References are
-- forward-only, have one parent and cannot create cycles or shared ownership.
local Codec=require('game.net.codec')
local P=require('game.net.protocol')
local Records={MAX_NODES=12000,MAX_ENTRIES=50000,MAX_DEPTH=32,MAX_STRING=8192,MAX_KEY=128}
local restricted={network=true,credentialHash=true,token=true,checkpoints=true,receipts=true,
    sessionSerial=true,accessibility=true,musicVolume=true,sfxVolume=true,rainVolume=true,
    musicMuted=true,musicPaused=true}
local function scalar(value)
    local kind=type(value)
    return kind=='boolean' or (kind=='string' and #value<=Records.MAX_STRING)
        or (kind=='number' and value==value and value>-math.huge and value<math.huge and math.abs(value)<=1e12)
end
local function keyValid(key)
    return (type(key)=='string' and #key>0 and #key<=Records.MAX_KEY and not restricted[key])
        or P.integer(key,-2147483647,2147483647)
end
local function before(a,b)
    if type(a)~=type(b) then return type(a)=='number' end
    return a<b
end
local function dense(value,maximum)
    if type(value)~='table' then return nil end
    local count=0
    for index in pairs(value) do
        if not P.integer(index,1,maximum) then return nil end
        count=count+1
    end
    if count~=#value then return nil end
    for index=1,count do if value[index]==nil then return nil end end
    return count
end
Records.dense=dense
function Records.budget() return {nodes=0,entries=0} end
local function consume(budget,field,maximum,count)
    budget[field]=budget[field]+(count or 1)
    return budget[field]<=maximum
end
function Records.encode(value,budget)
    budget=budget or Records.budget()
    local nodes=Codec.array({}); local ancestors={}
    local function visit(source,depth)
        if type(source)~='table' or getmetatable(source)~=nil then return nil,'unsupported_state_table' end
        if depth>Records.MAX_DEPTH or ancestors[source] then return nil,'state_nesting' end
        if not consume(budget,'nodes',Records.MAX_NODES) then return nil,'state_node_limit' end
        local id=#nodes+1; local entries=Codec.array({}); nodes[id]=entries
        ancestors[source]=true
        local keys={}
        for key in pairs(source) do
            if not keyValid(key) then return nil,'invalid_state_key' end
            keys[#keys+1]=key
            if #keys>Records.MAX_ENTRIES then return nil,'state_entry_limit' end
        end
        table.sort(keys,before)
        for _,key in ipairs(keys) do
            if not consume(budget,'entries',Records.MAX_ENTRIES) then return nil,'state_entry_limit' end
            local item=source[key]; local entry={key=key}
            if type(item)=='table' then
                local reference,reason=visit(item,depth+1)
                if not reference then return nil,reason end
                entry.ref=reference
            elseif scalar(item) then entry.value=item
            else return nil,'invalid_state_value' end
            entries[#entries+1]=entry
        end
        ancestors[source]=nil; return id
    end
    local root,reason=visit(value,1)
    if not root then return nil,reason end
    return {nodes=nodes}
end
function Records.decode(record,budget)
    budget=budget or Records.budget()
    if not P.fields(record,{nodes=true}) then return nil,'invalid_state_record' end
    local count=dense(record.nodes,Records.MAX_NODES)
    if not count or count<1 or not consume(budget,'nodes',Records.MAX_NODES,count) then return nil,'state_node_limit' end
    local values,parents,depths={},{},{[1]=1}
    for index=1,count do values[index]={} end
    for index,entries in ipairs(record.nodes) do
        if index>1 and parents[index]~=1 then return nil,'unowned_state_node' end
        local size=dense(entries,Records.MAX_ENTRIES)
        if not size or not consume(budget,'entries',Records.MAX_ENTRIES,size) then return nil,'state_entry_limit' end
        local previous
        for _,entry in ipairs(entries) do
            if not P.fields(entry,{key=true,ref=true,value=true}) or not keyValid(entry.key)
                or (previous~=nil and not before(previous,entry.key)) then return nil,'invalid_state_entry' end
            previous=entry.key
            if entry.ref~=nil then
                if entry.value~=nil or not P.integer(entry.ref,index+1,count) or parents[entry.ref] then return nil,'invalid_state_reference' end
                local depth=depths[index]+1
                if depth>Records.MAX_DEPTH then return nil,'state_nesting' end
                parents[entry.ref]=1; depths[entry.ref]=depth
                values[index][entry.key]=values[entry.ref]
            elseif scalar(entry.value) then values[index][entry.key]=entry.value
            else return nil,'invalid_state_value' end
        end
    end
    return values[1]
end
return Records
