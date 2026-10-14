-- Owned gun simulation records and private authored-frame presentation.
-- Host legacy fields remain the host's record; a companion never inherits them.
local Players=require('game.coop_players')
local Items=require('game.item_instances')
local P=require('game.net.protocol')
local Sessions={VERSION=1}
local persistent={actorId=true,weapon=true,itemId=true,ammoType=true,capacity=true,borrowed=true,magazine=true,
    reloadTimer=true,cooldown=true,fireMode=true,weaponAction=true,weaponActionElapsed=true,
    weaponReloadDuration=true,tubeReloadTotalRounds=true,tubeReloadRemaining=true,
    tubeReloadCompleted=true,tubeReloadRoundTimer=true}
local views=setmetatable({},{__mode='kv'})
local records=setmetatable({},{__mode='k'})
local function finite(n,low,high) return type(n)=='number' and n==n and n>=low and n<=high end
function Sessions.record(gun) return records[gun] or gun end
function Sessions.bind(gun,data)
    local id=Players.actorId(data); if id then gun.actorId=id end
    return gun
end
function Sessions.owned(gun,data)
    local id=Players.actorId(data)
    return gun and (id and gun.actorId==id or not id and gun.actorId==nil) or false
end
function Sessions.view(gun,width,height)
    gun=Sessions.record(gun)
    local view=views[gun]; if view then return view end
    local localState={aimX=(width or 960)/2,aimY=(height or 720)/2,
        weaponX=(width or 960)*.68,weaponY=(height or 720)*.70,ads=false,fireHeld=false,fireHeldSources={}}
    -- Old saves can contain a device's aim/ADS/touch state. Keep it out of the
    -- simulation record and begin the new device with neutral controls.
    for key in pairs(gun) do if not persistent[key] then gun[key]=nil end end
    view=setmetatable({}, {__index=function(_,key)
        if persistent[key] then return gun[key] end; return localState[key]
    end,__newindex=function(_,key,value)
        if persistent[key] then gun[key]=value else localState[key]=value end
    end})
    records[view]=gun; views[gun]=view; return view
end
function Sessions.scope(data,container)
    local id=Players.actorId(data)
    if not id then return container end -- Existing standalone/offline helpers.
    container.shooterVersion=Sessions.VERSION
    if id=='host' then return container end
    container.shooterSessions=container.shooterSessions or {}
    local session=container.shooterSessions[id]
    if not session then
        session={loanAmmo=0,loanActive=false}; container.shooterSessions[id]=session
    end
    return session
end
function Sessions.reclaim(container)
    local function clear(owner)
        owner.loanAmmo=0; owner.loanActive=false
        if owner.weaponSession and owner.weaponSession.borrowed then owner.weaponSession=nil end
        if owner.weaponSessions then owner.weaponSessions.loan=nil end
    end
    clear(container)
    for _,owner in pairs(container.shooterSessions or {}) do clear(owner) end
end
function Sessions.reset(container)
    Sessions.reclaim(container)
    container.weaponSession=nil; container.weaponSessions=nil
    for _,owner in pairs(container.shooterSessions or {}) do owner.weaponSession=nil; owner.weaponSessions=nil end
end
local function cleanRecord(gun,id,actor,catalog)
    if type(gun)~='table' then return end
    local legacy=gun.actorId==nil
    for key in pairs(gun) do if not persistent[key] then gun[key]=nil end end
    if gun.actorId==nil then gun.actorId=id end
    if legacy and gun.weapon then
        local spec=catalog.weaponCombat[gun.weapon]
        if not spec or spec.kind~='ranged' or not spec.ammo or spec.ammo=='arrows' or spec.ammo=='rocks'
            or spec.ammo=='ball-bearings' then return legacy,false end
        if spec then
            if gun.borrowed==nil then gun.borrowed=false end
            if not gun.borrowed and not gun.itemId then
                local entry=Items.owned(actor,gun.weapon); if entry then gun.itemId=entry.id end
                if not gun.itemId then return legacy,false end
            end
            gun.capacity=math.max(1,math.floor(spec.capacity or 1)); gun.ammoType=spec.ammo
            if gun.magazine==nil then gun.magazine=0 end
            if gun.cooldown==nil then gun.cooldown=0 end
            if gun.reloadTimer==nil then gun.reloadTimer=0 end
            if gun.fireMode==nil then gun.fireMode='single' end
        end
    end
    return legacy,true
end
local function cleanOwner(owner,id,actor,catalog)
    local _,usable=cleanRecord(owner.weaponSession,id,actor,catalog)
    if usable==false then owner.weaponSession=nil end
    local rekey={}
    for key,gun in pairs(type(owner.weaponSessions)=='table' and owner.weaponSessions or {}) do
        local legacy,available=cleanRecord(gun,id,actor,catalog)
        if available==false then rekey[#rekey+1]={old=key}
        elseif legacy and key==gun.weapon and (gun.borrowed or gun.itemId) then
            rekey[#rekey+1]={old=key,key=gun.borrowed and 'loan' or gun.itemId,gun=gun}
        end
    end
    for _,entry in ipairs(rekey) do
        owner.weaponSessions[entry.old]=nil
        if entry.key and owner.weaponSessions[entry.key]==nil then owner.weaponSessions[entry.key]=entry.gun end
    end
end
function Sessions.prepare(data)
    local catalog=require('game.catalog')
    for _,container in ipairs({data.lastStand or false,data.trainAmbush or false}) do
        if type(container)=='table' and (container.weaponSession or container.weaponSessions or container.shooterSessions) then
            container.shooterVersion=Sessions.VERSION; cleanOwner(container,'host',data.players.host,catalog)
            for id,owner in pairs(type(container.shooterSessions)=='table' and container.shooterSessions or {}) do
                if type(owner)=='table' and data.players[id] then cleanOwner(owner,id,data.players[id],catalog) end
            end
        end
    end
end
local function validGun(gun,catalog,actor,key)
    if type(gun)~='table' or getmetatable(gun)~=nil or not P.fields(gun,persistent) then return false end
    if gun.actorId~=actor.id then return false end
    if gun.weapon==nil then
        return key==nil and gun.itemId==nil and gun.ammoType==nil and gun.capacity==nil and gun.borrowed==nil
            and gun.magazine==nil and gun.fireMode==nil and gun.weaponAction==nil
            and finite(gun.reloadTimer,0,3600) and finite(gun.cooldown,0,3600)
    end
    local spec=catalog.weaponCombat[gun.weapon]
    if not spec or spec.kind~='ranged' or not spec.ammo or not P.text(gun.weapon,128)
        or gun.borrowed~=true and gun.borrowed~=false or gun.ammoType~=spec.ammo
        or gun.capacity~=math.max(1,math.floor(spec.capacity or 1))
        or not P.integer(gun.magazine,0,gun.capacity) or not finite(gun.reloadTimer,0,3600)
        or not finite(gun.cooldown,0,3600)
        or not require('game.first_person_weapon_manifest').fireModeValid(gun.weapon,gun.fireMode)
        or gun.weaponAction~=nil and gun.weaponAction~='fire' and gun.weaponAction~='reload' then return false end
    if gun.borrowed then
        if gun.weapon~='frontier-22-lever-rifle' or gun.itemId~=nil or key~=nil and key~='loan' then return false end
    else
        if not P.text(gun.itemId,32) or key~=nil and key~=gun.itemId then return false end
        -- A stored gun may have been dropped/sold since this encounter. It
        -- remains inert; if present, its exact owned instance must match.
        local item=Items.owned(actor,gun.itemId)
        if item and item.name~=gun.weapon then return false end
    end
    for _,name in ipairs({'weaponActionElapsed','weaponReloadDuration','tubeReloadTotalRounds',
        'tubeReloadRemaining','tubeReloadCompleted','tubeReloadRoundTimer'}) do
        local n=gun[name]; if n~=nil and not finite(n,0,3600) then return false end
    end
    if gun.tubeReloadTotalRounds~=nil then
        if gun.weaponAction~='reload' or not P.integer(gun.tubeReloadTotalRounds,1,gun.capacity)
            or not P.integer(gun.tubeReloadRemaining,0,gun.tubeReloadTotalRounds)
            or not P.integer(gun.tubeReloadCompleted,0,gun.tubeReloadTotalRounds)
            or gun.tubeReloadRemaining+gun.tubeReloadCompleted>gun.tubeReloadTotalRounds
            or not finite(gun.tubeReloadRoundTimer,0,3600) or not finite(gun.weaponReloadDuration,.01,3600) then return false end
    end
    return true
end
local function validOwner(owner,catalog,actor,guest)
    if type(owner)~='table' or getmetatable(owner)~=nil then return false end
    if guest and not P.fields(owner,{weaponSession=true,weaponSessions=true,loanAmmo=true,loanActive=true}) then return false end
    if owner.loanAmmo~=nil and not P.integer(owner.loanAmmo,0,1000000)
        or owner.loanActive~=nil and type(owner.loanActive)~='boolean' then return false end
    if owner.weaponSession~=nil and not validGun(owner.weaponSession,catalog,actor) then return false end
    if owner.weaponSessions~=nil then
        if type(owner.weaponSessions)~='table' then return false end
        local count=0
        for key,gun in pairs(owner.weaponSessions) do
            count=count+1; if count>128 or not P.text(key,32) or not validGun(gun,catalog,actor,key) then return false end
        end
    end
    return true
end
function Sessions.validate(data)
    local catalog=require('game.catalog')
    for _,container in ipairs({data.lastStand or false,data.trainAmbush or false}) do
        if type(container)=='table' and container.shooterVersion~=nil then
            if container.shooterVersion~=Sessions.VERSION or not data.players
                or not validOwner(container,catalog,data.players.host,false) then return false end
            if container.shooterSessions~=nil then
                if type(container.shooterSessions)~='table' then return false end
                for id,owner in pairs(container.shooterSessions) do
                    if id~='companion' or not data.players[id] or not validOwner(owner,catalog,data.players[id],true) then return false end
                end
            end
        end
    end
    return true
end
return Sessions
