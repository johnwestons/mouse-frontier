local Viewport = {}

function Viewport.transform(baseWidth, baseHeight)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local scale = math.min(windowWidth / baseWidth, windowHeight / baseHeight)
    return math.floor((windowWidth-baseWidth*scale)/2), math.floor((windowHeight-baseHeight*scale)/2), scale, scale
end

function Viewport.toGame(x, y, baseWidth, baseHeight)
    local offsetX, offsetY, scaleX, scaleY = Viewport.transform(baseWidth, baseHeight)
    return (x-offsetX)/scaleX, (y-offsetY)/scaleY
end

return Viewport
