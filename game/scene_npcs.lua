-- Persistent scene preparation is shared by command drafts and local views.
local Stops=require("game.stops")
local Range=require("game.shooting_range")
local Settlements=require("game.settlements")
local Util=require("game.util")
local Family=require("game.family")
local NPCs={}
function NPCs.prepare(data,catalog,rng)
    if data.scene~="stop" and data.scene~="house" then return nil end
    local layout=Stops.ensure(data,catalog,data.scene,rng)
    Range.ensure(layout,data.location,Settlements)
    data.currentNPC=(data.scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    local key=Util.sceneKey(data.scene,data.location)..(data.scene=="house" and (":"..tostring(data.activeHouseDoor or 1)) or "")
    local saved=data.npcStates[key]
    local defaults=data.scene=="house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
    saved=saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
    saved.weapon=layout.npcWeapon
    if data.scene=="house" then
        saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
        saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
    else
        saved.x,saved.y=Settlements.clamp(saved.x,saved.y,data.location)
        saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,data.location)
    end
    data.npcStates[key]=saved
    Family.ensure(saved,data.currentNPC,rng)
    return saved
end
return NPCs
