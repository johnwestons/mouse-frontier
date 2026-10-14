-- Independent references keep guest treatment art alive across the ordinary
-- world's lazy image eviction. Every path is existing authored art.
local Art={}
function Art.new(npc,item)
    local assets={bandageStrips={},owned={}}
    local function load(path)
        if not love.filesystem.getInfo(path) then return nil end
        local image=love.graphics.newImage(path); assets.owned[#assets.owned+1]=image; return image
    end
    for name,file in pairs({wound='small-cut.png',disinfectant='disinfectant-bottle.png',rag='clean-rag.png',
        swab='ointment-swab.png',gauze='gauze-pad.png',bandage='bandage-roll.png'}) do
        assets[name]=load('assets/sprites/props/first-aid/'..file)
    end
    for i,file in ipairs({'bandage-strip.png','bandage-strip-2.png','bandage-strip-3.png'}) do
        assets.bandageStrips[i]=load('assets/sprites/props/first-aid/'..file)
    end
    if type(npc)=='string' and npc:match('^[%w_%-]+%.png$') then assets.npc=load('assets/sprites/NPCS/'..npc) end
    if type(item)=='string' and item:match('^[%w_%-]+$') then assets.medical=load('assets/sprites/items/'..item..'.png') end
    return assets
end
function Art.release(assets)
    for _,image in ipairs(assets and assets.owned or {}) do image:release() end
end
return Art
