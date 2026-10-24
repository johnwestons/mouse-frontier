-- One shared, durable claim per ruined house. Graphics settings and camera
-- position never affect reach, rewards or whether a cache has been collected.
local Sites=require('game.battle_sites')
local Grid=require('game.battle_grid')
local Fog=require('game.battle_fog')
local Actors=require('game.battle_actors')
local Loot=require('game.loot_progression')
local Search={}
local positions=setmetatable({},{__mode='k'})
local function owner(data,b)
    local e=b and b.encounter
    if not e then return nil end
    if e.source=='expedition' then return data.expeditions and data.expeditions[e.areaId] end
    return data.encounters and data.encounters[tostring(data.location)]
end
function Search.list(b)
    if not b or not b.field then return {}end
    if positions[b.field]then return positions[b.field]end
    local result={}
    for id,s in ipairs(Sites.list(b.field))do
        result[#result+1]={id=id,q=s.q+math.floor(s.w/2),r=s.r+math.floor(s.d/2)}
    end
    positions[b.field]=result;return result
end
function Search.receipt(data,b,id)
    local saved=owner(data,b)
    return saved and saved.ruinCaches and saved.ruinCaches[tostring(id)]
end
function Search.available(data,b,u,id)
    if not u or not Actors.id(u)or u.team~='ally'or u.hp<=0 or b.finished then return false,'search_unavailable' end
    if type(id)~='number'or id~=math.floor(id)or id<1 or id>12 then return false,'invalid_cache' end
    local cache=Search.list(b)[id]
    if not cache or not owner(data,b)then return false,'search_unavailable' end
    if Search.receipt(data,b,id)then return false,'cache_collected' end
    if Grid.distance(u,cache)>1 or not Fog.visible(b,cache.q,cache.r)or not Grid.lineOfSight(b,u,cache)then
        return false,'cache_out_of_reach'
    end
    return true
end
function Search.nearby(data,b,u)
    for _,cache in ipairs(Search.list(b))do if Search.available(data,b,u,cache.id)then return cache end end
end
local function ammunition(actor,catalog,location,rng)
    for i=1,2 do
        local combat=catalog.weaponCombat[actor.equipment[i]]
        if combat and combat.ammo and catalog.ammoPickupAmounts[combat.ammo]then return combat.ammo end
    end
    return Loot.rollAmmo(catalog,location,rng)
end
function Search.claim(data,b,u,id,catalog,rng)
    local valid,reason=Search.available(data,b,u,id);if not valid then return nil,reason end
    local actor=Actors.data(data,u);local location=data.location or 1
    local kind=(id-1)%6+1;local item,ammo
    if kind==1 then item=Loot.rollSupply(catalog,'food',location,rng)
    elseif kind==2 then item=Loot.rollSupply(catalog,'water',location,rng)
    elseif kind==3 then item=Loot.rollMedical(catalog,location,'common',rng)
    elseif kind==4 then ammo=ammunition(actor,catalog,location,rng)
    elseif kind==5 then item=Loot.rollCraftMaterial(catalog,location,rng)
    else item=Loot.rollItem(catalog,location,{weaponChance=.25,rng=rng})end
    local scrap=2+math.min(4,math.floor(location/10))+math.floor(rng()*3)
    local receipt={actorId=Actors.id(u),scrap=scrap}
    local messages={'+'..scrap..' shared scrap'}
    if item then
        local _,destination=require('game.events').giveItem(actor,catalog,item)
        receipt.item=item;receipt.delivery=destination
        messages[#messages+1]=require('game.util').titleFromFile(item)..(destination=='inventory'and' (backpack)'or' (train mailbox)')
    end
    if ammo then
        local amount=catalog.ammoPickupAmounts[ammo]or 6
        actor.ammo[ammo]=(actor.ammo[ammo]or 0)+amount
        receipt.ammo=ammo;receipt.amount=amount
        messages[#messages+1]='+'..amount..' '..ammo..' (personal ammo)'
    end
    data.scrap=(data.scrap or 0)+scrap
    local saved=owner(data,b);saved.ruinCaches=saved.ruinCaches or {};saved.ruinCaches[tostring(id)]=receipt
    return receipt,'Ruin searched: '..table.concat(messages,', ')..'.'
end
function Search.validate(data)
    local function receipts(saved)
        if type(saved)~='table'then return false end
        local entries=saved.ruinCaches;if entries==nil then return true end
        if type(entries)~='table'then return false end
        for key,r in pairs(entries)do
            local id=type(key)=='string'and tonumber(key)
            if not id or id<1 or id>12 or tostring(id)~=key or id~=math.floor(id)or type(r)~='table'
                or r.actorId~='host'and r.actorId~='companion'or type(r.scrap)~='number'or r.scrap<2 or r.scrap>8 or r.scrap~=math.floor(r.scrap)then return false end
            for field in pairs(r)do if not ({actorId=true,scrap=true,item=true,delivery=true,ammo=true,amount=true})[field]then return false end end
            if r.item~=nil and(type(r.item)~='string'or #r.item<1 or #r.item>128
                or not ({inventory=true,mailbox=true,pending=true})[r.delivery])or r.item==nil and r.delivery~=nil then return false end
            if r.ammo~=nil and(type(r.ammo)~='string'or #r.ammo<1 or #r.ammo>64 or type(r.amount)~='number'
                or r.amount<1 or r.amount>1000 or r.amount~=math.floor(r.amount))or r.ammo==nil and r.amount~=nil then return false end
        end
        return true
    end
    for _,saved in pairs(data.encounters or {})do if not receipts(saved)then return false end end
    for _,saved in pairs(data.expeditions or {})do if not receipts(saved)then return false end end
    return true
end
return Search
