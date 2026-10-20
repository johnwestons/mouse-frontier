-- Named destination reservations and read-only directions shared by the host,
-- guest journal, map, and hand-in eligibility.
local Identity=require('game.npc_identity')
local Targets={}
function Targets.reserve(data,stop,rng,preferred)
    rng=rng or math.random
    data.stopLayouts=data.stopLayouts or {}
    local layout=data.stopLayouts[tostring(stop)]
    if not layout then
        layout={houseX=rng(390,700),treeA=rng(110,250),treeB=rng(760,860),house=rng(1,8),tree=rng(1,7)}
        data.stopLayouts[tostring(stop)]=layout
    end
    local roster=data.npcRoster or {}
    local file=preferred or layout.npcOutside or layout.npc or roster[rng(math.max(1,#roster))] or data.currentNPC or 'mail-mouse.png'
    layout.npcOutside=layout.npcOutside or layout.npc or file; layout.npc=layout.npcOutside
    local door,found=1,file==layout.npcOutside
    for key,home in pairs(layout.houseDoors or {}) do if home.npc==file then door=home.door or tonumber(key) or 1; found=true; break end end
    if not found then
        local occupied={}
        for key in pairs(layout.houseDoors or {}) do occupied[tonumber(key)]=true end
        if layout.npcInside then occupied[layout.activeHouseDoor or 1]=true end
        for _,reservedDoor in pairs(layout.reservedResidents or {}) do occupied[reservedDoor]=true end
        for candidate=1,5 do if not occupied[candidate] then door=candidate; break end end
        layout.reservedResidents=layout.reservedResidents or {}; layout.reservedResidents[file]=door
        -- A legacy letter may name somebody omitted from an already prepared
        -- roster. Rebuild its membership while reusing saved resident actors.
        if layout.residentVersion==1 then layout.residentVersion=nil end
    end
    local person=Identity.ensure(data,file,stop,door)
    return person,file
end
function Targets.bind(data,quest,rng)
    local person=quest.recipientId and Identity.get(data,quest.recipientId)
    if not person then person=Targets.reserve(data,quest.destination,rng,quest.recipient) end
    quest.recipientId=person.id; quest.recipient=person.file
    if quest.sender then quest.senderId=Identity.ensure(data,quest.sender,quest.origin or data.location,1).id end
    return quest
end
function Targets.prepare(data)
    for _,collection in ipairs({data.mailQuests or {},data.supplyQuests or {}}) do
        for _,quest in ipairs(collection) do if not quest.complete and quest.destination then
            Targets.bind(data,quest,function(low,high) return high and low or 1 end)
        end end
    end
end
function Targets.matches(data,quest,reference)
    if quest.destination~=data.location then return false end
    if quest.recipientId then return Identity.key(data,reference)==quest.recipientId end
    return not quest.recipient or quest.recipient==(type(reference)=='table' and (reference.npc or reference.file) or reference)
end
function Targets.pending(data,reference)
    local id=Identity.key(data,reference)
    if not id then return nil end
    for _,collection in ipairs({data.mailQuests or {},data.supplyQuests or {}}) do
        for _,q in ipairs(collection) do if not q.complete and q.recipientId==id then return q end end
    end
end
function Targets.current(data)
    for _,collection in ipairs({data.mailQuests or {},data.supplyQuests or {}}) do
        for _,q in ipairs(collection) do if not q.complete and q.destination==data.location and q.recipientId then return q end end
    end
end
function Targets.doorMarkers(data)
    local result,seen={},{}
    for _,actor in pairs(data.npcStates or {}) do
        if actor.characterId and actor.scene=='house' and actor.homeDoor and not seen[actor.homeDoor] then
            local quest=Targets.pending(data,actor.characterId)
            if quest and quest.destination==data.location then
                result[#result+1]=actor.homeDoor; seen[actor.homeDoor]=true
            end
        end
    end
    table.sort(result); return result
end
function Targets.directions(data,quest)
    local person=quest.recipientId and Identity.get(data,quest.recipientId)
    if not person then return 'Stop '..tostring(quest.destination or '?') end
    if data.location==quest.destination then
        for _,actor in pairs(data.npcStates or {}) do
            if actor.characterId==person.id then
                return actor.scene=='house' and ('Inside home '..tostring(actor.homeDoor or person.homeDoor)) or 'Outside by the station'
            end
        end
    end
    return 'Station / home '..tostring(person.homeDoor)..' • Stop '..tostring(quest.destination)
end
function Targets.label(data,quest,cargo)
    local name=Identity.name(data,quest.recipientId or quest.recipient,quest.destination)
    return 'Deliver '..(cargo or 'mail')..' to '..name..' at Stop '..tostring(quest.destination)..'.'
end
function Targets.validate(data)
    for _,collection in ipairs({data.mailQuests or {},data.supplyQuests or {}}) do
        for _,q in ipairs(collection) do
          if type(q)~='table' then return false,'invalid delivery' end
          if q.recipientId then
            local p=Identity.get(data,q.recipientId)
            if not p or p.file~=q.recipient or p.homeStop~=q.destination then return false,'invalid delivery identity' end
            if q.senderId then
                local sender=Identity.get(data,q.senderId)
                if not sender or sender.file~=q.sender or sender.homeStop~=q.origin then return false,'invalid sender identity' end
            end
          end
        end
    end
    return true
end
return Targets
