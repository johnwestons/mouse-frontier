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

Compositions.templates = {
    {{"storage",300,350,1.25},{"heat",470,350,1.2},{"seating",735,365,1.2},{"containers",330,535,1.3},{"work",700,530,1.25}},
    {{"sleep",285,360,1.2},{"work",500,350,1.2},{"storage",735,370,1.2},{"seating",355,530,1.25},{"containers",680,525,1.25}},
    {{"containers",300,355,1.25},{"seating",485,365,1.2},{"heat",720,355,1.2},{"sleep",325,525,1.3},{"storage",705,525,1.25}},
    {{"work",290,360,1.2},{"storage",470,350,1.2},{"seating",730,365,1.2},{"containers",350,525,1.3},{"heat",685,530,1.2}},
    {{"storage",300,355,1.2},{"sleep",490,350,1.25},{"containers",725,360,1.2},{"seating",335,530,1.3},{"work",700,525,1.2}},
    {{"heat",300,355,1.2},{"seating",430,365,1.2},{"storage",735,350,1.2},{"sleep",330,525,1.3},{"containers",690,525,1.25}},
    {{"work",300,355,1.2},{"containers",470,355,1.25},{"sleep",735,360,1.2},{"storage",335,530,1.25},{"seating",690,525,1.25}},
    {{"seating",290,360,1.2},{"heat",465,350,1.2},{"work",730,365,1.2},{"storage",350,530,1.25},{"containers",680,525,1.25}},
    {{"sleep",300,355,1.25},{"storage",485,355,1.2},{"seating",720,360,1.2},{"work",330,530,1.25},{"heat",700,525,1.2}},
    {{"containers",300,355,1.2},{"work",470,355,1.2},{"heat",735,365,1.2},{"seating",340,530,1.25},{"sleep",690,525,1.25}},
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
    local template=Compositions.templates[((index or 1)-1)%#Compositions.templates+1]; local result={}
    for layer,entry in ipairs(template) do
        local name=Compositions.pick(entry[1])
        if name then result[#result+1]={name=name,x=entry[2],y=entry[3],scale=entry[4],rotation=0,layer=layer} end
    end
    return result
end

return Compositions
