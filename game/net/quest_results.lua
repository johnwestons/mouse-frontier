-- Actual post-hand-in facts; no random seeds, raw quests or spoken text.
local P=require('game.net.protocol')
local R={}
local function amount(n) return P.integer(n,0,1000000000) end
local destinations={backpack=true,mailbox=true,ammunition=true,['house storage']=true}
function R.valid(command,v)
    if command~='quest.help' and command~='quest.deliver' then return false end
    if command=='quest.help' then
        if not P.fields(v,{completed=true,item=true,gained=true,total=true,missing=true,label=true}) or type(v.completed)~='boolean' then return false end
        if v.completed then return P.text(v.item,128) and amount(v.gained) and amount(v.total) and v.missing==nil and v.label==nil end
        return P.text(v.missing,128) and (v.label==nil or P.text(v.label,128)) and v.item==nil and v.gained==nil and v.total==nil
    end
    if not P.fields(v,{completed=true,item=true,delivery=true,coal=true,scrap=true,xp=true,levels=true,gained=true,total=true,recipients=true,amount=true})
        or v.completed~=true or not P.text(v.item,128) or not destinations[v.delivery]
        or not amount(v.coal) or not amount(v.scrap) or not amount(v.xp) or not amount(v.levels) or not amount(v.gained) or not amount(v.total)
        or not P.fields(v.recipients,{host=true,companion=true}) or not next(v.recipients) then return false end
    for _,xp in pairs(v.recipients) do if not amount(xp) or xp~=v.xp then return false end end
    return v.delivery=='ammunition' and P.integer(v.amount,1,1000000000) or v.delivery~='ammunition' and v.amount==nil
end
function R.project(command,v)
    if type(v)~='table' then return nil,'invalid_public_result' end
    local d
    if command=='quest.help' then
        d=v.completed and {completed=true,item=v.item,gained=v.gained,total=v.total}
            or {completed=false,missing=v.missing,label=v.label}
    elseif type(v.reward)=='table' then
        local r=v.reward; local recipients={}
        for _,id in ipairs({'host','companion'}) do recipients[id]=(v.recipients or {})[id] end
        d={completed=true,item=r.item,delivery=r.delivery,coal=r.coalAdded,scrap=r.scrapAdded,xp=r.xp,levels=r.levels,
            gained=v.gained,total=v.total,recipients=recipients,amount=r.amount}
    end
    if not R.valid(command,d) then return nil,'invalid_public_result' end
    return d
end
return R
