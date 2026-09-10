local Config = {
    identity = "mouse-frontier",
    title = "Mouse Frontier",
    baseWidth = 960,
    baseHeight = 720,
    minimumWidth = 720,
    minimumHeight = 540,
    holdPickupSeconds = 0.85,
    -- The landscape is lowered to the rail-side ground line marked in the
    -- presentation reference. A small overscan protects the fullscreen edge.
    landscape = {verticalOffset = 90, seamOverlap = 2, trackSpeed = 1.08},
    -- Keep the locomotive/car union centered on the 960-wide authored stage.
    -- The locomotive has its own additional left offset in game/train.lua.
    trainCar = {x = 429, y = 280, w = 620, h = 363, gap = 0, wall = 16},
    colors = {
        ink = {0.10, 0.065, 0.04},
        wall = {0.31, 0.20, 0.12},
        trim = {0.16, 0.09, 0.05},
        floorA = {0.46, 0.30, 0.16},
        floorB = {0.35, 0.21, 0.11},
        brass = {0.86, 0.58, 0.18},
        cream = {0.96, 0.88, 0.68},
        panel = {0.12, 0.09, 0.07, 0.94},
        green = {0.32, 0.70, 0.38},
        blue = {0.25, 0.56, 0.78},
        red = {0.78, 0.30, 0.24},
    },
}

return Config
