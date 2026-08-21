local Clouds = {}

local placements = {
    {phase = 0.00, yTrain = 82,  scale = 0.34, speed = 10, image = 1, index = 1},
    {phase = 0.12, yTrain = 150, scale = 0.24, speed = 7,  image = 5, index = 2},
    {phase = 0.24, yTrain = 70,  scale = 0.29, speed = 12, image = 2, index = 3},
    {phase = 0.36, yTrain = 128, scale = 0.21, speed = 6,  image = 6, index = 4},
    {phase = 0.49, yTrain = 94,  scale = 0.32, speed = 9,  image = 3, index = 5},
    {phase = 0.61, yTrain = 182, scale = 0.23, speed = 8,  image = 7, index = 6},
    {phase = 0.73, yTrain = 116, scale = 0.27, speed = 11, image = 4, index = 7},
    {phase = 0.85, yTrain = 62,  scale = 0.20, speed = 6,  image = 8, index = 8},
    {phase = 0.97, yTrain = 138, scale = 0.30, speed = 8,  image = 9, index = 9},
}

function Clouds.new(images)
    return {images = images or {}, time = 0}
end

function Clouds.update(layer, dt)
    if layer then layer.time = (layer.time + dt) % 100000 end
end

function Clouds.draw(layer, mode, width, height, sceneryOffset, stopNumber)
    if not layer or #layer.images == 0 then return end
    local span = width + 260
    for _, cloud in ipairs(placements) do
        local image = layer.images[cloud.image] or layer.images[1]
        if image then
            local iw, ih = image:getDimensions()
            -- Begin just beyond the right edge, drift westward, and wrap only
            -- after the entire cloud has cleared the left edge.
            local distance = (cloud.phase * span + layer.time * cloud.speed) % span
            local x = width + 130 - distance
            local stopY = 78 + ((cloud.index * 83 + (stopNumber or 1) * 47) % 340)
            local baseY = mode == "stop" and stopY or cloud.yTrain
            local y = mode == "train" and math.min(height * 0.32, baseY) or baseY
            y = y + math.sin(layer.time * 0.12 + cloud.phase * 8) * 2
            love.graphics.setColor(1, 1, 1, 0.80)
            love.graphics.draw(image, x, y, 0, cloud.scale, cloud.scale, iw / 2, ih / 2)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Clouds
