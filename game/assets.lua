local Catalog = require("game.catalog")
local CharacterAnimation = require("game.character_animation")
local EventUI = require("game.event_ui")
local Roster = require("game.roster")
local Wildlife = require("game.wildlife") -- retained only for dynamic chickens

local Assets = {}
local missingRequired
local lazyPaths=setmetatable({},{__mode="k"})

local function loadImage(path)
    local ok, image = pcall(love.graphics.newImage, path)
    return ok and image or nil
end

local function prepareLazyImages(destination)
    local paths={}; lazyPaths[destination]=paths
    setmetatable(destination,{__index=function(self,key)
        local path=paths[key]
        if not path then return nil end
        local image=loadImage(path)
        if image then rawset(self,key,image) end
        return image
    end})
end

local function registerLazyImage(destination,key,path)
    local paths=lazyPaths[destination]
    if paths then paths[key]=path else destination[key]=loadImage(path) end
end

local function releaseLazyImages(destination,keep)
    if not lazyPaths[destination] then return end
    for key,image in pairs(destination) do
        if not (keep and keep[key]) then
            if image and image.release then pcall(image.release,image) end
            rawset(destination,key,nil)
        end
    end
end

local function requireImage(path)
    local image = loadImage(path)
    if not image and missingRequired then missingRequired[#missingRequired + 1] = path end
    return image
end

local function loadFolderImages(path, destination, predicate)
    if not love.filesystem.getInfo(path) then return end
    for _, file in ipairs(love.filesystem.getDirectoryItems(path)) do
        if file:match("%.png$") and (not predicate or predicate(file)) then
            destination[file:gsub("%.png$", "")] = loadImage(path .. "/" .. file)
        end
    end
end

local function registerItemAtlas(ui, path, names, columns, rows)
    local image = loadImage(path)
    if not image then return end
    local imageWidth, imageHeight = image:getDimensions()
    local cellWidth, cellHeight = imageWidth / columns, imageHeight / rows
    for index, name in ipairs(names) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        ui.atlasItems[name] = {
            image = image,
            quad = love.graphics.newQuad(column * cellWidth, row * cellHeight, cellWidth, cellHeight, imageWidth, imageHeight),
            w = cellWidth,
            h = cellHeight,
        }
    end
end

local function loadBattleAtlas(file, label)
    local image = loadImage("assets/sprites/battle-maps/" .. file)
    if not image then return nil end
    local imageWidth, imageHeight = image:getDimensions()
    local cellWidth, cellHeight = imageWidth / 3, imageHeight / 2
    local atlas = {name = label, image = image, quads = {}, cw = cellWidth, ch = cellHeight}
    for index = 1, 6 do
        local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
        atlas.quads[index] = love.graphics.newQuad(column * cellWidth, row * cellHeight, cellWidth, cellHeight, imageWidth, imageHeight)
    end
    return atlas
end

local function loadMenuFrames(ui)
    ui.menuFrames = {}
    for index, file in ipairs({"train-dialog-frame-v1.png", "train-panel-frame-v1.png", "train-tooltip-frame-v1.png", "train-button-frame-v1.png"}) do
        local image = loadImage("assets/sprites/ui/" .. file)
        if image then
            local frame = {image = image, w = image:getWidth(), h = image:getHeight(), quads = {}}
            local sliceX, sliceY = math.floor(frame.w * .22), math.floor(frame.h * .28)
            local xs, ys = {0, sliceX, frame.w - sliceX, frame.w}, {0, sliceY, frame.h - sliceY, frame.h}
            for row = 1, 3 do
                frame.quads[row] = {}
                for column = 1, 3 do
                    frame.quads[row][column] = love.graphics.newQuad(xs[column], ys[row], xs[column + 1] - xs[column], ys[row + 1] - ys[row], frame.w, frame.h)
                end
            end
            ui.menuFrames[index] = frame
        end
    end
end

local function loadShader()
    return love.graphics.newShader([[
        extern number hueShift;
        extern number saturation;

        vec3 rgbToHsv(vec3 c) {
            vec4 K = vec4(0.0, -0.3333333, 0.6666667, -1.0);
            vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
            vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
            float d = q.x - min(q.w, q.y);
            float e = 0.0000001;
            return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
        }

        vec3 hsvToRgb(vec3 c) {
            vec3 p = abs(fract(c.xxx + vec3(0.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
            return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
        }

        vec4 effect(vec4 color, Image texture, vec2 textureCoordinates, vec2 screenCoordinates) {
            vec4 pixel = Texel(texture, textureCoordinates) * color;
            if (pixel.a > 0.0) {
                vec3 hsv = rgbToHsv(pixel.rgb);
                hsv.x = fract(hsv.x + hueShift);
                hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
                pixel.rgb = hsvToRgb(hsv);
            }
            return pixel;
        }
    ]])
end

function Assets.load(targets)
    missingRequired = {}
    local ui, scenery = targets.ui, targets.scenery
    local characters, characterImages = targets.characters, targets.characterImages
    local npcImages, mobImages, mobFiles = targets.npcImages, targets.mobImages, targets.mobFiles
    local characterWalkImages, npcWalkImages = targets.characterWalkImages, targets.npcWalkImages
    local characterActionImages = targets.characterActionImages
    local mobAttackImages, mobIdleImages, mobHitImages = targets.mobAttackImages, targets.mobIdleImages, targets.mobHitImages
    local mobDeathImages, mobWalkImages, mobRangedImages = targets.mobDeathImages, targets.mobWalkImages, targets.mobRangedImages

    for _,images in ipairs({characterWalkImages,npcWalkImages,characterActionImages,mobAttackImages,mobIdleImages,mobHitImages,mobDeathImages,mobWalkImages,mobRangedImages}) do
        prepareLazyImages(images)
    end

    ui.radioFace = loadImage("assets/sprites/ui/radio/radio-gui.png")
    ui.radioButtonsImage = loadImage("assets/sprites/ui/radio/radio-buttons.png")
    if ui.radioButtonsImage then
        local imageWidth, imageHeight = ui.radioButtonsImage:getDimensions()
        ui.radioButtonQuads = {}
        for index = 1, 3 do
            ui.radioButtonQuads[index] = love.graphics.newQuad((index - 1) * imageWidth / 3, 0, imageWidth / 3, imageHeight, imageWidth, imageHeight)
        end
    end
    ui.objectTintShader = loadShader()

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/MainCharacters")) do
        if Roster.isPlayable(file) then
            characters[#characters + 1] = file
            characterImages[file] = requireImage("assets/sprites/MainCharacters/" .. file)
        end
    end
    table.sort(characters)

    local backgroundFiles = love.filesystem.getDirectoryItems("assets/backgrounds")
    for index = 1, 12 do
        local prefix = "^stop%-" .. string.format("%02d", index)
        for _, file in ipairs(backgroundFiles) do
            if file:match(prefix) then targets.backgroundImages[index] = loadImage("assets/backgrounds/" .. file) end
        end
    end

    scenery.fire = loadImage("assets/sprites/characters/fire-spirit.png")
    scenery.fireFrames = {scenery.fire, loadImage("assets/sprites/characters/animations/fire-spirit-idle-2.png"), scenery.fire, loadImage("assets/sprites/characters/animations/fire-spirit-idle-3.png")}
    scenery.boiler = loadImage("assets/sprites/train-decorations/boiler-firebox.png")
    scenery.curtain = loadImage("assets/sprites/train-decorations/train-window-curtain.png") or loadImage("assets/sprites/train-decorations/porthole-curtain.png")
    scenery.smokeLarge1 = loadImage("assets/sprites/train-decorations/locomotive-smoke-large-1.png")
    scenery.smokeLarge2 = loadImage("assets/sprites/train-decorations/locomotive-smoke-large-2.png")
    scenery.smokeSmall = loadImage("assets/sprites/train-decorations/locomotive-smoke-small.png")

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/MainCharacters/animations")) do
        if file:match("%-walk%.png$") and not file:match("%-left%.png$") and not file:match("%-right%.png$") then
            registerLazyImage(characterWalkImages,file:gsub("%-walk%.png$", ".png"),"assets/sprites/MainCharacters/animations/" .. file)
        elseif file:match("%-action%.png$") then
            registerLazyImage(characterActionImages,file:gsub("%-action%.png$", ".png"),"assets/sprites/MainCharacters/animations/" .. file)
        end
    end

    scenery.homeTexture = loadImage("assets/textures/home-interior-floor.png")
    -- Interior images are intentionally not created here.  The filename list is
    -- cheap startup metadata; AssetStreamer keeps only the active home on the GPU.
    scenery.interiors = nil
    scenery.interiorFiles = {}
    for _, file in ipairs({"frontier-cabin.png", "railway-cottage.png", "desert-adobe.png", "forest-homestead.png", "station-house.png"}) do
        scenery.interiorFiles[#scenery.interiorFiles + 1] = file
    end
    -- Generated stop-specific interiors: five distinct homes for each of the
    -- first five stops.  They are loaded as standalone scenes, never as a sheet.
    local generatedInteriorFiles={}
    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/interiors")) do
        if file:match("^stop%d%d%-interior%-%d%d%.png$") then
            generatedInteriorFiles[#generatedInteriorFiles+1]=file
        end
    end
    table.sort(generatedInteriorFiles)
    for _, file in ipairs(generatedInteriorFiles) do
        scenery.interiorFiles[#scenery.interiorFiles + 1] = file
    end
    scenery.trainTexture = loadImage("assets/textures/train-interior-panels.png")

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/NPCS")) do
        if Roster.isNpcCandidate(file) then npcImages[file] = requireImage("assets/sprites/NPCS/" .. file) end
    end
    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/NPCS/animations")) do
        if file:match("%-walk%.png$") then
            local base = file:gsub("%-walk%.png$", ".png")
            local path="assets/sprites/NPCS/animations/" .. file
            registerLazyImage(npcWalkImages,base,path)
            registerLazyImage(characterWalkImages,base,path)
        end
    end

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/Mobs")) do
        if file:match("%.png$") then
            mobFiles[#mobFiles + 1] = file
            mobImages[file] = requireImage("assets/sprites/Mobs/" .. file)
        end
    end
    if love.filesystem.getInfo("assets/sprites/Mobs/animations") then
        for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/Mobs/animations")) do
            local path = "assets/sprites/Mobs/animations/" .. file
            if file:match("%-attack%.png$") then registerLazyImage(mobAttackImages,file:gsub("%-attack%.png$", ".png"),path)
            elseif file:match("%-idle%-2%.png$") then registerLazyImage(mobIdleImages,file:gsub("%-idle%-2%.png$", ".png"),path)
            elseif file:match("%-hit%.png$") then registerLazyImage(mobHitImages,file:gsub("%-hit%.png$", ".png"),path)
            elseif file:match("%-death%.png$") then registerLazyImage(mobDeathImages,file:gsub("%-death%.png$", ".png"),path)
            elseif file:match("%-walk%.png$") then registerLazyImage(mobWalkImages,file:gsub("%-walk%.png$", ".png"),path)
            elseif file:match("%-ranged%.png$") then registerLazyImage(mobRangedImages,file:gsub("%-ranged%.png$", ".png"),path) end
        end
    end
    if love.filesystem.getInfo("assets/sprites/NPCS/families") then
        loadFolderImages("assets/sprites/NPCS/families", targets.familyImages)
    end
    table.sort(mobFiles)

    ui.propImages = {}
    for _, path in ipairs({"assets/sprites/props", "assets/sprites/items", "assets/sprites/furniture", "assets/sprites/weapons", "assets/sprites/train-decorations", "assets/sprites/ammo"}) do
        loadFolderImages(path, ui.propImages)
    end
    targets.itemIdleImages["flower-pot"] = {ui.propImages["flower-pot"], loadImage("assets/sprites/items/animations/flower-pot-idle-2.png"), loadImage("assets/sprites/items/animations/flower-pot-idle-3.png")}

    ui.atlasItems = {}
    registerItemAtlas(ui, "assets/sprites/atlases/food-water-v1.png", {"trail-beans-can", "dried-berry-pouch", "cornbread-square", "mushroom-stew", "jerky-bundle", "preserved-peaches", "metal-water-flask", "blue-water-bottle", "rainwater-jar", "patched-canteen", "boxed-fruit-drink", "ceramic-water-crock"}, 4, 3)
    registerItemAtlas(ui, "assets/sprites/atlases/firearms-v1.png", {"compact-scrap-pistol", "long-barrel-22-pistol", "heavy-frontier-pistol", "machine-pistol", "weathered-lever-rifle", "improvised-service-rifle", "compact-carbine", "rugged-submachine-gun"}, 4, 2)
    registerItemAtlas(ui, "assets/sprites/gear/backpack-upgrades-v1.png", {"patched-canvas-pack", "bedroll-hiking-pack", "frontier-leather-pack", "scavenger-frame-pack"}, 2, 2)
    loadMenuFrames(ui)

    scenery.trainFrames, scenery.worldTrainFrames = {}, {}
    for index = 1, 3 do
        local image = loadImage("assets/sprites/train/animations/locomotive-red-run-" .. index .. ".png")
        scenery.trainFrames[index], scenery.worldTrainFrames[index] = image, image
    end
    scenery.redTrain = loadImage("assets/sprites/train/locomotive-red.png")
    scenery.worldTrain = scenery.redTrain
    scenery.trainCarImages = {}
    for _, entry in ipairs(Catalog.trainCarCatalog) do
        scenery.trainCarImages[entry.id] = loadImage("assets/sprites/train/cars/" .. entry.id .. ".png")
    end
    scenery.trainCarImages["living-car"] = loadImage("assets/sprites/train/cars/living-car.png")
    scenery.track = loadImage("assets/sprites/tracks/railway-track-v1.png")

    local projectileImage = loadImage("assets/sprites/projectiles/projectiles-packed-v1.png")
    if projectileImage then
        local imageWidth, imageHeight = projectileImage:getDimensions()
        local cellWidth = imageWidth / 5
        scenery.projectiles = {image = projectileImage, w = cellWidth, h = imageHeight, quads = {}}
        for index = 1, 5 do scenery.projectiles.quads[index] = love.graphics.newQuad((index - 1) * cellWidth, 0, cellWidth, imageHeight, imageWidth, imageHeight) end
    end

    local groundImage = loadImage("assets/sprites/ground/stop-ground-textures-v1.png")
    if groundImage then
        local imageWidth, imageHeight = groundImage:getDimensions()
        scenery.stopGround = {image = groundImage, w = imageWidth / 2, h = imageHeight / 2, quads = {}}
        for index = 1, 4 do
            local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
            scenery.stopGround.quads[index] = love.graphics.newQuad(column * imageWidth / 2, row * imageHeight / 2, imageWidth / 2, imageHeight / 2, imageWidth, imageHeight)
        end
    end

    scenery.battleAtlases, scenery.battleVariations = {}, {}
    for _, entry in ipairs({{"WASTELAND", "wasteland-tiles-v2.png", "wasteland-tiles-v3.png"}, {"FOREST", "forest-tiles-v1.png", "forest-tiles-v2.png"}, {"TOWN RUINS", "town-ruins-tiles-v1.png", "town-ruins-tiles-v2.png"}, {"MOUNTAINS", "mountain-tiles-v1.png", "mountain-tiles-v2.png"}}) do
        scenery.battleAtlases[#scenery.battleAtlases + 1] = loadBattleAtlas(entry[2], entry[1])
        scenery.battleVariations[#scenery.battleVariations + 1] = loadBattleAtlas(entry[3], entry[1])
    end

    -- Settlement sprites now provide the complete stop surface and buildings.
    -- Keep only chicken assets from the wildlife module for future dynamic spawns.
    scenery.stopWildlife, scenery.stopWildlifeFeeding = {}, {}
    loadFolderImages("assets/sprites/stop-wildlife", scenery.stopWildlife, function(file) return not file:find("atlas") end)
    Wildlife.load(scenery.stopWildlife, loadImage)
    scenery.eventArt = EventUI.load(loadImage)
    if love.filesystem.getInfo("assets/sprites/stop-wildlife/animations") then
        for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/stop-wildlife/animations")) do
            local name = file:match("^(.-)%-feed%.png$")
            if name then scenery.stopWildlifeFeeding[name] = loadImage("assets/sprites/stop-wildlife/animations/" .. file) end
        end
    end

    if #missingRequired > 0 then
        error("Required image assets failed to load:\n" .. table.concat(missingRequired, "\n"))
    end
    missingRequired = nil
    return CharacterAnimation.load("assets/sprites/character-animations", loadImage)
end

function Assets.retainAnimationImages(tables,keep)
    for _,images in ipairs(tables or {}) do releaseLazyImages(images,keep) end
end

return Assets
