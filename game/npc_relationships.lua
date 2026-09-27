local Relationships={}

Relationships.version=1
Relationships.tiers={
    {name="New Face",minimum=0},
    {name="Familiar Face",minimum=3},
    {name="Friend",minimum=7},
    {name="Trusted Friend",minimum=14},
}

local function countKeys(values)
    local count=0
    for _ in pairs(values or {}) do count=count+1 end
    return count
end

local function globalStep(goodwill)
    goodwill=math.max(0,math.floor(tonumber(goodwill) or 0))
    if goodwill>=24 then return 3 end
    if goodwill>=12 then return 2 end
    if goodwill>=5 then return 1 end
    return 0
end

local function poolFingerprint(lines)
    local hash=7
    for index,line in ipairs(lines) do
        hash=(hash*31+index)%2147483647
        line=tostring(line)
        hash=(hash*31+#line)%2147483647
        for byte=1,#line do hash=(hash*31+line:byte(byte))%2147483647 end
        hash=(hash*31+1)%2147483647
    end
    return tostring(#lines)..":"..tostring(hash)
end

local function validOrder(order,count)
    if type(order)~="table" or #order~=count then return false end
    local seen={}
    for position=1,count do
        local value=order[position]
        if type(value)~="number" or value~=value or value<=-math.huge or value>=math.huge
            or value~=math.floor(value) or value<1 or value>count or seen[value] then return false end
        seen[value]=true
    end
    return true
end

local function validIndex(value,count)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
        and value==math.floor(value) and value>=1 and value<=count
end

local function randomInteger(rng,low,high)
    if low>=high then return low end
    local value=rng and rng(high-low+1) or love.math.random(high-low+1)
    return low+math.max(0,math.min(high-low,math.floor(value)-1))
end

local function shuffledOrder(count,rng)
    local order={}
    for index=1,count do order[index]=index end
    for index=count,2,-1 do
        local other=randomInteger(rng,1,index)
        order[index],order[other]=order[other],order[index]
    end
    return order
end

local function dialogueLine(record,lines,rng)
    local count=#lines
    if count==0 then return nil end
    local fingerprint=poolFingerprint(lines)
    local cursor=tonumber(record.dialogueCursor)
    local validCursor=cursor and cursor==cursor and cursor>-math.huge and cursor<math.huge
        and cursor==math.floor(cursor) and cursor>=1 and cursor<=count+1
    local samePool=record.dialoguePool==fingerprint
    local order=record.dialogueOrder
    if not samePool or not validOrder(order,count) or not validCursor then
        local previous=samePool and tonumber(record.dialogueLast) or nil
        order=shuffledOrder(count,rng)
        if count>1 and validIndex(previous,count)
            and order[1]==previous then
            local other=randomInteger(rng,2,count)
            order[1],order[other]=order[other],order[1]
        end
        record.dialoguePool=fingerprint
        record.dialogueOrder=order
        record.dialogueCursor=1
        cursor=1
    elseif cursor>count then
        order=shuffledOrder(count,rng)
        local previous=tonumber(record.dialogueLast)
        if count>1 and validIndex(previous,count)
            and order[1]==previous then
            local other=randomInteger(rng,2,count)
            order[1],order[other]=order[other],order[1]
        end
        record.dialogueOrder=order
        record.dialogueCursor=1
        cursor=1
    end
    local selected=order[cursor]
    record.dialogueCursor=cursor+1
    record.dialogueLast=selected
    return lines[selected]
end

function Relationships.ensureData(data)
    data.relationships=type(data.relationships)=="table" and data.relationships or {}
    return data.relationships
end

function Relationships.ensure(data,npc)
    local records=Relationships.ensureData(data)
    npc=type(npc)=="string" and npc or "unknown-traveler"
    local record=records[npc]
    if type(record)~="table" then
        record={version=Relationships.version,goodwillEarned=0,helpCount=0,gifts=0,uniqueGifts={},rides=0,talks=0,trades=0}
        records[npc]=record
    end
    record.version=Relationships.version
    record.goodwillEarned=math.max(0,math.floor(tonumber(record.goodwillEarned) or 0))
    record.helpCount=math.max(0,math.floor(tonumber(record.helpCount) or 0))
    record.gifts=math.max(0,math.floor(tonumber(record.gifts) or 0))
    record.uniqueGifts=type(record.uniqueGifts)=="table" and record.uniqueGifts or {}
    record.rides=math.max(0,math.floor(tonumber(record.rides) or 0))
    record.talks=math.max(0,math.floor(tonumber(record.talks) or 0))
    record.trades=math.max(0,math.floor(tonumber(record.trades) or 0))
    return record
end

function Relationships.status(data,npc)
    local record=Relationships.ensure(data,npc)
    local points=record.goodwillEarned*2+countKeys(record.uniqueGifts)*3+record.rides
    local tier,index=Relationships.tiers[1],1
    for candidate,profile in ipairs(Relationships.tiers) do
        if points>=profile.minimum then tier,index=profile,candidate end
    end
    return {name=tier.name,index=index,points=points,helpCount=record.helpCount,gifts=record.gifts,rides=record.rides,talks=record.talks}
end

function Relationships.recordHelp(data,npc,amount,kind,location)
    if type(npc)~="string" or npc=="" then return nil end
    local record=Relationships.ensure(data,npc)
    local gained=math.max(0,math.floor(tonumber(amount) or 0))
    record.goodwillEarned=record.goodwillEarned+gained
    if gained>0 then record.helpCount=record.helpCount+1 end
    record.lastHelp=kind or "help"; record.lastHelpStop=math.max(1,math.floor(tonumber(location) or 1))
    return Relationships.status(data,npc)
end

function Relationships.recordRide(data,npc)
    local record=Relationships.ensure(data,npc)
    record.rides=record.rides+1
    return Relationships.status(data,npc)
end

local giftLines={useful="Gift accepted."}

function Relationships.recordGift(data,npc,item,category)
    local record=Relationships.ensure(data,npc)
    record.gifts=record.gifts+1
    record.uniqueGifts[item or ("gift-"..record.gifts)]=true
    record.lastGift=item; record.lastGiftCategory=category or "useful"
    local status=Relationships.status(data,npc)
    return {accepted=true,line="Gift accepted: "..tostring(item or category or "item"):gsub("%-"," ")..".",status=status}
end

function Relationships.rejection(data,npc)
    local status=Relationships.status(data,npc)
    local line="Item cannot be used by this NPC."
    return {accepted=false,line=line,status=status}
end

function Relationships.merchantTerms(data,npc)
    local personal=Relationships.status(data,npc)
    local global=globalStep(data.goodwill)
    local personalStep=personal.index-1
    return {
        discount=math.min(.20,global*.04+personalStep*.02),
        saleBonus=math.min(.20,global*.03+personalStep*.02),
        budgetBonus=global*4+personalStep*3,
        tier=personal.name,
    }
end

function Relationships.buyPrice(data,npc,base)
    local terms=Relationships.merchantTerms(data,npc)
    return math.max(1,math.floor((tonumber(base) or 1)*(1-terms.discount)+.5)),terms
end

function Relationships.sellPrice(data,npc,base)
    local terms=Relationships.merchantTerms(data,npc)
    return math.max(1,math.floor((tonumber(base) or 1)*(1+terms.saleBonus)+.5)),terms
end

function Relationships.recordTrade(data,npc)
    local record=Relationships.ensure(data,npc); record.trades=record.trades+1
    return Relationships.status(data,npc)
end

function Relationships.npcDialogue(data,npc,fallbackLines,rng)
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    local lines=type(fallbackLines)=="table" and fallbackLines or {}
    local line=dialogueLine(record,lines,rng)
    return line,Relationships.status(data,npc)
end

function Relationships.passengerDialogue(data,passenger,fallbackLines,rng)
    local record=Relationships.ensure(data,passenger.npc); record.talks=record.talks+1
    passenger.relationshipTalks=math.max(0,math.floor(tonumber(passenger.relationshipTalks) or 0))+1
    local lines=type(fallbackLines)=="table" and fallbackLines or {}
    local line=dialogueLine(record,lines,rng)
    return line,Relationships.status(data,passenger.npc)
end

function Relationships.audit()
    local data={goodwill=12,relationships={}}
    local first=Relationships.ensure(data,"merchant.png")
    Relationships.recordHelp(data,"merchant.png",3,"aid",4)
    Relationships.recordGift(data,"merchant.png","water-bottle","water")
    Relationships.recordRide(data,"merchant.png")
    local status=Relationships.status(data,"merchant.png")
    local buy,terms=Relationships.buyPrice(data,"merchant.png",20)
    local sell=Relationships.sellPrice(data,"merchant.png",10)
    local line=Relationships.npcDialogue(data,"merchant.png",{"Hello."})
    local persistent=Relationships.ensure(data,"merchant.png")==first
    return {ready=persistent and status.index>=3 and buy<20 and sell>10 and terms.budgetBonus>0 and line=="Hello.",
        persistent=persistent,tier=status.name,points=status.points,buyPrice=buy,sellPrice=sell,budgetBonus=terms.budgetBonus,
        curve="npc-relationships-v1"}
end

return Relationships
