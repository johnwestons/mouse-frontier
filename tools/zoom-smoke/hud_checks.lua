-- Require actual fixed HUD coverage before comparing zoomed render records.
local Checks = {}
local patterns = {
    "^STOP ", "^HEALTH", "^LEVEL ", "^LV ", "^GOODWILL ", "^TRAIN ", "^CARS ", "^AMMUNITION$",
    "^TIME  ", "^AMMO  ", "^TACTICAL ENCOUNTER", "^OBJECTIVE", "^JOURNEY MENU$",
    "^PAUSE", "^JOYSTICK  MOVE", "^HOLD  ", "^HOSTILES  ", "^MORALE  ", "^POSITION  ",
    "^MAG  ", "^ROUNDS  ", "^FIRE MODE  ", "^PHASE ",
}
Checks.required = {
    train = {"^STOP ", "^HEALTH", "^LEVEL ", "^GOODWILL ", "^AMMUNITION$"},
    stop = {"^STOP ", "^HEALTH", "^LV ", "^GOODWILL ", "^TRAIN ", "^CARS "},
    house = {"^STOP ", "^HEALTH", "^LV ", "^GOODWILL ", "^TRAIN ", "^CARS "},
    battle = {"^TACTICAL ENCOUNTER", "^OBJECTIVE"},
    range = {"^TIME  ", "^AMMO  "},
    interior = {"^PAUSE", "^JOYSTICK  MOVE"},
    shootout = {"^HOLD  ", "^HOSTILES  ", "^MORALE  ", "^HEALTH", "^POSITION  ", "^MAG  ", "^ROUNDS  ", "^FIRE MODE  "},
}

function Checks.captures(value)
    if type(value) ~= "string" then return false end
    for _,pattern in ipairs(patterns) do if value:match(pattern) then return true end end
    return false
end

function Checks.compare(scene, before, after, expect)
    local required = assert(Checks.required[scene], "unknown zoom smoke scene: " .. tostring(scene))
    for _,pattern in ipairs(required) do
        local found = false
        for label in pairs(before) do if label:match(pattern) then found = true; break end end
        expect(found, scene .. " did not draw required HUD label " .. pattern .. " at zoom 1")
    end
    local count = 0
    for label, transform in pairs(before) do
        expect(after[label] ~= nil, scene .. " lost HUD label at zoom 2: " .. label)
        for index = 1, 4 do
            local first, second = transform[index], after[label][index]
            expect(type(first) == "number" and type(second) == "number" and math.abs(first - second) < .001,
                scene .. " changed HUD position/scale at zoom 2: " .. label .. " component " .. index)
        end
        count = count + 1
    end
    for label in pairs(after) do
        expect(before[label] ~= nil, scene .. " added unexpected HUD label at zoom 2: " .. label)
    end
    expect(count > 0, scene .. " compared no HUD labels")
    return count
end

return Checks
