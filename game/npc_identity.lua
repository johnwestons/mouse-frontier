-- A person is independent of the sprite used to draw them. Readers never
-- allocate names; preparation and authority transactions own all allocation.
local Util=require('game.util')
local Identity={}
local first={'Ada','Alden','Alma','Amos','Ansel','Basil','Bea','Bram','Cora','Della','Edwin','Elsie','Emmett','Fern','Flora','Gideon',
    'Hazel','Hollis','Ida','Iris','Jasper','June','Kit','Lena','Mabel','Milo','Nell','Orin','Otis','Pearl','Rhea','Rowan',
    'Rufus','Ruth','Sylvie','Theo','Vera','Walter','Willa','Wren'}
local last={'Ash','Barley','Birch','Bracken','Bramble','Brook','Burr','Cedar','Clover','Copper','Dale','Dew','Elm','Fennel','Field','Flint',
    'Glen','Gorse','Grove','Hawthorn','Hearth','Hickory','Hollow','Juniper','Lark','Leaf','Meadow','Moss','Nettle','Oak','Pine','Reed',
    'Ridge','River','Root','Russet','Sedge','Thistle','Vale','Willow'}
local special={['homeStop:conductor']={name='Silas Reed',role='Conductor'},['homeStop:tinker']={name='Tobin Flint',role='Mechanic'}}
local species={'tortoise','hedgehog','opossum','raccoon','squirrel','rabbit','badger','ferret','weasel','mouse','shrew','otter','gecko','lizard','mole','fox','crow','frog','rat'}
local jobs={{'conductor','Conductor'},{'tinker','Mechanic'},{'mechanic','Mechanic'},{'engineer','Engineer'},{'medic','Medic'},
    {'herbalist','Herbalist'},{'botanist','Gardener'},{'gardener','Gardener'},{'cook','Cook'},{'merchant','Trader'},
    {'mail','Postkeeper'},{'courier','Courier'},{'prospector','Prospector'},{'scout','Scout'},{'ranger','Ranger'},
    {'trapper','Trapper'},{'homesteader','Homesteader'},{'scavenger','Salvager'},{'radio','Radio operator'},{'signal','Signal keeper'}}
local function hash(value)
    local n=17; for i=1,#value do n=(n*31+value:byte(i))%2147483647 end; return n
end
local function keys(t)
    local result={}; for key in pairs(t or {}) do result[#result+1]=key end
    table.sort(result,function(a,b) return tostring(a)<tostring(b) end); return result
end
local function copy(t)
    if type(t)~='table' then return t end
    local result={}; for k,v in pairs(t) do result[k]=copy(v) end; return result
end
function Identity.residentId(stop,file) return 'npc:'..tostring(stop)..':'..file end
function Identity.describe(file)
    local kind='Critter'; local role='Resident'; local s=(file or ''):lower()
    for _,word in ipairs(species) do if s:find(word,1,true) then kind=Util.titleFromFile(word); break end end
    for _,pair in ipairs(jobs) do if s:find(pair[1],1,true) then role=pair[2]; break end end
    return kind,role
end
function Identity.ensure(data,file,stop,door,id)
    if type(file)~='string' then return nil end
    data.npcIdentities=data.npcIdentities or {}
    id=id or Identity.residentId(stop or data.location or 1,file)
    local record=data.npcIdentities[id]
    if record then return record end
    local used={}; for _,entry in pairs(data.npcIdentities) do used[entry.name:lower()]=true end
    local fixed=special[id]; local name=fixed and fixed.name
    if not name then
        local start=hash(id)%(#first*#last)
        for offset=0,#first*#last-1 do
            local index=(start+offset)%(#first*#last)
            local candidate=first[index%#first+1]..' '..last[math.floor(index/#first)+1]
            if not used[candidate:lower()] then name=candidate; break end
        end
    end
    assert(name,'NPC name pool exhausted')
    local kind,role=Identity.describe(file)
    record={id=id,name=name,file=file,species=kind,role=fixed and fixed.role or role,
        homeStop=stop or data.location or 1,homeDoor=door or 1}
    data.npcIdentities[id]=record
    return record
end
function Identity.get(data,reference,stop)
    local records=data and data.npcIdentities or {}
    if type(reference)=='table' then
        if reference.characterId then return records[reference.characterId] end
        reference=reference.file or reference.npc
    end
    if type(reference)~='string' then return nil end
    if records[reference] then return records[reference] end
    stop=stop or data.location or 1
    if stop==1 and data.homeStop and data.homeStop.version==1 then
        local id=reference=='tortoise-conductor.png' and 'homeStop:conductor' or reference=='tinker-fox.png' and 'homeStop:tinker'
        if id and records[id] then return records[id] end
    end
    if data.scene=='train' and stop==data.location then
        local found
        for _,p in ipairs(data.passengers or {}) do if p.npc==reference and p.characterId then
            if found then return nil end -- callers with two matching sprites must pass the passenger record
            found=records[p.characterId]
        end end
        if found then return found end
    end
    return records[Identity.residentId(stop,reference)]
end
function Identity.key(data,reference,stop)
    local person=Identity.get(data,reference,stop)
    return person and person.id or (type(reference)=='table' and (reference.characterId or reference.npc or reference.file) or reference)
end
function Identity.name(data,reference,stop)
    local person=Identity.get(data,reference,stop)
    if person then return person.name end
    return Util.titleFromFile(type(reference)=='table' and (reference.npc or reference.file) or reference or 'Traveler')
end
function Identity.title(data,reference,stop)
    local person=Identity.get(data,reference,stop)
    return person and (person.name..' • '..person.role) or Identity.name(data,reference,stop)
end
function Identity.ensureStop(data,layout,stop)
    stop=stop or data.location
    if layout.homeStop then
        Identity.ensure(data,'tortoise-conductor.png',1,1,'homeStop:conductor')
        Identity.ensure(data,'tinker-fox.png',1,1,'homeStop:tinker'); return
    end
    local seen={}
    local function add(file,door)
        if file and not seen[file] then Identity.ensure(data,file,stop,door); seen[file]=true end
    end
    add(layout.npcOutside or layout.npc,1)
    for _,key in ipairs(keys(layout.houseDoors)) do local home=layout.houseDoors[key]; add(home.npc,home.door or tonumber(key)) end
    add(layout.npcInside,1)
    for _,file in ipairs(keys(layout.reservedResidents)) do add(file,layout.reservedResidents[file]) end
end
function Identity.prepare(data)
    data.npcIdentities=data.npcIdentities or {}
    for _,key in ipairs(keys(data.stopLayouts)) do
        local stop=tonumber(key); if stop then Identity.ensureStop(data,data.stopLayouts[key],stop) end
    end
    for key,actor in pairs(data.npcStates or {}) do
        if type(actor)=='table' and actor.file then
            local stop=tonumber(tostring(key):match('^resident:(%d+):'))
            if stop then actor.characterId=Identity.ensure(data,actor.file,stop,actor.homeDoor).id
            elseif special[key] then actor.characterId=Identity.ensure(data,actor.file,1,1,key).id end
        end
    end
    for _,p in ipairs(data.passengers or {}) do
        local person=Identity.get(data,p) or Identity.ensure(data,p.npc,p.origin or data.location,1)
        p.characterId=person.id
    end
    -- Old histories used one sprite-wide key. Preserve each old record once,
    -- on its most recent known resident, instead of cloning friendship to every
    -- critter using that sprite. Keep the legacy entry as historical data.
    for file,record in pairs(data.relationships or {}) do
        if type(file)=='string' and not file:find(':',1,true) and file:match('%.png$') and type(record)=='table' and not record.identityMigrated then
            local person
            for _,p in ipairs(data.passengers or {}) do if p.npc==file then person=Identity.get(data,p); break end end
            person=person or Identity.get(data,file,record.lastHelpStop or data.location)
            if person and not data.relationships[person.id] then data.relationships[person.id]=copy(record) end
            record.identityMigrated=true
        end
    end
    return data
end
function Identity.board(data,passenger)
    local person=Identity.get(data,passenger) or Identity.ensure(data,passenger.npc,passenger.origin or data.location,1)
    passenger.characterId=person.id; person.status='aboard'; person.lastStop=data.location
    return person
end
function Identity.arrive(data,passenger)
    local person=Identity.get(data,passenger)
    if person then person.status='arrived'; person.lastStop=data.location end
    return person
end
function Identity.validate(data)
    local records=data.npcIdentities
    if records==nil then return true end
    if type(records)~='table' then return false,'NPC identities must be a table' end
    local seen={}
    for id,p in pairs(records) do
        if type(id)~='string' or #id>128 or type(p)~='table' or p.id~=id
            or type(p.name)~='string' or #p.name<3 or #p.name>60 or p.name:find('[%c]')
            or type(p.file)~='string' or #p.file>100 or not p.file:match('%.png$')
            or type(p.role)~='string' or type(p.species)~='string'
            or type(p.homeStop)~='number' or p.homeStop<1 or p.homeStop>50 or p.homeStop~=math.floor(p.homeStop)
            or type(p.homeDoor)~='number' or p.homeDoor<1 or p.homeDoor>5 or p.homeDoor~=math.floor(p.homeDoor)
            or seen[p.name:lower()] then return false,'invalid or duplicate NPC identity' end
        seen[p.name:lower()]=true
        if not special[id] and id~=Identity.residentId(p.homeStop,p.file) then return false,'NPC identity does not match its home' end
        if p.status and not ({aboard=true,arrived=true})[p.status] then return false,'invalid NPC travel status' end
        if p.lastStop and (type(p.lastStop)~='number' or p.lastStop<1 or p.lastStop>50 or p.lastStop~=math.floor(p.lastStop)) then return false,'invalid NPC last stop' end
    end
    for _,p in ipairs(data.passengers or {}) do
        if type(p)~='table' then return false,'invalid passenger' end
        if p.characterId and (not records[p.characterId] or records[p.characterId].file~=p.npc) then return false,'invalid passenger identity' end
    end
    for _,actor in pairs(data.npcStates or {}) do
        if type(actor)=='table' and actor.characterId and (not records[actor.characterId] or records[actor.characterId].file~=actor.file) then return false,'invalid resident identity' end
    end
    for _,layout in pairs(data.stopLayouts or {}) do if type(layout)~='table' then return false,'invalid stop layout' end end
    return true
end
return Identity
