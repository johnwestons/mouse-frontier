local Util = {}

function Util.pointIn(x,y,rectangle)
    return rectangle and x>=rectangle.x and x<=rectangle.x+rectangle.w and y>=rectangle.y and y<=rectangle.y+rectangle.h
end

function Util.titleFromFile(name)
    name=(name or ""):gsub("%.png$",""):gsub("%-"," ")
    return (name:gsub("(%a)([%w']*)",function(first,rest) return first:upper()..rest end))
end

function Util.sceneKey(scene,location)
    if scene=="train" then return "train" end
    return scene..":"..tostring(location or 1)
end

function Util.clampHouseFloor(x,y)
    -- Interior walk restrictions are intentionally disabled for now.  The
    -- room art varies by house and the hand-drawn masks need to be authored
    -- per interior; keep movement inside the visible 960x720 scene instead.
    return math.max(12,math.min(948,x)),math.max(12,math.min(708,y))
end

return Util
