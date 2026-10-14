-- Saved personal window choices. Live occupancy/readiness stays ephemeral.
local P=require('game.net.protocol')
local State={VERSION=1}
local windows={wide=true,tall=true}
local function actor(data,id) return (id=='host' or id=='companion') and data.players and data.players[id]~=nil end
function State.validate(data)
    local q=data.lastStand; if not q then return true end
    if q.positionVersion==nil then return q.firingPositions==nil end
    if q.positionVersion~=State.VERSION or not P.fields(q.firingPositions,{host=true,companion=true}) then return false end
    local seen={}
    for id,window in pairs(q.firingPositions) do
        if not actor(data,id) or not windows[window] or seen[window] then return false end
        seen[window]=true
    end
    return true
end
function State.prepare(data)
    local q=data.lastStand; if not q or q.positionVersion~=nil then return end
    -- No new companion is allocated merely because an actor has enrolled.
    local defenders=q.combat and q.combat.defenders
    local host=defenders and defenders.host and defenders.host.windowId or q.lastWindow
    local companion=defenders and defenders.companion and defenders.companion.windowId
    if not windows[host] then host=nil end
    if not actor(data,'companion') or not windows[companion] or companion==host then companion=nil end
    q.firingPositions={host=host,companion=companion}; q.positionVersion=State.VERSION
end
function State.ensure(data)
    State.prepare(data); assert(State.validate(data),'invalid Last Stand firing positions')
    return assert(data.lastStand).firingPositions
end
function State.selected(data,id)
    local q=data.lastStand; return q and q.positionVersion==State.VERSION and q.firingPositions and q.firingPositions[id]
end
function State.owner(data,window)
    local q=data.lastStand
    for id,selected in pairs(q and q.firingPositions or {}) do if selected==window then return id end end
end
function State.claim(data,id,window)
    if not actor(data,id) or not windows[window] then return false,'invalid_position' end
    local selections=State.ensure(data); local owner=State.owner(data,window)
    if owner and owner~=id then return false,'position_occupied' end
    local previous=selections[id]; selections[id]=window
    return true,nil,previous
end
function State.release(data,id)
    if not actor(data,id) then return false,'invalid_position' end
    local selections=State.ensure(data); local previous=selections[id]; selections[id]=nil
    return true,nil,previous
end
function State.reset(q) q.firingPositions=nil; q.positionVersion=nil end
return State
