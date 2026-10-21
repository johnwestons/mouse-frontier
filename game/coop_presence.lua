-- Personal local visits. The campaign root remains the host's scene for the
-- existing solo runtime; a companion's saved presence supplies its own view.
local P=require('game.net.protocol')
local Presence={}
local scenes={train=true,stop=true,house=true,caravan=true,expedition=true}
local direct={scene=true,activeHouseDoor=true,lastStopDoor=true,activeExpeditionArea=true,currentNPC=true}
local fields={epoch=true,revision=true,scene=true,activeHouseDoor=true,lastStopDoor=true,
    activeExpeditionArea=true,currentNPC=true,inOffice=true,activeCampId=true}
function Presence.get(data,id)
    local actor=data.players and data.players[id]
    local p=actor and actor.presence
    return p and data.coop and p.epoch==data.coop.sceneEpoch and p or nil
end
function Presence.revision(data,id)
    local p=Presence.get(data,id); return p and p.revision or 0
end
function Presence.capture(data,revision)
    local p={epoch=data.coop.sceneEpoch,revision=revision or 0}
    for key in pairs(direct) do p[key]=data[key] end
    p.inOffice=data.homeStop and data.homeStop.inOffice==true or false
    p.activeCampId=data.crowCaravans and data.crowCaravans.activeCampId
    return p
end
function Presence.ensure(data)
    for _,id in ipairs({'host','companion'}) do
        local actor=data.players[id]
        if actor and not Presence.get(data,id) then actor.presence=Presence.capture(data) end
    end
end
local function overlay(source,key,p,field)
    if not source then return nil end
    return setmetatable({}, {
        __index=function(_,k) if k==key then return p[field] end; return source[k] end,
        __newindex=function(_,k,v) if k==key then p[field]=v else source[k]=v end end,
    })
end
function Presence.read(data,id,key)
    local p=id=='companion' and Presence.get(data,id)
    if not p then return false end
    if direct[key] then return true,p[key] end
    if key=='homeStop' then return true,overlay(data.homeStop,'inOffice',p,'inOffice') end
    if key=='crowCaravans' then return true,overlay(data.crowCaravans,'activeCampId',p,'activeCampId') end
    return false
end
function Presence.write(data,id,key,value)
    local p=id=='companion' and Presence.get(data,id)
    if p and direct[key] then p[key]=value; return true end
    return false
end
function Presence.key(data,id)
    local p=id=='companion' and Presence.get(data,id)
    local scene=p and p.scene or data.scene
    local detail
    if scene=='house' then detail=p and p.activeHouseDoor or data.activeHouseDoor or 1
    elseif scene=='expedition' then detail=p and p.activeExpeditionArea or data.activeExpeditionArea
    elseif scene=='caravan' then detail=p and p.activeCampId or data.crowCaravans and data.crowCaravans.activeCampId
    elseif scene=='stop' then detail=p and p.inOffice or not p and data.homeStop and data.homeStop.inOffice or false end
    return table.concat({tostring(data.location),tostring(scene),tostring(detail)},':')
end
function Presence.same(data,a,b) return Presence.key(data,a)==Presence.key(data,b) end
function Presence.validate(data)
    for id,actor in pairs(data.players or {}) do
        local p=actor.presence
        if p then
            if not P.fields(p,fields) or not data.coop or p.epoch~=data.coop.sceneEpoch
                or not P.integer(p.revision,0,2147483647) or not scenes[p.scene] or type(p.inOffice)~='boolean'
                or p.currentNPC~=nil and not P.text(p.currentNPC,128)
                or p.lastStopDoor~=nil and not P.integer(p.lastStopDoor,1,100)
                or p.activeHouseDoor~=nil and not P.integer(p.activeHouseDoor,1,100)
                or p.activeExpeditionArea~=nil and not P.text(p.activeExpeditionArea,64)
                or p.activeCampId~=nil and not P.text(p.activeCampId,64) then return false,'invalid player presence' end
            if p.scene=='house' and not p.activeHouseDoor or p.scene~='house' and p.activeHouseDoor
                or p.scene=='expedition' and not (data.expeditions and data.expeditions[p.activeExpeditionArea])
                or p.scene~='expedition' and p.activeExpeditionArea
                or p.inOffice and (p.scene~='stop' or data.location~=1 or not data.homeStop or data.homeStop.stage=='departed') then
                return false,'invalid local scene'
            end
        end
    end
    return true
end
return Presence
