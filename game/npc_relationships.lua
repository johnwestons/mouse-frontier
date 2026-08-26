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

local giftLines={
    weapon="I'll keep this close if trouble finds us. Thank you.",
    medical="This could save somebody's life. I won't waste it.",
    food="A shared meal means more out here than you might think.",
    water="Clean water is a precious gift. Thank you, friend.",
    gear="This will make the road a little kinder. Thank you.",
    fuel="You just helped keep a cold night away.",
    useful="I can put this to good use. I'll remember your kindness.",
}

function Relationships.recordGift(data,npc,item,category)
    local record=Relationships.ensure(data,npc)
    record.gifts=record.gifts+1
    record.uniqueGifts[item or ("gift-"..record.gifts)]=true
    record.lastGift=item; record.lastGiftCategory=category or "useful"
    local status=Relationships.status(data,npc)
    return {accepted=true,line=giftLines[category] or giftLines.useful,status=status}
end

function Relationships.rejection(data,npc)
    local status=Relationships.status(data,npc)
    local line=status.index>=3 and "You're kind to offer, but someone else will need that more than I do."
        or "I appreciate the thought, but I can't make use of that right now."
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

function Relationships.npcDialogue(data,npc,fallbackLines)
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    local status=Relationships.status(data,npc); local lines
    if record.goodwillEarned>=5 then
        lines={"I know that when you say you'll help, you mean it.","Folks here still talk about everything you've done for us.","You're family along this stretch of track now."}
    elseif record.helpCount>0 then
        lines={"I remember the help you gave us. It mattered.","Good to see you again, friend.","You left this place better than you found it."}
    elseif record.gifts>0 then
        lines={"I still remember your gift. That was mighty thoughtful.","You didn't have to share what you had, but you did.","It's good to see a generous face again."}
    elseif globalStep(data.goodwill)>=2 then
        lines={"Word about your good deeds reached us before your train did.","People down the line say you're someone we can trust.","Your train has become a welcome sight around here."}
    else lines=fallbackLines end
    lines=type(lines)=="table" and #lines>0 and lines or {"Safe travels, friend."}
    return lines[((record.talks-1)%#lines)+1],status
end

function Relationships.passengerDialogue(data,passenger,fallbackLines)
    local npc=passenger and passenger.npc
    local record=Relationships.ensure(data,npc); record.talks=record.talks+1
    passenger.relationshipTalks=math.max(0,math.floor(tonumber(passenger.relationshipTalks) or 0))+1
    local status=Relationships.status(data,npc); local job=passenger.job or "scavenger"
    local lines={
        greenhouse="The greenhouse car makes me think we can grow something lasting.",
        fireman="I'll keep listening to the engine. She tells you what she needs.",
        medic="If anyone gets hurt, bring them to me before the wound worsens.",
        scavenger="I'll keep an eye out for useful salvage along the rails.",
    }
    local line
    if record.gifts>0 and passenger.relationshipTalks%3==0 then line="I haven't forgotten the gift you shared with me."
    elseif status.index>=3 then line="Whatever waits at my stop, I'm glad I'm traveling with a trusted friend."
    elseif passenger.destination then line=(lines[job] or lines.scavenger).." We're headed together to stop "..passenger.destination.."."
    else
        local fallback=type(fallbackLines)=="table" and fallbackLines or {}
        line=fallback[((passenger.relationshipTalks-1)%math.max(1,#fallback))+1] or lines[job] or lines.scavenger
    end
    return line,status
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
    return {ready=persistent and status.index>=3 and buy<20 and sell>10 and terms.budgetBonus>0 and line~="Hello.",
        persistent=persistent,tier=status.name,points=status.points,buyPrice=buy,sellPrice=sell,budgetBonus=terms.budgetBonus,
        curve="npc-relationships-v1"}
end

return Relationships
