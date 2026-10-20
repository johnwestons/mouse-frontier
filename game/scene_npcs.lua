-- Persistent scene preparation is shared by command drafts and local views.
local Stops=require("game.stops")
local Range=require("game.shooting_range")
local Settlements=require("game.settlements")
local Util=require("game.util")
local Family=require("game.family")
local Home=require("game.home_stop")
local Routines=require("game.npc_routines")
local Doors=require("game.interior_doors")
local Identity=require('game.npc_identity')
local NPCs={}
local function layoutFor(data)
    return data and data.stopLayouts and data.stopLayouts[tostring(data.location)]
end
local function departed(data,layout,actor)
    local offer=layout.coopOffers and layout.coopOffers[actor.file]
    if offer and offer.kind=='ride' and offer.status=='accepted' then return true end
    for _,passenger in ipairs(data.passengers or {}) do
        if passenger.npc==actor.file and passenger.origin==data.location then return true end
    end
    return false
end
function NPCs.hasResidents(data)
    if Home.isHome(data) then return false end
    local layout=layoutFor(data)
    return layout~=nil and layout.residentVersion==1 and type(layout.residentKeys)=='table'
end
function NPCs.list(data,scene,door)
    local result={}
    if not NPCs.hasResidents(data) then return result end
    scene=scene or data.scene; door=door or data.activeHouseDoor or 1
    local layout=layoutFor(data)
    for _,key in ipairs(layout.residentKeys) do
        local actor=data.npcStates and data.npcStates[key]
        if actor and not departed(data,layout,actor) and (scene==nil or actor.scene==scene)
            and (actor.scene~='house' or actor.homeDoor==door) then result[#result+1]=actor end
    end
    return result
end
function NPCs.find(data,file,scene,door)
    for _,actor in ipairs(NPCs.list(data,scene,door)) do if actor.file==file then return actor end end
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function ensureResidents(data,catalog,rng)
    local selected=data.currentNPC
    local layout=Stops.ensure(data,catalog,data.scene,rng)
    Range.ensure(layout,data.location,Settlements)
    if NPCs.hasResidents(data) then
        for _,key in ipairs(layout.residentKeys) do
            local actor=data.npcStates[key]
            if actor then actor.characterId=Identity.ensure(data,actor.file,data.location,actor.homeDoor).id end
        end
        data.currentNPC=selected; return layout
    end
    data.npcStates=data.npcStates or {}
    local activeDoor=data.activeHouseDoor or 1
    local interior,inside,layoutDoor=layout.interior,layout.npcInside,layout.activeHouseDoor
    layout.houseDoors=layout.houseDoors or {}
    -- Keep previously assigned occupants/interiors when upgrading a save.
    if not next(layout.houseDoors) and inside then
        local oldDoor=layoutDoor or (data.scene=='house' and activeDoor or 1)
        layout.houseDoors[tostring(oldDoor)]={door=oldDoor,npc=inside,interior=interior}
    end
    for door=1,Routines.doorCount(data.location) do Stops.ensureDoor(data,catalog,door,rng) end
    layout.residentKeys={}
    local added={}
    local function add(file,door,scene)
        if not file or added[file] then return end
        added[file]=true
        local key='resident:'..tostring(data.location)..':'..file
        local oldKey=Util.sceneKey(scene,data.location)..(scene=='house' and ':'..tostring(door) or '')
        local actor=data.npcStates[key] or copy(data.npcStates[oldKey]) or {}
        local home=layout.houseDoors[tostring(door)]
        local x,y
        if scene=='stop' then x,y=Settlements.doorPoint(data.location,door); x,y=Settlements.clamp(x+24,y+28,data.location)
        else x,y=Doors.spawnPoint(home and home.interior); x,y=Util.clampHouseFloor(x+(480-x)*.5,y+(440-y)*.5) end
        actor.file=file; actor.homeDoor=door; actor.scene=actor.scene or scene
        actor.characterId=Identity.ensure(data,file,data.location,door).id
        actor.x,actor.y=actor.x or x,actor.y or y
        if actor.scene=='stop' then actor.x,actor.y=Settlements.clamp(actor.x,actor.y,data.location)
        else actor.x,actor.y=Util.clampHouseFloor(actor.x,actor.y) end
        actor.homeX,actor.homeY=actor.x,actor.y
        actor.routineStep=actor.routineStep or (actor.scene=='stop' and 3 or 1)
        actor.routinePhase=actor.routinePhase or 'travel'; actor.routineClock=actor.routineClock or 0
        actor.weapon=actor.weapon or layout.npcWeapon
        layout.npcOffers[file]=layout.npcOffers[file] or (file:lower():find('crow%-merchant') and 'trade' or 'none')
        Family.ensure(actor,file,rng)
        data.npcStates[key]=actor; layout.residentKeys[#layout.residentKeys+1]=key
    end
    add(layout.npcOutside,1,'stop')
    for door=1,Routines.doorCount(data.location) do add(layout.houseDoors[tostring(door)].npc,door,'house') end
    for file,door in pairs(layout.reservedResidents or {}) do add(file,door,'stop') end
    layout.residentVersion=1
    layout.interior,layout.npcInside,layout.activeHouseDoor=interior,inside,layoutDoor
    if data.scene=='house' and layout.houseDoors[tostring(activeDoor)] then
        local home=layout.houseDoors[tostring(activeDoor)]
        layout.interior,layout.npcInside,layout.activeHouseDoor=home.interior,home.npc,activeDoor
    end
    data.currentNPC=selected
    return layout
end
function NPCs.locked(runtime)
    return runtime.dialogue or runtime.helpDialogue or runtime.questOffer or runtime.tradeOpen
        or runtime.giftOpen or runtime.peopleOpen or runtime.firstAid or runtime.guestActivityOpen
end
-- Selection is local presentation state; actor occupancy remains authoritative.
function NPCs.refresh(runtime,held)
    local data=runtime.saveData
    if not NPCs.hasResidents(data) then return runtime.npcActor end
    runtime.npcActors=NPCs.list(data,runtime.scene,data.activeHouseDoor)
    local selected=held and NPCs.find(data,data.currentNPC,runtime.scene,data.activeHouseDoor)
    local best
    if not selected then
        local player=runtime.player or {x=data.playerX or 480,y=data.playerY or 500}
        for _,actor in ipairs(runtime.npcActors) do
            local d=(player.x-actor.x)^2+(player.y-actor.y)^2
            if not best or d<best then selected,best=actor,d end
        end
    end
    runtime.npcActor=selected; data.currentNPC=selected and selected.file or nil
    local layout=layoutFor(data)
    layout.offer=layout.npcOffers and layout.npcOffers[data.currentNPC] or 'none'
    return selected
end
function NPCs.update(data,dt,options)
    if not NPCs.hasResidents(data) then return end
    options=options or {}
    local layout=layoutFor(data)
    for _,key in ipairs(layout.residentKeys) do
        local actor=data.npcStates[key]
        if actor and not departed(data,layout,actor) then
            local held=options.held and options.held(actor)
            Routines.update(data,actor,dt,{held=held,interiorFiles=options.interiorFiles})
            if not held then
                Family.update(actor,dt,function(ox,oy,x,y)
                    if actor.scene=='stop' then return Settlements.move(data.location,ox,oy,x,y) end
                    return Util.clampHouseFloor(x,y)
                end)
            end
        end
    end
end
function NPCs.prepareHome(data)
    Home.layout(data)
    if not Home.isOffice(data) then return nil end
    data.npcStates=data.npcStates or {}
    local key="homeStop:conductor"
    local actor=data.npcStates[key] or {}
    local point=Home.points.conductor
    actor.x,actor.y=point.x,point.y
    actor.homeX,actor.homeY=point.x,point.y
    actor.targetX,actor.targetY=nil,nil
    actor.velocityX,actor.velocityY=0,0
    actor.intentX,actor.intentY=0,0
    actor.moving=false
    actor.facing=actor.facing or -1
    actor.wait=1.5
    actor.weapon=nil
    actor.family=nil
    actor.file=data.currentNPC
    actor.characterId='homeStop:conductor'
    data.npcStates[key]=actor
    return actor
end
function NPCs.prepare(data,catalog,rng)
    if data.scene~="stop" and data.scene~="house" then return nil end
    if data.scene=="stop" and Home.isHome(data) then return NPCs.prepareHome(data) end
    ensureResidents(data,catalog,rng)
    return NPCs.refresh({saveData=data,scene=data.scene},true)
end
return NPCs
