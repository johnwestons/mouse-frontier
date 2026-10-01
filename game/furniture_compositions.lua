local Compositions = {}

-- Furniture is grouped by purpose rather than by a fixed filename list. New
-- sprites can be added to a group and will be selected automatically when the
-- asset exists.
Compositions.groups = {
    storage={"bookcase","medicine-cabinet","train-locker","pantry-cupboard","barrel-cabinet","blue-steamer-trunk"},
    work={"rolltop-writing-desk","side-table","round-pedestal-table","quilting-frame","brass-washstand"},
    seating={"armchair-green","rocking-chair","round-stool","patchwork-train-bench","patchwork-footstool","train-car-writing-chair"},
    heat={"floor-lamp","potbelly-stove","copper-plant-stand"},
    sleep={"single-bed","blue-sofa","wooden-cradle","bedroll"},
    containers={"travel-chest","supply-crate","storage-bench"},
}

-- Room slots are points on the visible floor, arranged as two loose furniture
-- bays with a clear path through the middle. The doorway moves with the
-- generated interior variant, so shift the bays away from that entry side.
-- Coordinates use the game's 960x720 space (the interior art is drawn within
-- x=105..855, y=205..650).
local roomSlots = {
    [1]={{300,435},{360,550},{700,440},{700,565},{435,420}},
    [2]={{300,445},{360,565},{650,490},{715,585},{425,420}},
    [3]={{290,480},{365,575},{720,460},{720,570},{610,415}},
    [4]={{360,440},{410,570},{720,455},{715,565},{610,415}},
    [5]={{350,430},{390,565},{720,440},{715,565},{615,415}},
}

-- Each entry selects a furnishing category, a room slot, and its relative
-- scale. Slot numbers keep the composition's functional mix while allowing
-- each doorway-facing floor plan to get its own placement.
Compositions.templates = {
    {{"storage",1,1.25},{"heat",2,1.2},{"seating",3,1.2},{"containers",4,1.3},{"work",5,1.25}},
    {{"sleep",1,1.2},{"work",2,1.2},{"storage",3,1.2},{"seating",4,1.25},{"containers",5,1.25}},
    {{"containers",1,1.25},{"seating",2,1.2},{"heat",3,1.2},{"sleep",4,1.3},{"storage",5,1.25}},
    {{"work",1,1.2},{"storage",2,1.2},{"seating",3,1.2},{"containers",4,1.3},{"heat",5,1.2}},
    {{"storage",1,1.2},{"sleep",2,1.25},{"containers",3,1.2},{"seating",4,1.3},{"work",5,1.25}},
    {{"heat",1,1.2},{"seating",2,1.2},{"storage",3,1.2},{"sleep",4,1.3},{"containers",5,1.25}},
    {{"work",1,1.2},{"containers",2,1.25},{"sleep",3,1.2},{"storage",4,1.25},{"seating",5,1.25}},
    {{"seating",1,1.2},{"heat",2,1.2},{"work",3,1.2},{"storage",4,1.25},{"containers",5,1.25}},
    {{"sleep",1,1.25},{"storage",2,1.2},{"seating",3,1.2},{"work",4,1.25},{"heat",5,1.2}},
    {{"containers",1,1.2},{"work",2,1.2},{"heat",3,1.2},{"seating",4,1.25},{"sleep",5,1.25}},
}

local function available(name)
    return love.filesystem.getInfo("assets/sprites/furniture/"..name..".png") ~= nil
end

function Compositions.pick(group)
    local candidates={}
    for _,name in ipairs(Compositions.groups[group] or {}) do if available(name) then candidates[#candidates+1]=name end end
    return #candidates>0 and candidates[love.math.random(#candidates)] or nil
end

function Compositions.build(index)
    index=math.max(1,math.floor(index or 1))
    local template=Compositions.templates[(index-1)%#Compositions.templates+1]
    -- Indices 1-5 are the original interiors. Generated homes use five-image
    -- groups beginning at index 6, with matching numbered doorway variants.
    local variant=index<=5 and index or ((index-6)%5+1)
    local slots=roomSlots[variant] or roomSlots[1]
    local result={}
    for _,entry in ipairs(template) do
        local name=Compositions.pick(entry[1])
        local point=slots[entry[2]]
        if name and point then
            result[#result+1]={name=name,x=point[1],y=point[2],scale=entry[3],rotation=0,layer=math.floor(point[2]/10)}
        end
    end
    return result
end

return Compositions
