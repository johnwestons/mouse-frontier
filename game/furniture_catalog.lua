local Furniture = {}

-- Train furnishings are purchased as inventory items. Keep this roster
-- independent of the filesystem so authority, saves and headless tools agree.
Furniture.names = {
    "armchair-green", "barrel-cabinet", "blue-sofa", "blue-steamer-trunk",
    "bookcase", "brass-washstand", "ceramic-table-lamp", "copper-plant-stand",
    "floor-lamp", "framed-family-portrait", "gun-rack-dark-walnut",
    "gun-rack-deer-plaque", "gun-rack-reclaimed-pale", "medicine-cabinet",
    "pantry-cupboard", "patchwork-footstool", "patchwork-train-bench",
    "potbelly-stove", "quilting-frame", "railway-folding-screen", "rocking-chair",
    "rolltop-writing-desk", "round-pedestal-table", "round-stool", "side-table",
    "single-bed", "standing-dressing-mirror", "storage-bench", "supply-crate",
    "train-car-writing-chair", "train-locker", "travel-chest",
    "wall-mounted-coat-hooks", "wooden-coat-rack", "wooden-cradle",
    "wooden-wall-clock", "woven-frontier-rug",
}

Furniture.items = {}
for _,name in ipairs(Furniture.names) do Furniture.items[name]=true end

-- Small decorations stay affordable; seats, storage and large furnishings
-- cost more than ordinary supplies while remaining below late-route weapons.
Furniture.prices = {
    ["armchair-green"]=12, ["barrel-cabinet"]=16, ["blue-sofa"]=24, ["blue-steamer-trunk"]=18,
    ["bookcase"]=14, ["brass-washstand"]=12, ["ceramic-table-lamp"]=6, ["copper-plant-stand"]=8,
    ["floor-lamp"]=9, ["framed-family-portrait"]=6, ["gun-rack-dark-walnut"]=16,
    ["gun-rack-deer-plaque"]=18, ["gun-rack-reclaimed-pale"]=14, ["medicine-cabinet"]=18,
    ["pantry-cupboard"]=18, ["patchwork-footstool"]=6, ["patchwork-train-bench"]=14,
    ["potbelly-stove"]=20, ["quilting-frame"]=14, ["railway-folding-screen"]=12, ["rocking-chair"]=12,
    ["rolltop-writing-desk"]=22, ["round-pedestal-table"]=14, ["round-stool"]=6, ["side-table"]=8,
    ["single-bed"]=22, ["standing-dressing-mirror"]=12, ["storage-bench"]=16, ["supply-crate"]=12,
    ["train-car-writing-chair"]=10, ["train-locker"]=20, ["travel-chest"]=16,
    ["wall-mounted-coat-hooks"]=5, ["wooden-coat-rack"]=8, ["wooden-cradle"]=16,
    ["wooden-wall-clock"]=8, ["woven-frontier-rug"]=10,
}

function Furniture.isFurniture(name)
    return Furniture.items[name]==true
end

return Furniture
