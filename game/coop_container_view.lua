-- Read-only affordances use the same reach rules as the host. They only decide
-- which panel to show; authority always validates access again on each action.
local Entities=require('game.coop_entities')
local Commands=require('game.coop_inventory')
local Areas=require('game.expedition_areas')
local Containers={}
Containers.isContainer=Commands.isContainer
local function position(item,record)
    if record.kind=='drop' then return item.x,item.y end
    if record.kind=='expeditionChest' then
        local area=Areas.definition(record.areaId)
        for _,spot in ipairs(area and area.interactions or {}) do
            if spot.chestId==record.key then return spot.x,spot.y end
        end
    end
end
function Containers.find(data,id,state,catalog)
    local item,record=Entities.find(data,id)
    if Commands.isContainer(item,catalog) and Commands.canAccess(data,data,state,item,record) then return item end
end
function Containers.nearest(data,state,catalog)
    local nearest,distance
    for _,record in ipairs(Entities.records(data)) do
        local item=record.value
        if Commands.isContainer(item,catalog) and Commands.canAccess(data,data,state,item,record) then
            local x,y=position(item,record)
            if x and y then
                local d=(state.x-x)^2+(state.y-y)^2
                if not distance or d<distance then nearest,distance=item,d end
            end
        end
    end
    return nearest,distance
end
return Containers
