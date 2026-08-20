local InteriorDoors = {}

-- Interior artwork is drawn into this fixed game-space rectangle in main.lua.
local DRAW_X, DRAW_Y, DRAW_W, DRAW_H = 105, 205, 750, 445

-- Normalized doorway thresholds. These are deliberately kept outside the
-- save data so correcting an art anchor fixes every save immediately.
local anchors = {
    ["frontier-cabin.png"]={.055,.49},
    ["railway-cottage.png"]={.055,.49},
    ["desert-adobe.png"]={.055,.49},
    ["forest-homestead.png"]={.105,.48},
    ["station-house.png"]={.055,.49},

    -- Stop 1 interiors were individually inspected against their artwork.
    ["stop01-interior-01.png"]={.455,.285},
    ["stop01-interior-02.png"]={.885,.475},
    ["stop01-interior-03.png"]={.405,.335},
    ["stop01-interior-04.png"]={.135,.735},
    ["stop01-interior-05.png"]={.135,.605},
}

-- Generated additions remain usable before a hand-authored override is added.
-- Their numbered layouts tend to preserve these broad doorway regions.
local generatedFallback = {
    [1]={.12,.68}, [2]={.88,.48}, [3]={.38,.34},
    [4]={.13,.72}, [5]={.14,.60},
}

local function filenameFor(index,files)
    return files and files[index] or nil
end

function InteriorDoors.point(index,files)
    local filename=filenameFor(index,files)
    local anchor=filename and anchors[filename]
    if not anchor and filename then
        local variant=tonumber(filename:match("interior%-(%d%d)%.png$"))
        anchor=generatedFallback[variant]
    end
    anchor=anchor or {.08,.55}
    return DRAW_X+anchor[1]*DRAW_W,DRAW_Y+anchor[2]*DRAW_H
end

function InteriorDoors.near(x,y,index,files,radius)
    local doorX,doorY=InteriorDoors.point(index,files)
    local dx,dy=x-doorX,y-doorY
    return dx*dx+dy*dy<=(radius or 58)^2
end

function InteriorDoors.spawnPoint(index,files)
    local x,y=InteriorDoors.point(index,files)
    -- Step a little toward the room center so the character starts indoors,
    -- while remaining close enough for the exit prompt to stay visible.
    return x+(480-x)*.07,y+(440-y)*.07
end

return InteriorDoors
